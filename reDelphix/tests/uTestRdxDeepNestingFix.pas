unit uTestRdxDeepNestingFix;

// Editorhilfe SCA018 DeepNesting (uRdxDeepNestingFix): der Planer auf Text
// (erste Fixture, FPC-tauglich) und der ECHTE Detektor (uDeepNesting) auf
// dem echten AST mit MapFix wie der Adapter der Tabelle (zweite Fixture,
// nur Delphi). Die Fixtures stehen in einer Routine 'Foo', deren Kopf auf
// Zeile 4 steht; der Rumpf beginnt auf Zeile 5, seine erste Anweisung
// steht auf Zeile 6 (IF_LINE). Die Meldung nennt die Art der tiefsten
// Stelle ('Depth 5 (if from line 8, limit: 4)'); der Planer bekommt deren
// Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDeepNestingFix = class
  public
    // ---- Umformung ----
    [Test] procedure LastIf_BecomesGuard;
    [Test] procedure BeginOnIfLine_BecomesGuard;
    [Test] procedure NotCondition_Stripped;
    [Test] procedure Condition_Parenthesized;
    [Test] procedure MultiLineCondition_Kept;
    [Test] procedure Function_ResultSetBefore_BecomesGuard;
    [Test] procedure NestedBlockAndComments_Dedented;
    [Test] procedure NestedRoutine_UsesInnermost;
    [Test] procedure ForVarInBlock_BecomesGuard;
    // ---- Gegenproben ----
    [Test] procedure Function_ResultNotSet_NoHelp;
    [Test] procedure CodeAfterIfOrElse_NoHelp;
    [Test] procedure IfNotInRoutineBody_NoHelp;
    [Test] procedure ReportedOutsideIf_NoHelp;
    [Test] procedure MovedLineOrMessage_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure CommentInHeadOrTail_NoHelp;
    [Test] procedure InlineVar_NoHelp;
    [Test] procedure AnonymousGotoOrShadowedExit_NoHelp;
    [Test] procedure LayoutOrIndent_NoHelp;
    [Test] procedure ConditionalExpression_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxDeepNestingDetector = class
  public
    [Test] procedure Detector_ReportsDeepestLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoLevelsOver_TwoSteps;
    [Test] procedure Detector_MapFix_OneEdit;
    [Test] procedure Detector_CodeAfterIf_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uDeepNesting,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix (wie der Adapter der Tabelle)
  uTestRdxDetectorKit,   // TSeen, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxDeepNestingFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  IF_LINE = 6;   // erste Rumpfzeile von Wrap
  INNER   = 8;   // das innere if von Std

// ---- Helfer ----

// Eine Unit mit EINER Routine; Kopf auf Zeile 4, Rumpf ab Zeile 6.
function WrapIn(const AHead: string; const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AHead, 'begin'])
    + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

function Wrap(const ABody: array of string): string;
begin
  Result := WrapIn('procedure Foo;', ABody);
end;

// Das Muster: AHead ist die if-Zeile, der Block traegt ein inneres if auf
// Zeile INNER.
function Std(const AHead: string): string;
begin
  Result := Wrap([AHead, '  begin', '    if B then', '      Work;', '  end;']);
end;

// ... und sein Ergebnis mit der Waechter-Klausel AGuard.
function StdFixed(const AGuard: string): string;
begin
  Result := Wrap([AGuard, '  if B then', '    Work;']);
end;

// Die Meldung des Detektors fuer die Art AKind auf Zeile ALine.
function Msg(const AKind: string; ALine: Integer): string;
begin
  Result := Format('Depth 5 (%s from line %d, limit: 4)', [AKind, ALine]);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage: der neue Text, oder
// '' bei Ablehnung (AReason).
function PlanMsg(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Ok := False;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Ok := TRdxDeepNestingFix.GuardClause(Map, ALine, AMessage, E, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Dasselbe fuer die Art AKind auf Zeile ALine.
function Plan(const ASource: string; ALine: Integer; const AKind: string;
  out AReason: string): string;
begin
  Result := PlanMsg(ASource, ALine, Msg(AKind, ALine), AReason);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund); die
// gemeldete Stelle ist eine Struktur der Art AKind.
function AppliedAs(const ASource: string; ALine: Integer;
  const AKind: string): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, AKind, R);
  Assert.IsTrue(Result <> '', R);
end;

// Dasselbe fuer ein if.
function Applied(const ASource: string; ALine: Integer): string;
begin
  Result := AppliedAs(ASource, ALine, 'if');
end;

procedure AssertRefusedAs(const ASource: string; ALine: Integer;
  const AKind, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, AKind, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
begin
  AssertRefusedAs(ASource, ALine, 'if', AReason);
end;

// ---- Umformung ----

procedure TTestRdxDeepNestingFix.LastIf_BecomesGuard;
begin
  Assert.AreEqual(
    Wrap(['  Prepare;', '  if not Ready then Exit;', '  if B then',
      '    Work;', '  More;']),
    Applied(Wrap(['  Prepare;', '  if Ready then', '  begin', '    if B then',
      '      Work;', '    More;', '  end;']), IF_LINE + 3));
  // Ohne ';' hinter dem end; der Block auf Tiefe 4 (Einrueckung des
  // Kopfs mit 'begin' eingerueckt).
  Assert.AreEqual(
    Wrap(['  if not Ready then Exit;', '  if B then', '    Work;']),
    Applied(Wrap(['  if Ready then', '    begin', '      if B then',
      '        Work;', '    end']), INNER));
end;

procedure TTestRdxDeepNestingFix.BeginOnIfLine_BecomesGuard;
begin
  // 'begin' auf der if-Zeile; die gemeldete Stelle ist eine for-Schleife.
  Assert.AreEqual(
    Wrap(['  if not Ready then Exit;', '  for I := 0 to 9 do',
      '    Work(I);']),
    AppliedAs(Wrap(['  if Ready then begin', '    for I := 0 to 9 do',
      '      Work(I);', '  end;']), IF_LINE + 1, 'for'));
end;

procedure TTestRdxDeepNestingFix.NotCondition_Stripped;
begin
  // 'not X' mit einfachem Operand X: das 'not' entfaellt.
  Assert.AreEqual(StdFixed('  if Assigned(F) then Exit;'),
    Applied(Std('  if not Assigned(F) then'), INNER));
  Assert.AreEqual(StdFixed('  if (A or B) then Exit;'),
    Applied(Std('  if not (A or B) then'), INNER));
  Assert.AreEqual(StdFixed('  if F.Items[0]^.Active then Exit;'),
    Applied(Std('  if NOT F.Items[0]^.Active then'), INNER));
end;

procedure TTestRdxDeepNestingFix.Condition_Parenthesized;
begin
  // Einfacher Operand: 'not X'; alles andere in Klammern.
  Assert.AreEqual(StdFixed('  if not List[0].Visible then Exit;'),
    Applied(Std('  if List[0].Visible then'), INNER));
  Assert.AreEqual(StdFixed('  if not (A) then Exit;'),
    Applied(Std('  if (A) then'), INNER));
  Assert.AreEqual(StdFixed('  if not (A and B) then Exit;'),
    Applied(Std('  if A and B then'), INNER));
  Assert.AreEqual(StdFixed('  if not (X = ''a'') then Exit;'),
    Applied(Std('  if X = ''a'' then'), INNER));
  // 'not A and B' ist '(not A) and B' - das not darf nicht entfallen.
  Assert.AreEqual(StdFixed('  if not (not A and B) then Exit;'),
    Applied(Std('  if not A and B then'), INNER));
end;

procedure TTestRdxDeepNestingFix.MultiLineCondition_Kept;
begin
  Assert.AreEqual(
    Wrap(['  if not (A and', '     B) then Exit;', '  if C then',
      '    Work;']),
    Applied(Wrap(['  if A and', '     B then', '  begin', '    if C then',
      '      Work;', '  end;']), IF_LINE + 3));
end;

procedure TTestRdxDeepNestingFix.Function_ResultSetBefore_BecomesGuard;
begin
  Assert.AreEqual(
    WrapIn('function Foo: Integer;', ['  Result := 0;',
      '  if not Ready then Exit;', '  if B then', '    Result := 1;']),
    Applied(WrapIn('function Foo: Integer;', ['  Result := 0;',
      '  if Ready then', '  begin', '    if B then', '      Result := 1;',
      '  end;']), IF_LINE + 3));
  // Der Name der Funktion zaehlt wie Result.
  Assert.AreEqual(
    WrapIn('function Foo: Integer;', ['  Foo := 0;',
      '  if not Ready then Exit;', '  if B then', '    Foo := 1;']),
    Applied(WrapIn('function Foo: Integer;', ['  Foo := 0;',
      '  if Ready then', '  begin', '    if B then', '      Foo := 1;',
      '  end;']), IF_LINE + 3));
end;

procedure TTestRdxDeepNestingFix.NestedBlockAndComments_Dedented;
begin
  // Kommentare, Leerzeile und ein inneres begin..end ruecken mit aus.
  Assert.AreEqual(
    Wrap(['  if not Ready then Exit;', '  // first', '  if B then',
      '  begin', '    Work;', '  end;', '', '  More; // tail']),
    Applied(Wrap(['  if Ready then', '  begin', '    // first',
      '    if B then', '    begin', '      Work;', '    end;', '',
      '    More; // tail', '  end;']), IF_LINE + 3));
end;

procedure TTestRdxDeepNestingFix.NestedRoutine_UsesInnermost;
var
  Src : string;
begin
  // Die Stelle liegt in der geschachtelten Routine; deren letztes if.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    '  procedure Inner;', '  begin', '    if Ready then', '    begin',
    '      if B then', '        Work;', '    end;', '  end;', 'begin',
    '  Inner;', 'end;', 'end.']);
  Assert.AreEqual(
    Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
      '  procedure Inner;', '  begin', '    if not Ready then Exit;',
      '    if B then', '      Work;', '  end;', 'begin', '  Inner;', 'end;',
      'end.']),
    Applied(Src, 9));
end;

procedure TTestRdxDeepNestingFix.ForVarInBlock_BecomesGuard;
begin
  // 'for var' gehoert zu seiner Schleife - keine Sperre.
  Assert.AreEqual(
    Wrap(['  if not Ready then Exit;', '  for var I := 0 to 9 do',
      '    Work(I);']),
    AppliedAs(Wrap(['  if Ready then', '  begin', '    for var I := 0 to 9 do',
      '      Work(I);', '  end;']), INNER, 'for'));
end;

// ---- Gegenproben ----

procedure TTestRdxDeepNestingFix.Function_ResultNotSet_NoHelp;
begin
  AssertRefused(WrapIn('function Foo: Integer;', ['  if Ready then',
    '  begin', '    if B then', '      Result := 1;', '  end;']), INNER,
    _(R_DN_RESULT));
  // Nur bedingt oder in einem Block gesetzt zaehlt nicht.
  AssertRefused(WrapIn('function Foo: Integer;', ['  if X then Result := 0;',
    '  if Ready then', '  begin', '    if B then', '      Result := 1;',
    '  end;']), INNER + 1, _(R_DN_RESULT));
  AssertRefused(WrapIn('function Foo: Integer;', ['  begin',
    '    Result := 0;', '  end;', '  if Ready then', '  begin',
    '    if B then', '      Result := 1;', '  end;']), INNER + 3,
    _(R_DN_RESULT));
end;

procedure TTestRdxDeepNestingFix.CodeAfterIfOrElse_NoHelp;
begin
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work;', '  end;', '  Done;']), INNER, _(R_DN_NOT_LAST));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work;', '  end', '  else', '    Other;']), INNER,
    _(R_DN_NOT_LAST));
  // Das letzte if steht im try - die letzte Anweisung ist das try.
  AssertRefused(Wrap(['  try', '    if Ready then', '    begin',
    '      if B then', '        Work;', '    end;', '  finally', '    Done;',
    '  end;']), INNER + 1, _(R_DN_NOT_LAST));
end;

procedure TTestRdxDeepNestingFix.IfNotInRoutineBody_NoHelp;
begin
  AssertRefused(Wrap(['  while X do', '    if Ready then', '    begin',
    '      if B then', '        Work;', '    end;']), INNER + 1,
    _(R_DN_NOT_TOP, ['do']));
  AssertRefused(Wrap(['  if X then Foo else if Ready then', '  begin',
    '    if B then', '      Work;', '  end;']), INNER,
    _(R_DN_NOT_TOP, ['else']));
  // Hauptblock eines Programms: keine Routine.
  AssertRefused(Join(['program p;', 'begin', '  if Ready then', '  begin',
    '    if B then', '      Work;', '  end;', 'end.']), 5,
    _(R_DN_NO_ROUTINE));
end;

procedure TTestRdxDeepNestingFix.ReportedOutsideIf_NoHelp;
var
  R : string;
begin
  // Die tiefste Stelle liegt VOR dem letzten if - die Waechter-Klausel
  // flachte sie nicht ab.
  Assert.AreEqual('', Plan(Wrap(['  for I := 0 to 9 do', '    Work(I);',
    '  if Ready then', '  begin', '    More;', '  end;']), IF_LINE, 'for', R));
  Assert.AreEqual(_(R_DN_NOT_INSIDE), R);
  // Gemeldet ist das if selbst (Zeile des aeusseren if).
  AssertRefused(Std('  if Ready then'), IF_LINE, _(R_DN_NOT_INSIDE));
end;

procedure TTestRdxDeepNestingFix.MovedLineOrMessage_NoHelp;
var
  R : string;
begin
  // Auf der Zeile steht keine Struktur der gemeldeten Art.
  AssertRefused(Std('  if Ready then'), INNER + 1,
    MsgMovedSuffix(_(R_DN_MOVED, ['if'])));
  AssertRefusedAs(Std('  if Ready then'), INNER, 'while',
    MsgMovedSuffix(_(R_DN_MOVED, ['while'])));
  AssertRefused(Std('  if Ready then'), 99,
    MsgMovedSuffix(_(R_DN_MOVED, ['if'])));
  // 'if' im Kommentar bzw. String ist keine Struktur.
  AssertRefused(Wrap(['  if Ready then', '  begin', '    // if B then',
    '    S := ''if'';', '  end;']), INNER, MsgMovedSuffix(_(R_DN_MOVED, ['if'])));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    // if B then',
    '    S := ''if'';', '  end;']), INNER + 1,
    MsgMovedSuffix(_(R_DN_MOVED, ['if'])));
  // Eine Meldung ohne Art.
  Assert.AreEqual('', PlanMsg(Std('  if Ready then'), INNER, 'deep', R));
  Assert.AreEqual(_(R_DN_MESSAGE), R);
  Assert.AreEqual('', PlanMsg(Std('  if Ready then'), INNER,
    'Depth 5 (with from line 8, limit: 4)', R));
  Assert.AreEqual(_(R_DN_MESSAGE), R);
end;

procedure TTestRdxDeepNestingFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work;', '    {$IFDEF X}', '    More;', '    {$ENDIF}', '  end;']),
    INNER, _(R_DN_DIRECTIVE));
  // Auch vor dem if: bedingter Code kann die letzte Anweisung verschieben.
  AssertRefused(Wrap(['  {$IFDEF X}', '  Prepare;', '  {$ENDIF}',
    '  if Ready then', '  begin', '    if B then', '      Work;', '  end;']),
    INNER + 3, _(R_DN_DIRECTIVE));
end;

procedure TTestRdxDeepNestingFix.CommentInHeadOrTail_NoHelp;
begin
  AssertRefused(Std('  if Ready then // only when ready'), INNER,
    _(R_DN_COMMENT));
  AssertRefused(Std('  if Ready { x } then'), INNER, _(R_DN_COMMENT));
  AssertRefused(Wrap(['  if Ready then', '  begin // b', '    if B then',
    '      Work;', '  end;']), INNER, _(R_DN_COMMENT));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work;', '  end; // done']), INNER, _(R_DN_COMMENT));
end;

procedure TTestRdxDeepNestingFix.InlineVar_NoHelp;
begin
  AssertRefused(Wrap(['  if Ready then', '  begin', '    var X := 1;',
    '    if B then', '      Work(X);', '  end;']), INNER + 1, _(R_DN_INLINE));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    const C = 1;',
    '    if B then', '      Work(C);', '  end;']), INNER + 1,
    _(R_DN_INLINE));
end;

procedure TTestRdxDeepNestingFix.AnonymousGotoOrShadowedExit_NoHelp;
begin
  AssertRefused(Wrap(['  Run(procedure begin Work; end);', '  if Ready then',
    '  begin', '    if B then', '      Work;', '  end;']), INNER + 1,
    _(R_DN_ANON));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      goto L;', '  end;']), INNER, _(R_DN_JUMP));
  // Ein eigener Bezeichner 'Exit' in der Datei.
  AssertRefused(WrapIn('procedure Foo(Exit: Boolean);', ['  if Ready then',
    '  begin', '    if B then', '      Work;', '  end;']), INNER,
    _(R_DN_SHADOW));
end;

procedure TTestRdxDeepNestingFix.LayoutOrIndent_NoHelp;
begin
  // Code hinter begin, if nicht vorn, end nicht vorn.
  AssertRefused(Wrap(['  if Ready then begin Prepare;', '    if B then',
    '      Work;', '  end;']), IF_LINE + 1, _(R_DN_LAYOUT));
  AssertRefused(Wrap(['  Prepare; if Ready then', '  begin', '    if B then',
    '      Work;', '  end;']), INNER, _(R_DN_LAYOUT));
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work; end;']), INNER, _(R_DN_LAYOUT));
  // Eine Blockzeile weniger eingerueckt als die erste.
  AssertRefused(Wrap(['  if Ready then', '  begin', '    if B then',
    '      Work;', ' More;', '  end;']), INNER, _(R_DN_INDENT, [10]));
  // Eine Blockzeile beginnt in einem Block-Kommentar.
  AssertRefused(Wrap(['  if Ready then', '  begin', '    { note',
    '      more }', '    if B then', '      Work;', '  end;']), INNER + 2,
    _(R_DN_MULTILINE));
end;

procedure TTestRdxDeepNestingFix.ConditionalExpression_NoHelp;
begin
  // Delphi 13: 'if X then A else B' als Ausdruck in der Bedingung.
  AssertRefused(Std('  if (if X then A else B) then'), INNER,
    _(R_DN_COND_EXPR));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA018 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TDeepNestingDetector.AnalyzeUnit(Root, Path, Results);
end;

// Die Funde mit der Vorgabe-Grenze 4 (uSCAConsts.DetectorMaxNesting ist
// global; ein anderer Test oder eine ini koennte sie verstellen).
function Detect(const ASource: string): TArray<TSeen>;
var
  Old : Integer;
begin
  Old := DetectorMaxNesting;
  DetectorMaxNesting := 4;
  try
    Result := DetectSource('rdx_nest_', ASource, fkDeepNesting, RunDetector);
  finally
    DetectorMaxNesting := Old;
  end;
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber MapFix - so ruft sie
// der Adapter der Tabelle.
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
    Result := MapFix(SL, ASeen.Line, ASeen.Msg, TRdxDeepNestingFix.GuardClause);
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

// Tiefe 5: if A > if B > if C > if D > if E (Zeile 12).
function Depth5: string;
begin
  Result := Wrap(['  Prepare;', '  if A then', '  begin', '    if B then',
    '      if C then', '        if D then', '          if E then',
    '            Work;', '  end;']);
end;

procedure TTestRdxDeepNestingDetector.Detector_ReportsDeepestLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Depth5);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(12, Seen[0].Line, 'die tiefste Stelle (if E)');
  Assert.AreEqual('Depth 5 (if from line 12, limit: 4)', Seen[0].Msg);
end;

procedure TTestRdxDeepNestingDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Depth5);
  Assert.AreEqual(Wrap(['  Prepare;', '  if not A then Exit;', '  if B then',
    '    if C then', '      if D then', '        if E then',
    '          Work;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxDeepNestingDetector.Detector_TwoLevelsOver_TwoSteps;
var
  Src : string;
begin
  // Tiefe 6: der erste Schritt laesst Tiefe 5 stehen; deren Methode endet
  // wieder mit einem 'if .. then begin .. end', der zweite Schritt greift.
  Src := Wrap(['  if A then', '  begin', '    if B then', '    begin',
    '      if C then', '        if D then', '          if E then',
    '            if F then', '              Work;', '    end;', '  end;']);
  Assert.AreEqual('Depth 6 (if from line 13, limit: 4)', Detect(Src)[0].Msg);
  Assert.AreEqual(Wrap(['  if not A then Exit;', '  if not B then Exit;',
    '  if C then', '    if D then', '      if E then', '        if F then',
    '          Work;']), FixAll(Src));
end;

procedure TTestRdxDeepNestingDetector.Detector_MapFix_OneEdit;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Depth5, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual<Integer>(IF_LINE + 1, O.Edits[0].Span.StartLine, 'ab dem if');
  Assert.AreEqual<Integer>(14, O.Edits[0].Span.EndLine, 'bis zum end');
  Assert.AreEqual('if not A then Exit;'#10, Copy(O.Edits[0].NewText, 1, 20));
  // Die Kennzeichnung setzt erst die Tabellenzeile - der Planer laesst sie
  // auf dem Default (Changes: False).
  Assert.IsFalse(O.ChangesBehavior);
end;

procedure TTestRdxDeepNestingDetector.Detector_CodeAfterIf_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Wrap(['  if A then', '  begin', '    if B then',
    '      if C then', '        if D then', '          if E then',
    '            Work;', '  end;', '  Done;']), S);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DN_NOT_LAST), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDeepNestingFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxDeepNestingDetector);
  {$ENDIF}

end.
