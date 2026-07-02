unit uEngineApi;

// ============================================================================
//  SCA.Engine - Public Facade (Phase 0)
// ============================================================================
//
// EINZIGE empfohlene Eintrittstuer fuer einen FREMD-Consumer (eigenes CLI,
// Build-Step, Editor-Lint, eingebettete GUI). Buendelt die ~8 Orchestrierungs-
// Schritte, die CLI/IDE/Form heute jeweils selbst zusammenstoepseln, hinter
// EINEM Aufruf:
//
//     Res := TAnalysisSession.Create.Run(Req);   // bzw. ScanRecursive(...)
//
// Minimal-Consumer (uses uEngineApi, uMethodd12;):
//
//     var Res: TScanResult;
//     begin
//       Res := ScanRecursive('C:\src', 'strict');
//       try
//         Res.WriteSarif('out.sarif');
//         // Res.Findings: TObjectList<TLeakFinding> zum Iterieren
//       finally
//         Res.Free;
//       end;
//     end;
//
// Konzept + Roadmap: Konzept_EngineApiSchnittstelle.md
//
// PHASE-0-GRENZEN (bewusst):
//   * Die Engine-Konfiguration laeuft intern noch ueber die globalen
//     Variablen in uSCAConsts/uLexer - die Facade KAPSELT sie nur (setzt
//     sie aus dem Request), entfernt sie nicht. Folge: weiterhin EIN Scan
//     pro Prozess (NICHT thread-safe). Mehrere TAnalysisSession-Instanzen
//     teilen denselben globalen State. Echte In-Process-Parallelitaet ist
//     Phase 3 (Konzept_D2_SingletonEntkopplung.md) - dann wandert der State
//     in die Session-Instanz; die hier definierte API-Form bleibt gleich.
//
// PROFIL-SEMANTIK:
//   * Req.Profile = ''          -> alle Detektoren (Engine-Default, [] = kein Filter)
//   * Req.Profile = 'default'   -> kuratiertes Default-Profil aus sca-rules.json
//   * Req.Profile = 'strict'/'security'/'bugs-only'/... -> benanntes Profil
//
// ============================================================================

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts, uIgnoreList;

const
  // Tool-Identitaet fuer SARIF tool.driver.name. Die Engine-Version kommt
  // aus uSCAConsts.SCA_VERSION.
  SCA_DEFAULT_TOOLNAME = 'StaticCodeAnalyser';

type
  // Was gescannt wird.
  TScanScope = (
    ssRecursive,    // Path = Wurzelordner, rekursiv
    ssSingleFile,   // Path = eine .pas-Datei
    ssFileList,     // Files = explizite Datei-Liste (Path = optionaler BaseDir)
    ssVcsChanged,   // nur per VCS geaenderte .pas/.dfm (Path = Repo, VcsRange optional)
    ssSource        // Source = In-Memory-Quelltext (kein Datei-Pfad; Path = optionaler Logical-Name)
  );

  // Vollstaendige Scan-Anfrage. Statt globale Variablen zu setzen, fuellt der
  // Consumer dieses Record und uebergibt es an TAnalysisSession.Run.
  TScanRequest = record
  public
    Scope          : TScanScope;
    Path           : string;            // Wurzel (ssRecursive) / Datei (ssSingleFile) / BaseDir
    Files          : TArray<string>;    // fuer ssFileList
    Source         : string;            // ssSource: In-Memory-Quelltext (statt Path)
    VcsRange       : string;            // ssVcsChanged: '' = Auto (Working-Tree vs Base); sonst 'shaA..shaB'
    Profile        : string;            // '' = alle Detektoren; sonst Profilname (s. Header)
    MinSeverity    : TLeakSeverity;     // Befunde unter dieser Schwelle werden verworfen
    MinConfidence  : TFindingConfidence;
    MaxFileBytes   : Integer;           // <= 0 -> Engine-Default (5 MB) beibehalten
    UsesCheck      : Boolean;           // teuren Unused-Uses-Detektor mitlaufen lassen
    AutoDiscover   : Boolean;           // Custom-Klassen waehrend des Scans entdecken
    IfdefDefines   : TArray<string>;    // {$IFDEF}-aware Parsing mit diesen Defines (leer = aus)
    CustomRulesPath: string;            // YAML mit Custom-Rules ('' = keine)
    BaselinePath   : string;            // Findings gegen diese Baseline-JSON filtern ('' = aus)
    WriteBaselinePath: string;          // aktuelle Findings als neue Baseline schreiben ('' = aus)
    ApplyRepoIni   : Boolean;           // true: repo analyser.ini laden + VOLL anwenden (8 Schwellen,
                                        // PathOverrides, Magic/Format-Listen, INI-Profil/Custom-Rules) wie der CLI.
                                        // false (Default): nur die Felder dieses Requests, keine INI.
    MinSeverityName: string;            // nur im INI-Modus: Override fuer [Rules] MinSeverity
                                        // ('error'/'warning'/'hint'; '' = INI/Default belassen)
    ConfigRoot     : string;            // INI-Modus: Wurzel fuer INI-/PathOverrides-/Custom-Rules-
                                        // Aufloesung (ApplyDetectorThresholds). '' -> Path verwenden.
                                        // Noetig wenn Scan-Ziel != Config-Root (z.B. Single-File).
    SkipConfig     : Boolean;           // true: Run wendet KEINE Config an - der Consumer hat den
                                        // globalen Detektor-/Schwellen-State bereits selbst gesetzt
                                        // (z.B. IDE via TIDEAnalysisPrep.SetupForRun). Nur Scope->Scan->Baseline.
    SingleFileProjectRoot: string;      // nur ssSingleFile: ProjectRoot fuer den projektweiten
                                        // Symbol-Referenz-Index (AnalyzeLeaks(File, ProjectRoot, UsesCheck)).
                                        // '' -> Single-File ohne Cross-Unit-Index (1-arg-Ueberladung).
    IgnoreList     : TIgnoreList;       // nur ssRecursive: Ignore-/Test-Filter waehrend des rekursiven
                                        // Scans (IDE reicht ihre FIgnoreList durch). nil -> kein Filter.
    Progress       : TProc<Integer, Integer>;  // (current, total); EAbort darin bricht ab
    // Liefert ein Request mit sinnvollen Defaults (ssRecursive, alle Detektoren,
    // loseste Schwellen, Engine-Default-Limits).
    class function Init: TScanRequest; static;
  end;

  // Ergebnis eines Scans. Besitzt die Findings-Liste; mit .Free freigeben
  // (gibt die Findings mit frei, ausser nach ReleaseFindings).
  TScanResult = class
  private
    FFindings : TObjectList<TLeakFinding>;
    FBaseDir  : string;
    function CountSeverity(ASev: TLeakSeverity): Integer;
  public
    constructor Create(AFindings: TObjectList<TLeakFinding>; const ABaseDir: string);
    destructor  Destroy; override;

    // Export-Helfer (Version = SCA_VERSION, BaseDir = aus dem Scan).
    procedure WriteSarif(const AFileName: string;
                         const AToolName: string = SCA_DEFAULT_TOOLNAME);
    procedure WriteSonar(const AFileName: string);
    procedure WriteHtml (const AFileName: string);

    // Gibt die Ownership der Findings-Liste ab; danach besitzt sie der
    // Aufrufer (muss sie selbst freigeben). FFindings wird nil, Destroy
    // gibt dann nichts frei.
    function ReleaseFindings: TObjectList<TLeakFinding>;

    function FindingCount: Integer;
    function ErrorCount  : Integer;
    function WarningCount: Integer;
    function HintCount   : Integer;

    property Findings: TObjectList<TLeakFinding> read FFindings;
    property BaseDir : string                    read FBaseDir;
  end;

  // Eine Analyse-Sitzung. In Phase 0 zustandslos (delegiert an die globalen
  // Engine-Bausteine). Die Klasse existiert jetzt, damit Phase 3 den Cache-/
  // Index-State in die Instanz ziehen kann, OHNE die Aufruf-Form zu aendern.
  TAnalysisSession = class
  private
    procedure ApplyConfig(const Req: TScanRequest);
  public
    function Run(const Req: TScanRequest): TScanResult;
  end;

// Bequemlichkeit: Ein-Zeilen-Rekursiv-Scan ohne explizite Session.
function ScanRecursive(const APath: string;
  const AProfile: string = ''): TScanResult;

// Bequemlichkeit: In-Memory-Scan eines Quelltext-Strings (kein Datei-Pfad).
// Fuer Editor-Lint/Embedding. Den logischen Datei-Namen kann man ueber die
// volle TScanRequest (ssSource + Path) setzen - dann tragen die Findings den.
function AnalyzeSource(const Source: string;
  const AProfile: string = ''): TScanResult;

implementation

uses
  System.IOUtils, System.SyncObjs,
  uStaticAnalyzer2, uRuleCatalog, uLexer, uCustomRuleDetector, uVcsChanges,
  uRepoSettings, uBaseline, uExportSARIF, uExportSonarGeneric, uExportHtml;

var
  // Serialisiert ALLE Engine-Scans prozessweit. Der Engine-State ist global
  // und nicht thread-safe: LeakyClasses/DiscoveredClasses/Config-Vars werden
  // waehrend des Scans mutiert (uStaticAnalyzer2). Ohne Serialisierung racet
  // ein Background-Consumer (IDE-Watch-Worker) mit UI-Thread-Scans -> TString-
  // List-Mutation waehrend Fremd-Iteration -> AV / korrupte Findings.
  // Rekursiv (TCriticalSection ist reentrant), damit ein Consumer, der den
  // Lock um SetupForRun+Run als Einheit haelt, mit Run's internem Enter nicht
  // deadlockt. Single-Threaded (CLI/Form): unkontent -> null Verhaltens-
  // aenderung, A/B byte-identisch.
  GEngineLock: TCriticalSection = nil;

function WriteTempSource(const ASrc: string): string;
// Schreibt ASrc in eine eindeutige Temp-.pas. GUID-Name (kollisionsfrei bei
// parallelen Sessions), .pas-Endung (Parser/Single-File-Pfad erwartet das).
var
  G : string;
begin
  G := TGUID.NewGuid.ToString;
  G := G.Replace('{', '').Replace('}', '').Replace('-', '');
  Result := TPath.Combine(TPath.GetTempPath, 'sca_src_' + G + '.pas');
  TFile.WriteAllText(Result, ASrc, TEncoding.UTF8);
end;

{ TScanRequest }

class function TScanRequest.Init: TScanRequest;
begin
  Result.Scope           := ssRecursive;
  Result.Path            := '';
  Result.Files           := nil;
  Result.Source          := '';
  Result.VcsRange        := '';
  Result.Profile         := '';          // '' = alle Detektoren (Engine-Default)
  Result.MinSeverity     := lsHint;      // loseste Schwelle -> alles
  Result.MinConfidence   := fcMedium;    // Engine-Default
  Result.MaxFileBytes    := 0;           // 0 -> Engine-Default (5 MB) belassen
  Result.UsesCheck       := False;
  Result.AutoDiscover    := False;
  Result.IfdefDefines    := nil;
  Result.CustomRulesPath := '';
  Result.BaselinePath      := '';
  Result.WriteBaselinePath := '';
  Result.ApplyRepoIni      := False;
  Result.MinSeverityName   := '';
  Result.ConfigRoot        := '';
  Result.SkipConfig        := False;
  Result.SingleFileProjectRoot := '';
  Result.IgnoreList        := nil;
  Result.Progress        := nil;
end;

{ TScanResult }

constructor TScanResult.Create(AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string);
begin
  inherited Create;
  FFindings := AFindings;
  FBaseDir  := ABaseDir;
end;

destructor TScanResult.Destroy;
begin
  FFindings.Free;   // nil-sicher (nach ReleaseFindings)
  inherited;
end;

function TScanResult.ReleaseFindings: TObjectList<TLeakFinding>;
begin
  Result    := FFindings;
  FFindings := nil;
end;

procedure TScanResult.WriteSarif(const AFileName, AToolName: string);
begin
  TSARIFWriter.WriteFile(AFileName, FFindings, FBaseDir, SCA_VERSION, AToolName);
end;

procedure TScanResult.WriteSonar(const AFileName: string);
begin
  TSonarGenericWriter.WriteFile(AFileName, FFindings, FBaseDir);
end;

procedure TScanResult.WriteHtml(const AFileName: string);
begin
  TExporterHtml.Run(FFindings, '', AFileName);
end;

function TScanResult.CountSeverity(ASev: TLeakSeverity): Integer;
var
  F: TLeakFinding;
begin
  Result := 0;
  if FFindings = nil then Exit;
  for F in FFindings do
    if F.Severity = ASev then Inc(Result);
end;

function TScanResult.FindingCount: Integer;
begin
  if FFindings = nil then Result := 0 else Result := FFindings.Count;
end;

function TScanResult.ErrorCount  : Integer; begin Result := CountSeverity(lsError);   end;
function TScanResult.WarningCount: Integer; begin Result := CountSeverity(lsWarning); end;
function TScanResult.HintCount   : Integer; begin Result := CountSeverity(lsHint);    end;

{ TAnalysisSession }

procedure TAnalysisSession.ApplyConfig(const Req: TScanRequest);
var
  Def      : string;
  Settings : TRepoSettings;
begin
  // 1) Detektor-/Schwellen-Config.
  if Req.ApplyRepoIni then
  begin
    // INI-Modus (wie CLI): repo-/prozessweite analyser.ini laden, Request-
    // Overrides drueberlegen, dann das VOLLE TRepoSettings anwenden -- die 8
    // Detector-Schwellen, PathOverrides, Magic/Format-Listen, INI-Profil und
    // INI-Custom-Rules. Leeres Profil -> 'default' (TRepoSettings-Semantik,
    // NICHT die ''=alle-Semantik des Direkt-Modus).
    Settings := TRepoSettings.Create;
    try
      try Settings.Load; except end;
      if Req.Profile         <> '' then Settings.Profile     := Req.Profile;
      if Req.MinSeverityName <> '' then Settings.MinSeverity := Req.MinSeverityName;
      if Req.ConfigRoot <> '' then
        Settings.ApplyDetectorThresholds(Req.ConfigRoot)
      else
        Settings.ApplyDetectorThresholds(Req.Path);
    finally
      Settings.Free;
    end;
  end
  else
  begin
    // Direkt-Modus: nur die Felder dieses Requests, keine INI. '' = [] = kein
    // Filter = alle Detektoren (nativer Engine-Default); benanntes Profil via
    // Regel-Katalog.
    if Req.Profile <> '' then
      uSCAConsts.DetectorEnabledKinds := TRuleCatalog.GetProfile(Req.Profile)
    else
      uSCAConsts.DetectorEnabledKinds := [];
    uSCAConsts.DetectorMinSeverity  := Req.MinSeverity;
    uSCAConsts.FindingMinConfidence := Req.MinConfidence;
    if Req.MaxFileBytes > 0 then
      uSCAConsts.DetectorMaxFileBytes := Req.MaxFileBytes;
    uSCAConsts.AutoDiscoverCustomClasses := Req.AutoDiscover;
  end;

  // 2) {$IFDEF}-aware Parsing (beide Modi - Request-Level statt globaler Fummelei)
  LexerIfdefClear;
  if Length(Req.IfdefDefines) > 0 then
  begin
    gLexerIfdefSkipEnabled := True;
    for Def in Req.IfdefDefines do
      if Trim(Def) <> '' then
        LexerIfdefAddDefine(Trim(Def));
  end
  else
    gLexerIfdefSkipEnabled := False;

  // 3) Custom-Rules: expliziter Request-Pfad gewinnt. Im INI-Modus hat
  //    ApplyDetectorThresholds evtl. schon INI-Custom-Rules geladen -- die
  //    NICHT wegclearen (nur ueberschreiben, wenn der Request einen Pfad nennt).
  if Req.CustomRulesPath <> '' then
    TCustomRuleDetector.LoadFromYaml(Req.CustomRulesPath)
  else if not Req.ApplyRepoIni then
    TCustomRuleDetector.ClearRules;
end;

function TAnalysisSession.Run(const Req: TScanRequest): TScanResult;
var
  Findings : TObjectList<TLeakFinding>;
  Files    : TStringList;
  Info     : string;
  BaseDir  : string;
begin
  // Prozessweite Scan-Serialisierung gegen den nicht-thread-safen globalen
  // Engine-State (s. GEngineLock). Deckt ApplyConfig + Scan + Baseline ab.
  // Rekursiv -> ein Consumer, der den Lock bereits um SetupForRun+Run haelt,
  // re-entert hier problemlos. NIE ueber Synchronize/ProcessMessages hinweg
  // halten (Deadlock) - der Watch-Worker released daher vor Synchronize.
  GEngineLock.Enter;
  try
  if not Req.SkipConfig then
    ApplyConfig(Req);

  case Req.Scope of
    ssSingleFile:
      begin
        // Mit ProjectRoot -> projektweiter Symbol-Index (Cross-Unit-Detektoren);
        // ohne -> reiner Single-File-Scan.
        if Req.SingleFileProjectRoot <> '' then
          Findings := TStaticAnalyzer2.AnalyzeLeaks(
                        Req.Path, Req.SingleFileProjectRoot, Req.UsesCheck)
        else
          Findings := TStaticAnalyzer2.AnalyzeLeaks(Req.Path, Req.UsesCheck);
        BaseDir  := ExtractFilePath(Req.Path);
      end;

    ssFileList:
      begin
        Files := TStringList.Create;
        try
          Files.AddStrings(Req.Files);
          Findings := TStaticAnalyzer2.AnalyzeLeaksFromList(
                        Files, Req.Progress, Req.UsesCheck);
        finally
          Files.Free;
        end;
        BaseDir := Req.Path;   // optionaler Basis-Root fuer relative Export-Pfade
      end;

    ssVcsChanged:
      begin
        // Im INI-Modus die analyser.ini an die VCS-Ermittlung reichen
        // (BaseBranch / Git-Exe / Ignore-Liste) - wie der CLI. Sonst nil
        // (Overload-Default = Auto-Verhalten).
        var VcsSettings: TRepoSettings := nil;
        if Req.ApplyRepoIni then
        begin
          VcsSettings := TRepoSettings.Create;
          try VcsSettings.Load; except end;
        end;
        try
          if Req.VcsRange <> '' then
            Files := TVcsChanges.GetChangedPasFilesDiff(Req.Path, Req.VcsRange, Info, VcsSettings)
          else
            Files := TVcsChanges.GetChangedPasFilesAuto(Req.Path, Info, VcsSettings);
          try
            if Files = nil then
              // kein Repo / Range nicht aufloesbar -> leeres Ergebnis statt Crash
              Findings := TObjectList<TLeakFinding>.Create(True)
            else
              Findings := TStaticAnalyzer2.AnalyzeLeaksFromList(
                            Files, Req.Progress, Req.UsesCheck);
          finally
            Files.Free;   // nil ist fuer .Free unkritisch
          end;
        finally
          VcsSettings.Free;
        end;
        BaseDir := Req.Path;
      end;

    ssSource:
      begin
        // In-Memory: Quelltext in eine Temp-.pas schreiben und den (stabilen,
        // resident-sicheren) Single-File-Pfad fahren -> volle Per-File-
        // Pipeline (AST + source-line Detektoren + Suppression). NICHT der
        // rekursive Pfad (der haengt residente Hosts, siehe G3).
        var Fn := WriteTempSource(Req.Source);
        try
          Findings := TStaticAnalyzer2.AnalyzeLeaks(Fn, Req.UsesCheck);
        finally
          try TFile.Delete(Fn); except end;
        end;
        // Findings tragen den Temp-Pfad; auf den logischen Namen (Req.Path)
        // umstempeln, falls gesetzt (Editor-Lint: Buffer-Name).
        if Req.Path <> '' then
          for var Fnd in Findings do
            Fnd.FileName := Req.Path;
        BaseDir := ExtractFilePath(Req.Path);
      end;

  else
    // ssRecursive (Default)
    Findings := TStaticAnalyzer2.AnalyzeLeaksRecursive(
                  Req.Path, Req.Progress, Req.UsesCheck, Req.IgnoreList);
    BaseDir  := Req.Path;
  end;

  // Baseline (wie der CLI: nach dem Scan, vor Result/Export; Fehler nicht
  // fatal - ein kaputtes Baseline-File soll den Lauf nicht stoppen).
  if Req.BaselinePath <> '' then
    try TBaseline.Apply(Findings, Req.BaselinePath); except end;
  if Req.WriteBaselinePath <> '' then
    try TBaseline.Write(Findings, Req.WriteBaselinePath); except end;

  Result := TScanResult.Create(Findings, BaseDir);
  finally
    GEngineLock.Leave;
  end;
end;

{ Convenience }

function ScanRecursive(const APath, AProfile: string): TScanResult;
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
begin
  Req := TScanRequest.Init;
  Req.Path    := APath;
  Req.Profile := AProfile;
  Ses := TAnalysisSession.Create;
  try
    Result := Ses.Run(Req);
  finally
    Ses.Free;
  end;
end;

function AnalyzeSource(const Source, AProfile: string): TScanResult;
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
begin
  Req := TScanRequest.Init;
  Req.Scope   := ssSource;
  Req.Source  := Source;
  Req.Profile := AProfile;
  Ses := TAnalysisSession.Create;
  try
    Result := Ses.Run(Req);
  finally
    Ses.Free;
  end;
end;

initialization
  GEngineLock := TCriticalSection.Create;

finalization
  FreeAndNil(GEngineLock);

end.
