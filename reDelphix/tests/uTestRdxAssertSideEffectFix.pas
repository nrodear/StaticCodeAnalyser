unit uTestRdxAssertSideEffectFix;

// Editorhilfe SCA169 AssertWithSideEffect (uRdxAssertSideEffectFix): der
// Planer auf Text (erste Fixture, auch im FPC-Pruefstand) und - nur Delphi -
// der ECHTE Detektor (uAssertWithSideEffect) auf dem echten AST mit MapFix
// wie der Adapter der Tabelle (zweite Fixture). Die Fixtures stehen in einer
// Routine 'Foo'; die erste Rumpfzeile ist Zeile 6 (STMT_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxAssertSideEffectFix = class
  public
    // ---- Umformung ----
    [Test] procedure Bare_BecomesIfNot;
    [Test] procedure WithMessage_KeepsMessage;
    [Test] procedure QuoteInCondition_Doubled;
    [Test] procedure Parenthesized_NoSecondPair;
    [Test] procedure SystemQualified_KeepsQualifier;
    [Test] procedure NoSemicolonBeforeEnd_NoneAdded;
    [Test] procedure BranchOnOwnLine_BecomesIfNot;
    [Test] procedure TrailingComment_Stays;
    // ---- Gegenproben ----
    [Test] procedure MovedCommentOrString_NoHelp;
    [Test] procedure TwoAsserts_NoHelp;
    [Test] procedure NotAlone_NoHelp;
    [Test] procedure ForeignQualifier_NoHelp;
    [Test] procedure DanglingElse_NoHelp;
    [Test] procedure CaseLabel_NoHelp;
    [Test] procedure MultiLine_NoHelp;
    [Test] procedure CommentOrTail_NoHelp;
    [Test] procedure AnonymousOrGeneric_NoHelp;
    [Test] procedure ArgumentCount_NoHelp;
    [Test] procedure LongCondition_NoHelp;
    [Test] procedure OwnAssertOrWith_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxAssertSideEffectDetector = class
  public
    [Test] procedure Detector_ReportsAssertLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_WithMessage_RoundTrip;
    [Test] procedure Detector_BareName_RoundTrip;
    [Test] procedure Detector_TwoAsserts_BothFixed;
    [Test] procedure Detector_ForeignQualifier_NoHelp;
    [Test] procedure Detector_DanglingElse_NoHelp;
    [Test] procedure MapFix_StaleLine_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uAssertWithSideEffect,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix - wie der Adapter in uRdxFixTable
  uTestRdxDetectorKit,   // TSeen, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxAssertSideEffectFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  STMT_LINE = 6;   // erste Rumpfzeile von Wrap
  // Die Meldung des Detektors (fest, ohne Spalte).
  MSG_169 = 'Assert argument contains a function call - the call has a side '
    + 'effect that disappears in Release builds (Assert is compiled out '
    + 'without DCC_Assertions). Move the call outside Assert.';

// ---- Helfer ----

// Eine Unit mit EINER Routine Foo; Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'procedure Foo(X: Integer);', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
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
      Ok := TRdxAssertSideEffectFix.AssertOutside(Map, ALine, MSG_169, E,
        AReason);
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

procedure TTestRdxAssertSideEffectFix.Bare_BecomesIfNot;
begin
  // Ohne Meldung wird die Bedingung zur Meldung (wie SCA074) - ein
  // 'Assert(False)' meldete SCA074 sofort wieder.
  Assert.AreEqual(
    Wrap(['  if not (UpdateCache(X)) then Assert(False, ''UpdateCache(X)'');']),
    Applied(Wrap(['  Assert(UpdateCache(X));']), STMT_LINE));
  // Ein blosser Name ruft die Funktion ebenso.
  Assert.AreEqual(
    Wrap(['  if not (InitializeSubsystem) then '
      + 'Assert(False, ''InitializeSubsystem'');']),
    Applied(Wrap(['  Assert(InitializeSubsystem);']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.WithMessage_KeepsMessage;
begin
  // Das Komma im String trennt keine Argumente.
  Assert.AreEqual(
    Wrap(['  if not (InitCache(X)) then Assert(False, ''cache, ready'');']),
    Applied(Wrap(['  Assert(InitCache(X), ''cache, ready'');']), STMT_LINE));
  Assert.AreEqual(
    Wrap(['  if not (InitCache(X)) then Assert(False, Format(''%d'', [X]));']),
    Applied(Wrap(['  Assert(InitCache(X), Format(''%d'', [X]));']),
      STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.QuoteInCondition_Doubled;
begin
  Assert.AreEqual(
    Wrap(['  if not (Open(''a.txt'')) then '
      + 'Assert(False, ''Open(''''a.txt'''')'');']),
    Applied(Wrap(['  Assert(Open(''a.txt''));']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.Parenthesized_NoSecondPair;
begin
  Assert.AreEqual(
    Wrap(['  if not (InitA(1) and Ready) then '
      + 'Assert(False, ''(InitA(1) and Ready)'');']),
    Applied(Wrap(['  Assert((InitA(1) and Ready));']), STMT_LINE));
  // Zwei Paare sind nicht EIN Paar um alles.
  Assert.AreEqual(
    Wrap(['  if not ((InitA(1)) and (Ready)) then '
      + 'Assert(False, ''(InitA(1)) and (Ready)'');']),
    Applied(Wrap(['  Assert((InitA(1)) and (Ready));']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.SystemQualified_KeepsQualifier;
begin
  Assert.AreEqual(
    Wrap(['  if not (InitX(1)) then System.Assert(False, ''InitX(1)'');']),
    Applied(Wrap(['  System.Assert(InitX(1));']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.NoSemicolonBeforeEnd_NoneAdded;
begin
  Assert.AreEqual(
    Wrap(['  if not (InitX(1)) then Assert(False, ''InitX(1)'')']),
    Applied(Wrap(['  Assert(InitX(1))']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.BranchOnOwnLine_BecomesIfNot;
begin
  // Im else-Zweig, im then-Zweig ohne else dahinter, hinter do.
  Assert.AreEqual(
    Wrap(['  if A then', '    Foo', '  else',
      '    if not (InitX(1)) then Assert(False, ''InitX(1)'');']),
    Applied(Wrap(['  if A then', '    Foo', '  else',
      '    Assert(InitX(1));']), STMT_LINE + 3));
  Assert.AreEqual(
    Wrap(['  if A then',
      '    if not (InitX(1)) then Assert(False, ''InitX(1)'');', '  Foo;']),
    Applied(Wrap(['  if A then', '    Assert(InitX(1));', '  Foo;']),
      STMT_LINE + 1));
  Assert.AreEqual(
    Wrap(['  for i := 0 to 1 do',
      '    if not (InitX(i)) then Assert(False, ''InitX(i)'');']),
    Applied(Wrap(['  for i := 0 to 1 do', '    Assert(InitX(i));']),
      STMT_LINE + 1));
end;

procedure TTestRdxAssertSideEffectFix.TrailingComment_Stays;
begin
  Assert.AreEqual(
    Wrap(['  if not (InitX(1)) then Assert(False, ''InitX(1)''); // Start']),
    Applied(Wrap(['  Assert(InitX(1)); // Start']), STMT_LINE));
end;

// ---- Gegenproben ----

procedure TTestRdxAssertSideEffectFix.MovedCommentOrString_NoHelp;
begin
  AssertRefused(Wrap(['  Foo;', '  Assert(InitX(1));']), STMT_LINE,
    MsgMovedSuffix(_(R_ASSERTSE_MOVED)));
  AssertRefused(Wrap(['  // Assert(InitX(1));']), STMT_LINE,
    MsgMovedSuffix(_(R_ASSERTSE_MOVED)));
  AssertRefused(Wrap(['  S := ''Assert(InitX(1))'';']), STMT_LINE,
    MsgMovedSuffix(_(R_ASSERTSE_MOVED)));
  // Kein Aufruf von Assert: die Klasse Assert von DUnitX.
  AssertRefused(Wrap(['  Assert.IsTrue(InitX(1));']), STMT_LINE,
    MsgMovedSuffix(_(R_ASSERTSE_MOVED)));
  // Die Zeile beginnt in einem Block-Kommentar.
  AssertRefused(Wrap(['  {', '  } Assert(InitX(1));']), STMT_LINE + 1,
    MsgLineStartsInCommentOrString);
end;

procedure TTestRdxAssertSideEffectFix.TwoAsserts_NoHelp;
begin
  AssertRefused(Wrap(['  Assert(InitX(1)); Assert(InitY(2));']), STMT_LINE,
    _(R_ASSERTSE_MANY));
end;

procedure TTestRdxAssertSideEffectFix.NotAlone_NoHelp;
begin
  AssertRefused(Wrap(['  if A then Assert(InitX(1));']), STMT_LINE,
    _(R_ASSERTSE_NOT_ALONE));
  AssertRefused(Wrap(['  Foo; Assert(InitX(1));']), STMT_LINE,
    _(R_ASSERTSE_NOT_ALONE));
  AssertRefused(Wrap(['  { Start } Assert(InitX(1));']), STMT_LINE,
    _(R_ASSERTSE_NOT_ALONE));
end;

procedure TTestRdxAssertSideEffectFix.ForeignQualifier_NoHelp;
begin
  AssertRefused(Wrap(['  Obj.Assert(InitX(1));']), STMT_LINE,
    _(R_ASSERTSE_FOREIGN, ['Obj']));
end;

procedure TTestRdxAssertSideEffectFix.DanglingElse_NoHelp;
begin
  // 'if A then if not (..) then Assert(..) else Foo' gaebe das else dem
  // neuen if.
  AssertRefused(Wrap(['  if A then', '    Assert(InitX(1))', '  else',
    '    Foo;']), STMT_LINE + 1, _(R_ASSERTSE_DANGLING));
end;

procedure TTestRdxAssertSideEffectFix.CaseLabel_NoHelp;
begin
  AssertRefused(Wrap(['  case K of', '    1:', '      Assert(InitX(1));',
    '  end;']), STMT_LINE + 2, _(R_ASSERTSE_LABEL));
end;

procedure TTestRdxAssertSideEffectFix.MultiLine_NoHelp;
begin
  AssertRefused(Wrap(['  Assert(InitX(1),', '    ''schief'');']), STMT_LINE,
    _(R_ASSERTSE_ONE_LINE));
  // Das ';' erst auf der Folgezeile.
  AssertRefused(Wrap(['  Assert(InitX(1))', '  ;']), STMT_LINE,
    _(R_ASSERTSE_FORM));
end;

procedure TTestRdxAssertSideEffectFix.CommentOrTail_NoHelp;
begin
  AssertRefused(Wrap(['  Assert(InitX(1) { erst });']), STMT_LINE,
    _(R_ASSERTSE_COMMENT));
  AssertRefused(Wrap(['  Assert(InitX(1)); Foo;']), STMT_LINE,
    _(R_ASSERTSE_TAIL));
  AssertRefused(Wrap(['  Assert(InitX(1)); {$IFDEF X}', '  {$ENDIF}']),
    STMT_LINE, _(R_ASSERTSE_TAIL));
end;

procedure TTestRdxAssertSideEffectFix.AnonymousOrGeneric_NoHelp;
begin
  AssertRefused(Wrap(
    ['  Assert(Run(function: Boolean begin Result := Init; end));']),
    STMT_LINE, _(R_ASSERTSE_ANON));
  AssertRefused(Wrap(['  Assert(InitList<Integer>(1));']), STMT_LINE,
    _(R_ASSERTSE_GENERIC));
end;

procedure TTestRdxAssertSideEffectFix.ArgumentCount_NoHelp;
begin
  AssertRefused(Wrap(['  Assert();']), STMT_LINE, _(R_ASSERTSE_ARGS, [1]));
  AssertRefused(Wrap(['  Assert(InitX(1), ''a'', ''b'');']), STMT_LINE,
    _(R_ASSERTSE_ARGS, [3]));
end;

procedure TTestRdxAssertSideEffectFix.LongCondition_NoHelp;
var
  Long : string;
begin
  // Ohne Meldung wuerde die Bedingung ein Literal ueber 255 Zeichen (E2056).
  Long := 'InitX(' + StringOfChar('1', 250) + ')';
  AssertRefused(Wrap(['  Assert(' + Long + ');']), STMT_LINE,
    _(R_ASSERTSE_LONG));
  // Mit Meldung braucht es kein Literal.
  Assert.AreEqual(
    Wrap(['  if not (' + Long + ') then Assert(False, ''lang'');']),
    Applied(Wrap(['  Assert(' + Long + ', ''lang'');']), STMT_LINE));
end;

procedure TTestRdxAssertSideEffectFix.OwnAssertOrWith_NoHelp;
begin
  // Eine eigene Routine Assert der Datei bindet vor System.Assert.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Assert(C: Boolean);', 'begin', 'end;',
    'procedure Foo(X: Integer);', 'begin', '  Assert(InitX(1));', 'end;',
    'end.']), 9, _(R_ASSERTSE_OWN));
  // Ein with davor in der Routine: Assert koennte ein Member sein.
  AssertRefused(Wrap(['  with Obj do', '  begin', '    Assert(InitX(1));',
    '  end;']), STMT_LINE + 2, _(R_ASSERTSE_WITH));
end;

{$IFNDEF FPC}

{ ---- Detektor und MapFix ---- }

// Die Funde der Art SCA169 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAssertWithSideEffectDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_assertse_', ASource, fkAssertWithSideEffect,
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
    Result := MapFix(SL, ASeen.Line, ASeen.Msg,
      TRdxAssertSideEffectFix.AssertOutside);
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

procedure TTestRdxAssertSideEffectDetector.Detector_ReportsAssertLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  Foo;', '  Assert(UpdateCache(X));']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(STMT_LINE + 1, Seen[0].Line, 'Zeile des Assert');
end;

procedure TTestRdxAssertSideEffectDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Wrap(['  Assert(UpdateCache(X));']));
  Assert.AreEqual(
    Wrap(['  if not (UpdateCache(X)) then Assert(False, ''UpdateCache(X)'');']),
    Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxAssertSideEffectDetector.Detector_WithMessage_RoundTrip;
begin
  Assert.AreEqual(
    Wrap(['  if not (InitCache(X)) then Assert(False, ''cache ready'');']),
    FixAll(Wrap(['  Assert(InitCache(X), ''cache ready'');'])));
end;

procedure TTestRdxAssertSideEffectDetector.Detector_BareName_RoundTrip;
begin
  // Das Katalog-Beispiel (BadExample von SCA169) ohne Kommentar.
  Assert.AreEqual(
    Wrap(['  if not (InitializeSubsystem) then '
      + 'Assert(False, ''InitializeSubsystem'');']),
    FixAll(Wrap(['  Assert(InitializeSubsystem);'])));
end;

procedure TTestRdxAssertSideEffectDetector.Detector_TwoAsserts_BothFixed;
var
  Src : string;
begin
  Src := Wrap(['  Assert(UpdateCache(X));', '  Assert(InitCache(X), ''c'');']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(
    Wrap(['  if not (UpdateCache(X)) then Assert(False, ''UpdateCache(X)'');',
      '  if not (InitCache(X)) then Assert(False, ''c'');']),
    FixAll(Src));
end;

procedure TTestRdxAssertSideEffectDetector.Detector_ForeignQualifier_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Der Detektor schneidet den Qualifizierer ab und meldet auch
  // 'Obj.Assert(..)'; die Hilfe nimmt nur System.Assert.
  O := PlanFirst(Wrap(['  Obj.Assert(UpdateCache(X));']), S);
  Assert.AreEqual<Integer>(STMT_LINE, S.Line);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_ASSERTSE_FOREIGN, ['Obj']), O.Reason);
end;

procedure TTestRdxAssertSideEffectDetector.Detector_DanglingElse_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Wrap(['  if A then', '    Assert(UpdateCache(X))', '  else',
    '    Foo;']), S);
  Assert.AreEqual<Integer>(STMT_LINE + 1, S.Line);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_ASSERTSE_DANGLING), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxAssertSideEffectDetector.MapFix_StaleLine_NoHelp;
var
  SL : TStringList;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  try
    // Der Fund zeigt auf Zeile 7, doch dort steht 'end;'.
    SL.Text := Wrap(['  Assert(UpdateCache(X));']);
    O := MapFix(SL, STMT_LINE + 1, MSG_169,
      TRdxAssertSideEffectFix.AssertOutside);
  finally
    SL.Free;
  end;
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_ASSERTSE_MOVED)), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAssertSideEffectFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxAssertSideEffectDetector);
  {$ENDIF}

end.
