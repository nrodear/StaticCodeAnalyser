unit uTestDfmCircularDataSource;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmCircularDataSource = class
  public
    // --- Treffer ---
    [Test] procedure Test_DirectCycle_DataSetToMasterSource_Detected;
    [Test] procedure Test_SelfLoop_Detected;
    [Test] procedure Test_TransitiveCycle_FourNodes_Detected;
    [Test] procedure Test_DirectCycle_BothPartiesReported;

    // --- Nicht-Treffer ---
    [Test] procedure Test_LinearChain_NoFinding;
    [Test] procedure Test_MasterDetailWithoutBackref_NoFinding;
    [Test] procedure Test_DanglingDataSet_NoFinding;
    [Test] procedure Test_EmptyDfm_NoFinding;
    [Test] procedure Test_NonIdentValue_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_SeverityIsError;
    [Test] procedure Test_Finding_KindIsCircularDataSource;
    [Test] procedure Test_Finding_MissingVarShowsCyclePath;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmCircularDataSource;

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
      TDfmCircularDataSourceDetector.Analyze(Graph, 'test.dfm', Result);
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

procedure TTestDfmCircularDataSource.Test_DirectCycle_DataSetToMasterSource_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object ds: TDataSource'#13#10 +
  '    DataSet = q'#13#10 +
  '  end'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    MasterSource = ds'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    // ds <-> q -> beide gemeldet, weil beide am Zyklus beteiligt
    Assert.AreEqual<Integer>(2, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_SelfLoop_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object ds: TDataSource'#13#10 +
  '    DataSet = ds'#13#10 +                  // self loop
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_TransitiveCycle_FourNodes_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object dsA: TDataSource DataSet = qA end'#13#10 +
  '  object qA: TADOQuery MasterSource = dsB end'#13#10 +
  '  object dsB: TDataSource DataSet = qB end'#13#10 +
  '  object qB: TADOQuery MasterSource = dsA end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(4, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_DirectCycle_BothPartiesReported;
// Sicherstellen, dass der Befund die beiden beteiligten Komponenten
// nennt, nicht nur einen Knoten.
const DFM =
  'object Form: TForm'#13#10 +
  '  object dsX: TDataSource DataSet = qX end'#13#10 +
  '  object qX: TADOQuery MasterSource = dsX end'#13#10 +
  'end';
var
  F        : TObjectList<TLeakFinding>;
  HasDsX   : Boolean;
  HasQX    : Boolean;
  Fnd      : TLeakFinding;
begin
  F := RunOn(DFM);
  try
    HasDsX := False; HasQX := False;
    for Fnd in F do
      if Fnd.Kind = fkDfmCircularDataSource then
      begin
        if Pos('dsX', Fnd.MissingVar) > 0 then HasDsX := True;
        if Pos('qX',  Fnd.MissingVar) > 0 then HasQX  := True;
      end;
    Assert.IsTrue(HasDsX, 'dsX im Befund-Set erwartet');
    Assert.IsTrue(HasQX,  'qX im Befund-Set erwartet');
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmCircularDataSource.Test_LinearChain_NoFinding;
// Master-Detail-Kette ohne Rueckverweis: legitimes Setup.
const DFM =
  'object Form: TForm'#13#10 +
  '  object dsMaster: TDataSource DataSet = qMaster end'#13#10 +
  '  object qMaster: TADOQuery end'#13#10 +
  '  object dsDetail: TDataSource DataSet = qDetail end'#13#10 +
  '  object qDetail: TADOQuery MasterSource = dsMaster end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_MasterDetailWithoutBackref_NoFinding;
// Master-Detail ist OK, solange MasterSource auf eine ANDERE DataSource zeigt.
const DFM =
  'object Form: TForm'#13#10 +
  '  object dsHead: TDataSource DataSet = qHead end'#13#10 +
  '  object qHead: TADOQuery end'#13#10 +
  '  object qLines: TADOQuery MasterSource = dsHead end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_DanglingDataSet_NoFinding;
// DataSource zeigt auf eine Komponente, die im DFM nicht existiert.
// Eigener Befund waere SchemaMismatch o.ae., nicht CircularDataSource.
const DFM =
  'object Form: TForm'#13#10 +
  '  object ds: TDataSource DataSet = doesNotExist end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_EmptyDfm_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object Form: TForm end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_NonIdentValue_NoFinding;
// Wenn DataSet-Property kein Ident ist (z.B. String, leer), darf der
// Detektor das nicht als Edge interpretieren.
const DFM =
  'object Form: TForm'#13#10 +
  '  object ds: TDataSource'#13#10 +
  '    DataSet = '''''#13#10 +                  // leerer String
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmCircularDataSource.Test_Finding_SeverityIsError;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object ds: TDataSource DataSet = q end'#13#10 +
    '  object q: TADOQuery MasterSource = ds end'#13#10 +
    'end');
  try
    Assert.AreEqual(lsError, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_Finding_KindIsCircularDataSource;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object ds: TDataSource DataSet = q end'#13#10 +
    '  object q: TADOQuery MasterSource = ds end'#13#10 +
    'end');
  try
    Assert.AreEqual(fkDfmCircularDataSource, F[0].Kind);
  finally F.Free; end;
end;

procedure TTestDfmCircularDataSource.Test_Finding_MissingVarShowsCyclePath;
// Befund-Text sollte den Zyklus-Pfad enthalten, damit User die Kette
// im Editor verfolgen kann.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object ds: TDataSource DataSet = q end'#13#10 +
    '  object q: TADOQuery MasterSource = ds end'#13#10 +
    'end');
  try
    Assert.Contains(F[0].MissingVar, 'ds');
    Assert.Contains(F[0].MissingVar, 'q');
    Assert.Contains(F[0].MissingVar, '->');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmCircularDataSource);

end.
