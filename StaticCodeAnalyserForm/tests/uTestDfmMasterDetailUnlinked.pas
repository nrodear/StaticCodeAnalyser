unit uTestDfmMasterDetailUnlinked;

// Tests fuer den TDfmMasterDetailUnlinkedDetector.
// Pattern: MasterSource gesetzt, MasterFields + IndexFieldNames beide leer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmMasterDetailUnlinked = class
  public
    // --- Positive (Treffer) ---
    [Test] procedure Test_MasterSourceWithoutFields_Detected;
    [Test] procedure Test_MasterSourceMasterFieldsEmpty_StillDetected;
    [Test] procedure Test_TwoUnlinkedDataSets_BothReported;

    // --- Negative (Skip / NoFinding) ---
    [Test] procedure Test_MasterSourceWithMasterFields_NoFinding;
    [Test] procedure Test_MasterSourceWithIndexFieldNames_NoFinding;
    [Test] procedure Test_NoMasterSource_NoFinding;
    [Test] procedure Test_EmptyDfm_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsTargetAndSource;
    [Test] procedure Test_NestedInPanel_StillDetected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmMasterDetailUnlinked;

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
      TDfmMasterDetailUnlinkedDetector.Analyze(Graph, 'test.dfm', Result);
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

// --- Positive ---

procedure TTestDfmMasterDetailUnlinked.Test_MasterSourceWithoutFields_Detected;
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_MasterSourceMasterFieldsEmpty_StillDetected;
// MasterFields = '' (leerer String) zaehlt als "nicht gesetzt".
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '    MasterFields = '''''#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_TwoUnlinkedDataSets_BothReported;
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '  end'#13#10 +
  '  object qItems: TFDQuery'#13#10 +
  '    MasterSource = dsOrders'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(2, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

// --- Negative ---

procedure TTestDfmMasterDetailUnlinked.Test_MasterSourceWithMasterFields_NoFinding;
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '    MasterFields = ''CustomerID'''#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_MasterSourceWithIndexFieldNames_NoFinding;
// IndexFieldNames als Alternative zu MasterFields ist auch gueltig.
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '    IndexFieldNames = ''CustomerID'''#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_NoMasterSource_NoFinding;
// Standalone-Query ohne Master-Detail-Setup - kein Befund.
const DFM =
  'object F: TF'#13#10 +
  '  object qStandalone: TFDQuery'#13#10 +
  '    SQL.Strings = (''SELECT * FROM t'')'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_EmptyDfm_NoFinding;
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

// --- Finding-Inhalt ---

procedure TTestDfmMasterDetailUnlinked.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TF'#13#10 +
  '  object q: TFDQuery'#13#10 +
  '    MasterSource = dsMaster'#13#10 +
  '  end'#13#10 +
  'end';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := RunOn(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmMasterDetailUnlinked then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkDfmMasterDetailUnlinked, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_Finding_MissingVarMentionsTargetAndSource;
const DFM =
  'object F: TF'#13#10 +
  '  object qOrders: TFDQuery'#13#10 +
  '    MasterSource = dsCustomers'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'qOrders');
    Assert.Contains(F[0].MissingVar, 'dsCustomers');
    Assert.Contains(LowerCase(F[0].MissingVar), 'cross-join');
  finally F.Free; end;
end;

procedure TTestDfmMasterDetailUnlinked.Test_NestedInPanel_StillDetected;
// Auch tief verschachtelt im Komponenten-Baum funktionieren EnumerateAll.
const DFM =
  'object F: TF'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object qOrders: TFDQuery'#13#10 +
  '      MasterSource = dsCustomers'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmMasterDetailUnlinked));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmMasterDetailUnlinked);

end.
