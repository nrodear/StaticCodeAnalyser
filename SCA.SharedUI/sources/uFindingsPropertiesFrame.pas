unit uFindingsPropertiesFrame;

// Schmaler, dockbarer Findings-View fuer EINE Datei (Properties-Stil).
//
// Lebt in SCA.SharedUI -> plain VCL, KEIN ToolsAPI-Import. Der IDE-Plugin-
// Wrapper (uIDEFindingsPropertiesForm) instanziiert das Frame, ruft
// TIDETheme.Apply + RefreshFromTheme und subscribed Watch-Mode-Updates.
//
// Public API:
//   * SetFindings(FileName, Findings)  - Owned. Frame uebernimmt.
//   * SetActiveFile(FileName)          - Editor-Tab-Wechsel. Wenn der
//                                        File-Name vom aktuellen abweicht,
//                                        Grid wird geleert (bis neue
//                                        Findings reinkommen).
//   * RefreshFromTheme                 - Wrapper ruft das nach Theme-
//                                        Wechsel auf.
//   * Clear                            - Grid + Header leeren.
//   * OnFindingClick: TFindingClickEvent - Single-Click auf Zeile.
//
// Layout (siehe Konzept_FindingsPropertiesPanel.md, Abschnitt "Layout"):
//   +-- TPanel (Header, alTop) ---------------------+
//   | TLabel  "<filename> (N Findings)"             |
//   | TComboBox  All / Errors / Errors+Warnings     |
//   +-----------------------------------------------+
//   | TStringGrid (alClient, virtual via GetCellText)|
//   +-----------------------------------------------+

interface

uses
  System.Classes, System.SysUtils, System.Types, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Grids, Vcl.StdCtrls,
  Vcl.Graphics,
  uMethodd12,
  uAnalyserTypes,
  uFindingGridRenderer;

type
  // Callback wenn User auf eine Finding-Zeile klickt - Caller springt im
  // Editor zur Zeile (im Standalone-Mode kann der Caller das Mapping
  // anders machen).
  TFindingClickEvent = procedure(Sender: TObject;
    Finding: TLeakFinding) of object;

  TFindingsPropertiesFrame = class(TFrame)
  strict private
    FHeaderPanel   : TPanel;
    FHeaderLabel   : TLabel;
    // Sub-Panel direkt unter dem Header-Label - traegt die drei Toolbar-
    // Controls in fester Reihenfolge: [Clear][Reload] FSeverityCombo.
    // Reihenfolge ergibt sich aus der Create-Reihenfolge in BuildControls
    // ueber Align=alLeft (Clear+Reload) bzw. alClient (Combo).
    FToolbarPanel  : TPanel;
    FBtnClear      : TButton;
    FBtnReload     : TButton;
    FSeverityCombo : TComboBox;
    FGrid          : TStringGrid;
    FAllFindings   : TObjectList<TLeakFinding>;   // OWNED, ungefiltert (aktuelle Datei)
    FVisibleRows   : TList<TLeakFinding>;         // Refs auf FAllFindings, gefiltert
    // Per-File-Findings-Cache. Schluessel = NormalizePath. Eintrag wird
    // gefuellt bei SetFindings, gelesen bei SetActiveFile - so behalten
    // andere offene Dateien ihre Findings, auch wenn der Wrapper-Cache
    // den naechsten Re-Scan skippt.
    // OWNED: das Dictionary hat die TObjectList<TLeakFinding>-Refs; deren
    // OwnsObjects ist True, damit beim Cache-Eviction die Findings freed
    // werden. Beim Anzeigen werden Kopien der Refs in FAllFindings gelegt
    // (Pointer-Sharing, NICHT zweite Owner) - genau wie bisher in
    // FVisibleRows. FAllFindings.OwnsObjects ist deshalb auf False
    // gesetzt sobald der Cache aktiv ist.
    FFindingsByFile : TObjectDictionary<string, TObjectList<TLeakFinding>>;
    FCurrentFile   : string;
    FGridConfig    : TFindingGridConfig;
    FOnClick       : TFindingClickEvent;
    FOnDestroying  : TNotifyEvent;
    // Toolbar-Button-Events. Frame kann selbst nicht scannen oder Marker
    // loeschen (kein OTAPI/GHighlighter-Zugriff aus SCA.SharedUI). Wrapper
    // im IDE-Plugin haengt die Handler ein - bleibt Layering-konform.
    FOnReloadRequested       : TNotifyEvent;
    FOnClearMarkersRequested : TNotifyEvent;
    // Sort-State. FSortColumn = -1 -> unsortiert (Insertion-Order vom
    // Detector). 0..COL_COUNT-1 -> sortiert nach dieser Spalte.
    // FSortDescending toggelt bei wiederholtem Klick auf gleiche Spalte.
    FSortColumn      : Integer;
    FSortDescending  : Boolean;
    procedure BuildControls;
    procedure BuildGridConfig;
    procedure EnsureComboItems;
    procedure ApplySeverityFilter;
    procedure UpdateHeader;
  strict protected
    // Wird von VCL gerufen wenn das Window-Handle erstellt wird - das
    // passiert beim ersten Show UND bei jedem Re-Parent (Dock/Undock).
    // Items defensiv repopulieren, falls VCL sie waehrend der Re-Parent-
    // Sequenz verworfen hat.
    procedure CreateWnd; override;
    procedure SeverityComboChange(Sender: TObject);
    // Toolbar-Buttons - Funktionalitaet wird in Step 2 dranngeschraubt.
    // Aktuell leere Stubs, damit das Layout sichtbar ist und Naming feststeht.
    procedure BtnClearClick(Sender: TObject);
    procedure BtnReloadClick(Sender: TObject);
    // Cache-Helpers fuer FFindingsByFile.
    function  CloneFinding(F: TLeakFinding): TLeakFinding;
    procedure StoreInCache(const AFileName: string);
    function  LoadFromCache(const AFileName: string): Boolean;
    procedure RemoveFromCache(const AFileName: string);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure GridDblClick(Sender: TObject);
    procedure GridClick(Sender: TObject);
    procedure GridResize(Sender: TObject);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ToggleSortColumn(ACol: Integer);
    procedure SortVisibleRows;
    function  GetCellText(ACol, ARow: Integer): string;
    function  GetCellSeverity(ARow: Integer): TFindingSeverity;
    // .pas + .dfm gleichen Basenames sind im SCA-Modell EIN Scan-Ziel
    // (Worker analysiert die .pas, DFM-Findings kommen mit dem gleichen
    // Result-Batch zurueck). Frame muss Tab-Wechsel zwischen den beiden
    // NICHT als Datei-Wechsel werten - sonst clear'd er die Findings die
    // gerade vom .pas-Scan kamen.
    class function ArePasDfmRelated(const A, B: string): Boolean; static;
    // [DEPRECATED] Wrapper auf uPathNormalize.NormalizePathForKey. Bleibt
    // als class-function fuer interne Stabilitaet (alt-API), Tests
    // referenzieren sie. Neue Aufrufer importieren uPathNormalize direkt.
    class function NormalizePath(const APath: string): string; static;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Uebernimmt Ownership der Findings-Liste. Wenn Findings = nil
    // wird der Grid geleert. Wenn AFileName <> FCurrentFile wird zuerst
    // auf die neue Datei umgeschaltet.
    procedure SetFindings(const AFileName: string;
      Findings: TObjectList<TLeakFinding>);

    // Editor-Tab-Wechsel. Wenn die neue Datei nicht der aktuellen Cache-
    // Datei entspricht, wird der Grid temporaer geleert (bis der Watch-
    // Mode neue Findings liefert).
    procedure SetActiveFile(const AFileName: string);

    // Vom IDE-Plugin-Wrapper aufgerufen nach Theme-Wechsel. Frame holt
    // sich die neuen Farben via uAnalyserTheme.ActiveStyleServices
    // (= globaler Hook der vom IDE-Plugin gesetzt wird).
    procedure RefreshFromTheme;

    procedure Clear;
    // Wrapper kann den Cache-Eintrag fuer eine bestimmte Datei verwerfen
    // (Reload-Button). Public-Wrapper um RemoveFromCache.
    procedure InvalidateFindingsCache(const AFileName: string);

    function VisibleCount: Integer;
    function TotalCount: Integer;

    property CurrentFile: string read FCurrentFile;
    property OnFindingClick: TFindingClickEvent read FOnClick write FOnClick;
    // Wird im Destructor gefeuert BEVOR die Felder freed werden. IDE-
    // Plugin-Wrapper nutzt das, um seinen FFrame-Slot auf nil zu setzen,
    // damit asynchrone Callbacks (Theme-Sub, Watch-Findings-Sub) nicht
    // auf einen freed Frame zugreifen.
    property OnDestroying: TNotifyEvent read FOnDestroying write FOnDestroying;
    // Reload-Button: Wrapper triggert einen erneuten Single-File-Scan fuer
    // die aktuell sichtbare Datei (TriggerAutoScan im IDE-Wrapper).
    property OnReloadRequested: TNotifyEvent
      read FOnReloadRequested write FOnReloadRequested;
    // Clear-Button: Wrapper loescht ALLE Marker in ALLEN Dateien
    // (GHighlighter.Clear) - der File-bezogene Grid-Clear wird
    // anschliessend lokal ausgefuehrt.
    property OnClearMarkersRequested: TNotifyEvent
      read FOnClearMarkersRequested write FOnClearMarkersRequested;
  end;

implementation

{$R *.dfm}

// noinspection-file BeginEndRequired, ClassPerFile, ConsecutiveSection, LongMethod, NestedRoutine, NilComparison, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter, UnusedPublicMember

uses
  System.Generics.Defaults,   // TComparer<T>.Construct
  Vcl.Themes,
  uSCAConsts,        // KIND_META (Rule-Name)
  uAnalyserTheme,    // ActiveStyleServices
  uIDEToolbar,       // ApplySegoeUI - selbes Font-Setup wie TAnalyserFrame
  uPathNormalize,    // SPOT fuer Pfad-Normalisierung
  uLocalization;     // _() Translation-Macro

type
  // Class-Crack: TStringGrid.OnResize ist protected (TControl-Erbe). Wir
  // brauchen den Hook fuer die Stretching-Spaltenbreite (Message-Column).
  // Standard-VCL-Pattern - genauso wie TControlAccess in uIDEAnalyserForm.
  TStringGridAccess = class(TStringGrid);

const
  // Spalten-Layout (5 Spalten: Method / Line / Type / Rule / Severity).
  // Analog zum IDE-Grid (uIDEAnalyserForm), abzueglich der Datei-Spalte
  // weil das Properties-Fenster sowieso datei-bezogen ist.
  COL_METHOD   = 0;
  COL_LINE     = 1;
  COL_TYPE     = 2;
  COL_RULE     = 3;
  COL_SEVERITY = 4;
  COL_COUNT    = 5;

  HEADER_METHOD   = 'Method';
  HEADER_LINE     = 'Line';
  HEADER_TYPE     = 'Type';
  HEADER_RULE     = 'Rule';
  HEADER_SEVERITY = 'Severity';

  COMBO_ALL                 = 'All severities';
  COMBO_ERRORS_ONLY         = 'Errors only';
  COMBO_ERRORS_AND_WARNINGS = 'Errors + Warnings';

  // Fixed-width-Spalten in Pixeln (96-DPI). Rule stretcht via GridResize.
  // Knapp dimensioniert damit das Panel auch im schmalen Dock-Mode
  // (rechts/links angedockt, ~280-350 px) noch alle Spalten zeigt -
  // sonst wuerde Severity ganz rechts ausgeblendet. Akzent-Bar links
  // bleibt zusaetzlich als Severity-Farbindikator immer sichtbar.
  W_METHOD   = 95;
  W_LINE     = 40;
  W_TYPE     = 72;
  W_SEVERITY = 56;
  // Mindest-Breite fuer Rule wenn der Rest schon eng ist.
  W_RULE_MIN = 80;

{ TFindingsPropertiesFrame }

constructor TFindingsPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAllFindings    := TObjectList<TLeakFinding>.Create({AOwnsObjects=}True);
  FVisibleRows    := TList<TLeakFinding>.Create;
  // OwnsValues: Dict-Eviction freed die Cache-Liste samt ihrer Klone.
  FFindingsByFile := TObjectDictionary<string, TObjectList<TLeakFinding>>.Create([doOwnsValues]);
  FCurrentFile := '';
  FSortColumn      := -1;       // unsortiert = Detector-Reihenfolge
  FSortDescending  := False;
  BuildControls;
  BuildGridConfig;
  UpdateHeader;
  // Selbes Font-Setup wie TAnalyserFrame im IDE-Plugin: Segoe UI Size 8 +
  // ParentFont=False. Wird rekursiv auf alle Children angewandt damit
  // Header-Label, ComboBox und Grid einheitliches Plugin-Look haben.
  TIDEToolbar.ApplySegoeUI(Self);
end;

destructor TFindingsPropertiesFrame.Destroy;
begin
  // Erst Listener informieren, damit asynchrone Callbacks ihren Frame-Ref
  // auf nil setzen koennen, BEVOR wir hier die Felder freed.
  if Assigned(FOnDestroying) then
    try FOnDestroying(Self); except end;
  FVisibleRows.Free;
  FAllFindings.Free;
  FFindingsByFile.Free;
  inherited;
end;

procedure TFindingsPropertiesFrame.BuildControls;
const
  BTN_SIZE = 26;   // quadratisch ("4-eckig") - 26 px DIP, skaliert
                   // ueber Form.Scaled wenn der User DPI != 96 fuehrt
begin
  // ---- Header-Panel ----
  // Header-Hoehe nun 18 (Label) + 28 (Toolbar) + 6 (Padding) = ~52.
  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent    := Self;
  FHeaderPanel.Align     := alTop;
  FHeaderPanel.Height    := 52;
  FHeaderPanel.BevelOuter := bvNone;
  FHeaderPanel.Padding.SetBounds(6, 4, 6, 4);
  TIDEToolbar.ApplySegoeUI(FHeaderPanel);

  FHeaderLabel := TLabel.Create(Self);
  FHeaderLabel.Parent  := FHeaderPanel;
  FHeaderLabel.Align   := alTop;
  FHeaderLabel.Height  := 18;
  FHeaderLabel.Caption := _('(no file)');
  TIDEToolbar.ApplySegoeUI(FHeaderLabel);
  FHeaderLabel.Font.Style := [fsBold];   // bold NACH ApplySegoeUI

  // ---- Toolbar-Sub-Panel: [Clear][Reload] FSeverityCombo ----
  // Liegt als alTop UNTER dem Label im Header. Reihenfolge der Children
  // ergibt sich aus der Create-Sequenz + Align (alLeft+alLeft+alClient).
  FToolbarPanel := TPanel.Create(Self);
  FToolbarPanel.Parent     := FHeaderPanel;
  FToolbarPanel.Align      := alTop;
  FToolbarPanel.Top        := 22;       // direkt unter dem 18px-Label
  FToolbarPanel.Height     := BTN_SIZE + 2;   // BTN_SIZE + 1px Luft oben/unten
  FToolbarPanel.BevelOuter := bvNone;
  FToolbarPanel.ParentBackground := False;
  FToolbarPanel.ParentColor      := True;
  TIDEToolbar.ApplySegoeUI(FToolbarPanel);

  // Button "Clear" - ganz links. Quadratisch (BTN_SIZE x BTN_SIZE).
  // Caption ist ein Unicode-Glyph (U+2715 MULTIPLICATION X) statt Text -
  // erspart Image-Assets und passt sauber in den 26x26-Button. Hint
  // traegt den verbalen Namen fuer Tooltip + Screen-Reader.
  FBtnClear := TButton.Create(Self);
  FBtnClear.Parent  := FToolbarPanel;
  FBtnClear.Align   := alLeft;
  FBtnClear.Width   := BTN_SIZE;
  FBtnClear.Height  := BTN_SIZE;
  FBtnClear.Caption := #$2715;   // ✕
  FBtnClear.Hint    := _('Clear current findings');
  FBtnClear.ShowHint:= True;
  FBtnClear.OnClick := BtnClearClick;
  TIDEToolbar.ApplySegoeUI(FBtnClear);
  FBtnClear.Font.Size := 11;     // Symbol-Glyph leicht groesser als Text-Default

  // Button "Reload" - rechts neben Clear. Beide alLeft - die zweite
  // alLeft-Control landet rechts der ersten (VCL ControlIndex-Order).
  // Caption: U+21BB CLOCKWISE OPEN CIRCLE ARROW (↻).
  FBtnReload := TButton.Create(Self);
  FBtnReload.Parent  := FToolbarPanel;
  FBtnReload.Align   := alLeft;
  FBtnReload.Width   := BTN_SIZE;
  FBtnReload.Height  := BTN_SIZE;
  FBtnReload.Caption := #$21BB;  // ↻
  FBtnReload.Hint    := _('Re-run analysis for current file');
  FBtnReload.ShowHint:= True;
  FBtnReload.OnClick := BtnReloadClick;
  TIDEToolbar.ApplySegoeUI(FBtnReload);
  FBtnReload.Font.Size := 11;

  // Severity-Combo - rechter Rest (alClient nach den beiden alLeft).
  FSeverityCombo := TComboBox.Create(Self);
  FSeverityCombo.Parent    := FToolbarPanel;
  FSeverityCombo.Align     := alClient;
  FSeverityCombo.AlignWithMargins := True;
  FSeverityCombo.Margins.SetBounds(4, 1, 0, 1);
  FSeverityCombo.Height    := 24;   // expliziter Wert, sonst kann VCL beim
                                    // Re-Parent (Dock-Recreate) auf 0 gehen
                                    // und die Combo wird optisch verschluckt
  FSeverityCombo.Style     := csDropDownList;
  TIDEToolbar.ApplySegoeUI(FSeverityCombo);
  EnsureComboItems;
  FSeverityCombo.OnChange  := SeverityComboChange;

  // ---- Grid ----
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent      := Self;
  FGrid.Align       := alClient;
  FGrid.DefaultDrawing := False;     // wir zeichnen via OnDrawCell
  // VCL-Constraint: FixedRows < RowCount. Setup-Reihenfolge daher
  // RowCount=2 (Header + 1 Slot) BEVOR FixedRows=1. Empty-State (keine
  // Findings) bleibt RowCount=2, leerer DataRow wird einfach mit ''
  // gerendert.
  FGrid.RowCount    := 2;
  FGrid.ColCount    := COL_COUNT;
  FGrid.FixedRows   := 1;
  FGrid.FixedCols   := 0;
  FGrid.Options     := FGrid.Options
                       + [goRowSelect, goThumbTracking]
                       - [goEditing, goRangeSelect];
  FGrid.DefaultRowHeight := 18;
  FGrid.OnDrawCell  := GridDrawCell;
  FGrid.OnDblClick  := GridDblClick;
  FGrid.OnClick     := GridClick;
  FGrid.OnMouseDown := GridMouseDown;
  TStringGridAccess(FGrid).OnResize := GridResize;
  FGrid.DoubleBuffered := True;
  TIDEToolbar.ApplySegoeUI(FGrid);

  // Header-Captions setzen (im Virtual-Mode liefert GetCellText sie bei
  // ARow=0; aber DefaultDrawing=False zeichnet auch den Header via
  // OnDrawCell, der ueber GetCellText geht - hier nur defensiv setzen).
  FGrid.Cells[COL_METHOD,   0] := _(HEADER_METHOD);
  FGrid.Cells[COL_LINE,     0] := _(HEADER_LINE);
  FGrid.Cells[COL_TYPE,     0] := _(HEADER_TYPE);
  FGrid.Cells[COL_RULE,     0] := _(HEADER_RULE);
  FGrid.Cells[COL_SEVERITY, 0] := _(HEADER_SEVERITY);

  FGrid.ColWidths[COL_METHOD]   := W_METHOD;
  FGrid.ColWidths[COL_LINE]     := W_LINE;
  FGrid.ColWidths[COL_TYPE]     := W_TYPE;
  FGrid.ColWidths[COL_SEVERITY] := W_SEVERITY;
  // Rule stretcht auf den Rest in GridResize.
end;

procedure TFindingsPropertiesFrame.BuildGridConfig;
begin
  // IDE-Style-Config: Theme aktiv, Severity-Akzent-Bar links, Virtual-Mode
  // via GetCellText. SeverityColumn auf unsere Spaltennummerierung
  // umbiegen (1 = Sev).
  FGridConfig := TFindingGridRenderer.IDEConfig(
    {ASortColumn=}-1, {ASortDescending=}False);
  FGridConfig.SeverityColumn   := COL_SEVERITY;  // jetzt 4 (vorher 1)
  FGridConfig.GetCellText      := GetCellText;
  FGridConfig.GetCellSeverity  := GetCellSeverity;
  FGridConfig.ShowSortIndicator := True;
  // GetStyleServices wird im RefreshFromTheme dynamisch gehookt -
  // initial nimmt der Renderer Vcl.Themes.StyleServices (VCL-global).
end;

procedure TFindingsPropertiesFrame.RefreshFromTheme;
var
  Style : TCustomStyleServices;
begin
  Style := ActiveStyleServices;   // uAnalyserTheme: respektiert
                                  // StyleServicesProvider-Hook (vom
                                  // IDE-Plugin auf IOTAIDEThemingServices
                                  // gesetzt).
  if Style <> nil then
  begin
    // Frame selbst (sonst weisser Rand zwischen Header und Grid in Dark-Theme)
    Self.Color            := Style.GetSystemColor(clBtnFace);

    FHeaderPanel.ParentBackground := False;       // damit Color greift
    FHeaderPanel.ParentColor := False;
    FHeaderPanel.Color    := Style.GetSystemColor(clBtnFace);
    FHeaderLabel.Color    := FHeaderPanel.Color;
    FHeaderLabel.Font.Color := Style.GetSystemColor(clWindowText);

    // Toolbar-Sub-Panel + Buttons - sonst heller Streifen unter dem Label
    // in Dark-Theme (Default-Panel-Color ist clBtnFace, was im Dark-Mode
    // anders aufgeloest wird als unsere explizit gesetzte HeaderPanel-Color).
    FToolbarPanel.ParentBackground := False;
    FToolbarPanel.ParentColor      := False;
    FToolbarPanel.Color := FHeaderPanel.Color;
    // TButton wird vom IDE-ThemingServices automatisch gefarbt - hier nur
    // sicherstellen, dass die Schrift mit dem Header-Theme matcht.
    FBtnClear.Font.Color  := Style.GetSystemColor(clWindowText);
    FBtnReload.Font.Color := Style.GetSystemColor(clWindowText);

    // ComboBox: csDropDownList ignoriert oft das Theming aus dem IDE-
    // ThemingServices weil VCL den csDropDownList-Render an die Windows-
    // ComboBox-Native-Control delegiert. Explizit Color + Font setzen
    // - VCL-Style-Engine paint'd damit den Drop-Body manuell.
    FSeverityCombo.Color      := Style.GetSystemColor(clWindow);
    FSeverityCombo.Font.Color := Style.GetSystemColor(clWindowText);

    FGrid.Color           := Style.GetSystemColor(clWindow);
    FGrid.Font.Color      := Style.GetSystemColor(clWindowText);
    FGrid.FixedColor      := Style.GetSystemColor(clBtnFace);
  end;
  // GetStyleServices fuer den Renderer auf den aktuellen Style einhaengen
  // (lambda capture - Renderer ruft das pro Zelle auf).
  FGridConfig.GetStyleServices :=
    function: TCustomStyleServices
    begin
      Result := ActiveStyleServices;
    end;
  FGrid.Invalidate;
end;

procedure TFindingsPropertiesFrame.SetFindings(const AFileName: string;
  Findings: TObjectList<TLeakFinding>);
var
  NewNorm, CurNorm: string;
begin
  // FCurrentFile zeigt die im Editor sichtbare Datei. Wenn der Scan-Batch
  // fuer den Companion kommt (z.B. .pas-Worker-Result waehrend User im
  // .dfm-Tab ist), behalten wir den User-sichtbaren Namen. Nur bei
  // unrelated incoming-Datei (oder leerem State) wechseln.
  NewNorm := NormalizePath(AFileName);
  CurNorm := NormalizePath(FCurrentFile);
  if (FCurrentFile = '') or
     not (SameText(NewNorm, CurNorm) or
          ArePasDfmRelated(NewNorm, CurNorm)) then
    FCurrentFile := AFileName;
  FAllFindings.Clear;
  if Findings <> nil then
  begin
    // Ownership uebertragen: Quell-Liste OwnsObjects=False, damit ihr
    // Free die Items NICHT freigibt - wir haben sie jetzt in FAllFindings.
    // VORHER: while Findings.Count > 0 do Add(Findings[0]); Delete(0).
    //         Jedes Delete(0) shiftet die Restliste -> O(N^2). Bei 200+
    //         Findings spuerbarer Lag im UI-Thread.
    // JETZT:  Capacity vorab reservieren + linearer Index-Walk = O(N).
    Findings.OwnsObjects := False;
    try
      FAllFindings.Capacity := FAllFindings.Count + Findings.Count;
      for var I := 0 to Findings.Count - 1 do
        FAllFindings.Add(Findings[I]);
      Findings.Clear;   // entfernt Refs, freed Items NICHT (OwnsObjects=False)
    finally
      Findings.Free;
    end;
  end;
  // Per-File-Cache: spaeter Tab-Wechsel zurueck zu dieser Datei laed die
  // Findings aus dem Cache statt einen leeren Grid anzuzeigen (Wrapper
  // skippt den Re-Scan dank FLastScanTimes, dispatched also nichts neu).
  StoreInCache(AFileName);
  ApplySeverityFilter;
  UpdateHeader;
end;

procedure TFindingsPropertiesFrame.SetActiveFile(const AFileName: string);
var
  NewNorm, CurNorm: string;
begin
  NewNorm := NormalizePath(AFileName);
  CurNorm := NormalizePath(FCurrentFile);
  if SameText(NewNorm, CurNorm) then Exit;
  // .pas <-> .dfm Tab-Wechsel ist KEIN echter Datei-Wechsel - der Scan-
  // Batch (.pas + .dfm zusammen) bleibt gueltig. Nur die "sichtbare" Datei
  // aktualisieren, Findings stehen lassen.
  if ArePasDfmRelated(NewNorm, CurNorm) then
  begin
    FCurrentFile := AFileName;
    UpdateHeader;
    Exit;
  end;
  FCurrentFile := AFileName;
  // Per-File-Cache-Hit: Findings der neuen Datei sind noch vom letzten
  // Scan gespeichert -> nicht clearen, sondern aus Cache laden. So bleibt
  // das Grid beim Tab-Wechsel zwischen schon-gescannten Dateien gefuellt,
  // auch wenn der Wrapper-Re-Scan-Cache (FLastScanTimes) skipt und damit
  // kein Watch-Dispatch nachgeschoben wird.
  if LoadFromCache(AFileName) then
  begin
    ApplySeverityFilter;
    UpdateHeader;
    Exit;
  end;
  FAllFindings.Clear;
  FVisibleRows.Clear;
  FGrid.RowCount := 2;   // FixedRows=1 verlangt RowCount>=2
  UpdateHeader;
end;

class function TFindingsPropertiesFrame.NormalizePath(
  const APath: string): string;
begin
  // Delegiert an die zentrale Implementation. Verhaltens-Aenderung:
  // jetzt zusaetzlich lowercase (Windows-FS ist case-insensitive) -
  // SameText-Vergleiche oben werden dadurch redundant aber bleiben
  // korrekt. AddOrSetValue-Cache-Keys werden konsistent zwischen Frame,
  // Highlighter und Wrapper.
  Result := uPathNormalize.NormalizePathForKey(APath);
end;

class function TFindingsPropertiesFrame.ArePasDfmRelated(
  const A, B: string): Boolean;
var
  ExtA, ExtB: string;
begin
  Result := False;
  if (A = '') or (B = '') then Exit;
  ExtA := LowerCase(ExtractFileExt(A));
  ExtB := LowerCase(ExtractFileExt(B));
  // Beide muessen .pas vs .dfm sein (eine Richtung oder die andere).
  if not (((ExtA = '.pas') and (ExtB = '.dfm')) or
          ((ExtA = '.dfm') and (ExtB = '.pas'))) then Exit;
  // Selbe Datei abzueglich Extension. SameText fuer case-insensitive
  // FS auf Windows.
  Result := SameText(ChangeFileExt(A, ''), ChangeFileExt(B, ''));
end;

function TFindingsPropertiesFrame.VisibleCount: Integer;
begin
  Result := FVisibleRows.Count;
end;

function TFindingsPropertiesFrame.TotalCount: Integer;
begin
  Result := FAllFindings.Count;
end;

procedure TFindingsPropertiesFrame.Clear;
begin
  // Cache komplett verwerfen: nach Clear soll der naechste Scan tatsaechlich
  // neu fuellen, nicht aus altem Per-File-Cache laden.
  FFindingsByFile.Clear;
  FCurrentFile := '';
  FAllFindings.Clear;
  FVisibleRows.Clear;
  FGrid.RowCount := 2;   // FixedRows=1 verlangt RowCount>=2
  UpdateHeader;
end;

procedure TFindingsPropertiesFrame.CreateWnd;
begin
  inherited;
  // Items + ItemIndex stabilisieren - VCL verwirft sie beim Dock-Recreate
  // gelegentlich. Hier laufen wir nach dem Re-Parent, also nach dem
  // verlustreichen Moment.
  if Assigned(FSeverityCombo) then
    EnsureComboItems;
  // Theme defensiv reapplien - sonst startet das Panel im Default-Style
  // (weiss) bis der Wrapper-FrameCreated-Pfad zum RefreshFromTheme kommt.
  // Bei Re-Parent (Dock/Undock) noetig weil die Color-Properties teils
  // zurueckgesetzt werden.
  if Assigned(FHeaderPanel) and Assigned(FSeverityCombo) and Assigned(FGrid) then
    RefreshFromTheme;
end;

procedure TFindingsPropertiesFrame.EnsureComboItems;
// Items defensiv neu populieren wenn sie weg sind. Bei Dock/Undock-
// Recreate berichtet der User dass die Combo leer wird - vermutlich
// VCL-DFM-Stream-Replay setzt Items.Clear nach dem Constructor. Pro
// Aufruf billig (Compare via Count) - wir gehen den Items.Add-Pfad nur
// wenn wirklich was fehlt.
begin
  if FSeverityCombo.Items.Count >= 3 then Exit;
  FSeverityCombo.Items.BeginUpdate;
  try
    FSeverityCombo.Items.Clear;
    FSeverityCombo.Items.Add(_(COMBO_ALL));
    FSeverityCombo.Items.Add(_(COMBO_ERRORS_ONLY));
    FSeverityCombo.Items.Add(_(COMBO_ERRORS_AND_WARNINGS));
  finally
    FSeverityCombo.Items.EndUpdate;
  end;
  if FSeverityCombo.ItemIndex < 0 then
    FSeverityCombo.ItemIndex := 0;
end;

procedure TFindingsPropertiesFrame.ApplySeverityFilter;
var
  F        : TLeakFinding;
  Sev      : TFindingSeverity;
  FilterIdx: Integer;
begin
  // Defensive: Combo-Items koennen nach Dock/Undock-Recreate fehlen UND
  // ItemIndex transient -1 zeigen. EnsureComboItems repopuliert wenn
  // noetig, FilterIdx faellt auf 0 (All) zurueck wenn nichts ausgewaehlt.
  EnsureComboItems;
  FilterIdx := FSeverityCombo.ItemIndex;
  if FilterIdx < 0 then FilterIdx := 0;

  FVisibleRows.Clear;
  for F in FAllFindings do
  begin
    Sev := SeverityFromKindLevel(F.Kind, F.Severity);
    case FilterIdx of
      0 : FVisibleRows.Add(F);                                  // All
      1 : if Sev = fsError then FVisibleRows.Add(F);            // Errors only
      2 : if Sev in [fsError, fsWarning] then FVisibleRows.Add(F);
    else
      FVisibleRows.Add(F);                                       // unbekannt -> show all
    end;
  end;
  // Sort nach Filter, vor RowCount-Setzen.
  SortVisibleRows;
  // RowCount = Header + sichtbare Findings. Minimum 2 wegen FixedRows=1.
  if FVisibleRows.Count = 0 then
    FGrid.RowCount := 2
  else
    FGrid.RowCount := FVisibleRows.Count + 1;
  FGrid.Invalidate;
end;

procedure TFindingsPropertiesFrame.GridMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
// Header-Click erkennen und Sort-Toggle ausloesen. ARow=0 ist die
// Header-Zeile (FixedRows=1). MouseToCell mappt Pixel-Koordinaten auf
// Cell-Indizes.
var
  ACol, ARow: Integer;
begin
  if Button <> mbLeft then Exit;
  FGrid.MouseToCell(X, Y, ACol, ARow);
  if (ARow = 0) and (ACol >= 0) and (ACol < COL_COUNT) then
    ToggleSortColumn(ACol);
end;

procedure TFindingsPropertiesFrame.ToggleSortColumn(ACol: Integer);
// Zweimal auf gleiche Spalte = Toggle Asc/Desc. Andere Spalte = neu sortieren,
// Default-Richtung aufsteigend.
begin
  if FSortColumn = ACol then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := ACol;
    FSortDescending := False;
  end;
  FGridConfig.SortColumn     := FSortColumn;
  FGridConfig.SortDescending := FSortDescending;
  ApplySeverityFilter;       // sortiert + re-rendert
end;

procedure TFindingsPropertiesFrame.SortVisibleRows;
// Stabiles Sort der gefilterten Rows nach FSortColumn. Pro Spalte ein
// dedizierter Comparer: Line = Integer-Vergleich (sonst sortiert "10"
// vor "9"), Severity = Enum-Ordnung (fsError=0 < fsWarning < fsHint),
// Rule + Message = String-CompareText (case-insensitive).
var
  SortCol     : Integer;
  Descending  : Boolean;
begin
  if FSortColumn < 0 then Exit;
  SortCol    := FSortColumn;
  Descending := FSortDescending;
  FVisibleRows.Sort(TComparer<TLeakFinding>.Construct(
    function(const L, R: TLeakFinding): Integer
    begin
      case SortCol of
        COL_METHOD:
          Result := CompareText(L.MethodName, R.MethodName);
        COL_LINE:
          Result := StrToIntDef(L.LineNumber, 0) -
                    StrToIntDef(R.LineNumber, 0);
        COL_TYPE:
          Result := CompareText(L.TypeText, R.TypeText);
        COL_RULE:
          Result := CompareText(KIND_META[L.Kind].Name,
                                KIND_META[R.Kind].Name);
        COL_SEVERITY:
          Result := Integer(SeverityFromKindLevel(L.Kind, L.Severity)) -
                    Integer(SeverityFromKindLevel(R.Kind, R.Severity));
      else
        Result := 0;
      end;
      if Descending then Result := -Result;
    end));
end;

procedure TFindingsPropertiesFrame.UpdateHeader;
var
  FileBase : string;
begin
  if FCurrentFile = '' then
  begin
    FHeaderLabel.Caption := _('(no file selected)');
    Exit;
  end;
  FileBase := ExtractFileName(FCurrentFile);
  if FAllFindings.Count = 0 then
    FHeaderLabel.Caption := Format(_('%s (no findings)'), [FileBase])
  else if FAllFindings.Count = FVisibleRows.Count then
    FHeaderLabel.Caption := Format(_('%s (%d findings)'),
      [FileBase, FAllFindings.Count])
  else
    FHeaderLabel.Caption := Format(_('%s (%d of %d findings)'),
      [FileBase, FVisibleRows.Count, FAllFindings.Count]);
end;

procedure TFindingsPropertiesFrame.SeverityComboChange(Sender: TObject);
begin
  ApplySeverityFilter;
  UpdateHeader;
end;

function TFindingsPropertiesFrame.CloneFinding(F: TLeakFinding): TLeakFinding;
// Deep-Copy aller Datenfelder. Wert-Felder, Strings - shallow Assign reicht.
// Identisch zu der Variante im IDE-Wrapper, hier nochmal damit das Frame
// in SCA.SharedUI keine OTAPI-Dependencies braucht.
begin
  Result := TLeakFinding.Create;
  Result.FileName   := F.FileName;
  Result.MethodName := F.MethodName;
  Result.LineNumber := F.LineNumber;
  Result.MissingVar := F.MissingVar;
  Result.Severity   := F.Severity;
  Result.Kind       := F.Kind;
  Result.Confidence := F.Confidence;
  Result.RuleID     := F.RuleID;
end;

procedure TFindingsPropertiesFrame.StoreInCache(const AFileName: string);
// Klont die aktuelle FAllFindings-Liste in den File-Cache. Ueberschreibt
// einen ggf. existierenden Cache-Eintrag fuer AFileName (OwnsValues ->
// alte Liste freed).
var
  Key   : string;
  Owned : TObjectList<TLeakFinding>;
  F     : TLeakFinding;
begin
  if AFileName = '' then Exit;
  Key := NormalizePath(AFileName);
  if Key = '' then Exit;
  Owned := TObjectList<TLeakFinding>.Create({AOwnsObjects=}True);
  try
    Owned.Capacity := FAllFindings.Count;
    for F in FAllFindings do
      Owned.Add(CloneFinding(F));
  except
    Owned.Free;
    raise;
  end;
  FFindingsByFile.AddOrSetValue(Key, Owned);
end;

function TFindingsPropertiesFrame.LoadFromCache(
  const AFileName: string): Boolean;
// True wenn fuer AFileName ein Cache-Eintrag existierte und in FAllFindings
// uebernommen wurde. FAllFindings wird VOR dem Laden geleert.
var
  Key    : string;
  Cached : TObjectList<TLeakFinding>;
  F      : TLeakFinding;
begin
  Result := False;
  Key := NormalizePath(AFileName);
  if Key = '' then Exit;
  if not FFindingsByFile.TryGetValue(Key, Cached) then Exit;
  FAllFindings.Clear;
  FAllFindings.Capacity := Cached.Count;
  for F in Cached do
    FAllFindings.Add(CloneFinding(F));
  Result := True;
end;

procedure TFindingsPropertiesFrame.InvalidateFindingsCache(
  const AFileName: string);
begin
  RemoveFromCache(AFileName);
end;

procedure TFindingsPropertiesFrame.RemoveFromCache(const AFileName: string);
// Cache-Eintrag fuer eine Datei explizit verwerfen. Wird vom Wrapper
// genutzt wenn Reload-Button geklickt - sonst wuerde der naechste Tab-
// Wechsel zur selben Datei den alten Cache-Eintrag rauskramen statt
// die frisch gescannten Findings zu zeigen.
var
  Key : string;
begin
  Key := NormalizePath(AFileName);
  if Key = '' then Exit;
  FFindingsByFile.Remove(Key);   // OwnsValues -> Liste freed
end;

procedure TFindingsPropertiesFrame.BtnClearClick(Sender: TObject);
begin
  // Wrapper loescht alle Marker in allen Dateien (GHighlighter.Clear).
  // Wenn kein Wrapper haengt, lokaler Fallback = nur Grid + Header
  // leeren, damit der Button im Standalone-Modus auch nicht no-op ist.
  if Assigned(FOnClearMarkersRequested) then
    FOnClearMarkersRequested(Self)
  else
    Clear;
end;

procedure TFindingsPropertiesFrame.BtnReloadClick(Sender: TObject);
begin
  // Wrapper triggert TriggerAutoScan(CurrentFile). Ohne Wrapper bleibt
  // Reload no-op - im Standalone-Modus gibt es keinen Re-Scan-Pfad.
  if Assigned(FOnReloadRequested) then
    FOnReloadRequested(Self);
end;

function TFindingsPropertiesFrame.GetCellText(ACol, ARow: Integer): string;
var
  F : TLeakFinding;
begin
  Result := '';
  if ARow = 0 then
  begin
    case ACol of
      COL_METHOD:   Result := _(HEADER_METHOD);
      COL_LINE:     Result := _(HEADER_LINE);
      COL_TYPE:     Result := _(HEADER_TYPE);
      COL_RULE:     Result := _(HEADER_RULE);
      COL_SEVERITY: Result := _(HEADER_SEVERITY);
    end;
    Exit;
  end;
  if (ARow - 1) >= FVisibleRows.Count then Exit;
  F := FVisibleRows[ARow - 1];
  case ACol of
    COL_METHOD:   Result := F.MethodName;
    COL_LINE:     Result := F.LineNumber;
    COL_TYPE:     Result := F.TypeText;
    COL_RULE:
      begin
        // Konsistent zur zentralen BuildFindingTitle-Heuristik im
        // IDE-Plugin: Rule-Name + Identifier-Suffix wenn MissingVar
        // ein Identifier-only-Wert ist (z.B. ein Variablen-Name) -
        // sonst nur Rule-Name.
        Result := KIND_META[F.Kind].Name;
        if (F.MissingVar <> '') and (Pos(' ', F.MissingVar) = 0) then
          Result := Result + ': ' + F.MissingVar;
      end;
    COL_SEVERITY:
      case SeverityFromKindLevel(F.Kind, F.Severity) of
        fsError:   Result := 'E';
        fsWarning: Result := 'W';
        fsHint:    Result := 'H';
      end;
  end;
end;

function TFindingsPropertiesFrame.GetCellSeverity(
  ARow: Integer): TFindingSeverity;
var
  F: TLeakFinding;
begin
  Result := fsHint;
  if (ARow = 0) or ((ARow - 1) >= FVisibleRows.Count) then Exit;
  F := FVisibleRows[ARow - 1];
  Result := SeverityFromKindLevel(F.Kind, F.Severity);
end;

procedure TFindingsPropertiesFrame.GridDrawCell(Sender: TObject;
  ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
begin
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State, FGridConfig);
end;

procedure TFindingsPropertiesFrame.GridClick(Sender: TObject);
var
  Row : Integer;
  F   : TLeakFinding;
begin
  if not Assigned(FOnClick) then Exit;
  Row := FGrid.Row;
  if (Row <= 0) or ((Row - 1) >= FVisibleRows.Count) then Exit;
  F := FVisibleRows[Row - 1];
  FOnClick(Self, F);
end;

procedure TFindingsPropertiesFrame.GridDblClick(Sender: TObject);
begin
  // Konsistent zu IntelliJ-Pattern (Doppelklick = Go-To). Single-Click
  // macht es schon, Dbl-Click ist Konvenienz fuer Power-User.
  GridClick(Sender);
end;

procedure TFindingsPropertiesFrame.GridResize(Sender: TObject);
var
  Avail : Integer;
begin
  // Rule stretcht auf die restliche Breite (minus Scrollbar-Margin).
  Avail := FGrid.ClientWidth
           - FGrid.ColWidths[COL_METHOD]
           - FGrid.ColWidths[COL_LINE]
           - FGrid.ColWidths[COL_TYPE]
           - FGrid.ColWidths[COL_SEVERITY]
           - 20;
  if Avail < W_RULE_MIN then Avail := W_RULE_MIN;
  FGrid.ColWidths[COL_RULE] := Avail;
end;

end.
