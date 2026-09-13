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

    // --- Geerbte Form: Handler lebt nur in der Elternklasse (Luecke 133) ---
    [Test] procedure Test_EmptyHandlerInParentOnly_ChildSilent;
    [Test] procedure Test_EmptyHandlerInParentOnly_ParentStillReports;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  System.Classes, System.IOUtils,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder, uDfmRepoIndex,
  uDfmEmptyBoundEvent,
  uDfmDeadEvent;   // Kontrollmessung: ist die Elternkette aufgeloest?

const
  // Fundort-Name, den die Harnesse an die Detektoren reichen. Der Wert ist
  // beliebig - er landet nur in TLeakFinding.FileName -, steht aber an
  // drei Stellen und gehoert deshalb an eine.
  EBE_DFM_NAME = 'test.dfm';

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
    TDfmEmptyBoundEventDetector.Analyze(Binding, EBE_DFM_NAME, Result);
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(3, Count(F, fkDfmEmptyBoundEvent));
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmEmptyBoundEvent));
  finally F.Free; end;
end;

{ --- Geerbte Form: der Handler lebt nur in der Elternklasse ---------------- }
//
// Testluecke 133 (Voll-Review 2026-09-12). Analyze liest
// Binding.MethodImpls, und das ist KLASSENLOKAL - anders als
// Binding.ResolveHandler, das die Vererbung hochlaeuft. Bei einer
// geerbten Form ohne eigene Implementierung findet die Suche nichts und
// der Detektor schweigt.
//
// DAS IST RICHTIG, NICHT EINE LUECKE - und der Unterschied ist wichtig
// genug fuer zwei Tests: der leere Rumpf steht EINMAL, naemlich in der
// Elternklasse, und wird dort auch EINMAL gemeldet. Liefe die Suche ueber
// ResolveHandler, meldete jede erbende Form denselben leeren Rumpf noch
// einmal - ein Duplikat je Nachfahre.
//
// Der Pin sichert genau das ab: wer den Detektor spaeter auf
// ResolveHandler umstellt, sieht hier rot und muss sich die
// Duplikatfrage stellen.
//
// GEGENPROBE GEGEN DEN FALSCHEN GRUND: der Kind-Test prueft zusaetzlich,
// dass TDfmDeadEventDetector schweigt. DeadEvent loest ueber die
// Elternkette auf; bliebe die Kette unaufgeloest, wuerde es 'Handler
// existiert nicht' melden. Sein Schweigen beweist, dass die Bindung den
// Elternteil kennt - das Schweigen von EmptyBoundEvent kommt also
// wirklich von der klassenlokalen Suche und nicht von einer kaputten
// Bindung. Am gebauten Stand nachgemessen (Kind 0/0, Elternteil 1).

const
  EBE_PARENT_PAS =
    'unit uBase;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, Vcl.StdCtrls, System.Classes;'#13#10 +
    'type'#13#10 +
    '  TBaseForm = class(TForm)'#13#10 +
    '    btnGo: TButton;'#13#10 +
    '    procedure btnGoClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'var BaseForm: TBaseForm;'#13#10 +
    'implementation'#13#10 +
    'procedure TBaseForm.btnGoClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';
  EBE_PARENT_DFM =
    'object BaseForm: TBaseForm'#13#10 +
    '  object btnGo: TButton'#13#10 +
    '    OnClick = btnGoClick'#13#10 +
    '  end'#13#10 +
    'end';
  EBE_CHILD_PAS =
    'unit uChild;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, uBase;'#13#10 +
    'type'#13#10 +
    '  TChildForm = class(TBaseForm)'#13#10 +
    '  end;'#13#10 +
    'var ChildForm: TChildForm;'#13#10 +
    'implementation'#13#10 +
    'end.';
  EBE_CHILD_DFM =
    'inherited ChildForm: TChildForm'#13#10 +
    '  inherited btnGo: TButton'#13#10 +
    '    OnClick = btnGoClick'#13#10 +
    '  end'#13#10 +
    'end';
  // Dateinamen, unter denen die beiden Units abgelegt werden. Als
  // Konstanten, weil sie an drei Stellen gebraucht werden (Schreiben,
  // Indizieren, Auswaehlen) und der Auswahl-Parameter genau einen davon
  // tragen muss.
  EBE_FN_CHILD  = 'uChild.pas';
  EBE_FN_PARENT = 'uBase.pas';

function RunInheritedPair(const AUnitToAnalyze, ADfmSrc: string;
  out ADeadEvents: Integer): TObjectList<TLeakFinding>;
// Baut Eltern- und Kind-Unit in einem Temp-Verzeichnis auf, indiziert
// beide und bindet MIT Elternaufloesung (BindWithParents) - so wie
// uDfmAnalysisRunner es im Repo-Lauf tut.
//
// AUnitToAnalyze ist EBE_FN_CHILD oder EBE_FN_PARENT und sagt, welche der
// beiden Formen untersucht wird. Bewusst ein Dateiname und kein Boolean:
// am Aufruf steht dann 'uChild.pas' statt 'True', und der Leser muss die
// Signatur nicht nachschlagen.
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
  RepoIdx   : TDfmRepoIndex;
  FileList  : TStringList;
  Tmp, ChildFn, ParentFn, Fn : string;
  Tote      : TObjectList<TLeakFinding>;
begin
  Result      := TObjectList<TLeakFinding>.Create(True);
  ADeadEvents := 0;

  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_ebe_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(Tmp);
  try
    ChildFn  := TPath.Combine(Tmp, EBE_FN_CHILD);
    ParentFn := TPath.Combine(Tmp, EBE_FN_PARENT);
    TFile.WriteAllText(ChildFn,  EBE_CHILD_PAS,  TEncoding.UTF8);
    TFile.WriteAllText(ParentFn, EBE_PARENT_PAS, TEncoding.UTF8);

    Fn := TPath.Combine(Tmp, AUnitToAnalyze);

    DfmParser := TDfmParser.Create;
    try
      Graph := DfmParser.ParseSource(ADfmSrc);
    finally
      DfmParser.Free;
    end;

    PasParser := TParser2.Create;
    try
      UnitNode := PasParser.ParseFile(Fn);
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
        TDfmEmptyBoundEventDetector.Analyze(Binding, EBE_DFM_NAME, Result);
        // Kontrollmessung: laeuft die Elternkette? Getrennte Liste, damit
        // die Zusicherung des Aufrufers nur EmptyBoundEvent zaehlt.
        Tote := TObjectList<TLeakFinding>.Create(True);
        try
          TDfmDeadEventDetector.Analyze(Binding, EBE_DFM_NAME, Tote);
          ADeadEvents := Tote.Count;
        finally
          Tote.Free;
        end;
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

procedure TTestDfmEmptyBoundEvent.Test_EmptyHandlerInParentOnly_ChildSilent;
var
  F    : TObjectList<TLeakFinding>;
  Tote : Integer;
begin
  F := RunInheritedPair(EBE_FN_CHILD, EBE_CHILD_DFM, Tote);
  try
    Assert.AreEqual<Integer>(0, Tote,
      'Kontrollmessung: DeadEvent muss schweigen - sonst ist die '
      + 'Elternkette gar nicht aufgeloest und der Test unten beweist nichts');
    Assert.AreEqual<Integer>(0, Count(F, fkDfmEmptyBoundEvent),
      'der leere Rumpf gehoert der Elternklasse und wird nur dort gemeldet');
  finally F.Free; end;
end;

procedure TTestDfmEmptyBoundEvent.Test_EmptyHandlerInParentOnly_ParentStillReports;
// Die Gegenprobe: dieselbe Konstellation, aber die ELTERN-Form
// untersucht. Ohne sie waere der Test darueber auch dann gruen, wenn der
// Detektor an geerbten Aufbauten grundsaetzlich nichts mehr faende.
var
  F    : TObjectList<TLeakFinding>;
  Tote : Integer;
begin
  F := RunInheritedPair(EBE_FN_PARENT, EBE_PARENT_DFM, Tote);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmEmptyBoundEvent),
      'in der Elternklasse steht der leere Rumpf - genau einmal gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmEmptyBoundEvent);

end.
