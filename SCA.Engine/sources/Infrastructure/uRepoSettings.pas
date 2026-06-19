unit uRepoSettings;

// Persistente Settings fuer das Static Code Analysis Tool.
//
// Datei: %APPDATA%\StaticCodeAnalyser\analyser.ini
//
// Vorgaenger-Datei: repo.ini - wird beim ersten Start automatisch zu
// analyser.ini umbenannt, damit existierende User-Settings erhalten bleiben.
//
// [Repo]
// BaseBranch=develop          ; leer = auto (origin/HEAD -> main -> master)
// IncludeWorkingTree=1        ; 1 = uncommitted Aenderungen mit, 0 = nur committed
//
// [Paths]
// GitExe=C:\custom\git.exe    ; leer = auto (PATH + Tortoise-Hints)
// SvnExe=C:\custom\svn.exe
//
// [Detectors]
// LeakyClasses=TFDQuery,TIBQuery,TZipMaster
//                          ; zusaetzliche Klassen die der MemoryLeak-Detektor
//                          ; trackt - kommagetrennt. Werden zu den Default-
//                          ; Klassen (TStringList, TList, TFileStream, ...)
//                          ; aus uSCAConsts.LeakyClasses HINZUGEFUEGT.
// ExcludeLeakyClasses=TComponent,TThread
//                          ; Klassen die NICHT getrackt werden - werden aus
//                          ; der Default-Liste entfernt (False-Positive-
//                          ; Reduktion bei strikt Owner-basierten Projekten).
//
// Aenderungen wirken beim naechsten Klick auf "Branch-Changes" bzw.
// "Analyse starten".

interface

uses
  System.SysUtils, System.Classes, System.IniFiles;

const
  // ---------------------------------------------------------------------------
  // Default-Werte fuer User-Settings. Zentrale Konstanten damit Constructor
  // (Z810ff), Load (Ini.ReadXxx-Defaults), Save und externe Quick-Read-Caller
  // EINEN Wert teilen. Vorher 2-3 mal dupliziert je Property, Drift bei
  // Default-Aenderung wahrscheinlich.
  //
  // Aufgenommen sind nur die "lebenden" User-Settings (Hot-Path-Toggles +
  // User-Wunsch-Defaults). Detektor-Schwellwerte (MaxBodyLines etc.) bleiben
  // direkt im Constructor weil die nicht extern quick-readable sind.
  // ---------------------------------------------------------------------------
  DEF_SILENT_ENABLED         = True;
  DEF_AUTO_EXPAND_ANNOTATION = False;
  DEF_OVERLAY_SHOW_ON_HOVER  = False;
  DEF_EDITOR_COLOR_SCHEME    = 'default';
  DEF_LANGUAGE               = 'en';
  DEF_OVERLAY_POSITION       = 'sameline';

type
  TRepoSettings = class
  private
    FBaseBranch        : string;
    FIncludeWorkingTree: Boolean;
    FGitExePath        : string;
    FSvnExePath        : string;
    FConfigPath        : string;
    FLeakyClasses      : TStringList; // Custom-Eintraege aus [Detectors]
    FExcludeLeaky      : TStringList; // [Detectors] ExcludeLeakyClasses
    FAutoDiscover      : Boolean;     // [Detectors] AutoDiscoverClasses
    FUsesCheck         : Boolean;     // [Detectors] UsesCheck
    FIncludeTests      : Boolean;     // [Detectors] IncludeTests
    // Detektor-Schwellwerte (alle [Detectors]-Sektion).
    FMaxBodyLines      : Integer;     // LongMethodMaxBodyLines
    FMaxStatements     : Integer;     // LongMethodMaxStatements
    FMaxParams         : Integer;     // LongParamListMaxParams
    FMaxNesting        : Integer;     // DeepNestingMaxDepth
    FMaxCyclomatic     : Integer;     // CyclomaticMax
    FMinBlockLines     : Integer;     // DuplicateBlockMinLines
    FMaxFileMB         : Integer;     // MaxFileMB (5 Default)
    FMaxLineLength     : Integer;     // MaxLineLength (120 Default) - uTooLongLine
    FMaxCaseBranches   : Integer;     // MaxCaseBranches (10 Default) - uCaseStatementSize
    FMagicTrivials     : TStringList; // MagicNumberTrivials (CSV)
    FFormatFunctions   : TStringList; // FormatFunctions (CSV)
    FCustomRulesFile   : string;      // CustomRulesFile (Pfad zur YAML)
    FProfile           : string;      // [Rules] Profile = ide-fast|default|strict
    FMinSeverity       : string;      // [Rules] MinSeverity = error|warning|hint
    FMinConfidence     : string;      // [Rules] MinConfidence = low|medium|high
    FIdeProfile        : string;      // [Rules] IdeProfile (Default: ide-fast)
    FIdeMinSeverity    : string;      // [Rules] IdeMinSeverity (Default: hint)
    FDetectorReviewFilterEnabled : Boolean; // [Rules] EnableDetectorReviewFilter
                                            // (Default False, Debug-Build-Tool)
    FSilentEnabled     : Boolean;     // [Silent] Enabled (Default: True)
    // [UI] AutoExpandAnnotation: kontrolliert ob das Hover-Overlay nach
    // ~250ms automatisch von der Mini-Inline-Badge in die volle Detail-
    // Ansicht aufklappt. False (Default) = nur Title-Bar; User muss aufs
    // Title-Label klicken um den Desc/Fix-Block zu sehen. True = altes
    // Pre-0.9.9-Verhalten (automatisch nach 250ms).
    FAutoExpandAnnotation : Boolean;
    // [UI] OverlayShowOnHover: kontrolliert ob das Annotation-Overlay
    // bereits beim Hover ueber die markierte Zeile erscheint. False (Default)
    // = erst beim KLICK auf die markierte Zeile zeigt sich das Overlay -
    // ungestoertes Lesen ist Default. True = altes Hover-Verhalten.
    FOverlayShowOnHover : Boolean;
    // [UI] EditorColorScheme: Farbschema NUR fuer Editor-Marker
    // (Stripe + Mini-Infobar + Overlay-Titlebar). Erlaubte Werte:
    //   'default' - Original-ACCENT_* Farben (Default)
    //   'gray'    - reine Graustufen
    //   'subtle'  - gedaempfte/desaturierte Farben
    // Properties-Panel + Hauptfenster-Grid + Stat-Tiles bleiben theme-
    // unabhaengig bei den Original-Severity-Farben.
    FEditorColorScheme : string;
    FLanguage          : string;      // [UI] Language ('de', 'en', '')
    FOverlayPosition   : string;      // [UI] OverlayPosition ('sameline' | 'below')
    // Code-Quality-Grade-Schwellwerte (alle aus [Score]).
    // Default-Skala: A=0, B<=50, C<=200, D<=500, E>500.
    FScoreThresholdB   : Integer;     // [Score] GradeBMax (50)
    FScoreThresholdC   : Integer;     // [Score] GradeCMax (200)
    FScoreThresholdD   : Integer;     // [Score] GradeDMax (500)
  public
    constructor Create;
    destructor Destroy; override;

    // Laedt aus analyser.ini. Wenn die Datei nicht existiert, wird sie mit
    // einem dokumentierten Default-Inhalt angelegt.
    procedure Load;
    // Speichert aktuelle Werte in analyser.ini (legt Verzeichnis bei Bedarf an).
    procedure Save;

    // Convenience-Class-Methoden fuer Ein-Property-Reads. Kapseln
    // Create + Load + Free, sodass Caller das Boilerplate nicht jedes
    // Mal hinschreiben muss. Vorher: 8 Zeilen Boilerplate (Settings.Create,
    // try, try Settings.Load except end, Result := ..., finally, Settings.Free).
    // Jetzt: TRepoSettings.QuickReadBool('Silent', 'Enabled', True).
    // Fuer Hot-Path-Reads (jeder Hotkey-Druck) trotzdem ueber den Cache-
    // Pattern (siehe GCachedEditorScheme in uAnalyserTheme) gehen.
    class function QuickReadBool(const ASection, AKey: string;
      ADefault: Boolean): Boolean; static;
    class function QuickReadStr(const ASection, AKey, ADefault: string): string; static;
    procedure EnsureConfigExists;

    function ConfigFilePath: string;
    // Class-Variante - liefert den Pfad ohne TRepoSettings-Instanz zu
    // brauchen. Macht auch die repo.ini -> analyser.ini Auto-Migration.
    // Genutzt von QuickReadBool/Str damit der Pfad-Lookup keine
    // TStringList-Allokation kostet.
    class function ResolvedConfigPath: string; static;

    // '' bedeutet auto-detect (origin/HEAD, dann main, dann master).
    property BaseBranch: string read FBaseBranch write FBaseBranch;
    // True (Default): committed Branch-Diff + uncommitted Working Tree;
    // False: nur committed.
    property IncludeWorkingTree: Boolean read FIncludeWorkingTree
                                         write FIncludeWorkingTree;
    // '' bedeutet auto-detect via PATH/Tortoise-Hints.
    property GitExePath: string read FGitExePath write FGitExePath;
    property SvnExePath: string read FSvnExePath write FSvnExePath;

    // Zusaetzliche Klassen die der MemoryLeak-Detektor tracken soll.
    // Aus [Detectors] LeakyClasses (kommagetrennt) gelesen. Aufrufer
    // ruft RegisterToLeakyClasses() um sie an uSCAConsts.LeakyClasses
    // anzuhaengen, bevor die Analyse startet.
    property LeakyClasses: TStringList read FLeakyClasses;

    // Klassen die NICHT getrackt werden sollen (z.B. TComponent wenn das
    // Projekt durchgaengig auf Owner-Pattern setzt). Aus [Detectors]
    // ExcludeLeakyClasses (kommagetrennt). Werden in RegisterToLeakyClasses
    // aus der globalen Liste entfernt.
    property ExcludeLeakyClasses: TStringList read FExcludeLeaky;

    // Wenn True: vor dem MemoryLeak-Detektor scannt der Analyzer das AST
    // auf 'class(...)' Deklarationen und ergaenzt die LeakyClasses-Liste
    // automatisch um Custom-Klassen die NICHT von TForm/TFrame/TComponent/
    // TInterfacedObject erben (siehe uCustomClassDiscovery).
    property AutoDiscoverClasses: Boolean read FAutoDiscover write FAutoDiscover;

    // Wenn True: zusaetzlicher Detektor laeuft, der ungenutzte Eintraege in
    // der uses-Klausel meldet. Default False weil er bei Property/Operator-
    // /Generics-Code False-Positives produziert. Aus [Detectors] UsesCheck.
    property UsesCheck: Boolean read FUsesCheck write FUsesCheck;

    // Wenn True: DUnit/DUnitX-Tests (uTest*.pas, *_Tests.pas, /tests/-Ordner)
    // werden mit-analysiert. Default False - Test-Code produziert ueber-
    // proportional viele Code-Smell-Befunde (LongMethod, MagicNumber) die
    // den Hauptbefund ueberlagern. Aus [Detectors] IncludeTests.
    property IncludeTests: Boolean read FIncludeTests write FIncludeTests;

    // ---- Detektor-Schwellwerte (alle [Detectors]). Werden via
    // ApplyDetectorThresholds in die globalen Variablen in uSCAConsts
    // gespiegelt. Defaults entsprechen den fruheren hardcoded Konstanten,
    // also bleibt das Verhalten ohne INI-Eintraege unveraendert. ----

    // uLongMethod: Methode wird als "lang" markiert wenn Body-Lines UND
    // Statement-Count beide ueber den Schwellwerten liegen.
    property LongMethodMaxBodyLines:  Integer read FMaxBodyLines  write FMaxBodyLines;
    property LongMethodMaxStatements: Integer read FMaxStatements write FMaxStatements;

    // uLongParamList: Methoden mit > MaxParams Parametern werden gemeldet.
    property LongParamListMaxParams:  Integer read FMaxParams     write FMaxParams;

    // uDeepNesting: Verschachtelung > MaxDepth Ebenen.
    property DeepNestingMaxDepth:     Integer read FMaxNesting    write FMaxNesting;

    // uCyclomaticComplexity: McCabe-Komplexitaet > MaxCyclomatic.
    // Default 10 (industry standard - Sonar/Checkstyle/PMD).
    // Zaehlt: 1 base + if + case-arm + for/while/repeat + on-handler +
    // and/or/xor BinaryOps. else zaehlt nicht (binary branch).
    property CyclomaticMax:           Integer read FMaxCyclomatic write FMaxCyclomatic;

    // uDuplicateBlock: Block muss min. MinBlockLines (normalisierte Zeilen)
    // lang sein um als Duplikat zu zaehlen.
    property DuplicateBlockMinLines:  Integer read FMinBlockLines write FMinBlockLines;

    // uStaticAnalyzer2: Dateien groesser als MaxFileMB werden uebersprungen
    // (Schutz vor Out-of-Memory bei generiertem Code). In MB statt Bytes
    // weil's INI-freundlicher ist.
    property MaxFileMB:               Integer read FMaxFileMB     write FMaxFileMB;

    // uTooLongLine: Zeilen ueber MaxLineLength werden als lsHint gemeldet.
    // Default 120, konfigurierbar via [Detectors] MaxLineLength.
    property MaxLineLength:           Integer read FMaxLineLength write FMaxLineLength;

    // uCaseStatementSize: case-Statements mit >=MaxCaseBranches werden
    // gemeldet. Default 10, konfigurierbar via [Detectors] MaxCaseBranches.
    property MaxCaseBranches:         Integer read FMaxCaseBranches write FMaxCaseBranches;

    // uMagicNumbers: Liste der Zahlen die NICHT als Magic-Number gemeldet
    // werden. Aus INI als CSV gelesen, im Detektor als StringList verfuegbar.
    property MagicNumberTrivials:     TStringList read FMagicTrivials;

    // uFormatMismatch: Liste der Funktionsnamen die als Format-aequivalent
    // behandelt werden (gleiche %-Platzhalter-Semantik). Defaults: Format,
    // FormatUtf8, FormatString. Aus [Detectors] FormatFunctions=... als CSV.
    property FormatFunctions:         TStringList read FFormatFunctions;

    // uCustomRuleDetector: Pfad zur YAML-Datei mit projekt-spezifischen
    // Regeln (siehe examples/analyser-rules.yml). Leer = keine Custom-
    // Rules. Relative Pfade sind relativ zum Projekt-Root oder absolut.
    // Aus [Detectors] CustomRulesFile=... gelesen.
    property CustomRulesFile:         string      read FCustomRulesFile
                                                  write FCustomRulesFile;

    // Profile-Name aus [Rules] Profile. Bekannte Werte (Catalog-definiert):
    //   '' / 'default' -> alle Detektoren laufen
    //   'ide-fast'     -> nur Bugs/Vulnerabilities (Live-Analyse im IDE)
    //   'strict'       -> alle + opt-in Detektoren (UsesCheck)
    // ApplyDetectorThresholds loest den Namen via TRuleCatalog.GetProfile
    // in uSCAConsts.DetectorEnabledKinds auf. Unbekannte Namen fallen
    // auf AllKinds zurueck (kein Crash, OutputDebugString-Warnung).
    property Profile:                 string      read FProfile
                                                  write FProfile;

    // Min-Severity aus [Rules] MinSeverity. Werte (case-insensitive):
    //   'hint' / '' -> alles laeuft (Default)
    //   'warning'   -> nur Warning + Error (Hint-Detektoren werden geskippt)
    //   'error'     -> nur Error
    // Orthogonal zu Profile - beide Filter werden ODER-verknuepft skippen.
    property MinSeverity:             string      read FMinSeverity
                                                  write FMinSeverity;

    // [Rules] MinConfidence = low|medium|high (Default 'medium'). Post-Filter
    // ueber TLeakFinding.Confidence: Befunde unter der Schwelle fliegen raus.
    //   'low'    -> kein Filter
    //   'medium' -> nur fcLow raus (Default)
    //   'high'   -> nur sichere Treffer
    // Orthogonal zu Severity/Profile; in ApplyDetectorThresholds nach
    // uSCAConsts.FindingMinConfidence gespiegelt.
    property MinConfidence:           string      read FMinConfidence
                                                  write FMinConfidence;

    // Wie Profile / MinSeverity, aber separat fuer das IDE-Plugin. Der
    // Form-Frame ruft UseIdeRuleSet vor ApplyDetectorThresholds; daraufhin
    // werden FProfile/FMinSeverity transient mit den IDE-Werten ueber-
    // schrieben. Damit kann das gleiche analyser.ini-File standalone das
    // volle Rule-Set fahren und im IDE-Live-Mode ein schlankes Subset.
    // Defaults: IdeProfile=ide-fast, IdeMinSeverity=hint.
    property IdeProfile:              string      read FIdeProfile
                                                  write FIdeProfile;
    property IdeMinSeverity:          string      read FIdeMinSeverity
                                                  write FIdeMinSeverity;

    // [Rules] EnableDetectorReviewFilter (bool, default False).
    // Wenn True UND der Build hat das DEBUG-Symbol gesetzt, erscheint der
    // 'Detector Review (1 per detector, random)'-Eintrag in der Severity-
    // Filter-Combo. Release-Builds sehen ihn nie - das ist ein internes
    // Review-Tool, nicht fuer End-User gedacht.
    property DetectorReviewFilterEnabled: Boolean  read FDetectorReviewFilterEnabled
                                                   write FDetectorReviewFilterEnabled;

    // [Silent] Enabled - schaltet das Editor-Rechtsklick-Item an/aus.
    // Default True. Wenn False feuert der Silent-Mode-Entrypoint sofort
    // einen Early-Exit, kein Analyse-Lauf, keine Marker. Konfigurierbar
    // ueber Tools > Options > Third Party > Static Code Analyser
    // (siehe uIDESCAOptions) oder per Hand in analyser.ini.
    property SilentEnabled:           Boolean     read FSilentEnabled
                                                  write FSilentEnabled;
    property AutoExpandAnnotation:    Boolean     read FAutoExpandAnnotation
                                                  write FAutoExpandAnnotation;
    property OverlayShowOnHover:      Boolean     read FOverlayShowOnHover
                                                  write FOverlayShowOnHover;
    property EditorColorScheme:       string      read FEditorColorScheme
                                                  write FEditorColorScheme;

    // UI-Sprache. '' bedeutet "use Default" (= deutsch beim aktuellen Build,
    // falls dxgettext jemals aktiviert wird, wuerde es OS-Locale nutzen).
    // Aus [UI] Language gelesen. Erlaubte Werte: 'de', 'en', ''.
    property Language: string read FLanguage write FLanguage;

    // Position des Hover-AnnotationOverlay zur Befund-Zeile. Aus [UI]
    // OverlayPosition gelesen. Erlaubte Werte:
    //   'sameline' (Default) - Overlay startet AUF der Finding-Zeile selbst
    //                          (Title-Bar ueberlagert die Zeile, faltet
    //                          nach unten auf)
    //   'below'              - Overlay startet eine Zeile UNTER der Finding-
    //                          Zeile (alte Default - Befund-Zeile bleibt
    //                          sichtbar)
    // Aenderung erfordert IDE-Neustart (Wert wird in uIDELineHighlighter
    // einmalig zur ShowAt-Zeit gelesen).
    property OverlayPosition: string read FOverlayPosition write FOverlayPosition;

    // Schwellwerte fuer die Letter-Grade-Anzeige der Code-Quality-Kachel.
    // Roher Score wird auf A..E gemappt (siehe ScoreToGrade in uIDE-
    // AnalyserForm). Defaults (50/200/500) entsprechen einer Default-Skala
    // die fuer 5..50k-LOC-Projekte sinnvoll skaliert.
    // Aus [Score] GradeBMax / GradeCMax / GradeDMax gelesen.
    property ScoreThresholdB: Integer read FScoreThresholdB write FScoreThresholdB;
    property ScoreThresholdC: Integer read FScoreThresholdC write FScoreThresholdC;
    property ScoreThresholdD: Integer read FScoreThresholdD write FScoreThresholdD;

    // Customs an uSCAConsts.LeakyClasses anhaengen + Excludes daraus
    // entfernen. Reihenfolge: Adds zuerst, Excludes danach (User koennte
    // theoretisch eine Klasse adden UND excluden - dann Wins exclude).
    procedure RegisterToLeakyClasses;

    // Spiegelt die Schwellwerte in die globalen Variablen in uSCAConsts.
    // Wird vor jedem Analyse-Lauf aus der UI heraus aufgerufen, damit
    // INI-Aenderungen ohne App-Neustart wirken.
    //
    // AProjectRoot (optional): wird genutzt um relative CustomRulesFile-
    // Pfade aufzuloesen. Reihenfolge:
    //   1. Absoluter Pfad aus INI                       (wenn TPath.IsPathRooted)
    //   2. <AProjectRoot>\<filename>                    (typisch: meine-rules.yml im Repo)
    //   3. <ConfigDir>\<filename>                       (= AppData-INI-Verzeichnis)
    //   4. <ExeDir>\<filename>                          (Standalone-Default-Lookup)
    // Erste existierende Datei gewinnt. Wenn nichts gefunden -> ClearRules
    // (kein Crash, OutputDebugString-Hinweis).
    procedure ApplyDetectorThresholds(const AProjectRoot: string = '');

    // Vor ApplyDetectorThresholds vom IDE-Plugin gerufen. Transient
    // (in-memory) - speichert NICHT zurueck in die INI. Bewirkt, dass der
    // anschliessende ApplyDetectorThresholds-Call die IDE-Werte spiegelt.
    // Standalone-Pfad ruft nicht und behaelt die [Rules] Profile/MinSeverity
    // unveraendert.
    procedure UseIdeRuleSet;

    // Schreibt die im aktuellen Lauf gefundenen Discovery-Treffer
    // (uSCAConsts.DiscoveredClasses) in eine LeakyClassesDiscover.log
    // neben der analyser.ini. Reine Uebersicht/Kuratierungs-Hilfe -
    // die LeakyClasses-Konfiguration in der INI wird NICHT angefasst.
    // Der User entscheidet handisch welche Eintraege er in [Detectors]
    // LeakyClasses= uebernimmt. Bestehende Eintraege im .log werden
    // gemerged (sortiert + dedupliziert), ExcludeLeakyClasses werden
    // uebersprungen.
    procedure PersistDiscoveredClasses;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeStrictPrivate, CaseStatementSize, CyclomaticComplexity, DuplicateString, EmptyExcept, ExceptOnException, FreeWithoutNil, GodClass, GroupedDeclaration, IfElseBegin, LargeClass, LongMethod, NestedRoutine, NestedTry, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedPublicMember
// Destructor-Pattern: Free im Destruktor ohne nil-out (Object wird sofort
// danach freigegeben).

uses
  Winapi.Windows, System.IOUtils,
  uIgnoreList, uSCAConsts, uCustomRuleDetector, uRuleCatalog,
  uPathOverrides;

const
  DEFAULT_INI_CONTENT =
    '; ============================================================'#13#10 +
    ';  Static Code Analysis Tool for Delphi - analyser.ini'#13#10 +
    '; ============================================================'#13#10 +
    ';'#13#10 +
    '; Diese Datei listet ALLE verfuegbaren Optionen mit Default-Werten.'#13#10 +
    '; Format pro Option:'#13#10 +
    ';   Kommentar erklaert was die Option macht.'#13#10 +
    ';   OPTION=<default>           <- aktiv mit Default-Wert'#13#10 +
    ';   ;OPTION=<beispiel>         <- auskommentierte Beispiel-Variante'#13#10 +
    ';'#13#10 +
    '; Aenderungen wirken beim naechsten Klick auf "Analyse starten" /'#13#10 +
    '; "Branch-Changes" / "Aktuelle Datei". Kein Plugin-Reload noetig.'#13#10 +
    ';'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Repo] - VCS-Settings fuer den "Branch-Changes"-Button'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Repo]'#13#10 +
    ''#13#10 +
    '; BaseBranch (string, default: leer = auto-detect)'#13#10 +
    '; Vergleichs-Branch fuer "git diff <base>...HEAD".'#13#10 +
    '; Leer = Auto-Detect: origin/HEAD -> main -> master.'#13#10 +
    'BaseBranch='#13#10 +
    ';BaseBranch=develop'#13#10 +
    ';BaseBranch=release/2024.1'#13#10 +
    ';BaseBranch=origin/main'#13#10 +
    ''#13#10 +
    '; IncludeWorkingTree (bool, default: 1)'#13#10 +
    '; Uncommitted Aenderungen mit einbeziehen?'#13#10 +
    ';   1 = ja  (Default - typisch fuer Pre-Commit-Check)'#13#10 +
    ';   0 = nein (nur committed Branch-Diff)'#13#10 +
    'IncludeWorkingTree=1'#13#10 +
    ';IncludeWorkingTree=0'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Paths] - Tool-Pfade (falls nicht in PATH gefunden)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Paths]'#13#10 +
    ''#13#10 +
    '; GitExe (string, default: leer = auto via PATH+Tortoise)'#13#10 +
    '; Voller Pfad zu git.exe wenn weder PATH noch typische'#13#10 +
    '; Tortoise-Installation greifen.'#13#10 +
    'GitExe='#13#10 +
    ';GitExe=C:\Program Files\Git\bin\git.exe'#13#10 +
    ';GitExe=C:\Program Files\TortoiseGit\bin\git.exe'#13#10 +
    ''#13#10 +
    '; SvnExe (string, default: leer = auto via PATH+Tortoise)'#13#10 +
    'SvnExe='#13#10 +
    ';SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe'#13#10 +
    ';SvnExe=C:\Program Files\Subversion\bin\svn.exe'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Detectors] - Detektor-spezifische Tuning-Optionen'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Detectors]'#13#10 +
    ''#13#10 +
    '; LeakyClasses (kommagetrennt, default: leer)'#13#10 +
    '; Zusaetzliche Klassen die der MemoryLeak-Detektor tracken soll.'#13#10 +
    '; Werden zu den 30 Default-Klassen (TStringList, TList, TDictionary,'#13#10 +
    '; TFileStream, TBitmap, ...) hinzugefuegt.'#13#10 +
    'LeakyClasses='#13#10 +
    ';LeakyClasses=TFDQuery,TIBQuery,TZipMaster'#13#10 +
    ';LeakyClasses=TIdHTTP,TIdSMTP,TIdFTP'#13#10 +
    ''#13#10 +
    '; ExcludeLeakyClasses (kommagetrennt, default: leer)'#13#10 +
    '; Klassen die aus der Default-Liste ENTFERNT werden.'#13#10 +
    '; Sinnvoll wenn dein Projekt konsequent auf Owner-Pattern setzt -'#13#10 +
    '; z.B. TComponent wird normalerweise vom Parent-Owner freigegeben.'#13#10 +
    'ExcludeLeakyClasses='#13#10 +
    ';ExcludeLeakyClasses=TComponent'#13#10 +
    ';ExcludeLeakyClasses=TComponent,TThread'#13#10 +
    ''#13#10 +
    '; AutoDiscoverClasses (bool, default: 0)'#13#10 +
    '; Wenn 1: scannt das Projekt nach Klassen-Deklarationen und'#13#10 +
    '; ergaenzt LeakyClasses um alle Custom-Klassen die NICHT von'#13#10 +
    '; TForm/TFrame/TComponent/TInterfacedObject erben.'#13#10 +
    '; Mehr Befunde, ggf. mehr False-Positives -> per ExcludeLeakyClasses'#13#10 +
    '; gezielt ausschliessen.'#13#10 +
    'AutoDiscoverClasses=0'#13#10 +
    ';AutoDiscoverClasses=1'#13#10 +
    ''#13#10 +
    '; UsesCheck (bool, default: 0)'#13#10 +
    '; Wenn 1: zusaetzlicher Detektor meldet ungenutzte Eintraege in der'#13#10 +
    '; uses-Klausel. Standardmaessig aus, weil bei Property/Operator-/'#13#10 +
    '; Generics-Code False-Positives auftreten koennen.'#13#10 +
    'UsesCheck=0'#13#10 +
    ';UsesCheck=1'#13#10 +
    ''#13#10 +
    '; IncludeTests (bool, default: 0)'#13#10 +
    '; Wenn 1: DUnit/DUnitX-Tests (uTest*.pas, *_Tests.pas, /tests/-Ordner,'#13#10 +
    '; TestProject*.dpr) werden mit-analysiert. Default aus, weil Test-Code'#13#10 +
    '; ueberproportional viele Code-Smell-Befunde produziert (LongMethod,'#13#10 +
    '; MagicNumber) die den eigentlichen Hauptbefund ueberlagern.'#13#10 +
    'IncludeTests=0'#13#10 +
    ';IncludeTests=1'#13#10 +
    ''#13#10 +
    '; Live-Analyse: nur IDE-Plugin, nicht konfigurierbar.'#13#10 +
    '; Beim Klick auf "Aktuelle Datei" haengt das Plugin einen'#13#10 +
    '; IOTAModuleNotifier an genau diese Datei und scannt sie bei'#13#10 +
    '; jedem Save (Debounce 300 ms) und jedem Edit (Debounce 1000 ms)'#13#10 +
    '; im Hintergrund-Thread. "Analyse starten" und "Branch-Changes"'#13#10 +
    '; sind reine One-Shot-Laeufe ohne Live-Mode.'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  Detektor-Schwellwerte. Werte spiegeln die Defaults wider -'#13#10 +
    ';  einfach raus-kommentieren oder anpassen wenn Du es anders'#13#10 +
    ';  brauchst.'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '; LongMethod: Methode wird gemeldet wenn beide Schwellen ueber-'#13#10 +
    '; schritten sind (Body-Zeilen UND Statements). So entgehen wir'#13#10 +
    '; FPs bei lang-aber-flachen Massendaten-Initialisierungen.'#13#10 +
    ';LongMethodMaxBodyLines=50'#13#10 +
    ';LongMethodMaxStatements=30'#13#10 +
    ''#13#10 +
    '; LongParamList: > MaxParams Parameter -> Refactoring-Hinweis.'#13#10 +
    ';LongParamListMaxParams=5'#13#10 +
    ''#13#10 +
    '; DeepNesting: > MaxDepth verschachtelte Ebenen (if/while/for/'#13#10 +
    '; case/try) -> Refactoring-Hinweis.'#13#10 +
    ';DeepNestingMaxDepth=4'#13#10 +
    ''#13#10 +
    '; CyclomaticComplexity (McCabe): > Schwelle -> Refactoring-Hinweis.'#13#10 +
    '; Zaehlt: 1 base + if + case-arm + for/while/repeat + on-handler +'#13#10 +
    '; and/or/xor BinaryOps. else zaehlt nicht (binary branch).'#13#10 +
    '; Industry-Standard 10 (Sonar/Checkstyle/PMD).'#13#10 +
    ';CyclomaticMax=10'#13#10 +
    ''#13#10 +
    '; DuplicateBlock: minimale Blockgroesse fuer Duplikat-Erkennung.'#13#10 +
    '; Hoeher = weniger FPs (Boilerplate), niedriger = mehr Treffer.'#13#10 +
    ';DuplicateBlockMinLines=8'#13#10 +
    ''#13#10 +
    '; MaxFileMB: Dateien groesser als das werden uebersprungen'#13#10 +
    '; (Schutz vor OOM bei generiertem Code, .dfm-Dumps etc.).'#13#10 +
    ';MaxFileMB=5'#13#10 +
    ''#13#10 +
    '; MagicNumberTrivials: kommagetrennt, Zahlen die nicht als'#13#10 +
    '; Magic-Number gemeldet werden (Defaults: 0,1,2,-1,10,100).'#13#10 +
    ';MagicNumberTrivials=0,1,2,-1,10,100'#13#10 +
    ';MagicNumberTrivials=0,1,2,-1,10,100,1000,1024'#13#10 +
    ''#13#10 +
    '; FormatFunctions: kommagetrennt, Funktionsnamen mit Format()-'#13#10 +
    '; aequivalenter %-Platzhalter-Semantik. Defaults: Format,'#13#10 +
    '; FormatUtf8, FormatString. Erweiterbar um projekt-spezifische'#13#10 +
    '; Helper (z.B. _fmt, FmtUtf8) - der Detektor zaehlt Platzhalter'#13#10 +
    '; vs. Argumente fuer alle gelisteten Funktionen.'#13#10 +
    ';FormatFunctions=Format,FormatUtf8,FormatString'#13#10 +
    ';FormatFunctions=Format,FormatUtf8,FormatString,_fmt'#13#10 +
    ''#13#10 +
    '; CustomRulesFile: Pfad zur YAML-Datei mit projekt-spezifischen'#13#10 +
    '; Regeln (siehe examples/analyser-rules.yml + examples/profile-*.yml).'#13#10 +
    '; Pattern-Typen: substring | regex | word, mit optionalen file-include'#13#10 +
    '; und file-exclude Glob-Filtern. Findings erscheinen mit der Custom-'#13#10 +
    '; Rule-ID (z.B. PROJ001) im Grid und in SARIF.'#13#10 +
    ';'#13#10 +
    '; Pfad-Aufloesung (in Reihenfolge):'#13#10 +
    ';   1. Absoluter Pfad     -> direkt verwenden'#13#10 +
    ';   2. Relativ + Projekt   -> <Projekt-Root>\<wert>     <- typisch'#13#10 +
    ';   3. Relativ + AppData   -> %APPDATA%\StaticCodeAnalyser\<wert>'#13#10 +
    ';   4. Relativ + ExeDir    -> <Tool-Verz.>\<wert>'#13#10 +
    ';'#13#10 +
    '; Empfohlen: Datei "analyser-rules.yml" ins Projekt-Root legen und'#13#10 +
    '; nur den Dateinamen (ohne Pfad) hier eintragen. So pflegt jedes'#13#10 +
    '; Projekt sein eigenes Ruleset im Repo (Team-shared, versioniert).'#13#10 +
    ';CustomRulesFile='#13#10 +
    ';CustomRulesFile=analyser-rules.yml'#13#10 +
    ';CustomRulesFile=profile-strict.yml'#13#10 +
    ';CustomRulesFile=C:\Team\shared-sca-rules.yml'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Rules] - Rule-Set-Filter (Profile + Severity-Threshold)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Rules]'#13#10 +
    ''#13#10 +
    '; Profile (string, default: default / im IDE-Plugin: ide-fast)'#13#10 +
    '; Vordefinierte Rule-Auswahl aus rules/sca-rules.json -> "profiles".'#13#10 +
    '; Werkseitig vorhanden:'#13#10 +
    ';   ide-fast      - schnelle Live-Analyse, nur Bugs+Vulnerabilities'#13#10 +
    ';                   (Speicherleck, SQL-Injection, NilDeref, ...)'#13#10 +
    ';   default       - alle Regeln aktiv (Standalone-Default)'#13#10 +
    ';   strict        - alle + opt-in (UsesCheck)'#13#10 +
    ';   security      - nur Vulnerabilities + Security Hotspots'#13#10 +
    ';                   (Pre-Merge-Security-Review)'#13#10 +
    ';   bugs-only     - nur "falsches Verhalten"-Detektoren (CI-Gate)'#13#10 +
    ';   code-quality  - nur Code Smells + Duplikate (Refactoring)'#13#10 +
    ';   dfm-only      - nur DFM-Detektoren (Form-/UI-Reviews)'#13#10 +
    '; Eigene Profile kannst Du in sca-rules.json unter "profiles" pflegen.'#13#10 +
    'Profile=default'#13#10 +
    ';Profile=ide-fast'#13#10 +
    ';Profile=strict'#13#10 +
    ';Profile=security'#13#10 +
    ';Profile=bugs-only'#13#10 +
    ';Profile=code-quality'#13#10 +
    ';Profile=dfm-only'#13#10 +
    ''#13#10 +
    '; MinSeverity (string, default: hint)'#13#10 +
    '; Skippt alle Detektoren mit Default-Severity unterhalb dieser Schwelle.'#13#10 +
    ';   hint    - alles laeuft (Default)'#13#10 +
    ';   warning - nur Warning + Error, Hints (Long Method, MagicNumber, ...) raus'#13#10 +
    ';   error   - nur sichere Bugs / Vulnerabilities'#13#10 +
    '; Wirkt orthogonal zu Profile: beide Filter werden geODERt.'#13#10 +
    'MinSeverity=hint'#13#10 +
    ';MinSeverity=warning'#13#10 +
    ';MinSeverity=error'#13#10 +
    ''#13#10 +
    '; IdeProfile / IdeMinSeverity (Default: ide-fast / hint)'#13#10 +
    '; Wie Profile / MinSeverity, aber nur fuer das IDE-Plugin (Live-Mode).'#13#10 +
    '; Standalone (Form, CLI) nutzt Profile / MinSeverity. So kann die'#13#10 +
    '; Live-Analyse im IDE ein schlankes Subset fahren, waehrend der Full-'#13#10 +
    '; Run im Standalone das komplette Rule-Set anwendet.'#13#10 +
    'IdeProfile=ide-fast'#13#10 +
    ';IdeProfile=default'#13#10 +
    ';IdeProfile=strict'#13#10 +
    'IdeMinSeverity=hint'#13#10 +
    ';IdeMinSeverity=warning'#13#10 +
    ''#13#10 +
    '; EnableDetectorReviewFilter (bool, default: False)'#13#10 +
    '; Internes Review-Tool: blendet einen Severity-Combo-Eintrag'#13#10 +
    '; "Detector Review (1 per detector, random)" ein. Greift NUR wenn der'#13#10 +
    '; Build mit {$DEFINE DEBUG} compiliert wurde - Release-Builds zeigen'#13#10 +
    '; den Eintrag nie, egal wie diese Einstellung steht. Default off.'#13#10 +
    ';EnableDetectorReviewFilter=true'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [PathOverrides] - Pfad-basierte Severity-/Drop-Filter'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; Loest "Test-Code-Noise" ohne Profile-Schwund: ein Profile bleibt'#13#10 +
    '; scharf, aber Findings auf Test-/Demo-/Generated-Pfaden werden'#13#10 +
    '; gedroppt oder runtergestuft.'#13#10 +
    ';'#13#10 +
    '; Format:   <glob> = <action>'#13#10 +
    ';'#13#10 +
    '; Glob:     Forward- oder Backslashes; case-insensitive; ** = beliebige Tiefe'#13#10 +
    '; Aktion:   drop:*                    - alle Findings droppen'#13#10 +
    ';           drop:KindA,KindB,...      - nur diese Kinds droppen'#13#10 +
    ';           severity:hint:<KindList>  - Severity downgrade'#13#10 +
    ';           severity:warn:<KindList>  -      "'#13#10 +
    ';           severity:error:<KindList> -      " (Eskalation)'#13#10 +
    ';'#13#10 +
    '; Erste passende Rule gewinnt - Reihenfolge wichtig.'#13#10 +
    ';'#13#10 +
    '; Beispiele (auskommentiert):'#13#10 +
    '[PathOverrides]'#13#10 +
    ';tests\**.pas        = drop:*'#13#10 +
    ';**\test_*.pas       = drop:MissingFinally,MagicNumber'#13#10 +
    ';demos\legacy\**.pas = drop:LongMethod,DeepNesting,CyclomaticComplexity'#13#10 +
    ';src\generated\**    = severity:hint:*'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Silent] - Silent-Mode Editor-Kontextmenu'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Silent]'#13#10 +
    ''#13#10 +
    '; Enabled (bool, default: 1)'#13#10 +
    '; Schaltet den "Analyse current file (silent)"-Eintrag im Editor-'#13#10 +
    '; Rechtsklick-Menue an/aus.'#13#10 +
    '; Auch konfigurierbar via Tools > Options > Third Party >'#13#10 +
    '; Static Code Analyser.'#13#10 +
    'Enabled=1'#13#10 +
    ';Enabled=0'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [UI] - Oberflaechen-Einstellungen'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[UI]'#13#10 +
    ''#13#10 +
    '; Language (string, default: en)'#13#10 +
    '; UI-Sprache. Aktuell unterstuetzt:'#13#10 +
    ';   en = English (Default - Source-Sprache, kein Dictionary-Lookup)'#13#10 +
    ';   de = Deutsch (eingebautes Dictionary in uLocalization)'#13#10 +
    ';   '''' (leer) = wie ''en'''#13#10 +
    'Language=en'#13#10 +
    ';Language=de'#13#10 +
    ''#13#10 +
    '; OverlayPosition (string, default: sameline)'#13#10 +
    '; Position des Hover-Annotation-Overlays im Editor:'#13#10 +
    ';   sameline = Overlay startet AUF der Finding-Zeile (Title-Bar'#13#10 +
    ';              ueberlagert die Zeile; faltet nach unten auf)'#13#10 +
    ';   below    = Overlay startet eine Zeile UNTER der Finding-Zeile'#13#10 +
    ';              (alte Default - Befund-Zeile bleibt sichtbar)'#13#10 +
    '; Auch konfigurierbar via Tools > Options > Third Party >'#13#10 +
    '; Static Code Analyser. Aenderung erfordert IDE-Neustart.'#13#10 +
    'OverlayPosition=sameline'#13#10 +
    ';OverlayPosition=below'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Score] - Code-Quality-Letter-Grade-Schwellwerte'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; Die Code-Quality-Kachel zeigt den gewichteten Befund-Score als'#13#10 +
    '; Letter-Grade A..E statt als rohe Zahl. Mapping (roher Score):'#13#10 +
    ';   A : 0'#13#10 +
    ';   B : 1..GradeBMax'#13#10 +
    ';   C : GradeBMax+1 .. GradeCMax'#13#10 +
    ';   D : GradeCMax+1 .. GradeDMax'#13#10 +
    ';   E : > GradeDMax'#13#10 +
    ';'#13#10 +
    '; Rohwerte landen im Tooltip. Defaults passen fuer Projekte um'#13#10 +
    '; 5..50k LOC; kleinere Projekte ggf. strengere Schwellwerte,'#13#10 +
    '; Legacy-Repos toleranter.'#13#10 +
    ';'#13#10 +
    '; Gewichte (hardcoded, NICHT konfigurierbar): Vuln=10, Error=7,'#13#10 +
    '; Hotspot=5, Warning=3, Hint=1, FileErr=2.'#13#10 +
    ''#13#10 +
    '[Score]'#13#10 +
    ''#13#10 +
    '; GradeBMax (int, default: 50)'#13#10 +
    '; Roher Score bis einschliesslich dieses Werts gibt Grade B.'#13#10 +
    'GradeBMax=50'#13#10 +
    ';GradeBMax=20      ; strikter (kleines Projekt)'#13#10 +
    ';GradeBMax=100     ; nachsichtiger (Legacy-Repo)'#13#10 +
    ''#13#10 +
    '; GradeCMax (int, default: 200)'#13#10 +
    '; Obergrenze fuer Grade C; danach Grade D.'#13#10 +
    'GradeCMax=200'#13#10 +
    ';GradeCMax=80'#13#10 +
    ';GradeCMax=400'#13#10 +
    ''#13#10 +
    '; GradeDMax (int, default: 500)'#13#10 +
    '; Obergrenze fuer Grade D; alles darueber faellt auf Grade E.'#13#10 +
    'GradeDMax=500'#13#10 +
    ';GradeDMax=200'#13#10 +
    ';GradeDMax=1000'#13#10;

constructor TRepoSettings.Create;
begin
  inherited;
  FBaseBranch         := '';
  FIncludeWorkingTree := True;
  FGitExePath         := '';
  FSvnExePath         := '';
  FConfigPath         := '';
  FLeakyClasses       := TStringList.Create;
  FLeakyClasses.CaseSensitive := False;
  FExcludeLeaky       := TStringList.Create;
  FExcludeLeaky.CaseSensitive := False;
  FAutoDiscover       := False;
  FUsesCheck          := False;
  FIncludeTests       := False;
  // Detektor-Schwellwerte: Defaults entsprechen den alten hardcoded Werten.
  FMaxBodyLines  := 50;
  FMaxStatements := 30;
  FMaxParams     := 5;
  FMaxNesting    := 4;
  FMaxCyclomatic := 10;
  FMinBlockLines := 8;
  FMaxFileMB     := 5;
  FMaxLineLength := 120;
  FMaxCaseBranches := 10;
  FMagicTrivials := TStringList.Create;
  FMagicTrivials.CaseSensitive := False;
  FMagicTrivials.Sorted        := True;
  FMagicTrivials.Duplicates    := dupIgnore;
  FMagicTrivials.AddStrings(['0', '1', '2', '-1', '10', '100']);
  FFormatFunctions := TStringList.Create;
  FFormatFunctions.CaseSensitive := False;
  FFormatFunctions.Sorted        := True;
  FFormatFunctions.Duplicates    := dupIgnore;
  FFormatFunctions.AddStrings(['format', 'formatutf8', 'formatstring']);

  FCustomRulesFile := '';
  FProfile        := '';              // '' = default (= AllKinds, kein Filter)
  FMinSeverity    := 'hint';          // 'hint' = alles laeuft
  FMinConfidence  := 'medium';        // 'medium' = nur fcLow raus (Default)
  FIdeProfile     := 'ide-fast';      // IDE-Plugin Default: schnelles Subset
  FIdeMinSeverity := 'hint';          // IDE-Plugin: alle Severities (Subset deckt schon)
  FDetectorReviewFilterEnabled := False; // internes Review-Tool, default aus
  FSilentEnabled          := DEF_SILENT_ENABLED;
  FAutoExpandAnnotation   := DEF_AUTO_EXPAND_ANNOTATION;
  FOverlayShowOnHover     := DEF_OVERLAY_SHOW_ON_HOVER;
  FEditorColorScheme      := DEF_EDITOR_COLOR_SCHEME;
  FLanguage               := DEF_LANGUAGE;
  FOverlayPosition        := DEF_OVERLAY_POSITION;

  // [Score] Defaults: Skala fuer mittelgrosse Projekte. A=0, B<=50,
  // C<=200, D<=500, E>500. Anpassbar via analyser.ini fuer projekt-
  // spezifische Kalibrierung (kleinere Projekte ggf. strenger,
  // Legacy-Repos toleranter).
  FScoreThresholdB := 50;
  FScoreThresholdC := 200;
  FScoreThresholdD := 500;
end;

destructor TRepoSettings.Destroy;
begin
  FLeakyClasses.Free;
  FExcludeLeaky.Free;
  FMagicTrivials.Free;
  FFormatFunctions.Free;
  inherited;
end;

class function TRepoSettings.QuickReadBool(const ASection, AKey: string;
  ADefault: Boolean): Boolean;
// Single-Property-Quick-Read. Loest die ehemals 3+ Boilerplate-Funktionen
// (IsSilentEnabled, IsAutoExpandEnabled, IsShowOnHoverEnabled) in 1-Liner auf.
//
// Caller-Beispiel:
//   if TRepoSettings.QuickReadBool('Silent', 'Enabled', True) then ...
//
// Hinweis: Vollladung der TRepoSettings (TStringList-Allokation +
// Default-Setup). Wenn das in einem Hot-Path geht (siehe BuildMarkEntries-
// Crash 2026-06-17), stattdessen einen globalen Cache wie
// GCachedEditorScheme in uAnalyserTheme verwenden und beim Settings-Save
// refreshen.
var
  Ini     : TIniFile;
  CfgPath : string;
begin
  Result := ADefault;
  try
    CfgPath := TRepoSettings.ResolvedConfigPath;
    if (CfgPath = '') or not FileExists(CfgPath) then Exit;
    Ini := TIniFile.Create(CfgPath);
    try
      Result := Ini.ReadBool(ASection, AKey, ADefault);
    finally
      Ini.Free;
    end;
  except
    // Bei jedem Fehler: ADefault behalten.
  end;
end;

class function TRepoSettings.QuickReadStr(
  const ASection, AKey, ADefault: string): string;
var
  Ini     : TIniFile;
  CfgPath : string;
begin
  Result := ADefault;
  try
    CfgPath := TRepoSettings.ResolvedConfigPath;
    if (CfgPath = '') or not FileExists(CfgPath) then Exit;
    Ini := TIniFile.Create(CfgPath);
    try
      Result := Ini.ReadString(ASection, AKey, ADefault);
    finally
      Ini.Free;
    end;
  except
  end;
end;

function TRepoSettings.ConfigFilePath: string;
begin
  if FConfigPath = '' then
    FConfigPath := TRepoSettings.ResolvedConfigPath;
  Result := FConfigPath;
end;

class function TRepoSettings.ResolvedConfigPath: string;
var
  OldPath: string;
begin
  // Liegt im selben Verzeichnis wie ignore.txt (= %APPDATA%\StaticCodeAnalyser\).
  Result := TIgnoreList.ConfigDir + 'analyser.ini';

  // Auto-Migration: wenn die alte repo.ini noch existiert und es noch keine
  // analyser.ini gibt, einfach umbenennen. So bleiben User-Settings
  // (BaseBranch, Tortoise-Pfade, Custom-LeakyClasses) erhalten.
  if not FileExists(Result) then
  begin
    OldPath := TIgnoreList.ConfigDir + 'repo.ini';
    if FileExists(OldPath) then
      try RenameFile(OldPath, Result); except end;
  end;
end;

procedure TRepoSettings.EnsureConfigExists;
var
  Path, Dir: string;
  SL       : TStringList;
begin
  Path := ConfigFilePath;
  if FileExists(Path) then Exit;
  Dir := ExtractFilePath(Path);
  if (Dir <> '') and not DirectoryExists(Dir) then
    try ForceDirectories(Dir); except Exit; end;
  SL := TStringList.Create;
  try
    SL.Text := DEFAULT_INI_CONTENT;
    try SL.SaveToFile(Path, TEncoding.UTF8); except end;
  finally
    SL.Free;
  end;
end;

procedure TRepoSettings.Load;
// TMemIniFile statt TIniFile: liest die ganze Datei EINMAL im Ctor ein,
// alle ReadString/ReadBool-Aufrufe danach sind In-Memory-Lookups.
// Macht den Plugin-Optionen-Open spuerbar schneller (~25 Reads ohne
// 25 separate Datei-Open/Close-Syscalls).
var
  Ini       : TMemIniFile;
  RawList   : string;
  Items     : TArray<string>;
  Item      : string;
  Trimmed   : string;
begin
  EnsureConfigExists;
  Ini := TMemIniFile.Create(ConfigFilePath);
  try
    FBaseBranch         := Trim(Ini.ReadString('Repo',  'BaseBranch',         ''));
    FIncludeWorkingTree :=      Ini.ReadBool  ('Repo',  'IncludeWorkingTree', True);
    FGitExePath         := Trim(Ini.ReadString('Paths', 'GitExe',             ''));
    FSvnExePath         := Trim(Ini.ReadString('Paths', 'SvnExe',             ''));

    // [Detectors] LeakyClasses=Klasse1,Klasse2,... -> FLeakyClasses
    RawList := Trim(Ini.ReadString('Detectors', 'LeakyClasses', ''));
    FLeakyClasses.Clear;
    if RawList <> '' then
    begin
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FLeakyClasses.Add(Trimmed);
      end;
    end;

    // [Detectors] ExcludeLeakyClasses=Klasse1,... -> FExcludeLeaky
    RawList := Trim(Ini.ReadString('Detectors', 'ExcludeLeakyClasses', ''));
    FExcludeLeaky.Clear;
    if RawList <> '' then
    begin
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FExcludeLeaky.Add(Trimmed);
      end;
    end;

    // [Detectors] AutoDiscoverClasses=1 -> FAutoDiscover
    FAutoDiscover := Ini.ReadBool('Detectors', 'AutoDiscoverClasses', False);

    // [Detectors] UsesCheck=1   -> FUsesCheck    (Default aus, oft FP)
    // [Detectors] IncludeTests=1 -> FIncludeTests (Default aus, Test-Code-Noise)
    FUsesCheck    := Ini.ReadBool('Detectors', 'UsesCheck',    False);
    FIncludeTests := Ini.ReadBool('Detectors', 'IncludeTests', False);

    // Detektor-Schwellwerte (alle [Detectors]). Defaults = alte hardcoded
    // Werte, also bleibt das Verhalten ohne explizite INI-Eintraege gleich.
    FMaxBodyLines  := Ini.ReadInteger('Detectors', 'LongMethodMaxBodyLines',  50);
    FMaxStatements := Ini.ReadInteger('Detectors', 'LongMethodMaxStatements', 30);
    FMaxParams     := Ini.ReadInteger('Detectors', 'LongParamListMaxParams',  5);
    FMaxNesting    := Ini.ReadInteger('Detectors', 'DeepNestingMaxDepth',     4);
    FMaxCyclomatic := Ini.ReadInteger('Detectors', 'CyclomaticMax',          10);
    FMinBlockLines := Ini.ReadInteger('Detectors', 'DuplicateBlockMinLines',  8);
    FMaxFileMB     := Ini.ReadInteger('Detectors', 'MaxFileMB',               5);
    FMaxLineLength := Ini.ReadInteger('Detectors', 'MaxLineLength',           120);
    FMaxCaseBranches := Ini.ReadInteger('Detectors', 'MaxCaseBranches',       10);

    RawList := Trim(Ini.ReadString('Detectors', 'MagicNumberTrivials', ''));
    if RawList <> '' then
    begin
      FMagicTrivials.Clear;
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FMagicTrivials.Add(Trimmed);
      end;
    end;
    // Wenn der Eintrag leer ist, behalten wir die Default-Liste aus dem
    // Constructor (0,1,2,-1,10,100) - das spiegelt das alte Verhalten.

    // [Detectors] FormatFunctions=Format,FormatUtf8,... (CSV) ->
    // FFormatFunctions. Wenn leer behalten wir den Default aus dem
    // Constructor (format,formatutf8,formatstring).
    RawList := Trim(Ini.ReadString('Detectors', 'FormatFunctions', ''));
    if RawList <> '' then
    begin
      FFormatFunctions.Clear;
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FFormatFunctions.Add(Trimmed);
      end;
    end;

    // [Detectors] CustomRulesFile=path/to/analyser-rules.yml -> Custom-
    // Rule-Detector laed sie beim naechsten Analyse-Start. Leer = aus.
    FCustomRulesFile := Trim(Ini.ReadString('Detectors', 'CustomRulesFile', ''));

    // [Rules] Profile=...     -> FProfile (default leer = AllKinds-Filter)
    // [Rules] MinSeverity=... -> FMinSeverity (default 'hint' = alles).
    // Beide werden in ApplyDetectorThresholds in die uSCAConsts-Globals
    // gespiegelt; Default-Werte erhalten alte Semantik (kein Skip).
    FProfile       := Trim(Ini.ReadString('Rules', 'Profile',       ''));
    FMinSeverity   := Trim(Ini.ReadString('Rules', 'MinSeverity',   'hint')).ToLower;
    FMinConfidence := Trim(Ini.ReadString('Rules', 'MinConfidence', 'medium')).ToLower;
    // IDE-Plugin-spezifische Overrides. Werden via UseIdeRuleSet transient
    // in FProfile/FMinSeverity gespiegelt - die INI bleibt unveraendert.
    FIdeProfile     := Trim(Ini.ReadString('Rules', 'IdeProfile',     'ide-fast'));
    FIdeMinSeverity := Trim(Ini.ReadString('Rules', 'IdeMinSeverity', 'hint')).ToLower;
    FDetectorReviewFilterEnabled := Ini.ReadBool('Rules', 'EnableDetectorReviewFilter', False);

    // [Silent] Enabled (bool, Default True) - schaltet Editor-Rechtsklick +
    // Hotkey fuer den Silent-Mode an/aus. Konfigurierbar via Tools > Options
    // > Third Party > Static Code Analyser.
    FSilentEnabled        := Ini.ReadBool  ('Silent',  'Enabled',              DEF_SILENT_ENABLED);
    FAutoExpandAnnotation := Ini.ReadBool  ('UI',      'AutoExpandAnnotation', DEF_AUTO_EXPAND_ANNOTATION);
    FOverlayShowOnHover   := Ini.ReadBool  ('UI',      'OverlayShowOnHover',   DEF_OVERLAY_SHOW_ON_HOVER);
    FEditorColorScheme    := Ini.ReadString('UI',      'EditorColorScheme',    DEF_EDITOR_COLOR_SCHEME);

    // [Hotkeys] Master-Toggle + Per-Feature-Toggle + Shortcut-Strings.
    FLanguage        := Trim(Ini.ReadString('UI', 'Language',        DEF_LANGUAGE)).ToLower;
    FOverlayPosition := Trim(Ini.ReadString('UI', 'OverlayPosition', DEF_OVERLAY_POSITION)).ToLower;
    if (FOverlayPosition <> 'sameline') and (FOverlayPosition <> 'below') then
      FOverlayPosition := 'sameline';  // unbekannter Wert -> Default

    // [Score] Letter-Grade-Schwellwerte. Defaults bleiben gleich wenn
    // die Section fehlt - kein Verhaltens-Bruch fuer existierende INIs.
    FScoreThresholdB := Ini.ReadInteger('Score', 'GradeBMax',  50);
    FScoreThresholdC := Ini.ReadInteger('Score', 'GradeCMax', 200);
    FScoreThresholdD := Ini.ReadInteger('Score', 'GradeDMax', 500);
    // Defensive: erzwinge B < C < D, sonst gibt's "tote" Grades.
    if FScoreThresholdC <= FScoreThresholdB then
      FScoreThresholdC := FScoreThresholdB + 1;
    if FScoreThresholdD <= FScoreThresholdC then
      FScoreThresholdD := FScoreThresholdC + 1;
  finally
    Ini.Free;
  end;
end;

procedure TRepoSettings.RegisterToLeakyClasses;
var
  i, k: Integer;
begin
  // uSCAConsts.LeakyClasses ist die globale Live-Liste (TStringList),
  // NICHT meine Property mit gleichem Namen.
  if not Assigned(uSCAConsts.LeakyClasses) then Exit;

  // 1) Customs hinzufuegen (Sorted+dupIgnore -> idempotent)
  for i := 0 to FLeakyClasses.Count - 1 do
    uSCAConsts.LeakyClasses.Add(FLeakyClasses[i]);

  // 2) Excludes in die globale Exclude-Liste schreiben. Auto-Discovery
  //    konsultiert sie pro File-Pass, sonst wuerden Discovered-Classes
  //    die Excludes ueberschreiben.
  if Assigned(uSCAConsts.LeakyClassExcludes) then
  begin
    uSCAConsts.LeakyClassExcludes.Clear;
    for i := 0 to FExcludeLeaky.Count - 1 do
      uSCAConsts.LeakyClassExcludes.Add(FExcludeLeaky[i]);
  end;

  // 3) Excludes aus der LeakyClasses-Liste entfernen (gewinnt ueber Adds).
  for i := 0 to FExcludeLeaky.Count - 1 do
  begin
    k := uSCAConsts.LeakyClasses.IndexOf(FExcludeLeaky[i]);
    if k >= 0 then uSCAConsts.LeakyClasses.Delete(k);
  end;
end;

procedure TRepoSettings.Save;
// TMemIniFile: alle Writes batch'en in den Speicher, EIN UpdateFile am Ende
// schreibt das ganze File raus. Vorher 11 Open/Write/Close-Zyklen.
var
  Ini: TMemIniFile;
begin
  EnsureConfigExists;
  Ini := TMemIniFile.Create(ConfigFilePath);
  try
    Ini.WriteString('Repo',  'BaseBranch',         FBaseBranch);
    Ini.WriteBool  ('Repo',  'IncludeWorkingTree', FIncludeWorkingTree);
    Ini.WriteString('Paths', 'GitExe',             FGitExePath);
    Ini.WriteString('Paths', 'SvnExe',             FSvnExePath);
    // Profile + MinSeverity (+ IDE-Pendants) werden persistiert, damit
    // die letzte UI-Auswahl ueber Restarts erhalten bleibt. Standalone-
    // Form hat alle vier potentiell veraendert, IDE-Plugin nur IdeProfile -
    // ueberfluessige Writes schaden nicht (Wert = INI-Lade-Wert).
    Ini.WriteString('Rules', 'Profile',            FProfile);
    Ini.WriteString('Rules', 'MinSeverity',        FMinSeverity);
    Ini.WriteString('Rules', 'MinConfidence',      FMinConfidence);
    Ini.WriteString('Rules', 'IdeProfile',         FIdeProfile);
    Ini.WriteString('Rules', 'IdeMinSeverity',     FIdeMinSeverity);
    Ini.WriteBool  ('Rules', 'EnableDetectorReviewFilter', FDetectorReviewFilterEnabled);
    Ini.WriteBool  ('Silent', 'Enabled',           FSilentEnabled);
    Ini.WriteBool  ('UI',     'AutoExpandAnnotation', FAutoExpandAnnotation);
    Ini.WriteBool  ('UI',     'OverlayShowOnHover',   FOverlayShowOnHover);
    Ini.WriteString('UI',     'EditorColorScheme',    FEditorColorScheme);
    // [Detectors]-Toggles: jetzt UI-aenderbar via Tools > Options.
    Ini.WriteBool  ('Detectors', 'UsesCheck',           FUsesCheck);
    Ini.WriteBool  ('Detectors', 'IncludeTests',        FIncludeTests);
    Ini.WriteBool  ('Detectors', 'AutoDiscoverClasses', FAutoDiscover);
    Ini.WriteString('UI',    'Language',           FLanguage);
    Ini.WriteString('UI',    'OverlayPosition',    FOverlayPosition);
    // Pflicht bei TMemIniFile: ohne UpdateFile bleiben alle Writes nur
    // im Speicher (TIniFile dagegen schreibt pro Write sofort).
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function ResolveCustomRulesPath(const AConfigured, AProjectRoot,
  AConfigDir, AExeDir: string): string;
// Liefert den ersten existierenden Pfad aus den Lookup-Locations,
// '' wenn keine Datei gefunden. AConfigured kann absolut oder relativ sein.
var
  Cands : array of string;
  C     : string;
begin
  Result := '';
  if AConfigured = '' then Exit;

  // Absoluter Pfad? -> direkt verwenden
  if TPath.IsPathRooted(AConfigured) then
  begin
    if TFile.Exists(AConfigured) then Result := AConfigured;
    Exit;
  end;

  // Relativ: in 3 Locations suchen, in dieser Reihenfolge
  SetLength(Cands, 0);
  if AProjectRoot <> '' then
  begin
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := TPath.Combine(AProjectRoot, AConfigured);
  end;
  if AConfigDir <> '' then
  begin
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := TPath.Combine(AConfigDir, AConfigured);
  end;
  if AExeDir <> '' then
  begin
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := TPath.Combine(AExeDir, AConfigured);
  end;
  for C in Cands do
    if TFile.Exists(C) then Exit(C);
end;

procedure TRepoSettings.UseIdeRuleSet;
// Transient override: das IDE-Plugin ruft das vor jedem
// ApplyDetectorThresholds-Call. Spiegelt IdeProfile/IdeMinSeverity in
// die normalen Profile/MinSeverity-Felder, damit ApplyDetectorThresholds
// nichts ueber das aufrufende Binary wissen muss.
begin
  if FIdeProfile     <> '' then FProfile     := FIdeProfile;
  if FIdeMinSeverity <> '' then FMinSeverity := FIdeMinSeverity;
end;

procedure TRepoSettings.ApplyDetectorThresholds(const AProjectRoot: string = '');

  function ParseMinSev(const S: string): TLeakSeverity;
  // Default lsHint = nichts wird wegen Severity geskippt. Andere Werte
  // (case-insensitive) wirken als Whitelist nach oben.
  var L: string;
  begin
    L := LowerCase(Trim(S));
    if L = 'error'   then Exit(lsError);
    if L = 'warning' then Exit(lsWarning);
    Result := lsHint;
  end;

var
  i           : Integer;
  ResolvedPath: string;
begin
  // Skalare Schwellwerte direkt in die Globals spiegeln. Detektoren lesen
  // beim naechsten Lauf von dort.
  uSCAConsts.DetectorMaxBodyLines  := FMaxBodyLines;
  uSCAConsts.DetectorMaxStatements := FMaxStatements;
  uSCAConsts.DetectorMaxParams     := FMaxParams;
  uSCAConsts.DetectorMaxNesting    := FMaxNesting;
  uSCAConsts.DetectorMaxCyclomatic := FMaxCyclomatic;
  uSCAConsts.DetectorMinBlockLines := FMinBlockLines;
  uSCAConsts.DetectorMaxFileBytes  := FMaxFileMB * 1024 * 1024;
  uSCAConsts.DetectorMaxLineLength   := FMaxLineLength;
  uSCAConsts.DetectorMaxCaseBranches := FMaxCaseBranches;

  // [Rules] Profile -> EnabledKinds Whitelist. Leer = AllKinds = kein
  // Filter (alte Semantik). Unbekannter Name faellt im Catalog auf
  // AllKinds zurueck (kein Crash).
  if FProfile = '' then
    uSCAConsts.DetectorEnabledKinds := TRuleCatalog.GetProfile('default')
  else
    uSCAConsts.DetectorEnabledKinds := TRuleCatalog.GetProfile(FProfile);

  // [Rules] MinSeverity -> globaler Severity-Schwellwert.
  uSCAConsts.DetectorMinSeverity := ParseMinSev(FMinSeverity);

  // [Rules] MinConfidence -> globaler Konfidenz-Schwellwert (Post-Filter).
  uSCAConsts.FindingMinConfidence := uSCAConsts.ParseConfidence(FMinConfidence, fcMedium);

  // [PathOverrides] -> uPathOverrides global. Wird im Analyzer-Pipeline
  // als Post-Filter nach uSuppression aufgerufen.
  uPathOverrides.TPathOverrides.Load(ConfigFilePath);

  // Trivial-Liste: globale Liste mit unseren INI-Eintraegen ueberschreiben.
  if Assigned(uSCAConsts.DetectorMagicTrivials) then
  begin
    uSCAConsts.DetectorMagicTrivials.Clear;
    for i := 0 to FMagicTrivials.Count - 1 do
      uSCAConsts.DetectorMagicTrivials.Add(FMagicTrivials[i]);
  end;

  // Format-Funktions-Liste analog spiegeln.
  if Assigned(uSCAConsts.DetectorFormatFunctions) then
  begin
    uSCAConsts.DetectorFormatFunctions.Clear;
    for i := 0 to FFormatFunctions.Count - 1 do
      uSCAConsts.DetectorFormatFunctions.Add(FFormatFunctions[i]);
  end;

  // Custom-Rules: YAML laden wenn Pfad gesetzt. Path-Resolver probiert
  // ProjectRoot, ConfigDir, ExeDir der Reihe nach. Bei Fehlern (kaputte
  // YAML, ungueltiger Regex) Rules verwerfen statt Crash - der Haupt-
  // analyzer laeuft dann eben ohne Custom-Rules weiter. ClearRules ist
  // Pflicht wenn der Pfad leer wird (Settings-Update).
  if FCustomRulesFile <> '' then
  begin
    ResolvedPath := ResolveCustomRulesPath(
      FCustomRulesFile,
      AProjectRoot,
      ExtractFilePath(ConfigFilePath),
      ExtractFilePath(ParamStr(0)));
    if ResolvedPath <> '' then
    begin
      try
        uCustomRuleDetector.TCustomRuleDetector.LoadFromYaml(ResolvedPath);
      except
        on E: Exception do
        begin
          // Konsolen-Output fuer Standalone, IDE-Plugin sieht das im
          // OutputDebugString-Stream. Kein Crash, kein Modal-Dialog.
          OutputDebugString(PChar(Format(
            'StaticCodeAnalyser: Custom-Rules-Datei nicht ladbar (%s): %s',
            [ResolvedPath, E.Message])));
          uCustomRuleDetector.TCustomRuleDetector.ClearRules;
        end;
      end;
    end
    else
    begin
      OutputDebugString(PChar(Format(
        'StaticCodeAnalyser: CustomRulesFile nicht gefunden: "%s" '+
        '(gesucht in ProjectRoot="%s", ConfigDir, ExeDir)',
        [FCustomRulesFile, AProjectRoot])));
      uCustomRuleDetector.TCustomRuleDetector.ClearRules;
    end;
  end
  else
    uCustomRuleDetector.TCustomRuleDetector.ClearRules;
end;

procedure TRepoSettings.PersistDiscoveredClasses;
// Schreibt die im aktuellen Lauf gefundenen Klassen in
// LeakyClassesDiscover.log neben analyser.ini. Zwei Sektionen:
//   [Instantiable]  - Klassen mit ctor/dtor oder Create-Aufruf
//   [Static-only]   - keine Instanziierungs-Hinweise (auskommentiert)
//
// Bestehende Eintraege werden gemerged (Cumulative Log ueber alle
// bisherigen Laeufe), Duplikate via case-insensitive IndexOf entfernt.
// Wenn bei einer Sektion nichts neues hinzukam wird das File nicht
// angefasst (mtime/git-diff schonen).
const
  LOG_FILE      = 'LeakyClassesDiscover.log';
  HEADER_INST   = '; --- Instantiable (ctor/dtor declared or Create() call found) ---';
  HEADER_STATIC = '; --- Static-only candidates (no instantiation evidence) ---';
  FILE_INTRO =
    '; LeakyClassesDiscover.log - Auto-Discovery output'#13#10 +
    '; Manually copy the names you want into [Detectors] LeakyClasses='#13#10 +
    '; in analyser.ini. The static-only block is commented out as a hint.'#13#10;

  procedure MergeNewHits(Source, Target: TStringList;
    Excludes: TStringList; out Changed: Boolean);
  // Mergt Discovery-Treffer in eine sortierte Target-Liste, ueberspringt
  // Excludes und meldet via Changed ob es etwas neues gab.
  var
    j   : Integer;
    Cls : string;
  begin
    Changed := False;
    if not Assigned(Source) then Exit;
    for j := 0 to Source.Count - 1 do
    begin
      Cls := Source[j];
      if Excludes.IndexOf(Cls) >= 0 then Continue;
      if Target.IndexOf(Cls) < 0 then
      begin
        Target.Add(Cls);
        Changed := True;
      end;
    end;
  end;

  procedure ReadOldList(const Lines: TStringList; const Header: string;
    Target: TStringList);
  // Liest Klassennamen unter einem Section-Header bis zum naechsten
  // Header oder Dateiende. Auskommentierte Eintraege ('; TFoo') werden
  // entfettet und mit aufgenommen, damit der Static-Only-Block bei
  // Reload nicht verloren geht.
  var
    InSection : Boolean;
    i         : Integer;
    Line      : string;
  begin
    InSection := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      if Line = '' then Continue;
      if SameText(Line, Header) then
      begin
        InSection := True;
        Continue;
      end;
      // Anderer Section-Header beendet den aktuellen Block
      if Line.StartsWith('; ---') and not SameText(Line, Header) then
      begin
        InSection := False;
        Continue;
      end;
      if not InSection then Continue;
      // Bisherige Klassennamen koennen mit ';' oder '; ' praefixiert sein
      // (Static-Only-Block) - praefix abschneiden bevor wir den Namen
      // wieder als Klassennamen behandeln.
      while Line.StartsWith(';') or Line.StartsWith('#') do
      begin
        Delete(Line, 1, 1);
        Line := TrimLeft(Line);
      end;
      if Line = '' then Continue;
      Target.Add(Line);
    end;
  end;

var
  LogPath           : string;
  Inst, Stat        : TStringList;   // finale Listen (gemerged)
  Raw               : TStringList;
  i                 : Integer;
  Output            : TStringList;
  ChangedInst       : Boolean;
  ChangedStat       : Boolean;
begin
  // Wenn beide Discovery-Listen leer sind: nichts zu tun
  if (not Assigned(uSCAConsts.DiscoveredClasses) or
      (uSCAConsts.DiscoveredClasses.Count = 0)) and
     (not Assigned(uSCAConsts.DiscoveredStaticClasses) or
      (uSCAConsts.DiscoveredStaticClasses.Count = 0)) then Exit;

  EnsureConfigExists;
  LogPath := ExtractFilePath(ConfigFilePath) + LOG_FILE;

  Inst := TStringList.Create;
  Stat := TStringList.Create;
  try
    Inst.CaseSensitive := False;
    Inst.Sorted        := True;
    Inst.Duplicates    := dupIgnore;
    Stat.CaseSensitive := False;
    Stat.Sorted        := True;
    Stat.Duplicates    := dupIgnore;

    // 1) bestehendes .log einlesen
    if FileExists(LogPath) then
    begin
      Raw := TStringList.Create;
      try
        try Raw.LoadFromFile(LogPath); except end;
        ReadOldList(Raw, HEADER_INST,   Inst);
        ReadOldList(Raw, HEADER_STATIC, Stat);
      finally
        Raw.Free;
      end;
    end;

    // 2) neue Treffer mergen, Excludes ueberspringen
    MergeNewHits(uSCAConsts.DiscoveredClasses,       Inst, FExcludeLeaky, ChangedInst);
    MergeNewHits(uSCAConsts.DiscoveredStaticClasses, Stat, FExcludeLeaky, ChangedStat);

    if not (ChangedInst or ChangedStat) then Exit;

    // 3) zusammenbauen und schreiben
    Output := TStringList.Create;
    try
      Output.Text := FILE_INTRO;
      Output.Add('');
      Output.Add(HEADER_INST);
      for i := 0 to Inst.Count - 1 do
        Output.Add(Inst[i]);
      Output.Add('');
      Output.Add(HEADER_STATIC);
      for i := 0 to Stat.Count - 1 do
        Output.Add('; ' + Stat[i]);

      try Output.SaveToFile(LogPath); except end;
    finally
      Output.Free;
    end;
  finally
    Inst.Free;
    Stat.Free;
  end;
end;

end.
