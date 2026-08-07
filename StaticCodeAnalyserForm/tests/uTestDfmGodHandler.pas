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

    // --- Mehr Varianten ---
    [Test] procedure Test_DifferentEvents_SameHandler_StillCounts;
    [Test] procedure Test_TwoGodHandlers_TwoFindings;
    [Test] procedure Test_ThresholdZero_FallsBackToFive;
    [Test] procedure Test_UniformClassAndEvent_Silent;
    [Test] procedure Test_SameClassDifferentEvents_Reported;
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

var
  GOldGodHandlerMax: Integer;

procedure TTestDfmGodHandler.SetUp;
begin
  // Alt-Wert sichern statt hartkodiertem Default-Restore: driftet der
  // Engine-Default je von 5 weg, wuerde TearDown sonst den falschen Wert
  // in Folge-Fixtures injizieren (Audit_TestQualitaet F3).
  GOldGodHandlerMax := DetectorMaxGodHandlerEvents;
  DetectorMaxGodHandlerEvents := 5;     // Phase-1-Default
end;

procedure TTestDfmGodHandler.TearDown;
begin
  DetectorMaxGodHandlerEvents := GOldGodHandlerMax;
end;

procedure TTestDfmGodHandler.Test_FiveBindings_Detected;
  // Fixture heterogen (TCheckBox-Bindung): das Homogenitaets-Gate
  // (2026-08-09) schweigt bei EINER Klasse + EINEM Event-Typ.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TButton OnClick = MainClick end'#13#10 +
  '  object b4: TButton OnClick = MainClick end'#13#10 +
  '  object b5: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
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
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmGodHandler));
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
  '  object b7: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
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
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmGodHandler));
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
  '  object b5: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_CustomThreshold_RespectedFromConfig;
// Schwelle 3 -> 3 Bindings reichen.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = MainClick end'#13#10 +
  '  object b2: TButton OnClick = MainClick end'#13#10 +
  '  object b3: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DetectorMaxGodHandlerEvents := 3;
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TF'#13#10 +
  '  object c1: TButton OnClick = MainClick end'#13#10 +
  '  object c2: TButton OnClick = MainClick end'#13#10 +
  '  object c3: TButton OnClick = MainClick end'#13#10 +
  '  object c4: TButton OnClick = MainClick end'#13#10 +
  '  object c5: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmGodHandler, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_DifferentEvents_SameHandler_StillCounts;
// Derselbe Handler haengt an OnClick + OnDblClick + OnEnter + OnExit +
// OnKeyDown - 5 verschiedene Events, aber alle auf MainHandler -> God.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton'#13#10 +
  '    OnClick    = MainHandler'#13#10 +
  '    OnDblClick = MainHandler'#13#10 +
  '    OnEnter    = MainHandler'#13#10 +
  '    OnExit     = MainHandler'#13#10 +
  '    OnKeyDown  = MainHandler'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_TwoGodHandlers_TwoFindings;
// Zwei verschiedene Handler, jeder mit 5 Bindings -> zwei Findings.
const DFM =
  'object F: TF'#13#10 +
  '  object a1: TButton OnClick = HandlerA end'#13#10 +
  '  object a2: TButton OnClick = HandlerA end'#13#10 +
  '  object a3: TButton OnClick = HandlerA end'#13#10 +
  '  object a4: TButton OnClick = HandlerA end'#13#10 +
  '  object a5: TCheckBox OnClick = HandlerA end'#13#10 +
  '  object b1: TButton OnClick = HandlerB end'#13#10 +
  '  object b2: TButton OnClick = HandlerB end'#13#10 +
  '  object b3: TButton OnClick = HandlerB end'#13#10 +
  '  object b4: TButton OnClick = HandlerB end'#13#10 +
  '  object b5: TCheckBox OnClick = HandlerB end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(2, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_ThresholdZero_FallsBackToFive;
// DetectorMaxGodHandlerEvents = 0 ist nicht "abschalten", sondern Safety-
// Net (uDfmGodHandler.pas:45 ergaenzt auf 5). Test fixiert das Verhalten.
const DFM =
  'object F: TF'#13#10 +
  '  object d1: TButton OnClick = MainClick end'#13#10 +
  '  object d2: TButton OnClick = MainClick end'#13#10 +
  '  object d3: TButton OnClick = MainClick end'#13#10 +
  '  object d4: TButton OnClick = MainClick end'#13#10 +
  '  object d5: TCheckBox OnClick = MainClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DetectorMaxGodHandlerEvents := 0;
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler));
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_UniformClassAndEvent_Silent;
// Homogenitaets-Gate (User-Entscheid 2026-08-09): EIN Handler an N
// Instanzen DERSELBEN Klasse mit DEMSELBEN Event (Tag-Farbmenue,
// Klaviertasten) ist parametrisierte Buendelung - kein God-Handler.
const DFM =
  'object F: TF'#13#10 +
  '  object m1: TMenuItem OnClick = ColorClick end'#13#10 +
  '  object m2: TMenuItem OnClick = ColorClick end'#13#10 +
  '  object m3: TMenuItem OnClick = ColorClick end'#13#10 +
  '  object m4: TMenuItem OnClick = ColorClick end'#13#10 +
  '  object m5: TMenuItem OnClick = ColorClick end'#13#10 +
  '  object m6: TMenuItem OnClick = ColorClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmGodHandler),
    'homogene Tag-Buendelung muss still bleiben');
  finally F.Free; end;
end;

procedure TTestDfmGodHandler.Test_SameClassDifferentEvents_Reported;
// Gleiche Klasse, aber GEMISCHTE Event-Typen -> heterogen -> Fund.
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick    = MainHandler end'#13#10 +
  '  object b2: TButton OnClick    = MainHandler end'#13#10 +
  '  object b3: TButton OnDblClick = MainHandler end'#13#10 +
  '  object b4: TButton OnClick    = MainHandler end'#13#10 +
  '  object b5: TButton OnClick    = MainHandler end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmGodHandler),
    'gemischte Event-Typen bleiben ein God-Handler-Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmGodHandler);

end.
