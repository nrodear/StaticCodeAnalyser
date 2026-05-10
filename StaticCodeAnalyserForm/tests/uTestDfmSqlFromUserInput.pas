unit uTestDfmSqlFromUserInput;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmSqlFromUserInput = class
  public
    // --- Treffer (Assignment) ---
    [Test] procedure Test_SqlText_FromEdit_Detected;
    [Test] procedure Test_CommandText_FromMemo_Detected;
    [Test] procedure Test_FdQuery_SqlText_FromComboBox_Detected;

    // --- Treffer (Call) ---
    [Test] procedure Test_SqlAdd_FromEdit_Detected;

    // --- Nicht-Treffer ---
    [Test] procedure Test_StaticSql_NoFinding;
    [Test] procedure Test_SqlFromParameter_NoFinding;
    [Test] procedure Test_NoDbQueryField_NoFinding;
    [Test] procedure Test_NoUiInputField_NoFinding;
    [Test] procedure Test_AssignmentToOtherProperty_NoFinding;
    [Test] procedure Test_AssignmentWithoutConcat_NoFinding;

    // --- Robustheit ---
    [Test] procedure Test_NoFormClass_NoFinding;
    [Test] procedure Test_NoPascalAst_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_SeverityIsError;
    [Test] procedure Test_Finding_KindIsSqlFromUserInput;
    [Test] procedure Test_Finding_MissingVarMentionsBothComponents;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder,
  uDfmSqlFromUserInput;

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
    TDfmSqlFromUserInputDetector.Analyze(Binding, 'test.dfm', Result);
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

const
  DFM_BASIC =
    'object F: TF'#13#10 +
    '  object qFind: TADOQuery end'#13#10 +
    '  object edName: TEdit end'#13#10 +
    'end';

{ --- Treffer (Assignment) --- }

procedure TTestDfmSqlFromUserInput.Test_SqlText_FromEdit_Detected;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Text := ''SELECT * FROM users WHERE name='' + edName.Text;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_CommandText_FromMemo_Detected;
const DFM =
  'object F: TF'#13#10 +
  '  object qExec: TADOCommand end'#13#10 +
  '  object memSql: TMemo end'#13#10 +
  'end';
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qExec: TADOCommand; memSql: TMemo; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qExec.CommandText := ''EXEC '' + memSql.Lines.Text;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_FdQuery_SqlText_FromComboBox_Detected;
const DFM =
  'object F: TF'#13#10 +
  '  object qSel: TFDQuery end'#13#10 +
  '  object cbType: TComboBox end'#13#10 +
  'end';
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qSel: TFDQuery; cbType: TComboBox; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qSel.SQL.Text := ''SELECT * FROM t WHERE kind=' + #39#39 + ''' + cbType.Text + ' + #39#39 + ''';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

{ --- Treffer (Call) --- }

procedure TTestDfmSqlFromUserInput.Test_SqlAdd_FromEdit_Detected;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Add(''WHERE name='' + edName.Text);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmSqlFromUserInput.Test_StaticSql_NoFinding;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Text := ''SELECT * FROM users'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_SqlFromParameter_NoFinding;
// Parameterisierter Query - keine UI-Konkatenation.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Text := ''SELECT * FROM users WHERE name = :n'';'#13#10 +
  '  qFind.Parameters.ParamByName(''n'').Value := edName.Text;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_NoDbQueryField_NoFinding;
const DFM = 'object F: TF object edName: TEdit end end';
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  someOther.SQL.Text := ''x'' + edName.Text;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_NoUiInputField_NoFinding;
// SQL aus einer Local-Variable, kein UI-Field beteiligt.
const DFM = 'object F: TF object qFind: TADOQuery end end';
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Text := ''SELECT * FROM t WHERE x='' + s;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_AssignmentToOtherProperty_NoFinding;
// 'qFind.Active := True' - keine SQL-Property, kein Befund.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.Active := True;'#13#10 +
  '  edName.Text := ''x'' + edName.Text;'#13#10 +    // konkat auf UI selbst, kein SQL
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_AssignmentWithoutConcat_NoFinding;
// SQL kommt aus Edit.Text DIREKT (ohne '+') - keine Konkatenation,
// damit kein Befund. Das wird typisch in Test-Fixtures benutzt, oder ist
// ein Pattern wo der ganze SQL als Vorlage im Editor steht.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go;'#13#10 +
  'begin'#13#10 +
  '  qFind.SQL.Text := edName.Text;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    // Diese Heuristik-Wahl ist konservativ: ohne '+' ist es zwar auch
    // riskant, aber haeufig legitim (eingebauter SQL-Editor). Wenn das
    // strenger gesetzt werden soll, ist das ein Tuning-Schritt.
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

{ --- Robustheit --- }

procedure TTestDfmSqlFromUserInput.Test_NoFormClass_NoFinding;
const PAS =
  'unit u; interface type TOther = class end; implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_NoPascalAst_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, '');
  try
    Assert.AreEqual(0, Count(F, fkDfmSqlFromUserInput));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmSqlFromUserInput.Test_Finding_SeverityIsError;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go; begin qFind.SQL.Text := ''x'' + edName.Text; end; end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(lsError, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_Finding_KindIsSqlFromUserInput;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go; begin qFind.SQL.Text := ''x'' + edName.Text; end; end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.AreEqual(fkDfmSqlFromUserInput, F[0].Kind);
  finally F.Free; end;
end;

procedure TTestDfmSqlFromUserInput.Test_Finding_MissingVarMentionsBothComponents;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) qFind: TADOQuery; edName: TEdit; end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.go; begin qFind.SQL.Text := ''x'' + edName.Text; end; end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_BASIC, PAS);
  try
    Assert.Contains(F[0].MissingVar, 'qFind');
    Assert.Contains(F[0].MissingVar, 'edName');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmSqlFromUserInput);

end.
