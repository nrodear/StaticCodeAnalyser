unit uTestRdxGotoExitFix;

// Editorhilfe SCA060 GotoStatement (uRdxGotoExitFix), nur Delphi
// (reDelphix.Test): der Planer auf Text (erste Fixture), der Adapter in der
// Form der Tabelle und der ECHTE Detektor (uGotoStatement) auf dem echten
// AST (zweite Fixture). Die Fixtures stehen in einer Routine 'Foo', deren
// Kopf auf Zeile 4 steht; der Rumpf beginnt auf Zeile 6, seine erste
// Anweisung steht auf Zeile 7 (GOTO_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxGotoExitFix = class
  public
    // ---- Umformung ----
    [Test] procedure LabelAtEnd_BecomesExit;
    [Test] procedure LabelWithEmptyStatement_BecomesExit;
    [Test] procedure LabelCaseInsensitive_BecomesExit;
    [Test] procedure NumericLabel_BecomesExit;
    [Test] procedure Function_BecomesExit;
    [Test] procedure InsideTryFinally_BecomesExit;
    [Test] procedure ElseBranch_BecomesExit;
    [Test] procedure NestedRoutine_UsesInnermost;
    [Test] procedure OuterRoutineAfterNested_BecomesExit;
    // ---- Gegenproben ----
    [Test] procedure LabelNotLast_NoHelp;
    [Test] procedure LabelInNestedBlock_NoHelp;
    [Test] procedure LabelOfOuterRoutine_NoHelp;
    [Test] procedure TwoGotosOnLine_NoHelp;
    [Test] procedure MovedLineOrColumn_NoHelp;
    [Test] procedure CommentOrStringGoto_NoHelp;
    [Test] procedure CommentInsideGoto_NoHelp;
    [Test] procedure LabelOnNextLine_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure AnonymousMethod_NoHelp;
    [Test] procedure MainBlock_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxGotoExitDetector = class
  public
    // ---- Adapter der Tabelle ----
    [Test] procedure Adapter_PlansExitWithoutBehaviorChange;
    [Test] procedure Adapter_StaleFinding_NoHelp;
    [Test] procedure Adapter_NoColumn_NoHelp;
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsGotoLineAndColumn;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoGotos_BothFixed;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_LabelNotLast_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uGotoStatement,
  uRdxRecipeRunner,
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxGotoExitFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  GOTO_LINE = 7;   // erste Rumpfzeile von Wrap

// ---- Helfer ----

// Eine Unit mit EINER Routine; Kopf auf Zeile 4, Rumpf ab Zeile 7.
function WrapIn(const AHead: string; const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AHead,
    'label Fin;', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

function Wrap(const ABody: array of string): string;
begin
  Result := WrapIn('procedure Foo;', ABody);
end;

// Die Spalte des ersten 'goto' (ohne Gross/klein) in Zeile ALine von
// ASource; 0 ohne.
function GotoCol(const ASource: string; ALine: Integer): Integer;
var
  SL : TStringList;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    if (ALine >= 1) and (ALine <= SL.Count) then
      Result := Pos('goto', LowerCase(SL[ALine - 1]));
    // Ohne 'goto' auf der Zeile: eine Spalte, die der Planer pruefen muss.
    if Result = 0 then
      Result := 1;
  finally
    SL.Free;
  end;
end;

// Der Planer fuer Zeile ALine, Spalte ACol: der neue Text, oder '' bei
// Ablehnung (AReason).
function PlanAt(const ASource: string; ALine, ACol: Integer;
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
      Ok := TRdxGotoExitFix.GotoToExit(Map, ALine,
        Format('`goto` weakens structured control flow (col %d).', [ACol]),
        E, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Wie PlanAt, die Spalte ist die des ersten 'goto' der Zeile.
function Plan(const ASource: string; ALine: Integer;
  out AReason: string): string;
begin
  Result := PlanAt(ASource, ALine, GotoCol(ASource, ALine), AReason);
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

procedure TTestRdxGotoExitFix.LabelAtEnd_BecomesExit;
begin
  Assert.AreEqual(
    Wrap(['  if Failed then Exit;', '  Work;', 'Fin:']),
    Applied(Wrap(['  if Failed then goto Fin;', '  Work;', 'Fin:']),
      GOTO_LINE));
  // Eingerueckte Marke und mehrere Leerzeilen davor.
  Assert.AreEqual(
    Wrap(['  Exit;', '', '  Work;', '', '  Fin:']),
    Applied(Wrap(['  goto Fin;', '', '  Work;', '', '  Fin:']), GOTO_LINE));
end;

procedure TTestRdxGotoExitFix.LabelWithEmptyStatement_BecomesExit;
begin
  Assert.AreEqual(
    Wrap(['  if A then Exit;', 'Fin: ;']),
    Applied(Wrap(['  if A then goto Fin;', 'Fin: ;']), GOTO_LINE));
end;

procedure TTestRdxGotoExitFix.LabelCaseInsensitive_BecomesExit;
begin
  Assert.AreEqual(
    Wrap(['  if A then Exit;', '  FIN:']),
    Applied(Wrap(['  if A then GoTo fin;', '  FIN:']), GOTO_LINE));
end;

procedure TTestRdxGotoExitFix.NumericLabel_BecomesExit;
begin
  Assert.AreEqual(
    Wrap(['  if A then Exit;', '  99:']),
    Applied(Wrap(['  if A then goto 99;', '  99:']), GOTO_LINE));
end;

procedure TTestRdxGotoExitFix.Function_BecomesExit;
begin
  // Result bleibt in beiden Faellen, wie es ist.
  Assert.AreEqual(
    WrapIn('function Foo: Integer;', ['  Result := 1;',
      '  if Failed then Exit;', '  Result := 2;', 'Fin:']),
    Applied(WrapIn('function Foo: Integer;', ['  Result := 1;',
      '  if Failed then goto Fin;', '  Result := 2;', 'Fin:']),
      GOTO_LINE + 1));
end;

procedure TTestRdxGotoExitFix.InsideTryFinally_BecomesExit;
begin
  // Beide laufen durch das finally.
  Assert.AreEqual(
    Wrap(['  try', '    if A then Exit;', '    Work;', '  finally',
      '    Cleanup;', '  end;', 'Fin:']),
    Applied(Wrap(['  try', '    if A then goto Fin;', '    Work;',
      '  finally', '    Cleanup;', '  end;', 'Fin:']), GOTO_LINE + 1));
end;

procedure TTestRdxGotoExitFix.ElseBranch_BecomesExit;
begin
  Assert.AreEqual(
    Wrap(['  if A then', '    Work', '  else Exit;', '  More;', 'Fin:']),
    Applied(Wrap(['  if A then', '    Work', '  else goto Fin;', '  More;',
      'Fin:']), GOTO_LINE + 2));
end;

procedure TTestRdxGotoExitFix.NestedRoutine_UsesInnermost;
var
  Src : string;
begin
  // Das 'goto' steht in der verschachtelten Routine, deren eigene letzte
  // Marke Fin ist.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    '  procedure Inner;', '  label Fin;', '  begin',
    '    if A then goto Fin;', '    Work;', '  Fin:', '  end;', 'begin',
    '  Inner;', 'end;', 'end.']);
  Assert.AreEqual(
    StringReplace(Src, 'goto Fin', 'Exit', []),
    Applied(Src, 8));
end;

procedure TTestRdxGotoExitFix.OuterRoutineAfterNested_BecomesExit;
var
  Src : string;
begin
  // Die verschachtelte Routine ist zu Ende; das 'goto' gehoert der aeusseren.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    '  procedure Inner;', '  begin', '  end;', 'label Fin;', 'begin',
    '  if A then goto Fin;', '  Inner;', 'Fin:', 'end;', 'end.']);
  Assert.AreEqual(
    StringReplace(Src, 'goto Fin', 'Exit', []),
    Applied(Src, 10));
end;

// ---- Gegenproben ----

procedure TTestRdxGotoExitFix.LabelNotLast_NoHelp;
begin
  // Code hinter der Marke: 'Exit' wuerde ihn ueberspringen.
  AssertRefused(Wrap(['  if A then goto Fin;', 'Fin:', '  Cleanup;']),
    GOTO_LINE, _(R_GOTO_NOT_LAST, ['Fin']));
  // Eine andere Marke am Ende.
  AssertRefused(Wrap(['  if A then goto Fin;', 'Fin:', '  Cleanup;',
    'Done:']), GOTO_LINE, _(R_GOTO_NOT_LAST, ['Fin']));
  // Marke ohne Doppelpunkt ist keine Marke.
  AssertRefused(Wrap(['  if A then goto Fin;', '  Fin']), GOTO_LINE,
    _(R_GOTO_NOT_LAST, ['Fin']));
end;

procedure TTestRdxGotoExitFix.LabelInNestedBlock_NoHelp;
begin
  // Die Marke ist die letzte Anweisung eines inneren Blocks, nicht der
  // Routine.
  AssertRefused(Wrap(['  if A then', '  begin', '    goto Fin;',
    '    Work;', '  Fin:', '  end;']), GOTO_LINE + 2,
    _(R_GOTO_NOT_LAST, ['Fin']));
end;

procedure TTestRdxGotoExitFix.LabelOfOuterRoutine_NoHelp;
var
  Src : string;
begin
  // Die Marke Fin ist Ende der AEUSSEREN Routine; das 'goto' in der
  // verschachtelten gehoert zu deren eigener Marke - die hier fehlt.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    '  procedure Inner;', '  begin', '    goto Fin;', '    Work;',
    '  end;', 'begin', '  Inner;', 'Fin:', 'end;', 'end.']);
  AssertRefused(Src, 7, _(R_GOTO_NOT_LAST, ['Fin']));
end;

procedure TTestRdxGotoExitFix.TwoGotosOnLine_NoHelp;
begin
  AssertRefused(Wrap(['  if A then goto Fin else if B then goto Fin;',
    'Fin:']), GOTO_LINE, _(R_GOTO_MANY));
end;

procedure TTestRdxGotoExitFix.MovedLineOrColumn_NoHelp;
var
  Src, R : string;
begin
  Src := Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']);
  // Die Zeile davor / danach traegt kein 'goto'.
  AssertRefused(Src, GOTO_LINE + 1, MsgMovedSuffix(_(R_GOTO_MOVED)));
  Assert.AreEqual('', PlanAt(Src, GOTO_LINE, 1, R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GOTO_MOVED)), R, 'Spalte 1');
  Assert.AreEqual('', PlanAt(Src, GOTO_LINE, 99, R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GOTO_MOVED)), R, 'Spalte hinter der Zeile');
  Assert.AreEqual('', PlanAt(Src, 99, 3, R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GOTO_MOVED)), R, 'Zeile hinter der Datei');
  // Ohne Spalte in der Meldung.
  Assert.AreEqual('', PlanAt(Src, GOTO_LINE, 0, R));
  Assert.AreEqual(MsgNoColumn, R, 'keine Spalte');
end;

procedure TTestRdxGotoExitFix.CommentOrStringGoto_NoHelp;
var
  R, Fixed : string;
begin
  // Kommentar und String sind nie Code.
  AssertRefused(Wrap(['  // goto Fin;', '  Work;', 'Fin:']), GOTO_LINE,
    MsgMovedSuffix(_(R_GOTO_MOVED)));
  AssertRefused(Wrap(['  S := ''goto Fin;'';', '  Work;', 'Fin:']),
    GOTO_LINE, MsgMovedSuffix(_(R_GOTO_MOVED)));
  AssertRefused(Wrap(['  { goto Fin; }', '  Work;', 'Fin:']), GOTO_LINE,
    MsgMovedSuffix(_(R_GOTO_MOVED)));
  // Ein 'goto' im Kommentar zaehlt nicht als zweites.
  Fixed := Plan(Wrap(['  if A then goto Fin; // goto Fin;', 'Fin:']),
    GOTO_LINE, R);
  Assert.IsTrue(Fixed <> '', R);
  Assert.AreEqual(Wrap(['  if A then Exit; // goto Fin;', 'Fin:']), Fixed);
end;

procedure TTestRdxGotoExitFix.CommentInsideGoto_NoHelp;
begin
  AssertRefused(Wrap(['  if A then goto { weiter } Fin;', 'Fin:']),
    GOTO_LINE, _(R_GOTO_COMMENT));
end;

procedure TTestRdxGotoExitFix.LabelOnNextLine_NoHelp;
begin
  AssertRefused(Wrap(['  if A then goto', '    Fin;', 'Fin:']), GOTO_LINE,
    _(R_GOTO_FORM));
end;

procedure TTestRdxGotoExitFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  if A then goto Fin;', '  {$IFDEF X}', '  Work;',
    '  {$ENDIF}', 'Fin:']), GOTO_LINE, _(R_GOTO_DIRECTIVE));
  // Auch auf der Zeile selbst.
  AssertRefused(Wrap(['  if A then goto Fin; {$IFDEF X}', '  Work;',
    '  {$ENDIF}', 'Fin:']), GOTO_LINE, _(R_GOTO_DIRECTIVE));
end;

procedure TTestRdxGotoExitFix.AnonymousMethod_NoHelp;
begin
  AssertRefused(Wrap(['  if A then goto Fin;',
    '  Run(procedure begin Work; end);', 'Fin:']), GOTO_LINE,
    _(R_GOTO_ANON));
end;

procedure TTestRdxGotoExitFix.MainBlock_NoHelp;
begin
  // Hauptblock eines Programms: keine Routine.
  AssertRefused(Join(['program p;', 'label Fin;', 'begin',
    '  if A then goto Fin;', '  Work;', 'Fin:', 'end.']), 4,
    _(R_GOTO_NO_ROUTINE));
end;

{$IFNDEF FPC}

{ ---- Adapter und Detektor ---- }

// Die Funde der Art SCA060 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TGotoStatementDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_goto_', ASource, fkGotoStatement, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors, so wie die Tabelle sie ruft
// (Adapter).
function PlanFirst(const ASource: string; out ASeen: TSeen): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  ASeen := Seen[0];
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, fkGotoStatement);
  try
    SL.Text := ASource;
    Result := PlanGotoExit(nil, SL, F, nil);
  finally
    F.Free;
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

procedure TTestRdxGotoExitDetector.Adapter_PlansExitWithoutBehaviorChange;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']), S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, O.Variant, 'Hauptweg');
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual('goto Fin', O.Edits[0].Expected);
  Assert.AreEqual('Exit', O.Edits[0].NewText);
  Assert.AreEqual<Integer>(GOTO_LINE, O.Edits[0].Span.StartLine);
end;

procedure TTestRdxGotoExitDetector.Adapter_StaleFinding_NoHelp;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  // Der Fund zeigt auf Zeile 8, doch dort steht kein 'goto'.
  F := TLeakFinding.New('t.pas', '', GOTO_LINE + 1, 'x (col 3).',
    fkGotoStatement);
  try
    SL.Text := Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']);
    O := PlanGotoExit(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_GOTO_MOVED)), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxGotoExitDetector.Adapter_NoColumn_NoHelp;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', GOTO_LINE, 'goto', fkGotoStatement);
  try
    SL.Text := Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']);
    O := PlanGotoExit(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(MsgNoColumn, O.Reason);
end;

procedure TTestRdxGotoExitDetector.Detector_ReportsGotoLineAndColumn;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(GOTO_LINE, Seen[0].Line, 'Zeile des goto');
  Assert.AreEqual<Integer>(13, GotoColumn(Seen[0].Msg), 'Spalte des goto');
end;

procedure TTestRdxGotoExitDetector.Detector_RoundTrip;
var
  Src, Fixed : string;
begin
  Src := Wrap(['  if A then goto Fin;', '  Work;', 'Fin:']);
  Fixed := FixAll(Src);
  Assert.AreEqual(Wrap(['  if A then Exit;', '  Work;', 'Fin:']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxGotoExitDetector.Detector_TwoGotos_BothFixed;
var
  Src, Fixed : string;
begin
  Src := Wrap(['  if A then goto Fin;', '  Work;', '  if B then goto Fin;',
    '  More;', 'Fin:']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Fixed := FixAll(Src);
  Assert.AreEqual(Wrap(['  if A then Exit;', '  Work;', '  if B then Exit;',
    '  More;', 'Fin:']), Fixed);
end;

procedure TTestRdxGotoExitDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkGotoStatement);
  Assert.IsTrue(Pos('goto', Meta.BadExample) > 0, Meta.BadExample);
  // Der Katalog deutet den Code mit '...' an - als Anweisung eingesetzt.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    StringReplace(CatalogText(Meta.BadExample), '...', 'Work;', [rfReplaceAll]),
    'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(StringReplace(Src, 'goto MyExit', 'Exit', []), FixAll(Src));
end;

procedure TTestRdxGotoExitDetector.Detector_LabelNotLast_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Wrap(['  if A then goto Fin;', 'Fin:', '  Cleanup;']), S);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_GOTO_NOT_LAST, ['Fin']), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxGotoExitFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxGotoExitDetector);
  {$ENDIF}

end.
