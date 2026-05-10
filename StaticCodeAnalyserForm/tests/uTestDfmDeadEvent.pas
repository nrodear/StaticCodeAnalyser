unit uTestDfmDeadEvent;

// Validiert sowohl den TFormBinder (Pascal-AST + DFM-Graph pairing) als
// auch den TDfmDeadEventDetector als End-to-End-Pfad. Wenn diese Tests
// gruen sind, sitzt die Iteration-3-Infrastruktur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDeadEvent = class
  public
    // --- Treffer ---
    [Test] procedure Test_HandlerMissing_Detected;
    [Test] procedure Test_MultipleEvents_OnlyMissingReported;
    [Test] procedure Test_NestedComponent_DeadEvent_Detected;

    // --- Nicht-Treffer ---
    [Test] procedure Test_HandlerExistsAsImpl_NoFinding;
    [Test] procedure Test_HandlerExistsAsClassSignature_NoFinding;
    [Test] procedure Test_HandlerLookupCaseInsensitive_NoFinding;

    // --- Robustheit ---
    [Test] procedure Test_NoFormClass_NoFinding;
    [Test] procedure Test_FormClassNameMismatch_NoFinding;
    [Test] procedure Test_NonEventProperty_Ignored;     // OnlineMode = True
    [Test] procedure Test_OnlineModeStyleName_NotTreatedAsEvent;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_SeverityIsError;
    [Test] procedure Test_Finding_KindIsDeadEvent;
    [Test] procedure Test_Finding_MissingVarMentionsHandlerAndForm;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder,
  uDfmDeadEvent;

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
    TDfmDeadEventDetector.Analyze(Binding, 'test.dfm', Result);
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
  // Pascal-Unit mit einer Form-Klasse + Methoden-Implementation. Wird in
  // den Tests punktuell variiert.
  PAS_BASE =
    'unit uMainForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
    'type'#13#10 +
    '  TMainForm = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    procedure btnSaveClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TMainForm.btnSaveClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  ShowMessage(''hi'');'#13#10 +
    'end;'#13#10 +
    'end.';

  // DFM, das den Handler korrekt referenziert.
  DFM_GOOD =
    'object MainForm: TMainForm'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnSaveClick'#13#10 +
    '  end'#13#10 +
    'end';

  // DFM, das auf einen nicht existierenden Handler zeigt (klassischer
  // Rename-Vergisst-DFM-Fall).
  DFM_DEAD =
    'object MainForm: TMainForm'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnSaveClickOLD'#13#10 +
    '  end'#13#10 +
    'end';

{ --- Treffer --- }

procedure TTestDfmDeadEvent.Test_HandlerMissing_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, PAS_BASE);
  try
    Assert.AreEqual(1, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_MultipleEvents_OnlyMissingReported;
const DFM =
  'object MainForm: TMainForm'#13#10 +
  '  object btnSave: TButton'#13#10 +
  '    OnClick = btnSaveClick'#13#10 +              // existiert
  '    OnEnter = btnSaveEnterMISSING'#13#10 +       // existiert NICHT
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS_BASE);
  try
    Assert.AreEqual(1, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_NestedComponent_DeadEvent_Detected;
const DFM =
  'object MainForm: TMainForm'#13#10 +
  '  object pnlTop: TPanel'#13#10 +
  '    object btnInner: TButton'#13#10 +
  '      OnClick = doesNotExist'#13#10 +
  '    end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS_BASE);
  try
    Assert.AreEqual(1, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmDeadEvent.Test_HandlerExistsAsImpl_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_GOOD, PAS_BASE);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_HandlerExistsAsClassSignature_NoFinding;
// Methode ist in der Klassendeklaration vorhanden, aber Implementation
// fehlt - das ist zwar ein Linker-Problem, aber kein DFM-Streaming-Crash.
// DeadEvent darf NICHT melden, wenn die Methode zumindest deklariert ist.
const PAS =
  'unit uMainForm;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type'#13#10 +
  '  TMainForm = class(TForm)'#13#10 +
  '    procedure btnSaveClick(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_GOOD, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_HandlerLookupCaseInsensitive_NoFinding;
// DFM schreibt 'BTNSAVECLICK' (aller Caps), Pascal hat 'btnSaveClick'.
// Delphi-Identifier sind nicht case-sensitiv -> kein Befund.
const DFM =
  'object MainForm: TMainForm'#13#10 +
  '  object btnSave: TButton'#13#10 +
  '    OnClick = BTNSAVECLICK'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS_BASE);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

{ --- Robustheit --- }

procedure TTestDfmDeadEvent.Test_NoFormClass_NoFinding;
// Kein Pascal-AST verfuegbar -> Detektor MUSS schweigen, sonst
// produziert er bei jedem .dfm ohne sauberen Parse einen falschen Bug.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, '');
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_FormClassNameMismatch_NoFinding;
// DFM-Root ist 'TForm2', Pascal-Klasse heisst 'TForm99'. Ohne match-
// bare Klasse kann der Binder die Methode nicht finden - er meldet das
// aber NICHT als DeadEvent (waere ein anderer Befund, FormBinding-
// Mismatch, der hier ausserhalb des Scope ist).
const DFM =
  'object Form2: TForm2'#13#10 +
  '  object btn: TButton OnClick = doesNotMatter end'#13#10 +
  'end';
const PAS =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'type TForm99 = class end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_NonEventProperty_Ignored;
// 'Caption' ist kein Event - kein Versuch der Methoden-Aufloesung.
const DFM =
  'object MainForm: TMainForm'#13#10 +
  '  Caption = ''ungebundener Text wird nicht als Handler interpretiert'''#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS_BASE);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_OnlineModeStyleName_NotTreatedAsEvent;
// 'OnlineMode' faengt mit 'On' an, ist aber kein Event (drittes Zeichen
// 'l', nicht 'M'/'C'/...). Plus: Wert ist Bool, nicht Ident.
const DFM =
  'object MainForm: TMainForm'#13#10 +
  '  OnlineMode = True'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS_BASE);
  try
    Assert.AreEqual(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmDeadEvent.Test_Finding_SeverityIsError;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, PAS_BASE);
  try
    Assert.AreEqual(lsError, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_Finding_KindIsDeadEvent;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, PAS_BASE);
  try
    Assert.AreEqual(fkDfmDeadEvent, F[0].Kind);
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_Finding_MissingVarMentionsHandlerAndForm;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, PAS_BASE);
  try
    Assert.Contains(F[0].MissingVar, 'btnSaveClickOLD');
    Assert.Contains(F[0].MissingVar, 'TMainForm');
    Assert.Contains(F[0].MissingVar, 'btnSave');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDeadEvent);

end.
