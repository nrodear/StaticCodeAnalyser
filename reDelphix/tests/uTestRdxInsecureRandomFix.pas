unit uTestRdxInsecureRandomFix;

// Editorhilfe SCA167 InsecureRandom (uRdxInsecureRandomFix): 'Randomize;'
// in den initialization-Abschnitt der Unit. Zwei Fixtures:
//   TTestRdxInsecureRandomFix          der Planer auf Text (Code-Sicht aus
//                                      einer TStringList), ohne Parser und
//                                      Detektor - FPC-tauglich;
//   TTestRdxInsecureRandomFixDetector  Rundlaeufe mit dem ECHTEN Detektor
//                                      (uInsecureRandom) ueber den Einstieg
//                                      der Tabelle (TRdxFixTable.FixFor,
//                                      Adapter PlanInsecureRandom) - nur
//                                      Delphi.
// Prueft: neuer Abschnitt vor 'end.' (auch hinter Deklarationen, auch
// gross geschrieben), vor einem finalization ohne initialization, erste
// Anweisung eines vorhandenen Abschnitts (neue Zeile mit der Stufe der
// Zeile danach, hinter einem Kommentar, inline), Meldung mit Qualifizierer,
// Anweisung ueber zwei Zeilen - und die Sperren: Zeile verschoben (String,
// Kommentar, fremdes Objekt), Randomize/RandSeed schon da, keine Unit,
// kein implementation, 'begin .. end.' (SCA088), Bedingungsblock, zwei
// Abschnitte, 'end.' nicht allein auf der Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxInsecureRandomFix = class
  public
    // ---- Umformung ----
    [Test] procedure Sca167_NewSection_BeforeEnd;
    [Test] procedure Sca167_NewSection_AfterDeclarations;
    [Test] procedure Sca167_NewSection_UpperCase;
    [Test] procedure Sca167_NewSection_BeforeFinalization;
    [Test] procedure Sca167_ExistingInit_NewLine;
    [Test] procedure Sca167_ExistingInit_AfterComment;
    [Test] procedure Sca167_ExistingInit_Inline;
    [Test] procedure Sca167_QualifiedAndTwoLines;
    [Test] procedure Sca167_CallOf;
    // ---- Gegenproben: keine Hilfe ----
    [Test] procedure Sca167_Moved_NoHelp;
    [Test] procedure Sca167_SeedPresent_NoHelp;
    [Test] procedure Sca167_NotUnit_NoHelp;
    [Test] procedure Sca167_Legacy_NoHelp;
    [Test] procedure Sca167_Conditional_NoHelp;
    [Test] procedure Sca167_LineForm_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxInsecureRandomFixDetector = class
  public
    [Test] procedure Sca167_Detector_RoundTrip;
    [Test] procedure Sca167_Detector_ExistingInit_RoundTrip;
    [Test] procedure Sca167_Detector_CatalogExample;
    [Test] procedure Sca167_Detector_RandSeed_NoHelp;
    [Test] procedure Sca167_Detector_Legacy_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uInsecureRandom,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxInsecureRandomFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

const
  // Kopf und eine Routine mit Random - die meisten Faelle haengen an.
  HEAD: array[0..2] of string = ('unit t;', 'interface', 'implementation');
  DICE: array[0..3] of string = ('function Dice: Integer;', 'begin',
    '  Result := Random(6) + 1;', 'end;');
  // Was die Hilfe vor 'end.' einfuegt.
  NEW_INIT: array[0..2] of string = ('initialization', '  Randomize;', '');

// ---- Helfer ----

// Die Meldung des Detektors fuer den Aufruf ACall (uInsecureRandom).
function MsgFor(const ACall: string): string;
begin
  Result := ACall + '(...) without prior Randomize - deterministic sequence '
    + '(Seed=0 until Randomize)';
end;

// HEAD, DICE und die Zeilen ATail.
function DiceUnit(const ATail: array of string): string;
begin
  Result := Join(HEAD) + #13#10 + Join(DICE) + #13#10 + Join(ATail);
end;

// Der Planer an Zeile ALine fuer den Aufruf ACall: der neue Text, bei einer
// Ablehnung '' und der Grund in AReason.
function FixAt(const ASource: string; ALine: Integer; const ACall: string;
  out AReason: string): string;
var
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
begin
  Result := '';
  Map := NewMap(ASource);
  try
    if TRdxInsecureRandomFix.AddRandomize(Map, ALine, MsgFor(ACall), Edit,
         AReason) then
      Result := Apply(ASource, Edit);
  finally
    Map.Free;
  end;
end;

// Dasselbe fuer 'Random' an der ersten Zeile mit 'Random('.
function Fix(const ASource: string; out AReason: string): string;
begin
  Result := FixAt(ASource, LineOf(ASource, 'Random('), 'Random', AReason);
end;

// Die Hilfe muss Text liefern und ohne Grund auskommen.
function Fixed(const ASource: string): string;
var
  Reason : string;
begin
  Result := Fix(ASource, Reason);
  Assert.AreEqual('', Reason);
end;

// Keine Hilfe, der Grund ist AReason.
procedure AssertRefused(const ASource, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, Reason));
  Assert.AreEqual(AReason, Reason);
end;

// ---- Umformung ----

procedure TTestRdxInsecureRandomFix.Sca167_NewSection_BeforeEnd;
begin
  // Ohne initialization: ein neuer Abschnitt vor 'end.', danach eine
  // Leerzeile.
  Assert.AreEqual(DiceUnit(['initialization', '  Randomize;', '', 'end.']),
    Fixed(DiceUnit(['end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_NewSection_AfterDeclarations;
begin
  // Die Unit endet mit Deklarationen statt einer Routine - das 'end.' ist
  // trotzdem der Schluss der Unit (kein begin davor).
  Assert.AreEqual(
    DiceUnit(['var', '  GSeed: Integer;', 'initialization', '  Randomize;',
      '', 'end.']),
    Fixed(DiceUnit(['var', '  GSeed: Integer;', 'end.'])));
  // Ein Kommentar hinter dem 'end.' stoert nicht.
  Assert.AreEqual(
    DiceUnit(['initialization', '  Randomize;', '', 'end. // t']),
    Fixed(DiceUnit(['end. // t'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_NewSection_UpperCase;
begin
  // Schreibweise wie das end ('END.' -> 'INITIALIZATION').
  Assert.AreEqual(DiceUnit(['INITIALIZATION', '  Randomize;', '', 'END.']),
    Fixed(DiceUnit(['END.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_NewSection_BeforeFinalization;
begin
  // FPC erlaubt finalization ohne initialization - der Abschnitt kommt
  // davor.
  Assert.AreEqual(
    DiceUnit(['initialization', '  Randomize;', '', 'finalization', '  Done;',
      'end.']),
    Fixed(DiceUnit(['finalization', '  Done;', 'end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_ExistingInit_NewLine;
begin
  // Erste Anweisung, die Stufe aus der Zeile danach.
  Assert.AreEqual(
    DiceUnit(['initialization', '  Randomize;', '  Foo;', 'end.']),
    Fixed(DiceUnit(['initialization', '  Foo;', 'end.'])));
  Assert.AreEqual(
    DiceUnit(['initialization', '    Randomize;', '    Foo;', 'end.']),
    Fixed(DiceUnit(['initialization', '    Foo;', 'end.'])));
  // Leerer Abschnitt vor finalization: zwei Leerzeichen.
  Assert.AreEqual(
    DiceUnit(['initialization', '  Randomize;', 'finalization', '  Done;',
      'end.']),
    Fixed(DiceUnit(['initialization', 'finalization', '  Done;', 'end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_ExistingInit_AfterComment;
begin
  // Ein Kommentar hinter initialization bleibt auf seiner Zeile.
  Assert.AreEqual(
    DiceUnit(['initialization // setup', '  Randomize;', '  Foo;', 'end.']),
    Fixed(DiceUnit(['initialization // setup', '  Foo;', 'end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_ExistingInit_Inline;
begin
  // Code auf derselben Zeile: Randomize direkt hinter initialization.
  Assert.AreEqual(
    DiceUnit(['initialization Randomize; Foo;', 'end.']),
    Fixed(DiceUnit(['initialization Foo;', 'end.'])));
  // Eine Direktive dahinter ebenso - Randomize steht vor ihr, unbedingt.
  Assert.AreEqual(
    DiceUnit(['initialization Randomize; {$IFDEF X}', '  Foo;', '{$ENDIF}',
      'end.']),
    Fixed(DiceUnit(['initialization {$IFDEF X}', '  Foo;', '{$ENDIF}',
      'end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_QualifiedAndTwoLines;
var
  S, Reason : string;
begin
  // System.Random wie in der Meldung.
  S := Join(HEAD) + #13#10 + Join(['procedure P;', 'begin',
    '  X := System.Random(6);', 'end;', 'end.']);
  Assert.AreEqual(
    Join(HEAD) + #13#10 + Join(['procedure P;', 'begin',
      '  X := System.Random(6);', 'end;']) + #13#10 + Join(NEW_INIT)
      + #13#10 + 'end.',
    FixAt(S, LineOf(S, 'System.Random'), 'System.Random', Reason));
  Assert.AreEqual('', Reason);
  // Die Anweisung beginnt auf der gemeldeten Zeile, der Aufruf steht auf
  // der naechsten.
  S := Join(HEAD) + #13#10 + Join(['procedure P;', 'begin', '  X :=',
    '    RandomRange(1, 6);', 'end;', 'end.']);
  Assert.AreEqual(
    Join(HEAD) + #13#10 + Join(['procedure P;', 'begin', '  X :=',
      '    RandomRange(1, 6);', 'end;']) + #13#10 + Join(NEW_INIT)
      + #13#10 + 'end.',
    FixAt(S, LineOf(S, 'X :='), 'RandomRange', Reason));
  Assert.AreEqual('', Reason);
end;

procedure TTestRdxInsecureRandomFix.Sca167_CallOf;
var
  Reason : string;
begin
  Assert.AreEqual('Random', TRdxInsecureRandomFix.CallOf(MsgFor('Random')));
  Assert.AreEqual('System.Random',
    TRdxInsecureRandomFix.CallOf(MsgFor('System.Random')));
  Assert.AreEqual('RandomFrom',
    TRdxInsecureRandomFix.CallOf(MsgFor('RandomFrom')));
  Assert.AreEqual('', TRdxInsecureRandomFix.CallOf(MsgFor('Foo')));
  Assert.AreEqual('', TRdxInsecureRandomFix.CallOf('Random(...)'));
  // Ohne Aufruf in der Meldung keine Hilfe.
  Assert.AreEqual('', FixAt(DiceUnit(['end.']), 6, 'Foo', Reason));
  Assert.AreEqual(_(R_RND_NO_CALL), Reason);
end;

// ---- Gegenproben: keine Hilfe ----

procedure TTestRdxInsecureRandomFix.Sca167_Moved_NoHelp;
var
  S, Reason : string;
begin
  // Kommentar, String und ein eigenes Zufallsobjekt sind kein RTL-Random.
  S := Join(HEAD) + #13#10 + Join(['procedure P;', 'begin',
    '  // Random(6)', '  Y := 1;', '  S := ''Random(6)'';', '  Y := 2;',
    '  X := FRng.Random(6);', 'end;', 'end.']);
  Assert.AreEqual('', FixAt(S, LineOf(S, '// Random'), 'Random', Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_RND_MOVED, ['Random'])), Reason);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'S :='), 'Random', Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_RND_MOVED, ['Random'])), Reason);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'FRng'), 'Random', Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_RND_MOVED, ['Random'])), Reason);
end;

procedure TTestRdxInsecureRandomFix.Sca167_SeedPresent_NoHelp;
var
  S : string;
begin
  // Randomize schon im Code - auch qualifiziert: der Fund ist veraltet.
  AssertRefused(DiceUnit(['initialization', '  Randomize;', 'end.']),
    MsgStaleSuffix(_(R_RND_HAS_RANDOMIZE)));
  AssertRefused(DiceUnit(['initialization', '  System.Randomize;', 'end.']),
    MsgStaleSuffix(_(R_RND_HAS_RANDOMIZE)));
  // RandSeed gesetzt: eine feste Folge ist vermutlich gewollt.
  S := DiceUnit(['initialization', '  RandSeed := 42;', 'end.']);
  AssertRefused(S, _(R_RND_RANDSEED, [LineOf(S, 'RandSeed')]));
  // Gegenprobe: Randomize nur im Kommentar zaehlt nicht.
  Assert.AreEqual(
    DiceUnit(['// Randomize', 'initialization', '  Randomize;', '', 'end.']),
    Fixed(DiceUnit(['// Randomize', 'end.'])));
end;

procedure TTestRdxInsecureRandomFix.Sca167_NotUnit_NoHelp;
begin
  AssertRefused(Join(['program p;', 'begin', '  X := Random(6);', 'end.']),
    _(R_RND_NOT_UNIT, [MsgByHand]));
  // Include-Datei ohne 'unit'.
  AssertRefused(Join(DICE), _(R_RND_NO_UNIT));
  // Skript-Unit ohne implementation.
  AssertRefused(Join(['unit t;', 'interface']) + #13#10 + Join(DICE)
    + #13#10 + 'end.', _(R_RND_NO_IMPL));
end;

procedure TTestRdxInsecureRandomFix.Sca167_Legacy_NoHelp;
begin
  // 'begin .. end.' (SCA088): erst initialization daraus machen.
  AssertRefused(DiceUnit(['begin', '  Foo;', 'end.']), _(R_RND_LEGACY));
  AssertRefused(DiceUnit(['begin', '  if A then', '  begin', '    Foo;',
    '  end;', 'end.']), _(R_RND_LEGACY));
end;

procedure TTestRdxInsecureRandomFix.Sca167_Conditional_NoHelp;
begin
  AssertRefused(DiceUnit(['{$IFDEF MSWINDOWS}', 'initialization', '  Foo;',
    '{$ENDIF}', 'end.']), _(R_RND_CONDITIONAL));
  AssertRefused(DiceUnit(['{$IFDEF MSWINDOWS}', 'end.']),
    _(R_RND_CONDITIONAL));
  AssertRefused(DiceUnit(['{$IFDEF A}', 'initialization', '  Foo;',
    '{$ELSE}', 'initialization', '  Bar;', '{$ENDIF}', 'end.']),
    _(R_RND_MANY, [2, 'initialization']));
end;

procedure TTestRdxInsecureRandomFix.Sca167_LineForm_NoHelp;
begin
  // Routine und Unit enden auf einer Zeile.
  AssertRefused(Join(HEAD) + #13#10
    + 'function Dice: Integer; begin Result := Random(6); end; end.',
    _(R_RND_LINE_FORM, ['end']));
end;

{$IFNDEF FPC}

// ---- Echter Detektor (uInsecureRandom) ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TInsecureRandomDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s167_', ASource, fkInsecureRandom, RunDetector);
end;

// Die Hilfe fuer einen Fund des Detektors ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanInsecureRandom) - ohne Quellstellen-
// Dienst, den die Hilfe nicht braucht.
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, fkInsecureRandom);
  try
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt. Jede Anwendung ist gekennzeichnet (E2, Zeile der Tabelle).
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    O := PlanSeen(Result, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet (E2)');
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// Der Detektor meldet, die Hilfe lehnt den ersten Fund mit AReason ab.
procedure AssertDetectorNoHelp(const ASource, AReason: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := PlanSeen(ASource, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(AReason, O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxInsecureRandomFixDetector.Sca167_Detector_RoundTrip;
var
  Source : string;
  Seen   : TArray<TSeen>;
begin
  // Zwei Aufrufe in zwei Routinen - EINE Anwendung erledigt beide Funde.
  Source := DiceUnit(['function Pick: Integer;', 'begin',
    '  Result := RandomRange(1, 10);', 'end;', 'end.']);
  Seen := Detect(Source);
  Assert.AreEqual<Integer>(2, Length(Seen));
  Assert.AreEqual<Integer>(LineOf(Source, 'Random(6)'), Seen[0].Line);
  Assert.AreEqual('Random', TRdxInsecureRandomFix.CallOf(Seen[0].Msg));
  Assert.AreEqual(
    DiceUnit(['function Pick: Integer;', 'begin',
      '  Result := RandomRange(1, 10);', 'end;', 'initialization',
      '  Randomize;', '', 'end.']),
    FixAll(Source));
end;

procedure TTestRdxInsecureRandomFixDetector.Sca167_Detector_ExistingInit_RoundTrip;
begin
  Assert.AreEqual(
    DiceUnit(['initialization', '  Randomize;', '  Foo;', 'end.']),
    FixAll(DiceUnit(['initialization', '  Foo;', 'end.'])));
end;

procedure TTestRdxInsecureRandomFixDetector.Sca167_Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  // Das Beispiel 'bad' des Katalogs (DealCards mit Random(52)) in einer
  // Unit: der Detektor meldet es, nach der Hilfe nicht mehr.
  Meta := TRuleCatalog.GetRuleCanonical(fkInsecureRandom);
  Bad := CatalogText(Meta.BadExample);
  Assert.IsTrue(Pos('Random(52)', Bad) > 0, Bad);
  Assert.AreEqual<Integer>(1,
    Length(Detect(Join(HEAD) + #13#10 + Bad + #13#10 + 'end.')));
  Assert.AreEqual(Join(HEAD) + #13#10 + Bad + #13#10 + Join(NEW_INIT)
    + #13#10 + 'end.',
    FixAll(Join(HEAD) + #13#10 + Bad + #13#10 + 'end.'));
end;

procedure TTestRdxInsecureRandomFixDetector.Sca167_Detector_RandSeed_NoHelp;
var
  S : string;
begin
  // Der Detektor kennt RandSeed nicht und meldet - die Hilfe lehnt ab.
  S := DiceUnit(['initialization', '  RandSeed := 42;', 'end.']);
  AssertDetectorNoHelp(S, _(R_RND_RANDSEED, [LineOf(S, 'RandSeed')]));
end;

procedure TTestRdxInsecureRandomFixDetector.Sca167_Detector_Legacy_NoHelp;
begin
  AssertDetectorNoHelp(DiceUnit(['begin', '  Foo;', 'end.']),
    _(R_RND_LEGACY));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxInsecureRandomFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxInsecureRandomFixDetector);
  {$ENDIF}

end.
