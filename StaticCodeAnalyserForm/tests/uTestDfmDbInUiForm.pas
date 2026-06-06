unit uTestDfmDbInUiForm;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDbInUiForm = class
  public
    [Test] procedure Test_AdoConnectionOnForm_Detected;
    [Test] procedure Test_AdoQueryOnForm_Detected;
    [Test] procedure Test_DataSourceOnForm_Detected;
    [Test] procedure Test_AllThreeOnForm_AllReported;

    [Test] procedure Test_DbComponentsOnDataModule_Silent;
    [Test] procedure Test_DbComponentsOnNamedDataModule_Silent;
    [Test] procedure Test_OnlyUiComponents_NoFinding;

    [Test] procedure Test_NestedDbComponent_StillDetected;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsClassAndForm;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmDbInUiForm;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmDbInUiFormDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

procedure TTestDfmDbInUiForm.Test_AdoConnectionOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_AdoQueryOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DataSourceOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object ds: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_AllThreeOnForm_AllReported;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  '  object ds: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DbComponentsOnDataModule_Silent;
// Klassen-Name endet auf 'DataModule' -> Detektor schweigt (das ist
// genau das gewuenschte Pattern).
const DFM =
  'object dm: TDataModule'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DbComponentsOnNamedDataModule_Silent;
// 'TOrderDataModule' endet auch auf 'DataModule' -> Whitelist.
const DFM =
  'object dmOrder: TOrderDataModule'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_OnlyUiComponents_NoFinding;
const DFM =
  'object frmMain: TMainForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object btn: TButton end'#13#10 +
  '    object ed: TEdit end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_NestedDbComponent_StillDetected;
// DB-Komponente versteckt sich unter einem Panel - EnumerateAll laeuft
// rekursiv, wird trotzdem gefunden.
const DFM =
  'object frm: TMainForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object q: TADOQuery end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_Finding_KindAndSeverity;
const DFM =
  'object frm: TMainForm object conn: TADOConnection end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmDbInUiForm, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_Finding_MissingVarMentionsClassAndForm;
const DFM =
  'object frmMain: TMainForm object conn: TADOConnection end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'conn');
    Assert.Contains(F[0].MissingVar, 'TADOConnection');
    Assert.Contains(F[0].MissingVar, 'TMainForm');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDbInUiForm);

end.
