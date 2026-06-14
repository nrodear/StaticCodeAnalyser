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
  uQuickFix,
  uAnalyserPalette, uAnalyserTypes, uAnalyserTheme, uIDEColors, uLocalization,
  uRecentPaths,
  uIDELineHighlighter, uIDEMessages, uIDEWatchMode, uIDEStatsTiles,
  uIDEHelpPanel, uExportMenu, uIDEEditorIntegration, uIDEStatusBar,
  uIDETheme, uIDEToolbar, uIDEAnalyseProgress, uIDEGridTooltip,
  uIDELifecycle, uIDEAnalyseRunner,
  uIDEAnnotationOverlay,
  uIDEFindingNav,                          // Ctrl+Alt+Up/Down Befund-Navigation
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
    // Snapshot der initial-populierten Combo-Items (FormCreate). Wird
    // in RebuildFilterCombos genutzt um nach jedem Scan auf Eintraege
    // mit > 0 Treffern zu reduzieren - und beim naechsten Scan wieder
    // zu erweitern.
    FAllSeverityItems  : TArray<TFilterComboItem>;
    FAllTypeItems      : TArray<TFilterComboItem>;
    // Letzter NICHT-Separator-Mode der gewaehlt war. Wird gebraucht um
    // bei Klick auf einen Separator (Tag = -1) NICHT auf 'All'
    // zurueckzuspringen sondern auf die zuletzt aktive Auswahl.
    // Default 0 = Ord(fmAll); FilterChange aktualisiert bei jedem
    // gueltigen Klick.
    FLastNonSeparatorMode : Integer;
    FFilterMode     : TFilterMode;
    FCurrentBaseDir : string;
    FFilterCombo       : TComboBox;
    // Hilfe-Panel rechts (Vorher/Nachher-Code-Beispiele) inklusive
    // dessen Splitter, Dock-State-Timer und Layout-Logik. Ehemals 7
    // Felder + 4 Methoden direkt im Frame - jetzt ausgelagert in
    // uIDEHelpPanel.TFindingHintPanel.
    FHintPanel         : TFindingHintPanel;
    FDisplayedFindings : TList<TLeakFinding>;
    // Vorab gebauter Grid-Renderer-Config mit Closures (siehe InitGridConfig).
    // Vorher wurde der Config pro Zelle in GridDrawCell frisch erzeugt - bei
    // ~300 sichtbaren Zellen pro Repaint × 3 anonymen Methoden = 900 Heap-
    // Allokationen pro Frame. Mausrad-Scroll hat das massiv aufgestaut.
    FGridConfig        : TFindingGridConfig;
    // Gecachte IDE-StyleServices fuer den Grid-Renderer. Vorher: pro Zelle
    // wurde Supports(BorlandIDEServices, IOTAIDEThemingServices, ...)
    // ausgefuehrt - ein COM-QueryInterface pro Zelle. Wird in
    // RefreshFromIDETheme genullt, damit ein Theme-Switch frische Werte
    // holt.
    FCachedIDEStyles   : TCustomStyleServices;
    // Original-WindowProc des FResultGrid (von InstallGridWheelCoalescer
    // gesetzt). GridWindowProc reicht alles an FOrigGridWindowProc weiter.
    FOrigGridWindowProc: TWndMethod;

    // Debouncer fuer Multi-File-Highlighter-Rebuild (siehe Konzept_
    // GridPerformance150k.md, Tier A1). HighlightAllFindingsInFile baut
    // einen Array ueber alle FDisplayedFindings + FixHint pro Eintrag -
    // bei 10k+ Befunden teuer und wurde frueher pro Pfeiltasten-Event
    // und pro Such-Keystroke gerufen.
    FHighlightDebounceTimer : TTimer;
    FPendingHighlightFile   : string;
    // Debouncer fuer ApplyFilter (Tier B1) - frueher pro Such-Keystroke.
    FFilterDebounceTimer    : TTimer;

    FPanelStats        : TPanel;
    // Toolbar-Panels - werden in CreateUI als alTop angelegt. Refs gehalten,
    // damit der Responsive-Controller pro Reihe den Resize hooken kann.
    FPanelPath         : TPanel;
    FPanelFilters      : TPanel;
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
    // Diese Buttons werden NICHT mehr in der Toolbar angezeigt - ihre
    // Aktionen sind ausschliesslich ueber das Hamburger-Menu (FHamburgerMenu)
    // erreichbar. Felder bleiben als nil; OnClick-Handler werden direkt
    // an die MenuItems gebunden, nicht an die Buttons.
    // (FBtnRepo/FBtnIgnore/FBtnAnalyseChanged/FBtnCancel/FBtnExport entfernt)

    // FBtnBrowse: war frueher lokal — als Field gebraucht damit
    // ApplyToolbarSizing den Icon-Button-Sizing-Pfad anwenden kann.
    FBtnBrowse                                     : TButton;

    // Hamburger-Button + PopupMenu - IMMER sichtbar (keine Stage-Bindung).
    // Enthaelt: Branch-Changes, Cancel, Export, Settings, Ignore.
    FBtnHamburger                                  : TButton;
    FHamburgerMenu                                 : TPopupMenu;
    // MenuItems deren Enabled-Zustand sich zur Laufzeit aendert:
    //   FMICancel         - nur waehrend laufender Analyse aktiv
    //   FMIAnalyseChanged - waehrend Analyse deaktiviert
    //   FMIClearMarks     - nur aktiv wenn GHighlighter ueberhaupt Marker hat
    // Sync via HamburgerMenuPopup an FAnalyseProgress.Running / GHighlighter.HasMarks.
    FMICancel, FMIAnalyseChanged, FMIClearMarks    : TMenuItem;
    FLblFilter, FLblType                           : TLabel;
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
    FBtnAnalyse        : TButton;      // gemerkt fuer Enable/Disable
    FBtnAnalyseCurrent : TButton;
    // (FBtnCancel, FBtnAnalyseChanged sind im Hamburger-Menu, kein Field
    //  noetig — OnClick-Handler werden direkt an die MenuItems gebunden.)
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
    // Baut FGridConfig einmal (siehe Field-Kommentar).
    procedure InitGridConfig;
    // Installiert Custom-WindowProc auf FResultGrid, der pendingende
    // WM_MOUSEWHEEL-Messages in einen einzigen grossen Scroll faltet.
    // Vorher: jeder Wheel-Tick triggerte einen separaten Paint, bei
    // schnellem Drehen baute sich eine sekundenlange Message-Queue auf.
    procedure InstallGridWheelCoalescer;
    procedure GridWindowProc(var Msg: TMessage);
    // Erzeugt die Debounce-Timer (TTimer-Komponenten owned-by-Self).
    procedure InitDebounceTimers;
    // OnTimer der zwei Debouncer.
    procedure HighlightDebounceFire(Sender: TObject);
    procedure FilterDebounceFire(Sender: TObject);
    // Statt direktem HighlightAllFindingsInFile - resettet den 200ms-
    // Timer und merkt sich die zuletzt angefragte Datei. Aufeinander-
    // folgende Calls innerhalb des Intervalls kollabieren zu EINEM
    // Rebuild nach Idle.
    procedure ScheduleHighlightRefresh(const AFileName: string);
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
    // Combo-Item-Populationen: extrahiert aus dem Constructor um die
    // ~110 Zeilen Items-AddObject-Setup nicht im UI-Build-Pfad zu mischen.
    // Jede Methode konfiguriert die Items + ItemIndex einer einzelnen
    // Combo; Reihenfolge / Sentinel-Marker / Severity-Gruppierung sind in
    // der Methode selbst dokumentiert.
    procedure PopulateFilterCombo;
    procedure PopulateTypeCombo;
    procedure PopulateProfileCombo;
    // Snapshot der initial-populierten Filter-Combo-Items - wird in
    // RebuildFilterCombos genutzt um nach jedem Scan auf Eintraege mit
    // > 0 Treffern zu reduzieren. Separator-Items (ModeOrd = -1) bleiben
    // bei der Filterung erhalten, werden danach in einem zweiten Pass
    // wieder entfernt wenn sie "leer" stehen (zwei Separatoren hintereinander
    // oder am Listen-Ende).
    procedure SnapshotFilterItems;
    procedure RebuildFilterCombos;
    // UI-Build-Helper: aus dem Constructor ausgelagert um die Setup-
    // Pfade lesbar zu halten. Reihenfolge im Constructor:
    //   ApplyToolbarSizing -> WireResponsiveLayout -> BuildResultGrid.
    procedure ApplyToolbarSizing(AUnifCtrlH: Integer);
    procedure WireResponsiveLayout;
    procedure BuildResultGrid(AParent: TWinControl);
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
    // Loescht ALLE Hover-Annotation-Marker (Stripes + sichtbares Overlay)
    // quer ueber alle Dateien. Nur Anzeige-Reset - die zugrundeliegende
    // Findings-Liste im Grid bleibt unveraendert (User kann ueber "Markieren"
    // im Kontextmenue erneut anzeigen).
    procedure ClearAllMarksClick(Sender: TObject);
    procedure EditIgnoreListClick(Sender: TObject);
    procedure EditRepoSettingsClick(Sender: TObject);
    // Folge-Anpassungen die FResponsive nach jedem Resize triggert:
    // 1) Sub-Panel-Width an Label-Visibility anpassen (FilterSubPanels)
    // 2) SearchEdit MinWidth dynamisch je nach freiem Platz (SearchMinWidth)
    procedure ResponsiveAfterApply(Sender: TObject);
    procedure HamburgerClick(Sender: TObject);
    procedure HamburgerMenuPopup(Sender: TObject);
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
    procedure UpdateFilterStatus(const Criteria: TFindingFilterCriteria;
      TotalMatched: Integer = 0);
    // Erzeugt einen vollstaendigen Markdown-Prompt fuer Claude AI: Befund-
    // Metadaten, FixHint (Vorher/Nachher) und Code-Auszug aus der Quelldatei.
    function  BuildClaudePrompt(F: TLeakFinding): string;
    procedure CopyFindingToClipboard(F: TLeakFinding);
    // Wendet einen Quick-Fix DIREKT im IDE-Editor an (TIDEEditor.
    // ApplyLineReplacement). Trigger: F4 auf der Grid-Zeile. No-op
    // wenn der Befund-Kind keinen Quick-Fix-Provider hat oder der
    // Provider auf der Original-Zeile kein Pattern matched. Status-
    // bar zeigt Ergebnis (success/failure/unsupported).
    procedure ApplyQuickFixForRow(RowIdx: Integer);

    // Fuegt `// noinspection <RuleName>` direkt ueber der Befund-Zeile
    // im IDE-Editor ein. Trigger: Ctrl+Alt+S auf der Grid-Zeile.
    // Beim naechsten Analyse-Lauf filtert uSuppression den Befund.
    procedure ApplySuppressForRow(RowIdx: Integer);
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
    // IDE-Theme-Abonnement: Refcount-Halter aus TIDETheme.Subscribe.
    // Solange das Interface gehalten wird, ruft TIDETheme bei jedem
    // ChangedTheme-Event RefreshFromIDETheme. Im Destruktor wird das
    // Field auf nil gesetzt; die RAII-Hülle deregistriert sich dann
    // automatisch.
    FThemeSub : IInterface;
    // SetParent override - feuert beim Dock <-> Float-Wechsel oder beim
    // ersten Hosting des Frames. Zwei Verantwortungen:
    //   1. Theme: Float-Wechsel erzeugt ein neues Host-TForm, dessen
    //      Titelzeile noch nicht themed ist. TIDETheme.Apply walked
    //      bis zum TopForm und macht ApplyTheme dort. (Reine IDE-Theme-
    //      Wechsel werden NICHT hier behandelt - das macht der Subscribe.)
    //   2. Layout: postet WM_SCA_REFIT fuer deferred FrameResize (IDE
    //      setzt Bounds NACH SetParent; csLoading kann VCL.Resize-Override
    //      ueberspringen).
    procedure SetParent(AParent: TWinControl); override;
    // Deferred FrameResize nach abgeschlossenem IDE-Dock-Vorgang.
    // SetParent postet WM_SCA_REFIT; zu diesem Zeitpunkt sind Bounds
    // korrekt gesetzt und csLoading ist geloescht.
    procedure WMScaRefit(var Message: TMessage); message WM_SCA_REFIT;
    // Zweiter Theme-Trigger neben dem INTAIDEThemingServicesNotifier.
    // Im Docked-Modus propagiert ApplyTheme(TopForm) nicht in den
    // Frame-Subtree (TopForm = IDE-Main, nicht unser Container);
    // VCL feuert aber CM_STYLECHANGED via WndProc-Kette an jeden
    // Control. Wir leiten das an RefreshFromIDETheme weiter.
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  public
    FProjectPath : TComboBox;
    FResultGrid  : TStringGrid;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Resize; override;
    // Wendet das aktuelle IDE-Theme auf den Frame an. Wird vom
    // TIDETheme-Subscribe bei jedem Theme-Wechsel gerufen und von
    // SetParent als zusaetzlicher Trigger (Dock/Float-Wechsel). Public,
    // damit auch externer Code einen Theme-Refresh erzwingen kann.
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

// Silent-Single-File-Scan. Vom Properties-Wrapper genutzt um beim Tab-Wechsel
// die aktive Datei automatisch zu re-analysieren. ACenterOnFirstFinding=False
// unterdrueckt das Editor-Auto-Scroll auf den ersten Befund (sonst springt
// der Editor bei jedem Tab-Wechsel unerwartet zur Line des ersten Findings).
procedure RunSilentAnalysisForFile(const AFileName: string;
  ACenterOnFirstFinding: Boolean = True);

implementation

// noinspection-file BeginEndRequired, BooleanParam, ClassPerFile, ConsecutiveSection, EmptyExcept, ExceptOnException, GodClass, GroupedDeclaration, IfElseBegin, LargeClass, LongMethod, NestedRoutine, NestedTry, PublicField, PublicMemberWithoutDoc, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedPublicMember, UnusedRoutine
// Plugin-Form: catch-all an Action-Click-Handlern (Resize, ItemPaint etc.).
// GodClass/LargeClass: dockable Plugin-Form sammelt alle UI-Events,
// VCL-Action-Owner-Pattern erlaubt keine sinnvolle Dekomposition.

{$R *.dfm}

// Forward-Declaration: IsShortcutsMasterEnabled wird von TAnalyserFrame.GridKeyDown
// aufgerufen (Zeile ~1634) - die Implementierung steht weiter unten in der Unit.
function IsShortcutsMasterEnabled: Boolean; forward;

type
  // Access-Class zum Setzen protected-deklarierter Properties (TControl.OnClick).
  // Lokal in der Unit gehalten - kein public API. Standard-VCL-Pattern.
  TControlAccess = class(TControl);

const
  // ---- 3-Stufen-Responsive-Layout (96-DPI-logisch, via ScaleW skaliert) -
  //
  // Stufe 1 (NARROW, < BREAKPOINT_MEDIUM = 500):
  //   Nur die 4 essential Stats-Tiles (Errors/Warnings/Hints/Quality).
  //   Filter-Labels weg. Settings/Ignore/Cancel/Branch-Changes alle hidden -
  //   User muss das Fenster aufweiten um diese Aktionen zu erreichen.
  //
  // Stufe 2 (MEDIUM, >= 500 .. < BREAKPOINT_FULL = 850):
  //   Komplette Tile-Reihe (alle 9 Tiles) sichtbar. Filter-/Type-Labels
  //   sichtbar. Settings/Ignore/Cancel/Export/Branch-Changes bleiben
  //   hidden. Tile-Reihe braucht abhaengig von TILE_W in uIDEStatsTiles
  //   entsprechend Platz; ueberzaehlige werden vom alLeft-Layout ggf.
  //   beschnitten (akzeptabel).
  //
  // Stufe 3 (FULL, >= BREAKPOINT_FULL = 850):
  //   Volle UI: alle 9 Tiles + komplette Toolbar (alle Aktionen direkt
  //   erreichbar). Branch-Changes sichtbar.
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
  BTN_W_ICON         = 32;     // Icon-only (Browse "...", Branch-Changes ⎇)
  BTN_W_SHORT        = 56;     // "Ignore..."
  BTN_W_MED_SHORT    = 64;     // "Settings..."
  BTN_W_MED          = 68;     // "Cancel", "Export"
  BTN_W_MED_LONG     = 48;     // "📄 File"
  BTN_W_LONG         = 64;     // "▶ Analyse"

  // ---- Label-Widths -----------------------------------------------------
  LBL_W_PATH         = 78;     // "Path:" (AutoSize, Wert nur als Fallback)
  LBL_W_FILTER       = 76;     // "Severity:"
  LBL_W_TYPE         = 36;     // "Type:"
  LBL_W_PROFILE      = 48;     // "Profile:"

  // ---- Combo-Widths (innerhalb der Sub-Panel-Container) -----------------
  // Severity-Combo: 200 px statt 160, damit die laengsten deutschen Labels
  // ("Master-Detail nicht verknuepft", "Ungenutztes oeffentliches Member",
  // "Datumsformat-Einstellungen") im geschlossenen Zustand ohne Ellipse
  // sichtbar sind. Der Sub-Panel-Container (FPanelSev) skaliert ueber
  // LBL_W_FILTER + CMB_W_FILTER automatisch mit.
  CMB_W_FILTER       = 200;    // Severity-Combo
  CMB_W_TYPE         = 130;    // Type-Combo
  CMB_W_PROFILE      = 110;    // Profile-Combo (ide-fast, default, strict)

  // ---- Stats-Panel ------------------------------------------------------
  STATS_PANEL_HEIGHT = 53;     // 1 Tile-Reihe (TopRow 20 + Caption 12 + Padding); +8 px Hoehe fuer Glyph-Atem
  STATS_PADDING      = 4;

  // ---- Misc -------------------------------------------------------------
  PROGRESS_HEIGHT    = 14;
  GRID_MIN_HEIGHT    = 120;
  GRID_MIN_WIDTH     = 300;
  // Floated: SearchEdit hat genug Platz, MinWidth grosszuegig.
  // Docked: nur SearchEdit + Profile + Filter-Combos sichtbar -
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
  PanelPath: TPanel;
  // Theming-Service-Vars werden in FrameCreated genutzt; hier nur Default fuer
  // den Notifier-Index setzen, damit Destroy nicht versucht, einen ungueltigen
  // Index abzumelden falls der Service nie verfuegbar war.
  LblPath: TLabel;
  BtnAnalyse: TButton;
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

  // IDE-Theme: Subscribe registriert RefreshFromIDETheme als Callback
  // beim zentralen TIDETheme-Singleton. Der initiale Apply-Call kommt
  // erst in TAnalyserDockableForm.FrameCreated, sobald BorlandIDEServices
  // verfuegbar ist und der Frame ein Parent hat. FThemeSub haelt den
  // Refcount; im Destruktor reicht FThemeSub := nil; um die Subscription
  // aufzuloesen.
  FThemeSub := TIDETheme.Subscribe(RefreshFromIDETheme);

  // Frame folgt dem aktiven IDE-Theme. IDE_BG_CHROME = clBtnFace, vom
  // VCL-Style remapped auf das aktive Theme (hell/dunkel/Custom).
  Color := IDE_BG_CHROME;
  TIDEToolbar.ApplySegoeUI(Self);
  // DoubleBuffered: reduziert Flicker bei Resize, Theme-Switch und
  // Stats-Tile-Updates. Die VCL malt erst in ein Off-Screen-Bitmap
  // und blittet einmal — kein Zwischenzustand sichtbar.
  DoubleBuffered := True;

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

  // alTop-Panels werden in Sicht-Reihenfolge erzeugt (FPanelStats zuerst →
  // oben, dann PanelPath, PanelSearch). VCL dockt alTop in
  // genau dieser Reihenfolge an den oberen Rand. Die Tiles selbst werden
  // erst nach WireResponsiveLayout via BuildStatsTiles eingehaengt (Tiles
  // registrieren sich beim FResponsive-Controller, der bis dahin nicht
  // existiert).
  FPanelStats := TPanel.Create(Self);
  FPanelStats.Parent      := Self;
  FPanelStats.Align       := alTop;
  FPanelStats.Height      := ScaleW(STATS_PANEL_HEIGHT);
  FPanelStats.BevelOuter  := bvNone;
  // Color + ParentBackground (Default=True) reichen — VCL-Style malt
  // den themed Chrome-Hintergrund. Frueher war ParentBackground:=False
  // explizit, das war ein Rest aus der Pre-Theme-Ära und macht keinen
  // visuellen Unterschied mehr.
  FPanelStats.Color       := IDE_BG_CHROME;
  FPanelStats.Padding.SetBounds(ScaleW(STATS_PADDING), ScaleW(STATS_PADDING),
                                ScaleW(STATS_PADDING), ScaleW(STATS_PADDING));

  // ---- Zeile: Projektpfad ----
  // Outer-Row via Helper. Right padding=0 sitzt im Helper drin, damit
  // alRight-Buttons (Browse "...") buendig am rechten Panel-Rand sitzen.
  PanelPath := TIDEToolbar.CreateRow(Self, Self, ToolbarRowH,
    ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
  FPanelPath := PanelPath;

  LblPath := TIDEToolbar.AddLabel(Self, PanelPath, _('Path:'),
    ScaleW(LBL_W_PATH));
  // AddLabel setzt AutoSize:=False mit fixer Width fuer konsistente
  // Toolbar-Optik. Fuer LblPath bewusst auf AutoSize=True umstellen:
  // "Path:"/"Pfad:" ist kurz, das alClient-Combo daneben bekommt den
  // gewonnenen Platz.
  LblPath.AutoSize := True;

  FBtnBrowse := TIDEToolbar.AddButton(Self, PanelPath, '...',
    ScaleW(BTN_W_ICON), alRight, BrowseClick);

  // FBtnIgnore + FBtnRepo (Ignore-Liste / Settings) sind aus der Toolbar
  // raus - nur noch ueber Hamburger-Menu erreichbar.

  FProjectPath := TComboBox.Create(Self);
  FProjectPath.Parent := PanelPath;
  FProjectPath.Align  := alClient;
  FProjectPath.Style  := csDropDown;
  TIDEToolbar.ApplySegoeUI(FProjectPath);

  // (Filter-Reihe entfernt — Severity- und Type-Combo sind in PanelSearch
  // gewandert, neben dem Profile-Combo. Damit eine Toolbar-Reihe weniger.)

  // UsesCheck und IncludeTests werden jetzt aus analyser.ini [Detectors]
  // gelesen - keine Checkboxen mehr in der Toolbar (siehe FRepoSettings).

  // ---- Zeile: Severity-Filter + Type-Filter ----
  // Eigene alTop-Toolbar-Reihe fuer die zwei Filter-Sub-Panels.
  // Sub-Panel-Wrapper (FPanelSev/FPanelType) noetig wegen VCL-Quirk:
  // TLabel (TGraphicControl) und TComboBox (TWinControl) werden auf
  // einem gemeinsamen alLeft-Parent in unterschiedlichen Align-Passes
  // positioniert. Im Sub-Panel haben sie einen exklusiven Container
  // und sitzen strikt von links nach rechts.
  var PanelFilters := TIDEToolbar.CreateRow(Self, Self, ToolbarRowH,
    ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
  FPanelFilters := PanelFilters;

  // Severity-Filter (filtert bereits erzeugte Befunde).
  FFilterCombo := TIDEToolbar.CreateLabelCombo(Self, PanelFilters,
    _('Severity:'), ScaleW(LBL_W_FILTER), ScaleW(CMB_W_FILTER), FLblFilter);
  FFilterCombo.OnChange := FilterChange;
  FPanelSev := FFilterCombo.Parent as TPanel;
  PopulateFilterCombo;

  // Type-Filter (Sonar-Kategorie).
  FTypeCombo := TIDEToolbar.CreateLabelCombo(Self, PanelFilters,
    _('Type:'), ScaleW(LBL_W_TYPE), ScaleW(CMB_W_TYPE), FLblType);
  FTypeCombo.OnChange := TypeFilterChange;
  FPanelType := FTypeCombo.Parent as TPanel;
  PopulateTypeCombo;
  FTypeFilter := tfAll;

  // Snapshot der initial-populierten Combo-Items - RebuildFilterCombos
  // reduziert daraus pro Scan auf Eintraege mit > 0 Treffern.
  SnapshotFilterItems;

  // ---- Zeile: Aktionen + Profile + Suche + Export ----
  // Wie PanelPath: Right-Padding=0 ist im Helper, damit der rechte
  // Cancel/Export-Block buendig am Panel-Rand sitzt.
  var PanelSearch := TIDEToolbar.CreateRow(Self, Self, ToolbarRowH,
    ScaleW(TB_PADDING_LR), ScaleW(TB_PADDING_TB));
  // Left-Padding fuer DIESE Row auf 0: BtnAnalyse soll buendig an der
  // linken Frame-Kante sitzen (kein Einrueck-Gap wie bei Path-/Filter-Row).
  PanelSearch.Padding.Left := 0;
  FPanelSearch := PanelSearch;

  // Action-Buttons links - "▶ Analyse" zuerst (links), dann "📄 File"
  BtnAnalyse := TIDEToolbar.AddButton(Self, PanelSearch, _('▶ Analyse'),
    ScaleW(BTN_W_LONG), alLeft, AnalyseClick);
  FBtnAnalyse := BtnAnalyse;

  FBtnAnalyseCurrent := TIDEToolbar.AddButton(Self, PanelSearch, _('📄 File'),
    ScaleW(BTN_W_MED_LONG), alLeft, AnalyseCurrentFileClick);

  // Profile (rule-set scope): steuert welches Rule-Set die NAECHSTE
  // Analyse benutzt (ide-fast / default / strict / ...). Items kommen
  // aus rules/sca-rules.json (TRuleCatalog.ProfileNames); Default-
  // Selektion = FRepoSettings.IdeProfile. Transient (kein INI-Save);
  // wirkt beim naechsten Analyse-Klick ueber PrepareAnalysis ->
  // UseIdeRuleSet + ApplyDetectorThresholds.
  FProfileCombo := TIDEToolbar.CreateLabelCombo(Self, PanelSearch,
    _('Profile:'), ScaleW(LBL_W_PROFILE), ScaleW(CMB_W_PROFILE), FLblProfile);
  FProfileCombo.OnChange := ProfileChange;
  FProfileCombo.Hint     := _('Rule-set profile (ide-fast / default / strict). ' +
                              'Takes effect at the next analysis run.');
  FProfileCombo.ShowHint := True;
  FPanelProfile := FProfileCombo.Parent as TPanel;
  PopulateProfileCombo;

  // FBtnAnalyseChanged + FBtnCancel + FBtnExport sind aus der Toolbar raus -
  // ihre Aktionen sind ausschliesslich im Hamburger-Menu (unten).

  // Hamburger-Button am rechten Rand - IMMER sichtbar, das ist der
  // einzige Zugang zu Branch-Changes / Cancel / Export / Settings / Ignore.
  // Caption #$2630 = "Trigram for Heaven" (Hamburger-Glyph).
  FBtnHamburger := TIDEToolbar.AddButton(Self, PanelSearch, #$2630,
    ScaleW(BTN_W_ICON), alRight, HamburgerClick,
    _('Actions menu: Branch-Changes, Cancel, Export, Settings, Ignore'));

  // Export-Menu (PopupMenu-Objekt) wird trotzdem gebraucht - Hamburger-
  // Item "Export..." ruft FExportMenu.PopupAt() auf.
  FExportMenu := TFindingExportMenu.Create(Self,
    FAllFindings, FDisplayedFindings, GetResultGrid,
    StatusMode, GetCurrentBaseDir);

  // Analyse-Busy-Controller. ABtnCancel=nil (Cancel ist Menu-Item, kein
  // Button), Run-Buttons-Liste enthaelt nur die immer-sichtbaren beiden.
  FAnalyseProgress := TAnalyseProgressController.Create(Self,
    FProgressBar, nil,
    [FBtnAnalyse, FBtnAnalyseCurrent]);

  // Analyse-Runner: kapselt RunAll/RunCurrent/RunChanged.
  FAnalyseRunner := TAnalyseRunner.Create(Self, Pointer(Self),
    FAnalyseProgress, FRepoSettings, FIgnoreList, FProgressBar,
    StatusMode, StatusProgress, PopulateFindings);

  // Sucheingabe fuellt den Rest in der Mitte. MinWidth verhindert Kollaps
  // bei sehr schmal gedocktem Frame - sonst frisst Search-Edit als
  // alClient zwischen den alLeft/alRight-Buttons gerne 0 px.
  // MinWidth wird per AdjustSearchMinWidth dynamisch gesetzt (docked vs
  // floated); hier nur den Floated-Default als sichere Initial-Annahme.
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := PanelSearch;
  FSearchEdit.Align  := alClient;
  FSearchEdit.Constraints.MinWidth := ScaleW(SEARCH_MIN_WIDTH_FLOATED);
  // MaxWidth=150: Search-Edit soll nicht ueber die gewuenschte Breite
  // hinaus stretchen, alClient cappt dann den Stretch.
  FSearchEdit.Constraints.MaxWidth := ScaleW(150);
  FSearchEdit.TextHint := _('Filter file / method / finding...');
  FSearchEdit.OnChange := SearchChange;
  TIDEToolbar.ApplySegoeUI(FSearchEdit);

  // Einheitliche Toolbar-Hoehe + Icon-Button-Constraints. Details siehe
  // ApplyToolbarSizing weiter unten.
  ApplyToolbarSizing(UnifCtrlH);

  // Responsive-Layout: 3-Stufen-Controller + Sichtbarkeitstabelle.
  // WireResponsiveLayout legt FResponsive an, registriert die Controls
  // und setzt den AfterApply-Hook.
  WireResponsiveLayout;

  // ---- alTop-Reihenfolge fix ----
  // VCL TWinControl.AlignControls sortiert alTop-Children nach Margins.
  // ControlTop (= Control.Top). Wir setzen die Tops explizit aufsteigend.
  // DisableAlign/EnableAlign verhindert dass jede einzelne Top-Zuweisung
  // einen Zwischen-Realign triggert.
  // Tatsaechliche Top-Werte sind irrelevant — VCL re-positioniert beim
  // EnableAlign neu basierend auf der relativen Sortierung.
  //
  // Visuelle Reihenfolge (top -> bottom):
  //   FPanelStats   - Tile-Reihe (Errors/Warnings/Hints/Bugs/...)
  //   PanelSearch   - "▶ Analyse" + "📄 File" + Profile + Search + Hamburger
  //   PanelPath     - "Path:" + Combo + Browse
  //   PanelFilters  - Severity + Type
  DisableAlign;
  try
    FPanelStats.Top   := 10;
    PanelSearch.Top   := 20;
    PanelPath.Top     := 30;
    PanelFilters.Top  := 40;
  finally
    EnableAlign;
  end;

  // ---- Statistik-Tiles in das jetzt korrekt gestackte FPanelStats ----
  // FResponsive existiert ab WireResponsiveLayout, BuildStatsTiles
  // registriert die optionalen Tiles als FResponsive.RegisterCtrl.
  BuildStatsTiles(FPanelStats);

  // Initial-Stats setzen, damit die Score-Kachel beim Frame-Open schon
  // den Letter-Grade ("A" bei leerer Befund-Liste) anzeigt statt der
  // CountLbl-Default-"0". Severity-/Type-Kacheln bleiben "0" - dort
  // ist 0 die richtige Anzeige fuer "noch keine Analyse gelaufen".
  UpdateStats;

  // ---- Client: Result-Grid + Hilfe-Panel direkt auf das Frame ----
  // Frueher gab es einen PanelClient-Wrapper (alClient TPanel) als Container
  // fuer Grid + Help. Die Wrapper-Schicht war nicht noetig — das Frame
  // selbst hat genug freie Flaeche nach den alTop/alBottom-Stripes, und
  // VCL setzt alRight (FHelpPanel) und alClient (FResultGrid) direkt auf
  // dem Frame korrekt nebeneinander.
  //
  // Hilfe-Panel + Splitter + Dock-State-Logik komplett gekapselt in
  // uIDEHelpPanel. Anchor = Self damit HostIsFloating den Form-Chain
  // hochlaufen kann. Ownership via Self -> auto-Free.
  FHintPanel := TFindingHintPanel.Create(Self, Self, Self);

  BuildResultGrid(Self);

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

  // Theme-Subscription FRUEH aufloesen: setzt das IInterface auf nil,
  // was den Refcount auf 0 fallen laesst -> TSubscription.Destroy
  // unsubscribed beim Singleton. Ein noch schwebender Theme-Wechsel-
  // Callback feuert dann nicht mehr in halb-zerlegte Frame-Felder.
  FThemeSub := nil;

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
  // Delegation an den zentralen TIDETheme-Manager. Apply macht:
  //   1. IOTAIDEThemingServices.ApplyTheme auf dem TopForm (Float-Mode)
  //      bzw. auf Self (Dock-Mode).
  //   2. Rekursives Invalidate aller Kinder.
  //   3. Expliziten Repaint auf TStringGrid (Paint-Cache).
  // Defensiv: nicht waehrend Destroy weiterleiten - csDestroying ist
  // gesetzt sobald der Destructor startet.
  if csDestroying in ComponentState then Exit;
  // Style-Cache leeren - der naechste Grid-Repaint zieht die neue
  // Theme-Referenz nach (z.B. nach Wechsel Dark <-> Light in der IDE).
  FCachedIDEStyles := nil;
  TIDETheme.Apply(Self);
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

// ---------------------------------------------------------------------------
// Populate-Methoden fuer die drei Toolbar-Combos.
//
// Aus dem Constructor ausgelagert (~110 Zeilen reine Items-AddObject-
// Aufrufe) - der UI-Build-Pfad bleibt damit lesbar, und Sprach-Wechsel-
// Hooks koennen die Combos bei Bedarf wiederbefuellen.
// ---------------------------------------------------------------------------

procedure TAnalyserFrame.PopulateFilterCombo;
// Severity-Filter: gruppiert nach Errors / Warnings / Hints. Sentinel-Items
// mit Tag = -1 (z.B. '--- Errors ---') sind nicht selektierbar; FilterChange
// faengt den Klick darauf ab und setzt zurueck auf "All".

  procedure Add(const ACaption: string; AMode: TFilterMode);
  begin
    FFilterCombo.Items.AddObject(_(ACaption), TObject(Ord(AMode)));
  end;

  procedure Sep(const ACaption: string);
  begin
    FFilterCombo.Items.AddObject(_(ACaption), TObject(-1));
  end;

begin
  // ---- Gesamt-Kategorien ----
  Add('All',            fmAll);
  // Spezial-Modus fuer Detector-Qualitaets-Review: zeigt EINEN zufaelligen
  // Befund pro Detector-Kind. Severity/Type-Filter wirken danach auf die
  // Stichprobe (kein erneutes Sampling beim Toggle).
  // Nur in DEBUG-Builds UND wenn die INI [Rules] EnableDetectorReviewFilter
  // gesetzt hat - Release-Builds sehen den Eintrag nie (internes Tool).
  {$IFDEF DEBUG}
  if Assigned(FRepoSettings) and FRepoSettings.DetectorReviewFilterEnabled then
    Add('Detector Review (1 per detector, random)', fmDetectorReview);
  {$ENDIF}
  Add('Errors (all)',   fmErrors);
  Add('Warnings (all)', fmWarnings);
  Add('Hints (all)',    fmHints);

  // ---- Errors (einzeln) ----
  Sep('--- Errors ---');
  Add('Memory Leak',                       fmMemoryLeak);
  Add('SQL Injection',                     fmSQLInjection);
  Add('Hardcoded Secrets',                 fmHardcodedSecret);
  Add('Format()',                          fmFormatMismatch);
  Add('Nil-Deref',                         fmNilDeref);
  Add('Div by Zero',                       fmDivByZero);
  Add('Missing Raise',                     fmMissingRaise);
  Add('Result Unassigned',                 fmRoutineResultUnassigned);
  Add('Instance-Invoked Constructor',      fmInstanceInvokedConstructor);
  Add('Char -> PChar Cast',                fmCharToCharPointerCast);
  Add('Raise outside except',              fmRaiseOutsideExcept);
  Add('Use After Free',                    fmUseAfterFree);
  Add('Abstract method not implemented',   fmAbstractNotImpl);
  Add('Leak in constructor',               fmLeakInConstructor);
  Add('Integer overflow (Int64 mul)',      fmIntegerOverflow);
  Add('God Class',                         fmGodClass);
  Add('Free without nil-out',              fmFreeWithoutNil);
  Add('Multiple Exit',                     fmMultipleExit);
  Add('Large Class',                       fmLargeClass);
  Add('Unsorted uses clause',              fmUnsortedUses);
  Add('Missing unit header',               fmMissingUnitHeader);
  Add('Float equality',                    fmFloatEquality);
  Add('Raise in destructor',               fmExceptInDestructor);
  Add('Boolean parameter as flag',         fmBooleanParam);
  Add('Unused private method',             fmUnusedPrivateMethod);
  Add('Could be class method',             fmCanBeClassMethod);
  Add('Missing override',                  fmMissingOverride);
  Add('Boolean always true / false',       fmBoolAlwaysTrue);
  Add('Constant return value',             fmConstantReturn);
  Add('Hardcoded user string',             fmHardcodedString);
  Add('Command Injection',                 fmCommandInjection);

  // ---- Warnings (einzeln) ----
  Sep('--- Warnings ---');
  Add('Empty Except',          fmEmptyExcept);
  Add('Missing Finally',       fmMissingFinally);
  Add('Dead Code',             fmDeadCode);
  Add('Unused Uses',           fmUnusedUses);
  Add('Debug Output',          fmDebugOutput);
  Add('Hardcoded Path',        fmHardcodedPath);
  Add('Read Error',            fmFileReadError);
  Add('Re-Raise Exception',    fmReRaiseException);
  Add('Raising Raw Exception', fmRaisingRawException);
  Add('Date Format Settings',  fmDateFormatSettings);
  Add('Unicode -> Ansi Cast',  fmUnicodeToAnsiCast);
  Add('IfThen Short-Circuit',  fmIfThenShortCircuit);
  Add('Exception Too General', fmExceptionTooGeneral);
  Add('Insecure Crypto Algo',  fmInsecureCryptoAlgorithm);

  // ---- Hints (einzeln) ----
  Sep('--- Hints ---');
  Add('Long Method',             fmLongMethod);
  Add('Many Parameters',         fmLongParamList);
  Add('Magic Number',            fmMagicNumber);
  Add('Duplicate Strings',       fmDuplicateString);
  Add('Duplicate Code Blocks',   fmDuplicateBlock);
  Add('Deep Nesting',            fmDeepNesting);
  Add('Cyclomatic Complexity',   fmCyclomaticComplexity);
  Add('TODO/FIXME',              fmTodoComment);
  Add('Empty Methods',           fmEmptyMethod);
  Add('Can Be Unit Private',     fmCanBeUnitPrivate);
  Add('Can Be Strict Private',   fmCanBeStrictPrivate);
  Add('Can Be Protected',        fmCanBeProtected);
  Add('Unused Public Member',    fmUnusedPublicMember);
  Add('Unused Local Var',        fmUnusedLocalVar);
  Add('Unused Parameter',        fmUnusedParameter);
  Add('Tautological Expression', fmTautologicalBoolExpr);
  Add('Master-Detail Unlinked',  fmDfmMasterDetailUnlinked);
  Add('Data Module Split Hint',  fmDfmDataModuleSplitHint);
  Add('Dangerous SQL Statement', fmSqlDangerousStatement);
  Add('Format Locale Hint',      fmFormatLocaleHint);
  Add('Cast And Free',           fmCastAndFree);
  Add('Inherited (empty)',       fmInheritedMethodEmpty);
  Add('Nil Comparison',          fmNilComparison);
  // mORMot-Cluster (SCA153-155)
  Add('Unpaired Lock',                            fmUnpairedLock);
  Add('Move/FillChar SizeOf(Pointer)',            fmMoveSizeOfPointer);
  Add('with on multiple targets',                 fmWithMultipleTargets);
  // mORMot-Cluster Phase 2 (SCA156-158)
  Add('GetMem without try/finally',               fmGetMemWithoutFreeMem);
  Add('SetLength grow in loop',                   fmSetLengthAppendInLoop);
  Add('PChar arithmetic without empty-check',     fmPointerArithmeticOnString);
  // mORMot-Cluster Phase 3 (SCA159-161)
  Add('Empty typed exception handler',            fmEmptyOnHandler);
  Add('String cast from raw pointer',             fmStringFromPointer);
  Add('Pointer subtraction (Win64 truncation)',   fmPointerSubtraction);
  // Audit-Nachzug (Todo_neuerdetector-Checkliste)
  Add('Unused Routine',                           fmUnusedRoutine);
  Add('NOSONAR Marker (legacy)',                  fmNoSonarMarker);
  // SCA165 - Unused-Suppression-Marker
  Add('Unused noinspection Marker',               fmUnusedSuppression);

  FFilterCombo.ItemIndex := 0; // "All"
end;

procedure TAnalyserFrame.PopulateTypeCombo;
// Sonar-Kategorien als Filter. Englische Identifiers fix - matchen die
// Strings in den Befund-TypeText-Feldern (Bug/Code Smell/Vulnerability/
// Security Hotspot/Code Duplication).
begin
  // Items.Objects tragen Ord(TTypeFilter) damit RebuildFilterCombos die
  // aktuelle Auswahl nach dem Scan via Mode-Ord wiederherstellen kann -
  // ItemIndex-basiertes Mapping waere nach dem Reduzieren verschoben.
  // tfAll = 0 -> Object = nil (siehe TypeFilterChange-Lookup).
  FTypeCombo.Items.AddObject(_('All'),              TObject(Ord(tfAll)));
  FTypeCombo.Items.AddObject('Bug',                 TObject(Ord(tfBug)));
  FTypeCombo.Items.AddObject('Code Smell',          TObject(Ord(tfCodeSmell)));
  FTypeCombo.Items.AddObject('Vulnerability',       TObject(Ord(tfVulnerability)));
  FTypeCombo.Items.AddObject('Security Hotspot',    TObject(Ord(tfSecurityHotspot)));
  FTypeCombo.Items.AddObject('Code Duplication',    TObject(Ord(tfCodeDuplication)));
  FTypeCombo.ItemIndex := 0;
end;

procedure TAnalyserFrame.PopulateProfileCombo;
// Profile-Liste aus rules/sca-rules.json (TRuleCatalog.ProfileNames).
// Fallback 'default' wenn das Catalog leer ist.
// Default-Selektion: FRepoSettings.IdeProfile, fallback 'ide-fast', sonst 0.
var
  ProfileList : TArray<string>;
  ProfileName : string;
  Idx         : Integer;
begin
  ProfileList := TRuleCatalog.ProfileNames;
  if Length(ProfileList) = 0 then
    FProfileCombo.Items.Add(_('default'))
  else
    for ProfileName in ProfileList do
      FProfileCombo.Items.Add(ProfileName);

  Idx := FProfileCombo.Items.IndexOf(FRepoSettings.IdeProfile);
  if Idx < 0 then Idx := FProfileCombo.Items.IndexOf('ide-fast');
  if Idx < 0 then Idx := 0;
  FProfileCombo.ItemIndex := Idx;
end;

procedure TAnalyserFrame.ApplyToolbarSizing(AUnifCtrlH: Integer);
// Loest die VCL-Quirk dass TComboBox die Align.Height ignoriert. Buttons
// und Edits respektieren Align von Hause aus, der Helper-Aufruf ist hier
// redundant aber konsistent: jede Toolbar-Component geht durch denselben
// Sizing-Pfad. ScaleW skaliert den 96-DPI-Wert auf die Container-PPI.
// Icon-Buttons mit erzwungener Width+Height-Constraints damit sie pixel-
// genau identisch rendern (Browse + Hamburger).
begin
  // Icon-Buttons - quadratisch mit fixer Width.
  TToolbarSizing.ApplyIconButton(FBtnBrowse,         ScaleW(BTN_W_ICON), AUnifCtrlH);
  TToolbarSizing.ApplyIconButton(FBtnHamburger,      ScaleW(BTN_W_ICON), AUnifCtrlH);
  // Restliche Components nur Hoehe vereinheitlichen.
  TToolbarSizing.Apply(FProjectPath,        AUnifCtrlH);
  TToolbarSizing.Apply(FFilterCombo,        AUnifCtrlH);
  TToolbarSizing.Apply(FTypeCombo,          AUnifCtrlH);
  TToolbarSizing.Apply(FProfileCombo,       AUnifCtrlH);
  TToolbarSizing.Apply(FBtnAnalyse,         AUnifCtrlH);
  TToolbarSizing.Apply(FBtnAnalyseCurrent,  AUnifCtrlH);
  TToolbarSizing.Apply(FSearchEdit,         AUnifCtrlH);
end;

procedure TAnalyserFrame.WireResponsiveLayout;
// 3-Stufen-Sichtbarkeitstabelle. Eine Klasse, eine ClientWidth-Quelle
// (= Frame.ClientWidth). Stage-Bestimmung + DPI-Skalierung intern.
// AfterApply-Callback fired nach JEDEM Resize -> dynamische Folge-
// Anpassungen (FilterSubPanels-Width, SearchEdit-MinWidth) bleiben aktuell.
// FResponsive selbst wird Self-owned -> Auto-Free im Frame-Destroy.
//
// Stats-Tiles werden in BuildStatsTiles registriert (laufzeit-bedingt
// erst NACH dem dortigen Tile-Setup).
begin
  FResponsive := TResponsiveLayoutController.Create(Self, Self,
    BREAKPOINT_MEDIUM, BREAKPOINT_FULL);

  // PanelPath: FBtnBrowse, LblPath, FProjectPath: immer sichtbar.
  // (FBtnRepo/FBtnIgnore wurden entfernt — im Hamburger-Menu.)

  // PanelFilters (Severity + Type)
  FResponsive.RegisterCtrl(FLblFilter,         usMedium);
  FResponsive.RegisterCtrl(FLblType,           usMedium);
  // (FFilterCombo, FTypeCombo + Sub-Panels: immer sichtbar)

  // PanelSearch: Profile-Label im MEDIUM ausblenden.
  // (FBtnCancel/FBtnExport/FBtnAnalyseChanged wurden entfernt — im Hamburger-Menu.
  //  FBtnHamburger ist IMMER sichtbar - keine Registrierung.
  //  FBtnAnalyse, FBtnAnalyseCurrent, FProfileCombo, FSearchEdit: immer sichtbar.)
  FResponsive.RegisterCtrl(FLblProfile,        usMedium);

  FResponsive.AfterApply := ResponsiveAfterApply;
end;

procedure TAnalyserFrame.BuildResultGrid(AParent: TWinControl);
// Virtuelles TStringGrid: Cell-Inhalt kommt zur Paint-Zeit via OnDrawCell
// aus FDisplayedFindings (siehe GridDrawCell + TFindingGridRenderer).
// FixedCols/FixedRows = Header. ColWidths sind 96-DPI-Defaults; GridResize
// passt die Befund-Spalte (4) dynamisch der verbleibenden Breite an.
begin
  FResultGrid := TStringGrid.Create(Self);
  FResultGrid.Parent := AParent;
  FResultGrid.Align  := alClient;
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
  TIDEToolbar.ApplySegoeUI(FResultGrid);
  // DoubleBuffered: TStringGrid hat viele kleine OnDrawCell-Aufrufe,
  // Off-Screen-Buffer eliminiert Flicker beim Scrollen und beim
  // Severity-Recolor nach einem Sort-Wechsel.
  FResultGrid.DoubleBuffered := True;
  FResultGrid.GridLineWidth  := 1;
  FResultGrid.Options := [goFixedVertLine, goFixedHorzLine,
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
  InitGridConfig;
  // WindowProc-Subclassing fuer WM_MOUSEWHEEL-Coalescing. Muss NACH der
  // Grid-Erzeugung (FResultGrid existiert) und vor dem ersten Paint sein.
  InstallGridWheelCoalescer;
  // Debouncer fuer Highlighter-Rebuild + ApplyFilter (Konzept Tier A1+B1).
  InitDebounceTimers;
  FResultGrid.OnDrawCell   := GridDrawCell;
  FResultGrid.OnDblClick   := GridDblClick;
  FResultGrid.OnSelectCell := GridSelectCell;
  FResultGrid.OnMouseDown  := GridMouseDown;
  FResultGrid.OnKeyDown    := GridKeyDown;
  // Tooltip-Setup (Subclass + Hint-Properties + HintPause-Override) ist
  // im TFindingGridTooltip-Helper gekapselt. Owner=Self -> Auto-Free
  // plus expliziter FreeAndNil im Destruktor (Restore-Reihenfolge).
  FGridTooltip := TFindingGridTooltip.Create(Self, FResultGrid, FDisplayedFindings);
end;

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
  WireTile(FTileScore,    _('Quality') + sLineBreak +
           _('Weighted quality score (lower = better).')
           + sLineBreak + _('Weights: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.')
           + sLineBreak + _('Click: reset filters (show everything)'),
           0, TileClickClear);

  // Tile-Visibility wird ueber den zentralen FResponsive registriert.
  // Tile-Labels -> Parent.Parent ist die TilePanel (TopRow dazwischen).
  //
  // Tier-Aufteilung:
  //   essential (immer):     Errors, Warnings, Hints, Quality           (4)
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
    // Separator-Eintrag (---/--- Errors ---/--- Hints ---). User-Wunsch:
    // beim Klick zum NAECHSTEN Detail-Eintrag UNTERHALB des Separators
    // springen (= erstes Item der jeweiligen Kategorie). Fallback wenn
    // kein Item mehr unter dem Separator liegt: vorherige Auswahl
    // wiederherstellen.
    // Re-Entry-Schutz: ItemIndex-Setzen feuert OnChange erneut.
    var NextIdx : Integer := -1;
    for var j := idx + 1 to FFilterCombo.Items.Count - 1 do
      if Integer(FFilterCombo.Items.Objects[j]) >= 0 then
      begin
        NextIdx := j;
        Break;
      end;
    if NextIdx >= 0 then
    begin
      // Forward-Springen zum naechsten echten Eintrag - Filter wechselt.
      tag := Integer(FFilterCombo.Items.Objects[NextIdx]);
      OldOnChange := FFilterCombo.OnChange;
      FFilterCombo.OnChange := nil;
      try
        FFilterCombo.ItemIndex := NextIdx;
      finally
        FFilterCombo.OnChange := OldOnChange;
      end;
      FFilterMode := TFilterMode(tag);
      FLastNonSeparatorMode := tag;
      ApplyFilter;
      Exit;
    end;
    // Kein Folge-Eintrag (Separator am Listen-Ende) -> vorherige Auswahl
    // wiederherstellen, kein Filter-Update.
    var RestoreIdx := 0;
    for var i := 0 to FFilterCombo.Items.Count - 1 do
      if (Integer(FFilterCombo.Items.Objects[i]) = FLastNonSeparatorMode)
         and (Integer(FFilterCombo.Items.Objects[i]) >= 0) then
      begin
        RestoreIdx := i;
        Break;
      end;
    OldOnChange := FFilterCombo.OnChange;
    FFilterCombo.OnChange := nil;
    try
      FFilterCombo.ItemIndex := RestoreIdx;
    finally
      FFilterCombo.OnChange := OldOnChange;
    end;
    Exit;
  end;
  FFilterMode := TFilterMode(tag);
  FLastNonSeparatorMode := tag;  // Anker fuer den naechsten Separator-Klick
  ApplyFilter;
end;

procedure TAnalyserFrame.TypeFilterChange(Sender: TObject);
// Type-Lookup via Items.Objects = Ord(TTypeFilter) - robust gegen
// Item-Removal in RebuildFilterCombos. tfAll = 0 als nil-Object.
var
  idx : Integer;
begin
  if FTypeCombo.Items.Count = 0 then Exit;
  idx := FTypeCombo.ItemIndex;
  if (idx < 0) or (idx >= FTypeCombo.Items.Count) then Exit;
  if Assigned(FTypeCombo.Items.Objects[idx]) then
    FTypeFilter := TTypeFilter(Integer(FTypeCombo.Items.Objects[idx]))
  else
    FTypeFilter := tfAll;
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
  const Criteria: TFindingFilterCriteria; TotalMatched: Integer);
begin
  // Wenn TotalMatched gesetzt ist und ueber dem angezeigten Count liegt,
  // wurde gecappt (UIMaxDisplayedFindings) - macht's transparent.
  if (TotalMatched > 0) and (TotalMatched > FDisplayedFindings.Count) then
    StatusFindings(Format(_(
      'Showing first %d of %d findings - refine the filter to see more'),
      [FDisplayedFindings.Count, TotalMatched]))
  else
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
  i            : Integer;
  Criteria     : TFindingFilterCriteria;
  SortCfg      : TFindingSortConfig;
  TotalMatched : Integer;
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

    // ---- DetectorReview-Stichprobe ----------------------------------
    // Pro Detector-Kind 1 zufaelligen Befund behalten. Wirkt NACH dem
    // normalen Filter-Loop (Type/Search greifen weiter); Severity-Combo
    // greift implizit nicht (fmDetectorReview faellt in Matches durch
    // zum else-Pfad = True). Randomize bei jedem Aufruf - Reviewer sieht
    // bei Re-Toggle eine andere Stichprobe und deckt ueber mehrere Klicks
    // mehr Befunde ab.
    if Criteria.Mode = fmDetectorReview then
    begin
      Randomize;
      var Buckets := TObjectDictionary<TFindingKind,
                       TList<TLeakFinding>>.Create([doOwnsValues]);
      try
        for var F in FDisplayedFindings do
        begin
          if not Buckets.ContainsKey(F.Kind) then
            Buckets.Add(F.Kind, TList<TLeakFinding>.Create);
          Buckets[F.Kind].Add(F);    // nur Referenzen, kein Free
        end;
        FDisplayedFindings.Clear;
        for var Bucket in Buckets.Values do
          if Bucket.Count > 0 then
            FDisplayedFindings.Add(Bucket[Random(Bucket.Count)]);
      finally
        Buckets.Free;
      end;
    end;

    // ---- Sortierung (Logik in uFindingFilter.TFindingSorter.Sort) ----
    if FSortColumn >= 0 then
    begin
      SortCfg.Column     := FSortColumn;
      SortCfg.Descending := FSortDescending;
      SortCfg.BaseDir    := FCurrentBaseDir;
      TFindingSorter.Sort(FDisplayedFindings, SortCfg);
    end;

    // ---- Anzeige-Cap (NACH Sort, damit die Top-N sortiert sind) ----
    // TStringGrid wird ab ~50k Zeilen spuerbar trag. Export/Highlighter/
    // Baseline arbeiten weiterhin mit FAllFindings - der Cap betrifft
    // ausschliesslich die Grid-Anzeige. 0 = kein Cap.
    TotalMatched := FDisplayedFindings.Count;
    if (uSCAConsts.UIMaxDisplayedFindings > 0) and
       (TotalMatched > uSCAConsts.UIMaxDisplayedFindings) then
      FDisplayedFindings.Count := uSCAConsts.UIMaxDisplayedFindings;

    PopulateGridFromDisplayed;
  finally
    SendMessage(FResultGrid.Handle, WM_SETREDRAW, 1, 0);
    FResultGrid.Invalidate;
  end;

  UpdateFilterStatus(Criteria, TotalMatched);

  // Multi-File-Marker-Refresh: nach jedem Filter-Wechsel oder
  // Analyse-Lauf zeigt der Highlighter ab sofort Stripes + Hover-
  // Overlays auf JEDEM Editor-Tab dessen Datei in der gefilterten
  // Liste vertreten ist. Vorher: erst nach Grid-Klick. Damit ist der
  // Tab-Switch-Use-Case ohne Click erreichbar.
  ScheduleHighlightRefresh('');
end;

// ---------------------------------------------------------------------------
// Suchfeld
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.SearchChange(Sender: TObject);
// 200ms-Debounce statt ApplyFilter pro Keystroke. Bei "memory" tippen
// laeuft ApplyFilter EINMAL nach Tippstopp, nicht 6x dazwischen.
// Andere Filter-Wechsel (Severity-/Type-Combo) feuern weiter sofort.
begin
  if FFilterDebounceTimer = nil then
  begin
    // Fallback wenn Setup noch nicht durch (sollte nicht vorkommen).
    ApplyFilter;
    Exit;
  end;
  FFilterDebounceTimer.Enabled := False;
  FFilterDebounceTimer.Enabled := True;
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
// Tastatur-Shortcuts im Findings-Grid:
//   * Cursor-Up/Down navigieren via VCL-Default; OnSelectCell ruft
//     UpdateHelp automatisch - kein F3-Handler noetig.
//   * Ctrl+Alt+F = Apply Quick-Fix
//   * Ctrl+Alt+S = Insert Suppression
//   * Enter      = Goto Editor (analog Doppelklick)
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // Master-Gate: bei ShortcutsEnabled=False wird KEIN Plugin-Shortcut im
  // Grid verarbeitet. Cursor-Navigation per VCL-Default bleibt aktiv.
  if not IsShortcutsMasterEnabled then Exit;
  if (Key = Ord('F')) and (ssCtrl in Shift) and (ssAlt in Shift) then
  begin
    // Ctrl+Alt+F = Apply Quick-Fix: ersetzt die Zeile direkt im IDE-Editor
    // (TIDEEditor.ApplyLineReplacement). Konflikt-frei mit RAD-Studio-
    // Defaults (F4 ist "Run to Cursor", Ctrl+. konfliktet mit Code-
    // Completion; Ctrl+Alt+F ist die IntelliJ-Quick-Fix-Konvention).
    // No-op wenn kein Provider registriert oder Pattern auf der Zeile
    // nicht matched - Status-Bar zeigt jeweils den Grund.
    ApplyQuickFixForRow(FResultGrid.Row);
    Key := 0;
  end
  else if (Key = Ord('S')) and (ssCtrl in Shift) and (ssAlt in Shift) then
  begin
    // Ctrl+Alt+S = Insert Suppression: fuegt `// noinspection <RuleName>`
    // ueber die Befund-Zeile im IDE-Editor ein. Naechster Analyse-Lauf
    // filtert den Befund weg. Ctrl+Z reverts den Insert.
    ApplySuppressForRow(FResultGrid.Row);
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

procedure TAnalyserFrame.SnapshotFilterItems;
var
  i : Integer;
begin
  SetLength(FAllSeverityItems, FFilterCombo.Items.Count);
  for i := 0 to FFilterCombo.Items.Count - 1 do
  begin
    FAllSeverityItems[i].Display := FFilterCombo.Items[i];
    // Sentinel-Separatoren werden mit Tag = -1 angelegt; Pointer-Cast
    // erhaelt das durch Integer-Roundtrip.
    FAllSeverityItems[i].ModeOrd := Integer(FFilterCombo.Items.Objects[i]);
  end;
  SetLength(FAllTypeItems, FTypeCombo.Items.Count);
  for i := 0 to FTypeCombo.Items.Count - 1 do
  begin
    FAllTypeItems[i].Display := FTypeCombo.Items[i];
    FAllTypeItems[i].ModeOrd := Integer(FTypeCombo.Items.Objects[i]);
  end;
end;

procedure TAnalyserFrame.RebuildFilterCombos;
// Reduziert FFilterCombo + FTypeCombo auf Eintraege deren Mode/Type in
// FAllFindings mindestens einen Treffer hat. 'All' und 'Detector Review'
// bleiben immer drin. Separatoren (ModeOrd = -1) werden im ersten Pass
// vorlaufig behalten und im zweiten Pass weggeworfen wenn sie keinen
// folgenden Detail-Eintrag mehr haben (vermeidet '--- Errors ---'-
// Header ohne darunter liegende Items).
var
  Item : TFilterComboItem;
  SavedSevMode, SavedTypeMode, NewIdx, i : Integer;
  Filtered : TArray<TFilterComboItem>;
  Tmp : TList<TFilterComboItem>;
begin
  if FAllFindings = nil then Exit;
  if Length(FAllSeverityItems) = 0 then Exit;

  // Aktuelle Auswahl merken (Mode-Ord, nicht Index).
  SavedSevMode := Ord(fmAll);
  if (FFilterCombo.ItemIndex >= 0)
     and Assigned(FFilterCombo.Items.Objects[FFilterCombo.ItemIndex]) then
    SavedSevMode := Integer(FFilterCombo.Items.Objects[FFilterCombo.ItemIndex]);
  SavedTypeMode := Ord(tfAll);
  if (FTypeCombo.ItemIndex >= 0)
     and Assigned(FTypeCombo.Items.Objects[FTypeCombo.ItemIndex]) then
    SavedTypeMode := Integer(FTypeCombo.Items.Objects[FTypeCombo.ItemIndex]);

  // ---- Severity-Filter: zwei-Pass-Filterung ----
  Tmp := TList<TFilterComboItem>.Create;
  try
    for Item in FAllSeverityItems do
    begin
      if (Item.ModeOrd = -1)                    // Separator: vorlaeufig behalten
         or (Item.ModeOrd = Ord(fmAll))
         or (Item.ModeOrd = Ord(fmDetectorReview))
         or (TFindingFilter.CountForMode(FAllFindings,
                                         TFilterMode(Item.ModeOrd)) > 0) then
        Tmp.Add(Item);
    end;
    // Pass 2: orphan separators entfernen (Separator gefolgt von Separator
    // oder am Ende der Liste -> weg).
    SetLength(Filtered, 0);
    for i := 0 to Tmp.Count - 1 do
    begin
      if Tmp[i].ModeOrd = -1 then
      begin
        if (i = Tmp.Count - 1) or (Tmp[i + 1].ModeOrd = -1) then
          Continue;
      end;
      // noinspection SetLengthAppendInLoop
      // Filtered ist klein (max. Filter-Combo-Items, ~5-15); kein Perf-Hot-Path.
      SetLength(Filtered, Length(Filtered) + 1);
      Filtered[High(Filtered)] := Tmp[i];
    end;
  finally
    Tmp.Free;
  end;

  FFilterCombo.Items.BeginUpdate;
  try
    FFilterCombo.Clear;
    for Item in Filtered do
      FFilterCombo.Items.AddObject(Item.Display, TObject(Item.ModeOrd));
  finally
    FFilterCombo.Items.EndUpdate;
  end;
  NewIdx := 0;
  for i := 0 to FFilterCombo.Items.Count - 1 do
    if (Integer(FFilterCombo.Items.Objects[i]) = SavedSevMode)
       and (Integer(FFilterCombo.Items.Objects[i]) <> -1) then
    begin
      NewIdx := i;
      Break;
    end;
  FFilterCombo.ItemIndex := NewIdx;

  // ---- Type-Combo ----
  FTypeCombo.Items.BeginUpdate;
  try
    FTypeCombo.Clear;
    for Item in FAllTypeItems do
    begin
      if (Item.ModeOrd = Ord(tfAll))
         or (TFindingFilter.CountForType(FAllFindings,
                                         TTypeFilter(Item.ModeOrd)) > 0) then
        FTypeCombo.Items.AddObject(Item.Display, TObject(Item.ModeOrd));
    end;
  finally
    FTypeCombo.Items.EndUpdate;
  end;
  NewIdx := 0;
  for i := 0 to FTypeCombo.Items.Count - 1 do
    if Integer(FTypeCombo.Items.Objects[i]) = SavedTypeMode then
    begin
      NewIdx := i;
      Break;
    end;
  FTypeCombo.ItemIndex := NewIdx;
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
  // Filter-Combos auf Eintraege mit > 0 Treffern reduzieren - vor
  // ApplyFilter damit die anschliessende Filterung schon gegen die
  // ggf. zurueckgesetzte Auswahl arbeitet.
  RebuildFilterCombos;
  ApplyFilter;
  // ApplyFilter -> HighlightAllFindingsInFile baut die Multi-File-Marker
  // bereits sauber neu auf (SetAllFindings ersetzt den gesamten internen
  // State). Ein zusaetzlicher GHighlighter.Clear ist nicht mehr noetig -
  // er wuerde die gerade gesetzten Marker sofort wieder loeschen.
  // (Befund-Spiegelung in IDE-Messages-Toolbar ist deaktiviert -
  //  siehe Kommentar am Ende von ApplyFilter.)
end;

// Liefert den Sonar-Style-Letter-Grade A..E aus dem rohen gewichteten
// Score. Schwellwerte aus analyser.ini [Score]:
//   * A  = perfekt (0 Findings)
//   * B  = 1..ABMax    (Default 50)
//   * C  = ABMax+1..BCMax (Default 200)
//   * D  = BCMax+1..CDMax (Default 500)
//   * E  = > CDMax
//
// Vorteil gegenueber der reinen Zahl: skaliert wahrnehmungs-konstant -
// 12.847 ist nicht "viel schlimmer als 5.420", in beiden Faellen wirft
// die Kachel "E" raus und der Reader weiss sofort "rot". Detail-Zahl
// landet im Tooltip.
function ScoreToGrade(AScore, ABMax, BCMax, CDMax: Integer): string;
begin
  if AScore <= 0     then Exit('A');
  if AScore <= ABMax then Exit('B');
  if AScore <= BCMax then Exit('C');
  if AScore <= CDMax then Exit('D');
  Result := 'E';
end;

// Liefert eine 1-Zeilen-Erklaerung zum Grade fuer den Tooltip.
function GradeMeaning(const AGrade: string): string;
begin
  if AGrade = 'A' then Exit(_('No findings - clean baseline'));
  if AGrade = 'B' then Exit(_('Clean - minor smells only'));
  if AGrade = 'C' then Exit(_('Visible tech debt, no critical bugs'));
  if AGrade = 'D' then Exit(_('Multiple errors/vulnerabilities - refactor advised'));
  Result := _('Refactor needed - many critical findings');
end;

// Setzt Hint-Property rekursiv auf C und seine TWinControl-Children.
// Notwendig weil der Tile aus mehreren ueberlagerten Labels besteht und
// der Tooltip auf jedem Sub-Control sichtbar sein muss.
procedure SetHintRecursive(C: TControl; const NewHint: string);
var
  i  : Integer;
  WC : TWinControl;
begin
  if C = nil then Exit;
  C.Hint := NewHint;
  if C is TWinControl then
  begin
    WC := TWinControl(C);
    for i := 0 to WC.ControlCount - 1 do
      SetHintRecursive(WC.Controls[i], NewHint);
  end;
end;

procedure TAnalyserFrame.UpdateStats;
// Befuellt die Sonar-Style Tiles mit Severity-, Typ-Aufteilung und
// Quality-Score. Jede Kachel hat ihr eigenes Count-Label - keine
// Indirektion, keine Truncation, keine OnDraw-Logik.
//
// Quality-Score-Gewichte (gewichtete Summe, niedriger = besser):
//   Vulnerability=10, Error=7, Hotspot=5, Warning=3, Hint=1, FileErr=2
//
// Anzeige seit 2026-05: roher Score wird auf Letter-Grade A..E gemappt
// (siehe ScoreToGrade). Die Kachel zeigt nur noch den Buchstaben, die
// Rohzahl + Severity-Breakdown landen im Tooltip - skaliert besser bei
// grossen Projekten und macht die Aussage wahrnehmungs-konstant.
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
  grade                        : string;
  scoreHint                    : string;
  scoreTile                    : TControl;
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

  // Codequalitaet: Letter-Grade-Anzeige + Detail im Tooltip.
  // Kachel zeigt nur den Buchstaben (A..E) - eine rohe Zahl wuerde bei
  // grossen Projekten 4-/5-stellig werden und ist ohne Skala unleserlich.
  // Tooltip listet Score + Breakdown, sodass der User per Hover die
  // Roh-Werte sieht. Schwellwerte aus analyser.ini [Score].
  var
    abMax, bcMax, cdMax: Integer;
  if Assigned(FRepoSettings) then
  begin
    abMax := FRepoSettings.ScoreThresholdB;
    bcMax := FRepoSettings.ScoreThresholdC;
    cdMax := FRepoSettings.ScoreThresholdD;
  end
  else
  begin
    abMax := 50;
    bcMax := 200;
    cdMax := 500;
  end;
  grade := ScoreToGrade(score, abMax, bcMax, cdMax);
  FTileScore.Caption := grade;

  scoreHint :=
    _('Code Quality') + ': ' + grade + ' - ' + GradeMeaning(grade) + sLineBreak +
    Format(_('Raw score: %d'), [score]) + sLineBreak +
    Format(_('Errors: %d, Warnings: %d, Hints: %d'),
      [nErr, nWarn, nHint]) + sLineBreak +
    Format(_('Vulnerabilities: %d, Hotspots: %d, File errors: %d'),
      [nVuln, nHot, nFileErr]) + sLineBreak +
    Format(_('Grade scale: A=0, B<=%d, C<=%d, D<=%d, E>%d'),
      [abMax, bcMax, cdMax, cdMax]) + sLineBreak +
    _('Weights: Vuln 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2') + sLineBreak +
    _('Click: reset filters (show everything)');

  // Hint rekursiv setzen: Tile-Container + alle Subcontrols (TopRow,
  // IconLbl, CountLbl, CapLbl) - sonst wuerde Hover auf Glyph oder
  // Caption keinen Tooltip zeigen.
  if Assigned(FTileScore.Parent) and Assigned(FTileScore.Parent.Parent) then
  begin
    scoreTile := FTileScore.Parent.Parent;
    SetHintRecursive(scoreTile, scoreHint);
  end;
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
  // Help-Panel-Repaint flushen, bevor der (potenziell blockierende)
  // Clipboard-Write laeuft - Windows-Clipboard-Listener koennen
  // Clipboard.AsText 50-200ms abwuergen, das Panel soll vorher sichtbar sein.
  Application.ProcessMessages;
  CopyFindingToClipboard(Finding);

  // Editor-Line-Highlights: alle Befunde der gleichen Datei mit Stripe
  // markieren. Wenn die Datei nicht offen ist, malt GHighlighter beim
  // naechsten Oeffnen. Debounce: bei Pfeiltasten-Hold kollabieren viele
  // Aufrufe zu einem Rebuild nach Idle (Konzept Tier A1).
  ScheduleHighlightRefresh(Finding.FileName);
end;

procedure TAnalyserFrame.CopyFindingToClipboard(F: TLeakFinding);
// Bei Findings mit Quick-Fix-Provider wird ein "Quick-Fix"-Markdown-
// Block vorangestellt: Original-Zeile + Fixed-Zeile direkt zum Pasten.
// Der Claude-Prompt-Block folgt darunter wie bisher.
var
  prompt    : string;
  LineNo    : Integer;
  OrigLine  : string;
  Fix       : TQuickFixResult;
  SrcLines  : TStringList;
  QuickFixHdr : string;
begin
  if not Assigned(F) then Exit;

  prompt := BuildClaudePrompt(F);
  QuickFixHdr := '';

  // Wenn ein Quick-Fix-Provider fuer dieses Kind registriert ist,
  // versuche die Original-Zeile zu lesen und einen Fix vorzuschlagen.
  if TQuickFix.HasProviderFor(F.Kind) then
  begin
    LineNo := StrToIntDef(F.LineNumber, 0);
    if (LineNo > 0) and (F.FileName <> '') and FileExists(F.FileName) then
    begin
      SrcLines := TStringList.Create;
      try
        try
          SrcLines.LoadFromFile(F.FileName, TEncoding.UTF8);
        except
          try SrcLines.LoadFromFile(F.FileName); except SrcLines.Clear; end;
        end;
        if (LineNo <= SrcLines.Count) then
        begin
          OrigLine := SrcLines[LineNo - 1];
          Fix := TQuickFix.ProposeFix(F, OrigLine);
          if Fix.Applied then
          begin
            QuickFixHdr :=
              '## Quick-Fix' + sLineBreak +
              Fix.Description + sLineBreak + sLineBreak +
              '**Vorher (Zeile ' + F.LineNumber + '):**' + sLineBreak +
              '```pascal' + sLineBreak + Fix.Original + sLineBreak + '```' + sLineBreak + sLineBreak +
              '**Nachher (direkt einfuegen):**' + sLineBreak +
              '```pascal' + sLineBreak + Fix.Fixed + sLineBreak + '```' + sLineBreak + sLineBreak +
              '---' + sLineBreak + sLineBreak;
          end;
        end;
      finally
        SrcLines.Free;
      end;
    end;
  end;

  try
    Clipboard.AsText := QuickFixHdr + prompt;
    if Assigned(FStatusBar) then
    begin
      if QuickFixHdr <> '' then
        StatusMode(Format(
          _('Quick-Fix + AI prompt copied to clipboard: %s, line %s (%s)'),
          [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]))
      else
        StatusMode(Format(
          _('AI prompt copied to clipboard: %s, line %s (%s)'),
          [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]));
    end;
  except
    // Clipboard kann unter bestimmten IDE-Modi blockiert sein - silent skip
  end;
end;

procedure TAnalyserFrame.ApplyQuickFixForRow(RowIdx: Integer);
// Pipeline:
//   1. Finding fuer Grid-Zeile holen
//   2. Source-Zeile aus der Datei lesen (UTF-8 mit ANSI-Fallback)
//   3. TQuickFix.ProposeFix
//   4. TIDEEditor.ApplyLineReplacement
// Bei jedem Schritt: Status-Bar-Hint, kein Crash bei Fehler.
var
  F          : TLeakFinding;
  LineNo     : Integer;
  SrcLines   : TStringList;
  Fix        : TQuickFixResult;
  OK         : Boolean;
begin
  if not Assigned(FDisplayedFindings) then Exit;
  if (RowIdx <= 0) or (RowIdx > FDisplayedFindings.Count) then Exit;

  F := FDisplayedFindings[RowIdx - 1];
  if not Assigned(F) then Exit;

  if not TQuickFix.HasProviderFor(F.Kind) then
  begin
    StatusMode(Format(
      _('Quick-Fix: no provider for ''%s'' - manual fix required'),
      [F.RuleID]));
    Exit;
  end;

  LineNo := StrToIntDef(F.LineNumber, 0);
  if (LineNo <= 0) or (F.FileName = '') or not FileExists(F.FileName) then
  begin
    StatusMode(_('Quick-Fix: cannot locate source line'));
    Exit;
  end;

  SrcLines := TStringList.Create;
  try
    try
      SrcLines.LoadFromFile(F.FileName, TEncoding.UTF8);
    except
      try SrcLines.LoadFromFile(F.FileName); except SrcLines.Clear; end;
    end;
    if LineNo > SrcLines.Count then
    begin
      StatusMode(_('Quick-Fix: line out of range'));
      Exit;
    end;
    Fix := TQuickFix.ProposeFix(F, SrcLines[LineNo - 1]);
  finally
    SrcLines.Free;
  end;

  if not Fix.Applied then
  begin
    StatusMode(Format(
      _('Quick-Fix: pattern not matched on line %d - manual fix required'),
      [LineNo]));
    Exit;
  end;

  OK := TIDEEditor.ApplyLineReplacement(F.FileName, LineNo, Fix.Fixed);
  if OK then
    StatusMode(Format(_('Quick-Fix applied: %s'), [Fix.Description]))
  else
    StatusMode(_('Quick-Fix: editor write failed (file not in IDE?)'));
end;

procedure TAnalyserFrame.ApplySuppressForRow(RowIdx: Integer);
// Holt das Finding fuer die Grid-Zeile + ruft TIDEEditor.InsertLineAbove
// mit `// noinspection <KindName>`. Schreibt das Result in die Status-Bar.
var
  F      : TLeakFinding;
  LineNo : Integer;
  OK     : Boolean;
  Marker : string;
begin
  if not Assigned(FDisplayedFindings) then Exit;
  if (RowIdx <= 0) or (RowIdx > FDisplayedFindings.Count) then Exit;
  F := FDisplayedFindings[RowIdx - 1];
  if not Assigned(F) then Exit;

  LineNo := StrToIntDef(F.LineNumber, 0);
  if (LineNo <= 0) or (F.FileName = '') then
  begin
    StatusMode(_('Suppress: cannot locate source line'));
    Exit;
  end;

  Marker := '// noinspection ' + KindName(F.Kind);
  OK := TIDEEditor.InsertLineAbove(F.FileName, LineNo, Marker);
  if OK then
    StatusMode(Format(_('Suppress inserted: %s'), [Marker]))
  else
    StatusMode(_('Suppress: editor write failed (file not in IDE?)'));
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
var
  ProfileOverride: string;
begin
  if not Assigned(FRepoSettings) then Exit;
  // Profile-Override aus der UI-Combo extrahieren - leere String wenn nichts
  // gewaehlt (dann gilt der INI-Wert nach UseIdeRuleSet).
  ProfileOverride := '';
  if Assigned(FProfileCombo) and (FProfileCombo.ItemIndex >= 0) then
    ProfileOverride := FProfileCombo.Items[FProfileCombo.ItemIndex];

  // Schritte 1-7 (Load + Register + IDE-Profile + Override + Thresholds +
  // AutoDiscover-Sync + Clear + BumpGeneration) laufen ueber den Single-
  // Point-of-Truth in uIDELifecycle - synchronisiert mit Silent-Mode +
  // Watch-Worker, damit alle Pfade konsistenten Detector-State setzen.
  TIDEAnalysisPrep.SetupForRun(FRepoSettings, Trim(FProjectPath.Text),
    ProfileOverride);

  // Watch-Mode-Activate/Deactivate bleibt Frame-lokal weil die Callbacks
  // (OnWatchFindings, OnWatchStatus) Frame-Methoden sind. Im Bulk-Pfad
  // (AWatchedFile leer) deaktivieren um keinen alten Watcher zu halten.
  if Assigned(GWatchMode) then
  begin
    if AWatchedFile <> '' then
      GWatchMode.Activate(OnWatchFindings, OnWatchStatus, AWatchedFile,
        FRepoSettings.UsesCheck)
    else if GWatchMode.Active then
      GWatchMode.Deactivate;
  end;
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

procedure TAnalyserFrame.ClearAllMarksClick(Sender: TObject);
// Entfernt mit einem Schlag ALLE Hover-Annotation-Marker quer ueber alle
// Dateien: Editor-Stripes verschwinden, sichtbares Overlay-Popup wird
// versteckt, Save-Notifier werden abgemeldet. Der GHighlighter.Clear-Pfad
// triggert intern InvalidateAllLines + HideOverlay + DetachAllSaveNotifiers
// (siehe uIDELineHighlighter.TFindingHighlighter.Clear). Das Grid mit den
// Findings bleibt unveraendert - User kann ueber das Kontextmenue "Markieren"
// erneut Marker setzen, ohne neu zu analysieren.
begin
  if Assigned(GHighlighter) then GHighlighter.Clear;
  if Assigned(GAnnotationOverlay) then GAnnotationOverlay.HideOverlay;
  StatusMode(_('All markers cleared.'));
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
  // FilterSubPanels (Severity+Type+Profile-Wrapper) sitzen in PanelFilters,
  // SearchEdit-MinWidth haengt an PanelSearch.
  if Assigned(FPanelFilters) then AdjustFilterSubPanels(FPanelFilters);
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
// belegen und die Search-Row platzen.
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

// ---------------------------------------------------------------------------
// Hamburger-Menu: einziger Zugang zu Branch-Changes / Cancel / Export /
// Settings / Ignore (die zugehoerigen Buttons sind nicht mehr in der
// Toolbar). Menu wird lazy beim ersten Klick gebaut. PopupMenu-Hook
// synct die Enabled-States der dynamischen Items (Cancel, Branch) mit
// FAnalyseProgress.Running.
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.BuildHamburgerMenu;
var
  MI : TMenuItem;
begin
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := HamburgerMenuPopup;

  // ---- Aktions-Block: Branch-Changes ---------------------------------
  FMIAnalyseChanged := TMenuItem.Create(FHamburgerMenu);
  FMIAnalyseChanged.Caption := _('Analyse Branch-Changes');
  FMIAnalyseChanged.OnClick := AnalyseChangedFilesClick;
  FHamburgerMenu.Items.Add(FMIAnalyseChanged);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Cancel (Enabled wird in HamburgerMenuPopup gesynct) -----------
  FMICancel := TMenuItem.Create(FHamburgerMenu);
  FMICancel.Caption := _('Cancel Analysis');
  FMICancel.OnClick := CancelAnalyseClick;
  FHamburgerMenu.Items.Add(FMICancel);

  // ---- Clear all hover-marker (Enabled-Sync ueber GHighlighter.HasMarks)
  FMIClearMarks := TMenuItem.Create(FHamburgerMenu);
  FMIClearMarks.Caption := _('Clear all markers');
  FMIClearMarks.OnClick := ClearAllMarksClick;
  FHamburgerMenu.Items.Add(FMIClearMarks);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Export --------------------------------------------------------
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Export') + '...';
  MI.OnClick := HamburgerExportClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
  FHamburgerMenu.Items.Add(MI);

  // ---- Konfig-Block: Settings + Ignore -------------------------------
  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Settings...');
  MI.OnClick := EditRepoSettingsClick;
  FHamburgerMenu.Items.Add(MI);

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := _('Ignore list...');
  MI.OnClick := EditIgnoreListClick;
  FHamburgerMenu.Items.Add(MI);

  FBtnHamburger.PopupMenu := FHamburgerMenu;
end;

procedure TAnalyserFrame.HamburgerMenuPopup(Sender: TObject);
// Enabled-Sync VOR dem Oeffnen: Cancel ist nur waehrend laufender Analyse
// aktiv; Branch-Changes ist waehrend Analyse deaktiviert;
// Clear-Markers nur wenn ueberhaupt Marker im Highlighter liegen.
begin
  if Assigned(FMICancel) then
    FMICancel.Enabled :=
      Assigned(FAnalyseProgress) and FAnalyseProgress.Running;
  if Assigned(FMIAnalyseChanged) then
    FMIAnalyseChanged.Enabled :=
      (not Assigned(FAnalyseProgress)) or (not FAnalyseProgress.Running);
  if Assigned(FMIClearMarks) then
    FMIClearMarks.Enabled := Assigned(GHighlighter) and GHighlighter.HasMarks;
end;

procedure TAnalyserFrame.HamburgerClick(Sender: TObject);
// Lazy-Build des Menus beim ersten Klick, dann Popup unter dem Button.
var
  P : TPoint;
begin
  if not Assigned(FBtnHamburger) then Exit;
  if not Assigned(FHamburgerMenu) then
    BuildHamburgerMenu;
  if not Assigned(FHamburgerMenu) then Exit;
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FHamburgerMenu.Popup(P.X, P.Y);
end;

procedure TAnalyserFrame.HamburgerExportClick(Sender: TObject);
// Export-Menu-Item: oeffnet das Export-Popup unter dem Hamburger-Button.
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
  ScheduleHighlightRefresh(absPath);
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
    Entries[Count].Severity := DispSev;    // Multi-Mark-Ranking (staerkste zuerst)
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

procedure TAnalyserFrame.CMStyleChanged(var Message: TMessage);
// Zweiter Theme-Trigger neben TIDETheme.Subscribe (= INTAIDEThemingServices-
// Notifier). VCL feuert CM_STYLECHANGED via WndProc-Kette an jeden Control
// wenn TStyleManager.SetStyle laeuft. Im Docked-Modus ist das oft der einzige
// Pfad der unseren Frame erreicht: TopForm ist dort das IDE-Main-Window,
// dessen ApplyTheme nicht in unseren Frame-Subtree propagiert; die VCL-
// Nachricht hingegen wandert ueber Parent-Hierarchie und Control-Iteration
// an alle Children. Forwarding an RefreshFromIDETheme -> per-Control
// ApplyTheme im TIDETheme-Manager.
begin
  inherited;
  if csDestroying in ComponentState then Exit;
  RefreshFromIDETheme;
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
    if FPanelFilters.Width <> W then FPanelFilters.Width := W;
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
    if FPanelFilters.Width <> W then FPanelFilters.Width := W;
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

procedure TAnalyserFrame.InitGridConfig;
// Bau-once: alle 3 Closures (StyleServices, CellText, CellSeverity) werden
// hier EINMAL alloziert. Vorher: pro DrawCell-Aufruf - 3 anonyme Methoden +
// Config-Record × ~300 sichtbare Zellen pro Repaint = ~900 Heap-Allokationen
// pro Frame. Bei Mausrad-Scroll waren das mehrere tausend kleine Objekte
// pro Sekunde → GDI/Paint kam nicht hinterher → Event-Stau.
//
// Sort-Indicator (FSortColumn / FSortDescending) wird in GridDrawCell pro
// Frame im Config aktualisiert - kostet nur 2 Integer-Writes, keine Alloc.
begin
  FGridConfig := TFindingGridRenderer.IDEConfig(FSortColumn, FSortDescending);
  FGridConfig.GetStyleServices :=
    function: TCustomStyleServices
    var
      Theming: IOTAIDEThemingServices;
    begin
      // Cache-Hit: stabile Theme-Referenz, kein QueryInterface pro Zelle.
      // Invalidierung in RefreshFromIDETheme.
      if FCachedIDEStyles <> nil then Exit(FCachedIDEStyles);
      if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
        FCachedIDEStyles := Theming.StyleServices;
      Result := FCachedIDEStyles;
    end;
  FGridConfig.GetCellText :=
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

procedure TAnalyserFrame.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
// Reicht die in InitGridConfig vorbereitete Config durch. Sort-Indikator-
// Felder werden pro Aufruf aktualisiert (2 Integer-Writes), die Closures
// bleiben stabil.
begin
  FGridConfig.SortColumn     := FSortColumn;
  FGridConfig.SortDescending := FSortDescending;
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State, FGridConfig);
end;

procedure TAnalyserFrame.InstallGridWheelCoalescer;
// Installiert einen Custom-WindowProc auf FResultGrid (Instance-Level
// Subclassing, kein neuer Component-Typ noetig). Das Original wird in
// FOrigGridWindowProc gemerkt und in GridWindowProc weitergerufen.
// Cleanup: beim Frame-Destroy gibt inherited FResultGrid frei -
// FOrigGridWindowProc zeigt dann ins Leere, wird aber nie wieder gerufen.
begin
  if FResultGrid = nil then Exit;
  FOrigGridWindowProc := FResultGrid.WindowProc;
  FResultGrid.WindowProc := GridWindowProc;
end;

procedure TAnalyserFrame.GridWindowProc(var Msg: TMessage);
// Coalescing: alle pendingenden WM_MOUSEWHEEL der Grid-Queue zu einem
// einzigen grossen Scroll falten. Vorher: jedes WM_MOUSEWHEEL fuehrte
// zu Scroll + Repaint; bei Repaint > Wheel-Tick-Intervall stauten sich
// Messages und der Grid scrollte sekundenlang nach dem Loslassen weiter.
// Nach Coalescing: 1 grosse Scrolloperation, 1 Repaint, kein Backlog.
var
  PendingMsg : TMsg;
  TotalDelta : Integer;
begin
  if Msg.Msg = WM_MOUSEWHEEL then
  begin
    TotalDelta := TWMMouseWheel(Msg).WheelDelta;
    // Pendingende WM_MOUSEWHEEL der gleichen HWND aus der Queue ziehen
    // (PM_REMOVE) und Delta aufsummieren. Andere Messages bleiben drin.
    while PeekMessage(PendingMsg, FResultGrid.Handle,
                      WM_MOUSEWHEEL, WM_MOUSEWHEEL, PM_REMOVE) do
      Inc(TotalDelta, SmallInt(HiWord(PendingMsg.wParam)));
    // SmallInt-Sattigung, damit HiWord-Roundtrip ueberlebt (Wrap waere
    // bei einem riesigen Burst sonst moeglich).
    if TotalDelta > High(SmallInt) then TotalDelta := High(SmallInt)
    else if TotalDelta < Low(SmallInt) then TotalDelta := Low(SmallInt);
    TWMMouseWheel(Msg).WheelDelta := SmallInt(TotalDelta);
  end;
  FOrigGridWindowProc(Msg);
end;

procedure TAnalyserFrame.InitDebounceTimers;
const
  DEBOUNCE_MS = 200;
begin
  FHighlightDebounceTimer := TTimer.Create(Self);
  FHighlightDebounceTimer.Interval := DEBOUNCE_MS;
  FHighlightDebounceTimer.Enabled  := False;
  FHighlightDebounceTimer.OnTimer  := HighlightDebounceFire;

  FFilterDebounceTimer := TTimer.Create(Self);
  FFilterDebounceTimer.Interval := DEBOUNCE_MS;
  FFilterDebounceTimer.Enabled  := False;
  FFilterDebounceTimer.OnTimer  := FilterDebounceFire;
end;

procedure TAnalyserFrame.HighlightDebounceFire(Sender: TObject);
// Idle-Tick erreicht - jetzt der eigentliche, teure Highlighter-Rebuild.
// Bei Pfeiltasten-Hold haben sich viele ScheduleHighlightRefresh-Aufrufe
// auf EINEN Timer-Reset reduziert; hier feuert er nur 1x nach Stopp.
begin
  if FHighlightDebounceTimer <> nil then
    FHighlightDebounceTimer.Enabled := False;
  if csDestroying in ComponentState then Exit;
  HighlightAllFindingsInFile(FPendingHighlightFile);
end;

procedure TAnalyserFrame.ScheduleHighlightRefresh(const AFileName: string);
// Statt direkt HighlightAllFindingsInFile zu rufen, 200ms-Timer resetten.
// Aufeinanderfolgende Aufrufe innerhalb des Intervalls kollabieren zu
// einem einzigen Rebuild nach User-Idle.
begin
  if FHighlightDebounceTimer = nil then
  begin
    // Setup noch nicht durch - synchron als Fallback, damit es zumindest
    // funktionert (z.B. fruehe Frame-Init-Pfade).
    HighlightAllFindingsInFile(AFileName);
    Exit;
  end;
  FPendingHighlightFile := AFileName;
  FHighlightDebounceTimer.Enabled := False; // reset countdown
  FHighlightDebounceTimer.Enabled := True;
end;

procedure TAnalyserFrame.FilterDebounceFire(Sender: TObject);
// Idle-Tick: jetzt der eigentliche ApplyFilter-Aufruf (Filter-Scan +
// Sort + Highlighter-Schedule).
begin
  if FFilterDebounceTimer <> nil then
    FFilterDebounceTimer.Enabled := False;
  if csDestroying in ComponentState then Exit;
  ApplyFilter;
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
  // First-time-open-via-Menu-Flow:
  //
  //   1. User -> View > Static Code Analysis
  //   2. ShowAnalyserDockableForm -> NTASvc.CreateDockableForm
  //   3. TAnalyserFrame.Create:
  //        - Color := IDE_BG_CHROME
  //        - ApplySegoeUI(Self)
  //        - FThemeSub := TIDETheme.Subscribe  (Notifier registriert)
  //        - Toolbar-Zeilen + Grid erzeugen
  //   4. IDE setzt Frame.Parent := HostTForm
  //        -> SetParent-Override: RefreshFromIDETheme -> Apply (Theme #1)
  //   5. <hier> FrameCreated:
  //        - Font-Reset auf Frame (gegen IDE-Embed-Override - Children
  //          mit ParentFont=False sind davon nicht betroffen).
  //        - Constraints auf HostForm hochpropagieren (Float-Mindestgroesse).
  //
  TIDEToolbar.ApplySegoeUI(F);

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

    // Float-Mode-Icon: ohne explizites HostForm.Icon faellt das Window-
    // Caption-Icon im undocked Zustand auf das RAD-Studio-Default zurueck.
    // Multi-Res ICO (SCA_APP_ICO) aus der sca_branding.res - Windows picks
    // size by DPI/Caption-Height/Alt-Tab.
    // GetParentForm liefert TCustomForm dessen .Icon protected ist; erst
    // TForm macht es published. Cast ist sicher: das IDE-DockHost ist immer
    // ein TForm-Descendant, KEIN reiner TCustomForm.
    if HostForm is TForm then
      try
        TForm(HostForm).Icon.LoadFromResourceName(HInstance, 'SCA_APP_ICO');
      except
        // Resource fehlt -> kein Icon, kein Plugin-Crash.
      end;
  end;

  // Theme-Apply auch hier - belt-and-suspenders zum SetParent-Override:
  // bei manchen IDE-Dock-Sequenzen (insb. wenn der Frame ueber einen
  // anderen Mechanismus parented wird als das einfache Parent-Setzen)
  // greift der SetParent-Pfad nicht zuverlaessig. Apply ist idempotent
  // (kein Schaden bei mehrfachem Aufruf) und stellt sicher dass das
  // erstmalige Open via Menue garantiert themed ist.
  TIDETheme.Apply(F);
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
    Result[Count].Severity := DispSev;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

procedure RunSilentAnalysisForFile(const AFileName: string;
  ACenterOnFirstFinding: Boolean = True);
// Silent-Mode-Entrypoint: analysiert AFileName + setzt Marker direkt am
// GHighlighter. Kein Frame, kein Dock-Open. Fehler still an
// OutputDebugString. Settings + Profile werden frisch geladen (analog zu
// WatchMode-Worker).
// ACenterOnFirstFinding: True (Default) = Editor scrollt zur ersten
// Finding-Line. False = nur Analyse, keine Editor-Bewegung (gebraucht vom
// Properties-Panel-Auto-Scan beim Tab-Wechsel).
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
    // Dock-Combo gewinnt ueber INI - so wirkt eine Profile-Auswahl im Dock
    // auch im Silent-Run. Wenn das Dock nie geoeffnet wurde: Override leer
    // -> INI-Wert aus UseIdeRuleSet greift.
    var DockOverride := '';
    if Assigned(GDockableForm) and Assigned(GDockableForm.Frame) then
      DockOverride := GDockableForm.Frame.CurrentProfileOverride;

    // Single-Point-of-Truth Setup (uIDELifecycle): Load + Register +
    // UseIdeRuleSet + ProfileOverride + ApplyDetectorThresholds +
    // AutoDiscover-Sync + Discovered-Clear + BumpGeneration. Schritte
    // identisch zu TAnalyserFrame.PrepareAnalysis - kein Drift mehr.
    TIDEAnalysisPrep.SetupForRun(Settings, ExtractFilePath(AFileName),
      DockOverride);

    try
      // Single-File-Analyse mit projektweitem Symbol-Reference-Index
      // (ProjectRoot via .dproj/.dpk/.dpr-Walk-Up, Fallback .git-Root).
      // Visibility-Detektoren laufen mittlerweile single-file-only - der
      // Projekt-Scope dient den uebrigen Cross-Unit-Detektoren (DFM-Repo,
      // Custom-Rules) sowie der Symbol-Sammlung fuer kuenftige Analysen.
      Findings := TStaticAnalyzer2.AnalyzeLeaks(AFileName,
        TStaticFiles.FindProjectRoot(AFileName), Settings.UsesCheck);
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

    // Properties-Panel (und andere Subscriber) ueber die Silent-Findings
    // informieren. Borrowed-Refs - Subscriber klonen selbst wenn sie
    // persistieren wollen. Idempotent wenn keine Subscriber registriert.
    if Assigned(GWatchMode) and Assigned(Findings) then
      GWatchMode.DispatchToSubscribers(AFileName, Findings);

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
    if ACenterOnFirstFinding and (FirstLine < MaxInt) then
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

function IsShortcutsMasterEnabled: Boolean;
// Master-Gate ueber ALLE Plugin-Shortcuts. Wird in jedem Shortcut-Handler
// (TSCAKeyboardBinding, TSCAFindingNavBinding, GridKeyDown) ganz vorne
// abgefragt. False -> alle Tastenkuerzel sind tot, aber der Silent-Mode
// per Rechtsklick-Menue + die Toolbar-Buttons bleiben funktional.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    Result := Settings.ShortcutsEnabled;
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
// Bindet den konfigurierbaren Silent-Analyse-Shortcut.
// Wird einmalig beim BPL-Load gerufen; Default = Ctrl+Alt+A, kann ueber
// analyser.ini [Hotkeys] SilentAnalyseShortcut oder Tools > Options
// veraendert werden. Aenderung erfordert IDE-Neustart.
var
  Settings : TRepoSettings;
  SC       : TShortCut;
begin
  SC := ShortCut(Ord('A'), [ssCtrl, ssAlt]);  // Default
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    if Trim(Settings.SilentAnalyseShortcut) <> '' then
    begin
      var Parsed := TextToShortCut(Settings.SilentAnalyseShortcut);
      if Parsed <> 0 then SC := Parsed;
    end;
  finally
    Settings.Free;
  end;
  BindingServices.AddKeyBinding([SC], SilentAnalyseKeyProc, nil);
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
// Master-Toggle ueberlagert: bei ShortcutsEnabled=False meldet der Handler
// krUnhandled, IDE-Default greift. Rechtsklick-Menue funktioniert
// unabhaengig (geht ueber IsSilentEnabled, nicht das Master-Gate).
begin
  if not IsShortcutsMasterEnabled then
  begin
    BindingResult := krUnhandled;
    Exit;
  end;
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

  // Globaler Hook: ActiveStyleServices liefert ab jetzt die IDE-Theme-
  // StyleServices statt der VCL-globalen. Damit folgen alle shared UI-
  // Komponenten (uAnalyserTheme.SeverityBg, uIDEStatsTiles.TTilePanel.
  // Paint, uIDEHelpPanel) dem IDE-Theme - kritisch wenn der User einen
  // anderen VCL-Style aktiv hat als das IDE-Theme.
  uAnalyserTheme.StyleServicesProvider :=
    function: TCustomStyleServices
    var
      Theming: IOTAIDEThemingServices;
    begin
      Result := nil;
      if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
        Result := Theming.StyleServices;
    end;

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
  // Ctrl+Alt+Down / Ctrl+Alt+Up: zur naechsten / vorherigen markierten
  // Finding-Zeile im aktuellen Editor-Tab springen (wrap-around).
  // Nutzt GHighlighter; muss daher NACH RegisterLineHighlighter laufen.
  RegisterFindingNavBinding;

  // Tools > Options > Third Party > Static Code Analyser
  // (Checkbox um den Silent-Mode aus-/anzuschalten).
  RegisterSCAAddInOptions;

  // Tools > Options > Third Party > Sonar Integration
  // (separate Page - Host/Token/ProjectKey + Test-Connection).
  RegisterSonarAddInOptions;
end;

procedure ShowAnalyserDockableForm;
// Wird vom View-Menue-Eintrag + vom IDE-Wizard-Execute gerufen. Robust
// gegen Race-Conditions: wenn GDockableForm waehrend Plugin-Reload kurz
// nil ist, einfach nicht crashen. Exception aus CreateDockableForm wuerde
// sonst stumm verschluckt und der User denkt das Menue reagiert nicht.
var
  NTASvc : INTAServices;
begin
  if not Assigned(GDockableForm) then Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTASvc) then Exit;
  try
    NTASvc.CreateDockableForm(GDockableForm);
  except
    on E: Exception do
      // Sichtbares Feedback statt stilles Schlucken - der User sieht
      // sonst gar nichts beim Menueklick und kann den Fehler nicht melden.
      Application.MessageBox(
        PChar('Static Code Analyser: ' + E.ClassName + #10#13 + E.Message),
        'Plugin Open Error',
        MB_ICONERROR or MB_OK);
  end;
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
  UnregisterFindingNavBinding;
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
