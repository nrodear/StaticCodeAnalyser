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
    // FP-Fix Charge 15: Collection-Item-Events (pvkItemList) binden
    // auch - beide Fixtures VOR dem Bau an der rw70-Exe verprobt
    // (dort feuern DoAction UND Verwaist; nach dem Fix nur Verwaist).
    [Test] procedure Gate_ItemListBoundHandler_NoFinding;
    [Test] procedure Gate_ItemListOtherHandler_StillDetected;
    // Testluecke 137: Bindung im ELTERN-DFM zaehlt mit
    [Test] procedure Test_BoundInParentDfm_NoFinding;
    [Test] procedure Test_UnboundInParentDfm_StillDetected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  System.Classes, System.IOUtils,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder, uDfmRepoIndex,
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmOrphanHandler));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler));
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

procedure TTestDfmOrphanHandler.Gate_ItemListBoundHandler_NoFinding;
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TWM = class(TForm)'#13#10 +
  '  procedure DoAction(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWM.DoAction(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM =
  'object WM: TWM'#13#10 +
  '  object Acts: TWebActions'#13#10 +
  '    Actions = <'#13#10 +
  '      item'#13#10 +
  '        Name = ''wa1'''#13#10 +
  '        OnAction = DoAction'#13#10 +
  '      end>'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler),
      'OnAction im item-Block IST eine Bindung');
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Gate_ItemListOtherHandler_StillDetected;
// Gleiche DFM, aber die published Methode heisst anders als der
// item-Handler - sie bleibt verwaist (TP-Gegenprobe).
const PAS =
  'unit u; interface uses Vcl.Forms;'#13#10 +
  'type TWM = class(TForm)'#13#10 +
  '  procedure Verwaist(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWM.Verwaist(Sender: TObject); begin end;'#13#10 +
  'end.';
const DFM =
  'object WM: TWM'#13#10 +
  '  object Acts: TWebActions'#13#10 +
  '    Actions = <'#13#10 +
  '      item'#13#10 +
  '        OnAction = DoAction'#13#10 +
  '      end>'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM, PAS);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmOrphanHandler),
      'fremder item-Handler rettet die verwaiste Methode nicht');
  finally F.Free; end;
end;

{ --- Bindung im ELTERN-DFM (Testluecke 137) --------------------------------- }
//
// Analyze sammelt die gebundenen Handler nicht nur aus dem eigenen
// Binding, sondern laeuft die Parent-Kette hoch (Z.125-135, samt
// SammleItemListBindungen am jeweiligen FormNode). Damit gilt eine
// published Methode der KIND-Klasse, die ein Knopf im ELTERN-DFM per
// OnClick bindet, nicht als verwaist.
//
// Diese Anti-FP-Eigenschaft war ungetestet: alle Bestandstests binden
// ueber TFormBinder.Bind, dort ist Parent immer nil, und die while-
// Schleife dreht sich genau einmal. Faellt der Aufstieg weg, faellt
// heute kein Test - der FP kaeme still zurueck.
//
// Der Harness benutzt deshalb BindWithParents mit einem TDfmRepoIndex
// ueber beide Units, so wie uDfmAnalysisRunner im Repo-Lauf.
// Am gebauten Stand nachgemessen (gebunden 0, ungebunden 1).

function RunKindMitEltern(const AParentDfm: string): TObjectList<TLeakFinding>;
// Legt Eltern- und Kind-Unit ab, indiziert beide und untersucht das
// KIND. AParentDfm ist der einzige Unterschied zwischen den zwei Tests:
// einmal mit OnClick-Bindung, einmal ohne.
const
  PARENT_PAS =
    'unit uBase;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, Vcl.StdCtrls, System.Classes;'#13#10 +
    'type'#13#10 +
    '  TBaseForm = class(TForm)'#13#10 +
    '    btnGo: TButton;'#13#10 +
    '  end;'#13#10 +
    'var BaseForm: TBaseForm;'#13#10 +
    'implementation'#13#10 +
    'end.';
  CHILD_PAS =
    'unit uChild;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, System.Classes, uBase;'#13#10 +
    'type'#13#10 +
    '  TChildForm = class(TBaseForm)'#13#10 +
    '  published'#13#10 +
    '    procedure SharedClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'var ChildForm: TChildForm;'#13#10 +
    'implementation'#13#10 +
    'procedure TChildForm.SharedClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  DoSomething;'#13#10 +
    'end;'#13#10 +
    'end.';
  CHILD_DFM =
    'inherited ChildForm: TChildForm'#13#10 +
    'end';
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
  RepoIdx   : TDfmRepoIndex;
  FileList  : TStringList;
  Tmp, ChildFn, ParentFn : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_orph_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(Tmp);
  try
    ChildFn  := TPath.Combine(Tmp, 'uChild.pas');
    ParentFn := TPath.Combine(Tmp, 'uBase.pas');
    TFile.WriteAllText(ChildFn,  CHILD_PAS,  TEncoding.UTF8);
    TFile.WriteAllText(ParentFn, PARENT_PAS, TEncoding.UTF8);
    // Das ELTERN-DFM muss neben der Eltern-.pas liegen: BindWithParents
    // sucht es ueber den RepoIndex genau dort.
    TFile.WriteAllText(TPath.Combine(Tmp, 'uBase.dfm'), AParentDfm,
      TEncoding.UTF8);

    DfmParser := TDfmParser.Create;
    try
      Graph := DfmParser.ParseSource(CHILD_DFM);
    finally
      DfmParser.Free;
    end;

    PasParser := TParser2.Create;
    try
      UnitNode := PasParser.ParseFile(ChildFn);
    finally
      PasParser.Free;
    end;

    RepoIdx := TDfmRepoIndex.Create;
    try
      FileList := TStringList.Create;
      try
        FileList.Add(ChildFn);
        FileList.Add(ParentFn);
        RepoIdx.Build(FileList);
      finally
        FileList.Free;
      end;

      Binding := TFormBinder.BindWithParents(Graph, UnitNode, RepoIdx);
      try
        TDfmOrphanHandlerDetector.Analyze(Binding, 'uChild.dfm', Result);
      finally
        Binding.Free;
        UnitNode.Free;
        Graph.Free;
      end;
    finally
      RepoIdx.Free;
    end;
  finally
    if TDirectory.Exists(Tmp) then TDirectory.Delete(Tmp, True);
  end;
end;

procedure TTestDfmOrphanHandler.Test_BoundInParentDfm_NoFinding;
// Der Knopf steht im Eltern-DFM und bindet SharedClick; die Methode ist
// im Kind published. Kein Orphan - der Aufstieg ueber Walker.Parent
// findet die Bindung.
var F: TObjectList<TLeakFinding>;
begin
  F := RunKindMitEltern(
    'object BaseForm: TBaseForm'#13#10 +
    '  object btnGo: TButton'#13#10 +
    '    OnClick = SharedClick'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmOrphanHandler),
      'im Eltern-DFM gebunden ist gebunden');
  finally F.Free; end;
end;

procedure TTestDfmOrphanHandler.Test_UnboundInParentDfm_StillDetected;
// Die Gegenprobe: derselbe Aufbau, nur OHNE die OnClick-Zeile im
// Eltern-DFM. Ohne sie waere der Test darueber auch dann gruen, wenn der
// Detektor an geerbten Aufbauten grundsaetzlich schwiege.
var F: TObjectList<TLeakFinding>;
begin
  F := RunKindMitEltern(
    'object BaseForm: TBaseForm'#13#10 +
    '  object btnGo: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmOrphanHandler),
      'nirgends gebunden - der Handler ist verwaist');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmOrphanHandler);

end.
