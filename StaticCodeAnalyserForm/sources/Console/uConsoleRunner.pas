unit uConsoleRunner;

// Headless CLI-Mode fuer analyser.d12.exe. Nicht-interaktiv, fuer
// CI/CD-Pipelines (GitHub Actions, GitLab CI, Jenkins, lokale
// Pre-Commit-Hooks).
//
// Aufruf-Beispiele:
//   analyser.exe --path D:\repo --full --report-sarif sca.sarif
//   analyser.exe --path D:\repo --branch --report-sarif sca.sarif
//   analyser.exe --file MeineUnit.pas --quiet
//   analyser.exe --help
//
// Exit-Code-Konvention (klassisch fuer SCA-Tools):
//   0  = keine Findings (clean)
//   1  = nur Hints
//   2  = mindestens 1 Warning (keine Errors)
//   3  = mindestens 1 Error
//   4  = mindestens 1 Read-Error (Parser-/IO-Fehler)
//   99 = Tool-Fehler (Args ungueltig, Pfad fehlt, ...)
//
// Die Rangleiter 1-3 gewinnt gegen 4: ein Lauf mit Errors UND Lesefehlern
// meldet 3. --fail-on darf einen Lauf mit Lesefehlern aber nicht auf 0
// druecken - herabgestuft wird dort auf 4 statt auf 0, sonst meldet die
// Pipeline gruen fuer einen Scan, der Teile des Baums nie gesehen hat.
// Einzige Ausnahme: --fail-on none bedeutet ausdruecklich "nie scheitern"
// und bleibt 0 (Nutzerentscheid 2026-08-08).
//
// Ist der Aufrufer in einem reinen Console-Kontext entstanden (kein
// Terminal angehaengt), schreibt der Runner trotzdem ueber WriteLn -
// fuer Pipe-Redirection und Log-Files reicht das.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  uMethodd12;

type
  // Ergebnis des CLI-Runs - der Caller (.dpr) ruebergibt das an Halt().
  TCliExitCode = (
    cecClean        = 0,
    cecHints        = 1,
    cecWarnings     = 2,
    cecErrors       = 3,
    cecReadErrors   = 4,
    cecToolError    = 99
  );

  // Geparste Args. Public damit Tests die Parse-Logik isoliert ansprechen
  // koennen (kein Run-Side-Effect).
  TCliArgs = record
    Help          : Boolean;        // --help / -h / -?
    ShowVersion   : Boolean;        // --version
    Path          : string;         // --path <dir>
    SingleFile    : string;         // --file <path>
    // ---- Scan-Scope-Variation (Konzept_ScanScope_2026-07-20) ----
    ProjectFile   : string;         // --project <file.dproj>        DCCReference-Liste
    GroupFile     : string;         // --project-group <file.groupproj>  Union aller Projekte
    IndexRoot     : string;         // --index-root <dir>  Cross-Unit-Index-Superset
                                    //   (mit --project/--project-group/--branch/--diff)
    Full          : Boolean;        // --full      (rekursiv ab Path)
    Branch        : Boolean;        // --branch    (nur VCS-geaenderte)
    Diff          : string;         // --diff <sha1>..<sha2>  PR-Review-Mode
    ReportSarif   : string;         // --report-sarif <out.sarif>
    ReportHtml    : string;         // --report-html  <out.html>  Self-contained Code-Review-Report
    // CSV und JSON gab es bis 2026-08-08 NUR im GUI-Exportmenue -
    // ausgerechnet die zwei Formate, zu denen man in einem Skript
    // greift (Excel, Ticket-Automatisierung), waren die einzigen, die
    // man nicht skripten konnte. Die Writer existierten laengst.
    ReportCsv     : string;         // --report-csv   <out.csv>
    ReportJson    : string;         // --report-json  <out.json>
    Quiet         : Boolean;        // --quiet
    BaseDir       : string;         // --base-dir <dir>  (fuer relative Pfade
                                    //   im SARIF; default = Path)
    CustomRules   : string;         // --custom-rules <analyser-rules.yml>
    Profile       : string;         // --profile <name>         (siehe sca-rules.json)
    MinSeverity   : string;         // --min-severity hint|warning|error
    // ---- Baseline / CI-Exit-Codes ----
    Baseline      : string;         // --baseline <file.json>     filter known findings
    WriteBaseline : string;         // --write-baseline <file.json|auto>  snapshot for future runs
    BaselineScan  : string;         // --baseline-scan y|n  (.sca-Aufloesung + harter Fehler)
    // --baseline-path-fingerprint y|n: Relativpfad statt blossem Dateinamen
    // im Fingerprint. Bis 2026-08-08 gab es das NUR in der analyser.ini und
    // damit nicht in CI - obwohl genau dort der Schaden entsteht: eine
    // Baseline aus einem Unterordner unterdrueckt gleichnamige Units in
    // ALLEN anderen Ordnern mit (nachgemessen: 4-Eintrag-Baseline aus
    // alpha\ verschluckte samtliche Funde in beta\, inklusive einer
    // SQL-Injection, die nie jemand geprueft hatte).
    BaselinePathFp : string;
    FailOn        : string;         // --fail-on=error|warning|hint|none  (default: graded)
    // ---- Sonar-Integration (Phase A der todo-sonar.md Roadmap) ----
    SonarExport   : string;         // --sonar-export <out.json>  Generic Issue Format
    SonarInit     : Boolean;        // --sonar-init               sonar-project.properties template
    SonarTest     : Boolean;        // --sonar-test               health-check
    SonarHost     : string;         // --sonar-host <url>
    SonarToken    : string;         // --sonar-token <token>
    SonarProject  : string;         // --sonar-project <key>
    SonarBranch   : string;         // --sonar-branch <name>
    SonarInsecure : Boolean;        // --sonar-insecure           accept self-signed TLS
    SonarConfig   : string;         // --sonar-config <path>      alternative INI
    // ---- Perf Stufe 2 (2026-07-25) ----
    Parallel      : Boolean;        // --parallel                 Per-File-Parallelisierung (opt-in;
                                    //   faellt bei AutoDiscovery/Custom-Rules/--time-detectors still
                                    //   auf seriell zurueck - Gate in uStaticAnalyzer2)
    ParallelWorkers : string;       // --parallel-workers <n>     Worker-Anzahl (0/leer = auto)
    // ---- Perf-Diagnostik ----
    TimeDetectors : Boolean;        // --time-detectors           pro-Detektor-Timing-Tabelle nach Scan
    TimeDetectorsOut : string;      // --time-detectors-out <file> schreibt die Markdown-Tabelle in
                                    //   die angegebene Datei (zusaetzlich zu/statt stdout). Pflicht
                                    //   wenn man die Tabelle als Datei archivieren will (stdout-Pipes
                                    //   funktionieren seit 2026-07-05 ebenfalls, s. dpr-Redirect-Support).
    // ---- Telemetrie (C.5) ----
    TelemetryCsv  : string;         // --telemetry-csv <file>     suppression-marker-hits als CSV ausgeben
    // ---- Findings-Filter ----
    HideTestFixtures : Boolean;     // --hide-test-fixtures       drop findings aus uTest*/Sample/Demo-Files
    HideTestExplicit : Boolean;     // True wenn HideTestFixtures vom User explizit gesetzt wurde
                                    //   (Auto-Default je nach Profile sonst).
    // ---- A.5 IFDEF-Awareness (Phase 1b-Wiring) ----
    IfdefAware    : Boolean;        // --ifdef-aware              Lexer skippt {$IFDEF X}-Branches
                                    //   wo X NICHT im IfdefDefines-Set steht
    NoIfdefAware  : Boolean;        // --no-ifdef-aware           Opt-Out vom Profile-Auto-Default
                                    //   (gewinnt ueber Profile-basiertes IfdefAware=True)
    IfdefDefines  : string;         // --define X[,Y,Z]           Comma-separated Defines
                                    //   (mehrfach --define X erlaubt - akkumuliert)
    ParseError    : string;         // nicht-leer wenn Args invalid
  end;

  TConsoleRunner = class
  public
    // Parsing-Layer - testbar ohne IO. ParamStr/ParamCount-Wrapper:
    // die Tests koennen ein eigenes string-Array uebergeben.
    class function ParseArgs(const Args: array of string): TCliArgs; static;
    class function ParseSysArgs: TCliArgs; static;

    // Run-Layer. Liefert den Exit-Code fuer Halt(). KEINE Exceptions
    // nach aussen - alles wird auf stderr geloggt + Exit-Code gesetzt.
    class function Run(const Args: TCliArgs): Integer; static;

    // Hauptentry vom .dpr - kombiniert Parse + Run, fuer den haeufigen
    // Fall ohne Test-Mocks.
    class function RunFromCmdLine: Integer; static;

    // Die beiden folgenden sind public, damit Tests sie ohne einen
    // kompletten Run mit echten Dateien pruefen koennen. Der Exit-Code
    // ist die Schnittstelle zur CI - er gehoert unter Test.
    class function CalcExitCode(const Findings: TObjectList<TLeakFinding>): Integer; static;
    // Gemeinsame Severity-Klassifikation fuer WriteSummary + CalcExitCode
    // (2026-07-04 dedupliziert). fkFileReadError zaehlt IMMER als ReadError,
    // unabhaengig von seiner Severity - nie in Errors/Warnings/Hints.
    class procedure CountBySeverity(const Findings: TObjectList<TLeakFinding>;
      out Errors, Warnings, Hints, ReadErrors: Integer); static;
  private
    class procedure WriteHelp; static;
    class procedure WriteVersion; static;
    class procedure WriteSummary(const Findings: TObjectList<TLeakFinding>;
      Quiet: Boolean); static;
  end;

// Exit-Code-Politik von --fail-on. In der interface-Sektion, damit die
// Tests sie ohne Run-Seiteneffekt aufrufen koennen.
//   Raw        - der Code aus CalcExitCode (Rangleiter 0-4)
//   FailOn     - der Wert von --fail-on
//   ReadErrors - Anzahl der Dateien, die der Lauf nicht lesen konnte.
//                Bewusst die Zahl und kein Boolean: am Aufrufer steht dann
//                der Zaehler aus CountBySeverity statt eines nichtssagenden
//                True/False.
function ApplyFailOnPolicy(Raw: Integer; const FailOn: string;
  ReadErrors: Integer): Integer;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, ConsecutiveSection, DebugOutput, ExceptOnException, GroupedDeclaration, IfElseBegin, InsecureCryptoAlgorithm, NestedRoutine, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedPublicMember
// DebugOutput: WriteLn IST das CLI-Output-Medium dieses Console-Runners (by design).
// InsecureCryptoAlgorithm: 'sha1..sha2' im Hilfetext ist ein Git-Ref-Beispiel, keine Krypto.
// CLI-Top-Level: outer except E: Exception fuer "non-zero exit + error msg"
// statt Crash mit stack-trace. Idiomatisch fuer Console-Apps.

uses
  System.IOUtils, System.Math,
  System.Generics.Defaults,           // TComparer fuer Detector-Timings-Sort
  uSCAConsts, uStaticAnalyzer2, uVcsChanges, uRepoSettings, uEngineApi,
  uExportSARIF, uExportHtml, uExport, uCustomRuleDetector,
  uExportSonarGeneric, uSonarConfig,
  uDetectorUtils,                     // TDetectorUtils.IsTestFixturePath
  uRuleCatalog,                       // TRuleCatalog.GetProfile fuer die Startzeile
  uBaseline,
  uSuppressionTelemetry,              // C.5 Telemetrie
  uLexer;                             // A.5 Phase 1b-Wiring: gLexerIfdefSkipEnabled etc.

const
  // Bis zu so vielen gefilterten Dateien werden die Namen genannt; darueber
  // nur die Anzahl. Sechs passen in eine Zeile, ohne die Ausgabe zu
  // sprengen - mehr liest ohnehin niemand.
  MAX_NAMED_FIXTURE_FILES = 6;

  // SCA_VERSION kommt aus uSCAConsts (Single-Source-of-Truth). Bis 0.9.8
  // stand hier eine zweite, hart kodierte Kopie: ein Versionssprung in
  // uSCAConsts liess die CLI weiter die alte Nummer melden - in --version,
  // im Banner UND im SARIF-Tool-Block.
  SCA_TOOLNAME = 'StaticCodeAnalyser';

{ ---- Args-Parser ---- }

class function TConsoleRunner.ParseArgs(const Args: array of string): TCliArgs;
// Akzeptiert sowohl "--key value" als auch "--key=value".
// Boolean-Switches haben kein Value.
var
  i      : Integer;
  A, V   : string;
  EqPos  : Integer;
  // HasVal (outer) wird im outer-Body initialisiert bevor GetValue
  // aufgerufen wird; FP des Nested-Closure-Pattern.
  HasVal : Boolean;
  Errored: Boolean;

  // Holt den Value-String fuer den aktuellen Switch und schreibt ihn in
  // Target. Liefert True bei Erfolg; bei Fehlschlag werden ParseError +
  // Errored-Flag gesetzt. Caller bricht ueber Errored ab.
  procedure GetValue(var Target: string; const SwitchName: string);
  begin
    if HasVal then begin Target := V; Exit; end;
    // i (outer) wird im outer-Body in der Switch-Schleife initialisiert
    // bevor GetValue aufgerufen wird; FP des Nested-Closure-Pattern.
    if i + 1 > High(Args) then
    begin
      Result.ParseError := Format('%s braucht einen Wert', [SwitchName]);
      Errored := True;
      Exit;
    end;
    Inc(i);
    Target := Args[i];
  end;

begin
  // Defaults: alle Felder sind Zero-Value (False / '' / 0) - Default()
  // initialisiert den kompletten Record, inkl. der Felder die der alte
  // explizite Block nicht abdeckte (Diff, FailOn, IfdefAware, ...).
  // 2026-07-04 konsolidiert; Nicht-Zero-Defaults gibt es hier keine.
  Result  := Default(TCliArgs);
  Errored := False;

  i := Low(Args);
  while (i <= High(Args)) and not Errored do
  begin
    A := Args[i];
    EqPos := Pos('=', A);
    if EqPos > 0 then
    begin
      V := Copy(A, EqPos + 1, MaxInt);
      A := Copy(A, 1, EqPos - 1);
      HasVal := True;
    end
    else
    begin
      V := '';
      HasVal := False;
    end;

    if (A = '--help') or (A = '-h') or (A = '-?') or (A = '/?') then
      Result.Help := True
    else if A = '--version' then
      Result.ShowVersion := True
    else if A = '--full' then
      Result.Full := True
    else if A = '--branch' then
      Result.Branch := True
    else if A = '--diff' then
      GetValue(Result.Diff, '--diff')
    else if A = '--quiet' then
      Result.Quiet := True
    else if A = '--path' then
      GetValue(Result.Path, '--path')
    else if A = '--file' then
      GetValue(Result.SingleFile, '--file')
    else if A = '--project' then
      GetValue(Result.ProjectFile, '--project')
    else if A = '--project-group' then
      GetValue(Result.GroupFile, '--project-group')
    else if A = '--index-root' then
      GetValue(Result.IndexRoot, '--index-root')
    else if A = '--report-sarif' then
      GetValue(Result.ReportSarif, '--report-sarif')
    else if A = '--report-html' then
      GetValue(Result.ReportHtml, '--report-html')
    else if A = '--report-csv' then
      GetValue(Result.ReportCsv, '--report-csv')
    else if A = '--report-json' then
      GetValue(Result.ReportJson, '--report-json')
    else if A = '--base-dir' then
      GetValue(Result.BaseDir, '--base-dir')
    else if A = '--custom-rules' then
      GetValue(Result.CustomRules, '--custom-rules')
    else if A = '--profile' then
      GetValue(Result.Profile, '--profile')
    else if A = '--min-severity' then
      GetValue(Result.MinSeverity, '--min-severity')
    // Baseline + CI-Exit-Codes
    else if A = '--baseline' then
      GetValue(Result.Baseline, '--baseline')
    else if A = '--write-baseline' then
      GetValue(Result.WriteBaseline, '--write-baseline')
    else if A = '--baseline-scan' then
      GetValue(Result.BaselineScan, '--baseline-scan')
    else if A = '--baseline-path-fingerprint' then
      GetValue(Result.BaselinePathFp, '--baseline-path-fingerprint')
    else if A.StartsWith('--fail-on=') then
      Result.FailOn := LowerCase(A.Substring(Length('--fail-on=')))
    else if A = '--fail-on' then
      GetValue(Result.FailOn, '--fail-on')
    // Sonar-Flags (Phase A todo-sonar.md)
    else if A = '--sonar-export' then
      GetValue(Result.SonarExport, '--sonar-export')
    else if A = '--sonar-init' then
      Result.SonarInit := True
    else if A = '--sonar-test' then
      Result.SonarTest := True
    else if A = '--sonar-host' then
      GetValue(Result.SonarHost, '--sonar-host')
    else if A = '--sonar-token' then
      GetValue(Result.SonarToken, '--sonar-token')
    else if A = '--sonar-project' then
      GetValue(Result.SonarProject, '--sonar-project')
    else if A = '--sonar-branch' then
      GetValue(Result.SonarBranch, '--sonar-branch')
    else if A = '--sonar-insecure' then
      Result.SonarInsecure := True
    else if A = '--sonar-config' then
      GetValue(Result.SonarConfig, '--sonar-config')
    else if A = '--parallel' then
      Result.Parallel := True
    else if A = '--parallel-workers' then
      GetValue(Result.ParallelWorkers, '--parallel-workers')
    else if A = '--time-detectors' then
      Result.TimeDetectors := True
    else if A = '--time-detectors-out' then
    begin
      GetValue(Result.TimeDetectorsOut, '--time-detectors-out');
      Result.TimeDetectors := True;  // Out impliziert Aktivierung
    end
    else if A = '--telemetry-csv' then
      GetValue(Result.TelemetryCsv, '--telemetry-csv')
    else if A = '--hide-test-fixtures' then
    begin
      Result.HideTestFixtures := True;
      Result.HideTestExplicit := True;
    end
    else if A = '--show-test-fixtures' then
    begin
      Result.HideTestFixtures := False;
      Result.HideTestExplicit := True;
    end
    else if A = '--ifdef-aware' then
      Result.IfdefAware := True
    else if A = '--no-ifdef-aware' then
      Result.NoIfdefAware := True
    else if A = '--define' then
    begin
      var DefVal := '';
      GetValue(DefVal, '--define');
      if Result.IfdefDefines = '' then
        Result.IfdefDefines := DefVal
      else
        Result.IfdefDefines := Result.IfdefDefines + ',' + DefVal;
    end
    else
    begin
      Result.ParseError := Format('Unbekannter Switch: %s', [A]);
      Errored := True;
    end;
    Inc(i);
  end;
  if Errored then Exit;

  // --sonar-test und --sonar-init sind Standalone-Aktionen ohne Pfad-Pflicht.
  if Result.SonarTest or Result.SonarInit then Exit;

  // Konsistenz-Pruefung: genau eine Eingabe-Quelle muss gesetzt sein.
  var SourceCount := 0;
  if Result.Path <> ''        then Inc(SourceCount);
  if Result.SingleFile <> ''  then Inc(SourceCount);
  if Result.ProjectFile <> '' then Inc(SourceCount);
  if Result.GroupFile <> ''   then Inc(SourceCount);
  if (SourceCount = 0) and not Result.Help and not Result.ShowVersion then
  begin
    Result.ParseError :=
      'Keine Eingabe-Quelle: --path, --file, --project oder --project-group angeben';
    Exit;
  end;
  if SourceCount > 1 then
  begin
    Result.ParseError :=
      '--path, --file, --project und --project-group sind exklusiv';
    Exit;
  end;

  // --index-root nur dort, wo ein Listen-Scope existiert (Projekt/Gruppe/
  // Branch/Diff); bei --path ist der Index ohnehin der ganze Baum.
  if (Result.IndexRoot <> '') and (Result.ProjectFile = '') and
     (Result.GroupFile = '') and not Result.Branch and (Result.Diff = '') then
  begin
    Result.ParseError :=
      '--index-root braucht --project, --project-group, --branch oder --diff';
    Exit;
  end;
  if (Result.IndexRoot <> '') and not DirectoryExists(Result.IndexRoot) then
  begin
    Result.ParseError := Format(
      '--index-root Verzeichnis nicht gefunden: %s', [Result.IndexRoot]);
    Exit;
  end;

  // --branch braucht --path (Branch-Diff laeuft per Repo-Root)
  if Result.Branch and (Result.Path = '') then
  begin
    Result.ParseError := '--branch braucht --path';
    Exit;
  end;

  // --diff braucht --path (analog --branch, Repo-Root-Resolver)
  if (Result.Diff <> '') and (Result.Path = '') then
  begin
    Result.ParseError := '--diff braucht --path';
    Exit;
  end;
  // --diff und --branch schliessen sich aus (--diff = committed-only,
  // --branch = committed + working-tree, beides Git aber unterschiedliche
  // Filter-Strategien).
  if (Result.Diff <> '') and Result.Branch then
  begin
    Result.ParseError := '--diff und --branch sind exklusiv';
    Exit;
  end;

  // --full / --branch sind exklusiv; ohne beide bei --path = Default --full
  if Result.Full and Result.Branch then
  begin
    Result.ParseError := '--full und --branch sind exklusiv';
    Exit;
  end;
  if (Result.Path <> '') and not Result.Full and not Result.Branch then
    Result.Full := True;

  // BaseDir defaulten auf Path bzw. Dir der SingleFile. Fuer --project/
  // --project-group bleibt er leer - dort liefert der Engine-Dispatch den
  // gemeinsamen Wurzelpfad der aufgeloesten Liste (CommonRoot) als BaseDir,
  // was '..'-Includes ausserhalb des Projektverzeichnisses korrekt abdeckt.
  if Result.BaseDir = '' then
  begin
    if Result.Path <> '' then
      Result.BaseDir := Result.Path
    else if Result.SingleFile <> '' then
      Result.BaseDir := ExtractFilePath(Result.SingleFile);
  end;
end;

class function TConsoleRunner.ParseSysArgs: TCliArgs;
var
  Args : TArray<string>;
  i    : Integer;
begin
  SetLength(Args, ParamCount);
  for i := 1 to ParamCount do
    Args[i - 1] := ParamStr(i);
  Result := ParseArgs(Args);
end;

{ ---- Help / Version ---- }

class procedure TConsoleRunner.WriteHelp;
begin
  WriteLn(SCA_TOOLNAME, ' v', SCA_VERSION, ' - Headless CLI');
  WriteLn('');
  WriteLn('Usage:');
  WriteLn('  analyser.exe --path <dir> [--full|--branch] [--report-sarif <file>]');
  WriteLn('  analyser.exe --file <path.pas> [--report-sarif <file>]');
  WriteLn('');
  WriteLn('Input:');
  WriteLn('  --path <dir>          Project root, recursive scan (default mode = --full)');
  WriteLn('  --file <pas>          Single .pas file');
  WriteLn('  --project <dproj>     Scan the project''s DCCReference file list');
  WriteLn('                        (search-path units are NOT included - the list');
  WriteLn('                        is exactly what the .dproj references)');
  WriteLn('  --project-group <groupproj>');
  WriteLn('                        Scan all projects of the group (deduplicated)');
  WriteLn('  --index-root <dir>    Build the cross-unit index over this directory');
  WriteLn('                        while analysing only the file list (default for');
  WriteLn('                        --project/--project-group: common root of the');
  WriteLn('                        resolved list). Also valid with --branch/--diff.');
  WriteLn('');
  WriteLn('Scope (mit --path):');
  WriteLn('  --full                Recursive (default if neither flag set)');
  WriteLn('  --branch              Only VCS-changed files (Git/SVN auto-detected)');
  WriteLn('  --diff <range>        Only files changed between two Git refs.');
  WriteLn('                        Range syntax: sha1..sha2 / branchA..branchB');
  WriteLn('                        / sha1...sha2 (common-ancestor diff).');
  WriteLn('                        Use case: PR review - "what changed in this MR?".');
  WriteLn('');
  WriteLn('Output:');
  WriteLn('  --report-sarif <file> Write SARIF v2.1.0 report to <file>');
  WriteLn('  --report-html  <file> Write self-contained HTML Code-Review report');
  WriteLn('  --report-csv   <file> Write findings as CSV (UTF-8 with BOM, so');
  WriteLn('                        Excel reads it correctly)');
  WriteLn('  --report-json  <file> Write findings as JSON array');
  WriteLn('                        (filter/sort/snippets, no external assets)');
  WriteLn('  --base-dir <dir>      Make file paths in report relative to <dir>');
  WriteLn('                        (default = --path)');
  WriteLn('  --quiet               Suppress per-finding stdout output');
  WriteLn('');
  WriteLn('Custom rules:');
  WriteLn('  --custom-rules <yml>  Load project-specific rules from YAML file');
  WriteLn('                        (regex/substring/word patterns, see');
  WriteLn('                         examples/analyser-rules.yml)');
  WriteLn('');
  WriteLn('Rule-set:');
  WriteLn('  --profile <name>      Bundled or custom profile from rules/sca-rules.json');
  WriteLn('                        (default, strict, ide-fast, security,');
  WriteLn('                         bugs-only, code-quality, style, dfm-only)');
  WriteLn('                        default = alles AUSSER den sechs reinen');
  WriteLn('                        Konventions-Regeln; die liegen in style.');
  WriteLn('                        strict = wirklich alles.');
  WriteLn('                        Overrides [Rules] Profile in analyser.ini.');
  WriteLn('  --min-severity <lvl>  hint|warning|error - skip detectors below');
  WriteLn('                        this severity threshold.');
  WriteLn('                        Overrides [Rules] MinSeverity in analyser.ini.');
  WriteLn('');
  WriteLn('CI / Baseline:');
  WriteLn('  --baseline <file>     Drop findings whose fingerprint matches a known');
  WriteLn('                        entry in <file> (JSON, written by --write-baseline).');
  WriteLn('                        Only NEW findings remain in output / exit code.');
  WriteLn('  --write-baseline <f>  Write current findings to <f> for future --baseline.');
  WriteLn('                        <f> = auto: write to the .sca default location');
  WriteLn('                        (<dir-of-project>\.sca\<name>.baseline.json).');
  WriteLn('  --baseline-scan y|n   y: resolve the baseline via --baseline, then');
  WriteLn('                        [Baseline] File= (analyser.ini), then the .sca');
  WriteLn('                        folder next to --project/--project-group (or');
  WriteLn('                        <path>\.sca\sca.baseline.json). HARD error');
  WriteLn('                        (exit 99) if requested and no file exists.');
  WriteLn('                        Resolves only - writes nothing.');
  WriteLn('  --baseline-path-fingerprint y|n');
  WriteLn('                        y: the fingerprint uses the file''s RELATIVE');
  WriteLn('                        PATH instead of just its name. Default n');
  WriteLn('                        (compatible). Use y when the same unit name');
  WriteLn('                        exists in several folders - otherwise one');
  WriteLn('                        accepted finding silently suppresses the');
  WriteLn('                        same-named unit everywhere else. Changing');
  WriteLn('                        this invalidates existing baselines: write');
  WriteLn('                        a fresh one. Overrides [Baseline]');
  WriteLn('                        PathInFingerprint in analyser.ini.');
  WriteLn('  --fail-on <lvl>       Exit-code policy: error|warning|hint|none|graded.');
  WriteLn('                        Default (=graded): use the tiered exit codes below.');
  WriteLn('                        ''none''    - exit 0 even with findings present.');
  WriteLn('                        ''hint''    - exit non-zero on any finding (= graded).');
  WriteLn('                        ''warning'' - only warnings + errors fail the build.');
  WriteLn('                        ''error''   - only errors fail the build.');
  WriteLn('                        A run that could not READ every file never');
  WriteLn('                        reports success: where the policy would');
  WriteLn('                        otherwise return 0, exit 4 is returned.');
  WriteLn('                        Example, 1 read error + 2 hints: graded -> 1,');
  WriteLn('                        warning -> 4, error -> 4, none -> 0.');
  WriteLn('                        Only ''none'' silences a read error.');
  WriteLn('');
  WriteLn('Sonar integration (see docs/sonar-setup.md):');
  WriteLn('  --sonar-export <file> Write Sonar Generic Issue Format JSON');
  WriteLn('                        (consume via sonar.externalIssuesReportPaths)');
  WriteLn('  --sonar-init          Write sonar-project.properties template');
  WriteLn('                        next to --path (or current dir). Never');
  WriteLn('                        overwrites: falls back to .sample, and');
  WriteLn('                        refuses if that differs too.');
  WriteLn('  --sonar-test          Run connectivity health-check (DNS, status,');
  WriteLn('                        token, project access). Exit 0 = healthy.');
  WriteLn('  --sonar-host <url>    Override Sonar host URL');
  WriteLn('  --sonar-token <tok>   Override Sonar bearer token');
  WriteLn('  --sonar-project <k>   Override Sonar projectKey');
  WriteLn('  --sonar-branch <b>    Branch name written into the --sonar-init');
  WriteLn('                        template (sonar.branch.name). The findings');
  WriteLn('                        export has no branch field - the branch is');
  WriteLn('                        read by sonar-scanner, not by this tool.');
  WriteLn('  --sonar-insecure      Accept self-signed TLS certificates');
  WriteLn('  --sonar-config <ini>  Alternative analyser.ini path for Sonar lookup');
  WriteLn('');
  WriteLn('Performance:');
  WriteLn('  --parallel            DEFEKT - NICHT BENUTZEN. Per-File-Parallel-');
  WriteLn('                        scan. Elf Detektoren teilen sich unit-globale');
  WriteLn('                        TRegEx-Instanzen; unter Last verlieren sie');
  WriteLn('                        ECHTE Funde und erfinden Fehler-Records.');
  WriteLn('                        Gemessen: 13 Laeufe = 13 verschiedene');
  WriteLn('                        Ergebnisse, 40 verlorene Funde. Und es ist');
  WriteLn('                        nicht einmal schneller (seriell 24s, parallel');
  WriteLn('                        28-41s). Mit --parallel-workers 1 ist der Lauf');
  WriteLn('                        byte-identisch zum seriellen - das belegt die');
  WriteLn('                        Nebenlaeufigkeit als Ursache.');
  WriteLn('  --parallel-workers <n>');
  WriteLn('                        Worker-Anzahl fuer --parallel (0/weggelassen =');
  WriteLn('                        automatisch: CPU-Kerne, gedeckelt auf Dateianzahl).');
  WriteLn('');
  WriteLn('Perf-Diagnostik:');
  WriteLn('  --time-detectors      Aggregiert per-Detektor TotalMs + CallCount');
  WriteLn('  --time-detectors-out <file>');
  WriteLn('                        Schreibt die Markdown-Tabelle in die angegebene Datei');
  WriteLn('                        (impliziert --time-detectors). Praktisch zum');
  WriteLn('                        Archivieren; stdout-Pipes funktionieren ebenfalls.');
  WriteLn('                        ueber den Scan. Markdown-Tabelle am Ende.');
  WriteLn('                        Identifiziert Hot-Path-Detektoren fuer');
  WriteLn('                        gezielte Optimierung.');
  WriteLn('  --telemetry-csv <file> Pro suppressed Finding eine CSV-Zeile.');
  WriteLn('                        Spalten: timestamp_iso, kind, filename,');
  WriteLn('                        finding_line, marker_line. Aggregierbar');
  WriteLn('                        ueber Runs fuer "Noise-Ranking pro');
  WriteLn('                        Detektor" (Konzept C.5).');
  WriteLn('');
  WriteLn('Findings-Filter:');
  WriteLn('  --hide-test-fixtures  Findings aus uTest*/Sample/Demo-Files ausblenden.');
  WriteLn('                        Auto-On bei --profile default/selftest-quiet,');
  WriteLn('                        Auto-Off bei --profile strict.');
  WriteLn('                        Explizit setzbar via --hide- / --show-test-fixtures.');
  WriteLn('  --show-test-fixtures  Komplement: behaelt Test-Fixture-Findings');
  WriteLn('                        auch bei default-Profile.');
  WriteLn('');
  WriteLn('Conditional-Compilation (A.5):');
  WriteLn('  --ifdef-aware         Lexer ueberspringt {$IFDEF X}-Branches');
  WriteLn('                        wo X NICHT im Define-Set steht.');
  WriteLn('                        Auto-On bei --profile selftest-quiet');
  WriteLn('                        (mit MSWINDOWS,WIN64,UNICODE,CONDITIONALEXPRESSIONS);');
  WriteLn('                        sonst Default OFF.');
  WriteLn('  --no-ifdef-aware      Opt-Out vom Profile-Auto-Default - alle Branches.');
  WriteLn('  --define <X>[,Y,Z]    Defines fuer --ifdef-aware. Mehrfach moeglich.');
  WriteLn('                        Beispiel: --define MSWINDOWS,WIN64,UNICODE');
  WriteLn('');
  WriteLn('Other:');
  WriteLn('  --help, -h, -?, /?    Show this help');
  WriteLn('  --version             Print version and exit');
  WriteLn('');
  WriteLn('Exit codes:');
  WriteLn('   0 = clean');
  WriteLn('   1 = hints only');
  WriteLn('   2 = warnings present');
  WriteLn('   3 = errors present');
  WriteLn('   4 = read errors (parser/IO), no higher tier reached');
  WriteLn('  99 = tool error (bad args, missing path, ...)');
  WriteLn('');
  WriteLn('  The tiers outrank each other in that order: a run with errors AND');
  WriteLn('  read errors exits 3, not 4. --fail-on lowers a suppressed tier to');
  WriteLn('  0 - but a run that hit read errors lowers to 4 instead, so an');
  WriteLn('  incomplete scan is never reported as success. --fail-on none is');
  WriteLn('  the one exception and always exits 0. Tool errors (99) are decided');
  WriteLn('  before --fail-on is consulted and cannot be lowered at all.');
  WriteLn('');
  WriteLn('Switch syntax: both "--key value" and "--key=value" are accepted.');
end;

class procedure TConsoleRunner.WriteVersion;
begin
  WriteLn(SCA_TOOLNAME, ' v', SCA_VERSION);
end;

{ ---- Sonar Helpers ---- }

function SanitizeSonarKey(const S: string): string;
// Sonar akzeptiert als projectKey nur Buchstaben, Ziffern und - _ . : ;
// alles andere wird zu '-' zusammengezogen. Ein Key aus reinen Ziffern
// wird serverseitig abgelehnt und bekommt deshalb ein Praefix.
var
  C, Prev  : Char;
  HasAlpha : Boolean;
begin
  Result   := '';
  Prev     := #0;
  HasAlpha := False;
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', ':']) then
    begin
      Result := Result + C;
      Prev   := C;
      if not CharInSet(C, ['0'..'9']) then HasAlpha := True;
    end
    else if Prev <> '-' then
    begin
      Result := Result + '-';
      Prev   := '-';
    end;
  end;
  while (Result <> '') and CharInSet(Result[1], ['-', '.', ':']) do
    Delete(Result, 1, 1);
  while (Result <> '') and CharInSet(Result[Length(Result)], ['-', '.', ':']) do
    Delete(Result, Length(Result), 1);
  if (Result <> '') and not HasAlpha then Result := 'delphi-' + Result;
end;

const
  // Kopf des Templates als Konstante: als Folge von L.Add-Zeilen war die
  // erzeugende Routine ueber die LongMethod-Grenze gewachsen.
  SONAR_TEMPLATE_HEADER : array[0..17] of string = (
    '# SonarQube Generic Issue Import - written by StaticCodeAnalyser',
    '# --sonar-init. projectKey/projectName are derived from the folder',
    '# name - CHECK THEM: the key has to match the project in SonarQube.',
    '#',
    '#   analyser.exe --path . --sonar-export sca-findings.json',
    '#   sonar-scanner',
    '#',
    '# Server URL and token are NOT in this file on purpose: it is',
    '# committed, and a cloned repo must not be able to redirect your',
    '# token to a foreign host. Pass them via the environment:',
    '#',
    '#   set SONAR_HOST_URL=https://sonarqube.example.com',
    '#   set SONAR_TOKEN=<token>',
    '#',
    '# If your team keeps the URL in the repo, uncomment the next line.',
    '# sonar-scanner reads it; StaticCodeAnalyser deliberately ignores it.',
    '# sonar.host.url=https://sonarqube.example.com',
    '');

function BuildSonarPropertiesTemplate(const ADir, ABranch,
  AOrg: string): string;
// Das Template soll OHNE Nacharbeit laufen: der projectKey wird aus dem
// Ordnernamen abgeleitet statt '<your-project-key>' zu schreiben - der
// Platzhalter war als Key syntaktisch ungueltig, der sonar-scanner brach
// darauf ab. Host und Token stehen bewusst NICHT drin (die Datei liegt im
// Repo), sondern als kommentierte Env-Anleitung.
//
// ABranch/AOrg sind der einzige Ort, an dem --sonar-branch bzw.
// SONAR_ORGANIZATION den Export ueberhaupt beeinflussen KOENNEN: das
// Generic Issue Format kennt kein Branch-Feld, den Branch liest allein
// der sonar-scanner - und zwar aus dieser Datei.
var
  Folder, Key, S : string;
  L : TStringList;
begin
  Folder := ExtractFileName(ExcludeTrailingPathDelimiter(ADir));
  Key    := SanitizeSonarKey(Folder);
  if Key = '' then
  begin
    Folder := 'Delphi Project';
    Key    := 'delphi-project';
  end;

  L := TStringList.Create;
  try
    for S in SONAR_TEMPLATE_HEADER do
    begin
      L.Add(S);
    end;
    L.Add('sonar.projectKey=' + Key);
    L.Add('sonar.projectName=' + Folder);
    if AOrg <> '' then
    begin
      L.Add('sonar.organization=' + AOrg);
    end;
    if ABranch <> '' then
    begin
      L.Add('sonar.branch.name=' + ABranch);
    end;
    L.Add('sonar.sources=.');
    L.Add('sonar.sourceEncoding=UTF-8');
    L.Add('sonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**');
    L.Add('');
    L.Add('# SCA findings as external issues (Generic Issue Format)');
    L.Add('sonar.externalIssuesReportPaths=sca-findings.json');
    L.Add('');
    L.Add('# Alternative: SARIF (Sonar deduplicates neither - pick ONE)');
    L.Add('# sonar.sarifReportPaths=sca-findings.sarif');
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure WriteTextNoBom(const AFile, AText: string);
// Eigene Routine, damit RunSonarInit mit EINEM try auskommt: das
// Encoding-Objekt braucht ein finally, der Schreibfehler ein except -
// beides ineinander ist genau das, was NestedTry anmahnt.
var
  Enc : TEncoding;
begin
  // Ohne BOM: der sonar-scanner liest die Datei als Java-Properties,
  // ein BOM landet sonst im ersten Schluessel.
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(AFile, AText, Enc);
  finally
    Enc.Free;
  end;
end;

function ReadTextOrEmpty(const AFile: string): string;
begin
  try
    Result := TFile.ReadAllText(AFile, TEncoding.UTF8);
  except
    Result := '';
  end;
end;

function BuildSonarConfig(const Args: TCliArgs): TSonarConfig; forward;

function RunSonarInit(const Args: TCliArgs): Integer;
// --sonar-init: legt sonar-project.properties an. Existiert die Datei,
// wird auf .sample ausgewichen - und auch die wird NICHT ueberschrieben:
// sie kann von Hand angepasst worden sein (frueher ging genau das
// wortlos verloren). Gleicher Inhalt = No-Op, abweichender = Abbruch.
var
  TargetDir, OutFile, Tmpl : string;
  Cfg : TSonarConfig;
begin
  if Args.Path <> '' then TargetDir := Args.Path else TargetDir := GetCurrentDir;
  // GetFullPath VOR dem Ableiten des Schluessels. Ohne das war ausgerechnet
  // die dokumentierte Aufrufform kaputt: '--path .' liefert als Ordnername
  // '.', was der Sanitizer zu '' abschleift - der Schluessel fiel auf
  // 'delphi-project' zurueck, statt den Projektordner zu benennen. Und ein
  // Pfad mit Schraegstrichen ('--path C:/repo') machte den GANZEN Pfad zum
  // Schluessel, weil ExtractFileName unter Windows nur '\' trennt.
  // Am Binary reproduziert 2026-08-08.
  TargetDir := IncludeTrailingPathDelimiter(TPath.GetFullPath(TargetDir));
  // Branch/Organization aus CLI, Env und INI - sie landen im Template,
  // weil der sonar-scanner sie dort liest.
  Cfg       := BuildSonarConfig(Args);
  Tmpl      := BuildSonarPropertiesTemplate(TargetDir, Cfg.Branch,
                                            Cfg.Organization);
  OutFile   := TargetDir + 'sonar-project.properties';

  if TFile.Exists(OutFile) then
  begin
    OutFile := OutFile + '.sample';
    WriteLn('Existing sonar-project.properties detected - writing ',
            ExtractFileName(OutFile), ' instead.');
  end;

  if TFile.Exists(OutFile) then
  begin
    if ReadTextOrEmpty(OutFile) = Tmpl then
    begin
      WriteLn(OutFile, ' is already up to date - nothing written.');
      Exit(Integer(cecClean));
    end;
    WriteLn(ErrOutput, 'sonar-init aborted: ', OutFile, ' exists and differs.');
    WriteLn(ErrOutput, 'Rename or delete it first - it may hold manual edits.');
    Exit(Integer(cecToolError));
  end;

  try
    WriteTextNoBom(OutFile, Tmpl);
    WriteLn('Wrote ', OutFile);
    WriteLn('Check sonar.projectKey before running sonar-scanner.');
    Result := Integer(cecClean);
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'sonar-init failed: ', E.Message);
      Result := Integer(cecToolError);
    end;
  end;
end;

function BuildSonarConfig(const Args: TCliArgs): TSonarConfig;
var
  Cli       : TSonarCliOverrides;
  Project   : string;
begin
  Cli := Default(TSonarCliOverrides);
  Cli.HostUrl    := Args.SonarHost;
  Cli.Token      := Args.SonarToken;
  Cli.ProjectKey := Args.SonarProject;
  Cli.Branch     := Args.SonarBranch;
  Cli.Insecure   := Args.SonarInsecure;
  Cli.ConfigPath := Args.SonarConfig;

  if Args.Path <> '' then Project := Args.Path
  else if Args.SingleFile <> '' then Project := ExtractFilePath(Args.SingleFile)
  else Project := GetCurrentDir;

  Result := TSonarConfigResolver.Resolve(Cli, Args.SonarConfig, Project);
end;

function RunSonarTest(const Args: TCliArgs): Integer;
// --sonar-test: Connectivity health-check ohne Analyse.
var
  Cfg : TSonarConfig;
  R   : TSonarHealthResult;
begin
  Cfg := BuildSonarConfig(Args);
  WriteLn('Sonar config:');
  WriteLn('  host    = ', Cfg.HostUrl,   '   (', Cfg.SourceHostUrl, ')');
  WriteLn('  project = ', Cfg.ProjectKey,'   (', Cfg.SourceProjectKey, ')');
  if Cfg.Organization <> '' then
    WriteLn('  org     = ', Cfg.Organization, '   (SonarCloud)');
  if Cfg.Token <> '' then
    WriteLn('  token   = (', Length(Cfg.Token), ' chars from ', Cfg.SourceToken, ')')
  else
    WriteLn('  token   = (none)');
  // Ein 'PT:'-Eintrag ist Base64, keine Verschluesselung. Er wird gelesen
  // (auch unter Windows), darf den Nutzer aber nicht in dem Glauben lassen,
  // die INI sei DPAPI-geschuetzt.
  if Cfg.TokenIsPlaintext then
  begin
    WriteLn(ErrOutput, 'WARNING: the token in analyser.ini is stored as ' +
                       'plaintext (PT: = Base64, not encrypted).');
    WriteLn(ErrOutput, '         Anyone who can read the file has the token. ' +
                       'Prefer SONAR_TOKEN from the environment,');
    WriteLn(ErrOutput, '         or re-save it on Windows so it gets ' +
                       'DPAPI-protected for your account.');
  end;
  // Eine Repo-eigene sonar-project.properties darf den Host nicht
  // bestimmen (sonst geht der Token des Nutzers an einen fremden
  // Server). Der Wert wird ignoriert - aber sichtbar, damit eine
  // legitime Repo-Konfiguration nicht raetselhaft wirkungslos bleibt.
  if Cfg.IgnoredRepoHost <> '' then
  begin
    WriteLn('  Hinweis: sonar.host.url aus sonar-project.properties wird');
    WriteLn('           ignoriert (', Cfg.IgnoredRepoHost, ').');
    WriteLn('           Host per --sonar-host, SONAR_HOST_URL oder analyser.ini setzen.');
  end;
  WriteLn('');
  R := TSonarHealthCheck.Run(Cfg);
  Write(TSonarHealthCheck.FormatChecklist(R));
  if R.Healthy then Result := Integer(cecClean)
  else Result := Integer(cecToolError);
end;

{ ---- Per-Detector-Timing-Tabelle ---- }

procedure WriteDetectorTimingsMarkdown(const AOutFile: string = '');
// Schreibt eine Markdown-Tabelle pro Detektor mit TotalMs / CallCount /
// AvgMs / %-Anteil-am-Scan, sortiert nach TotalMs absteigend. Daten kommt
// aus gDetectorTimings (befuellt durch das AOnTime-Lambda in ParseLeaks).
// AOutFile = '' -> stdout (WriteLn). AOutFile <> '' -> zusaetzlich
// als UTF-8 in die Datei schreiben (Archiv-Komfort; stdout-Pipes gehen seit
// dem dpr-Redirect-Support 2026-07-05 ebenfalls).
var
  Pairs       : TArray<TPair<string, TPair<Int64, Integer>>>;
  TotalMs     : Int64;
  i           : Integer;
  Name        : string;
  Acc         : TPair<Int64, Integer>;
  Avg, Pct    : Double;
  Lines       : TStringList;
begin
  if (gDetectorTimings = nil) or (gDetectorTimings.Count = 0) then Exit;

  // Snapshot in Array kopieren damit wir sortieren koennen.
  Pairs := gDetectorTimings.ToArray;
  // Sortieren nach TotalMs absteigend.
  TArray.Sort<TPair<string, TPair<Int64, Integer>>>(Pairs,
    TComparer<TPair<string, TPair<Int64, Integer>>>.Construct(
      function(const L, R: TPair<string, TPair<Int64, Integer>>): Integer
      begin
        Result := CompareValue(R.Value.Key, L.Value.Key);
      end));

  TotalMs := 0;
  for i := 0 to High(Pairs) do
    Inc(TotalMs, Pairs[i].Value.Key);

  // Zeilen in TStringList aufbauen (single source of truth) - danach
  // BEIDE Pfade: WriteLn auf stdout/CONOUT$ + optional File-Save.
  Lines := TStringList.Create;
  try
    Lines.Add('');
    Lines.Add('## Per-Detector Timing');
    Lines.Add('');
    Lines.Add('| Rank | Detector | Total ms | Calls | Avg ms | % Scan |');
    Lines.Add('|---:|---|---:|---:|---:|---:|');
    for i := 0 to High(Pairs) do
    begin
      Name := Pairs[i].Key;
      Acc  := Pairs[i].Value;
      if Acc.Value > 0 then
        Avg := Acc.Key / Acc.Value
      else
        Avg := 0;
      if TotalMs > 0 then
        Pct := (Acc.Key * 100.0) / TotalMs
      else
        Pct := 0;
      Lines.Add(Format('| %d | %s | %d | %d | %.2f | %.1f%% |',
        [i + 1, Name, Acc.Key, Acc.Value, Avg, Pct]));
    end;
    Lines.Add('');
    Lines.Add(Format('Total: %d ms over %d detectors',
      [TotalMs, Length(Pairs)]));

    // stdout-Pfad: Konsole ODER Redirect-Ziel (dpr bindet umgeleitete
    // Streams seit 2026-07-05 an ihre Std-Handles).
    for i := 0 to Lines.Count - 1 do
      WriteLn(Lines[i]);

    // File-Pfad: explizit gewuenschte Zusatz-Datei.
    if AOutFile <> '' then
    begin
      try
        Lines.SaveToFile(AOutFile, TEncoding.UTF8);
      except
        on E: Exception do
          WriteLn(ErrOutput, 'Could not write timings to ', AOutFile,
                  ': ', E.Message);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Run ---- }

class function TConsoleRunner.Run(const Args: TCliArgs): Integer;
var
  Findings  : TObjectList<TLeakFinding>;
  Files     : TStringList;
  RepoInfo  : string;
  Settings  : TRepoSettings;
begin
  // Sofort-Exits
  if Args.ParseError <> '' then
  begin
    WriteLn(ErrOutput, 'Error: ', Args.ParseError);
    WriteLn(ErrOutput, 'Try --help for usage.');
    Exit(Integer(cecToolError));
  end;
  if Args.Help    then begin WriteHelp;    Exit(Integer(cecClean)); end;
  if Args.ShowVersion then begin WriteVersion; Exit(Integer(cecClean)); end;

  // Sonar standalone actions - kein Analyse-Run noetig
  if Args.SonarInit then Exit(RunSonarInit(Args));
  if Args.SonarTest then Exit(RunSonarTest(Args));

  // A.5 Phase 1b-Wiring: IFDEF-Awareness aus CLI-Args in den globalen
  // Lexer-Config-State spiegeln. Wirkt fuer alle TParser2.ParseSource-
  // Aufrufe waehrend des Runs.
  //
  // Profile-Auto-Default: --profile selftest-quiet aktiviert IfdefAware
  // automatisch (mit MSWINDOWS+WIN64+UNICODE+CONDITIONALEXPRESSIONS als
  // Default-Defines). User kann via --no-ifdef-aware opt-out wenn er
  // bewusst alle Branches scannen will.
  var EffectiveIfdefAware   : Boolean := Args.IfdefAware;
  var EffectiveIfdefDefines : string  := Args.IfdefDefines;
  if (not EffectiveIfdefAware) and (not Args.NoIfdefAware)
     and SameText(Args.Profile, 'selftest-quiet') then
  begin
    EffectiveIfdefAware := True;
    if EffectiveIfdefDefines = '' then
      EffectiveIfdefDefines := 'MSWINDOWS,WIN64,UNICODE,CONDITIONALEXPRESSIONS';
  end;
  if Args.NoIfdefAware then
    EffectiveIfdefAware := False;

  // Die effektiven IFDEF-Defines wandern weiter unten als Request-Feld in
  // uEngineApi.Run (das setzt den Lexer-State) - hier nur noch die Meldung.
  if EffectiveIfdefAware and (not Args.Quiet) then
    WriteLn(Format('IFDEF-Awareness aktiv: %d Define(s).',
      [Length(EffectiveIfdefDefines.Split([',', ';']))]));

  // Pfad-Validierung
  if (Args.Path <> '') and not TDirectory.Exists(Args.Path) then
  begin
    WriteLn(ErrOutput, 'Error: Pfad existiert nicht: ', Args.Path);
    Exit(Integer(cecToolError));
  end;
  if (Args.SingleFile <> '') and not TFile.Exists(Args.SingleFile) then
  begin
    WriteLn(ErrOutput, 'Error: Datei existiert nicht: ', Args.SingleFile);
    Exit(Integer(cecToolError));
  end;

  Findings := nil;
  Files    := nil;
  Settings := nil;
  try
    // Custom-Rules laden BEVOR die Analyse startet (uStaticAnalyzer2
    // ruft TCustomRuleDetector.AnalyzeFile pro Datei auf - HasRules-Check
    // sorgt dafuer dass ohne --custom-rules nichts passiert).
    if Args.CustomRules <> '' then
    begin
      if not TFile.Exists(Args.CustomRules) then
      begin
        WriteLn(ErrOutput, 'Error: Custom-Rules-Datei existiert nicht: ',
                Args.CustomRules);
        Exit(Integer(cecToolError));
      end;
      try
        TCustomRuleDetector.LoadFromYaml(Args.CustomRules);
        if not Args.Quiet then
          WriteLn(Format('Loaded %d custom rule(s) from %s',
            [TCustomRuleDetector.RuleCount, Args.CustomRules]));
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'Custom rules error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end
    else
      // Sicherheitshalber Reset - falls vorheriger CLI-Run im selben Prozess
      // Rules zurueckgelassen hat (relevant wenn Tests den Runner mehrfach
      // aufrufen).
      TCustomRuleDetector.ClearRules;

    // Settings BEVOR jeder Analyse laden + anwenden, damit [Rules]
    // Profile/MinSeverity aus der INI greifen UND --profile / --min-severity
    // sie ueberschreiben koennen. Vor V0.9.0 lief CLI komplett ohne
    // INI-Anwendung - daher liefen immer alle Detektoren.
    Settings := TRepoSettings.Create;
    try Settings.Load; except end;
    // Herkunft merken, BEVOR die CLI-Argumente drueberschreiben - nur so
    // laesst sich unten sagen, woher das Profil wirklich kommt.
    var ProfileFromIni : string := Settings.Profile;
    if Args.Profile     <> '' then Settings.Profile     := Args.Profile;
    if Args.MinSeverity <> '' then Settings.MinSeverity := Args.MinSeverity;

    // ---- Baseline-Scan-Aufloesung (Konzept_BaselineSca Inkrement 2) ----
    // Praezedenz: --baseline <file> > [Baseline] File= > .sca-Standardort.
    // FRUEH und HART: bei --baseline-scan y ohne existierende Datei bricht
    // der Lauf VOR dem Scan mit cecToolError ab - in CI darf ein
    // Tippfehler nicht lautlos 'alles ist neu' melden. (Der Anzeige-
    // Filter TBaselineSet in EXE/Plugin bleibt bewusst fail-open.)
    var EffBaseline      : string := Args.Baseline;
    var EffWriteBaseline : string := Args.WriteBaseline;
    var BlProjOrGroup    : string := Args.GroupFile;
    if BlProjOrGroup = '' then BlProjOrGroup := Args.ProjectFile;
    var WantBaselineScan : Boolean :=
      SameText(Args.BaselineScan, 'y') or SameText(Args.BaselineScan, 'yes')
      or (Args.BaselineScan = '1');
    if (Args.BaselineScan <> '') and (not WantBaselineScan) and
       not (SameText(Args.BaselineScan, 'n') or
            SameText(Args.BaselineScan, 'no') or (Args.BaselineScan = '0')) then
    begin
      WriteLn(ErrOutput,
        'Error: --baseline-scan erwartet y|n, bekommen: ', Args.BaselineScan);
      Exit(Integer(cecToolError));
    end;
    // Fingerprint-Modus aus dem CLI-Schalter. NUR pruefen und merken -
    // gesetzt wird er unmittelbar vor Write bzw. Apply (s. u.).
    //
    // Warum nicht hier: TAnalysisSession.ApplyConfig ruft
    // ResetEngineConfigDefaults, und dort werden die beiden
    // Baseline-Globals seit 2026-08-08 bewusst zurueckgesetzt (damit ein
    // zweiter Scan im selben Prozess nichts erbt). Ein hier gesetzter
    // Wert waere also beim Scan wieder weg - genau die Falle, in die
    // schon --custom-rules gelaufen ist. Nachgemessen: die Baseline trug
    // trotz '--baseline-path-fingerprint y' weiterhin
    // "pathFingerprint": false.
    var CliPathFp     : Boolean := False;
    var HasCliPathFp  : Boolean := Args.BaselinePathFp <> '';
    if HasCliPathFp then
    begin
      if SameText(Args.BaselinePathFp, 'y') or
         SameText(Args.BaselinePathFp, 'yes') or
         (Args.BaselinePathFp = '1') then
      begin
        CliPathFp := True;
      end
      else if SameText(Args.BaselinePathFp, 'n') or
              SameText(Args.BaselinePathFp, 'no') or
              (Args.BaselinePathFp = '0') then
      begin
        CliPathFp := False;
      end
      else
      begin
        WriteLn(ErrOutput,
          'Error: --baseline-path-fingerprint erwartet y|n, bekommen: ',
          Args.BaselinePathFp);
        Exit(Integer(cecToolError));
      end;
    end;
    if WantBaselineScan then
    begin
      var Probed := TStringList.Create;
      try
        if EffBaseline = '' then
          EffBaseline := Settings.BaselineFile;
        if EffBaseline = '' then
          EffBaseline := TBaseline.ResolveBaselinePath(
            BlProjOrGroup, Args.Path, Probed)
        else
          Probed.Add(EffBaseline);
        if (EffBaseline = '') or not FileExists(EffBaseline) then
        begin
          WriteLn(ErrOutput, 'Error: baseline scan requested but no ' +
            'baseline file found - looked for:');
          for var ProbedLine in Probed do
            WriteLn(ErrOutput, '  ', ProbedLine);
          Exit(Integer(cecToolError));
        end;
        if not Args.Quiet then
          WriteLn('Baseline: ', EffBaseline);
      finally
        Probed.Free;
      end;
    end
    else if (EffBaseline <> '') and not FileExists(EffBaseline) then
    begin
      // Explizit angegebene, fehlende Baseline war frueher ein stiller
      // No-op ('leer laden' -> 0 Drops) - jetzt harter Fehler.
      WriteLn(ErrOutput, 'Error: --baseline file not found: ', EffBaseline);
      Exit(Integer(cecToolError));
    end;
    // Format pruefen, BEVOR gescannt wird: eine verwechselte Datei (typisch
    // ein SARIF-Report) parst zwar als JSON, traegt aber keine Fingerprints -
    // Apply filterte daraufhin nichts und das Gate meldete den kompletten
    // Bestand als neu. Ein falsch-gruenes bzw. falsch-rotes Gate ist der
    // teuerste Zustand fuer ein CI-Werkzeug (Audit 2026-08-08).
    if EffBaseline <> '' then
    begin
      var BlReason : string;
      if not TBaseline.IsBaselineFile(EffBaseline, BlReason) then
      begin
        WriteLn(ErrOutput, 'Error: --baseline is not a baseline file: ',
          EffBaseline);
        WriteLn(ErrOutput, '       ', BlReason);
        Exit(Integer(cecToolError));
      end;
    end;
    // '--write-baseline auto' -> .sca-Standardziel des Scan-Ziels.
    if SameText(EffWriteBaseline, 'auto') then
    begin
      EffWriteBaseline := TBaseline.DefaultBaselineTarget(
        BlProjOrGroup, Args.Path);
      if EffWriteBaseline = '' then
      begin
        WriteLn(ErrOutput, 'Error: --write-baseline auto braucht ' +
          '--project/--project-group oder --path');
        Exit(Integer(cecToolError));
      end;
    end;
    // ApplyDetectorThresholds (volle Config-Anwendung) macht jetzt
    // uEngineApi.Run via Req.ApplyRepoIni mit denselben Overrides; Settings
    // hier bleibt nur fuer Profile-Read (Fixture-Default + Message unten).
    // Das aktive Regelset IMMER nennen (ausser --quiet). Bis 0.9.8 erschien
    // diese Zeile nur, wenn --profile oder --min-severity explizit uebergeben
    // wurden - kam das Profil aus der analyser.ini, schwieg die CLI. Ein
    // 'ide-fast' in der INI liefert fuer Hinweis-Regeln NULL Funde, und der
    // Aufrufer sieht als einzige Erklaerung eine leere Ergebnisliste. Genau
    // dieser Fall hat in der Entwicklung eine Fehldiagnose ('Binary kaputt')
    // ausgeloest; er ist die haeufigste Support-Frage, die aus einer einzigen
    // Ausgabezeile beantwortbar ist.
    if not Args.Quiet then
    begin
      var ProfileSrc  : string;
      var SeveritySrc : string;
      var ActiveKinds : Integer;
      // Herkunft NICHT am Wert festmachen, sondern daran, ob die INI
      // ueberhaupt existiert. Vorher stand auf einem frischen Rechner
      // 'analyser.ini' in der Zeile, obwohl keine da war - beim
      // Erste-Minuten-Durchlauf 2026-08-02 aufgefallen. Wer dem Hinweis
      // folgt und die Datei sucht, findet nichts.
      var HasIni : Boolean := FileExists(TRepoSettings.ResolvedConfigPath);
      if Args.Profile <> '' then ProfileSrc := '--profile'
      else if HasIni and (ProfileFromIni <> '') then ProfileSrc := 'analyser.ini'
      else ProfileSrc := 'Default';
      if Args.MinSeverity <> '' then SeveritySrc := '--min-severity'
      else if HasIni then SeveritySrc := 'analyser.ini/Default'
      else SeveritySrc := 'Default';
      // GetProfile einmal aufloesen - der Aufruf laedt den Katalog.
      var Active : TFindingKinds := TRuleCatalog.GetProfile(Settings.Profile);
      ActiveKinds := 0;
      for var K := Low(TFindingKind) to High(TFindingKind) do
        if K in Active then Inc(ActiveKinds);
      WriteLn(Format('Rule-set: Profile=%s (%s), MinSeverity=%s (%s), %d rules active',
        [Settings.Profile, ProfileSrc, Settings.MinSeverity, SeveritySrc,
         ActiveKinds]));
    end;

    // Per-Detector-Timing aktivieren wenn --time-detectors angefordert.
    // Engine-internes AOnTime-Lambda erkennt das nil-vs-Assigned und
    // summiert pro Detektor ueber den gesamten Scan.
    if Args.TimeDetectors then
      gDetectorTimings := TDictionary<string, TPair<Int64, Integer>>.Create;

    // C.5 Telemetrie: pro suppressed Finding eine CSV-Zeile sammeln,
    // wenn --telemetry-csv <file> aktiv ist. uSuppression appendet
    // wenn gSuppressionTelemetry assigned ist.
    if Args.TelemetryCsv <> '' then
      gSuppressionTelemetry := TSuppressionTelemetry.Create;

    // Test-Fixture-Auto-Default je nach Profile (wenn vom User nicht
    // explizit per --hide-/--show-test-fixtures ueberschrieben):
    //   * strict         -> AUS (User will alles sehen)
    //   * default        -> AN  (Production-Code-Focus)
    //   * selftest-quiet -> AN  (Dogfooding ohne Fixture-Noise)
    //   * andere/custom  -> AUS (konservativer Default)
    var EffectiveHideTestFixtures: Boolean;
    if Args.HideTestExplicit then
      EffectiveHideTestFixtures := Args.HideTestFixtures
    else
      EffectiveHideTestFixtures :=
        SameText(Settings.Profile, 'default') or
        SameText(Settings.Profile, 'selftest-quiet');

    try
      // Request fuer die Engine-Facade bauen. Config kommt aus der repo-INI
      // (Req.ApplyRepoIni) mit denselben Arg-Overrides wie zuvor; ConfigRoot =
      // Args.Path, weil das Scan-Ziel davon abweichen kann (Single-File).
      // IFDEF-Defines + Profil/Severity wandern als Request-Felder statt als
      // globaler State. Scope-Wahl + VCS-Enumeration + Early-Exit bleiben hier
      // CLI-Policy; die Datei-Liste geht via ssFileList an Run.
      var Req := TScanRequest.Init;
      Req.ApplyRepoIni    := True;
      Req.ConfigRoot      := Args.Path;
      Req.Profile         := Args.Profile;
      Req.MinSeverityName := Args.MinSeverity;
      // Perf Stufe 2 (2026-07-25): opt-in Per-File-Parallelisierung.
      // Gate-Rueckfall auf seriell (AutoDiscovery/Custom-Rules/Timings)
      // entscheidet die Engine selbst (uStaticAnalyzer2).
      //
      // 2026-08-08: Der Modus ist DEFEKT (s. Hilfetext). Wer ihn trotzdem
      // setzt, bekommt eine unuebersehbare Warnung auf stderr - still
      // falsche Ergebnisse sind fuer ein CI-Werkzeug der teuerste
      // denkbare Zustand, und die frueher zugesagte Byte-Identitaet ist
      // nachweislich falsch.
      if Args.Parallel then
      begin
        WriteLn(ErrOutput, '');
        WriteLn(ErrOutput, 'WARNUNG: --parallel ist DEFEKT und liefert nicht reproduzierbare');
        WriteLn(ErrOutput, '         Ergebnisse. Elf Detektoren teilen sich unit-globale');
        WriteLn(ErrOutput, '         TRegEx-Instanzen; unter Last gehen ECHTE Funde verloren');
        WriteLn(ErrOutput, '         und es entstehen erfundene Fehler-Records.');
        WriteLn(ErrOutput, '         Der Modus ist ausserdem LANGSAMER als der serielle Lauf.');
        WriteLn(ErrOutput, '         Fuer belastbare Ergebnisse: --parallel weglassen.');
        WriteLn(ErrOutput, '');
      end;
      Req.Parallel        := Args.Parallel;
      Req.ParallelWorkers := StrToIntDef(Args.ParallelWorkers, 0);
      if EffectiveIfdefAware and (EffectiveIfdefDefines <> '') then
        Req.IfdefDefines := EffectiveIfdefDefines.Split([',', ';']);
      // Custom-Rules: der Pfad MUSS in den Request. Der CLI laedt die YAML
      // zwar schon oben (fuer die Frueh-Validierung und die Meldung
      // "Loaded N custom rule(s)"), aber danach ruft
      // TAnalysisSession.ApplyConfig ueber ApplyRepoIni die
      // ApplyDetectorThresholds - und deren else-Zweig ruft ClearRules,
      // sobald in der analyser.ini kein [Detectors] CustomRulesFile steht
      // (uRepoSettings:1608). Bis 2026-08-08 blieb Req.CustomRulesPath
      // deshalb leer, die frisch geladenen Regeln wurden geloescht, und
      // der Lauf meldete "Loaded 2 custom rule(s)" bei null Funden -
      // reproduziert mit 2 Regeln x 4 Treffern = 8 erwarteten Funden.
      // Mit gesetztem Pfad laedt ApplyConfig sie NACH dem INI-Schritt neu
      // (uEngineApi:419) - das repariert zugleich die Praezedenz: der
      // explizite Schalter gewinnt jetzt gegen die INI, nicht umgekehrt.
      Req.CustomRulesPath := Args.CustomRules;

      // Diff-Mode A<->B: nur zwischen Commits geaenderte Dateien (PR-Review).
      if Args.Diff <> '' then
      begin
        Files := TVcsChanges.GetChangedPasFilesDiff(Args.Path, Args.Diff, RepoInfo, Settings);
        if (Files = nil) or (Files.Count = 0) then
        begin
          if not Args.Quiet then
            WriteLn('No .pas files differ in range ', Args.Diff, '. ', RepoInfo);
          Exit(Integer(cecClean));
        end;
        if not Args.Quiet then
          WriteLn(RepoInfo);
        Req.Scope := ssFileList;
        Req.Files := Files.ToStringArray;
        Req.Path  := Args.Path;
        Req.IndexRoot := Args.IndexRoot;
      end
      // Branch-Mode: VCS-geaenderte Dateien ermitteln, dann analysieren
      else if Args.Branch then
      begin
        Files := TVcsChanges.GetChangedPasFilesAuto(Args.Path, RepoInfo, Settings);
        if (Files = nil) or (Files.Count = 0) then
        begin
          if not Args.Quiet then
            WriteLn('No VCS-changed .pas files found. ', RepoInfo);
          Exit(Integer(cecClean));
        end;
        if not Args.Quiet then
          WriteLn(Format('Analyzing %d changed file(s). %s', [Files.Count, RepoInfo]));
        Req.Scope := ssFileList;
        Req.Files := Files.ToStringArray;
        Req.Path  := Args.Path;
        Req.IndexRoot := Args.IndexRoot;
      end
      // Projekt-Mode (Scan-Scope-Konzept 2026-07-20): .dproj-Dateiliste
      else if Args.ProjectFile <> '' then
      begin
        if not Args.Quiet then
          WriteLn('Analyzing project: ', Args.ProjectFile);
        Req.Scope     := ssProject;
        Req.Path      := Args.ProjectFile;
        Req.IndexRoot := Args.IndexRoot;
      end
      // Projektgruppen-Mode: .groupproj -> Union aller Projekt-Listen
      else if Args.GroupFile <> '' then
      begin
        if not Args.Quiet then
          WriteLn('Analyzing project group: ', Args.GroupFile);
        Req.Scope     := ssProjectGroup;
        Req.Path      := Args.GroupFile;
        Req.IndexRoot := Args.IndexRoot;
      end
      // Single-File-Mode
      else if Args.SingleFile <> '' then
      begin
        if not Args.Quiet then
          WriteLn('Analyzing: ', Args.SingleFile);
        Req.Scope := ssSingleFile;
        Req.Path  := Args.SingleFile;
      end
      // Full-Recursive-Mode
      else
      begin
        if not Args.Quiet then
          WriteLn('Analyzing recursively: ', Args.Path);
        Req.Scope := ssRecursive;
        Req.Path  := Args.Path;
      end;

      // Zentraler Engine-Aufruf (ersetzt die bisher 3x duplizierte
      // Orchestrierung - jetzt eine Facade fuer CLI/IDE/Form).
      var Ses := TAnalysisSession.Create;
      try
        var Res := Ses.Run(Req);
        try
          Findings := Res.ReleaseFindings;   // Ownership -> CLI (finally gibt frei)
        finally
          Res.Free;
        end;
      finally
        Ses.Free;
      end;

      // --parallel angenommen, aber seriell gelaufen? Das sagen. Der
      // Rueckfall ist Absicht (Determinismus geht vor Tempo), aber
      // schweigend war er eine Falle: der Aufrufer glaubt, parallel zu
      // messen, und misst seriell. Auf ErrOutput, damit --quiet-Pipelines,
      // die stdout weiterverarbeiten, die Warnung trotzdem sehen.
      if Args.Parallel and (gParallelDeclineReason <> '') then
      begin
        // Erst stdout leeren. Gehen beide Stroeme in dasselbe Terminal,
        // zerreissen sie sich sonst mitten im Wort - beobachtet:
        // "...ueber die DateireihenSummary: 0 Error(s)...folge und ist".
        // Der Inhalt stimmt, lesbar ist es nicht.
        Flush(Output);
        WriteLn(ErrOutput,
          'Hinweis: --parallel war gesetzt, der Scan lief aber seriell - '
          + gParallelDeclineReason + '.');
        Flush(ErrOutput);
      end;
    except
      on E: Exception do
      begin
        WriteLn(ErrOutput, 'Tool error: ', E.ClassName, ': ', E.Message);
        Exit(Integer(cecToolError));
      end;
    end;

    if Findings = nil then
      Findings := TObjectList<TLeakFinding>.Create(True);

    // ---- Test-Fixture-Filter (vor Baseline + Output) ----
    // Findings aus uTest*/Sample/Demo-Files droppen wenn Profile dies
    // verlangt (Auto-Default) bzw. --hide-test-fixtures explizit gesetzt.
    // fkFileReadError bleibt drin (Diagnostic-Befund), kein Profile-Filter.
    if EffectiveHideTestFixtures then
    begin
      var FixtureDropped := 0;
      // Betroffene DATEIEN mitfuehren, nicht nur zaehlen - siehe die
      // Ausgabe unten.
      var DroppedFiles := TStringList.Create;
      try
        DroppedFiles.Sorted := True;
        DroppedFiles.Duplicates := dupIgnore;
        for var i := Findings.Count - 1 downto 0 do
        begin
          if Findings[i].Kind = fkFileReadError then Continue;
          // BaseDir hier ist der Scan-Wurzel-Pfad - sichert das Pfad-Anchoring
          // gegen externe Repo-Pfade die zufaellig '/tests/' enthalten.
          if TDetectorUtils.IsTestFixturePath(Findings[i].FileName,
               Args.Path) then
          begin
            DroppedFiles.Add(ExtractFileName(Findings[i].FileName));
            Findings.Delete(i);
            Inc(FixtureDropped);
          end;
        end;

        // ERSTE-MINUTEN-FALLE (Durchlauf 2026-08-02): der Filter greift bei
        // Profil 'default' automatisch, und zu den Mustern gehoeren
        // '*Demo.pas', '*Sample.pas' und 'MeineUnit.pas'. Das sind Namen aus
        // UNSEREM Korpus, aber auch genau die, die ein Neuanwender beim
        // Ausprobieren vergibt. Wer seine erste Datei 'Demo.pas' nennt,
        // bekam bisher 'Summary: 0 findings' und eine Zeile, die weder die
        // Datei nannte noch sagte, wie man sie sichtbar macht - und schloss
        // daraus, das Werkzeug funktioniere nicht.
        //
        // Jetzt: die betroffenen Dateien werden genannt, und wenn NICHTS
        // uebrig bleibt, steht die Abhilfe direkt daneben.
        if (not Args.Quiet) and (FixtureDropped > 0) then
        begin
          var Names := DroppedFiles.CommaText;
          if DroppedFiles.Count > MAX_NAMED_FIXTURE_FILES then
            Names := Format('%d Dateien', [DroppedFiles.Count]);
          WriteLn(Format('Test-fixture filter: %d findings dropped in %s',
                         [FixtureDropped, Names]));
          if Findings.Count = 0 then
            WriteLn('  -> nichts uebrig. Wenn das eigener Code ist: '
                  + '--show-test-fixtures');
        end;
      finally
        DroppedFiles.Free;
      end;
    end;

    // ---- Snapshot fuer kuenftige Baseline ----
    // MUSS vor dem Baseline-FILTER laufen: TBaseline.Apply veraendert die
    // Findings-Liste destruktiv. Bis 2026-08-08 stand dieser Block
    // dahinter, weshalb '--baseline alt --write-baseline neu' - das
    // naheliegende Auffrischen, das sogar in der eigenen CI-Doku stand -
    // nur die NEUEN Funde in die Baseline schrieb. Nachgemessen: aus 226
    // Eintraegen wurden 0, und der naechste Build meldete den gesamten
    // Altbestand erneut. Eine Baseline ist ein Abbild des IST-Zustands,
    // nicht der Differenz.
    if EffWriteBaseline <> '' then
    begin
      try
        if HasCliPathFp then
          uSCAConsts.BaselinePathFingerprint := CliPathFp;
        if BlProjOrGroup <> '' then
          uSCAConsts.BaselineFingerprintRoot := ExtractFilePath(BlProjOrGroup)
        else
          uSCAConsts.BaselineFingerprintRoot := Args.Path;
        // Kein ForceDirectories mehr hier: TBaseline.Write legt das
        // Zielverzeichnis selbst an (und vertraegt anders als der
        // Aufruf hier einen blossen Dateinamen ohne Verzeichnisanteil).
        // Die GESCHRIEBENE Anzahl melden, nicht Findings.Count: Lesefehler
        // sind nicht baseline-faehig und werden von Write uebersprungen.
        var BlWritten := TBaseline.Write(Findings, EffWriteBaseline);
        if not Args.Quiet then
          WriteLn(Format('Baseline written: %s (%d findings)',
            [EffWriteBaseline, BlWritten]));
      except
        on E: Exception do
        begin
          // Ein nicht geschriebener Snapshot ist ein Werkzeugfehler: der
          // naechste Lauf haette sonst still die falsche Vergleichsbasis.
          WriteLn(ErrOutput, 'Baseline write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    // ---- Baseline-Filter (vor Output / Exit-Code) ----
    if EffBaseline <> '' then
    begin
      try
        // PathInFingerprint-Modus: Relativierungs-Wurzel = Projekt-/
        // Gruppen-Verzeichnis, sonst Scan-Pfad (nur der Consumer kennt
        // den Zuschnitt; Root leer -> Fallback Dateiname in uBaseline).
        if HasCliPathFp then
          uSCAConsts.BaselinePathFingerprint := CliPathFp;
        if BlProjOrGroup <> '' then
          uSCAConsts.BaselineFingerprintRoot := ExtractFilePath(BlProjOrGroup)
        else
          uSCAConsts.BaselineFingerprintRoot := Args.Path;
        var BlWarnings := TStringList.Create;
        var Dropped : Integer;
        try
          Dropped := TBaseline.Apply(Findings, EffBaseline, BlWarnings);
          for var BlWarn in BlWarnings do
            WriteLn(ErrOutput, 'Baseline warning: ', BlWarn);
        finally
          BlWarnings.Free;
        end;
        if (not Args.Quiet) and (Dropped > 0) then
          WriteLn(Format('Baseline filtered: %d known findings dropped (%s)',
            [Dropped, EffBaseline]));
      except
        on E: Exception do
          WriteLn(ErrOutput, 'Baseline read warning: ', E.Message);
        // Baseline-Fehler ist nicht fatal - Lauf geht ohne Filter weiter
      end;
    end;

    // SARIF-Output (wenn angefordert)
    if Args.ReportSarif <> '' then
    begin
      try
        TSARIFWriter.WriteFile(Args.ReportSarif, Findings, Args.BaseDir,
                               SCA_VERSION, SCA_TOOLNAME);
        if not Args.Quiet then
          WriteLn('SARIF report written: ', Args.ReportSarif);
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'SARIF write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    // HTML Code-Review-Report (wenn angefordert). Wiederverwendet TExporterHtml
    // aus der GUI-Pfad, daher self-contained mit Filter/Sort/Snippets.
    if Args.ReportHtml <> '' then
    begin
      try
        // SourceFile = leer -> kein Snippet-Embed, weil das vollstaendige
        // Repo gescannt wurde; Findings tragen pro Item ihren eigenen FileName.
        // Args.BaseDir defaultet auf Args.Path (s. Arg-Parsing) - damit
        // stehen im Report Relativpfade statt blosser Dateinamen.
        TExporterHtml.Run(Findings, '', Args.ReportHtml, Args.BaseDir);
        if not Args.Quiet then
          WriteLn('HTML report written: ', Args.ReportHtml);
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'HTML write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    // CSV-Output (Excel, Pivot, schnelles Auszaehlen).
    if Args.ReportCsv <> '' then
    begin
      try
        TExporter.ExportCsv(Findings, Args.ReportCsv, Args.BaseDir);
        if not Args.Quiet then
          WriteLn('CSV report written: ', Args.ReportCsv);
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'CSV write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    // JSON-Output (eigene Skripte, Ticket-Automatisierung).
    if Args.ReportJson <> '' then
    begin
      try
        TExporter.ExportJson(Findings, Args.ReportJson, Args.BaseDir);
        if not Args.Quiet then
          WriteLn('JSON report written: ', Args.ReportJson);
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'JSON write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    // Sonar Generic Issue Format (P1 - todo-sonar.md)
    if Args.SonarExport <> '' then
    begin
      try
        var OutsideBase := TSonarGenericWriter.WriteFile(
          Args.SonarExport, Findings, Args.BaseDir);
        if not Args.Quiet then
          WriteLn('Sonar Generic report written: ', Args.SonarExport);
        // Pfade ausserhalb von --base-dir bleiben absolut, und Sonar wirft
        // solche Issues still als "unknown files" weg. Ohne Hinweis sieht
        // man im Dashboard nur, dass Funde fehlen - nicht warum.
        if OutsideBase > 0 then
        begin
          WriteLn(ErrOutput, Format(
            'WARNING: %d issue(s) point outside --base-dir and keep an ' +
            'absolute path.', [OutsideBase]));
          WriteLn(ErrOutput,
            '         SonarQube discards those as "unknown files". Set ' +
            '--base-dir to the same root the scanner uses.');
        end;
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'Sonar export error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    WriteSummary(Findings, Args.Quiet);
    // Per-Detector-Timing-Tabelle wenn --time-detectors aktiv. NACH dem
    // Summary damit Quiet-Mode-User die Tabelle bekommen waehrend die
    // Finding-Auflistung weiter unterdrueckt bleibt.
    if Args.TimeDetectors and Assigned(gDetectorTimings) then
      WriteDetectorTimingsMarkdown(Args.TimeDetectorsOut);
    // C.5 Telemetrie: CSV schreiben wenn aktiviert.
    if (Args.TelemetryCsv <> '') and Assigned(gSuppressionTelemetry) then
    begin
      try
        gSuppressionTelemetry.SaveCsv(Args.TelemetryCsv, False);
        if not Args.Quiet then
          WriteLn(Format('Telemetry: %d suppression-hits written to %s',
            [gSuppressionTelemetry.Count, Args.TelemetryCsv]));
      except
        on E: Exception do
          WriteLn(ErrOutput, 'Telemetry write error: ', E.Message);
      end;
    end;
    Result := CalcExitCode(Findings);
    // Lesefehler-Flag NEBEN dem Raw-Code: ApplyFailOnPolicy sieht sonst nur
    // die Spitze der Rangleiter (z.B. 1 = Hints) und wuerde den Lauf auf 0
    // druecken, obwohl Dateien ungelesen blieben. Dieselbe Quelle wie die
    // Summary-Zeile - Exit-Code und Ausgabe koennen nicht auseinanderlaufen.
    var CntE, CntW, CntH, CntRe: Integer;
    CountBySeverity(Findings, CntE, CntW, CntH, CntRe);
    // --fail-on User-Policy ggf. anwenden (Default: graded = Raw beibehalten)
    Result := ApplyFailOnPolicy(Result, Args.FailOn, CntRe);
  finally
    FreeAndNil(gDetectorTimings);
    if Assigned(gSuppressionTelemetry) then
      FreeAndNil(gSuppressionTelemetry);
    Findings.Free;
    Files.Free;
    Settings.Free;
  end;
end;

class function TConsoleRunner.RunFromCmdLine: Integer;
begin
  Result := Run(ParseSysArgs);
end;

{ ---- Output ---- }

class procedure TConsoleRunner.CountBySeverity(
  const Findings: TObjectList<TLeakFinding>;
  out Errors, Warnings, Hints, ReadErrors: Integer);
// Klassifikations-Kern von WriteSummary + CalcExitCode. Sonderfall:
// fkFileReadError landet ausschliesslich in ReadErrors - seine Severity
// wird bewusst ignoriert (Exit-Code 4 = I/O-Problem, siehe Unit-Header).
var
  F : TLeakFinding;
begin
  Errors     := 0;
  Warnings   := 0;
  Hints      := 0;
  ReadErrors := 0;
  for F in Findings do
  begin
    if F.Kind = fkFileReadError then Inc(ReadErrors)
    else case F.Severity of
      lsError   : Inc(Errors);
      lsWarning : Inc(Warnings);
      lsHint    : Inc(Hints);
    else
      ; // TLeakSeverity kennt exakt lsError/lsWarning/lsHint - alle Werte
        // sind oben abgedeckt. Der leere else-Zweig ist nur da, um SCA168
        // (DefaultCaseInCaseStatement) zu bedienen, das die Vollstaendigkeit
        // des case nicht prueft; am Verhalten aendert er nichts.
    end;
  end;
end;

class procedure TConsoleRunner.WriteSummary(
  const Findings: TObjectList<TLeakFinding>; Quiet: Boolean);
var
  F             : TLeakFinding;
  CntErr        : Integer;
  CntWarn       : Integer;
  CntHint       : Integer;
  CntFileErr    : Integer;
begin
  CountBySeverity(Findings, CntErr, CntWarn, CntHint, CntFileErr);

  if not Quiet then
  begin
    WriteLn('');
    for F in Findings do
      WriteLn(Format('%s  %s:%s  %s  %s',
        [F.SeverityText, F.FileName, F.LineNumber,
         KindName(F.Kind), F.MissingVar]));
    WriteLn('');
  end;

  WriteLn(Format('Summary: %d Error(s), %d Warning(s), %d Hint(s), %d Read Error(s)',
    [CntErr, CntWarn, CntHint, CntFileErr]));
end;

class function TConsoleRunner.CalcExitCode(
  const Findings: TObjectList<TLeakFinding>): Integer;
var
  CntErr     : Integer;
  CntWarn    : Integer;
  CntHint    : Integer;
  CntFileErr : Integer;
begin
  CountBySeverity(Findings, CntErr, CntWarn, CntHint, CntFileErr);
  // Reihenfolge: Errors > Warnings > Hints > FileErrors > Clean
  if CntErr     > 0 then Exit(Integer(cecErrors));
  if CntWarn    > 0 then Exit(Integer(cecWarnings));
  if CntHint    > 0 then Exit(Integer(cecHints));
  if CntFileErr > 0 then Exit(Integer(cecReadErrors));
  Result := Integer(cecClean);
end;

function ApplyFailOnPolicy(Raw: Integer; const FailOn: string;
  ReadErrors: Integer): Integer;
// Schliesst Exit-Codes auf 0 zurueck wenn die User-Policy die Severity
// nicht eskalieren will. Werte (case-insensitive):
//   ''/'graded' - Default-Verhalten (Raw uebernehmen)
//   'none'      - immer 0
//   'hint'      - >= cecHints exit non-zero (= aktuelles Default)
//   'warning'   - nur >= cecWarnings exit non-zero
//   'error'     - nur >= cecErrors  exit non-zero
//
// ReadErrors > 0: mindestens eine Datei war nicht lesbar (fkFileReadError).
// Eine Herabstufung darf daraus nicht 0 machen - sonst meldet die Pipeline
// gruen fuer einen Scan, der Teile des Baums nie gesehen hat. Statt 0 kommt
// dann cecReadErrors (4).
// Warum das Flag ueberhaupt noetig ist: CalcExitCode kollabiert vier Zaehler
// auf EINEN Rang. Ab da ist "es gab Lesefehler" nur noch am Raw-Code
// erkennbar, wenn sonst gar nichts gefunden wurde - in jedem realen Repo
// gewinnt ein Hint, und der Lesefehler war unsichtbar (2026-08-08 gemessen).
// Ausnahme: 'none' heisst ausdruecklich "nie scheitern" und bleibt 0.
var
  L          : string;
  Suppressed : Integer;   // was ein herabgestufter Lauf zurueckgibt
begin
  L := LowerCase(Trim(FailOn));
  if (L = '') or (L = 'graded') then Exit(Raw);
  if L = 'none' then Exit(0);
  // Tool-Fehler bleibt immer nicht-null
  if Raw = Integer(cecToolError) then Exit(Raw);
  // Read-Errors muessen sichtbar bleiben (nicht-null) in allen Modi ausser 'none'
  if Raw = Integer(cecReadErrors) then Exit(Raw);

  if ReadErrors > 0 then Suppressed := Integer(cecReadErrors)
  else                   Suppressed := Integer(cecClean);

  if L = 'error' then
  begin
    if Raw = Integer(cecErrors) then Exit(Raw)
    else                              Exit(Suppressed);
  end;
  if L = 'warning' then
  begin
    if Raw >= Integer(cecWarnings) then Exit(Raw)
    else                                Exit(Suppressed);
  end;
  if L = 'hint' then
  begin
    if Raw >= Integer(cecHints) then Exit(Raw)
    else                             Exit(Suppressed);
  end;
  // Unbekannter Wert -> Default
  Result := Raw;
end;

end.
