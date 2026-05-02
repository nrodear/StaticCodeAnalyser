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
  Vcl.Clipbrd,
  DesignIntf, ToolsAPI,
  uStaticAnalyzer2, uStaticFiles, uMethodd12, uSCAConsts, uExport,
  uFixHint, uIgnoreList, uVcsChanges, uRepoSettings;

type
  TFilterMode = (fmAll,
                 // Schweregrad-Gruppen
                 fmErrors, fmWarnings, fmHints,
                 // Fehler-Detektoren
                 fmSQLInjection, fmHardcodedSecret, fmFormatMismatch,
                 fmNilDeref, fmDivByZero,
                 // Warnungs-Detektoren
                 fmEmptyExcept, fmMissingFinally, fmDeadCode,
                 fmUnusedUses, fmDebugOutput, fmHardcodedPath,
                 fmFileReadError,
                 // Hinweis-Detektoren
                 fmLongMethod, fmLongParamList, fmMagicNumber,
                 fmDuplicateString, fmDeepNesting,
                 fmTodoComment, fmEmptyMethod, fmDuplicateBlock);

  // Zweiter Filter (orthogonal zu Schweregrad): Sonar-Typ-Kategorie
  TTypeFilter = (tfAll, tfBug, tfCodeSmell, tfVulnerability,
                 tfSecurityHotspot, tfCodeDuplication);

  TAnalyserFrame = class(TFrame)
  private
    FStatusBar      : TStatusBar;
    FAllFindings    : TObjectList<TLeakFinding>;
    FFilterMode     : TFilterMode;
    FCurrentBaseDir : string;
    FFilterCombo       : TComboBox;
    FHelpDescLabel     : TLabel;
    FHelpBeforePanel   : TPanel;
    FHelpBefore        : TMemo;
    FHelpAfter         : TMemo;
    FDisplayedFindings : TList<TLeakFinding>;

    FPanelStats        : TPanel;
    // Eine horizontale Tile-Reihe: 4 Severity-Tiles + 3 Type-Tiles + Score.
    // Layout pro Tile: Glyph-Icon links + Count rechts (Top-Row), Caption
    // unten zentriert. Glyphs aus Segoe Fluent Icons (vektor, kein SVG-Lib).
    // Code Smell und Hotspot werden NICHT angezeigt (zaehlen aber in den Score).
    FTileError, FTileWarn, FTileHint, FTileFileSev : TLabel; // Severity
    FTileBug, FTileVuln, FTileDup                  : TLabel; // Type
    FTileScore                                     : TLabel; // Codequalitaet
    // Export-Dropdown: ein Button "Export ▾" mit Popup statt 5 Einzel-Buttons.
    FExportMenu        : TPopupMenu;
    // ---- Zweiter Filter --------------------------------------------------
    FTypeFilter        : TTypeFilter;
    FTypeCombo         : TComboBox;

    FSearchEdit        : TEdit;
    FSortColumn        : Integer;     // -1 = unsortiert
    FSortDescending    : Boolean;
    FChkUsesCheck      : TCheckBox;
    FChkIncludeTests   : TCheckBox; // Default: aus (Tests werden ausgeschlossen)
    // ---- Analyse-Fortschritt --------------------------------------------
    FProgressBar       : TProgressBar; // sichtbar nur waehrend Analyse
    FBtnCancel         : TButton;      // sichtbar nur waehrend Analyse
    FBtnAnalyse        : TButton;      // gemerkt fuer Enable/Disable
    FBtnAnalyseCurrent : TButton;
    FBtnAnalyseChanged : TButton; // Branch-Aenderungen via Git/SVN
    FAnalyseRunning    : Boolean;
    FAnalyseCancelled  : Boolean;
    FLastProgressTick  : Cardinal;     // GetTickCount, drosselt UI-Updates
    // Ignore-Liste fuer Dateien, die NICHT analysiert werden sollen.
    // Wird beim Frame-Start aus %APPDATA%\StaticCodeAnalyser\ignore.txt geladen.
    FIgnoreList        : TIgnoreList;
    // Repo-/VCS-Settings (BaseBranch, IncludeWorkingTree, exe-Pfade).
    // Wird aus %APPDATA%\StaticCodeAnalyser\repo.ini geladen.
    FRepoSettings      : TRepoSettings;

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
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GridKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure GridResize(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure ExportCsvClick(Sender: TObject);
    procedure ExportJsonClick(Sender: TObject);
    procedure ExportJiraClick(Sender: TObject);
    procedure CopyClipboardClick(Sender: TObject);
    procedure ExportHtmlClick(Sender: TObject);
    // Klappt das PopupMenu unter dem Export-Button auf.
    procedure ExportMenuButtonClick(Sender: TObject);
    function  CurrentFocusFile: string;

    // Erstellt die Sonar-Style Tile-Reihe (alle 10 Tiles in einer Zeile).
    procedure BuildStatsTiles(Parent: TPanel);
    // Flache Kachel: Icon-Glyph (akzentfarbig) + Count rechts oben,
    // Caption unten zentriert. Hintergrund einheitlich (kein Box).
    function  MakeTile(Parent: TWinControl; const Caption, Glyph: string;
      IconColor: TColor; AWidth: Integer): TLabel;
    // Statusbar-Helpers (3 Panels: Befunde-Count, Datei-Progress, Mode)
    procedure StatusFindings(const T: string);
    procedure StatusProgress(const T: string);
    procedure StatusMode(const T: string);
    procedure TypeFilterChange(Sender: TObject);
    procedure CancelAnalyseClick(Sender: TObject);
    procedure SetAnalyseUiBusy(ABusy: Boolean; ATotal: Integer = 0);
    procedure EditIgnoreListClick(Sender: TObject);
    procedure EditRepoSettingsClick(Sender: TObject);
    procedure AnalyseAllClasses(const APath: string);
    procedure PopulateFindings(const findings: TObjectList<TLeakFinding>;
      const BaseDir: string);
    procedure UpdateStats;
    procedure ApplyFilter;
    // Erzeugt einen vollstaendigen Markdown-Prompt fuer Claude AI: Befund-
    // Metadaten, FixHint (Vorher/Nachher) und Code-Auszug aus der Quelldatei.
    function  BuildClaudePrompt(F: TLeakFinding): string;
    procedure CopyFindingToClipboard(F: TLeakFinding);
    procedure UpdateHelp(Row: Integer);
    class function FixHint(const Finding: TLeakFinding): TFixHint; static;
    procedure OpenFileAtLine(const AbsPath: string; LineNumber: Integer);
    procedure LoadRecentPaths;
    procedure SaveRecentPath(const APath: string);
  public
    FProjectPath : TComboBox;
    FResultGrid  : TStringGrid;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Resize; override;
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



const
  MAX_RECENT    = 3;
  COLOR_ERROR      = TColor($00C0C0FF); // Hellrot - Fehler
  COLOR_WARNING    = TColor($00C0FFFF); // Hellgelb - Warnung
  COLOR_HINT       = TColor($00E8F0E0); // Hellgruen - Hinweis (Code-Smell)
  COLOR_FILEERROR  = TColor($008080FF); // Orange - Lesefehler
  COLOR_UNUSEDUSES = TColor($00F0D8FF); // Lavendel - ungenutzte Uses
  COLOR_NILDEREF   = TColor($0080A0FF); // Hellrot-Orange - NilDeref
  COLOR_DIVZERO    = TColor($008080FF); // Orange - DivByZero (gleich FileError)
  COLOR_DEADCODE   = TColor($00E8E8E8); // Grau - toter Code

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

function GetCurrentIDEProjectDir: string;
var
  ProjGroup : IOTAProjectGroup;
begin
  Result := '';
  if not Assigned(BorlandIDEServices) then Exit;
  ProjGroup := (BorlandIDEServices as IOTAModuleServices).MainProjectGroup;
  if Assigned(ProjGroup) then
    Result := ExcludeTrailingPathDelimiter(
      ExtractFilePath(ProjGroup.FileName));
end;

{ TIDEAnalyserForm }

constructor TAnalyserFrame.Create(AOwner: TComponent);
var
  PanelPath, PanelButtons, PanelClient: TPanel;
  LblPath: TLabel;
  BtnBrowse, BtnAnalyse: TButton;
begin
  inherited Create(AOwner);
  Color         := clWhite;
  ParentFont    := False;
  Font.Name     := 'Segoe UI';
  Font.Size     := 6;
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
  FRepoSettings      := TRepoSettings.Create;
  try FRepoSettings.Load; except end;
  FFilterMode        := fmAll;
  // Default-Sort: Severity-Spalte (5) aufsteigend - Fehler oben, Hinweise unten.
  FSortColumn        := 5;
  FSortDescending    := False;

  // ---- Statusleiste mit 3 Panels ----
  // Panel 0 (links, fix):    Befund-Anzahl ("X / Y Befunde")
  // Panel 1 (mitte, fix):    Datei-Progress / aktuelle Datei
  // Panel 2 (rechts, fill):  VCS-Modus, Status-Meldungen, Fehlertexte
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent      := Self;
  FStatusBar.Align       := alBottom;
  FStatusBar.SimplePanel := False;

  with FStatusBar.Panels.Add do begin Width := 160; Text := ''; end;            // Findings
  with FStatusBar.Panels.Add do begin Width := 220; Text := ''; end;            // Progress
  // Letztes Panel - Width = Rest. TStatusBar streckt das letzte Panel
  // automatisch auf alle uebrige Breite wenn Width gross genug ist.
  with FStatusBar.Panels.Add do begin Width := 5000; Text := 'Bereit.'; end;

  // ---- Fortschrittsbalken (nur waehrend Analyse sichtbar) -----------------
  // Liegt zwischen Top-Panels und Statusbar - alBottom oberhalb der Statusbar.
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent  := Self;
  FProgressBar.Align   := alBottom;
  FProgressBar.Height  := 14;
  FProgressBar.Min     := 0;
  FProgressBar.Max     := 100;
  FProgressBar.Smooth  := True;
  FProgressBar.Visible := False;

  // ---- Zeile: Projektpfad ----
  PanelPath := TPanel.Create(Self);
  PanelPath.Parent      := Self;
  PanelPath.Align       := alTop;
  PanelPath.Height      := 22;
  PanelPath.BevelOuter  := bvNone;
  PanelPath.Color       := clWhite;
  PanelPath.Padding.SetBounds(6, 2, 6, 2);

  LblPath := TLabel.Create(Self);
  LblPath.Parent    := PanelPath;
  LblPath.Caption   := 'Projektpfad:';
  LblPath.Align     := alLeft;
  LblPath.Layout    := tlCenter;
  LblPath.Width     := 78;

  BtnBrowse := TButton.Create(Self);
  BtnBrowse.Parent  := PanelPath;
  BtnBrowse.Caption := '...';
  BtnBrowse.Width   := 28;
  BtnBrowse.Align   := alRight;
  BtnBrowse.OnClick := BrowseClick;

  // Ignore-Liste editieren - oeffnet ignore.txt im Notepad/Default-Editor
  var BtnIgnore := TButton.Create(Self);
  BtnIgnore.Parent  := PanelPath;
  BtnIgnore.Caption := 'Ignore...';
  BtnIgnore.Width   := 60;
  BtnIgnore.Align   := alRight;
  BtnIgnore.Hint    := 'Ignore-Liste oeffnen (welche Dateien NICHT analysiert werden)';
  BtnIgnore.ShowHint := True;
  BtnIgnore.OnClick := EditIgnoreListClick;

  // Repo-Settings (BaseBranch, Tortoise-Pfade etc. fuer Branch-Changes)
  var BtnRepo := TButton.Create(Self);
  BtnRepo.Parent  := PanelPath;
  BtnRepo.Caption := 'Repo...';
  BtnRepo.Width   := 60;
  BtnRepo.Align   := alRight;
  BtnRepo.Hint    := 'Repo-Settings oeffnen (BaseBranch, git/svn-Pfad fuer ' +
                     'den "Branch-Changes"-Button)';
  BtnRepo.ShowHint := True;
  BtnRepo.OnClick := EditRepoSettingsClick;

  FProjectPath := TComboBox.Create(Self);
  FProjectPath.Parent      := PanelPath;
  FProjectPath.Align       := alClient;
  FProjectPath.Style       := csDropDown;
  FProjectPath.ParentFont  := False;
  FProjectPath.Font.Name   := 'Segoe UI';
  FProjectPath.Font.Size   := 6;

  // ---- Zeile: Buttons ----
  PanelButtons := TPanel.Create(Self);
  PanelButtons.Parent      := Self;
  PanelButtons.Align       := alTop;
  PanelButtons.Height      := 22;
  PanelButtons.BevelOuter  := bvNone;
  PanelButtons.Color       := clWhite;
  PanelButtons.Padding.SetBounds(6, 2, 6, 2);

  // Aktions-Buttons (Analyse starten / Aktuelle Datei) liegen nicht hier,
  // sondern in PanelSearch zusammen mit den Export-Buttons. Damit bleibt
  // diese Filter-Zeile uebersichtlich.

  // Filter-Label
  var LblFilter := TLabel.Create(Self);
  LblFilter.Parent  := PanelButtons;
  LblFilter.Caption := 'Schweregrad:';
  LblFilter.Align   := alLeft;
  LblFilter.Layout  := tlCenter;
  LblFilter.Width   := 76;

  // Filter-Dropdown - nach Schweregrad gruppiert.
  // Items.Objects haelt den Ord(TFilterMode) als Tag; Separatoren haben Tag = -1
  // und werden in FilterChange auf "Alle" zurueckgesetzt.
  FFilterCombo := TComboBox.Create(Self);
  FFilterCombo.Parent      := PanelButtons;
  FFilterCombo.Style       := csDropDownList;
  FFilterCombo.Align       := alLeft;
  FFilterCombo.Width       := 160;
  FFilterCombo.Font.Name   := 'Segoe UI';
  FFilterCombo.Font.Size   := 6;
  FFilterCombo.ParentFont  := False;
  FFilterCombo.OnChange    := FilterChange;

  // Hilfsmethode-Inline ueber Lambdas geht in Delphi nicht - direkt schreiben.
  FFilterCombo.Items.AddObject('Alle',                  TObject(Ord(fmAll)));
  FFilterCombo.Items.AddObject('Fehler (alle)',         TObject(Ord(fmErrors)));
  FFilterCombo.Items.AddObject('Warnungen (alle)',      TObject(Ord(fmWarnings)));
  FFilterCombo.Items.AddObject('Hinweise (alle)',       TObject(Ord(fmHints)));

  FFilterCombo.Items.AddObject('--- Fehler ---',        TObject(-1));
  FFilterCombo.Items.AddObject('SQL Injection',         TObject(Ord(fmSQLInjection)));
  FFilterCombo.Items.AddObject('Hardcoded Secrets',     TObject(Ord(fmHardcodedSecret)));
  FFilterCombo.Items.AddObject('Format()',              TObject(Ord(fmFormatMismatch)));
  FFilterCombo.Items.AddObject('Nil-Deref',             TObject(Ord(fmNilDeref)));
  FFilterCombo.Items.AddObject('Div by Zero',           TObject(Ord(fmDivByZero)));

  FFilterCombo.Items.AddObject('--- Warnungen ---',     TObject(-1));
  FFilterCombo.Items.AddObject('Leere Exceptions',      TObject(Ord(fmEmptyExcept)));
  FFilterCombo.Items.AddObject('Missing Finally',       TObject(Ord(fmMissingFinally)));
  FFilterCombo.Items.AddObject('Toter Code',            TObject(Ord(fmDeadCode)));
  FFilterCombo.Items.AddObject('Ungenutzte Uses',       TObject(Ord(fmUnusedUses)));
  FFilterCombo.Items.AddObject('Debug-Ausgabe',         TObject(Ord(fmDebugOutput)));
  FFilterCombo.Items.AddObject('Hardkodierter Pfad',    TObject(Ord(fmHardcodedPath)));
  FFilterCombo.Items.AddObject('Lesefehler',            TObject(Ord(fmFileReadError)));

  FFilterCombo.Items.AddObject('--- Hinweise ---',      TObject(-1));
  FFilterCombo.Items.AddObject('Lange Methode',         TObject(Ord(fmLongMethod)));
  FFilterCombo.Items.AddObject('Viele Parameter',       TObject(Ord(fmLongParamList)));
  FFilterCombo.Items.AddObject('Magic Number',          TObject(Ord(fmMagicNumber)));
  FFilterCombo.Items.AddObject('Doppelte Strings',      TObject(Ord(fmDuplicateString)));
  FFilterCombo.Items.AddObject('Doppelte Code-Bloecke', TObject(Ord(fmDuplicateBlock)));
  FFilterCombo.Items.AddObject('Tiefe Verschachtelung', TObject(Ord(fmDeepNesting)));
  FFilterCombo.Items.AddObject('TODO/FIXME',            TObject(Ord(fmTodoComment)));
  FFilterCombo.Items.AddObject('Leere Methoden',        TObject(Ord(fmEmptyMethod)));

  FFilterCombo.ItemIndex := 0; // "Alle"

  // Trennabstand
  var SepF1 := TPanel.Create(Self);
  SepF1.Parent     := PanelButtons;
  SepF1.Align      := alLeft;
  SepF1.Width      := 8;
  SepF1.BevelOuter := bvNone;
  SepF1.Color      := clWhite;

  // ---- Zweiter Filter: Typ (Sonar-Kategorie) ----
  var LblType := TLabel.Create(Self);
  LblType.Parent  := PanelButtons;
  LblType.Caption := 'Typ:';
  LblType.Align   := alLeft;
  LblType.Layout  := tlCenter;
  LblType.Width   := 28;

  FTypeCombo := TComboBox.Create(Self);
  FTypeCombo.Parent      := PanelButtons;
  FTypeCombo.Style       := csDropDownList;
  FTypeCombo.Align       := alLeft;
  FTypeCombo.Width       := 130;
  FTypeCombo.Font.Name   := 'Segoe UI';
  FTypeCombo.Font.Size   := 6;
  FTypeCombo.ParentFont  := False;
  FTypeCombo.OnChange    := TypeFilterChange;
  FTypeCombo.Items.Add('Alle');
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
  Sep2.Width      := 8;
  Sep2.BevelOuter := bvNone;
  Sep2.Color      := clWhite;

  // Checkbox: Uses-Check optional aktivieren (default: aus)
  FChkUsesCheck := TCheckBox.Create(Self);
  FChkUsesCheck.Parent      := PanelButtons;
  FChkUsesCheck.Caption     := 'mit uses check';
  FChkUsesCheck.Width       := 110;
  FChkUsesCheck.Align       := alLeft;
  FChkUsesCheck.Checked     := False;
  FChkUsesCheck.ParentFont  := False;
  FChkUsesCheck.Font.Name   := 'Segoe UI';
  FChkUsesCheck.Font.Size   := 6;
  FChkUsesCheck.Hint        := 'Aktiviert die Pruefung auf ungenutzte uses-Eintraege ' +
                               '(kann false positives produzieren)';
  FChkUsesCheck.ShowHint    := True;

  // Checkbox: Tests einbeziehen (default: aus - Tests werden ausgeschlossen)
  FChkIncludeTests := TCheckBox.Create(Self);
  FChkIncludeTests.Parent      := PanelButtons;
  FChkIncludeTests.Caption     := 'Tests einschliessen';
  FChkIncludeTests.Width       := 130;
  FChkIncludeTests.Align       := alLeft;
  FChkIncludeTests.Checked     := False;
  FChkIncludeTests.ParentFont  := False;
  FChkIncludeTests.Font.Name   := 'Segoe UI';
  FChkIncludeTests.Font.Size   := 6;
  FChkIncludeTests.Hint        :=
    'Wenn aktiviert: DUnit/DUnitX-Tests (uTest*.pas, *_Tests.pas, ' +
    'TestProject*.dpr, /tests/-Verzeichnisse) werden mit-analysiert. ' +
    'Default aus - Tests sind selten "schlechter Code", produzieren aber ' +
    'oft Befunde (LongMethod, MagicNumber).';
  FChkIncludeTests.ShowHint    := True;

  // ---- Zeile: Aktionen + Suche + Export ----
  var PanelSearch := TPanel.Create(Self);
  PanelSearch.Parent      := Self;
  PanelSearch.Align       := alTop;
  PanelSearch.Height      := 22;
  PanelSearch.BevelOuter  := bvNone;
  PanelSearch.Color       := clWhite;
  PanelSearch.Padding.SetBounds(6, 2, 6, 2);

  // Action-Buttons links - "Analyse starten" zuerst (links), dann "Aktuelle Datei"
  BtnAnalyse := TButton.Create(Self);
  BtnAnalyse.Parent   := PanelSearch;
  BtnAnalyse.Caption  := 'Analyse starten';
  BtnAnalyse.Width    := 100;
  BtnAnalyse.Align    := alLeft;
  BtnAnalyse.OnClick  := AnalyseClick;
  FBtnAnalyse := BtnAnalyse;

  FBtnAnalyseCurrent := TButton.Create(Self);
  FBtnAnalyseCurrent.Parent   := PanelSearch;
  FBtnAnalyseCurrent.Caption  := 'Aktuelle Datei';
  FBtnAnalyseCurrent.Width    := 90;
  FBtnAnalyseCurrent.Align    := alLeft;
  FBtnAnalyseCurrent.OnClick  := AnalyseCurrentFileClick;

  // Branch-Aenderungen via Git/SVN: nur die im Branch geaenderten .pas-Files
  FBtnAnalyseChanged := TButton.Create(Self);
  FBtnAnalyseChanged.Parent   := PanelSearch;
  FBtnAnalyseChanged.Caption  := 'Branch-Changes';
  FBtnAnalyseChanged.Width    := 120;
  FBtnAnalyseChanged.Align    := alLeft;
  FBtnAnalyseChanged.OnClick  := AnalyseChangedFilesClick;
  FBtnAnalyseChanged.Hint     :=
    'Analysiert nur Dateien die im aktuellen Branch geaendert wurden ' +
    '(Git: Branch-Diff vs main + Working Tree; SVN: Working Copy)';
  FBtnAnalyseChanged.ShowHint := True;

  // Cancel-Button - waehrend der Analyse sichtbar, sonst ausgeblendet
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent   := PanelSearch;
  FBtnCancel.Caption  := 'Abbrechen';
  FBtnCancel.Width    := 80;
  FBtnCancel.Align    := alLeft;
  FBtnCancel.Visible  := False;
  FBtnCancel.OnClick  := CancelAnalyseClick;

  // Trennabstand
  var SepActions := TPanel.Create(Self);
  SepActions.Parent     := PanelSearch;
  SepActions.Align      := alLeft;
  SepActions.Width      := 8;
  SepActions.BevelOuter := bvNone;
  SepActions.Color      := clWhite;

  var LblSearch := TLabel.Create(Self);
  LblSearch.Parent  := PanelSearch;
  LblSearch.Caption := 'Suche:';
  LblSearch.Align   := alLeft;
  LblSearch.Layout  := tlCenter;
  LblSearch.Width   := 32;

  // Export-Buttons rechts (alRight: zuletzt erstelltes Element ist am
  // weitesten links - daher die optisch gewuenschte Reihenfolge umgekehrt
  // erstellen).
  // ---- Export-Dropdown statt 5 Einzel-Buttons ----------------------------
  // Spart ~250 px Toolbar-Platz. Klick zeigt PopupMenu mit allen Varianten.
  FExportMenu := TPopupMenu.Create(Self);
  var Mi: TMenuItem;
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := 'HTML-Report (alle Befunde)...'; Mi.OnClick := ExportHtmlClick;     FExportMenu.Items.Add(Mi);
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := 'JSON...';                       Mi.OnClick := ExportJsonClick;     FExportMenu.Items.Add(Mi);
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := 'CSV...';                        Mi.OnClick := ExportCsvClick;      FExportMenu.Items.Add(Mi);
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := '-';                                                                  FExportMenu.Items.Add(Mi);
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := 'Jira-Markup -> Clipboard';      Mi.OnClick := ExportJiraClick;     FExportMenu.Items.Add(Mi);
  Mi := TMenuItem.Create(FExportMenu); Mi.Caption := 'Plain-Text -> Clipboard';       Mi.OnClick := CopyClipboardClick;  FExportMenu.Items.Add(Mi);

  var BtnExport := TButton.Create(Self);
  BtnExport.Parent     := PanelSearch;
  BtnExport.Caption    := 'Export ' + #$25BC; // schwarzes Dreieck nach unten
  BtnExport.Width      := 80;
  BtnExport.Align      := alRight;
  BtnExport.PopupMenu  := FExportMenu;
  BtnExport.OnClick    := ExportMenuButtonClick;
  BtnExport.Hint       := 'Export: HTML, JSON, CSV, Jira-Markup, Plain-Text';
  BtnExport.ShowHint   := True;

  // Sucheingabe fuellt den Rest in der Mitte
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent      := PanelSearch;
  FSearchEdit.Align       := alClient;
  FSearchEdit.TextHint    := 'Datei / Methode / Befund filtern...';
  FSearchEdit.OnChange    := SearchChange;
  FSearchEdit.ParentFont  := False;
  FSearchEdit.Font.Name   := 'Segoe UI';
  FSearchEdit.Font.Size   := 6;

  // ---- Statistik-Leiste: eine Reihe Sonar-Style Tiles (dunkler Hintergrund) ---
  FPanelStats := TPanel.Create(Self);
  FPanelStats.Parent      := Self;
  FPanelStats.Align       := alTop;
  FPanelStats.Height      := 45; // 1 Tile-Reihe ~25% kleiner: TopRow 20 + Caption ~12 + Padding
  FPanelStats.BevelOuter  := bvNone;
  FPanelStats.Color       := TColor($00282828); // Dunkles Anthrazit (BGR)
  FPanelStats.ParentBackground := False;
  FPanelStats.Padding.SetBounds(4, 4, 4, 4);

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

  // Hilfe-Panel rechts neben dem Grid (alRight innerhalb PanelClient).
  // Splitter-bedienbar - User kann Breite per Drag anpassen.
  var HelpPanel := TPanel.Create(Self);
  HelpPanel.Parent              := PanelClient;
  HelpPanel.Align               := alRight;
  HelpPanel.Width               := 360;
  HelpPanel.Constraints.MinWidth := 220; // sonst werden Code-Memos zu schmal
  HelpPanel.BevelOuter          := bvNone;
  HelpPanel.Color               := $00F4F4F4;

  // 1px linke Trennlinie - optisches Limit zwischen Grid und Help-Panel.
  var HelpLeftSep := TPanel.Create(Self);
  HelpLeftSep.Parent     := HelpPanel;
  HelpLeftSep.Align      := alLeft;
  HelpLeftSep.Width      := 1;
  HelpLeftSep.BevelOuter := bvNone;
  HelpLeftSep.Color      := $00BBBBBB;

  FHelpDescLabel := TLabel.Create(Self);
  FHelpDescLabel.Parent      := HelpPanel;
  FHelpDescLabel.Align       := alTop;
  FHelpDescLabel.Height      := 16;
  FHelpDescLabel.Layout      := tlCenter;
  FHelpDescLabel.Font.Name   := 'Segoe UI';
  FHelpDescLabel.Font.Size   := 7;
  FHelpDescLabel.Font.Style  := [fsBold];
  FHelpDescLabel.Font.Color  := $00303030;
  FHelpDescLabel.Color       := $00E8E8E8;
  FHelpDescLabel.ParentColor := False;
  FHelpDescLabel.Caption     := '  Zeile auswaehlen fuer Loesungshinweis';

  var HelpCode := TPanel.Create(Self);
  HelpCode.Parent      := HelpPanel;
  HelpCode.Align       := alClient;
  HelpCode.BevelOuter  := bvNone;
  HelpCode.Color       := $00F4F4F4;

  // Vorher/Nachher vertikal gestapelt (vorher: nebeneinander).
  // Bei einem rechts-angedockten Help-Panel passt die Hoehe besser zu den
  // typischen Code-Snippet-Laengen als die Breite.
  FHelpBeforePanel := TPanel.Create(Self);
  FHelpBeforePanel.Parent      := HelpCode;
  FHelpBeforePanel.Align       := alTop;
  FHelpBeforePanel.Height      := 150;
  FHelpBeforePanel.BevelOuter  := bvNone;
  FHelpBeforePanel.Color       := $00F0E8E8;

  var LblBefore := TLabel.Create(Self);
  LblBefore.Parent      := FHelpBeforePanel;
  LblBefore.Align       := alTop;
  LblBefore.Height      := 14;
  LblBefore.Layout      := tlCenter;
  LblBefore.Caption     := '  Vorher (Problem)';
  LblBefore.Font.Name   := 'Segoe UI';
  LblBefore.Font.Size   := 6;
  LblBefore.Font.Style  := [fsBold];
  LblBefore.Font.Color  := $00000080;
  LblBefore.Color       := $00DCC8C8;
  LblBefore.ParentColor := False;

  FHelpBefore := TMemo.Create(Self);
  FHelpBefore.Parent      := FHelpBeforePanel;
  FHelpBefore.Align       := alClient;
  FHelpBefore.ReadOnly    := True;
  FHelpBefore.BorderStyle := bsNone;
  FHelpBefore.ScrollBars  := ssBoth;
  FHelpBefore.Color       := $00F0E8E8;
  FHelpBefore.Font.Name   := 'Consolas';
  FHelpBefore.Font.Size   := 6;
  FHelpBefore.Font.Color  := $00400000;

  // Splitter zwischen Vorher und Nachher (drag um die Verhaeltnisse anzupassen)
  var BeforeAfterSplitter := TSplitter.Create(Self);
  BeforeAfterSplitter.Parent      := HelpCode;
  BeforeAfterSplitter.Align       := alTop;
  BeforeAfterSplitter.Height      := 4;
  BeforeAfterSplitter.Color       := $00BBBBBB;
  BeforeAfterSplitter.ResizeStyle := rsUpdate;

  var HelpAfterPanel := TPanel.Create(Self);
  HelpAfterPanel.Parent      := HelpCode;
  HelpAfterPanel.Align       := alClient;
  HelpAfterPanel.BevelOuter  := bvNone;
  HelpAfterPanel.Color       := $00E8F0E8;

  var LblAfter := TLabel.Create(Self);
  LblAfter.Parent      := HelpAfterPanel;
  LblAfter.Align       := alTop;
  LblAfter.Height      := 14;
  LblAfter.Layout      := tlCenter;
  LblAfter.Caption     := '  Nachher (Loesung)';
  LblAfter.Font.Name   := 'Segoe UI';
  LblAfter.Font.Size   := 6;
  LblAfter.Font.Style  := [fsBold];
  LblAfter.Font.Color  := $00006000;
  LblAfter.Color       := $00C8DCC8;
  LblAfter.ParentColor := False;

  FHelpAfter := TMemo.Create(Self);
  FHelpAfter.Parent      := HelpAfterPanel;
  FHelpAfter.Align       := alClient;
  FHelpAfter.ReadOnly    := True;
  FHelpAfter.BorderStyle := bsNone;
  FHelpAfter.ScrollBars  := ssBoth;
  FHelpAfter.Color       := $00E8F0E8;
  FHelpAfter.Font.Name   := 'Consolas';
  FHelpAfter.Font.Size   := 6;
  FHelpAfter.Font.Color  := $00004000;

  // Splitter zwischen Grid (links) und Help-Panel (rechts) - User kann
  // die Help-Panel-Breite per Drag anpassen.
  var HelpSplitter := TSplitter.Create(Self);
  HelpSplitter.Parent     := PanelClient;
  HelpSplitter.Align      := alRight;
  HelpSplitter.Width      := 4;
  HelpSplitter.Color      := $00BBBBBB;
  HelpSplitter.ResizeStyle := rsUpdate;

  FResultGrid := TStringGrid.Create(Self);
  FResultGrid.Parent           := PanelClient;
  FResultGrid.Align            := alClient;
  // MinWidth=300 verhindert dass der Help-Splitter den Grid-Bereich
  // praktisch auf Null zieht. MinHeight=120 weiterhin gegen Mini-Hoehe.
  FResultGrid.Constraints.MinHeight := 120;
  FResultGrid.Constraints.MinWidth  := 300;
  FResultGrid.FixedCols        := 0;
  FResultGrid.ColCount         := 6;
  FResultGrid.RowCount         := 2;
  FResultGrid.DefaultColWidth  := 100;
  FResultGrid.DefaultRowHeight := 20;
  FResultGrid.FixedRows        := 1;
  FResultGrid.ParentFont       := False;
  FResultGrid.Font.Name        := 'Segoe UI';
  FResultGrid.Font.Size        := 8;
  FResultGrid.GridLineWidth    := 1;
  FResultGrid.Options          := [goFixedVertLine, goFixedHorzLine,
                                   goVertLine, goHorzLine,
                                   goColSizing, goRowSelect, goThumbTracking];
  // Spaltenbreiten fuer 600px: 130+85+38+90+Scrollbar(17) = 360px fest
  // -> Befund-Spalte fuellt ~240px
  FResultGrid.ColWidths[0] := 130;  // Datei
  FResultGrid.ColWidths[1] :=  85;  // Methode
  FResultGrid.ColWidths[2] :=  38;  // Zeile
  FResultGrid.ColWidths[3] := 110;  // Typ (fix)
  FResultGrid.ColWidths[4] := 240;  // Regel/Befund (fuellt Rest per GridResize)
  FResultGrid.ColWidths[5] :=  90;  // Schweregrad (fix)
  FResultGrid.Cells[0, 0] := 'Datei';
  FResultGrid.Cells[1, 0] := 'Methode';
  FResultGrid.Cells[2, 0] := 'Zeile';
  FResultGrid.Cells[3, 0] := 'Typ';
  FResultGrid.Cells[4, 0] := 'Regel';
  FResultGrid.Cells[5, 0] := 'Schweregrad';
  FResultGrid.OnDrawCell   := GridDrawCell;
  FResultGrid.OnDblClick    := GridDblClick;
  FResultGrid.OnSelectCell  := GridSelectCell;
  FResultGrid.OnMouseMove   := GridMouseMove;
  FResultGrid.OnMouseDown   := GridMouseDown;
  FResultGrid.OnKeyDown     := GridKeyDown;
  FResultGrid.ShowHint     := True;
  FResultGrid.Hint         := '';

  LoadRecentPaths;
end;

destructor TAnalyserFrame.Destroy;
begin
  FreeAndNil(FAllFindings);
  FreeAndNil(FDisplayedFindings);
  FreeAndNil(FIgnoreList);
  FreeAndNil(FRepoSettings);
  inherited;
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

type
  // Lokale TPanel-Subklasse fuer Tiles mit duennem benutzerdefinierten
  // Rahmen. TPanel.BorderStyle=bsSingle waere 2px schwarz - wir wollen
  // einen 1px-Rahmen in einer dezenten Akzentfarbe, sichtbar auf dem
  // dunklen Stats-Hintergrund.
  TTilePanel = class(TPanel)
  private
    FBorderColor: TColor;
  protected
    procedure Paint; override;
  public
    property BorderColor: TColor read FBorderColor write FBorderColor;
  end;

procedure TTilePanel.Paint;
begin
  inherited; // zeichnet Hintergrund (Color) und Bevel
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color   := FBorderColor;
  Canvas.Pen.Width   := 1;
  Canvas.Rectangle(ClientRect);
end;

function TAnalyserFrame.MakeTile(Parent: TWinControl; const Caption, Glyph: string;
  IconColor: TColor; AWidth: Integer): TLabel;
const
  CL_FG_TXT     = TColor($00E8E8E8); // Off-white fuer Count
  CL_FG_DIM     = TColor($00B0B0B0); // Dimmer Caption
  CL_TILE_BG    = TColor($00282828); // Tile-Hintergrund (= Stats-Panel)
  CL_BORDER     = TColor($00505050); // Duenner Rahmen (etwas heller als BG)
var
  Tile     : TTilePanel;
  TopRow   : TPanel;
  IconLbl  : TLabel;
  CountLbl : TLabel;
  CapLbl   : TLabel;
begin
  Tile := TTilePanel.Create(Self);
  Tile.Parent      := Parent;
  Tile.Align       := alLeft;
  Tile.Width       := AWidth;
  Tile.AlignWithMargins := True;
  Tile.Margins.SetBounds(0, 0, 3, 0);
  Tile.BevelOuter  := bvNone;
  Tile.BorderStyle := bsNone;
  Tile.ParentBackground := False;
  Tile.Color       := CL_TILE_BG;
  Tile.BorderColor := CL_BORDER;
  Tile.ShowHint    := True;
  Tile.Hint        := Caption;

  // Top-Row: Icon links + Zahl direkt daneben
  TopRow := TPanel.Create(Self);
  TopRow.Parent      := Tile;
  TopRow.Align       := alTop;
  TopRow.AlignWithMargins := True;
  TopRow.Margins.SetBounds(1, 1, 1, 0); // 1px Abstand zum Tile-Rahmen
  TopRow.Height      := 20;
  TopRow.BevelOuter  := bvNone;
  TopRow.ParentBackground := False;
  TopRow.Color       := CL_TILE_BG;

  IconLbl := TLabel.Create(Self);
  IconLbl.Parent      := TopRow;
  IconLbl.Align       := alLeft;
  IconLbl.Width       := 20;
  IconLbl.Caption     := Glyph;
  IconLbl.Alignment   := taCenter;
  IconLbl.Layout      := tlCenter;
  IconLbl.Transparent := True;
  IconLbl.Font.Name   := 'Segoe Fluent Icons';
  IconLbl.Font.Size   := 11;
  IconLbl.Font.Color  := IconColor;

  CountLbl := TLabel.Create(Self);
  CountLbl.Parent      := TopRow;
  CountLbl.Align       := alClient;
  CountLbl.Caption     := '0';
  CountLbl.Alignment   := taLeftJustify;
  CountLbl.Layout      := tlCenter;
  CountLbl.Transparent := True;
  CountLbl.Font.Name   := 'Segoe UI';
  CountLbl.Font.Size   := 11;
  CountLbl.Font.Style  := [fsBold];
  CountLbl.Font.Color  := CL_FG_TXT;

  // Caption unten, ueber volle Tile-Breite zentriert.
  // AlignWithMargins/Margins(1,0,1,1) damit der Tile-Rahmen sichtbar bleibt.
  CapLbl := TLabel.Create(Self);
  CapLbl.Parent      := Tile;
  CapLbl.Align       := alClient;
  CapLbl.AlignWithMargins := True;
  CapLbl.Margins.SetBounds(1, 0, 1, 1);
  CapLbl.Caption     := Caption;
  CapLbl.Alignment   := taCenter;
  CapLbl.Layout      := tlTop;
  CapLbl.Transparent := True;
  CapLbl.Font.Name   := 'Segoe UI';
  CapLbl.Font.Size   := 6;
  CapLbl.Font.Color  := CL_FG_DIM;

  Result := CountLbl;
end;

procedure TAnalyserFrame.BuildStatsTiles(Parent: TPanel);
const
  // Akzentfarben fuer Glyph-Icons (BGR-Hex). Inspiriert vom Screenshot:
  // jedes Icon eine eigene farbliche Identitaet, Zahl/Text einheitlich hell.
  ICON_ERROR    = TColor($002030E0); // Rot-Orange
  ICON_WARN     = TColor($002090F0); // Orange
  ICON_INFO     = TColor($00F09020); // Hellblau
  ICON_FILEERR  = TColor($00A0A0A0); // Hellgrau
  ICON_SMELL    = TColor($00B040A0); // Magenta (Komplexitaet)
  ICON_BUG      = TColor($002030E0); // Rot
  ICON_VULN     = TColor($0080C040); // Gruen (Sicherheit)
  ICON_HOT      = TColor($0040D0E0); // Gelb (Performance)
  ICON_DUP      = TColor($00F0A040); // Cyan-Blau
  ICON_SCORE    = TColor($002080F0); // Orange (Codequalitaet/Flamme)

  // Segoe Fluent Icons / Segoe MDL2 Assets Codepoints (vektor).
  GLYPH_ERROR    = #$E783; // ErrorBadge (i im Kreis hier wirkt wie Stop)
  GLYPH_WARN     = #$E7BA; // Warning (Dreieck mit !)
  GLYPH_INFO     = #$E946; // Info (i im Kreis)
  GLYPH_FILEERR  = #$E711; // Cancel (X) - "Ausnahmen"
  GLYPH_SMELL    = #$E950; // CommandPrompt - "Komplexitaet" (geschweifte Klammern)
  GLYPH_BUG      = #$EBE8; // Bug
  GLYPH_VULN     = #$E72E; // Lock - "Sicherheit"
  GLYPH_HOT      = #$E945; // Lightning - "Performance"
  GLYPH_DUP      = #$E8C8; // Copy - "Duplikate"
  GLYPH_SCORE    = #$EB91; // Flame - "Codequalitaet"

  TILE_W       = 65;
  TILE_W_SCORE = 72; // letzter Tile etwas breiter (laengeres Wort)
begin
  // Container leeren falls bereits aufgebaut.
  while Parent.ControlCount > 0 do
    Parent.Controls[0].Free;

  // Reihenfolge: alLeft = das zuerst erstellte landet ganz links.
  // Captions matchen unser echtes Datenmodell (TFindingType, TLeakSeverity).
  // Code Smell und Hotspot bewusst weggelassen - die zaehlen weiterhin in den
  // Quality-Score (siehe UpdateStats), bekommen aber keine eigene Kachel.
  // Umlaute via Codepoint, da .pas-Datei kein UTF-8-BOM hat (#$00E4 = ae).
  FTileError    := MakeTile(Parent, 'Fehler',                       GLYPH_ERROR,   ICON_ERROR,   TILE_W);
  FTileWarn     := MakeTile(Parent, 'Warnungen',                    GLYPH_WARN,    ICON_WARN,    TILE_W);
  FTileHint     := MakeTile(Parent, 'Hinweise',                     GLYPH_INFO,    ICON_INFO,    TILE_W);
  FTileFileSev  := MakeTile(Parent, 'Lesefehler',                   GLYPH_FILEERR, ICON_FILEERR, TILE_W);
  FTileBug      := MakeTile(Parent, 'Bugs',                         GLYPH_BUG,     ICON_BUG,     TILE_W);
  FTileVuln     := MakeTile(Parent, 'Sicherheit',                   GLYPH_VULN,    ICON_VULN,    TILE_W);
  FTileDup      := MakeTile(Parent, 'Duplikate',                    GLYPH_DUP,     ICON_DUP,     TILE_W);
  FTileScore    := MakeTile(Parent, 'Codequalit'#$00E4't',          GLYPH_SCORE,   ICON_SCORE,   TILE_W_SCORE);
end;

procedure TAnalyserFrame.StatusFindings(const T: string);
begin
  if Assigned(FStatusBar) and (FStatusBar.Panels.Count > 0) then
    FStatusBar.Panels[0].Text := T;
end;

procedure TAnalyserFrame.StatusProgress(const T: string);
begin
  if Assigned(FStatusBar) and (FStatusBar.Panels.Count > 1) then
    FStatusBar.Panels[1].Text := T;
end;

procedure TAnalyserFrame.StatusMode(const T: string);
begin
  if Assigned(FStatusBar) and (FStatusBar.Panels.Count > 2) then
    FStatusBar.Panels[2].Text := T;
end;


// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.FilterChange(Sender: TObject);
var
  idx, tag: Integer;
begin
  idx := FFilterCombo.ItemIndex;
  if idx < 0 then Exit;
  tag := Integer(FFilterCombo.Items.Objects[idx]);
  if tag < 0 then
  begin
    // Separator-Eintrag - keine Filter-Aktion, Auswahl auf "Alle" zuruecksetzen.
    FFilterCombo.ItemIndex := 0;
    FFilterMode := fmAll;
  end
  else
    FFilterMode := TFilterMode(tag);
  ApplyFilter;
end;

procedure TAnalyserFrame.TypeFilterChange(Sender: TObject);
begin
  if FTypeCombo.ItemIndex < 0 then Exit;
  FTypeFilter := TTypeFilter(FTypeCombo.ItemIndex);
  ApplyFilter;
end;

procedure TAnalyserFrame.ApplyFilter;

  function DisplayName(const FullPath: string): string;
  begin
    // Im Grid steht nur der Dateiname - der volle Pfad kommt als Tooltip
    // ueber den GridMouseMove-Handler aus FDisplayedFindings.
    Result := ExtractFileName(FullPath);
  end;

var
  f           : TLeakFinding;
  i, row      : Integer;
  keep        : Boolean;
  severityTxt : string;
  searchLow   : string;
  fileNameLow : string;
begin
  searchLow := Trim(FSearchEdit.Text).ToLower;

  SendMessage(FResultGrid.Handle, WM_SETREDRAW, 0, 0);
  try
    FDisplayedFindings.Clear;

    // ---- Filter ----
    for i := 0 to FAllFindings.Count - 1 do
    begin
      f           := FAllFindings[i];
      severityTxt := f.SeverityText;
      case FFilterMode of
        fmErrors:          keep := severityTxt = 'Fehler';
        fmWarnings:        keep := severityTxt = 'Warnung';
        fmHints:           keep := severityTxt = 'Hinweis';
        fmEmptyExcept:     keep := f.Kind = fkEmptyExcept;
        fmSQLInjection:    keep := f.Kind = fkSQLInjection;
        fmHardcodedSecret: keep := f.Kind = fkHardcodedSecret;
        fmFormatMismatch:  keep := f.Kind = fkFormatMismatch;
        fmFileReadError:   keep := f.Kind = fkFileReadError;
        fmUnusedUses:      keep := f.Kind = fkUnusedUses;
        fmNilDeref:        keep := f.Kind = fkNilDeref;
        fmMissingFinally:  keep := f.Kind = fkMissingFinally;
        fmDivByZero:       keep := f.Kind = fkDivByZero;
        fmDeadCode:        keep := f.Kind = fkDeadCode;
        fmLongMethod:      keep := f.Kind = fkLongMethod;
        fmLongParamList:   keep := f.Kind = fkLongParamList;
        fmMagicNumber:     keep := f.Kind = fkMagicNumber;
        fmDuplicateString: keep := f.Kind = fkDuplicateString;
        fmDuplicateBlock:  keep := f.Kind = fkDuplicateBlock;
        fmHardcodedPath:   keep := f.Kind = fkHardcodedPath;
        fmDebugOutput:     keep := f.Kind = fkDebugOutput;
        fmDeepNesting:     keep := f.Kind = fkDeepNesting;
        fmTodoComment:     keep := f.Kind = fkTodoComment;
        fmEmptyMethod:     keep := f.Kind = fkEmptyMethod;
      else
        keep := True;
      end;
      if not keep then Continue;

      // ---- Typ-Filter (zusaetzliche Einschraenkung) ----
      case FTypeFilter of
        tfBug             : if f.FindingType <> ftBug             then Continue;
        tfCodeSmell       : if f.FindingType <> ftCodeSmell       then Continue;
        tfVulnerability   : if f.FindingType <> ftVulnerability   then Continue;
        tfSecurityHotspot : if f.FindingType <> ftSecurityHotspot then Continue;
        tfCodeDuplication : if f.FindingType <> ftCodeDuplication then Continue;
        tfAll             : ; // alle Typen durchlassen
      end;

      // ---- Suche (Datei / Methode / Befund) ----
      if searchLow <> '' then
      begin
        fileNameLow := DisplayName(f.FileName).ToLower;
        if (Pos(searchLow, fileNameLow) = 0) and
           (Pos(searchLow, f.MethodName.ToLower) = 0) and
           (Pos(searchLow, f.MissingVar.ToLower) = 0) then
          Continue;
      end;

      FDisplayedFindings.Add(f);
    end;

    // ---- Sortierung (Vergleichslogik direkt inline,
    //      da anonyme Methoden in Delphi keine lokalen Funktionen erfassen koennen) ----
    //
    // Severity-Rang: Lesefehler kommt unten (parser-Fehler, kein Code-Problem),
    // sonst Fehler -> Warnung -> Hinweis. Innerhalb gleicher Severity wird
    // nach Datei und Zeile stabilisiert, damit die Liste nicht jedes Mal anders
    // gemischt aussieht.
    if FSortColumn >= 0 then
    begin
      var SortCol  := FSortColumn;
      var SortDesc := FSortDescending;
      var BaseDir  := FCurrentBaseDir;
      FDisplayedFindings.Sort(TComparer<TLeakFinding>.Construct(
        function(const A, B: TLeakFinding): Integer

          function SeverityRank(const Sev: string): Integer;
          begin
            if      Sev = 'Fehler'     then Result := 0
            else if Sev = 'Warnung'    then Result := 1
            else if Sev = 'Hinweis'    then Result := 2
            else if Sev = 'Lesefehler' then Result := 3
            else                            Result := 4;
          end;

          function FileKey(const F: TLeakFinding): string;
          begin
            if BaseDir <> '' then
              Result := ExtractRelativePath(IncludeTrailingPathDelimiter(BaseDir), F.FileName)
            else
              Result := ExtractFileName(F.FileName);
          end;

        var SA, SB: string;
        begin
          case SortCol of
            0: Result := CompareText(FileKey(A), FileKey(B));
            1: Result := CompareText(A.MethodName, B.MethodName);
            2: Result := StrToIntDef(A.LineNumber, 0) - StrToIntDef(B.LineNumber, 0);
            3: Result := CompareText(A.TypeText, B.TypeText);
            4: Result := CompareText(A.MissingVar, B.MissingVar);
            5: Result := SeverityRank(A.SeverityText) - SeverityRank(B.SeverityText);
          else
            Result := 0;
          end;
          if SortDesc then Result := -Result;

          // Sekundaer-Sortierung (immer aufsteigend), damit Reihenfolge
          // bei gleichem Primaerschluessel deterministisch ist.
          if Result = 0 then
          begin
            SA := FileKey(A);
            SB := FileKey(B);
            Result := CompareText(SA, SB);
            if Result = 0 then
              Result := StrToIntDef(A.LineNumber, 0) - StrToIntDef(B.LineNumber, 0);
          end;
        end));
    end;

    // ---- Grid befuellen ----
    FResultGrid.RowCount := Max(FDisplayedFindings.Count + 1, 2);
    row := 1;
    for f in FDisplayedFindings do
    begin
      FResultGrid.Cells[0, row] := DisplayName(f.FileName);
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
  finally
    SendMessage(FResultGrid.Handle, WM_SETREDRAW, 1, 0);
    FResultGrid.Invalidate;
  end;

  StatusFindings(Format('%d / %d Befunde',
    [FDisplayedFindings.Count, FAllFindings.Count]));
  StatusMode(Format('Filter: %s%s', [FFilterCombo.Text,
    IfThen(searchLow <> '', ', Suche: ' + searchLow, '')]));
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
procedure TAnalyserFrame.ExportCsvClick(Sender: TObject);
var
  Dlg : TSaveDialog;
  Lst : TObjectList<TLeakFinding>;
begin
  if FDisplayedFindings.Count = 0 then
  begin
    StatusMode('Nichts zu exportieren - Filter liefert 0 Eintraege.');
    Exit;
  end;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title    := 'CSV-Export';
    Dlg.Filter   := 'CSV-Datei (*.csv)|*.csv';
    Dlg.DefaultExt := 'csv';
    Dlg.FileName := 'analyse-befunde.csv';
    if not Dlg.Execute then Exit;

    Lst := TObjectList<TLeakFinding>.Create(False);
    try
      for var F in FDisplayedFindings do Lst.Add(F);
      try
        TExporter.ExportCsv(Lst, Dlg.FileName);
        StatusMode(Format('CSV gespeichert: %s (%d Eintraege)',
          [ExtractFileName(Dlg.FileName), Lst.Count]));
      except
        on E: Exception do
          StatusMode('CSV-Export fehlgeschlagen: ' + E.Message);
      end;
    finally
      Lst.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TAnalyserFrame.ExportJsonClick(Sender: TObject);
var
  Dlg : TSaveDialog;
  Lst : TObjectList<TLeakFinding>;
begin
  if FDisplayedFindings.Count = 0 then
  begin
    StatusMode('Nichts zu exportieren - Filter liefert 0 Eintraege.');
    Exit;
  end;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title    := 'JSON-Export';
    Dlg.Filter   := 'JSON-Datei (*.json)|*.json';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'analyse-befunde.json';
    if not Dlg.Execute then Exit;

    Lst := TObjectList<TLeakFinding>.Create(False);
    try
      for var F in FDisplayedFindings do Lst.Add(F);
      try
        TExporter.ExportJson(Lst, Dlg.FileName);
        StatusMode(Format('JSON gespeichert: %s (%d Eintraege)',
          [ExtractFileName(Dlg.FileName), Lst.Count]));
      except
        on E: Exception do
          StatusMode('JSON-Export fehlgeschlagen: ' + E.Message);
      end;
    finally
      Lst.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Datei-Fokus fuer Jira-/Clipboard-Export bestimmen
// ---------------------------------------------------------------------------
function TAnalyserFrame.CurrentFocusFile: string;
// Welche Datei ist aktuell "im Fokus"? Bevorzugt der ausgewaehlte Grid-Eintrag,
// sonst wenn alle sichtbaren Befunde aus derselben Datei stammen, diese - sonst
// leer (= Aufrufer muss Datei abfragen).
var
  row, idx : Integer;
  refFile  : string;
  F        : TLeakFinding;
begin
  Result := '';
  // 1) Aktive Auswahlzeile
  row := FResultGrid.Row;
  idx := row - 1;
  if (idx >= 0) and (idx < FDisplayedFindings.Count) then
    Exit(FDisplayedFindings[idx].FileName);
  // 2) Alle sichtbaren Befunde gehoeren zur selben Datei
  refFile := '';
  for F in FDisplayedFindings do
  begin
    if refFile = '' then
      refFile := F.FileName
    else if not SameText(F.FileName, refFile) then
      Exit('');
  end;
  Result := refFile;
end;

// ---------------------------------------------------------------------------
// Jira-Export der aktuellen Datei in die Zwischenablage
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.ExportJiraClick(Sender: TObject);
var
  src       : string;
  jiraText  : string;
  filterSet : TSeverityFilter;
begin
  src := CurrentFocusFile;
  if src = '' then
  begin
    StatusMode('Jira-Export: bitte zuerst eine Zeile auswaehlen (Datei nicht eindeutig).');
    Exit;
  end;
  // Standard: Fehler + Warnungen. Hinweise sind oft zu viel fuer ein Ticket.
  filterSet := [lsError, lsWarning];
  jiraText := TExporter.BuildJiraText(FAllFindings, src, filterSet);
  Clipboard.AsText := jiraText;
  StatusMode(Format(
    'Jira-Wiki-Markup fuer %s in Zwischenablage kopiert (Fehler+Warnungen).',
    [ExtractFileName(src)]));
end;

// ---------------------------------------------------------------------------
// Clipboard: Plain-Text der Fehler+Warnungen einer Datei
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.CopyClipboardClick(Sender: TObject);
var
  src  : string;
  text : string;
begin
  src := CurrentFocusFile;
  if src = '' then
  begin
    StatusMode('Clipboard: bitte zuerst eine Zeile auswaehlen (Datei nicht eindeutig).');
    Exit;
  end;
  text := TExporter.BuildClipboardText(FAllFindings, src,
    [lsError, lsWarning]);
  Clipboard.AsText := text;
  StatusMode(Format(
    'Fehler+Warnungen fuer %s in Zwischenablage kopiert.',
    [ExtractFileName(src)]));
end;

// ---------------------------------------------------------------------------
// HTML-Report fuer alle Befunde (oder nur die aktuelle Datei)
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.ExportMenuButtonClick(Sender: TObject);
// Klappt das Popup-Menu direkt unterhalb des Buttons auf, sodass es
// auch ohne Rechtsklick aktiviert wird.
var
  Btn   : TControl;
  Pt    : TPoint;
begin
  if (Sender is TControl) and Assigned(FExportMenu) then
  begin
    Btn := TControl(Sender);
    Pt  := Btn.ClientToScreen(Point(0, Btn.Height));
    FExportMenu.Popup(Pt.X, Pt.Y);
  end;
end;

procedure TAnalyserFrame.ExportHtmlClick(Sender: TObject);
// HTML-Report enthaelt IMMER alle Befunde - sortiert und gefiltert wird im
// erzeugten HTML per JS (Header-Klick + Datei-Dropdown).
var
  Dlg     : TSaveDialog;
  defName : string;
  baseDir : string;
begin
  if (FCurrentBaseDir <> '') then
    baseDir := FCurrentBaseDir
  else
    baseDir := '';
  defName := TExporter.DefaultHtmlFileName('', baseDir);

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter      := 'HTML-Datei (*.html)|*.html';
    Dlg.DefaultExt  := 'html';
    Dlg.FileName    := ExtractFileName(defName);
    if baseDir <> '' then
      Dlg.InitialDir := baseDir;
    Dlg.Options     := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;

    try
      // SourceFile = '' -> alle Befunde im Report
      TExporter.ExportHtml(FAllFindings, '', Dlg.FileName);
      StatusMode(Format('HTML-Report gespeichert: %s',
        [ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do
        StatusMode('HTML-Export fehlgeschlagen: ' + E.Message);
    end;
  finally
    Dlg.Free;
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
  nBug, nSmell, nVuln, nHot, nDup : Integer;
  score      : Integer;
begin
  nErr  := 0; nWarn := 0; nHint := 0; nFileErr := 0;
  nBug  := 0; nSmell := 0; nVuln := 0; nHot := 0; nDup := 0;

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
      ftCodeSmell       : Inc(nSmell);
      ftVulnerability   : Inc(nVuln);
      ftSecurityHotspot : Inc(nHot);
      ftCodeDuplication : Inc(nDup);
    end;
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

  // Codequalitaet (gewichteter Score - Smell und Hotspot eingerechnet)
  FTileScore.Caption    := IntToStr(score);
end;

// ---------------------------------------------------------------------------
// Hilfe-Hinweis
// ---------------------------------------------------------------------------
class function TAnalyserFrame.FixHint(const Finding: TLeakFinding): TFixHint;
begin
  Result.Description := '';
  Result.Before      := '';
  Result.After       := '';

  case Finding.Kind of

    fkMemoryLeak:
      if Finding.Severity = lsError then
      begin
        Result.Description := 'Objekt erstellt, aber nie freigegeben (Speicherleck)';
        Result.Before :=
          'list := TStringList.Create;'#13#10 +
          'list.Add(''Eintrag'');'#13#10 +
          '// list.Free fehlt!'#13#10 +
          '// -> Speicherleck';
        Result.After :=
          'list := TStringList.Create;'#13#10 +
          'try'#13#10 +
          '  list.Add(''Eintrag'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list);'#13#10 +
          'end;';
      end
      else if Pos(' - R'#$FC'ckgabewert', Finding.MissingVar) > 0 then
      begin
        Result.Description := 'Funktionsr'#$FC'ckgabe wird nicht freigegeben';
        Result.Before :=
          '// Funktion gibt ein neues Objekt zur'#$FC'ck -'#13#10 +
          '// Aufrufer ist f'#$FC'r die Freigabe zust'#$E4'ndig.'#13#10 +
          ''#13#10 +
          'list := BuildList();'#13#10 +
          'list.Add(''x'');'#13#10 +
          '// list.Free fehlt!';
        Result.After :=
          'list := BuildList();'#13#10 +
          'try'#13#10 +
          '  list.Add(''x'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list);'#13#10 +
          'end;'#13#10 +
          ''#13#10 +
          '// Oder: Result := list;  (Ownership weitergeben)';
      end
      else
      begin
        Result.Description := 'Free liegt ausserhalb des finally-Blocks';
        Result.Before :=
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  other.Free;'#13#10 +
          'end;'#13#10 +
          'list.Free; // ← zu spaet!'#13#10 +
          '// Exception vor Free = Leck';
        Result.After :=
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list); // ← hier'#13#10 +
          '  other.Free;'#13#10 +
          'end;';
      end;

    fkEmptyExcept:
    begin
      Result.Description := 'Leerer except-Block verschluckt Exceptions';
      Result.Before :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  // leer'#13#10 +
        'end;'#13#10 +
        '// Fehler bleibt unsichtbar!';
      Result.After :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  on E: Exception do'#13#10 +
        '    LogError(E.Message);'#13#10 +
        '  // oder: raise;'#13#10 +
        'end;';
    end;

    fkSQLInjection:
    begin
      Result.Description := 'SQL-Befehl per "+" aufgebaut - SQL-Injection-Risiko';
      Result.Before :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM t'''#13#10 +
        '  + '' WHERE id = '' + Id;'#13#10 +
        ''#13#10 +
        '// Angreifer kann Id manipulieren!';
      Result.After :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM t'''#13#10 +
        '  + '' WHERE id = :Id'';'#13#10 +
        'Query.ParamByName(''Id'')'#13#10 +
        '  .AsString := Id;';
    end;

    fkHardcodedSecret:
    begin
      Result.Description := 'Passwort / Token als Literal im Quellcode';
      Result.Before :=
        'FPassword := ''geheim123'';'#13#10 +
        'FToken    := ''sk-abc-xyz'';'#13#10 +
        ''#13#10 +
        '// Sichtbar im Quellcode,'#13#10 +
        '// Repository und Build-Logs!';
      Result.After :=
        '// Aus Konfigurationsdatei:'#13#10 +
        'FPassword := Ini.ReadString('#13#10 +
        '  ''Auth'', ''Password'', '''');'#13#10 +
        ''#13#10 +
        '// Oder Umgebungsvariable:'#13#10 +
        'FPassword := GetEnvironmentVariable(''APP_PWD'');';
    end;

    fkFormatMismatch:
    begin
      Result.Description := 'Format()-Platzhalter-Anzahl ≠ Argument-Anzahl';
      Result.Before :=
        '// 2 Platzhalter, 1 Argument'#13#10 +
        's := Format('#13#10 +
        '  ''%s ist %d Jahre alt'','#13#10 +
        '  [Name]); // ← Age fehlt!'#13#10 +
        ''#13#10 +
        '// Laufzeitfehler: EConvertError';
      Result.After :=
        '// 2 Platzhalter, 2 Argumente'#13#10 +
        's := Format('#13#10 +
        '  ''%s ist %d Jahre alt'','#13#10 +
        '  [Name, Age]); // ← korrekt'#13#10 +
        ''#13#10 +
        '// Tipp: %% fuer ein echtes %-Zeichen';
    end;

    fkFileReadError:
    begin
      Result.Description := 'Datei konnte nicht gelesen oder geparst werden';
      Result.Before :=
        '// Moegliche Ursachen:'#13#10 +
        '// - Unbekannte Datei-Kodierung'#13#10 +
        '// - Datei gesperrt / kein Lesezugriff'#13#10 +
        '// - Datei groesser als 5 MB'#13#10 +
        '// - Syntaxfehler beim Parsen';
      Result.After :=
        '// Loesungsansaetze:'#13#10 +
        '// - Datei in UTF-8 oder UTF-16 speichern'#13#10 +
        '// - Dateizugriff und Berechtigungen pruefen'#13#10 +
        '// - Sehr grosse oder generierte Dateien'#13#10 +
        '//   aus dem Projektpfad ausschliessen';
    end;

    fkNilDeref:
    begin
      Result.Description := 'Nil-Dereferenzierung: Zugriff auf m'#$F6'glicherweise nil-Variable';
      Result.Before :=
        'obj := nil;'#13#10 +
        '// ... kein Create ...'#13#10 +
        'obj.DoSomething;  // EAccessViolation!';
      Result.After :=
        'obj := TFoo.Create;'#13#10 +
        'try'#13#10 +
        '  obj.DoSomething;'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(obj);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Oder: if Assigned(obj) then obj.DoSomething;';
    end;

    fkMissingFinally:
    begin
      Result.Description := 'Create ohne try/finally: Exception kann Free verhindern';
      Result.Before :=
        'list := TStringList.Create;'#13#10 +
        'DoWork(list);   // Exception hier'#13#10 +
        'list.Free;      // wird nie erreicht!';
      Result.After :=
        'list := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  DoWork(list);'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(list); // immer ausgef'#$FC'hrt'#13#10 +
        'end;';
    end;

    fkDivByZero:
    begin
      Result.Description := 'Division durch Null: EZeroDivide m'#$F6'glich';
      Result.Before :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  Result := Sum div Count; // Count=0 -> EZeroDivide'#13#10 +
        'end;';
      Result.After :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  if Count = 0 then Exit(0);'#13#10 +
        '  Result := Sum div Count;'#13#10 +
        'end;';
    end;

    fkDeadCode:
    begin
      Result.Description := 'Toter Code: Anweisungen nach Exit/raise nie erreichbar';
      Result.Before :=
        'if Error then'#13#10 +
        'begin'#13#10 +
        '  raise Exception.Create(''Fehler'');'#13#10 +
        '  Cleanup;  // wird nie ausgef'#$FC'hrt!'#13#10 +
        'end;';
      Result.After :=
        'if Error then'#13#10 +
        'begin'#13#10 +
        '  Cleanup;  // vor dem raise'#13#10 +
        '  raise Exception.Create(''Fehler'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Oder Cleanup in finally-Block auslagern';
    end;

    fkLongMethod:
    begin
      Result.Description := 'Methode zu lang - aufteilen erh'#$F6'ht Lesbarkeit';
      Result.Before :=
        'procedure TFoo.DoEverything;'#13#10 +
        'begin'#13#10 +
        '  // 100+ Zeilen Logik...'#13#10 +
        '  // Validierung, Daten holen,'#13#10 +
        '  // verarbeiten, speichern, loggen'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.DoEverything;'#13#10 +
        'begin'#13#10 +
        '  if not Validate then Exit;'#13#10 +
        '  ProcessData;'#13#10 +
        '  Persist;'#13#10 +
        '  LogResult;'#13#10 +
        'end;';
    end;

    fkLongParamList:
    begin
      Result.Description := 'Zu viele Parameter - Parameter-Object verwenden';
      Result.Before :=
        'procedure CreateUser(AName, AEmail,'#13#10 +
        '  APhone, AAddress, ACity,'#13#10 +
        '  ACountry: string;'#13#10 +
        '  AAge: Integer);';
      Result.After :=
        'type'#13#10 +
        '  TUserData = record'#13#10 +
        '    Name, Email, Phone: string;'#13#10 +
        '    Age: Integer;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure CreateUser(const Data: TUserData);';
    end;

    fkMagicNumber:
    begin
      Result.Description := 'Magic Number - durch benannte Konstante ersetzen';
      Result.Before :=
        'if RetryCount > 100 then'#13#10 +
        '  raise Exception.Create(''Zu viele Versuche'');';
      Result.After :=
        'const'#13#10 +
        '  MAX_RETRIES = 100;'#13#10 +
        ''#13#10 +
        'if RetryCount > MAX_RETRIES then'#13#10 +
        '  raise Exception.Create(''Zu viele Versuche'');';
    end;

    fkDuplicateString:
    begin
      Result.Description := 'String-Literal mehrfach - als Konstante extrahieren';
      Result.Before :=
        'Logger.Warn(''Datenbank-Verbindung verloren'');'#13#10 +
        '// ... 30 Zeilen sp'#$E4'ter ...'#13#10 +
        'Logger.Error(''Datenbank-Verbindung verloren'');';
      Result.After :=
        'const'#13#10 +
        '  MSG_DB_LOST = ''Datenbank-Verbindung verloren'';'#13#10 +
        ''#13#10 +
        'Logger.Warn(MSG_DB_LOST);'#13#10 +
        'Logger.Error(MSG_DB_LOST);';
    end;

    fkHardcodedPath:
    begin
      Result.Description := 'Hardkodierter Pfad - aus Konfiguration laden';
      Result.Before :=
        'LogFile := ''C:\Logs\app.log'';'#13#10 +
        '// L'#$E4'uft nur auf einem Rechner!';
      Result.After :=
        'LogFile := IncludeTrailingPathDelimiter('#13#10 +
        '  TPath.GetDocumentsPath) + ''app.log'';'#13#10 +
        ''#13#10 +
        '// Oder aus Ini/Umgebungsvariable laden';
    end;

    fkDebugOutput:
    begin
      Result.Description := 'Debug-Ausgabe in Produktionscode';
      Result.Before :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  ShowMessage(''Wert: '' + IntToStr(X));'#13#10 +
        '  // wahrscheinlich vergessen!'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  Logger.Debug(''Wert: %d'', [X]);'#13#10 +
        '  // bzw. ganz entfernen wenn'#13#10 +
        '  // nicht mehr ben'#$F6'tigt'#13#10 +
        'end;';
    end;

    fkDeepNesting:
    begin
      Result.Description := 'Zu tiefe Verschachtelung - Early-Exit oder Methoden-Extraktion';
      Result.Before :=
        'if A then'#13#10 +
        '  if B then'#13#10 +
        '    if C then'#13#10 +
        '      if D then'#13#10 +
        '        if E then'#13#10 +
        '          DoIt;';
      Result.After :=
        'if not A then Exit;'#13#10 +
        'if not B then Exit;'#13#10 +
        'if not C then Exit;'#13#10 +
        'if not D then Exit;'#13#10 +
        'if not E then Exit;'#13#10 +
        'DoIt;';
    end;

    fkUnusedUses:
    begin
      Result.Description := 'Uses-Eintrag wird m'#$F6'glicherweise nicht ben'#$F6'tigt';
      Result.Before :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.IniFiles,   // <- kein TIniFile im Code?'#13#10 +
        '  System.Classes;'#13#10 +
        ''#13#10 +
        '// Kompilierzeit + Laufzeit-Overhead'#13#10 +
        '// durch ungenutzte Abh'#$E4'ngigkeiten';
      Result.After :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.Classes;    // nur ben'#$F6'tigte Units'#13#10 +
        ''#13#10 +
        '// Tipp: Compiler-Hint [H2189]'#13#10 +
        '// "Unit X implicitly uses Y"'#13#10 +
        '// zeigt echte Abh'#$E4'ngigkeiten';
    end;

    fkTodoComment:
    begin
      Result.Description := 'Offener Marker im Kommentar - vor Release abarbeiten';
      Result.Before :=
        '// TODO: Tabelle persistieren'#13#10 +
        '// FIXME: race condition bei parallelem Save'#13#10 +
        '// HACK: workaround fuer Bug #4711'#13#10 +
        ''#13#10 +
        '// Marker bleiben sonst Jahre stehen';
      Result.After :=
        '// Variante 1: Aufgabe erledigen und Marker entfernen'#13#10 +
        ''#13#10 +
        '// Variante 2: in Issue-Tracker uebernehmen,'#13#10 +
        '// im Code referenzieren:'#13#10 +
        '// see JIRA-1234';
    end;

    fkEmptyMethod:
    begin
      Result.Description := 'Methodenrumpf ist leer - vergessener Stub oder unbeabsichtigt?';
      Result.Before :=
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Aufrufer denkt es passiert was -'#13#10 +
        '// passiert aber nichts.';
      Result.After :=
        '// Variante 1: Implementieren'#13#10 +
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        '  FList.Sort;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Variante 2: Wenn als Hook gedacht,'#13#10 +
        '// virtual deklarieren:'#13#10 +
        '// procedure DoStuff; virtual;';
    end;

  end;
end;

procedure TAnalyserFrame.UpdateHelp(Row: Integer);
const
  COLOR_DESC_DEFAULT = TColor($00E8E8E8);
  COLOR_DESC_ERROR   = TColor($00C8C8FF);  // hellrot
  COLOR_DESC_WARN    = TColor($00C0ECFF);  // hellgelb
  COLOR_DESC_HINT    = TColor($00D8E8C8);  // hellgruen
var
  Idx  : Integer;
  F    : TLeakFinding;
  Hint : TFixHint;
begin
  Idx := Row - 1;
  if (Idx < 0) or (Idx >= FDisplayedFindings.Count) then
  begin
    FHelpDescLabel.Caption    := '  Zeile auswaehlen fuer Loesungshinweis';
    FHelpDescLabel.Color      := COLOR_DESC_DEFAULT;
    FHelpBefore.Lines.Text    := '';
    FHelpAfter.Lines.Text     := '';
    Exit;
  end;

  F    := FDisplayedFindings[Idx];
  Hint := FixHint(F);

  if Hint.Description = '' then
  begin
    FHelpDescLabel.Caption := '  Kein Loesungshinweis verfuegbar.';
    FHelpDescLabel.Color   := COLOR_DESC_DEFAULT;
    FHelpBefore.Lines.Text := '';
    FHelpAfter.Lines.Text  := '';
    Exit;
  end;

  // Farbe der Beschriftungsleiste je Schweregrad
  if F.SeverityText = 'Fehler' then
    FHelpDescLabel.Color := COLOR_DESC_ERROR
  else if F.SeverityText = 'Hinweis' then
    FHelpDescLabel.Color := COLOR_DESC_HINT
  else
    FHelpDescLabel.Color := COLOR_DESC_WARN;

  FHelpDescLabel.Caption := '  ' + Hint.Description;
  FHelpBefore.Lines.Text := Hint.Before;
  FHelpAfter.Lines.Text  := Hint.After;
end;

procedure TAnalyserFrame.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
// Klick auf Zeile: Hilfetext aktualisieren UND Befund als Claude-AI-Prompt
// in die Zwischenablage legen, damit der User nur noch Strg+V im Chat machen muss.
var
  idx: Integer;
begin
  CanSelect := True;
  UpdateHelp(ARow);

  idx := ARow - 1; // Zeile 0 = Header
  if (idx >= 0) and (idx < FDisplayedFindings.Count) then
    CopyFindingToClipboard(FDisplayedFindings[idx]);
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
        'Claude-AI-Prompt in Zwischenablage: %s, Zeile %s (%s)',
        [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]));
  except
    // Clipboard kann unter bestimmten IDE-Modi blockiert sein - silent skip
  end;
end;

function TAnalyserFrame.BuildClaudePrompt(F: TLeakFinding): string;
// Markdown-Block fuer Claude-AI-Chat: Befund-Tabelle + Beschreibung +
// Code-Kontext (+/-5 Zeilen mit '>' Marker) + Vorher/Nachher.
const
  CONTEXT_LINES = 5;

  function KindToName(K: TFindingKind): string;
  begin
    case K of
      fkMemoryLeak      : Result := 'MemoryLeak';
      fkEmptyExcept     : Result := 'EmptyExcept';
      fkSQLInjection    : Result := 'SQLInjection';
      fkHardcodedSecret : Result := 'HardcodedSecret';
      fkFormatMismatch  : Result := 'FormatMismatch';
      fkFileReadError   : Result := 'FileReadError';
      fkUnusedUses      : Result := 'UnusedUses';
      fkNilDeref        : Result := 'NilDeref';
      fkMissingFinally  : Result := 'MissingFinally';
      fkDivByZero       : Result := 'DivByZero';
      fkDeadCode        : Result := 'DeadCode';
      fkLongMethod      : Result := 'LongMethod';
      fkLongParamList   : Result := 'LongParamList';
      fkMagicNumber     : Result := 'MagicNumber';
      fkDuplicateString : Result := 'DuplicateString';
      fkHardcodedPath   : Result := 'HardcodedPath';
      fkDebugOutput     : Result := 'DebugOutput';
      fkDeepNesting     : Result := 'DeepNesting';
      fkTodoComment     : Result := 'TodoComment';
      fkEmptyMethod     : Result := 'EmptyMethod';
      fkDuplicateBlock  : Result := 'DuplicateBlock';
    else
      Result := '?';
    end;
  end;

  function LoadSnippet(const APath: string; ALine: Integer): string;
  var
    SL                : TStringList;
    SB                : TStringBuilder;
    i, FromIdx, ToIdx : Integer;
    Marker            : string;
  begin
    Result := '';
    if (APath = '') or (ALine <= 0) or not FileExists(APath) then Exit;

    SL := TStringList.Create;
    try
      try
        SL.LoadFromFile(APath, TEncoding.UTF8);
      except
        try SL.LoadFromFile(APath); except Exit; end;
      end;

      FromIdx := ALine - 1 - CONTEXT_LINES;
      ToIdx   := ALine - 1 + CONTEXT_LINES;
      if FromIdx < 0 then FromIdx := 0;
      if ToIdx > SL.Count - 1 then ToIdx := SL.Count - 1;
      if FromIdx > ToIdx then Exit;

      SB := TStringBuilder.Create;
      try
        for i := FromIdx to ToIdx do
        begin
          if (i + 1) = ALine then Marker := '> ' else Marker := '  ';
          SB.Append(Marker);
          SB.Append(Format('%4d  ', [i + 1]));
          SB.AppendLine(SL[i]);
        end;
        Result := SB.ToString;
      finally
        SB.Free;
      end;
    finally
      SL.Free;
    end;
  end;

var
  SB      : TStringBuilder;
  Hint    : TFixHint;
  Line    : Integer;
  Snippet : string;
begin
  Hint    := FixHint(F); // bestehende class-Helper-Methode des Frames
  Line    := StrToIntDef(F.LineNumber, 0);
  Snippet := LoadSnippet(F.FileName, Line);

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Code-Analyse Befund');
    SB.AppendLine('');
    SB.AppendLine('| Feld | Wert |');
    SB.AppendLine('|------|------|');
    SB.AppendLine('| Datei | `' + F.FileName + '` |');
    SB.AppendLine('| Zeile | ' + F.LineNumber + ' |');
    if F.MethodName <> '' then
      SB.AppendLine('| Methode | `' + F.MethodName + '` |');
    SB.AppendLine('| Schweregrad | ' + F.SeverityText + ' |');
    SB.AppendLine('| Typ | ' + F.TypeText + ' |');
    SB.AppendLine('| Regel | ' + KindToName(F.Kind) + ' |');
    SB.AppendLine('| Detail | ' + F.MissingVar + ' |');
    SB.AppendLine('');

    if Hint.Description <> '' then
    begin
      SB.AppendLine('## Beschreibung');
      SB.AppendLine(Hint.Description);
      SB.AppendLine('');
    end;

    if Snippet <> '' then
    begin
      SB.AppendLine('## Code-Kontext');
      SB.AppendLine('```pascal');
      SB.Append(Snippet);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    if Hint.Before <> '' then
    begin
      SB.AppendLine('## Vorher (Problem)');
      SB.AppendLine('```pascal');
      SB.AppendLine(Hint.Before);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    if Hint.After <> '' then
    begin
      SB.AppendLine('## Nachher (Loesung)');
      SB.AppendLine('```pascal');
      SB.AppendLine(Hint.After);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    SB.AppendLine('---');
    SB.AppendLine('Bitte schlage einen konkreten Fix fuer die markierte ' +
      'Code-Stelle vor. Erklaere kurz die Ursache und liefere den ' +
      'angepassten Code-Block.');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
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
    Dlg.Title   := 'Projektordner auswaehlen';
    if Dlg.Execute then
      FProjectPath.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Analyse starten
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.AnalyseClick(Sender: TObject);
begin
  if not TStaticFiles.ValidatePath(FProjectPath.Text) then
  begin
    ShowMessage('Bitte einen gueltigen Projektpfad angeben.');
    Exit;
  end;
  SaveRecentPath(FProjectPath.Text);
  AnalyseAllClasses(FProjectPath.Text);
end;

procedure TAnalyserFrame.AnalyseCurrentFileClick(Sender: TObject);
var
  EditorSvc : IOTAEditorServices;
  EditView  : IOTAEditView;
  FilePath  : string;
  findings  : TObjectList<TLeakFinding>;
begin
  try
    EditorSvc := BorlandIDEServices as IOTAEditorServices;
    if not Assigned(EditorSvc) then
    begin
      StatusMode('IDE-Editor-Service nicht verfuegbar.');
      Exit;
    end;
    EditView := EditorSvc.TopView;
    if not Assigned(EditView) then
    begin
      StatusMode('Keine Datei geoeffnet.');
      Exit;
    end;

    FilePath := EditView.Buffer.FileName;
    if (FilePath = '') or not FilePath.EndsWith('.pas', True) then
    begin
      StatusMode('Aktuelle Datei ist keine Pascal-Datei.');
      Exit;
    end;

    Screen.Cursor := crHourglass;
    try
      StatusProgress('Analysiere: ' + ExtractFileName(FilePath));
      Application.ProcessMessages;

      findings := nil;
      try
        try
          findings := TStaticAnalyzer2.AnalyzeLeaks(FilePath,
            FChkUsesCheck.Checked);
        except
          on E: Exception do
          begin
            StatusMode('Analysefehler: ' + E.Message);
            Exit;
          end;
        end;

        if Assigned(findings) then
          PopulateFindings(findings, ExtractFilePath(FilePath));
      finally
        findings.Free;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
  except
    on E: Exception do
    begin
      Screen.Cursor := crDefault;
      StatusMode('Unerwarteter Fehler: ' + E.Message);
    end;
  end;
end;

procedure TAnalyserFrame.AnalyseChangedFilesClick(Sender: TObject);
// Branch-Aenderungen via Git oder SVN. Verwendet den aktuellen Projektpfad
// als Startpunkt fuer die Repo-Erkennung.
var
  startPath : string;
  files     : TStringList;
  info      : string;
  findings  : TObjectList<TLeakFinding>;
  wasCanc   : Boolean;
begin
  startPath := Trim(FProjectPath.Text);
  if (startPath = '') or not DirectoryExists(startPath) then
  begin
    StatusMode('Branch-Changes: bitte einen gueltigen Projektpfad angeben (zur Repo-Erkennung).');
    Exit;
  end;

  // ---- Settings frisch laden (User koennte repo.ini in der Zwischenzeit
  //      ueber den "Repo-Settings"-Button editiert haben) ----
  if Assigned(FRepoSettings) then
    try FRepoSettings.Load; except end;

  // ---- VCS-Diff einholen ----
  files := TVcsChanges.GetChangedPasFilesAuto(startPath, info, FRepoSettings);
  try
    if files.Count = 0 then
    begin
      StatusMode(info + ' - keine geaenderten .pas-Dateien');
      Exit;
    end;

    // ---- Analyse starten ----
    SetAnalyseUiBusy(True, files.Count);
    FLastProgressTick := 0;
    wasCanc := False;
    try
      StatusMode(info);
      StatusProgress(Format('%d Datei(en) - laeuft...', [files.Count]));
      Application.ProcessMessages;

      findings := nil;
      try
        try
          findings := TStaticAnalyzer2.AnalyzeLeaksFromList(files,
            procedure(Current, Total: Integer)
            var
              tick: Cardinal;
            begin
              try
                if (not Assigned(FProgressBar)) or (not Assigned(FStatusBar)) then
                  Exit;
                tick := GetTickCount;
                if (tick - FLastProgressTick > 100) or (Current = Total) then
                begin
                  FLastProgressTick := tick;
                  if (FProgressBar.Max <> Total) and (Total > 0) then
                    FProgressBar.Max := Total;
                  FProgressBar.Position := Current;
                  StatusProgress(Format('Datei %d / %d', [Current, Total]));
                  Application.ProcessMessages;
                end;
                if FAnalyseCancelled then Abort;
              except
                on EAbort do raise;
              end;
            end,
            FChkUsesCheck.Checked);
        except
          on EAbort do
          begin
            wasCanc := True;
          end;
          on E: Exception do
          begin
            StatusMode('Analysefehler: ' + E.Message);
            Exit;
          end;
        end;

        if Assigned(findings) then
          PopulateFindings(findings, startPath);
        if wasCanc then
          StatusMode('Analyse abgebrochen');
      finally
        findings.Free;
      end;
    finally
      SetAnalyseUiBusy(False);
    end;
  finally
    files.Free;
  end;
end;

procedure TAnalyserFrame.SetAnalyseUiBusy(ABusy: Boolean; ATotal: Integer);
// Toggelt UI in den "Analyse-laeuft"-Modus.
// Busy=True: Buttons aus, ProgressBar ein, Cancel sichtbar.
// Busy=False: alles zurueck, ProgressBar verschwunden.
begin
  FAnalyseRunning := ABusy;
  FAnalyseCancelled := False;

  if Assigned(FBtnAnalyse)        then FBtnAnalyse.Enabled        := not ABusy;
  if Assigned(FBtnAnalyseCurrent) then FBtnAnalyseCurrent.Enabled := not ABusy;
  if Assigned(FBtnAnalyseChanged) then FBtnAnalyseChanged.Enabled := not ABusy;

  if Assigned(FBtnCancel) then
  begin
    FBtnCancel.Visible := ABusy;
    FBtnCancel.Enabled := ABusy;
  end;

  if Assigned(FProgressBar) then
  begin
    FProgressBar.Visible  := ABusy;
    FProgressBar.Position := 0;
    if ATotal > 0 then
      FProgressBar.Max := ATotal
    else
      FProgressBar.Max := 100;
  end;

  if ABusy then
    Screen.Cursor := crAppStart
  else
    Screen.Cursor := crDefault;
end;

procedure TAnalyserFrame.CancelAnalyseClick(Sender: TObject);
// Markiert die Analyse als abzubrechen; der Progress-Callback raised EAbort
// beim naechsten Update und unwindet so aus AnalyzeLeaksRecursive heraus.
begin
  if not FAnalyseRunning then Exit;
  FAnalyseCancelled := True;
  FBtnCancel.Enabled := False; // Doppelklick verhindern
  StatusMode('Analyse wird abgebrochen...');
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
    StatusMode('Konnte Editor nicht oeffnen. Datei: ' + Path);
    Exit;
  end;

  // Liste sofort neu laden, damit Aenderungen ohne Frame-Neustart wirken
  try FIgnoreList.LoadDefault; except end;
  StatusMode(Format(
    'Ignore-Liste neu geladen (%d Muster). Pfad: %s',
    [FIgnoreList.PatternCount, Path]));
end;

procedure TAnalyserFrame.EditRepoSettingsClick(Sender: TObject);
// Oeffnet repo.ini im Default-Editor. Beim naechsten Klick auf
// "Branch-Changes" werden die Settings automatisch neu geladen.
var
  Path: string;
begin
  if not Assigned(FRepoSettings) then Exit;
  FRepoSettings.EnsureConfigExists;
  Path := FRepoSettings.ConfigFilePath;

  try
    ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    StatusMode('Konnte Editor nicht oeffnen. Datei: ' + Path);
    Exit;
  end;

  StatusMode('Repo-Settings: ' + Path + ' - Aenderungen wirken beim naechsten Klick auf Branch-Changes.');
end;

procedure TAnalyserFrame.AnalyseAllClasses(const APath: string);
var
  findings : TObjectList<TLeakFinding>;
  wasCancelled : Boolean;
begin
  // ProgressBar.Max kennen wir erst nach dem ersten Callback - bis dahin
  // zeigen wir einen "Marquee"-aehnlichen Stand (Max=100, Position=0).
  SetAnalyseUiBusy(True, 0);
  FLastProgressTick := 0;
  wasCancelled := False;
  // Test-Filter aus UI-Checkbox uebernehmen: Checked=true -> Tests einschliessen,
  // also SkipTests=false. IgnoreList wird waehrend des Verzeichnis-Scans
  // konsultiert.
  if Assigned(FIgnoreList) then
    FIgnoreList.SkipTests := not FChkIncludeTests.Checked;
  try
    try
      StatusMode('Analyse laeuft - Dateien werden gesucht...');
      Application.ProcessMessages;

      findings := nil;
      try
        try
          findings := TStaticAnalyzer2.AnalyzeLeaksRecursive(APath,
            procedure(Current, Total: Integer)
            // Total = -1 bedeutet: wir sind in der Verzeichnis-Scan-Phase.
            // Total >= 0  bedeutet: pro-Datei-Analyse-Phase.
            const
              MAX_SCAN_FILES = 20000; // Hardlimit - schuetzt vor Endlos-Scan
            var
              tick     : Cardinal;
              doUpdate : Boolean;
            begin
              try
                // Defensive: Frame koennte vom IDE-Host zerstoert werden
                if (not Assigned(FProgressBar)) or (not Assigned(FStatusBar)) then
                  Exit;

                tick := GetTickCount;
                // ProcessMessages und Status-Update zusammen drosseln (~10/s).
                // Cancel-Check und Hardlimit greifen aber bei JEDEM Tick.
                doUpdate := (tick - FLastProgressTick > 100);

                if Total < 0 then
                begin
                  // ---- Scan-Phase: wir wissen die Gesamtzahl noch nicht ----
                  // Hardlimit gegen pathologische Verzeichnisse / Symlink-Loops
                  if Current > MAX_SCAN_FILES then
                  begin
                    StatusMode(Format(
                      'Mehr als %d Dateien gefunden - Scan abgebrochen.',
                      [MAX_SCAN_FILES]));
                    Abort;
                  end;

                  if doUpdate then
                  begin
                    FLastProgressTick := tick;
                    // Marquee-Pseudo: Position pendelt mit gefundenen Dateien
                    FProgressBar.Max := 100;
                    FProgressBar.Position := Current mod 100;
                    StatusProgress(Format('Scanne... %d gefunden', [Current]));
                    Application.ProcessMessages;
                  end;
                end
                else
                begin
                  // ---- Analyse-Phase: Total ist die Datei-Anzahl ----
                  if doUpdate or (Current = Total) then
                  begin
                    FLastProgressTick := tick;
                    if (FProgressBar.Max <> Total) and (Total > 0) then
                      FProgressBar.Max := Total;
                    FProgressBar.Position := Current;
                    StatusProgress(Format('Datei %d / %d (%d%%)',
                      [Current, Total,
                       IfThen(Total > 0, Round(Current * 100 / Total), 0)]));
                    Application.ProcessMessages;
                  end;
                end;

                if FAnalyseCancelled then
                  Abort; // raised EAbort - silent
              except
                on EAbort do raise;
                // andere UI-Update-Fehler schlucken, Analyse weiterlaufen lassen
              end;
            end,
            FChkUsesCheck.Checked,
            FIgnoreList);
        except
          on EAbort do
          begin
            wasCancelled := True;
            // findings ist nil - AnalyzeLeaksRecursive gibt seine Result-Liste
            // bei EAbort frei. Wir behalten daher die alten FAllFindings.
          end;
          on E: Exception do
          begin
            StatusMode('Analysefehler: ' + E.Message);
            Exit;
          end;
        end;

        if Assigned(findings) then
          PopulateFindings(findings, APath);

        if wasCancelled then
          StatusMode('Analyse abgebrochen - keine neuen Befunde geladen');
      finally
        findings.Free;
      end;
    except
      on E: Exception do
        StatusMode('Unerwarteter Fehler: ' + E.Message);
    end;
  finally
    SetAnalyseUiBusy(False);
  end;
end;

// ---------------------------------------------------------------------------
// Doppelklick -> Datei in IDE oeffnen, direkt zur gefundenen Zeile springen
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
// Tooltip in der Datei-Spalte: voller Pfad aus FDisplayedFindings.
// Sonst: nur Cell-Text (z.B. fuer abgeschnittene Detail-Texte).
var
  grid    : TStringGrid;
  ACol, ARow, idx: Integer;
  hintText: string;
begin
  grid := TStringGrid(Sender);
  grid.MouseToCell(X, Y, ACol, ARow);
  hintText := '';
  if ARow >= 1 then
  begin
    idx := ARow - 1;
    if (ACol = 0) and (idx >= 0) and (idx < FDisplayedFindings.Count) then
      hintText := FDisplayedFindings[idx].FileName
    else
      hintText := grid.Cells[ACol, ARow];
  end;
  if grid.Hint <> hintText then
  begin
    grid.Hint := hintText;
    Application.HintPause := 300;
    Application.ActivateHint(grid.ClientToScreen(Point(X, Y)));
  end;
end;

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
    StatusMode('Datei nicht gefunden: ' + absPath);
    Exit;
  end;

  OpenFileAtLine(absPath, lineNo);
  StatusMode(Format('Geoeffnet: %s  Zeile: %d',
    [ExtractFileName(absPath), lineNo]));
end;

procedure TAnalyserFrame.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer);
var
  ModuleSvc : IOTAModuleServices;
  Module    : IOTAModule;
  SrcEditor : IOTASourceEditor;
  EditView  : IOTAEditView;
  EditPos   : TOTAEditPos;
  ActionSvc : IOTAActionServices;
  i         : Integer;
begin
  ModuleSvc := BorlandIDEServices as IOTAModuleServices;
  if not Assigned(ModuleSvc) then Exit;

  // Modul suchen (bereits geoeffnet oder erst oeffnen)
  Module := ModuleSvc.FindModule(AbsPath);
  if not Assigned(Module) then
  begin
    ActionSvc := BorlandIDEServices as IOTAActionServices;
    if Assigned(ActionSvc) then
      ActionSvc.OpenFile(AbsPath);
    Module := ModuleSvc.FindModule(AbsPath);
  end;

  if not Assigned(Module) then Exit;
  if LineNumber <= 0 then Exit;

  // IOTASourceEditor aus dem Modul holen
  SrcEditor := nil;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, SrcEditor) then
      Break;

  if not Assigned(SrcEditor) then Exit;

  // Editor-Tab in den Vordergrund bringen (wichtig wenn Datei bereits geoeffnet)
  SrcEditor.Show;

  // View holen und Cursor setzen
  EditView := SrcEditor.GetEditView(0);
  if Assigned(EditView) then
  begin
    EditPos.Col  := 1;
    EditPos.Line := LineNumber;
    EditView.CursorPos := EditPos;
    EditView.MoveViewToCursor;
    EditView.Paint;
  end;
end;

procedure TAnalyserFrame.Resize;
var
  HalfW: Integer;
begin
  inherited;
  if Assigned(FResultGrid) then
    GridResize(FResultGrid);
  // Vorher/Nachher-Haelften gleichmaessig vertikal aufteilen
  // (Vorher ist alTop, FHelpBeforePanel.Height steuert die Aufteilung).
  if Assigned(FHelpBeforePanel) and Assigned(FHelpBeforePanel.Parent) then
  begin
    HalfW := (FHelpBeforePanel.Parent.Height - 5) div 2;  // -5 fuer Splitter
    if HalfW > 40 then
      FHelpBeforePanel.Height := HalfW;
  end;
end;

// ---------------------------------------------------------------------------
// Grid-Zeichnen
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.GridResize(Sender: TObject);
const
  COL_SEV_W  = 90; // Schweregrad-Spalte fix
  COL_TYPE_W = 110; // Typ-Spalte fix
var
  used, regelW: Integer;
begin
  FResultGrid.ColWidths[3] := COL_TYPE_W;
  FResultGrid.ColWidths[5] := COL_SEV_W;
  used := FResultGrid.ColWidths[0] + FResultGrid.ColWidths[1] +
          FResultGrid.ColWidths[2] + COL_TYPE_W + COL_SEV_W +
          GetSystemMetrics(SM_CXVSCROLL);
  regelW := FResultGrid.ClientWidth - used;
  if regelW > 80 then
    FResultGrid.ColWidths[4] := regelW;
end;

procedure TAnalyserFrame.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
const
  HEADER_TOP    = TColor($00E8E8E8);
  HEADER_BOTTOM = TColor($00C8C8C8);
  ZEBRA         = TColor($00F5F5F5);
  SEP_LINE      = TColor($00AAAAAA);
var
  grid    : TStringGrid;
  severity: string;
  bgColor : TColor;
  txtRect : TRect;
begin
  grid := TStringGrid(Sender);
  txtRect := Rect;
  InflateRect(txtRect, -4, 0);

  // ---- Header-Zeile ----
  if ARow = 0 then
  begin
    // Verlauf oben -> unten
    GradientFillRect(grid.Canvas, Rect, HEADER_TOP, HEADER_BOTTOM, True);
    // Trennlinie unten
    grid.Canvas.Pen.Color := SEP_LINE;
    grid.Canvas.MoveTo(Rect.Left,  Rect.Bottom - 1);
    grid.Canvas.LineTo(Rect.Right, Rect.Bottom - 1);
    // Text mit Sort-Indikator
    grid.Canvas.Brush.Style := bsClear;
    grid.Canvas.Font.Name   := 'Segoe UI';
    grid.Canvas.Font.Size   := 8;
    grid.Canvas.Font.Style  := [fsBold];
    grid.Canvas.Font.Color  := clBlack;
    var HeaderText := grid.Cells[ACol, ARow];
    if ACol = FSortColumn then
    begin
      if FSortDescending then
        HeaderText := HeaderText + ' v'
      else
        HeaderText := HeaderText + ' ^';
    end;
    DrawText(grid.Canvas.Handle, PChar(HeaderText),
      -1, txtRect, DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX);
    Exit;
  end;

  // ---- Datenzeilen ----
  severity := grid.Cells[5, ARow];
  if severity = 'Lesefehler' then
    bgColor := COLOR_FILEERROR
  else if (ARow >= 1) and (ARow - 1 < FDisplayedFindings.Count) and
          (FDisplayedFindings[ARow - 1].Kind = fkUnusedUses) then
    bgColor := COLOR_UNUSEDUSES
  else if (ARow >= 1) and (ARow - 1 < FDisplayedFindings.Count) and
          (FDisplayedFindings[ARow - 1].Kind in [fkNilDeref, fkDivByZero]) then
    bgColor := COLOR_NILDEREF
  else if (ARow >= 1) and (ARow - 1 < FDisplayedFindings.Count) and
          (FDisplayedFindings[ARow - 1].Kind = fkDeadCode) then
    bgColor := COLOR_DEADCODE
  else if severity = 'Fehler' then
    bgColor := COLOR_ERROR
  else if severity = 'Warnung' then
    bgColor := COLOR_WARNING
  else if severity = 'Hinweis' then
    bgColor := COLOR_HINT
  else if Odd(ARow) then
    bgColor := ZEBRA
  else
    bgColor := clWindow;

  if gdSelected in State then
    bgColor := clHighlight;

  grid.Canvas.Brush.Color := bgColor;
  grid.Canvas.FillRect(Rect);
  grid.Canvas.Brush.Style := bsClear;

  grid.Canvas.Font.Name := 'Segoe UI';
  grid.Canvas.Font.Size := 8;
  if gdSelected in State then
    grid.Canvas.Font.Color := clHighlightText
  else
    grid.Canvas.Font.Color := clWindowText;

  // Datei-Spalte fett
  if (ACol = 0) and (not (gdSelected in State)) then
    grid.Canvas.Font.Style := [fsBold]
  else
    grid.Canvas.Font.Style := [];

  DrawText(grid.Canvas.Handle, PChar(grid.Cells[ACol, ARow]),
    -1, txtRect, DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX or DT_END_ELLIPSIS);
end;

// ---------------------------------------------------------------------------
// Recent Paths
// ---------------------------------------------------------------------------
procedure TAnalyserFrame.LoadRecentPaths;
var
  Ini        : TIniFile;
  i          : Integer;
  path       : string;
  ideProject : string;
begin
  FProjectPath.Items.Clear;

  // Aktuell geoeffnetes IDE-Projekt als ersten Eintrag
  ideProject := GetCurrentIDEProjectDir;
  if ideProject <> '' then
    FProjectPath.Items.Add(ideProject);

  // Letzte 3 Pfade aus INI
  ForceDirectories(ExtractFilePath(GetIniPath));
  Ini := TIniFile.Create(GetIniPath);
  try
    for i := 1 to MAX_RECENT do
    begin
      path := Ini.ReadString('Recent', 'Path' + IntToStr(i), '');
      if (path <> '') and (FProjectPath.Items.IndexOf(path) < 0) then
        FProjectPath.Items.Add(path);
    end;
  finally
    Ini.Free;
  end;

  if FProjectPath.Items.Count > 0 then
    FProjectPath.Text := FProjectPath.Items[0]
  else
    FProjectPath.Text := '';
end;

procedure TAnalyserFrame.SaveRecentPath(const APath: string);
var
  Ini : TIniFile;
  i   : Integer;
  idx : Integer;
begin
  // Aus der Liste entfernen falls bereits vorhanden, dann vorne einfuegen
  idx := FProjectPath.Items.IndexOf(APath);
  if idx >= 0 then
    FProjectPath.Items.Delete(idx);
  FProjectPath.Items.Insert(0, APath);
  FProjectPath.Text := APath;

  // Auf MAX_RECENT begrenzen (IDE-Projekt nicht mitzaehlen)
  while FProjectPath.Items.Count > MAX_RECENT + 1 do
    FProjectPath.Items.Delete(FProjectPath.Items.Count - 1);

  // In INI speichern (ohne IDE-Projekt-Eintrag)
  ForceDirectories(ExtractFilePath(GetIniPath));
  Ini := TIniFile.Create(GetIniPath);
  try
    i := 1;
    for var j := 0 to FProjectPath.Items.Count - 1 do
    begin
      if i > MAX_RECENT then Break;
      Ini.WriteString('Recent', 'Path' + IntToStr(i), FProjectPath.Items[j]);
      Inc(i);
    end;
    for i := i to MAX_RECENT do
      Ini.DeleteKey('Recent', 'Path' + IntToStr(i));
  finally
    Ini.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TAnalyserDockableForm
// ---------------------------------------------------------------------------

function TAnalyserDockableForm.GetCaption: string;
begin
  Result := 'Static Code Analyser';
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
  F: TAnalyserFrame;
begin
  FFrame := AFrame as TAnalyserFrame;
  F := FFrame;
  // IDE kann die Schrift des Frames beim Einbetten ueberschreiben ->
  // hier explizit nach dem Hosting nochmal setzen.
  F.Font.Name := 'Segoe UI';
  F.Font.Size := 6;
  F.FResultGrid.Font.Name := 'Segoe UI';
  F.FResultGrid.Font.Size := 8;
  F.FProjectPath.Font.Name := 'Segoe UI';
  F.FProjectPath.Font.Size := 6;
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
  GDockableForm := TAnalyserDockableForm.Create;

  NTASvc := BorlandIDEServices as INTAServices;

  // Dockable Form registrieren (fuer Desktop-State-Persistenz)
  NTASvc.RegisterDockableForm(GDockableForm);

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
    Item.Caption := 'Static Code Analyser';
    Item.OnClick := GDockableForm.ViewMenuClick;
    ViewMenu.Add(Item);
    GViewMenuItem := Item;
  end;
end;

procedure ShowAnalyserDockableForm;
begin
  if Assigned(GDockableForm) then
    (BorlandIDEServices as INTAServices).CreateDockableForm(GDockableForm);
end;

procedure UnregisterAnalyserDockableForm;
begin
  if Assigned(GViewMenuItem) then
  begin
    GViewMenuItem.Parent.Remove(GViewMenuItem);
    FreeAndNil(GViewMenuItem);
  end;
  if Assigned(GDockableForm) then
  begin
    (BorlandIDEServices as INTAServices).UnregisterDockableForm(GDockableForm);
    GDockableForm := nil;
  end;
end;

end.
