unit uTestDfmForbiddenClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmForbiddenClass = class
  public
    [Setup]    procedure SetUp;
    [TearDown] procedure TearDown;

    [Test] procedure Test_EmptyList_Silent;
    [Test] procedure Test_ListedClass_Detected;
    [Test] procedure Test_CaseInsensitiveMatch;
    [Test] procedure Test_NonListedClass_NoFinding;
    [Test] procedure Test_MultipleHits_AllReported;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsClassAndName;

    // --- Mehr Varianten ---
    [Test] procedure Test_NestedComponent_ListedClass_Detected;
    [Test] procedure Test_RootObject_ListedClass_Detected;
    [Test] procedure Test_MultipleListEntries_OnlyMatchReported;

    // --- Konfigurations-Kette (2026-08-19, SCA038-Belebung) ---
    [Test] procedure Test_IniChain_FillsGlobalList;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmForbiddenClass, uRepoSettings;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmForbiddenClassDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

procedure TTestDfmForbiddenClass.SetUp;
begin
  if Assigned(DfmForbiddenClasses) then
    DfmForbiddenClasses.Clear;
end;

procedure TTestDfmForbiddenClass.TearDown;
begin
  // Andere Tests koennen die globale Liste auch verwenden - sauber leeren.
  if Assigned(DfmForbiddenClasses) then
    DfmForbiddenClasses.Clear;
end;

procedure TTestDfmForbiddenClass.Test_EmptyList_Silent;
// Default: DfmForbiddenClasses leer -> Detektor inaktiv.
const DFM =
  'object Form: TForm'#13#10 +
  '  object l: TLabel end'#13#10 +
  '  object q: TQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_ListedClass_Detected;
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_CaseInsensitiveMatch;
// DfmForbiddenClasses.CaseSensitive = False -> 'TLABEL' matcht 'TLabel'.
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('tlabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_NonListedClass_NoFinding;
const DFM = 'object Form: TForm object e: TEdit end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_MultipleHits_AllReported;
const DFM =
  'object Form: TForm'#13#10 +
  '  object l1: TLabel end'#13#10 +
  '  object l2: TLabel end'#13#10 +
  '  object q: TQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  DfmForbiddenClasses.Add('TQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_Finding_KindAndSeverity;
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmForbiddenClass, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_Finding_MissingVarMentionsClassAndName;
const DFM = 'object Form: TForm object lblTitle: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'lblTitle');
    Assert.Contains(F[0].MissingVar, 'TLabel');
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_NestedComponent_ListedClass_Detected;
// Untergeordnete Komponente in einem Panel - Detektor laeuft rekursiv.
const DFM =
  'object Form: TForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object q: TQuery end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_RootObject_ListedClass_Detected;
// Das Root-Object selbst kann auch eine verbotene Klasse sein
// (z.B. TFrame, wenn man Frames sperrt).
const DFM = 'object Frame1: TFrame end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TFrame');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_MultipleListEntries_OnlyMatchReported;
// Forbidden-List enthaelt drei Klassen, nur eine kommt im DFM vor.
const DFM = 'object F: TForm object q: TQuery end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TQuery');
  DfmForbiddenClasses.Add('TADOConnection');
  DfmForbiddenClasses.Add('TIBQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure LadeIniKetteAusAppData;
// Der Messpunkt des INI-Ketten-Tests, als eigene Funktion: haelt den
// Test frei von try-in-try (NestedTry-Regel des Self-Scans) und
// macht sichtbar, WAS gemessen wird - exakt der Weg, den EXE, Plugin
// und CLI produktiv nehmen (Load + ApplyDetectorThresholds).
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    Settings.Load;
    Settings.ApplyDetectorThresholds;
  finally
    Settings.Free;
  end;
end;

procedure TTestDfmForbiddenClass.Test_IniChain_FillsGlobalList;
// Der einzige Test im Repo, der die INI-Kette DURCHMISST statt die
// Globale direkt zu setzen: [Components] ForbiddenClasses= ->
// TRepoSettings.Load -> ApplyDetectorThresholds -> Globale. Genau
// diese Kette fehlte bis 2026-08-19 - der Detektor war produktiv
// tot, waehrend alle Detektor-Tests gruen waren (sie fuhren an der
// Konfiguration vorbei). APPDATA wird auf ein Temp-Verzeichnis
// umgebogen, weil TIgnoreList.ConfigDir die Variable zur Laufzeit
// aufloest - so bleibt die echte Nutzer-INI unberuehrt.
const
  APPDATA_VAR = 'APPDATA';
var
  AltAppData : string;
  TmpWurzel  : string;
  CfgDir     : string;
begin
  AltAppData := GetEnvironmentVariable(APPDATA_VAR);
  TmpWurzel  := TPath.Combine(TPath.GetTempPath,
    'sca_test_components_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', ''));
  CfgDir := TPath.Combine(TmpWurzel, 'StaticCodeAnalyser');
  TDirectory.CreateDirectory(CfgDir);
  TFile.WriteAllText(TPath.Combine(CfgDir, 'analyser.ini'),
    '[Components]' + sLineBreak +
    'ForbiddenClasses=TLabel, tquery;TIBQuery' + sLineBreak);
  SetEnvironmentVariable(APPDATA_VAR, PChar(TmpWurzel));
  try
    LadeIniKetteAusAppData;
    Assert.AreEqual<Integer>(3, DfmForbiddenClasses.Count,
      'Komma UND Semikolon trennen, Leerraum wird getrimmt');
    Assert.IsTrue(DfmForbiddenClasses.IndexOf('TLabel') >= 0,
      'TLabel fehlt in der Globalen');
    Assert.IsTrue(DfmForbiddenClasses.IndexOf('TQUERY') >= 0,
      'Globale muss case-insensitiv finden (tquery aus der INI)');
    Assert.IsTrue(DfmForbiddenClasses.IndexOf('TIBQuery') >= 0,
      'TIBQuery (Semikolon-getrennt) fehlt');
  finally
    SetEnvironmentVariable(APPDATA_VAR, PChar(AltAppData));
    // TearDown leert die Globale ohnehin - hier trotzdem explizit,
    // damit kein Folge-Test den INI-Stand erbt.
    DfmForbiddenClasses.Clear;
  end;
  // Aufraeumen NACH dem try-Ende (Geschwister, keine Schachtelung).
  // noinspection EmptyExcept
  // Ein gesperrtes Temp-Verzeichnis darf das Testergebnis nicht
  // kippen; schlaegt eine Assertion fehl, bleibt das Verzeichnis
  // ohnehin zur Diagnose liegen (Exception ueberspringt diese Zeile).
  try TDirectory.Delete(TmpWurzel, True); except end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmForbiddenClass);

end.
