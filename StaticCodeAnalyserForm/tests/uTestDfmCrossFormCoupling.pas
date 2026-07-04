unit uTestDfmCrossFormCoupling;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmCrossFormCoupling = class
  public
    // --- Treffer ---
    [Test] procedure Test_DottedAssignToOtherForm_Detected;
    [Test] procedure Test_CallOnOtherForm_Detected;
    [Test] procedure Test_DeepDottedPath_Detected;

    // --- Nicht-Treffer ---
    [Test] procedure Test_SelfReference_NotDetected;
    [Test] procedure Test_UnknownIdentifier_NotDetected;
    [Test] procedure Test_NoRepoIndex_Silent;
    [Test] procedure Test_PlainAssign_NoDot_NoFinding;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsOtherFormAndExpr;

    // --- Multi-Hit ---
    [Test] procedure Test_MultipleAccesses_AllReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDfmParser, uComponentGraph,
  uFormBinder, uDfmRepoIndex,
  uDfmCrossFormCoupling;

// Schreibt zwei .pas in einen temp-Ordner und laesst den RepoIndex
// darueber laufen, damit Form-Variablen aus beiden Units bekannt sind.
function RunWithIndex(const DfmSrc, MainPas, OtherPas: string;
  UseIndex: Boolean = True): TObjectList<TLeakFinding>;
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
  Index     : TDfmRepoIndex;
  Tmp       : string;
  MainFn, OtherFn : string;
  FileList  : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  // Temp-Files anlegen (.pas mit den passenden Inhalten).
  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_xform_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(Tmp);

  MainFn  := TPath.Combine(Tmp, 'uMain.pas');
  OtherFn := TPath.Combine(Tmp, 'uOther.pas');
  // Writes INNERHALB des try: wirft der zweite Write, raeumt das finally
  // den ersten + das Verzeichnis trotzdem ab (Audit_TestQualitaet F7).
  try
    TFile.WriteAllText(MainFn,  MainPas);
    if OtherPas <> '' then
      TFile.WriteAllText(OtherFn, OtherPas);

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
    Index   := nil;
    try
      if UseIndex then
      begin
        Index := TDfmRepoIndex.Create;
        FileList := TStringList.Create;
        try
          FileList.Add(MainFn);
          if OtherPas <> '' then FileList.Add(OtherFn);
          Index.Build(FileList);
        finally
          FileList.Free;
        end;
      end;

      TDfmCrossFormCouplingDetector.Analyze(Binding, Index,
        ExtractFileName(MainFn), Result);
    finally
      Index.Free;
      Binding.Free;
      UnitNode.Free;
      Graph.Free;
    end;
  finally
    // Rekursives Delete: raeumt auch Restdateien ab statt im finally zu
    // werfen (und die Original-Exception zu maskieren).
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
  // uOther.pas - definiert TOther + globale Form2-Variable.
  PAS_OTHER =
    'unit uOther;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'type TOther = class(TForm) end;'#13#10 +
    'var Form2: TOther;'#13#10 +
    'implementation'#13#10 +
    'end.';

{ --- Treffer --- }

procedure TTestDfmCrossFormCoupling.Test_DottedAssignToOtherForm_Detected;
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Form2.Edit1.Text := ''x'';'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_CallOnOtherForm_Detected;
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Form2.Refresh;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_DeepDottedPath_Detected;
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Form2.qOrders.SQL.Text := ''SELECT 1'';'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmCrossFormCoupling.Test_SelfReference_NotDetected;
// Zugriff ueber die eigene Form-Variable - kein Cross-Form-Smell.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) Edit1: TEdit; end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Main.Edit1.Text := ''x'';'#13#10 +    // Self-Zugriff ueber eigene Var
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain object Edit1: TEdit end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_UnknownIdentifier_NotDetected;
// 'SomeLib.DoStuff' - SomeLib ist keine registrierte Form-Var.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  SomeLib.DoStuff;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_NoRepoIndex_Silent;
// Single-File-Pfad: Repo-Index nicht aufgebaut -> Detektor schweigt.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Form2.Edit1.Text := ''x'';'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER, False);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_PlainAssign_NoDot_NoFinding;
// 'X := 1' enthaelt keinen Punkt - kein Pfad-Pattern, kein Befund.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := 1;'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmCrossFormCoupling.Test_Finding_KindAndSeverity;
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin Form2.Edit1.Text := ''x''; end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual(fkDfmCrossFormCoupling, F[0].Kind);
    Assert.AreEqual(lsWarning, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_Finding_MissingVarMentionsOtherFormAndExpr;
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin Form2.Edit1.Text := ''x''; end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.Contains(F[0].MissingVar, 'Form2');
    Assert.Contains(F[0].MissingVar, 'TOther');
  finally F.Free; end;
end;

procedure TTestDfmCrossFormCoupling.Test_MultipleAccesses_AllReported;
// Zwei Cross-Form-Zugriffe im selben Body -> beide werden gemeldet.
const PAS_MAIN =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMain = class(TForm) end;'#13#10 +
  'var Main: TMain;'#13#10 +
  'implementation'#13#10 +
  'procedure TMain.Go;'#13#10 +
  'begin'#13#10 +
  '  Form2.Edit1.Text := ''a'';'#13#10 +
  '  Form2.Edit2.Text := ''b'';'#13#10 +
  'end;'#13#10 +
  'end.';
const DFM = 'object Main: TMain end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithIndex(DFM, PAS_MAIN, PAS_OTHER);
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmCrossFormCoupling));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmCrossFormCoupling);

end.
