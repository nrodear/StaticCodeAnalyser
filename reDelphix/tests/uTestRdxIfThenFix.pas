unit uTestRdxIfThenFix;

// Editorhilfe SCA131 IfThenShortCircuit (uRdxIfThenFix): der Planer auf Text
// (erste Fixture, auch im FPC-Pruefstand) und - nur Delphi - der ECHTE
// Detektor (uIfThenShortCircuit) auf dem echten AST mit MapFix wie der
// Adapter der Tabelle (zweite Fixture). Die Fixtures stehen in einer
// Routine 'Foo' hinter 'uses <Unit>;'; die erste Rumpfzeile ist Zeile 8
// (STMT_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIfThenFix = class
  public
    // ---- Umformung ----
    [Test] procedure Plain_BecomesIfElse;
    [Test] procedure QualifiedAndFpcUnit_BecomesIfElse;
    [Test] procedure CommasInStringsAndCalls_SplitRight;
    [Test] procedure NoSemicolonBeforeEnd_NoneAdded;
    [Test] procedure TabIndent_KeepsTabs;
    [Test] procedure TrailingComment_Stays;
    [Test] procedure TargetPathAndPositions_BecomesIfElse;
    // ---- Gegenproben ----
    [Test] procedure MovedCommentOrString_NoHelp;
    [Test] procedure TwoIfThen_NoHelp;
    [Test] procedure BranchWithoutBegin_NoHelp;
    [Test] procedure NotAlone_NoHelp;
    [Test] procedure InlineVar_NoHelp;
    [Test] procedure NotWholeRightSide_NoHelp;
    [Test] procedure MultiLineCall_NoHelp;
    [Test] procedure ArgumentCount_NoHelp;
    [Test] procedure GenericOrAnonymous_NoHelp;
    [Test] procedure CommentOrTail_NoHelp;
    [Test] procedure OwnOrForeignIfThen_NoHelp;
    [Test] procedure NoUnitOrWith_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxIfThenDetector = class
  public
    [Test] procedure Detector_ReportsStatementLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_Qualified_RoundTrip;
    [Test] procedure Detector_TwoStatements_BothFixed;
    [Test] procedure Detector_EmbeddedInWrapper_NoHelp;
    [Test] procedure MapFix_StaleLine_NoHelp;
    [Test] procedure TargetOf_ReadsTarget;
    [Test] procedure VariantReason_NamesTarget;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uIfThenShortCircuit,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix - wie der Adapter in uRdxFixTable
  uTestRdxDetectorKit,   // TSeen, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxIfThenFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  STMT_LINE = 8;   // erste Rumpfzeile von Wrap
  // Die Meldung des Detektors (fest, ohne Spalte).
  MSG_131 = 'IfThen() always evaluates both branches - use if/then/else for '
    + 'side-effecting calls';

// ---- Helfer ----

// Eine Unit mit 'uses AUses;' und EINER Routine Foo; Rumpf ab Zeile 8.
function Wrap(const AUses: string; const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'uses',
    '  ' + AUses + ';', 'procedure Foo(b: Boolean);', 'begin']) + #13#10
    + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

function Src(const ABody: array of string): string;
begin
  Result := Wrap('System.Math', ABody);
end;

// Der Planer fuer Zeile ALine: der neue Text, oder '' bei Ablehnung
// (AReason).
function Plan(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Ok := TRdxIfThenFix.IfThenToIf(Map, ALine, MSG_131, E, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxIfThenFix.Plain_BecomesIfElse;
begin
  Assert.AreEqual(
    Src(['  if b then', '    x := A()', '  else', '    x := B();']),
    Applied(Src(['  x := IfThen(b, A(), B());']), STMT_LINE));
  // Gross/klein egal, Leerraum im Aufruf faellt weg.
  Assert.AreEqual(
    Src(['  if Ready(1) then', '    Result := Load', '  else',
      '    Result := Fallback(2);']),
    Applied(Src(['  Result := IFTHEN( Ready(1) ,Load,  Fallback(2) );']),
      STMT_LINE));
end;

procedure TTestRdxIfThenFix.QualifiedAndFpcUnit_BecomesIfElse;
begin
  // FPC (und alte Delphi-Units) nennen die Unit ohne 'System.'.
  Assert.AreEqual(
    Wrap('Math', ['  if b then', '    x := A()', '  else', '    x := B();']),
    Applied(Wrap('Math', ['  x := Math.IfThen(b, A(), B());']), STMT_LINE));
  Assert.AreEqual(
    Wrap('Classes, System.StrUtils', ['  if b then', '    s := GetA()',
      '  else', '    s := GetB();']),
    Applied(Wrap('Classes, System.StrUtils',
      ['  s := System.StrUtils.IfThen(b, GetA(), GetB());']), STMT_LINE));
  // 'Name in ''datei''' (Programmdatei) zaehlt mit dem Namen.
  Assert.AreEqual(
    Wrap('StrUtils in ''..\StrUtils.pas''', ['  if b then', '    s := GetA()',
      '  else', '    s := GetB();']),
    Applied(Wrap('StrUtils in ''..\StrUtils.pas''',
      ['  s := StrUtils.IfThen(b, GetA(), GetB());']), STMT_LINE));
end;

procedure TTestRdxIfThenFix.CommasInStringsAndCalls_SplitRight;
begin
  // Kommas in Strings und in Klammern trennen keine Argumente; die Strings
  // bleiben wie geschrieben.
  Assert.AreEqual(
    Wrap('System.StrUtils', ['  if Ok(1, 2) then', '    s := Load(''a,b'')',
      '  else', '    s := Fallback([1, 2], ''x'''', y'');']),
    Applied(Wrap('System.StrUtils',
      ['  s := IfThen(Ok(1, 2), Load(''a,b''), Fallback([1, 2], ''x'''', y''));']),
      STMT_LINE));
end;

procedure TTestRdxIfThenFix.NoSemicolonBeforeEnd_NoneAdded;
begin
  Assert.AreEqual(
    Src(['  if b then', '    x := A()', '  else', '    x := B()']),
    Applied(Src(['  x := IfThen(b, A(), B())']), STMT_LINE));
end;

procedure TTestRdxIfThenFix.TabIndent_KeepsTabs;
begin
  Assert.AreEqual(
    Src([#9'if b then', #9#9'x := A()', #9'else', #9#9'x := B();']),
    Applied(Src([#9'x := IfThen(b, A(), B());']), STMT_LINE));
end;

procedure TTestRdxIfThenFix.TrailingComment_Stays;
begin
  Assert.AreEqual(
    Src(['  if b then', '    x := A()', '  else', '    x := B(); // Wert']),
    Applied(Src(['  x := IfThen(b, A(), B()); // Wert']), STMT_LINE));
end;

procedure TTestRdxIfThenFix.TargetPathAndPositions_BecomesIfElse;
begin
  // Ein Pfad mit Index als Ziel.
  Assert.AreEqual(
    Src(['  if b then', '    Self.FItems[i + 1].Value := A()', '  else',
      '    Self.FItems[i + 1].Value := B();']),
    Applied(Src(['  Self.FItems[i + 1].Value := IfThen(b, A(), B());']),
      STMT_LINE));
  // Hinter ';', im try- und im repeat-Teil.
  Assert.AreEqual(
    Src(['  y := 1;', '  try', '    if b then', '      x := A()', '    else',
      '      x := B();', '  finally', '    Done;', '  end;']),
    Applied(Src(['  y := 1;', '  try', '    x := IfThen(b, A(), B());',
      '  finally', '    Done;', '  end;']), STMT_LINE + 2));
  Assert.AreEqual(
    Src(['  repeat', '    if b then', '      x := A()', '    else',
      '      x := B();', '  until x > 0;']),
    Applied(Src(['  repeat', '    x := IfThen(b, A(), B());',
      '  until x > 0;']), STMT_LINE + 1));
end;

// ---- Gegenproben ----

procedure TTestRdxIfThenFix.MovedCommentOrString_NoHelp;
begin
  // Zeile verschoben: dort steht kein IfThen.
  AssertRefused(Src(['  y := 1;', '  x := IfThen(b, A(), B());']), STMT_LINE,
    MsgMovedSuffix(_(R_IFTHEN_MOVED)));
  // Kommentar und String sind nie Code.
  AssertRefused(Src(['  // x := IfThen(b, A(), B());']), STMT_LINE,
    MsgMovedSuffix(_(R_IFTHEN_MOVED)));
  AssertRefused(Src(['  s := ''x := IfThen(b, A(), B())'';']), STMT_LINE,
    MsgMovedSuffix(_(R_IFTHEN_MOVED)));
  // Die Zeile beginnt in einem Block-Kommentar.
  AssertRefused(Src(['  {', '  } x := IfThen(b, A(), B());']), STMT_LINE + 1,
    MsgLineStartsInCommentOrString);
end;

procedure TTestRdxIfThenFix.TwoIfThen_NoHelp;
begin
  AssertRefused(Src(['  x := IfThen(b, IfThen(c, A(), B()), C());']),
    STMT_LINE, _(R_IFTHEN_MANY));
end;

procedure TTestRdxIfThenFix.BranchWithoutBegin_NoHelp;
begin
  AssertRefused(Src(['  if c then', '    x := IfThen(b, A(), B());']),
    STMT_LINE + 1, _(R_IFTHEN_BRANCH, ['then']));
  AssertRefused(Src(['  if c then', '    y := 1', '  else',
    '    x := IfThen(b, A(), B());']), STMT_LINE + 3,
    _(R_IFTHEN_BRANCH, ['else']));
  AssertRefused(Src(['  for i := 0 to 1 do', '    x := IfThen(b, A(), B());']),
    STMT_LINE + 1, _(R_IFTHEN_BRANCH, ['do']));
  AssertRefused(Src(['  case k of', '    1:', '      x := IfThen(b, A(), B());',
    '  end;']), STMT_LINE + 2, _(R_IFTHEN_BRANCH, [':']));
  // Auf derselben Zeile wie das then: das Ziel waere 'if c then x'.
  AssertRefused(Src(['  if c then x := IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_FORM));
end;

procedure TTestRdxIfThenFix.NotAlone_NoHelp;
begin
  AssertRefused(Src(['  y := 1; x := IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_NOT_ALONE));
  AssertRefused(Src(['  { Wert } x := IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_NOT_ALONE));
  // Keine Zuweisung: ein Aufruf mit IfThen als Argument.
  AssertRefused(Src(['  ShowMessage(IfThen(b, A(), B()));']), STMT_LINE,
    _(R_IFTHEN_FORM));
end;

procedure TTestRdxIfThenFix.InlineVar_NoHelp;
begin
  AssertRefused(Src(['  var x := IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_INLINE, ['var']));
end;

procedure TTestRdxIfThenFix.NotWholeRightSide_NoHelp;
begin
  AssertRefused(Src(['  x := Trim(IfThen(b, A(), B()));']), STMT_LINE,
    _(R_IFTHEN_NOT_WHOLE));
  AssertRefused(Src(['  x := IfThen(b, A(), B()) + 1;']), STMT_LINE,
    _(R_IFTHEN_NOT_WHOLE));
  AssertRefused(Src(['  x := 1 + IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_NOT_WHOLE));
end;

procedure TTestRdxIfThenFix.MultiLineCall_NoHelp;
begin
  AssertRefused(Src(['  x := IfThen(b, A(),', '    B());']), STMT_LINE,
    _(R_IFTHEN_ONE_LINE));
  // Das ';' erst auf der Folgezeile.
  AssertRefused(Src(['  x := IfThen(b, A(), B())', '  ;']), STMT_LINE,
    _(R_IFTHEN_FORM));
end;

procedure TTestRdxIfThenFix.ArgumentCount_NoHelp;
begin
  AssertRefused(Src(['  s := IfThen(b, Load());']), STMT_LINE,
    _(R_IFTHEN_TWO_ARGS));
  AssertRefused(Src(['  x := IfThen(b);']), STMT_LINE,
    _(R_IFTHEN_ARGS, [1]));
end;

procedure TTestRdxIfThenFix.GenericOrAnonymous_NoHelp;
begin
  AssertRefused(Src(['  x := IfThen(b, TFoo<Integer>.Make(), B());']),
    STMT_LINE, _(R_IFTHEN_GENERIC));
  AssertRefused(Src(
    ['  x := IfThen(b, Run(function: Integer begin Result := 1; end), B());']),
    STMT_LINE, _(R_IFTHEN_ANON));
end;

procedure TTestRdxIfThenFix.CommentOrTail_NoHelp;
begin
  AssertRefused(Src(['  x := IfThen(b, A() { erst }, B());']), STMT_LINE,
    _(R_IFTHEN_COMMENT));
  AssertRefused(Src(['  x := IfThen(b, A(), B()); {$IFDEF X}', '  {$ENDIF}']),
    STMT_LINE, _(R_IFTHEN_TAIL));
  AssertRefused(Src(['  x := IfThen(b, A(), B()); y := 1;']), STMT_LINE,
    _(R_IFTHEN_TAIL));
end;

procedure TTestRdxIfThenFix.OwnOrForeignIfThen_NoHelp;
begin
  // Eine eigene IfThen der Datei bindet vor System.Math.
  AssertRefused(Join(['unit t;', 'interface', 'implementation', 'uses',
    '  System.Math;', 'function IfThen(c: Boolean; a, b: Integer): Integer;',
    'begin', '  Result := a;', 'end;', 'procedure Foo(b: Boolean);', 'begin',
    '  x := IfThen(b, A(), B());', 'end;', 'end.']), 12, _(R_IFTHEN_OWN));
  // Ein fremder Qualifizierer.
  AssertRefused(Src(['  x := Foo.IfThen(b, A(), B());']), STMT_LINE,
    _(R_IFTHEN_FOREIGN, ['Foo']));
end;

procedure TTestRdxIfThenFix.NoUnitOrWith_NoHelp;
begin
  // Weder System.Math noch System.StrUtils in uses - auch nicht als Teil
  // eines laengeren Namens.
  AssertRefused(Wrap('System.SysUtils, MyMath', ['  x := IfThen(b, A(), B());']),
    STMT_LINE, _(R_IFTHEN_NO_UNIT));
  // Ein with davor in der Routine: IfThen oder x koennten Member sein.
  AssertRefused(Src(['  with Obj do', '  begin',
    '    x := IfThen(b, A(), B());', '  end;']), STMT_LINE + 2,
    _(R_IFTHEN_WITH));
end;

{$IFNDEF FPC}

{ ---- Detektor und MapFix ---- }

// Die Funde der Art SCA131 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TIfThenShortCircuitDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ifthen_', ASource, fkIfThenShortCircuit,
    RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors - MapFix wie der Adapter der
// Tabelle (Zeile und Meldung aus dem Fund).
function PlanFirst(const ASource: string; out ASeen: TSeen): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  ASeen := Seen[0];
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := MapFix(SL, ASeen.Line, ASeen.Msg, TRdxIfThenFix.IfThenToIf);
  finally
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  O    : TRdxFixOutcome;
  S    : TSeen;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    if Length(Detect(Result)) = 0 then
      Exit;
    O := PlanFirst(Result, S);
    Assert.IsTrue(O.Enabled, O.Reason);
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxIfThenDetector.Detector_ReportsStatementLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Src(['  y := 1;', '  x := IfThen(b, A(), B());']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(STMT_LINE + 1, Seen[0].Line, 'Zeile der Anweisung');
end;

procedure TTestRdxIfThenDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Src(['  x := IfThen(b, A(), B());']));
  Assert.AreEqual(
    Src(['  if b then', '    x := A()', '  else', '    x := B();']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxIfThenDetector.Detector_Qualified_RoundTrip;
begin
  Assert.AreEqual(
    Wrap('Math', ['  if b then', '    x := Compute()', '  else',
      '    x := Fallback();']),
    FixAll(Wrap('Math', ['  x := Math.IfThen(b, Compute(), Fallback());'])));
end;

procedure TTestRdxIfThenDetector.Detector_TwoStatements_BothFixed;
var
  Src2 : string;
begin
  Src2 := Src(['  x := IfThen(b, A(), B());', '  y := IfThen(b, 0, C());']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src2)), 'zwei Funde');
  Assert.AreEqual(
    Src(['  if b then', '    x := A()', '  else', '    x := B();',
      '  if b then', '    y := 0', '  else', '    y := C();']),
    FixAll(Src2));
end;

procedure TTestRdxIfThenDetector.Detector_EmbeddedInWrapper_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet auch das eingebettete IfThen (Major 70); die Hilfe
  // formt nur die ganze rechte Seite um.
  O := PlanFirst(Src(['  x := Trim(IfThen(b, A(), B()));']), S);
  Assert.AreEqual<Integer>(STMT_LINE, S.Line);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_IFTHEN_NOT_WHOLE), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxIfThenDetector.MapFix_StaleLine_NoHelp;
var
  SL : TStringList;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  try
    // Der Fund zeigt auf Zeile 9, doch dort steht 'end;'.
    SL.Text := Src(['  x := IfThen(b, A(), B());']);
    O := MapFix(SL, STMT_LINE + 1, MSG_131, TRdxIfThenFix.IfThenToIf);
  finally
    SL.Free;
  end;
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_IFTHEN_MOVED)), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxIfThenDetector.TargetOf_ReadsTarget;
var
  O : TRdxFixOutcome;
  S : TSeen;
begin
  // Das Ziel aus der Ersetzung - so liest es der Adapter fuer die Typfrage.
  O := PlanFirst(Src(['  FList[i] := IfThen(b, A(), B());']), S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('FList[i]', TRdxIfThenFix.TargetOf(O.Edits[0].Expected));
  Assert.AreEqual('', TRdxIfThenFix.TargetOf('x'), 'ohne ":="');
end;

procedure TTestRdxIfThenDetector.VariantReason_NamesTarget;
begin
  Assert.AreEqual(_(R_IFTHEN_VARIANT, ['V']),
    TRdxIfThenFix.VariantReason('V'));
  Assert.IsTrue(Pos('V', TRdxIfThenFix.VariantReason('V')) > 0,
    'der Grund nennt das Ziel');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIfThenFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxIfThenDetector);
  {$ENDIF}

end.
