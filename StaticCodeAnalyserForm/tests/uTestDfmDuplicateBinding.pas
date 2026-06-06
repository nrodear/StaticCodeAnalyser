unit uTestDfmDuplicateBinding;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDuplicateBinding = class
  public
    // --- Treffer ---
    [Test] procedure Test_TwoEditsSameField_BothReported;
    [Test] procedure Test_ThreeEditsSameField_AllThreeReported;
    [Test] procedure Test_CaseInsensitiveBindingMatch;
    [Test] procedure Test_NestedComponents_StillDetected;

    // --- Mehrere Gruppen ---
    [Test] procedure Test_TwoIndependentGroups_AllReported;

    // --- Nicht-Treffer ---
    [Test] procedure Test_DifferentFields_NoFinding;
    [Test] procedure Test_DifferentDataSources_NoFinding;
    [Test] procedure Test_OnlyOneBinding_NoFinding;
    [Test] procedure Test_MissingDataSource_NoFinding;
    [Test] procedure Test_MissingDataField_NoFinding;
    [Test] procedure Test_EmptyDataField_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_SeverityIsWarning;
    [Test] procedure Test_Finding_KindIsDuplicateBinding;
    [Test] procedure Test_Finding_MissingVarContainsDataSourceAndField;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmDuplicateBinding;

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
      TDfmDuplicateBindingDetector.Analyze(Graph, 'test.dfm', Result);
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

{ --- Treffer --- }

procedure TTestDfmDuplicateBinding.Test_TwoEditsSameField_BothReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object dsOrder: TDataSource'#13#10 +
    '  end'#13#10 +
    '  object ed1: TDBEdit'#13#10 +
    '    DataSource = dsOrder'#13#10 +
    '    DataField = ''Total'''#13#10 +
    '  end'#13#10 +
    '  object ed2: TDBEdit'#13#10 +
    '    DataSource = dsOrder'#13#10 +
    '    DataField = ''Total'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_ThreeEditsSameField_AllThreeReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object ed1: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  object ed2: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  object ed3: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_CaseInsensitiveBindingMatch;
// 'TOTAL' vs 'total' - sollten als gleiches Field gelten (Delphi-Felder
// sind nicht case-sensitiv).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object ed1: TDBEdit DataSource = ds DataField = ''TOTAL'' end'#13#10 +
    '  object ed2: TDBEdit DataSource = ds DataField = ''total'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_NestedComponents_StillDetected;
// Geschwister-Komponenten in unterschiedlichen Panels duerfen das nicht
// verschleiern - der EnumerateAll-Walk flacht ab.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object p1: TPanel'#13#10 +
    '    object ed1: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  end'#13#10 +
    '  object p2: TPanel'#13#10 +
    '    object ed2: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_TwoIndependentGroups_AllReported;
// Zwei Field-Konflikte unabhaengig voneinander -> 4 Befunde (je 2).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = ''A'' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds DataField = ''A'' end'#13#10 +
    '  object e3: TDBEdit DataSource = ds DataField = ''B'' end'#13#10 +
    '  object e4: TDBEdit DataSource = ds DataField = ''B'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(4, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmDuplicateBinding.Test_DifferentFields_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = ''A'' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds DataField = ''B'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_DifferentDataSources_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds1 DataField = ''X'' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds2 DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_OnlyOneBinding_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_MissingDataSource_NoFinding;
// Komponente hat DataField aber keine DataSource - wird nicht beachtet.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataField = ''X'' end'#13#10 +
    '  object e2: TDBEdit DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_MissingDataField_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds end'#13#10 +
    '  object e2: TDBEdit DataSource = ds end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_EmptyDataField_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = '''' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds DataField = '''' end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDuplicateBinding));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmDuplicateBinding.Test_Finding_SeverityIsWarning;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual(lsWarning, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_Finding_KindIsDuplicateBinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    '  object e2: TDBEdit DataSource = ds DataField = ''X'' end'#13#10 +
    'end');
  try
    Assert.AreEqual(fkDfmDuplicateBinding, F[0].Kind);
  finally F.Free; end;
end;

procedure TTestDfmDuplicateBinding.Test_Finding_MissingVarContainsDataSourceAndField;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object e1: TDBEdit DataSource = dsOrder DataField = ''Total'' end'#13#10 +
    '  object e2: TDBEdit DataSource = dsOrder DataField = ''Total'' end'#13#10 +
    'end');
  try
    Assert.Contains(F[0].MissingVar, 'dsOrder');
    Assert.Contains(F[0].MissingVar, 'Total');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDuplicateBinding);

end.
