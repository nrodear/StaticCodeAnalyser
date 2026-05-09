unit uIDELineHighlighter;

// Editor-Line-Highlight und Annotation-Overlay via INTACodeEditorEvents
// (kanonische ToolsAPI.Editor-Loesung fuer RAD Studio 12+).
//
// ARCHITEKTUR:
//   TFindingEditorEvents  – implementiert INTACodeEditorEvents. Wird einmalig
//                           global ueber INTACodeEditorServices registriert
//                           und empfaengt Paint-Callbacks fuer ALLE Views.
//
//   TFindingHighlighter   – Singleton (GHighlighter). Haelt die selektierte
//                           Befund-Stelle (Datei + Zeile + Annotation-Texte).
//                           SetSelected aktualisiert den Zustand und loest
//                           per InvalidateTopEditorLogicalLine einen gezielten
//                           Repaint aus.
//
// VORTEILE vs. altem INTAEditViewNotifier-Ansatz:
//   * Context.EditControl  -> TWinControl direkt, kein WindowFromDC-Hack,
//                             kein EnumChildWindows-Fallback.
//   * Einmalige globale Registrierung -> kein per-View-Attach/Detach-Tracking.
//   * AllowedLineStages    -> filtert unnoetigen Paint-Overhead heraus.
//   * Context.EditorState.CharHeight -> DPI-bewusstes Overlay-Sizing.
//   * InvalidateTopEditorLogicalLine -> praeziser als View.Paint (Full-Repaint).
//
// PAINT-ZYKLUS (pro Editor):
//   BeginPaint  -> Reset FSelectedVisible wenn dieser Editor die selektierte
//                  Zeile zuvor enthalten hat (FSavedEditor-Match).
//   PaintLine   -> Nur Stage=plsBackground, BeforeEvent=False.
//                  Trifft die selektierte Zeile: Stripe zeichnen, Kontext speichern.
//   EndPaint    -> Verbirgt das Overlay wenn die markierte Zeile nicht mehr
//                  gemalt wurde (gescrollt, deselektiert). Zeigt das Overlay
//                  NICHT proaktiv – das passiert nur in EditorMouseMove.
//
// HOVER-MODUS:
//   SetSelected setzt nur den Selektionszustand (roter Stripe). Das Overlay
//   erscheint erst wenn die Maus ueber die markierte Zeile schwebt
//   (EditorMouseMove + Hit-Test gegen FSavedCodeRect). Verlaesst die Maus
//   die Zeile oder wird gescrollt, verschwindet das Overlay sofort.
//   Voraussetzung: cevMouseEvents + cevWindowEvents in AllowedEvents.
//
// HIDE-ON-MOUSE-LEAVE (TTimer in TFindingEditorEvents):
//   Das Overlay ist topmost (Embarcadero-Pattern wie Code Insight) und
//   ueberdeckt damit auch gefloatete IDE-Tool-Panels. Sobald die Maus den
//   Editor verlaesst, feuert EditorMouseMove nicht mehr — der Timer pollt
//   alle 200ms GetCursorPos und versteckt das Overlay wenn der Cursor
//   nicht mehr ueber FSavedCodeRect ist. Dadurch "verschwindet" das
//   Overlay wenn der User auf das gefloatete Panel klickt/hovert.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls,
  ToolsAPI, ToolsAPI.Editor,
  uMethodd12,
  uIDEAnnotationOverlay;

type
  TFindingHighlighter = class;  // forward

  // WICHTIG: Basisklasse TNotifierObject, NUR INTACodeEditorEvents listen.
  TFindingEditorEvents = class(TNotifierObject, INTACodeEditorEvents)
  private
    // Zustand pro Paint-Zyklus: gesetzt/gelesen in Begin/Paint/End-Dreischritt.
    FSelectedVisible : Boolean;
    FSavedCodeRect   : TRect;
    FSavedEditor     : TWinControl;  // Editor der die selektierte Zeile enthielt
    FSavedCharHeight : Integer;      // DPI-aware Zeilenhoehe aus Context.EditorState
    // Hide-on-mouse-leave Timer: Das Overlay ist topmost (siehe Z-Order-Doku
    // in uIDEAnnotationOverlay), liegt also auch ueber gefloateten IDE-Tool-
    // Panels. Damit das nicht stoert, prueft dieser Timer alle 200ms ob der
    // Cursor noch ueber FSavedCodeRect ist — wenn nicht, HideOverlay.
    // Notwendig weil EditorMouseMove nicht mehr feuert sobald die Maus den
    // Editor verlaesst.
    FHoverWatch  : TTimer;
    procedure DoHoverWatch(Sender: TObject);
  protected
    // INTACodeEditorEvents — nur BeginPaint/EndPaint/PaintLine relevant.
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure EditorElided(const Editor: TWinControl; const LogicalLineNum: Integer);
    procedure EditorUnElided(const Editor: TWinControl; const LogicalLineNum: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseUp(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure EndPaint(const Editor: TWinControl);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
      const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
      const Context: INTACodeEditorPaintContext);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
      const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
      const Context: INTACodeEditorPaintContext);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function AllowedEvents: TCodeEditorEvents;
    function AllowedGutterStages: TPaintGutterStages;
    function AllowedLineStages: TPaintLineStages;
    function UIOptions: TCodeEditorUIOptions;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ResetState;  // Zustand leeren wenn Selektion aufgehoben wird
  end;

  TFindingHighlighter = class
  private
    FSelectedFile    : string;   // normalisiert (lower-case, '/' -> '\')
    FSelectedLine    : Integer;  // 1-basiert; 0 = nichts markiert
    FAnnotationTitle : string;
    FAnnotationDesc  : string;
    FAnnotationBadge : string;
    FEditorEvents    : INTACodeEditorEvents;  // haelt Refcount am Leben
    FEditorEventsObj : TFindingEditorEvents;  // Objekt-Ref fuer ResetState-Aufruf
    FEditorEventsIdx : Integer;               // Index aus AddEditorEventsNotifier; -1 = nicht registriert
    function NormalizePath(const APath: string): string;
    procedure InvalidateLine(ALine: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure SetSelected(const AFilePath: string; ALine: Integer;
      const ATitle: string = ''; const ADesc: string = '';
      const ABadge: string = '');
    procedure Clear;

    function HasSelection: Boolean;
    function IsSelectedFile(const AFileName: string): Boolean;
    function ShouldHighlight(const AFilePath: string; ALine: Integer): Boolean;
    function AnnotationTitle: string;
    function AnnotationDesc: string;
    function AnnotationBadge: string;
  end;

var
  GHighlighter : TFindingHighlighter = nil;

procedure RegisterLineHighlighter;
procedure UnregisterLineHighlighter;

implementation

const
  CL_HIGHLIGHT_BAR = TColor($000020D0);  // #D02000 – kraeftiges Rot
  STRIPE_WIDTH_PX  = 3;

{ ---- TFindingHighlighter ---- }

constructor TFindingHighlighter.Create;
begin
  inherited;
  FSelectedLine    := 0;
  FEditorEventsIdx := -1;
  FEditorEventsObj := TFindingEditorEvents.Create;
  FEditorEvents    := FEditorEventsObj as INTACodeEditorEvents;
end;

destructor TFindingHighlighter.Destroy;
begin
  FEditorEvents := nil;  // Refcount sinkt; nach RemoveEditorEventsNotifier (in UnregisterLineHighlighter) -> 0 -> Objekt freigegeben
  inherited;
end;

function TFindingHighlighter.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TFindingHighlighter.InvalidateLine(ALine: Integer);
var
  Svc: INTACodeEditorServices;
begin
  if ALine <= 0 then Exit;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      Svc.InvalidateTopEditorLogicalLine(ALine);
  except
  end;
end;

procedure TFindingHighlighter.SetSelected(const AFilePath: string;
  ALine: Integer; const ATitle: string; const ADesc: string;
  const ABadge: string);
var
  OldLine : Integer;
begin
  if (AFilePath = '') or (ALine <= 0) then
  begin
    Clear;
    Exit;
  end;
  // Overlay sofort verbergen — im Hover-Modus erscheint es erst wieder,
  // wenn die Maus die neue Zielzeile beruehrt.
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  OldLine          := FSelectedLine;
  FSelectedFile    := NormalizePath(AFilePath);
  FSelectedLine    := ALine;
  FAnnotationTitle := ATitle;
  FAnnotationDesc  := ADesc;
  FAnnotationBadge := ABadge;
  // Alte Zeile repainten (entfernt den Stripe), dann neue Zeile (zeigt Stripe + Overlay).
  if (OldLine > 0) and (OldLine <> ALine) then
    InvalidateLine(OldLine);
  InvalidateLine(ALine);
end;

procedure TFindingHighlighter.Clear;
var
  HadLine : Integer;
begin
  HadLine          := FSelectedLine;
  FSelectedFile    := '';
  FSelectedLine    := 0;
  FAnnotationTitle := '';
  FAnnotationDesc  := '';
  FAnnotationBadge := '';
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;
  InvalidateLine(HadLine);
end;

function TFindingHighlighter.HasSelection: Boolean;
begin
  Result := FSelectedLine > 0;
end;

function TFindingHighlighter.IsSelectedFile(const AFileName: string): Boolean;
begin
  Result := HasSelection and (NormalizePath(AFileName) = FSelectedFile);
end;

function TFindingHighlighter.ShouldHighlight(const AFilePath: string;
  ALine: Integer): Boolean;
begin
  Result := HasSelection and (FSelectedLine = ALine) and
            (NormalizePath(AFilePath) = FSelectedFile);
end;

function TFindingHighlighter.AnnotationTitle: string; begin Result := FAnnotationTitle; end;
function TFindingHighlighter.AnnotationDesc: string;  begin Result := FAnnotationDesc;  end;
function TFindingHighlighter.AnnotationBadge: string; begin Result := FAnnotationBadge; end;

{ ---- TFindingEditorEvents ---- }

constructor TFindingEditorEvents.Create;
begin
  inherited;
  FHoverWatch := TTimer.Create(nil);
  FHoverWatch.Interval := 200;
  FHoverWatch.Enabled  := False;
  FHoverWatch.OnTimer  := DoHoverWatch;
end;

destructor TFindingEditorEvents.Destroy;
begin
  FreeAndNil(FHoverWatch);
  inherited;
end;

procedure TFindingEditorEvents.ResetState;
begin
  FSelectedVisible := False;
  FSavedEditor     := nil;
  FSavedCodeRect   := Default(TRect);
  FSavedCharHeight := 0;
  if Assigned(FHoverWatch) then
    FHoverWatch.Enabled := False;
end;

procedure TFindingEditorEvents.DoHoverWatch(Sender: TObject);
var
  CursorPos : TPoint;
  EditorPt  : TPoint;
begin
  // Wenn keine markierte Zeile mehr da ist oder der Editor verschwunden ist,
  // Timer abschalten — kein Hover-Kontext mehr.
  if not FSelectedVisible or not Assigned(FSavedEditor) then
  begin
    FHoverWatch.Enabled := False;
    if Assigned(GAnnotationOverlay) then
      GAnnotationOverlay.HideOverlay;
    Exit;
  end;
  // Cursor-Position in Editor-Client-Koordinaten umrechnen und gegen den
  // gespeicherten CodeRect der markierten Zeile testen.
  if not GetCursorPos(CursorPos) then Exit;
  EditorPt := CursorPos;
  Winapi.Windows.ScreenToClient(FSavedEditor.Handle, EditorPt);
  if not PtInRect(FSavedCodeRect, EditorPt) then
  begin
    if Assigned(GAnnotationOverlay) then
      GAnnotationOverlay.HideOverlay;
    FHoverWatch.Enabled := False;
  end;
end;

function TFindingEditorEvents.AllowedEvents: TCodeEditorEvents;
begin
  // BeginPaint/EndPaint + PaintLine: Stripe zeichnen + Sichtbarkeits-Tracking.
  // cevMouseEvents: EditorMouseMove fuer Hover-Show/Hide des Overlays.
  // cevWindowEvents: EditorScrolled -> Overlay sofort ausblenden.
  // Hinweis: AllowedEvents wird von der IDE pro Event-Dispatch (mehrfach
  // pro Sekunde) aufgerufen — KEIN Logging hier, sonst flutet die Datei.
  Result := [cevBeginEndPaintEvents, cevPaintLineEvents,
             cevMouseEvents, cevWindowEvents];
end;

function TFindingEditorEvents.AllowedLineStages: TPaintLineStages;
begin
  // Nur Background-Stage: nach dem Default-Hintergrund unseren Stripe drauf.
  Result := [plsBackground];
end;

function TFindingEditorEvents.AllowedGutterStages: TPaintGutterStages;
begin
  Result := [];
end;

function TFindingEditorEvents.UIOptions: TCodeEditorUIOptions;
begin
  Result := [];
end;

// No-ops fuer nicht subskribierte Events
procedure TFindingEditorEvents.EditorResized(const Editor: TWinControl); begin end;
procedure TFindingEditorEvents.EditorElided(const Editor: TWinControl; const LogicalLineNum: Integer); begin end;
procedure TFindingEditorEvents.EditorUnElided(const Editor: TWinControl; const LogicalLineNum: Integer); begin end;
procedure TFindingEditorEvents.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer); begin end;
procedure TFindingEditorEvents.EditorMouseUp(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer); begin end;
procedure TFindingEditorEvents.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext); begin end;
procedure TFindingEditorEvents.PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string; const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext); begin end;

procedure TFindingEditorEvents.EditorScrolled(const Editor: TWinControl;
  const Direction: TCodeEditorScrollDirection);
begin
  // Beim Scroll Overlay sofort verbergen — die markierte Zeile wandert.
  // Nach dem Scroll feuert PaintLine erneut und FSavedCodeRect wird
  // aktualisiert; das naechste EditorMouseMove zeigt das Overlay neu.
  if Editor <> FSavedEditor then Exit;
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  if Assigned(FHoverWatch) then
    FHoverWatch.Enabled := False;
end;

procedure TFindingEditorEvents.EditorMouseMove(const Editor: TWinControl;
  Shift: TShiftState; X, Y: Integer);
var
  P             : TPoint;
  AWidth, LineH : Integer;
  Hit           : Boolean;
begin
  // Hot path: erst die billigsten Bailouts, dann Hit-Test, dann Show/Hide.
  if not Assigned(GAnnotationOverlay) or not Assigned(GHighlighter) then Exit;
  if not FSelectedVisible then Exit;          // Markierte Zeile aktuell nicht gemalt
  if Editor <> FSavedEditor then               // Maus in anderem Editor
  begin
    GAnnotationOverlay.HideOverlay;
    Exit;
  end;

  // X/Y sind Editor-Client-Koordinaten – gleiche Basis wie FSavedCodeRect.
  Hit := PtInRect(FSavedCodeRect, Point(X, Y));
  if Hit then
  begin
    // WS_CHILD-Modus: das Overlay erwartet Editor-Client-Koordinaten,
    // KEIN ClientToScreen mehr. Position = direkt unter der markierten
    // Zeile, X = Code-Bereich-Left, Y = Code-Bereich-Bottom.
    P.X := FSavedCodeRect.Left;
    P.Y := FSavedCodeRect.Bottom;
    AWidth := FSavedCodeRect.Right - FSavedCodeRect.Left;
    if AWidth < 200 then AWidth := 200;
    LineH := FSavedCharHeight;
    if LineH < 16 then LineH := 20;  // Fallback wenn CharHeight nicht gesetzt
    try
      GAnnotationOverlay.ShowAt(FSavedEditor, P.X, P.Y, AWidth, LineH,
        GHighlighter.AnnotationTitle,
        GHighlighter.AnnotationDesc,
        GHighlighter.AnnotationBadge);
      // Hide-on-mouse-leave Timer aktivieren: Pollt alle 200ms ob die
      // Maus noch ueber der markierten Zeile ist (auch wenn EditorMouseMove
      // nicht mehr feuert, weil Maus ausserhalb des Editors).
      FHoverWatch.Enabled := True;
    except
    end;
  end
  else
  begin
    GAnnotationOverlay.HideOverlay;
    FHoverWatch.Enabled := False;
  end;
end;

procedure TFindingEditorEvents.BeginPaint(const Editor: TWinControl;
  const ForceFullRepaint: Boolean);
begin
  // WICHTIG: Visible NUR bei ForceFullRepaint zuruecksetzen!
  //
  // Caret-Blink + jeder MouseMove triggern partielle Repaints
  // (ForceFullRepaint=False) bei denen PaintLine NICHT fuer unsere Zeile
  // gerufen wird (nur der Caret-Bereich wird neu gemalt). Wuerden wir hier
  // unbedingt zuruecksetzen, bliebe FSelectedVisible dauerhaft False, weil
  // der naechste PaintLine fuer die Zeile erst beim naechsten Full-Repaint
  // kommt. Die Hover-Erkennung wuerde nie greifen.
  //
  // Bei partiellen Repaints bleibt die markierte Zeile sichtbar auf dem
  // Bildschirm — also bleibt der Hover-Anker gueltig.
  if (Editor = FSavedEditor) and ForceFullRepaint then
    FSelectedVisible := False;
end;

procedure TFindingEditorEvents.PaintLine(const Rect: TRect;
  const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  SR : TRect;
begin
  if not Assigned(GHighlighter) then Exit;
  if not Assigned(Context) or not Assigned(Context.EditControl) then Exit;
  // AllowedLineStages = [plsBackground] -> Stage ist immer plsBackground hier.
  // BeforeEvent=False: Default-Hintergrund bereits gemalt, Stripe drueber legen.
  if BeforeEvent then Exit;
  if not GHighlighter.ShouldHighlight(Context.FileName, Context.LogicalLineNum) then Exit;

  FSavedEditor     := Context.EditControl;
  FSelectedVisible := True;
  FSavedCodeRect   := Context.LineState.CodeRect;
  // CharHeight fuer DPI-bewusstes Overlay-Sizing in EditorMouseMove verwenden.
  FSavedCharHeight := Context.EditorState.CharHeight;

  // 3px roter Stripe am linken Rand des Code-Bereichs.
  // Hinweis: Parameter 'Rect' verdeckt Winapi.Windows.Rect, deshalb SR direkt nutzen.
  SR := FSavedCodeRect;
  SR.Right := SR.Left + STRIPE_WIDTH_PX;
  Context.Canvas.Brush.Color := CL_HIGHLIGHT_BAR;
  Context.Canvas.Brush.Style := bsSolid;
  Context.Canvas.FillRect(SR);
end;

procedure TFindingEditorEvents.EndPaint(const Editor: TWinControl);
begin
  // Hover-Modus: Das Overlay wird in EditorMouseMove gezeigt, nicht hier.
  // EndPaint dient nur zum *Verbergen* — wenn die markierte Zeile aus dem
  // Sichtbereich gescrollt oder durch Editieren entfernt wurde, hat
  // BeginPaint FSelectedVisible auf False zurueckgesetzt und PaintLine wurde
  // fuer diese Zeile NICHT aufgerufen. Dann kein gueltiger Hover-Anker mehr.
  if not Assigned(GAnnotationOverlay) then Exit;
  if Editor <> FSavedEditor then Exit;
  if not FSelectedVisible then
    GAnnotationOverlay.HideOverlay;
end;

{ ---- Register/Unregister ---- }

procedure RegisterLineHighlighter;
var
  Svc: INTACodeEditorServices;
begin
  if Assigned(GHighlighter) then Exit;
  GHighlighter := TFindingHighlighter.Create;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      GHighlighter.FEditorEventsIdx :=
        Svc.AddEditorEventsNotifier(GHighlighter.FEditorEvents);
  except
  end;
end;

procedure UnregisterLineHighlighter;
var
  Svc: INTACodeEditorServices;
begin
  if not Assigned(GHighlighter) then Exit;
  try
    if (GHighlighter.FEditorEventsIdx >= 0) and
       Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      Svc.RemoveEditorEventsNotifier(GHighlighter.FEditorEventsIdx);
  except
  end;
  // Nach RemoveEditorEventsNotifier: IDE hat ihre Ref freigegeben.
  // FreeAndNil loest den Destructor aus der FEditorEvents := nil setzt ->
  // Refcount sinkt auf 0 -> TFindingEditorEvents wird automatisch freigegeben.
  FreeAndNil(GHighlighter);
end;

end.
