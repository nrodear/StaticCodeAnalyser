unit uMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.IOUtils, System.StrUtils,
  System.Types,   // TPoint + Point()-Inline-Funktion (Hamburger-Popup-Positionierung)
  System.Classes, Vcl.Graphics, System.Generics.Collections,
   Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Grids, Vcl.Menus,   // Vcl.Menus: TPopupMenu/TMenuItem (Hamburger-Felder)
  uStaticAnalyzer2,
  uMethodd12, uSCAConsts, uFixHint, uClaudePrompt, uLocalization,
  uAnalyserTypes,  // SeverityFromKindLevel, TFindingSeverity (Grid-Renderer-Callback)
  uRepoSettings, uRecentPaths, uFindingGridRenderer, uDfmTextViewer,
  uIDEHelpPanel,                  // TFindingHintPanel (im class-Feld referenziert)
  uExportMenu,                    // TFindingExportMenu (Class-Field-Reference)
  uFindingFilter,                 // TFilterComboItem (Snapshot-Felder)
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
    procedure HamburgerClick(Sender: TObject);
    procedure HamburgerMenuPopup(Sender: TObject);
    procedure BuildHamburgerMenu;
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
    procedure AnalyseSingleFile(const AFilePath: string);
    procedure FillGridFromFindings(Findings: TObjectList<TLeakFinding>;
      const ABaseDir: string);
    function  BuildClaudePrompt(F: TLeakFinding): string;
    function SelectFolder: string;
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

// noinspection-file ConcatToFormat, DebugOutput, EmptyExcept, EmptyOnHandler, ExceptOnException, GodClass, LargeClass, MultipleExit
// UI-Form-Top-Level: catch-all-Handler an Action-Grenzen (Click/Resize) sind
// gewollt - eine UI-Exception darf nie die App killen. EmptyOnHandler/
// EmptyExcept fuer EAbort (User-Cancel) sind intentional. DebugOutput-Pattern
// ShowMessage ist hier als User-Feedback-Kanal verwendet, nicht als Debug.
// GodClass/LargeClass: VCL-Main-Form sammelt VCL-Event-Handler, kann nicht
// dekomponiert werden ohne Action-Owner-Splits.

uses
  clipbrd,
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

{$R *.dfm}

procedure TForm2.FormCreate(Sender: TObject);
var
  Settings    : TRepoSettings;
  ProfileList : TArray<string>;
  Name        : string;
  Idx         : Integer;
begin
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
  ResultGrid.OnDrawCell := ResultGridDrawCell;
  ResultGrid.OnDblClick := ResultGridDblClick;
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
  SeverityFilterCombo.Items.AddObject(_('Memory Leaks (all)'),     TObject(Ord(fmMemoryLeak)));
  SeverityFilterCombo.Items.AddObject(_('Can Be Unit Private'),    TObject(Ord(fmCanBeUnitPrivate)));
  SeverityFilterCombo.Items.AddObject(_('Can Be Strict Private'),  TObject(Ord(fmCanBeStrictPrivate)));
  SeverityFilterCombo.Items.AddObject(_('Can Be Protected'),       TObject(Ord(fmCanBeProtected)));
  SeverityFilterCombo.Items.AddObject(_('Unused Public Member'),   TObject(Ord(fmUnusedPublicMember)));
  SeverityFilterCombo.Items.AddObject(_('Unused Local Var'),       TObject(Ord(fmUnusedLocalVar)));
  SeverityFilterCombo.Items.AddObject(_('Unused Parameter'),       TObject(Ord(fmUnusedParameter)));
  SeverityFilterCombo.Items.AddObject(_('Tautological Expression'),TObject(Ord(fmTautologicalBoolExpr)));
  SeverityFilterCombo.Items.AddObject(_('Master-Detail Unlinked'), TObject(Ord(fmDfmMasterDetailUnlinked)));
  SeverityFilterCombo.Items.AddObject(_('Data Module Split Hint'), TObject(Ord(fmDfmDataModuleSplitHint)));
  SeverityFilterCombo.Items.AddObject(_('Dangerous SQL Statement'),TObject(Ord(fmSqlDangerousStatement)));
  SeverityFilterCombo.Items.AddObject(_('Format Locale Hint'),     TObject(Ord(fmFormatLocaleHint)));
  // SonarDelphi-Migration (SCA120-131)
  SeverityFilterCombo.Items.AddObject(_('Missing Raise'),                TObject(Ord(fmMissingRaise)));
  SeverityFilterCombo.Items.AddObject(_('Result Unassigned'),            TObject(Ord(fmRoutineResultUnassigned)));
  SeverityFilterCombo.Items.AddObject(_('Re-Raise Exception'),           TObject(Ord(fmReRaiseException)));
  SeverityFilterCombo.Items.AddObject(_('Cast And Free'),                TObject(Ord(fmCastAndFree)));
  SeverityFilterCombo.Items.AddObject(_('Instance-Invoked Constructor'), TObject(Ord(fmInstanceInvokedConstructor)));
  SeverityFilterCombo.Items.AddObject(_('Inherited (empty)'),            TObject(Ord(fmInheritedMethodEmpty)));
  SeverityFilterCombo.Items.AddObject(_('Nil Comparison'),               TObject(Ord(fmNilComparison)));
  SeverityFilterCombo.Items.AddObject(_('Raising Raw Exception'),        TObject(Ord(fmRaisingRawException)));
  SeverityFilterCombo.Items.AddObject(_('Date Format Settings'),         TObject(Ord(fmDateFormatSettings)));
  SeverityFilterCombo.Items.AddObject(_('Unicode -> Ansi Cast'),         TObject(Ord(fmUnicodeToAnsiCast)));
  SeverityFilterCombo.Items.AddObject(_('Char -> PChar Cast'),           TObject(Ord(fmCharToCharPointerCast)));
  SeverityFilterCombo.Items.AddObject(_('IfThen Short-Circuit'),         TObject(Ord(fmIfThenShortCircuit)));
  // Sonar-50 Critical (SCA132-137)
  SeverityFilterCombo.Items.AddObject(_('Exception Too General'),        TObject(Ord(fmExceptionTooGeneral)));
  SeverityFilterCombo.Items.AddObject(_('Raise outside except'),         TObject(Ord(fmRaiseOutsideExcept)));
  SeverityFilterCombo.Items.AddObject(_('Use After Free'),               TObject(Ord(fmUseAfterFree)));
  SeverityFilterCombo.Items.AddObject(_('Abstract method not implemented'), TObject(Ord(fmAbstractNotImpl)));
  SeverityFilterCombo.Items.AddObject(_('Leak in constructor'),          TObject(Ord(fmLeakInConstructor)));
  SeverityFilterCombo.Items.AddObject(_('Integer overflow (Int64 mul)'), TObject(Ord(fmIntegerOverflow)));
  SeverityFilterCombo.Items.AddObject(_('God Class'),                    TObject(Ord(fmGodClass)));
  SeverityFilterCombo.Items.AddObject(_('Free without nil-out'),         TObject(Ord(fmFreeWithoutNil)));
  SeverityFilterCombo.Items.AddObject(_('Multiple Exit'),                TObject(Ord(fmMultipleExit)));
  SeverityFilterCombo.Items.AddObject(_('Large Class'),                  TObject(Ord(fmLargeClass)));
  SeverityFilterCombo.Items.AddObject(_('Unsorted uses clause'),         TObject(Ord(fmUnsortedUses)));
  SeverityFilterCombo.Items.AddObject(_('Missing unit header'),          TObject(Ord(fmMissingUnitHeader)));
  SeverityFilterCombo.Items.AddObject(_('Float equality'),               TObject(Ord(fmFloatEquality)));
  SeverityFilterCombo.Items.AddObject(_('Raise in destructor'),          TObject(Ord(fmExceptInDestructor)));
  SeverityFilterCombo.Items.AddObject(_('Boolean parameter as flag'),    TObject(Ord(fmBooleanParam)));
  SeverityFilterCombo.Items.AddObject(_('Unused private method'),        TObject(Ord(fmUnusedPrivateMethod)));
  SeverityFilterCombo.Items.AddObject(_('Could be class method'),        TObject(Ord(fmCanBeClassMethod)));
  SeverityFilterCombo.Items.AddObject(_('Missing override'),             TObject(Ord(fmMissingOverride)));
  SeverityFilterCombo.Items.AddObject(_('Boolean always true / false'),  TObject(Ord(fmBoolAlwaysTrue)));
  SeverityFilterCombo.Items.AddObject(_('Constant return value'),        TObject(Ord(fmConstantReturn)));
  SeverityFilterCombo.Items.AddObject(_('Hardcoded user string'),        TObject(Ord(fmHardcodedString)));
  // mORMot-Cluster (SCA153-155)
  SeverityFilterCombo.Items.AddObject(_('Unpaired Lock'),                TObject(Ord(fmUnpairedLock)));
  SeverityFilterCombo.Items.AddObject(_('Move/FillChar SizeOf(Pointer)'),TObject(Ord(fmMoveSizeOfPointer)));
  SeverityFilterCombo.Items.AddObject(_('with on multiple targets'),     TObject(Ord(fmWithMultipleTargets)));
  // mORMot-Cluster Phase 2 (SCA156-158)
  SeverityFilterCombo.Items.AddObject(_('GetMem without try/finally'),        TObject(Ord(fmGetMemWithoutFreeMem)));
  SeverityFilterCombo.Items.AddObject(_('SetLength grow in loop'),            TObject(Ord(fmSetLengthAppendInLoop)));
  SeverityFilterCombo.Items.AddObject(_('PChar arithmetic without empty-check'),  TObject(Ord(fmPointerArithmeticOnString)));
  // mORMot-Cluster Phase 3 (SCA159-161)
  SeverityFilterCombo.Items.AddObject(_('Empty typed exception handler'),     TObject(Ord(fmEmptyOnHandler)));
  SeverityFilterCombo.Items.AddObject(_('String cast from raw pointer'),      TObject(Ord(fmStringFromPointer)));
  SeverityFilterCombo.Items.AddObject(_('Pointer subtraction (Win64 truncation)'), TObject(Ord(fmPointerSubtraction)));
  // Audit-Nachzug (Todo_neuerdetector-Checkliste)
  SeverityFilterCombo.Items.AddObject(_('Command Injection'),            TObject(Ord(fmCommandInjection)));
  SeverityFilterCombo.Items.AddObject(_('Insecure Crypto Algo'),         TObject(Ord(fmInsecureCryptoAlgorithm)));
  SeverityFilterCombo.Items.AddObject(_('Unused Routine'),               TObject(Ord(fmUnusedRoutine)));
  SeverityFilterCombo.Items.AddObject(_('NOSONAR Marker (legacy)'),      TObject(Ord(fmNoSonarMarker)));
  SeverityFilterCombo.Items.AddObject(_('Unused noinspection Marker'),   TObject(Ord(fmUnusedSuppression)));
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
  FGridConfig := TFindingGridRenderer.StandaloneConfig;
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
begin
  Projectpath.Text := SelectFolder;
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
    Settings.ApplyDetectorThresholds(Trim(Projectpath.Text));
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
        findings := TStaticAnalyzer2.AnalyzeLeaksRecursive(path,
          procedure(C, T: Integer) begin ProgressCallback(C, T); end,
          Settings.UsesCheck);
        FillGridFromFindings(findings, path);
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
        findings := TStaticAnalyzer2.AnalyzeLeaks(AFilePath,
          Trim(Projectpath.Text), Settings.UsesCheck);
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
         or (TFindingFilter.CountForMode(FAllFindings,
                                         TFilterMode(Item.ModeOrd)) > 0) then
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
    if Tag >= 0 then Criteria.Mode := TFilterMode(Tag);
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

procedure TForm2.ResultGridDblClick(Sender: TObject);
// Bei .dfm-Befunden oeffnen wir den eingebauten DFM-Text-Viewer mit Goto-
// Zeile - kein externer ShellExecute, weil der Standard-Handler die DFM
// im Form-Designer aufmacht (Goto-Line funktioniert dort nicht).
// Bei .pas-Befunden weiter ShellExecute + Delphi-IDE-Sprung wie bisher.
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
begin
  row := ResultGrid.Row;
  if row < 1 then Exit;
  if (FDisplayedFindings = nil) or (row > FDisplayedFindings.Count) then Exit;
  f := FDisplayedFindings[row - 1];
  baseDir := IncludeTrailingPathDelimiter(FCurrentBaseDir);
  relPath := ExtractRelativePath(baseDir, f.FileName);
  if relPath = '' then Exit;
  lineNo := StrToIntDef(f.LineNumber, 0);
  absPath := IncludeTrailingPathDelimiter(Projectpath.Text) + relPath;
  if not FileExists(absPath) then
  begin
    StatusBar1.Panels[2].Text := _('File not found: ') + absPath;
    Exit;
  end;

  if EndsText('.dfm', absPath) then
  begin
    ShowDfmAsText(absPath, lineNo);
    StatusBar1.Panels[2].Text := Format(_('DFM viewer: %s  Line: %d'),
                                     [relPath, lineNo]);
    Exit;
  end;

  // ProcessMessages flushed Pending-Events (z.B. den Repaint nach Modal-
  // Close des DFM-Viewers). Ohne das Flush kann der direkt folgende
  // ShellExecute-Aufruf beim Delphi-IDE-DDE-Handler "verloren gehen" -
  // die IDE bekommt Focus, oeffnet die Datei aber nicht.
  Application.ProcessMessages;
  ShellExecute(Handle, 'open', PChar(absPath), nil, nil, SW_SHOWNORMAL);
  if lineNo > 0 then
  begin
    Sleep(1200); // Delphi IDE Zeit geben, die Datei zu oeffnen
    Application.ProcessMessages;
    NavigateDelphiToLine(lineNo);
  end;
  StatusBar1.Panels[2].Text := Format(_('Opened: %s  Line: %d'), [relPath, lineNo]);
end;

procedure TForm2.NavigateDelphiToLine(LineNo: Integer);
var
  BDSWnd: HWND;
  lineStr: string;
  i: Integer;
  inp: TInput;
  vk: Word;
begin
  // Belt-and-suspenders: ohne Ziel-Zeile wuerde ein Ctrl+G Dialog leer
  // bestaetigt und die IDE haengt mit einem offenen Dialog herum.
  if LineNo <= 0 then Exit;
  BDSWnd := FindWindow('TAppBuilder', nil);
  if BDSWnd = 0 then Exit;
  SetForegroundWindow(BDSWnd);
  Sleep(150);
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
  // Zeilennummer eintippen
  lineStr := IntToStr(LineNo);
  for i := 1 to Length(lineStr) do
  begin
    vk := VkKeyScan(lineStr[i]) and $FF;
    ZeroMemory(@inp, SizeOf(inp));
    inp.Itype := INPUT_KEYBOARD;
    inp.ki.wVk := vk;
    SendInput(1, inp, SizeOf(TInput));
    inp.ki.dwFlags := KEYEVENTF_KEYUP;
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

function TForm2.SelectFolder: string;
var
  OpenDialog: TFileOpenDialog;
begin
  Result := '';
  OpenDialog := TFileOpenDialog.Create(nil);
  try
    OpenDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    OpenDialog.Title := _('Choose folder');
    if OpenDialog.Execute then
      Result := OpenDialog.FileName;
  finally
    OpenDialog.Free;
  end;
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
begin
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
  StartDir := Trim(Projectpath.Text);
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
        Findings := TStaticAnalyzer2.AnalyzeLeaksFromList(Files,
          procedure(C, T: Integer) begin ProgressCallback(C, T); end,
          Settings.UsesCheck);
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

  MI := TMenuItem.Create(FHamburgerMenu);
  MI.Caption := '-';
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
