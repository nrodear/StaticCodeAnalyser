unit uTestDfmRequiredField;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmRequiredField = class
  public
    // --- Unbound ---
    [Test] procedure Test_RequiredField_NoControl_Detected;
    [Test] procedure Test_RequiredField_BoundControl_NoFinding;
    [Test] procedure Test_RequiredField_NoDataSource_Detected;
    [Test] procedure Test_NotRequired_NoFinding;
    [Test] procedure Test_FieldNameLookup_NotComponentName;
    [Test] procedure Test_CaseInsensitiveBinding_NoFinding;

    // --- NotVisible ---
    [Test] procedure Test_RequiredField_OnlyInvisibleControl_Detected;
    [Test] procedure Test_RequiredField_OneVisibleOneHidden_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Unbound_KindAndSeverity;
    [Test] procedure Test_NotVisible_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmRequiredField;

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
      TDfmRequiredFieldDetector.Analyze(Graph, 'test.dfm', Result);
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

{ --- Unbound --- }

procedure TTestDfmRequiredField.Test_RequiredField_NoControl_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField'#13#10 +
  '      FieldName = ''Total'''#13#10 +
  '      Required = True'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmRequiredFieldUnbound));
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_RequiredField_BoundControl_NoFinding;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField'#13#10 +
  '      FieldName = ''Total'''#13#10 +
  '      Required = True'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object edTotal: TDBEdit'#13#10 +
  '    DataSource = ds'#13#10 +
  '    DataField = ''Total'''#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldUnbound));
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_RequiredField_NoDataSource_Detected;
// DataSet ohne zugehoerige DataSource -> Field ist unbindbar.
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField'#13#10 +
  '      FieldName = ''Total'''#13#10 +
  '      Required = True'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmRequiredFieldUnbound));
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_NotRequired_NoFinding;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField'#13#10 +
  '      FieldName = ''Total'''#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldUnbound));
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldNotVisible));
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_FieldNameLookup_NotComponentName;
// Komponenten-Name 'qTotal' aber FieldName-Property = 'OrderTotal'.
// Bindung muss gegen FieldName matchen, nicht Komponenten-Name.
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField'#13#10 +
  '      FieldName = ''OrderTotal'''#13#10 +
  '      Required = True'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object edTotal: TDBEdit'#13#10 +
  '    DataSource = ds'#13#10 +
  '    DataField = ''OrderTotal'''#13#10 +     // matcht FieldName, nicht Komponenten-Namen
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldUnbound));
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_CaseInsensitiveBinding_NoFinding;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField FieldName = ''TOTAL'' Required = True end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object e: TDBEdit DataSource = ds DataField = ''total'' end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldUnbound));
  finally F.Free; end;
end;

{ --- NotVisible --- }

procedure TTestDfmRequiredField.Test_RequiredField_OnlyInvisibleControl_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField FieldName = ''Total'' Required = True end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object e: TDBEdit'#13#10 +
  '    DataSource = ds'#13#10 +
  '    DataField = ''Total'''#13#10 +
  '    Visible = False'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmRequiredFieldNotVisible));
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldUnbound),
      'darf nicht zusaetzlich als Unbound melden');
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_RequiredField_OneVisibleOneHidden_NoFinding;
// Wenn mind. eine bindende Komponente sichtbar ist - kein Befund.
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qTotal: TFloatField FieldName = ''Total'' Required = True end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object eHidden: TDBEdit DataSource = ds DataField = ''Total'' Visible = False end'#13#10 +
  '  object eShown:  TDBEdit DataSource = ds DataField = ''Total'' end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmRequiredFieldNotVisible));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmRequiredField.Test_Unbound_KindAndSeverity;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qT: TFloatField FieldName = ''X'' Required = True end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmRequiredFieldUnbound, F[0].Kind);
    Assert.AreEqual(lsWarning, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmRequiredField.Test_NotVisible_KindAndSeverity;
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qT: TFloatField FieldName = ''X'' Required = True end'#13#10 +
  '  end'#13#10 +
  '  object ds: TDataSource DataSet = q end'#13#10 +
  '  object e: TDBEdit DataSource = ds DataField = ''X'' Visible = False end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmRequiredFieldNotVisible, F[0].Kind);
    Assert.AreEqual(lsWarning, F[0].Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmRequiredField);

end.
