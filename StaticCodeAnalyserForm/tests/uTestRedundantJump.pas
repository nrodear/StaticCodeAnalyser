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
    [Test] procedure BreakBeforeEnd_Reported;
    [Test] procedure RedundantJump_KindAndSeverity;
    // --- Ist-Messung 2026-07-18 (SCA080 80% FP im Sample): End-Chain-Walk ---
    [Test] procedure NestedExitMoreCodeAfter_NoFinding;
    [Test] procedure QualifiedExitCall_NoFinding;
    [Test] procedure NestedExitAtRoutineTail_StillReported;   // TP-Gegenprobe
    [Test] procedure ExitThenInlineVar_NoFinding;             // inline-var = Code, kein Terminator
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

procedure TTestRedundantJump.BreakBeforeEnd_Reported;
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkRedundantJump) >= 1);
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

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantJump);

end.
