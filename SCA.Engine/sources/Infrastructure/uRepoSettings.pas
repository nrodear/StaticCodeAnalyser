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
  DEF_BASELINE_ONLY_NEW      = False;
  // [UI] AutoExpandAnnotation wurde 2026-07-05 ENTFERNT: das Overlay faltet
  // jetzt IMMER automatisch bis zur vollen Hint-Ansicht auf (UX-Entscheid,
  // die Collapsed-Zwischenstufe mit Klick-zum-Auffalten ist entfallen).
  // Ein evtl. noch vorhandener INI-Eintrag wird ignoriert.
  DEF_OVERLAY_SHOW_ON_HOVER  = False;
  // [UI] OverlayTextOnly: 1 = Annotation-Hint als reiner Text auf der
  // Editor-Canvas, OHNE Hintergrundfarbe und ohne Fenster-Overlay
  // (Konzept_AnnotationHint_NurText_2026-08-09, Weg B). 0 (Default) =
  // Fenster-Overlay mit Aufklapp-Animation wie bisher.
  DEF_OVERLAY_TEXT_ONLY      = False;
  DEF_EDITOR_COLOR_SCHEME    = 'default';
  DEF_LANGUAGE               = 'en';
  DEF_OVERLAY_POSITION       = 'sameline';
  // [UI] ClipboardOnClick: 1 = Zwischenablage nicht anfassen (Default),
  // 2 = Jira-Mini-Issue, 3 = Claude-AI-Prompt (Verhalten vor 2026-08-12).
  // Default BEWUSST 1: ein Zeilen-Klick, der ungefragt die systemweite
  // Zwischenablage ueberschreibt (und via Clipboard-History/Cloud-Sync
  // Quelltext in externe Senken spuelt), ist fuer ein Privacy-Produkt
  // die falsche Voreinstellung - Nutzerentscheid 2026-08-12.
  DEF_CLIPBOARD_ON_CLICK     = 1;
  // Gueltiger Wertebereich des Modus - die Klemmung in Load haengt daran.
  CLIPBOARD_ON_CLICK_MIN     = 1;
  CLIPBOARD_ON_CLICK_MAX     = 3;

type
  TRepoSettings = class
  private
    FBaseBranch        : string;
    FIncludeWorkingTree: Boolean;
    FGitExePath        : string;
    FSvnExePath        : string;
    FConfigPath        : string;
    FLeakyClasses      : TStringList; // Custom-Eintraege aus [Detectors]
    FOwnershipSinks    : TStringList; // [Detectors] OwnershipSinks (#5)
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
    FDfmForbiddenClasses : TStringList; // [Components] ForbiddenClasses (CSV)
    FCustomRulesFile   : string;      // CustomRulesFile (Pfad zur YAML)
    FProfile           : string;      // [Rules] Profile = ide-fast|default|strict
    FMinSeverity       : string;      // [Rules] MinSeverity = error|warning|hint
    FMinConfidence     : string;      // [Rules] MinConfidence = low|medium|high
    FIdeProfile        : string;      // [Rules] IdeProfile (Default: ide-fast)
    FIdeMinSeverity    : string;      // [Rules] IdeMinSeverity (Default: hint)
    FDetectorReviewFilterEnabled : Boolean; // [Rules] EnableDetectorReviewFilter
                                            // (Default False, Debug-Build-Tool)
    FSilentEnabled     : Boolean;     // [Silent] Enabled (Default: True)
    FBaselineFile      : string;      // [Baseline] File (Pfad zur Baseline-JSON)
    FBaselinePathFp    : Boolean;     // [Baseline] PathInFingerprint (Opt-in)
    FBaselineOnlyNew   : Boolean;     // [Baseline] OnlyNew (nur neue Funde zeigen)
    // [UI] OverlayShowOnHover: kontrolliert ob das Annotation-Overlay
    // bereits beim Hover ueber die markierte Zeile erscheint. False (Default)
    // = erst beim KLICK auf die markierte Zeile zeigt sich das Overlay -
    // ungestoertes Lesen ist Default. True = altes Hover-Verhalten.
    FOverlayShowOnHover : Boolean;
    // [UI] OverlayTextOnly: Nur-Text-Variante des Annotation-Hints
    // (transparent auf der Editor-Canvas statt Fenster-Overlay).
    FOverlayTextOnly    : Boolean;
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
    FClipboardOnClick  : Integer;     // [UI] ClipboardOnClick (1..3, s. DEF_CLIPBOARD_ON_CLICK)
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

    /// <summary>
    ///   Ergaenzt einen ganzen Abschnitt samt seiner Kommentare in einer
    ///   BESTEHENDEN analyser.ini, falls er dort noch fehlt.
    /// </summary>
    /// <remarks>
    ///   Wofuer: EnsureConfigExists schreibt die dokumentierte Vorlage nur,
    ///   wenn ueberhaupt keine Datei da ist. Wer schon eine hat, bekommt bei
    ///   einer neuen Programmfassung zwar das neue VERHALTEN (fehlende
    ///   Schluessel liefern ihre Vorgabe), sieht aber nie, dass es die
    ///   Einstellung gibt - die Kommentare in dieser Datei SIND die
    ///   Endanwender-Doku.
    ///
    ///   Der Text wird aus DEFAULT_INI_CONTENT herausgeschnitten, nicht ein
    ///   zweites Mal hingeschrieben. Sonst gaebe es zwei Fassungen, die
    ///   auseinanderlaufen koennen.
    ///
    ///   Angehaengt wird nur, wenn der Abschnitt fehlt - eine vorhandene
    ///   Einstellung wird nie ueberschrieben. Liefert True, wenn etwas
    ///   geschrieben wurde.
    /// </remarks>
    class function EnsureSection(const ASection: string): Boolean; static;

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

    // #5: [Detectors] OwnershipSinks - Routinen, die Ownership eines
    // uebergebenen Objekts uebernehmen. RegisterToLeakyClasses haengt sie
    // an uSCAConsts.OwnershipSinks (SCA001-FP-Suppression, opt-in).
    property OwnershipSinks: TStringList read FOwnershipSinks;

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

    // uDfmForbiddenClass (SCA038): Komponentenklassen, die in keiner
    // DFM vorkommen duerfen. Aus [Components] ForbiddenClasses=... als
    // CSV; leer (Default) = Detektor bleibt stumm. Gespiegelt wird in
    // ApplyDetectorThresholds - NICHT in RegisterToLeakyClasses, damit
    // auch die CLI die Liste bekommt (s. OwnershipSinks-Hinweis oben).
    property DfmForbiddenClasses:     TStringList read FDfmForbiddenClasses;

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
    property OverlayShowOnHover:      Boolean     read FOverlayShowOnHover
                                                  write FOverlayShowOnHover;
    // Nur-Text-Variante des Annotation-Hints (Nutzerwunsch 2026-08-12,
    // Konzept 2026-08-09): True = eine Zeile Text direkt auf der
    // Editor-Canvas, OHNE Hintergrundfarbe (kein FillRect - der Editor-
    // Hintergrund samt Auswahl bleibt sichtbar), permanent an jeder
    // Ankerzeile statt der Mini-Infobar; kein Fenster, keine Stufe 2
    // (Beschreibung/Fix bleiben im Findings-Panel), Verwerfen per Klick
    // auf den Text. False (Default) = Fenster-Overlay wie bisher.
    // Wirkt nach dem Speichern der Optionen (Modulcache im Highlighter).
    // noinspection BooleanPropertyNaming
    // Namensstil folgt dem INI-Key OverlayTextOnly und den Nachbarn
    // (OverlayShowOnHover, BaselineOnlyNew) statt einem Is-Praefix.
    property OverlayTextOnly:         Boolean     read FOverlayTextOnly
                                                  write FOverlayTextOnly;
    property EditorColorScheme:       string      read FEditorColorScheme
                                                  write FEditorColorScheme;

    // [Baseline] File - Pfad zur Baseline-JSON (Format kompatibel mit CLI
    // --write-baseline und dem HTML-Export). [Baseline] OnlyNew - wenn True
    // blendet das IDE-Plugin Funde aus, deren Fingerprint in der Baseline
    // steht (nur "neu seit Baseline" bleibt sichtbar). Non-destruktiv: die
    // volle Findings-Liste + Export bleiben unberuehrt, nur die Anzeige filtert.
    property BaselineFile:            string      read FBaselineFile
                                                  write FBaselineFile;
    // Opt-in: Relativpfad statt Dateiname im Baseline-Fingerprint.
    // noinspection BooleanPropertyNaming
    // Namensstil folgt dem [Baseline]-Bestand (BaselineOnlyNew, INI-Key
    // PathInFingerprint) statt einem Is-Praefix.
    property BaselinePathInFingerprint: Boolean    read FBaselinePathFp
                                                  write FBaselinePathFp;
    property BaselineOnlyNew:         Boolean     read FBaselineOnlyNew
                                                  write FBaselineOnlyNew;

    // UI-Sprache als ISO-639-1-Kuerzel, aus [UI] Language (kleingeschrieben).
    // Seit dem .po-Cutover 2026-07-26 nicht mehr auf 'de'/'en' begrenzt:
    // gueltig ist jedes Kuerzel aus uLocalization.AvailableLanguages
    // (eingebettete .po + externe i18n\*.po neben dem Modul). '' oder ein
    // unbekanntes Kuerzel bedeutet Englisch - SetLanguage faellt dann auf
    // Identity zurueck, ohne Fehler. Betrifft ausschliesslich die
    // Oberflaeche; Detektor-Meldungen sind nicht lokalisiert.
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

    // Was der Klick auf eine Befund-Zeile in die Zwischenablage legt.
    // Aus [UI] ClipboardOnClick gelesen, wirkt in EXE und IDE-Plugin:
    //   1 (Default) - Zwischenablage NICHT anfassen
    //   2           - Jira-Mini-Issue (Headline + 5 Fakten-Bullets)
    //   3           - Claude-AI-Prompt (Verhalten vor 2026-08-12; das
    //                 Plugin stellt bei Quick-Fix-faehigen Regeln einen
    //                 Quick-Fix-Block voran, die EXE nicht - bewusste
    //                 Alt-Divergenz)
    // Ungueltige Werte werden beim Laden auf 1 geklemmt; die Mapping-
    // Funktion in uFindingCopyText faellt zusaetzlich defensiv auf
    // "nicht anfassen" zurueck. Die expliziten Kopier-Gesten (Kontext-
    // menue "Copy AI prompt") kopieren unabhaengig davon immer.
    property ClipboardOnClick: Integer read FClipboardOnClick
                                       write FClipboardOnClick;

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
  uPathOverrides,
  uEngineApi;   // TAnalysisSession.Acquire/ReleaseEngineLock - Schnappschuss
                // der Discovery-Globals in PersistDiscoveredClasses. Zirkel
                // ueber die implementation-uses ist zulaessig: uEngineApi
                // fuehrt uRepoSettings ebenfalls nur in der implementation.

const
  DEFAULT_INI_CONTENT =
    '; ============================================================'#13#10 +
    ';  Static Code Analysis Tool for Delphi - analyser.ini'#13#10 +
    '; ============================================================'#13#10 +
    ';'#13#10 +
    '; This file lists ALL available options with their default values.'#13#10 +
    '; Layout per option:'#13#10 +
    ';   A comment explains what the option does.'#13#10 +
    ';   OPTION=<default>           <- active, set to its default'#13#10 +
    ';   ;OPTION=<example>          <- commented-out example variant'#13#10 +
    ';'#13#10 +
    '; Changes take effect on the next click of "Run analysis" /'#13#10 +
    '; "Branch changes" / "Current file". No plugin reload needed.'#13#10 +
    ';'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Repo] - VCS settings for the "Branch changes" button'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Repo]'#13#10 +
    ''#13#10 +
    '; BaseBranch (string, default: empty = auto-detect)'#13#10 +
    '; Branch to compare against for "git diff <base>...HEAD".'#13#10 +
    '; Empty = auto-detect: origin/HEAD -> main -> master.'#13#10 +
    'BaseBranch='#13#10 +
    ';BaseBranch=develop'#13#10 +
    ';BaseBranch=release/2024.1'#13#10 +
    ';BaseBranch=origin/main'#13#10 +
    ''#13#10 +
    '; IncludeWorkingTree (bool, default: 1)'#13#10 +
    '; Include uncommitted changes?'#13#10 +
    ';   1 = yes (default - the usual choice for a pre-commit check)'#13#10 +
    ';   0 = no  (committed branch diff only)'#13#10 +
    'IncludeWorkingTree=1'#13#10 +
    ';IncludeWorkingTree=0'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Paths] - tool paths (when they are not found on PATH)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Paths]'#13#10 +
    ''#13#10 +
    '; GitExe (string, default: empty = auto via PATH + Tortoise)'#13#10 +
    '; Full path to git.exe when neither PATH nor a typical Tortoise'#13#10 +
    '; installation resolves it.'#13#10 +
    'GitExe='#13#10 +
    ';GitExe=C:\Program Files\Git\bin\git.exe'#13#10 +
    ';GitExe=C:\Program Files\TortoiseGit\bin\git.exe'#13#10 +
    ''#13#10 +
    '; SvnExe (string, default: empty = auto via PATH + Tortoise)'#13#10 +
    'SvnExe='#13#10 +
    ';SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe'#13#10 +
    ';SvnExe=C:\Program Files\Subversion\bin\svn.exe'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Detectors] - per-detector tuning options'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Detectors]'#13#10 +
    ''#13#10 +
    '; LeakyClasses (comma-separated, default: empty)'#13#10 +
    '; Additional classes the memory-leak detector should track.'#13#10 +
    '; Added to the 30 built-in classes (TStringList, TList, TDictionary,'#13#10 +
    '; TFileStream, TBitmap, ...).'#13#10 +
    'LeakyClasses='#13#10 +
    ';LeakyClasses=TFDQuery,TIBQuery,TZipMaster'#13#10 +
    ';LeakyClasses=TIdHTTP,TIdSMTP,TIdFTP'#13#10 +
    ''#13#10 +
    '; ExcludeLeakyClasses (comma-separated, default: empty)'#13#10 +
    '; Classes REMOVED from the built-in list.'#13#10 +
    '; Useful when your project applies the owner pattern consistently -'#13#10 +
    '; TComponent, for instance, is normally freed by its parent owner.'#13#10 +
    'ExcludeLeakyClasses='#13#10 +
    ';ExcludeLeakyClasses=TComponent'#13#10 +
    ';ExcludeLeakyClasses=TComponent,TThread'#13#10 +
    ''#13#10 +
    '; AutoDiscoverClasses (bool, default: 0)'#13#10 +
    '; When 1: scans the project for class declarations and extends'#13#10 +
    '; LeakyClasses by every custom class that does NOT descend from'#13#10 +
    '; TForm / TFrame / TComponent / TInterfacedObject.'#13#10 +
    '; More findings, possibly more false positives - narrow them down'#13#10 +
    '; with ExcludeLeakyClasses.'#13#10 +
    'AutoDiscoverClasses=0'#13#10 +
    ';AutoDiscoverClasses=1'#13#10 +
    ''#13#10 +
    '; UsesCheck (bool, default: 0)'#13#10 +
    '; When 1: an extra detector reports unused entries in the uses'#13#10 +
    '; clause. Off by default, because property, operator and generics'#13#10 +
    '; code can produce false positives.'#13#10 +
    'UsesCheck=0'#13#10 +
    ';UsesCheck=1'#13#10 +
    ''#13#10 +
    '; IncludeTests (bool, default: 0)'#13#10 +
    '; When 1: DUnit/DUnitX tests (uTest*.pas, *_Tests.pas, /tests/'#13#10 +
    '; folders, TestProject*.dpr) are analysed too. Off by default,'#13#10 +
    '; because test code produces a disproportionate number of code-smell'#13#10 +
    '; findings (LongMethod, MagicNumber) that bury the real ones.'#13#10 +
    'IncludeTests=0'#13#10 +
    ';IncludeTests=1'#13#10 +
    ''#13#10 +
    '; Live analysis: IDE plugin only, not configurable.'#13#10 +
    '; Clicking "Current file" attaches an IOTAModuleNotifier to exactly'#13#10 +
    '; that file and rescans it on every save (300 ms debounce) and every'#13#10 +
    '; edit (1000 ms debounce) on a background thread. "Run analysis" and'#13#10 +
    '; "Branch changes" are plain one-shot runs with no live mode.'#13#10 +
    ';'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  Detector thresholds. The values mirror the defaults - comment'#13#10 +
    ';  them back in and adjust when you need something else.'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '; LongMethod: a method is reported when BOTH thresholds are'#13#10 +
    '; exceeded (body lines AND statements). That way long-but-flat bulk'#13#10 +
    '; data initialisation does not trigger a false positive.'#13#10 +
    ';LongMethodMaxBodyLines=50'#13#10 +
    ';LongMethodMaxStatements=30'#13#10 +
    ''#13#10 +
    '; LongParamList: more than MaxParams parameters -> refactoring hint.'#13#10 +
    ';LongParamListMaxParams=5'#13#10 +
    ''#13#10 +
    '; DeepNesting: more than MaxDepth nested levels (if/while/for/'#13#10 +
    '; case/try) -> refactoring hint.'#13#10 +
    ';DeepNestingMaxDepth=4'#13#10 +
    ''#13#10 +
    '; CyclomaticComplexity (McCabe): above the threshold -> refactoring hint.'#13#10 +
    '; Counted: 1 base + if + case arm + for/while/repeat + on handler +'#13#10 +
    '; and/or/xor binary operators. else does not count (binary branch).'#13#10 +
    '; Industry standard is 10 (Sonar / Checkstyle / PMD).'#13#10 +
    ';CyclomaticMax=10'#13#10 +
    ''#13#10 +
    '; DuplicateBlock: minimum block size for duplicate detection.'#13#10 +
    '; Higher = fewer false positives (boilerplate), lower = more hits.'#13#10 +
    ';DuplicateBlockMinLines=8'#13#10 +
    ''#13#10 +
    '; MaxFileMB: files larger than this are skipped (protects against'#13#10 +
    '; running out of memory on generated code, .dfm dumps and the like).'#13#10 +
    ';MaxFileMB=5'#13#10 +
    '; CognitiveLimit (int, default: 15)'#13#10 +
    '; Threshold for SCA176 (cognitive complexity). A method is reported when'#13#10 +
    '; its Sonar-style score is STRICTLY greater than this value; the value'#13#10 +
    '; itself appears in the message text.'#13#10 +
    '; A value of 0 or less reports practically every method that has any'#13#10 +
    '; control flow at all. A non-numeric value falls back to 15 silently.'#13#10 +
    ';CognitiveLimit=15'#13#10 +
    ''#13#10 +
    '; MaxCaseBranches (int, default: 10)'#13#10 +
    '; Threshold for SCA091. A `case` fires AT this branch count already, not'#13#10 +
    '; above it. 0 or a negative value does NOT switch the detector off - it'#13#10 +
    '; silently resets to 10; use the profile or rule filter for that.'#13#10 +
    ';MaxCaseBranches=10'#13#10 +
    ''#13#10 +
    '; MaxLineLength (int, default: 120)'#13#10 +
    '; Threshold for SCA062. A plain line scan without string or comment'#13#10 +
    '; awareness, so long comment and literal lines count too.'#13#10 +
    ';MaxLineLength=120'#13#10 +
    ''#13#10 +
    '; OwnershipSinks (comma-separated, default: empty)'#13#10 +
    '; Routine names that take ownership of an object passed to them. SCA001'#13#10 +
    '; then treats such a call as a handover and stays silent.'#13#10 +
    '; Applied by all three consumers (EXE, IDE plugin, CLI). Adding a name'#13#10 +
    '; takes effect on the next scan; REMOVING one needs a process restart'#13#10 +
    '; in the EXE/IDE (the list is only ever added to) - the CLI starts a'#13#10 +
    '; fresh process per run, so removals apply immediately there.'#13#10 +
    ';OwnershipSinks=TakeOwnership,AdoptObject'#13#10 +
    ''#13#10 +
    '; MagicNumberTrivials: comma-separated numbers that are NOT reported'#13#10 +
    '; as magic numbers (defaults: 0,1,2,-1,10,100).'#13#10 +
    ';MagicNumberTrivials=0,1,2,-1,10,100'#13#10 +
    ';MagicNumberTrivials=0,1,2,-1,10,100,1000,1024'#13#10 +
    ''#13#10 +
    '; FormatFunctions: comma-separated function names with Format()-'#13#10 +
    '; equivalent %-placeholder semantics. Defaults: Format, FormatUtf8,'#13#10 +
    '; FormatString. Extend with project-specific helpers (_fmt, FmtUtf8) -'#13#10 +
    '; the detector counts placeholders against arguments for every listed'#13#10 +
    '; function.'#13#10 +
    ';FormatFunctions=Format,FormatUtf8,FormatString'#13#10 +
    ';FormatFunctions=Format,FormatUtf8,FormatString,_fmt'#13#10 +
    ''#13#10 +
    '; CustomRulesFile: path to the YAML file holding project-specific'#13#10 +
    '; rules (see examples/analyser-rules.yml + examples/profile-*.yml).'#13#10 +
    '; Pattern types: substring | regex | word, with optional file-include'#13#10 +
    '; and file-exclude glob filters. Findings appear with the custom rule'#13#10 +
    '; ID (PROJ001, say) in the grid and in SARIF.'#13#10 +
    ';'#13#10 +
    '; Path resolution, in this order:'#13#10 +
    ';   1. Absolute path      -> used as is'#13#10 +
    ';   2. Relative + project -> <project root>\<value>      <- the usual case'#13#10 +
    ';   3. Relative + AppData -> %APPDATA%\StaticCodeAnalyser\<value>'#13#10 +
    ';   4. Relative + ExeDir  -> <tool directory>\<value>'#13#10 +
    ';'#13#10 +
    '; Recommended: put a file named "analyser-rules.yml" in the project'#13#10 +
    '; root and enter only the file name here. Each project then keeps its'#13#10 +
    '; own rule set in its repository - shared with the team, versioned.'#13#10 +
    ';CustomRulesFile='#13#10 +
    ';CustomRulesFile=analyser-rules.yml'#13#10 +
    ';CustomRulesFile=profile-strict.yml'#13#10 +
    ';CustomRulesFile=C:\Team\shared-sca-rules.yml'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Components] - DFM component bans (SCA038)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Components]'#13#10 +
    ''#13#10 +
    '; ForbiddenClasses (string CSV, default: empty = SCA038 stays silent)'#13#10 +
    '; Component classes that must not appear in any DFM of the project.'#13#10 +
    '; Every use is reported as SCA038 (DfmForbiddenClass); matching is'#13#10 +
    '; case-insensitive. Typical use: ban legacy or replaced components.'#13#10 +
    ';ForbiddenClasses='#13#10 +
    ';ForbiddenClasses=TLabel,TQuery'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Rules] - rule-set filter (profile + severity threshold)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Rules]'#13#10 +
    ''#13#10 +
    '; Profile (string, default: default / in the IDE plugin: ide-fast)'#13#10 +
    '; Predefined rule selection from rules/sca-rules.json -> "profiles".'#13#10 +
    '; Shipped with the tool:'#13#10 +
    ';   ide-fast      - fast live analysis, bugs and vulnerabilities only'#13#10 +
    ';                   (memory leak, SQL injection, nil deref, ...)'#13#10 +
    ';   default       - every rule active (standalone default)'#13#10 +
    ';   strict        - every rule plus opt-in ones (UsesCheck)'#13#10 +
    ';   security      - vulnerabilities and security hotspots only'#13#10 +
    ';                   (pre-merge security review)'#13#10 +
    ';   bugs-only     - only detectors for "behaves wrongly" (CI gate)'#13#10 +
    ';   code-quality  - code smells and duplicates only (refactoring)'#13#10 +
    ';   dfm-only      - DFM detectors only (form / UI reviews)'#13#10 +
    '; You can maintain your own profiles under "profiles" in sca-rules.json.'#13#10 +
    'Profile=default'#13#10 +
    ';Profile=ide-fast'#13#10 +
    ';Profile=strict'#13#10 +
    ';Profile=security'#13#10 +
    ';Profile=bugs-only'#13#10 +
    ';Profile=code-quality'#13#10 +
    ';Profile=dfm-only'#13#10 +
    ''#13#10 +
    '; MinSeverity (string, default: hint)'#13#10 +
    '; Skips every detector whose default severity is below this threshold.'#13#10 +
    ';   hint    - everything runs (default)'#13#10 +
    ';   warning - Warning and Error only; hints (LongMethod, MagicNumber, ...) drop out'#13#10 +
    ';   error   - certain bugs and vulnerabilities only'#13#10 +
    '; Orthogonal to Profile: the two filters are ORed.'#13#10 +
    'MinSeverity=hint'#13#10 +
    ';MinSeverity=warning'#13#10 +
    ';MinSeverity=error'#13#10 +
    '; MinConfidence (string, default: medium)'#13#10 +
    '; Confidence floor. Findings below it are dropped by the post-filter:'#13#10 +
    ';   low    - no filtering, everything a detector produced'#13#10 +
    ';   medium - the shipped default'#13#10 +
    ';   high   - only findings the detector is certain about'#13#10 +
    '; An unknown value falls back to medium.'#13#10 +
    'MinConfidence=medium'#13#10 +
    ';MinConfidence=low'#13#10 +
    ';MinConfidence=high'#13#10 +
    ''#13#10 +
    '; IdeProfile / IdeMinSeverity (defaults: ide-fast / hint)'#13#10 +
    '; Like Profile / MinSeverity, but for the IDE plugin only (live mode).'#13#10 +
    '; Standalone (form, CLI) uses Profile / MinSeverity. This lets the'#13#10 +
    '; live analysis in the IDE run a lean subset while the full run in the'#13#10 +
    '; standalone applies the complete rule set.'#13#10 +
    'IdeProfile=ide-fast'#13#10 +
    ';IdeProfile=default'#13#10 +
    ';IdeProfile=strict'#13#10 +
    'IdeMinSeverity=hint'#13#10 +
    ';IdeMinSeverity=warning'#13#10 +
    ''#13#10 +
    '; EnableDetectorReviewFilter (bool, default: False)'#13#10 +
    '; Internal review tool: adds a severity-combo entry'#13#10 +
    '; "Detector Review (1 per detector, random)". Takes effect ONLY when'#13#10 +
    '; the build was compiled with {$DEFINE DEBUG} - release builds never'#13#10 +
    '; show the entry, whatever this setting says. Off by default.'#13#10 +
    ';EnableDetectorReviewFilter=true'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Baseline] - hide findings that already existed'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; A baseline is a JSON file of finding fingerprints, written with'#13#10 +
    '; `--write-baseline`. Anything whose fingerprint is in it counts as'#13#10 +
    '; "old" and disappears from the view - what is left is "new since the'#13#10 +
    '; baseline". Nothing is deleted: the export and "write baseline" always'#13#10 +
    '; see the full list.'#13#10 +
    ''#13#10 +
    '[Baseline]'#13#10 +
    ''#13#10 +
    '; File (string, default: empty = the .sca standard location)'#13#10 +
    '; Path to the baseline JSON. Empty does not mean off - the consumers fall'#13#10 +
    '; back to <project>\.sca\<name>.baseline.json.'#13#10 +
    '; Use an ABSOLUTE path: a relative one resolves against different bases'#13#10 +
    '; depending on which part of the tool asks, so the same entry can point'#13#10 +
    '; at different files.'#13#10 +
    '; If the configured file is MISSING, the EXE and the plugin fail open -'#13#10 +
    '; the filter is silently inactive and every finding shows. The CLI aborts'#13#10 +
    '; instead. A typo in the path therefore does not show up in the IDE.'#13#10 +
    'File='#13#10 +
    ';File=C:\repo\.sca\project.baseline.json'#13#10 +
    ''#13#10 +
    '; OnlyNew (bool, default: 0)'#13#10 +
    '; Turns the "only new findings" view filter on. Needs a baseline file to'#13#10 +
    '; be findable, otherwise it does nothing (fail-open).'#13#10 +
    '; The value must be NUMERIC. `OnlyNew=True` does not parse and falls back'#13#10 +
    '; to 0 without a word.'#13#10 +
    '; Read by the standalone EXE and the IDE plugin only - the CLI uses'#13#10 +
    '; --baseline / --baseline-scan instead.'#13#10 +
    'OnlyNew=0'#13#10 +
    ';OnlyNew=1'#13#10 +
    ''#13#10 +
    '; PathInFingerprint (bool, default: 0)'#13#10 +
    '; What identifies a file inside the fingerprint:'#13#10 +
    ';   0 = the file name alone, tolerant of a different checkout location'#13#10 +
    ';   1 = the relative path from the scan root, so same-named units in'#13#10 +
    ';       different folders stop sharing one fingerprint namespace'#13#10 +
    '; SWITCHING THIS INVALIDATES AN EXISTING BASELINE. The mode is stamped'#13#10 +
    '; into the JSON; after a switch the file has to be written again, or only'#13#10 +
    '; the weaker context-hash stage still matches.'#13#10 +
    '; In the CLI, --baseline-path-fingerprint overrides this key.'#13#10 +
    'PathInFingerprint=0'#13#10 +
    ';PathInFingerprint=1'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [PathOverrides] - path-based severity and drop filters'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; Solves test-code noise without weakening the profile: the profile'#13#10 +
    '; stays sharp, but findings on test, demo or generated paths are'#13#10 +
    '; dropped or downgraded.'#13#10 +
    ';'#13#10 +
    '; Format:   <glob> = <action>'#13#10 +
    ';'#13#10 +
    '; Glob:     forward or backslashes; case-insensitive; ** = any depth'#13#10 +
    '; Action:   drop:*                    - drop every finding'#13#10 +
    ';           drop:KindA,KindB,...      - drop only these kinds'#13#10 +
    ';           severity:hint:<KindList>  - downgrade severity'#13#10 +
    ';           severity:warn:<KindList>  -      "'#13#10 +
    ';           severity:error:<KindList> -      " (escalation)'#13#10 +
    ';'#13#10 +
    '; The first matching rule wins - order matters.'#13#10 +
    ';'#13#10 +
    '; Examples (commented out):'#13#10 +
    '[PathOverrides]'#13#10 +
    ';tests\**.pas        = drop:*'#13#10 +
    ';**\test_*.pas       = drop:MissingFinally,MagicNumber'#13#10 +
    ';demos\legacy\**.pas = drop:LongMethod,DeepNesting,CyclomaticComplexity'#13#10 +
    ';src\generated\**    = severity:hint:*'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Silent] - silent-mode editor context menu'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[Silent]'#13#10 +
    ''#13#10 +
    '; Enabled (bool, default: 1)'#13#10 +
    '; Turns the "Analyse current file (silent)" entry in the editor'#13#10 +
    '; right-click menu on or off.'#13#10 +
    '; Also configurable via Tools > Options > Third Party >'#13#10 +
    '; Static Code Analyser.'#13#10 +
    'Enabled=1'#13#10 +
    ';Enabled=0'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Editor] - what a finding opens with (double-click)'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; Affects the standalone EXE ONLY. The IDE plugin jumps straight to'#13#10 +
    '; the spot through the ToolsAPI and needs none of this.'#13#10 +
    ''#13#10 +
    '[Editor]'#13#10 +
    ''#13#10 +
    '; ExternalEditor (string, default: empty = off)'#13#10 +
    '; Full path to an editor. Once set, it takes over opening for EVERY'#13#10 +
    '; kind of file - including .dfm - and the Delphi IDE is no longer'#13#10 +
    '; involved.'#13#10 +
    '; Why that is often the better choice: from the outside the EXE'#13#10 +
    '; cannot hand the IDE a line number (there is no switch for it), so'#13#10 +
    '; it has to simulate Ctrl+G and the digits. An editor that accepts'#13#10 +
    '; the line on its command line hits the mark every time.'#13#10 +
    'ExternalEditor='#13#10 +
    ';ExternalEditor=C:\Program Files\Microsoft VS Code\Code.exe'#13#10 +
    ';ExternalEditor=C:\Program Files\Notepad++\notepad++.exe'#13#10 +
    ';ExternalEditor=C:\Program Files\Sublime Text\subl.exe'#13#10 +
    ''#13#10 +
    '; ExternalEditorArgs (string, default: -g "%file%:%line%")'#13#10 +
    '; Arguments for the editor. Placeholders (case does not matter):'#13#10 +
    ';   %file%  full path of the file'#13#10 +
    ';   %line%  line number (at least 1)'#13#10 +
    ';   %col%   column - currently ALWAYS 1, because findings do not'#13#10 +
    ';           carry a column yet; meant only for editors that refuse'#13#10 +
    ';           to jump without one'#13#10 +
    ';   %dir%   directory of the file, without a trailing separator'#13#10 +
    ';   %%      a literal percent sign'#13#10 +
    '; Anything unknown between percent signs is left as it stands.'#13#10 +
    '; When a value contains a space and the placeholder is not already'#13#10 +
    '; quoted, quotes are added automatically - so the template does not'#13#10 +
    '; have to carry them.'#13#10 +
    '; TWO TRAPS WHEN COPYING A LINE:'#13#10 +
    '; 1. A comment AFTER the value is not stripped; it would become part'#13#10 +
    ';    of the arguments. That is why each editor name sits on the line'#13#10 +
    ';    above its template.'#13#10 +
    '; 2. If the WHOLE value is quoted, Windows strips that outer pair'#13#10 +
    ';    again while reading (that is how the profile API underneath INI'#13#10 +
    ';    files works). The templates below therefore never begin or end'#13#10 +
    ';    with a quote - and they do not need to, because values'#13#10 +
    ';    containing spaces are quoted automatically.'#13#10 +
    ';'#13#10 +
    '; Visual Studio Code (default):'#13#10 +
    'ExternalEditorArgs=-g "%file%:%line%"'#13#10 +
    '; Notepad++:'#13#10 +
    ';ExternalEditorArgs=-n%line% "%file%"'#13#10 +
    '; Sublime Text:'#13#10 +
    ';ExternalEditorArgs=%file%:%line%:%col%'#13#10 +
    '; UltraEdit:'#13#10 +
    ';ExternalEditorArgs=%file%/%line%'#13#10 +
    '; IntelliJ / Rider:'#13#10 +
    ';ExternalEditorArgs=--line %line% "%file%"'#13#10 +
    ''#13#10 +
    '; DfmTarget (string, default: ide)'#13#10 +
    '; What a double-click on a .dfm finding opens WHEN no external editor'#13#10 +
    '; is configured above:'#13#10 +
    ';   ide    = Delphi IDE'#13#10 +
    ';   viewer = built-in text viewer'#13#10 +
    '; An honest note on the choice: depending on registration the IDE'#13#10 +
    '; opens a .dfm in the form designer, and from there no path leads to'#13#10 +
    '; a line number. The built-in viewer shows the file as text and jumps'#13#10 +
    '; to the line reliably - but it cannot change anything. If no handler'#13#10 +
    '; answers at all, the viewer is used anyway.'#13#10 +
    '; zurueckgefallen.'#13#10 +
    'DfmTarget=ide'#13#10 +
    ';DfmTarget=viewer'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [UI] - user-interface settings'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[UI]'#13#10 +
    ''#13#10 +
    '; Language (string, default: en)'#13#10 +
    '; UI language as an ISO 639-1 code. Any code is valid for which a'#13#10 +
    '; translation exists:'#13#10 +
    ';   en = English (default - the source language, no lookup needed)'#13#10 +
    ';   embedded .po files (currently de, fr) - see i18n\ in the repository'#13#10 +
    ';   your own i18n\<code>.po next to the EXE or the plugin BPL'#13#10 +
    ';   '''' (empty) or an unknown code behaves like ''en'''#13#10 +
    '; Affects the user interface ONLY - detector messages, findings and'#13#10 +
    '; exports are never translated.'#13#10 +
    '; Also selectable via Tools > Options > Third Party > Static Code'#13#10 +
    '; Analyser (IDE) or the hamburger menu > Language (form).'#13#10 +
    'Language=en'#13#10 +
    ';Language=de'#13#10 +
    ''#13#10 +
    '; Theme (string, default: system)'#13#10 +
    '; Light or dark for the standalone EXE. The IDE plugin always follows'#13#10 +
    '; the theme of the IDE and does not read this key.'#13#10 +
    ';   system = follow the Windows app theme (as shipped); a theme'#13#10 +
    ';            change in Windows takes effect at once, no restart'#13#10 +
    ';   light  = always light'#13#10 +
    ';   dark   = always dark'#13#10 +
    '; Also selectable in the hamburger menu under "Appearance" - that'#13#10 +
    '; menu item writes exactly this key.'#13#10 +
    'Theme=system'#13#10 +
    ';Theme=dark'#13#10 +
    ''#13#10 +
    '; OverlayPosition (string, default: sameline)'#13#10 +
    '; Position of the hover annotation overlay in the editor:'#13#10 +
    ';   sameline = the overlay starts ON the finding line (the title bar'#13#10 +
    ';              covers the line; it unfolds downwards)'#13#10 +
    ';   below    = the overlay starts one line BELOW the finding line'#13#10 +
    ';              (the former default - the finding line stays visible)'#13#10 +
    '; Also configurable via Tools > Options > Third Party >'#13#10 +
    '; Static Code Analyser. A change requires an IDE restart.'#13#10 +
    'OverlayPosition=sameline'#13#10 +
    ';OverlayPosition=below'#13#10 +
    ''#13#10 +
    '; OverlayTextOnly (bool 0/1, default: 0)'#13#10 +
    '; Text-only variant of the annotation hint in the IDE editor:'#13#10 +
    ';   0 = window overlay with an unfold animation (as before)'#13#10 +
    ';   1 = a single line of text right of the code, transparent (NO'#13#10 +
    ';       background colour - selection and line colour stay visible),'#13#10 +
    ';       shown permanently on every finding line instead of the mini'#13#10 +
    ';       info bar. No window: description and fix example live in the'#13#10 +
    ';       findings panel; dismiss by clicking the text; long titles'#13#10 +
    ';       appear in short form (badge + rule name).'#13#10 +
    '; Also configurable via Tools > Options > Third Party >'#13#10 +
    '; Static Code Analyser. Takes effect once the options are saved;'#13#10 +
    '; OverlayPosition applies to the window overlay (mode 0) only.'#13#10 +
    'OverlayTextOnly=0'#13#10 +
    ';OverlayTextOnly=1'#13#10 +
    '; EditorColorScheme (string, default: default)'#13#10 +
    '; Colour palette of the finding markers in the IDE code editor:'#13#10 +
    ';   default | gray | subtle'#13#10 +
    '; A typo (`grey`, say) falls back to `default` silently. IDE plugin only;'#13#10 +
    '; the standalone EXE ignores it. Takes effect after an IDE restart when'#13#10 +
    '; edited by hand - the options page applies it at once.'#13#10 +
    'EditorColorScheme=default'#13#10 +
    ';EditorColorScheme=gray'#13#10 +
    ';EditorColorScheme=subtle'#13#10 +
    ''#13#10 +
    '; OverlayShowOnHover (bool 0/1, default: 0)'#13#10 +
    '; When the annotation overlay opens in the IDE editor:'#13#10 +
    ';   0 = on a left click on a marked line (default)'#13#10 +
    ';   1 = on hover as well'#13#10 +
    '; Edited by hand it takes effect after an IDE restart; set through'#13#10 +
    '; Tools > Options it applies immediately.'#13#10 +
    'OverlayShowOnHover=0'#13#10 +
    ';OverlayShowOnHover=1'#13#10 +
    ''#13#10 +
    '; ClipboardOnClick (int 1..3, default: 1)'#13#10 +
    '; What clicking a finding line puts on the clipboard (standalone EXE'#13#10 +
    '; AND IDE plugin):'#13#10 +
    ';   1 = leave the clipboard alone (default)'#13#10 +
    ';   2 = Jira mini issue: one headline plus five fact bullets'#13#10 +
    ';       (rule, file:line, method, message, fix hint)'#13#10 +
    ';   3 = Claude AI prompt (the behaviour before 2026-08-12; in the'#13#10 +
    ';       IDE plugin with a quick-fix block prepended when the rule'#13#10 +
    ';       has a quick-fix provider - the EXE copies the prompt'#13#10 +
    ';       without that block)'#13#10 +
    '; Invalid values fall back to 1. A change takes effect on the next'#13#10 +
    '; analysis run at the latest. The explicit copy gestures (context'#13#10 +
    '; menu "Copy AI prompt") always copy the AI prompt regardless of this'#13#10 +
    '; setting. There is no automatic AI access of any kind - the text'#13#10 +
    '; only ever reaches the local clipboard.'#13#10 +
    ';'#13#10 +
    'ClipboardOnClick=1'#13#10 +
    ';ClipboardOnClick=3'#13#10 +
    ''#13#10 +
    '; Element.<Name> (bool 0/1, default: 1)'#13#10 +
    '; Kill switch per UI element of the IDE plugin: 0 silences exactly'#13#10 +
    '; that element without uninstalling anything - for the case where an'#13#10 +
    '; element disturbs the IDE. Takes effect after an IDE restart; the'#13#10 +
    '; plugin reports which elements were skipped at load time via debug'#13#10 +
    '; output (DebugView, prefix SCA-UI). The standalone EXE does not read'#13#10 +
    '; these keys.'#13#10 +
    '; Valid names:'#13#10 +
    ';   SharedUiHooks, DockForm, LineHighlighter, AnnotationOverlay,'#13#10 +
    ';   WatchMode, WarmUpCaches, ViewMenuItem, EditorContextMenu,'#13#10 +
    ';   OptionsPageSCA, OptionsPageSonar, FindingsProperties,'#13#10 +
    ';   AboutBox, ToolsMenuItem'#13#10 +
    '; PackageWizard is deliberately NOT switchable - it carries the'#13#10 +
    '; teardown of every other element on unload.'#13#10 +
    '; Dependent degradation: DockForm=0 also removes the View menu entry;'#13#10 +
    '; WatchMode=0 leaves the properties panel without live findings;'#13#10 +
    '; SharedUiHooks=0 falls back to VCL default colours.'#13#10 +
    ';'#13#10 +
    ';Element.AnnotationOverlay=0'#13#10 +
    ''#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Score] - thresholds for the code-quality letter grade'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; The code-quality tile shows the weighted finding score as a letter'#13#10 +
    '; grade A..E instead of a raw number. Mapping (raw score):'#13#10 +
    ';   A : 0'#13#10 +
    ';   B : 1..GradeBMax'#13#10 +
    ';   C : GradeBMax+1 .. GradeCMax'#13#10 +
    ';   D : GradeCMax+1 .. GradeDMax'#13#10 +
    ';   E : > GradeDMax'#13#10 +
    ';'#13#10 +
    '; Raw values appear in the tooltip. The defaults suit projects around'#13#10 +
    '; 5..50k lines of code; smaller projects may want stricter thresholds,'#13#10 +
    '; legacy repositories more tolerant ones.'#13#10 +
    ';'#13#10 +
    '; Weights (hardcoded, NOT configurable): Vuln=10, Error=7,'#13#10 +
    '; Hotspot=5, Warning=3, Hint=1, FileErr=2.'#13#10 +
    ''#13#10 +
    '[Score]'#13#10 +
    ''#13#10 +
    '; GradeBMax (int, default: 50)'#13#10 +
    '; A raw score up to and including this value earns grade B.'#13#10 +
    'GradeBMax=50'#13#10 +
    ';GradeBMax=20      ; stricter (small project)'#13#10 +
    ';GradeBMax=100     ; more tolerant (legacy repository)'#13#10 +
    ''#13#10 +
    '; GradeCMax (int, default: 200)'#13#10 +
    '; Upper bound for grade C; above it, grade D.'#13#10 +
    'GradeCMax=200'#13#10 +
    ';GradeCMax=80'#13#10 +
    ';GradeCMax=400'#13#10 +
    ''#13#10 +
    '; GradeDMax (int, default: 500)'#13#10 +
    '; Upper bound for grade D; anything above falls to grade E.'#13#10 +
    'GradeDMax=500'#13#10 +
    ';GradeDMax=200'#13#10 +
    ';GradeDMax=1000'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [Sonar] - SonarQube / SonarCloud connection'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';'#13#10 +
    '; Used by the connection check only (`--sonar-test`, "Test Connection" in'#13#10 +
    '; the IDE) and by `--sonar-init`, which writes a sonar-project.properties'#13#10 +
    '; from these values. None of it influences the analysis or any detector.'#13#10 +
    ';'#13#10 +
    '; THIS SECTION HAS THE LOWEST PRIORITY of the four configuration sources.'#13#10 +
    '; A CLI flag, an environment variable (SONAR_HOST_URL, SONAR_TOKEN,'#13#10 +
    '; SONAR_PROJECT_KEY, SONAR_ORGANIZATION, SONAR_BRANCH) and - for the'#13#10 +
    '; project key, organisation and branch - a sonar-project.properties in the'#13#10 +
    '; scanned repository all win over it. `--sonar-test` prints which source'#13#10 +
    '; supplied each value.'#13#10 +
    ';'#13#10 +
    '; THE TOKEN IS NOT IN THIS SECTION. It lives encrypted in [SonarTokens]'#13#10 +
    '; and is written by the options page or `--sonar-token`; on Windows it is'#13#10 +
    '; protected per user and machine, so a copied analyser.ini is useless'#13#10 +
    '; elsewhere. Write it by hand and it will not decrypt. Prefer the'#13#10 +
    '; SONAR_TOKEN environment variable when you do not want it on disk at all.'#13#10 +
    ''#13#10 +
    '[Sonar]'#13#10 +
    ''#13#10 +
    '; HostUrl (string, default: empty)'#13#10 +
    '; Base URL of the server. The connection check sends the token to exactly'#13#10 +
    '; this host as a bearer header - point it somewhere wrong and the secret'#13#10 +
    '; goes there. That is why a sonar.host.url found in the scanned'#13#10 +
    '; repository is deliberately ignored.'#13#10 +
    'HostUrl='#13#10 +
    ';HostUrl=https://sonarcloud.io'#13#10 +
    ';HostUrl=https://sonar.example.internal'#13#10 +
    ''#13#10 +
    '; ProjectKey (string, default: empty)'#13#10 +
    '; The project on the server that the check looks up.'#13#10 +
    'ProjectKey='#13#10 +
    ';ProjectKey=my-org_my-project'#13#10 +
    ''#13#10 +
    '; Organization (string, default: empty)'#13#10 +
    '; SonarCloud tenant key. Without it SonarCloud answers 400 and the check'#13#10 +
    '; reports "project not found" although the project exists.'#13#10 +
    'Organization='#13#10 +
    ';Organization=my-org'#13#10 +
    ''#13#10 +
    '; Branch (string, default: empty)'#13#10 +
    '; Branch name for the project lookup and for --sonar-init.'#13#10 +
    'Branch='#13#10 +
    ';Branch=main'#13#10 +
    ''#13#10 +
    '; Insecure (bool 0/1, default: 0)'#13#10 +
    '; 1 skips TLS certificate validation for the connection check. For a'#13#10 +
    '; server with a self-signed certificate - it weakens exactly the'#13#10 +
    '; transport that carries the token, so leave it at 0 unless you know why.'#13#10 +
    'Insecure=0'#13#10 +
    ';Insecure=1'#13#10 +
    ''#13#10 +
    '; TokenRef (string, default: empty)'#13#10 +
    '; Name of the entry in [SonarTokens] that holds the encrypted token.'#13#10 +
    '; Lets one INI carry several tokens.'#13#10 +
    'TokenRef='#13#10 +
    ';TokenRef=sonarcloud'#13#10;

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
  FOwnershipSinks     := TStringList.Create;
  FOwnershipSinks.CaseSensitive := False;
  FExcludeLeaky       := TStringList.Create;
  FExcludeLeaky.CaseSensitive := False;
  FDfmForbiddenClasses := TStringList.Create;
  FDfmForbiddenClasses.CaseSensitive := False;
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
  FOverlayShowOnHover     := DEF_OVERLAY_SHOW_ON_HOVER;
  FOverlayTextOnly        := DEF_OVERLAY_TEXT_ONLY;
  FEditorColorScheme      := DEF_EDITOR_COLOR_SCHEME;
  FLanguage               := DEF_LANGUAGE;
  FOverlayPosition        := DEF_OVERLAY_POSITION;
  FClipboardOnClick       := DEF_CLIPBOARD_ON_CLICK;

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
  FOwnershipSinks.Free;
  FExcludeLeaky.Free;
  FMagicTrivials.Free;
  FFormatFunctions.Free;
  FDfmForbiddenClasses.Free;
  inherited;
end;

class function TRepoSettings.QuickReadBool(const ASection, AKey: string;
  ADefault: Boolean): Boolean;
// Single-Property-Quick-Read. Loest die ehemals 3+ Boilerplate-Funktionen
// (z.B. IsSilentEnabled, IsShowOnHoverEnabled) in 1-Liner auf.
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
  Ini     : TMemIniFile;
  CfgPath : string;
begin
  Result := ADefault;
  try
    CfgPath := TRepoSettings.ResolvedConfigPath;
    if (CfgPath = '') or not FileExists(CfgPath) then Exit;
    // TMemIniFile wie in Load - NICHT TIniFile: das ginge ueber
    // GetPrivateProfileString, und die Profil-API liest die von
    // EnsureConfigExists als UTF-8+BOM geschriebene Datei als ANSI.
    Ini := TMemIniFile.Create(CfgPath);
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
  Ini     : TMemIniFile;
  CfgPath : string;
begin
  Result := ADefault;
  try
    CfgPath := TRepoSettings.ResolvedConfigPath;
    if (CfgPath = '') or not FileExists(CfgPath) then Exit;
    // TMemIniFile wie in Load - NICHT TIniFile. TIniFile liest ueber
    // GetPrivateProfileString, und die Profil-API interpretiert die von
    // EnsureConfigExists als UTF-8+BOM geschriebene Datei als ANSI. Ein
    // ExternalEditor-Pfad mit Umlaut (C:\Users\Juergen-mit-Umlaut\...)
    // kam so als Zeichensalat zurueck, FileExists schlug fehl, und der
    // eingerichtete Editor war NIE startbar. TMemIniFile laedt ueber
    // TStringList.LoadFromFile mit BOM-Erkennung - derselbe Weg, den
    // die Vollladung schon immer nimmt.
    Ini := TMemIniFile.Create(CfgPath);
    try
      Result := Ini.ReadString(ASection, AKey, ADefault);
    finally
      Ini.Free;
    end;
  except
  end;
end;

// --- Hilfsmittel fuer SectionBlockFromTemplate -------------------------

// Kopfzeile eines Abschnitts: '[Name]'.
function IniIsSectionHead(const ALine: string): Boolean;
var
  S : string;
begin
  S := Trim(ALine);
  Result := (Length(S) >= 2) and (S[1] = '[') and (S[Length(S)] = ']');
end;

// Eine auskommentierte EINSTELLUNG (';Schluessel=Wert') - also ein
// Beispiel, das zum Abschnitt DARUEBER gehoert, im Gegensatz zu
// erklaerendem Fliesstext, der zum Abschnitt DARUNTER ueberleitet.
//
// Unterschieden am LEERZEICHEN hinter dem ';'. Genau so haelt es die
// Vorlage durchgehend: ';Enabled=0' ist ein Beispiel, '; Enabled (bool,
// default: 1)' ist Erklaerung. Ein Versuch ueber "vor dem '=' steht ein
// Bezeichner" scheiterte nachweislich an Prosa wie
// '; Gewichte (hardcoded): Vuln=10, Error=7' - die sah wie eine
// Einstellung aus und zerschnitt [UI] und [Score] falsch.
function IniIsCommentedSetting(const ALine: string): Boolean;
var
  S : string;
begin
  S := Trim(ALine);
  Result := (Length(S) > 1) and (S[1] = ';')
        and (S[2] <> ' ') and (S[2] <> #9)
        and (Pos('=', S) > 0);
end;

// Zeile, die beim Abgrenzen dem NACHBARN zugeschlagen werden darf.
function IniIsFiller(const ALine: string): Boolean;
var
  S : string;
begin
  S := Trim(ALine);
  Result := ((S = '') or (S[1] = ';')) and not IniIsCommentedSetting(ALine);
end;

/// <summary>Erste Zeile des Blocks: Anfang des Erklaerteils ueber AIdx.</summary>
/// <remarks>
///   Geht nach oben nur bis zur EIGENEN Titelzeile ';  [Name] - ...' und
///   deren Rahmen. Ein Lauf "so weit wie Kommentare reichen" lief in den
///   Vorgaengerabschnitt hinein - fuer [Silent] zog er die Beispiele aus
///   [PathOverrides] mit.
/// </remarks>
function IniBlockFirst(ATpl: TStringList; const AHead: string;
  AIdx: Integer): Integer;

  function IsSeparator(const ALine: string): Boolean;
  begin
    // Bewusst ohne StartsStr: das braeuchte System.StrUtils im uses
    // dieser Unit, und die steht dort heute nicht.
    Result := Copy(Trim(ALine), 1, 5) = '; ---';
  end;

var
  i, TitleAt : Integer;
begin
  TitleAt := -1;
  i := AIdx - 1;
  while (i >= 0) and IniIsFiller(ATpl[i]) do
  begin
    if (Copy(Trim(ATpl[i]), 1, 1) = ';')
       and (Pos(LowerCase(AHead), LowerCase(ATpl[i])) > 0) then
    begin
      TitleAt := i;
      Break;
    end;
    Dec(i);
  end;

  if TitleAt < 0 then
    Exit(AIdx);                       // Abschnitt ohne Erklaerblock

  Result := TitleAt;
  if (Result > 0) and IsSeparator(ATpl[Result - 1]) then Dec(Result);
  if (Result > 0) and (Trim(ATpl[Result - 1]) = ';') then Dec(Result);
  if (Result > 0) and (Trim(ATpl[Result - 1]) = '') then Dec(Result);
end;

/// <summary>Erste Zeile NACH dem Block.</summary>
/// <remarks>
///   Bis zum naechsten Abschnittskopf - dessen Erklaerblock aber wieder
///   zurueckgeben, der gehoert ihm.
/// </remarks>
function IniBlockLast(ATpl: TStringList; AIdx: Integer): Integer;
begin
  Result := AIdx + 1;
  while (Result < ATpl.Count) and not IniIsSectionHead(ATpl[Result]) do
    Inc(Result);
  while (Result - 1 > AIdx) and IniIsFiller(ATpl[Result - 1]) do
    Dec(Result);
end;

/// <summary>
///   Schneidet einen Abschnitt samt seines Erklaerblocks aus der
///   mitgelieferten Vorlage. Leer, wenn die Vorlage ihn nicht kennt.
/// </summary>
function SectionBlockFromTemplate(const AHead: string): string;
var
  Tpl               : TStringList;
  i, Idx            : Integer;
  First, Last       : Integer;
begin
  Result := '';
  Tpl := TStringList.Create;
  try
    Tpl.Text := DEFAULT_INI_CONTENT;
    Idx := -1;
    for i := 0 to Tpl.Count - 1 do
      if SameText(Trim(Tpl[i]), AHead) then
      begin
        Idx := i;
        Break;
      end;
    if Idx < 0 then Exit;             // Abschnitt kennt die Vorlage nicht

    First := IniBlockFirst(Tpl, AHead, Idx);
    Last  := IniBlockLast(Tpl, Idx);
    for i := First to Last - 1 do
      // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
      // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
      // noinspection StringConcatInLoop
      Result := Result + Tpl[i] + sLineBreak;
  finally
    Tpl.Free;
  end;
end;

class function TRepoSettings.EnsureSection(const ASection: string): Boolean;
var
  Path, Head, Block : string;
  Cur               : TStringList;
  Bytes             : TBytes;
  FS                : TFileStream;
  i                 : Integer;
begin
  Result := False;
  Head   := '[' + ASection + ']';
  try
    Path := TRepoSettings.ResolvedConfigPath;
    // Gibt es die Datei gar nicht, ist EnsureConfigExists zustaendig -
    // die schreibt ohnehin die vollstaendige Vorlage.
    if (Path = '') or not FileExists(Path) then Exit;

    Cur := TStringList.Create;
    try
      Cur.LoadFromFile(Path, TEncoding.UTF8);
      // Schon vorhanden? Dann nichts anfassen. Auf ZEILEN vergleichen,
      // damit ein '[Editor]' mitten in einem Kommentar nicht als
      // vorhandener Abschnitt durchgeht.
      for i := 0 to Cur.Count - 1 do
        if SameText(Trim(Cur[i]), Head) then Exit;
    finally
      Cur.Free;
    end;

    Block := SectionBlockFromTemplate(Head);
    if Trim(Block) = '' then Exit;

    // ANHAENGEN, nicht neu schreiben. Die vorhandene Datei wird dabei
    // kein einziges Byte umgeschrieben - waere sie ohne BOM und mit
    // Umlauten gespeichert, haette ein Neuschreiben ueber
    // TEncoding.UTF8 sie unwiederbringlich verstuemmelt. Der Block
    // selbst ist reines ASCII und damit in beiden Kodierungen gleich.
    Bytes := TEncoding.ASCII.GetBytes(sLineBreak + Block);
    FS := TFileStream.Create(Path, fmOpenReadWrite or fmShareDenyWrite);
    try
      FS.Seek(0, soEnd);
      FS.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
    Result := True;
  except
    // Eine nicht schreibbare Konfiguration ist kein Fehler, den diese
    // Stelle behandeln koennte - dann fehlt eben die Erklaerung.
    Result := False;
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
  // Bestands-INIs kennen [Components] noch nicht (Sektion kam mit der
  // SCA038-Belebung): den dokumentierten Vorlagenblock anhaengen, damit
  // der Schluessel auffindbar ist. No-op, sobald die Sektion existiert;
  // fehlt die Datei ganz, hat EnsureConfigExists sie eben mit Vorlage
  // inklusive [Components] geschrieben.
  EnsureSection('Components');
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

    // [Detectors] OwnershipSinks=Routine1,Routine2,... -> FOwnershipSinks (#5)
    RawList := Trim(Ini.ReadString('Detectors', 'OwnershipSinks', ''));
    FOwnershipSinks.Clear;
    if RawList <> '' then
    begin
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FOwnershipSinks.Add(Trimmed);
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
    // Untere Schranke: <2 laesst in uDuplicateBlock den Window-Loop
    // (0..MinBlockLines-1) leer laufen + einen Out-of-Bounds-Read auf
    // Normalized[NCount] zu -> jede Datei als Massen-Duplikat bzw. Range-
    // Check-Crash. Endanwender-Fehlkonfig (0/negativ) hart abfangen.
    if FMinBlockLines < 2 then FMinBlockLines := 2;
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

    // [Components] ForbiddenClasses=TLabel,TQuery (CSV) -> SCA038.
    // Immer erst leeren: anders als bei FormatFunctions gibt es keine
    // Constructor-Defaults zu bewahren - leer heisst Detektor stumm.
    FDfmForbiddenClasses.Clear;
    RawList := Trim(Ini.ReadString('Components', 'ForbiddenClasses', ''));
    if RawList <> '' then
    begin
      Items := RawList.Split([',', ';']);
      for Item in Items do
      begin
        Trimmed := Trim(Item);
        if Trimmed <> '' then FDfmForbiddenClasses.Add(Trimmed);
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
    FOverlayShowOnHover   := Ini.ReadBool  ('UI',      'OverlayShowOnHover',   DEF_OVERLAY_SHOW_ON_HOVER);
    FOverlayTextOnly      := Ini.ReadBool  ('UI',      'OverlayTextOnly',      DEF_OVERLAY_TEXT_ONLY);
    FEditorColorScheme    := Ini.ReadString('UI',      'EditorColorScheme',    DEF_EDITOR_COLOR_SCHEME);

    // [Baseline] - non-destruktiver "nur neue Funde"-Filter im IDE-Editor.
    // File = Pfad zur Baseline-JSON (kompatibel mit CLI --write-baseline und
    // HTML-Export). OnlyNew=False (Default) -> Filter aus, alle Funde sichtbar.
    FBaselineFile    := Trim(Ini.ReadString('Baseline', 'File',    ''));
    FBaselinePathFp  := Ini.ReadBool       ('Baseline', 'PathInFingerprint', False);
    FBaselineOnlyNew := Ini.ReadBool       ('Baseline', 'OnlyNew', DEF_BASELINE_ONLY_NEW);

    // [Hotkeys] Master-Toggle + Per-Feature-Toggle + Shortcut-Strings.
    FLanguage        := Trim(Ini.ReadString('UI', 'Language',        DEF_LANGUAGE)).ToLower;
    FOverlayPosition := Trim(Ini.ReadString('UI', 'OverlayPosition', DEF_OVERLAY_POSITION)).ToLower;
    if (FOverlayPosition <> 'sameline') and (FOverlayPosition <> 'below') then
      FOverlayPosition := 'sameline';  // unbekannter Wert -> Default

    // [UI] ClipboardOnClick (1..3, s. Property-Doku). Validierung wie bei
    // OverlayPosition: unbekannter Wert -> Default (= nicht anfassen).
    FClipboardOnClick := Ini.ReadInteger('UI', 'ClipboardOnClick',
      DEF_CLIPBOARD_ON_CLICK);
    if (FClipboardOnClick < CLIPBOARD_ON_CLICK_MIN) or
       (FClipboardOnClick > CLIPBOARD_ON_CLICK_MAX) then
      FClipboardOnClick := DEF_CLIPBOARD_ON_CLICK;

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

  // #5: Ownership-Sinks in die globale Live-Liste spiegeln (ResetEngineConfig-
  // Defaults hat sie zuvor geleert -> Add reicht, dupIgnore idempotent).
  if Assigned(uSCAConsts.OwnershipSinks) then
    for i := 0 to FOwnershipSinks.Count - 1 do
      uSCAConsts.OwnershipSinks.Add(FOwnershipSinks[i]);

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
    Ini.WriteBool  ('UI',     'OverlayShowOnHover',   FOverlayShowOnHover);
    Ini.WriteBool  ('UI',     'OverlayTextOnly',      FOverlayTextOnly);
    Ini.WriteString('UI',     'EditorColorScheme',    FEditorColorScheme);
    Ini.WriteString('Baseline', 'File',              FBaselineFile);
    Ini.WriteBool  ('Baseline', 'PathInFingerprint', FBaselinePathFp);
    Ini.WriteBool  ('Baseline', 'OnlyNew',           FBaselineOnlyNew);
    // [Detectors]-Toggles: jetzt UI-aenderbar via Tools > Options.
    Ini.WriteBool  ('Detectors', 'UsesCheck',           FUsesCheck);
    Ini.WriteBool  ('Detectors', 'IncludeTests',        FIncludeTests);
    Ini.WriteBool  ('Detectors', 'AutoDiscoverClasses', FAutoDiscover);
    Ini.WriteString('UI',    'Language',           FLanguage);
    Ini.WriteString('UI',    'OverlayPosition',    FOverlayPosition);
    Ini.WriteInteger('UI',   'ClipboardOnClick',   FClipboardOnClick);
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

  // [Baseline] PathInFingerprint -> globaler Fingerprint-Modus (die Root
  // setzt der Consumer selbst, weil nur er den Scan-Zuschnitt kennt).
  uSCAConsts.BaselinePathFingerprint := FBaselinePathFp;

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

  // SCA038: verbotene Komponentenklassen spiegeln. BEWUSST hier und
  // nicht in RegisterToLeakyClasses: das rufen nur EXE und IDE-Plugin,
  // die CLI bekaeme die Liste nie (der bei OwnershipSinks dokumentierte
  // Defekt wuerde sich wiederholen). Die Globale ist sorted+dupIgnore,
  // Duplikate aus der INI kollabieren dort von selbst.
  if Assigned(uSCAConsts.DfmForbiddenClasses) then
  begin
    uSCAConsts.DfmForbiddenClasses.Clear;
    for i := 0 to FDfmForbiddenClasses.Count - 1 do
      uSCAConsts.DfmForbiddenClasses.Add(FDfmForbiddenClasses[i]);
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
  SnapInst, SnapStat: TStringList;   // Schnappschuss der Globals (unter Lock)
  Raw               : TStringList;
  i                 : Integer;
  Output            : TStringList;
  ChangedInst       : Boolean;
  ChangedStat       : Boolean;
begin
  Inst     := TStringList.Create;
  Stat     := TStringList.Create;
  SnapInst := TStringList.Create;
  SnapStat := TStringList.Create;
  try
    // Die prozessglobalen Discovery-Listen werden in uStaticAnalyzer2
    // (DiscoveredClasses.Add) IMMER unter dem Engine-Lock beschrieben -
    // gelesen wurden sie hier bisher ohne. Einseitige Serialisierung ist
    // keine: Aufrufer ist der UI-Thread (TAnalyserFrame.FinishAnalysis bzw.
    // uMainForm), und ein parallel gestarteter Watch-Worker schreibt
    // waehrenddessen. Beide Listen sind Sorted, jedes Add ist damit ein
    // InsertItem mit moeglichem Realloc + Move; der Leser saehe einen
    // veralteten Count, verschobene Elemente oder freigegebene
    // String-Pointer.
    //
    // Deshalb: KOPIEREN unter dem Lock, verarbeiten und schreiben
    // ausserhalb. Das Lock haelt nur fuer die beiden Assign-Aufrufe, das
    // Datei-I/O bleibt draussen.
    //
    // Warum der UI-Thread hier gefahrlos warten darf: ein Worker, der das
    // Lock haelt, blockiert NIE auf dem UI-Thread. Fortschritt geht ueber
    // TThread.Queue (asynchron), und Synchronize(DeliverResults) laeuft
    // erst NACH der Lock-Freigabe (uIDEAnalyseRunner). Es gibt also keinen
    // Zyklus, in dem beide aufeinander warten.
    //
    // WIE LANGE es dauern kann, ist damit aber nicht gesagt - der
    // Kommentar behauptete bis 2026-08-19 "hoechstens ein Watch-Scan (eine
    // Datei)". Das untertreibt: das Lock deckt auch den Aufbau des
    // Vorab-Index, und mehrere Watch-Worker koennen hintereinander
    // anstehen. Im ungluecklichen Fall haelt das den UI-Thread Sekunden.
    // Blockierungsfrei waere ein TryAcquire mit Rueckfall auf "diesmal
    // nicht persistieren" - Discovery-Treffer sind Beiwerk, kein
    // Nutzerauftrag. Bewusst offen gelassen, weil es das Verhalten des
    // Speicherns aendert und nicht in einen Kommentar-Nachtrag gehoert.
    //
    // TCriticalSection ist reentrant - ein Aufrufer, der das Lock schon
    // haelt, laeuft durch.
    TAnalysisSession.AcquireEngineLock;
    try
      if Assigned(uSCAConsts.DiscoveredClasses) then
        SnapInst.Assign(uSCAConsts.DiscoveredClasses);
      if Assigned(uSCAConsts.DiscoveredStaticClasses) then
        SnapStat.Assign(uSCAConsts.DiscoveredStaticClasses);
    finally
      TAnalysisSession.ReleaseEngineLock;
    end;

    // Wenn beide Discovery-Listen leer waren: nichts zu tun
    if (SnapInst.Count = 0) and (SnapStat.Count = 0) then Exit;

    EnsureConfigExists;
    LogPath := ExtractFilePath(ConfigFilePath) + LOG_FILE;

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

    // 2) neue Treffer mergen, Excludes ueberspringen - aus dem
    //    Schnappschuss, nicht aus den lebenden Globals.
    MergeNewHits(SnapInst, Inst, FExcludeLeaky, ChangedInst);
    MergeNewHits(SnapStat, Stat, FExcludeLeaky, ChangedStat);

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
    SnapInst.Free;
    SnapStat.Free;
  end;
end;

end.
