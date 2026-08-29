unit uTestEngineApi;

// Tests fuer die Engine-Facade uEngineApi (TScanRequest/TScanResult/
// TAnalysisSession). End-to-End ueber echte Temp-Dateien.
//
// WICHTIG: Diese Tests fahren BEWUSST nur den Single-File-Pfad (ssSingleFile
// -> TStaticAnalyzer2.AnalyzeLeaks). Den REKURSIVEN Pfad (AnalyzeLeaksRecursive
// + DFM-Repo-/Symbol-Index-Build) NICHT, weil er im RESIDENTEN TestInsight-
// Prozess die IDE destabilisiert (2026-06-26 reproduziert: Tests gruen, danach
// Debugger-Exception + IDE-Hang). Das deckt sich mit Konzept_EngineApiSchnittstelle.md
// (G3: Engine nicht abgesichert fuer residente/eingebettete Mehrfach-Laeufe).
// Der Single-File-Pfad ist suite-erprobt (uTestComboChecks ruft AnalyzeLeaks
// auf Temp-Dateien). Die Facade leitet ssRecursive nur 1:1 an die Engine weiter;
// Produktiv (CLI/IDE) ist der rekursive Pfad bereits massiv abgedeckt.

interface

uses
  DUnitX.TestFramework,
  uEngineApi, uIgnoreList;

type
  [TestFixture]
  TTestEngineApi = class
  private
    FDir: string;
    function RunSingle(const ASrc, AProfile: string): TScanResult;
    // IgnoreList-Facade-Tests (ssProject): 2 Bug-Units + minimale .dproj.
    function BuildIgnoreFixture: string;
    function RunProject(const ADproj: string; AIgnore: TIgnoreList): TScanResult;
    procedure ResetEngineGlobals;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Init_HasSaneDefaults;
    // TFixtureFilter (2026-08-29): die Regel lag bis dahin im
    // CLI-Laeufer, jetzt in der Engine - hier ihr Vertrag.
    [Test] procedure FixtureFilter_AutoHidesOnlyKnownProfiles;
    [Test] procedure FixtureFilter_DropsFixturesKeepsProduction;
    [Test] procedure FixtureFilter_ReadErrorSurvivesFilter;
    [Test] procedure FixtureFilter_BaseDirAnchorsThePattern;
    // Upstream-Befund 6 (GITLAK, 28.08.)
    [Test] procedure IgnoreList_BrokenMaskDoesNotKillTheScan;
    [Test] procedure FindingAliases_MessageLineRuleId;
    [Test] procedure AnalyzeContext_DestroyFreesOwnedOnly;
    [Test] procedure AnalyzeSource_FindsBugInMemory;
    [Test] procedure AnalyzeSource_StampsVirtualName;
    [Test] procedure SingleFile_FindsSqlInjection;
    [Test] procedure NamedProfile_NarrowsOrEqualToAll;
    [Test] procedure WriteSarif_ProducesNonEmptyFile;
    [Test] procedure ReleaseFindings_TransfersOwnership;
    [Test] procedure Baseline_FiltersKnownFindings;
    [Test] procedure ResetEngineConfigDefaults_ClearsBaselineFingerprintMode;
    [Test] procedure SkipConfig_RespectsPresetConfig;
    [Test] procedure IgnoreList_NilDefault_ScansAllProjectFiles;
    [Test] procedure IgnoreList_SkipsMatchingFile;
    // G2-5-Hook (2026-08-25): der Vertrag "ReleaseTransientCaches leert
    // den prozessweiten Text-Cache" - gemessen ueber TransientCacheCount.
    // Faellt der Hook einem Refactoring zum Opfer, waechst das
    // 32-Bit-Plugin wieder auf das 1,3-GB-Plateau der Messreihe.
    [Test] procedure ReleaseTransientCaches_EmptiesTextCache;
  end;

implementation

uses
  System.SysUtils, System.Classes,   // TStringList - AcquireLines-Probe (G2-5-Test)
  System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAnalyzeContext, uAstFileCache, uFileTextCache, uSymbolReferenceIndex;

const
  // Garantiert MEHRERE Befunde, darunter einen, der auch unter der
  // Evidenz-Politik (K2 Stufe 1, uEvidenceTiering) lsError BLEIBT:
  //   * fkSQLInjection  - fcMedium seit jeher -> unter der Politik nur
  //     noch Warning (der alte Kommentar "fcHigh" war stale),
  //   * fkFormatMismatch - fcHigh + Katalog-Error ("%s %d" vs. 1 Arg,
  //     Muster aus uTestFormatMismatch) -> traegt die ErrorCount>=1-
  //     Zusicherungen dieser Fixture politik-fest.
  BUG_SRC =
    'unit SampleBug;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Run(const UserId: string);'#13#10 +
    'begin'#13#10 +
    '  Query.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId;'#13#10 +
    '  ShowMessage(Format(''%s ist %d Jahre alt'', [UserId]));'#13#10 +
    'end;'#13#10 +
    'end.';

{ Helpers }

procedure TTestEngineApi.ResetEngineGlobals;
begin
  // Globale Engine-Konfiguration auf Engine-Default zuruecksetzen, damit diese
  // Fixture keine anderen kontaminiert (Phase-0-Facade teilt den Prozess-State).
  //
  // Bewusst der ZENTRALE Riegel statt einer handgepflegten Auswahl: die
  // Vorgaengerfassung listete drei Globals auf und verpasste dadurch die
  // beiden Baseline-Globals, die spaeter dazukamen. Ueber
  // ResetEngineConfigDefaults erbt die Fixture jedes kuenftige Global
  // automatisch.
  uSCAConsts.ResetEngineConfigDefaults;
end;

function TTestEngineApi.RunSingle(const ASrc, AProfile: string): TScanResult;
// Schreibt ASrc in eine Temp-Datei und scannt sie ueber die Facade
// (ssSingleFile). Caller gibt das Ergebnis frei.
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
  Fn  : string;
begin
  Fn := TPath.Combine(FDir, 'SampleBug.pas');
  TFile.WriteAllText(Fn, ASrc, TEncoding.UTF8);
  Req := TScanRequest.Init;
  Req.Scope   := ssSingleFile;
  Req.Path    := Fn;
  Req.Profile := AProfile;
  Ses := TAnalysisSession.Create;
  try
    Result := Ses.Run(Req);
  finally
    Ses.Free;
  end;
end;

function TTestEngineApi.BuildIgnoreFixture: string;
// Schreibt zwei Bug-Units (je ein garantierter lsError-Befund, Muster BUG_SRC)
// plus eine minimale .dproj, die BEIDE als DCCReference listet. Liefert den
// .dproj-Pfad. Namen bewusst OHNE Test-Schema (uTest*/_Test), damit der
// eingebaute SkipTests-Filter der TIgnoreList hier nie mitspielt.
const
  DPROJ_XML =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DCCReference Include="KeptBug.pas"/>'#13#10 +
    '    <DCCReference Include="SkippedBug.pas"/>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '</Project>'#13#10;

  function BugUnit(const AName: string): string;
  begin
    Result :=
      'unit ' + AName + ';'#13#10 +
      'interface'#13#10 +
      'implementation'#13#10 +
      'procedure Run(const UserId: string);'#13#10 +
      'begin'#13#10 +
      '  Query.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId;'#13#10 +
      'end;'#13#10 +
      'end.';
  end;

begin
  TFile.WriteAllText(TPath.Combine(FDir, 'KeptBug.pas'),
    BugUnit('KeptBug'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FDir, 'SkippedBug.pas'),
    BugUnit('SkippedBug'), TEncoding.UTF8);
  Result := TPath.Combine(FDir, 'Fixture.dproj');
  TFile.WriteAllText(Result, DPROJ_XML, TEncoding.UTF8);
end;

function TTestEngineApi.RunProject(const ADproj: string;
  AIgnore: TIgnoreList): TScanResult;
// Facade-Scan ueber die Projektliste (ssProject). BEWUSST nicht ssRecursive:
// der rekursive Pfad ist im residenten Test-Prozess tabu (s. Unit-Header).
// Der Listen-Pfad wendet dieselbe Req.IgnoreList an (uEngineApi, ignore.txt-
// Parity zum Verzeichnis-Walk) und ist als IDE-Bulk-Produktionspfad erprobt;
// FromDproj laeuft bereits 12x pro Suite (COM-Guard-Kommentar uProjectFiles).
// Die Facade uebernimmt KEINE Ownership an AIgnore - Caller gibt frei.
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
begin
  Req := TScanRequest.Init;
  Req.Scope      := ssProject;
  Req.Path       := ADproj;
  Req.IgnoreList := AIgnore;   // nil = Init-Default = bisheriges Verhalten
  Ses := TAnalysisSession.Create;
  try
    Result := Ses.Run(Req);
  finally
    Ses.Free;
  end;
end;

procedure TTestEngineApi.Setup;
begin
  ResetEngineGlobals;
  // Eigenes Verzeichnis JE LAUF (GUID), wie in den uebrigen acht Fixtures.
  // Der frueher feste Name 'sca_engineapi_test' war prozess-GETEILT: ein
  // zweiter oder haengengebliebener TestProject-Lauf (TestInsight ist
  // resident, s. Unit-Kopf) loeschte ihn in seinem TearDown mitten in
  // einen laufenden Test hinein. Folge waren zwei Phantom-Fehlschlaege
  // (2026-08-08): WriteSarif fand das Verzeichnis nicht mehr, und
  // Baseline_FiltersKnownFindings sah 4 statt 0 Funde, weil
  // TBaseline.Apply bei fehlender Datei still 0 liefert (uBaseline:234).
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_engineapi_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestEngineApi.TearDown;
begin
  ResetEngineGlobals;
  if (FDir <> '') and TDirectory.Exists(FDir) then
    try TDirectory.Delete(FDir, True); except end;
end;

{ Tests }

procedure TTestEngineApi.Init_HasSaneDefaults;
var R: TScanRequest;
begin
  R := TScanRequest.Init;
  Assert.AreEqual<Integer>(Ord(ssRecursive), Ord(R.Scope), 'Default-Scope = ssRecursive');
  Assert.AreEqual<string>('', R.Profile, 'Default-Profil = '''' (alle Detektoren)');
  Assert.AreEqual<Integer>(Ord(lsHint), Ord(R.MinSeverity));
  Assert.AreEqual<Integer>(Ord(fcMedium), Ord(R.MinConfidence));
  Assert.IsFalse(R.UsesCheck);
end;

procedure TTestEngineApi.FindingAliases_MessageLineRuleId;
// Phase-1-Datengrenze: Message (Alias auf MissingVar, lesend+schreibend),
// LineInt (LineNumber als Integer), ResolvedRuleId (SCAxxx via Catalog).
var L: TLeakFinding;
begin
  L := TLeakFinding.Create;
  try
    L.MissingVar := 'leaked X';
    L.LineNumber := '42';
    L.SetKind(fkSQLInjection);
    Assert.AreEqual<string>('leaked X', L.Message, 'Message aliast MissingVar (lesend)');
    Assert.AreEqual<Integer>(42, L.LineInt, 'LineInt parst LineNumber');
    Assert.IsTrue(L.ResolvedRuleId.StartsWith('SCA'),
      'ResolvedRuleId loest die SCAxxx-ID ueber den Catalog auf');
    L.Message := 'updated';
    Assert.AreEqual<string>('updated', L.MissingVar, 'Message-Setter schreibt MissingVar');
  finally
    L.Free;
  end;
end;

procedure TTestEngineApi.AnalyzeContext_DestroyFreesOwnedOnly;
// Phase-3-Foundation (Konzept_D2): TAnalyzeContext.Destroy gibt die BESESSENEN
// Instanzen frei (AstFileCache/SymbolRefIndex/DfmRepoIndex), fasst aber die nur
// REFERENZIERTEN (FileTextCache/DetectorTimings) NICHT an.
var
  Ctx : TAnalyzeContext;
  Ftc : TFileTextCache;
begin
  // try/finally nachgezogen 2026-08-16: der Parser sieht diese Routine erst
  // seit dem Exit-/goto-Fix vollstaendig, und SCA002 hatte recht - warf eine
  // der Zuweisungen, leckten beide Objekte.
  Ftc := nil;
  Ctx := nil;
  try
    Ftc := TFileTextCache.Create;                        // separat besessen
    Ctx := TAnalyzeContext.Create;
    Ctx.AstFileCache   := TAstFileCache.Create;          // owned -> Destroy frees
    Ctx.SymbolRefIndex := TSymbolReferenceIndex.Create;  // owned -> Destroy frees
    Ctx.FileTextCache  := Ftc;                           // nur referenziert
    FreeAndNil(Ctx);     // Kern des Tests: darf nicht crashen, gibt nur die
                         // besessenen frei - und muss VOR Ftc.Free laufen
    Assert.Pass('Context-Destroy gibt nur besessene Instanzen frei');
  finally
    Ctx.Free;            // nur belegt, wenn eine Zuweisung oben warf
    Ftc.Free;            // kein Double-Free -> Ctx hat Ftc nicht angefasst
  end;
end;

procedure TTestEngineApi.AnalyzeSource_FindsBugInMemory;
// Phase 2: In-Memory-Scan eines Quelltext-Strings (ohne Datei-Pfad).
var Res: TScanResult;
begin
  Res := AnalyzeSource(BUG_SRC);
  try
    Assert.IsTrue(Res.FindingCount >= 1, 'In-Memory-Scan findet den Bug');
    Assert.IsTrue(Res.ErrorCount   >= 1,
      'FormatMismatch ist lsError+fcHigh - ueberlebt die Evidenz-Politik');
  finally Res.Free; end;
end;

procedure TTestEngineApi.AnalyzeSource_StampsVirtualName;
// ssSource + Path = logischer Name -> Findings tragen den (Editor-Lint).
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
  Res : TScanResult;
begin
  Req := TScanRequest.Init;
  Req.Scope  := ssSource;
  Req.Source := BUG_SRC;
  Req.Path   := 'Virtual\Buffer.pas';
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try
      Assert.IsTrue(Res.FindingCount >= 1, 'In-Memory-Scan findet den Bug');
      Assert.AreEqual<string>('Virtual\Buffer.pas', Res.Findings[0].FileName,
        'logischer Name wird auf die Findings gestempelt');
    finally Res.Free; end;
  finally Ses.Free; end;
end;

procedure TTestEngineApi.SingleFile_FindsSqlInjection;
var Res: TScanResult;
begin
  Res := RunSingle(BUG_SRC, '');
  try
    Assert.IsTrue(Res.FindingCount >= 1, 'mind. ein Befund erwartet');
    Assert.IsTrue(Res.ErrorCount   >= 1,
      'FormatMismatch ist lsError+fcHigh - ueberlebt die Evidenz-Politik');
  finally Res.Free; end;
end;

procedure TTestEngineApi.NamedProfile_NarrowsOrEqualToAll;
var
  Res: TScanResult;
  CountAll, CountSec: Integer;
begin
  Res := RunSingle(BUG_SRC, '');            // alle Detektoren
  try CountAll := Res.FindingCount; finally Res.Free; end;

  Res := RunSingle(BUG_SRC, 'security');    // benanntes Profil = Teilmenge
  try CountSec := Res.FindingCount; finally Res.Free; end;

  // Ein benanntes Profil ist immer Teilmenge von "alle" -> beweist, dass
  // TRuleCatalog.GetProfile korrekt in den Filter verdrahtet ist.
  Assert.IsTrue(CountSec <= CountAll,
    Format('security (%d) darf nicht mehr finden als alle (%d)', [CountSec, CountAll]));
end;

procedure TTestEngineApi.WriteSarif_ProducesNonEmptyFile;
var
  Res     : TScanResult;
  SarifFn : string;
begin
  Res := RunSingle(BUG_SRC, '');
  try
    SarifFn := TPath.Combine(FDir, 'out.sarif');
    Res.WriteSarif(SarifFn);
    Assert.IsTrue(TFile.Exists(SarifFn), 'SARIF-Datei wurde geschrieben');
    Assert.IsTrue(TFile.GetSize(SarifFn) > 0, 'SARIF-Datei ist nicht leer');
  finally Res.Free; end;
end;

procedure TTestEngineApi.ReleaseFindings_TransfersOwnership;
var
  Res : TScanResult;
  L   : TObjectList<TLeakFinding>;
  N   : Integer;
begin
  Res := RunSingle(BUG_SRC, '');
  try
    N := Res.FindingCount;
    L := Res.ReleaseFindings;     // Ownership-Uebergabe
  finally
    Res.Free;                     // darf L NICHT mitfreigeben
  end;
  try
    Assert.IsNotNull(L, 'ReleaseFindings liefert die Liste');
    Assert.AreEqual<Integer>(N, L.Count, 'Liste nach Res.Free noch gueltig');
  finally
    L.Free;
  end;
end;

procedure TTestEngineApi.ResetEngineConfigDefaults_ClearsBaselineFingerprintMode;
// Regressionsnetz fuer den Reset-VERTRAG: ResetEngineConfigDefaults sagt
// zu, ALLE Scan-Konfigurations-Globals dieser Unit zurueckzusetzen. Die
// beiden Baseline-Globals fehlten dort (2026-08-08) - der Fingerprint
// haette sonst an Prozess-Restzustand gehangen. Faellt der naechste
// vergessene Global auf, faellt zuerst dieser Test.
begin
  uSCAConsts.BaselinePathFingerprint := True;
  uSCAConsts.BaselineFingerprintRoot := TPath.GetTempPath;   // irgendein Wert
  uSCAConsts.ResetEngineConfigDefaults;
  Assert.IsFalse(uSCAConsts.BaselinePathFingerprint,
    'Pfad-Modus faellt auf den Default zurueck');
  Assert.AreEqual<string>('', uSCAConsts.BaselineFingerprintRoot,
    'Fingerprint-Wurzel wird geleert');
end;

procedure TTestEngineApi.Baseline_FiltersKnownFindings;
// Phase-4-Vorbereitung: Run() filtert request-driven gegen eine Baseline
// (BaselinePath) und kann eine neue schreiben (WriteBaselinePath). 1. Lauf
// schreibt die Baseline aus den BUG-Findings; 2. Lauf mit derselben Baseline
// -> dieselben Findings sind "bekannt" -> 0 neue.
var
  Req        : TScanRequest;
  Ses        : TAnalysisSession;
  Res        : TScanResult;
  Fn, BaseFn : string;
  CountFresh : Integer;
begin
  Fn     := TPath.Combine(FDir, 'SampleBug.pas');
  BaseFn := TPath.Combine(FDir, 'base.json');
  TFile.WriteAllText(Fn, BUG_SRC, TEncoding.UTF8);

  // 1) Scan + Baseline schreiben
  Req := TScanRequest.Init;
  Req.Scope             := ssSingleFile;
  Req.Path              := Fn;
  Req.WriteBaselinePath := BaseFn;
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try CountFresh := Res.FindingCount; finally Res.Free; end;
  finally Ses.Free; end;
  Assert.IsTrue(CountFresh >= 1, 'Erst-Scan findet den Bug');
  Assert.IsTrue(TFile.Exists(BaseFn), 'Baseline-Datei wurde geschrieben');
  // INHALT pruefen, nicht nur die Existenz: eine leere Baseline und ein
  // Fingerprint-Mismatch sehen am Ende beide wie "0 gedroppt" aus. Ohne
  // diese Zusicherung kostete die Unterscheidung 2026-08-08 eine ganze
  // Diagnose-Runde.
  Assert.Contains(TFile.ReadAllText(BaseFn, TEncoding.UTF8), '"fingerprint"',
    'Baseline enthaelt Fingerprints (nicht leer geschrieben)');

  // 2) Scan mit Baseline -> bekannte Findings werden gefiltert
  Req := TScanRequest.Init;
  Req.Scope        := ssSingleFile;
  Req.Path         := Fn;
  Req.BaselinePath := BaseFn;
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try
      Assert.AreEqual<Integer>(0, Res.FindingCount,
        'alle Findings sind in der Baseline -> 0 neue');
    finally Res.Free; end;
  finally Ses.Free; end;
end;

procedure TTestEngineApi.SkipConfig_RespectsPresetConfig;
// Phase-4-Vorbereitung: Req.SkipConfig=true -> Run wendet KEINE Config an, der
// vom Consumer gesetzte globale Detektor-Filter bleibt stehen (IDE konfiguriert
// selbst via SetupForRun). Beweis: nur fkTodoComment aktiviert -> der SQL-Bug
// (BUG_SRC, kein TODO) wird NICHT gefunden. Ohne SkipConfig wuerde Run auf []
// (alle Detektoren) zuruecksetzen und den SQL-Bug finden.
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
  Res : TScanResult;
  Fn  : string;
begin
  Fn := TPath.Combine(FDir, 'SampleBug.pas');
  TFile.WriteAllText(Fn, BUG_SRC, TEncoding.UTF8);
  uSCAConsts.DetectorEnabledKinds := [fkTodoComment];   // restriktiv, kein SQL
  Req := TScanRequest.Init;
  Req.Scope      := ssSingleFile;
  Req.Path       := Fn;
  Req.SkipConfig := True;                                // Config NICHT anfassen
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try
      Assert.AreEqual<Integer>(0, Res.FindingCount,
        'SkipConfig laesst [fkTodoComment]-Filter stehen -> SQL-Bug nicht gefunden');
    finally Res.Free; end;
  finally Ses.Free; end;
end;

procedure TTestEngineApi.IgnoreList_NilDefault_ScansAllProjectFiles;
// TP-Gegenprobe fuer das additive Facade-Feld Req.IgnoreList: Init liefert
// nil, und ein Request OHNE IgnoreList verhaelt sich unveraendert - BEIDE
// Projekt-Dateien werden gescannt und liefern ihren SQL-Injection-Befund.
var
  Res  : TScanResult;
  F    : TLeakFinding;
  Kept, Skipped : Integer;
begin
  Assert.IsNull(TScanRequest.Init.IgnoreList,
    'Init-Default = nil (kein Filter, bisheriges Verhalten)');
  Res := RunProject(BuildIgnoreFixture, nil);
  try
    Kept := 0; Skipped := 0;
    for F in Res.Findings do
    begin
      if F.FileName.EndsWith('KeptBug.pas', True)    then Inc(Kept);
      if F.FileName.EndsWith('SkippedBug.pas', True) then Inc(Skipped);
    end;
    Assert.IsTrue(Kept >= 1,    'KeptBug.pas liefert seinen Befund');
    Assert.IsTrue(Skipped >= 1, 'ohne IgnoreList wird SkippedBug.pas mitgescannt');
  finally
    Res.Free;
  end;
end;

procedure TTestEngineApi.IgnoreList_SkipsMatchingFile;
// Fix-Test: Req.IgnoreList wird an den Scan-Pfad durchgereicht - die
// gematchte Datei faellt KOMPLETT aus dem Ergebnis (auch kein SCA194-
// Orphan: der ssProject-Pfad reicht dieselbe Liste an Detect weiter).
// Die nicht gematchte Datei liefert weiterhin ihren Befund (Monotonie:
// der Filter unterdrueckt nur, er erzeugt nichts Neues).
var
  Res   : TScanResult;
  F     : TLeakFinding;
  Ign   : TIgnoreList;
  IgnFn : string;
  Kept, Skipped : Integer;
begin
  IgnFn := TPath.Combine(FDir, 'ignore.txt');
  TFile.WriteAllText(IgnFn, 'SkippedBug.pas'#13#10, TEncoding.UTF8);
  Ign := TIgnoreList.Create;
  try
    Ign.SkipTests := False;        // nur das explizite Muster soll wirken
    Ign.LoadFromFile(IgnFn);
    Res := RunProject(BuildIgnoreFixture, Ign);
    try
      Kept := 0; Skipped := 0;
      for F in Res.Findings do
      begin
        if F.FileName.EndsWith('KeptBug.pas', True)    then Inc(Kept);
        if F.FileName.EndsWith('SkippedBug.pas', True) then Inc(Skipped);
      end;
      Assert.IsTrue(Kept >= 1,
        'nicht gematchte Datei liefert weiterhin ihren Befund');
      Assert.AreEqual<Integer>(0, Skipped,
        'gematchte Datei wird uebersprungen - kein einziges Finding');
    finally
      Res.Free;
    end;
  finally
    Ign.Free;
  end;
end;

procedure TTestEngineApi.ReleaseTransientCaches_EmptiesTextCache;
// KEIN ssRecursive: der Unit-Kopf verbietet den rekursiven Pfad im
// residenten TestInsight-Prozess ausdruecklich (IDE-Hang, 2026-06-26
// reproduziert) - die Gegenpruefung hat den Verstoss gefangen (V3).
// Stattdessen ssSingleFile (der stabile Pfad dieser Datei), und der
// Cache wird DETERMINISTISCH ueber AcquireLines gefuellt statt ueber
// die Suppression-Phase, die nur bei Funden liest.
var
  Dir    : string;
  Datei  : string;
  Ses    : TAnalysisSession;
  Req    : TScanRequest;
  Res    : TScanResult;
  Lines  : TStringList;
  Cached : Boolean;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca_hook_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(Dir);
  try
    Datei := TPath.Combine(Dir, 'u.pas');
    TFile.WriteAllText(Datei,
      'unit u;'#13#10'interface'#13#10'implementation'#13#10 +
      'procedure P; begin end;'#13#10'end.');
    // Ein Single-File-Lauf stellt sicher, dass die Engine ihren
    // prozessweiten Cache angelegt hat (Scan-Start erzeugt ihn).
    Req := TScanRequest.Init;
    Req.Scope := ssSingleFile;
    Req.Path  := Datei;
    Ses := TAnalysisSession.Create;
    try
      Res := Ses.Run(Req);
      Res.Free;
    finally
      Ses.Free;
    end;
    // Cache nachweisbar fuellen: Acquire ueber den GLOBALEN Cache
    // (ACache=nil). OwnedByCache=True heisst, der Eintrag liegt drin.
    Lines := AcquireLines(Datei, Cached, nil);
    Assert.IsNotNull(Lines, 'Temp-Datei muss lesbar sein');
    ReleaseLines(Lines, Cached);
    Assert.IsTrue(Cached,
      'Vorbedingung: der Eintrag muss im PROZESSWEITEN Cache liegen - ' +
      'liegt er nicht, prueft der Test nichts (gFileTextCache fehlt?)');
    Assert.IsTrue(TransientCacheCount > 0, 'Vorbedingung: Cache gefuellt');
    TAnalysisSession.ReleaseTransientCaches;
    Assert.AreEqual<Integer>(0, TransientCacheCount,
      'der Hook muss den Cache leeren (G2-5)');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ ---- TFixtureFilter ---- }

// Zu den woertlichen C:-Pfaden in diesem Block: sie SIND die
// Testdaten - der Filter entscheidet allein anhand von Pfadsegmenten
// und der Scanwurzel, also muessen beide im Test stehen. Die Marker
// sind bewusst zeilengenau und nicht dateiweit: die uebrigen Tests
// dieser Unit fahren ueber ECHTE Temp-Dateien, dort waere ein
// hartkodierter Pfad ein echter Befund, den ein Dateimarker
// verdecken wuerde.

function MakeFindingFor(const AFile: string;
  AKind: TFindingKind): TLeakFinding;
// Minimaler Fund fuer die Filter-Tests: nur Datei und Art zaehlen, der
// Filter sieht nichts anderes an.
begin
  Result          := TLeakFinding.Create;
  Result.FileName := AFile;
  Result.SetKind(AKind);
end;


procedure TTestEngineApi.FixtureFilter_AutoHidesOnlyKnownProfiles;
// Die Profil-Liste ist ABSICHTLICH explizit. Ein
// "alles ausser strict"-Ansatz haette jedes kuenftige Profil
// stillschweigend zum Filtern gebracht - dieser Test faellt um, wenn
// jemand die Logik umdreht.
begin
  Assert.IsTrue(TFixtureFilter.AutoHidesFixtures('default'),
    'default filtert Fixtures automatisch');
  Assert.IsTrue(TFixtureFilter.AutoHidesFixtures('selftest-quiet'),
    'selftest-quiet ebenfalls (Dogfooding ohne Fixture-Rauschen)');
  Assert.IsFalse(TFixtureFilter.AutoHidesFixtures('strict'),
    'strict NICHT - wer strict faehrt, will alles sehen');
  Assert.IsFalse(TFixtureFilter.AutoHidesFixtures(''),
    'kein Profil -> nicht filtern');
  Assert.IsFalse(TFixtureFilter.AutoHidesFixtures('security'),
    'ein anderes Profil filtert nicht, solange es nicht gelistet ist');
end;

procedure TTestEngineApi.FixtureFilter_DropsFixturesKeepsProduction;
// Der Grundfall: ein Fund in uTestFoo.pas geht, einer in uFoo.pas
// bleibt. Zusaetzlich der Nebenzweck von ADroppedFiles - der
// CLI-Laeufer zeigt die Namen an, weil "*Demo.pas" auch ein Name ist,
// den ein Neuanwender fuer sein eigenes Projekt waehlt.
var
  F     : TObjectList<TLeakFinding>;
  Namen : TStringList;
  n     : Integer;
begin
  F     := TObjectList<TLeakFinding>.Create(True);
  Namen := TStringList.Create;
  try
    // noinspection HardcodedPath
    F.Add(MakeFindingFor('C:\repo\tests\uTestFoo.pas', fkMemoryLeak));
    // noinspection HardcodedPath
    F.Add(MakeFindingFor('C:\repo\src\uFoo.pas', fkMemoryLeak));
    // noinspection HardcodedPath
    n := TFixtureFilter.Apply(F, 'C:\repo', Namen);
    Assert.AreEqual<Integer>(1, n, 'genau der Fixture-Fund faellt');
    Assert.AreEqual<Integer>(1, F.Count, 'der Produktionsfund bleibt');
    Assert.AreEqual('uFoo.pas', ExtractFileName(F[0].FileName),
      'und zwar der richtige');
    Assert.AreEqual<Integer>(1, Namen.Count,
      'der gedroppte Dateiname wird gemeldet');
  finally
    Namen.Free;
    F.Free;
  end;
end;

procedure TTestEngineApi.FixtureFilter_ReadErrorSurvivesFilter;
// DIE REGEL, DIE BEIM UMBAU LEICHT VERLORENGEHT: ein Lesefehler ist
// eine Aussage ueber die VOLLSTAENDIGKEIT des Laufs, kein Befund - kein
// Profil darf ihn wegfiltern. Ohne diesen Test meldet ein Scan, der
// halbe Verzeichnisse nicht lesen konnte, stillschweigend "sauber".
var
  F : TObjectList<TLeakFinding>;
  n : Integer;
begin
  F := TObjectList<TLeakFinding>.Create(True);
  try
    F.Add(MakeFindingFor('C:\repo\tests\uTestFoo.pas', fkFileReadError));
    // noinspection HardcodedPath
    F.Add(MakeFindingFor('C:\repo\tests\uTestBar.pas', fkMemoryLeak));
    n := TFixtureFilter.Apply(F, 'C:\repo');
    Assert.AreEqual<Integer>(1, n, 'nur der normale Fund faellt');
    Assert.AreEqual<Integer>(1, F.Count, 'der Lesefehler bleibt stehen');
    Assert.AreEqual<Integer>(Ord(fkFileReadError), Ord(F[0].Kind),
      'und zwar er selbst, nicht der andere');
  finally
    F.Free;
  end;
end;

procedure TTestEngineApi.FixtureFilter_BaseDirAnchorsThePattern;
// Die Scanwurzel verankert die Muster. Liegt der Scan UNTERHALB eines
// Pfades, der zufaellig "tests" heisst, darf das nicht den ganzen Lauf
// wegfiltern - sonst meldet ein Scan von C:\tests\meinprojekt
// gar nichts.
var
  F : TObjectList<TLeakFinding>;
begin
  F := TObjectList<TLeakFinding>.Create(True);
  try
    // noinspection HardcodedPath
    F.Add(MakeFindingFor('C:\tests\meinprojekt\src\uFoo.pas',
      fkMemoryLeak));
    // noinspection HardcodedPath
    TFixtureFilter.Apply(F, 'C:\tests\meinprojekt');
    Assert.AreEqual<Integer>(1, F.Count,
      'das tests-Segment liegt OBERHALB der Scanwurzel und zaehlt nicht');
  finally
    F.Free;
  end;
end;

procedure TTestEngineApi.IgnoreList_BrokenMaskDoesNotKillTheScan;
// UPSTREAM-BEFUND 6 (GITLAK): System.Masks wirft EMaskException bei
// unabgeschlossenem [, leerem [], fuehrendem - in einer Menge und ab
// 31 Wildcards. IsIgnored laeuft je Datei UND je Verzeichnis im
// per-Eintrag-except des Verzeichnis-Walks - ein Muster wie
// Backup[1.pas liess damit jede .pas UND jede Rekursion ausfallen.
// Der Scan lief durch, meldete null Funde und endete mit Code 0:
// nichts unterschied "sauber" von "nicht angesehen".
const
  DATEI = 'C:\repo\uFoo.pas';
  ECHTE = 'C:\repo\uEcht.pas';
var
  Liste : TIgnoreList;
  Pfad  : string;
begin
  Pfad := TPath.Combine(TPath.GetTempPath, 'sca-ignore-broken.txt');
  Liste := TIgnoreList.Create;
  try
    TFile.WriteAllText(Pfad,
      'Backup[1.pas' + sLineBreak + 'uEcht.pas');
    Liste.LoadFromFile(Pfad);

    // Wirft der Aufruf, faellt der Test mit genau dieser Exception -
    // vor dem Fix war es EMaskException, und im Walk verschluckte sie
    // das per-Eintrag-except.
    Assert.IsFalse(Liste.IsIgnored(DATEI),
      'und es darf erst recht nicht ALLES treffen');
    Assert.IsTrue(Liste.IsIgnored(ECHTE),
      'das gueltige Muster daneben wirkt weiterhin');
  finally
    Liste.Free;
    if TFile.Exists(Pfad) then TFile.Delete(Pfad);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEngineApi);

end.
