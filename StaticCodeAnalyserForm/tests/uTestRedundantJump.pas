unit uTestRedundantJump;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantJump = class
  public
    [Test] procedure ExitInMiddle_NoFinding;
    [Test] procedure ExitBeforeEnd_Reported;
    [Test] procedure ContinueBeforeEnd_Reported;
    [Test] procedure RedundantJump_KindAndSeverity;
    // --- Ist-Messung 2026-07-18 (SCA080 80% FP im Sample): End-Chain-Walk ---
    [Test] procedure NestedExitMoreCodeAfter_NoFinding;
    [Test] procedure QualifiedExitCall_NoFinding;
    [Test] procedure NestedExitAtRoutineTail_StillReported;   // TP-Gegenprobe
    [Test] procedure ExitThenInlineVar_NoFinding;             // inline-var = Code, kein Terminator
    // --- 30%-Audit 2026-07-31 (96% FP): Break gestrichen + Schleifen-Gate ---
    [Test] procedure BreakAtLoopTail_NoFinding;               // FP-Klasse 2
    [Test] procedure ExitInForSearchLoopAtTail_NoFinding;     // FP-Klasse 1
    [Test] procedure ExitInRepeatLoop_NoFinding;              // FP-Klasse 1 (repeat)
    [Test] procedure ExitInCaseArmInLoop_NoFinding;           // FP-Klasse 1 (case-Arm)
    [Test] procedure LoopBeforeExit_StillReported;            // TP-Gegenprobe (`;`-Regel)
    [Test] procedure ExitAfterStringWithLoopWords_StillReported; // TP-Gegenprobe (Blank-Fassung)
    [Test] procedure ExitInWithBlockAtTail_StillReported;     // TP-Gegenprobe (with ist keine Schleife)
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantJump.ExitInMiddle_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Failed then Exit;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump));
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitBeforeEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump));
  finally F.Free; end;
end;

procedure TTestRedundantJump.ContinueBeforeEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '    Continue;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRedundantJump) >= 1);
  finally F.Free; end;
end;

procedure TTestRedundantJump.BreakAtLoopTail_NoFinding;
// 30%-Audit 2026-07-31, FP-Klasse 2 (9/24 im Sample, 1375 Korpus-Funde):
// `Break` am Ende des Schleifenkoerpers ist - anders als `Continue` - KEIN
// No-Op. Es verhindert die naechsten Iterationen; bei `while True` erzeugt
// das Befolgen des Hints eine Endlosschleife. Vorher: gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  while True do'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '    Break;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Break am Koerperende beendet die Schleife - nicht redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.RedundantJump_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff; Exit; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantJump then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantJump, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantJump finding');
  finally F.Free; end;
end;

procedure TTestRedundantJump.NestedExitMoreCodeAfter_NoFinding;
// Ist-Messung 2026-07-18 (12/15-FP-Klasse): Exit in if-in-for-Suchschleife,
// 2 Ebenen tief -> 'Exit; end; end;' gefolgt von WEITEREM Prozedur-Code. Der
// alte Ein-Token-Look-Ahead sah nur das zweite 'end' und meldete "redundant",
// obwohl das Exit den Folgecode ueberspringt (essentiell). Der End-Chain-Walk
// laeuft die ganze Kette und sieht den 'if'-Terminator -> kein Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Find;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '  begin'#13#10 +
  '    if Match(i) then'#13#10 +
  '    begin'#13#10 +
  '      Idx := i;'#13#10 +
  '      Exit;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  '  if Idx < 0 then'#13#10 +
  '    MessageBeep(0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Exit in Suchschleife mit Folgecode ist NICHT redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.QualifiedExitCall_NoFinding;
// Ist-Messung 2026-07-18: 'ctx.Exit;' ist ein METHODENAUFRUF (CEF-V8-Context
// .Enter/.Exit-Paar), kein Exit-Statement. '.'-Praefix-Skip.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(ctx: TV8Context);'#13#10 +
  'begin'#13#10 +
  '  ctx.Enter;'#13#10 +
  '  DoStuff;'#13#10 +
  '  ctx.Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'qualifizierter .Exit-Methodenaufruf ist kein Jump-Statement');
  finally F.Free; end;
end;

procedure TTestRedundantJump.NestedExitAtRoutineTail_StillReported;
// TP-Gegenprobe zum Chain-Walk: 'Exit; end; end;' dessen Kette die ROUTINE
// schliesst (Terminator = 'procedure' der Folge-Routine) -> ohne Exit faellt
// die Kontrolle sowieso ans Routinen-Ende -> redundant, muss gemeldet bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'begin'#13#10 +
  '  DoOther;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump),
    'Exit dessen end-Kette die Routine schliesst bleibt redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitThenInlineVar_NoFinding;
// Compile-Review-Guard 2026-07-18: Delphi-12-inline-'var' ist AUSFUEHRBARER
// Code, keine Routinen-Grenze. 'Exit; end;' gefolgt von 'var h := ...' im
// selben Body -> das Exit ueberspringt den Folgecode -> NICHT redundant.
// (var/const/type sind bewusst NICHT im Terminator-Set des Chain-Walks.)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  if Precondition then'#13#10 +
  '  begin'#13#10 +
  '    Log(''start'');'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  '  var handler := TThing.Create;'#13#10 +
  '  handler.Run;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Exit vor inline-var-Folgecode ist nicht redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitInForSearchLoopAtTail_NoFinding;
// 30%-Audit 2026-07-31, FP-Klasse 1 (14/24 im Sample): Suchschleife, deren
// Treffer-Zweig mit `Exit` abbricht. Die end-Kette schliesst hier die
// ROUTINE (Terminator = 'procedure' der Folge-Routine), der Chain-Walk sagt
// also "redundant" - aber ohne das Exit liefe die Schleife weiter und
// Result wuerde von spaeteren Iterationen ueberschrieben. Vorher: gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'function Find: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := -1;'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '    if Match(i) then'#13#10 +
  '    begin'#13#10 +
  '      Result := i;'#13#10 +
  '      Exit;'#13#10 +
  '    end;'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'begin'#13#10 +
  '  DoOther;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Exit aus einer Suchschleife ist Frueh-Rueckkehr, nicht redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitInRepeatLoop_NoFinding;
// 30%-Audit 2026-07-31, FP-Klasse 1, repeat-Variante: die Kette endet auf
// `until` - fuer den Chain-Walk ein akzeptierter Terminator. Ohne das Exit
// laeuft die repeat-Schleife weiter. Vorher: gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  repeat'#13#10 +
  '    if Cond then'#13#10 +
  '    begin'#13#10 +
  '      DoStuff;'#13#10 +
  '      Exit;'#13#10 +
  '    end;'#13#10 +
  '  until Done;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Exit im repeat-Rumpf verhindert weitere Iterationen');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitInCaseArmInLoop_NoFinding;
// 30%-Audit 2026-07-31, FP-Klasse 1, case-Variante: der Rueckwaertsscan muss
// ueber den case-Arm und den case-Kopf hinweg bis zum for-Kopf laufen. Das
// `;` hinter dem vorigen Arm (`1: DoA;`) darf den Schleifenfund NICHT
// blockieren - beim Kreuzen des `case`-Openers wird das Flag zurueckgesetzt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '  begin'#13#10 +
  '    case Kind[i] of'#13#10 +
  '      1: DoA;'#13#10 +
  '      2: begin'#13#10 +
  '           DoB;'#13#10 +
  '           Exit;'#13#10 +
  '         end;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump),
    'Exit im case-Arm innerhalb einer Schleife ist nicht redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.LoopBeforeExit_StillReported;
// TP-Gegenprobe zum Schleifen-Gate (`;`-Regel). Die Schleife hat einen
// EINANWEISIGEN Rumpf und ist beim `Exit` bereits abgeschlossen - der Jump
// steht dahinter, nicht darin. Ein Gate ohne die `;`-Unterscheidung wuerde
// hier faelschlich unterdruecken (Korpus: 29 solche TPs, u.a.
// SynHighlighterJSON.pas:277). Muss gemeldet BLEIBEN.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  while Cond do Inc(Run);'#13#10 +
  '  Exit;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump),
    'Exit NACH einer abgeschlossenen Schleife bleibt redundant');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitAfterStringWithLoopWords_StillReported;
// TP-Gegenprobe zur Blank-Fassung: das String-Literal enthaelt die Woerter
// 'begin', 'do' und 'while'. Liefe der Rueckwaertsscan ueber die Fassung MIT
// Literalen, faende er dort einen Schleifenkopf und wuerde einen echten
// TP unterdruecken. Muss gemeldet BLEIBEN.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '  begin'#13#10 +
  '    Log(''while true do begin'');'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump),
    'Schleifenwoerter im String-Literal duerfen nicht als Schleife zaehlen');
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitInWithBlockAtTail_StillReported;
// TP-Gegenprobe: `with ... do begin` ist ein `do`-Block, aber KEINE
// Schleife - das Exit am Blockende bleibt redundant. Schuetzt davor, das
// Gate an `do` statt an for/while/repeat aufzuhaengen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with GetEngine do'#13#10 +
  '  begin'#13#10 +
  '    if Parse = 0 then'#13#10 +
  '      Exit;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump),
    'with-Block ist keine Schleife - Exit bleibt redundant');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantJump);

end.
