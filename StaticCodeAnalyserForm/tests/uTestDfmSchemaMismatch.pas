unit uTestDfmSchemaMismatch;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmSchemaMismatch = class
  public
    [Test] procedure Test_ComponentWithoutField_Detected;
    [Test] procedure Test_AllComponentsHaveFields_NoFinding;
    [Test] procedure Test_RootForm_NotConsideredAsMissingField;
    [Test] procedure Test_NestedComponent_StillDetected;
    [Test] procedure Test_CaseInsensitiveFieldMatch_NoFinding;
    [Test] procedure Test_NoFormClassFound_NoFinding;
    [Test] procedure Test_NoPascalAst_NoFinding;
    [Test] procedure Test_MultipleMissing_AllReported;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsComponentAndClass;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder,
  uDfmSchemaMismatch;

function RunOn(const DfmSrc, PasSrc: string): TObjectList<TLeakFinding>;
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  DfmParser := TDfmParser.Create;
  try
    Graph := DfmParser.ParseSource(DfmSrc);
  finally
    DfmParser.Free;
  end;
  UnitNode := nil;
  if PasSrc <> '' then
  begin
    PasParser := TParser2.Create;
    try
      UnitNode := PasParser.ParseSource(PasSrc);
    finally
      PasParser.Free;
    end;
  end;
  Binding := TFormBinder.Bind(Graph, UnitNode);
  try
    TDfmSchemaMismatchDetector.Analyze(Binding, 'test.dfm', Result);
  finally
    Binding.Free;
    UnitNode.Free;
    Graph.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

procedure TTestDfmSchemaMismatch.Test_ComponentWithoutField_Detected;
// DFM hat btnSave, Pascal-Klasse hat KEIN published Field btnSave.
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM =
  'object F: TF'#13#10 +
  '  object btnSave: TButton end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_AllComponentsHaveFields_NoFinding;
const PAS =
  'unit u; interface uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  btnSave: TButton;'#13#10 +
  '  edName: TEdit;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
const DFM =
  'object F: TF'#13#10 +
  '  object btnSave: TButton end'#13#10 +
  '  object edName: TEdit end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_RootForm_NotConsideredAsMissingField;
// Der Root 'F: TF' ist die Form-Klasse selbst, kein Field der Klasse.
// Darf NICHT als Mismatch gemeldet werden.
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_NestedComponent_StillDetected;
const PAS =
  'unit u; interface uses Vcl.Forms, Vcl.ExtCtrls;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  pnl: TPanel;'#13#10 +
  '  // btnInner field is missing'#13#10 +
  'end;'#13#10 +
  'implementation end.';
const DFM =
  'object F: TF'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object btnInner: TButton end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_CaseInsensitiveFieldMatch_NoFinding;
// Pascal: 'btnSave', DFM: 'BTNSAVE'. Delphi ist nicht case-sensitiv -
// gilt als gleicher Name.
const PAS =
  'unit u; interface uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TF = class(TForm) btnSave: TButton; end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF object BTNSAVE: TButton end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_NoFormClassFound_NoFinding;
// Pascal-Unit hat keine zur DFM-Root-Klasse passende Klassen-Decl.
// Detektor muss schweigen - waere sonst false-positive auf jeder unklaren
// .pas/.dfm-Paarung.
const PAS =
  'unit u; interface type TOther = class end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF object btnSave: TButton end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_NoPascalAst_NoFinding;
const DFM = 'object F: TF object btnSave: TButton end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_MultipleMissing_AllReported;
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM =
  'object F: TF'#13#10 +
  '  object a: TButton end'#13#10 +
  '  object b: TEdit end'#13#10 +
  '  object c: TPanel end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmSchemaMismatch));
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_Finding_KindAndSeverity;
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF object btnSave: TButton end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(fkDfmSchemaMismatch, F[0].Kind);
    Assert.AreEqual(lsError,             F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmSchemaMismatch.Test_Finding_MissingVarMentionsComponentAndClass;
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF object btnSave: TButton end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.Contains(F[0].MissingVar, 'btnSave');
    Assert.Contains(F[0].MissingVar, 'TButton');
    Assert.Contains(F[0].MissingVar, 'TF');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmSchemaMismatch);

end.
