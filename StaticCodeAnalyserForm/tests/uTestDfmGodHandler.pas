unit uTestDfmGodHandler;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmGodHandler = class
  public
    [Setup]    procedure SetUp;
    [TearDown] procedure TearDown;

    [Test] procedure Test_FiveBindings_Detected;
    [Test] procedure Test_FourBindings_NoFinding;
    [Test] procedure Test_ManyBindings_OneFindingPerHandler;
    [Test] procedure Test_DifferentHandlers_NoFinding;
    [Test] procedure Test_CaseInsensitiveCounting;
    [Test] procedure Test_CustomThreshold_RespectedFromConfig;
    [Test] procedure Test_Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uDfmParser, uComponentGraph,
  uAstNode, uFormBinder,
  uDfmGodHandler;

function RunOn(const DfmSrc: string): TObjectList<TLeakFinding>;
var
  Parser  : TDfmParser;
  Graph   : TComponentGraph;
  Binding : TFormBinding;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(DfmSrc);
  finally Parser.Free; end;
  Binding := TFormBinder.Bind(Graph, nil);
  try TDfmGodHandlerDetector.Analyze(Binding, 'test.dfm', Result);
  finally
    Binding.Free;
    Graph.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

procedure TTestDfmGodHandler.SetUp;
begin
  DetectorMaxGodHandlerEvents := 5;     // Phase-1-Default
end;

procedure TTestDfmGodHandler.TearDown;
begin
  DetectorMaxGodHandlerEvents := 5;
end;

procedure TTestDfmGodHandler.Test_FiveBindings_Detected;
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  '  object b5: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_FourBindings_NoFinding;
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(0, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_ManyBindings_OneFindingPerHandler;
// 7 Bindings auf MainClick - genau ein Befund, nicht sieben.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  '  object b5: TButton OnClick = MainClick end'#13#10 +
  '  object b6: TButton OnClick = MainClick end'#13#10 +
  '  object b7: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_DifferentHandlers_NoFinding;
// 5 Komponenten, jeder eigener Handler - kein God.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = Click1 end'#13#10 +
  '  object b2: TButton OnClick = Click2 end'#13#10 +
  '  object b3: TButton OnClick = Click3 end'#13#10 +
  '  object b4: TButton OnClick = Click4 end'#13#10 +
  '  object b5: TButton OnClick = Click5 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(0, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_CaseInsensitiveCounting;
// Bindungen mit unterschiedlicher Schreibweise zaehlen als gleicher
// Handler (Delphi-Identifier sind nicht case-sensitiv).
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = mainclick end'#13#10 +
  '  object b3: TButton OnClick = MAINCLICK end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  '  object b5: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_CustomThreshold_RespectedFromConfig;
// Schwelle 3 -> 3 Bindings reichen.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DetectorMaxGodHandlerEvents := 3;
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  '  object b5: TButton OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmGodHandler, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmGodHandler);

end.
