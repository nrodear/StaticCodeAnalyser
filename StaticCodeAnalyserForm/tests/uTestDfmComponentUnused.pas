unit uTestDfmComponentUnused;

// Tests fuer SCA184 TDfmComponentUnusedDetector - unbenutzte DFM-Komponente.
// Der Kern-Test ist Test_CrossUnitReference_NotDetected: eine published
// Komponente, die aus einer ZWEITEN Unit ueber den Form-Global benutzt wird,
// darf KEIN Fund sein (SymIdx.HasExternalRefs greift). Ohne diesen Schutz
// wuerde der Detektor einen FP-Sturm ausloesen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmComponentUnused = class
  public
    // --- Treffer ---
    [Test] procedure Test_UnusedComponent_Detected;

    // --- Nicht-Treffer (Benutzungs-Nachweise U1..U4) ---
    [Test] procedure Test_CrossUnitReference_NotDetected;   // U4 (FP-KERN)
    // KNOWN GAP v1 (Review 2026-07-05): Cross-Unit-ZUGRIFFE bei denen die
    // Komponente das MITTLERE Glied der Punkt-Kette ist (Form.Comp.Prop:=x /
    // Form.Comp.Method) werden NICHT erkannt - der geteilte Symbol-Index
    // indexiert per Vertrag nur das rechteste Kettenglied (Schutz gegen
    // uVisibilityCheck-TP-Verlust, s. Build_NestedDottedAccess_Rightmost-
    // Indexed). Diese Tests nageln den Ist-Zustand (FALSE POSITIVE) fest;
    // ein kuenftiger dedizierter Chain-Index (vor fcLow->fcMedium-Promotion)
    // MUSS sie bewusst auf 0 drehen.
    [Test] procedure Test_CrossUnitPropertyWrite_KnownGap_FalsePositive;
    [Test] procedure Test_CrossUnitMethodCall_KnownGap_FalsePositive;
    [Test] procedure Test_EventBound_NotDetected;           // U1
    [Test] procedure Test_DfmInternalDataSourceRef_NotDetected; // U2
    [Test] procedure Test_OwnCodeReference_NotDetected;     // U3

    // --- Harte Sicherheitsregeln (S1..S3) ---
    [Test] procedure Test_NoSymbolIndex_Silent;             // S1
    [Test] procedure Test_PersistentField_NotDetected;      // S2
    [Test] procedure Test_FindComponentInCode_Silent;       // S3

    // --- Finding-Inhalt / Einstufung ---
    [Test] procedure Test_Finding_KindSeverityConfidenceAndMessage;

    // ---- Testluecke 130: die drei ungetesteten Skip-Pfade ------------------
    [Test] procedure Test_OwnProjectFrameClass_NotDetected;        // S4
    [Test] procedure Test_UnknownFrameClass_StillDetected;         // S4-Gegenprobe
    [Test] procedure Test_InlineSubtree_NotDetected;               // inline
    [Test] procedure Test_InheritedComponent_NotDetected;          // inherited
    [Test] procedure Test_NameOnlyInConstLiteral_NotDetected;      // S3 je Komponente
    [Test] procedure Test_OtherTextInConstLiteral_StillDetected;   // S3-Gegenprobe
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder, uDfmRepoIndex, uSymbolReferenceIndex,
  uDfmComponentUnused;

// Schreibt Main- (+ optional Other-) .pas in einen temp-Ordner, baut Repo-
// und Symbol-Index ueber BEIDE Dateien und laesst den Detektor laufen.
// MainFn wird als AOwnUnitPath (Cross-Unit + S3-Quelltext) uebergeben.
function RunDetector(const DfmSrc, MainPas, OtherPas: string;
  UseSymIdx: Boolean = True): TObjectList<TLeakFinding>;
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
  RepoIdx   : TDfmRepoIndex;
  SymIdx    : TSymbolReferenceIndex;
  Tmp       : string;
  MainFn, OtherFn : string;
  FileList  : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_dfmcu_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(Tmp);

  MainFn  := TPath.Combine(Tmp, 'uMain.pas');
  OtherFn := TPath.Combine(Tmp, 'uOther.pas');
  try
    TFile.WriteAllText(MainFn, MainPas, TEncoding.UTF8);
    if OtherPas <> '' then
      TFile.WriteAllText(OtherFn, OtherPas, TEncoding.UTF8);

    DfmParser := TDfmParser.Create;
    try
      Graph := DfmParser.ParseSource(DfmSrc);
    finally
      DfmParser.Free;
    end;

    PasParser := TParser2.Create;
    try
      UnitNode := PasParser.ParseFile(MainFn);
    finally
      PasParser.Free;
    end;

    Binding := TFormBinder.Bind(Graph, UnitNode);
    RepoIdx := TDfmRepoIndex.Create;
    SymIdx  := nil;
    try
      FileList := TStringList.Create;
      try
        FileList.Add(MainFn);
        if OtherPas <> '' then FileList.Add(OtherFn);
        RepoIdx.Build(FileList);
        if UseSymIdx then
        begin
          SymIdx := TSymbolReferenceIndex.Create;
          SymIdx.Build(FileList);
        end;
      finally
        FileList.Free;
      end;

      TDfmComponentUnusedDetector.Analyze(Binding, Graph, RepoIdx, SymIdx,
        MainFn, 'uMain.dfm', Result);
    finally
      SymIdx.Free;
      RepoIdx.Free;
      Binding.Free;
      UnitNode.Free;
      Graph.Free;
    end;
  finally
    if TDirectory.Exists(Tmp) then TDirectory.Delete(Tmp, True);
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
  // Standard-DFM: eine unbenutzte Komponente unter der Form.
  DFM_ORPHAN =
    'object Form1: TForm1'#13#10 +
    '  object btnOrphan: TButton'#13#10 +
    '  end'#13#10 +
    'end';
  // Passende .pas mit published Field, aber ohne jede Nutzung.
  PAS_ORPHAN =
    'unit uMain;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
    'type TForm1 = class(TForm)'#13#10 +
    '  btnOrphan: TButton;'#13#10 +
    'end;'#13#10 +
    'var Form1: TForm1;'#13#10 +
    'implementation'#13#10 +
    'end.';

{ --- Treffer --- }

procedure TTestDfmComponentUnused.Test_UnusedComponent_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM_ORPHAN, PAS_ORPHAN, '');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmComponentUnused.Test_CrossUnitReference_NotDetected;
// FP-KERN: btnShared wird NUR aus uOther via Form1.btnShared gelesen. Der
// repo-weite Symbol-Index sieht die Cross-Unit-Referenz -> kein Fund.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnShared: TButton;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const PAS_OTHER =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Poke;'#13#10 +
  'var Dummy: TObject;'#13#10 +
  'begin'#13#10 +
  '  Dummy := Form1.btnShared;'#13#10 +   // Cross-Unit-Zugriff (rightmost = btnShared)
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnShared: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_CrossUnitPropertyWrite_KnownGap_FalsePositive;
// KNOWN GAP v1: btnShared wird aus uOther NUR per
// 'Form1.btnShared.Visible := False' angesprochen - die Komponente ist das
// MITTLERE Glied. Der geteilte Symbol-Index indexiert nur das rechteste Glied
// ('Visible'), 'btnShared' bleibt unsichtbar -> FALSE POSITIVE (1 Fund).
// Der Index-Vertrag (rightmost-only) bleibt bewusst so, um uVisibilityCheck
// nicht zu regressieren; die echte Loesung ist ein dedizierter Chain-Index
// vor der Promotion. Dieser Test nagelt den Ist-Zustand fest.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnShared: TButton;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const PAS_OTHER =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Poke;'#13#10 +
  'begin'#13#10 +
  '  Form1.btnShared.Visible := False;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnShared: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, PAS_OTHER);
  try
    // KNOWN GAP: sollte 0 sein, ist aber 1 (Mittel-Token nicht indexiert).
    Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused),
      'KNOWN GAP v1: Cross-Unit-Property-Write ueber Mittel-Token nicht erkannt');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_CrossUnitMethodCall_KnownGap_FalsePositive;
// KNOWN GAP v1: btnShared wird aus uOther nur per 'Form1.btnShared.SetFocus'
// benutzt (Methodenaufruf-Kette, Komponente = Mittel-Glied) -> FALSE POSITIVE.
// Gleiche Ursache wie Test_CrossUnitPropertyWrite_KnownGap_FalsePositive.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnShared: TButton;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const PAS_OTHER =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Poke;'#13#10 +
  'begin'#13#10 +
  '  Form1.btnShared.SetFocus;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnShared: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, PAS_OTHER);
  try
    // KNOWN GAP: sollte 0 sein, ist aber 1 (Mittel-Token nicht indexiert).
    Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused),
      'KNOWN GAP v1: Cross-Unit-Method-Call ueber Mittel-Token nicht erkannt');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_EventBound_NotDetected;
// U1: Komponente mit OnClick-Bindung ist interaktiv -> kein Fund.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls, System.Classes;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnGo: TButton;'#13#10 +
  '  procedure btnGoClick(Sender: TObject);'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.btnGoClick(Sender: TObject);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnGo: TButton OnClick = btnGoClick end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_DfmInternalDataSourceRef_NotDetected;
// U2: DataSource1 wird DFM-intern von DBGrid1.DataSource referenziert ->
// kein Fund. DBGrid1 selbst wird im Code angesprochen (U3), damit der Test
// exakt 0 liefert und die U2-Regel isoliert bleibt.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.DBGrids, Data.DB;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  DBGrid1: TDBGrid;'#13#10 +
  '  DataSource1: TDataSource;'#13#10 +
  '  procedure DoRefresh;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.DoRefresh;'#13#10 +
  'begin'#13#10 +
  '  DBGrid1.Refresh;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object DBGrid1: TDBGrid DataSource = DataSource1 end'#13#10 +
  '  object DataSource1: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_OwnCodeReference_NotDetected;
// U3: btnGo wird in einer eigenen Methode angesprochen -> kein Fund.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnGo: TButton;'#13#10 +
  '  procedure Go;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.Go;'#13#10 +
  'begin'#13#10 +
  '  btnGo.SetFocus;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnGo: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

{ --- Harte Sicherheitsregeln --- }

procedure TTestDfmComponentUnused.Test_NoSymbolIndex_Silent;
// S1: ohne Symbol-Index (Single-File-Modus) darf NICHTS emittiert werden -
// jede aus anderer Unit benutzte Komponente waere sonst falsch als unused.
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM_ORPHAN, PAS_ORPHAN, '', False); // UseSymIdx = False -> SymIdx = nil
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_PersistentField_NotDetected;
// S2: T*Field-Komponenten definieren das Dataset-Schema und sind auch ohne
// Code-Ref aktiv -> in v1 komplett ueberspringen.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Data.DB;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  SqlField1: TStringField;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object SqlField1: TStringField'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_FindComponentInCode_Silent;
// S3: die Unit ruft FindComponent( -> Komponenten koennten per Name
// aufgeloest werden -> gar nicht melden.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls, System.Classes;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnGo: TButton;'#13#10 +
  '  procedure DoStuff;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.DoStuff;'#13#10 +
  'var C: TComponent;'#13#10 +
  'begin'#13#10 +
  '  C := FindComponent(''btnGo'');'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnGo: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused));
  finally F.Free; end;
end;

{ --- Finding-Inhalt / Einstufung --- }

procedure TTestDfmComponentUnused.Test_Finding_KindSeverityConfidenceAndMessage;
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM_ORPHAN, PAS_ORPHAN, '');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused),
      'Fixture muss genau einen Fund liefern');
    Assert.AreEqual(fkDfmComponentUnused, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
    Assert.AreEqual(fcLow, F[0].Confidence);
    Assert.Contains(F[0].MissingVar, 'btnOrphan');
    Assert.Contains(F[0].MissingVar, 'TButton');
  finally F.Free; end;
end;

{ --- Testluecke 130 (Voll-Review 2026-09-12): die drei stummen Skip-Pfade --- }
//
// S4 (Z.350-351), der inline/inherited-Skip (Z.354) und S3 je Komponente
// (Z.366) hatten keinen Test. Der Bestandstest Test_FindComponentInCode_Silent
// deckt NUR die file-globale Haelfte von S3 ab (Z.325, 'FindComponent(' im
// Quelltext schaltet die ganze Datei stumm) - nicht den Namen im
// String-Literal einer EINZELNEN Komponente.
//
// Alle sechs Faelle sind am gebauten Stand nachgemessen (0/1/0/0/0/1). Der
// Detektor emittiert mit fcLow und ist unter dem Vorgabe-Filter
// MinConfidence=medium an der CLI unsichtbar; gemessen wurde deshalb mit
// einer eigenen analyser.ini (MinConfidence=low) in einem separaten
// APPDATA - die Konfiguration des Nutzers bleibt unberuehrt.
//
// Die sechs Fixturen sind fast gleich; jede Gegenprobe unterscheidet sich
// absichtlich in genau einer Sache von ihrem Partner (Klasse im Repo ja/nein,
// 'inline' statt 'object', Name im Literal ja/nein). Der Selbstscan meldet
// dafuer fuenf zusaetzliche DuplicateBlock-Hints - in Testunits kein Mangel
// (Profil-Politik), und ein Generator statt literaler Fixturen wuerde den
// einen Unterschied verstecken, um den es geht.

procedure TTestDfmComponentUnused.Test_OwnProjectFrameClass_NotDetected;
// S4: TMyFrame ist im Repo-Index (uOther deklariert die Klasse) -> visuelle
// Vererbung bzw. eingebetteter Frame, konservativ ueberspringen.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  fraEmbedded: TMyFrame;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const PAS_OTHER =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMyFrame = class(TFrame)'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object fraEmbedded: TMyFrame'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, PAS_OTHER);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused),
    'projekteigene Frame-Klasse wird uebersprungen');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_UnknownFrameClass_StillDetected;
// Die Gegenprobe zu S4, und sie traegt die ganze Aussage: identisches DFM,
// identische uMain - nur deklariert KEINE Unit die Klasse TMyFrame. Ohne
// diesen Test bliebe offen, ob oben der Repo-Index gegriffen hat oder
// einfach der Name 'fraEmbedded' irgendwo durchgerutscht ist.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  fraEmbedded: TMyFrame;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object fraEmbedded: TMyFrame'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused),
    'unbekannte Klasse: der S4-Skip darf NICHT greifen');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_InlineSubtree_NotDetected;
// 'inline' statt 'object' - eingebetteter Frame, Laufzeit-Sub-Objekt.
// HasInlineAncestorOrSelf laeuft die Parent-Kette hoch, weil IsInline nur am
// inline-Knoten selbst steht. Gegenprobe ist der Test darueber: dieselbe
// Datei mit 'object' meldet.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  fraEmbedded: TMyFrame;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  inline fraEmbedded: TMyFrame'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused),
    'inline-Subtree wird uebersprungen');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_InheritedComponent_NotDetected;
// 'inherited btnX' - in der Eltern-Form deklariertes Member. Der
// Bestandstest Test_UnusedComponent_Detected ist die Gegenprobe in Reinform:
// gleiche Struktur mit 'object' -> Fund.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnX: TButton;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  inherited btnX: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused),
    'inherited-Komponente wird uebersprungen');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_NameOnlyInConstLiteral_NotDetected;
// S3 JE KOMPONENTE (Z.366) - und die Fixture ist bewusst eine const-
// Deklaration, nicht ein ShowMessage('btnX ...').
//
// WARUM DAS DER UNTERSCHIED IST: Aufruf-Argumente landen im NAMEN des
// nkCall-Knotens (ParsePrimary haengt die Klammerinhalte an), und
// CollectCodeTokens tokenisiert Node.Name - ein Name im Call-Argument waere
// also schon ueber U3 (Z.363) still, eine Zeile VOR S3. const-Eintraege
// dagegen sind nkField-Knoten, und genau die ueberspringt CollectCodeTokens
// (Z.108). Der Rohtext-Scan CollectStringLiteralTokens sieht das Literal
// trotzdem. Damit ist S3 der einzige Pfad, der hier greifen kann.
//
// 'FindComponent(' steht bewusst NICHT in der Fixture - sonst haette die
// file-globale Haelfte von S3 (Z.325) schon vorher abgebrochen.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnX: TButton;'#13#10 +
  'end;'#13#10 +
  'const'#13#10 +
  '  SHinweis = ''btnX konnte nicht geladen werden'';'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnX: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmComponentUnused),
    'Name in einem String-Literal -> koennte per Name aufgeloest werden');
  finally F.Free; end;
end;

procedure TTestDfmComponentUnused.Test_OtherTextInConstLiteral_StillDetected;
// Gegenprobe zu S3: dieselbe Datei, dasselbe const - nur ohne den
// Komponentennamen im Literal. Ohne sie waere der Test darueber auch dann
// gruen, wenn die blosse Anwesenheit eines const-Abschnitts stoert.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnX: TButton;'#13#10 +
  'end;'#13#10 +
  'const'#13#10 +
  '  SHinweis = ''Etwas konnte nicht geladen werden'';'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnX: TButton'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDetector(DFM, PAS_MAIN, '');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmComponentUnused),
    'ohne den Namen im Literal greift S3 nicht');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmComponentUnused);

end.
