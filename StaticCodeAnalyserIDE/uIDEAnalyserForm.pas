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
  DesignIntf, ToolsAPI,
  uStaticAnalyzer2, uStaticFiles, uMethodd12, uSCAConsts, uExport,
  uFixHint, uIgnoreList, uRepoSettings, uClaudePrompt,
  uAnalyserPalette, uAnalyserTypes, uAnalyserTheme, uLocalization,
  uRecentPaths,
  uIDELineHighlighter, uIDEMessages, uIDEWatchMode, uIDEStatsTiles,
  uIDEHelpPanel, uIDEExportMenu, uIDEEditorIntegration, uIDEStatusBar,
  uIDEThemeIntegration, uIDEAnalyseProgress, uIDEGridTooltip,
  uIDELifecycle, uIDEAnalyseRunner,
  uFindingGridRenderer, uFindingFilter;

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
    // Toolbar-Controls die im gedockten/schmalen Modus ausgeblendet werden -
    // ihre Aktionen bleiben ueber das Hamburger-Menu erreichbar (FHamburgerMenu).
    FBtnRepo, FBtnIgnore                           : TButton;
    FBtnHamburger                                  : TButton;
    FHamburgerMenu                                 : TPopupMenu;
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
    procedure CancelAnalyseClick(Sender: TObject);
    procedure EditIgnoreListClick(Sender: TObject);
    procedure EditRepoSettingsClick(Sender: TObject);
    procedure HamburgerClick(Sender: TObject);
    procedure BuildHamburgerMenu;
    // DPI-Scaling fuer Layout-Konstanten. Liest TControl.CurrentPPI - falls
    // 0/uninit, fallback auf 96. Beispiel: ScaleW(28) liefert 28 bei 100%
    // DPI, 56 bei 200%.
    function  ScaleW(AValue: Integer): Integer;
    // OnResize-Handler fuer PanelButtons: passt FPanelSev/FPanelType-Width
    // an die Label-Visibility an. Wird CHAINED (TResponsiveVisibilityController
    // ruft uns als FOriginalOnResize NACH dem Label-Toggle), so dass die
    // Width-Anpassung den frischen Visible-Zustand sieht.
    procedure AdjustFilterSubPanels(Sender: TObject);
    // Setzt FSearchEdit.Constraints.MinWidth abhaengig von der PanelSearch-
    // Breite: docked = 60 (lasst SearchEdit weiter schrumpfen), floated = 120.
    procedure AdjustSearchMinWidth(Sender: TObject);
    // Frame.OnResize: forwarded explizit an alle Panel-OnResize-Handler.
    // Die TResponsiveVisibilityController hooken die Panel-OnResizes; in
    // manchen Dock-Szenarien (IDE setzt Frame.Width direkt, ohne dass das
    // sauber an alle Children durchgereicht wird) wuerde Hamburger sonst
    // im Construction-Zustand "haengen bleiben". Frame.OnResize feuert
    // garantiert.
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
    class function FixHint(const Finding: TLeakFinding): TFixHint; static;
    procedure OpenFileAtLine(const AbsPath: string; LineNumber: Integer);
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
    // applizieren. CMParentChanged gibt es in der VCL nicht, deshalb
    // ueber den virtuellen SetParent-Hook.
    procedure SetParent(AParent: TWinControl); override;
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
  // Single Breakpoint fuer Docked-vs-Floated. 96-DPI-logisch, in CreateUI
  // via ScaleW skaliert.
  // Below: docked-Mode = nur 4 essential Stats-Tiles + Hamburger sichtbar.
  // Alle Toolbar-Buttons (Settings/Ignore/Branch-Changes) und Labels
  // (Severity/Type/Search) verschwinden - Aktionen ueber das Hamburger-
  // Menu erreichbar.
  // Above: floated-Mode = volle UI inkl. aller 9 Tiles, Hamburger weg.
  BREAKPOINT_DOCKED = 700;

  // ---- Toolbar-Layout (alle Werte werden via ScaleW DPI-skaliert) -------
  TB_ROW_HEIGHT      = 22;     // alle Toolbar-Zeilen
  TB_PADDING_LR      = 6;      // Padding links/rechts in Toolbar-Panels
  TB_PADDING_TB      = 2;      // Padding oben/unten in Toolbar-Panels
  TB_SPACER_WIDTH    = 8;      // Trennabstand zwischen Bereichen
  TB_CANCEL_MARGIN   = 8;      // Margin links vom Cancel-Button

  // ---- Button-Widths ----------------------------------------------------
  BTN_W_ICON         = 28;     // Icon-only (Browse "...", Hamburger)
  BTN_W_SHORT        = 60;     // "Ignore..."
  BTN_W_MED_SHORT    = 70;     // "Settings..."
  BTN_W_MED          = 80;     // "Cancel", "Export"
  BTN_W_MED_LONG     = 90;     // "Current file"
  BTN_W_LONG         = 100;    // "Start analysis"
  BTN_W_XLONG        = 120;    // "Branch-Changes"

  // ---- Label-Widths -----------------------------------------------------
  LBL_W_PATH         = 78;     // "Project path:"
  LBL_W_FILTER       = 76;     // "Severity:"
  LBL_W_TYPE         = 36;     // "Type:"
  LBL_W_SEARCH       = 32;     // "Search:"

  // ---- Combo-Widths (innerhalb der Sub-Panel-Container) -----------------
  CMB_W_FILTER       = 160;    // Severity-Combo
  CMB_W_TYPE         = 130;    // Type-Combo

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
  // Default-Groesse: muss alle Top-Panels + Help-Panel + 120 px Grid + Statusbar
  // aufnehmen. Status 22 + Stats 120 + Path 22 + Buttons 22 + Search 22 + Help
  // 120 + Splitter 4 + Grid 120 = 452. Mit etwas Reserve auf 500.
  Height                  := 500;
  Constraints.MinHeight   := 470;
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
  PanelPath.Height      := ScaleW(TB_ROW_HEIGHT);
  PanelPath.BevelOuter  := bvNone;
  PanelPath.Color       := clBtnFace;
  PanelPath.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                              ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
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

  // Hamburger-Button: ersatz-Zugang zu den Aktionen, die im gedockten
  // (schmalen) Modus ausgeblendet werden. PopupMenu + OnClick werden
  // weiter unten via BuildHamburgerMenu verkabelt (nachdem auch
  // FBtnAnalyseChanged existiert - das Menu referenziert dessen Handler).
  // alRight + zuletzt zugewiesen -> landet ganz links der alRight-Gruppe;
  // bleibt damit auch sichtbar wenn FBtnRepo/FBtnIgnore versteckt sind.
  FBtnHamburger := TButton.Create(Self);
  FBtnHamburger.Parent  := PanelPath;
  FBtnHamburger.Caption := #$2630; // Trigram for Heaven (Hamburger-Glyph)
  FBtnHamburger.Width   := ScaleW(BTN_W_ICON);
  FBtnHamburger.Align   := alRight;
  FBtnHamburger.Hint    := _('More actions (Settings, Ignore list, Branch-Changes)');
  FBtnHamburger.ShowHint := True;

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
  PanelButtons.Height      := ScaleW(TB_ROW_HEIGHT);
  PanelButtons.BevelOuter  := bvNone;
  PanelButtons.Color       := clBtnFace;
  PanelButtons.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                                 ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
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
  PanelSearch.Height      := ScaleW(TB_ROW_HEIGHT);
  PanelSearch.BevelOuter  := bvNone;
  PanelSearch.Color       := clBtnFace;
  PanelSearch.Padding.SetBounds(ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB),
                                ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
  FPanelSearch := PanelSearch;

  // Action-Buttons links - "Analyse starten" zuerst (links), dann "Aktuelle Datei"
  BtnAnalyse := TButton.Create(Self);
  BtnAnalyse.Parent   := PanelSearch;
  BtnAnalyse.Caption  := _('Start analysis');
  BtnAnalyse.Width    := ScaleW(BTN_W_LONG);
  BtnAnalyse.Align    := alLeft;
  BtnAnalyse.OnClick  := AnalyseClick;
  FBtnAnalyse := BtnAnalyse;

  FBtnAnalyseCurrent := TButton.Create(Self);
  FBtnAnalyseCurrent.Parent   := PanelSearch;
  FBtnAnalyseCurrent.Caption  := _('Current file');
  FBtnAnalyseCurrent.Width    := ScaleW(BTN_W_MED_LONG);
  FBtnAnalyseCurrent.Align    := alLeft;
  FBtnAnalyseCurrent.OnClick  := AnalyseCurrentFileClick;

  // Branch-Aenderungen via Git/SVN: nur die im Branch geaenderten .pas-Files
  FBtnAnalyseChanged := TButton.Create(Self);
  FBtnAnalyseChanged.Parent   := PanelSearch;
  FBtnAnalyseChanged.Caption  := _('Branch-Changes');
  FBtnAnalyseChanged.Width    := ScaleW(BTN_W_XLONG);
  FBtnAnalyseChanged.Align    := alLeft;
  FBtnAnalyseChanged.OnClick  := AnalyseChangedFilesClick;
  FBtnAnalyseChanged.Hint     := _(
    'Analyses only files changed in the current branch ' +
    '(Git: branch diff vs main + working tree; SVN: working copy)');
  FBtnAnalyseChanged.ShowHint := True;

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

  // ---- Hamburger-Menu (alle "optionalen" Actions als Backup-Pfad) ----
  // Wird gebraucht wenn der Frame schmal gedockt ist und die zugehoerigen
  // Buttons via TResponsiveVisibilityController ausgeblendet werden.
  // Setup in BuildHamburgerMenu (referenziert bestehende Click-Handler).
  BuildHamburgerMenu;

  // ---- Responsive Visibility: Single Threshold (Docked vs Floated) -----
  // < BREAKPOINT_DOCKED (700): docked-Mode. Hamburger ersetzt alle
  // versteckten Buttons (Settings/Ignore/Branch-Changes); Filter-Labels
  // verschwinden (Combos selbsterklaerend); Stats-Tiles werden in
  // BuildStatsTiles gehandelt (4 essential + Hamburger).
  // Threshold wird DPI-skaliert: ClientWidth ist physisch, Konstante
  // logisch (96 DPI). Ohne Scale-Faktor wuerde Docked auf 200% DPI bei
  // bereits halber physischer Breite triggern.

  // PanelPath: Settings + Ignore weg im Docked
  TResponsiveVisibilityController.Create(Self, FPanelPath,
    [FBtnRepo, FBtnIgnore], ScaleW(BREAKPOINT_DOCKED));
  // PanelPath: Hamburger INVERS - nur im Docked sichtbar
  TResponsiveVisibilityController.Create(Self, FPanelPath,
    [FBtnHamburger], ScaleW(BREAKPOINT_DOCKED), True {Inverse});

  // PanelButtons: Filter-Labels weg, Sub-Panels schrumpfen (Combos bleiben).
  // WICHTIG: AdjustFilterSubPanels VOR dem Controller hooken. Der
  // Controller speichert OnResize als FOriginalOnResize und ruft es NACH
  // dem Visibility-Toggle - so sieht AdjustFilterSubPanels den frischen
  // FLbl*-Visible-Zustand und passt die Sub-Panel-Width an. Sonst
  // bleiben FPanelSev/FPanelType in voller Breite und PanelButtons platzt.
  FPanelButtons.OnResize := AdjustFilterSubPanels;
  TResponsiveVisibilityController.Create(Self, FPanelButtons,
    [FLblFilter, FLblType], ScaleW(BREAKPOINT_DOCKED));
  AdjustFilterSubPanels(FPanelButtons); // initial pass

  // PanelSearch: Aktions-Buttons + Search-Label weg im Docked. Start/
  // Current/Branch sind alle im Hamburger-Menu erreichbar - PanelSearch
  // zeigt im Docked nur noch SearchEdit + Export + Cancel (~250 px).
  // Plus: SearchEdit MinWidth schrumpft mit (60 statt 120 docked) damit
  // auch sehr enge Docks (300 px) noch funktionieren.
  // Hook AdjustSearchMinWidth VOR dem Controller (chain-Pattern).
  FPanelSearch.OnResize := AdjustSearchMinWidth;
  TResponsiveVisibilityController.Create(Self, FPanelSearch,
    [FBtnAnalyse, FBtnAnalyseCurrent, FBtnAnalyseChanged, FLblSearch],
    ScaleW(BREAKPOINT_DOCKED));
  AdjustSearchMinWidth(FPanelSearch); // initial pass

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
// Threshold: BREAKPOINT_DOCKED aus implementation-const (gemeinsam mit
// den Toolbar-Controllern in CreateUI).

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

  // Responsive Layout-Controller. Owner=Self -> wird beim Frame-Destroy
  // mit freigegeben; Parent.OnResize wird vom Controller selbst gehookt.
  // Tile-Labels -> Parent.Parent ist die TilePanel (TopRow zwischen).
  // Threshold DOCKED (700 px DPI-skaliert): bei < 700 nur die 4 essentiellen
  // Tiles (Errors/Warnings/Hints/Code Quality) sichtbar, der Rest hide.
  TResponsiveVisibilityController.Create(Self, Parent,
    [FTileFileSev.Parent.Parent,
     FTileBug.Parent.Parent,
     FTileVuln.Parent.Parent,
     FTileDup.Parent.Parent,
     FTileCyclomatic.Parent.Parent],
    ScaleW(BREAKPOINT_DOCKED));
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

procedure TAnalyserFrame.PopulateGridFromDisplayed;
var
  f   : TLeakFinding;
  row : Integer;
begin
  FResultGrid.RowCount := Max(FDisplayedFindings.Count + 1, 2);
  row := 1;
  for f in FDisplayedFindings do
  begin
    // Im Grid steht nur der Dateiname - der volle Pfad kommt als Tooltip
    // ueber TFindingGridTooltip/CM_HINTSHOW aus FDisplayedFindings.
    FResultGrid.Cells[0, row] := ExtractFileName(f.FileName);
    FResultGrid.Cells[1, row] := f.MethodName;
    FResultGrid.Cells[2, row] := f.LineNumber;
    FResultGrid.Cells[3, row] := f.TypeText;
    FResultGrid.Cells[4, row] := f.MissingVar;
    FResultGrid.Cells[5, row] := f.SeverityText;
    Inc(row);
  end;

  if FDisplayedFindings.Count = 0 then
  begin
    FResultGrid.Rows[1].Clear;
    FResultGrid.Cells[0, 1] := 'Keine Eintraege fuer diesen Filter.';
  end;
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
  // Editor-Line-Highlight ist click-getrieben (siehe GridSelectCell ->
  // GHighlighter.SetSelected). Beim Abschluss eines neuen Scans loeschen
  // wir die alte Markierung, damit kein Befund aus dem letzten Scan im
  // Editor stehen bleibt.
  if Assigned(GHighlighter) then
    GHighlighter.Clear;
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
// die Befund-Zeile rot markieren (PaintLine via INTAEditViewNotifier).
var
  idx     : Integer;
  Finding : TLeakFinding;
  LineNo  : Integer;
begin
  CanSelect := True;
  UpdateHelp(ARow);

  idx := ARow - 1; // Zeile 0 = Header
  if (idx < 0) or (idx >= FDisplayedFindings.Count) then Exit;

  Finding := FDisplayedFindings[idx];
  CopyFindingToClipboard(Finding);

  // Editor-Line-Highlight setzen. Wenn die Datei nicht offen ist, malt
  // GHighlighter beim naechsten Oeffnen (PaintLine prueft jeden Repaint).
  if Assigned(GHighlighter) then
  begin
    LineNo := StrToIntDef(Finding.LineNumber, 0);
    GHighlighter.SetSelected(Finding.FileName, LineNo);
  end;
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
    FRepoSettings.ApplyDetectorThresholds;
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
  FilePath  : string;
begin
  // IDE-Editor-Detection in uIDEEditorIntegration ausgelagert (saubere
  // Supports-Casts + Buffer-nil-Check, behebt die im TODO gelisteten
  // AV-Pfade beim Plugin-Reload).
  case TIDEEditor.TryGetCurrentPasFile(FilePath) of
    cfrNoEditorService:
      begin StatusMode(_('IDE editor service not available.')); Exit; end;
    cfrNoOpenView:
      begin StatusMode(_('No file opened.'));                   Exit; end;
    cfrNotPascalFile:
      begin StatusMode(_('Current file is not a Pascal file.')); Exit; end;
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
// Forwarded an alle vier Panel-OnResize-Handler. Damit die Responsive-
// Controller (gehookt auf Panel.OnResize) garantiert feuern, auch wenn
// die IDE-Dock-Logik die Children nicht sauber benachrichtigt.
begin
  if Assigned(FPanelPath)    and Assigned(FPanelPath.OnResize)
    then FPanelPath.OnResize(FPanelPath);
  if Assigned(FPanelButtons) and Assigned(FPanelButtons.OnResize)
    then FPanelButtons.OnResize(FPanelButtons);
  if Assigned(FPanelSearch)  and Assigned(FPanelSearch.OnResize)
    then FPanelSearch.OnResize(FPanelSearch);
  if Assigned(FPanelStats)   and Assigned(FPanelStats.OnResize)
    then FPanelStats.OnResize(FPanelStats);
end;

procedure TAnalyserFrame.AdjustSearchMinWidth(Sender: TObject);
// MinWidth auf den passenden Wert setzen, ohne TResponsiveVisibilityController
// dafuer zu erweitern (waere overkill - hier wechselt nur ein einzelner
// Constraint-Wert, kein Visible-Flag).
var
  Threshold : Integer;
begin
  if not Assigned(FSearchEdit) or not Assigned(FPanelSearch) then Exit;
  Threshold := ScaleW(BREAKPOINT_DOCKED);
  if FPanelSearch.ClientWidth >= Threshold then
    FSearchEdit.Constraints.MinWidth := ScaleW(SEARCH_MIN_WIDTH_FLOATED)
  else
    FSearchEdit.Constraints.MinWidth := ScaleW(SEARCH_MIN_WIDTH_DOCKED);
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
end;

procedure TAnalyserFrame.BuildHamburgerMenu;
// Popup-Menu fuer den Hamburger-Button. Items entsprechen den Toolbar-
// Aktionen, die im gedockten/schmalen Modus ausgeblendet werden -
// hier bleiben sie auch im Docked-Modus erreichbar. Reihenfolge:
// Aktionen (Start/Current/Branch) zuerst, dann Konfig (Settings/Ignore).
var
  MI : TMenuItem;
begin
  FHamburgerMenu := TPopupMenu.Create(Self);

  // Aktions-Block: alles was eine Analyse anstoesst
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Start analysis');
  MI.OnClick := AnalyseClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Current file');
  MI.OnClick := AnalyseCurrentFileClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Analyse Branch-Changes');
  MI.OnClick := AnalyseChangedFilesClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // Konfig-Block: oeffnet externe Editoren, kein Analyse-Trigger
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

  OpenFileAtLine(absPath, lineNo);
  // Editor-Line-Highlight setzen - die Datei ist jetzt sicher offen,
  // also wird PaintLine den Marker malen.
  if Assigned(GHighlighter) then
    GHighlighter.SetSelected(absPath, lineNo);
  StatusMode(Format(_('Opened: %s  Line: %d'),
    [ExtractFileName(absPath), lineNo]));
end;

procedure TAnalyserFrame.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer);
// Thin-Wrapper - Logik in uIDEEditorIntegration.TIDEEditor (mit
// Supports-Casts statt as-Cast). Behalten als Frame-Methode weil
// GridDblClick es aufruft und der Lifecycle-Sentinel-Schutz weiter
// ueber den Frame laufen soll (Defensive: kein OpenFile wenn der
// Frame gerade zerstoert wird).
begin
  if GLiveAnalyserFrame <> Pointer(Self) then Exit;
  TIDEEditor.OpenFileAtLine(AbsPath, LineNumber);
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
    RefreshFromIDETheme;
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
  // Responsive Visibility (Hamburger, Tiles, Filter-Labels) - forwarded
  // an alle Panel-OnResizes garantiert, dass die Controller bei
  // Float->Dock triggern.
  FrameResize(Self);
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
begin
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State,
    TFindingGridRenderer.IDEConfig(FSortColumn, FSortDescending));
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
  F : TAnalyserFrame;
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

// ---------------------------------------------------------------------------
// Registrierung und Anzeige
// ---------------------------------------------------------------------------

var
  GViewMenuItem: TMenuItem = nil;

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
  // Watch-Mode: Manager-Singleton anlegen. KEINE ToolsAPI-Calls hier -
  // der Module-Notifier wird erst beim Activate() aus PrepareAnalysis
  // angehaengt (nur im "Aktuelle Datei"-Pfad, Single-File-Watch).
  RegisterWatchMode;

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
    Item := TMenuItem.Create(nil);
    Item.Caption := 'Static Code Analysis';
    Item.OnClick := GDockableForm.ViewMenuClick;
    ViewMenu.Add(Item);
    GViewMenuItem := Item;
  end;
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
  UnregisterWatchMode;
end;

end.
