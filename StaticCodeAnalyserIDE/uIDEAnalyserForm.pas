unit uIDEAnalyserForm;

// Delphi IDE Expert - Analyser als dockbares IDE-Fenster.
// TAnalyserFrame enthaelt die gesamte UI; TAnalyserDockableForm
// registriert es ueber INTACustomDockableForm (wie der Projektmanager).

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
  System.SysUtils, System.StrUtils,
  System.Classes, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.IniFiles,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids, Vcl.ActnList, Vcl.ImgList, Vcl.Menus,
  Vcl.Clipbrd, Vcl.Themes,
  DesignIntf, ToolsAPI, DockForm,    // DockForm: TDockableForm (Editor-Service-Notifier-Signatur)
  uStaticAnalyzer2, uStaticFiles, uMethodd12, uSCAConsts, uExport,
  uFixHint, uIgnoreList, uRepoSettings, uRuleCatalog, uClaudePrompt,
  uAnalyserPalette, uAnalyserTypes, uAnalyserTheme, uLocalization,
  uRecentPaths,
  uIDELineHighlighter, uIDEMessages, uIDEWatchMode, uIDEStatsTiles,
  uIDEHelpPanel, uIDEExportMenu, uIDEEditorIntegration, uIDEStatusBar,
  uIDEThemeIntegration, uIDEAnalyseProgress, uIDEGridTooltip,
  uIDELifecycle, uIDEAnalyseRunner,
  uIDEAnnotationOverlay,
  uIDESCAOptions,                          // Tools > Options > SCA Page
  uIDESonarOptions,                        // Tools > Options > Sonar Integration
  uFindingGridRenderer, uFindingFilter;

const
  // Deferred-Layout-Recompute nach IDE-Dock-Vorgang: SetParent posted diese
  // Message; der Handler ruft FrameResize nachdem die IDE Bounds und
  // Parent vollstaendig gesetzt hat. WM_APP-Range ($8000-$BFFF) ist fuer
  // Application-Private-Use reserviert.
  WM_SCA_REFIT = WM_APP + 100;

type
  TAnalyserFrame = class(TFrame)
  private
    // Drei-Panel-StatusBar (Findings/Progress/Mode) inklusive Setup
    // ist nach uIDEStatusBar.TAnalyserStatusBar ausgelagert. Frame
    // delegiert die Status-Pushes via StatusFindings/Progress/Mode.
    FStatusBar      : TAnalyserStatusBar;
    FAllFindings    : TObjectList<TLeakFinding>;
    FFilterMode     : TFilterMode;
    FCurrentBaseDir : string;
    FFilterCombo       : TComboBox;
    // Hilfe-Panel rechts (Vorher/Nachher-Code-Beispiele) inklusive
    // dessen Splitter, Dock-State-Timer und Layout-Logik. Ehemals 7
    // Felder + 4 Methoden direkt im Frame - jetzt ausgelagert in
    // uIDEHelpPanel.TFindingHintPanel.
    FHintPanel         : TFindingHintPanel;
    FDisplayedFindings : TList<TLeakFinding>;

    FPanelStats        : TPanel;
    // Toolbar-Panels - werden in CreateUI als alTop angelegt. Refs gehalten,
    // damit der Responsive-Controller pro Reihe den Resize hooken kann.
    FPanelPath         : TPanel;
    FPanelButtons      : TPanel;
    FPanelSearch       : TPanel;
    // Sub-Panel-Container fuer Severity- und Type-Combo (Label + Combo
    // gemeinsam in einem alLeft-Block). Refs werden gebraucht damit der
    // Resize-Handler die Width an die Label-Visibility anpassen kann -
    // sonst bleibt das Sub-Panel breit obwohl das Label drinnen hidden ist.
    FPanelSev          : TPanel;
    FPanelType         : TPanel;
    // Drittes Filter-Sub-Panel: Profile-Combo (ide-fast / default / strict).
    // Schreibt transient in FRepoSettings.IdeProfile (kein INI-Save) - wirkt
    // beim NAECHSTEN Analyse-Klick. Items werden aus TRuleCatalog.ProfileNames
    // gefuellt; unbekannte JSON-Profile sind automatisch dabei.
    FPanelProfile      : TPanel;
    FLblProfile        : TLabel;
    FProfileCombo      : TComboBox;
    // Toolbar-Controls die im gedockten/schmalen Modus ausgeblendet werden -
    // ihre Aktionen bleiben ueber das Hamburger-Menu erreichbar (FHamburgerMenu).
    FBtnRepo, FBtnIgnore                           : TButton;
    // Im NARROW/MEDIUM-Mode hidden, FULL-only - via Hamburger-Menu erreichbar.
    FBtnExport                                     : TButton;
    FBtnHamburger                                  : TButton;
    FHamburgerMenu                                 : TPopupMenu;
    // Hamburger-Menu-Items deren Enabled-Zustand sich zur Laufzeit aendert
    // (Cancel: nur waehrend laufender Analyse aktiv; Branch-Changes: waehrend
    // Analyse deaktiviert). HamburgerMenuPopup synct mit den zugehoerigen
    // Buttons. ▶ Analyse + 📄 File sind keine Menu-Items - die Buttons sind
    // immer im Toolbar sichtbar.
    FMICancel, FMIAnalyseChanged                   : TMenuItem;
    FLblFilter, FLblType, FLblSearch               : TLabel;
    // Eine horizontale Tile-Reihe: 4 Severity-Tiles + 3 Type-Tiles + Score.
    // Layout pro Tile: Glyph-Icon links + Count rechts (Top-Row), Caption
    // unten zentriert. Glyphs aus Segoe Fluent Icons (vektor, kein SVG-Lib).
    // Code Smell und Hotspot werden NICHT angezeigt (zaehlen aber in den Score).
    FTileError, FTileWarn, FTileHint, FTileFileSev : TLabel; // Severity
    FTileBug, FTileVuln, FTileDup                  : TLabel; // Type
    FTileCyclomatic                                : TLabel; // Detector-spez.
    FTileScore                                     : TLabel; // Codequalitaet
    // Export-Dropdown: ein Button "Export ▾" mit Popup statt 5 Einzel-Buttons.
    // Export-Popup ist komplett gekapselt in uIDEExportMenu.
    // Hier nur das Field-Reference, Frame ruft AttachToButton beim
    // BtnExport-Setup.
    FExportMenu        : TFindingExportMenu;
    // Zentraler 3-Stufen-Responsive-Controller. Single source of truth fuer
    // alle Visibility-Regeln (siehe RegisterCtrl-Block in CreateUI).
    FResponsive        : TResponsiveLayoutController;
    // ---- Zweiter Filter --------------------------------------------------
    FTypeFilter        : TTypeFilter;
    FTypeCombo         : TComboBox;

    FSearchEdit        : TEdit;
    FSortColumn        : Integer;     // -1 = unsortiert
    FSortDescending    : Boolean;
    // UsesCheck und IncludeTests sind aus der UI rausgewandert -
    // werden jetzt aus analyser.ini [Detectors] gelesen
    // (FRepoSettings.UsesCheck / .IncludeTests).
    // ---- Analyse-Fortschritt --------------------------------------------
    FProgressBar       : TProgressBar; // sichtbar nur waehrend Analyse
    FBtnCancel         : TButton;      // sichtbar nur waehrend Analyse
    FBtnAnalyse        : TButton;      // gemerkt fuer Enable/Disable
    FBtnAnalyseCurrent : TButton;
    FBtnAnalyseChanged : TButton; // Branch-Aenderungen via Git/SVN
    // Running/Cancelled-Flags + UI-Toggle (Buttons enable/disable,
    // Progressbar reset, Cursor) sind nach uIDEAnalyseProgress.
    // TAnalyseProgressController ausgelagert. Frame ruft BeginRun/EndRun.
    FAnalyseProgress   : TAnalyseProgressController;
    // Drei Analyse-Pipelines (RunAll/RunCurrent/RunChanged) sind nach
    // uIDEAnalyseRunner.TAnalyseRunner ausgelagert. Frame haelt nur
    // noch die Click-Handler die PrepareAnalysis + Runner.RunX +
    // FinishAnalysis koordinieren.
    FAnalyseRunner     : TAnalyseRunner;
    // Ignore-Liste fuer Dateien, die NICHT analysiert werden sollen.
    // Wird beim Frame-Start aus %APPDATA%\StaticCodeAnalyser\ignore.txt geladen.
    FIgnoreList        : TIgnoreList;
    // Repo-/VCS-Settings (BaseBranch, IncludeWorkingTree, exe-Pfade).
    // Wird aus %APPDATA%\StaticCodeAnalyser\analyser.ini geladen.
    FRepoSettings      : TRepoSettings;

    // Grid-Tooltip-Subsystem (Per-Cell-CM_HINTSHOW + 100ms-HintPause-
    // Override "Maus ueber Grid") ist nach uIDEGridTooltip.
    // TFindingGridTooltip ausgelagert. Frame haelt nur noch die Instanz.
    FGridTooltip : TFindingGridTooltip;
    // One-Shot-Timer: feuert 150 ms nach SetParent und ruft FrameResize
    // nochmals. Sichert den Fall, dass ProcessMessages waehrend des IDE-
    // Drag-and-Dock den sofort geposteten WM_SCA_REFIT noch vor dem
    // finalen Dock-Bounds-Set leert und danach kein weiterer Resize-Event
    // eintrifft (z.B. weil csLoading in WMSize AdjustSize+Resize blockiert).
    FDockRefitTimer : TTimer;
    procedure DockRefitTimerFired(Sender: TObject);

    // Vor jeder Analyse: INI neu laden, Custom-LeakyClasses + Excludes
    // registrieren, AutoDiscover-Flag setzen, DiscoveredClasses-Liste leeren.
    // AWatchedFile != '' aktiviert Single-File-Live-Watch auf diese Datei
    // (Save+Edit-Trigger). Im Bulk-Pfad ('' uebergeben) wird der Watch
    // explizit deaktiviert - laufende Watcher vom letzten "Aktuelle Datei"-
    // Klick werden also abgemeldet.
    procedure PrepareAnalysis(const AWatchedFile: string = '');
    // Nach jeder Analyse: wenn AutoDiscoverClasses=1 die Treffer in die
    // INI persistieren (die unter [Detectors] LeakyClasses= landen).
    procedure FinishAnalysis;

    // Callbacks fuer den WatchMode-Manager (Live-Analyse beim Speichern).
    // OnWatchFindings ersetzt die Befunde fuer EINE Datei in FAllFindings,
    // ohne den Rest zu loeschen. OnWatchStatus aktualisiert die Statusbar.
    procedure OnWatchFindings(const FileName: string;
      Findings: TObjectList<TLeakFinding>);
    procedure OnWatchStatus(const Status: string);

    procedure BrowseClick(Sender: TObject);
    procedure AnalyseClick(Sender: TObject);
    procedure AnalyseCurrentFileClick(Sender: TObject);
    procedure AnalyseChangedFilesClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure GridDblClick(Sender: TObject);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GridKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure GridResize(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    // Export-Click-Handler sind nach uIDEExportMenu ausgelagert.
    // Diese zwei Getter werden vom Helper aufgerufen (Live-Werte statt
    // Snapshots, weil Grid spaeter gebaut wird und BaseDir sich pro
    // Run aendert).
    function  GetCurrentBaseDir: string;
    function  GetResultGrid: TStringGrid;
    // Klappt das PopupMenu unter dem Export-Button auf.
    // Popup-Show + CurrentFocusFile sind nach uIDEExportMenu ausgelagert.

    // Erstellt die Sonar-Style Tile-Reihe (alle 10 Tiles in einer Zeile).
    procedure BuildStatsTiles(Parent: TPanel);
    // (MakeTile + Tile-Layout sind nach uIDEStatsTiles ausgelagert.)
    // Statusbar-Helpers (3 Panels: Befunde-Count, Datei-Progress, Mode)
    procedure StatusFindings(const T: string);
    procedure StatusProgress(const T: string);
    procedure StatusMode(const T: string);
    procedure TypeFilterChange(Sender: TObject);
    // Profile-Combo OnChange: aktualisiert FRepoSettings.IdeProfile in-memory.
    // Wirkt beim naechsten Klick auf Analyse / Aktuelle Datei / Branch-Changes,
    // weil PrepareAnalysis dann UseIdeRuleSet + ApplyDetectorThresholds ruft.
    procedure ProfileChange(Sender: TObject);
    procedure CancelAnalyseClick(Sender: TObject);
    procedure EditIgnoreListClick(Sender: TObject);
    procedure EditRepoSettingsClick(Sender: TObject);
    // Folge-Anpassungen die FResponsive nach jedem Resize triggert:
    // 1) Sub-Panel-Width an Label-Visibility anpassen (FilterSubPanels)
    // 2) SearchEdit MinWidth dynamisch je nach freiem Platz (SearchMinWidth)
    procedure ResponsiveAfterApply(Sender: TObject);
    procedure HamburgerClick(Sender: TObject);
    procedure HamburgerMenuPopup(Sender: TObject);
    // Hamburger-Menu-Item "Export...": oeffnet das Export-Popup an der
    // Hamburger-Button-Position (statt am hidden BtnExport).
    procedure HamburgerExportClick(Sender: TObject);
    procedure BuildHamburgerMenu;
    // DPI-Scaling fuer Layout-Konstanten. Liest TControl.CurrentPPI - falls
    // 0/uninit, fallback auf 96. Beispiel: ScaleW(28) liefert 28 bei 100%
    // DPI, 56 bei 200%.
    function  ScaleW(AValue: Integer): Integer;
    // Passt FPanelSev/FPanelType-Width an die Label-Visibility an.
    // Wird vom FResponsive.AfterApply-Callback gerufen NACHDEM die Label-
    // Visibility durchgesetzt wurde -> Width-Anpassung sieht frischen Zustand.
    procedure AdjustFilterSubPanels(Sender: TObject);
    // Setzt FSearchEdit.Constraints.MinWidth abhaengig von der PanelSearch-
    // Breite: narrow = 60 (lasst SearchEdit weiter schrumpfen), >=medium = 120.
    procedure AdjustSearchMinWidth(Sender: TObject);
    // Frame.OnResize-Trigger: ruft FResponsive.ForceUpdate. Brauchen wir weil
    // die IDE-Dock-Logik in manchen Szenarien Frame.OnResize selbst nicht
    // sauber feuert (Width direkt gesetzt ohne Resize-Event). FrameResize
    // wird daher zusaetzlich explizit aus FrameCreated / SetParent / Dock-
    // Refit-Timer aufgerufen, um die Stage-Anwendung zu garantieren.
    procedure FrameResize(Sender: TObject);
    // Klick auf Stat-Kachel: setzt Severity-/Type-Filter passend (z.B.
    // Errors-Kachel -> FFilterCombo zeigt nur Errors). Sender.Tag traegt
    // den TFilterMode bzw. TTypeFilter-Ordinal.
    procedure TileClickSeverity(Sender: TObject);
    procedure TileClickType(Sender: TObject);
    procedure TileClickClear(Sender: TObject);
    procedure PopulateFindings(const findings: TObjectList<TLeakFinding>;
      const BaseDir: string);
    procedure UpdateStats;
    procedure ApplyFilter;
    // Schreibt FDisplayedFindings ins Grid (6 Spalten pro Zeile). Bei
    // leerer Liste erscheint ein Platzhalter-Text in Zeile 1.
    procedure PopulateGridFromDisplayed;
    // Statusbar-Update nach ApplyFilter: zeigt n/m findings + Filter-Text.
    procedure UpdateFilterStatus(const Criteria: TFindingFilterCriteria);
    // Erzeugt einen vollstaendigen Markdown-Prompt fuer Claude AI: Befund-
    // Metadaten, FixHint (Vorher/Nachher) und Code-Auszug aus der Quelldatei.
    function  BuildClaudePrompt(F: TLeakFinding): string;
    procedure CopyFindingToClipboard(F: TLeakFinding);
    procedure UpdateHelp(Row: Integer);
    // Sammelt alle Befunde aus FDisplayedFindings die zur gleichen Datei
    // gehoeren und uebergibt sie als komplette Marker-Liste an den
    // GHighlighter (Multi-Marker-Modell). Wird bei Klick/Doppelklick auf
    // einen Befund gerufen.
    procedure HighlightAllFindingsInFile(const AFileName: string);
    class function FixHint(const Finding: TLeakFinding): TFixHint; static;
    function OpenFileAtLine(const AbsPath: string;
                            LineNumber: Integer): TOpenFileMode;
    procedure LoadRecentPaths;
    procedure SaveRecentPath(const APath: string);
  protected
    // IDE-Theme-Integration (Notifier + Refresh-Pfade) ist nach
    // uIDEThemeIntegration.TIDEThemeIntegration ausgelagert. Frame
    // haelt nur noch die Helper-Instanz und die zwei Hooks die
    // klassen-gebunden bleiben muessen (CMStyleChanged-Message-
    // Handler + SetParent-Override).
    FThemeIntegration : TIDEThemeIntegration;
    // Reagiert auf VCL-Style-Wechsel (= IDE-Theme-Wechsel). Erzwingt
    // Re-Paint, damit die ueber clBtnFace/clWindow/StyleServices spaet
    // aufgeloesten Farben mit dem neuen Theme neu gezeichnet werden.
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
    // SetParent override - feuert beim Dock <-> Float-Wechsel oder beim
    // ersten Hosting des Frames. Style-Hooks ueberleben den Wechsel oft
    // nicht (neuer Top-Level-Window-Kontext), daher Theme erneut
    // applizieren. Postet ausserdem WM_SCA_REFIT fuer deferred FrameResize
    // (IDE setzt Bounds NACH SetParent; csLoading kann VCL.Resize-Override
    // ueberspringen).
    procedure SetParent(AParent: TWinControl); override;
    // Deferred FrameResize nach abgeschlossenem IDE-Dock-Vorgang.
    // SetParent postet WM_SCA_REFIT; zu diesem Zeitpunkt sind Bounds
    // korrekt gesetzt und csLoading ist geloescht.
    procedure WMScaRefit(var Message: TMessage); message WM_SCA_REFIT;
    // Wird nach jedem Theme-Refresh als Callback vom Helper aufgerufen.
    // Triggert den TStringGrid-Repaint, der ueber die rekursive
    // Invalidate nicht zuverlaessig vom Paint-Cache abgeholt wird.
    procedure RepaintGridAfterTheme;
  public
    FProjectPath : TComboBox;
    FResultGrid  : TStringGrid;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Resize; override;
    // Delegiert auf FThemeIntegration.RefreshFromIDETheme. Public,
    // damit auch externer Code (oder Tests) einen Theme-Refresh
    // erzwingen kann, ohne den Helper direkt anzufassen.
    procedure RefreshFromIDETheme;
    // Liefert die aktuelle Profile-Combo-Auswahl als String, oder leer
    // wenn der Frame keinen Override hat. Der Silent-Mode-Entrypoint
    // ruft das so dass eine im Dock geaenderte Profile-Wahl auch ohne
    // INI-Save fuer Silent-Runs gilt (analog Dock-PrepareAnalysis).
    function CurrentProfileOverride: string;
  end;

  TAnalyserDockableForm = class(TInterfacedObject, INTACustomDockableForm)
  private
    FFrame: TAnalyserFrame;
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    procedure ViewMenuClick(Sender: TObject);
    // Klickhandler des "Analyse current file (silent)"-Eintrags im
    // View > Static Code Analysis-Submenu (+ Hotkey Ctrl+Alt+A).
    // Triggert Silent-Mode: aktuelle Editor-Datei analysieren + Marker
    // direkt setzen, OHNE Dock-Fenster zu oeffnen.
    procedure AnalyseCurrentFromEditorMenuClick(Sender: TObject);
    property Frame: TAnalyserFrame read FFrame;
  end;

var
  GDockableForm: TAnalyserDockableForm;

procedure RegisterAnalyserDockableForm;
procedure UnregisterAnalyserDockableForm;
procedure ShowAnalyserDockableForm;

implementation

{$R *.dfm}

type
  // Access-Class zum Setzen protected-deklarierter Properties (TControl.OnClick).
  // Lokal in der Unit gehalten - kein public API. Standard-VCL-Pattern.
  TControlAccess = class(TControl);

const
  // ---- 3-Stufen-Responsive-Layout (96-DPI-logisch, via ScaleW skaliert) -
  //
  // Stufe 1 (NARROW, < BREAKPOINT_MEDIUM = 500):
  //   Nur die 4 essential Stats-Tiles (Errors/Warnings/Hints/Code Quality).
  //   Hamburger sichtbar (Aktionen via Menu). Filter-Labels weg.
  //   Settings/Ignore/Cancel/Branch-Changes/Search-Lbl alle hidden.
  //   Typisch: schmal gedockt im IDE-Tool-Window.
  //
  // Stufe 2 (MEDIUM, >= 500 .. < BREAKPOINT_FULL = 850):
  //   Komplette Tile-Reihe (alle 9 Tiles) sichtbar. Filter-/Type-Labels
  //   sichtbar. Settings/Ignore/Cancel/Export/Branch-Changes/Search-Label
  //   bleiben hidden -> Hamburger bleibt sichtbar fuer diese Aktionen.
  //   Tile-Reihe braucht abhaengig von TILE_W in uIDEStatsTiles entsprechend
  //   Platz; ueberzaehlige werden vom alLeft-Layout ggf. beschnitten
  //   (akzeptabel).
  //
  // Stufe 3 (FULL, >= BREAKPOINT_FULL = 850):
  //   Volle UI: alle 9 Tiles + komplette Toolbar. Hamburger weg
  //   (alle Aktionen direkt erreichbar). Branch-Changes + Search-Lbl sichtbar.
  //
  // BREAKPOINT_MEDIUM dient gleichzeitig als FLOAT_MIN_WIDTH: das floated
  // Fenster wird via Constraints.MinWidth auf 500 px begrenzt - schmaler
  // ergibt im Float-Mode visuell keinen Sinn (zu wenig fuer einen Toolbar).
  BREAKPOINT_MEDIUM = 500;
  BREAKPOINT_FULL   = 850;
  // Backward-compat-Alias: alter Code referenziert BREAKPOINT_DOCKED.
  // Semantisch = BREAKPOINT_FULL (oberhalb keine docked-style Elemente).
  BREAKPOINT_DOCKED = BREAKPOINT_FULL;
  // Floated-Form Mindestbreite (= MEDIUM-Schwelle): unter 500 px ergibt
  // floated keinen Sinn (Stufe-1-Layout ist nur fuer enge Docks gedacht).
  FLOAT_MIN_WIDTH   = BREAKPOINT_MEDIUM;

  // ---- Toolbar-Layout (alle Werte werden via ScaleW DPI-skaliert) -------
  // Strategie: Control-Hoehe wird zur Laufzeit aus Self.Font abgeleitet
  // (TToolbarSizing.HeightForFont) - so passt sich die Toolbar automatisch
  // an Font-Size-Aenderungen an (8pt -> 22 px, 9pt -> 23 px, 10pt -> 24 px).
  // Panel-Hoehe = Ctrl-Hoehe + 2*Padding; lokale Variable im Constructor
  // verteilt diese beiden Werte (UnifCtrlH, ToolbarRowH) an die Panel-Setup-
  // und TToolbarSizing.Apply-Aufrufstellen.
  TB_PADDING_LR      = 6;      // Padding links/rechts in Toolbar-Panels
  TB_PADDING_TB      = 1;      // Padding oben/unten in Toolbar-Panels
  TB_SPACER_WIDTH    = 8;      // Trennabstand zwischen Bereichen
  TB_CANCEL_MARGIN   = 12;     // Margin links vom Cancel-Button (visuell vom Edit absetzen)

  // ---- Button-Widths ----------------------------------------------------
  // Captions passen mit Segoe UI 8pt + ~4-6 px Innenpadding. Im NARROW/MEDIUM
  // ist ein Teil ueber FResponsive ausgeblendet - siehe RegisterCtrl-Block.
  BTN_W_ICON         = 32;     // Icon-only (Browse "...", Hamburger ☰, Branch-Changes ⎇)
  BTN_W_SHORT        = 56;     // "Ignore..."
  BTN_W_MED_SHORT    = 64;     // "Settings..."
  BTN_W_MED          = 68;     // "Cancel", "Export"
  BTN_W_MED_LONG     = 48;     // "📄 File"
  BTN_W_LONG         = 64;     // "▶ Analyse"

  // ---- Label-Widths -----------------------------------------------------
  LBL_W_PATH         = 78;     // "Project path:"
  LBL_W_FILTER       = 76;     // "Severity:"
  LBL_W_TYPE         = 36;     // "Type:"
  LBL_W_PROFILE      = 48;     // "Profile:"
  LBL_W_SEARCH       = 32;     // "Search:"

  // ---- Combo-Widths (innerhalb der Sub-Panel-Container) -----------------
  CMB_W_FILTER       = 160;    // Severity-Combo
  CMB_W_TYPE         = 130;    // Type-Combo
  CMB_W_PROFILE      = 110;    // Profile-Combo (ide-fast, default, strict)

  // ---- Stats-Panel ------------------------------------------------------
  STATS_PANEL_HEIGHT = 45;     // 1 Tile-Reihe (TopRow 20 + Caption 12 + Padding)
  STATS_PADDING      = 4;

  // ---- Misc -------------------------------------------------------------
  PROGRESS_HEIGHT    = 14;
  GRID_MIN_HEIGHT    = 120;
  GRID_MIN_WIDTH     = 300;
  // Floated: SearchEdit hat genug Platz, MinWidth grosszuegig.
  // Docked: nur Cancel + Export + SearchEdit + Hamburger sichtbar -
  // SearchEdit darf weiter schrumpfen damit auch 300-px-Docks passen.
  SEARCH_MIN_WIDTH_FLOATED = 120;
  SEARCH_MIN_WIDTH_DOCKED  =  60;

// MAX_RECENT lebt in uRecentPaths (DEFAULT_MAX_RECENT = 3); konsistent
// zwischen IDE und Standalone, kein Drift mehr.
// Severity- und Akzentfarben sind in uAnalyserPalette zentral definiert
// und werden ueber uAnalyserTheme.SeverityBg / SeverityAccent (mit
// TFindingSeverity-Enum) abgerufen.

// Sentinel fuer Frame-Lifecycle-Race in der Worker-Anonymous-Method:
// TAnalyseRunner.RunAll/RunChanged uebergeben Closures die ProgressBar /
// AnalyseProgress / StatusMode-Callbacks ueber den Runner-Self captured
// halten. Wenn der User waehrend der Analyse das IDE-Dock-Fenster
// schliesst, wird das Frame-Objekt zerstoert - die Closure haelt aber
// noch eine ungueltige Self-Referenz und greift bei Application.
// ProcessMessages-Reentry darauf zu (AV in ein freies Heap-Block).
//
// Schutzmassnahme: globaler Pointer der genau auf den aktuell lebenden
// Frame zeigt. Constructor setzt ihn auf Self, Destructor auf nil.
// Closures snapshoten den Frame-Pointer in eine LOKALE Variable
// (anonymous-method-Capture-by-Value) und vergleichen sie pro Iteration
// gegen GLiveAnalyserFrame. Bei Mismatch (Frame zerstoert oder anderer
// Frame aktiv) sofort Abort ohne Field-Zugriff.
//
// Funktioniert weil der Pointer-VERGLEICH safe ist auch wenn Self auf
// invaliden Speicher zeigt - es wird kein Feld dereferenziert.
//
// GLiveAnalyserFrame lebt in uIDELifecycle (gemeinsam mit TAnalyseRunner
// nutzbar ohne uses-Zyklus).

// Einfacher Verlauf von AFrom (oben) nach ATo (unten)
procedure GradientFillRect(Canvas: TCanvas; R: TRect; AFrom, ATo: TColor;
  Vertical: Boolean);
var
  tv: array[0..1] of TRIVERTEX;
  gr: GRADIENT_RECT;
begin
  tv[0].x     := R.Left;
  tv[0].y     := R.Top;
  tv[0].Red   := GetRValue(ColorToRGB(AFrom)) shl 8;
  tv[0].Green := GetGValue(ColorToRGB(AFrom)) shl 8;
  tv[0].Blue  := GetBValue(ColorToRGB(AFrom)) shl 8;
  tv[0].Alpha := 0;
  tv[1].x     := R.Right;
  tv[1].y     := R.Bottom;
  tv[1].Red   := GetRValue(ColorToRGB(ATo)) shl 8;
  tv[1].Green := GetGValue(ColorToRGB(ATo)) shl 8;
  tv[1].Blue  := GetBValue(ColorToRGB(ATo)) shl 8;
  tv[1].Alpha := 0;
  gr.UpperLeft  := 0;
  gr.LowerRight := 1;
  if Vertical then
    GradientFill(Canvas.Handle, @tv, 2, @gr, 1, GRADIENT_FILL_RECT_V)
  else
    GradientFill(Canvas.Handle, @tv, 2, @gr, 1, GRADIENT_FILL_RECT_H);
end;

function GetIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(
    GetEnvironmentVariable('APPDATA')) +
    'StaticCodeAnalyser\recent.ini';
end;

// Backward-compat-Wrapper - liefert das aktive IDE-Projekt-Verzeichnis.
// Logik liegt jetzt in uIDEEditorIntegration.TIDEEditor (saubere
// Supports-Casts statt as-Cast der bei nil-Service AV werfen wuerde).
function GetCurrentIDEProjectDir: string;
begin
  Result := TIDEEditor.GetCurrentProjectDir;
end;

{ TIDEAnalyserForm }

constructor TAnalyserFrame.Create(AOwner: TComponent);
var
  PanelPath, PanelButtons, PanelClient: TPanel;
  // Theming-Service-Vars werden in FrameCreated genutzt; hier nur Default fuer
  // den Notifier-Index setzen, damit Destroy nicht versucht, einen ungueltigen
  // Index abzumelden falls der Service nie verfuegbar war.
  LblPath: TLabel;
  BtnBrowse, BtnAnalyse: TButton;
  // Aus Font abgeleitete Hoehen, einmalig nach Font-Setup berechnet:
  //   UnifCtrlH   - Soll-Hoehe fuer alle Toolbar-Controls (Button/Edit/Combo)
  //   ToolbarRowH - Panel-Hoehe = UnifCtrlH + 2*TB_PADDING_TB
  UnifCtrlH, ToolbarRowH: Integer;
begin
  inherited Create(AOwner);
  // Lifecycle-Sentinel registrieren: ab jetzt darf der Worker-Callback
  // auf Self-Felder zugreifen (siehe GLiveAnalyserFrame oben).
  GLiveAnalyserFrame := Pointer(Self);

  // Settings VOR dem ersten _()-UI-Aufruf laden, damit die UI-Sprache aus
  // analyser.ini [UI]/Language gleich beim ersten Caption-Build gilt.
  // Bei Fehlern: Fallback auf 'de' aus dem Default-Constructor.
  FRepoSettings := TRepoSettings.Create;
  try FRepoSettings.Load; except end;
  SetLanguage(FRepoSettings.Language);
  // Custom-LeakyClasses + Excludes + AutoDiscover-Flag durchreichen
  try
    FRepoSettings.RegisterToLeakyClasses;
    AutoDiscoverCustomClasses := FRepoSettings.AutoDiscoverClasses;
  except end;

  // IDE-Theme-Helper: registriert sich spaeter via Attach (in
  // TAnalyserDockableForm.FrameCreated). RepaintGridAfterTheme wird
  // nach jedem Refresh vom Helper zurueckgerufen.
  FThemeIntegration := TIDEThemeIntegration.Create(Self, Self, RepaintGridAfterTheme);

  // Frame folgt dem aktiven IDE-Theme: clBtnFace ist der Standard-Chrome-
  // Hintergrund (hell im Light-Theme, dunkel im Dark-Theme, korrekt in
  // Mountain Mist/Carbon/Custom-Themes).
  Color         := clBtnFace;
  ParentFont    := False;
  Font.Name     := 'Segoe UI';
  Font.Size     := 8;

  // Toolbar-Hoehen aus Font ableiten. Font.Height ist negativ in Pixel und
  // bereits DPI-aware (=  -PointSize * CurrentPPI / 72) - kein extra ScaleW.
  // ToolbarRowH = UnifCtrlH + 2*Padding (mit ScaleW da TB_PADDING_TB
  // ein 96-DPI-logischer Wert ist).
  UnifCtrlH   := TToolbarSizing.HeightForFont(Font);
  ToolbarRowH := UnifCtrlH + 2 * ScaleW(TB_PADDING_TB);
  // Default-Groesse: muss alle Top-Panels + Help-Panel + 120 px Grid +
  // Statusbar aufnehmen. Status 22 + Stats 45 + 3*Toolbar 24 + Help 120 +
  // Splitter 4 + Grid 120 = ~383 minimum. Mit Reserve auf 470/500.
  Height                  := 500;
  Constraints.MinHeight   := 470;
  // Floated-Mindestbreite: unter 500 px ergibt der Toolbar visuell keinen
  // Sinn (auch der MEDIUM-Tier des Responsive-Layouts startet bei 500 px).
  // Die Constraint wird in TAnalyserDockableForm.FrameCreated zusaetzlich
  // auf das Host-Form propagiert, damit der IDE-Floating-Container die
  // Mindestbreite ebenfalls respektiert.
  Constraints.MinWidth    := ScaleW(FLOAT_MIN_WIDTH);
  FAllFindings       := TObjectList<TLeakFinding>.Create(True);
  FDisplayedFindings := TList<TLeakFinding>.Create;
  // Ignore-Liste laden / Default-Datei anlegen falls nicht vorhanden
  FIgnoreList        := TIgnoreList.Create;
  try FIgnoreList.LoadDefault; except end;
  // FRepoSettings wurde bereits oben (vor SetLanguage) initialisiert.
  FFilterMode        := fmAll;
  // Default-Sort: Severity-Spalte (5) aufsteigend - Fehler oben, Hinweise unten.
  FSortColumn        := 5;
  FSortDescending    := False;

  // ---- Statusleiste mit 3 Panels (Findings / Progress / Mode) ----
  // Setup + Push-Methoden in uIDEStatusBar.TAnalyserStatusBar gekapselt.
  FStatusBar := TAnalyserStatusBar.Create(Self, Self);
  FStatusBar.Mode(_('Ready.'));

  // ---- Fortschrittsbalken (nur waehrend Analyse sichtbar) -----------------
  // Liegt zwischen Top-Panels und Statusbar - alBottom oberhalb der Statusbar.
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent  := Self;
  FProgressBar.Align   := alBottom;
  FProgressBar.Height  := ScaleW(PROGRESS_HEIGHT);
  FProgressBar.Min     := 0;
  FProgressBar.Max     := 100;
  FProgressBar.Smooth  := True;
  // Immer sichtbar, damit das Grid bei Start/Ende der Analyse nicht
  // springt. Im Idle-Zustand bleibt der Balken einfach leer (Pos 0).
  FProgressBar.Visible := True;

  // ---- Zeile: Projektpfad ----
  PanelPath := TPanel.Create(Self);
  PanelPath.Parent      := Self;
  PanelPath.Align       := alTop;
  PanelPath.Height      := ToolbarRowH;
  PanelPath.BevelOuter  := bvNone;
  PanelPath.Color       := clBtnFace;
  // Right padding=0: alRight-Button (Browse "...") sitzt buendig am rechten
  // Panel-Rand statt mit 6 px Inset - matched optisch mit dem Hamburger auf
  // PanelSearch und mit der Combo-rechts-Kante.
  PanelPath.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                              0, ScaleW(TB_PADDING_TB));
  FPanelPath := PanelPath;

  LblPath := TLabel.Create(Self);
  LblPath.Parent    := PanelPath;
  LblPath.Caption   := _('Project path:');
  LblPath.Align     := alLeft;
  LblPath.Layout    := tlCenter;
  LblPath.Width     := ScaleW(LBL_W_PATH);

  BtnBrowse := TButton.Create(Self);
  BtnBrowse.Parent  := PanelPath;
  BtnBrowse.Caption := '...';
  BtnBrowse.Width   := ScaleW(BTN_W_ICON);
  BtnBrowse.Align   := alRight;
  BtnBrowse.OnClick := BrowseClick;

  // Ignore-Liste editieren - oeffnet ignore.txt im Notepad/Default-Editor
  FBtnIgnore := TButton.Create(Self);
  FBtnIgnore.Parent  := PanelPath;
  FBtnIgnore.Caption := _('Ignore...');
  FBtnIgnore.Width   := ScaleW(BTN_W_SHORT);
  FBtnIgnore.Align   := alRight;
  FBtnIgnore.Hint    := _('Open ignore list (which files are NOT analysed)');
  FBtnIgnore.ShowHint := True;
  FBtnIgnore.OnClick := EditIgnoreListClick;

  // Settings-Datei analyser.ini (BaseBranch + Tortoise-Pfade fuer
  // Branch-Changes, Custom-LeakyClasses fuer den MemoryLeak-Detektor).
  FBtnRepo := TButton.Create(Self);
  FBtnRepo.Parent  := PanelPath;
  FBtnRepo.Caption := _('Settings...');
  FBtnRepo.Width   := ScaleW(BTN_W_MED_SHORT);
  FBtnRepo.Align   := alRight;
  FBtnRepo.Hint    := _('Open analyser.ini (BaseBranch, git/svn paths, custom LeakyClasses)');
  FBtnRepo.ShowHint := True;
  FBtnRepo.OnClick := EditRepoSettingsClick;


  FProjectPath := TComboBox.Create(Self);
  FProjectPath.Parent      := PanelPath;
  FProjectPath.Align       := alClient;
  FProjectPath.Style       := csDropDown;
  FProjectPath.ParentFont  := False;
  FProjectPath.Font.Name   := 'Segoe UI';
  FProjectPath.Font.Size   := 8;

  // ---- Zeile: Buttons ----
  PanelButtons := TPanel.Create(Self);
  PanelButtons.Parent      := Self;
  PanelButtons.Align       := alTop;
  PanelButtons.Height      := ToolbarRowH;
  PanelButtons.BevelOuter  := bvNone;
  PanelButtons.Color       := clBtnFace;
  // Right padding=0: konsistente rechte Kante mit PanelPath/PanelSearch,
  // auch wenn diese Zeile selbst keine alRight-Buttons hat - Comboboxen
  // schliessen optisch in derselben rechten Spalte ab.
  PanelButtons.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                                 0, ScaleW(TB_PADDING_TB));
  FPanelButtons := PanelButtons;

  // Aktions-Buttons (Analyse starten / Aktuelle Datei) liegen nicht hier,
  // sondern in PanelSearch zusammen mit den Export-Buttons. Damit bleibt
  // diese Filter-Zeile uebersichtlich.

  // Severity-Filter: Label + Combo in einem eigenen Panel-Container.
  // Mit losem alLeft auf PanelButtons direkt verschoben sich Label und
  // Combo gegeneinander (TLabel ist TGraphicControl, TComboBox ist
  // TWinControl - VCL aligned die in unterschiedlichen Passes); im
  // Sub-Panel laufen sie strikt von links nach rechts.
  FPanelSev := TPanel.Create(Self);
  FPanelSev.Parent     := PanelButtons;
  FPanelSev.Align      := alLeft;
  FPanelSev.BevelOuter := bvNone;
  FPanelSev.Color      := clBtnFace;
  FPanelSev.Width      := ScaleW(LBL_W_FILTER + CMB_W_FILTER);

  FLblFilter := TLabel.Create(Self);
  FLblFilter.Parent   := FPanelSev;
  FLblFilter.Caption  := _('Severity:');
  FLblFilter.Align    := alLeft;
  FLblFilter.AutoSize := False;
  FLblFilter.Width    := ScaleW(LBL_W_FILTER);
  FLblFilter.Layout   := tlCenter;

  // Filter-Dropdown - nach Schweregrad gruppiert.
  // Items.Objects haelt den Ord(TFilterMode) als Tag; Separatoren haben Tag = -1
  // und werden in FilterChange auf "Alle" zurueckgesetzt.
  FFilterCombo := TComboBox.Create(Self);
  FFilterCombo.Parent      := FPanelSev;
  FFilterCombo.Style       := csDropDownList;
  FFilterCombo.Align       := alClient;
  FFilterCombo.Font.Name   := 'Segoe UI';
  FFilterCombo.Font.Size   := 8;
  FFilterCombo.ParentFont  := False;
  FFilterCombo.OnChange    := FilterChange;

  // Hilfsmethode-Inline ueber Lambdas geht in Delphi nicht - direkt schreiben.
  FFilterCombo.Items.AddObject(_('All'),                    TObject(Ord(fmAll)));
  FFilterCombo.Items.AddObject(_('Errors (all)'),           TObject(Ord(fmErrors)));
  FFilterCombo.Items.AddObject(_('Warnings (all)'),         TObject(Ord(fmWarnings)));
  FFilterCombo.Items.AddObject(_('Hints (all)'),            TObject(Ord(fmHints)));

  FFilterCombo.Items.AddObject(_('--- Errors ---'),         TObject(-1));
  FFilterCombo.Items.AddObject(_('Memory Leak'),            TObject(Ord(fmMemoryLeak)));
  FFilterCombo.Items.AddObject(_('SQL Injection'),          TObject(Ord(fmSQLInjection)));
  FFilterCombo.Items.AddObject(_('Hardcoded Secrets'),      TObject(Ord(fmHardcodedSecret)));
  FFilterCombo.Items.AddObject(_('Format()'),               TObject(Ord(fmFormatMismatch)));
  FFilterCombo.Items.AddObject(_('Nil-Deref'),              TObject(Ord(fmNilDeref)));
  FFilterCombo.Items.AddObject(_('Div by Zero'),            TObject(Ord(fmDivByZero)));

  FFilterCombo.Items.AddObject(_('--- Warnings ---'),       TObject(-1));
  FFilterCombo.Items.AddObject(_('Empty Except'),           TObject(Ord(fmEmptyExcept)));
  FFilterCombo.Items.AddObject(_('Missing Finally'),        TObject(Ord(fmMissingFinally)));
  FFilterCombo.Items.AddObject(_('Dead Code'),              TObject(Ord(fmDeadCode)));
  FFilterCombo.Items.AddObject(_('Unused Uses'),            TObject(Ord(fmUnusedUses)));
  FFilterCombo.Items.AddObject(_('Debug Output'),           TObject(Ord(fmDebugOutput)));
  FFilterCombo.Items.AddObject(_('Hardcoded Path'),         TObject(Ord(fmHardcodedPath)));
  FFilterCombo.Items.AddObject(_('Read Error'),             TObject(Ord(fmFileReadError)));

  FFilterCombo.Items.AddObject(_('--- Hints ---'),          TObject(-1));
  FFilterCombo.Items.AddObject(_('Long Method'),            TObject(Ord(fmLongMethod)));
  FFilterCombo.Items.AddObject(_('Many Parameters'),        TObject(Ord(fmLongParamList)));
  FFilterCombo.Items.AddObject(_('Magic Number'),           TObject(Ord(fmMagicNumber)));
  FFilterCombo.Items.AddObject(_('Duplicate Strings'),      TObject(Ord(fmDuplicateString)));
  FFilterCombo.Items.AddObject(_('Duplicate Code Blocks'),  TObject(Ord(fmDuplicateBlock)));
  FFilterCombo.Items.AddObject(_('Deep Nesting'),           TObject(Ord(fmDeepNesting)));
  FFilterCombo.Items.AddObject(_('Cyclomatic Complexity'),  TObject(Ord(fmCyclomaticComplexity)));
  FFilterCombo.Items.AddObject(_('TODO/FIXME'),             TObject(Ord(fmTodoComment)));
  FFilterCombo.Items.AddObject(_('Empty Methods'),          TObject(Ord(fmEmptyMethod)));
  FFilterCombo.Items.AddObject(_('Can Be Private'),         TObject(Ord(fmCanBePrivate)));
  FFilterCombo.Items.AddObject(_('Can Be Protected'),       TObject(Ord(fmCanBeProtected)));
  FFilterCombo.Items.AddObject(_('Unused Public Member'),   TObject(Ord(fmUnusedPublicMember)));
  FFilterCombo.Items.AddObject(_('Unused Local Var'),       TObject(Ord(fmUnusedLocalVar)));
  FFilterCombo.Items.AddObject(_('Unused Parameter'),       TObject(Ord(fmUnusedParameter)));
  FFilterCombo.Items.AddObject(_('Tautological Expression'),TObject(Ord(fmTautologicalBoolExpr)));
  FFilterCombo.Items.AddObject(_('Master-Detail Unlinked'), TObject(Ord(fmDfmMasterDetailUnlinked)));
  FFilterCombo.Items.AddObject(_('Data Module Split Hint'), TObject(Ord(fmDfmDataModuleSplitHint)));
  FFilterCombo.Items.AddObject(_('Dangerous SQL Statement'),TObject(Ord(fmSqlDangerousStatement)));
  FFilterCombo.Items.AddObject(_('Format Locale Hint'),     TObject(Ord(fmFormatLocaleHint)));

  FFilterCombo.ItemIndex := 0; // "All"

  // Trennabstand
  var SepF1 := TPanel.Create(Self);
  SepF1.Parent     := PanelButtons;
  SepF1.Align      := alLeft;
  SepF1.Width      := ScaleW(TB_SPACER_WIDTH);
  SepF1.BevelOuter := bvNone;
  SepF1.Color      := clBtnFace;

  // ---- Zweiter Filter: Typ (Sonar-Kategorie) - gleicher Container-Trick ----
  FPanelType := TPanel.Create(Self);
  FPanelType.Parent     := PanelButtons;
  FPanelType.Align      := alLeft;
  FPanelType.BevelOuter := bvNone;
  FPanelType.Color      := clBtnFace;
  FPanelType.Width      := ScaleW(LBL_W_TYPE + CMB_W_TYPE);

  FLblType := TLabel.Create(Self);
  FLblType.Parent   := FPanelType;
  FLblType.Caption  := _('Type:');
  FLblType.Align    := alLeft;
  FLblType.AutoSize := False;
  FLblType.Width    := ScaleW(LBL_W_TYPE);
  FLblType.Layout   := tlCenter;

  FTypeCombo := TComboBox.Create(Self);
  FTypeCombo.Parent      := FPanelType;
  FTypeCombo.Style       := csDropDownList;
  FTypeCombo.Align       := alClient;
  FTypeCombo.Font.Name   := 'Segoe UI';
  FTypeCombo.Font.Size   := 8;
  FTypeCombo.ParentFont  := False;
  FTypeCombo.OnChange    := TypeFilterChange;
  FTypeCombo.Items.Add(_('All'));
  FTypeCombo.Items.Add('Bug');
  FTypeCombo.Items.Add('Code Smell');
  FTypeCombo.Items.Add('Vulnerability');
  FTypeCombo.Items.Add('Security Hotspot');
  FTypeCombo.Items.Add('Code Duplication');
  FTypeCombo.ItemIndex := 0;
  FTypeFilter := tfAll;

  // Trennabstand vor Profile-Combo
  var SepProfile := TPanel.Create(Self);
  SepProfile.Parent     := PanelButtons;
  SepProfile.Align      := alLeft;
  SepProfile.Width      := ScaleW(TB_SPACER_WIDTH);
  SepProfile.BevelOuter := bvNone;
  SepProfile.Color      := clBtnFace;

  // ---- Dritter Filter: Profile (rule-set scope) ----------------------------
  // Schreibt FRepoSettings.IdeProfile (transient, kein INI-Save). Items werden
  // aus rules/sca-rules.json -> profiles geholt; default-Selektion ist der
  // INI-Wert (typisch 'ide-fast' im IDE, 'default' im Standalone). Wirkt erst
  // beim naechsten Analyse-Run (PrepareAnalysis ruft UseIdeRuleSet +
  // ApplyDetectorThresholds).
  FPanelProfile := TPanel.Create(Self);
  FPanelProfile.Parent     := PanelButtons;
  FPanelProfile.Align      := alLeft;
  FPanelProfile.BevelOuter := bvNone;
  FPanelProfile.Color      := clBtnFace;
  FPanelProfile.Width      := ScaleW(LBL_W_PROFILE + CMB_W_PROFILE);

  FLblProfile := TLabel.Create(Self);
  FLblProfile.Parent   := FPanelProfile;
  FLblProfile.Caption  := _('Profile:');
  FLblProfile.Align    := alLeft;
  FLblProfile.AutoSize := False;
  FLblProfile.Width    := ScaleW(LBL_W_PROFILE);
  FLblProfile.Layout   := tlCenter;

  FProfileCombo := TComboBox.Create(Self);
  FProfileCombo.Parent      := FPanelProfile;
  FProfileCombo.Style       := csDropDownList;
  FProfileCombo.Align       := alClient;
  FProfileCombo.Font.Name   := 'Segoe UI';
  FProfileCombo.Font.Size   := 8;
  FProfileCombo.ParentFont  := False;
  FProfileCombo.OnChange    := ProfileChange;
  FProfileCombo.Hint        := _('Rule-set profile (ide-fast / default / strict). ' +
                                 'Takes effect at the next analysis run.');
  FProfileCombo.ShowHint    := True;
  // Items aus TRuleCatalog.ProfileNames (rules/sca-rules.json -> profiles).
  // FRepoSettings.Load lief schon in FrameCreate (siehe oben), daher koennen
  // wir die Default-Selektion direkt setzen. Fallback wenn der Catalog leer
  // ist (z.B. JSON fehlt): ein 'default'-Eintrag, damit die UI nicht crashed.
  begin
    var ProfileList := TRuleCatalog.ProfileNames;
    if Length(ProfileList) = 0 then
      FProfileCombo.Items.Add(_('default'))
    else
      for var ProfileName in ProfileList do
        FProfileCombo.Items.Add(ProfileName);

    // Default = IdeProfile aus der INI (Frame laeuft im IDE-Plugin).
    // Wenn der INI-Wert nicht im Catalog ist: erste verfuegbare Option.
    var Idx := FProfileCombo.Items.IndexOf(FRepoSettings.IdeProfile);
    if Idx < 0 then Idx := FProfileCombo.Items.IndexOf('ide-fast');
    if Idx < 0 then Idx := 0;
    FProfileCombo.ItemIndex := Idx;
  end;

  // Trennabstand zur Checkbox
  var Sep2 := TPanel.Create(Self);
  Sep2.Parent     := PanelButtons;
  Sep2.Align      := alLeft;
  Sep2.Width      := ScaleW(TB_SPACER_WIDTH);
  Sep2.BevelOuter := bvNone;
  Sep2.Color      := clBtnFace;

  // UsesCheck und IncludeTests werden jetzt aus analyser.ini [Detectors]
  // gelesen - keine Checkboxen mehr in der Toolbar (siehe FRepoSettings).

  // ---- Zeile: Aktionen + Suche + Export ----
  var PanelSearch := TPanel.Create(Self);
  PanelSearch.Parent      := Self;
  PanelSearch.Align       := alTop;
  PanelSearch.Height      := ToolbarRowH;
  PanelSearch.BevelOuter  := bvNone;
  PanelSearch.Color       := clBtnFace;
  // Right padding=0: Hamburger sitzt buendig am rechten Panel-Rand statt
  // mit 6 px Inset. Matched optisch mit Browse "..." auf PanelPath.
  PanelSearch.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                                0, ScaleW(TB_PADDING_TB));
  FPanelSearch := PanelSearch;

  // Action-Buttons links - "▶ Analyse" zuerst (links), dann "📄 File"
  BtnAnalyse := TButton.Create(Self);
  BtnAnalyse.Parent   := PanelSearch;
  BtnAnalyse.Caption  := _('▶ Analyse');
  BtnAnalyse.Width    := ScaleW(BTN_W_LONG);
  BtnAnalyse.Align    := alLeft;
  BtnAnalyse.OnClick  := AnalyseClick;
  FBtnAnalyse := BtnAnalyse;

  FBtnAnalyseCurrent := TButton.Create(Self);
  FBtnAnalyseCurrent.Parent   := PanelSearch;
  FBtnAnalyseCurrent.Caption  := _('📄 File');
  FBtnAnalyseCurrent.Width    := ScaleW(BTN_W_MED_LONG);
  FBtnAnalyseCurrent.Align    := alLeft;
  FBtnAnalyseCurrent.OnClick  := AnalyseCurrentFileClick;

  // Branch-Aenderungen via Git/SVN: nur die im Branch geaenderten .pas-Files.
  // Icon-only (Glyph ⎇ U+2387 "alternative"-Symbol, sieht wie Branch-Fork aus),
  // matcht visuell die anderen Icon-Buttons (Browse "...", Hamburger ☰).
  // Caption-Text "Branch-Changes" ist im Hint und im Hamburger-Menu.
  FBtnAnalyseChanged := TButton.Create(Self);
  FBtnAnalyseChanged.Parent   := PanelSearch;
  FBtnAnalyseChanged.Caption  := #$2387; // ⎇
  FBtnAnalyseChanged.Width    := ScaleW(BTN_W_ICON);
  FBtnAnalyseChanged.Align    := alLeft;
  FBtnAnalyseChanged.OnClick  := AnalyseChangedFilesClick;
  FBtnAnalyseChanged.Hint     := _('Branch-Changes') + ': ' + _(
    'Analyses only files changed in the current branch ' +
    '(Git: branch diff vs main + working tree; SVN: working copy)');
  FBtnAnalyseChanged.ShowHint := True;

  // Hamburger-Button: ganz rechts in PanelSearch. Als erstes alRight-
  // Control hinzugefuegt -> VCL platziert es am rechten Rand; Cancel und
  // Export landen links davon. Nur im Docked-Modus sichtbar (Inverse-
  // Controller weiter unten). PopupMenu + OnClick via BuildHamburgerMenu.
  FBtnHamburger := TButton.Create(Self);
  FBtnHamburger.Parent   := PanelSearch;
  FBtnHamburger.Caption  := #$2630; // Trigram for Heaven (Hamburger-Glyph)
  FBtnHamburger.Width    := ScaleW(BTN_W_ICON);
  FBtnHamburger.Align    := alRight;
  FBtnHamburger.Hint     := _('All toolbar actions (Analyse, Browse, Export, Settings, ...)');
  FBtnHamburger.ShowHint := True;

  // Cancel-Button - immer sichtbar (verhindert Layout-Sprung beim
  // Start/Ende der Analyse), nur Enabled wird getoggelt. Sitzt fix am
  // rechten Toolbar-Rand (alRight) und ist von den Analyse-Buttons
  // links optisch entkoppelt.
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent   := PanelSearch;
  FBtnCancel.Caption  := _('Cancel');
  FBtnCancel.Width    := ScaleW(BTN_W_MED);
  FBtnCancel.Align    := alRight;
  FBtnCancel.AlignWithMargins := True;
  FBtnCancel.Margins.SetBounds(ScaleW(TB_CANCEL_MARGIN), 0, 0, 0);
  FBtnCancel.Visible  := True;
  FBtnCancel.Enabled  := False;
  FBtnCancel.OnClick  := CancelAnalyseClick;

  // Analyse-Busy-Controller jetzt erstellen - Buttons + Progressbar
  // existieren alle. Owner=Self -> Auto-Free im Frame-Destroy
  // (wird zusaetzlich explizit FreeAndNil'd vor anderen Feldern).
  FAnalyseProgress := TAnalyseProgressController.Create(Self,
    FProgressBar, FBtnCancel,
    [FBtnAnalyse, FBtnAnalyseCurrent, FBtnAnalyseChanged]);

  // Analyse-Runner: kapselt RunAll/RunCurrent/RunChanged. Bekommt
  // Refs auf Progress + RepoSettings + IgnoreList + ProgressBar plus
  // method-of-object Callbacks fuer Status- und Result-Delivery.
  // Pointer(Self) wird gegen GLiveAnalyserFrame verglichen (Lifecycle-
  // Race-Schutz beim Hot-Plug-Reload).
  FAnalyseRunner := TAnalyseRunner.Create(Self, Pointer(Self),
    FAnalyseProgress, FRepoSettings, FIgnoreList, FProgressBar,
    StatusMode, StatusProgress, PopulateFindings);

  // Trennabstand
  var SepActions := TPanel.Create(Self);
  SepActions.Parent     := PanelSearch;
  SepActions.Align      := alLeft;
  SepActions.Width      := ScaleW(TB_SPACER_WIDTH);
  SepActions.BevelOuter := bvNone;
  SepActions.Color      := clBtnFace;

  FLblSearch := TLabel.Create(Self);
  FLblSearch.Parent  := PanelSearch;
  FLblSearch.Caption := _('Search:');
  FLblSearch.Align   := alLeft;
  FLblSearch.Layout  := tlCenter;
  FLblSearch.Width   := ScaleW(LBL_W_SEARCH);

  // Export-Dropdown statt 5 Einzel-Buttons - spart ~250 px Toolbar-Platz.
  // Komplettes Menu + Click-Handler + CurrentFocusFile-Logik in
  // uIDEExportMenu.TFindingExportMenu gekapselt.
  // FResultGrid existiert hier noch NICHT (wird weiter unten erzeugt) -
  // daher Getter-Methode statt Direkt-Reference.
  FExportMenu := TFindingExportMenu.Create(Self,
    FAllFindings, FDisplayedFindings, GetResultGrid,
    StatusMode, GetCurrentBaseDir);

  var BtnExport := TButton.Create(Self);
  FBtnExport := BtnExport;
  BtnExport.Parent     := PanelSearch;
  BtnExport.Caption    := _('Export') + ' ' + #$25BC; // schwarzes Dreieck nach unten
  BtnExport.Width      := ScaleW(BTN_W_MED);
  BtnExport.Align      := alRight;
  BtnExport.Hint       := _('Export: HTML, JSON, CSV, Jira markup, plain text');
  BtnExport.ShowHint   := True;
  // PopupMenu + OnClick wirft der Helper auf den Button.
  FExportMenu.AttachToButton(BtnExport);

  // Sucheingabe fuellt den Rest in der Mitte. MinWidth verhindert Kollaps
  // bei sehr schmal gedocktem Frame - sonst frisst Search-Edit als
  // alClient zwischen den alLeft/alRight-Buttons gerne 0 px.
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent      := PanelSearch;
  FSearchEdit.Align       := alClient;
  // MinWidth wird per AdjustSearchMinWidth dynamisch gesetzt (docked vs
  // floated). Hier nur den Floated-Default als sichere Initial-Annahme,
  // bis der erste Resize-Pass laeuft.
  FSearchEdit.Constraints.MinWidth := ScaleW(SEARCH_MIN_WIDTH_FLOATED);
  FSearchEdit.TextHint    := _('Filter file / method / finding...');
  FSearchEdit.OnChange    := SearchChange;
  FSearchEdit.ParentFont  := False;
  FSearchEdit.Font.Name   := 'Segoe UI';
  FSearchEdit.Font.Size   := 8;

  // ---- Toolbar-Controls einheitliche Hoehe (siehe TToolbarSizing) -------
  // Loest die VCL-Quirk dass TComboBox die Align.Height ignoriert. Buttons
  // und Edits respektieren Align von Hause aus, der Helper-Aufruf ist hier
  // redundant aber konsistent: jede Toolbar-Component geht durch denselben
  // Sizing-Pfad. ScaleW skaliert den 96-DPI-Wert auf die Container-PPI.
  // Icon-Buttons mit erzwungener Width+Height-Constraints damit sie pixel-
  // genau identisch rendern (Browse + Hamburger + Branch-Changes).
  TToolbarSizing.ApplyIconButton(BtnBrowse,          ScaleW(BTN_W_ICON), UnifCtrlH);
  TToolbarSizing.ApplyIconButton(FBtnHamburger,      ScaleW(BTN_W_ICON), UnifCtrlH);
  TToolbarSizing.ApplyIconButton(FBtnAnalyseChanged, ScaleW(BTN_W_ICON), UnifCtrlH);
  // Restliche Components nur Hoehe vereinheitlichen.
  TToolbarSizing.Apply(FBtnIgnore,          UnifCtrlH);
  TToolbarSizing.Apply(FBtnRepo,            UnifCtrlH);
  TToolbarSizing.Apply(FProjectPath,        UnifCtrlH);
  TToolbarSizing.Apply(FFilterCombo,        UnifCtrlH);
  TToolbarSizing.Apply(FTypeCombo,          UnifCtrlH);
  TToolbarSizing.Apply(FBtnAnalyse,         UnifCtrlH);
  TToolbarSizing.Apply(FBtnAnalyseCurrent,  UnifCtrlH);
  TToolbarSizing.Apply(FBtnCancel,          UnifCtrlH);
  TToolbarSizing.Apply(FBtnExport,          UnifCtrlH);
  TToolbarSizing.Apply(FSearchEdit,         UnifCtrlH);

  // ---- Hamburger-Menu (alle "optionalen" Actions als Backup-Pfad) ----
  // Wird gebraucht wenn der Frame schmal gedockt ist und die zugehoerigen
  // Buttons via FResponsive ausgeblendet werden.
  // Setup in BuildHamburgerMenu (referenziert bestehende Click-Handler).
  BuildHamburgerMenu;

  // ---- Zentraler Responsive-Layout-Controller (3 Stufen) ----------------
  // Eine Klasse, eine ClientWidth-Quelle (= Frame.ClientWidth), eine
  // Sichtbarkeitstabelle. Stage-Bestimmung + DPI-Skalierung intern.
  // Alle Sichtbarkeitsregeln stehen direkt unter dieser Stelle - kein
  // Verstreut-Sein ueber 3 Panels und 5 Controller mehr.
  // AfterApply-Callback fired nach JEDEM Resize -> dynamische Folge-Anpassungen
  // (FilterSubPanels-Width, SearchEdit-MinWidth) bleiben aktuell.
  // FResponsive selbst wird Self-owned -> Auto-Free im Frame-Destroy.
  FResponsive := TResponsiveLayoutController.Create(Self, Self,
    BREAKPOINT_MEDIUM, BREAKPOINT_FULL);

  // PanelPath
  FResponsive.RegisterCtrl(FBtnRepo,           usFull);
  FResponsive.RegisterCtrl(FBtnIgnore,         usFull);
  // (BtnBrowse, LblPath, FProjectPath: immer sichtbar - keine Registrierung noetig)

  // PanelButtons
  FResponsive.RegisterCtrl(FLblFilter,         usMedium);
  FResponsive.RegisterCtrl(FLblType,           usMedium);
  FResponsive.RegisterCtrl(FLblProfile,        usMedium);
  // (FFilterCombo, FTypeCombo, FProfileCombo, FPanelSev, FPanelType,
  //  FPanelProfile: immer sichtbar)

  // PanelSearch
  FResponsive.RegisterCtrl(FBtnCancel,         usFull);
  FResponsive.RegisterCtrl(FBtnExport,         usFull);
  FResponsive.RegisterCtrl(FBtnAnalyseChanged, usFull);
  FResponsive.RegisterCtrl(FLblSearch,         usFull);
  FResponsive.RegisterCtrl(FBtnHamburger,      usNarrow, usMedium);  // inverse
  // (FBtnAnalyse, FBtnAnalyseCurrent, FSearchEdit: immer sichtbar)

  // Stats-Tiles werden in BuildStatsTiles registriert (FResponsive ist
  // dort verfuegbar, Owner-Reference ueber Self-Field).

  // Folge-Anpassungen nach jedem Resize (Sub-Panel-Width-Sync,
  // SearchEdit-MinWidth-Sync). Beide sind idempotent, koennen mehrfach
  // pro Resize laufen.
  FResponsive.AfterApply := ResponsiveAfterApply;

  // ---- Statistik-Leiste: eine Reihe Sonar-Style Tiles (dunkler Hintergrund) ---
  FPanelStats := TPanel.Create(Self);
  FPanelStats.Parent      := Self;
  FPanelStats.Align       := alTop;
  FPanelStats.Height      := ScaleW(STATS_PANEL_HEIGHT);
  FPanelStats.BevelOuter  := bvNone;
  FPanelStats.Color       := clBtnFace; // folgt IDE-Theme statt fest dunkel
  FPanelStats.ParentBackground := False;
  FPanelStats.Padding.SetBounds(ScaleW(STATS_PADDING), ScaleW(STATS_PADDING),
                                ScaleW(STATS_PADDING), ScaleW(STATS_PADDING));

  BuildStatsTiles(FPanelStats);

  // alTop-Reihenfolge explizit setzen (gewuenschte Top-zu-Bottom-Reihenfolge:
  //   FPanelStats -> PanelPath -> PanelButtons -> PanelSearch).
  // alTop dockt in Z-Order von vorne nach hinten - also bringen wir sie in der
  // gewuenschten Reihenfolge nach vorne (das letzte BringToFront landet ganz
  // vorne und damit oben).
  PanelSearch.BringToFront;
  PanelButtons.BringToFront;
  PanelPath.BringToFront;
  FPanelStats.BringToFront;

  // ---- Client: Result-Grid + Hilfe-Panel ----
  PanelClient := TPanel.Create(Self);
  PanelClient.Parent     := Self;
  PanelClient.Align      := alClient;
  PanelClient.BevelOuter := bvNone;

  // Hilfe-Panel + Splitter + Dock-State-Logik komplett gekapselt in
  // uIDEHelpPanel. Anchor = Self damit HostIsFloating den Form-Chain
  // hochlaufen kann. Ownership via Self -> auto-Free.
  FHintPanel := TFindingHintPanel.Create(Self, PanelClient, Self);

  FResultGrid := TStringGrid.Create(Self);
  FResultGrid.Parent           := PanelClient;
  FResultGrid.Align            := alClient;
  // MinWidth=300 verhindert dass der Help-Splitter den Grid-Bereich
  // praktisch auf Null zieht. MinHeight=120 weiterhin gegen Mini-Hoehe.
  FResultGrid.Constraints.MinHeight := ScaleW(GRID_MIN_HEIGHT);
  FResultGrid.Constraints.MinWidth  := ScaleW(GRID_MIN_WIDTH);
  FResultGrid.FixedCols        := 0;
  FResultGrid.ColCount         := 6;
  FResultGrid.RowCount         := 2;
  FResultGrid.DefaultColWidth  := ScaleW(100);
  FResultGrid.DefaultRowHeight := ScaleW(20);
  FResultGrid.FixedRows        := 1;
  FResultGrid.ParentFont       := False;
  FResultGrid.Font.Name        := 'Segoe UI';
  FResultGrid.Font.Size        := 8;
  FResultGrid.GridLineWidth    := 1;
  FResultGrid.Options          := [goFixedVertLine, goFixedHorzLine,
                                   goVertLine, goHorzLine,
                                   goColSizing, goRowSelect, goThumbTracking];
  // Spaltenbreiten (DPI-skaliert): 130+85+38+110+240+90 = 693 px @ 100% DPI.
  // Befund-Spalte (4) faellt der GridResize-Handler den Rest zu.
  FResultGrid.ColWidths[0] := ScaleW(130);  // Datei
  FResultGrid.ColWidths[1] := ScaleW( 85);  // Methode
  FResultGrid.ColWidths[2] := ScaleW( 38);  // Zeile
  FResultGrid.ColWidths[3] := ScaleW(110);  // Typ (fix)
  FResultGrid.ColWidths[4] := ScaleW(240);  // Regel/Befund (fuellt Rest per GridResize)
  FResultGrid.ColWidths[5] := ScaleW( 90);  // Schweregrad (fix)
  FResultGrid.Cells[0, 0] := _('File');
  FResultGrid.Cells[1, 0] := _('Method');
  FResultGrid.Cells[2, 0] := _('Line');
  FResultGrid.Cells[3, 0] := _('Type');
  FResultGrid.Cells[4, 0] := _('Rule');
  FResultGrid.Cells[5, 0] := _('Severity');
  FResultGrid.OnDrawCell   := GridDrawCell;
  FResultGrid.OnDblClick    := GridDblClick;
  FResultGrid.OnSelectCell  := GridSelectCell;
  FResultGrid.OnMouseDown   := GridMouseDown;
  FResultGrid.OnKeyDown     := GridKeyDown;
  // Tooltip-Setup (Subclass + Hint-Properties + HintPause-Override) ist
  // im TFindingGridTooltip-Helper gekapselt. Owner=Self -> Auto-Free
  // plus expliziter FreeAndNil im Destruktor (Restore-Reihenfolge).
  FGridTooltip := TFindingGridTooltip.Create(Self, FResultGrid, FDisplayedFindings);

  LoadRecentPaths;

  // Initial Layout-Pass: Responsive-Controller-Visibility-Status setzen,
  // ohne auf den ersten Resize-Event zu warten. Resize-Override (s.u.)
  // uebernimmt alle weiteren Bounds-Changes inklusive Float->Dock.
  FrameResize(Self);
end;

destructor TAnalyserFrame.Destroy;
begin
  // ALLERERSTES: Lifecycle-Sentinel zuruecksetzen. Falls ein laufender
  // Worker-Callback waehrend dieses Destructors via Application.ProcessMessages
  // antriggert wird, sieht er den nil-Pointer und exit'd - kein Zugriff auf
  // bereits halb-zerstoerte Frame-Felder.
  if GLiveAnalyserFrame = Pointer(Self) then
    GLiveAnalyserFrame := nil;

  // Help-Panel-Timer ist jetzt in TFindingHintPanel.Destroy gekapselt
  // (wird auto-gestoppt wenn Owner=Self den Helper freigibt).

  // Watch-Mode deaktivieren BEVOR FAllFindings & Co. weg sind -
  // laufende Background-Worker-Synchronize-Calls duerfen jetzt droppen
  // statt in die OnWatchFindings-Callback zu laufen (die zugriffe Frame-
  // Felder die gleich freigegeben werden).
  if Assigned(GWatchMode) and GWatchMode.Active then
    GWatchMode.Deactivate;

  // Analyse-Runner FRUEH freigeben - vor anderen Feldern. Falls noch
  // ein Worker-Callback in flight waere, wuerde GLiveAnalyserFrame=nil
  // (oben gesetzt) den Sentinel-Check failen lassen. Wir haben hier
  // also eine Default-no-op-Garantie. Owner=Self wuerde es spaeter via
  // DestroyComponents ohnehin freigeben.
  FreeAndNil(FAnalyseRunner);

  // Tooltip-Helper FRUEH freigeben: restored die WndProc-Subclass am
  // Grid und HintPause-Override am Application, bevor andere Felder
  // weg sind. Sonst koennte ein letzter CM_*-Wisch in unsere
  // ungueltige WndProc feuern.
  FreeAndNil(FGridTooltip);

  // Theme-Helper FRUEH freigeben: meldet den IDE-Notifier ab, sodass
  // ein noch schwebender Theme-Wechsel-Callback nicht in halb-zerlegte
  // Frame-Felder laeuft. Owner=Self wuerde das auch erledigen, aber
  // erst NACH inherited Destroy - zu spaet.
  FreeAndNil(FThemeIntegration);

  // Analyse-Progress-Controller halt nur Widget-Referenzen (kein
  // Ownership). Wir nilen das Feld trotzdem fruehzeitig, damit ein
  // verspaetet-feuernder Worker-Callback ein Assigned-Check sauber
  // false zurueckliefert.
  FreeAndNil(FAnalyseProgress);

  FreeAndNil(FAllFindings);
  FreeAndNil(FDisplayedFindings);
  FreeAndNil(FIgnoreList);
  FreeAndNil(FRepoSettings);
  inherited;
end;

procedure TAnalyserFrame.RefreshFromIDETheme;
begin
  // Reine Delegation - die ganze Refresh-Logik (TopForm-ApplyTheme,
  // ApplyThemeRecursive, Grid-Repaint via Callback) lebt jetzt im
  // Helper. Nil-safe weil der Frame waehrend Destroy hier nicht
  // mehr ankommen sollte, aber defensiv fuer den Fall dass ein
  // verspaeteter SetParent waehrend Teardown feuert.
  if Assigned(FThemeIntegration) then
    FThemeIntegration.RefreshFromIDETheme;
end;

procedure TAnalyserFrame.RepaintGridAfterTheme;
begin
  // Wird vom Helper nach jedem Theme-Refresh als Callback aufgerufen.
  // TStringGrid hat einen besonders starren Paint-Cache der nicht von
  // der rekursiven Invalidate abgeholt wird - hier explizit forcieren.
  if Assigned(FResultGrid) then
  begin
    FResultGrid.Invalidate;
    FResultGrid.Repaint;
  end;
end;

// ---------------------------------------------------------------------------
// Sonar-Style Tile-Reihe - 10 Tiles horizontal, einheitlicher Hintergrund.
//
//   [Fehler] [Warnungen] [Hinweise] [Lesefehler] [Code Smell]
//   [Bugs] [Sicherheit] [Hotspot] [Duplikate] [Codequalitaet]
//
// Pro Tile: Akzentfarbiges Glyph-Icon links + Count rechts (Top-Row), darunter
// Caption zentriert. 1px duenner Rahmen ueber TTilePanel-Subklasse (Paint
// override). Glyphs aus Segoe Fluent Icons / Segoe MDL2 Assets - vektor,
// auf jedem Win10/11 nativ verfuegbar (kein SVG-Library-Dependency).
//
// Mapping zu unserem Datenmodell:
//   Fehler/Warnungen/Hinweise/Lesefehler -> Severity-Buckets (Err/Warn/Hint/FileErr)
//   Code Smell                           -> ftCodeSmell-Count
//   Bugs/Sicherheit/Hotspot/Duplikate    -> Type-Buckets (Bug/Vuln/Hotspot/Dup)
//   Codequalitaet                        -> gewichteter Quality-Score
// ---------------------------------------------------------------------------

// TTilePanel + MakeTile + BuildStatsTiles wurden nach uIDEStatsTiles
// extrahiert. Hier nur noch die Frame-seitige Brücke, die die OUT-Params
// in die Frame-Felder schreibt - UpdateStats greift weiterhin direkt auf
// FTileError/FTileWarn/... zu, daher bleibt die Feld-Struktur unveraendert.

procedure TAnalyserFrame.BuildStatsTiles(Parent: TPanel);
// Thresholds: BREAKPOINT_MEDIUM (500) + BREAKPOINT_FULL (850) aus
// implementation-const (gemeinsam mit den Toolbar-Controllern in CreateUI).

  procedure WireTile(CountLbl: TLabel; const AHint: string; ATag: Integer;
    OnClickHandler: TNotifyEvent);
  // CountLbl.Parent.Parent = TilePanel. Wir setzen Hint + Tag + OnClick
  // sowohl auf den TilePanel-Container als auch rekursiv auf alle TControl-
  // Children (TopRow + IconLbl + CountLbl + CapLbl) - sonst wuerde ein
  // Klick auf das Glyph oder die Caption nichts triggern.
  //
  // TControlAccess (oben in implementation-type) durchbricht die protected-
  // Sichtbarkeit von TControl.OnClick.
    procedure ApplyTo(C: TControl; const H: string; T: Integer; H2: TNotifyEvent);
    var i: Integer;
    begin
      C.Hint     := H;
      C.ShowHint := True;
      C.Tag      := T;
      TControlAccess(C).OnClick := H2;
      C.Cursor   := crHandPoint; // signalisiert Klickbarkeit
      if C is TWinControl then
        for i := 0 to TWinControl(C).ControlCount - 1 do
          ApplyTo(TWinControl(C).Controls[i], H, T, H2);
    end;

  var
    Tile : TControl;
  begin
    if not Assigned(CountLbl) or not Assigned(CountLbl.Parent)
       or not Assigned(CountLbl.Parent.Parent) then Exit;
    Tile := CountLbl.Parent.Parent;
    ApplyTo(Tile, AHint, ATag, OnClickHandler);
  end;

begin
  TStatsTilesBuilder.Build(Self, Parent,
    FTileError, FTileWarn, FTileHint, FTileFileSev,
    FTileBug, FTileVuln, FTileDup, FTileCyclomatic, FTileScore);

  // Severity-Bucket-Kacheln -> klick filtert FilterCombo
  WireTile(FTileError,    _('Errors')   + sLineBreak +
           _('Real bugs / security holes (severity Error). Fix immediately.')
           + sLineBreak + _('Click: filter grid to Errors'),
           Ord(fmErrors), TileClickSeverity);

  WireTile(FTileWarn,     _('Warnings') + sLineBreak +
           _('Likely bugs / risky patterns. Review before merge.')
           + sLineBreak + _('Click: filter grid to Warnings'),
           Ord(fmWarnings), TileClickSeverity);

  WireTile(FTileHint,     _('Hints') + sLineBreak +
           _('Code smells / style. Refactoring candidates.')
           + sLineBreak + _('Click: filter grid to Hints'),
           Ord(fmHints), TileClickSeverity);

  WireTile(FTileFileSev,  _('Read errors') + sLineBreak +
           _('File could not be read / parsed. Check path/encoding.')
           + sLineBreak + _('Click: filter grid to read errors'),
           Ord(fmFileReadError), TileClickSeverity);

  // Detector-spezifische Kachel
  WireTile(FTileCyclomatic, _('Cyclomatic Complexity') + sLineBreak +
           _('Methods with McCabe complexity > threshold (default 10).')
           + sLineBreak + _('Hard to test - refactor into smaller methods.')
           + sLineBreak + _('Click: filter grid to Cyclomatic'),
           Ord(fmCyclomaticComplexity), TileClickSeverity);

  // Type-Bucket-Kacheln -> klick filtert TypeCombo
  WireTile(FTileBug,      _('Bugs') + sLineBreak +
           _('Findings of type Bug (wrong behaviour, crash, wrong result).')
           + sLineBreak + _('Crosses severities - Bugs can be Errors OR Warnings.')
           + sLineBreak + _('Click: filter grid to Bug type'),
           Ord(tfBug), TileClickType);

  WireTile(FTileVuln,     _('Security') + sLineBreak +
           _('Security holes (SQL injection, hardcoded secrets ...).')
           + sLineBreak + _('Click: filter grid to Vulnerability type'),
           Ord(tfVulnerability), TileClickType);

  WireTile(FTileDup,      _('Duplicates') + sLineBreak +
           _('Copied code (strings, blocks). Extract Method/Constant candidates.')
           + sLineBreak + _('Click: filter grid to Duplicate type'),
           Ord(tfCodeDuplication), TileClickType);

  // Code-Quality-Score: kein semantischer Filter (Score ist Aggregation),
  // Klick wirkt als Reset-Button auf alle Filter.
  WireTile(FTileScore,    _('Code Quality') + sLineBreak +
           _('Weighted quality score (lower = better).')
           + sLineBreak + _('Weights: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.')
           + sLineBreak + _('Click: reset filters (show everything)'),
           0, TileClickClear);

  // Tile-Visibility wird ueber den zentralen FResponsive registriert.
  // Tile-Labels -> Parent.Parent ist die TilePanel (TopRow dazwischen).
  //
  // Tier-Aufteilung:
  //   essential (immer):     Errors, Warnings, Hints, Code Quality      (4)
  //   MEDIUM+ (>= 500):      Read errors, Bugs, Security, Duplicates,
  //                          Cyclomatic                                 (+5 -> 9)
  if Assigned(FResponsive) then
  begin
    FResponsive.RegisterCtrl(FTileFileSev.Parent.Parent,    usMedium);
    FResponsive.RegisterCtrl(FTileBug.Parent.Parent,        usMedium);
    FResponsive.RegisterCtrl(FTileVuln.Parent.Parent,       usMedium);
    FResponsive.RegisterCtrl(FTileDup.Parent.Parent,        usMedium);
    FResponsive.RegisterCtrl(FTileCyclomatic.Parent.Parent, usMedium);
  end;
end;

// Status-Bar-Push-Methoden delegieren an uIDEStatusBar.TAnalyserStatusBar.
// Die Existenz-Pruefung auf FStatusBar bleibt hier - die drei Methoden
// werden von Closures im Analyse-Worker auch waehrend Constructor- und
// Destructor-Pfaden aufgerufen, wenn FStatusBar evtl. noch nil ist.
procedure TAnalyserFrame.StatusFindings(const T: string);
begin
  if Assigned(FStatusBar) then FStatusBar.Findings(T);
end;

procedure TAnalyserFrame.StatusProgress(const T: string);
begin
  if Assigned(FStatusBar) then FStatusBar.Progress(T);
end;

procedure TAnalyserFrame.StatusMode(const T: string);
begin
  if Assigned(FStatusBar) then FStatusBar.Mode(T);
end;


// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.FilterChange(Sender: TObject);
var
  idx, tag: Integer;
  OldOnChange: TNotifyEvent;
begin
  // Defensive Bound-Checks: ItemIndex kann -1 sein (nichts ausgewaehlt) oder
  // bei einer leeren Combo theoretisch ungueltig. Items.Objects[-1] waere AV.
  if FFilterCombo.Items.Count = 0 then Exit;
  idx := FFilterCombo.ItemIndex;
  if (idx < 0) or (idx >= FFilterCombo.Items.Count) then Exit;

  tag := Integer(FFilterCombo.Items.Objects[idx]);
  if tag < 0 then
  begin
    // Separator-Eintrag - keine Filter-Aktion, Auswahl auf "Alle" zuruecksetzen.
    // Re-Entry-Schutz: das ItemIndex-Setzen feuert OnChange erneut. Wir
    // entkoppeln den Handler temporaer, sonst wuerde FilterChange rekursiv
    // aufgerufen.
    OldOnChange := FFilterCombo.OnChange;
    FFilterCombo.OnChange := nil;
    try
      FFilterCombo.ItemIndex := 0;
    finally
      FFilterCombo.OnChange := OldOnChange;
    end;
    FFilterMode := fmAll;
  end
  else
    FFilterMode := TFilterMode(tag);
  ApplyFilter;
end;

procedure TAnalyserFrame.TypeFilterChange(Sender: TObject);
var
  idx: Integer;
begin
  if FTypeCombo.Items.Count = 0 then Exit;
  idx := FTypeCombo.ItemIndex;
  if (idx < 0) or (idx >= FTypeCombo.Items.Count) then Exit;
  FTypeFilter := TTypeFilter(idx);
  ApplyFilter;
end;

procedure TAnalyserFrame.ProfileChange(Sender: TObject);
// Re-Filter macht hier KEINEN Sinn - das Profile beeinflusst, welche
// Detektoren beim NAECHSTEN Run laufen, nicht die Anzeige der schon
// gefundenen Befunde. Nur ein Status-Hint, damit der User Feedback sieht.
// Die eigentliche Anwendung passiert in PrepareAnalysis (liest die
// aktuelle Combo-Selektion + ueberschreibt FRepoSettings.Profile).
//
// Persistenz: die UI-Auswahl wird in [Rules] IdeProfile persistiert,
// damit sie beim naechsten Frame-Start als Default zurueckkommt.
// Save-Fehler schlucken wir still (Read-Only-INI, fehlende Berechtigung):
// in dem Fall wirkt die Selektion nur fuer die aktuelle Session.
var
  Selected : string;
begin
  if not Assigned(FProfileCombo) or (FProfileCombo.ItemIndex < 0) then Exit;
  Selected := FProfileCombo.Items[FProfileCombo.ItemIndex];
  StatusMode(Format(_('Profile "%s" - active on next analysis run'),
    [Selected]));

  if Assigned(FRepoSettings) then
  try
    FRepoSettings.IdeProfile := Selected;
    FRepoSettings.Save;
  except
    // Keine Modal-Dialoge im OnChange - persistente Fehler sehen wir
    // beim naechsten Save (Repo-Settings-Dialog) wieder.
  end;
end;

procedure TAnalyserFrame.PopulateGridFromDisplayed;
// Virtual-Mode: nur RowCount setzen + Repaint triggern. Die Zell-Strings
// liest GridDrawCell.GetCellText lazy aus FDisplayedFindings - das
// vermeidet bei 66k+ Befunden ~50-100 MB Cells[]-Vorallokation
// (32-Bit-Process-Limit).
begin
  FResultGrid.RowCount := Max(FDisplayedFindings.Count + 1, 2);
  if FDisplayedFindings.Count = 0 then
  begin
    // Placeholder-Zeile bleibt explizit in Cells (GetCellText liest sie
    // dann via Fallback aus).
    FResultGrid.Rows[1].Clear;
    FResultGrid.Cells[0, 1] := 'Keine Eintraege fuer diesen Filter.';
  end;
  FResultGrid.Invalidate;
end;

procedure TAnalyserFrame.UpdateFilterStatus(
  const Criteria: TFindingFilterCriteria);
begin
  StatusFindings(Format(_('%d / %d findings'),
    [FDisplayedFindings.Count, FAllFindings.Count]));
  StatusMode(Format(_('Filter: %s%s'), [FFilterCombo.Text,
    IfThen(Criteria.SearchLow <> '',
           ', ' + _('Search: ') + Criteria.SearchLow, '')]));

  // Befunde werden bewusst NICHT mehr in die IDE-Messages-Toolbar
  // gespiegelt - das eigene Grid + Statusbar reicht und vermeidet,
  // dass Compiler-Output beim Scan ueberschrieben wird. uIDEMessages
  // bleibt fuer den Fall stehen dass die Funktion wieder gewuenscht
  // wird (TIDEMessages.ReportFindings(FDisplayedFindings)).
end;

procedure TAnalyserFrame.ApplyFilter;
var
  i        : Integer;
  Criteria : TFindingFilterCriteria;
  SortCfg  : TFindingSortConfig;
begin
  Criteria.Mode       := FFilterMode;
  Criteria.TypeFilter := FTypeFilter;
  Criteria.SearchLow  := Trim(FSearchEdit.Text).ToLower;

  SendMessage(FResultGrid.Handle, WM_SETREDRAW, 0, 0);
  try
    FDisplayedFindings.Clear;

    // ---- Filter (Logik in uFindingFilter.TFindingFilter.Matches) ----
    for i := 0 to FAllFindings.Count - 1 do
      if TFindingFilter.Matches(FAllFindings[i], Criteria) then
        FDisplayedFindings.Add(FAllFindings[i]);

    // ---- Sortierung (Logik in uFindingFilter.TFindingSorter.Sort) ----
    if FSortColumn >= 0 then
    begin
      SortCfg.Column     := FSortColumn;
      SortCfg.Descending := FSortDescending;
      SortCfg.BaseDir    := FCurrentBaseDir;
      TFindingSorter.Sort(FDisplayedFindings, SortCfg);
    end;

    PopulateGridFromDisplayed;
  finally
    SendMessage(FResultGrid.Handle, WM_SETREDRAW, 1, 0);
    FResultGrid.Invalidate;
  end;

  UpdateFilterStatus(Criteria);

  // Multi-File-Marker-Refresh: nach jedem Filter-Wechsel oder
  // Analyse-Lauf zeigt der Highlighter ab sofort Stripes + Hover-
  // Overlays auf JEDEM Editor-Tab dessen Datei in der gefilterten
  // Liste vertreten ist. Vorher: erst nach Grid-Klick. Damit ist der
  // Tab-Switch-Use-Case ohne Click erreichbar.
  HighlightAllFindingsInFile('');
end;

// ---------------------------------------------------------------------------
// Suchfeld
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.SearchChange(Sender: TObject);
begin
  ApplyFilter;
end;

// ---------------------------------------------------------------------------
// Spalten-Sortierung per Klick auf Header
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow: Integer;
begin
  if Button <> mbLeft then Exit;
  FResultGrid.MouseToCell(X, Y, ACol, ARow);
  if ARow <> 0 then Exit; // Nur Header-Zeile
  if (ACol < 0) or (ACol > 4) then Exit;

  if FSortColumn = ACol then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := ACol;
    FSortDescending := False;
  end;
  ApplyFilter;
end;

// ---------------------------------------------------------------------------
// Tastatur-Navigation: F3 = naechster, Shift+F3 = vorheriger Befund
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  NewRow: Integer;
begin
  if Key = VK_F3 then
  begin
    if ssShift in Shift then
      NewRow := FResultGrid.Row - 1
    else
      NewRow := FResultGrid.Row + 1;

    if (NewRow >= 1) and (NewRow < FResultGrid.RowCount) then
    begin
      FResultGrid.Row := NewRow;
      UpdateHelp(NewRow);
    end;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    GridDblClick(Sender);
    Key := 0;
  end;
end;

// ---------------------------------------------------------------------------
// Export-Buttons
// ---------------------------------------------------------------------------
// ---- Getter fuer den Export-Menu-Helper (uIDEExportMenu) ----
function TAnalyserFrame.GetCurrentBaseDir: string;
begin
  Result := FCurrentBaseDir;
end;

function TAnalyserFrame.GetResultGrid: TStringGrid;
begin
  Result := FResultGrid;
end;

function TAnalyserFrame.CurrentProfileOverride: string;
// Spiegelt den im Dock-Frame gewaehlten Profile-Eintrag wider. Wird vom
// Silent-Mode konsultiert damit eine im Dock geaenderte Combo-Auswahl auch
// ohne INI-Save fuer Silent-Runs gilt.
begin
  Result := '';
  if Assigned(FProfileCombo) and (FProfileCombo.ItemIndex >= 0) then
    Result := FProfileCombo.Items[FProfileCombo.ItemIndex];
end;

procedure TAnalyserFrame.OnWatchStatus(const Status: string);
// Vom WatchMode-Manager via TThread.Synchronize / Timer-OnTimer auf dem
// UI-Thread. Aktualisiert das Mode-Panel der Statusbar wenn moeglich.
begin
  // Lifecycle-Race: Frame koennte zerstoert worden sein waehrend ein
  // letzter Status-Push noch in der Queue lag.
  if GLiveAnalyserFrame <> Pointer(Self) then Exit;
  if Status = '' then
    StatusMode('')
  else
    StatusMode('[watch] ' + Status);
end;

procedure TAnalyserFrame.OnWatchFindings(const FileName: string;
  Findings: TObjectList<TLeakFinding>);
// Wird auf UI-Thread aufgerufen wenn ein Watch-Worker fertig analysiert hat.
// Ersetzt die Befunde fuer EINE Datei in FAllFindings, ohne den Rest des
// Scans zu verlieren. Findings.OwnsObjects := False damit die TLeakFinding-
// Instanzen an FAllFindings (hat eigene Ownership=True) wandern.
var
  i: Integer;
begin
  if GLiveAnalyserFrame <> Pointer(Self) then
  begin
    // Frame zerstoert - Liste freigeben, sonst Memory-Leak.
    if Assigned(Findings) then
      Findings.Free;
    Exit;
  end;
  if not Assigned(Findings) then Exit;

  try
    // 1) Alte Findings fuer DIESE Datei aus FAllFindings entfernen.
    for i := FAllFindings.Count - 1 downto 0 do
      if SameText(FAllFindings[i].FileName, FileName) then
        FAllFindings.Delete(i);

    // 2) Neue Findings einhaengen (Ownership-Transfer).
    Findings.OwnsObjects := False;
    for i := 0 to Findings.Count - 1 do
      FAllFindings.Add(Findings[i]);

    // 3) UI auffrischen
    UpdateStats;
    ApplyFilter;
    StatusMode(Format('[watch] updated %s (%d findings)',
      [ExtractFileName(FileName), Findings.Count]));
  finally
    Findings.Free;
  end;
end;

procedure TAnalyserFrame.PopulateFindings(
  const findings: TObjectList<TLeakFinding>; const BaseDir: string);
var
  i: Integer;
begin
  FCurrentBaseDir := BaseDir;
  findings.OwnsObjects := False;
  FAllFindings.Clear;
  for i := 0 to findings.Count - 1 do
    FAllFindings.Add(findings[i]);
  UpdateStats;
  ApplyFilter;
  // ApplyFilter -> HighlightAllFindingsInFile baut die Multi-File-Marker
  // bereits sauber neu auf (SetAllFindings ersetzt den gesamten internen
  // State). Ein zusaetzlicher GHighlighter.Clear ist nicht mehr noetig -
  // er wuerde die gerade gesetzten Marker sofort wieder loeschen.
  // (Befund-Spiegelung in IDE-Messages-Toolbar ist deaktiviert -
  //  siehe Kommentar am Ende von ApplyFilter.)
end;

procedure TAnalyserFrame.UpdateStats;
// Befuellt die Sonar-Style Tiles mit Severity-, Typ-Aufteilung und
// Quality-Score. Jede Kachel hat ihr eigenes Count-Label - keine
// Indirektion, keine Truncation, keine OnDraw-Logik.
//
// Quality-Score-Gewichte (gewichtete Summe, niedriger = besser):
//   Vulnerability=10, Error=7, Hotspot=5, Warning=3, Hint=1, FileErr=2
const
  W_VULN     = 10;
  W_ERROR    = 7;
  W_HOTSPOT  = 5;
  W_WARNING  = 3;
  W_HINT     = 1;
  W_FILEERR  = 2;
var
  f                 : TLeakFinding;
  nErr, nWarn, nHint, nFileErr : Integer;
  nBug, nVuln, nHot, nDup      : Integer;
  nCyclo                       : Integer;
  score                        : Integer;
begin
  nErr  := 0; nWarn := 0; nHint := 0; nFileErr := 0;
  nBug  := 0; nVuln := 0; nHot  := 0; nDup := 0;
  nCyclo := 0;

  // Severity- und Typ-Aufteilung sind UNABHAENGIG: jeder Befund zaehlt
  // in genau einer Severity-Bucket UND in genau einer Type-Bucket.
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
      // ftCodeSmell zaehlt nur via Severity (nHint/nWarn) - keine eigene
      // Tile, kein eigener Score-Faktor (Smell-Gewicht steckt in der
      // Severity-Tabelle).
    end;

    // Detector-spezifischer Bucket: Cyclomatic Complexity. Zaehlt
    // ZUSAETZLICH zur Hint-Severity und CodeSmell-Type, gibt aber eine
    // eigene Kachel - macht das Refactoring-Ziel auf einen Blick sichtbar.
    if f.Kind = fkCyclomaticComplexity then
      Inc(nCyclo);
  end;

  score := nVuln    * W_VULN     +
           nErr     * W_ERROR    +
           nHot     * W_HOTSPOT  +
           nWarn    * W_WARNING  +
           nHint    * W_HINT     +
           nFileErr * W_FILEERR;

  if not Assigned(FTileError) then Exit;

  // Severity-Buckets: Fehler / Warnungen / Hinweise / Ausnahmen
  FTileError.Caption    := IntToStr(nErr);
  FTileWarn.Caption     := IntToStr(nWarn);
  FTileHint.Caption     := IntToStr(nHint);
  FTileFileSev.Caption  := IntToStr(nFileErr);

  // Type-Buckets: Bugs / Sicherheit / Duplikate (Smell + Hotspot ohne Kachel,
  // zaehlen aber weiterhin in den Quality-Score)
  FTileBug.Caption      := IntToStr(nBug);
  FTileVuln.Caption     := IntToStr(nVuln);
  FTileDup.Caption      := IntToStr(nDup);

  // Detector-spezifisch
  if Assigned(FTileCyclomatic) then
    FTileCyclomatic.Caption := IntToStr(nCyclo);

  // Codequalitaet (gewichteter Score - Smell und Hotspot eingerechnet)
  FTileScore.Caption    := IntToStr(score);
end;

// ---------------------------------------------------------------------------
// Hilfe-Hinweis
// ---------------------------------------------------------------------------
class function TAnalyserFrame.FixHint(const Finding: TLeakFinding): TFixHint;
// Thin-Wrapper - delegiert an den zentralen Resolver in uFixHint.
// Vorher: ~400 Zeilen redundanter case-Block, der zudem fkDuplicateBlock
// nicht abdeckte (kein Hinweistext fuer dupliziete Bloecke). Jetzt:
// alle 21 Finding-Kinds via uFixHint.TFixHintResolver garantiert abgedeckt.
begin
  Result := TFixHintResolver.FixHint(Finding);
end;

procedure TAnalyserFrame.UpdateHelp(Row: Integer);
// Thin wrapper - die ganze Display-Logik ist in TFindingHintPanel
// gekapselt. Wir verwalten hier nur den Row-zu-Finding-Lookup.
var
  Idx : Integer;
begin
  if not Assigned(FHintPanel) then Exit;
  Idx := Row - 1;
  if (Idx < 0) or (Idx >= FDisplayedFindings.Count) then
    FHintPanel.ShowPlaceholder
  else
    FHintPanel.ShowFinding(FDisplayedFindings[Idx]);
end;

procedure TAnalyserFrame.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
// Klick auf Zeile: Hilfetext aktualisieren, Befund als Claude-AI-Prompt
// in die Zwischenablage legen UND - falls die Datei in der IDE offen ist -
// alle Befund-Zeilen der gleichen Datei rot markieren (Multi-Marker-Modell).
var
  idx     : Integer;
  Finding : TLeakFinding;
begin
  CanSelect := True;
  UpdateHelp(ARow);

  idx := ARow - 1; // Zeile 0 = Header
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;

  Finding := FDisplayedFindings[idx];
  CopyFindingToClipboard(Finding);

  // Editor-Line-Highlights: alle Befunde der gleichen Datei mit Stripe
  // markieren. Wenn die Datei nicht offen ist, malt GHighlighter beim
  // naechsten Oeffnen.
  HighlightAllFindingsInFile(Finding.FileName);
end;

procedure TAnalyserFrame.CopyFindingToClipboard(F: TLeakFinding);
var
  prompt: string;
begin
  if not Assigned(F) then Exit;
  prompt := BuildClaudePrompt(F);
  try
    Clipboard.AsText := prompt;
    if Assigned(FStatusBar) then
      StatusMode(Format(
        _('AI prompt copied to clipboard: %s, line %s (%s)'),
        [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]));
  except
    // Clipboard kann unter bestimmten IDE-Modi blockiert sein - silent skip
  end;
end;

function TAnalyserFrame.BuildClaudePrompt(F: TLeakFinding): string;
// Markdown-Block fuer Claude-AI-Chat: Befund-Tabelle + Beschreibung +
// Code-Kontext (+/-5 Zeilen mit '>' Marker) + Vorher/Nachher.
// Thin-Wrapper - die Logik ist in uClaudePrompt zentralisiert (war
// zuvor 1:1 mit uMainForm dupliziert). Das Plugin uebergibt explizit
// seine eigene FixHint-Methode, da dort die Hint-Logik im Frame liegt.
begin
  Result := TClaudePrompt.Build(F, FixHint(F));
end;

// ---------------------------------------------------------------------------
// Ordner auswaehlen
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.BrowseClick(Sender: TObject);
var
  Dlg: TFileOpenDialog;
begin
  Dlg := TFileOpenDialog.Create(nil);
  try
    Dlg.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    Dlg.Title   := _('Select project folder');
    if Dlg.Execute then
      FProjectPath.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Analyse starten
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.PrepareAnalysis(const AWatchedFile: string);
begin
  if not Assigned(FRepoSettings) then Exit;
  try
    FRepoSettings.Load;
    FRepoSettings.RegisterToLeakyClasses;
    // IDE-Plugin: vor ApplyDetectorThresholds das IDE-spezifische
    // Profile/MinSeverity transient aktivieren (IdeProfile=ide-fast als
    // Default). Standalone-Pfad ruft das NICHT und nutzt [Rules] Profile.
    FRepoSettings.UseIdeRuleSet;
    // UI-Override: Profile-Combo gewinnt ueber die INI. So kann der User
    // im laufenden Frame zwischen ide-fast / default / strict umschalten
    // ohne die INI zu editieren. Load hat FRepoSettings.Profile gerade
    // erst aus der INI ueberschrieben - die Combo-Auswahl muss DANACH
    // gewinnen, sonst wuerde der INI-Wert die UI-Aktion verschlucken.
    if Assigned(FProfileCombo) and (FProfileCombo.ItemIndex >= 0) then
      FRepoSettings.Profile := FProfileCombo.Items[FProfileCombo.ItemIndex];
    // ProjectRoot durchreichen damit relative CustomRulesFile-Pfade
    // (z.B. 'analyser-rules.yml' im Projekt-Wurzelverzeichnis) gefunden werden.
    FRepoSettings.ApplyDetectorThresholds(Trim(FProjectPath.Text));
    AutoDiscoverCustomClasses := FRepoSettings.AutoDiscoverClasses;
    // Frische Discovery-Liste pro Run, sonst wandern Treffer aus
    // vorherigen Projekten in die INI mit.
    if Assigned(uSCAConsts.DiscoveredClasses) then
      uSCAConsts.DiscoveredClasses.Clear;
    if Assigned(uSCAConsts.DiscoveredStaticClasses) then
      uSCAConsts.DiscoveredStaticClasses.Clear;

    // Live-Watch nur im "Aktuelle Datei"-Pfad (AWatchedFile != '').
    // Bulk-Pfade (Full-Project, Branch-Changes) deaktivieren explizit -
    // sonst bleibt ein vom letzten "Aktuelle Datei"-Klick aktiver Watcher
    // haengen. Generation bumpen damit laufende Worker ihre Ergebnisse
    // droppen (sonst ueberschreiben sie die gleich geschriebenen
    // FAllFindings).
    if Assigned(GWatchMode) then
    begin
      GWatchMode.BumpGeneration;
      if AWatchedFile <> '' then
        GWatchMode.Activate(OnWatchFindings, OnWatchStatus, AWatchedFile)
      else if GWatchMode.Active then
        GWatchMode.Deactivate;
    end;
  except end;
end;

procedure TAnalyserFrame.FinishAnalysis;
begin
  if Assigned(FRepoSettings) and FRepoSettings.AutoDiscoverClasses then
    try FRepoSettings.PersistDiscoveredClasses; except end;
end;

procedure TAnalyserFrame.AnalyseClick(Sender: TObject);
begin
  if not TStaticFiles.ValidatePath(FProjectPath.Text) then
  begin
    ShowMessage(_('Please provide a valid project path.'));
    Exit;
  end;
  SaveRecentPath(FProjectPath.Text);
  PrepareAnalysis;
  try
    if Assigned(FAnalyseRunner) then
      FAnalyseRunner.RunAll(FProjectPath.Text);
  finally
    FinishAnalysis;
  end;
end;

procedure TAnalyserFrame.AnalyseCurrentFileClick(Sender: TObject);
var
  FilePath : string;
  AsPas    : string;
  Idx      : Integer;
begin
  // Quelle der "aktuellen Datei" in dieser Reihenfolge:
  //   1) Selektierte Zeile im Befund-Grid (User klickt einen Befund an und
  //      will GENAU diese Datei erneut scannen). Der IDE-Editor-Tab kann
  //      veraltet sein - er folgt nur dem letzten Doppelklick, einfache
  //      Selektion oeffnet die Datei nicht. Ohne diesen Schritt landet der
  //      Button auf der zuletzt doppelt-geklickten Datei statt auf der
  //      aktuell ausgewaehlten.
  //   2) Aktuelle Editor-Tab im IDE (TryGetCurrentPasFile, alter Default).
  //      Behaelt die Original-Pfade fuer "kein Befund-Grid geoeffnet",
  //      "Plugin gerade gestartet", "kein Lauf gemacht".
  FilePath := '';

  if Assigned(FDisplayedFindings) and Assigned(FResultGrid)
     and (FResultGrid.Row >= 1) then
  begin
    Idx := FResultGrid.Row - 1;
    if (Idx >= 0) and (Idx < FDisplayedFindings.Count) then
    begin
      FilePath := FDisplayedFindings[Idx].FileName;
      // .dfm-Befund: AnalyzeLeaks erwartet eine .pas - der DfmAnalysisRunner
      // liest das companion .dfm selbst nach. Selber Pfad wie in
      // TryGetCurrentPasFile fuer .dfm-Editor-Tabs.
      if EndsText('.dfm', FilePath) then
      begin
        AsPas := ChangeFileExt(FilePath, '.pas');
        if FileExists(AsPas) then
          FilePath := AsPas
        else
          FilePath := ''; // keine companion .pas -> Fallback auf IDE-Editor
      end;
    end;
  end;

  // Fallback: IDE-Editor-Detection in uIDEEditorIntegration ausgelagert
  // (saubere Supports-Casts + Buffer-nil-Check).
  if FilePath = '' then
  begin
    case TIDEEditor.TryGetCurrentPasFile(FilePath) of
      cfrNoEditorService:
        begin StatusMode(_('IDE editor service not available.')); Exit; end;
      cfrNoOpenView:
        begin StatusMode(_('No file opened.'));                   Exit; end;
      cfrNotPascalFile:
        begin StatusMode(_('Current file is not a Pascal file.')); Exit; end;
    end;
  end;

  if not FileExists(FilePath) then
  begin
    StatusMode(_('File not found: ') + FilePath);
    Exit;
  end;

  // "Aktuelle Datei" -> Single-File-Live-Watch auf genau diese Datei
  // (Save+Edit-Trigger). Andere offene Dateien werden NICHT mit-beobachtet.
  PrepareAnalysis(FilePath);
  try
    if Assigned(FAnalyseRunner) then
      FAnalyseRunner.RunCurrent(FilePath);
  finally
    FinishAnalysis;
  end;
end;

procedure TAnalyserFrame.AnalyseChangedFilesClick(Sender: TObject);
// Branch-Aenderungen via Git oder SVN. Verwendet den aktuellen Projektpfad
// als Startpunkt fuer die Repo-Erkennung.
var
  startPath : string;
begin
  startPath := Trim(FProjectPath.Text);
  if (startPath = '') or not DirectoryExists(startPath) then
  begin
    StatusMode(_('Branch changes: please provide a valid project path (for repo detection).'));
    Exit;
  end;

  // Settings frisch laden (User koennte analyser.ini in der Zwischenzeit
  // ueber den "Repo-Settings"-Button editiert haben).
  PrepareAnalysis;
  if Assigned(FRepoSettings) then
    try
      // Sprach-Aenderung wirkt erst beim naechsten UI-Aufbau (alle bereits
      // gesetzten Captions bleiben auf der bisherigen Sprache). User-Hinweis:
      // Plugin-Reload fuer vollen Sprachwechsel.
      SetLanguage(FRepoSettings.Language);
    except end;
  try
    if Assigned(FAnalyseRunner) then
      FAnalyseRunner.RunChanged(startPath);
  finally
    FinishAnalysis;
  end;
end;

procedure TAnalyserFrame.CancelAnalyseClick(Sender: TObject);
// Markiert die Analyse als abzubrechen; der Progress-Callback raised EAbort
// beim naechsten Update und unwindet so aus AnalyzeLeaksRecursive heraus.
begin
  if not Assigned(FAnalyseProgress) or not FAnalyseProgress.Running then Exit;
  FAnalyseProgress.RequestCancel;
  StatusMode(_('Cancelling analysis...'));
end;

procedure TAnalyserFrame.EditIgnoreListClick(Sender: TObject);
// Oeffnet die Ignore-Liste mit dem System-Default-Editor (Notepad).
// Nach Schliessen muss der User die Analyse neu starten - die Datei wird
// hier sofort nachgeladen, damit der naechste Lauf die Aenderungen sieht.
var
  Path: string;
begin
  if not Assigned(FIgnoreList) then Exit;
  FIgnoreList.EnsureConfigExists;
  Path := FIgnoreList.ConfigFilePath;

  // Datei mit Default-Editor oeffnen (ShellExecute via "open"-Verb).
  // Bei Misserfolg: Pfad in Statusleiste, damit User manuell oeffnen kann.
  try
    ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    StatusMode(_('Could not open editor. File: ') + Path);
    Exit;
  end;

  // Liste sofort neu laden, damit Aenderungen ohne Frame-Neustart wirken
  try FIgnoreList.LoadDefault; except end;
  StatusMode(Format(
    'Ignore-Liste neu geladen (%d Muster). Pfad: %s',
    [FIgnoreList.PatternCount, Path]));
end;

procedure TAnalyserFrame.EditRepoSettingsClick(Sender: TObject);
// Oeffnet analyser.ini im Default-Editor. PrepareAnalysis (vor jedem
// Analyse-Lauf) ruft FRepoSettings.Load - damit greifen Aenderungen beim
// naechsten Klick auf "Start analysis", "Current file" ODER "Branch-
// Changes" gleichermassen.
var
  Path: string;
begin
  if not Assigned(FRepoSettings) then Exit;
  FRepoSettings.EnsureConfigExists;
  Path := FRepoSettings.ConfigFilePath;

  try
    ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    StatusMode(_('Could not open editor. File: ') + Path);
    Exit;
  end;

  StatusMode(Format(_('Settings: %s - changes take effect on the next analysis run.'),
    [Path]));
end;

function TAnalyserFrame.ScaleW(AValue: Integer): Integer;
// DPI-Skalierung: konvertiert 96-DPI-Designwerte zur aktuellen Container-
// PPI. Wird aus CreateUI fuer JEDE Width/Height-Zuweisung gerufen, damit
// das Plugin auf High-DPI-Displays nicht winzig wirkt.
var
  PPI : Integer;
begin
  PPI := CurrentPPI;
  if PPI <= 0 then PPI := 96;
  Result := MulDiv(AValue, PPI, 96);
end;

procedure TAnalyserFrame.FrameResize(Sender: TObject);
// Triggert den zentralen Responsive-Controller. Frueher 4 Panel-OnResize-
// Forwards; nicht mehr noetig - FResponsive ist auf Self.OnResize gehookt
// und ApplyVisibility deckt alle Stufen + AfterApply-Callbacks ab.
// Wir rufen ForceUpdate explizit damit die IDE-Dock-Logik (die OnResize
// nicht immer feuert) sicher abgedeckt ist.
begin
  if Assigned(FResponsive) then
    FResponsive.ForceUpdate;
end;

procedure TAnalyserFrame.ResponsiveAfterApply(Sender: TObject);
// Wird nach jedem Resize von FResponsive aufgerufen. Sammelt die zwei
// dynamischen Anpassungen die nicht pure on/off sind:
//   1) FilterSubPanels-Width (haengt an Label-Visibility)
//   2) SearchEdit-MinWidth (haengt an freier Toolbar-Restbreite)
begin
  if Assigned(FPanelButtons) then AdjustFilterSubPanels(FPanelButtons);
  if Assigned(FPanelSearch)  then AdjustSearchMinWidth(FPanelSearch);
end;

procedure TAnalyserFrame.AdjustSearchMinWidth(Sender: TObject);
// MinWidth dynamisch berechnen: Wunsch-Wert cappen auf den tatsaechlich
// freien Platz zwischen alLeft + alRight Buttons. Sonst kann das alClient-
// Edit die rechten Buttons (Cancel/Export) ueberlagern wenn die Toolbar-
// Breite zwar > Threshold ist, aber die Buttons-Summe + Wunsch-MinWidth
// trotzdem nicht reinpasst.
//
// 3-Tier-Logik:
//   NARROW (< 500): kleiner MinWidth (60) - in Stufe 1 muss SearchEdit
//                   sich auch in 300-400 px breiten Docks behaupten.
//   MEDIUM/FULL (>= 500): grosser MinWidth (120) - genug Toolbar-Breite
//                         da, das Edit darf nicht zur Reststreifen werden.
// Die ClientWidth-Schwelle ist BREAKPOINT_MEDIUM, weil schon ab Stufe 2
// die optionalen Buttons (Settings/Ignore/Cancel) zurueckkommen und das
// Edit nicht mehr alleine die Toolbar dominiert.
var
  i        : Integer;
  C        : TControl;
  ButtonsW : Integer;
  Avail    : Integer;
  Wanted   : Integer;
begin
  if not Assigned(FSearchEdit) or not Assigned(FPanelSearch) then Exit;

  // Summe aller sichtbaren alLeft + alRight Children (inkl. Margins).
  ButtonsW := 0;
  for i := 0 to FPanelSearch.ControlCount - 1 do
  begin
    C := FPanelSearch.Controls[i];
    if (C = FSearchEdit) or not C.Visible then Continue;
    if C.Align in [alLeft, alRight] then
    begin
      ButtonsW := ButtonsW + C.Width;
      if C.AlignWithMargins then
        ButtonsW := ButtonsW + C.Margins.Left + C.Margins.Right;
    end;
  end;

  // Freier Platz fuer alClient (Search-Edit).
  Avail := FPanelSearch.ClientWidth - ButtonsW
         - FPanelSearch.Padding.Left - FPanelSearch.Padding.Right;

  // Wunsch: FLOATED-Width ab MEDIUM-Tier (>=500 px), DOCKED-Width im
  // NARROW-Tier (<500 px). Bei knappem Platz auf Avail cappen, damit
  // das Edit nicht die alRight-Buttons ueberlagert. Fallback auf 0 wenn
  // wirklich kein Platz uebrig (Responsive-Controller blendet dann sowieso
  // bei den Breakpoints ueberzaehlige Buttons aus).
  if FPanelSearch.ClientWidth >= ScaleW(BREAKPOINT_MEDIUM) then
    Wanted := ScaleW(SEARCH_MIN_WIDTH_FLOATED)
  else
    Wanted := ScaleW(SEARCH_MIN_WIDTH_DOCKED);
  if Wanted > Avail then
    Wanted := Max(0, Avail);

  FSearchEdit.Constraints.MinWidth := Wanted;
end;

procedure TAnalyserFrame.AdjustFilterSubPanels(Sender: TObject);
// Sub-Panel-Width = Label-Anteil (nur wenn Label sichtbar) + Combo-Anteil.
// Im NARROW-Modus sind die Labels hidden -> Sub-Panels schrumpfen entsprechend.
// Sonst wuerden FPanelSev/FPanelType weiterhin die volle Label+Combo-Breite
// belegen und PanelButtons platzen.
begin
  if Assigned(FPanelSev) and Assigned(FLblFilter) then
  begin
    if FLblFilter.Visible then
      FPanelSev.Width := ScaleW(LBL_W_FILTER + CMB_W_FILTER)
    else
      FPanelSev.Width := ScaleW(CMB_W_FILTER);
  end;
  if Assigned(FPanelType) and Assigned(FLblType) then
  begin
    if FLblType.Visible then
      FPanelType.Width := ScaleW(LBL_W_TYPE + CMB_W_TYPE)
    else
      FPanelType.Width := ScaleW(CMB_W_TYPE);
  end;
  if Assigned(FPanelProfile) and Assigned(FLblProfile) then
  begin
    if FLblProfile.Visible then
      FPanelProfile.Width := ScaleW(LBL_W_PROFILE + CMB_W_PROFILE)
    else
      FPanelProfile.Width := ScaleW(CMB_W_PROFILE);
  end;
end;

procedure TAnalyserFrame.BuildHamburgerMenu;
// Popup-Menu fuer den Hamburger-Button. Im NARROW-Modus (<500 px) sind
// ALLE Toolbar-Tasten ausgeblendet - das Hamburger-Menu ist die einzige
// Aktions-Quelle. Im MEDIUM-Modus (500-849) sind die meisten Tasten wieder
// da, das Menu bleibt aber redundant erreichbar (kein Schaden).
//
// Reihenfolge (logische Gruppen, jeweils durch Separator getrennt):
//   1. Analyse-Aktionen: Voll, Aktuelle Datei, Branch-Changes
//   2. Cancel (laufende Analyse abbrechen)
//   3. Ressourcen: Browse (Projekt-Pfad), Export
//   4. Konfig: Settings, Ignore-Liste
var
  MI : TMenuItem;
begin
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := HamburgerMenuPopup;

  // ---- Aktions-Block (nur Branch-Changes; Analyse + File sind im
  // Toolbar IMMER sichtbar und brauchen daher keinen Menu-Eintrag) -------
  FMIAnalyseChanged := TMenuItem.Create(FHamburgerMenu);
  FMIAnalyseChanged.Caption := _('Analyse Branch-Changes');
  FMIAnalyseChanged.OnClick := AnalyseChangedFilesClick;
  FHamburgerMenu.Items.Add(FMIAnalyseChanged);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Cancel (Enabled wird in HamburgerMenuPopup gesynct) -------------
  FMICancel := TMenuItem.Create(FHamburgerMenu);
  FMICancel.Caption := _('Cancel Analysis');
  FMICancel.OnClick := CancelAnalyseClick;
  FHamburgerMenu.Items.Add(FMICancel);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Ressourcen-Block: Export ----------------------------------------
  // (Browse ist nicht im Menu - der "..."-Button ist immer im Toolbar sichtbar)
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Export') + '...';
  MI.OnClick := HamburgerExportClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Konfig-Block: oeffnet externe Editoren, kein Analyse-Trigger ----
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Settings...');
  MI.OnClick := EditRepoSettingsClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Ignore list...');
  MI.OnClick := EditIgnoreListClick;
  FHamburgerMenu.Items.Add(MI);

  FBtnHamburger.PopupMenu := FHamburgerMenu;
  // Standard-Behavior von TButton.PopupMenu ist Rechtsklick - hier wollen
  // wir Linksklick. HamburgerClick wirft das Popup unter dem Button auf
  // (gleicher Pattern wie der Export-Button).
  FBtnHamburger.OnClick := HamburgerClick;
end;

procedure TAnalyserFrame.HamburgerMenuPopup(Sender: TObject);
// Enabled-Zustand der Live-Items vor dem Oeffnen des Menus synchronisieren -
// die zugehoerigen Buttons werden vom TAnalyseProgressController waehrend
// einer laufenden Analyse toggled. Cancel ist umgekehrt: nur waehrend
// Analyse aktiv.
begin
  if Assigned(FMICancel) and Assigned(FBtnCancel) then
    FMICancel.Enabled := FBtnCancel.Enabled;
  if Assigned(FMIAnalyseChanged) and Assigned(FBtnAnalyseChanged) then
    FMIAnalyseChanged.Enabled := FBtnAnalyseChanged.Enabled;
end;

procedure TAnalyserFrame.HamburgerClick(Sender: TObject);
// Klick auf den Hamburger-Button -> Popup-Menu unter dem Button anzeigen.
// Position: linke untere Ecke des Buttons (in Screen-Koordinaten).
var
  P : TPoint;
begin
  if not Assigned(FBtnHamburger) or not Assigned(FHamburgerMenu) then Exit;
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FHamburgerMenu.Popup(P.X, P.Y);
end;

procedure TAnalyserFrame.HamburgerExportClick(Sender: TObject);
// Hamburger-Menu-Item "Export...": oeffnet dasselbe Popup wie der
// BtnExport, aber an der Hamburger-Button-Position. Im NARROW-Modus
// ist BtnExport hidden - das Hamburger-Item ist die einzige Quelle.
var
  P : TPoint;
begin
  if not Assigned(FBtnHamburger) or not Assigned(FExportMenu) then Exit;
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FExportMenu.PopupAt(P.X, P.Y);
end;

// ---------------------------------------------------------------------------
// Stat-Tile Klick-Handler: setzen Severity- bzw. Type-Filter.
// Sender.Tag = Ord(TFilterMode) bzw. Ord(TTypeFilter).
// FilterCombo.OnChange feuert -> ApplyFilter laeuft automatisch.
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.TileClickSeverity(Sender: TObject);
// WICHTIG: TComboBox.ItemIndex-Setter feuert OnChange NICHT (nur User-
// Interaktion tut das). Wir muessen FilterChange/TypeFilterChange explizit
// aufrufen, sonst aktualisiert sich das Grid nicht.
var
  Target  : TFilterMode;
  i, OrdT : Integer;
begin
  if not Assigned(FFilterCombo) or not (Sender is TComponent) then Exit;
  Target := TFilterMode(TComponent(Sender).Tag);
  if Assigned(FTypeCombo) and (FTypeCombo.ItemIndex <> 0) then
    FTypeCombo.ItemIndex := 0;
  OrdT := Ord(Target);
  for i := 0 to FFilterCombo.Items.Count - 1 do
    if Integer(FFilterCombo.Items.Objects[i]) = OrdT then
    begin
      FFilterCombo.ItemIndex := i;
      // Erst Type-Filter-Change (Type wurde reset, damit der Severity-
      // Filter sicher greift), dann Filter-Change (eigentlicher Klick-
      // Effekt). Beide Handler rufen letztlich ApplyFilter -> Grid
      // wird einmal redrawn (kein Doppel-Repaint, ApplyFilter selbst
      // ist idempotent gegen denselben Stand).
      TypeFilterChange(FTypeCombo);
      FilterChange(FFilterCombo);
      Exit;
    end;
end;

procedure TAnalyserFrame.TileClickType(Sender: TObject);
var
  Target : TTypeFilter;
begin
  if not Assigned(FTypeCombo) or not (Sender is TComponent) then Exit;
  Target := TTypeFilter(TComponent(Sender).Tag);
  if Assigned(FFilterCombo) and (FFilterCombo.ItemIndex <> 0) then
    FFilterCombo.ItemIndex := 0;
  FTypeCombo.ItemIndex := Ord(Target);
  // ItemIndex-Setter feuert KEIN OnChange - explizit triggern.
  FilterChange(FFilterCombo);
  TypeFilterChange(FTypeCombo);
end;

procedure TAnalyserFrame.TileClickClear(Sender: TObject);
// Codequalitaet-Kachel: kein semantischer Filter (Score ist eine Aggregation).
// Klick setzt beide Filter auf "Alle" zurueck - praktisch als Reset-Button.
begin
  if Assigned(FFilterCombo) then FFilterCombo.ItemIndex := 0;
  if Assigned(FTypeCombo)   then FTypeCombo.ItemIndex   := 0;
  // ItemIndex-Setter feuert KEIN OnChange - explizit triggern.
  if Assigned(FFilterCombo) then FilterChange(FFilterCombo);
  if Assigned(FTypeCombo)   then TypeFilterChange(FTypeCombo);
end;

// ---------------------------------------------------------------------------
// Doppelklick -> Datei in IDE oeffnen, direkt zur gefundenen Zeile springen
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridDblClick(Sender: TObject);
var
  row, idx: Integer;
  absPath : string;
  lineNo  : Integer;
  F       : TLeakFinding;
begin
  row := FResultGrid.Row;
  if row < 1 then Exit;
  idx := row - 1;
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;

  F       := FDisplayedFindings[idx];
  absPath := F.FileName;
  lineNo  := StrToIntDef(F.LineNumber, 0);
  if absPath = '' then Exit;

  if not FileExists(absPath) then
  begin
    StatusMode(_('File not found: ') + absPath);
    Exit;
  end;

  // Bei .dfm-Befund hat OpenFileAtLine drei moegliche Auspraegungen:
  //   ofmRegular         -> .pas-Befund, ganz normal
  //   ofmDfmAsText       -> .pas war zu (oder nicht modifiziert) -> die
  //                         DFM wurde geschlossen und als Text wieder
  //                         geoeffnet. CursorPos zeigt direkt auf die
  //                         Befund-Zeile in der DFM.
  //   ofmDfmFallbackPas  -> .pas war modifiziert; statt sie zu zerstoeren
  //                         oeffnen wir die .pas, Cursor auf Zeile 1. User
  //                         schaltet bei Bedarf via Alt+F12 zur DFM-Text-
  //                         Sicht und kennt die DFM-Zeile aus dem Hint.
  var Mode: TOpenFileMode := OpenFileAtLine(absPath, lineNo);
  // Editor-Line-Highlights setzen — Datei ist jetzt offen, alle Befunde
  // der Datei werden mit Stripe markiert (Multi-Marker-Modell).
  HighlightAllFindingsInFile(absPath);
  case Mode of
    ofmDfmAsText:
      StatusMode(Format(_('DFM as text: %s  Line: %d'),
        [ExtractFileName(absPath), lineNo]));
    ofmDfmFallbackPas:
      StatusMode(Format(
        _('DFM finding at line %d - .pas is modified, press Alt+F12 to view DFM as text'),
        [lineNo]));
  else
    StatusMode(Format(_('Opened: %s  Line: %d'),
      [ExtractFileName(absPath), lineNo]));
  end;
end;

procedure TAnalyserFrame.HighlightAllFindingsInFile(const AFileName: string);
// Multi-File-Marker-Refresh: bauen Eintraege fuer ALLE Dateien der
// aktuellen FDisplayedFindings-Liste und uebergeben sie an den
// GHighlighter. Der AFileName-Parameter ist nur noch ein Vermerk
// "welche Datei hat den Refresh angefordert" - das Ergebnis ist
// dasselbe, egal wer ihn ausloest. Der Highlighter zeigt die
// Marker auf JEDEM Editor-Tab dessen Datei in FDisplayedFindings
// vertreten ist; Tab-Wechsel funktioniert ohne weiteren Refresh.
//
// Pro Marker:
//   - FileName  -> Bucket-Schluessel im Multi-File-Marker-Dictionary
//   - Title/Desc/Badge/Fix -> Hover-Overlay-Inhalt
//   - Color via SeverityAccent (Severity-abhaengige Stripe-Farbe wie im Grid)
//
// Marker-Anzahl ist <= FDisplayedFindings.Count; bei 5000+ Findings
// kostet die Liste etwa 2-3 MB Heap - akzeptabel, Lookup ist O(1)
// per Datei.
var
  i       : Integer;
  F       : TLeakFinding;
  Entries : TArray<TFindingMarkEntry>;
  Count   : Integer;
  LineNo  : Integer;
  DispSev : TFindingSeverity;
begin
  if not Assigned(GHighlighter) or not Assigned(FDisplayedFindings) then Exit;

  SetLength(Entries, FDisplayedFindings.Count);
  Count := 0;
  for i := 0 to FDisplayedFindings.Count - 1 do
  begin
    F := FDisplayedFindings[i];
    if not Assigned(F) then Continue;
    if F.FileName = '' then Continue;
    LineNo := StrToIntDef(F.LineNumber, 0);
    if LineNo <= 0 then Continue;
    DispSev := SeverityFromKindLevel(F.Kind, F.Severity);
    var FH := FixHint(F);
    Entries[Count].FileName := F.FileName;
    Entries[Count].Line     := LineNo;
    Entries[Count].Title    := F.MissingVar;
    Entries[Count].Desc     := FH.Description;
    Entries[Count].Badge    := F.TypeText + _(' · ') + F.SeverityText;
    Entries[Count].Color    := SeverityAccent(DispSev);
    Entries[Count].Fix      := FH.After;   // Nachher-Code im Hover-Overlay
    Inc(Count);
  end;
  SetLength(Entries, Count);

  GHighlighter.SetAllFindings(Entries);
end;

function TAnalyserFrame.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer): TOpenFileMode;
// Thin-Wrapper - Logik in uIDEEditorIntegration.TIDEEditor (mit
// Supports-Casts statt as-Cast). Behalten als Frame-Methode weil
// GridDblClick es aufruft und der Lifecycle-Sentinel-Schutz weiter
// ueber den Frame laufen soll (Defensive: kein OpenFile wenn der
// Frame gerade zerstoert wird).
begin
  Result := ofmRegular;
  if GLiveAnalyserFrame <> Pointer(Self) then Exit;
  Result := TIDEEditor.OpenFileAtLine(AbsPath, LineNumber);
end;

procedure TAnalyserFrame.CMStyleChanged(var Message: TMessage);
begin
  inherited;
  // VCL-Style-Wechsel und IDE-Theme-Wechsel laufen am Ende durch denselben
  // Refresh-Pfad. Verhindert dass der Code in zwei Routinen synchron
  // gehalten werden muss. Message-Handler bleibt klassen-gebunden, der
  // Body delegiert nur.
  RefreshFromIDETheme;
end;

procedure TAnalyserFrame.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent <> nil) and not (csDestroying in ComponentState) then
  begin
    RefreshFromIDETheme;
    if HandleAllocated then
    begin
      // Sofortiger deferred Pass: IDE setzt Dock-Bounds NACH SetParent.
      PostMessage(Handle, WM_SCA_REFIT, 0, 0);
      // Timer-gesicherter zweiter Pass (300 ms): ProcessMessages waehrend
      // der IDE-Drag-Animation kann den PostMessage oben zu frueh leeren
      // (noch vor dem finalen Bounds-Set). 300 ms > HintPanel-Polling-
      // Intervall (250 ms) - damit sind Dock-Animation und Floating-Property
      // sicher stabil. Timer laeuft unabhaengig vom Message-Queue-Timing.
      if not Assigned(FDockRefitTimer) then
      begin
        FDockRefitTimer          := TTimer.Create(Self);
        FDockRefitTimer.Interval := 300;
        FDockRefitTimer.OnTimer  := DockRefitTimerFired;
      end;
      FDockRefitTimer.Enabled := False;
      FDockRefitTimer.Enabled := True;
    end;
  end;
end;

procedure TAnalyserFrame.WMScaRefit(var Message: TMessage);
var
  W: Integer;
begin
  // AlignControls ist durch csLoading blockiert (IDE-Dock-Restore via DFM).
  // Panels sind dynamisch erstellt (kein csLoading) - direktes Width-Setzen
  // umgeht den Block; Panel.OnResize faellt aus -> Controller reagiert.
  // Self.ClientWidth via Win32 GetClientRect - immer korrekt, auch bei
  // blockiertem AlignControls.
  W := ClientWidth;
  if (W > 0) and Assigned(FPanelPath) then
  begin
    if FPanelPath.Width    <> W then FPanelPath.Width    := W;
    if FPanelButtons.Width <> W then FPanelButtons.Width := W;
    if FPanelSearch.Width  <> W then FPanelSearch.Width  := W;
    if FPanelStats.Width   <> W then FPanelStats.Width   := W;
  end;
  FrameResize(Self);
end;

procedure TAnalyserFrame.DockRefitTimerFired(Sender: TObject);
// One-Shot (300 ms nach SetParent): garantiert FrameResize NACH dem
// vollstaendigen Dock-Vorgang. 300 ms > HintPanel-Polling (250 ms),
// sodass IDE-Dock-Animation und DFM-Restore sicher abgeschlossen sind.
// Bypassed AlignControls (csLoading-Block) durch direktes Panel-Width-Setzen.
var
  W: Integer;
begin
  FDockRefitTimer.Enabled := False;
  if not HandleAllocated then Exit;
  W := ClientWidth;
  if (W > 0) and Assigned(FPanelPath) then
  begin
    if FPanelPath.Width    <> W then FPanelPath.Width    := W;
    if FPanelButtons.Width <> W then FPanelButtons.Width := W;
    if FPanelSearch.Width  <> W then FPanelSearch.Width  := W;
    if FPanelStats.Width   <> W then FPanelStats.Width   := W;
  end;
  FrameResize(Self);
end;

procedure TAnalyserFrame.Resize;
// VCL-Override: feuert bei JEDEM Bounds-Change (Dock, Undock, Manual-
// Resize, Parent-Re-Layout). Robuster als das OnResize-Event, das die
// IDE-Dock-Logik bei Float->Dock-Transitions teilweise verschluckt.
begin
  inherited;
  // Hilfe-Panel-Layout (Dock-Sync + 1/3-Breite + Vorher/Nachher-Haelften)
  // ist nach uIDEHelpPanel.TFindingHintPanel.ApplyLayout ausgelagert.
  if Assigned(FHintPanel) then
    FHintPanel.ApplyLayout;
  if Assigned(FResultGrid) then
    GridResize(FResultGrid);
  // Sofortiger Pass - kann stale Panel-Breiten sehen falls VCL-AlignControls
  // fuer die Child-Panels noch nicht propagiert hat (RequestAlign/CM_ALIGN
  // laeuft manchmal versetzt gegenueber Frame.Resize).
  FrameResize(Self);
  // Deferred zweiter Pass: korrekte Panel-Breiten nach abgeschlossener
  // VCL-Alignment-Kaskade. Zusammen mit dem PostMessage in SetParent
  // deckt das beide Dock-Races ab.
  if HandleAllocated then
    PostMessage(Handle, WM_SCA_REFIT, 0, 0);
end;

// ---------------------------------------------------------------------------
// Grid-Zeichnen
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridResize(Sender: TObject);
// Thin Delegate - Logik in uFindingGridRenderer.TFindingGridLayout.
// Wrapper bleibt bestehen weil das OnResize-Event ein method-of-object
// erwartet. Standalone uMainForm nutzt denselben Helper.
begin
  TFindingGridLayout.SetColumnWidths(FResultGrid);
end;

procedure TAnalyserFrame.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
// Implementation in UI/uFindingGridRenderer.pas - hier nur die Frame-
// spezifische Konfiguration uebergeben (Severity-Spalte 5, Theme an,
// Sort-Indicator mit unserem aktuellen Sort-State).
//
// Virtual-Mode: Datenzeilen-Inhalt wird ueber GetCellText aus
// FDisplayedFindings gezogen statt aus FResultGrid.Cells[] - das spart
// bei 66k+ Befunden ~50-100 MB Cell-String-Allokationen
// (32-Bit-Process-Limit).
var
  Config : TFindingGridConfig;
begin
  Config := TFindingGridRenderer.IDEConfig(FSortColumn, FSortDescending);
  Config.GetCellText :=
    function(ACellCol, ACellRow: Integer): string
    var
      f : TLeakFinding;
    begin
      if ACellRow = 0 then
        Result := FResultGrid.Cells[ACellCol, 0]
      else if (FDisplayedFindings <> nil) and
              (ACellRow >= 1) and
              (ACellRow <= FDisplayedFindings.Count) then
      begin
        f := FDisplayedFindings[ACellRow - 1];
        case ACellCol of
          0: Result := ExtractFileName(f.FileName);
          1: Result := f.MethodName;
          2: Result := f.LineNumber;
          3: Result := f.TypeText;
          4: Result := f.MissingVar;
          5: Result := f.SeverityText;
        else
          Result := '';
        end;
      end
      else
        // Placeholder-Zeile (z.B. 'Keine Eintraege...') - aus Cells lesen.
        Result := FResultGrid.Cells[ACellCol, ACellRow];
    end;
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State, Config);
end;

// ---------------------------------------------------------------------------
// Recent Paths -- duenne Wrapper um TRecentPaths (Common/uRecentPaths.pas).
// Pinned-Eintrag = aktuell geoeffnetes IDE-Projekt, Position 0.
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.LoadRecentPaths;
begin
  // Defekte INI darf das Frame nicht reissen - die IDE wuerde sonst
  // mit einem Plugin-Lade-Fehler hochkommen.
  try
    TRecentPaths.Load(
      FProjectPath, GetIniPath,
      DEFAULT_MAX_RECENT,
      GetCurrentIDEProjectDir, ppFirst);
  except
    FProjectPath.Items.Clear;
    FProjectPath.Text := '';
  end;
end;

procedure TAnalyserFrame.SaveRecentPath(const APath: string);
begin
  TRecentPaths.Save(
    FProjectPath, GetIniPath, APath,
    DEFAULT_MAX_RECENT,
    GetCurrentIDEProjectDir, ppFirst);
end;

// ---------------------------------------------------------------------------
// TAnalyserDockableForm
// ---------------------------------------------------------------------------

function TAnalyserDockableForm.GetCaption: string;
begin
  Result := 'Static Code Analysis';
end;

function TAnalyserDockableForm.GetIdentifier: string;
begin
  Result := 'StaticCodeAnalyser.DockForm';
end;

function TAnalyserDockableForm.GetFrameClass: TCustomFrameClass;
begin
  Result := TAnalyserFrame;
end;

procedure TAnalyserDockableForm.FrameCreated(AFrame: TCustomFrame);
var
  F        : TAnalyserFrame;
  HostForm : TCustomForm;
begin
  FFrame := AFrame as TAnalyserFrame;
  F := FFrame;
  // IDE kann die Schrift des Frames beim Einbetten ueberschreiben ->
  // hier explizit nach dem Hosting nochmal setzen.
  F.Font.Name := 'Segoe UI';
  F.Font.Size := 8;
  F.FResultGrid.Font.Name := 'Segoe UI';
  F.FResultGrid.Font.Size := 8;
  F.FProjectPath.Font.Name := 'Segoe UI';
  F.FProjectPath.Font.Size := 8;

  // Floated-Mindestbreite/-hoehe auf das IDE-Host-Form propagieren.
  // Frame.Constraints schuetzt nur den Frame selbst - im undocked Zustand
  // bestimmt das Host-Form die tatsaechliche Fensterbreite. GetParentForm
  // walks die Parent-Kette hoch bis zum naechsten TCustomForm.
  HostForm := GetParentForm(F);
  if Assigned(HostForm) then
  begin
    if HostForm.Constraints.MinWidth < F.Constraints.MinWidth then
      HostForm.Constraints.MinWidth := F.Constraints.MinWidth;
    if HostForm.Constraints.MinHeight < F.Constraints.MinHeight then
      HostForm.Constraints.MinHeight := F.Constraints.MinHeight;
  end;

  // IDE-Theme einmalig anwenden + Notifier registrieren. Logik
  // ist nach uIDEThemeIntegration.TIDEThemeIntegration.Attach
  // ausgelagert - der Helper wurde im Frame-Ctor erstellt und
  // wartet bis hier auf seinen ersten "es gibt einen Hosting-
  // Kontext"-Trigger.
  if Assigned(F.FThemeIntegration) then
    F.FThemeIntegration.Attach;
end;

function TAnalyserDockableForm.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TAnalyserDockableForm.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TAnalyserDockableForm.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
  // no customization
end;

function TAnalyserDockableForm.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TAnalyserDockableForm.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TAnalyserDockableForm.CustomizeToolBar(ToolBar: TToolBar);
begin
  // no toolbar
end;

procedure TAnalyserDockableForm.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
  // nothing to persist
end;

procedure TAnalyserDockableForm.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
  // nothing to restore
end;

function TAnalyserDockableForm.GetEditState: TEditState;
begin
  Result := [];
end;

function TAnalyserDockableForm.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure TAnalyserDockableForm.ViewMenuClick(Sender: TObject);
begin
  ShowAnalyserDockableForm;
end;

// Forward-Deklaration: die Silent-Mode-Procedures sind weiter unten in
// dieser Unit definiert (nahe dem Editor-Kontext-Menu-Hook), aber der
// AnalyseCurrentFromEditorMenuClick-Handler oben braucht sie.
procedure RunSilentAnalysisForCurrentEditorFile; forward;

procedure TAnalyserDockableForm.AnalyseCurrentFromEditorMenuClick(
  Sender: TObject);
// Silent-Mode: aktive Editor-Datei analysieren + Marker direkt setzen.
// Dock-Fenster bleibt geschlossen, kein Frame, kein Befund-Grid - nur
// die Annotation-Overlays (3 px Stripe + Hover-Popup) im Editor.
//
// Wenn der User das Grid sehen will: ueber das View-Menue 'Static Code
// Analysis' das Dock oeffnen + dort die Buttons benutzen.
begin
  RunSilentAnalysisForCurrentEditorFile;
end;

// ---------------------------------------------------------------------------
// Registrierung und Anzeige
// ---------------------------------------------------------------------------

var
  GViewMenuItem        : TMenuItem = nil;

// ----------------------------------------------------------------------------
// Silent-Mode (Editor-Kontextmenu -> direkter Annotation-Overlay, kein Dock)
// ----------------------------------------------------------------------------
//
// Frame-freie Pipeline: aktuelle Datei -> AnalyzeLeaks -> Mark-Entries ->
// GHighlighter.SetAllFindings. Marker (Stripe + Hover-Overlay) erscheinen im
// Editor; das Dock-Fenster wird NICHT geoeffnet, kein Befund-Grid.
//
// Fehler werden an OutputDebugString geleitet (keine Frame-StatusBar im
// Silent-Mode verfuegbar).
//
// Threading: laeuft synchron im UI-Thread. AnalyzeLeaks fuer eine einzelne
// .pas-Datei ist typischerweise <200 ms - akzeptabel. Wenn das pro Datei
// zu langsam wird, kann der Aufruf in einen TThread.Queue-Worker umziehen
// (analog uIDEWatchMode.TWatchAnalyzer).

function BuildMarkEntries(Findings: TObjectList<TLeakFinding>): TArray<TFindingMarkEntry>;
// Konvertiert eine Liste von TLeakFinding zu TFindingMarkEntry[]. Logik
// dupliziert aus Frame.HighlightAllFindingsInFile, jetzt Frame-frei damit
// auch der Silent-Mode sie nutzen kann.
var
  i, Count : Integer;
  F        : TLeakFinding;
  LineNo   : Integer;
  DispSev  : TFindingSeverity;
begin
  if not Assigned(Findings) then Exit(nil);
  SetLength(Result, Findings.Count);
  Count := 0;
  for i := 0 to Findings.Count - 1 do
  begin
    F := Findings[i];
    if not Assigned(F) then Continue;
    if F.FileName = '' then Continue;
    LineNo := StrToIntDef(F.LineNumber, 0);
    if LineNo <= 0 then Continue;
    DispSev := SeverityFromKindLevel(F.Kind, F.Severity);
    // TFixHintResolver.FixHint statt bare FixHint: hier sind wir NICHT in
    // einer TAnalyserFrame-Methode (wo der Klassen-Wrapper Self.FixHint
    // greift), sondern in einer Top-Level-Procedure - direkter Resolver-Call.
    var FH := TFixHintResolver.FixHint(F);
    Result[Count].FileName := F.FileName;
    Result[Count].Line     := LineNo;
    Result[Count].Title    := F.MissingVar;
    Result[Count].Desc     := FH.Description;
    Result[Count].Badge    := F.TypeText + _(' · ') + F.SeverityText;
    Result[Count].Color    := SeverityAccent(DispSev);
    Result[Count].Fix      := FH.After;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

procedure RunSilentAnalysisForFile(const AFileName: string);
// Silent-Mode-Entrypoint: analysiert AFileName + setzt Marker direkt am
// GHighlighter. Kein Frame, kein Dock-Open. Fehler still an
// OutputDebugString. Settings + Profile werden frisch geladen (analog zu
// WatchMode-Worker).
var
  Settings : TRepoSettings;
  Findings : TObjectList<TLeakFinding>;
  Entries  : TArray<TFindingMarkEntry>;
begin
  if AFileName = '' then Exit;
  if not Assigned(GHighlighter) then Exit;
  if not FileExists(AFileName) then
  begin
    OutputDebugString(PChar(Format(
      'SCA Silent: file not found: %s', [AFileName])));
    Exit;
  end;

  Settings := TRepoSettings.Create;
  Findings := nil;
  try
    try Settings.Load; except end;
    // IDE-Profile (Default 'ide-fast') aktivieren - sonst laeuft im Silent-
    // Mode der volle Standalone-Default-Lauf, was bei Live-Klicks zu lang
    // dauern wuerde.
    Settings.UseIdeRuleSet;
    // Dock-Combo gewinnt ueber INI - so wirkt eine Profile-Auswahl im Dock
    // auch im Silent-Run, ohne dass der User vorher Save druecken muss.
    // Wenn das Dock nie geoeffnet wurde, ist Frame=nil -> Override=leer ->
    // INI-Wert aus UseIdeRuleSet greift.
    if Assigned(GDockableForm) and Assigned(GDockableForm.Frame) then
    begin
      var DockOverride := GDockableForm.Frame.CurrentProfileOverride;
      if DockOverride <> '' then Settings.Profile := DockOverride;
    end;
    Settings.ApplyDetectorThresholds(ExtractFilePath(AFileName));
    Settings.RegisterToLeakyClasses;

    // Analog Dock-Plugin PrepareAnalysis: das AutoDiscover-
    // Global muss VOR AnalyzeLeaks aus den Settings gespiegelt werden -
    // uStaticAnalyzer2 prueft AutoDiscoverCustomClasses, nicht
    // Settings.AutoDiscoverClasses. Ohne diesen Zuweis bleibt das Flag auf
    // dem Wert vom letzten Dock-Run haengen (oder False beim Kalt-Start).
    AutoDiscoverCustomClasses := Settings.AutoDiscoverClasses;
    // Frische Discovery-Liste pro Silent-Run, sonst schleichen Treffer
    // vom letzten Dock-/Silent-Run in die Detection mit.
    if Assigned(uSCAConsts.DiscoveredClasses) then
      uSCAConsts.DiscoveredClasses.Clear;
    if Assigned(uSCAConsts.DiscoveredStaticClasses) then
      uSCAConsts.DiscoveredStaticClasses.Clear;

    try
      Findings := TStaticAnalyzer2.AnalyzeLeaks(AFileName, Settings.UsesCheck);
    except
      on E: Exception do
      begin
        OutputDebugString(PChar(Format(
          'SCA Silent: analyse error %s: %s: %s',
          [AFileName, E.ClassName, E.Message])));
        Exit;
      end;
    end;

    Entries := BuildMarkEntries(Findings);
    // SetAllFindings ersetzt komplett - bei Bedarf koennte man stattdessen
    // ReplaceMarksForFile nutzen damit Marker anderer Dateien erhalten
    // bleiben. SetAllFindings ist hier OK weil der Silent-Mode pro Klick
    // einen Snapshot setzt, der nur die geklickte Datei zeigt.
    GHighlighter.SetAllFindings(Entries);

    // Editor auf den ERSTEN Befund (= kleinste Zeile > 0) zentrieren -
    // sonst muesste der User die orange/rote Markierung am Editor-Rand
    // selber suchen. Datei-Level-Befunde (fkFileReadError, Line 0) zaehlen
    // nicht als Sprungziel. Erst nach SetAllFindings, damit der
    // GHighlighter-State bereits passt wenn der Editor neu zeichnet.
    var FirstLine : Integer := MaxInt;
    if Assigned(Findings) then
      for var F in Findings do
      begin
        if F.Kind = fkFileReadError then Continue;
        var LineN := StrToIntDef(F.LineNumber, 0);
        if (LineN > 0) and (LineN < FirstLine) then
          FirstLine := LineN;
      end;
    if FirstLine < MaxInt then
      TIDEEditor.CenterCurrentViewOnLine(FirstLine);
  finally
    Findings.Free;
    Settings.Free;
  end;
end;

function IsSilentEnabled: Boolean;
// Liest [Silent] Enabled aus analyser.ini - True wenn das User-Flag den
// Silent-Mode (Rechtsklick + Hotkey) aktiviert. Default True.
// Wird vor JEDEM Silent-Trigger gefragt damit die User-Konfig sofort wirkt -
// kein Plugin-Reload noetig.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    Result := Settings.SilentEnabled;
  finally
    Settings.Free;
  end;
end;

procedure RunSilentAnalysisForCurrentEditorFile;
// Holt die aktuell aktive Editor-Datei via TIDEEditor + ruft den Silent-
// Analyzer. Vorher Settings-Flag pruefen - User kann das Feature ueber
// Tools > Options ausschalten.
var
  FilePath : string;
begin
  if not IsSilentEnabled then Exit;
  case TIDEEditor.TryGetCurrentPasFile(FilePath) of
    cfrNoEditorService:
      OutputDebugString('SCA Silent: IDE editor service not available');
    cfrNoOpenView:
      OutputDebugString('SCA Silent: no file opened');
    cfrNotPascalFile:
      OutputDebugString('SCA Silent: current file is not a Pascal file');
  else
    RunSilentAnalysisForFile(FilePath);
  end;
end;

// ----------------------------------------------------------------------------
// Editor-Kontext-Menu-Hook via OnPopup-Chain
// ----------------------------------------------------------------------------
//
// Delphi 12 baut das Editor-Rechtsklick-Menue bei JEDEM Klick neu auf. Items
// die wir permanent in Popup.Items haengen, ueberleben den Rebuild nicht -
// und ein zweiter Permanent-Insert kollidiert mit IDE-Internals
// ('ecSwapCppHdrFiles existiert bereits').
//
// Saubere Loesung (GExperts/CnPack-Pattern, Quellen: dummzeuch.de blog,
// davidghoyle.co.uk):
//   1) Per INTAEditServicesNotifier auf WindowShow lauschen
//   2) Editor-Form-Components nach TPopupMenu durchsuchen
//   3) Pop's vorhandenes OnPopup-Event aufheben + eigenes Handler installieren
//   4) Unser Handler:
//      a) Alten SCA-Item raus + freigeben (vor IDE-Rebuild)
//      b) Original-OnPopup rufen -> IDE rebuilt komplett
//      c) Frisches Item am ENDE des Popups einhaengen
//   5) Beim Unload: Original-OnPopup wiederherstellen, Items freigeben
//
// Wichtig laut Recherche:
//   * Item AM ENDE des Popups einhaengen (sonst Action-Manager-Konflikt)
//   * NIEMALS Action zuweisen - nur OnClick (sonst ecSwapCppHdrFiles-Konflikt)
//   * OnPopup-Chain, nicht Overwrite (sonst broken bei mehreren Plugins)

type
  TPopupHookSlot = class
  public
    Popup       : TPopupMenu;
    OrigOnPopup : TNotifyEvent;
    OurItem     : TMenuItem;     // aktuelles Item; nil zwischen Popup-Shows
    constructor Create(APopup: TPopupMenu; AOrig: TNotifyEvent);
  end;

  TEditorContextMenuHook = class(TNotifierObject, INTAEditServicesNotifier)
  private
    // Pro gehooktem Popup ein Slot mit Original-Handler + aktuellem Item.
    // doOwnsValues: bei Remove/Clear/Destroy werden Slot-Objekte freigegeben.
    FSlots : TObjectDictionary<TPopupMenu, TPopupHookSlot>;
    procedure HookEditorForm(AForm: TCustomForm);
    function  FindEditorPopup(AForm: TCustomForm): TPopupMenu;
    procedure OnPopupHandler(Sender: TObject);
    procedure ItemClick(Sender: TObject);
  protected
    // INTAEditServicesNotifier
    procedure WindowShow(const EditWindow: INTAEditWindow;
      Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow;
      Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow;
      Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
  public
    constructor Create;
    destructor Destroy; override;
  end;

  // IOTAKeyboardBinding fuer Ctrl+Alt+A (Silent-Mode globaler Hotkey).
  // Wird via IOTAKeyboardServices.AddKeyboardBinding registriert und feuert
  // editor-weit - unabhaengig davon ob das Editor-Popup gerade konstruiert
  // wurde. Ersetzt das frueher genutzte TMenuItem.ShortCut, das nur nach
  // dem ersten Rechtsklick funktionierte.
  TSCAKeyboardBinding = class(TNotifierObject, IOTAKeyboardBinding)
  protected
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
  private
    procedure SilentAnalyseKeyProc(const Context: IOTAKeyContext;
      KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
  end;

var
  GCtxMenuHook    : TEditorContextMenuHook = nil;
  GCtxMenuHookIfc : INTAEditServicesNotifier = nil;
  GCtxMenuHookIdx : Integer = -1;
  GKeyBinding     : TSCAKeyboardBinding = nil;
  GKeyBindingIfc  : IOTAKeyboardBinding = nil;
  GKeyBindingIdx  : Integer = -1;

{ TPopupHookSlot }

constructor TPopupHookSlot.Create(APopup: TPopupMenu; AOrig: TNotifyEvent);
begin
  inherited Create;
  Popup       := APopup;
  OrigOnPopup := AOrig;
  OurItem     := nil;
end;

{ TEditorContextMenuHook }

constructor TEditorContextMenuHook.Create;
begin
  inherited;
  FSlots := TObjectDictionary<TPopupMenu, TPopupHookSlot>.Create([doOwnsValues]);
end;

destructor TEditorContextMenuHook.Destroy;
var
  Slot : TPopupHookSlot;
begin
  // Hooks loesen: pro Slot Original-OnPopup wiederherstellen (nur wenn unser
  // Handler noch dranhaengt) und unser Item freigeben. Try/except defensive
  // weil das Popup zwischenzeitlich vom IDE freigegeben sein koennte.
  if Assigned(FSlots) then
  begin
    for Slot in FSlots.Values do
    try
      if Assigned(Slot.Popup) then
      begin
        // Nur restoren wenn unser Handler noch installiert ist; sonst hat
        // ein anderes Plugin nach uns gehookt - dessen Chain wuerde brechen
        // wenn wir blind ueberschreiben. Vergleich via .Data (= Self) ist
        // robuster als .Code (vermeidet Method-vs-Class-Pointer-Syntax).
        if TMethod(Slot.Popup.OnPopup).Data = Pointer(Self) then
          Slot.Popup.OnPopup := Slot.OrigOnPopup;
      end;
      if Assigned(Slot.OurItem) then
      begin
        if Assigned(Slot.Popup) and (Slot.Popup.Items.IndexOf(Slot.OurItem) >= 0) then
          Slot.Popup.Items.Remove(Slot.OurItem);
        Slot.OurItem.Free;
        Slot.OurItem := nil;
      end;
    except
    end;
    FreeAndNil(FSlots);
  end;
  inherited;
end;

function TEditorContextMenuHook.FindEditorPopup(AForm: TCustomForm): TPopupMenu;
// Editor-Window-Form hat (typisch) ein TPopupMenu-Component fuer das Code-
// Editor-Rechtsklick-Menue. Bei mehreren Kandidaten wird der genommen mit
// den meisten Items (heuristik: Code-Editor-Menue ist umfangreichste).
var
  i : Integer;
begin
  Result := nil;
  if not Assigned(AForm) then Exit;
  for i := 0 to AForm.ComponentCount - 1 do
    if AForm.Components[i] is TPopupMenu then
    begin
      if (Result = nil) or
         (TPopupMenu(AForm.Components[i]).Items.Count > Result.Items.Count) then
        Result := TPopupMenu(AForm.Components[i]);
    end;
end;

procedure TEditorContextMenuHook.HookEditorForm(AForm: TCustomForm);
// Sucht Popup im Form. Wenn noch nicht gehookt: OnPopup aufheben + eigenes
// installieren. Idempotent (zweiter Aufruf auf gleichem Popup = no-op).
var
  Popup : TPopupMenu;
  Slot  : TPopupHookSlot;
begin
  Popup := FindEditorPopup(AForm);
  if not Assigned(Popup) then Exit;
  if FSlots.ContainsKey(Popup) then Exit;   // bereits gehookt

  Slot := TPopupHookSlot.Create(Popup, Popup.OnPopup);
  FSlots.Add(Popup, Slot);
  Popup.OnPopup := OnPopupHandler;
end;

procedure TEditorContextMenuHook.OnPopupHandler(Sender: TObject);
// Wird vor jedem Popup-Show gefeuert. Reihenfolge KRITISCH:
//   1) Eigener alter Item raus + freigeben - VOR IDE-Rebuild, damit der
//      Rebuild keine Inkonsistenzen sieht
//   2) Original-OnPopup rufen - IDE baut Menue komplett neu auf
//   3) Frisches Item ans ENDE - nach IDE-Rebuild, damit wir nicht
//      "wegrebuilt" werden
//
// Item hat Owner=nil + nur OnClick (kein Action) - vermeidet die
// IDE-Action-Manager-Kollisionen.
var
  Popup   : TPopupMenu;
  Slot    : TPopupHookSlot;
  NewItem : TMenuItem;
begin
  Popup := Sender as TPopupMenu;
  if not FSlots.TryGetValue(Popup, Slot) then Exit;

  // (1) Alten SCA-Eintrag vom letzten Show raus + freigeben
  if Assigned(Slot.OurItem) then
  begin
    try
      if Popup.Items.IndexOf(Slot.OurItem) >= 0 then
        Popup.Items.Remove(Slot.OurItem);
      Slot.OurItem.Free;
    except
    end;
    Slot.OurItem := nil;
  end;

  // (2) IDE-Rebuild via Original-Handler
  if Assigned(Slot.OrigOnPopup) then
    try Slot.OrigOnPopup(Sender); except end;

  // (3) Frischen SCA-Item ans Ende - nur wenn Silent-Mode aktiviert ist.
  // User-Setting (Tools > Options) wird bei jedem Popup-Show frisch
  // ausgewertet, damit Aenderungen sofort wirken.
  if not IsSilentEnabled then Exit;

  NewItem := TMenuItem.Create(nil);
  NewItem.Caption  := _('Analyse current file (silent)');
  NewItem.Hint     := _('Static Code Analyser: analyse this file, no dock opens');
  // ShortCut hier dient NUR der visuellen Anzeige im Popup ("Ctrl+Alt+A"
  // rechts neben Caption). Die echte Hotkey-Verarbeitung laeuft ueber
  // IOTAKeyboardBinding (TSCAKeyboardBinding), das den Key krHandled-marked
  // VOR VCL ihn sieht - kein Doppel-Trigger. Lifecycle der beiden Mechanismen
  // ist symmetrisch in Register/UnregisterAnalyserDockableForm gepaart.
  NewItem.ShortCut := ShortCut(Ord('A'), [ssCtrl, ssAlt]);
  NewItem.OnClick  := ItemClick;
  Popup.Items.Add(NewItem);
  Slot.OurItem := NewItem;
end;

procedure TEditorContextMenuHook.ItemClick(Sender: TObject);
// Delegiert an den Silent-Mode-Entrypoint. Kein Dock, kein Frame.
begin
  RunSilentAnalysisForCurrentEditorFile;
end;

// INTAEditServicesNotifier
procedure TEditorContextMenuHook.WindowShow(const EditWindow: INTAEditWindow;
  Show, LoadedFromDesktop: Boolean);
begin
  // Feuert vor allem fuer NEU erscheinende Editor-Windows. Bei Plugin-
  // Install nach IDE-Start sind die Fenster oft schon da -> WindowShow
  // verpasst sie. Defense-in-depth in WindowActivated + EditorViewActivated.
  if Show and Assigned(EditWindow) then
    HookEditorForm(EditWindow.Form);
end;

procedure TEditorContextMenuHook.WindowActivated(
  const EditWindow: INTAEditWindow);
begin
  // Feuert wenn der User in ein Editor-Window klickt / es fokussiert.
  // Bis dahin ist das TPopupMenu garantiert erzeugt (das ist normalerweise
  // lazy bei ersten Rechtsklick - aber WindowActivated kommt vor dem 1.
  // Rechtsklick). HookEditorForm ist idempotent.
  if Assigned(EditWindow) then
    HookEditorForm(EditWindow.Form);
end;

procedure TEditorContextMenuHook.EditorViewActivated(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  // Feuert bei jedem Tab-Wechsel. Triple-safety damit auch fuer Windows
  // die wir zum Plugin-Install-Zeitpunkt nicht gesehen haben (Desktop-
  // Restore, Plugin-Load-after-IDE-Start) der Hook spaetestens beim ersten
  // Tab-Klick installiert wird.
  if Assigned(EditWindow) then
    HookEditorForm(EditWindow.Form);
end;

procedure TEditorContextMenuHook.WindowNotification(
  const EditWindow: INTAEditWindow; Operation: TOperation);
var
  Popup : TPopupMenu;
begin
  // Editor-Window wird zerstoert -> Slot-Eintrag entfernen damit Destroy
  // nicht auf einen freigegebenen Popup zugreift.
  if (Operation = opRemove) and Assigned(EditWindow) then
  begin
    Popup := FindEditorPopup(EditWindow.Form);
    if Assigned(Popup) and FSlots.ContainsKey(Popup) then
      FSlots.Remove(Popup);   // doOwnsValues -> Slot wird gefreut
  end;
end;

procedure TEditorContextMenuHook.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean); begin end;
procedure TEditorContextMenuHook.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView); begin end;
procedure TEditorContextMenuHook.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TEditorContextMenuHook.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TEditorContextMenuHook.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;

procedure RegisterEditorContextMenuHook;
var
  EdSvc : IOTAEditorServices;
  NtSvc : INTAEditorServices;
  i     : Integer;
begin
  if Assigned(GCtxMenuHook) then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EdSvc) then Exit;

  GCtxMenuHook    := TEditorContextMenuHook.Create;
  GCtxMenuHookIfc := GCtxMenuHook as INTAEditServicesNotifier;
  GCtxMenuHookIdx := EdSvc.AddNotifier(GCtxMenuHookIfc);

  // Schon-offene Editor-Windows sofort versorgen
  if Supports(BorlandIDEServices, INTAEditorServices, NtSvc) then
    for i := 0 to NtSvc.EditWindowCount - 1 do
      if Assigned(NtSvc.EditWindow[i]) then
        GCtxMenuHook.HookEditorForm(NtSvc.EditWindow[i].Form);
end;

procedure UnregisterEditorContextMenuHook;
var
  Svc : IOTAEditorServices;
begin
  if GCtxMenuHookIdx >= 0 then
  begin
    try
      if Supports(BorlandIDEServices, IOTAEditorServices, Svc) then
        Svc.RemoveNotifier(GCtxMenuHookIdx);
    except
    end;
    GCtxMenuHookIdx := -1;
  end;
  GCtxMenuHookIfc := nil;  // Refcount sinkt -> Destroy faehrt Slot-Cleanup
  GCtxMenuHook    := nil;
end;

{ TSCAKeyboardBinding }

procedure TSCAKeyboardBinding.BindKeyboard(
  const BindingServices: IOTAKeyBindingServices);
// Bindet Ctrl+Alt+A an SilentAnalyseKeyProc. AddKeyBinding nimmt ein Array
// von TShortcut entgegen - hier nur ein Wert.
begin
  // AKeyProcData (3. Param) hat in dieser ToolsAPI-Version keinen Default -
  // nil explizit uebergeben (wir nutzen keine Per-Binding-Daten).
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('A'), [ssCtrl, ssAlt])],
    SilentAnalyseKeyProc, nil);
end;

function TSCAKeyboardBinding.GetBindingType: TBindingType;
begin
  // btPartial = wir fuegen Bindings zur bestehenden IDE-Keymap hinzu.
  // btComplete waere "wir ersetzen die komplette Keymap" (z.B. Vim-Mode).
  Result := btPartial;
end;

function TSCAKeyboardBinding.GetDisplayName: string;
begin
  // Sichtbar unter Tools > Options > Keyboard Mappings (falls IDE das listet).
  Result := 'Static Code Analyser: Silent-Mode Hotkey';
end;

function TSCAKeyboardBinding.GetName: string;
begin
  // Eindeutiger interner Identifier - sollte keinen Clash mit anderen
  // Plugins haben.
  Result := 'SCA.SilentAnalysisBinding';
end;

procedure TSCAKeyboardBinding.SilentAnalyseKeyProc(const Context: IOTAKeyContext;
  KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
// Wird bei Ctrl+Alt+A im Editor gerufen. Triggert Silent-Analyse fuer die
// aktuelle Datei und meldet krHandled - dann reicht die IDE den Key nicht
// weiter an andere Handler oder den Default-Editor.
begin
  RunSilentAnalysisForCurrentEditorFile;
  BindingResult := krHandled;
end;

procedure RegisterKeyboardBinding;
// Registriert die Ctrl+Alt+A-Bindung in der IDE. AddKeyboardBinding liefert
// einen Index >= 0 fuer Erfolg. Ein negativer Wert (oder eine Exception)
// deutet auf einen Konflikt mit einem anderen Plugin/Keymap hin -
// loggen wir nach OutputDebugString damit der User im Event-Log nachsehen
// kann (kein UI-Crash - Silent-Mode laeuft dann nur ueber Editor-Rechtsklick).
var
  KBSvc : IOTAKeyboardServices;
begin
  if Assigned(GKeyBinding) then Exit;
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, KBSvc) then
  begin
    OutputDebugString('SCA: IOTAKeyboardServices not available - Ctrl+Alt+A hotkey disabled');
    Exit;
  end;
  GKeyBinding    := TSCAKeyboardBinding.Create;
  GKeyBindingIfc := GKeyBinding as IOTAKeyboardBinding;
  try
    GKeyBindingIdx := KBSvc.AddKeyboardBinding(GKeyBindingIfc);
    if GKeyBindingIdx < 0 then
      OutputDebugString('SCA: AddKeyboardBinding returned negative index - Ctrl+Alt+A may conflict with another plugin');
  except
    on E: Exception do
    begin
      OutputDebugString(PChar(Format(
        'SCA: AddKeyboardBinding failed: %s: %s', [E.ClassName, E.Message])));
      // Refcount sauber abbauen - Interface bleibt sonst auf einer
      // halb-registrierten Bindung haengen.
      GKeyBindingIfc := nil;
      GKeyBinding    := nil;
      GKeyBindingIdx := -1;
    end;
  end;
end;

procedure UnregisterKeyboardBinding;
var
  KBSvc : IOTAKeyboardServices;
begin
  if GKeyBindingIdx >= 0 then
  begin
    try
      if Supports(BorlandIDEServices, IOTAKeyboardServices, KBSvc) then
        KBSvc.RemoveKeyboardBinding(GKeyBindingIdx);
    except
    end;
    GKeyBindingIdx := -1;
  end;
  GKeyBindingIfc := nil;  // Refcount sinkt -> Destroy
  GKeyBinding    := nil;
end;

procedure RegisterAnalyserDockableForm;
var
  NTASvc   : INTAServices;
  MainMenu : TMainMenu;
  i        : Integer;
  ViewMenu : TMenuItem;
  Item     : TMenuItem;
begin
  // Defensive: Supports() statt as-Cast - schlaegt Cast fehl, brechen
  // wir den BPL-Load *vor* Erzeugen von GDockableForm ab. Sonst
  // (alte as-Variante) wuerden GDockableForm bleiben + GViewMenuItem nil
  // und der nachfolgende Unregister-Pfad doppel-frees riskieren.
  if not Supports(BorlandIDEServices, INTAServices, NTASvc) then Exit;

  GDockableForm := TAnalyserDockableForm.Create;

  // Dockable Form registrieren (fuer Desktop-State-Persistenz)
  NTASvc.RegisterDockableForm(GDockableForm);

  // Custom-Line-Highlighter: Manager + INTAEditServicesNotifier sofort
  // registrieren. Per-View-Notifier werden ueber EditorViewActivated
  // angehaengt; AV-sicher dank ref-counting (siehe uIDELineHighlighter).
  RegisterLineHighlighter;
  RegisterAnnotationOverlay;
  // Watch-Mode: Manager-Singleton anlegen. KEINE ToolsAPI-Calls hier -
  // der Module-Notifier wird erst beim Activate() aus PrepareAnalysis
  // angehaengt (nur im "Aktuelle Datei"-Pfad, Single-File-Watch).
  RegisterWatchMode;

  // RuleCatalog warm laden - sonst wuerde der erste Open der Tools-
  // Options-Page das JSON synchron parsen (~20-50 ms). Hier ist der
  // Aufruf im BPL-Load-Pfad versteckt und faellt nicht auf.
  TRuleCatalog.ProfileNames;   // triggert EnsureLoaded

  // Eintrag im Ansicht-Menue hinzufuegen
  MainMenu := NTASvc.GetMainMenu;
  ViewMenu := nil;
  for i := 0 to MainMenu.Items.Count - 1 do
    if SameText(MainMenu.Items[i].Name, 'ViewsMenu') or
       SameText(MainMenu.Items[i].Caption, 'Ansicht') or
       SameText(MainMenu.Items[i].Caption, '&Ansicht') or
       SameText(MainMenu.Items[i].Caption, 'View') or
       SameText(MainMenu.Items[i].Caption, '&View') then
    begin
      ViewMenu := MainMenu.Items[i];
      Break;
    end;

  if Assigned(ViewMenu) then
  begin
    // View-Menu: nur ein flacher Eintrag "Static Code Analysis" der das
    // Dock-Fenster oeffnet. Silent-Mode (aktuelle Datei analysieren)
    // wird ueber das Editor-Rechtsklick-Menue gestartet, nicht hier.
    Item := TMenuItem.Create(nil);
    Item.Caption := _('Static Code Analysis');
    Item.OnClick := GDockableForm.ViewMenuClick;
    ViewMenu.Add(Item);
    GViewMenuItem := Item;
  end;

  // Editor-Rechtsklick-Menue: dynamischer OnPopup-Hook fuer den
  // Silent-Mode-Eintrag. Der Shortcut auf dem Menue-Item ist nur noch
  // Visual-Hint - die echte Hotkey-Verarbeitung laeuft ueber
  // IOTAKeyboardBinding (siehe RegisterKeyboardBinding) und feuert
  // editor-weit, auch ohne dass das Popup je geoeffnet wurde.
  RegisterEditorContextMenuHook;
  RegisterKeyboardBinding;

  // Tools > Options > Third Party > Static Code Analyser
  // (Checkbox um den Silent-Mode aus-/anzuschalten).
  RegisterSCAAddInOptions;

  // Tools > Options > Third Party > Sonar Integration
  // (separate Page - Host/Token/ProjectKey + Test-Connection).
  RegisterSonarAddInOptions;
end;

procedure ShowAnalyserDockableForm;
var
  NTASvc : INTAServices;
begin
  if not Assigned(GDockableForm) then Exit;
  if Supports(BorlandIDEServices, INTAServices, NTASvc) then
    NTASvc.CreateDockableForm(GDockableForm);
end;

procedure UnregisterAnalyserDockableForm;
var
  NTASvc : INTAServices;
begin
  if Assigned(GViewMenuItem) then
  begin
    GViewMenuItem.Parent.Remove(GViewMenuItem);
    FreeAndNil(GViewMenuItem);
  end;
  UnregisterEditorContextMenuHook;
  UnregisterKeyboardBinding;
  UnregisterSCAAddInOptions;
  UnregisterSonarAddInOptions;
  if Assigned(GDockableForm) then
  begin
    // GDockableForm ist ein TInterfacedObject -> wird ueber den
    // Refcount der globalen Variable freigegeben (Setzen auf nil
    // released die Reference). Der UnregisterDockableForm-Call
    // gibt zusaetzlich die IDE-interne Reference frei.
    // Falls Supports() fehlschlaegt: nur die globale Reference auf
    // nil setzen reicht - die IDE haelt dann die letzte und gibt
    // beim Plugin-Unload selbst frei. Nichts wird hier geleakt.
    if Supports(BorlandIDEServices, INTAServices, NTASvc) then
      NTASvc.UnregisterDockableForm(GDockableForm);
    GDockableForm := nil;
  end;
  UnregisterLineHighlighter;
  UnregisterAnnotationOverlay;
  UnregisterWatchMode;
end;

end.
