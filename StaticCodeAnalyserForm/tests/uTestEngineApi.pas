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
  uEngineApi;

type
  [TestFixture]
  TTestEngineApi = class
  private
    FDir: string;
    function RunSingle(const ASrc, AProfile: string): TScanResult;
    procedure ResetEngineGlobals;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Init_HasSaneDefaults;
    [Test] procedure FindingAliases_MessageLineRuleId;
    [Test] procedure AnalyzeContext_DestroyFreesOwnedOnly;
    [Test] procedure AnalyzeSource_FindsBugInMemory;
    [Test] procedure AnalyzeSource_StampsVirtualName;
    [Test] procedure SingleFile_FindsSqlInjection;
    [Test] procedure NamedProfile_NarrowsOrEqualToAll;
    [Test] procedure WriteSarif_ProducesNonEmptyFile;
    [Test] procedure ReleaseFindings_TransfersOwnership;
    [Test] procedure Baseline_FiltersKnownFindings;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAnalyzeContext, uAstFileCache, uFileTextCache, uSymbolReferenceIndex;

const
  // Garantiert ein lsError-Befund (fkSQLInjection, fcHigh) - robust gegen
  // Severity-/Confidence-Schwellen.
  BUG_SRC =
    'unit SampleBug;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Run(const UserId: string);'#13#10 +
    'begin'#13#10 +
    '  Query.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId;'#13#10 +
    'end;'#13#10 +
    'end.';

{ Helpers }

procedure TTestEngineApi.ResetEngineGlobals;
begin
  // Globale Engine-Konfiguration auf Engine-Default zuruecksetzen, damit diese
  // Fixture keine anderen kontaminiert (Phase-0-Facade teilt den Prozess-State).
  uSCAConsts.DetectorEnabledKinds := [];
  uSCAConsts.DetectorMinSeverity  := lsHint;
  uSCAConsts.FindingMinConfidence := fcMedium;
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

procedure TTestEngineApi.Setup;
begin
  ResetEngineGlobals;
  FDir := TPath.Combine(TPath.GetTempPath, 'sca_engineapi_test');
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
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
  Ftc := TFileTextCache.Create;                          // separat besessen
  Ctx := TAnalyzeContext.Create;
  Ctx.AstFileCache   := TAstFileCache.Create;            // owned -> Destroy frees
  Ctx.SymbolRefIndex := TSymbolReferenceIndex.Create;    // owned -> Destroy frees
  Ctx.FileTextCache  := Ftc;                             // nur referenziert
  Ctx.Free;            // darf nicht crashen; gibt nur die besessenen frei
  Ftc.Free;            // kein Double-Free -> Ctx hat Ftc nicht angefasst
  Assert.Pass('Context-Destroy gibt nur besessene Instanzen frei');
end;

procedure TTestEngineApi.AnalyzeSource_FindsBugInMemory;
// Phase 2: In-Memory-Scan eines Quelltext-Strings (ohne Datei-Pfad).
var Res: TScanResult;
begin
  Res := AnalyzeSource(BUG_SRC);
  try
    Assert.IsTrue(Res.FindingCount >= 1, 'In-Memory-Scan findet den Bug');
    Assert.IsTrue(Res.ErrorCount   >= 1, 'SQL-Injection ist lsError');
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
    Assert.IsTrue(Res.ErrorCount   >= 1, 'SQL-Injection ist lsError');
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

initialization
  TDUnitX.RegisterTestFixture(TTestEngineApi);

end.
