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

initialization
  TDUnitX.RegisterTestFixture(TTestDfmComponentUnused);

end.
