unit uTestDfmEmptyBoundEvent;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmEmptyBoundEvent = class
  public
    [Test] procedure Test_BoundHandlerEmpty_Detected;
    [Test] procedure Test_HandlerWithStatement_NoFinding;
    [Test] procedure Test_HandlerWithInheritedOnly_NoFinding;
    [Test] procedure Test_MultipleBoundEvents_OnlyEmptyOnesReported;
    [Test] procedure Test_HandlerMissingAltogether_NoFinding; // DeadEvent-Domain
    [Test] procedure Test_UnboundEmptyMethod_NoFinding;       // OrphanHandler-Domain
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsComponentAndEvent;

    // --- Mehr Varianten ---
    [Test] procedure Test_MultipleEmptyBoundEvents_AllReported;
    [Test] procedure Test_HandlerWithCommentOnly_StillEmpty;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder,
  uDfmEmptyBoundEvent;

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
    TDfmEmptyBoundEventDetector.Analyze(Binding, 'test.dfm', Result);
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

procedure TTestDfmEmptyBoundEvent.Test_BoundHandlerEmpty_Detected;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure btnSaveClick(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.btnSaveClick(Sender: TObject); begin end; end.';
const DFM =
  'object F: TF object b: TButton OnClick = btnSaveClick end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_HandlerWithStatement_NoFinding;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure Click(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.Click(Sender: TObject);'#13#10 +
  'begin DoSomething; end; end.';
const DFM = 'object F: TF object b: TButton OnClick = Click end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_HandlerWithInheritedOnly_NoFinding;
// 'inherited;' produziert einen nkInherited-Child -> nicht leer per Konvention
// (analog uEmptyMethod).
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure Click(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.Click(Sender: TObject);'#13#10 +
  'begin inherited; end; end.';
const DFM = 'object F: TF object b: TButton OnClick = Click end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_MultipleBoundEvents_OnlyEmptyOnesReported;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure FullClick(Sender: TObject);'#13#10 +
  '  procedure EmptyClick(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.FullClick(Sender: TObject); begin Bla; end;'#13#10 +
  'procedure TF.EmptyClick(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM =
  'object F: TF'#13#10 +
  '  object a: TButton OnClick = FullClick end'#13#10 +
  '  object b: TButton OnClick = EmptyClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_HandlerMissingAltogether_NoFinding;
// Wenn die Methode gar nicht existiert, ist das ein DeadEvent-Befund,
// nicht ein EmptyBoundEvent-Befund.
const PAS =
  'unit u; interface uses Vcl.Forms; type TF = class(TForm) end;'#13#10 +
  'implementation end.';
const DFM = 'object F: TF object b: TButton OnClick = ghostHandler end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_UnboundEmptyMethod_NoFinding;
// Eine published Methode mit leerem Body, die NICHT gebunden ist, ist
// OrphanHandler-Territorium. EmptyBoundEvent darf hier nichts melden.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure StubClick(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.StubClick(Sender: TObject); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_Finding_KindAndSeverity;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure C(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.C(Sender: TObject); begin end; end.';
const DFM = 'object F: TF object b: TButton OnClick = C end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(fkDfmEmptyBoundEvent, F[0].Kind);
    Assert.AreEqual(lsHint,               F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_Finding_MissingVarMentionsComponentAndEvent;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure C(Sender: TObject); end;'#13#10 +
  'implementation procedure TF.C(Sender: TObject); begin end; end.';
const DFM = 'object F: TF object btnX: TButton OnClick = C end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.Contains(F[0].MissingVar, 'btnX');
    Assert.Contains(F[0].MissingVar, 'OnClick');
    Assert.Contains(F[0].MissingVar, 'C');
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_MultipleEmptyBoundEvents_AllReported;
// Mehrere leere gebundene Handler -> mehrere Findings.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure E1(Sender: TObject);'#13#10 +
  '  procedure E2(Sender: TObject);'#13#10 +
  '  procedure E3(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.E1(Sender: TObject); begin end;'#13#10 +
  'procedure TF.E2(Sender: TObject); begin end;'#13#10 +
  'procedure TF.E3(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM =
  'object F: TF'#13#10 +
  '  object b1: TButton OnClick = E1 end'#13#10 +
  '  object b2: TButton OnClick = E2 end'#13#10 +
  '  object b3: TButton OnClick = E3 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(3, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_HandlerWithCommentOnly_StillEmpty;
// Body enthaelt nur einen Kommentar - aus Parser-Sicht ist das ein
// leerer Body, also ein Finding.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm) procedure C(Sender: TObject); end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.C(Sender: TObject);'#13#10 +
  'begin'#13#10 +
  '  // TODO: implementieren'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object F: TF object b: TButton OnClick = C end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmEmptyBoundEvent);

end.
