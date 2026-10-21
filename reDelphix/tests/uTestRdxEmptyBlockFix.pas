unit uTestRdxEmptyBlockFix;

// Editorhilfe SCA077 EmptyBlock (uRdxEmptyBlockFix): die Planer auf Text
// (TTestRdxEmptyBlockFix, auch im FPC-Pruefstand lesbar) und der ECHTE
// Detektor (uEmptyBlock) mit dem Adapter PlanEmptyBlock (nur Delphi,
// TTestRdxEmptyBlockDetector). Der Fund zeigt auf die Zeile des BEGIN; die
// Fixtures stehen in einer Routine ('procedure Foo;' auf Zeile 4, begin auf
// Zeile 5, der Rumpf ab Zeile 6).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxEmptyBlockFix = class
  public
    [Test] procedure Basic_WithToCall;
    [Test] procedure LastStatementWithoutSemicolon;
    [Test] procedure BeginEndOnOwnLines;
    [Test] procedure Chain_AndStringsInArguments;
    [Test] procedure UnderThenAndElse;
    [Test] procedure NoCall_NoHelp;
    [Test] procedure SeveralObjects_NoHelp;
    [Test] procedure PossibleCast_NoHelp;
    [Test] procedure Comment_NoHelp;
    [Test] procedure NotEmpty_NoHelp;
    [Test] procedure OtherEmptyBlocks_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure SeveralBeginsOnLine_NoHelp;
    [Test] procedure HeaderOverSeveralLines_NoHelp;
    [Test] procedure UnreadableExpression_NoHelp;
    [Test] procedure Tail_NoHelp;
    [Test] procedure CommentedOrStringBlock_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxEmptyBlockDetector = class
  public
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_SeparateLines_RoundTrip;
    [Test] procedure Detector_TwoBlocks_OneAfterTheOther;
    [Test] procedure Detector_CatalogExample_NoHelp;
    [Test] procedure Detector_PlainBeginEnd_NoHelp;
    [Test] procedure Adapter_OutcomeAndStaleFinding;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uEmptyBlock,
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  uRdxRecipeRunner,      // TRdxFixOutcome
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxEmptyBlockFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

const
  FIRST_LINE = 6;   // erste Rumpfzeile in Wrap

// ---- Helfer ----

// Eine Unit mit EINER Routine; begin auf Zeile 5, der Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
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
      Ok := TRdxEmptyBlockFix.WithToCall(Map, ALine, '', E, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Wie Plan, aber die Hilfe muss gelten (sonst scheitert der Test mit dem
// Grund).
function Applied(const ASource: string; ALine: Integer): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, R);
  Assert.IsTrue(Result <> '', R);
end;

// Keine Hilfe, mit genau diesem Grund.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// Die Gruende der verschobenen Stelle, in der Sprache der Tests.
function NoBeginReason: string;
begin
  Result := MsgMovedSuffix(_(R_EBL_NO_BEGIN));
end;

function NotEmptyReason: string;
begin
  Result := MsgMovedSuffix(_(R_EBL_NOT_EMPTY));
end;

// ---- Umformung ----

procedure TTestRdxEmptyBlockFix.Basic_WithToCall;
begin
  Assert.AreEqual(Wrap(['  Items.Add(T);']),
    Applied(Wrap(['  with Items.Add(T) do begin end;']), FIRST_LINE));
  // Die Nachbarn bleiben.
  Assert.AreEqual(Wrap(['  A := 1;', '  Items.Add(T);', '  B := 2;']),
    Applied(Wrap(['  A := 1;', '  with Items.Add(T) do begin end;',
      '  B := 2;']), FIRST_LINE + 1));
  // Gross/klein und Leerraum im Block stehen nicht im Weg.
  Assert.AreEqual(Wrap(['  Items.Add(T);']),
    Applied(Wrap(['  WITH Items.Add(T) DO BEGIN   END;']), FIRST_LINE));
end;

procedure TTestRdxEmptyBlockFix.LastStatementWithoutSemicolon;
begin
  // Das end der Routine folgt: ohne ';' bleibt ohne ';'.
  Assert.AreEqual(Wrap(['  Items.Add(T)']),
    Applied(Wrap(['  with Items.Add(T) do begin end']), FIRST_LINE));
end;

procedure TTestRdxEmptyBlockFix.BeginEndOnOwnLines;
begin
  // Der Fund steht auf der Zeile des begin (7).
  Assert.AreEqual(Wrap(['  Items.Add(T);']),
    Applied(Wrap(['  with Items.Add(T) do', '  begin', '  end;']),
      FIRST_LINE + 1));
  Assert.AreEqual(Wrap(['  Items.Add(T);']),
    Applied(Wrap(['  with Items.Add(T) do', '  begin end;']),
      FIRST_LINE + 1));
  Assert.AreEqual(Wrap(['  Items.Add(T);']),
    Applied(Wrap(['  with Items.Add(T) do begin', '  end;']), FIRST_LINE));
end;

procedure TTestRdxEmptyBlockFix.Chain_AndStringsInArguments;
begin
  Assert.AreEqual(Wrap(['  A.B(1).C(2, ''x'');']),
    Applied(Wrap(['  with A.B(1).C(2, ''x'') do begin end;']), FIRST_LINE));
  // Eine Klammer im String ist keine Klammer.
  Assert.AreEqual(Wrap(['  Q.Fmt(''a(b'', [1]);']),
    Applied(Wrap(['  with Q.Fmt(''a(b'', [1]) do begin end;']), FIRST_LINE));
  // Klassenaufruf: der Konstruktor laeuft wie vorher.
  Assert.AreEqual(Wrap(['  TFoo.Create(Self);']),
    Applied(Wrap(['  with TFoo.Create(Self) do begin end;']), FIRST_LINE));
  // Aufruf ohne Argumente in Klammern.
  Assert.AreEqual(Wrap(['  Items.Clear();']),
    Applied(Wrap(['  with Items.Clear() do begin end;']), FIRST_LINE));
end;

procedure TTestRdxEmptyBlockFix.UnderThenAndElse;
begin
  Assert.AreEqual(Wrap(['  if X then Items.Add(T);']),
    Applied(Wrap(['  if X then with Items.Add(T) do begin end;']),
      FIRST_LINE));
  Assert.AreEqual(Wrap(['  if X then Y else Items.Add(T);']),
    Applied(Wrap(['  if X then Y else with Items.Add(T) do begin end;']),
      FIRST_LINE));
  Assert.AreEqual(Wrap(['  if X then Items.Add(T) else Y;']),
    Applied(Wrap(['  if X then with Items.Add(T) do begin end else Y;']),
      FIRST_LINE));
end;

// ---- Sperren ----

procedure TTestRdxEmptyBlockFix.NoCall_NoHelp;
begin
  // Als Anweisung bliebe ein Bezeichner - ungueltig.
  AssertRefused(Wrap(['  with Foo do begin end;']), FIRST_LINE,
    _(R_EBL_NO_CALL));
  AssertRefused(Wrap(['  with A.B do begin end;']), FIRST_LINE,
    _(R_EBL_NO_CALL));
  AssertRefused(Wrap(['  with A.B(1).C do begin end;']), FIRST_LINE,
    _(R_EBL_NO_CALL));
end;

procedure TTestRdxEmptyBlockFix.SeveralObjects_NoHelp;
begin
  AssertRefused(Wrap(['  with A, B.C(1) do begin end;']), FIRST_LINE,
    _(R_EBL_MULTI));
  AssertRefused(Wrap(['  with A.B(1), C do begin end;']), FIRST_LINE,
    _(R_EBL_MULTI));
end;

procedure TTestRdxEmptyBlockFix.PossibleCast_NoHelp;
begin
  // 'TButton(Sender);' ist keine Anweisung.
  AssertRefused(Wrap(['  with TButton(Sender) do begin end;']), FIRST_LINE,
    _(R_EBL_CAST));
  AssertRefused(Wrap(['  with Foo(1) do begin end;']), FIRST_LINE,
    _(R_EBL_CAST));
  AssertRefused(Wrap(['  with Vcl.TButton(Sender) do begin end;']), FIRST_LINE,
    _(R_EBL_CAST));
  // Ein Cast vorn in der Kette ist ein Aufruf hinten: geht.
  Assert.AreEqual(Wrap(['  TFoo(X).Bar(1);']),
    Applied(Wrap(['  with TFoo(X).Bar(1) do begin end;']), FIRST_LINE));
end;

procedure TTestRdxEmptyBlockFix.Comment_NoHelp;
begin
  AssertRefused(Wrap(['  with Items.Add(T) do begin { spaeter } end;']),
    FIRST_LINE, _(R_EBL_COMMENT));
  AssertRefused(Wrap(['  with Items.Add(T) do begin // TODO', '  end;']),
    FIRST_LINE, _(R_EBL_COMMENT));
  AssertRefused(Wrap(['  with Items.Add(T) { c } do begin end;']),
    FIRST_LINE, _(R_EBL_COMMENT));
  AssertRefused(Wrap(['  with Items.Add(T) do', '  // c', '  begin', '  end;']),
    FIRST_LINE + 2, _(R_EBL_COMMENT));
  AssertRefused(Wrap(['  with Items.Add(T) do begin {$IFDEF X} {$ENDIF} end;']),
    FIRST_LINE, _(R_EBL_COMMENT));
end;

procedure TTestRdxEmptyBlockFix.NotEmpty_NoHelp;
begin
  AssertRefused(Wrap(['  with Items.Add(T) do begin Foo; end;']), FIRST_LINE,
    NotEmptyReason);
  AssertRefused(Wrap(['  with Items.Add(T) do begin', '    begin end;',
    '  end;']), FIRST_LINE, NotEmptyReason);
end;

procedure TTestRdxEmptyBlockFix.OtherEmptyBlocks_NoHelp;
begin
  // Diese leeren Bloecke meldet SCA077 auch - die Hilfe fasst sie nicht an.
  AssertRefused(Wrap(['  if X then begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  if X then Y else begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  begin end;']), FIRST_LINE, _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  while C do begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  for I := 0 to 3 do begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  with A.B(1) do while C do begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  with A.B(1) do if C then begin end;']), FIRST_LINE,
    _(R_EBL_NO_WITH));
  AssertRefused(Wrap(['  try', '    begin end;', '  except', '  end;']),
    FIRST_LINE + 1, _(R_EBL_NO_WITH));
end;

procedure TTestRdxEmptyBlockFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  A := 1;', '  with Items.Add(T) do begin end;']);
  AssertRefused(Src, FIRST_LINE, NoBeginReason);
  AssertRefused(Src, 1, NoBeginReason);
  AssertRefused(Src, 99, NoBeginReason);
end;

procedure TTestRdxEmptyBlockFix.SeveralBeginsOnLine_NoHelp;
begin
  AssertRefused(Wrap(['  with A.B(1) do begin end; with C.D(2) do begin end;']),
    FIRST_LINE, _(R_EBL_MANY));
end;

procedure TTestRdxEmptyBlockFix.HeaderOverSeveralLines_NoHelp;
begin
  AssertRefused(Wrap(['  with', '    A.B(1) do begin end;']), FIRST_LINE + 1,
    _(R_EBL_MULTILINE));
  AssertRefused(Wrap(['  with A.B(1)', '    do begin end;']), FIRST_LINE + 1,
    _(R_EBL_MULTILINE));
  // Argumente ueber mehrere Zeilen: der Kopf liegt ueber zwei Zeilen.
  AssertRefused(Wrap(['  with A.B(1,', '    2) do begin end;']), FIRST_LINE + 1,
    _(R_EBL_MULTILINE));
end;

procedure TTestRdxEmptyBlockFix.UnreadableExpression_NoHelp;
begin
  AssertRefused(Wrap(['  with L[0].Add(1) do begin end;']), FIRST_LINE,
    _(R_EBL_SHAPE));
  AssertRefused(Wrap(['  with (A as B).C(1) do begin end;']), FIRST_LINE,
    _(R_EBL_SHAPE));
  AssertRefused(Wrap(['  with Sender as TFoo do begin end;']), FIRST_LINE,
    _(R_EBL_SHAPE));
  AssertRefused(Wrap(['  with inherited Foo(1) do begin end;']), FIRST_LINE,
    _(R_EBL_SHAPE));
end;

procedure TTestRdxEmptyBlockFix.Tail_NoHelp;
begin
  AssertRefused(Wrap(['  with Items.Add(T) do begin end Bar;']), FIRST_LINE,
    _(R_EBL_TAIL));
end;

procedure TTestRdxEmptyBlockFix.CommentedOrStringBlock_NoHelp;
begin
  // Kommentar und String sind kein Code: dort steht kein begin.
  AssertRefused(Wrap(['  // with Items.Add(T) do begin end;']), FIRST_LINE,
    NoBeginReason);
  AssertRefused(Wrap(['  S := ''with Items.Add(T) do begin end;'';']),
    FIRST_LINE, NoBeginReason);
  AssertRefused(Wrap(['  { with Items.Add(T) do begin end; }']), FIRST_LINE,
    NoBeginReason);
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TEmptyBlockDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s077_', ASource, fkEmptyBlock, RunDetector);
end;

// Die Hilfe des Adapters fuer den Fund ASeen, so wie die Tabelle sie ruft.
function OutcomeFor(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, fkEmptyBlock);
  try
    SL.Text := ASource;
    Result := PlanEmptyBlock(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer den ERSTEN Fund des Detektors, angewendet wie der Editor.
function FixFirst(const ASource: string): string;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := OutcomeFor(ASource, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Result := Apply(ASource, O.Edits);
end;

procedure TTestRdxEmptyBlockDetector.Detector_RoundTrip;
var
  Src, After : string;
  Seen       : TArray<TSeen>;
begin
  Src := Wrap(['  with Items.Add(T) do begin end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet genau einen Fund');
  Assert.AreEqual<Integer>(FIRST_LINE, Seen[0].Line, 'auf der Zeile des begin');
  After := FixFirst(Src);
  Assert.AreEqual(Wrap(['  Items.Add(T);']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxEmptyBlockDetector.Detector_SeparateLines_RoundTrip;
var
  Src, After : string;
  Seen       : TArray<TSeen>;
begin
  Src := Wrap(['  with Items.Add(T) do', '  begin', '  end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet genau einen Fund');
  Assert.AreEqual<Integer>(FIRST_LINE + 1, Seen[0].Line, 'auf der Zeile des begin');
  After := FixFirst(Src);
  Assert.AreEqual(Wrap(['  Items.Add(T);']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxEmptyBlockDetector.Detector_TwoBlocks_OneAfterTheOther;
var
  Src, Step : string;
begin
  Src := Wrap(['  with A.Add(1) do begin end;', '  with B.Add(2) do begin end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)));
  Step := FixFirst(Src);
  Assert.AreEqual(Wrap(['  A.Add(1);', '  with B.Add(2) do begin end;']), Step);
  Assert.AreEqual<Integer>(1, Length(Detect(Step)));
  Step := FixFirst(Step);
  Assert.AreEqual(Wrap(['  A.Add(1);', '  B.Add(2);']), Step);
  Assert.AreEqual<Integer>(0, Length(Detect(Step)));
end;

procedure TTestRdxEmptyBlockDetector.Detector_CatalogExample_NoHelp;
var
  Meta : TRuleMeta;
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Das Katalog-Beispiel 'if Active then begin end;' meldet der Detektor, die
  // Hilfe fasst es nicht an.
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyBlock);
  Assert.IsTrue(Pos('begin end', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + CatalogText(Meta.BadExample) + #13#10
    + Join(['end;', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet das Beispiel');
  O := OutcomeFor(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe fuer das Katalog-Beispiel');
  Assert.AreEqual(_(R_EBL_NO_WITH), O.Reason);
end;

procedure TTestRdxEmptyBlockDetector.Detector_PlainBeginEnd_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := Wrap(['  begin', '  end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet den Block');
  O := OutcomeFor(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_EBL_NO_WITH), O.Reason);
end;

procedure TTestRdxEmptyBlockDetector.Adapter_OutcomeAndStaleFinding;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Old  : TSeen;
begin
  Src := Wrap(['  with Items.Add(T) do begin end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := OutcomeFor(Src, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, O.Variant, 'Hauptweg');
  Assert.IsFalse(O.ChangesBehavior, 'gleiche Bedeutung');
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual<Integer>(FIRST_LINE, O.Edits[0].Span.StartLine);
  // Der Fund zeigt auf eine Zeile ohne begin.
  Old := Seen[0];
  Old.Line := 4;
  O := OutcomeFor(Src, Old);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(NoBeginReason, O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxEmptyBlockFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxEmptyBlockDetector);
  {$ENDIF}

end.
