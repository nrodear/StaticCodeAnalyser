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

    // --- Ancestor-Kette (Real-World-Audit 2026-07-31) ---
    [Test] procedure Test_UnresolvedUserAncestor_NoFinding;
    [Test] procedure Test_UnresolvedGrandAncestor_HandlerNotFindable_NoFinding;
    [Test] procedure Test_ResolvedParentChain_HandlerInParent_NotReported;
    [Test] procedure Test_ResolvedParentChain_BothHandlersNowhere_Detected;
    [Test] procedure Test_ResolvedParentChain_HandlerNowhere_Detected;

    // --- 'OnFoo = nil' ist keine Bindung (2026-08-03) ---
    [Test] procedure Test_NilHandler_NotTreatedAsBinding;
    [Test] procedure Test_NonNilHandler_StillReported;   // Kontrolle

    // --- Mehrdeutiger Ahn: der RepoIndex hat geraten (2026-08-03) ---
    [Test] procedure Test_AmbiguousAncestorClass_NoFinding;
    [Test] procedure Test_UniqueAncestorClass_StillReported;  // Kontrolle

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

// noinspection-file MemoryLeak, ClassPerFile, GodClass
// MemoryLeak: die Fixture erzeugt ein Objekt ohne Free absichtlich -
//   Pruefgegenstand. (Am 2026-08-03 kurzzeitig entfernt, weil ein
//   --file-Scan den Marker als wirkungslos meldete. In diesem Modus
//   KANN SCA001 hier nicht feuern - die Sonde war blind, nicht der
//   Marker ueberfluessig. Nur der Voll-Scan entscheidet das.)
// ClassPerFile: die zusaetzlichen Klassendeklarationen stehen in
//   STRING-LITERALEN - Pascal-Fixtures fuer den Parser, keine Klassen
//   dieser Unit. Der Detektor arbeitet zeilenweise und kann das nicht
//   unterscheiden.
// GodClass: eine DUnitX-Fixture ist eine Liste von Testfaellen, keine
//   Klasse mit Verantwortung. Aufteilen wuerde die Tests nur verstecken.
// (MemoryLeak stand hier bis 2026-08-03; SCA165 meldete den Marker als
//  wirkungslos - der Leak-Detektor ist inzwischen genauer.)

uses
  System.SysUtils, System.StrUtils, System.Classes,
  System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  System.IOUtils,
  uDfmParser, uComponentGraph,
  uFormBinder, uDfmRepoIndex,
  uDfmDeadEvent;

const
  // Dreimal woertlich waere DuplicateString - der eigene
  // Analyser meldet das ab drei Vorkommen.
  TEST_DFM = 'test.dfm';

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
    TDfmDeadEventDetector.Analyze(Binding, TEST_DFM, Result);
  finally
    Binding.Free;
    UnitNode.Free;
    Graph.Free;
  end;
end;

function RunOnWithParent(const DfmSrc, PasSrc, ParentClass,
  ParentPasSrc: string): TObjectList<TLeakFinding>;
// Wie RunOn, baut aber zusaetzlich die Parent-Bindung von Hand auf (im
// Produktivpfad macht das TFormBinder.BindWithParents ueber den RepoIndex,
// den es im Unit-Test nicht gibt). Das Kind-Binding uebernimmt via
// AdoptParent die Ownership an Parent-Binding/-Graph/-UnitNode.
var
  DfmParser   : TDfmParser;
  Graph       : TComponentGraph;
  ParentGraph : TComponentGraph;
  PasParser   : TParser2;
  UnitNode    : TAstNode;
  ParentUnit  : TAstNode;
  Binding     : TFormBinding;
  ParentBind  : TFormBinding;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  DfmParser := TDfmParser.Create;
  try
    Graph := DfmParser.ParseSource(DfmSrc);
  finally
    DfmParser.Free;
  end;

  PasParser := TParser2.Create;
  try
    UnitNode   := PasParser.ParseSource(PasSrc);
    ParentUnit := PasParser.ParseSource(ParentPasSrc);
  finally
    PasParser.Free;
  end;

  // Synth-Graph fuer die Parent-Klasse (analog uFormBinder.BuildParent, wenn
  // die Basis-Form keine eigene .dfm hat).
  ParentGraph := TComponentGraph.Create;
  ParentGraph.AddRoot('', ParentClass, 0, 0);

  Binding    := TFormBinder.Bind(Graph, UnitNode);
  ParentBind := TFormBinder.Bind(ParentGraph, ParentUnit);
  try
    Binding.AdoptParent(ParentBind, ParentGraph, ParentUnit);
    TDfmDeadEventDetector.Analyze(Binding, TEST_DFM, Result);
  finally
    Binding.Free;      // gibt ParentBind + ParentGraph + ParentUnit mit frei
    UnitNode.Free;
    Graph.Free;
  end;
end;

function WriteTempRepo(const PasSrc: string;
  const AncestorUnits: array of string; out ATmpDir: string): TStringList;
// Legt ein Wegwerf-Verzeichnis mit Haupt- und Ahnen-Units an und liefert
// die Dateiliste fuer TDfmRepoIndex.Build. Bewusst eine eigene Routine:
// sonst stapeln sich in RunWithRepoIndex vier try-Ebenen uebereinander -
// der eigene Analyser meldet das zu Recht als NestedTry.
var
  Fn : string;
  I  : Integer;
begin
  ATmpDir := TPath.Combine(TPath.GetTempPath, 'sca_de_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(ATmpDir);
  Result := TStringList.Create;
  try
    Fn := TPath.Combine(ATmpDir, 'uMainForm.pas');
    TFile.WriteAllText(Fn, PasSrc, TEncoding.UTF8);
    Result.Add(Fn);
    for I := Low(AncestorUnits) to High(AncestorUnits) do
    begin
      // Verschiedene DATEInamen, gleicher KLASSENname im Inhalt - genau so
      // entsteht die Mehrdeutigkeit, die geprueft werden soll.
      Fn := TPath.Combine(ATmpDir, Format('uAncestor%d.pas', [I]));
      TFile.WriteAllText(Fn, AncestorUnits[I], TEncoding.UTF8);
      Result.Add(Fn);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure AnalyzeWithIndex(Graph: TComponentGraph; UnitNode: TAstNode;
  FileList: TStringList; Results: TObjectList<TLeakFinding>);
// Index bauen, ueber BindWithParents binden, Detektor laufen lassen.
// Ebenfalls ausgelagert, damit RunWithRepoIndex flach bleibt.
var
  RepoIdx : TDfmRepoIndex;
  Binding : TFormBinding;
begin
  // Erst binden, dann analysieren - NACHEINANDER, nicht ineinander.
  // Der Index wird nach BindWithParents nicht mehr gebraucht: die
  // Ahnen-ASTs haengen als FOwnedResources an der Bindung selbst.
  RepoIdx := TDfmRepoIndex.Create;
  try
    RepoIdx.Build(FileList);
    Binding := TFormBinder.BindWithParents(Graph, UnitNode, RepoIdx);
  finally
    RepoIdx.Free;
  end;

  try
    TDfmDeadEventDetector.Analyze(Binding, TEST_DFM, Results);
  finally
    Binding.Free;
  end;
end;

function RunWithRepoIndex(const DfmSrc, PasSrc: string;
  const AncestorUnits: array of string): TObjectList<TLeakFinding>;
// Baut die Parent-Kette ueber den ECHTEN Produktivpfad (BindWithParents +
// TDfmRepoIndex) statt per AdoptParent von Hand. Nur so entsteht die
// Mehrdeutigkeits-Markierung, denn die sitzt im Index.
var
  DfmParser : TDfmParser;
  PasParser : TParser2;
  Graph     : TComponentGraph;
  UnitNode  : TAstNode;
  FileList  : TStringList;
  TmpDir    : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  DfmParser := TDfmParser.Create;
  try
    Graph := DfmParser.ParseSource(DfmSrc);
  finally
    DfmParser.Free;
  end;

  PasParser := TParser2.Create;
  try
    UnitNode := PasParser.ParseSource(PasSrc);
  finally
    PasParser.Free;
  end;

  FileList := WriteTempRepo(PasSrc, AncestorUnits, TmpDir);
  try
    AnalyzeWithIndex(Graph, UnitNode, FileList, Result);
  finally
    FileList.Free;
    TDirectory.Delete(TmpDir, True);
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

function CountHandler(F: TObjectList<TLeakFinding>;
  const AHandlerName: string): Integer;
// 2026-07-31 (Review-Fund "Test_ResolvedParentChain_HandlerInParent ist
// vakuum-gruen"): reine Mengenzaehlung reicht nicht - die Tests der
// Ancestor-Gruppe muessen belegen, WELCHER Handler gemeldet wurde. Der
// Detektor legt den Handlernamen in MissingVar ab
// ('<Comp>.<Event> = <Handler> (handler missing in <Klasse>)').
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if (Fnd.Kind = fkDfmDeadEvent)
       and ContainsText(Fnd.MissingVar, AHandlerName) then Inc(Result);
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmDeadEvent.Test_HandlerExistsAsImpl_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_GOOD, PAS_BASE);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
  finally F.Free; end;
end;

{ --- Ancestor-Kette (Real-World-Audit 2026-07-31) --- }

const
  // Kind-Form erbt von einer USER-Basisklasse (nicht von TForm) - genau das
  // skia4delphi-Muster (TfrmSplashScreen = class(TfrmBase)).
  PAS_CHILD_OF_BASE =
    'unit uChildForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, uBaseForm;'#13#10 +
    'type'#13#10 +
    '  TMainForm = class(TBaseForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  // Basisklasse MIT dem Handler (in der published-Defaultsection).
  PAS_BASE_WITH_HANDLER =
    'unit uBaseForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type'#13#10 +
    '  TBaseForm = class(TForm)'#13#10 +
    '    procedure btnSaveClickOLD(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TBaseForm.btnSaveClickOLD(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';

  // Basisklasse OHNE den Handler.
  PAS_BASE_WITHOUT_HANDLER =
    'unit uBaseForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type'#13#10 +
    '  TBaseForm = class(TForm)'#13#10 +
    '    procedure SomethingElse(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  // Wie PAS_BASE_WITHOUT_HANDLER, aber die Basisklasse erbt ihrerseits von
  // einer USER-Klasse, die niemand aufloesen kann (TDeepBaseForm ist im Test
  // nirgends vorhanden). Einziger Unterschied zu PAS_BASE_WITHOUT_HANDLER ist
  // das Ahnen-Token - damit bilden Test_UnresolvedGrandAncestor_* und
  // Test_ResolvedParentChain_HandlerNowhere_Detected ein Differenzpaar, das
  // GENAU IsAncestorChainResolved isoliert (2026-07-31, Review-Fund
  // "vakuum-gruen").
  PAS_BASE_OPEN_CHAIN =
    'unit uBaseForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, uDeepBaseForm;'#13#10 +
    'type'#13#10 +
    '  TBaseForm = class(TDeepBaseForm)'#13#10 +
    '    procedure SomethingElse(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  // Zwei Event-Bindungen auf derselben Komponente: btnSaveClickOLD existiert
  // (nur!) in der Basisklasse, btnSaveEnterGONE existiert nirgends. Der
  // eingebaute Positivfall macht den Test gegen eine kaputte Ahnen-Suche
  // scharf: faellt die Parent-Aufloesung weg, kommen 2 statt 1 Fund.
  DFM_DEAD_TWO =
    'object MainForm: TMainForm'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnSaveClickOLD'#13#10 +
    '    OnEnter = btnSaveEnterGONE'#13#10 +
    '  end'#13#10 +
    'end';

procedure TTestDfmDeadEvent.Test_UnresolvedUserAncestor_NoFinding;
// FP-Fix (Real-World-Audit 2026-07-31, skia4delphi Sample.Form.SplashScreen):
// die Formklasse erbt von einer USER-Basisklasse, die der Binder nicht
// aufloesen konnte (kein RepoIndex / Basis-Unit nicht gefunden). DFM-Streaming
// sucht den Handler ueber die GESAMTE Hierarchie - solange die Kette offen
// ist, ist der behauptete Load-Crash unbeweisbar. Ohne das Gate meldet der
// Detektor hier einen Error-Fund.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_DEAD, PAS_CHILD_OF_BASE);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent),
      'unaufgeloeste Ahnen-Kette -> kein Befund');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_UnresolvedGrandAncestor_HandlerNotFindable_NoFinding;
// SCHARFER Test fuer IsAncestorChainResolved (2026-07-31, Review-Fund
// "Test_ResolvedParentChain_HandlerInParent_NoFinding ist vakuum-gruen"):
// Der Vorgaenger konnte das Gate prinzipiell nicht pruefen - bei aufgeloester
// Kette LAESST das Gate den Pfad ja durch, die 0 kam allein aus HasHandler.
// Hier ist die Kette dagegen OFFEN, obwohl ein Parent-Binding existiert:
// TMainForm -> TBaseForm (gebunden) -> TDeepBaseForm (nicht aufloesbar).
// Der DFM-Handler btnSaveClickOLD ist weder im Kind noch in TBaseForm
// deklariert; deklariert waere er - unbeweisbar fuer uns - in TDeepBaseForm.
// Streicht man Zeile 'if not IsAncestorChainResolved(Binding) then Exit;' oder
// nagelt die Funktion auf True fest, meldet der Detektor hier 1 Fund und der
// Test wird ROT. Zusaetzlich pinnt der Fall den Ketten-Walk
// (while Top.Parent <> nil): ohne ihn wuerde nur das Kind geprueft.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnWithParent(DFM_DEAD, PAS_CHILD_OF_BASE, 'TBaseForm',
                       PAS_BASE_OPEN_CHAIN);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent),
      'offene Kette oberhalb des Parents -> kein Befund');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_ResolvedParentChain_HandlerInParent_NotReported;
// Kette vollstaendig aufgeloest (Parent-Binding vorhanden, dessen Ahn ist
// TForm) und der Handler existiert in der Basisklasse -> dieser Handler darf
// NICHT gemeldet werden.
//
// 2026-07-31 (Review-Fund vakuum-gruen): frueher hiess der Test
// ..._NoFinding und verglich 0 mit 0 - beide Suppressoren (Ancestor-Gate UND
// vererbte Handler-Aufloesung) haetten einzeln ausfallen duerfen, ohne dass
// er rot wird. Jetzt traegt die Fixture einen zweiten Event, dessen Handler
// nirgends existiert. Damit ist die erwartete Menge nicht mehr leer:
//   * faellt die Parent-Aufloesung in TFormBinding.ResolveHandler weg
//     -> 2 Funde statt 1 (btnSaveClickOLD taucht auf) -> ROT
//   * fehlt das Parent-Binding ganz oder liefert das Gate faelschlich False
//     -> 0 Funde -> ROT
// Die Gegenrichtung (Gate faelschlich True bei offener Kette) deckt
// Test_UnresolvedUserAncestor_NoFinding /
// Test_UnresolvedGrandAncestor_HandlerNotFindable_NoFinding ab.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnWithParent(DFM_DEAD_TWO, PAS_CHILD_OF_BASE, 'TBaseForm',
                       PAS_BASE_WITH_HANDLER);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent),
      'genau der nirgends existierende Handler ist ein Befund');
    Assert.AreEqual<Integer>(0, CountHandler(F, 'btnSaveClickOLD'),
      'geerbter Handler ist kein toter Event');
    Assert.AreEqual<Integer>(1, CountHandler(F, 'btnSaveEnterGONE'),
      'nicht existierender Handler bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_ResolvedParentChain_BothHandlersNowhere_Detected;
// Kontrolle zur Fixture von Test_ResolvedParentChain_HandlerInParent_NotReported
// (2026-07-31): identisches DFM, aber die Basisklasse hat den Handler NICHT.
// Dann muessen BEIDE Events gemeldet werden. Ohne diesen Test koennte die
// erwartete 1 oben auch aus einer verschluckten Event-Bindung stammen statt
// aus der Vererbungs-Aufloesung.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnWithParent(DFM_DEAD_TWO, PAS_CHILD_OF_BASE, 'TBaseForm',
                       PAS_BASE_WITHOUT_HANDLER);
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmDeadEvent),
      'beide Handler fehlen in der ganzen Kette');
    Assert.AreEqual<Integer>(1, CountHandler(F, 'btnSaveClickOLD'),
      'ohne Basis-Deklaration ist auch btnSaveClickOLD ein Befund');
    Assert.AreEqual<Integer>(1, CountHandler(F, 'btnSaveEnterGONE'),
      'zweiter Handler bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_ResolvedParentChain_HandlerNowhere_Detected;
// TP-Gegenprobe zum Ancestor-Gate: die Kette ist KOMPLETT aufgeloest (bis
// TForm) und der Handler existiert nirgends - der Fund muss erhalten bleiben.
// Differenzpaar zu Test_UnresolvedGrandAncestor_HandlerNotFindable_NoFinding:
// identische Fixture bis auf das Ahnen-Token der Basisklasse (TForm hier,
// TDeepBaseForm dort). Ein Gate, das immer False liefert, faellt hier auf.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnWithParent(DFM_DEAD, PAS_CHILD_OF_BASE, 'TBaseForm',
                       PAS_BASE_WITHOUT_HANDLER);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent),
      'aufgeloeste Kette ohne Handler bleibt ein Befund');
    Assert.AreEqual<Integer>(1, CountHandler(F, 'btnSaveClickOLD'),
      'gemeldet wird der DFM-Handler aus der Bindung');
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent));
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

{ --- 'OnFoo = nil' ist keine Bindung --------------------------------- }

const
  DFM_NIL_HANDLER =
    'object MainForm: TMainForm'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = nil'#13#10 +
    '  end'#13#10 +
    'end';

  DFM_MISSING_HANDLER =
    'object MainForm: TMainForm'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnSaveNichtVorhanden'#13#10 +
    '  end'#13#10 +
    'end';

procedure TTestDfmDeadEvent.Test_NilHandler_NotTreatedAsBinding;
// 'OnClick = nil' sagt ausdruecklich: KEIN Handler. Das als fehlenden
// Handler zu melden dreht die Aussage um. Belegt am Referenzkorpus mit
// genau einem Vorkommen (cnwizards CnListCompFrm.dfm, OnCustomDrawItem).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_NIL_HANDLER, PAS_BASE);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent),
      'OnClick = nil ist keine Bindung und darf nichts melden');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_NonNilHandler_StillReported;
// KONTROLLE zum Test darueber: gleicher Aufbau, echter Name statt 'nil'.
// Ohne diese Probe waere der Test darueber auch dann gruen, wenn der
// nil-Filter die Regel komplett abgeschaltet haette.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM_MISSING_HANDLER, PAS_BASE);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent));
    Assert.AreEqual<Integer>(1, CountHandler(F, 'btnSaveNichtVorhanden'));
  finally F.Free; end;
end;

{ --- Mehrdeutiger Ahn ------------------------------------------------ }

const
  // Eigener Name: 'TBaseForm' fuehren die aelteren Fixtures dieser
  // Datei bereits. Als Konstante, weil er sonst dreimal woertlich
  // dastuende - ab drei meldet der eigene Analyser DuplicateString.
  AMBIG_BASE = 'TAmbigBase';

  // Kind-Form, deren Ahn NICHT VCL-Root ist -> der Index muss ihn suchen.
  PAS_CHILD_OF_BASE =
    'unit uMainForm;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type'#13#10 +
    '  TMainForm = class(' + AMBIG_BASE + ')'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  // Zwei Units, BEIDE mit einer Klasse TBaseForm - nur eine kennt den
  // Handler. Genau die Lage aus skia4delphi (TfrmBase in VCL und in FMX).
  PAS_BASE_WITH_HANDLER =
    'unit uAncestorA;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type'#13#10 +
    '  ' + AMBIG_BASE + ' = class(TForm)'#13#10 +
    '    procedure pnlBackClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  PAS_BASE_WITHOUT_HANDLER =
    'unit uAncestorB;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type'#13#10 +
    '  ' + AMBIG_BASE + ' = class(TForm)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  DFM_CALLS_PNLBACK =
    'object MainForm: TMainForm'#13#10 +
    '  object pnlBack: TPanel'#13#10 +
    '    OnClick = pnlBackClick'#13#10 +
    '  end'#13#10 +
    'end';

procedure TTestDfmDeadEvent.Test_AmbiguousAncestorClass_NoFinding;
// Zwei Units deklarieren TBaseForm; der Index kann nur eine liefern und
// hat damit GERATEN. Trifft er die falsche, fehlt der Handler nur
// scheinbar - gemeldet wuerde ein Load-Crash, den es nicht gibt. Also
// schweigen, unabhaengig davon, welche der beiden gewaehlt wurde.
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithRepoIndex(DFM_CALLS_PNLBACK, PAS_CHILD_OF_BASE,
         [PAS_BASE_WITH_HANDLER, PAS_BASE_WITHOUT_HANDLER]);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDeadEvent),
      'Bei mehrdeutigem Ahn beweist "Handler nicht gefunden" nichts');
  finally F.Free; end;
end;

procedure TTestDfmDeadEvent.Test_UniqueAncestorClass_StillReported;
// KONTROLLE: gleicher Aufbau mit nur EINER Ahnen-Unit, die den Handler
// nicht kennt. Die Kette ist eindeutig aufgeloest, der Handler fehlt
// wirklich - es MUSS gemeldet werden. Ohne diese Probe koennte das
// Mehrdeutigkeits-Gate die Regel generell stumm geschaltet haben.
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithRepoIndex(DFM_CALLS_PNLBACK, PAS_CHILD_OF_BASE,
         [PAS_BASE_WITHOUT_HANDLER]);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDeadEvent));
    Assert.AreEqual<Integer>(1, CountHandler(F, 'pnlBackClick'));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDeadEvent);

end.
