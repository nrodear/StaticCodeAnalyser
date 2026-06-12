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
  uAnalyserPalette,  // ACCENT_ERROR / ACCENT_HINT als Default-Akzente
  uAnalyserTheme,    // BlendColor + theme-adaptive Severity-Farben
  uLocalization;     // _() — Symbol/Trennzeichen via dxgettext lokalisierbar

type
  TAnnotationOverlay = class(TForm)
  private
    FBorderPanel    : TPanel;   // 3px linker Rand (Rot)
    FContentArea    : TPanel;   // rechts davon: Titel + Desc + Fix
    FPanelTitle     : TPanel;
    FLblTitle       : TLabel;   // "⚠  Memory Leak – ..."
    FLblBadge       : TLabel;   // "BUG · ERROR" rechts
    // Schliessen-Glyph oben rechts ("✕"). Klick entfernt die aktuell
    // angezeigte Markierung aus GHighlighter (User dismissed false-positive
    // oder "schon manuell gefixed"). Liegt rechts vom Badge.
    FLblClose       : TLabel;
    // Aktuell angezeigte Datei + Zeile - werden in ShowAt gesetzt und vom
    // Close-Klick gebraucht um die richtige Markierung zu loeschen.
    FCurrentFile    : string;
    FCurrentLine    : Integer;
    FPanelDesc      : TPanel;
    FLblDesc        : TLabel;
    // "Nachher / After"-Hinweis-Block (Fix-Hint aus uFixHint.After).
    // Eigenes Panel mit eigenem Header-Label und monospace-Body, damit
    // Code-Snippets visuell sauber vom Beschreibungstext getrennt sind.
    // Nicht-sichtbar wenn der Detektor keinen After-Code liefert.
    FPanelFix       : TPanel;
    FLblFixHeader   : TLabel;   // "✓ Nachher" / "✓ After"
    FLblFix         : TLabel;   // After-Code, Consolas-monospace
    // Cache: letzter ShowAt-Aufruf – verhindert redundante Win32-Aufrufe.
    FLastX, FLastY, FLastW, FLastLineH : Integer;
    FLastTitle, FLastDesc, FLastBadge, FLastFix : string;
    FLastAccent                        : TColor;  // Severity-Akzent
    FLastWindowBase                    : TColor;  // Editor-Theme-BG (Cache-Invalidator!)
    // Editor in den wir aktuell als WS_CHILD eingebettet sind. 0 = noch
    // nicht eingebettet (initialer WS_POPUP-Zustand).
    FCurrentParent : HWND;
    // Drei-Stufen-Morph aus der permanenten Mini-Inline-Badge ins volle
    // Overlay:
    //   Stage 0 -> 1 nach 80ms : Window-W waechst von FStartWidth
    //                            (Mini-Badge-Breite) auf FLastW (volle
    //                            Title-Bar-Breite). H bleibt FCollapsedHeight.
    //   Stage 1 -> 2 nach 170ms (250ms gesamt): Window-H waechst von
    //                            FCollapsedHeight auf FExpandedHeight.
    //   Stage 2 = final.
    // Wenn AStartWidth=0 (= kein W-Morph gewuenscht), startet ShowAt
    // direkt in Stage 1 und springt nur die 250ms-H-Auffaltung.
    FExpandTimer    : TTimer;
    FCollapsedHeight: Integer;
    FExpandedHeight : Integer;
    FStartWidth     : Integer;  // Mini-Badge-Width fuer Stage 0
    FExpandStage    : Integer;  // 0=W-morph pending, 1=H-morph pending, 2=final
    procedure EmbedIntoEditor(AEditorHandle: HWND);
    procedure CloseLblClick(Sender: TObject);
    procedure OnExpandTick(Sender: TObject);
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
    // AFix: zusaetzlich der "Nachher"-Code-Block aus uFixHint.After.
    // Leer-String -> Fix-Block wird unsichtbar, Overlay-Hoehe entsprechend
    // kuerzer. Multiline OK (sLineBreak intern); WordWrap an, Monospace.
    // AFileName + ALineNo identifizieren die aktuell gezeigte Markierung -
    // werden vom Close-Glyph-Klick gebraucht um genau diese eine Markierung
    // aus GHighlighter zu entfernen. Beide leer = Close-Glyph hidden.
    // AStartWidth (optional, Default 0) - wenn > 0, startet das Overlay
    // mit dieser schmalen Breite (= Mini-Inline-Badge-Width). Nach 80ms
    // expandiert die W auf AWidth (Stufe 1), nach weiteren 170ms expandiert
    // H auf TotalH (Stufe 2). So entsteht ein zweistufiger Morph aus der
    // permanenten Mini-Badge in das volle Overlay - kein Color/Position-Jump
    // beim Hover-Beginn, dafuer 2 sichtbare Wachstumsphasen.
    // AStartWidth=0 -> kein W-Morph (sofort volle AWidth + 250ms-H-Auffalt).
    procedure ShowAt(AEditor: TWinControl;
      AClientX, AClientY, AWidth, ALineH: Integer;
      const ATitle, ADesc, ABadge: string;
      AAccentColor: TColor = clNone;
      const AFix: string = '';
      const AFileName: string = '';
      ALineNo: Integer = 0;
      AStartWidth: Integer = 0);
    procedure HideOverlay;
    // True wenn AScreenPos in einem AZonePx x AZonePx grossen Quadrat um den
    // Close-[x]-Button (Mittelpunkt) liegt. Wird von uIDELineHighlighter
    // genutzt um zu entscheiden ob das Overlay sichtbar bleiben soll wenn
    // die Maus die Code-Zeile verlassen hat. Default-Zone 50 px.
    function IsCursorNearClose(const AScreenPos: TPoint;
      AZonePx: Integer = 50): Boolean;
  end;

var
  GAnnotationOverlay : TAnnotationOverlay = nil;

procedure RegisterAnnotationOverlay;
procedure UnregisterAnnotationOverlay;

// Liefert das Emoji-Prefix fuer den TypeText im Badge.
// Erkennt Praefix (case-insensitive) der englischen TLeakFinding.TypeText-
// Strings: Bug / Code Smell / Vulnerability / Security Hotspot /
// Code Duplication / Read Error.
// Astral-Plane-Glyphen werden als UTF-16-Surrogat-Paare geliefert -
// werden vom OS-Font-Linking (Segoe UI -> Segoe UI Emoji) gerendert.
// Liefert '' wenn TypeText unbekannt - Caller faellt dann auf Text-only.
function BadgeIcon(const ABadge: string): string;

implementation

// noinspection-file ConcatToFormat, EmptyExcept, GodClass, LargeClass
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uIDELineHighlighter;   // GHighlighter (implementation-only - vermeidet
                         // den Zyklus mit dem interface-uses dort).

function BadgeIcon(const ABadge: string): string;
var
  Low : string;
begin
  Low := LowerCase(ABadge);
  if      Low.StartsWith('bug')                then Result := #$D83D#$DC1E  // 🐞
  else if Low.StartsWith('code smell')         then Result := #$D83D#$DCA8  // 💨
  else if Low.StartsWith('vulnerability')      then Result := #$D83D#$DD13  // 🔓
  else if Low.StartsWith('security hotspot')   then Result := #$D83D#$DD25  // 🔥
  else if Low.StartsWith('code duplication')   then Result := #$D83D#$DCD1  // 📑
  else if Low.StartsWith('read error')         then Result := #$274C        // ❌
  else                                              Result := '';
end;

const
  STRIPE_W       = 3;
  // Mindesthoehen in Pixeln (96 DPI-Baseline); ShowAt skaliert dynamisch.
  MIN_TITLE_H    = 20;
  MIN_DESC_H     = 18;
  // Maximale Description-Hoehe in Pixeln — verhindert dass das Overlay
  // halb-bildschirmgross wird bei sehr langen Texten. ~220px deckt
  // ca. 12 Zeilen Segoe UI 9pt ab. Wert ist auf den Multi-Finding-Summary
  // ausgelegt (Bullet-Liste mit allen Befunden einer Zeile) - bei
  // einzelnen Findings wird die exakte Hoehe per DT_CALCRECT bestimmt.
  MAX_DESC_H     = 220;
  // Vertikales Padding der Description (oben + unten) in Pixeln.
  DESC_PAD_V     = 8;

// Theme-aware Default-Farben fuer den Constructor.
//
// Die echten Color-Werte (BG/FG/Stripe/Badge) werden in ShowAt aus der
// Severity + dem aktiven Editor-Theme via BlendColor neu berechnet -
// die Konstruktor-Defaults sind nur fuer den Moment zwischen Create()
// und der ersten ShowAt-Anwendung relevant.
//
// Vorher: hartcodierte dunkle Hex-Werte (CL_TITLE_BG/CL_DESC_BG vor dem
// Theme-Audit 2026-05-18) - die haben auf einem hellen IDE-Theme einen
// kurzen dunklen Flash erzeugt wenn der Overlay angezeigt wurde bevor
// ShowAt seinen ersten Paint-Pass abgeschlossen hatte. Jetzt holen wir
// die Defaults aus dem aktiven VCL-Style (StyleServices.GetSystemColor)
// und der Severity-Palette (uAnalyserPalette.ACCENT_*), sodass ein
// eventueller Flash zumindest theme-konform ist.
function DefaultSurface: TColor;
begin
  Result := StyleServices.GetSystemColor(clWindow);
end;

function DefaultText: TColor;
begin
  Result := StyleServices.GetSystemColor(clWindowText);
end;

function DefaultBadgeBg: TColor;
// Akzent-getoeneter Badge-Hintergrund. Saturierter Rot-Hauch ueber dem
// Theme-Surface - matched die spaetere ShowAt-Logik die BlendColor
// (Window, Accent, 0.9) verwendet.
begin
  Result := BlendColor(StyleServices.GetSystemColor(clWindow),
                       ACCENT_ERROR, 0.9);
end;

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
  Color       := DefaultSurface;
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
  FBorderPanel.Color          := ACCENT_ERROR;

  // ---- rechter Bereich: Titel + Beschreibung ----
  FContentArea                := TPanel.Create(Self);
  FContentArea.Parent         := Self;
  FContentArea.Align          := alClient;
  FContentArea.BevelOuter     := bvNone;
  FContentArea.StyleElements  := [];
  FContentArea.ParentBackground := False;
  FContentArea.Color          := DefaultSurface;

  // ---- Titelzeile ----
  FPanelTitle                := TPanel.Create(Self);
  FPanelTitle.Parent         := FContentArea;
  FPanelTitle.Align          := alTop;
  FPanelTitle.Height         := MIN_TITLE_H;
  FPanelTitle.BevelOuter     := bvNone;
  FPanelTitle.StyleElements  := [];
  FPanelTitle.ParentBackground := False;
  FPanelTitle.Color          := DefaultSurface;

  // Close-Glyph "✕" ganz links. alLeft + erste Insertion -> liegt am
  // linkesten Rand des Title-Panels. Titel + Badge ruecken um die Close-
  // Button-Breite nach rechts ein.
  // Klick entfernt die aktuell angezeigte Markierung aus GHighlighter.
  FLblClose                    := TLabel.Create(Self);
  FLblClose.Parent             := FPanelTitle;
  FLblClose.Align              := alLeft;
  FLblClose.AutoSize           := False;
  FLblClose.Width              := 22;
  FLblClose.Caption            := #$2715;  // ✕
  FLblClose.Alignment          := taCenter;
  FLblClose.Layout             := tlCenter;
  FLblClose.Font.Color         := DefaultText;  // wird in ShowAt auf Auto-Kontrast gesetzt
  FLblClose.Font.Name          := 'Segoe UI';
  FLblClose.Font.Size          := 9;            // dezenter - frueher 11pt
  FLblClose.Font.Style         := [fsBold];
  FLblClose.Color              := DefaultSurface;
  FLblClose.ParentColor        := False;
  FLblClose.StyleElements      := [];
  FLblClose.Cursor             := crHandPoint;
  FLblClose.ShowHint           := True;
  FLblClose.Hint               := _('Dismiss this finding (remove marker)');
  FLblClose.OnClick            := CloseLblClick;

  // Badge (alRight, wird vor FLblTitle angelegt -> VCL platziert es rechts)
  FLblBadge                    := TLabel.Create(Self);
  FLblBadge.Parent             := FPanelTitle;
  FLblBadge.Align              := alRight;
  FLblBadge.AutoSize           := True;
  FLblBadge.Font.Color         := clWhite;     // wird in ShowAt auf Auto-Kontrast gesetzt
  FLblBadge.Font.Style         := [fsBold];    // wie Mini-Inline-Badge
  FLblBadge.Font.Name          := 'Segoe UI';
  FLblBadge.Font.Size          := 8;           // identisch zur Mini-Inline-Badge
  FLblBadge.Layout             := tlCenter;
  FLblBadge.Color              := DefaultBadgeBg;
  FLblBadge.Transparent        := False;
  FLblBadge.ParentColor        := False;  // KRITISCH: erbt sonst Parent-Color
  FLblBadge.StyleElements      := [];     // VCL-Theme nicht ueberschreiben
  FLblBadge.AlignWithMargins   := True;
  FLblBadge.Margins.SetBounds(4, 1, 6, 3);   // Top 3->1, Bottom bleibt 3
                                             // => Badge ist insgesamt 2 px
                                             // TAELLER als Original-Stand
                                             // (1 px Iteration vom 1.Fix +
                                             // weitere 1 px Iteration jetzt).
                                             // Width bleibt AutoSize an der
                                             // Text-Metrik.

  // Titel (alClient, fuellt den Rest links)
  FLblTitle                    := TLabel.Create(Self);
  FLblTitle.Parent             := FPanelTitle;
  FLblTitle.Align              := alClient;
  FLblTitle.Font.Color         := DefaultText;  // wird in ShowAt auf Auto-Kontrast gesetzt
  FLblTitle.Font.Style         := [fsBold];
  FLblTitle.Font.Name          := 'Segoe UI';
  FLblTitle.Font.Size          := 8;            // identisch zur Mini-Inline-Badge
  FLblTitle.Layout             := tlCenter;
  FLblTitle.Alignment          := taLeftJustify;
  FLblTitle.ParentColor        := False;  // erbt sonst Parent-Color zur Render-Zeit
  FLblTitle.StyleElements      := [];     // VCL-Theme nicht ueberschreiben Font.Color
  FLblTitle.AlignWithMargins   := True;
  FLblTitle.Margins.SetBounds(8, 0, 4, 0);
  FLblTitle.EllipsisPosition   := epEndEllipsis;

  // ---- Beschreibungszeile ----
  // Vorher alClient; jetzt alTop mit dynamischer Hoehe (ShowAt setzt die
  // exakte Pixel-Hoehe), damit darunter Platz fuer das Fix-Panel bleibt.
  FPanelDesc                := TPanel.Create(Self);
  FPanelDesc.Parent         := FContentArea;
  FPanelDesc.Align          := alTop;
  FPanelDesc.BevelOuter     := bvNone;
  FPanelDesc.StyleElements  := [];
  FPanelDesc.ParentBackground := False;
  FPanelDesc.Color          := DefaultSurface;

  FLblDesc                    := TLabel.Create(Self);
  FLblDesc.Parent             := FPanelDesc;
  FLblDesc.Align              := alClient;
  FLblDesc.Font.Color         := DefaultText;
  FLblDesc.Font.Style         := [fsItalic];
  FLblDesc.Font.Name          := 'Segoe UI';
  FLblDesc.Font.Size          := 9;  // +1pt fuer bessere Lesbarkeit
  FLblDesc.Layout             := tlTop;          // mehrzeilig: oben anliegend
  FLblDesc.Alignment          := taLeftJustify;
  FLblDesc.ParentColor        := False;
  FLblDesc.StyleElements      := [];
  FLblDesc.AlignWithMargins   := True;
  FLblDesc.Margins.SetBounds(8, 4, 8, 4);        // mehr Padding fuer Wrap-Text
  FLblDesc.WordWrap           := True;           // mehrzeilig statt Ellipsis
  FLblDesc.EllipsisPosition   := epNone;

  // ---- Fix-Hinweis ("Nachher") ----
  // Eigenes Panel unter der Beschreibung mit kleiner gruener Header-Zeile
  // ("✓ Nachher") und dem After-Code in Monospace. Nicht sichtbar wenn
  // der Detektor keinen After-Code liefert; ShowAt setzt Visible je nach
  // AFix-Parameter.
  FPanelFix                := TPanel.Create(Self);
  FPanelFix.Parent         := FContentArea;
  FPanelFix.Align          := alClient;
  FPanelFix.BevelOuter     := bvNone;
  FPanelFix.StyleElements  := [];
  FPanelFix.ParentBackground := False;
  FPanelFix.Color          := DefaultSurface;
  FPanelFix.Visible        := False;            // bis ShowAt setzt

  FLblFixHeader              := TLabel.Create(Self);
  FLblFixHeader.Parent       := FPanelFix;
  FLblFixHeader.Align        := alTop;
  // Wichtig: das ✓ als #$2713 (Unicode-Code-Point) statt als Literal-
  // Char in der Source. Sonst kommt es zu Mojibake wenn die Source als
  // ANSI/CP-1252 statt UTF-8 gespeichert wurde - die UTF-8-Byte-Sequence
  // E2 9C 93 wird sonst als 'âœ"'/'ãeˆ' o.ae. interpretiert. Bei dem ⚠
  // im Title-Label wurde derselbe Trick verwendet (siehe ShowAt: _(#$26A0)).
  FLblFixHeader.Caption      := #$2713 + ' ' + _('After');
  FLblFixHeader.Font.Color   := ACCENT_HINT; // Palette-Hint-Gruen (theme-konsistent)
  FLblFixHeader.Font.Style   := [fsBold];
  FLblFixHeader.Font.Name    := 'Segoe UI';
  FLblFixHeader.Font.Size    := 9;
  FLblFixHeader.Layout       := tlCenter;
  FLblFixHeader.Alignment    := taLeftJustify;
  FLblFixHeader.ParentColor  := False;
  FLblFixHeader.StyleElements := [];
  FLblFixHeader.AlignWithMargins := True;
  FLblFixHeader.Margins.SetBounds(8, 4, 8, 2);

  FLblFix                    := TLabel.Create(Self);
  FLblFix.Parent             := FPanelFix;
  FLblFix.Align              := alClient;
  FLblFix.Font.Color         := DefaultText;
  FLblFix.Font.Style         := [];
  FLblFix.Font.Name          := 'Consolas';     // Monospace fuer Code
  FLblFix.Font.Size          := 9;
  FLblFix.Layout             := tlTop;
  FLblFix.Alignment          := taLeftJustify;
  FLblFix.ParentColor        := False;
  FLblFix.StyleElements      := [];
  FLblFix.AlignWithMargins   := True;
  FLblFix.Margins.SetBounds(8, 0, 8, 6);
  FLblFix.WordWrap           := True;
  FLblFix.EllipsisPosition   := epNone;

  // Morph-Timer: ShowAt setzt das Intervall fuer die naechste Stufe (80ms
  // fuer Stage 0->1 W-grow, dann 170ms fuer Stage 1->2 H-grow).
  // Owner = Self -> wird mit dem Form freigegeben.
  FExpandTimer          := TTimer.Create(Self);
  FExpandTimer.Interval := 250;
  FExpandTimer.Enabled  := False;
  FExpandTimer.OnTimer  := OnExpandTick;
  FExpandStage          := 2;       // initialer Zustand: nichts zu morphen
  FStartWidth           := 0;
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
  AAccentColor: TColor;
  const AFix: string;
  const AFileName: string;
  ALineNo: Integer;
  AStartWidth: Integer);
const
  FIX_HEADER_H = 22;  // kleine "✓ After"-Header-Zeile
  MAX_FIX_H    = 200; // ~10 Zeilen Consolas 9pt
var
  TitleH, DescH, FixH, TotalH : Integer;
  BadgeCaption             : string;
  WasVisible               : Boolean;
  DC                       : HDC;
  EffAccent                : TColor;
  TitleBg, BadgeBg         : TColor;
  HeaderFg                 : TColor;     // Auto-Kontrast fuer Schrift auf EffAccent
  WindowBase               : TColor;
  HasFix                   : Boolean;

  function MeasureWrapped(const AText: string; AFont: TFont): Integer;
  // DT_CALCRECT mit der gegebenen Font-Metrik; verfuegbare Breite ist die
  // Form-Breite minus Stripe minus Default-Margins (8 + 8). Liefert die
  // exakt benoetigte Pixel-Hoehe fuer Wrap-Text.
  var
    Inner  : TRect;
    PrevFn : HFONT;
  begin
    Result := 0;
    if AText = '' then Exit;
    Inner := Rect(0, 0, AWidth - STRIPE_W - 16, 0);
    PrevFn := SelectObject(DC, AFont.Handle);
    try
      Winapi.Windows.DrawText(DC, PChar(AText), Length(AText), Inner,
        DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
      Result := Inner.Bottom - Inner.Top;
    finally
      SelectObject(DC, PrevFn);
    end;
  end;

begin
  // Editor muss da sein — sonst keine Sinn das Overlay zu zeigen.
  if not Assigned(AEditor) or not AEditor.HandleAllocated then Exit;

  HasFix := Trim(AFix) <> '';

  // Hoehen DPI-bewusst aus der Editor-Zeilenhoehe ableiten.
  TitleH := Max(MIN_TITLE_H, ALineH);

  // Description- und Fix-Hoehe dynamisch via DT_CALCRECT auf einem
  // temporaeren Screen-DC messen.
  DC := GetDC(0);
  try
    DescH := MeasureWrapped(ADesc, FLblDesc.Font) + 2 * DESC_PAD_V;
    if HasFix then
      FixH := FIX_HEADER_H + MeasureWrapped(AFix, FLblFix.Font) + DESC_PAD_V
    else
      FixH := 0;
  finally
    ReleaseDC(0, DC);
  end;
  // Auf Min/Max clampen.
  DescH := Max(MIN_DESC_H, Min(DescH, MAX_DESC_H));
  if HasFix then
    FixH := Max(FIX_HEADER_H + MIN_DESC_H, Min(FixH, MAX_FIX_H));

  TotalH := TitleH + DescH + FixH;

  // Icon-Prefix vor dem Badge: '🐞 Bug · Error' (analog Mini-Inline-Badge).
  // Wenn TypeText nicht erkannt wird, faellt BadgeIcon auf '' zurueck.
  if BadgeIcon(ABadge) <> '' then
    BadgeCaption := '  ' + BadgeIcon(ABadge) + ' ' + ABadge + '  '
  else
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
    and (AFix     = FLastFix)
    and (WindowBase = FLastWindowBase)
  then
    Exit;

  // ZIEL: Title-Zeile sieht GENAUSO aus wie die permanente Mini-Inline-Badge
  // in uIDELineHighlighter.DrawMiniInfoBar (gleiche BG-Farbe, gleicher
  // Auto-Kontrast, gleiche Schrift, gleicher Pfeil-Prefix). So entsteht beim
  // Hover ein nahtloser Morph: die Mini-Badge wird durch die wachsende
  // Title-Zeile abgeloest ohne Color-Jump.
  //
  // Vorher: TitleBg=70%Akzent, BadgeBg=90%Akzent, Schrift immer weiss.
  // Jetzt: BG voller Akzent, Schrift = Auto-Kontrast (schwarz/weiss) nach
  // ITU-R-BT.601-Luminanz.
  EffAccent := AAccentColor;
  if EffAccent = clNone then
    EffAccent := ACCENT_ERROR;
  TitleBg := EffAccent;
  BadgeBg := EffAccent;
  if IsLightColor(EffAccent) then
    HeaderFg := clBlack
  else
    HeaderFg := clWhite;
  FBorderPanel.Color   := EffAccent;
  FPanelTitle.Color    := TitleBg;
  FContentArea.Color   := TitleBg;
  FLblBadge.Color      := BadgeBg;
  FLblTitle.Font.Color := HeaderFg;
  FLblBadge.Font.Color := HeaderFg;
  FLblClose.Color      := EffAccent;
  FLblClose.Font.Color := HeaderFg;
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
  // Pfeil-Prefix wurde entfernt (User-Request) - Icon sitzt jetzt im Badge.
  FLblTitle.Caption    := ATitle;
  FLblDesc.Caption     := ADesc;
  FLblBadge.Caption    := BadgeCaption;
  FLblBadge.Visible    := ABadge <> '';
  FPanelTitle.Height   := TitleH;  // dynamisches DPI-Sizing
  FPanelDesc.Height    := DescH;   // explizite Hoehe seit alTop

  // Fix-Block nur wenn AFix nicht-leer; Panel-Visible setzt VCL um, das
  // alClient-Layout kollabiert automatisch wenn das Panel unsichtbar ist.
  if HasFix then
  begin
    FLblFix.Caption    := AFix;
    FPanelFix.Color    := WindowBase;     // gleiche Basis wie Description
    FLblFix.Font.Color := FLblDesc.Font.Color;
    FPanelFix.Visible  := True;
  end
  else
  begin
    FLblFix.Caption    := '';
    FPanelFix.Visible  := False;
  end;

  // Cache aktualisieren
  FLastX          := AClientX;
  FLastY          := AClientY;
  FLastW          := AWidth;
  FLastLineH      := ALineH;
  FLastTitle      := ATitle;
  FLastDesc       := ADesc;
  FLastBadge      := ABadge;
  FLastFix        := AFix;
  FLastAccent     := AAccentColor;
  FLastWindowBase := WindowBase;

  // DREI-STUFEN-MORPH:
  // Stage 0 (sofort) - Overlay startet auf Mini-Badge-Breite (AStartWidth)
  //   und Title-Hoehe; visuell deckungsgleich mit der Mini-Inline-Badge.
  // Stage 0->1 nach 80ms via FExpandTimer - W expandiert auf AWidth.
  //   Title-Text + Close-Glyph werden im neuen W-Raum sichtbar.
  // Stage 1->2 nach weiteren 170ms (= 250ms gesamt nach Show) - H expandiert
  //   von TitleH auf TotalH. Desc/Fix-Panels werden sichtbar.
  // Wenn AStartWidth=0: Stage 0 wird uebersprungen, direkt Stage 1
  //   (alte Default-Auffalt - kein W-Morph).
  FCollapsedHeight := TitleH;
  FExpandedHeight  := TotalH;
  FStartWidth      := AStartWidth;

  // Position via raw Win32 — SetBounds wuerde VCL-Logik triggern die
  // fuer ein WS_CHILD-zwangs-eingebettetes-Form unzuverlaessig ist.
  // Editor-Client-Koordinaten gehen direkt in MoveWindow.
  if AStartWidth > 0 then
  begin
    Winapi.Windows.MoveWindow(Handle, AClientX, AClientY, AStartWidth, TitleH, True);
    FExpandStage := 0;             // erster Tick wird W-grow machen
    FExpandTimer.Interval := 80;
  end
  else
  begin
    Winapi.Windows.MoveWindow(Handle, AClientX, AClientY, AWidth, TitleH, True);
    FExpandStage := 1;             // erster Tick wird H-grow machen
    FExpandTimer.Interval := 250;
  end;

  // Visible:=True damit VCL und Win32 synchron sind — sonst zeichnet VCL
  // die TGraphicControl-Children (TLabel) nicht.
  if not Visible then
    Visible := True
  else
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW or RDW_ERASE);

  // Timer (re)starten - Enabled:=False vor True erzwingt Countdown-Reset.
  FExpandTimer.Enabled := False;
  // Timer braucht es nur wenn noch etwas zu wachsen ist.
  if (FExpandStage = 0) or ((FExpandStage = 1) and (TotalH > TitleH)) then
    FExpandTimer.Enabled := True;

  // Identitaet der gerade angezeigten Markierung fuer Close-Klick speichern.
  // Leerer File-Name -> Close-Glyph ausblenden (Caller hat keine Datei
  // mitgegeben, z.B. Test-Fixtures).
  FCurrentFile := AFileName;
  FCurrentLine := ALineNo;
  if Assigned(FLblClose) then
    FLblClose.Visible := (AFileName <> '') and (ALineNo > 0);
end;

procedure TAnnotationOverlay.CloseLblClick(Sender: TObject);
// Entfernt die aktuell angezeigte Markierung aus GHighlighter und versteckt
// das Overlay. Greift direkt auf den globalen Highlighter zu - der lebt
// per Definition laenger als das Overlay (beide werden in
// UnregisterAnalyserDockableForm aufgeraeumt). Frame-Grid bleibt unsynced
// (Befund ist dort noch in der Liste); das ist OK als MVP - User kann
// "Analyse starten" klicken um die Liste zu refreshen.
begin
  if (FCurrentFile <> '') and (FCurrentLine > 0)
     and Assigned(GHighlighter) then
    GHighlighter.RemoveMark(FCurrentFile, FCurrentLine);
  HideOverlay;
end;

procedure TAnnotationOverlay.HideOverlay;
begin
  // Pending Auffalten cancellen - sonst expandiert ein hidden Form-Handle
  // und kann beim naechsten Show kurz als grosser Stub aufflackern.
  if Assigned(FExpandTimer) then
    FExpandTimer.Enabled := False;
  // Cache leeren damit das naechste ShowAt immer neu zeichnet.
  FLastX := -1; FLastY := -1;
  if Visible then
    Visible := False;
end;

procedure TAnnotationOverlay.OnExpandTick(Sender: TObject);
// Zwei-Stufen-State-Machine fuer den Morph aus der Mini-Badge in das
// volle Overlay. ShowAt setzt FExpandStage und Interval; jeder Tick
// schiebt eine Stufe weiter.
// Defensive: HideOverlay koennte zwischenzeitlich gefeuert haben.
begin
  FExpandTimer.Enabled := False;
  if not Visible then Exit;

  case FExpandStage of
    0:
    begin
      // Stage 0 -> 1: W waechst von FStartWidth auf FLastW (volle Breite).
      // Position + H bleiben.
      Winapi.Windows.MoveWindow(Handle, FLastX, FLastY, FLastW, FCollapsedHeight, True);
      RedrawWindow(Handle, nil, 0,
        RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW);
      // Naechste Stufe nach 170ms = 250ms gesamt seit Show.
      FExpandStage := 1;
      FExpandTimer.Interval := 170;
      if FExpandedHeight > FCollapsedHeight then
        FExpandTimer.Enabled := True;
    end;

    1:
    begin
      // Stage 1 -> 2: H waechst von FCollapsedHeight auf FExpandedHeight.
      if FExpandedHeight > FCollapsedHeight then
      begin
        Winapi.Windows.MoveWindow(Handle, FLastX, FLastY, FLastW, FExpandedHeight, True);
        RedrawWindow(Handle, nil, 0,
          RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW);
      end;
      FExpandStage := 2;
    end;
  end;
end;

function TAnnotationOverlay.IsCursorNearClose(const AScreenPos: TPoint;
  AZonePx: Integer): Boolean;
// Screen-Koordinaten des Close-Buttons holen + Quadrat AZonePx x AZonePx
// um seinen Mittelpunkt aufspannen + PtInRect-Test. Bewusst um den
// MITTELPUNKT zentriert (nicht den Button-Rand erweitert) - sonst wird die
// Hot-Zone bei groesserem Button asymmetrisch.
var
  BtnTL, BtnBR : TPoint;
  Center       : TPoint;
  HalfZone     : Integer;
  Zone         : TRect;
begin
  Result := False;
  if not Assigned(FLblClose) or not FLblClose.Visible then Exit;
  // ClientToScreen auf Top-Left + Bottom-Right - liefert das Button-Rect
  // in Screen-Koordinaten ohne auf BoundsRect/ScreenRect-Properties
  // angewiesen zu sein (manche VCL-Versionen liefern dort den Parent-Rect).
  BtnTL := FLblClose.ClientToScreen(Point(0, 0));
  BtnBR := FLblClose.ClientToScreen(Point(FLblClose.Width, FLblClose.Height));
  Center.X := (BtnTL.X + BtnBR.X) div 2;
  Center.Y := (BtnTL.Y + BtnBR.Y) div 2;
  HalfZone := AZonePx div 2;
  Zone := Rect(Center.X - HalfZone, Center.Y - HalfZone,
               Center.X + HalfZone, Center.Y + HalfZone);
  Result := PtInRect(Zone, AScreenPos);
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
