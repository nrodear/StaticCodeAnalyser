unit uIDEAnnotationOverlay;

// Overlay-Fenster: zeigt Befund-Titel + Badge + Beschreibung als Block
// direkt unter der betroffenen Editor-Zeile.
//
// Z-ORDER (WS_CHILD-Pattern):
//   Das Form startet als WS_POPUP (VCL-Default), wird aber beim ersten
//   ShowAt(AEditor) via SetParent + GWL_STYLE-Wechsel zu einem WS_CHILD
//   des Editor-EditControls. Damit:
//     - liegt das Overlay innerhalb des Editor-Window-Rechtecks (geclippt)
//     - kann es KEIN unabhaengiges Top-Level-Window (gefloatete IDE-Tool-
//       Panels, Object Inspector, ...) ueberdecken, weil es nicht selbst
//       Top-Level ist
//     - wandert es korrekt mit dem Editor mit (Scroll, Resize, Move)
//   Trade-off: das Overlay ist hart am Editor-Rand abgeschnitten — wenn
//   die Befund-Zeile am unteren Editor-Rand liegt, ragt der Hint nicht
//   nach unten heraus.
//
// Hide-on-mouse-leave (siehe TFindingEditorEvents.HoverWatch in
// uIDELineHighlighter.pas) sorgt dafuer, dass das Overlay verschwindet
// sobald die Maus den Editor verlaesst.
//
// Design (theme-adaptiv via StyleServices):
//   Titelzeile: BlendColor(clWindow, Severity-Akzent, 50%) — Light: pastell,
//               Dark: mid-akzent. Text = clWindowText (Theme-adaptiv).
//   Badge:      BlendColor(clWindow, Severity-Akzent, 85%) — staerker farbig.
//   Beschreibungszeile: clWindow + clGrayText (neutraler Bereich).
//   Linker Rand: voller Severity-Akzent — korrespondiert zum PaintLine-Stripe
//                (gleiche Farbe wie der Editor-Stripe und der Grid-4px-Stripe).
//
// ShowAt empfaengt ALineH (Zeilen-Pixelhoehe aus Context.EditorState.CharHeight)
// fuer DPI-bewusstes Sizing. Position + Inhalt werden gecacht: bei identischen
// Parametern wird der Win32-Aufruf uebersprungen, was Flimmern bei schnellen
// MouseMove-Events vermeidet.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Themes,
  ToolsAPI, ToolsAPI.Editor,  // INTACodeEditorServices.Options.BackgroundColor[atWhiteSpace]
  uAnalyserTheme,    // BlendColor + theme-adaptive Severity-Farben
  uLocalization;     // _() — Symbol/Trennzeichen via dxgettext lokalisierbar

type
  TAnnotationOverlay = class(TForm)
  private
    FBorderPanel : TPanel;   // 3px linker Rand (Rot)
    FContentArea : TPanel;   // rechts davon: Titel + Desc
    FPanelTitle  : TPanel;
    FLblTitle    : TLabel;   // "⚠  Memory Leak – ..."
    FLblBadge    : TLabel;   // "BUG · ERROR" rechts
    FPanelDesc   : TPanel;
    FLblDesc     : TLabel;
    // Cache: letzter ShowAt-Aufruf – verhindert redundante Win32-Aufrufe.
    FLastX, FLastY, FLastW, FLastLineH : Integer;
    FLastTitle, FLastDesc, FLastBadge  : string;
    FLastAccent                        : TColor;  // Severity-Akzent
    FLastWindowBase                    : TColor;  // Editor-Theme-BG (Cache-Invalidator!)
    // Editor in den wir aktuell als WS_CHILD eingebettet sind. 0 = noch
    // nicht eingebettet (initialer WS_POPUP-Zustand).
    FCurrentParent : HWND;
    procedure EmbedIntoEditor(AEditorHandle: HWND);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Overlay UNTER der markierten Editor-Zeile anzeigen.
    // AEditor: Editor-Control. Beim ersten Aufruf wird das Overlay als
    //   WS_CHILD in dieses Control eingebettet (siehe Z-ORDER-Doku oben).
    //   Bei einem anderen Editor wird re-parented.
    // AClientX/Y, AWidth, AHeight: Position + Groesse in EDITOR-CLIENT-
    //   Koordinaten (NICHT mehr Screen-Koordinaten — Caller muss nicht
    //   mehr ClientToScreen rufen).
    // ALineH = Context.EditorState.CharHeight (DPI-skalierte Zeilenhoehe).
    // ABadge z.B. "BUG · ERROR" oder "CODE SMELL · WARNING".
    // AAccentColor: Severity-Akzentfarbe (gleiche Quelle wie der Editor-Stripe).
    //   Wird zum Theming der Title-Bar, Badge und linken Stripe genutzt — so
    //   bekommt jeder Befund-Typ ein passendes Farbschema. clNone -> Default-Rot.
    procedure ShowAt(AEditor: TWinControl;
      AClientX, AClientY, AWidth, ALineH: Integer;
      const ATitle, ADesc, ABadge: string;
      AAccentColor: TColor = clNone);
    procedure HideOverlay;
  end;

var
  GAnnotationOverlay : TAnnotationOverlay = nil;

procedure RegisterAnnotationOverlay;
procedure UnregisterAnnotationOverlay;

implementation

const
  // Exakte Farben aus dem Mockup (Delphi TColor = $00BBGGRR)
  CL_STRIPE      = TColor($000020D0); // #D02000 – roter linker Rand
  CL_TITLE_BG    = TColor($001A1A2A); // #2A1A1A – dunkelrot Titelzeile
  CL_TITLE_FG    = TColor($00A0A0E8); // #E8A0A0 – helles Rosa/Rot
  CL_BADGE_BG    = TColor($0015157A); // #7A1515 – sattes Dunkelrot Badge
  CL_BADGE_FG    = TColor($00AAAAFF); // #FFAAAA – sehr helles Rosa Badge
  CL_DESC_BG     = TColor($00222222); // #222    – fast Schwarz
  CL_DESC_FG     = TColor($00888888); // #888    – mittelgrau
  STRIPE_W       = 3;
  // Mindesthoehen in Pixeln (96 DPI-Baseline); ShowAt skaliert dynamisch.
  MIN_TITLE_H    = 20;
  MIN_DESC_H     = 18;
  // Maximale Description-Hoehe in Pixeln — verhindert dass das Overlay
  // halb-bildschirmgross wird bei sehr langen Texten. ~120px deckt
  // ca. 6-7 Zeilen Segoe UI 8pt ab.
  MAX_DESC_H     = 120;
  // Vertikales Padding der Description (oben + unten) in Pixeln.
  DESC_PAD_V     = 8;

// Liefert den Source-Editor-Hintergrund via offizieller ToolsAPI.
// INTACodeEditorServices.Options.BackgroundColor[atWhiteSpace] ist die
// kanonische Quelle (siehe DX.Blame und ToolsAPI.Editor.pas:685) — reflektiert
// die Editor-Color-Speed-Setting, NICHT die IDE-Frame-Theme-Farbe (das ist
// der Unterschied: IDE kann dunkel sein bei hellem Editor und umgekehrt).
// Liefert clNone wenn die Service-Instanz nicht erreichbar ist.
function GetEditorThemeBgColor: TColor;
var
  Svc : INTACodeEditorServices;
begin
  Result := clNone;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      Result := Svc.Options.BackgroundColor[atWhiteSpace];
  except
    // Service kann ggf. nicht initialisiert sein — clNone als Fallback OK.
  end;
end;

// True wenn Farbe "hell" wirkt (Luminanz > 50%). Fuer Auto-Kontrast-
// Wahl der Textfarbe (clBlack auf hell, clWhite auf dunkel).
function IsLightColor(AColor: TColor): Boolean;
var
  rgb : Cardinal;
  R, G, B : Integer;
  Lum : Integer;
begin
  rgb := ColorToRGB(AColor);
  R := GetRValue(rgb);
  G := GetGValue(rgb);
  B := GetBValue(rgb);
  // Perzeptuelle Luminanz: ITU-R BT.601 (gewichtetes Mittel).
  Lum := (R * 299 + G * 587 + B * 114) div 1000;
  Result := Lum > 127;
end;

constructor TAnnotationOverlay.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Color       := CL_TITLE_BG;
  Visible     := False;
  // KRITISCH (Multi-Monitor-Setup):
  //
  // Position := poDesigned: VCL's Default fuer manche Form-Konfigurationen
  //   ist poScreenCenter / poMainFormCenter, was beim Visible:=True das
  //   Form zentriert.
  //
  // DefaultMonitor := dmDesktop: VCL's Default ist dmActiveForm — das
  //   zwingt das Form beim Visible:=True auf den Monitor des aktiven
  //   Forms (oder MainForm), wobei UNSERE SetBounds-Koordinaten komplett
  //   ueberschrieben werden. Das Overlay erscheint dann am falschen
  //   Monitor (typisch in der Mitte des Primary-Monitors oder bei (0,0)
  //   des MainForm-Monitors). Mit dmDesktop respektiert VCL die
  //   uebergebenen absoluten Bildschirmkoordinaten unangetastet.
  Position := poDesigned;
  DefaultMonitor := dmDesktop;

  // KRITISCH (VCL-Themes): StyleElements := [] auf dem Form, sonst greift
  // der StyleHook und uebermalt unsere Panel-Color durch die VCL-Style-
  // Backgroundfarbe (Vcl.ExtCtrls.pas:3411-3424 — TCustomPanel.Paint
  // ueberschreibt Color wenn seClient in StyleElements). Gleiches gilt
  // fuer alle Panels und das Badge-Label unten.
  StyleElements := [];

  // ---- 3px linker Rand (Farb-Stripe) ----
  FBorderPanel                := TPanel.Create(Self);
  FBorderPanel.Parent         := Self;
  FBorderPanel.Align          := alLeft;
  FBorderPanel.Width          := STRIPE_W;
  FBorderPanel.BevelOuter     := bvNone;
  FBorderPanel.StyleElements  := [];     // VCL-Theme nicht ueberschreiben
  FBorderPanel.ParentBackground := False; // sonst flaecht clBtnFace durch
  FBorderPanel.Color          := CL_STRIPE;

  // ---- rechter Bereich: Titel + Beschreibung ----
  FContentArea                := TPanel.Create(Self);
  FContentArea.Parent         := Self;
  FContentArea.Align          := alClient;
  FContentArea.BevelOuter     := bvNone;
  FContentArea.StyleElements  := [];
  FContentArea.ParentBackground := False;
  FContentArea.Color          := CL_TITLE_BG;

  // ---- Titelzeile ----
  FPanelTitle                := TPanel.Create(Self);
  FPanelTitle.Parent         := FContentArea;
  FPanelTitle.Align          := alTop;
  FPanelTitle.Height         := MIN_TITLE_H;
  FPanelTitle.BevelOuter     := bvNone;
  FPanelTitle.StyleElements  := [];
  FPanelTitle.ParentBackground := False;
  FPanelTitle.Color          := CL_TITLE_BG;

  // Badge (alRight, wird vor FLblTitle angelegt -> VCL platziert es rechts)
  FLblBadge                    := TLabel.Create(Self);
  FLblBadge.Parent             := FPanelTitle;
  FLblBadge.Align              := alRight;
  FLblBadge.AutoSize           := True;
  FLblBadge.Font.Color         := CL_BADGE_FG;
  FLblBadge.Font.Style         := [];
  FLblBadge.Font.Name          := 'Segoe UI';
  FLblBadge.Font.Size          := 8;
  FLblBadge.Layout             := tlCenter;
  FLblBadge.Color              := CL_BADGE_BG;
  FLblBadge.Transparent        := False;
  FLblBadge.ParentColor        := False;  // KRITISCH: erbt sonst Parent-Color
  FLblBadge.StyleElements      := [];     // VCL-Theme nicht ueberschreiben
  FLblBadge.AlignWithMargins   := True;
  FLblBadge.Margins.SetBounds(4, 3, 6, 3);

  // Titel (alClient, fuellt den Rest links)
  FLblTitle                    := TLabel.Create(Self);
  FLblTitle.Parent             := FPanelTitle;
  FLblTitle.Align              := alClient;
  FLblTitle.Font.Color         := CL_TITLE_FG;
  FLblTitle.Font.Style         := [fsBold];
  FLblTitle.Font.Name          := 'Segoe UI';
  FLblTitle.Font.Size          := 8;
  FLblTitle.Layout             := tlCenter;
  FLblTitle.Alignment          := taLeftJustify;
  FLblTitle.ParentColor        := False;  // erbt sonst Parent-Color zur Render-Zeit
  FLblTitle.StyleElements      := [];     // VCL-Theme nicht ueberschreiben Font.Color
  FLblTitle.AlignWithMargins   := True;
  FLblTitle.Margins.SetBounds(8, 0, 4, 0);
  FLblTitle.EllipsisPosition   := epEndEllipsis;

  // ---- Beschreibungszeile ----
  FPanelDesc                := TPanel.Create(Self);
  FPanelDesc.Parent         := FContentArea;
  FPanelDesc.Align          := alClient;
  FPanelDesc.BevelOuter     := bvNone;
  FPanelDesc.StyleElements  := [];
  FPanelDesc.ParentBackground := False;
  FPanelDesc.Color          := CL_DESC_BG;

  FLblDesc                    := TLabel.Create(Self);
  FLblDesc.Parent             := FPanelDesc;
  FLblDesc.Align              := alClient;
  FLblDesc.Font.Color         := CL_DESC_FG;
  FLblDesc.Font.Style         := [fsItalic];
  FLblDesc.Font.Name          := 'Segoe UI';
  FLblDesc.Font.Size          := 8;
  FLblDesc.Layout             := tlTop;          // mehrzeilig: oben anliegend
  FLblDesc.Alignment          := taLeftJustify;
  FLblDesc.ParentColor        := False;
  FLblDesc.StyleElements      := [];
  FLblDesc.AlignWithMargins   := True;
  FLblDesc.Margins.SetBounds(8, 4, 8, 4);        // mehr Padding fuer Wrap-Text
  FLblDesc.WordWrap           := True;           // mehrzeilig statt Ellipsis
  FLblDesc.EllipsisPosition   := epNone;
end;

procedure TAnnotationOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Initialer Zustand: WS_POPUP. Wird beim ersten ShowAt(AEditor) ueber
  // EmbedIntoEditor zu WS_CHILD umgewandelt (Style-Wechsel + SetParent).
  // Bis dahin: kein TOPMOST, kein TOOLWINDOW — neutrales Popup, das nie
  // selbststaendig gezeigt wird (ShowAt setzt Bounds + Visible erst NACH
  // Embedding).
  Params.Style     := WS_POPUP;
  Params.ExStyle   := WS_EX_NOACTIVATE;
  Params.WndParent := Application.Handle;
end;

procedure TAnnotationOverlay.EmbedIntoEditor(AEditorHandle: HWND);
var
  Style   : NativeInt;
  ExStyle : NativeInt;
begin
  // Hot-swap des Window-Styles: WS_POPUP -> WS_CHILD. Win32 erlaubt das
  // explizit zur Laufzeit (siehe MSDN SetWindowLongPtr GWL_STYLE).
  // Erforderlich: SWP_FRAMECHANGED damit der Style-Cache invalidiert wird.
  if AEditorHandle = FCurrentParent then Exit;  // bereits eingebettet

  if not HandleAllocated then HandleNeeded;

  Style   := GetWindowLongPtr(Handle, GWL_STYLE);
  ExStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);

  // WS_POPUP weg, WS_CHILD + WS_CLIPSIBLINGS rein.
  Style := (Style and not WS_POPUP) or WS_CHILD or WS_CLIPSIBLINGS;
  // WS_EX_TOPMOST weg — als Child sind wir per definitionem geclippt.
  ExStyle := ExStyle and not (WS_EX_TOPMOST or WS_EX_TOOLWINDOW);

  SetWindowLongPtr(Handle, GWL_STYLE, Style);
  SetWindowLongPtr(Handle, GWL_EXSTYLE, ExStyle);

  Winapi.Windows.SetParent(Handle, AEditorHandle);

  // SWP_FRAMECHANGED: Win32 informieren dass sich Style geaendert hat,
  // sonst greift der Wechsel erst beim naechsten Window-Event.
  SetWindowPos(Handle, 0, 0, 0, 0, 0,
    SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
    SWP_NOACTIVATE or SWP_NOOWNERZORDER);

  FCurrentParent := AEditorHandle;
end;

procedure TAnnotationOverlay.ShowAt(AEditor: TWinControl;
  AClientX, AClientY, AWidth, ALineH: Integer;
  const ATitle, ADesc, ABadge: string;
  AAccentColor: TColor);
var
  TitleH, DescH, TotalH    : Integer;
  BadgeCaption             : string;
  WasVisible               : Boolean;
  DC                       : HDC;
  OldFont                  : HFONT;
  CalcRect                 : TRect;
  EffAccent                : TColor;
  TitleBg, BadgeBg         : TColor;
  WindowBase               : TColor;
begin
  // Editor muss da sein — sonst keine Sinn das Overlay zu zeigen.
  if not Assigned(AEditor) or not AEditor.HandleAllocated then Exit;

  // Hoehen DPI-bewusst aus der Editor-Zeilenhoehe ableiten.
  TitleH := Max(MIN_TITLE_H, ALineH);

  // Description-Hoehe dynamisch via DrawText DT_CALCRECT messen — Wrap-Text
  // mit der tatsaechlichen Schriftmetrik. Nutzt FLblDesc.Font auf einem
  // temporaeren DC; CalcRect.Bottom liefert die exakt benoetigte Pixelhoehe.
  DC := GetDC(0);
  try
    OldFont := SelectObject(DC, FLblDesc.Font.Handle);
    try
      // Verfuegbare Breite: Form-Breite minus Stripe minus Label-Margins.
      CalcRect := Rect(0, 0,
        AWidth - STRIPE_W - FLblDesc.Margins.Left - FLblDesc.Margins.Right, 0);
      Winapi.Windows.DrawText(DC, PChar(ADesc), Length(ADesc), CalcRect,
        DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
      DescH := (CalcRect.Bottom - CalcRect.Top) + 2 * DESC_PAD_V;
    finally
      SelectObject(DC, OldFont);
    end;
  finally
    ReleaseDC(0, DC);
  end;
  // Auf Min/Max clampen: mind. 1 Zeile, max. MAX_DESC_H Pixel.
  DescH := Max(MIN_DESC_H, Min(DescH, MAX_DESC_H));

  TotalH := TitleH + DescH;

  BadgeCaption := '  ' + ABadge + '  ';

  // KRITISCH zuerst: Embedding sicherstellen, BEVOR wir Bounds/Visible
  // setzen. Sonst wuerde VCL das Form als Top-Level-Popup positionieren
  // und unsere editor-client-Koordinaten als Screen-Koordinaten missdeuten.
  EmbedIntoEditor(AEditor.Handle);

  // Editor-Theme-Farbe via offizielle ToolsAPI (nicht StyleServices, das
  // wuerde die IDE-Frame-Theme-Farbe liefern). DX.Blame nutzt das gleiche
  // Pattern fuer themed Editor-Overlays.
  WindowBase := GetEditorThemeBgColor;
  if WindowBase = clNone then
    WindowBase := StyleServices.GetSystemColor(clWindow);  // Fallback

  WasVisible := Visible and IsWindowVisible(Handle);

  // Cache-Pruefung: Nur greift wenn alle Parameter UND der Editor-Theme-
  // Hintergrund unveraendert sind. WindowBase im Cache ist der Trigger fuer
  // automatische Re-Berechnung nach Theme-Wechsel.
  if WasVisible
    and (AClientX = FLastX) and (AClientY = FLastY)
    and (AWidth   = FLastW) and (ALineH   = FLastLineH)
    and (ATitle   = FLastTitle) and (ADesc = FLastDesc)
    and (ABadge   = FLastBadge) and (AAccentColor = FLastAccent)
    and (WindowBase = FLastWindowBase)
  then
    Exit;

  // Title-BG ~ 70% Akzent + 30% Editor-BG = saturierte Severity-Farbe in
  //           der Editor-Theme-Helligkeit, weisser Text gut kontrastiert.
  // Badge-BG ~ 90% Akzent + 10% Editor-BG = fast voller Akzent.
  // Title/Badge-FG = clWhite fix — auf saturiertem Akzent in jeder Severity
  //                  zuverlaessig lesbar (User-Wunsch: Warn-Text soll weiss sein).
  EffAccent := AAccentColor;
  if EffAccent = clNone then
    EffAccent := CL_STRIPE;
  TitleBg := BlendColor(WindowBase, EffAccent, 0.70);
  BadgeBg := BlendColor(WindowBase, EffAccent, 0.90);
  FBorderPanel.Color   := EffAccent;
  FPanelTitle.Color    := TitleBg;
  FContentArea.Color   := TitleBg;
  FLblBadge.Color      := BadgeBg;
  FLblTitle.Font.Color := clWhite;
  FLblBadge.Font.Color := clWhite;
  // Description-Bereich: Editor-Hintergrund + dezent abgeschwaechter Text
  // (auto-kontrast — neutraler Bereich der dem Editor-Theme folgt).
  // Im Dark-Theme bewusst heller (0.75) als im Light-Theme (0.55), weil
  // Helligkeitswahrnehmung auf dunklem Hintergrund schneller "verschwindet".
  FPanelDesc.Color     := WindowBase;
  if IsLightColor(WindowBase) then
    FLblDesc.Font.Color := BlendColor(WindowBase, clBlack, 0.55)  // mittelgrau auf hell
  else
    FLblDesc.Font.Color := BlendColor(WindowBase, clWhite, 0.75); // hellgrau auf dunkel

  // Inhalt setzen — VCL invalidiert die Labels automatisch beim Caption-Set.
  // Symbol ueber _() durch dxgettext lokalisierbar (Default U+26A0 = ⚠).
  FLblTitle.Caption    := _(#$26A0) + '  ' + ATitle;
  FLblDesc.Caption     := ADesc;
  FLblBadge.Caption    := BadgeCaption;
  FLblBadge.Visible    := ABadge <> '';
  FPanelTitle.Height   := TitleH;  // dynamisches DPI-Sizing

  // Cache aktualisieren
  FLastX          := AClientX;
  FLastY          := AClientY;
  FLastW          := AWidth;
  FLastLineH      := ALineH;
  FLastTitle      := ATitle;
  FLastDesc       := ADesc;
  FLastBadge      := ABadge;
  FLastAccent     := AAccentColor;
  FLastWindowBase := WindowBase;

  // Position via raw Win32 — SetBounds wuerde VCL-Logik triggern die
  // fuer ein WS_CHILD-zwangs-eingebettetes-Form unzuverlaessig ist.
  // Editor-Client-Koordinaten gehen direkt in MoveWindow.
  Winapi.Windows.MoveWindow(Handle, AClientX, AClientY, AWidth, TotalH, True);

  // Visible:=True damit VCL und Win32 synchron sind — sonst zeichnet VCL
  // die TGraphicControl-Children (TLabel) nicht.
  if not Visible then
    Visible := True
  else
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW or RDW_ERASE);
end;

procedure TAnnotationOverlay.HideOverlay;
begin
  // Cache leeren damit das naechste ShowAt immer neu zeichnet.
  FLastX := -1; FLastY := -1;
  if Visible then
    Visible := False;
end;

{ ---- Lifecycle ---- }

procedure RegisterAnnotationOverlay;
begin
  if not Assigned(GAnnotationOverlay) then
    GAnnotationOverlay := TAnnotationOverlay.Create(nil);
end;

procedure UnregisterAnnotationOverlay;
begin
  FreeAndNil(GAnnotationOverlay);
end;

end.
