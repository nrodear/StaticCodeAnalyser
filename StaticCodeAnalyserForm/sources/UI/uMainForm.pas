unit uMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.IOUtils, System.StrUtils,
  System.Types,   // TPoint + Point()-Inline-Funktion (Hamburger-Popup-Positionierung)
  System.Classes, Vcl.Graphics, System.Generics.Collections,
   Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Grids, Vcl.Menus,   // Vcl.Menus: TPopupMenu/TMenuItem (Hamburger-Felder)
  uStaticAnalyzer2, uEngineApi,
  uMethodd12, uSCAConsts, uFixHint, uClaudePrompt, uFindingCopyText,
  uLocalization,
  uAnalyserTypes,  // SeverityFromKindLevel, TFindingSeverity (Grid-Renderer-Callback)
  uRepoSettings, uRecentPaths, uScanTargetDialog, uFindingGridRenderer, uDfmTextViewer,
  uEditorCommand,                 // TEditorSpec (Parametertyp von OpenViaExternalEditor)
  uIDEHelpPanel,                  // TFindingHintPanel (im class-Feld referenziert)
  uExportMenu,                    // TFindingExportMenu (Class-Field-Reference)
  uFindingFilter,                 // TFilterComboItem (Snapshot-Felder)
  uFuzzyComboSearch,              // tippbare Severity-Combo mit Fuzzy-Suche
  uBaseline,                      // TBaselineSet (class-Feld FBaselineSet) + TBaseline.Write
  Vcl.Controls
 ;

type
  TForm2 = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;             // jetzt: Filter-Row (Severity/Type/Profile/Min/Search)
    PanelActions: TPanel;
    Projectpath: TComboBox;
    ResultGrid: TStringGrid;
    Label1: TLabel;
    Button2: TButton;
    Button6: TButton;
    Button7: TButton;
    StatusBar1: TStatusBar;
    Panel4: TPanel;
    PanelStats: TPanel;       // Sonar-Style Stats-Tile-Reihe (uIDEStatsTiles)
    // ---- Display-Filter (filtern ANGEZEIGTE Findings, kein Re-Run) ----
    LblFilter: TLabel;
    SeverityFilterCombo: TComboBox;
    LblType: TLabel;
    TypeFilterCombo: TComboBox;
    SearchEdit: TEdit;
    // ---- Rule-Set-Filter (Profile + Min-Severity) ----
    // Combos schreiben transient in TRepoSettings.Profile/MinSeverity
    // und persistieren ueber Save. Wirken erst beim NAECHSTEN Analyse-Klick.
    LblProfile: TLabel;
    ProfileCombo: TComboBox;
    LblMinSev: TLabel;
    MinSevCombo: TComboBox;
    // Branch-Changes Button (VCS-Diff)
    BtnBranch: TButton;
    FBtnHamburger: TButton;
    procedure Button1Click(Sender: TObject);
    procedure ResultGridClick(Sender: TObject);
    procedure ResultGridDblClick(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure Button7Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ResultGridDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure AppShowHint(var HintStr: string; var CanShow: Boolean;
      var HintInfo: THintInfo);
    procedure ProfileComboChange(Sender: TObject);
    procedure MinSevComboChange(Sender: TObject);
    procedure SeverityFilterComboChange(Sender: TObject);
    procedure TypeFilterComboChange(Sender: TObject);
    procedure SearchEditChange(Sender: TObject);
    procedure BtnBranchClick(Sender: TObject);
    // Wird per OnResize gehookt - aktualisiert die 1/3-Breite des Hint-
    // Panels + die Vorher/Nachher-Aufteilung.
    procedure FormResizeHandler(Sender: TObject);

  private
    // Aktuell angezeigte Befunde - in der Form gehalten, damit ResultGridClick
    // den vollen TLeakFinding (inkl. Kind/Severity-Details) zur ausgewaehlten
    // Zeile findet und einen kompletten Claude-AI-Prompt erzeugen kann.
    FAllFindings       : TObjectList<TLeakFinding>;
    // Snapshot der initial-populierten Filter-Combo-Eintraege (FormCreate).
    // RebuildFilterCombos zieht daraus die Eintraege mit > 0 Treffern.
    FAllSeverityItems  : TArray<TFilterComboItem>;
    // Fuzzy-Suche der Severity-Combo; gehoert dem Formular (Owner=Self).
    FSeveritySearch    : TFuzzyComboSearch;
    // Entprellung des Suchfeldes. Das IDE-Plugin hat sie seit laengerem
    // (TAnalyserFrame.SearchChange, 200 ms); hier lief ApplyFilter bis
    // jetzt bei JEDEM Tastendruck ueber alle Befunde.
    FSearchDebounce    : TTimer;
    FAllTypeItems      : TArray<TFilterComboItem>;
    // Gefilterte Untermenge (Display-Filter via Severity/Type/Search).
    // Owned=False - die Findings gehoeren FAllFindings.
    FDisplayedFindings : TList<TLeakFinding>;
    // Aktueller BaseDir des letzten Analyse-Laufs - fuer Re-Filter im
    // Grid-Refresh (FillGridFromFindings braucht ihn).
    FCurrentBaseDir    : string;
    // Cache: absoluter Dateipfad -> ExtractRelativePath(FCurrentBaseDir, ...)
    // Spalte 0 im Grid wird pro Repaint fuer alle sichtbaren Zeilen neu
    // berechnet - bei 150k+ Befunden ist ExtractRelativePath nicht trivial.
    // Wird bei jedem Wechsel von FCurrentBaseDir komplett geleert.
    FRelPathCache      : TDictionary<string, string>;
    // Vorab gebauter Grid-Renderer-Config (mit Closures fuer GetCellText/
    // GetCellSeverity). Zuvor wurde der Config pro Zelle frisch erzeugt -
    // jede Zelle = 2 frisch alloziierte anonyme Methoden (Heap + IRefCount).
    // Bei 300 sichtbaren Zellen pro Repaint × mehreren Repaints/s war das
    // der Hauptgrund warum sich Mausrad-Events bis zu 5s aufgestaut haben.
    // Die Closures referenzieren Self.FDisplayedFindings / FCurrentBaseDir /
    // FRelPathCache - bleiben damit auch bei BaseDir-Wechsel gueltig.
    FGridConfig        : TFindingGridConfig;
    // Stats-Tile Count-Labels (uIDEStatsTiles befuellt sie, UpdateStats
    // schreibt pro Lauf in Caption).
    FTileError, FTileWarn, FTileHint, FTileFileSev : TLabel;
    FTileBug, FTileVuln, FTileDup                  : TLabel;
    FTileCyclomatic, FTileScore                    : TLabel;
    // Hint-Panel rechts vom Grid (Before/After-Code-Beispiele).
    // Standalone-Modus: AlwaysVisible=True (kein Auto-Hide).
    FHintPanel : TFindingHintPanel;
    // Geteilter Export-Menu-Helper (HTML / JSON / CSV / Jira / Clipboard
    // / Sonar-Generic / Sonar-Push). Identisch zum IDE-Plugin.
    FExportMenu : TFindingExportMenu;
    FBtnExport  : TButton;
    // Progress-Feedback waehrend Analyse (analog zum IDE-Plugin).
    // ProgressBar in der StatusBar eingebettet, Cancel-Button daneben.
    // Werden zur Laufzeit erzeugt - kein DFM-Eintrag noetig.
    FProgressBar    : TProgressBar;
    FBtnCancel      : TButton;
    FCancelRequested: Boolean;
    FLastProgressTick: Cardinal;
    // Hamburger-Menue (analog IDE-Plugin): einziger Zugang zu
    // Branch-Changes / Cancel / Export / Settings / Ignore. Toolbar
    // bleibt schlank, Aktionen sind alle ueber dieses Menue erreichbar.
    FHamburgerMenu  : TPopupMenu;
    // Dynamisch ge-Enable/Disable'd in HamburgerMenuPopup.
    FMICancel       : TMenuItem;
    // Untermenue "Language" (Backlog-Welle 1, 2026-07-26). Die Form hat
    // keinen Options-Dialog - Settings heisst hier "analyser.ini im Editor
    // oeffnen". Das Hamburger-Menue ist damit der einzige UI-Ort, an dem
    // eine Sprachauswahl ohne neues Formular Platz hat.
    FMILanguage     : TMenuItem;
    FMIAppearance   : TMenuItem;   // Hell / Dunkel / Wie Windows
    FMIOpenWith     : TMenuItem;   // womit ein Befund geoeffnet wird
    FMIBaseline     : TMenuItem;   // 'Nur neue Funde' (Haken)
    // Fingerprints der akzeptierten Funde. FAllFindings bleibt IMMER
    // vollstaendig - der Filter wirkt nur auf die Anzeige, damit Export
    // und 'Baseline schreiben' weiter alles sehen (Plugin-Semantik).
    FBaselineSet    : TBaselineSet;
    FGridMenu       : TPopupMenu;
    // Zwischenablage ENTPRELLT (Vorbild Plugin-Fix 2026-08-03,
    // FClipCopyTimer in uIDEAnalyserForm): vorher schrieb JEDER
    // Auswahlwechsel - auch jeder Pfeiltasten-Schritt, die VCL feuert
    // OnClick auch bei Tastatur-Navigation - sofort und ungeschuetzt die
    // systemweite Zwischenablage (~30x/s bei gehaltener Taste).
    FClipTimer      : TTimer;
    // Was der KLICK-Pfad in die Zwischenablage legt ([UI] ClipboardOnClick,
    // Default: nichts - fcmNone). Gelesen in FormCreate und je Lauf frisch
    // in ApplyDetectorConfig; Aenderung wirkt beim naechsten Analyse-Lauf.
    // Die explizite Kontextmenue-Geste kopiert unabhaengig davon.
    FClipCopyMode   : TFindingCopyMode;
    // Programmatischer Grid-Umbau (ApplyFilter nach Sortier-/Filter-
    // wechsel) loest ueber die Zeilen-Klemmung OnClick aus - der zeigte
    // dann einen NIE angeklickten Fund im Panel und ueberschrieb die
    // Zwischenablage mit dessen Prompt.
    FGridUpdating   : Boolean;
    // Der letzte linke Mausdruck traf die Kopfzeile (Sortier-Geste).
    // ResultGridClick verbraucht den Merker und steigt aus: OnClick kann
    // Maus- und Tastatur-Ausloesung nicht unterscheiden, und die
    // Mausposition taugt dort nicht als Kriterium - OnClick feuert auch
    // bei Pfeiltasten, waehrend der Zeiger zufaellig ueber der Kopfzeile
    // stehen kann (Begruendung wie am Enter-Handler ResultGridKeyDown).
    FHeaderMousePress : Boolean;
    // Warum der Lauf per Abort endete ('' = Nutzer-Cancel). Wird vom
    // ProgressCallback VOR dem Abort gesetzt und im EAbort-Zweig
    // angezeigt - der Status-Text alleine lag waehrend des Laufs unter
    // der Progressbar und war nie zu sehen.
    FAbortReason    : string;
    FSortColumn     : Integer;     // -1 = unsortiert (Scan-Reihenfolge)
    FSortDescending : Boolean;
    procedure HamburgerClick(Sender: TObject);
    procedure HamburgerMenuPopup(Sender: TObject);
    procedure BuildHamburgerMenu;
    // Fuellt das Sprach-Untermenue aus uLocalization.AvailableLanguages.
    procedure BuildLanguageMenu(AParent: TMenuItem);
    // Header-Klick sortiert; zweiter Klick auf dieselbe Spalte kehrt um.
    // Mechanik wie im Plugin (GridMouseDown dort); die eigentliche
    // Sortierung liegt in uFindingFilter.TFindingSorter.
    procedure ResultGridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ResultGridKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure ClipCopyFire(Sender: TObject);
    // Der Oeffnen-Kern von ResultGridDblClick - auch per Enter erreichbar.
    procedure OpenSelectedFinding;
    // Gemeinsame Aufloesung fuer alle Tasten-Aktionen am Grid: Fund der
    // aktuellen Zeile + absoluter Pfad (DirOfProjectPath-Rebase) + Zeile.
    function  TryResolveSelectedFinding(var AFinding: TLeakFinding;
      var AAbsPath, ARelPath: string; var ALineNo: Integer): Boolean;
    // Ctrl+Alt+S / Ctrl+Alt+F - die Tasten des IDE-Plugins. Das Plugin
    // schreibt in den IDE-Editor (Strg+Z nimmt zurueck); die EXE
    // schreibt in die DATEI, deshalb laufen beide Wege ueber
    // uSourceLineEdit mit Byte-Treue-Probe.
    procedure SuppressSelectedFinding;
    procedure QuickFixSelectedFinding;
    // Kachel-Klicks wie im Plugin: Severity-/Typ-Kacheln filtern das
    // Grid, die Quality-Kachel setzt alle Filter zurueck.
    // Drei Status-Kanaele wie im Plugin (uIDEStatusBar-Schema):
    // 0 = Fundzahl (persistent), 1 = Scan-Fortschritt, 2 = Ereignisse.
    // Detail-Spalte fuellt die Restbreite (Plugin-Pendant GridResize;
    // der SharedUI-Helfer passt nicht - 6-Spalten-Layout dort).
    procedure GridFillResize;
    // Fenster-Bounds/Maximiert + Spaltenbreiten in der Recent-INI.
    procedure SaveWindowLayout;
    procedure RestoreWindowLayout;
    procedure StatusFindings(const T: string);
    procedure StatusProgress(const T: string);
    // --- Baseline (Plugin-Paritaet) ---
    procedure RefreshBaselineSet;
    procedure WriteBaselineClick(Sender: TObject);
    procedure BaselineOnlyNewClick(Sender: TObject);
    function  BaselineActive: Boolean;
    // Baseline-Inkrement 3 (Konzept par.3): .sca-Aufloesung + Checkbox.
    procedure ToggleBaselineOnlyNew(ANewVal: Boolean);
    function  OfferWriteBaseline(const AProbedText: string): Boolean;
    function  CurrentProjOrGroupFile: string;
    function  ResolveUiBaselinePath(ASettings: TRepoSettings;
      AProbed: TStrings): string;
    // --- Kontextmenue am Grid ---
    procedure BuildGridMenu;
    procedure GridMenuPopup(Sender: TObject);
    procedure GridMenuOpenClick(Sender: TObject);
    procedure GridMenuCopyClick(Sender: TObject);
    procedure GridMenuSuppressClick(Sender: TObject);
    procedure WireTiles;
    procedure TileClickSeverity(Sender: TObject);
    procedure TileClickType(Sender: TObject);
    procedure TileClickKind(Sender: TObject);
    procedure TileClickClear(Sender: TObject);
    // Panel der Auswahl nachziehen, OHNE die Zwischenablage anzufassen.
    procedure UpdateHintPanelToSelection;
    // Alle statischen Captions durch den Katalog ziehen. Die DFM-Werte
    // sind nur die Design-Zeit-Vorgabe - ohne diesen Pass blieb die
    // Filterzeile in JEDER Sprache englisch. Wird auch beim
    // Sprachwechsel gerufen (Sofortwirkung fuer Labels/Buttons/Header).
    procedure ApplyUiCaptions;
    procedure BuildAppearanceMenu(AParent: TMenuItem);
    procedure AppearanceItemClick(Sender: TObject);
    procedure BuildOpenWithMenu(AParent: TMenuItem);
    procedure OpenWithItemClick(Sender: TObject);
    procedure ConfigureEditorClick(Sender: TObject);
    procedure PersistDfmTarget(AValue: TDfmTarget);
    // Wird von TAppTheme nach jedem wirksamen Wechsel gerufen.
    // Ein VCL-Style-Wechsel erreicht selbstgezeichnete Flaechen
    // NICHT - Grid, Kacheln und Hilfe-Panel muessen selbst neu.
    procedure ThemeChanged(Sender: TObject);
    // WM_SETTINGCHANGE mit lParam = ImmersiveColorSet ist das
    // einzige Signal, das Windows bei einem Themenwechsel sendet.
    procedure SettingChange(var Msg: TWMSettingChange);
      message WM_SETTINGCHANGE;
    procedure LanguageItemClick(Sender: TObject);
    procedure HamburgerExportClick(Sender: TObject);
    procedure HamburgerSettingsClick(Sender: TObject);
    procedure HamburgerIgnoreListClick(Sender: TObject);
    // Getter / Callback fuer den FExportMenu-Konstruktor.
    function  GetResultGrid: TStringGrid;
    function  GetCurrentBaseDir: string;
    procedure StatusModeProc(const Msg: string);
    // Baut FGridConfig einmal beim Form-Init. Closures binden an Self -
    // referenzieren bei jedem Aufruf die AKTUELLEN Werte der Form-Felder
    // (FDisplayedFindings, FCurrentBaseDir, FRelPathCache).
    procedure InitGridConfig;
    // Wendet die Display-Filter (Severity-Combo / Type-Combo / Search)
    // auf FAllFindings an und fuellt FDisplayedFindings + Grid neu.
    procedure ApplyFilter;
    // Aktualisiert die Stats-Tile-Captions aus FAllFindings.
    procedure UpdateStats;
    // Snapshot der initial-populierten Combo-Items (FormCreate). Wird von
    // RebuildFilterCombos genutzt um nach jedem Scan auf nicht-leere
    // Eintraege zu reduzieren und beim naechsten Scan ggf. wieder zu
    // erweitern.
    procedure SnapshotFilterItems;
    // Idle-Tick der Suchfeld-Entprellung.
    procedure SearchDebounceFire(Sender: TObject);
    // Reduziert SeverityFilterCombo + TypeFilterCombo auf Eintraege deren
    // Mode/Type mindestens einen Treffer in FAllFindings hat ('All' und
    // 'Detector Review' bleiben immer) und setzt BEIDE Combos danach auf
    // 'All' zurueck. Nutzerentscheid 2026-08-12: nach einem Scan startet
    // die Liste immer ungefiltert - vorher wurde die vorige Auswahl
    // restauriert, und ein stehengebliebener Filter las sich wie
    // "der Scan hat kaum etwas gefunden".
    procedure RebuildFilterCombos;
    // Inner helper: registriert eine bereits geladene Settings-Instanz und
    // setzt optional die Discovery-Listen zurueck. Wird vom Analyse-Pfad
    // direkt benutzt (der die Settings noch fuer UsesCheck/AutoDiscover braucht).
    procedure ApplyDetectorConfig(Settings: TRepoSettings;
      AClearDiscovery: Boolean);
    procedure AnalyseAllClasses(Sender: TObject; const path: string);
    // Scan-Scope-Variation (Konzept_ScanScope_2026-07-20, Phase 3):
    // Smart-Path - endet der Combo-Text auf .dproj/.groupproj (Datei
    // existiert), faehrt der Analyse-Button ssProject/ssProjectGroup.
    function  ScopeForPath(const APath: string): TScanScope;
    // Verzeichnis-Sicht auf den Combo-Text fuer Verzeichnis-Konsumenten
    // (Branch, InitialDir): bei Projektdatei-Text deren Verzeichnis.
    function  DirOfProjectPath(const APath: string): string;
    // --- Einen Befund oeffnen (s. ResultGridDblClick) ---------------------
    // Programm und Argumente getrennt uebergeben, Fehler ehrlich melden.
    function  LaunchProcess(const AExe, AParams: string;
      out AError: string): Boolean;
    function  OpenViaExternalEditor(const ASpec: TEditorSpec;
      const AAbsPath: string; ALine: Integer; out AError: string): Boolean;
    function  OpenViaDelphiIde(const AAbsPath: string;
      out AError: string): Boolean;
    // Waehlt den Weg und liefert den Text fuer die Statuszeile.
    function  OpenFindingAt(const AAbsPath, ARelPath: string;
      ALine: Integer): string;
    procedure ProjectpathChangedScope(Sender: TObject);
    procedure AnalyseSingleFile(const AFilePath: string);
    procedure FillGridFromFindings(Findings: TObjectList<TLeakFinding>;
      const ABaseDir: string);
    function  BuildClaudePrompt(F: TLeakFinding): string;
    function SelectPasFile: string;
    procedure LoadRecentPaths;
    procedure SaveRecentPath(const APath: string);
    function  AppPath: string;
    function  RecentIniPath: string;
    // Cancel-Handler fuer den Standalone-Analyse-Lauf.
    procedure BtnCancelClick(Sender: TObject);
    // Worker-Callback aus AnalyzeLeaksRecursive / AnalyzeLeaksFromList.
    // Total < 0  -> Scan-Phase (Marquee)
    // Total >= 0 -> File-Phase (Normal, Position=Current)
    procedure ProgressCallback(Current, Total: Integer);
    // UI-Zustand vor / nach einem Analyse-Lauf.
    procedure BeginAnalysisUI(KnownTotal: Integer);
    procedure EndAnalysisUI;
  public
  end;

var
  Form2: TForm2;

implementation

// noinspection-file BeginEndRequired, BooleanParam, CanBeClassMethod, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DebugOutput, DfmDefaultName, DfmHardcodedCaption, DfmOrphanHandler, DigitGrouping, DuplicateString, EmptyExcept, EmptyOnHandler, EmptyVisibilitySection, ExceptOnException, GodClass, GroupedDeclaration, IfElseBegin, LargeClass, LongMethod, MissingUnitHeader, MultipleExit, NestedTry, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// UI-Form-Top-Level: catch-all-Handler an Action-Grenzen (Click/Resize) sind
// gewollt - eine UI-Exception darf nie die App killen. EmptyOnHandler/
// EmptyExcept fuer EAbort (User-Cancel) sind intentional. DebugOutput-Pattern
// ShowMessage ist hier als User-Feedback-Kanal verwendet, nicht als Debug.
// GodClass/LargeClass: VCL-Main-Form sammelt VCL-Event-Handler, kann nicht
// dekomponiert werden ohne Action-Owner-Splits.

uses
  clipbrd,
  System.IniFiles,                // TIniFile (PersistDfmTarget - kommentarschonend)
  // uBaseline ist in interface uses (TBaselineSet-Feld) - hier nicht mehr
  // listen, sonst E2004 Bezeichner redeklariert.
  uSourceLineEdit,                // Suppress/Quick-Fix schreiben in die Datei
  uQuickFix,                      // TQuickFix.ProposeFix (Ctrl+Alt+F)
  uAppTheme,                      // Hell/Dunkel der Standalone-EXE
  uStaticFiles, uRuleCatalog,
  uExport,                        // TExporter.ExportCsv (kanonischer CSV-Schreiber)
  // uFindingFilter ist bereits in interface uses (TFilterComboItem-Feld) -
  // hier nicht mehr listen, sonst E2004 Bezeichner redeklariert.
  uVcsChanges,                    // BranchClick
  uIDEStatsTiles,                 // TStatsTilesBuilder.Build (Sonar-Style Tiles)
  uIDEToolbar,                    // TIDEToolbar.ApplySegoeUI - UI-Aligning mit IDE-Plugin
  uIDEColors,                     // IDE_BG_CHROME - Chrome-Panel-Hintergrund analog IDE
  uIgnoreList;                    // TIgnoreList.ConfigFilePath - Hamburger-Item
  // ShellAPI + uLocalization sind bereits im interface-uses (E2004-Schutz).
  // uIDEHelpPanel ist im interface-uses (TFindingHintPanel ist class-Feld)

const
  // Wartezeit des Suchfeld-Filters. Bewusst derselbe Wert wie im
  // IDE-Plugin (TAnalyserFrame DEBOUNCE_MS) - beide Oberflaechen sollen
  // sich beim Tippen gleich anfuehlen.
  SEARCH_DEBOUNCE_MS = 200;

{$R *.dfm}

function LoadBeforeWrite(ASettings: TRepoSettings): Boolean;
// Load vor Save - und NUR nach erfolgreichem Load darf geschrieben werden.
//
// TRepoSettings.Save schreibt rund 30 Schluessel aus den Objektfeldern in
// die INI zurueck: Profil, MinSeverity, MinConfidence, Sprache,
// Baseline-Pfad und -Modus, Editor-Farbschema, die Overlay-Optionen und die
// [Detectors]-Schalter. Faellt das vorherige Load aus (INI gesperrt, keine
// Rechte, defekte Datei), stehen genau diese Felder auf den
// Konstruktor-Defaults - und Save ueberschreibt die komplette Konfiguration
// des Nutzers mit Werkseinstellungen. Nicht nur die eine Einstellung, die
// der Klick aendern wollte.
//
// Der Kommentar an LanguageMenuClick beschreibt diese Falle seit jeher
// ("sonst wuerde Save die uebrigen Sections mit den Constructor-Defaults
// ueberschreiben") - eingehalten wurde sie nicht, weil das Load in einem
// stillen 'try ... except end' hing und der Ablauf danach unbeirrt weiter
// zum Save lief. Review-Fund 2026-08-19, dieselbe Klasse wie 3ff1b80 im
// Plugin.
//
// Der Fehler bleibt still (kein Modal-Dialog in einem OnChange), aber
// folgenlos ist er nicht mehr: der Aufrufer schreibt nicht und sagt es in
// der Statuszeile.
begin
  Result := True;
  try
    ASettings.Load;
  except
    Result := False;
  end;
end;

procedure TForm2.FormCreate(Sender: TObject);
var
  Settings    : TRepoSettings;
  ProfileList : TArray<string>;
  Name        : string;
  Idx         : Integer;
begin
  // Nach jedem wirksamen Hell/Dunkel-Wechsel neu zeichnen. Muss VOR dem
  // ersten Aufbau stehen, damit ein Wechsel waehrend des Starts nicht
  // verloren geht.
  TAppTheme.OnChanged := ThemeChanged;

  // UI-Sprache + Profile/MinSeverity-Combo-Inhalte aus analyser.ini lesen.
  // Settings hier kurzlebig - der Analyse-Pfad (ApplyDetectorConfig) baut
  // sich eine eigene frische Instanz, damit Edits an analyser.ini zwischen
  // den Runs ohne Form-Neustart greifen.
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    SetLanguage(Settings.Language);
    // Klick-Kopie-Modus initial lesen; je Analyse-Lauf zieht
    // ApplyDetectorConfig ihn frisch nach (gleiche Semantik wie die
    // uebrigen ini-Werte: Aenderung wirkt beim naechsten Lauf).
    FClipCopyMode := FindingCopyModeFromInt(Settings.ClipboardOnClick);

    // ---- Profile-Combo befuellen aus TRuleCatalog.ProfileNames ----
    ProfileList := TRuleCatalog.ProfileNames;
    // _('default') wie im IDE-Plugin (PopulateProfileCombo). VERTRAG an
    // die .po-Dateien: 'default' MUSS Passthrough bleiben (msgstr =
    // msgid), denn der Combo-Text wird als [Rules] Profile in die INI
    // zurueckgeschrieben und dort wieder per IndexOf gesucht.
    if Length(ProfileList) = 0 then
      ProfileCombo.Items.Add(_('default'))
    else
      for Name in ProfileList do ProfileCombo.Items.Add(Name);
    // Default-Selektion = [Rules] Profile aus INI (leer = default).
    if Settings.Profile <> '' then
      Idx := ProfileCombo.Items.IndexOf(Settings.Profile)
    else
      Idx := ProfileCombo.Items.IndexOf(_('default'));
    if Idx < 0 then Idx := 0;
    ProfileCombo.ItemIndex := Idx;

    // ---- Min-Severity-Combo befuellen: 3 fixe Stufen ----
    // BEWUSST unlokalisiert: die Texte sind zugleich die INI-Werte
    // ([Rules] MinSeverity, Rueckschreiben in MinSevComboChange). Eine
    // Uebersetzung braeuchte eine Display/Value-Trennung - das IDE-Plugin
    // (uIDESCAOptions) haelt sie genauso roh; gemeinsamer Backlog.
    MinSevCombo.Items.Add('hint');
    MinSevCombo.Items.Add('warning');
    MinSevCombo.Items.Add('error');
    Idx := MinSevCombo.Items.IndexOf(LowerCase(Settings.MinSeverity));
    if Idx < 0 then Idx := MinSevCombo.Items.IndexOf('hint');
    MinSevCombo.ItemIndex := Idx;
  finally
    Settings.Free;
  end;
  ApplyUiCaptions;

  // Branch-Button-Hint zur Laufzeit setzen (DFM-Hint waere hardcoded
  // Englisch). Pattern analog zum IDE-Plugin (FBtnAnalyseChanged.Hint).
  BtnBranch.Hint := _('Branch-Changes') + ': ' +
    _('analyse only files changed in current branch');
  ResultGrid.OnDrawCell  := ResultGridDrawCell;
  ResultGrid.OnDblClick  := ResultGridDblClick;
  ResultGrid.OnMouseDown := ResultGridMouseDown;   // Header-Klick = sortieren
  ResultGrid.OnKeyDown   := ResultGridKeyDown;     // Enter = Befund oeffnen

  FBaselineSet := TBaselineSet.Create;
  BuildGridMenu;

  FClipTimer := TTimer.Create(Self);
  FClipTimer.Interval := 120;        // wie im Plugin: eine Kopie nach Idle
  FClipTimer.Enabled  := False;
  FClipTimer.OnTimer  := ClipCopyFire;
  FSortColumn     := -1;
  FSortDescending := False;
  // Tooltip nur fuer Datei-Spalte, dynamisch ueber Application.OnShowHint.
  // Hint muss != '' sein damit VCL das Event ueberhaupt feuert -
  // AppShowHint setzt dann den echten Text aus der Zelle (oder canceled).
  ResultGrid.ParentShowHint := False;
  ResultGrid.ShowHint := True;
  ResultGrid.Hint := ' ';
  Application.HintPause      := 100;
  Application.HintShortPause := 100;
  Application.OnShowHint     := AppShowHint;
  // Owner-list - der Lifetime der TLeakFinding-Instanzen ist an die Form gekoppelt.
  FAllFindings       := TObjectList<TLeakFinding>.Create(True);
  // OwnsObjects=False - referenziert nur Items aus FAllFindings, kein Free.
  FDisplayedFindings := TList<TLeakFinding>.Create;
  // Rel-Path-Cache fuer das Grid (Spalte 0). Wird bei BaseDir-Wechsel
  // geleert (siehe Stelle wo FCurrentBaseDir gesetzt wird).
  FRelPathCache      := TDictionary<string, string>.Create;
  // Grid-Renderer-Config (mit Closures) einmal hier bauen statt pro Zelle.
  InitGridConfig;

  // ---- Display-Filter-Combos befuellen (Severity / Type) ----
  // Tag-Objects halten Ord(TFilterMode/TTypeFilter); ApplyFilter liest sie
  // wieder raus. Liste analog zum IDE-Plugin (uIDEAnalyserForm.CreateUI).
  SeverityFilterCombo.Items.AddObject(_('All'),                    TObject(Ord(fmAll)));
  // DetectorReview: nur in DEBUG-Builds UND wenn die INI
  // [Rules] EnableDetectorReviewFilter=true gesetzt hat. Release-Builds
  // sehen den Eintrag nie - internes Review-Tool, nicht fuer End-User.
  {$IFDEF DEBUG}
  begin
    var DRCfg := TRepoSettings.Create;
    try
      try DRCfg.Load; except end;
      if DRCfg.DetectorReviewFilterEnabled then
        SeverityFilterCombo.Items.AddObject(
          _('Detector Review (1 per detector, random)'),
          TObject(Ord(fmDetectorReview)));
    finally
      DRCfg.Free;
    end;
  end;
  {$ENDIF}
  SeverityFilterCombo.Items.AddObject(_('Errors (all)'),           TObject(Ord(fmErrors)));
  SeverityFilterCombo.Items.AddObject(_('Warnings (all)'),         TObject(Ord(fmWarnings)));
  SeverityFilterCombo.Items.AddObject(_('Hints (all)'),            TObject(Ord(fmHints)));

  // Checklist-Drift-Fix 2026-07-24 (Dedup-Runde): die fruehere Hand-
  // Liste einzelner Detektoren ist ENTFERNT - Einzel-Eintraege kommen
  // jetzt ausschliesslich aus der generierten, nach Severity gruppierten
  // Liste (SCAxxx-Praefix, TFindingFilter.AppendKindFilterItems). Die
  // fmXxx-Enum-Werte bleiben fuer Kompatibilitaet bestehen (tot).
  TFindingFilter.AppendKindFilterItems(SeverityFilterCombo.Items);
  SeverityFilterCombo.ItemIndex := 0;

  // TypeFilterCombo: Items.Objects tragen Ord(TTypeFilter) damit
  // RebuildFilterCombos die aktuelle Auswahl nach einem Scan
  // wiederherstellen kann (ItemIndex-Mapping waere nach dem Filtern
  // verschoben). tfAll = 0 -> Object = nil (siehe ApplyFilter-Lookup).
  // Uebersetzbar, weil die Filterung ueber Ord(TTypeFilter) im Object
  // laeuft (TFindingFilter.Matches vergleicht F.FindingType, nie den
  // Combo-Text) - die Grid-Spalte zeigt weiterhin das technische
  // TypeText-Feld, wie im IDE-Plugin.
  TypeFilterCombo.Items.AddObject(_('All'),              TObject(Ord(tfAll)));
  TypeFilterCombo.Items.AddObject(_('Bug'),              TObject(Ord(tfBug)));
  TypeFilterCombo.Items.AddObject(_('Code Smell'),       TObject(Ord(tfCodeSmell)));
  TypeFilterCombo.Items.AddObject(_('Vulnerability'),    TObject(Ord(tfVulnerability)));
  TypeFilterCombo.Items.AddObject(_('Security Hotspot'), TObject(Ord(tfSecurityHotspot)));
  TypeFilterCombo.Items.AddObject(_('Code Duplication'), TObject(Ord(tfCodeDuplication)));
  TypeFilterCombo.ItemIndex := 0;

  // Snapshot der frisch populierten Combo-Items - RebuildFilterCombos
  // reduziert daraus pro Scan auf Eintraege mit > 0 Treffern.
  SnapshotFilterItems;

  // Fuzzy-Suche auf der Severity-Combo. Sie traegt rund 200 Eintraege
  // (jede Regel als 'SCAxxx  KindName'); Scrollen ist dafuer die falsche
  // Bedienung. Der Helfer stellt die Combo auf csDropDown, filtert beim
  // Tippen und ruft SeverityFilterComboChange erst bei echter Auswahl -
  // sonst liefe mit jeder Taste ein Filterlauf ueber alle Befunde.
  FSeveritySearch := TFuzzyComboSearch.Create(Self);
  FSeveritySearch.Attach(SeverityFilterCombo);

  // Entprellung des Suchfeldes - 200 ms wie im IDE-Plugin.
  FSearchDebounce := TTimer.Create(Self);
  FSearchDebounce.Interval := SEARCH_DEBOUNCE_MS;
  FSearchDebounce.Enabled  := False;
  FSearchDebounce.OnTimer  := SearchDebounceFire;

  // ---- Sonar-Style Stats-Tile-Reihe oberhalb des Grids -----------------
  // PanelStats kommt aus dem DFM (alTop, Height=45). Tiles werden als
  // alLeft-Reihe gebaut. OUT-Params landen in den Frame-Feldern damit
  // UpdateStats sie spaeter befuellen kann.
  TStatsTilesBuilder.Build(Self, PanelStats,
    FTileError, FTileWarn, FTileHint, FTileFileSev,
    FTileBug, FTileVuln, FTileDup, FTileCyclomatic, FTileScore);
  WireTiles;   // Kacheln klickbar wie im Plugin (Filter/Reset)

  // ---- Hint-Panel rechts vom Grid (Before/After-Code-Beispiele) ----
  // AlwaysVisible=True - Standalone hat keinen Dock-Container, der
  // IDE-Plugin-Auto-Hide-Mechanismus wuerde sonst das Panel verstecken.
  // Parent=Panel2 (Grid-Container), Anchor=ResultGrid - so docked sich
  // das HelpPanel alRight zum Grid und kriegt initial 1/3 der Breite.
  FHintPanel := TFindingHintPanel.Create(Self, Panel2, ResultGrid, True);
  FHintPanel.ShowPlaceholder;
  FHintPanel.ApplyLayout;
  // OnResize hooken damit das HintPanel sich bei Form-Resize an die
  // 1/3-Breite anpasst (und die Vorher/Nachher-Aufteilung neu rechnet).
  Self.OnResize := FormResizeHandler;

  // ---- Export-Button + geteiltes Popup-Menu (HTML / JSON / CSV / Jira /
  //      Clipboard / Sonar-Generic / Sonar-Push). Selbe Implementierung
  //      wie im IDE-Plugin via uExportMenu.TFindingExportMenu.
  FBtnExport := TButton.Create(Self);
  FBtnExport.Parent  := PanelActions; // gleiche Toolbar wie Analyse-Buttons
  FBtnExport.Left    := BtnBranch.Left + BtnBranch.Width + 12;
  FBtnExport.Top     := BtnBranch.Top;
  FBtnExport.Width   := 90;
  FBtnExport.Height  := BtnBranch.Height;
  FBtnExport.Caption := _('Export') + ' ' + Char($25BC); // "▼"
  FBtnExport.Hint    := _('Export findings: HTML / JSON / CSV / Jira / ' +
                          'Clipboard / Sonar');
  FBtnExport.ShowHint := True;
  FExportMenu := TFindingExportMenu.Create(Self,
    FAllFindings, FDisplayedFindings,
    GetResultGrid, StatusModeProc, GetCurrentBaseDir);
  FExportMenu.AttachToButton(FBtnExport);

  // ---- ProgressBar + Cancel-Button in der StatusBar (Laufzeit-Widgets)
  // Layout: Cancel-Button rechts am StatusBar-Rand (alRight), die
  // ProgressBar mit FESTER Breite links daneben (ebenfalls alRight).
  // Frueher lag die Bar alClient ueber der GANZEN StatusBar und
  // verdeckte damit genau die Panel-Texte, die der Scan schreibt
  // ('File %d / %d (%d%%)') - sichtbar war nur ein Balken ohne Zahlen,
  // und auch die Limit-Meldung lief ins Leere. Beide Widgets werden in
  // BeginAnalysisUI sichtbar geschaltet und in EndAnalysisUI versteckt.
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent  := StatusBar1;
  FBtnCancel.Caption := _('Cancel');
  FBtnCancel.Width   := MulDiv(80, Screen.PixelsPerInch, 96);
  FBtnCancel.Align   := alRight;
  FBtnCancel.Enabled := False;
  FBtnCancel.Visible := False;
  FBtnCancel.OnClick := BtnCancelClick;

  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent  := StatusBar1;
  // Left := 0 VOR dem Align: bei zwei alRight-Controls ordnet die VCL
  // nach der aktuellen Position - so landet die Bar links vom Cancel.
  FProgressBar.Left    := 0;
  FProgressBar.Width   := MulDiv(240, Screen.PixelsPerInch, 96);
  FProgressBar.Align   := alRight;
  FProgressBar.Min     := 0;
  FProgressBar.Max     := 100;
  FProgressBar.Position:= 0;
  FProgressBar.Smooth  := True;
  FProgressBar.Style   := pbstNormal;
  FProgressBar.Visible := False;

  // ---- Hamburger-Menu (analog IDE-Plugin) -------------------------------
  // Konsolidiert Cancel / Export / Settings / Ignore in EIN Popup-Menu.
  // BtnBranch bleibt als eigenstaendiger Top-Level-Button sichtbar
  // (User-Wunsch - Branch-Analyse ist haeufig genug fuer einen direkten
  // Toolbar-Slot, Hamburger wuerde nur Klicks kosten).
  // Position: rechts neben BtnBranch (dort wo frueher FBtnExport sass).
  //FBtnHamburger := TButton.Create(Self);
  FBtnHamburger.Caption := #$2630;  // 'Trigram for Heaven' = Hamburger-Glyph
  FBtnHamburger.Hint    := _('Actions menu: Cancel, Export, Settings, Ignore');
  FBtnHamburger.ShowHint := True;
  FBtnHamburger.OnClick := HamburgerClick;
  BuildHamburgerMenu;
  // KEIN PopupMenu-Property setzen - die OnClick-Procedure macht den Popup
  // explizit via Menu.Popup(P.X, P.Y) am Hamburger-Button.

  // FBtnExport in der Toolbar verstecken - Export ist ueber das Hamburger-
  // Menu erreichbar. BtnBranch bleibt SICHTBAR als eigener Button.
  FBtnExport.Visible := False;

  // ---- Theming + Schrift-Konsistenz mit IDE-Plugin ----------------------
  // Segoe UI rekursiv auf alle Controls. Macht die Standalone-UI optisch
  // identisch mit dem IDE-Plugin (gleicher Helper).
  TIDEToolbar.ApplySegoeUI(Self);

  // Chrome-Panels in der gleichen Farbe wie das IDE-Plugin (IDE_BG_CHROME =
  // clBtnFace in Default-Theme, vom VCL-StyleHook automatisch geupdated
  // wenn der User ein anderes VCL-Theme aktiviert).
  PanelStats.Color   := IDE_BG_CHROME;
  PanelActions.Color := IDE_BG_CHROME;
  if Assigned(Panel3) then Panel3.Color := IDE_BG_CHROME;

  LoadRecentPaths;

  // Mindestgroesse: darunter kollabiert die absolut positionierte
  // Filterzeile (Suchfeld auf 0, Labels uebereinander) - die UI liess
  // sich kaputt-verkleinern (UI-Review P2-17). DPI-skaliert.
  Constraints.MinWidth  := MulDiv(760, Screen.PixelsPerInch, 96);
  Constraints.MinHeight := MulDiv(400, Screen.PixelsPerInch, 96);

  // Fenster/Spalten aus der letzten Sitzung (mit Monitor-Klemme),
  // danach die Detail-Spalte auf die Restbreite fuellen.
  RestoreWindowLayout;
  GridFillResize;

  // Scan-Scope Smart-Path (Konzept par.4.3): Button-Caption folgt dem
  // Combo-Inhalt (Verzeichnis vs .dproj vs .groupproj). Initial syncen.
  Projectpath.OnChange := ProjectpathChangedScope;
  ProjectpathChangedScope(nil);

  // ZULETZT, wenn ALLE Controls stehen: die Kacheln und die
  // Chrome-Panels oben entstehen NACH dem Style-Setzen im .dpr, und sie
  // malen mit ihrer eigenen Color auf eine Systemfarbe, die Windows im
  // Dunkelmodus nicht mitaendert. Ohne diesen Aufruf waeren sie beim
  // START hell - der Wechsel ueber das Menue haette sie dagegen
  // eingefaerbt, was den Fehler beim Pruefen leicht verdeckt.
  TAppTheme.ResolveSystemColors(Self);
end;

procedure TForm2.BtnCancelClick(Sender: TObject);
begin
  FCancelRequested := True;
  // Sofort sperren - verhindert Doppelklick-Spam bevor der naechste
  // Callback den Abort durchfuehrt.
  FBtnCancel.Enabled := False;
end;

procedure TForm2.BeginAnalysisUI(KnownTotal: Integer);
begin
  FCancelRequested  := False;
  FAbortReason      := '';
  FLastProgressTick := 0;
  Screen.Cursor     := crAppStart;
  // Analyse-Ausloeser sperren: der Callback pumpt Nachrichten, und ein
  // zweiter Klick (der ungeduldige Normalfall) schachtelte sonst einen
  // zweiten Lauf in den ersten - Cancel-Flag resettet, das innere
  // EndAnalysisUI versteckte Progressbar und Cancel des aeusseren Laufs,
  // Ergebnisse ueberschrieben sich. Export mit sperren: er laese
  // FAllFindings, waehrend der Lauf sie ersetzt.
  StatusProgress('');
  Button6.Enabled    := False;
  Button7.Enabled    := False;
  BtnBranch.Enabled  := False;
  if Assigned(FBtnExport) then FBtnExport.Enabled := False;
  FBtnCancel.Enabled := True;
  FBtnCancel.Visible := True;
  if KnownTotal > 0 then
  begin
    FProgressBar.Style := pbstNormal;
    FProgressBar.Max   := KnownTotal;
  end
  else
  begin
    // Scan-Phase: Marquee bis der erste File-Phase-Callback kommt.
    FProgressBar.Style := pbstMarquee;
    FProgressBar.Max   := 100;
  end;
  FProgressBar.Position := 0;
  FProgressBar.Visible  := True;
end;

procedure TForm2.EndAnalysisUI;
begin
  Button6.Enabled       := True;
  Button7.Enabled       := True;
  BtnBranch.Enabled     := True;
  if Assigned(FBtnExport) then FBtnExport.Enabled := True;
  FBtnCancel.Enabled    := False;
  FBtnCancel.Visible    := False;
  FProgressBar.Style    := pbstNormal;
  FProgressBar.Position := 0;
  FProgressBar.Visible  := False;
  Screen.Cursor         := crDefault;
end;

procedure TForm2.ProgressCallback(Current, Total: Integer);
// Wird vom Analyzer-Worker aufgerufen. Total<0 = Scan-Phase, sonst File-Phase.
// Throttle auf ~10/s damit das UI nicht ueberflutet wird.
const
  MAX_SCAN_FILES = 20000;
var
  tick     : Cardinal;
  doUpdate : Boolean;
begin
  // Auch das Fenster-X zaehlt: der Scan laeuft synchron im Hauptthread,
  // und ohne diese Pruefung lief er nach dem Schliessen-Klick stumm
  // weiter - die App wirkte abgestuerzt, das Fenster blieb stehen.
  if FCancelRequested or Application.Terminated then
    Abort;

  tick     := GetTickCount;
  doUpdate := (tick - FLastProgressTick > 100);

  // Defensiv: erster File-Phase-Tick (Total>=0) MUSS durch, damit der
  // Style-Switch Marquee->Normal nicht durch den 100ms-Throttle verzoegert
  // wird. Gleiche Logik wie im IDE-Plugin (uIDEAnalyseRunner).
  if (Total >= 0) and (FProgressBar.Style = pbstMarquee) then
    doUpdate := True;

  if Total < 0 then
  begin
    // ---- Scan-Phase ----
    if Current > MAX_SCAN_FILES then
    begin
      // Grund merken - der Status-Text hier laege unter der Progressbar.
      // Der EAbort-Zweig zeigt ihn nach dem Aufraeumen als Dialog, MIT
      // Ausweg: vorher stand nur 'scan cancelled', und wer ein grosses
      // Legacy-Projekt scannte, war ohne Hinweis am Ende.
      FAbortReason := Format(
        _('More than %d files found - scan stopped. Choose a subfolder, ' +
          'or exclude folders via the ignore list (hamburger menu).'),
        [MAX_SCAN_FILES]);
      Abort;
    end;
    if doUpdate then
    begin
      FLastProgressTick := tick;
      if FProgressBar.Style <> pbstMarquee then
        FProgressBar.Style := pbstMarquee;
      StatusProgress(Format(_('Scanning... %d found'), [Current]));
      Application.ProcessMessages;
    end;
  end
  else
  begin
    // ---- File-Phase ----
    if doUpdate or (Current = Total) then
    begin
      FLastProgressTick := tick;
      if FProgressBar.Style <> pbstNormal then
        FProgressBar.Style := pbstNormal;
      if (FProgressBar.Max <> Total) and (Total > 0) then
        FProgressBar.Max := Total;
      FProgressBar.Position := Current;
      if Total > 0 then
        StatusProgress(Format(_('File %d / %d (%d%%)'),
          [Current, Total, Round(Current * 100 / Total)]))
      else
        StatusProgress(Format(_('File %d'), [Current]));
      Application.ProcessMessages;
    end;
  end;
end;

procedure TForm2.FormResizeHandler(Sender: TObject);
begin
  if Assigned(FHintPanel) then FHintPanel.ApplyLayout;
  GridFillResize;
end;

procedure TForm2.GridFillResize;
// Detail-Spalte (3) nimmt die Restbreite - bei maximiertem Fenster lag
// rechts Leerflaeche, waehrend die Meldungs-Spalte auf ihren 148 px aus
// dem DFM klebte. File/Method/Line/Severity behalten ihre (ggf. vom
// Nutzer gezogenen) Breiten.
var
  Used, Rest : Integer;
begin
  Used := ResultGrid.ColWidths[0] + ResultGrid.ColWidths[1] +
          ResultGrid.ColWidths[2] + ResultGrid.ColWidths[4] +
          GetSystemMetrics(SM_CXVSCROLL) + 8;
  Rest := ResultGrid.ClientWidth - Used;
  if Rest > 100 then
    ResultGrid.ColWidths[3] := Rest;
end;

procedure TForm2.SaveWindowLayout;
// In die Recent-INI neben der EXE ([Window]/[Grid]) - dieselbe Datei,
// dieselbe Guard-Philosophie wie die MRU-Pfade: eine nicht schreibbare
// Komfort-INI darf nichts anhalten.
var
  Ini : TIniFile;
  R   : TRect;
  i   : Integer;
begin
  try
    Ini := TIniFile.Create(RecentIniPath);
    try
      // Bei Maximiert die POSITIONSWERTE NICHT anfassen: BoundsRect
      // traegt dann die bildschirmfuellenden Masse, und ein spaeteres
      // 'Wiederherstellen' wuerde ein pseudo-maximiertes Fenster
      // restaurieren. Die zuletzt gesicherten Normal-Bounds bleiben
      // stehen; nur das Flag (und das Grid) wird aktualisiert.
      if WindowState <> wsMaximized then
      begin
        R := BoundsRect;
        Ini.WriteInteger('Window', 'Left',   R.Left);
        Ini.WriteInteger('Window', 'Top',    R.Top);
        Ini.WriteInteger('Window', 'Width',  R.Width);
        Ini.WriteInteger('Window', 'Height', R.Height);
      end;
      Ini.WriteBool   ('Window', 'Maximized', WindowState = wsMaximized);
      for i := 0 to 4 do
        Ini.WriteInteger('Grid', 'W' + IntToStr(i), ResultGrid.ColWidths[i]);
    finally
      Ini.Free;
    end;
  except
    // still - Komfortdaten, s.o.
  end;
end;

procedure TForm2.RestoreWindowLayout;
const
  MIN_COL_W = 20;     // schmaler ist keine benutzbare Spalte
  MAX_COL_W = 2000;   // breiter ist ein kaputter INI-Wert
// Restore mit MONITOR-KLEMME: ein abgestoepselter Zweitmonitor darf
// das Fenster nicht ins Unsichtbare restaurieren.
var
  Ini  : TIniFile;
  R    : TRect;
  Work : TRect;
  Maxi : Boolean;
  i, W : Integer;
begin
  try
    Ini := TIniFile.Create(RecentIniPath);
    try
      if not Ini.ValueExists('Window', 'Width') then Exit;
      R.Left   := Ini.ReadInteger('Window', 'Left',   Left);
      R.Top    := Ini.ReadInteger('Window', 'Top',    Top);
      R.Width  := Ini.ReadInteger('Window', 'Width',  Width);
      R.Height := Ini.ReadInteger('Window', 'Height', Height);
      Maxi     := Ini.ReadBool   ('Window', 'Maximized', False);

      // Klemme auf den Monitor, der dem gespeicherten Rechteck am
      // naechsten ist (MonitorFromRect-Semantik der VCL).
      Work := Screen.MonitorFromRect(R).WorkareaRect;
      if R.Width  > Work.Width  then R.Width  := Work.Width;
      if R.Height > Work.Height then R.Height := Work.Height;
      if R.Left < Work.Left then R.Offset(Work.Left - R.Left, 0);
      if R.Top  < Work.Top  then R.Offset(0, Work.Top - R.Top);
      if R.Right  > Work.Right  then R.Offset(Work.Right - R.Right, 0);
      if R.Bottom > Work.Bottom then R.Offset(0, Work.Bottom - R.Bottom);

      BoundsRect := TRect.Create(R.Left, R.Top, R.Left + R.Width,
                                 R.Top + R.Height);
      if Maxi then
        WindowState := wsMaximized;

      for i := 0 to 4 do
      begin
        W := Ini.ReadInteger('Grid', 'W' + IntToStr(i), -1);
        // Plausibilitaetsfenster gegen kaputte INI-Werte.
        if (W >= MIN_COL_W) and (W <= MAX_COL_W) then
          ResultGrid.ColWidths[i] := W;
      end;
    finally
      Ini.Free;
    end;
  except
    // still - defekte Komfortdaten heissen nur: Standard-Layout.
  end;
end;

// Getter / Callbacks fuer FExportMenu. Live-Reads damit das Menu
// gegen die aktuellen Frame-Felder arbeitet, nicht gegen
// Construct-Zeit-Snapshots.
function TForm2.GetResultGrid: TStringGrid;
begin
  Result := ResultGrid;
end;

function TForm2.GetCurrentBaseDir: string;
begin
  Result := FCurrentBaseDir;
end;

procedure TForm2.StatusModeProc(const Msg: string);
begin
  StatusBar1.Panels[2].Text := Msg;
end;

procedure TForm2.FormDestroy(Sender: TObject);
begin
  SaveWindowLayout;
  // Klassen-Ereignis loesen: TAppTheme lebt laenger als die Form, ein
  // haengender Zeiger waere ein Aufruf ins Freigegebene.
  TAppTheme.OnChanged := nil;

  // Globalen Application.OnShowHint loesen damit kein dangling Methodenzeiger
  // ueberlebt wenn das Form zerstoert wird (relevant beim IDE-Plugin-Hosting).
  if TMethod(Application.OnShowHint).Data = Self then
    Application.OnShowHint := nil;
  FreeAndNil(FBaselineSet);
  FreeAndNil(FRelPathCache);
  FreeAndNil(FDisplayedFindings);
  FreeAndNil(FAllFindings);
end;

procedure TForm2.AppShowHint(var HintStr: string; var CanShow: Boolean;
  var HintInfo: THintInfo);
// Globaler Hint-Filter - feuert vor jedem Tooltip im Application-Scope.
// Wir lassen den Hint nur fuer Spalte 0 des ResultGrid durch und setzen
// CursorRect auf die aktuelle Zelle, damit VCL das Event neu feuert sobald
// die Maus die Zelle verlaesst (sonst bleibt der alte Tooltip kleben).
var
  ACol, ARow : Integer;
begin
  if HintInfo.HintControl <> ResultGrid then Exit;

  ResultGrid.MouseToCell(HintInfo.CursorPos.X, HintInfo.CursorPos.Y,
    ACol, ARow);
  // Virtual-Mode: Tooltip-Text aus FDisplayedFindings (Full-Path) statt
  // ResultGrid.Cells[0, ARow] (das waere im Virtual-Mode leer).
  if (ACol = 0) and (ARow >= 1) and (FDisplayedFindings <> nil) and
     (ARow <= FDisplayedFindings.Count) then
  begin
    HintStr               := FDisplayedFindings[ARow - 1].FileName;
    HintInfo.CursorRect   := ResultGrid.CellRect(ACol, ARow);
    HintInfo.HintMaxWidth := 600;
    CanShow               := True;
  end
  else
    CanShow := False;
end;

procedure TForm2.InitGridConfig;
// Bau-once: die zwei Closures referenzieren Self-Felder direkt, nicht via
// lokal-eingefrorene Variablen. Damit darf FGridConfig fuer die gesamte
// Form-Lebenszeit liegen bleiben - aenderbare Werte (FCurrentBaseDir,
// FDisplayedFindings) werden bei jedem Aufruf frisch ueber Self gelesen.
begin
  // Themenfaehige Konfiguration (2026-08-05). StandaloneConfig hatte
  // SECHS Schalter aus - kein Theme, keine Sortieranzeige, keine
  // Zebrastreifen, kein Akzentbalken, keine fette Dateispalte, keine
  // Ellipsen - und malte statt dessen hart kodierte Pastelltoene. Unter
  // einem dunklen Style waeren die Zeilen damit hell geblieben.
  // SeverityColumn bleibt 4: die EXE hat fuenf Spalten, das Plugin sechs.
  FGridConfig := TFindingGridRenderer.IDEConfig(-1, False);
  FGridConfig.SeverityColumn := 4;
  FGridConfig.GetCellText :=
    function(ACellCol, ACellRow: Integer): string
    var
      f       : TLeakFinding;
      baseDir : string;
    begin
      if ACellRow = 0 then
        Result := ResultGrid.Cells[ACellCol, 0]   // Header weiterhin aus Cells
      else if (FDisplayedFindings <> nil) and
              (ACellRow >= 1) and
              (ACellRow <= FDisplayedFindings.Count) then
      begin
        f := FDisplayedFindings[ACellRow - 1];
        case ACellCol of
          0:
            // Rel-Path-Cache (siehe FRelPathCache). IncludeTrailingPath-
            // Delimiter nur bei Cache-Miss - frueher pro Zelle.
            if not FRelPathCache.TryGetValue(f.FileName, Result) then
            begin
              baseDir := IncludeTrailingPathDelimiter(FCurrentBaseDir);
              Result  := ExtractRelativePath(baseDir, f.FileName);
              FRelPathCache.Add(f.FileName, Result);
            end;
          1: Result := f.MethodName;
          2: Result := f.LineNumber;
          3: Result := f.MissingVar;
          4: Result := f.SeverityText;
        else
          Result := '';
        end;
      end
      else
        // Placeholder-Zeilen (z.B. 'No findings.' / 'No matches.') werden
        // weiterhin via Cells[] gesetzt - aus Cells lesen.
        Result := ResultGrid.Cells[ACellCol, ACellRow];
    end;
  // Direkt-Enum-Lookup statt String-Roundtrip ueber die Severity-Spalte.
  FGridConfig.GetCellSeverity :=
    function(ACellRow: Integer): TFindingSeverity
    var
      f : TLeakFinding;
    begin
      if (FDisplayedFindings <> nil) and
         (ACellRow >= 1) and
         (ACellRow <= FDisplayedFindings.Count) then
      begin
        f := FDisplayedFindings[ACellRow - 1];
        Result := SeverityFromKindLevel(f.Kind, f.Severity);
      end
      else
        Result := fsUnknown;
    end;
end;

procedure TForm2.ResultGridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
// Reicht die in InitGridConfig vorbereitete Config durch - KEINE
// Allokationen mehr pro Zelle. Vorher: 2 anonyme Methoden + Config-Record
// pro DrawCell-Aufruf, bei ~300 Zellen pro Repaint × mehreren Repaints/s
// hat das den Mausrad-Event-Stau verursacht.
begin
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State, FGridConfig);
end;

procedure TForm2.Button1Click(Sender: TObject);
begin
  Close;
end;

procedure TForm2.Button2Click(Sender: TObject);
// '...'-Button (User 2026-07-22): EIN Dialog fuer Ordner ODER .dproj ODER
// .groupproj. Der gewaehlte Pfad landet in der Combo; der Analyse-Button
// erkennt den Scope daran (Smart-Path) und zeigt ihn in der Caption.
var
  Target : string;
begin
  Target := SelectScanTarget(Projectpath.Text);
  if Target <> '' then
    Projectpath.Text := Target;   // Caption-Sync via OnChange (Smart-Path)
end;

procedure TForm2.Button6Click(Sender: TObject);
begin
  if not TStaticFiles.ValidatePath(Projectpath.Text) then
  begin
    ShowMessage(_('Please provide a valid project path.'));
    Exit;
  end;
  SaveRecentPath(Projectpath.Text);
  AnalyseAllClasses(Sender, Projectpath.Text);
end;

procedure TForm2.Button7Click(Sender: TObject);
// Datei-Analyse: Datei-Dialog -> AnalyseSingleFile mit allen Detektoren.
var
  filePath: string;
begin
  filePath := SelectPasFile;
  if filePath = '' then Exit; // User hat abgebrochen
  AnalyseSingleFile(filePath);
end;

function TForm2.SelectPasFile: string;
var
  Dlg: TOpenDialog;
begin
  Result := '';
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title  := _('Select Pascal file to analyse');
    Dlg.Filter := _('Pascal file (*.pas)|*.pas|All files|*.*');
    Dlg.DefaultExt := 'pas';
    // Startverzeichnis aus aktuellem Projektpfad
    if (Projectpath.Text <> '') and DirectoryExists(Projectpath.Text) then
      Dlg.InitialDir := Projectpath.Text;
    if Dlg.Execute then
      Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TForm2.ApplyDetectorConfig(Settings: TRepoSettings;
  AClearDiscovery: Boolean);
begin
  try
    Settings.RegisterToLeakyClasses;
    // UI-Combos gewinnen ueber die INI (analog zum IDE-Plugin). Settings.Load
    // hat gerade die INI-Werte gesetzt - die Combos schreiben jetzt drueber.
    // Leerer Combo-Index lassen wir unangetastet (= INI-Wert bleibt aktiv).
    if Assigned(ProfileCombo) and (ProfileCombo.ItemIndex >= 0) then
      Settings.Profile := ProfileCombo.Items[ProfileCombo.ItemIndex];
    if Assigned(MinSevCombo) and (MinSevCombo.ItemIndex >= 0) then
      Settings.MinSeverity := MinSevCombo.Items[MinSevCombo.ItemIndex];
    // ProjectRoot durchreichen damit relative CustomRulesFile-Pfade
    // (z.B. 'analyser-rules.yml' im Projekt-Wurzelverzeichnis) gefunden werden.
    Settings.ApplyDetectorThresholds(DirOfProjectPath(Projectpath.Text));
    // Klick-Kopie-Modus je Lauf frisch aus der INI - "wirkt beim
    // naechsten Analyse-Lauf", wie in der ini-Vorlage dokumentiert.
    FClipCopyMode := FindingCopyModeFromInt(Settings.ClipboardOnClick);
    AutoDiscoverCustomClasses := Settings.AutoDiscoverClasses;
    if AClearDiscovery then
    begin
      // Discovery-Treffer aus vorherigen Laeufen verwerfen, sonst landen
      // sie mit-persistiert in LeakyClassesDiscover.log.
      if Assigned(uSCAConsts.DiscoveredClasses) then
        uSCAConsts.DiscoveredClasses.Clear;
      if Assigned(uSCAConsts.DiscoveredStaticClasses) then
        uSCAConsts.DiscoveredStaticClasses.Clear;
    end;
    // StatusBar-Indikator: User sieht welches Rule-Set gerade aktiv ist.
    // Format kompakt; bei MaxLen-Ueberlauf truncated VCL automatisch.
    StatusBar1.Panels[2].Text :=
      Format(_('Rule-set: Profile=%s, MinSeverity=%s'),
        [Settings.Profile, Settings.MinSeverity]);
  except
    // INI-Wert defekt darf den Lauf nicht abbrechen.
  end;
end;

function TForm2.ScopeForPath(const APath: string): TScanScope;
var
  P : string;
begin
  Result := ssRecursive;
  P := Trim(APath);
  if not FileExists(P) then Exit;
  if SameText(ExtractFileExt(P), '.dproj') then
    Result := ssProject
  else if SameText(ExtractFileExt(P), '.groupproj') then
    Result := ssProjectGroup;
end;

function TForm2.DirOfProjectPath(const APath: string): string;
begin
  Result := Trim(APath);
  if ScopeForPath(Result) <> ssRecursive then
    Result := ExcludeTrailingPathDelimiter(ExtractFilePath(Result));
end;

procedure TForm2.ProjectpathChangedScope(Sender: TObject);
// Caption-Paritaet 2026-08-14: Caption statisch wie im IDE-Plugin
// ('▶ Analyse'). Der sichtbare Modus-Indikator (Review-Auflage Konzept
// par.4.3) wandert in den Hint - die Information bleibt erhalten, nur
// nicht mehr als abweichender Button-Text.
begin
  Button6.Caption := _('▶ Analyse');
  Button6.ParentShowHint := False;
  Button6.ShowHint := True;
  case ScopeForPath(Projectpath.Text) of
    ssProject:      Button6.Hint := _('Analyse project');
    ssProjectGroup: Button6.Hint := _('Analyse group');
  else
    Button6.Hint := _('Analyse directory');
  end;
end;

procedure TForm2.AnalyseAllClasses(Sender: TObject; const path: string);
var
  Settings: TRepoSettings;
  findings: TObjectList<TLeakFinding>;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    // Custom-LeakyClasses + Excludes in die globalen Listen ziehen,
    // AutoDiscover-Flag durchreichen. MUSS vor dem Analyzer-Aufruf
    // passieren, sonst landet TMeineKlasse & Co. nie in LeakyClasses.
    ApplyDetectorConfig(Settings, True);

    StatusBar1.Panels[2].Text := _('Checking all classes...');
    BeginAnalysisUI(0); // Total unbekannt -> Marquee-Phase
    Application.ProcessMessages;

    findings := nil;
    try
      try
        // Frueher: TStaticAnalyzer.AnalyzeAllClassesRecursive (uParser-basiert,
        // nur MemoryLeak + EmptyExcept). Jetzt: TStaticAnalyzer2 ueber alle 21
        // Detektoren - dieselbe Pipeline wie "Aktuelle Datei" und das IDE-Plugin.
        // Phase 4: Scan ueber die Facade. Config via ApplyDetectorConfig (oben)
        // -> SkipConfig.
        // Ignore-Liste (SkipTests) EXAKT wie das IDE-Plugin (uIDEAnalyseRunner.
        // RunAll): ohne sie scannte die Form bisher tests/ + uTest*.pas mit -
        // Fixtures mit absichtlichen Mustern + dupliziertem SRC -> Standalone
        // zeigte ~4x Hints / ~42x Duplicates ggue. dem Plugin. SkipTests aus
        // IncludeTests (Default skip). CLI bleibt bewusst erschoepfend.
        var Ignore := TIgnoreList.Create;
        try
          try Ignore.LoadDefault; except end;
          Ignore.SkipTests := not Settings.IncludeTests;
          var Req := TScanRequest.Init;
          Req.SkipConfig := True;
          // Smart-Path (Konzept par.4.3): .dproj/.groupproj im Combo-Text
          // -> Projekt-/Gruppen-Scope; IgnoreList wirkt dort ueber den
          // Engine-Dispatch (Aufloesungs-Filter), Auto-IndexRoot haelt die
          // Cross-Unit-Indizes auf Verzeichnis-Breite (Engine-Default).
          Req.Scope      := ScopeForPath(path);
          Req.Path       := path;
          Req.UsesCheck  := Settings.UsesCheck;
          Req.IgnoreList := Ignore;
          Req.Progress   := procedure(C, T: Integer) begin ProgressCallback(C, T); end;
          var Ses := TAnalysisSession.Create;
          var Res: TScanResult := nil;
          try
            Res := Ses.Run(Req);
            findings := Res.ReleaseFindings;
          finally
            Res.Free;
            Ses.Free;
          end;
        finally
          Ignore.Free;
        end;
        // Verzeichnis-Sicht fuer alle Relativpfad-Konsumenten (Grid,
        // Export, Doppelklick) - bei Smart-Path waere 'path' ein Dateipfad.
        FillGridFromFindings(findings, DirOfProjectPath(path));
      except
        on EAbort do
        begin
          // Die Vorgaengerfassung liess den Zweig leer - der Kommentar
          // behauptete 'StatusBar bereits gesetzt', aber der Text stand
          // (a) nur beim Limit-Fall und (b) UNTER der Progressbar. Nach
          // dem Aufraeumen blieb ein eingefrorenes 'File 123 / 500' in
          // der Leiste stehen.
          if FAbortReason <> '' then
          begin
            StatusBar1.Panels[2].Text := FAbortReason;
            ShowMessage(FAbortReason);   // der Ausweg muss ankommen
          end
          else
            StatusBar1.Panels[2].Text := _('Analysis cancelled.');
        end;
        // noinspection ExceptionTooGeneral
        // Catch-all an der Action-Grenze ist in dieser Form gewollt
        // (s. Dateikopf): eine Analyse-Exception darf die App nicht
        // killen, die Meldung traegt die Klartext-Ursache.
        on E: Exception do
          StatusBar1.Panels[2].Text := _('Analysis error: ') + E.Message;
      end;
    finally
      findings.Free;
    end;

    // Discovery-Treffer in INI persistieren (nur wenn aktiviert).
    if Settings.AutoDiscoverClasses then
      try Settings.PersistDiscoveredClasses; except end;
  finally
    Settings.Free;
    EndAnalysisUI;
  end;
end;

procedure TForm2.AnalyseSingleFile(const AFilePath: string);
// Analysiert eine einzelne Datei mit allen Detektoren des AST-basierten
// Analyzers (TStaticAnalyzer2) - ergibt zusaetzlich zu Memory-Leaks auch
// Code-Smells, NilDeref, MagicNumber, DuplicateBlock etc.
var
  Settings: TRepoSettings;
  findings: TObjectList<TLeakFinding>;
begin
  if not FileExists(AFilePath) then
  begin
    ShowMessage(_('File not found: ') + AFilePath);
    Exit;
  end;

  // nil-init ist wichtig: wenn AnalyzeLeaks crasht BEVOR die Liste
  // zugewiesen wird, sehen wir ungueltigen Speicher im finally.
  findings := nil;
  Settings := TRepoSettings.Create;
  // Marquee-Animation waehrend der Single-File-Analyse - analog zum
  // IDE-Plugin RunCurrent. Kein File-Phase-Callback (eine Datei).
  BeginAnalysisUI(0);
  try
    try Settings.Load; except end;
    ApplyDetectorConfig(Settings, True);

    StatusBar1.Panels[2].Text := _('Analysing: ') + ExtractFileName(AFilePath);
    Application.ProcessMessages;

    try
      try
        // Single-File-Analyse mit projektweitem Index (fuer DFM-Repo +
        // andere Cross-Unit-Detektoren). Visibility-Detektoren (CanBeUnit/
        // StrictPrivate/Protected/UnusedPublicMember) laufen mittlerweile
        // single-file-only; der Projekt-Pfad bleibt fuer sie folgenlos.
        // Phase 4: Single-File ueber die Facade (ProjectRoot fuer Cross-Unit-Index).
        var Req := TScanRequest.Init;
        Req.SkipConfig            := True;
        Req.Scope                 := ssSingleFile;
        Req.Path                  := AFilePath;
        Req.SingleFileProjectRoot := DirOfProjectPath(Projectpath.Text);
        Req.UsesCheck             := Settings.UsesCheck;
        var Ses := TAnalysisSession.Create;
        var Res: TScanResult := nil;
        try
          Res := Ses.Run(Req);
          findings := Res.ReleaseFindings;
        finally
          Res.Free;
          Ses.Free;
        end;
      except
        on E: Exception do
        begin
          ShowMessage(_('Analysis error: ') + E.Message);
          Exit;
        end;
      end;

      if Assigned(findings) then
        FillGridFromFindings(findings, ExtractFilePath(AFilePath));
    finally
      findings.Free;
    end;

    if Settings.AutoDiscoverClasses then
      try Settings.PersistDiscoveredClasses; except end;
  finally
    Settings.Free;
    EndAnalysisUI;
  end;
end;

procedure TForm2.FillGridFromFindings(Findings: TObjectList<TLeakFinding>;
  const ABaseDir: string);
// Uebernimmt die Findings ins FAllFindings-Feld + BaseDir + delegiert das
// Grid-Befuellen an ApplyFilter. Damit greift Severity/Type/Search-Filter
// auch beim ersten Befuellen.
var
  i : Integer;
begin
  FAllFindings.Clear;
  if Assigned(Findings) then
  begin
    Findings.OwnsObjects := False;
    for i := 0 to Findings.Count - 1 do
      FAllFindings.Add(Findings[i]);
  end;
  // BaseDir wechselt -> alle gecachten Rel-Paths sind ungueltig.
  if Assigned(FRelPathCache) then
    FRelPathCache.Clear;
  FCurrentBaseDir := ABaseDir;
  // Stats spiegeln immer die GESAMTE Befund-Menge, nicht das gefilterte
  // Subset - User sieht "1 von 234 Bugs gefiltert" auf der Tile-Leiste.
  UpdateStats;
  // Baseline-Set VOR dem Combo-Umbau frisch laden: die Reduktion zaehlt
  // auf der baseline-bereinigten Menge (Konsistenz mit dem Grid) und
  // braeuchte sonst den Stand des VORIGEN Laufs. ApplyFilter laedt zwar
  // selbst nach, aber erst NACH dem Umbau.
  RefreshBaselineSet;
  // Filter-Combos auf Eintraege mit > 0 Treffern reduzieren - muss VOR
  // ApplyFilter laufen damit die anschliessende Filter-Application schon
  // gegen die aktuelle Auswahl (ggf. zurueckgesetzt auf 'All') arbeitet.
  RebuildFilterCombos;
  ApplyFilter;
end;

procedure TForm2.SnapshotFilterItems;
// Snapshot direkt nach Combo-Populate in FormCreate. Wird einmal
// aufgerufen - die Combos werden danach in-place reduziert,
// die Originale leben hier weiter.
var
  i : Integer;
begin
  SetLength(FAllSeverityItems, SeverityFilterCombo.Items.Count);
  for i := 0 to SeverityFilterCombo.Items.Count - 1 do
  begin
    FAllSeverityItems[i].Display := SeverityFilterCombo.Items[i];
    FAllSeverityItems[i].ModeOrd := Integer(SeverityFilterCombo.Items.Objects[i]);
  end;
  SetLength(FAllTypeItems, TypeFilterCombo.Items.Count);
  for i := 0 to TypeFilterCombo.Items.Count - 1 do
  begin
    FAllTypeItems[i].Display := TypeFilterCombo.Items[i];
    FAllTypeItems[i].ModeOrd := Integer(TypeFilterCombo.Items.Objects[i]);
  end;
end;

procedure TForm2.RebuildFilterCombos;
// Reduziert beide Combos auf Eintraege deren Mode/Type in FAllFindings
// mindestens einen Treffer hat. 'All' und 'Detector Review' bleiben
// immer drin (auch bei 0 Treffern - sind statisch nuetzliche Optionen).
//
// NACH DEM NEUAUFBAU STEHEN BEIDE COMBOS AUF 'All' (Index 0 - der
// fmAll/tfAll-Eintrag wird immer behalten und steht per Snapshot-Ordnung
// vorn). Nutzerentscheid 2026-08-12: ein Scan startet immer mit
// ungefilterter Liste. Die fruehere Restaurierung der vorigen Auswahl
// ist damit entfallen - ein stehengebliebener Filter las sich nach dem
// Scan wie "kaum Funde", obwohl nur der alte Filter noch griff. Der
// einzige Aufrufer ist der Nach-Scan-Pfad (PopulateFindings); wer die
// Routine je woanders ruft, uebernimmt damit auch den Reset.
var
  Item : TFilterComboItem;
  i : Integer;
  CountSrc : TList<TLeakFinding>;
  OwnedSrc : TList<TLeakFinding>;
begin
  if FAllFindings = nil then Exit;
  if Length(FAllSeverityItems) = 0 then Exit;

  // KONSISTENZ MIT DEM GRID (Review-Blocker 2026-08-12): gezaehlt wird
  // auf derselben baseline-bereinigten Menge, die ApplyFilter anzeigt.
  // Vorher zaehlte die Reduktion roh - bei aktivem "nur neue Funde" bot
  // die Combo Eintraege an, deren Grid-Sicht leer war. Die Kacheln
  // zaehlen bewusst weiter die Gesamtmenge (Nutzerentscheid 2026-08-12);
  // die Statuszeile benennt die ausgeblendete Anzahl.
  // try beginnt VOR dem Create (nil.Free ist ein No-op): die
  // Befuellschleife allokiert (Fingerprint-Strings, Listen-Wachstum) -
  // eine Ausnahme dort haette die Liste sonst geleakt.
  OwnedSrc := nil;
  CountSrc := FAllFindings;
  try
  if BaselineActive then
  begin
    OwnedSrc := TList<TLeakFinding>.Create;
    for i := 0 to FAllFindings.Count - 1 do
      if not FBaselineSet.Contains(FAllFindings[i]) then
        OwnedSrc.Add(FAllFindings[i]);
    CountSrc := OwnedSrc;
  end;

  // ---- SeverityFilterCombo ----
  SeverityFilterCombo.Items.BeginUpdate;
  try
    SeverityFilterCombo.Clear;
    for Item in FAllSeverityItems do
    begin
      if (Item.ModeOrd = Ord(fmAll))
         or (Item.ModeOrd = Ord(fmDetectorReview))
         or (TFindingFilter.CountForTag(CountSrc, Item.ModeOrd) > 0) then
        SeverityFilterCombo.Items.AddObject(Item.Display,
                                            TObject(Item.ModeOrd));
    end;
  finally
    SeverityFilterCombo.Items.EndUpdate;
  end;
  SeverityFilterCombo.ItemIndex := 0;
  // Der Helfer filtert gegen seinen eigenen Schnappschuss - nach jedem
  // Umbau der Items muss er ihn neu ziehen.
  if Assigned(FSeveritySearch) then FSeveritySearch.Resync;

  // ---- TypeFilterCombo ----
  TypeFilterCombo.Items.BeginUpdate;
  try
    TypeFilterCombo.Clear;
    for Item in FAllTypeItems do
    begin
      if (Item.ModeOrd = Ord(tfAll))
         or (TFindingFilter.CountForType(CountSrc,
                                         TTypeFilter(Item.ModeOrd)) > 0) then
        TypeFilterCombo.Items.AddObject(Item.Display, TObject(Item.ModeOrd));
    end;
  finally
    TypeFilterCombo.Items.EndUpdate;
  end;
  TypeFilterCombo.ItemIndex := 0;

  finally
    OwnedSrc.Free;
  end;
end;

// Implementierung weiter unten (bei WireTiles); UpdateStats braucht sie
// schon hier fuer den Quality-Tooltip-Refresh.
procedure TileWire(CountLbl: TLabel; const AHint: string; ATag: Integer;
  AHandler: TNotifyEvent); forward;

procedure TForm2.UpdateStats;
// Befuellt die 9 Stats-Tiles aus FAllFindings. Quality-Score = gewichtete
// Summe (niedriger = besser); Gewichte 1:1 vom IDE-Plugin uebernommen
// damit die Werte zwischen Standalone und Plugin vergleichbar sind.
// Quality-Kachel zeigt seit der Caption-Paritaet 2026-08-14 wie das
// Plugin den Letter-Grade A..E (Rohzahl + Breakdown im Tooltip).
const
  W_VULN     = 10;
  W_ERROR    = 7;
  W_HOTSPOT  = 5;
  W_WARNING  = 3;
  W_HINT     = 1;
  W_FILEERR  = 2;
var
  f                            : TLeakFinding;
  nErr, nWarn, nHint, nFileErr : Integer;
  nBug, nVuln, nHot, nDup      : Integer;
  nCyclo                       : Integer;
  score                        : Integer;
  grade                        : string;
  Settings                     : TRepoSettings;
  Counters                     : TScoreCounters;
begin
  if not Assigned(FTileError) then Exit;

  nErr  := 0; nWarn := 0; nHint := 0; nFileErr := 0;
  nBug  := 0; nVuln := 0; nHot  := 0; nDup  := 0;
  nCyclo := 0;

  for f in FAllFindings do
  begin
    if f.FindingType = ftFileError then
      Inc(nFileErr)
    else
      case f.Severity of
        lsError   : Inc(nErr);
        lsWarning : Inc(nWarn);
        lsHint    : Inc(nHint);
      end;

    case f.FindingType of
      ftBug             : Inc(nBug);
      ftVulnerability   : Inc(nVuln);
      ftSecurityHotspot : Inc(nHot);
      ftCodeDuplication : Inc(nDup);
    end;

    if f.Kind = fkCyclomaticComplexity then
      Inc(nCyclo);
  end;

  score := nVuln    * W_VULN     +
           nErr     * W_ERROR    +
           nHot     * W_HOTSPOT  +
           nWarn    * W_WARNING  +
           nHint    * W_HINT     +
           nFileErr * W_FILEERR;

  FTileError.Caption      := IntToStr(nErr);
  FTileWarn.Caption       := IntToStr(nWarn);
  FTileHint.Caption       := IntToStr(nHint);
  FTileFileSev.Caption    := IntToStr(nFileErr);
  FTileBug.Caption        := IntToStr(nBug);
  FTileVuln.Caption       := IntToStr(nVuln);
  FTileDup.Caption        := IntToStr(nDup);
  FTileCyclomatic.Caption := IntToStr(nCyclo);

  // Letter-Grade + Detail-Tooltip aus der geteilten Quelle
  // (uIDEStatsTiles) - Anzeige und Wortlaut identisch mit dem Plugin.
  // Schwellwerte aus analyser.ini [Score]; frische TRepoSettings wie
  // ueberall in der EXE (Edits an der ini greifen ohne Neustart).
  Counters.Score      := score;
  Counters.Errors     := nErr;
  Counters.Warnings   := nWarn;
  Counters.Hints      := nHint;
  Counters.Vulns      := nVuln;
  Counters.Hotspots   := nHot;
  Counters.FileErrors := nFileErr;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    Counters.GradeBMax := Settings.ScoreThresholdB;
    Counters.GradeCMax := Settings.ScoreThresholdC;
    Counters.GradeDMax := Settings.ScoreThresholdD;
  finally
    Settings.Free;
  end;
  grade := TStatsTilesBuilder.ScoreToGrade(score,
    Counters.GradeBMax, Counters.GradeCMax, Counters.GradeDMax);
  FTileScore.Caption := grade;
  // TileWire setzt den Hint rekursiv auf alle Sub-Labels der Kachel;
  // Tag/OnClick werden idempotent erneut gesetzt.
  TileWire(FTileScore, TStatsTilesBuilder.BuildScoreHint(grade, Counters),
    0, TileClickClear);
end;

procedure TForm2.ApplyFilter;
// Wendet Severity-Combo / Type-Combo / Search-Edit auf FAllFindings an,
// schreibt das Ergebnis in FDisplayedFindings und triggert Grid-Repaint
// (Virtual-Mode - ResultGridDrawCell.GetCellText zieht den Inhalt
// lazy aus FDisplayedFindings, keine Cells[]-Vorallokation).
// ResultGridClick mappt Grid-Row -> FDisplayedFindings[row-1] (nicht
// FAllFindings!), siehe ResultGridClick.
var
  Criteria       : TFindingFilterCriteria;
  f              : TLeakFinding;
  i              : Integer;
  BaselineHidden : Integer;
  HiddenSuffix   : string;
begin
  // Klick-Seiteneffekte unterdruecken: der Grid-Umbau unten loest ueber
  // die Zeilen-Klemmung OnClick aus (s. ResultGridClick). Try/finally,
  // weil der 0-Treffer-Pfad frueh aussteigt.
  FGridUpdating := True;
  // Ein noch scharfer Kopier-Timer gehoert zur ALTEN Liste - entschaerfen,
  // sonst kopierte er nach dem Umbau, was zufaellig an der geklemmten
  // Zeile steht (Debounce-Fenster-Race, Review 2026-08-12; Pendant im
  // Plugin-ApplyFilter).
  if Assigned(FClipTimer) then
    FClipTimer.Enabled := False;
  try
  // Baseline-Set frisch laden - eine von aussen geaenderte Baseline
  // wirkt damit beim naechsten Filterwechsel, ohne Neustart.
  RefreshBaselineSet;
  Criteria.Mode       := fmAll;
  Criteria.TypeFilter := tfAll;
  Criteria.SearchLow  := '';
  if Assigned(SeverityFilterCombo) and (SeverityFilterCombo.ItemIndex >= 0)
     and Assigned(SeverityFilterCombo.Items.Objects[SeverityFilterCombo.ItemIndex]) then
  begin
    var Tag := Integer(SeverityFilterCombo.Items.Objects[SeverityFilterCombo.ItemIndex]);
    // Kind-Tags (>= KIND_TAG_BASE) sind generierte Einzel-Detektor-
    // Eintraege (Checklist-Drift-Fix 2026-07-24).
    var KTag : TFindingKind;
    if TFindingFilter.KindFromTag(Tag, KTag) then
    begin
      Criteria.Mode       := fmSingleKind;
      Criteria.SingleKind := KTag;
    end
    else if Tag >= 0 then Criteria.Mode := TFilterMode(Tag);
  end;
  // TypeFilterCombo nutzt jetzt Items.Objects = Ord(TTypeFilter) -
  // robust gegen Item-Removal in RebuildFilterCombos. tfAll = 0 ist als
  // nil-Object kodiert (Assigned-Check fuehrt dann auf tfAll-Default).
  if Assigned(TypeFilterCombo) and (TypeFilterCombo.ItemIndex >= 0)
     and Assigned(TypeFilterCombo.Items.Objects[TypeFilterCombo.ItemIndex]) then
    Criteria.TypeFilter := TTypeFilter(
      Integer(TypeFilterCombo.Items.Objects[TypeFilterCombo.ItemIndex]));
  if Assigned(SearchEdit) then
    Criteria.SearchLow := LowerCase(Trim(SearchEdit.Text));

  FDisplayedFindings.Clear;
  BaselineHidden := 0;
  for i := 0 to FAllFindings.Count - 1 do
  begin
    f := FAllFindings[i];
    // Baseline zuerst: akzeptierte Funde ausblenden. FAllFindings bleibt
    // vollstaendig - Export und 'Baseline schreiben' sehen weiter alles
    // (Plugin-Semantik; fail-open bei fehlender/kaputter Datei).
    if BaselineActive and FBaselineSet.Contains(f) then
    begin
      Inc(BaselineHidden);
      Continue;
    end;
    if TFindingFilter.Matches(f, Criteria) then
      FDisplayedFindings.Add(f);
  end;
  // Transparenz fuer den Baseline-Filter: "0 / 4 findings" ohne diesen
  // Zusatz liest sich wie ein kaputter Filter (Fehlerbild 2026-08-12,
  // frisch geschriebene Baseline deckte alle Funde).
  HiddenSuffix := '';
  if BaselineHidden > 0 then
    HiddenSuffix := ' - ' + Format(_('%d hidden by baseline'), [BaselineHidden]);

  // DetectorReview-Stichprobe: pro Detector-Kind 1 zufaelligen Befund
  // behalten. Wird NACH dem normalen Filter-Loop ausgefuehrt, damit
  // Type-/Search-Filter weiter wirken. Severity-Combo greift implizit
  // nicht (fmDetectorReview faellt im Matches durch zum 'else' = True).
  if Criteria.Mode = fmDetectorReview then
  begin
    // Randomize bei jedem Aufruf: anderer Sample bei jeder Filter-
    // Aktion (Reviewer sieht bei Re-Toggle eine neue Stichprobe und
    // deckt ueber mehrere Klicks mehr Befunde ab).
    Randomize;
    var Buckets := TObjectDictionary<TFindingKind,
                     TList<TLeakFinding>>.Create([doOwnsValues]);
    try
      for f in FDisplayedFindings do
      begin
        if not Buckets.ContainsKey(f.Kind) then
          Buckets.Add(f.Kind, TList<TLeakFinding>.Create);
        Buckets[f.Kind].Add(f);  // nur Referenzen, kein Free
      end;
      FDisplayedFindings.Clear;
      for var Bucket in Buckets.Values do
        if Bucket.Count > 0 then
          FDisplayedFindings.Add(Bucket[Random(Bucket.Count)]);
    finally
      Buckets.Free;
    end;
  end;

  // ---- Sortierung (Logik in uFindingFilter.TFindingSorter) ----
  // NACH dem DetectorReview-Sampling und VOR dem Anzeige-Cap - sonst
  // zeigt die Anzeige die falschen Top-N. Dieselbe Stelle wie im Plugin.
  if FSortColumn >= 0 then
  begin
    var SortCfg: TFindingSortConfig;
    // ZUORDNEN, nicht durchreichen: TFindingSorter kennt das 6-spaltige
    // PLUGIN-Layout (0=Datei 1=Methode 2=Zeile 3=Typ 4=Detailtext
    // 5=Schwere-RANG, uFindingFilter case-Verteiler). Das EXE-Grid hat
    // 5 Spalten (0=Datei 1=Methode 2=Zeile 3=Detail 4=Schwere). Roh
    // durchgereicht sortierte 'Severity' nach dem MELDETEXT und
    // 'Detail' nach der unsichtbaren Typ-Kategorie - bei luegendem
    // Sortier-Pfeil; die Rang-Sortierung Error>Warning>Hint war aus
    // der EXE heraus gar nicht erreichbar.
    case FSortColumn of
      3:   SortCfg.Column := 4;   // Detail  -> MissingVar-Text
      4:   SortCfg.Column := 5;   // Schwere -> SeverityRank
    else
      SortCfg.Column := FSortColumn;  // Datei/Methode/Zeile sind gleich
    end;
    SortCfg.Descending := FSortDescending;
    SortCfg.BaseDir    := FCurrentBaseDir;
    TFindingSorter.Sort(FDisplayedFindings, SortCfg);
  end;

  // Anzeige-Cap: TStringGrid wird ab ~50k Zeilen spuerbar trag. Sind mehr
  // Treffer da, kappen wir die Anzeige (Export/CSV/Baseline arbeiten
  // weiterhin mit FAllFindings, sind also nicht betroffen). Die Status-
  // Leiste macht es transparent. 0 = kein Cap (alt).
  var TotalMatched: Integer := FDisplayedFindings.Count;
  if (uSCAConsts.UIMaxDisplayedFindings > 0) and
     (TotalMatched > uSCAConsts.UIMaxDisplayedFindings) then
    // TList<T>.Count := N truncated; OwnsObjects=False -> kein Free.
    FDisplayedFindings.Count := uSCAConsts.UIMaxDisplayedFindings;

  ResultGrid.RowCount := 2;
  ResultGrid.Rows[1].Clear;

  if FDisplayedFindings.Count = 0 then
  begin
    if FAllFindings.Count = 0 then
    begin
      ResultGrid.Cells[0, 1] := _('No findings.');
      StatusFindings(Format(_('%d / %d findings'), [0, 0]));
      StatusBar1.Panels[2].Text  := _('Done. No findings.');
    end
    else
    begin
      ResultGrid.Cells[0, 1] := _('No matches.');
      StatusFindings(Format(_('%d / %d findings'),
        [0, FAllFindings.Count]) + HiddenSuffix);
    end;
    Exit;
  end;

  // Virtual-Mode: nur RowCount setzen. Cell-Strings werden im OnDrawCell
  // ueber Config.GetCellText aus FDisplayedFindings gezogen - spart bei
  // 66k+ Befunden ~50-100 MB Cell-Storage im TStringGrid (32-Bit-Limit).
  ResultGrid.RowCount := FDisplayedFindings.Count + 1;
  ResultGrid.Invalidate;
  // Fundzahl PERSISTENT in Panel 0 (wortgleich zum Plugin) - vorher
  // stand sie in Panel 2 und wurde vom naechsten Klick-Ereignis
  // ('AI prompt copied ...') sofort weggewischt.
  if TotalMatched > FDisplayedFindings.Count then
    StatusFindings(Format(_(
      'Showing first %d of %d findings - refine the filter to see more'),
      [FDisplayedFindings.Count, TotalMatched]) + HiddenSuffix)
  else
    StatusFindings(Format(_('%d / %d findings'),
      [TotalMatched, FAllFindings.Count]) + HiddenSuffix);

  finally
    FGridUpdating := False;
    // Panel der neuen Lage nachziehen (auch im 0-Treffer-Exit-Pfad) -
    // sonst zeigt es einen inzwischen ausgefilterten Fund.
    UpdateHintPanelToSelection;
  end;
end;

var
  // Reentranz-Sperre fuer ResultGridDblClick. Bewusst eine Unit-Variable
  // und KEIN Feld: der Oeffnen-Weg pumpt Nachrichten, in denen das Fenster
  // geschlossen werden kann - ein 'finally FFeld := False' schriebe dann
  // in freigegebenen Speicher. Eine Unit-Variable braucht kein Self und
  // ueberlebt das. Die Anwendung hat genau ein Hauptfenster, also ist eine
  // Sperre pro Prozess auch inhaltlich richtig.
  gOpeningFinding : Boolean = False;

function TForm2.LaunchProcess(const AExe, AParams: string;
  out AError: string): Boolean;
// Ein Programm starten - Programm und Argumente STRIKT getrennt.
//
// Das ist genau die Form, die der eigene Detektor SCA163 (CommandInjection)
// als Abhilfe empfiehlt (uFixHint.pas): lpFile und lpParameters einzeln,
// niemals zu einer Zeichenkette verkettet. Damit kann ein Editorpfad oder
// eine Argumentvorlage aus der INI keine zweite Anweisung einschleusen.
//
// ShellExecuteEx statt ShellExecute, weil nur das einen brauchbaren Fehler
// liefert: ShellExecute gibt einen Zahlenwert zurueck, den im Bestand an
// sechs Stellen niemand geprueft hat, und wirft KEINE Exception - die
// try/except-Bloecke drumherum waren also wirkungslos und die Statuszeile
// meldete auch dann Erfolg, wenn gar nichts aufging.
var
  SEI : TShellExecuteInfo;
begin
  AError := '';
  FillChar(SEI, SizeOf(SEI), 0);
  SEI.cbSize := SizeOf(SEI);
  SEI.fMask  := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_NO_UI;
  SEI.Wnd    := Handle;
  SEI.lpVerb := 'open';
  SEI.lpFile := PChar(AExe);
  if AParams <> '' then
    SEI.lpParameters := PChar(AParams);
  SEI.nShow := SW_SHOWNORMAL;

  Result := ShellExecuteEx(@SEI);
  if Result then
  begin
    // Das Handle kommt wegen NOCLOSEPROCESS mit - sonst leckt es.
    if SEI.hProcess <> 0 then
      CloseHandle(SEI.hProcess);
  end
  else
    AError := SysErrorMessage(GetLastError);
end;

function TForm2.OpenViaExternalEditor(const ASpec: TEditorSpec;
  const AAbsPath: string; ALine: Integer; out AError: string): Boolean;
// Den eingerichteten externen Editor starten. False heisst: keiner
// eingerichtet oder der eingerichtete taugt nicht - der Aufrufer nimmt
// dann den naechsten Weg.
begin
  Result := False;
  AError := '';
  if ASpec.Exe = '' then Exit;         // nicht eingerichtet - kein Fehler
  if not TEditorCommand.IsLaunchableExe(ASpec.Exe) then
  begin
    AError := Format(_('Configured editor cannot be started: %s'), [ASpec.Exe]);
    Exit;
  end;
  Result := LaunchProcess(ASpec.Exe,
              TEditorCommand.Expand(ASpec.ArgsTpl, AAbsPath, ALine), AError);
end;

function TForm2.OpenViaDelphiIde(const AAbsPath: string;
  out AError: string): Boolean;
// Der Windows-Standardhandler oeffnet die Datei - NUR oeffnen, kein
// Zeilensprung. Der fruehere Anlauf ueber simulierte Tastatur (Ctrl+G
// + Ziffern) ist raus (User-Entscheid 2026-08-08): die IDE bietet von
// aussen keinen Zeilen-Schalter, und der blinde Tipp-Versuch schrieb
// die Zeilennummer als TEXT in die gerade geoeffnete Datei. Wer den
// Sprung will, richtet einen externen Editor ein ([Editor] in der
// analyser.ini - dort funktioniert %line%).
begin
  AError := '';
  // ProcessMessages flushed Pending-Events (z.B. den Repaint nach Modal-
  // Close des DFM-Viewers). Ohne das Flush kann der Start beim
  // Delphi-IDE-DDE-Handler "verloren gehen" - die IDE bekommt Focus,
  // oeffnet die Datei aber nicht.
  //
  // ProcessMessages fuehrt allerdings ALLES aus, was in der Schlange
  // steht - auch ein Schliessen des Fensters. Danach zeigen Self und
  // StatusBar1 auf freigegebenen Speicher, deshalb dahinter die
  // Pruefung.
  Application.ProcessMessages;
  if csDestroying in ComponentState then Exit(False);
  Result := LaunchProcess(AAbsPath, '', AError);
end;

function TForm2.OpenFindingAt(const AAbsPath, ARelPath: string;
  ALine: Integer): string;
// Waehlt den Weg und oeffnet. Liefert den Text fuer die Statuszeile -
// oder '', wenn das Fenster waehrenddessen geschlossen wurde und es
// keine Statuszeile mehr zu beschreiben gibt.
//
// Drei Wege, in dieser Reihenfolge:
//   1. Externer Editor, falls in der analyser.ini eingerichtet
//      ([Editor] ExternalEditor). Er gilt fuer ALLE Dateiarten - wer
//      einen einrichtet, will ihn auch benutzen.
//   2. Delphi-IDE ueber den Windows-Standardhandler.
//   3. Nur fuer .dfm: der eingebaute Textbetrachter.
//
// Fuer .dfm entscheidet [Editor] DfmTarget zwischen 2 und 3, Vorgabe ist
// die IDE. Ehrliche Einschraenkung: Weg 2 OEFFNET nur - die Delphi-IDE
// bietet von aussen keinen Zeilensprung (User-Entscheid 2026-08-08,
// vorher tippte eine Tastatur-Simulation die Zeilennummer in den Code).
// Zur Zeile springen koennen nur Weg 1 (%line% im externen Editor) und
// der eingebaute .dfm-Betrachter; der faengt ausserdem den Fall ab,
// dass gar kein Handler antwortet.
var
  spec  : TEditorSpec;
  isDfm : Boolean;
  err   : string;
begin
  isDfm := EndsText('.dfm', AAbsPath);
  // Einmal lesen, beide Entscheidungen daraus. Absichtlich bei JEDEM
  // Doppelklick neu: so wirkt eine Aenderung an der INI sofort, ohne dass
  // erst ein Analyselauf sie einliest.
  spec := TEditorCommand.Load;

  // ---- 1. externer Editor ----
  if OpenViaExternalEditor(spec, AAbsPath, ALine, err) then
  begin
    Result := Format(_('Opened in external editor: %s  Line: %d'),
                     [ARelPath, ALine]);
    Exit;
  end;
  if err <> '' then
    // Eingerichtet, aber untauglich: das ist eine Fehlbedienung, die der
    // Nutzer sehen muss - nicht stillschweigend auf die IDE ausweichen.
    Exit(err);

  // ---- 2. Delphi-IDE ----
  if (not isDfm) or (spec.DfmTarget = dtIde) then
  begin
    if OpenViaDelphiIde(AAbsPath, err) then
    begin
      // Dieser Weg pumpt Nachrichten - das Fenster kann inzwischen weg sein.
      if csDestroying in ComponentState then Exit('');
      // Ohne Zeilenangabe - die IDE springt nicht, das soll die
      // Statuszeile auch nicht behaupten.
      Result := Format(_('Opened in Delphi IDE: %s'), [ARelPath]);
      Exit;
    end;
    if csDestroying in ComponentState then Exit('');
    // Fuer .pas gibt es keinen dritten Weg - ehrlich melden statt
    // Erfolg zu behaupten, wie es die Vorgaengerfassung tat.
    if not isDfm then
    begin
      Result := Format(_('Could not open %s: %s'), [ARelPath, err]);
      Exit;
    end;
  end;

  // ---- 3. eingebauter Betrachter (nur .dfm) ----
  ShowDfmAsText(AAbsPath, ALine);
  Result := Format(_('DFM viewer: %s  Line: %d'), [ARelPath, ALine]);
end;

procedure TForm2.ResultGridDblClick(Sender: TObject);
// Nur noch der Maus-Einstieg: Kopfzeile aussortieren, dann den
// gemeinsamen Oeffnen-Kern rufen (OpenSelectedFinding - auch Enter
// landet dort).
begin
  // Doppelklick auf die KOPFZEILE ist die naheliegende Geste, um die
  // Sortierung schnell zweimal zu kippen - er darf nicht nebenbei den
  // gerade selektierten Befund oeffnen. Die VCL ruft bei
  // WM_LBUTTONDBLCLK erst DblClick und DANACH inherited MouseDown
  // (TCustomGrid.MouseDown, Vcl.Grids.pas) - der zweite Sortier-Kipp
  // laeuft also ohnehin ueber ResultGridMouseDown; hier ist nur
  // auszusteigen. ResultGrid.Row taugt dafuer nicht (steht noch auf der
  // Datenzeile), die Mausposition entscheidet.
  var P := ResultGrid.ScreenToClient(Mouse.CursorPos);
  var ACol, ARow: Integer;
  ResultGrid.MouseToCell(P.X, P.Y, ACol, ARow);
  if ARow = 0 then Exit;

  OpenSelectedFinding;
end;

procedure TForm2.ResultGridKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
// Enter = Befund oeffnen. TCustomGrid behandelt VK_RETURN selbst nicht -
// ohne diesen Handler war die Tastatur-Triage am Grid zu Ende und jeder
// Fund brauchte die Maus. Bewusst OHNE den Mauspositions-Header-Guard
// des Doppelklicks: bei Tastatur-Ausloesung ist die Mausposition
// bedeutungslos (sie koennte zufaellig ueber der Kopfzeile stehen).
begin
  // Ein auf der Kopfzeile begonnener, aber AUSSERHALB losgelassener
  // Mausdruck hinterlaesst FHeaderMousePress=True (kein OnClick, das ihn
  // verbraucht). Tastatur-Navigation raeumt den Merker hier ab, sonst
  // wuerde ihr naechstes OnClick verschluckt (Review 2026-08-12).
  FHeaderMousePress := False;
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;                       // kein Grid-Beep/Standardverhalten
    OpenSelectedFinding;
  end
  else if (Key = Ord('S')) and (Shift = [ssCtrl, ssAlt]) then
  begin
    Key := 0;
    SuppressSelectedFinding;
  end
  else if (Key = Ord('F')) and (Shift = [ssCtrl, ssAlt]) then
  begin
    Key := 0;
    QuickFixSelectedFinding;
  end;
end;

function TForm2.TryResolveSelectedFinding(var AFinding: TLeakFinding;
  var AAbsPath, ARelPath: string; var ALineNo: Integer): Boolean;
var
  row     : Integer;
  baseDir : string;
begin
  Result   := False;
  AFinding := nil;
  AAbsPath := '';
  ARelPath := '';
  ALineNo  := 0;
  row := ResultGrid.Row;
  if row < 1 then Exit;
  if (FDisplayedFindings = nil) or (row > FDisplayedFindings.Count) then Exit;
  AFinding := FDisplayedFindings[row - 1];
  baseDir  := IncludeTrailingPathDelimiter(FCurrentBaseDir);
  ARelPath := ExtractRelativePath(baseDir, AFinding.FileName);
  if ARelPath = '' then Exit;
  ALineNo := StrToIntDef(AFinding.LineNumber, 0);
  // DirOfProjectPath, nicht Projectpath.Text: bei einem Projekt-Scan
  // steht im Feld eine .dproj/.groupproj-DATEI. Ohne die Umrechnung
  // entstand hier ein Pfad wie ...\Mein.dproj\sources\u.pas, und der
  // Doppelklick meldete fuer JEDEN Befund eines Projekt-Scans
  // "File not found".
  AAbsPath := IncludeTrailingPathDelimiter(DirOfProjectPath(Projectpath.Text))
              + ARelPath;
  if not FileExists(AAbsPath) then
  begin
    StatusBar1.Panels[2].Text := _('File not found: ') + AAbsPath;
    Exit;
  end;
  Result := True;
end;

procedure TForm2.OpenSelectedFinding;
var
  relPath : string;
  absPath : string;
  lineNo  : Integer;
  f       : TLeakFinding;
  msg     : string;
begin
  // Reentranz-Sperre. Der IDE-Weg haelt den Hauptthread 1200 ms an und
  // ruft danach ProcessMessages - weitere Doppelklicks in dieser Zeit
  // landen nicht im Papierkorb, sondern in der Nachrichtenschlange und
  // kommen dort heraus. Ohne Sperre stapeln sich mehrere Oeffnen-Vorgaenge
  // und die Tastenanschlaege der einen laufen in die andere.
  if gOpeningFinding then Exit;
  gOpeningFinding := True;
  try
    if not TryResolveSelectedFinding(f, absPath, relPath, lineNo) then Exit;
    msg := OpenFindingAt(absPath, relPath, lineNo);
    if (msg <> '') and not (csDestroying in ComponentState) then
      StatusBar1.Panels[2].Text := msg;
  finally
    gOpeningFinding := False;
  end;
end;

procedure TForm2.SuppressSelectedFinding;
// Ctrl+Alt+S, wie im Plugin: '// noinspection <RuleName>' UEBER die
// Fundzeile. Das Plugin schreibt in den IDE-Editor (Strg+Z nimmt
// zurueck); hier geht es in die DATEI - uSourceLineEdit schreibt nur,
// wenn die Byte-Treue-Probe besteht. Der Befund verschwindet wie im
// Plugin erst mit dem naechsten Analyse-Lauf.
var
  f       : TLeakFinding;
  absPath : string;
  relPath : string;
  lineNo  : Integer;
  Marker  : string;
  Err     : string;
begin
  if not TryResolveSelectedFinding(f, absPath, relPath, lineNo) then Exit;
  if lineNo <= 0 then
  begin
    StatusBar1.Panels[2].Text := _('Suppress: cannot locate source line');
    Exit;
  end;
  Marker := '// noinspection ' + KindName(f.Kind);
  if TSourceLineEdit.InsertLineAbove(absPath, lineNo, Marker, Err) then
    StatusBar1.Panels[2].Text := Format(_('Suppress inserted: %s'), [Marker])
  else
    StatusBar1.Panels[2].Text :=
      Format(_('Suppress: could not write file: %s'), [Err]);
end;

procedure TForm2.QuickFixSelectedFinding;
// Ctrl+Alt+F, wie im Plugin: Zeile lesen, TQuickFix.ProposeFix, Zeile
// ersetzen. Statusmeldungen wortgleich zum Plugin - nur der
// Schreibfehler nennt hier die Datei statt des IDE-Editors.
var
  f        : TLeakFinding;
  absPath  : string;
  relPath  : string;
  lineNo   : Integer;
  OrigLine : string;
  Err      : string;
  Fix      : TQuickFixResult;
begin
  if not TryResolveSelectedFinding(f, absPath, relPath, lineNo) then Exit;
  if not TQuickFix.HasProviderFor(f.Kind) then
  begin
    StatusBar1.Panels[2].Text := Format(
      _('Quick-Fix: no provider for ''%s'' - manual fix required'),
      [f.RuleID]);
    Exit;
  end;
  if lineNo <= 0 then
  begin
    StatusBar1.Panels[2].Text := _('Quick-Fix: cannot locate source line');
    Exit;
  end;
  if not TSourceLineEdit.ReadLine(absPath, lineNo, OrigLine, Err) then
  begin
    StatusBar1.Panels[2].Text := _('Quick-Fix: line out of range');
    Exit;
  end;
  Fix := TQuickFix.ProposeFix(f, OrigLine);
  if not Fix.Applied then
  begin
    StatusBar1.Panels[2].Text := Format(
      _('Quick-Fix: pattern not matched on line %d - manual fix required'),
      [lineNo]);
    Exit;
  end;
  if TSourceLineEdit.ReplaceLine(absPath, lineNo, Fix.Fixed, Err) then
    StatusBar1.Panels[2].Text :=
      Format(_('Quick-Fix applied: %s'), [Fix.Description])
  else
    StatusBar1.Panels[2].Text :=
      Format(_('Quick-Fix: could not write file: %s'), [Err]);
end;

procedure TForm2.ResultGridClick(Sender: TObject);
// Bei Klick auf eine Befund-Zeile: Hint-Panel SOFORT (sichtbares
// Feedback), Zwischenablage ENTPRELLT ueber FClipTimer.
//
// Warum kein direkter Clipboard-Write mehr (Vorbild Plugin 2026-08-03):
// die VCL feuert OnClick auch bei Tastatur-Navigation - jeder
// Pfeiltasten-Schritt war ein systemweiter Clipboard-Write (~30x/s bei
// gehaltener Taste), und eine gerade von einem anderen Prozess gesperrte
// Zwischenablage (RDP, Clipboard-Manager) warf EClipboardException
// mitten in die Triage. Mit dem Timer faellt auch das ProcessMessages
// weg, das nur den Panel-Repaint vor dem blockierenden Write flushte.
//
// Index bezieht sich auf FDisplayedFindings, NICHT FAllFindings - der
// Filter hat moeglicherweise Eintraege entfernt.
var
  idx : Integer;
begin
  // Programmatischer Umbau (ApplyFilter nach Sortieren/Filtern): die
  // Zeilen-Klemmung feuert OnClick fuer eine Zeile, die niemand
  // angeklickt hat - Panel und Zwischenablage blieben sonst an einem
  // Zufallsfund haengen. Das Panel zieht ApplyFilter selbst nach.
  if FGridUpdating then Exit;
  // Kopfzeilen-Klick (Sortier-Geste, in MouseDown markiert): verbrauchen
  // und aussteigen. OnClick laeuft erst nach WM_LBUTTONUP, wenn
  // FGridUpdating laengst wieder False ist - ResultGrid.Row steht dann
  // auf einer Datenzeile, die niemand angeklickt hat.
  if FHeaderMousePress then
  begin
    FHeaderMousePress := False;
    Exit;
  end;

  idx := ResultGrid.Row - 1; // 0-basiert: Zeile 0 ist Header
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;
  if Assigned(FHintPanel) then
    FHintPanel.ShowFinding(FDisplayedFindings[idx]);
  if Assigned(FClipTimer) then
  begin
    FClipTimer.Enabled := False;   // neu bewaffnen
    FClipTimer.Enabled := True;
  end;
end;

procedure TForm2.ClipCopyFire(Sender: TObject);
// Die Auswahl steht - jetzt die EINE Kopie, fuer die AKTUELLE Zeile
// (nicht die, die den Timer bewaffnet hat: waehrend der 120 ms kann die
// Auswahl weitergewandert sein; kopiert gehoert, wo der Nutzer steht).
var
  idx : Integer;
  F   : TLeakFinding;
begin
  if Assigned(FClipTimer) then
    FClipTimer.Enabled := False;
  if csDestroying in ComponentState then Exit;
  // [UI] ClipboardOnClick=1 (Default): die Zwischenablage gehoert dem
  // Nutzer - nichts bauen, nichts schreiben. Die explizite Geste
  // (Kontextmenue "Copy AI prompt") laeuft NICHT ueber diesen Pfad.
  if FClipCopyMode = fcmNone then Exit;
  if FDisplayedFindings = nil then Exit;
  idx := ResultGrid.Row - 1;
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;
  F := FDisplayedFindings[idx];
  try
    Clipboard.AsText := TFindingCopyText.Build(F, FClipCopyMode);
  except
    // Zwischenablage gerade von einem anderen Prozess gesperrt (RDP,
    // Clipboard-Manager): still auslassen - der naechste Auswahlwechsel
    // versucht es erneut. Ein Dialog waere mitten in der Triage
    // schlimmer als eine verpasste Kopie.
    Exit;
  end;
  if FClipCopyMode = fcmJiraMini then
    StatusBar1.Panels[2].Text := Format(
      _('Jira mini issue copied to clipboard: %s, line %s (%s)'),
      [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText])
  else
    StatusBar1.Panels[2].Text := Format(
      _('AI prompt copied to clipboard: %s, line %s (%s)'),
      [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]);
end;

procedure TForm2.UpdateHintPanelToSelection;
// Nach ApplyFilter zeigt das Panel sonst einen inzwischen ausgefilterten
// Fund. Bewusst OHNE Zwischenablage - die gehoert dem bewussten Klick.
var
  idx : Integer;
begin
  if not Assigned(FHintPanel) then Exit;
  if (FDisplayedFindings = nil) or (FDisplayedFindings.Count = 0) then
  begin
    FHintPanel.ShowPlaceholder;
    Exit;
  end;
  idx := ResultGrid.Row - 1;
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then idx := 0;
  FHintPanel.ShowFinding(FDisplayedFindings[idx]);
end;

function TForm2.BuildClaudePrompt(F: TLeakFinding): string;
// Thin-Wrapper. Logik ist in uClaudePrompt zentralisiert (war zuvor 1:1
// dupliziert mit dem IDE-Plugin).
begin
  Result := TClaudePrompt.Build(F);
end;

// Recent Paths -- duenne Wrapper um TRecentPaths (Common/uRecentPaths.pas).
// Pinned-Eintrag = App-Pfad neben der EXE, Position end.
function TForm2.AppPath: string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName));
end;

function TForm2.RecentIniPath: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TForm2.LoadRecentPaths;
begin
  // Wenn die INI defekt ist (Disk-Voll, ACL, manuelles Editieren) darf
  // der FormCreate nicht crashen - dann startet die App ohne MRU.
  try
    TRecentPaths.Load(
      Projectpath, RecentIniPath,
      DEFAULT_MAX_RECENT,
      AppPath, ppLast);
  except
    Projectpath.Items.Clear;
    Projectpath.Text := '';
  end;
end;

procedure TForm2.SaveRecentPath(const APath: string);
begin
  // Die MRU-INI liegt NEBEN DER EXE. In einem nicht schreibbaren Ordner
  // (Program Files, Netz-Share) warf der Write hier eine Exception -
  // und zwar VOR dem Analyse-Aufruf: jeder Klick auf 'Analyse directory'
  // endete im Fehlerdialog, der Scan startete NIE. Dieselbe Philosophie
  // wie LoadRecentPaths (dort seit jeher mit Guard dokumentiert): eine
  // defekte Komfortliste darf die Kernfunktion nicht anhalten - dann
  // merkt sich die App den Pfad eben diese Sitzung nicht.
  try
    TRecentPaths.Save(
      Projectpath, RecentIniPath, APath,
      DEFAULT_MAX_RECENT,
      AppPath, ppLast);
  except
  end;
end;

procedure TForm2.ProfileComboChange(Sender: TObject);
// Aktuelle Combo-Auswahl direkt in analyser.ini [Rules] Profile persistieren.
// Wirkt erst beim naechsten Analyse-Klick (ApplyDetectorConfig liest sie),
// aber bleibt ueber Form-Restarts erhalten. Save-Fehler still schlucken -
// Read-Only-INI oder Berechtigungsproblem soll den Lauf nicht crashen.
var
  Settings: TRepoSettings;
begin
  if (ProfileCombo = nil) or (ProfileCombo.ItemIndex < 0) then Exit;
  Settings := TRepoSettings.Create;
  try
    if not LoadBeforeWrite(Settings) then
    begin
      StatusBar1.Panels[2].Text := _('Settings could not be reloaded - nothing was saved.');
      Exit;
    end;
    Settings.Profile := ProfileCombo.Items[ProfileCombo.ItemIndex];
    // Save-Fehler bleiben still: eine schreibgeschuetzte INI soll den Lauf
    // nicht abbrechen, und die Auswahl wirkt fuer diese Sitzung ohnehin.
    try Settings.Save; except end;
  finally
    Settings.Free;
  end;
  StatusBar1.Panels[2].Text :=
    Format(_('Profile "%s" - active on next analysis run'),
      [ProfileCombo.Items[ProfileCombo.ItemIndex]]);
end;

procedure TForm2.MinSevComboChange(Sender: TObject);
// Analog zu ProfileComboChange. Schreibt in [Rules] MinSeverity.
var
  Settings: TRepoSettings;
begin
  if (MinSevCombo = nil) or (MinSevCombo.ItemIndex < 0) then Exit;
  Settings := TRepoSettings.Create;
  try
    if not LoadBeforeWrite(Settings) then
    begin
      StatusBar1.Panels[2].Text := _('Settings could not be reloaded - nothing was saved.');
      Exit;
    end;
    Settings.MinSeverity := MinSevCombo.Items[MinSevCombo.ItemIndex];
    try Settings.Save; except end;   // s. ProfileComboChange
  finally
    Settings.Free;
  end;
  StatusBar1.Panels[2].Text :=
    Format(_('MinSeverity "%s" - active on next analysis run'),
      [MinSevCombo.Items[MinSevCombo.ItemIndex]]);
end;

procedure TForm2.SeverityFilterComboChange(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TForm2.TypeFilterComboChange(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TForm2.SearchEditChange(Sender: TObject);
// Entprellt statt sofort. Beim Tippen von 'memory' lief ApplyFilter
// vorher sechsmal ueber die komplette Fundliste und baute sechsmal das
// Grid neu; jetzt einmal nach dem Tippstopp. Uebernommen aus dem
// IDE-Plugin, das dieselbe Entprellung seit laengerem hat - gleiche
// Wartezeit, damit sich beide Oberflaechen gleich anfuehlen.
//
// Die anderen Filter (Severity-/Type-Combo) feuern weiterhin sofort: dort
// ist eine Auswahl ein einzelnes Ereignis, kein Zeichenstrom.
begin
  if FSearchDebounce = nil then
  begin
    ApplyFilter;   // Fallback, falls FormCreate noch nicht durch ist
    Exit;
  end;
  FSearchDebounce.Enabled := False;
  FSearchDebounce.Enabled := True;
end;

procedure TForm2.SearchDebounceFire(Sender: TObject);
begin
  if FSearchDebounce <> nil then FSearchDebounce.Enabled := False;
  if csDestroying in ComponentState then Exit;
  ApplyFilter;
end;

procedure TForm2.BtnBranchClick(Sender: TObject);
// Branch-Changes: nur die im aktuellen Git/SVN-Branch geaenderten .pas-Files
// analysieren. Pendant zum Branch-Button im IDE-Plugin.
var
  Settings : TRepoSettings;
  Files    : TStringList;
  Findings : TObjectList<TLeakFinding>;
  Info     : string;
  StartDir : string;
begin
  // Verzeichnis-Konsument (Review-Auflage par.4.3): bei Projektdatei-Text
  // im Combo deren Verzeichnis als Repo-Detection-Startpunkt verwenden.
  StartDir := DirOfProjectPath(Projectpath.Text);
  if StartDir = '' then
  begin
    StatusBar1.Panels[2].Text := _('Project path is empty.');
    Exit;
  end;

  Settings := TRepoSettings.Create;
  Files    := nil;
  Findings := nil;
  try
    try Settings.Load; except end;
    ApplyDetectorConfig(Settings, True);

    Files := TVcsChanges.GetChangedPasFilesAuto(StartDir, Info, Settings);
    if (Files = nil) or (Files.Count = 0) then
    begin
      StatusBar1.Panels[2].Text := Info + _(' - no changed .pas files');
      Exit;
    end;

    StatusBar1.Panels[2].Text := Format(_('Analysing %d changed file(s). %s'),
      [Files.Count, Info]);
    // Total ist hier vorab bekannt -> direkt File-Phase (kein Marquee).
    BeginAnalysisUI(Files.Count);
    Application.ProcessMessages;

    try
      try
        // Phase 4: VCS-Changed-Liste ueber die Facade.
        var Req := TScanRequest.Init;
        Req.SkipConfig := True;
        Req.Scope      := ssFileList;
        Req.Files      := Files.ToStringArray;
        Req.UsesCheck  := Settings.UsesCheck;
        Req.Progress   := procedure(C, T: Integer) begin ProgressCallback(C, T); end;
        var Ses := TAnalysisSession.Create;
        var Res: TScanResult := nil;
        try
          Res := Ses.Run(Req);
          Findings := Res.ReleaseFindings;
        finally
          Res.Free;
          Ses.Free;
        end;
        FillGridFromFindings(Findings, StartDir);
      except
        on EAbort do ;
        on E: Exception do
          StatusBar1.Panels[2].Text := _('Analysis error: ') + E.Message;
      end;
    finally
      EndAnalysisUI;
    end;
  finally
    Findings.Free;
    Files.Free;
    Settings.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Hamburger-Menu - konsolidiert Branch / Cancel / Export / Settings / Ignore
// in EIN Popup. Spiegelt das IDE-Plugin-Pattern (uIDEAnalyserForm) 1:1 -
// gleiche Items, gleiche Reihenfolge, gleiche Enabled-Sync-Logik.
// ---------------------------------------------------------------------------

procedure TForm2.ApplyUiCaptions;
begin
  // Filterzeile + Pfadzeile: die DFM-Captions wurden nie durch _()
  // ersetzt - ein deutscher Nutzer sah dauerhaft eine gemischt-
  // sprachige Toolbar (Button6 daneben war laengst uebersetzt).
  // Fenstertitel: der DFM-Wert bliebe sonst fix englisch. de laesst den
  // Produktnamen bewusst unuebersetzt (Passthrough), fr uebersetzt ihn.
  Caption := _('Static Code Analysis Tool for Delphi');
  LblFilter.Caption  := _('Severity:');
  LblType.Caption    := _('Type:');
  LblMinSev.Caption  := _('Min:');
  LblProfile.Caption := _('Profile:');
  // Caption-Paritaet 2026-08-14: Wortlaute wie im IDE-Plugin
  // (uIDEAnalyserForm CreateUI): 'Path:' statt 'Project path:',
  // Datei-Button mit Glyph, Suchfeld mit demselben Placeholder.
  // Das fruehere 'Search:'-Label ist wie im Plugin entfernt (User-Edit
  // im Designer) - der Placeholder uebernimmt die Beschriftung.
  Label1.Caption     := _('Path:');
  Button7.Caption    := _('📄 File');
  SearchEdit.TextHint := _('Filter file / method / finding...');
  // Button6-Caption setzt ProjectpathChangedScope (Smart-Path) selbst.

  ResultGrid.Cells[0, 0] := _('File');
  ResultGrid.Cells[1, 0] := _('Method');
  ResultGrid.Cells[2, 0] := _('Line');
  ResultGrid.Cells[3, 0] := _('Detail');
  ResultGrid.Cells[4, 0] := _('Severity');
end;

procedure TForm2.BuildHamburgerMenu;
var
  MI : TMenuItem;
begin
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := HamburgerMenuPopup;

  // (Branch-Changes ist NICHT mehr im Menue - BtnBranch ist eigenstaendiger
  // Top-Level-Button.)

  // ---- Cancel (Enabled wird in HamburgerMenuPopup gesynct) ----
  FMICancel := TMenuItem.Create(FHamburgerMenu);
  FMICancel.Caption := _('Cancel Analysis');
  FMICancel.OnClick := BtnCancelClick;          // existierender Handler
  FHamburgerMenu.Items.Add(FMICancel);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Export ----
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Export') + '...';
  MI.OnClick := HamburgerExportClick;
  FHamburgerMenu.Items.Add(MI);

  // ---- Konfig-Block: Settings + Ignore ----
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Settings...');
  MI.OnClick := HamburgerSettingsClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Ignore list...');
  MI.OnClick := HamburgerIgnoreListClick;
  FHamburgerMenu.Items.Add(MI);

  // ---- Erscheinungsbild (Hell / Dunkel / Wie Windows) ----
  FMIAppearance := TMenuItem.Create(FHamburgerMenu);
  FMIAppearance.Caption := _('Appearance');
  FHamburgerMenu.Items.Add(FMIAppearance);
  BuildAppearanceMenu(FMIAppearance);

  // ---- Baseline (Plugin-Paritaet) ----
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Write baseline from current scan...');
  MI.OnClick := WriteBaselineClick;
  FHamburgerMenu.Items.Add(MI);

  FMIBaseline := TMenuItem.Create(FHamburgerMenu);
  FMIBaseline.Caption := _('Show only new findings (baseline)');
  FMIBaseline.OnClick := BaselineOnlyNewClick;
  FHamburgerMenu.Items.Add(FMIBaseline);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Oeffnen mit (Untermenue) ----
  FMIOpenWith := TMenuItem.Create(FHamburgerMenu);
  FMIOpenWith.Caption := _('Open findings with');
  FHamburgerMenu.Items.Add(FMIOpenWith);
  BuildOpenWithMenu(FMIOpenWith);

  // ---- Sprache (Untermenue, Werte aus AvailableLanguages) ----
  FMILanguage := TMenuItem.Create(FHamburgerMenu);
  FMILanguage.Caption := _('Language');
  FHamburgerMenu.Items.Add(FMILanguage);
  BuildLanguageMenu(FMILanguage);
end;

procedure TForm2.ResultGridMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow: Integer;
begin
  // Rechtsklick: Selektion auf die ANGEKLICKTE Datenzeile nachziehen,
  // BEVOR WM_CONTEXTMENU das Popup oeffnet - TCustomGrid bewegt die
  // Current-Cell nur bei mbLeft, und "Copy AI prompt" liest die
  // Selektion (Review 2026-08-12, Logik-Dimension; Pendant im Plugin).
  // ResultGridClick zieht danach Hint-Panel und Kopier-Weiche nach -
  // dieselbe Wirkung wie ein Linksklick auf die Zeile.
  if Button = mbRight then
  begin
    ResultGrid.MouseToCell(X, Y, ACol, ARow);
    if (ARow >= 1) and Assigned(FDisplayedFindings)
       and (ARow <= FDisplayedFindings.Count) then
    begin
      ResultGrid.Row := ARow;
      FHeaderMousePress := False;   // etwaigen abgebrochenen Header-Druck verwerfen
      ResultGridClick(ResultGrid);
    end;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  ResultGrid.MouseToCell(X, Y, ACol, ARow);
  // Merker fuer das nachfolgende OnClick (Review 2026-08-12): ein Druck
  // auf der Kopfzeile darf dort weder Hint-Panel noch Kopier-Timer
  // anfassen - sonst landete 120 ms nach jedem Sortier-Klick der Prompt
  // eines nie angeklickten Befunds in der Zwischenablage.
  FHeaderMousePress := (ARow = 0);
  if ARow <> 0 then Exit;                       // nur die Header-Zeile
  if (ACol < 0) or (ACol > 4) then Exit;

  if FSortColumn = ACol then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn     := ACol;
    FSortDescending := False;
  end;
  // Indikator im Renderer nachziehen - er malt '^'/'v' aus der Config.
  FGridConfig.SortColumn     := FSortColumn;
  FGridConfig.SortDescending := FSortDescending;
  ApplyFilter;
end;

procedure TForm2.BuildAppearanceMenu(AParent: TMenuItem);
// Drei Radio-Eintraege. 'Wie Windows' ist der Auslieferwert; die Wahl
// liegt in analyser.ini ([UI] Theme) und ueberlebt den Neustart.
// Tag traegt den Modus, damit der Handler nicht von der uebersetzten
// Beschriftung abhaengt - dieselbe Bauart wie beim Sprach-Menue.
const
  CAPTIONS : array[TAppThemeMode] of string = (
    'Like Windows', 'Light', 'Dark');
var
  M  : TAppThemeMode;
  MI : TMenuItem;
begin
  if not Assigned(AParent) then Exit;
  AParent.Clear;
  for M := Low(TAppThemeMode) to High(TAppThemeMode) do
  begin
    MI := TMenuItem.Create(AParent);
    MI.Caption    := _(CAPTIONS[M]);
    MI.RadioItem  := True;
    MI.GroupIndex := 71;            // eigener Kreis, stoert die Sprache nicht
    MI.Tag        := Ord(M);
    MI.Checked    := (M = TAppTheme.Mode);
    MI.OnClick    := AppearanceItemClick;
    AParent.Add(MI);
  end;
end;

procedure TForm2.AppearanceItemClick(Sender: TObject);
var
  MI : TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  MI := TMenuItem(Sender);
  TAppTheme.SetMode(TAppThemeMode(MI.Tag));
  // Haken nachziehen: RadioItem setzt ihn zwar selbst, aber nur wenn der
  // Klick durchkam - SetMode kann bei gleicher Wahl frueh aussteigen.
  BuildAppearanceMenu(FMIAppearance);
end;

// Hint, Tag und OnClick landen auf dem Kachel-Container UND rekursiv
// auf allen Kindern - sonst triggert ein Klick auf Glyph oder
// Beschriftung nichts (Plugin-Erkenntnis, uIDEAnalyserForm.WireTile).
// Kein Control-Cracker noetig: die Kacheln bestehen aus TPanel- und
// TLabel-Ebenen, und BEIDE publizieren OnClick - das Plugin braucht
// seinen Cracker nur, weil es generisch ueber TControl zuweist.
procedure TileApplyRecursive(C: TControl; const AHint: string;
  ATag: Integer; AHandler: TNotifyEvent);
var
  i : Integer;
begin
  C.Hint     := AHint;
  C.ShowHint := True;
  C.Tag      := ATag;
  C.Cursor   := crHandPoint;   // signalisiert Klickbarkeit
  if C is TPanel then
    TPanel(C).OnClick := AHandler
  else if C is TLabel then
    TLabel(C).OnClick := AHandler;
  if C is TWinControl then
    for i := 0 to TWinControl(C).ControlCount - 1 do
      TileApplyRecursive(TWinControl(C).Controls[i], AHint, ATag, AHandler);
end;

procedure TileWire(CountLbl: TLabel; const AHint: string; ATag: Integer;
  AHandler: TNotifyEvent);
begin
  if not Assigned(CountLbl) or not Assigned(CountLbl.Parent)
     or not Assigned(CountLbl.Parent.Parent) then Exit;
  TileApplyRecursive(CountLbl.Parent.Parent, AHint, ATag, AHandler);
end;

procedure TForm2.StatusFindings(const T: string);
begin
  StatusBar1.Panels[0].Text := T;
end;

procedure TForm2.StatusProgress(const T: string);
begin
  StatusBar1.Panels[1].Text := T;
end;

function TForm2.BaselineActive: Boolean;
// FAIL-OPEN, wie im Plugin: fehlt oder bricht die Baseline-Datei, wird
// NICHTS ausgeblendet. Funde zu verstecken, weil eine Datei fehlt, waere
// die gefaehrlichere Richtung.
begin
  Result := Assigned(FBaselineSet) and (not FBaselineSet.IsEmpty);
end;

function TForm2.CurrentProjOrGroupFile: string;
// Smart-Path: steht in der Pfad-Combo eine .dproj/.groupproj-DATEI, ist
// das die Projekt-/Gruppen-Quelle fuer die .sca-Aufloesung.
begin
  Result := Trim(Projectpath.Text);
  if not (SameText(ExtractFileExt(Result), '.dproj') or
          SameText(ExtractFileExt(Result), '.groupproj')) then
    Result := '';
end;

// Absolute Pfade (Laufwerk, UNC, fuehrender Separator) erkennen -
// Pruefung von Hand, wie im Plugin, damit hier kein TPath-Namensraum
// noetig wird.
function IsAbsolutePathStr(const Path: string): Boolean;
begin
  Result := ((Length(Path) >= 2) and (Path[2] = ':')) or
            ((Length(Path) >= 2) and (Path[1] = '\') and (Path[2] = '\')) or
            ((Length(Path) >= 1) and ((Path[1] = '\') or (Path[1] = '/')));
end;

function TForm2.ResolveUiBaselinePath(ASettings: TRepoSettings;
  AProbed: TStrings): string;
// Praezedenz wie CLI (Konzept par.1): [Baseline] File= (mit Relativ-
// Aufloesung gegen das Scan-Verzeichnis) > .sca-Standardort neben der
// Projektdatei bzw. unter dem Scan-Pfad. '' wenn nichts existiert.
var
  Path : string;
begin
  Result := '';
  Path := Trim(ASettings.BaselineFile);
  if Path <> '' then
  begin
    if (not IsAbsolutePathStr(Path)) and (FCurrentBaseDir <> '') then
      Path := IncludeTrailingPathDelimiter(FCurrentBaseDir) + Path;
    if Assigned(AProbed) then AProbed.Add(Path);
    if FileExists(Path) then Exit(Path);
    Exit;                    // explizit konfiguriert, aber fehlt -> kein .sca-Raten
  end;
  Result := TBaseline.ResolveBaselinePath(CurrentProjOrGroupFile,
    DirOfProjectPath(Projectpath.Text), AProbed);
end;

procedure TForm2.RefreshBaselineSet;
// Laedt (oder leert) das Fingerprint-Set. Quelle: [Baseline] File= oder
// der .sca-Standardort (Inkrement 3). Wird vor jedem Anzeige-Aufbau
// gerufen; FAllFindings bleibt unberuehrt.
var
  Settings : TRepoSettings;
  Path     : string;
begin
  if not Assigned(FBaselineSet) then Exit;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    if not Settings.BaselineOnlyNew then
    begin
      FBaselineSet.Clear;
      Exit;
    end;
    Path := ResolveUiBaselinePath(Settings, nil);
    if Path = '' then
    begin
      FBaselineSet.Clear;
      Exit;
    end;
    // PathInFingerprint-Konsistenz: Modus + Root wie beim Schreiben der
    // Datei, sonst matchen die Fingerprints des Anzeige-Filters nicht.
    uSCAConsts.BaselinePathFingerprint := Settings.BaselinePathInFingerprint;
    if CurrentProjOrGroupFile <> '' then
      uSCAConsts.BaselineFingerprintRoot := ExtractFilePath(CurrentProjOrGroupFile)
    else
      uSCAConsts.BaselineFingerprintRoot := DirOfProjectPath(Projectpath.Text);
    try
      FBaselineSet.LoadFromFile(Path);
    except
      // Lesefehler darf die Anzeige nicht kippen - leeres Set = Filter aus.
      FBaselineSet.Clear;
    end;
  finally
    Settings.Free;
  end;
end;

function TForm2.OfferWriteBaseline(const AProbedText: string): Boolean;
// Dialog 'keine Baseline gefunden - jetzt schreiben?' inkl. Schreiben an
// den .sca-Standardort. False = Nutzer hat abgebrochen oder es gibt
// nichts zu schreiben (Aufrufer nimmt den Haken zurueck).
var
  Target : string;
begin
  Result := False;
  if Application.MessageBox(PChar(Format(
       _('Baseline is enabled but no baseline file was found.') + #13#10 +
       _('Looked for:') + #13#10 + '%s' + #13#10 +
       _('Write a new baseline with the current findings now?'),
       [AProbedText])),
     PChar(_('Write baseline')), MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  if (FAllFindings = nil) or (FAllFindings.Count = 0) then
  begin
    ShowMessage(_('No findings to write. Run an analysis first.'));
    Exit;
  end;
  Target := TBaseline.DefaultBaselineTarget(CurrentProjOrGroupFile,
    DirOfProjectPath(Projectpath.Text));
  if Target = '' then
  begin
    ShowMessage(_('No scan target selected - pick a path or project first.'));
    Exit;
  end;
  try
    ForceDirectories(ExtractFilePath(Target));
    // GESCHRIEBENE Anzahl melden, nicht FAllFindings.Count: Lesefehler
    // sind nicht baseline-faehig und werden von Write uebersprungen.
    var Written := TBaseline.Write(FAllFindings, Target);
    StatusBar1.Panels[2].Text := Format(
      _('Baseline written: %s (%d findings)'),
      [ExtractFileName(Target), Written]);
    Result := True;
  except
    // noinspection ExceptionTooGeneral
    // Fehlergrenze an der Action-Grenze (s. Dateikopf): jeder
    // Schreibfehler soll als Klartext beim Nutzer ankommen.
    on E: Exception do
      ShowMessage(Format(_('Could not write baseline: %s'), [E.Message]));
  end;
end;

procedure TForm2.ToggleBaselineOnlyNew(ANewVal: Boolean);
// Kern des Hamburger-Hakens 'Show only new findings (baseline)'.
// AKTIVIEREN ohne auffindbare Datei bietet an, sofort eine zu schreiben
// (.sca-Standardort) - kein harter Abbruch wie in der CLI, aber auch
// kein stilles Weiterlaufen (Konzept par.3/par.4).
var
  Settings : TRepoSettings;
  Probed   : TStringList;
begin
  Settings := TRepoSettings.Create;
  try
    if not LoadBeforeWrite(Settings) then
    begin
      StatusBar1.Panels[2].Text := _('Settings could not be reloaded - nothing was saved.');
      Exit;
    end;
    if ANewVal then
    begin
      Probed := TStringList.Create;
      try
        if (ResolveUiBaselinePath(Settings, Probed) = '') and
           (not OfferWriteBaseline(Probed.Text)) then
          Exit;             // Setting bleibt aus; Popup-Sync liest die INI
      finally
        Probed.Free;
      end;
    end;
    Settings.BaselineOnlyNew := ANewVal;
    try Settings.Save; except end;
  finally
    Settings.Free;
  end;
  RefreshBaselineSet;
  // Der Toggle aendert die sichtbare Menge im Ganzen - die Combos muessen
  // ihr folgen (Konsistenz-Vertrag mit dem Grid), inklusive Reset auf
  // 'All' wie nach einem Scan.
  RebuildFilterCombos;
  ApplyFilter;
end;

procedure TForm2.WriteBaselineClick(Sender: TObject);
// Schreibt die UNGEFILTERTEN Funde als Baseline-JSON. Format identisch zu
// CLI --write-baseline, Plugin und HTML-Export - die Datei ist zwischen
// allen dreien austauschbar.
var
  Dlg : TSaveDialog;
begin
  if (FAllFindings = nil) or (FAllFindings.Count = 0) then
  begin
    ShowMessage(_('No findings to write. Run an analysis first.'));
    Exit;
  end;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title      := _('Write baseline');
    Dlg.Filter     := _('Baseline JSON (*.json)|*.json');
    Dlg.DefaultExt := 'json';
    // .sca-Standardziel vorbelegen (Konzept par.3); Fallback wie bisher.
    var DefTarget := TBaseline.DefaultBaselineTarget(CurrentProjOrGroupFile,
      DirOfProjectPath(Projectpath.Text));
    if DefTarget <> '' then
    begin
      try ForceDirectories(ExtractFilePath(DefTarget)); except end;
      Dlg.InitialDir := ExcludeTrailingPathDelimiter(ExtractFilePath(DefTarget));
      Dlg.FileName   := ExtractFileName(DefTarget);
    end
    else
    begin
      Dlg.FileName := 'sca.baseline.json';
      if (FCurrentBaseDir <> '') and DirectoryExists(FCurrentBaseDir) then
        Dlg.InitialDir := FCurrentBaseDir;
    end;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    try
      var Written := TBaseline.Write(FAllFindings, Dlg.FileName);
      StatusBar1.Panels[2].Text := Format(
        _('Baseline written: %s (%d findings)'),
        [ExtractFileName(Dlg.FileName), Written]);
    except
      // noinspection ExceptionTooGeneral
      // Fehlergrenze an der Action-Grenze (s. Dateikopf): jeder
      // Schreibfehler (Schreibschutz, Platte voll, ACL) soll als
      // Klartext beim Nutzer ankommen statt die App zu sprengen.
      on E: Exception do
        ShowMessage(Format(_('Could not write baseline: %s'), [E.Message]));
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TForm2.BaselineOnlyNewClick(Sender: TObject);
// Haken umschalten - dieselbe Einstellung, die Plugin und CLI lesen
// ([Baseline] OnlyNew). Kern inkl. .sca-Aufloesung + Schreib-Angebot in
// ToggleBaselineOnlyNew (Inkrement 3; vorher blockte der Toggle mit
// einer Meldung, wenn [Baseline] File= nicht von Hand gesetzt war).
var
  Settings : TRepoSettings;
  NewVal   : Boolean;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    NewVal := not Settings.BaselineOnlyNew;
  finally
    Settings.Free;
  end;
  ToggleBaselineOnlyNew(NewVal);
end;

procedure TForm2.BuildGridMenu;
// Rechtsklick am Grid - die entdeckbare Form der Aktionen. Das Plugin
// hat seit 2026-08-12 ein eigenes Grid-Menue, dort bewusst nur mit
// "Copy AI prompt" (Oeffnen/Unterdruecken laufen im Dock ueber
// Doppelklick bzw. Shortcuts).
var
  MI : TMenuItem;
begin
  FGridMenu := TPopupMenu.Create(Self);
  FGridMenu.OnPopup := GridMenuPopup;

  MI := TMenuItem.Create(FGridMenu);
  MI.Caption := _('Open finding') + #9'Enter';
  MI.OnClick := GridMenuOpenClick;
  MI.Default := True;
  FGridMenu.Items.Add(MI);

  MI := TMenuItem.Create(FGridMenu);
  MI.Caption := _('Copy AI prompt');
  MI.OnClick := GridMenuCopyClick;
  FGridMenu.Items.Add(MI);

  MI := TMenuItem.Create(FGridMenu);
  MI.Caption := '-';
  FGridMenu.Items.Add(MI);

  // Quick-Fix steht bewusst NICHT im Menue (User-Entscheid 2026-08-08) -
  // die Aktion bleibt als Ctrl+Alt+F erreichbar (Plugin-Paritaet).
  MI := TMenuItem.Create(FGridMenu);
  MI.Caption := _('Insert suppression marker') + #9'Ctrl+Alt+S';
  MI.OnClick := GridMenuSuppressClick;
  FGridMenu.Items.Add(MI);

  ResultGrid.PopupMenu := FGridMenu;
end;

procedure TForm2.GridMenuPopup(Sender: TObject);
// Nur sinnvoll, wenn eine Datenzeile steht.
var
  HasRow : Boolean;
  i      : Integer;
begin
  HasRow := Assigned(FDisplayedFindings) and (FDisplayedFindings.Count > 0)
            and (ResultGrid.Row >= 1)
            and (ResultGrid.Row <= FDisplayedFindings.Count);
  for i := 0 to FGridMenu.Items.Count - 1 do
    FGridMenu.Items[i].Enabled := HasRow;
end;

procedure TForm2.GridMenuOpenClick(Sender: TObject);
begin
  OpenSelectedFinding;
end;

procedure TForm2.GridMenuCopyClick(Sender: TObject);
// Bewusst SOFORT statt ueber den Entprell-Timer: hier ist das Kopieren
// die ausdrueckliche Absicht des Nutzers, nicht ein Nebeneffekt der
// Navigation. Aus demselben Grund greift [UI] ClipboardOnClick hier
// NICHT: die Option regelt nur die automatische Kopie beim Zeilen-Klick;
// wer "Copy AI prompt" waehlt, bekommt den AI-Prompt - in jedem Modus.
var
  idx : Integer;
  F   : TLeakFinding;
begin
  if FDisplayedFindings = nil then Exit;
  idx := ResultGrid.Row - 1;
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;
  F := FDisplayedFindings[idx];
  try
    Clipboard.AsText := BuildClaudePrompt(F);
  except
    StatusBar1.Panels[2].Text := _('Clipboard is locked by another program.');
    Exit;
  end;
  StatusBar1.Panels[2].Text := Format(
    _('AI prompt copied to clipboard: %s, line %s (%s)'),
    [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]);
end;

procedure TForm2.GridMenuSuppressClick(Sender: TObject);
begin
  SuppressSelectedFinding;
end;

procedure TForm2.WireTiles;
begin
  // Severity-Kacheln -> Severity-Combo (Hint-Texte wortgleich zum
  // Plugin, die msgids existieren dort bereits).
  TileWire(FTileError, _('Errors') + sLineBreak +
    _('Real bugs / security holes (severity Error). Fix immediately.')
    + sLineBreak + _('Click: filter grid to Errors'),
    Ord(fmErrors), TileClickSeverity);
  TileWire(FTileWarn, _('Warnings') + sLineBreak +
    _('Likely bugs / risky patterns. Review before merge.')
    + sLineBreak + _('Click: filter grid to Warnings'),
    Ord(fmWarnings), TileClickSeverity);
  TileWire(FTileHint, _('Hints') + sLineBreak +
    _('Code smells / style. Refactoring candidates.')
    + sLineBreak + _('Click: filter grid to Hints'),
    Ord(fmHints), TileClickSeverity);
  // Diese beiden gibt es in der EXE-Severity-Combo NICHT als fm-Modus
  // (anders als im Plugin) - sie springen auf den generierten
  // REGEL-Eintrag (KIND_TAG_BASE + Ord(Kind)).
  TileWire(FTileFileSev, _('Read errors') + sLineBreak +
    _('File could not be read / parsed. Check path/encoding.')
    + sLineBreak + _('Click: filter grid to read errors'),
    Ord(fkFileReadError), TileClickKind);
  TileWire(FTileCyclomatic, _('Cyclomatic Complexity') + sLineBreak +
    _('Methods with McCabe complexity > threshold (default 10).')
    + sLineBreak + _('Hard to test - refactor into smaller methods.')
    + sLineBreak + _('Click: filter grid to Cyclomatic'),
    Ord(fkCyclomaticComplexity), TileClickKind);

  // Typ-Kacheln -> Typ-Combo
  TileWire(FTileBug, _('Bugs') + sLineBreak +
    _('Findings of type Bug (wrong behaviour, crash, wrong result).')
    + sLineBreak + _('Crosses severities - Bugs can be Errors OR Warnings.')
    + sLineBreak + _('Click: filter grid to Bug type'),
    Ord(tfBug), TileClickType);
  TileWire(FTileVuln, _('Security') + sLineBreak +
    _('Security holes (SQL injection, hardcoded secrets ...).')
    + sLineBreak + _('Click: filter grid to Vulnerability type'),
    Ord(tfVulnerability), TileClickType);
  TileWire(FTileDup, _('Duplicates') + sLineBreak +
    _('Copied code (strings, blocks). Extract Method/Constant candidates.')
    + sLineBreak + _('Click: filter grid to Duplicate type'),
    Ord(tfCodeDuplication), TileClickType);

  // Quality-Kachel = Reset (Score ist eine Aggregation, kein Filter).
  // Statischer Start-Hint wie im Plugin; UpdateStats ersetzt ihn nach
  // jedem Lauf durch den Detail-Tooltip (BuildScoreHint).
  TileWire(FTileScore, _('Quality') + sLineBreak +
    _('Weighted quality score (lower = better).')
    + sLineBreak + _('Weights: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.')
    + sLineBreak + _('Click: reset filters (show everything)'),
    0, TileClickClear);
end;

procedure TForm2.TileClickSeverity(Sender: TObject);
// WICHTIG (Plugin-Erkenntnis): der ItemIndex-Setter feuert KEIN
// OnChange - die Change-Handler muessen explizit gerufen werden.
var
  Target : TFilterMode;
begin
  if not (Sender is TComponent) then Exit;
  Target := TFilterMode(TComponent(Sender).Tag);
  // VOR der Zielsuche: eine offene Fuzzy-Reduktion tag-treu zuruecklegen,
  // damit die Suche die VOLLE Liste sieht (sonst verfehlte der Klick
  // sein Ziel, sobald der Nutzer gerade getippt hatte).
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  if TypeFilterCombo.ItemIndex <> 0 then
    TypeFilterCombo.ItemIndex := 0;
  // Tag-Suche mit Miss-Rueckfall auf 'All' - geteilt mit dem Plugin,
  // Vertrag und Begruendung an TTileFilterSelect.SelectByTag. Bis
  // 2026-08-19 brach die Suche hier wortlos ab: bei aktiver Baseline
  // konnte der Eintrag fehlen, dann blieb der alte Severity-Filter stehen,
  // obwohl der Typ-Filter oben schon zurueckgesetzt war.
  TTileFilterSelect.SelectByTag(SeverityFilterCombo, Ord(Target));
  // Commit-Gedaechtnis des Fuzzy-Helfers nachziehen - programmatisches
  // ItemIndex sieht der Helfer nicht, und sein Tag-Gate wuerde sonst die
  // naechste ECHTE Wieder-Auswahl in der Combo verschlucken (Review
  // 2026-08-12, Kachel-Pfad).
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  // EINMAL filtern, nicht zweimal (Review-Minor 2026-08-19): der
  // ItemIndex-Setter feuert kein OnChange, also muss der Klick den Filter
  // selbst anstossen - aber beide Change-Handler bestehen nur aus
  // 'ApplyFilter', und der lief damit zweimal ueber die gesamte
  // Befundliste. Das Plugin braucht dafuer einen Unterdrueckungs-Zaehler,
  // weil seine Handler noch Combo-Zustand parsen; hier reicht der direkte
  // Aufruf.
  ApplyFilter;
end;

procedure TForm2.TileClickKind(Sender: TObject);
// Kacheln, deren Ziel kein fm-Modus ist, sondern der generierte
// Regel-Eintrag der Severity-Combo (Objects = KIND_TAG_BASE+Ord(Kind)).
var
  Want : Integer;
begin
  if not (Sender is TComponent) then Exit;
  Want := TFindingFilter.KIND_TAG_BASE + TComponent(Sender).Tag;
  // Offene Fuzzy-Reduktion zuruecklegen, Begruendung s. TileClickSeverity.
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  if TypeFilterCombo.ItemIndex <> 0 then
    TypeFilterCombo.ItemIndex := 0;
  // Tag-Suche mit Miss-Rueckfall, s. TileClickSeverity.
  TTileFilterSelect.SelectByTag(SeverityFilterCombo, Want);
  // Commit-Gedaechtnis nachziehen, Begruendung s. TileClickSeverity.
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  // Einmal filtern, s. TileClickSeverity.
  ApplyFilter;
end;

procedure TForm2.TileClickType(Sender: TObject);
var
  Target : TTypeFilter;
begin
  if not (Sender is TComponent) then Exit;
  Target := TTypeFilter(TComponent(Sender).Tag);
  // Offene Fuzzy-Reduktion zuruecklegen: erst danach ist Index 0 der
  // All-Eintrag (Begruendung s. TileClickSeverity).
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  if SeverityFilterCombo.ItemIndex <> 0 then
    SeverityFilterCombo.ItemIndex := 0;
  // Tag-Suche mit Miss-Rueckfall, s. TileClickSeverity.
  TTileFilterSelect.SelectByTag(TypeFilterCombo, Ord(Target));
  // Auch hier: die Severity-Combo wurde oben auf 0 gesetzt - Commit-
  // Gedaechtnis nachziehen, Begruendung s. TileClickSeverity.
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  // Einmal filtern, s. TileClickSeverity.
  ApplyFilter;
end;

procedure TForm2.TileClickClear(Sender: TObject);
// Quality-Kachel als Ein-Griff-Reset. In der EXE gehoert das SUCHFELD
// mit dazu (das Plugin hat keines in dieser Form) - 'show everything'
// soll wirklich alles zeigen.
begin
  // Offene Fuzzy-Reduktion ZUERST zuruecklegen: in einer reduzierten
  // Liste ist Index 0 irgendein Treffer, nicht 'All'.
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  SeverityFilterCombo.ItemIndex := 0;
  TypeFilterCombo.ItemIndex     := 0;
  // Commit-Gedaechtnis nachziehen, Begruendung s. TileClickSeverity.
  if Assigned(FSeveritySearch) then FSeveritySearch.NoteHostSelection;
  if SearchEdit.Text <> '' then
    SearchEdit.Text := '';           // OnChange feuert (Setter am EDIT)
  // Einmal filtern, s. TileClickSeverity.
  ApplyFilter;
end;

procedure TForm2.BuildOpenWithMenu(AParent: TMenuItem);
// Was ein Doppelklick auf einen .dfm-Befund oeffnet. Nur diese eine Wahl
// steht im Menue - der externe Editor braucht einen Pfad und eine
// Argumentvorlage und gehoert damit in die INI; der letzte Eintrag fuehrt
// dorthin.
//
// Bauart wie beim Erscheinungsbild: der Tag traegt den Wert, damit der
// Handler nicht von der uebersetzten Beschriftung abhaengt.
const
  CAPTIONS : array[TDfmTarget] of string = (
    'DFM findings: Delphi IDE', 'DFM findings: built-in viewer');
var
  T   : TDfmTarget;
  Cur : TDfmTarget;
  MI  : TMenuItem;
begin
  if not Assigned(AParent) then Exit;
  AParent.Clear;
  Cur := TEditorCommand.Load.DfmTarget;
  for T := Low(TDfmTarget) to High(TDfmTarget) do
  begin
    MI := TMenuItem.Create(AParent);
    MI.Caption    := _(CAPTIONS[T]);
    MI.RadioItem  := True;
    MI.GroupIndex := 72;          // eigener Kreis, stoert Erscheinungsbild nicht
    MI.Tag        := Ord(T);
    MI.Checked    := (T = Cur);
    MI.OnClick    := OpenWithItemClick;
    AParent.Add(MI);
  end;

  MI := TMenuItem.Create(AParent);
  MI.Caption := '-';
  AParent.Add(MI);

  MI := TMenuItem.Create(AParent);
  MI.Caption := _('Configure external editor...');
  MI.OnClick := ConfigureEditorClick;
  AParent.Add(MI);
end;

procedure TForm2.OpenWithItemClick(Sender: TObject);
var
  MI : TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  MI := TMenuItem(Sender);
  PersistDfmTarget(TDfmTarget(MI.Tag));
  BuildOpenWithMenu(FMIOpenWith);
end;

procedure TForm2.ConfigureEditorClick(Sender: TObject);
// Die analyser.ini oeffnen - aber vorher sicherstellen, dass der
// [Editor]-Abschnitt ueberhaupt darin steht.
//
// Warum das noetig ist: die dokumentierte Vorlage wird nur geschrieben,
// wenn es noch GAR KEINE Datei gibt. Wer schon eine hat, bekaeme sonst
// eine Datei zu sehen, in der die Einstellung, die er gerade suchen
// wollte, nicht vorkommt - waehrend sie sehr wohl wirkt. Der Abschnitt
// wird nur ANGEHAENGT, wenn er fehlt; vorhandene Werte bleiben unberuehrt.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    Settings.EnsureConfigExists;
  finally
    Settings.Free;
  end;
  TRepoSettings.EnsureSection(TEditorCommand.INI_SECTION);
  HamburgerSettingsClick(Sender);
end;

procedure TForm2.PersistDfmTarget(AValue: TDfmTarget);
// Ueber TIniFile schreiben, NICHT ueber TRepoSettings.Save: dessen
// TMemIniFile schreibt die Datei komplett neu und wirft dabei saemtliche
// Kommentare weg - und die Kommentare SIND hier die Dokumentation.
// Dieselbe Entscheidung wie beim Theme (uAppTheme.PersistMode).
var
  Ini      : TIniFile;
  Settings : TRepoSettings;
begin
  // Unveraendert? Dann nichts anfassen. Ein Klick auf das bereits aktive
  // Radio-Item schrieb sonst trotzdem - und zwar VOR dem EnsureSection-
  // Nachtrag unten haette WritePrivateProfileString bei Alt-INIs ein
  // nacktes [Editor] ans Dateiende gelegt.
  if TEditorCommand.Load.DfmTarget = AValue then Exit;

  try
    // Erst dafuer sorgen, dass Verzeichnis UND Datei da sind. Ohne das
    // wirft TIniFile.Create/WriteString beim allerersten Start
    // (%APPDATA%\StaticCodeAnalyser\ existiert noch nicht), der leere
    // except unten schluckt es, und der Menuepunkt springt sichtbar
    // zurueck, ohne dass jemand erfaehrt warum.
    Settings := TRepoSettings.Create;
    try
      Settings.EnsureConfigExists;
    finally
      Settings.Free;
    end;
    // Und den DOKUMENTIERTEN [Editor]-Block nachtragen, BEVOR die
    // Profil-API schreibt. Andersherum legte WritePrivateProfileString
    // bei einer Alt-INI ein nacktes '[Editor]' mit nur der einen Zeile
    // an - und EnsureSection, das nur die Kopfzeile prueft, haengt den
    // erklaerten Block danach nie mehr an. 'Configure external
    // editor...' zeigte dann genau die unkommentierte Datei, die das
    // Feature verhindern sollte.
    TRepoSettings.EnsureSection(TEditorCommand.INI_SECTION);
    Ini := TIniFile.Create(TRepoSettings.ResolvedConfigPath);
    try
      Ini.WriteString(TEditorCommand.INI_SECTION,
                      TEditorCommand.KEY_DFMTARGET,
                      TEditorCommand.DfmTargetToStr(AValue));
    finally
      Ini.Free;
    end;
  except
    // Ehrlich melden statt still verwerfen: es gibt KEINEN
    // Sitzungszustand fuer diese Wahl - Menue und Doppelklick lesen die
    // INI jedes Mal neu. Eine schreibgeschuetzte Datei heisst also
    // 'Wahl wirkungslos', und das muss der Nutzer sehen. (Die
    // Vorgaengerfassung behauptete im Kommentar eine Sitzungsgeltung,
    // die nie existiert hat.)
    StatusBar1.Panels[2].Text :=
      Format(_('Could not save the choice - analyser.ini is not writable: %s'),
        [TRepoSettings.ResolvedConfigPath]);
  end;
end;

procedure TForm2.ThemeChanged(Sender: TObject);
// Ein VCL-Style-Wechsel faerbt Standard-Controls von allein. Alles, was
// die Anwendung SELBST malt, muss angestossen werden - sonst bleiben
// genau die Flaechen hell, die den Fund-Text tragen.
begin
  if csDestroying in ComponentState then Exit;
  // Kacheln, Hilfe-Panel und andere Flaechen, die den Style fuer sich
  // abgeschaltet haben, malen mit ihrer eigenen Color - und die zeigt auf
  // eine SYSTEMFARBE, die Windows im Dunkelmodus NICHT mitaendert. Ohne
  // diesen Aufruf bleiben sie hell, waehrend der Rest dunkel ist.
  TAppTheme.ResolveSystemColors(Self);
  if Assigned(ResultGrid) then
    ResultGrid.Invalidate;
  Invalidate;
end;

procedure TForm2.SettingChange(var Msg: TWMSettingChange);
// Windows meldet einen Themenwechsel ueber WM_SETTINGCHANGE mit dem
// Abschnittsnamen 'ImmersiveColorSet'. Es gibt kein spezifischeres
// Signal; deshalb erst den Namen pruefen und die Arbeit TAppTheme
// ueberlassen, das seinerseits nur bei echter Aenderung umschaltet.
begin
  inherited;
  if (Msg.Section <> nil)
     and SameText(string(Msg.Section), 'ImmersiveColorSet') then
    TAppTheme.HandleSystemThemeChanged;
end;

// Nativer Sprachname zum ISO-Kuerzel - Eigennamen, bewusst NICHT durch
// den Katalog uebersetzt ('Deutsch' heisst in jeder UI-Sprache Deutsch).
// Unbekannte Kuerzel (neue .po ohne Eintrag hier) zeigen das Kuerzel.
function LanguageNativeName(const ACode: string): string;
begin
  if SameText(ACode, 'de') then Exit('Deutsch');
  if SameText(ACode, 'en') then Exit('English');
  if SameText(ACode, 'fr') then Exit('Fran'#$00E7'ais');
  Result := ACode;
end;

procedure TForm2.BuildLanguageMenu(AParent: TMenuItem);
// Ein Radio-Item pro verfuegbarer Sprache. Die Liste kommt aus
// uLocalization.AvailableLanguages (eingebettete .po + externe i18n\*.po
// neben der EXE + 'en') - im Code steht KEIN Sprachkuerzel, damit eine
// neue Uebersetzung ohne UI-Aenderung auftaucht.
// Caption ist der NATIVE Sprachname (s. LanguageNativeName); das Kuerzel
// liegt zusaetzlich im Hint, damit der Click-Handler nicht von der
// Caption abhaengt.
var
  Codes : TArray<string>;
  Cur   : string;
  MI    : TMenuItem;
  I     : Integer;
begin
  if not Assigned(AParent) then Exit;
  // CurrentLanguage ist der zuletzt via SetLanguage gesetzte Wert -
  // FormCreate hat den INI-Wert bereits durchgereicht. Leer = Englisch.
  Cur := LowerCase(Trim(CurrentLanguage));
  if Cur = '' then Cur := 'en';

  Codes := AvailableLanguages;
  for I := Low(Codes) to High(Codes) do
  begin
    MI            := TMenuItem.Create(AParent);
    MI.Caption    := LanguageNativeName(Codes[I]);
    MI.Hint       := Codes[I];
    MI.RadioItem  := True;
    // Eigener GroupIndex fuer den Radio-Kreis. Alle anderen Items des
    // Hamburger-Menues liegen auf dem Default 0 - damit ist der Kreis
    // auf das Sprach-Untermenue begrenzt.
    MI.GroupIndex := 7;
    MI.Checked    := SameText(Codes[I], Cur);
    MI.OnClick    := LanguageItemClick;
    AParent.Add(MI);
  end;
end;

procedure TForm2.LanguageItemClick(Sender: TObject);
// Schreibt die Auswahl nach [UI] Language und stellt die Laufzeit sofort um.
//
// SOFORTWIRKUNG: SetLanguage wirkt auf alles was ab jetzt NEU gebaut wird
// (Statusmeldungen, Dialoge, Export-/Hamburger-Captions beim naechsten
// Aufbau). Die bereits gesetzten Captions von Form, Toolbar, Grid-Header
// und Hint-Panel bleiben auf der alten Sprache: sie werden genau einmal
// beim Control-Aufbau zugewiesen, ein Re-Caption-Pass existiert nicht.
// Darum der ehrliche Hinweis in der Statusleiste statt einer halb
// funktionierenden Live-Umschaltung.
//
// Detektor-Meldungen sind NICHT lokalisiert - die Auswahl beruehrt
// Fundzahlen, Grid-Inhalte und Exporte nicht.
var
  MI       : TMenuItem;
  Code     : string;
  Settings : TRepoSettings;
begin
  if not (Sender is TMenuItem) then Exit;
  MI   := TMenuItem(Sender);
  Code := LowerCase(Trim(MI.Hint));
  if Code = '' then Exit;

  Settings := TRepoSettings.Create;
  try
    // Load vor Save: sonst wuerde Save die uebrigen Sections mit den
    // Constructor-Defaults ueberschreiben (gleiches Muster wie die
    // Options-Page des IDE-Plugins). Genau das erzwingt LoadBeforeWrite -
    // vorher stand hier ein stilles 'except end', das den Ablauf trotzdem
    // zum Save durchliess.
    if not LoadBeforeWrite(Settings) then
    begin
      StatusBar1.Panels[2].Text := _('Settings could not be reloaded - nothing was saved.');
      Exit;
    end;
    Settings.Language := Code;
    try Settings.Save; except end;   // s. ProfileComboChange
  finally
    Settings.Free;
  end;

  SetLanguage(Code);
  // Sofort umstellen, was sich gefahrlos neu beschriften laesst:
  // Filterzeile, Pfadzeile, Grid-Header, Analyse-Button.
  ApplyUiCaptions;
  ProjectpathChangedScope(nil);
  StatusBar1.Panels[2].Text := Format(
    _('UI language: %s - remaining captions (tiles, filter lists, help panel) switch after a restart.'),
    [Code]);
  // Das Hamburger-Menue traegt seine Captions seit dem einmaligen Aufbau
  // in FormCreate - der Kommentar hier versprach frueher einen 'naechsten
  // Aufbau', den es nie gab. Neu bauen - aber NACH diesem Handler:
  // Sender ist ein Kind des Menues, das hier stuerbe (Use-after-free im
  // eigenen Klick). ForceQueue laeuft nach der aktuellen Nachricht im
  // Hauptthread.
  TThread.ForceQueue(nil,
    procedure
    begin
      if csDestroying in ComponentState then Exit;
      FreeAndNil(FHamburgerMenu);
      BuildHamburgerMenu;
    end);
end;

procedure TForm2.HamburgerMenuPopup(Sender: TObject);
// Enabled-Sync VOR dem Oeffnen. Cancel ist nur waehrend laufender Analyse
// aktiv. Branch-Changes ist als eigener Top-Level-Button kein Menue-Item
// mehr.
begin
  if Assigned(FMICancel) then
    FMICancel.Enabled := Assigned(FBtnCancel) and FBtnCancel.Enabled;
  // Baseline-Haken aus der INI nachziehen (kann von aussen geaendert
  // worden sein - Plugin und CLI schreiben denselben Schluessel).
  if Assigned(FMIBaseline) then
  begin
    var S := TRepoSettings.Create;
    try
      try S.Load; except end;
      FMIBaseline.Checked := S.BaselineOnlyNew;
    finally
      S.Free;
    end;
  end;
end;

procedure TForm2.HamburgerClick(Sender: TObject);
// Lazy: bei jedem Klick Popup unter dem Button anzeigen.
var P : TPoint;
begin
  if not Assigned(FBtnHamburger) or not Assigned(FHamburgerMenu) then Exit;
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FHamburgerMenu.Popup(P.X, P.Y);
end;

procedure TForm2.HamburgerExportClick(Sender: TObject);
// Export-Menu unter dem Hamburger-Button oeffnen. FExportMenu ist das
// gleiche Popup-Menu das frueher direkt am Export-Button hing.
var P : TPoint;
begin
  if not Assigned(FBtnHamburger) or not Assigned(FExportMenu) then Exit;
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FExportMenu.PopupAt(P.X, P.Y);
end;

procedure TForm2.HamburgerSettingsClick(Sender: TObject);
// Oeffnet analyser.ini im Default-Editor. Naechster Analyse-Klick laedt
// die INI neu (PrepareAnalysis ruft FRepoSettings.Load) - Aenderungen
// greifen ohne Form-Restart.
var
  Settings : TRepoSettings;
  Path     : string;
begin
  Settings := TRepoSettings.Create;
  try
    Settings.EnsureConfigExists;
    Path := Settings.ConfigFilePath;
  finally
    Settings.Free;
  end;
  try
    ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    StatusBar1.Panels[2].Text := _('Could not open editor. File: ') + Path;
    Exit;
  end;
  StatusBar1.Panels[2].Text := Format(_('Settings: %s - changes take effect on the next analysis run.'),
    [Path]);
end;

procedure TForm2.HamburgerIgnoreListClick(Sender: TObject);
// Oeffnet die Ignore-Liste mit dem Default-Editor (Notepad). Nach
// Schliessen kommt die naechste Analyse mit der frischen Liste.
var
  Ignore : TIgnoreList;
  Path   : string;
begin
  Ignore := TIgnoreList.Create;
  try
    Ignore.EnsureConfigExists;
    Path := Ignore.ConfigFilePath;
    try
      ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
    except
      StatusBar1.Panels[2].Text := _('Could not open editor. File: ') + Path;
      Exit;
    end;
    StatusBar1.Panels[2].Text := Format(
      _('Ignore list opened: %s'), [Path]);
  finally
    Ignore.Free;
  end;
end;

end.
