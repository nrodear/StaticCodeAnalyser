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
//   nach unten heraus. Workaround in ShowAt: bei wenig Platz unten oberhalb
//   der Zeile rendern.
//
// Hide-on-mouse-leave (siehe TFindingEditorEvents.HoverWatch in
// uIDELineHighlighter.pas) sorgt dafuer, dass das Overlay verschwindet
// sobald die Maus den Editor verlaesst.
//
// Design exakt nach Mockup:
//   Titelzeile: dunkelroter Hintergrund (#2A1A1A), helles Rosa-Text (#E8A0A0),
//               fett, Warning-Glyph links, Badge ("BUG · ERROR") rechts.
//   Beschreibungszeile: sehr dunkles Grau (#222), mittelgrau kursiv (#888).
//   Linker Rand: 3px rot (#D02000) — korrespondiert zum PaintLine-Stripe.
//
// ShowAt empfaengt ALineH (Zeilen-Pixelhoehe aus Context.EditorState.CharHeight)
// fuer DPI-bewusstes Sizing. Position + Inhalt werden gecacht: bei identischen
// Parametern wird der Win32-Aufruf uebersprungen, was Flimmern bei schnellen
// MouseMove-Events vermeidet.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;

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
    procedure ShowAt(AEditor: TWinControl;
      AClientX, AClientY, AWidth, ALineH: Integer;
      const ATitle, ADesc, ABadge: string);
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

  // ---- 3px linker Rand (Farb-Stripe) ----
  FBorderPanel            := TPanel.Create(Self);
  FBorderPanel.Parent     := Self;
  FBorderPanel.Align      := alLeft;
  FBorderPanel.Width      := STRIPE_W;
  FBorderPanel.BevelOuter := bvNone;
  FBorderPanel.Color      := CL_STRIPE;

  // ---- rechter Bereich: Titel + Beschreibung ----
  FContentArea            := TPanel.Create(Self);
  FContentArea.Parent     := Self;
  FContentArea.Align      := alClient;
  FContentArea.BevelOuter := bvNone;
  FContentArea.Color      := CL_TITLE_BG;

  // ---- Titelzeile ----
  FPanelTitle            := TPanel.Create(Self);
  FPanelTitle.Parent     := FContentArea;
  FPanelTitle.Align      := alTop;
  FPanelTitle.Height     := MIN_TITLE_H;
  FPanelTitle.BevelOuter := bvNone;
  FPanelTitle.Color      := CL_TITLE_BG;

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
  FLblTitle.AlignWithMargins   := True;
  FLblTitle.Margins.SetBounds(8, 0, 4, 0);
  FLblTitle.EllipsisPosition   := epEndEllipsis;

  // ---- Beschreibungszeile ----
  FPanelDesc            := TPanel.Create(Self);
  FPanelDesc.Parent     := FContentArea;
  FPanelDesc.Align      := alClient;
  FPanelDesc.BevelOuter := bvNone;
  FPanelDesc.Color      := CL_DESC_BG;

  FLblDesc                    := TLabel.Create(Self);
  FLblDesc.Parent             := FPanelDesc;
  FLblDesc.Align              := alClient;
  FLblDesc.Font.Color         := CL_DESC_FG;
  FLblDesc.Font.Style         := [fsItalic];
  FLblDesc.Font.Name          := 'Segoe UI';
  FLblDesc.Font.Size          := 8;
  FLblDesc.Layout             := tlCenter;
  FLblDesc.Alignment          := taLeftJustify;
  FLblDesc.AlignWithMargins   := True;
  FLblDesc.Margins.SetBounds(8, 1, 4, 1);
  FLblDesc.EllipsisPosition   := epEndEllipsis;
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
  const ATitle, ADesc, ABadge: string);
var
  TitleH, DescH, TotalH : Integer;
  BadgeCaption          : string;
  WasVisible            : Boolean;
begin
  // Editor muss da sein — sonst keine Sinn das Overlay zu zeigen.
  if not Assigned(AEditor) or not AEditor.HandleAllocated then Exit;

  // Hoehen DPI-bewusst aus der Editor-Zeilenhoehe ableiten.
  TitleH := Max(MIN_TITLE_H, ALineH);
  DescH  := Max(MIN_DESC_H, ALineH - 2);
  TotalH := TitleH + DescH;

  BadgeCaption := '  ' + ABadge + '  ';

  // KRITISCH zuerst: Embedding sicherstellen, BEVOR wir Bounds/Visible
  // setzen. Sonst wuerde VCL das Form als Top-Level-Popup positionieren
  // und unsere editor-client-Koordinaten als Screen-Koordinaten missdeuten.
  EmbedIntoEditor(AEditor.Handle);

  WasVisible := Visible and IsWindowVisible(Handle);

  // Cache-Pruefung: Nur greift wenn Form bereits sichtbar UND alle Werte
  // identisch sind.
  if WasVisible
    and (AClientX = FLastX) and (AClientY = FLastY)
    and (AWidth   = FLastW) and (ALineH   = FLastLineH)
    and (ATitle   = FLastTitle) and (ADesc = FLastDesc)
    and (ABadge   = FLastBadge)
  then
    Exit;

  // Inhalt setzen — VCL invalidiert die Labels automatisch beim Caption-Set.
  FLblTitle.Caption    := #$26A0 + '  ' + ATitle;  // U+26A0 = ⚠
  FLblDesc.Caption     := ADesc;
  FLblBadge.Caption    := BadgeCaption;
  FLblBadge.Visible    := ABadge <> '';
  FPanelTitle.Height   := TitleH;  // dynamisches DPI-Sizing

  // Cache aktualisieren
  FLastX      := AClientX;
  FLastY      := AClientY;
  FLastW      := AWidth;
  FLastLineH  := ALineH;
  FLastTitle  := ATitle;
  FLastDesc   := ADesc;
  FLastBadge  := ABadge;

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
