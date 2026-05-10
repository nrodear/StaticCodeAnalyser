unit uTestDfmOrphanHandler;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmOrphanHandler = class
  public
    [Test] procedure Test_PublishedHandlerNotBound_Detected;
    [Test] procedure Test_BoundHandler_NoFinding;
    [Test] procedure Test_NonSenderMethod_NotTreatedAsHandler;
    [Test] procedure Test_NoSenderName_NotTreatedAsHandler;
    [Test] procedure Test_WrongSenderType_NotTreatedAsHandler;
    [Test] procedure Test_BoundUnderDifferentCase_NoFinding;
    [Test] procedure Test_MultiParamHandler_StillDetected;
    [Test] procedure Test_PrivateMethod_NotConsidered;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsMethod;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder,
  uDfmOrphanHandler;

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
    TDfmOrphanHandlerDetector.Analyze(Binding, 'test.dfm', Result);
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

procedure TTestDfmOrphanHandler.Test_PublishedHandlerNotBound_Detected;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure btnOldClick(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.btnOldClick(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_BoundHandler_NoFinding;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure btnSaveClick(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.btnSaveClick(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM =
  'object F: TF'#13#10 +
  '  object btnSave: TButton OnClick = btnSaveClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_NonSenderMethod_NotTreatedAsHandler;
// 'procedure Foo;' ohne Parameter - kein Event-Handler-Kandidat.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure Foo;'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.Foo; begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_NoSenderName_NotTreatedAsHandler;
// Erster Parameter heisst nicht 'Sender' - keine Heuristik-Treffer.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure Process(Data: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.Process(Data: TObject); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_WrongSenderType_NotTreatedAsHandler;
// 'Sender: TButton' - eingeschraenkter Typ, kein generischer Event-Handler.
const PAS =
  'unit u; interface uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure Foo(Sender: TButton);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.Foo(Sender: TButton); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_BoundUnderDifferentCase_NoFinding;
// Delphi-Identifier case-insensitiv: 'btnSaveClick' im Pascal,
// 'BTNSAVECLICK' im DFM -> gilt als gebunden.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure btnSaveClick(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.btnSaveClick(Sender: TObject); begin end; end.';
const DFM =
  'object F: TF'#13#10 +
  '  object b: TButton OnClick = BTNSAVECLICK end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_MultiParamHandler_StillDetected;
// OnKeyPress hat 2 Parameter - aber Sender ist trotzdem Param[0]. Wenn
// nicht gebunden, muss der Detektor melden.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure HandleKey(Sender: TObject; var Key: Char);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TF.HandleKey(Sender: TObject; var Key: Char); begin end;'#13#10 +
  'end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(1, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_PrivateMethod_NotConsidered;
// Private Methoden landen nicht in PublishedMethods -> kein Befund.
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  'private'#13#10 +
  '  procedure DoIt(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.DoIt(Sender: TObject); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(0, Count(F, fkDfmOrphanHandler));
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_Finding_KindAndSeverity;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure btnDead(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.btnDead(Sender: TObject); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual(fkDfmOrphanHandler, F[0].Kind);
    Assert.AreEqual(lsHint,             F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_Finding_MissingVarMentionsMethod;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TF = class(TForm)'#13#10 +
  '  procedure btnDead(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation procedure TF.btnDead(Sender: TObject); begin end; end.';
const DFM = 'object F: TF end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.Contains(F[0].MissingVar, 'btnDead');
    Assert.Contains(F[0].MissingVar, 'TF');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmOrphanHandler);

end.
