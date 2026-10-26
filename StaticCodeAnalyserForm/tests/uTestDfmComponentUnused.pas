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

  // S4 nur fuer SICHTBARE, uebersetzbare Deklarationen (2026-10-26). Eigene
  // Fixture, weil TTestDfmComponentUnused sonst ueber 20 Tests waechst;
  // Ablauf (RunDetector/CountUnused) und Fixturen liegen auf Unit-Ebene.
  [TestFixture]
  TTestDfmComponentUnusedVisibility = class
  public
    [Test] procedure Test_FrameClassInUnusedUnit_StillDetected;    // nicht per uses
    [Test] procedure Test_ImplUsesClass_NotDetected;               // uses im impl-Teil
    [Test] procedure Test_HeaderStubUnitInUses_StillDetected;      // PSDecl-Muster
    [Test] procedure Test_HeaderStubWithInclude_NotDetected;       // {$I}-Rumpf
    [Test] procedure Test_IncludeSpellings_NotStub;                // (*$I, {$i'..'}, Tab
    [Test] procedure Test_ConditionalDirectives_StillStub;         // {$IFDEF} ist kein {$I}
    [Test] procedure Test_AbstractOnlyUnit_NotDetected;            // kein Rumpf noetig
    [Test] procedure Test_ExternalOnlyUnit_NotDetected;            // external: kein Rumpf
    [Test] procedure Test_UnitScopeSuffixInUses_NotDetected;       // 'Other' -> Vcl.Other
    [Test] procedure Test_InterposerInOwnUnit_NotDetected;         // eigene Unit
  end;

implementation

// noinspection-file ClassPerFile
// Zwei Fixtures fuer denselben Detektor (Grenze 20 Tests je Fixture): die
// Kernregeln und die S4-Sichtbarkeit teilen RunDetector und die Fixturen -
// eine zweite Datei braechte nur einen zweiten Projekteintrag.

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
// OtherFile: Dateiname der zweiten Unit - S4 vergleicht den Unit-Namen
// (Dateistamm) mit den uses-Eintraegen, z.B. 'Vcl.Other.pas'.
function RunDetector(const DfmSrc, MainPas, OtherPas: string;
  UseSymIdx: Boolean = True;
  const OtherFile: string = 'uOther.pas'): TObjectList<TLeakFinding>;
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
  OtherFn := TPath.Combine(Tmp, OtherFile);
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
// 2026-10-26: uMain bindet uOther jetzt per uses ein. Die alte Fixture tat
// das nicht - sie war so nicht uebersetzbar (TMyFrame in uMain unsichtbar)
// und gruen nur, weil S4 jede Deklaration im Scan-Umfang zaehlte. Genau
// die alte Fixture ist jetzt Test_FrameClassInUnusedUnit_StillDetected.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, uOther;'#13#10 +
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

// ---- S4 nur fuer SICHTBARE, uebersetzbare Deklarationen (2026-10-26) -------
//
// Korpus-Anlass: im Sammelscan D:\git-sca-realworld schalteten die Pascal-
// Script-Koepfe cnwizards/Bin/PSDecl/StdCtrls.pas, Menus.pas, ... (leerer
// implementation-Teil) und fremde Interposer (Kastri MainFrm 'TButton =
// class(...)') SCA184 fuer TLabel/TButton/TMenuItem in ALLEN Repos stumm -
// 10.975 von 11.993 Funden. Jetzt zaehlt nur eine Deklaration in der Form-
// Unit selbst oder in einer per uses eingebundenen Unit, und nie ein Stub.
//
// Am gebauten Stand f45c964d (alte Regel) per Mini-Repo nachgemessen
// (scratchpad sca184\mini, MinConfidence=low): UnusedUnit 0, HeaderStub 0 -
// beide Tests sind dort ROT (erwartet 1); die vier Gegenproben 0 = gruen.
// Die Pruefung, dass der Detektor im Mini-Repo ueberhaupt meldet, ist der
// Fall ohne zweite Unit (Test_UnknownFrameClass_StillDetected): 1.
//
// Die Fixturen entstehen aus FrameMain/FrameUnit: der eine Unterschied
// zwischen Fall und Gegenprobe steht damit als Argument im Aufruf.

function CountUnused(const DfmSrc, MainPas, OtherPas: string;
  const OtherFile: string = 'uOther.pas'): Integer;
// RunDetector, zaehlen, freigeben - die S4-Faelle unterscheiden sich nur in
// den Quelltexten, nicht im Ablauf.
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunDetector(DfmSrc, MainPas, OtherPas, True, OtherFile);
  try
    Result := Count(F, fkDfmComponentUnused);
  finally
    F.Free;
  end;
end;

function FrameMain(const AIfaceUses, AImplPart: string): string;
// uMain mit der Komponente fraEmbedded: TMyFrame. AIfaceUses = uses-Liste
// des interface-Teils, AImplPart steht direkt hinter 'implementation'.
begin
  Result := Format(
    'unit uMain;'#13#10 +
    'interface'#13#10 +
    'uses %s;'#13#10 +
    'type TForm1 = class(TForm)'#13#10 +
    '  fraEmbedded: TMyFrame;'#13#10 +
    'end;'#13#10 +
    'var Form1: TForm1;'#13#10 +
    'implementation'#13#10 +
    '%send.', [AIfaceUses, AImplPart]);
end;

function FrameUnit(const AMember, AImplPart: string;
  const AUnitName: string = 'uOther'): string;
// Die zweite Unit: deklariert TMyFrame mit AMember als Rumpf ('' = ohne
// Member); AImplPart steht direkt hinter 'implementation'.
begin
  Result := Format(
    'unit %s;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type TMyFrame = class(TFrame)'#13#10 +
    '%send;'#13#10 +
    'implementation'#13#10 +
    '%send.', [AUnitName, AMember, AImplPart]);
end;

const
  DFM_FRAME_OBJECT =
    'object Form1: TForm1'#13#10 +
    '  object fraEmbedded: TMyFrame'#13#10 +
    '  end'#13#10 +
    'end';
  // Konstruktor ohne Rumpf im implementation-Teil: macht uOther zum Stub,
  // solange kein Include den Rumpf nachliefert.
  MEMBER_NEEDS_BODY = '  constructor Create;'#13#10;
  USES_OTHER        = 'Vcl.Forms, uOther';

procedure TTestDfmComponentUnusedVisibility.Test_FrameClassInUnusedUnit_StillDetected;
// Die alte S4-Fixture: uOther deklariert TMyFrame, uMain bindet uOther aber
// NICHT ein. Der Compiler saehe die Klasse nicht; eine gleichnamige Klasse
// irgendwo im Scan-Umfang ist kein Beleg fuer "projekteigen". Gegenproben:
// Test_OwnProjectFrameClass_NotDetected (uOther im interface-uses) und
// Test_ImplUsesClass_NotDetected (uOther im implementation-uses).
begin
  Assert.AreEqual<Integer>(1,
    CountUnused(DFM_FRAME_OBJECT, FrameMain('Vcl.Forms', ''), FrameUnit('', '')),
    'Klasse nur in einer NICHT eingebundenen Unit: S4 darf nicht greifen');
end;

procedure TTestDfmComponentUnusedVisibility.Test_ImplUsesClass_NotDetected;
// uOther steht nur in der uses-Klausel des implementation-Teils. Fuer den
// Feldtyp reichte das dem Compiler nicht - S4 nimmt trotzdem beide Klauseln
// (konservative Seite, kein neuer Fund aus einer Sichtbarkeitsfeinheit).
// Traeger: CollectUsedUnits (uDfmComponentUnused) sammelt nkUsesItem ueber
// die GANZE Unit. Beschraenkt man es auf den interface-Teil, liefert dieser
// Test 1 wie Test_FrameClassInUnusedUnit_StillDetected, von dem er sich nur
// in AImplPart unterscheidet.
begin
  Assert.AreEqual<Integer>(0,
    CountUnused(DFM_FRAME_OBJECT, FrameMain('Vcl.Forms', 'uses uOther;'#13#10),
      FrameUnit('', '')),
    'uses im implementation-Teil zaehlt fuer S4 mit');
end;

procedure TTestDfmComponentUnusedVisibility.Test_HeaderStubUnitInUses_StillDetected;
// PSDecl-Muster: uOther ist eingebunden, deklariert TMyFrame mit einem
// Konstruktor, hat aber KEINE Routine im implementation-Teil - so eine Unit
// ist nicht uebersetzbar und liefert keine Komponentenklasse.
begin
  Assert.AreEqual<Integer>(1,
    CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''),
      FrameUnit(MEMBER_NEEDS_BODY, '')),
    'Header-Stub zaehlt nicht als projekteigene Klasse');
end;

procedure TTestDfmComponentUnusedVisibility.Test_HeaderStubWithInclude_NotDetected;
// Gegenprobe zum Stub, unterscheidet sich in genau einer Zeile: der Rumpf
// kommt per {$I} (Lazarus-LCL-Muster). Der Parser expandiert Includes nicht;
// ohne den Text-Schutz waere jede so gebaute Unit ein "Stub".
begin
  Assert.AreEqual<Integer>(0,
    CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''),
      FrameUnit(MEMBER_NEEDS_BODY, '{$I uOther.inc}'#13#10)),
    'Rumpf per Include: kein Stub, S4 greift');
end;

procedure TTestDfmComponentUnusedVisibility.Test_IncludeSpellings_NotStub;
// Weitere Schreibweisen derselben Direktive (Review 2026-10-26, m1): klein,
// Langform, Tab statt Leerzeichen, Apostroph direkt hinter $I, Klammer-
// Stern-Form. Traeger: DirectiveIsInclude/HasIncludeAfter (uDfmRepoIndex);
// die Fassung bis 3dd7d188 kannte nur '{$I ' und '{$INCLUDE ' (nach
// UpperCase) und machte die letzten vier Faelle zum Stub (1 Fund).
const
  SPELLINGS: array[0..5] of string = (
    '{$i uOther.inc}',
    '{$include uOther.inc}',
    '{$I'#9'uOther.inc}',
    '{$INCLUDE'#9'uOther.inc}',
    '{$I''uOther.inc''}',
    '(*$I uOther.inc*)');
var
  S : string;
begin
  for S in SPELLINGS do
  begin
    Assert.AreEqual<Integer>(0,
      CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''),
        FrameUnit(MEMBER_NEEDS_BODY, S + #13#10)),
      'Include nicht erkannt: ' + S);
  end;
end;

procedure TTestDfmComponentUnusedVisibility.Test_ConditionalDirectives_StillStub;
// Gegenprobe zu den Schreibweisen: Direktiven, die mit $I BEGINNEN, aber
// kein Include sind, lassen den Stub ein Stub. Traeger: die Bedingung an
// das Zeichen hinter $I/$INCLUDE (Whitespace oder Apostroph) in
// DirectiveIsInclude - ein blosser Praefix-Vergleich auf '{$I' machte jeden
// Fall hier zu 0.
const
  NOT_INCLUDES: array[0..4] of string = (
    '{$IFDEF DEBUG}{$ENDIF}',
    '{$IFNDEF DEBUG}{$ENDIF}',
    '{$IF Defined(DEBUG)}{$IFEND}',
    '{$IFOPT R+}{$ENDIF}',
    '{$I+}');
var
  S : string;
begin
  for S in NOT_INCLUDES do
  begin
    Assert.AreEqual<Integer>(1,
      CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''),
        FrameUnit(MEMBER_NEEDS_BODY, S + #13#10)),
      'Kein Include, trotzdem als Rumpf gewertet: ' + S);
  end;
end;

procedure TTestDfmComponentUnusedVisibility.Test_AbstractOnlyUnit_NotDetected;
// Gegenprobe zum Stub: eine abstrakte Methode braucht keinen Rumpf - die
// Unit ist trotz leerem implementation-Teil uebersetzbar.
begin
  Assert.AreEqual<Integer>(0,
    CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''),
      FrameUnit('  procedure Run; virtual; abstract;'#13#10, '')),
    'nur abstrakte Methoden: kein Stub, S4 greift');
end;

procedure TTestDfmComponentUnusedVisibility.Test_ExternalOnlyUnit_NotDetected;
// Das interface deklariert NUR eine external-Routine, der implementation-
// Teil ist leer - uebersetzbar (der Rumpf liegt in der DLL), also kein
// Stub, TMyFrame bleibt geschuetzt.
// Traeger: MethodNeedsBody (uDfmRepoIndex), die Pruefung auf ';external'
// im TypeRef (ParseMethodDirectives haengt es an, der Bibliotheksname
// danach bricht die Direktivenschleife nur ab). Ohne sie braucht Beep einen
// Rumpf, uOther wird zum Stub und der Test liefert 1 - wie
// Test_HeaderStubUnitInUses_StillDetected.
const PAS_OTHER =
  'unit uOther;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMyFrame = class(TFrame)'#13#10 +
  'end;'#13#10 +
  'procedure Beep; external ''user32.dll'';'#13#10 +
  'implementation'#13#10 +
  'end.';
begin
  Assert.AreEqual<Integer>(0,
    CountUnused(DFM_FRAME_OBJECT, FrameMain(USES_OTHER, ''), PAS_OTHER),
    'nur external-Routinen: kein Stub, S4 greift');
end;

procedure TTestDfmComponentUnusedVisibility.Test_UnitScopeSuffixInUses_NotDetected;
// Unit-Scope-Namen: 'uses Other' findet die Datei Vcl.Other.pas (wie
// 'uses StdCtrls' -> Vcl.StdCtrls). Ohne Suffix-Abgleich verloeren alte
// Formen ihre echten projekteigenen Klassen.
begin
  Assert.AreEqual<Integer>(0,
    CountUnused(DFM_FRAME_OBJECT, FrameMain('Vcl.Forms, Other', ''),
      FrameUnit('', '', 'Vcl.Other'), 'Vcl.Other.pas'),
    'uses-Eintrag ohne Scope-Praefix trifft Vcl.Other.pas');
end;

procedure TTestDfmComponentUnusedVisibility.Test_InterposerInOwnUnit_NotDetected;
// Interposer in der Form-Unit selbst ('TButton = class(Vcl.StdCtrls.TButton)'):
// sichtbar ohne uses-Eintrag, der Vergleich laeuft ueber den Pfad. Die
// Gegenprobe ohne Interposer ist Test_UnusedComponent_Detected.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Vcl.StdCtrls;'#13#10 +
  'type TButton = class(Vcl.StdCtrls.TButton)'#13#10 +
  '  procedure Run;'#13#10 +
  'end;'#13#10 +
  'type TForm1 = class(TForm)'#13#10 +
  '  btnX: TButton;'#13#10 +
  'end;'#13#10 +
  'var Form1: TForm1;'#13#10 +
  'implementation'#13#10 +
  'procedure TButton.Run;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM =
  'object Form1: TForm1'#13#10 +
  '  object btnX: TButton'#13#10 +
  '  end'#13#10 +
  'end';
begin
  Assert.AreEqual<Integer>(0, CountUnused(DFM, PAS_MAIN, ''),
    'Interposer in der eigenen Unit bleibt projekteigen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmComponentUnused);
  TDUnitX.RegisterTestFixture(TTestDfmComponentUnusedVisibility);

end.
