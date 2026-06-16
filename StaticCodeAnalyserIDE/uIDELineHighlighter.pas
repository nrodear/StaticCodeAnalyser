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
//   TFindingHighlighter   – Singleton (GHighlighter). Haelt die Marker
//                           ALLER Dateien gleichzeitig in einem
//                           FMarksByFile: TObjectDictionary<NormalizedPath,
//                           TDictionary<Line, TFindingMark>>. SetAllFindings
//                           ersetzt den gesamten Zustand atomar und loest
//                           per InvalidateTopEditorLogicalLine einen
//                           gezielten Repaint aller markierten Zeilen aus.
//                           PaintLine dispatcht ueber Context.FileName,
//                           damit der User beim Tab-Wechsel die Befunde
//                           der neuen Datei sieht ohne weiteren API-Call.
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
//   SetAllFindings setzt nur den Markierungszustand (rote Stripes). Die
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
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls,
  ToolsAPI, ToolsAPI.Editor,
  uMethodd12, uAnalyserTypes, uLocalization,
  uIDEAnnotationOverlay;

type
  TFindingHighlighter = class;  // forward

  // Pro Befund-Eintrag in einer Datei: Annotation-Texte + Stripe-Farbe.
  // Die Zeilennummer ist der TDictionary-Key (nicht im Record selbst).
  // Wenn mehrere Befunde auf der gleichen Zeile liegen, wird in
  // TFindingHighlighter.SetAllFindings ein Summary-Mark synthetisiert
  // (IsMulti=True, Desc als Bullet-Liste staerkste->schwaechste, Fix
  // unterdrueckt, Color/Badge/Severity = staerkster Eintrag).
  TFindingMark = record
    Title    : string;
    Desc     : string;
    Badge    : string;
    Color    : TColor;          // Stripe-Farbe (staerkste Severity)
    Fix      : string;          // After-Code (leer im Multi-Mode)
    Severity : TFindingSeverity;// fuer Stripe-Ranking
    IsMulti  : Boolean;         // True = synthetisierter Multi-Summary
  end;
  // Eintrag fuer SetAllFindings — die FileName-Property machte den
  // vorher impliziten "alle Eintraege gehoeren zur gleichen Datei"-
  // Vertrag explizit. Damit kann ein einziger SetAllFindings-Call
  // Marker fuer beliebig viele Dateien gleichzeitig setzen.
  // Severity wird vom Aufrufer gesetzt und steuert in der internen
  // Multi-Mark-Synthese die Reihenfolge (staerkste zuerst) und die
  // Stripe-Farbe der Summary-Markierung.
  TFindingMarkEntry = record
    FileName : string;
    Line     : Integer;
    Title    : string;
    Desc     : string;
    Badge    : string;
    Color    : TColor;
    Fix      : string;
    Severity : TFindingSeverity;
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
    // Pro markierter Zeile die X-Pixel-Koordinate (Editor-Client-System) wo
    // der sichtbare Code-Text endet. Aus LineState.VisibleTextRect.Right
    // in PaintLine. Wird im 'sameline'-OverlayPosition-Modus genutzt um die
    // Title-Bar direkt rechts neben dem Code zu platzieren. Fuer Zeilen
    // ohne Eintrag faellt EditorMouseMove auf CodeRect.Left + Fallback zurueck.
    FRenderedTextEnds : TDictionary<Integer, Integer>;
    // Hide-on-mouse-leave Timer: alle 200ms pruefen ob Cursor noch ueber
    // EINER der markierten Zeilen ist — sonst Overlay verbergen. Notwendig
    // weil EditorMouseMove nicht mehr feuert sobald die Maus den Editor
    // verlaesst (Hover-UX bei topmost-Overlay).
    FHoverWatch    : TTimer;
    // Aktuell im Overlay angezeigte Zeile, um redundante ShowAt-Calls zu
    // vermeiden wenn die Maus innerhalb derselben Zeile bewegt wird.
    FHoveredLine   : Integer;
    // Pfad der zuletzt von PaintLine gemalten Datei. Notwendig fuer den
    // Tab-Switch-Detection-Pfad: wenn der User auf einen anderen Editor-Tab
    // wechselt, feuert PaintLine fuer den neuen Pfad. Differenz zu
    // FLastPaintedFile -> FRenderedRects (Hit-Test-Daten der alten Datei)
    // sind stale und muessen vor dem ersten Mouse-Move geleert werden,
    // sonst zeigt das Hover-Overlay den Befund der vorigen Datei auf einer
    // unrelated Zeile der neuen Datei.
    FLastPaintedFile : string;
    // Throttle fuer den HitMiss-Refresh (siehe EditorMouseMove). Verhindert
    // dass jeder MouseMove ein InvalidateAllLines triggert wenn die Maus
    // im Editor aber NICHT auf einer markierten Zeile ist.
    FLastInvalidateTick : DWORD;
    procedure DoHoverWatch(Sender: TObject);
    // Findet welche markierte Zeile die Maus aktuell trifft. Liefert -1
    // wenn keine Zeile getroffen wird.
    function HitTestLine(X, Y: Integer): Integer;
    // Berechnet Geometrie + ruft GAnnotationOverlay.ShowAt fuer eine
    // bestimmte markierte Zeile. Wird vom Hover-Pfad (EditorMouseMove,
    // wenn die User-Option ShowOnHover aktiv ist) UND vom Click-Pfad
    // (EditorMouseDown, immer wenn der User auf eine markierte Zeile
    // klickt) genutzt. Setzt FHoveredLine + FHoverWatch-Timer.
    procedure ShowOverlayForLine(AHitLine: Integer);
    // Settings frisch lesen (analog IsAutoExpandEnabled im Overlay). Damit
    // wirkt ein Toggle in Tools > Options sofort, ohne Plugin-Reload.
    function IsShowOnHoverEnabled: Boolean;
    // True wenn der Cursor (Screen-Koordinaten) gerade ueber dem
    // GAnnotationOverlay-Fenster steht. Wird vor jedem HideOverlay-Aufruf
    // gefragt - sonst koennte der User den Close-[x]-Button nicht klicken,
    // weil das Overlay beim Mouse-Leave der Codezeile sofort verschwindet,
    // BEVOR die Maus den Overlay-Bereich erreicht.
    function IsCursorOverOverlay: Boolean;
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

  // Marker einer einzelnen Datei: Line -> Mark-Daten.
  TFileMarks = TDictionary<Integer, TFindingMark>;

  // Per-File-Slot fuer den Save-Auto-Clear-Notifier. IOTAModule + Cookie
  // werden beim Detach gebraucht; den Notifier selbst halten wir als
  // strong ref am Leben (der Cookie alleine reicht nicht, ohne ref wuerde
  // der TNotifierObject-Refcount auf 0 sinken und das Objekt freigegeben).
  TSaveNotifierSlot = record
    Module    : IOTAModule;
    Notifier  : IOTAModuleNotifier;
    Cookie    : Integer;
  end;

  TFindingHighlighter = class
  private
    // Multi-File-Marker-Storage: normalisierter Pfad -> TFileMarks.
    // Vorher: FActiveFile + FMarks (genau eine Datei). Jetzt traegt der
    // Highlighter Markierungen fuer beliebig viele Dateien gleichzeitig,
    // so dass der User beim Tab-Wechsel sofort die Befunde der neuen
    // Datei sieht ohne dass irgendwer SetActiveFile aufrufen muss.
    FMarksByFile     : TObjectDictionary<string, TFileMarks>;
    // Save-Auto-Clear: pro markierter Datei wird ein IOTAModuleNotifier
    // angehaengt der bei AfterSave die Marker dieser Datei loescht
    // (User hat editiert -> Zeilen-Nummern stimmen nicht mehr).
    // Key ist NormalizePath(filename); leerer Slot = keine Datei dieses
    // Namens aktuell im Editor offen (Attach scheitert dann still).
    FSaveNotifiers   : TDictionary<string, TSaveNotifierSlot>;
    FEditorEvents    : INTACodeEditorEvents;  // haelt Refcount am Leben
    FEditorEventsObj : TFindingEditorEvents;   // Refcount via FEditorEvents (siehe Create)
    FEditorEventsIdx : Integer;               // Index aus AddEditorEventsNotifier; -1 = nicht registriert
    function NormalizePath(const APath: string): string;
    // Save-Notifier-Verwaltung. Attach scheitert still wenn die Datei
    // (noch) nicht als IOTAModule offen ist - das ist OK, beim naechsten
    // Editor-Open kommt SetAllFindings ja sowieso erneut.
    procedure AttachSaveNotifier(const AKey: string);
    procedure DetachSaveNotifier(const AKey: string);
    procedure DetachAllSaveNotifiers;
  public
    // PUBLIC fuer TFindingEditorEvents — forciert Repaint aller markierten
    // Zeilen via InvalidateTopEditorLogicalLine. Wird in EditorScrolled
    // gerufen damit FRenderedRects nach dem Scroll wieder vollstaendig ist.
    procedure InvalidateAllLines;
    constructor Create;
    destructor Destroy; override;

    // Setzt die komplette Marker-Liste fuer ALLE Dateien atomar. Eintraege
    // werden intern nach FileName gruppiert; ein einziger Aufruf reicht
    // pro Analyse-Run / Filter-Wechsel. AEntries[i].FileName muss gesetzt
    // sein (leerer FileName -> Eintrag wird geskippt).
    procedure SetAllFindings(const AEntries: array of TFindingMarkEntry);
    // Pro-File-Variante: ERSETZT NUR die Marker fuer AFileName, alle
    // anderen Dateien bleiben unangetastet. Wird vom Silent-Scan-Pfad
    // (Auto-Scan bei Tab-Wechsel, Reload-Button) genutzt - sonst wuerde
    // jeder Single-File-Scan die Marker aller anderen Dateien wegfegen.
    // Wenn AEntries leer ist, wird der File-Eintrag in FMarksByFile
    // entfernt (= dieselbe Wirkung wie ClearFile).
    procedure ReplaceMarksForFile(const AFileName: string;
      const AEntries: array of TFindingMarkEntry);
    procedure Clear;

    // Loescht alle Marker fuer EINE Datei. Wird vom Save-Auto-Clear
    // gerufen (Edit+Save invalidiert Zeilen-Nummern). Idempotent;
    // unbekannte Datei = no-op. Triggert Repaint im sichtbaren Editor.
    procedure ClearFile(const AFileName: string);

    // Loescht einen einzelnen Marker (Datei + Zeile). Wird vom [x]-Button
    // im Hover-Overlay gerufen (User dismissed eine spezifische Markierung).
    // Idempotent; unbekannte Datei/Zeile = no-op. Triggert Repaint.
    procedure RemoveMark(const AFileName: string; ALineNo: Integer);

    // True wenn IRGENDEINE Datei Marker hat.
    function HasMarks: Boolean;
    // True wenn die spezifische Datei (normalisierter Pfad-Vergleich)
    // mindestens einen Marker hat.
    function HasMarksForFile(const AFileName: string): Boolean;
    function ShouldHighlight(const AFilePath: string; ALine: Integer): Boolean;
    // Liefert die Annotation-Texte fuer eine markierte Zeile in einer
    // bestimmten Datei. False wenn die Datei keine Marks hat oder die
    // Zeile nicht markiert ist.
    function TryGetMark(const AFile: string; ALine: Integer;
                        out AMark: TFindingMark): Boolean;

    // Liefert die markierten Zeilen einer Datei sortiert aufsteigend.
    // Wird vom Finding-Navigations-Hotkey (Ctrl+Alt+Up/Down) genutzt,
    // um zur naechsten/vorherigen Markierung im aktuellen Editor-File
    // zu springen. Leere Liste wenn keine Marks fuer die Datei.
    function GetSortedLinesForFile(const AFile: string): TArray<Integer>;
  end;

var
  GHighlighter : TFindingHighlighter = nil;

procedure RegisterLineHighlighter;
procedure UnregisterLineHighlighter;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeUnitPrivate, ClassPerFile, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DeepNesting, EmptyExcept, EmptyMethod, GodClass, GroupedDeclaration, LargeClass, LongMethod, LongParamList, MagicNumber, MultipleExit, NestedRoutine, NestedTry, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter, UnusedPublicMember
// OTAPI-Plugin: empty-except schluckt IDE-API-Failures (sonst killt jeder
// transienter OTAPI-Glitch das Plugin). LargeClass/GodClass = IDE-Plugin
// braucht alle Highlight-Routinen in einer Klasse fuer Notifier-Lifecycle.
// MultipleExit = guard-clauses fuer OTAPI-Nil-Checks (Standard-Pattern).

uses
  uAnalyserPalette,     // ACCENT_ERROR als zentrale Stripe-Default-Farbe
  uRepoSettings;        // OverlayPosition aus [UI]

const
  STRIPE_WIDTH_PX  = 3;

function IsLightColor(AColor: TColor): Boolean;
// ITU-R BT.601 Luminanz - bei > 127 ist die Farbe "hell" und Schwarz
// kontrastiert besser, sonst Weiss. Wird fuer Auto-Kontrast der Mini-
// Infobar-Schrift gebraucht (Severity-Akzent kann hell sein wie clYellow
// fuer Hint).
var
  RGB     : Cardinal;
  R, G, B : Integer;
  Lum     : Integer;
begin
  RGB := ColorToRGB(AColor);
  R := GetRValue(RGB);
  G := GetGValue(RGB);
  B := GetBValue(RGB);
  Lum := (R * 299 + G * 587 + B * 114) div 1000;
  Result := Lum > 127;
end;

procedure DrawMiniInfoBar(ACanvas: TCanvas; const AMark: TFindingMark;
  ABgColor: TColor; const ACodeRect: TRect; ATextEndX: Integer);
// Permanente Mini-Inline-Badge rechts vom Code: "<- Type . Severity"
// im Severity-Akzent als Hintergrund + kontrastreicher Schrift.
// Wird bei jedem PaintLine-Tick neu gemalt.
// Position: ATextEndX + 8px Gap; Y zentriert in ACodeRect.
// Wenn der Code so lang ist dass keine 60px mehr passen, wird die
// Badge weggelassen (kein unleserliches Stub).
const
  GAP_AFTER_CODE = 8;
  PAD_H          = 6;
  PAD_V          = 1;
  MIN_BADGE_W    = 60;
var
  Text   : string;
  Icon   : string;
  Sz     : TSize;
  BX, BY : Integer;
  BW, BH : Integer;
  R      : TRect;
  OldBrushColor : TColor;
  OldBrushStyle : TBrushStyle;
  OldFontColor  : TColor;
  OldFontName   : string;
  OldFontSize   : Integer;
  OldFontStyle  : TFontStyles;
begin
  // Type-Emoji + Badge: '🐞 Bug · Error'. Wenn TypeText unbekannt
  // bleibt der Icon-Prefix leer, dann nur Badge-Text.
  // Astral-Plane-Glyphen (🐞 = D83D DC1E surrogate-pair) werden via
  // OS-Font-Linking (Segoe UI -> Segoe UI Emoji) gerendert.
  Icon := BadgeIcon(AMark.Badge);
  if Icon <> '' then
    Text := Icon + ' ' + AMark.Badge
  else
    Text := AMark.Badge;
  if Trim(Text) = '' then Exit;  // leer

  // Canvas-State sichern (Editor zeichnet danach noch Text - wir
  // duerfen die Font-/Brush-Einstellungen nicht permanent veraendern).
  OldBrushColor := ACanvas.Brush.Color;
  OldBrushStyle := ACanvas.Brush.Style;
  OldFontColor  := ACanvas.Font.Color;
  OldFontName   := ACanvas.Font.Name;
  OldFontSize   := ACanvas.Font.Size;
  OldFontStyle  := ACanvas.Font.Style;
  try
    ACanvas.Font.Name  := 'Segoe UI';
    ACanvas.Font.Size  := 8;
    ACanvas.Font.Style := [fsBold];
    Sz := ACanvas.TextExtent(Text);

    BW := Sz.cx + 2 * PAD_H;
    BH := Sz.cy + 2 * PAD_V;
    BX := ATextEndX + GAP_AFTER_CODE;
    BY := ACodeRect.Top + (ACodeRect.Bottom - ACodeRect.Top - BH) div 2;
    if BY < ACodeRect.Top then BY := ACodeRect.Top;
    // 1px mehr Hoehe unten (User-Request) - Text-Position bleibt
    // gleich, nur die Box waechst nach unten. Boden minimal "atmen
    // lassen" damit die Schrift nicht direkt am Rand klebt.
    Inc(BH);

    // Kein Platz mehr fuer eine sinnvolle Badge? -> weglassen.
    if BX + MIN_BADGE_W > ACodeRect.Right then Exit;
    // Width clampen falls Badge ueber Code-Rand laufen wuerde.
    if BX + BW > ACodeRect.Right then
      BW := ACodeRect.Right - BX;

    R := Rect(BX, BY, BX + BW, BY + BH);
    ACanvas.Brush.Color := ABgColor;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.FillRect(R);

    // Auto-Kontrast: Schwarz auf hellem Akzent, Weiss auf dunklem.
    if IsLightColor(ABgColor) then
      ACanvas.Font.Color := clBlack
    else
      ACanvas.Font.Color := clWhite;
    ACanvas.Brush.Style := bsClear;   // transparent fuer Text
    ACanvas.TextOut(BX + PAD_H, BY + PAD_V, Text);
  finally
    ACanvas.Brush.Color := OldBrushColor;
    ACanvas.Brush.Style := OldBrushStyle;
    ACanvas.Font.Color  := OldFontColor;
    ACanvas.Font.Name   := OldFontName;
    ACanvas.Font.Size   := OldFontSize;
    ACanvas.Font.Style  := OldFontStyle;
  end;
end;

function TFindingEditorEvents.IsShowOnHoverEnabled: Boolean;
// Settings frisch bei jedem Bedarf lesen damit ein Toggle in Tools >
// Options sofort wirkt. INI-IO ist trivial (cached vom OS-File-Cache).
var
  S : TRepoSettings;
begin
  Result := False;   // Default: Click-only
  S := TRepoSettings.Create;
  try
    try
      S.Load;
      Result := S.OverlayShowOnHover;
    except
    end;
  finally
    S.Free;
  end;
end;

function GetOverlayPositionSetting: string;
// Liefert [UI] OverlayPosition aus analyser.ini. Frische Read pro Aufruf,
// aber nur einmal pro Hover-Enter (= neue Finding-Zeile) - nicht im
// MouseMove-Hot-Path. Default 'sameline' wenn INI nicht lesbar.
var
  S : TRepoSettings;
begin
  Result := 'sameline';
  S := TRepoSettings.Create;
  try
    try
      S.Load;
      if S.OverlayPosition <> '' then
        Result := S.OverlayPosition;
    except
      // INI nicht lesbar -> Default-String greift.
    end;
  finally
    S.Free;
  end;
end;

type
  // Wird beim Save (durch den IDE-Kern) gerufen. Wir delegieren an
  // GHighlighter.ClearFile damit die Marker dieser Datei verschwinden -
  // sie sind potenziell veraltet weil der User Zeilen verschoben hat.
  //
  // KRITISCH: alle 3 IOTAModuleNotifier-Versionen explizit listen +
  // implementieren (siehe ausfuehrlicher Kommentar in uIDEWatchMode -
  // Delphi 12 fragt via QueryInterface den neusten verfuegbaren Typ ab,
  // sonst AV in coreide290.bpl).
  TSaveAutoClearNotifier = class(TNotifierObject, IInterface,
    IOTANotifier, IOTAModuleNotifier80, IOTAModuleNotifier90,
    IOTAModuleNotifier)
  private
    FFileName : string;   // normalisiert (gleiche Form wie GHighlighter-Keys)
  protected
    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    // IOTAModuleNotifier
    function CheckOverwrite: Boolean;
    procedure ModuleRenamed(const NewName: string); overload;
    // IOTAModuleNotifier80
    function AllowSave: Boolean;
    function GetOverwriteFileNameCount: Integer;
    function GetOverwriteFileName(Index: Integer): string;
    procedure SetSaveFileName(const FileName: string);
    // IOTAModuleNotifier90
    procedure BeforeRename(const OldFileName, NewFileName: string);
    procedure AfterRename(const OldFileName, NewFileName: string);
  public
    constructor Create(const ANormalizedFileName: string);
  end;

{ ---- TSaveAutoClearNotifier ---- }

constructor TSaveAutoClearNotifier.Create(const ANormalizedFileName: string);
begin
  inherited Create;
  FFileName := ANormalizedFileName;
end;

procedure TSaveAutoClearNotifier.AfterSave;
begin
  // GHighlighter koennte zwischenzeitlich freigegeben sein (Plugin-Unload-
  // Race). Defensiv pruefen, dann nur die EINE Datei loeschen.
  if Assigned(GHighlighter) then
    GHighlighter.ClearFile(FFileName);
end;

// IOTANotifier
procedure TSaveAutoClearNotifier.BeforeSave; begin end;
procedure TSaveAutoClearNotifier.Destroyed;  begin end;
procedure TSaveAutoClearNotifier.Modified;   begin end;
// IOTAModuleNotifier
function  TSaveAutoClearNotifier.CheckOverwrite: Boolean; begin Result := True; end;
procedure TSaveAutoClearNotifier.ModuleRenamed(const NewName: string); begin end;
// IOTAModuleNotifier80
function  TSaveAutoClearNotifier.AllowSave: Boolean;            begin Result := True; end;
function  TSaveAutoClearNotifier.GetOverwriteFileNameCount: Integer; begin Result := 0; end;
function  TSaveAutoClearNotifier.GetOverwriteFileName(Index: Integer): string; begin Result := ''; end;
procedure TSaveAutoClearNotifier.SetSaveFileName(const FileName: string); begin end;
// IOTAModuleNotifier90
procedure TSaveAutoClearNotifier.BeforeRename(const OldFileName, NewFileName: string); begin end;
procedure TSaveAutoClearNotifier.AfterRename (const OldFileName, NewFileName: string); begin end;

{ ---- TFindingHighlighter ---- }

constructor TFindingHighlighter.Create;
begin
  inherited;
  // doOwnsValues: die inneren TFileMarks-Dictionaries werden bei Remove
  // / Clear / Destroy automatisch freigegeben.
  FMarksByFile     := TObjectDictionary<string, TFileMarks>.Create([doOwnsValues]);
  FSaveNotifiers   := TDictionary<string, TSaveNotifierSlot>.Create;
  FEditorEventsIdx := -1;
  // TFindingEditorEvents erbt TInterfacedObject - der Refcount wird ueber
  // FEditorEvents (INTACodeEditorEvents) gehalten, und das Nil-Setzen in
  // Destroy released das Objekt. Kein expliziter Free noetig.
  FEditorEventsObj := TFindingEditorEvents.Create;
  FEditorEvents    := FEditorEventsObj as INTACodeEditorEvents;
end;

destructor TFindingHighlighter.Destroy;
begin
  FEditorEvents := nil;  // Refcount sinkt; nach RemoveEditorEventsNotifier (in UnregisterLineHighlighter) -> 0 -> Objekt freigegeben
  // ALLE Save-Notifier abmelden BEVOR FMarksByFile weg ist, sonst koennte
  // ein verspaeteter AfterSave-Callback in einen freed Dictionary greifen.
  DetachAllSaveNotifiers;
  FreeAndNil(FSaveNotifiers);
  FreeAndNil(FMarksByFile);
  inherited;
end;

function TFindingHighlighter.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TFindingHighlighter.AttachSaveNotifier(const AKey: string);
// AKey ist bereits normalisiert (NormalizePath). Sucht das IOTAModule
// dazu - wenn die Datei nicht im IDE-Editor offen ist, bleibt der Slot
// leer und wir attachen nichts (das ist OK; sobald SetAllFindings das
// naechste mal laeuft - z.B. nach Filter-Wechsel - versuchen wir erneut).
var
  Slot      : TSaveNotifierSlot;
  ModSvc    : IOTAModuleServices;
  Module    : IOTAModule;
  i         : Integer;
  ModFile   : string;
begin
  if FSaveNotifiers.ContainsKey(AKey) then Exit; // schon attached
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  Module := nil;
  for i := 0 to ModSvc.ModuleCount - 1 do
  begin
    ModFile := NormalizePath(ModSvc.Modules[i].FileName);
    if ModFile = AKey then
    begin
      Module := ModSvc.Modules[i];
      Break;
    end;
  end;
  if not Assigned(Module) then Exit;

  Slot.Module    := Module;
  Slot.Notifier  := TSaveAutoClearNotifier.Create(AKey);
  Slot.Cookie    := Module.AddNotifier(Slot.Notifier);
  FSaveNotifiers.Add(AKey, Slot);
end;

procedure TFindingHighlighter.DetachSaveNotifier(const AKey: string);
var
  Slot : TSaveNotifierSlot;
begin
  if not FSaveNotifiers.TryGetValue(AKey, Slot) then Exit;
  try
    if Assigned(Slot.Module) and (Slot.Cookie >= 0) then
      Slot.Module.RemoveNotifier(Slot.Cookie);
  except
    // Module evtl. schon geschlossen; Slot trotzdem entfernen.
  end;
  FSaveNotifiers.Remove(AKey);  // strong refs (Module, Notifier) sinken
end;

procedure TFindingHighlighter.DetachAllSaveNotifiers;
var
  Keys : TArray<string>;
  K    : string;
begin
  if not Assigned(FSaveNotifiers) or (FSaveNotifiers.Count = 0) then Exit;
  Keys := FSaveNotifiers.Keys.ToArray;  // Kopie, damit wir waehrend
                                        // des Loops modifizieren duerfen
  for K in Keys do DetachSaveNotifier(K);
end;

procedure TFindingHighlighter.InvalidateAllLines;
var
  Svc      : INTACodeEditorServices;
  Bucket   : TFileMarks;
  Ln       : Integer;
begin
  // Forciert Repaint aller markierten Zeilen quer ueber alle Dateien.
  // InvalidateTopEditorLogicalLine triggert den Repaint im aktuell
  // sichtbaren Editor - der Filename-Filter passiert dann in PaintLine
  // ueber ShouldHighlight. Wir muessen daher nicht wissen, welche Datei
  // gerade vor dem User liegt, sondern nur welche Line-Nummern ueberhaupt
  // irgendwo gemerkt sind.
  if FMarksByFile.Count = 0 then Exit;
  try
    if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
    for Bucket in FMarksByFile.Values do
      for Ln in Bucket.Keys do
        Svc.InvalidateTopEditorLogicalLine(Ln);
  except
  end;
end;

function SeverityRank(S: TFindingSeverity): Integer;
// Ranking fuer Multi-Mark-Sortierung: kleinerer Rank = staerker.
// fsError staerker als fsWarning staerker als fsHint staerker als
// fsFileError; fsUnknown ans Ende.
begin
  case S of
    fsError     : Result := 0;
    fsWarning   : Result := 1;
    fsHint      : Result := 2;
    fsFileError : Result := 3;
  else
    Result := 4;
  end;
end;

function SeverityLabel(S: TFindingSeverity): string;
begin
  case S of
    fsError     : Result := 'ERROR';
    fsWarning   : Result := 'WARNING';
    fsHint      : Result := 'HINT';
    fsFileError : Result := 'READ ERROR';
  else
    Result := '';
  end;
end;

procedure TFindingHighlighter.SetAllFindings(
  const AEntries: array of TFindingMarkEntry);
var
  i, j      : Integer;
  Mark      : TFindingMark;
  FileKey   : string;
  Bucket    : TFileMarks;
  // Pro (file, line) sammeln wir zuerst ALLE Eintraege; danach
  // entscheidet sich pro Gruppe ob 1:1 oder als Summary-Mark gespeichert.
  PerLine   : TObjectDictionary<string,
                TObjectDictionary<Integer,
                  TList<TFindingMarkEntry>>>;
  LineMap   : TObjectDictionary<Integer, TList<TFindingMarkEntry>>;
  EntryList : TList<TFindingMarkEntry>;
  Group     : TList<TFindingMarkEntry>;
  Strongest : TFindingMarkEntry;
  DescSB    : TStringBuilder;
begin
  // Overlay sofort verbergen — im Hover-Modus erscheint es erst wieder,
  // wenn die Maus eine markierte Zeile beruehrt.
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;

  // Alte Markierungen invalidieren BEVOR die neue Liste gesetzt wird,
  // damit die alten Stripes weggemalt werden.
  InvalidateAllLines;

  // Kompletter Reset: alle bestehenden Pro-Datei-Buckets weg.
  // doOwnsValues -> innere Dictionaries werden hier freigegeben.
  FMarksByFile.Clear;

  // Phase 1: Eintraege nach (file, line) gruppieren ohne zu mergen.
  // doOwnsValues kaskadiert: aeusseres -> mittleres -> innere TList.
  PerLine := TObjectDictionary<string,
              TObjectDictionary<Integer,
                TList<TFindingMarkEntry>>>.Create([doOwnsValues]);
  try
    for i := 0 to High(AEntries) do
    begin
      if AEntries[i].Line <= 0 then Continue;
      FileKey := NormalizePath(AEntries[i].FileName);
      if FileKey = '' then Continue;

      if not PerLine.TryGetValue(FileKey, LineMap) then
      begin
        LineMap := TObjectDictionary<Integer,
                     TList<TFindingMarkEntry>>.Create([doOwnsValues]);
        PerLine.Add(FileKey, LineMap);
      end;

      if not LineMap.TryGetValue(AEntries[i].Line, EntryList) then
      begin
        EntryList := TList<TFindingMarkEntry>.Create;
        LineMap.Add(AEntries[i].Line, EntryList);
      end;
      EntryList.Add(AEntries[i]);
    end;

    // Phase 2: pro Gruppe Mark synthetisieren und in FMarksByFile ablegen.
    for FileKey in PerLine.Keys do
    begin
      LineMap := PerLine[FileKey];
      Bucket := TFileMarks.Create;
      FMarksByFile.Add(FileKey, Bucket);

      for var LineNo in LineMap.Keys do
      begin
        Group := LineMap[LineNo];
        if Group.Count = 0 then Continue;

        // Duplikate zusammenfassen. Aggressiver Title-only-Match: wenn
        // zwei Entries dieselbe Befund-Hauptmeldung (Title = F.MissingVar)
        // haben, ist es derselbe Finding - auch wenn Desc/Color leicht
        // abweichen (z.B. weil unterschiedliche Detector-Pfade leicht
        // andere FixHint-Descriptions liefern, oder Watch-Mode und
        // Properties-Panel-Auto-Scan kurz hintereinander dispatchen).
        if Group.Count > 1 then
        begin
          var SeenKeys : TDictionary<string, Boolean>;
          SeenKeys := TDictionary<string, Boolean>.Create;
          try
            for var k := Group.Count - 1 downto 0 do
            begin
              // Key = Title + Severity. Title allein wuerde zwei Findings
              // mit demselben Variablen-Namen aber unterschiedlichem
              // Severity (z.B. "Foo" als Error UND als Warning) faelsch-
              // licherweise zusammenfassen - der Severity-Suffix haelt
              // diese unterschiedlichen Findings auseinander.
              var Key := Trim(Group[k].Title) + '|' +
                         IntToStr(Ord(Group[k].Severity));
              if SeenKeys.ContainsKey(Key) then
                Group.Delete(k)
              else
                SeenKeys.Add(Key, True);
            end;
          finally
            SeenKeys.Free;
          end;
        end;

        // Staerkste Severity zuerst (kleinster Rank). Bei gleichem Rank
        // bleibt die Insertion-Order (TList.Sort ist stabil seit RAD12).
        Group.Sort(TComparer<TFindingMarkEntry>.Construct(
          function(const A, B: TFindingMarkEntry): Integer
          begin
            Result := SeverityRank(A.Severity) - SeverityRank(B.Severity);
          end));
        Strongest := Group[0];

        if Group.Count = 1 then
        begin
          // Single-Finding-Mark: 1:1 uebernehmen.
          Mark.Title    := Strongest.Title;
          Mark.Desc     := Strongest.Desc;
          Mark.Badge    := Strongest.Badge;
          Mark.Color    := Strongest.Color;
          Mark.Fix      := Strongest.Fix;
          Mark.Severity := Strongest.Severity;
          Mark.IsMulti  := False;
        end
        else
        begin
          // Multi-Mark: Summary-Markierung mit Bullet-Liste pro Befund.
          // Title + Severity-Label inline, Desc auf eingerueckter Folge-
          // zeile damit alle Detail-Beschreibungen erhalten bleiben - nicht
          // mehr nur die Titel zusammengefasst. Color/Badge/Severity kommen
          // weiterhin vom staerksten Eintrag, sodass der Editor-Stripe
          // konsistent die staerkste Severity zeigt.
          //
          // Beispiel-Output fuer 2 Befunde auf einer Zeile:
          //   • PointerArithmeticOnString  [Warning]
          //      String + integer addition treated as pointer arithmetic ...
          //   • UseAfterFree  [Error]
          //      Variable accessed after FreeAndNil ...
          DescSB := TStringBuilder.Create;
          try
            for j := 0 to Group.Count - 1 do
            begin
              if j > 0 then DescSB.AppendLine;
              // Bullet als #$2022-Escape, nicht als Literal-Char: das File
              // hat kein UTF-8-BOM, Delphi 12 liest Source als ANSI/CP-1252
              // und wuerde die UTF-8-Bytes E2 80 A2 als 3 falsche Chars
              // ('â€¢') in den String legen. Gleiches Pattern wie der
              // ✓-Glyph in uIDEAnnotationOverlay (#$2713).
              DescSB.Append(#$2022 + ' ');
              if Group[j].Title <> '' then
                DescSB.Append(Group[j].Title)
              else
                DescSB.Append('(unnamed)');
              if Group[j].Severity <> fsUnknown then
              begin
                DescSB.Append('  [');
                DescSB.Append(SeverityLabel(Group[j].Severity));
                DescSB.Append(']');
              end;
              if Group[j].Desc <> '' then
              begin
                DescSB.AppendLine;
                DescSB.Append('   ');           // 3 spaces = Indent unter Bullet
                DescSB.Append(Group[j].Desc);
              end;
            end;
            Mark.Desc := DescSB.ToString;
          finally
            DescSB.Free;
          end;
          // Title-Format ueber _() lokalisierbar (DE: 'N Befunde ...', EN: 'N findings ...').
          Mark.Title    := Format(_('%d findings on this line'), [Group.Count]);
          Mark.Badge    := Strongest.Badge;
          Mark.Color    := Strongest.Color;
          Mark.Fix      := '';
          Mark.Severity := Strongest.Severity;
          Mark.IsMulti  := True;
        end;

        Bucket.AddOrSetValue(LineNo, Mark);
      end;
    end;
  finally
    PerLine.Free;
  end;

  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;

  // Save-Notifier sync: alte abmelden die nicht mehr in FMarksByFile sind,
  // neue attachen fuer Dateien die jetzt erstmals Marker haben. Wird beim
  // Frame-First-Run leer (FSaveNotifiers ist leer); beim Filter-Wechsel /
  // Re-Analyse adjustiert es delta-basiert ohne unnoetige IDE-Calls.
  var ExistingKeys : TArray<string>;
  ExistingKeys := FSaveNotifiers.Keys.ToArray;
  // 1) Abmelden was nicht mehr Marker hat
  for var K in ExistingKeys do
    if not FMarksByFile.ContainsKey(K) then
      DetachSaveNotifier(K);
  // 2) Anmelden was neu hinzugekommen ist
  for var K in FMarksByFile.Keys do
    if not FSaveNotifiers.ContainsKey(K) then
      AttachSaveNotifier(K);

  // Neue Markierungen einmal repainten damit Stripes in allen sichtbaren
  // Editoren erscheinen.
  InvalidateAllLines;
end;

procedure TFindingHighlighter.ReplaceMarksForFile(const AFileName: string;
  const AEntries: array of TFindingMarkEntry);
// Pro-File-Variante zu SetAllFindings. Logik identisch (Gruppieren ->
// Dedup -> Sortieren nach Severity -> Single/Multi-Mark), aber Scope auf
// EINE Datei begrenzt. Marker anderer Dateien bleiben unangetastet.
var
  i, j      : Integer;
  Mark      : TFindingMark;
  FileKey   : string;
  Bucket    : TFileMarks;
  OldBucket : TFileMarks;
  LineMap   : TObjectDictionary<Integer, TList<TFindingMarkEntry>>;
  EntryList : TList<TFindingMarkEntry>;
  Group     : TList<TFindingMarkEntry>;
  Strongest : TFindingMarkEntry;
  DescSB    : TStringBuilder;
  Svc       : INTACodeEditorServices;
  HasSvc    : Boolean;
begin
  FileKey := NormalizePath(AFileName);
  if FileKey = '' then Exit;

  HasSvc := Supports(BorlandIDEServices, INTACodeEditorServices, Svc);

  // Hover-Overlay nur dann verstecken, wenn es eine Marke unserer Datei
  // zeigt. Bei anderen Dateien stoeren wir den User nicht.
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;

  // 1) Alte Markierungs-Lines fuer FileKey invalidieren, damit die
  //    bisherigen Stripes weggemalt werden. Andere Dateien bleiben
  //    unberuehrt.
  if FMarksByFile.TryGetValue(FileKey, OldBucket) then
  begin
    if HasSvc then
      for var OldLn in OldBucket.Keys do
        try Svc.InvalidateTopEditorLogicalLine(OldLn); except end;
    FMarksByFile.Remove(FileKey);   // OwnsValues -> Bucket freed
  end;

  // 2) Wenn keine neuen Eintraege: nur Save-Notifier abklemmen + raus.
  //    Identisch zu ClearFile fuer diese Datei.
  if Length(AEntries) = 0 then
  begin
    if FSaveNotifiers.ContainsKey(FileKey) then
      DetachSaveNotifier(FileKey);
    if Assigned(FEditorEventsObj) then
      FEditorEventsObj.ResetState;
    Exit;
  end;

  // 3) Eintraege nach Line gruppieren.
  LineMap := TObjectDictionary<Integer, TList<TFindingMarkEntry>>.Create([doOwnsValues]);
  try
    for i := 0 to High(AEntries) do
    begin
      if AEntries[i].Line <= 0 then Continue;
      // Defensive: FileName muss zu AFileName passen, sonst skip.
      if NormalizePath(AEntries[i].FileName) <> FileKey then Continue;

      if not LineMap.TryGetValue(AEntries[i].Line, EntryList) then
      begin
        EntryList := TList<TFindingMarkEntry>.Create;
        LineMap.Add(AEntries[i].Line, EntryList);
      end;
      EntryList.Add(AEntries[i]);
    end;

    // 4) Pro Gruppe Mark synthetisieren (identisch zu SetAllFindings).
    Bucket := TFileMarks.Create;
    FMarksByFile.Add(FileKey, Bucket);

    for var LineNo in LineMap.Keys do
    begin
      Group := LineMap[LineNo];
      if Group.Count = 0 then Continue;

      // Duplikate (Title + Severity) entfernen.
      if Group.Count > 1 then
      begin
        var SeenKeys : TDictionary<string, Boolean>;
        SeenKeys := TDictionary<string, Boolean>.Create;
        try
          for var k := Group.Count - 1 downto 0 do
          begin
            var Key := Trim(Group[k].Title) + '|' +
                       IntToStr(Ord(Group[k].Severity));
            if SeenKeys.ContainsKey(Key) then
              Group.Delete(k)
            else
              SeenKeys.Add(Key, True);
          end;
        finally
          SeenKeys.Free;
        end;
      end;

      Group.Sort(TComparer<TFindingMarkEntry>.Construct(
        function(const A, B: TFindingMarkEntry): Integer
        begin
          Result := SeverityRank(A.Severity) - SeverityRank(B.Severity);
        end));
      Strongest := Group[0];

      if Group.Count = 1 then
      begin
        Mark.Title    := Strongest.Title;
        Mark.Desc     := Strongest.Desc;
        Mark.Badge    := Strongest.Badge;
        Mark.Color    := Strongest.Color;
        Mark.Fix      := Strongest.Fix;
        Mark.Severity := Strongest.Severity;
        Mark.IsMulti  := False;
      end
      else
      begin
        DescSB := TStringBuilder.Create;
        try
          for j := 0 to Group.Count - 1 do
          begin
            if j > 0 then DescSB.AppendLine;
            DescSB.Append(#$2022 + ' ');
            if Group[j].Title <> '' then
              DescSB.Append(Group[j].Title)
            else
              DescSB.Append('(unnamed)');
            if Group[j].Severity <> fsUnknown then
            begin
              DescSB.Append('  [');
              DescSB.Append(SeverityLabel(Group[j].Severity));
              DescSB.Append(']');
            end;
            if Group[j].Desc <> '' then
            begin
              DescSB.AppendLine;
              DescSB.Append('   ');
              DescSB.Append(Group[j].Desc);
            end;
          end;
          Mark.Desc := DescSB.ToString;
        finally
          DescSB.Free;
        end;
        Mark.Title    := Format(_('%d findings on this line'), [Group.Count]);
        Mark.Badge    := Strongest.Badge;
        Mark.Color    := Strongest.Color;
        Mark.Fix      := '';
        Mark.Severity := Strongest.Severity;
        Mark.IsMulti  := True;
      end;

      Bucket.AddOrSetValue(LineNo, Mark);
    end;
  finally
    LineMap.Free;
  end;

  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;

  // 5) Save-Notifier nur fuer DIESE Datei sync.
  if Bucket.Count > 0 then
  begin
    if not FSaveNotifiers.ContainsKey(FileKey) then
      AttachSaveNotifier(FileKey);
  end
  else
  begin
    if FSaveNotifiers.ContainsKey(FileKey) then
      DetachSaveNotifier(FileKey);
    // Bucket leer -> Eintrag wieder rausnehmen, sonst stets-leeres File
    // im Dictionary.
    FMarksByFile.Remove(FileKey);
  end;

  // 6) Neue Markierungs-Lines invalidieren - sichtbar im aktiven Editor.
  if HasSvc and FMarksByFile.TryGetValue(FileKey, Bucket) then
    for var NewLn in Bucket.Keys do
      try Svc.InvalidateTopEditorLogicalLine(NewLn); except end;
end;

procedure TFindingHighlighter.Clear;
begin
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;
  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;
  InvalidateAllLines;
  FMarksByFile.Clear;
  // Save-Notifiers fuer alle Dateien abmelden (kein Auto-Clear mehr).
  DetachAllSaveNotifiers;
end;

procedure TFindingHighlighter.ClearFile(const AFileName: string);
// Wird vom Auto-Save-Pfad gerufen: Datei wurde editiert + gespeichert,
// die Zeilen-Nummern der Marker sind potenziell veraltet -> komplett raus.
// Auch vom [x]-Button im Overlay wenn der User die letzte Markierung
// einer Datei dismissed.
var
  Key : string;
begin
  if AFileName = '' then Exit;
  Key := NormalizePath(AFileName);

  // Overlay sofort verbergen falls es gerade diese Datei zeigt.
  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;

  // Bestehende Stripes invalidieren BEVOR die Daten weg sind, sonst
  // bleibt der alte Stripe sichtbar bis zum naechsten Repaint-Trigger.
  if FMarksByFile.ContainsKey(Key) then
  begin
    InvalidateAllLines;
    FMarksByFile.Remove(Key);  // doOwnsValues -> inner Dictionary auto-free
    DetachSaveNotifier(Key);
  end;

  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;
end;

procedure TFindingHighlighter.RemoveMark(const AFileName: string;
  ALineNo: Integer);
// Loescht EINEN Marker. Wenn das die letzte Markierung der Datei war,
// wird auch der Save-Notifier abgemeldet (via ClearFile-Fallback).
var
  Key    : string;
  Bucket : TFileMarks;
begin
  if (AFileName = '') or (ALineNo <= 0) then Exit;
  Key := NormalizePath(AFileName);

  if not FMarksByFile.TryGetValue(Key, Bucket) then Exit;
  if not Bucket.ContainsKey(ALineNo) then Exit;

  if Assigned(GAnnotationOverlay) then
    GAnnotationOverlay.HideOverlay;

  InvalidateAllLines;
  Bucket.Remove(ALineNo);

  // Letzte Markierung der Datei? Dann Bucket + Notifier komplett weg.
  if Bucket.Count = 0 then
  begin
    FMarksByFile.Remove(Key);
    DetachSaveNotifier(Key);
  end;

  if Assigned(FEditorEventsObj) then
    FEditorEventsObj.ResetState;
end;

function TFindingHighlighter.HasMarks: Boolean;
begin
  Result := FMarksByFile.Count > 0;
end;

function TFindingHighlighter.HasMarksForFile(const AFileName: string): Boolean;
var
  Bucket: TFileMarks;
begin
  Result := FMarksByFile.TryGetValue(NormalizePath(AFileName), Bucket)
        and (Bucket.Count > 0);
end;

function TFindingHighlighter.ShouldHighlight(const AFilePath: string;
  ALine: Integer): Boolean;
var
  Bucket: TFileMarks;
begin
  Result := FMarksByFile.TryGetValue(NormalizePath(AFilePath), Bucket)
        and Bucket.ContainsKey(ALine);
end;

function TFindingHighlighter.TryGetMark(const AFile: string; ALine: Integer;
  out AMark: TFindingMark): Boolean;
var
  Bucket: TFileMarks;
begin
  Result := FMarksByFile.TryGetValue(NormalizePath(AFile), Bucket)
        and Bucket.TryGetValue(ALine, AMark);
end;

function TFindingHighlighter.GetSortedLinesForFile(
  const AFile: string): TArray<Integer>;
var
  Bucket : TFileMarks;
begin
  if not FMarksByFile.TryGetValue(NormalizePath(AFile), Bucket)
     or (Bucket.Count = 0) then
    Exit(nil);
  Result := Bucket.Keys.ToArray;
  TArray.Sort<Integer>(Result);
end;

{ ---- TFindingEditorEvents ---- }

constructor TFindingEditorEvents.Create;
begin
  inherited;
  FRenderedRects    := TDictionary<Integer, TRect>.Create;
  FRenderedTextEnds := TDictionary<Integer, Integer>.Create;
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
  FreeAndNil(FRenderedTextEnds);
  inherited;
end;

procedure TFindingEditorEvents.ResetState;
begin
  FSavedEditor     := nil;
  FSavedCharHeight := 0;
  FHoveredLine     := -1;
  // FLastPaintedFile leeren, damit der naechste PaintLine-Tick als
  // "neue Datei" detektiert wird und sauber neu startet. Sonst koennten
  // alte Hit-Test-Rects einer vorherigen Datei kurzzeitig matchen.
  FLastPaintedFile := '';
  if Assigned(FRenderedRects) then
    FRenderedRects.Clear;
  if Assigned(FRenderedTextEnds) then
    FRenderedTextEnds.Clear;
  if Assigned(FHoverWatch) then
    FHoverWatch.Enabled := False;
end;

function TFindingEditorEvents.IsCursorOverOverlay: Boolean;
// Pruefung wurde verengt: Overlay bleibt nur sichtbar wenn die Maus in
// einem 50x50-Quadrat um den Close-[x]-Button steht (nicht mehr ueber
// dem GANZEN Overlay). Hintergrund: User soll dem Close-Button zielsicher
// nachfahren koennen, aber nicht versehentlich auf dem Overlay "haengen
// bleiben" wenn er eigentlich anderswo klicken wollte.
//
// Funktionsname bleibt aus Backwards-Kompat (die zwei Aufrufer
// EditorMouseMove + DoHoverWatch fragen damit "soll ich noch sichtbar
// halten?" - die genaue Geometrie ist eine Implementierungs-Detail).
const
  HOVER_ZONE_PX = 50;
var
  CursorScr : TPoint;
begin
  Result := False;
  if not Assigned(GAnnotationOverlay) then Exit;
  if not GAnnotationOverlay.Visible then Exit;
  if not Winapi.Windows.GetCursorPos(CursorScr) then Exit;
  Result := GAnnotationOverlay.IsCursorNearClose(CursorScr, HOVER_ZONE_PX);
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
    // Cursor verlaesst die markierte Zeile - aber NICHT verstecken wenn er
    // gerade ueber dem Overlay schwebt (User will den Close-[x]-Button
    // klicken). Timer laeuft weiter, beim naechsten Tick re-prueft er.
    if IsCursorOverOverlay then Exit;
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
procedure TFindingEditorEvents.EditorMouseDown(const Editor: TWinControl;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
// Click-Trigger fuer das Annotation-Overlay wenn die User-Option
// ShowOnHover deaktiviert ist (Default). Linksklick auf eine markierte
// Zeile zeigt das Overlay als Title-Bar; weiterer Klick aufs Title-Label
// im Overlay expandiert die Detail-Ansicht (siehe TitleLblClick im
// Overlay). Im ShowOnHover-True-Modus ist dieser Pfad no-op weil das
// Overlay bereits beim Hover sichtbar wird.
var
  HitLine : Integer;
begin
  if Button <> mbLeft then Exit;
  if not Assigned(GAnnotationOverlay) then Exit;
  if Editor <> FSavedEditor then Exit;
  if FRenderedRects.Count = 0 then Exit;
  if IsShowOnHoverEnabled then Exit;   // alter Pfad regelt das

  HitLine := HitTestLine(X, Y);
  if HitLine < 0 then
  begin
    // Klick auf nicht-markierte Zeile -> falls Overlay sichtbar ist (vom
    // vorherigen Marker-Klick), verstecken.
    if GAnnotationOverlay.Visible then
      GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
    Exit;
  end;
  ShowOverlayForLine(HitLine);
end;
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
  FRenderedTextEnds.Clear;
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
  HitLine       : Integer;
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
  // Defense-in-Depth: Tab-Switch ohne PaintLine-Trigger (rare, aber kommt
  // beim Show-without-Repaint vor). Wenn die zuletzt gemalte Datei nicht
  // dieselbe ist, die der GHighlighter aktiv haelt, sind FRenderedRects
  // stale - kein Overlay.
  if not GHighlighter.HasMarksForFile(FLastPaintedFile) then
  begin
    GAnnotationOverlay.HideOverlay;
    FHoveredLine := -1;
    FRenderedRects.Clear;
    FRenderedTextEnds.Clear;
    FHoverWatch.Enabled := False;
    Exit;
  end;

  // Hit-Test gegen alle gerenderten Marker-Rects.
  HitLine := HitTestLine(X, Y);
  if HitLine < 0 then
  begin
    // Maus hat die markierte Zeile verlassen - aber wenn sie gerade ueber
    // dem Overlay schwebt, NICHT verstecken (sonst kann der Close-[x]-
    // Button nie erreicht werden). HoverWatch-Timer laeuft weiter; sobald
    // der User Editor + Overlay verlaesst, kicked DoHoverWatch das Hide.
    if IsCursorOverOverlay then Exit;
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

  // User-Option: Overlay erscheint NUR beim Klick (Default), nicht beim
  // Hover. EditorMouseDown ruft denselben ShowOverlayForLine-Helper.
  if not IsShowOnHoverEnabled then
  begin
    // Hover-Path deaktiviert - HoverWatch-Timer trotzdem laufen lassen
    // damit das Overlay nach Leave wieder versteckt wird (User klickte
    // vorher, jetzt verlaesst er die Zeile).
    FHoverWatch.Enabled := True;
    Exit;
  end;

  ShowOverlayForLine(HitLine);
end;

procedure TFindingEditorEvents.ShowOverlayForLine(AHitLine: Integer);
// Zentraler Entry-Point fuer Overlay-Show. Wird von EditorMouseMove (Hover-
// Modus) und EditorMouseDown (Click-Modus) gleichermassen genutzt - der
// gesamte Geometrie- + ShowAt-Code lebt hier.
var
  P             : TPoint;
  AWidth, LineH : Integer;
  Mark          : TFindingMark;
  HitRect       : TRect;
begin
  if not Assigned(GAnnotationOverlay) or not Assigned(GHighlighter) then Exit;
  if AHitLine < 0 then Exit;

  // Annotation-Texte fuer die getroffene Zeile holen.
  if not GHighlighter.TryGetMark(FLastPaintedFile, AHitLine, Mark) then Exit;
  if not FRenderedRects.TryGetValue(AHitLine, HitRect) then Exit;

  // WS_CHILD-Modus: Position = Editor-Client-Koordinaten.
  // OverlayPosition aus analyser.ini steuert die Geometrie:
  //   sameline (Default): Title-Bar erscheint INLINE am rechten Zeilenende
  //                       (rechts neben dem Code-Text), P.Y = HitRect.Top.
  //                       Die Auffalt-Animation waechst nach unten in die
  //                       Code-Zeilen darunter. P.X kommt aus
  //                       FRenderedTextEnds (LineState.VisibleTextRect.Right);
  //                       Fallback CodeRect.Left + 60% wenn nicht erfasst.
  //   below             : Overlay startet eine Zeile UNTER der Finding-Zeile
  //                       in voller Code-Breite (alte Default, Befund-Zeile
  //                       bleibt sichtbar).
  // Wert wird hier pro Hover-Enter (= rare) frisch gelesen; kein Cache
  // noetig - der Hot-Path EditorMouseMove cached bereits via FHoveredLine.
  if SameText(GetOverlayPositionSetting, 'sameline') then
  begin
    // X = TextEnd + 8px Gap; nach links clampen wenn der Code rechts ueber
    // das Fenster hinausragt (mindestens MIN_INLINE_W vom rechten Rand).
    const MIN_INLINE_W = 320;
    const GAP_AFTER_CODE = 8;
    var TextEndX : Integer;
    if not FRenderedTextEnds.TryGetValue(AHitLine, TextEndX) then
      TextEndX := HitRect.Left + ((HitRect.Right - HitRect.Left) * 6) div 10;
    P.X := TextEndX + GAP_AFTER_CODE;
    if P.X > HitRect.Right - MIN_INLINE_W then
      P.X := HitRect.Right - MIN_INLINE_W;
    if P.X < HitRect.Left then P.X := HitRect.Left;
    P.Y := HitRect.Top;
    AWidth := HitRect.Right - P.X;
    if AWidth < MIN_INLINE_W then AWidth := MIN_INLINE_W;
  end
  else
  begin
    P.X := HitRect.Left;
    P.Y := HitRect.Bottom;
    AWidth := HitRect.Right - HitRect.Left;
    if AWidth < 200 then AWidth := 200;
  end;
  LineH := FSavedCharHeight;
  if LineH < 16 then LineH := 20;  // Fallback wenn CharHeight nicht gesetzt
  try
    // Mini-Badge-W (PaintLine zeichnet sie aus BadgeIcon + ' ' + Mark.Badge
    // in Segoe UI 8 bold + 12px Padding). Schaetzung: 6px pro Badge-Char
    // + 18px fuer das Emoji-Icon (Surrogate-Pair = 2 UTF-16 Chars, aber
    // Emoji rendert breiter als ein Text-Char). +12px Box-Padding. Wenn
    // BadgeIcon='' (unbekannter TypeText) entfaellt der Icon-Anteil.
    // Nur im sameline-Modus relevant.
    var EstBadgeW : Integer := 0;
    if SameText(GetOverlayPositionSetting, 'sameline') then
    begin
      EstBadgeW := Length(Mark.Badge) * 6 + 12;
      if BadgeIcon(Mark.Badge) <> '' then
        Inc(EstBadgeW, 18);
    end;

    GAnnotationOverlay.ShowAt(FSavedEditor, P.X, P.Y, AWidth, LineH,
      Mark.Title, Mark.Desc, Mark.Badge, Mark.Color, Mark.Fix,
      FLastPaintedFile, AHitLine, EstBadgeW);
    FHoveredLine := AHitLine;
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
  begin
    FRenderedRects.Clear;
    FRenderedTextEnds.Clear;
  end;
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
  HasMark   : Boolean;
begin
  if not Assigned(GHighlighter) then Exit;
  if not Assigned(Context) or not Assigned(Context.EditControl) then Exit;
  // AllowedLineStages = [plsBackground] -> Stage ist immer plsBackground hier.
  // BeforeEvent=False: Default-Hintergrund bereits gemalt, Stripe drueber legen.
  if BeforeEvent then Exit;

  // Tab-Switch-Detection: wenn die jetzt gemalte Datei nicht dieselbe ist
  // wie die letzte, sind die in FRenderedRects gespeicherten Hit-Test-
  // Rechtecke der alten Datei stale. Beim ersten MouseMove auf der neuen
  // Datei wuerde das Hover-Overlay sonst eine Stripe-Zeile der alten
  // Datei anhand der Y-Koordinate falsch matchen und einen unrelated
  // Befund anzeigen. Vor dem Befuellen der Rects fuer die neue Datei
  // einmalig den Stale-Cache leeren.
  if not SameText(Context.FileName, FLastPaintedFile) then
  begin
    FRenderedRects.Clear;
    FRenderedTextEnds.Clear;
    FHoveredLine := -1;
    FLastPaintedFile := Context.FileName;
    if Assigned(GAnnotationOverlay) then
      GAnnotationOverlay.HideOverlay;
    if Assigned(FHoverWatch) then
      FHoverWatch.Enabled := False;
  end;

  Line := Context.LogicalLineNum;
  if not GHighlighter.ShouldHighlight(Context.FileName, Line) then Exit;

  FSavedEditor     := Context.EditControl;
  CodeRect         := Context.LineState.CodeRect;
  // CharHeight fuer DPI-bewusstes Overlay-Sizing in EditorMouseMove verwenden.
  FSavedCharHeight := Context.EditorState.CharHeight;
  // Rect cachen damit EditorMouseMove pro Zeile den Hit-Test machen kann.
  FRenderedRects.AddOrSetValue(Line, CodeRect);
  // VisibleTextRect.Right = X-Pixel wo der sichtbare Code-Text endet.
  // Wird im 'sameline'-OverlayPosition-Modus genutzt um die Title-Bar
  // direkt rechts neben dem Code zu platzieren statt drueber zu legen.
  // ZUSAETZLICH: Mini-Infobar (Type / Severity) wird beim PaintLine
  // direkt hier rechts neben dem Code gezeichnet.
  var TextEndX : Integer := -1;
  try
    TextEndX := Context.LineState.VisibleTextRect.Right;
    FRenderedTextEnds.AddOrSetValue(Line, TextEndX);
  except
    // VisibleTextRect kann bei manchen Edge-Cases (gefoldete Zeilen, leere
    // Files) nicht verfuegbar sein - EditorMouseMove faellt dann auf
    // CodeRect.Left zurueck.
  end;

  // Stripe-Farbe + Mark fuer Mini-Infobar holen.
  HasMark := GHighlighter.TryGetMark(Context.FileName, Line, Mark);
  StripeCol := ACCENT_ERROR;
  if HasMark and (Mark.Color <> clNone) then
    StripeCol := Mark.Color;

  // 3px Stripe am linken Rand des Code-Bereichs.
  // Hinweis: Parameter 'Rect' verdeckt Winapi.Windows.Rect, deshalb SR direkt nutzen.
  SR := CodeRect;
  SR.Right := SR.Left + STRIPE_WIDTH_PX;
  Context.Canvas.Brush.Color := StripeCol;
  Context.Canvas.Brush.Style := bsSolid;
  Context.Canvas.FillRect(SR);

  // ---- Mini-Infobar am rechten Zeilenende ----
  // Format: ◀ <Badge>  (z.B. "◀ BUG · ERROR")
  // Permanent sichtbar - jeder PaintLine-Tick zeichnet sie neu.
  // Background = Severity-Akzent, Foreground = Kontrast (weiss/schwarz
  // je nach Luminanz). 8px Gap nach dem Code, ~10px Padding.
  if HasMark and (Mark.Badge <> '') and (TextEndX > 0) then
    DrawMiniInfoBar(Context.Canvas, Mark, StripeCol, CodeRect, TextEndX);
end;

procedure TFindingEditorEvents.EndPaint(const Editor: TWinControl);
var
  Line : Integer;
  Mark : TFindingMark;
  ToRemove : TList<Integer>;
begin
  if Editor <> FSavedEditor then Exit;

  // Stale-Cache-Cleanup: FRenderedRects/FRenderedTextEnds bekommen pro
  // PaintLine Eintraege fuer SICHTBARE markierte Zeilen dazu. Wenn der
  // User aus einem Bereich rausscrollt oder ein Marker durch einen
  // neuen Scan verschwindet, liegen alte Eintraege bis zum naechsten
  // ForceFullRepaint (BeginPaint-Branch) brach. Bei langen IDE-Sessions
  // ohne Full-Repaint summiert sich das. Hier in EndPaint pruefen ob
  // jede gecachte Line noch einen Mark hat - sonst raus.
  // Kosten: O(N) Dictionary-Lookups, N typisch ~100; in praxi negligible.
  if Assigned(GHighlighter) and (FRenderedRects.Count > 0)
     and (FLastPaintedFile <> '') then
  begin
    ToRemove := TList<Integer>.Create;
    try
      for Line in FRenderedRects.Keys do
        if not GHighlighter.TryGetMark(FLastPaintedFile, Line, Mark) then
          ToRemove.Add(Line);
      for Line in ToRemove do
      begin
        FRenderedRects.Remove(Line);
        FRenderedTextEnds.Remove(Line);
      end;
    finally
      ToRemove.Free;
    end;
  end;

  // Bei Full-Repaint (BeginPaint hat FRenderedRects geleert) wurden alle
  // tatsaechlich sichtbaren markierten Zeilen via PaintLine wieder
  // hinzugefuegt. Wenn FRenderedRects danach leer ist, gibt es keine
  // sichtbaren Marker mehr -> Overlay verbergen.
  if not Assigned(GAnnotationOverlay) then Exit;
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
