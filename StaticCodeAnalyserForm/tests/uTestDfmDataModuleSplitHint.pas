unit uTestDfmDataModuleSplitHint;

// Tests fuer den TDfmDataModuleSplitHintDetector (Aggregat-Hint).
// Wird nach TDfmDbInUiFormDetector aufgerufen und zaehlt dessen Findings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDataModuleSplitHint = class
  public
    [Setup]    procedure SetUp;
    [TearDown] procedure TearDown;

    // --- Positive ---
    [Test] procedure Test_ThreeDbComponentsOnForm_AggregateHintReported;
    [Test] procedure Test_FiveDbComponentsOnForm_HintListsThemAll;
    [Test] procedure Test_TenComponents_HintTruncatesAtFive;

    // --- Negative ---
    [Test] procedure Test_TwoDbComponentsBelowThreshold_NoAggregateHint;
    [Test] procedure Test_DataModuleRoot_NoAggregateHint;
    [Test] procedure Test_NoDbComponents_NoAggregateHint;

    // --- Konfig ---
    [Test] procedure Test_CustomThreshold_RespectedFromConfig;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Hint_MentionsCountAndExtractName;
    [Test] procedure Test_BothIndividualAndAggregate_Coexist;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmDbInUiForm, uDfmDataModuleSplitHint;

function RunDbInUiThenAggregate(const Src: string;
  const FileName: string = 'uMainForm.dfm'): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmDbInUiFormDetector.Analyze(Graph, FileName, Result);
      TDfmDataModuleSplitHintDetector.Aggregate(FileName, Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

procedure TTestDfmDataModuleSplitHint.SetUp;
begin
  DetectorMaxDbInUiFormHint := 3;
end;

procedure TTestDfmDataModuleSplitHint.TearDown;
begin
  DetectorMaxDbInUiFormHint := 3;
end;

// --- Positive ---

procedure TTestDfmDataModuleSplitHint.Test_ThreeDbComponentsOnForm_AggregateHintReported;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_FiveDbComponentsOnForm_HintListsThemAll;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn1: TADOConnection end'#13#10 +
  '  object Conn2: TFDConnection end'#13#10 +
  '  object Q1: TADOQuery end'#13#10 +
  '  object Q2: TFDQuery end'#13#10 +
  '  object DS1: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'Conn1');
    Assert.Contains(Hit.MissingVar, 'DS1');
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_TenComponents_HintTruncatesAtFive;
const DFM =
  'object F: TForm'#13#10 +
  '  object c1: TADOConnection end'#13#10 +
  '  object c2: TADOConnection end'#13#10 +
  '  object c3: TADOConnection end'#13#10 +
  '  object c4: TADOConnection end'#13#10 +
  '  object c5: TADOConnection end'#13#10 +
  '  object c6: TADOConnection end'#13#10 +
  '  object c7: TADOConnection end'#13#10 +
  '  object c8: TADOConnection end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, '... (+');
    Assert.Contains(Hit.MissingVar, 'more)');
  finally F.Free; end;
end;

// --- Negative ---

procedure TTestDfmDataModuleSplitHint.Test_TwoDbComponentsBelowThreshold_NoAggregateHint;
// 2 < 3 (Default-Threshold) -> kein Aggregat-Hint
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_DataModuleRoot_NoAggregateHint;
// uDfmDbInUiForm emittiert auf DataModule-Roots gar nichts -> Aggregat
// hat keinen Input -> kein Hint.
const DFM =
  'object DM: TDataModule'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_NoDbComponents_NoAggregateHint;
const DFM =
  'object F: TForm'#13#10 +
  '  object b: TButton end'#13#10 +
  '  object lbl: TLabel end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

// --- Konfig ---

procedure TTestDfmDataModuleSplitHint.Test_CustomThreshold_RespectedFromConfig;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DetectorMaxDbInUiFormHint := 2;
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint),
    'Threshold=2 macht 2 Komponenten zum Treffer');
  finally F.Free; end;
end;

// --- Finding-Inhalt ---

procedure TTestDfmDataModuleSplitHint.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkDfmDataModuleSplitHint, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_Hint_MentionsCountAndExtractName;
// Filename 'uMainForm.dfm' -> Vorschlag 'TMainFormDataModule'.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM, 'uMainForm.dfm');
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, '3 DB');
    Assert.Contains(Hit.MissingVar, 'TMainFormDataModule');
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_BothIndividualAndAggregate_Coexist;
// Aggregat ersetzt die Einzelmeldungen NICHT - beides bleibt im Grid.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmDbInUiForm),
      'Drei Einzel-DbInUiForm-Findings bleiben');
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint),
      'Plus ein Aggregat-Hint');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDataModuleSplitHint);

end.
