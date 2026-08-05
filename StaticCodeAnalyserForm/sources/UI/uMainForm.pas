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
  uMethodd12, uSCAConsts, uFixHint, uClaudePrompt, uLocalization,
  uAnalyserTypes,  // SeverityFromKindLevel, TFindingSeverity (Grid-Renderer-Callback)
  uRepoSettings, uRecentPaths, uScanTargetDialog, uFindingGridRenderer, uDfmTextViewer,
  uEditorCommand,                 // TEditorSpec (Parametertyp von OpenViaExternalEditor)
  uIDEHelpPanel,                  // TFindingHintPanel (im class-Feld referenziert)
  uExportMenu,                    // TFindingExportMenu (Class-Field-Reference)
  uFindingFilter,                 // TFilterComboItem (Snapshot-Felder)
  uFuzzyComboSearch,              // tippbare Severity-Combo mit Fuzzy-Suche
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
    LblSearch: TLabel;
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
    FBtnHamburger   : TButton;
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
    // 'Detector Review' bleiben immer). Aktuelle Auswahl wird via
    // Items.Objects-Tag wiederhergestellt; gibt es den vorher gewaehlten
    // Eintrag nach dem Scan nicht mehr, faellt der Combo auf 'All' zurueck.
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
    function  OpenViaDelphiIde(const AAbsPath: string; ALine: Integer;
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
    procedure NavigateDelphiToLine(LineNo: Integer);
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

    // ---- Profile-Combo befuellen aus TRuleCatalog.ProfileNames ----
    ProfileList := TRuleCatalog.ProfileNames;
    if Length(ProfileList) = 0 then
      ProfileCombo.Items.Add('default')
    else
      for Name in ProfileList do ProfileCombo.Items.Add(Name);
    // Default-Selektion = [Rules] Profile aus INI (leer = default).
    if Settings.Profile <> '' then
      Idx := ProfileCombo.Items.IndexOf(Settings.Profile)
    else
      Idx := ProfileCombo.Items.IndexOf('default');
    if Idx < 0 then Idx := 0;
    ProfileCombo.ItemIndex := Idx;

    // ---- Min-Severity-Combo befuellen: 3 fixe Stufen ----
    MinSevCombo.Items.Add('hint');
    MinSevCombo.Items.Add('warning');
    MinSevCombo.Items.Add('error');
    Idx := MinSevCombo.Items.IndexOf(LowerCase(Settings.MinSeverity));
    if Idx < 0 then Idx := MinSevCombo.Items.IndexOf('hint');
    MinSevCombo.ItemIndex := Idx;
  finally
    Settings.Free;
  end;
  ResultGrid.Cells[0, 0] := _('File');
  ResultGrid.Cells[1, 0] := _('Method');
  ResultGrid.Cells[2, 0] := _('Line');
  ResultGrid.Cells[3, 0] := _('Detail');
  ResultGrid.Cells[4, 0] := _('Severity');

  // Branch-Button-Hint zur Laufzeit setzen (DFM-Hint waere hardcoded
  // Englisch). Pattern analog zum IDE-Plugin (FBtnAnalyseChanged.Hint).
  BtnBranch.Hint := _('Branch-Changes') + ': ' +
    _('analyse only files changed in current branch');
  ResultGrid.OnDrawCell  := ResultGridDrawCell;
  ResultGrid.OnDblClick  := ResultGridDblClick;
  ResultGrid.OnMouseDown := ResultGridMouseDown;   // Header-Klick = sortieren
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
  TypeFilterCombo.Items.AddObject(_('All'),              TObject(Ord(tfAll)));
  TypeFilterCombo.Items.AddObject('Bug',                 TObject(Ord(tfBug)));
  TypeFilterCombo.Items.AddObject('Code Smell',          TObject(Ord(tfCodeSmell)));
  TypeFilterCombo.Items.AddObject('Vulnerability',       TObject(Ord(tfVulnerability)));
  TypeFilterCombo.Items.AddObject('Security Hotspot',    TObject(Ord(tfSecurityHotspot)));
  TypeFilterCombo.Items.AddObject('Code Duplication',    TObject(Ord(tfCodeDuplication)));
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
  // Layout: Cancel-Button rechts am StatusBar-Rand (alRight, Width=80),
  // ProgressBar fuellt den restlichen Platz (alClient). Beide werden in
  // BeginAnalysisUI sichtbar geschaltet und in EndAnalysisUI wieder
  // versteckt - so bleiben die Status-Text-Panels im Ruhe-Zustand
  // vollstaendig sichtbar.
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent  := StatusBar1;
  FBtnCancel.Caption := _('Cancel');
  FBtnCancel.Width   := 80;
  FBtnCancel.Align   := alRight;
  FBtnCancel.Enabled := False;
  FBtnCancel.Visible := False;
  FBtnCancel.OnClick := BtnCancelClick;

  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent  := StatusBar1;
  FProgressBar.Align   := alClient;
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
  FBtnHamburger := TButton.Create(Self);
  FBtnHamburger.Parent  := PanelActions;
  FBtnHamburger.Caption := #$2630;  // 'Trigram for Heaven' = Hamburger-Glyph
  FBtnHamburger.Width   := 32;
  FBtnHamburger.Height  := BtnBranch.Height;
  FBtnHamburger.Top     := BtnBranch.Top;
  FBtnHamburger.Left    := BtnBranch.Left + BtnBranch.Width + 12;
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
  FLastProgressTick := 0;
  Screen.Cursor     := crAppStart;
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
  if FCancelRequested then
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
      StatusBar1.Panels[2].Text := Format(
        _('More than %d files found - scan cancelled.'), [MAX_SCAN_FILES]);
      Abort;
    end;
    if doUpdate then
    begin
      FLastProgressTick := tick;
      if FProgressBar.Style <> pbstMarquee then
        FProgressBar.Style := pbstMarquee;
      StatusBar1.Panels[2].Text := Format(_('Scanning... %d found'), [Current]);
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
        StatusBar1.Panels[2].Text := Format(_('File %d / %d (%d%%)'),
          [Current, Total, Round(Current * 100 / Total)])
      else
        StatusBar1.Panels[2].Text := Format(_('File %d'), [Current]);
      Application.ProcessMessages;
    end;
  end;
end;

procedure TForm2.FormResizeHandler(Sender: TObject);
begin
  if Assigned(FHintPanel) then FHintPanel.ApplyLayout;
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
  // Klassen-Ereignis loesen: TAppTheme lebt laenger als die Form, ein
  // haengender Zeiger waere ein Aufruf ins Freigegebene.
  TAppTheme.OnChanged := nil;

  // Globalen Application.OnShowHint loesen damit kein dangling Methodenzeiger
  // ueberlebt wenn das Form zerstoert wird (relevant beim IDE-Plugin-Hosting).
  if TMethod(Application.OnShowHint).Data = Self then
    Application.OnShowHint := nil;
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
// Sichtbarer Modus-Indikator (Review-Auflage Konzept par.4.3): der Analyse-
// Button sagt, was er tun wird.
begin
  case ScopeForPath(Projectpath.Text) of
    ssProject:      Button6.Caption := _('Analyse project');
    ssProjectGroup: Button6.Caption := _('Analyse group');
  else
    Button6.Caption := _('Analyse directory');
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
          // User-Cancel oder MAX_SCAN_FILES-Limit. StatusBar wurde im
          // ProgressCallback bereits gesetzt.
          ;
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
// Aktuelle Auswahl wird via Mode-Ord wiederhergestellt; war der Eintrag
// vor dem Scan ausgewaehlt und ist jetzt weg, faellt der Combo auf
// 'All' (Index 0) zurueck.
var
  Item : TFilterComboItem;
  SavedSevMode, SavedTypeMode, NewIdx, i : Integer;
begin
  if FAllFindings = nil then Exit;
  if Length(FAllSeverityItems) = 0 then Exit;

  // Aktuelle Auswahl merken (Ord, nicht Index - Index verschiebt sich).
  SavedSevMode := Ord(fmAll);
  if (SeverityFilterCombo.ItemIndex >= 0)
     and Assigned(SeverityFilterCombo.Items.Objects[SeverityFilterCombo.ItemIndex]) then
    SavedSevMode := Integer(
      SeverityFilterCombo.Items.Objects[SeverityFilterCombo.ItemIndex]);
  SavedTypeMode := Ord(tfAll);
  if (TypeFilterCombo.ItemIndex >= 0)
     and Assigned(TypeFilterCombo.Items.Objects[TypeFilterCombo.ItemIndex]) then
    SavedTypeMode := Integer(
      TypeFilterCombo.Items.Objects[TypeFilterCombo.ItemIndex]);

  // ---- SeverityFilterCombo ----
  SeverityFilterCombo.Items.BeginUpdate;
  try
    SeverityFilterCombo.Clear;
    for Item in FAllSeverityItems do
    begin
      if (Item.ModeOrd = Ord(fmAll))
         or (Item.ModeOrd = Ord(fmDetectorReview))
         or (TFindingFilter.CountForTag(FAllFindings, Item.ModeOrd) > 0) then
        SeverityFilterCombo.Items.AddObject(Item.Display,
                                            TObject(Item.ModeOrd));
    end;
  finally
    SeverityFilterCombo.Items.EndUpdate;
  end;
  NewIdx := 0;
  for i := 0 to SeverityFilterCombo.Items.Count - 1 do
    if Integer(SeverityFilterCombo.Items.Objects[i]) = SavedSevMode then
    begin
      NewIdx := i;
      Break;
    end;
  SeverityFilterCombo.ItemIndex := NewIdx;
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
         or (TFindingFilter.CountForType(FAllFindings,
                                         TTypeFilter(Item.ModeOrd)) > 0) then
        TypeFilterCombo.Items.AddObject(Item.Display, TObject(Item.ModeOrd));
    end;
  finally
    TypeFilterCombo.Items.EndUpdate;
  end;
  NewIdx := 0;
  for i := 0 to TypeFilterCombo.Items.Count - 1 do
    if Integer(TypeFilterCombo.Items.Objects[i]) = SavedTypeMode then
    begin
      NewIdx := i;
      Break;
    end;
  TypeFilterCombo.ItemIndex := NewIdx;
end;

procedure TForm2.UpdateStats;
// Befuellt die 9 Stats-Tiles aus FAllFindings. Quality-Score = gewichtete
// Summe (niedriger = besser); Gewichte 1:1 vom IDE-Plugin uebernommen
// damit die Werte zwischen Standalone und Plugin vergleichbar sind.
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
  FTileScore.Caption      := IntToStr(score);
end;

procedure TForm2.ApplyFilter;
// Wendet Severity-Combo / Type-Combo / Search-Edit auf FAllFindings an,
// schreibt das Ergebnis in FDisplayedFindings und triggert Grid-Repaint
// (Virtual-Mode - ResultGridDrawCell.GetCellText zieht den Inhalt
// lazy aus FDisplayedFindings, keine Cells[]-Vorallokation).
// ResultGridClick mappt Grid-Row -> FDisplayedFindings[row-1] (nicht
// FAllFindings!), siehe ResultGridClick.
var
  Criteria : TFindingFilterCriteria;
  f        : TLeakFinding;
  i        : Integer;
begin
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
  for i := 0 to FAllFindings.Count - 1 do
  begin
    f := FAllFindings[i];
    if TFindingFilter.Matches(f, Criteria) then
      FDisplayedFindings.Add(f);
  end;

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
    SortCfg.Column     := FSortColumn;
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
      StatusBar1.Panels[2].Text  := _('Done. No findings.');
    end
    else
    begin
      ResultGrid.Cells[0, 1] := _('No matches.');
      StatusBar1.Panels[2].Text  := Format(_('Filtered: 0 of %d findings'),
        [FAllFindings.Count]);
    end;
    Exit;
  end;

  // Virtual-Mode: nur RowCount setzen. Cell-Strings werden im OnDrawCell
  // ueber Config.GetCellText aus FDisplayedFindings gezogen - spart bei
  // 66k+ Befunden ~50-100 MB Cell-Storage im TStringGrid (32-Bit-Limit).
  ResultGrid.RowCount := FDisplayedFindings.Count + 1;
  ResultGrid.Invalidate;
  if TotalMatched > FDisplayedFindings.Count then
    // gekappt - User darauf hinweisen, dass mehr Treffer existieren.
    StatusBar1.Panels[2].Text := Format(_(
      'Showing first %d of %d findings - refine the filter to see more'),
      [FDisplayedFindings.Count, TotalMatched])
  else if TotalMatched = FAllFindings.Count then
    StatusBar1.Panels[2].Text := Format(_('Done. %d findings. Click a row -> ' +
      'AI prompt on clipboard.'), [FAllFindings.Count])
  else
    StatusBar1.Panels[2].Text := Format(_('Filtered: %d of %d findings'),
      [TotalMatched, FAllFindings.Count]);
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
  ALine: Integer; out AError: string): Boolean;
// Der Windows-Standardhandler oeffnet die Datei; die Zeile wird danach
// ueber die Tastatur angesprungen, weil die IDE von aussen keinen
// Schalter fuer eine Zeilennummer anbietet.
begin
  AError := '';
  // ProcessMessages flushed Pending-Events (z.B. den Repaint nach Modal-
  // Close des DFM-Viewers). Ohne das Flush kann der Start beim
  // Delphi-IDE-DDE-Handler "verloren gehen" - die IDE bekommt Focus,
  // oeffnet die Datei aber nicht.
  //
  // ProcessMessages fuehrt allerdings ALLES aus, was in der Schlange
  // steht - auch ein Schliessen des Fensters. Danach zeigen Self und
  // StatusBar1 auf freigegebenen Speicher, deshalb hinter jedem Pumpen
  // eine Pruefung.
  Application.ProcessMessages;
  if csDestroying in ComponentState then Exit(False);
  Result := LaunchProcess(AAbsPath, '', AError);
  if not Result then Exit;
  if ALine > 0 then
  begin
    Sleep(1200); // Delphi IDE Zeit geben, die Datei zu oeffnen
    Application.ProcessMessages;
    if csDestroying in ComponentState then Exit;
    NavigateDelphiToLine(ALine);
  end;
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
// die IDE. Eine ehrliche Einschraenkung dazu: die IDE oeffnet eine .dfm
// je nach Registrierung im Formular-Entwurf, und dort geht kein Sprung
// zur Zeile - der eingebaute Betrachter kann das zuverlaessig. Deshalb
// bleibt er als Wahl bestehen und faengt ausserdem den Fall ab, dass gar
// kein Handler antwortet.
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
    if OpenViaDelphiIde(AAbsPath, ALine, err) then
    begin
      // Dieser Weg pumpt Nachrichten - das Fenster kann inzwischen weg sein.
      if csDestroying in ComponentState then Exit('');
      Result := Format(_('Opened: %s  Line: %d'), [ARelPath, ALine]);
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
// Zeile aufloesen, oeffnen lassen, melden. Die Wegwahl steckt in
// OpenFindingAt.
//
// Virtual-Mode: Pfad und Zeilennummer aus FDisplayedFindings statt aus
// ResultGrid.Cells[] (die im Virtual-Mode leer sind).
var
  row     : Integer;
  relPath : string;
  absPath : string;
  lineNo  : Integer;
  baseDir : string;
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
    row := ResultGrid.Row;
    if row < 1 then Exit;
    if (FDisplayedFindings = nil) or (row > FDisplayedFindings.Count) then Exit;
    f := FDisplayedFindings[row - 1];
    baseDir := IncludeTrailingPathDelimiter(FCurrentBaseDir);
    relPath := ExtractRelativePath(baseDir, f.FileName);
    if relPath = '' then Exit;
    lineNo := StrToIntDef(f.LineNumber, 0);
    // DirOfProjectPath, nicht Projectpath.Text: bei einem Projekt-Scan
    // steht im Feld eine .dproj/.groupproj-DATEI. Ohne die Umrechnung
    // entstand hier ein Pfad wie ...\Mein.dproj\sources\u.pas, und der
    // Doppelklick meldete fuer JEDEN Befund eines Projekt-Scans
    // "File not found".
    absPath := IncludeTrailingPathDelimiter(DirOfProjectPath(Projectpath.Text))
               + relPath;
    if not FileExists(absPath) then
    begin
      StatusBar1.Panels[2].Text := _('File not found: ') + absPath;
      Exit;
    end;

    msg := OpenFindingAt(absPath, relPath, lineNo);
    if (msg <> '') and not (csDestroying in ComponentState) then
      StatusBar1.Panels[2].Text := msg;
  finally
    gOpeningFinding := False;
  end;
end;

procedure TForm2.NavigateDelphiToLine(LineNo: Integer);
var
  BDSWnd: HWND;
  lineStr: string;
  i: Integer;
  inp: TInput;
begin
  // Belt-and-suspenders: ohne Ziel-Zeile wuerde ein Ctrl+G Dialog leer
  // bestaetigt und die IDE haengt mit einem offenen Dialog herum.
  if LineNo <= 0 then Exit;
  BDSWnd := FindWindow('TAppBuilder', nil);
  if BDSWnd = 0 then Exit;
  SetForegroundWindow(BDSWnd);
  Sleep(150);

  // NACHSEHEN, ob der Wechsel geklappt hat. SendInput schickt die Tasten an
  // das Fenster, das GERADE den Vordergrund hat - nicht an BDSWnd. Windows
  // verweigert SetForegroundWindow aber regelmaessig (Foreground-Lock),
  // und dann tippt diese Routine Ctrl+G und eine Zahl blind in das
  // Programm, das der Nutzer stattdessen vor sich hat. In einem Editor
  // waere das eine Aenderung an fremdem Text.
  if GetForegroundWindow <> BDSWnd then Exit;

  // Ctrl+G = Search > Go to Line Number
  ZeroMemory(@inp, SizeOf(inp));
  inp.Itype := INPUT_KEYBOARD;
  inp.ki.wVk := VK_CONTROL;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.wVk := Ord('G');
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.wVk := VK_CONTROL;
  SendInput(1, inp, SizeOf(TInput));
  Sleep(200);
  // Zeilennummer eintippen - als ZEICHEN, nicht als Taste.
  //
  // KEYEVENTF_UNICODE uebergibt das Zeichen selbst in wScan und laesst wVk
  // auf 0; Windows liefert es dann unabhaengig vom Tastaturlayout aus. Die
  // Vorgaengerfassung nahm 'VkKeyScan(Ch) and $FF' - das verwirft das obere
  // Byte, in dem der noetige Umschalt-Status steht. Auf einem AZERTY-Layout
  // liegen die Ziffern auf der Umschaltebene, und aus der Zeile 42 wurde so
  // die Eingabe "é'" im Gehe-zu-Zeile-Feld.
  lineStr := IntToStr(LineNo);
  for i := 1 to Length(lineStr) do
  begin
    ZeroMemory(@inp, SizeOf(inp));
    inp.Itype      := INPUT_KEYBOARD;
    inp.ki.wVk     := 0;
    inp.ki.wScan   := Ord(lineStr[i]);
    inp.ki.dwFlags := KEYEVENTF_UNICODE;
    SendInput(1, inp, SizeOf(TInput));
    inp.ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
    SendInput(1, inp, SizeOf(TInput));
  end;
  Sleep(50);
  ZeroMemory(@inp, SizeOf(inp));
  inp.Itype := INPUT_KEYBOARD;
  inp.ki.wVk := VK_RETURN;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(1, inp, SizeOf(TInput));
end;

procedure TForm2.ResultGridClick(Sender: TObject);
// Bei Klick auf eine Befund-Zeile:
//   1) Hint-Panel rechts mit Before/After-Code-Beispielen aktualisieren
//      (SOFORT - sichtbares Feedback fuer den User)
//   2) ProcessMessages laesst den Panel-Repaint durchlaufen, BEVOR
//   3) Clipboard.AsText evtl. durch Windows-Clipboard-Listener (Snipping-
//      Tool, Passwortmanager, Browser-Sync) 50-200ms blockiert wird.
// Index bezieht sich auf FDisplayedFindings, NICHT FAllFindings - der
// Filter hat moeglicherweise Eintraege entfernt.
var
  idx : Integer;
  F   : TLeakFinding;
begin
  idx := ResultGrid.Row - 1; // 0-basiert: Zeile 0 ist Header
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;
  F := FDisplayedFindings[idx];
  if Assigned(FHintPanel) then
    FHintPanel.ShowFinding(F);
  // Panel-Repaint flushen, damit der User das Before/After SOFORT sieht.
  // Erst danach den (potenziell blockierenden) Clipboard-Write absetzen.
  Application.ProcessMessages;
  Clipboard.AsText := BuildClaudePrompt(F);
  StatusBar1.Panels[2].Text := Format(
    _('AI prompt copied to clipboard: %s, line %s (%s)'),
    [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]);
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
  TRecentPaths.Save(
    Projectpath, RecentIniPath, APath,
    DEFAULT_MAX_RECENT,
    AppPath, ppLast);
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
    try Settings.Load; except end;
    Settings.Profile := ProfileCombo.Items[ProfileCombo.ItemIndex];
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
    try Settings.Load; except end;
    Settings.MinSeverity := MinSevCombo.Items[MinSevCombo.ItemIndex];
    try Settings.Save; except end;
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
  if Button <> mbLeft then Exit;
  ResultGrid.MouseToCell(X, Y, ACol, ARow);
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
    Ini := TIniFile.Create(TRepoSettings.ResolvedConfigPath);
    try
      Ini.WriteString(TEditorCommand.INI_SECTION,
                      TEditorCommand.KEY_DFMTARGET,
                      TEditorCommand.DfmTargetToStr(AValue));
    finally
      Ini.Free;
    end;
  except
    // BEWUSST leer: eine nicht schreibbare Konfiguration ist kein Fehler,
    // den diese Stelle behandeln koennte - die Wahl gilt dann eben nur
    // fuer diese Sitzung. (Keine eigene Unterdrueckung noetig: EmptyExcept
    // steht bereits in der dateiweiten Liste am Kopf dieser Unit.)
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

procedure TForm2.BuildLanguageMenu(AParent: TMenuItem);
// Ein Radio-Item pro verfuegbarer Sprache. Die Liste kommt aus
// uLocalization.AvailableLanguages (eingebettete .po + externe i18n\*.po
// neben der EXE + 'en') - im Code steht KEIN Sprachkuerzel, damit eine
// neue Uebersetzung ohne UI-Aenderung auftaucht.
// Caption ist das nackte ISO-639-1-Kuerzel; das Kuerzel liegt zusaetzlich
// im Hint, damit der Click-Handler nicht von der Caption abhaengt.
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
    MI.Caption    := Codes[I];
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
    // Options-Page des IDE-Plugins).
    try Settings.Load; except end;
    Settings.Language := Code;
    try Settings.Save; except end;
  finally
    Settings.Free;
  end;

  SetLanguage(Code);
  MI.Checked := True;
  StatusBar1.Panels[2].Text := Format(
    _('UI language: %s - captions already on screen switch after a restart.'),
    [Code]);
end;

procedure TForm2.HamburgerMenuPopup(Sender: TObject);
// Enabled-Sync VOR dem Oeffnen. Cancel ist nur waehrend laufender Analyse
// aktiv. Branch-Changes ist als eigener Top-Level-Button kein Menue-Item
// mehr.
begin
  if Assigned(FMICancel) then
    FMICancel.Enabled := Assigned(FBtnCancel) and FBtnCancel.Enabled;
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
