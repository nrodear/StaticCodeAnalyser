unit uTestDfmDbInUiForm;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDbInUiForm = class
  public
    [Test] procedure Test_AdoConnectionOnForm_Detected;
    [Test] procedure Test_AdoQueryOnForm_Detected;
    [Test] procedure Test_DataSourceOnForm_Detected;
    [Test] procedure Test_AllThreeOnForm_AllReported;

    [Test] procedure Test_DbComponentsOnDataModule_Silent;
    [Test] procedure Test_DbComponentsOnNamedDataModule_Silent;
    [Test] procedure Test_OnlyUiComponents_NoFinding;

    [Test] procedure Test_NestedDbComponent_StillDetected;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsClassAndForm;

    // ---- Wurzel-Erkennung ueber die Klassenkette (Verdacht 297) ----------
    [Test] procedure Test_TdmPrefixWithoutBinding_KnownGap_Reported;
    [Test] procedure Test_TdmPrefixWithBinding_Silent;
    [Test] procedure Test_DerivedDataModuleClassName_Silent;
    [Test] procedure Test_RealUiFormWithBinding_StillDetected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  System.IOUtils,
  uDfmParser, uComponentGraph, uAstNode, uParser2, uFormBinder,
  uDfmDbInUiForm;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
// Ohne Bindung - prueft die RUECKFALL-Ebene (Klassenname). Alle
// Bestandstests laufen darueber und muessen unveraendert gruen bleiben:
// genau das ist die Zusage, dass ein Lauf ohne .pas nicht schlechter wird.
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmDbInUiFormDetector.Analyze(Graph, nil, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function RunWithPas(const DfmSrc, PasSrc: string): TObjectList<TLeakFinding>;
// MIT Bindung - prueft die Vorrang-Ebene (Klassenkette der .pas). Der
// Aufbau spiegelt uDfmAnalysisRunner Block 3-5: .pas parsen, binden,
// Detektor mit Bindung rufen. Ohne RepoIndex, also TFormBinder.Bind statt
// BindWithParents - fuer eine Wurzel, die DIREKT von TDataModule erbt,
// stoppt die Aufloesung ohnehin sofort (Parent bleibt nil, der Ahn steht
// in FormClass.TypeRef).
var
  DfmParser : TDfmParser;
  Graph     : TComponentGraph;
  PasParser : TParser2;
  UnitNode  : TAstNode;
  Binding   : TFormBinding;
  Tmp, Fn   : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_dbui_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(Tmp);
  try
    Fn := TPath.Combine(Tmp, 'uMain.pas');
    TFile.WriteAllText(Fn, PasSrc, TEncoding.UTF8);

    DfmParser := TDfmParser.Create;
    try
      Graph := DfmParser.ParseSource(DfmSrc);
    finally
      DfmParser.Free;
    end;

    PasParser := TParser2.Create;
    try
      UnitNode := PasParser.ParseFile(Fn);
    finally
      PasParser.Free;
    end;

    Binding := TFormBinder.Bind(Graph, UnitNode);
    try
      TDfmDbInUiFormDetector.Analyze(Graph, Binding, 'uMain.dfm', Result);
    finally
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

procedure TTestDfmDbInUiForm.Test_AdoConnectionOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_AdoQueryOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DataSourceOnForm_Detected;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object ds: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_AllThreeOnForm_AllReported;
const DFM =
  'object frmOrder: TOrderForm'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  '  object ds: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DbComponentsOnDataModule_Silent;
// Klassen-Name endet auf 'DataModule' -> Detektor schweigt (das ist
// genau das gewuenschte Pattern).
const DFM =
  'object dm: TDataModule'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  '  object q: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DbComponentsOnNamedDataModule_Silent;
// 'TOrderDataModule' endet auch auf 'DataModule' -> Whitelist.
const DFM =
  'object dmOrder: TOrderDataModule'#13#10 +
  '  object conn: TADOConnection end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_OnlyUiComponents_NoFinding;
const DFM =
  'object frmMain: TMainForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object btn: TButton end'#13#10 +
  '    object ed: TEdit end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_NestedDbComponent_StillDetected;
// DB-Komponente versteckt sich unter einem Panel - EnumerateAll laeuft
// rekursiv, wird trotzdem gefunden.
const DFM =
  'object frm: TMainForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object q: TADOQuery end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm));
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_Finding_KindAndSeverity;
const DFM =
  'object frm: TMainForm object conn: TADOConnection end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmDbInUiForm, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_Finding_MissingVarMentionsClassAndForm;
const DFM =
  'object frmMain: TMainForm object conn: TADOConnection end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'conn');
    Assert.Contains(F[0].MissingVar, 'TADOConnection');
    Assert.Contains(F[0].MissingVar, 'TMainForm');
  finally F.Free; end;
end;

{ --- Wurzel-Erkennung ueber die Klassenkette -------------------------------- }
//
// Verdacht 297 des Voll-Reviews, am Korpus bestaetigt: der Suffix-Test
// 'Klassenname endet auf DataModule' erkannte 6 von 41 direkten
// TDataModule-Nachfahren. Seit dem 2026-09-12 entscheidet zuerst die
// aufgeloeste Klassenkette; der Name ist nur noch Rueckfall.
//
// Die vier Tests bilden ein Kreuz: Praefix-Konvention ohne und mit
// Bindung (der Unterschied IST der Fix), ein Name, den weder Suffix noch
// Praefix trifft, und die Gegenprobe, dass eine echte UI-Form auch mit
// Bindung gemeldet wird.

procedure TTestDfmDbInUiForm.Test_TdmPrefixWithoutBinding_KnownGap_Reported;
// OHNE .pas bleibt es beim Namen - und 'TdmMain' endet nicht auf
// 'DataModule'. Der Fund ist hier KEIN Mangel, sondern die dokumentierte
// Grenze eines Laufs ohne aufloesbare Klasse. Der Test haelt fest, dass
// der Rueckfall unveraendert arbeitet: waere er strenger geworden, wuerde
// diese Zeile rot.
const DFM =
  'object dmMain: TdmMain'#13#10 +
  '  object qryPersons: TADOQuery'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm),
    'ohne Bindung entscheidet allein der Klassenname');
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_TdmPrefixWithBinding_Silent;
// DERSELBE DFM, jetzt mit der .pas daneben: die Kette endet in
// TDataModule, also schweigt der Detektor. Das ist der Fix in einer Zeile
// Unterschied zum Test darueber.
//
// Korpus-Bezug: 21 der 23 Funde auf Tdm-Wurzeln standen auf genau dieser
// Konstellation (TdmMain), und ihr Meldetext widersprach sich selbst -
// 'move to a TDataModule', wo bereits eines vorlag.
const DFM =
  'object dmMain: TdmMain'#13#10 +
  '  object qryPersons: TADOQuery'#13#10 +
  '  end'#13#10 +
  'end';
const PAS =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, Data.Win.ADODB;'#13#10 +
  'type'#13#10 +
  '  TdmMain = class(TDataModule)'#13#10 +
  '    qryPersons: TADOQuery;'#13#10 +
  '  end;'#13#10 +
  'var dmMain: TdmMain;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithPas(DFM, PAS);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm),
    'die Klassenkette endet in TDataModule - kein Architektur-Smell');
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_DerivedDataModuleClassName_Silent;
// Ein Name, den WEDER der Suffix noch eine Praefix-Heuristik traefe.
// 'TEntitiesModule' steht so im Korpus; mit der Kette braucht es keine
// Namensregel mehr.
const DFM =
  'object EntitiesModule: TEntitiesModule'#13#10 +
  '  object conn: TFDConnection'#13#10 +
  '  end'#13#10 +
  'end';
const PAS =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, FireDAC.Comp.Client;'#13#10 +
  'type'#13#10 +
  '  TEntitiesModule = class(TDataModule)'#13#10 +
  '    conn: TFDConnection;'#13#10 +
  '  end;'#13#10 +
  'var EntitiesModule: TEntitiesModule;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithPas(DFM, PAS);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDbInUiForm),
    'die Kette traegt auch dort, wo keine Namenskonvention greift');
  finally F.Free; end;
end;

procedure TTestDfmDbInUiForm.Test_RealUiFormWithBinding_StillDetected;
// DIE GEGENPROBE, ohne die der Fix wertlos waere: eine echte Form mit
// aufgeloester Kette (TForm, nicht TDataModule) wird weiter gemeldet.
// Ohne diesen Test bliebe offen, ob die Bindung schlicht ALLES stumm
// schaltet.
const DFM =
  'object frmMain: TfrmMain'#13#10 +
  '  object qryPersons: TADOQuery'#13#10 +
  '  end'#13#10 +
  'end';
const PAS =
  'unit uMain;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms, Data.Win.ADODB;'#13#10 +
  'type'#13#10 +
  '  TfrmMain = class(TForm)'#13#10 +
  '    qryPersons: TADOQuery;'#13#10 +
  '  end;'#13#10 +
  'var frmMain: TfrmMain;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := RunWithPas(DFM, PAS);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDbInUiForm),
    'TForm-Kette: die Query gehoert weiterhin ins DataModule');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDbInUiForm);

end.
