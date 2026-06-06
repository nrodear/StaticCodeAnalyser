unit uTestDfmLayerViolation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmLayerViolation = class
  public
    [Test] procedure Test_EditDirectlyOnForm_Detected;
    [Test] procedure Test_DBEditDirectlyOnForm_Detected;
    [Test] procedure Test_EditInPanel_NoFinding;
    [Test] procedure Test_PanelOnForm_NoFinding;
    [Test] procedure Test_DataModuleRoot_Silent;
    [Test] procedure Test_ActionListOnForm_NoFinding;
    [Test] procedure Test_MultipleDirectInputs_AllReported;
    [Test] procedure Test_Finding_KindAndSeverity;

    // --- Mehr Varianten ---
    [Test] procedure Test_GroupBoxAsContainer_EditInside_NoFinding;
    [Test] procedure Test_Finding_MissingVarMentionsComponentAndClass;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uDfmParser, uComponentGraph,
  uDfmLayerViolation;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var Parser: TDfmParser; Graph: TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try TDfmLayerViolationDetector.Analyze(Graph, 'test.dfm', Result);
    finally Graph.Free; end;
  finally Parser.Free; end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

procedure TTestDfmLayerViolation.Test_EditDirectlyOnForm_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_DBEditDirectlyOnForm_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TDBEdit end end');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_EditInPanel_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object pnl: TPanel'#13#10 +
    '    object ed: TEdit end'#13#10 +
    '  end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_PanelOnForm_NoFinding;
// TPanel selbst ist Container, kein Input - keine Layer-Violation.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object pnl: TPanel end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_DataModuleRoot_Silent;
// DataModule darf direkte 'Inputs' tragen (auch wenn TEdit auf DM
// untypisch ist - der Layer-Detektor ist nur fuer Forms gedacht).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object dm: TDataModule object ed: TEdit end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_ActionListOnForm_NoFinding;
// TActionList ist Non-Visual und gehoert legitim auf die Form.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object al: TActionList end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_MultipleDirectInputs_AllReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object ed1: TEdit end'#13#10 +
    '  object ed2: TEdit end'#13#10 +
    '  object cb: TComboBox end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(3, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_Finding_KindAndSeverity;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
  try
    Assert.AreEqual(fkDfmLayerViolation, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_GroupBoxAsContainer_EditInside_NoFinding;
// Containerklassen wie TGroupBox kapseln Inputs - die Form selbst
// traegt also keinen direkten Input mehr.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object gb: TGroupBox'#13#10 +
    '    object ed: TEdit end'#13#10 +
    '  end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_Finding_MissingVarMentionsComponentAndClass;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object edUser: TEdit end end');
  try
    Assert.Contains(F[0].MissingVar, 'edUser');
    Assert.Contains(F[0].MissingVar, 'TEdit');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmLayerViolation);

end.
