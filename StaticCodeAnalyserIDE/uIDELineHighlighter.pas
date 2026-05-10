unit uIDELineHighlighter;

// Editor-Line-Highlight und Annotation-Overlay via INTACodeEditorEvents
// (kanonische ToolsAPI.Editor-Loesung fuer RAD Studio 12+).
//
// MULTI-MARKER-MODELL:
//   Klick auf einen Befund im Findings-Panel markiert ALLE Befunde der
//   gleichen Datei mit einem roten Stripe. Hover ueber jeden einzelnen
//   Marker zeigt den jeweiligen Annotation-Hint (Title/Desc/Badge).
//   Nur die "aktive Datei" hat Markierungen — Klick auf einen Befund in
//   einer anderen Datei laesst die alten Marker verschwinden und markiert
//   die neue Datei komplett.
//
// ARCHITEKTUR:
//   TFindingEditorEvents  – implementiert INTACodeEditorEvents. Wird einmalig
//                           global ueber INTACodeEditorServices registriert
//                           und empfaengt Paint-Callbacks fuer ALLE Views.
//                           Haelt FRenderedRects (Line -> CodeRect) als
//                           Hit-Test-Cache fuer Hover.
//
//   TFindingHighlighter   – Singleton (GHighlighter). Haelt die aktive Datei
//                           und FMarks (TDictionary<Line, TFindingMark>).
//                           SetActiveFile aktualisiert den Zustand und loest
//                           per InvalidateTopEditorLogicalLine einen gezielten
//                           Repaint aller markierten Zeilen aus.
//
// PAINT-ZYKLUS (pro Editor):
//   BeginPaint  -> FRenderedRects leeren NUR bei ForceFullRepaint
//                  (partielle Repaints wie Caret-Blink wuerden sonst den
//                  Hit-Test-Cache zerstoeren).
//   PaintLine   -> Nur Stage=plsBackground, BeforeEvent=False.
//                  Trifft eine markierte Zeile: Stripe zeichnen, CodeRect
//                  in FRenderedRects[Line] speichern.
//   EndPaint    -> Verbirgt das Overlay wenn nach einem Full-Repaint keine
//                  Marker mehr sichtbar sind (alle aus dem Sichtbereich
//                  gescrollt). Zeigt das Overlay NICHT proaktiv.
//
// HOVER-MODUS:
//   SetActiveFile setzt nur den Markierungszustand (rote Stripes). Die
//   Overlays erscheinen erst wenn die Maus ueber EINE der markierten
//   Zeilen schwebt. EditorMouseMove macht Hit-Test gegen alle Eintraege
//   in FRenderedRects und zeigt den Hint fuer die getroffene Zeile.
//   FHoveredLine cached die zuletzt angezeigte Zeile, damit Mouse-Move
//   innerhalb derselben Zeile keine ShowAt-Calls triggert.
//   Voraussetzung: cevMouseEvents + cevWindowEvents in AllowedEvents.
//
// HIDE-ON-MOUSE-LEAVE (TTimer in TFindingEditorEvents):
//   Sobald die Maus den Editor verlaesst, feuert EditorMouseMove nicht mehr.
//   Der Timer pollt alle 200ms GetCursorPos und versteckt das Overlay wenn
//   der Cursor nicht mehr ueber EINER der markierten Zeilen ist.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  System.Generics.Collections,
  Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls,
  ToolsAPI, ToolsAPI.Editor,
  uMethodd12,
  uIDEAnnotationOverlay;

type
  TFindingHighlighter = class;  // forward

  // Pro Befund-Eintrag in einer Datei: Annotation-Texte + Stripe-Farbe.
  // Die Zeilennummer ist der TDictionary-Key (nicht im Record selbst).
  TFindingMark = record
    Title : string;
    Desc  : string;
    Badge : string;
    Color : TColor;   // Stripe-Farbe (Severity-abhaengig)
  end;
  // Eintrag fuer SetActiveFile — kombiniert Zeilennummer + Mark-Daten.
  TFindingMarkEntry = record
    Line  : Integer;
    Title : string;
    Desc  : string;
    Badge : string;
    Color : TColor;
  end;

  // WICHTIG: Basisklasse TNotifierObject, NUR INTACodeEditorEvents listen.
  TFindingEditorEvents = class(TNotifierObject, INTACodeEditorEvents)
  private
    // Editor der zuletzt markierte Zeilen gemalt hat — nur dieser Editor
    // bekommt Hover-Behandlung. (Andere Editoren werden ignoriert.)
    FSavedEditor     : TWinControl;
    FSavedCharHeight : Integer;      // DPI-aware Zeilenhoehe aus Context.EditorState
    // Pro markierter Zeile der zuletzt gerenderte CodeRect (Editor-Client-
    // Koordinaten). Wird in BeginPaint geleert (nur bei ForceFullRepaint),
    // in PaintLine fuer jede markierte Zeile aktualisiert.
    FRenderedRects   : TDictionary<Integer, TRect>;
    // Hide-on-mouse-leave Timer: alle 200ms pruefen ob Cursor noch ueber
    // EINER der markierten Zeilen ist — sonst Overlay verbergen. Notwendig
    // weil EditorMouseMove nicht mehr feuert sobald die Maus den Editor
    // verlaesst (Hover-UX bei topmost-Overlay).
    FHoverWatch    : TTimer;
    // Aktuell im Overlay angezeigte Zeile, um redundante ShowAt-Calls zu
    // vermeiden wenn die Maus innerhalb derselben Zeile bewegt wird.
    FHoveredLine   : Integer;
    // Throttle fuer den HitMiss-Refresh (siehe EditorMouseMove). Verhindert
    // dass jeder MouseMove ein InvalidateAllLines triggert wenn die Maus
    // im Editor aber NICHT auf einer markierten Zeile ist.
    FLastInvalidateTick : DWORD;
    procedure DoHoverWatch(Sender: TObject);
    // Findet welche markierte Zeile die Maus aktuell trifft. Liefert -1
    // wenn keine Zeile getroffen wird.
    function HitTestLine(X, Y: Integer): Integer;
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
    // Aktive Datei: alle Markierungen beziehen sich auf diese Datei.
    // Pfad ist normalisiert (lower-case, '/' -> '\').
    FActiveFile      : string;
    // Alle Markierungen der aktiven Datei: Line -> Annotation-Texte.
    // Lookup ist O(1), erlaubt beliebig viele Markierungen pro Datei.
    FMarks           : TDictionary<Integer, TFindingMark>;
    FEditorEvents    : INTACodeEditorEvents;  // haelt Refcount am Leben
    FEditorEventsObj : TFindingEditorEvents;
    FEditorEventsIdx : Integer;               // Index aus AddEditorEventsNotifier; -1 = nicht registriert
    function NormalizePath(const APath: string): string;
  public
    // PUBLIC fuer TFindingEditorEvents — forciert Repaint aller markierten
    // Zeilen via InvalidateTopEditorLogicalLine. Wird in EditorScrolled
    // gerufen damit FRenderedRects nach dem Scroll wieder vollstaendig ist.
    procedure InvalidateAllLines;
    constructor Create;
    destructor Destroy; override;

    // Setzt die Liste aller Markierungen fuer eine Datei. Vorheriger Zustand
    // (ggf. andere Datei mit anderen Marks) wird komplett ersetzt.
    procedure SetActiveFile(const AFilePath: string;
      const AEntries: array of TFindingMarkEntry);
    procedure Clear;

    function HasMarks: Boolean;
    function IsActiveFile(const AFileName: string): Boolean;
    function ShouldHighlight(const AFilePath: string; ALine: Integer): Boolean;
    // Liefert die Annotation-Texte fuer eine markierte Zeile. False wenn Zeile
    // nicht markiert ist.
    function TryGetMark(ALine: Integer; out AMark: TFindingMark): Boolean;
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
  FMarks           := TDictionary<Integer, TFindingMark>.Create;
  FEditorEventsIdx := -1;
  FEditorEventsObj := TFindingEditorEvents.Create;
  FEditorEvents    := FEditorEventsObj as INTACodeEditorEvents;
end;

destructor TFindingHighlighter.Destroy;
begin
  FEditorEvents := nil;  // Refcount sinkt; nach RemoveEditorEventsNotifier (in UnregisterLineHighlighter) -> 0 -> Objekt freigegeben
  FreeAndNil(FMarks);
  inherited;
end;

function TFindingHighlighter.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TFindingHighlighter.InvalidateAllLines;
var
  Svc : INTACodeEditorServices;
  Ln  : Integer;
begin
  // Forciert Repaint aller markierten Zeilen — wird beim Datei-Wechsel oder
  // Clear gerufen damit die alten Stripes verschwinden.
  if FMarks.Count = 0 then Exit;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      for Ln in FMarks.Keys do
        Svc.InvalidateTopEditorLogicalLine(Ln);
  except
  end;
end;

procedure TFindingHighlighter.SetActiveFile(const AFilePath: string;
  const AEntries: array of TFindingMarkEntry);
var
  i    : Integer;
  Mark : TFindingMark;
begin
  if (AFilePath = '') or (Length(AEntries) = 0) then
  begin
    Clear;
    Exit;
  end;
  // Overlay sofort verbergen — im Hover-Modus erscheint es erst wieder,
  // wenn die Maus eine markierte Zeile beruehrt.
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;

  // Alte Markierungen invalidieren BEVOR die neue Liste gesetzt wird,
  // damit die alten Stripes weggemalt werden.
  InvalidateAllLines;

  FActiveFile := NormalizePath(AFilePath);
  FMarks.Clear;
  for i := 0 to High(AEntries) do
  begin
    if AEntries[i].Line <= 0 then Continue;
    Mark.Title := AEntries[i].Title;
    Mark.Desc  := AEntries[i].Desc;
    Mark.Badge := AEntries[i].Badge;
    Mark.Color := AEntries[i].Color;
    // Bei doppelten Zeilen: spaeterer Eintrag gewinnt (AddOrSetValue).
    FMarks.AddOrSetValue(AEntries[i].Line, Mark);
  end;

  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;

  // Neue Markierungen einmal repainten damit Stripes erscheinen.
  InvalidateAllLines;
end;

procedure TFindingHighlighter.Clear;
begin
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;
  InvalidateAllLines;
  FActiveFile := '';
  FMarks.Clear;
end;

function TFindingHighlighter.HasMarks: Boolean;
begin
  Result := FMarks.Count > 0;
end;

function TFindingHighlighter.IsActiveFile(const AFileName: string): Boolean;
begin
  Result := HasMarks and (NormalizePath(AFileName) = FActiveFile);
end;

function TFindingHighlighter.ShouldHighlight(const AFilePath: string;
  ALine: Integer): Boolean;
begin
  Result := HasMarks and FMarks.ContainsKey(ALine) and
            (NormalizePath(AFilePath) = FActiveFile);
end;

function TFindingHighlighter.TryGetMark(ALine: Integer;
  out AMark: TFindingMark): Boolean;
begin
  Result := FMarks.TryGetValue(ALine, AMark);
end;

{ ---- TFindingEditorEvents ---- }

constructor TFindingEditorEvents.Create;
begin
  inherited;
  FRenderedRects := TDictionary<Integer, TRect>.Create;
  FHoverWatch := TTimer.Create(nil);
  FHoverWatch.Interval := 200;
  FHoverWatch.Enabled  := False;
  FHoverWatch.OnTimer  := DoHoverWatch;
  FHoveredLine := -1;
end;

destructor TFindingEditorEvents.Destroy;
begin
  FreeAndNil(FHoverWatch);
  FreeAndNil(FRenderedRects);
  inherited;
end;

procedure TFindingEditorEvents.ResetState;
begin
  FSavedEditor     := nil;
  FSavedCharHeight := 0;
  FHoveredLine     := -1;
  if Assigned(FRenderedRects) then
    FRenderedRects.Clear;
  if Assigned(FHoverWatch) then
    FHoverWatch.Enabled := False;
end;

function TFindingEditorEvents.HitTestLine(X, Y: Integer): Integer;
var
  Pair : TPair<Integer, TRect>;
begin
  // Lineare Suche durch alle aktuell gerenderten Marker-Rects.
  // FRenderedRects.Count ist <= sichtbare-Zeilen-mit-Marker, typisch < 20.
  for Pair in FRenderedRects do
    if PtInRect(Pair.Value, Point(X, Y)) then
      Exit(Pair.Key);
  Result := -1;
end;

procedure TFindingEditorEvents.DoHoverWatch(Sender: TObject);
var
  CursorPos : TPoint;
  EditorPt  : TPoint;
begin
  // Wenn keine Marker mehr gerendert sind oder der Editor verschwunden ist,
  // Timer abschalten — kein Hover-Kontext mehr.
  if (FRenderedRects.Count = 0) or not Assigned(FSavedEditor) then
  begin
    FHoverWatch.Enabled := False;
    FHoveredLine := -1;
    if Assigned(GAnnotationOverlay) then
      GAnnotationOverlay.HideOverlay;
    Exit;
  end;
  // Cursor-Position in Editor-Client-Koordinaten umrechnen und gegen ALLE
  // gerenderten Marker-Rects testen.
  if not GetCursorPos(CursorPos) then Exit;
  EditorPt := CursorPos;
  Winapi.Windows.ScreenToClient(FSavedEditor.Handle, EditorPt);
  if HitTestLine(EditorPt.X, EditorPt.Y) < 0 then
  begin
    if Assigned(GAnnotationOverlay) then
      GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
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
  // Beim Scroll wandern alle markierten Zeilen — gespeicherte Rects sind
  // sofort veraltet. Cache leeren, Overlay verbergen.
  if Editor <> FSavedEditor then Exit;
  FRenderedRects.Clear;
  FHoveredLine := -1;
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  if Assigned(FHoverWatch) then
    FHoverWatch.Enabled := False;
  // KRITISCH fuer Hover nach Scroll: Markierte Zeilen explizit re-invalidieren
  // damit PaintLine sie neu malt und FRenderedRects beim naechsten
  // EditorMouseMove vollstaendig ist. Sonst trifft der Hit-Test eine vom
  // Editor schon gerenderte aber bei uns nicht mehr gecachte Zeile nicht
  // — das Hover-Overlay erscheint dann nicht.
  if Assigned(GHighlighter) then
    GHighlighter.InvalidateAllLines;
end;

procedure TFindingEditorEvents.EditorMouseMove(const Editor: TWinControl;
  Shift: TShiftState; X, Y: Integer);
var
  P             : TPoint;
  AWidth, LineH : Integer;
  HitLine       : Integer;
  Mark          : TFindingMark;
  HitRect       : TRect;
begin
  // Hot path: erst die billigsten Bailouts, dann Hit-Test, dann Show/Hide.
  if not Assigned(GAnnotationOverlay) or not Assigned(GHighlighter) then Exit;
  if FRenderedRects.Count = 0 then Exit;       // Aktuell nichts gerendert
  if Editor <> FSavedEditor then               // Maus in anderem Editor
  begin
    GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
    Exit;
  end;

  // Hit-Test gegen alle gerenderten Marker-Rects.
  HitLine := HitTestLine(X, Y);
  if HitLine < 0 then
  begin
    GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
    FHoverWatch.Enabled := False;
    // STALE-CACHE-WORKAROUND: Wenn wir Marks haben aber FRenderedRects
    // weniger Eintraege als FMarks hat, koennten Rects fuer sichtbare
    // Marker fehlen (passiert nach Wheel-Scroll bei dem EditorScrolled
    // nicht zuverlaessig feuert). Re-Invalidate forciert PaintLine, damit
    // FRenderedRects beim naechsten MouseMove vollstaendig ist.
    // Throttling: max alle 500ms, sonst Repaint-Loop.
    if Assigned(GHighlighter) and GHighlighter.HasMarks
       and (GetTickCount - FLastInvalidateTick > 500) then
    begin
      FLastInvalidateTick := GetTickCount;
      GHighlighter.InvalidateAllLines;
    end;
    Exit;
  end;

  // Schon dieselbe Zeile UND Overlay sichtbar -> nichts zu tun (Cache hit
  // vermeidet redundante ShowAt-Calls bei Mausbewegung INNERHALB der Zeile).
  // Wichtig: nur wenn Overlay tatsaechlich sichtbar ist, sonst wuerden wir
  // verpassen es zu re-zeigen wenn es zwischendurch versteckt wurde
  // (Window-Deactivate, Hide-on-Mouse-Leave, Editor-Repaint, ...).
  if (HitLine = FHoveredLine) and GAnnotationOverlay.Visible then
  begin
    FHoverWatch.Enabled := True;
    Exit;
  end;

  // Annotation-Texte fuer die getroffene Zeile holen.
  if not GHighlighter.TryGetMark(HitLine, Mark) then Exit;
  if not FRenderedRects.TryGetValue(HitLine, HitRect) then Exit;

  // WS_CHILD-Modus: Position = Editor-Client-Koordinaten direkt unter
  // der markierten Zeile.
  P.X := HitRect.Left;
  P.Y := HitRect.Bottom;
  AWidth := HitRect.Right - HitRect.Left;
  if AWidth < 200 then AWidth := 200;
  LineH := FSavedCharHeight;
  if LineH < 16 then LineH := 20;  // Fallback wenn CharHeight nicht gesetzt
  try
    GAnnotationOverlay.ShowAt(FSavedEditor, P.X, P.Y, AWidth, LineH,
      Mark.Title, Mark.Desc, Mark.Badge, Mark.Color);
    FHoveredLine := HitLine;
    // Hide-on-mouse-leave Timer aktivieren.
    FHoverWatch.Enabled := True;
  except
  end;
end;

procedure TFindingEditorEvents.BeginPaint(const Editor: TWinControl;
  const ForceFullRepaint: Boolean);
begin
  // WICHTIG: FRenderedRects NUR bei ForceFullRepaint leeren!
  //
  // Caret-Blink + jeder MouseMove triggern partielle Repaints
  // (ForceFullRepaint=False) bei denen PaintLine NICHT fuer alle markierten
  // Zeilen gerufen wird (nur der Caret-Bereich wird neu gemalt). Wuerden
  // wir hier unbedingt leeren, bliebe der Hit-Test-Cache leer und Hover
  // wuerde nicht greifen.
  //
  // Bei partiellen Repaints bleiben die markierten Zeilen sichtbar auf
  // dem Bildschirm — also bleiben die gespeicherten Rects gueltig.
  if (Editor = FSavedEditor) and ForceFullRepaint then
    FRenderedRects.Clear;
end;

procedure TFindingEditorEvents.PaintLine(const Rect: TRect;
  const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  SR        : TRect;
  CodeRect  : TRect;
  Line      : Integer;
  Mark      : TFindingMark;
  StripeCol : TColor;
begin
  if not Assigned(GHighlighter) then Exit;
  if not Assigned(Context) or not Assigned(Context.EditControl) then Exit;
  // AllowedLineStages = [plsBackground] -> Stage ist immer plsBackground hier.
  // BeforeEvent=False: Default-Hintergrund bereits gemalt, Stripe drueber legen.
  if BeforeEvent then Exit;
  Line := Context.LogicalLineNum;
  if not GHighlighter.ShouldHighlight(Context.FileName, Line) then Exit;

  FSavedEditor     := Context.EditControl;
  CodeRect         := Context.LineState.CodeRect;
  // CharHeight fuer DPI-bewusstes Overlay-Sizing in EditorMouseMove verwenden.
  FSavedCharHeight := Context.EditorState.CharHeight;
  // Rect cachen damit EditorMouseMove pro Zeile den Hit-Test machen kann.
  FRenderedRects.AddOrSetValue(Line, CodeRect);

  // Stripe-Farbe aus dem Mark holen (Severity-abhaengig: Error/Warning/Hint).
  // Fallback auf Default-Rot falls clNone uebergeben wurde.
  StripeCol := CL_HIGHLIGHT_BAR;
  if GHighlighter.TryGetMark(Line, Mark) and (Mark.Color <> clNone) then
    StripeCol := Mark.Color;

  // 3px Stripe am linken Rand des Code-Bereichs.
  // Hinweis: Parameter 'Rect' verdeckt Winapi.Windows.Rect, deshalb SR direkt nutzen.
  SR := CodeRect;
  SR.Right := SR.Left + STRIPE_WIDTH_PX;
  Context.Canvas.Brush.Color := StripeCol;
  Context.Canvas.Brush.Style := bsSolid;
  Context.Canvas.FillRect(SR);
end;

procedure TFindingEditorEvents.EndPaint(const Editor: TWinControl);
begin
  // Bei Full-Repaint (BeginPaint hat FRenderedRects geleert) wurden alle
  // tatsaechlich sichtbaren markierten Zeilen via PaintLine wieder
  // hinzugefuegt. Wenn FRenderedRects danach leer ist, gibt es keine
  // sichtbaren Marker mehr -> Overlay verbergen.
  if not Assigned(GAnnotationOverlay) then Exit;
  if Editor <> FSavedEditor then Exit;
  if FRenderedRects.Count = 0 then
  begin
    GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
  end;
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
