unit uIDEStatsTiles;

// Sonar-Style Stat-Tiles (9-Kachel-Reihe: Errors/Warnings/Hints/Read-Errors/
// Bugs/Security/Duplicates/Cyclomatic/Code-Quality). Aus uIDEAnalyserForm
// extrahiert damit die Form-Unit wieder unter 2500 Zeilen kommt und die
// Tile-Logik fuer den Standalone (Severity-Tiles im Form2) wiederverwendbar
// wird.
//
// Public API:
//   TTilePanel               - TPanel-Subklasse mit 1px Akzent-Rahmen
//   TStatsTilesBuilder.Build - erzeugt 8 Tiles als alLeft-Reihe in
//                              einem Parent-Panel; OUT-Params nehmen die
//                              Count-Labels auf (Caller stored sie in
//                              Frame-Feldern, UpdateStats schreibt direkt
//                              in deren Caption).
//
// Tile-Captions kommen ueber _() aus uLocalization (lokalisierbar). Die
// Akzentfarben fuer die Glyphen (ICON_ERROR etc.) liegen in uAnalyserPalette.

interface

uses
  System.Classes, System.UITypes, System.Generics.Collections,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Themes,
  Vcl.Forms;

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

  // Vereinheitlicht die Hoehe von Toolbar-Controls. Loest die VCL-Quirk
  // dass TComboBox die Align.Height ignoriert und stattdessen aus
  // ItemHeight + Frame-Padding eine eigene Hoehe berechnet. Buttons/Edits
  // respektieren Height direkt - Apply() setzt fuer beide das Richtige.
  //
  // Verwendung im Constructor (UnifCtrlH einmalig aus Self.Font ableiten):
  //   UnifCtrlH := TToolbarSizing.HeightForFont(Self.Font);
  //   TToolbarSizing.Apply(BtnAnalyse,    UnifCtrlH);
  //   TToolbarSizing.Apply(FFilterCombo,  UnifCtrlH);
  //   TToolbarSizing.ApplyIconButton(FBtnHamburger, ScaleW(BTN_W_ICON), UnifCtrlH);
  TToolbarSizing = class
  public
    // Berechnet eine fuer den Font passende Toolbar-Control-Hoehe.
    // Formel: Abs(Font.Height) + 11. Font.Height ist negativ in Pixel
    // (= -PointSize * CurrentPPI / 72), enthaelt also schon DPI-Scaling.
    // +11 = Border 1+1 + Inset 2+2 + Edit-Padding 2+1.
    // Beispiele bei 96 DPI:
    //   Font.Size=8  -> Font.Height=-11 -> Hoehe 22 px
    //   Font.Size=9  -> Font.Height=-12 -> Hoehe 23 px
    //   Font.Size=10 -> Font.Height=-13 -> Hoehe 24 px
    class function HeightForFont(Font: TFont): Integer; static;
    class procedure Apply(Ctrl: TControl; AHeight: Integer); static;
    // Erzwingt eine quadratische / fix-grosse Icon-Button-Geometrie via
    // Constraints fuer Width UND Height. Garantiert dass Icon-Buttons
    // (Browse "...", Hamburger ☰, Branch-Changes ⎇) im VCL-Theme
    // identisch rendern - die Width-Property alleine kann durch Align,
    // ParentLayout oder Theme-Quirks 1-2 px abweichen.
    class procedure ApplyIconButton(Ctrl: TControl;
      AWidth, AHeight: Integer); static;
  end;

  TStatsTilesBuilder = class
  public
    // Erzeugt einen einzelnen Tile (Icon-Glyph + Count + Caption) im
    // Parent-Container. Liefert das Count-Label zurueck - der Aufrufer
    // schreibt spaeter in Caption (z.B. '5' fuer 5 Errors).
    class function MakeTile(AOwner: TComponent; Parent: TWinControl;
      const Caption, Glyph: string; IconColor: TColor;
      AWidth: Integer): TLabel; static;

    // Erzeugt die komplette 9-Kachel-Reihe. Reihenfolge bei alLeft:
    // das zuerst erstellte landet ganz links. OUT-Params bekommen die
    // Count-Labels.
    class procedure Build(AOwner: TComponent; Parent: TPanel;
      out TileError, TileWarn, TileHint, TileFileSev: TLabel;
      out TileBug, TileVuln, TileDup, TileCyclomatic, TileScore: TLabel); static;
  end;

  // 3-Stufen-Responsive-Layout: Stage haengt von der ClientWidth des Root-
  // Containers (typisch: Frame) ab. Jede Stufe zeigt eine Untermenge von
  // Controls; Stage-Wechsel toggled Visible an allen registrierten Controls.
  //
  //   usNarrow  - Frame schmal gedockt (Plugin im IDE-Tool-Window)
  //   usMedium  - kleines floated Window
  //   usFull    - normales floated Window mit voller UI
  //
  // Verwendung:
  //   FResp := TResponsiveLayoutController.Create(Self, Self,
  //              BREAKPOINT_MEDIUM, BREAKPOINT_FULL);
  //   FResp.RegisterCtrl(BtnAlways);                    // immer sichtbar
  //   FResp.RegisterCtrl(LblFilter, usMedium);          // ab MEDIUM
  //   FResp.RegisterCtrl(BtnCancel, usFull);            // nur FULL
  //   FResp.RegisterCtrl(BtnHamburger, usNarrow, usMedium); // <FULL only
  TUiStage = (usNarrow, usMedium, usFull);

  TResponsiveLayoutController = class(TComponent)
  private
    type
      TEntry = record
        Control  : TControl;
        MinStage : TUiStage;
        MaxStage : TUiStage;
      end;
    var
      FRoot              : TWinControl;
      FEntries           : TList<TEntry>;
      FMediumThresholdPx : Integer;     // 96-DPI logisch
      FFullThresholdPx   : Integer;     // 96-DPI logisch
      FOriginalOnResize  : TNotifyEvent;
      FAfterApply  : TNotifyEvent;
      FLastStage         : TUiStage;
      FFirstApply        : Boolean;
    procedure HandleResize(Sender: TObject);
    procedure ApplyVisibility;
    function CurrentStage: TUiStage;
    function ScaleByPPI(AValue: Integer): Integer;
  public
    constructor Create(AOwner: TComponent; ARoot: TWinControl;
      AMediumPx, AFullPx: Integer); reintroduce;
    destructor Destroy; override;

    // Registriert ein Control mit seinem Sichtbarkeitsbereich.
    // Default (kein Min/Max): immer sichtbar in allen Stufen.
    procedure RegisterCtrl(AControl: TControl;
      AMinStage: TUiStage = usNarrow;
      AMaxStage: TUiStage = usFull);

    // Optional: Callback nach JEDEM Resize (nicht nur bei Stage-Wechsel).
    // Ideal fuer Folge-Anpassungen wie AdjustFilterSubPanels / AdjustSearchMinWidth -
    // letzteres haengt von ClientWidth innerhalb einer Stufe ab und muss
    // auch bei Float-Resize ohne Stage-Wechsel feuern.
    property AfterApply: TNotifyEvent
      read FAfterApply write FAfterApply;

    // Manuell triggern (z.B. von FrameResize aus).
    procedure ForceUpdate;
  end;


implementation

uses
  Winapi.Windows, uAnalyserPalette, uAnalyserTheme, uIDEColors, uLocalization;

type
  // Access-Class zum Lesen/Schreiben von TControl.OnResize (protected).
  // TPanel publishet das selbst, aber TWinControl/TFrame nicht direkt -
  // wir wollen den Controller universell auf jedem TWinControl-Root nutzen,
  // also brechen wir die Sichtbarkeit lokal. Standard-VCL-Pattern.
  TControlAccess = class(TControl);

{ TToolbarSizing }

const
  // Padding fuer Buttons/Edits oben+unten (Border + Inset + Edit-Innenabstand).
  // Empirisch kalibriert fuer Segoe UI 8-10pt mit Win11-Theme. Aenderungen
  // sind theme-abhaengig.
  CTRL_VPADDING_PX  = 11;
  // Frame-Padding einer TComboBox: ItemHeight + diese Konstante = Combo.Height.
  COMBO_FRAME_PX    =  6;
  // Fallback-Hoehe wenn Font nicht verfuegbar (entspricht Segoe UI 8pt @ 96 DPI).
  FALLBACK_CTRL_PX  = 22;

class function TToolbarSizing.HeightForFont(Font: TFont): Integer;
// Font.Height kann positiv oder negativ sein. Negativ = nur Glyph-Hoehe
// (Standard fuer Segoe UI in VCL); positiv = inkl. internes Leading.
// Wir wollen die "Cell-Height" -> Abs() ist sicher.
begin
  if not Assigned(Font) then Exit(FALLBACK_CTRL_PX);
  Result := Abs(Font.Height) + CTRL_VPADDING_PX;
end;

class procedure TToolbarSizing.ApplyIconButton(Ctrl: TControl;
  AWidth, AHeight: Integer);
// Vier-Hebel-Strategie: Width-Constraints, Height-Constraints, Width-Property,
// Height-Property. Garantiert dass die Buttons im VCL-Align-Pass nicht durch
// Padding/Theme/Parent-Layout um 1-2 px verschoben werden.
begin
  if not Assigned(Ctrl) then Exit;
  Ctrl.Constraints.MinWidth  := AWidth;
  Ctrl.Constraints.MaxWidth  := AWidth;
  Ctrl.Constraints.MinHeight := AHeight;
  Ctrl.Constraints.MaxHeight := AHeight;
  Ctrl.Width  := AWidth;
  Ctrl.Height := AHeight;
end;

class procedure TToolbarSizing.Apply(Ctrl: TControl; AHeight: Integer);
// Setzt eine einheitliche Hoehe ueber drei Mechanismen:
//   1) Constraints.MinHeight = MaxHeight = AHeight - VCL respektiert das
//      auch bei aktivem Align (alLeft/alClient/alRight). Ohne Constraints
//      wuerden die Children auf Container.ClientHeight gestreckt und das
//      Toolbar-Layout drift bei Font/DPI-Aenderungen.
//   2) Bei TComboBox zusaetzlich ItemHeight - die Combo-Renderhoehe ist
//      ItemHeight + COMBO_FRAME_PX. Constraints alleine genuegt nicht
//      weil VCL die Combo trotzdem auf Font-Naturhoehe zurueck-setzen kann.
//   3) Height redundant setzen damit der initial-Wert direkt stimmt
//      (vor dem ersten Align-Pass).
begin
  if not Assigned(Ctrl) then Exit;
  Ctrl.Constraints.MinHeight := AHeight;
  Ctrl.Constraints.MaxHeight := AHeight;
  if Ctrl is TComboBox then
    TComboBox(Ctrl).ItemHeight := AHeight - COMBO_FRAME_PX;
  Ctrl.Height := AHeight;
end;

function ScaleByPPI(C: TControl; AValue: Integer): Integer;
// Lokaler DPI-Helper: skaliert 96-DPI-Designwerte zur Container-PPI.
// CurrentPPI auf TControl ist ab Delphi 10.3 verfuegbar; falls 0 ->
// fallback 96.
var
  PPI : Integer;
begin
  if not Assigned(C) then Exit(AValue);
  PPI := C.CurrentPPI;
  if PPI <= 0 then PPI := 96;
  Result := MulDiv(AValue, PPI, 96);
end;

{ TTilePanel }

procedure TTilePanel.Paint;
var
  R: TRect;
begin
  inherited; // zeichnet Hintergrund (Color) und Bevel
  Canvas.Brush.Style := bsClear;
  // BorderColor ist ein System-Color-Index. WICHTIG: Vcl.Themes.StyleServices
  // (global, nicht ActiveStyleServices/Theming.StyleServices). Per setTheme-
  // Branch / commit cb3d109-Revert: im Docked-Modus liefert Theming.
  // StyleServices nach Theme-Switch nicht zuverlaessig frische Farben fuer
  // Custom-Paint - Tiles blieben in alten Farben. Die VCL-globale wird durch
  // Theming.ApplyTheme(Form) korrekt mitgezogen.
  Canvas.Pen.Color := StyleServices.GetSystemColor(FBorderColor);
  Canvas.Pen.Width := 2;
  // Geometrie fuer Pen.Width=2 + Rectangle (exclusive Right/Bottom):
  //   Rect(1, 1, W-1, H-1) -> Pen centered auf geometrische Linie:
  //     Top    Linie y=1 deckt Pixel y=0,1
  //     Bottom Linie y=H-1 deckt Pixel y=H-2,H-1
  //     Left   Linie x=1 deckt Pixel x=0,1
  //     Right  Linie x=W-1 deckt Pixel x=W-2,W-1
  //   -> alle 4 Kanten gleich dick 2 px sichtbar.
  // Die Sub-Children (TopRow, CapLbl) haben Margin=2 damit sie nicht
  // ueber die 2-Pixel-Innenkante des Rahmens laufen.
  R := Rect(1, 1, ClientWidth - 1, ClientHeight - 1);
  Canvas.Rectangle(R);
end;

{ TStatsTilesBuilder }

class function TStatsTilesBuilder.MakeTile(AOwner: TComponent;
  Parent: TWinControl; const Caption, Glyph: string;
  IconColor: TColor; AWidth: Integer): TLabel;
// Tile-Farben sind komplett ueber System-Color-Konstanten gefuehrt - der
// VCL-Style mappt sie zur Paint-Zeit auf das aktive IDE-Theme:
//   clBtnFace    = Tile-Hintergrund (Chrome)
//   cl3DDkShadow = duenner Rahmen
//   clBtnText    = Count-Zahl (kraeftig)
//   clGrayText   = Caption darunter (dezenter)
var
  Tile     : TTilePanel;
  TopRow   : TPanel;
  IconLbl  : TLabel;
  CountLbl : TLabel;
  CapLbl   : TLabel;
begin
  Tile := TTilePanel.Create(AOwner);
  Tile.Parent      := Parent;
  Tile.Align       := alLeft;
  Tile.Width       := ScaleByPPI(Parent, AWidth);
  Tile.AlignWithMargins := True;
  Tile.Margins.SetBounds(0, 0, ScaleByPPI(Parent, 3), 0);
  Tile.BevelOuter  := bvNone;
  Tile.BorderStyle := bsNone;
  Tile.ParentBackground := False;
  // IDE_BG_CONTENT (clWindow) statt IDE_BG_CHROME (clBtnFace): Tile-Flaeche
  // hebt sich klar vom Toolbar-Hintergrund ab. Hell-Theme: weisse Tiles auf
  // grauer Toolbar; Dark-Theme: dunklere Content-Flaeche gegen Chrome-Grau.
  Tile.Color       := IDE_BG_CONTENT;
  Tile.BorderColor := IDE_TILE_BORDER;
  Tile.ShowHint    := True;
  Tile.Hint        := Caption;

  // Top-Row: Icon links + Zahl direkt daneben
  TopRow := TPanel.Create(AOwner);
  TopRow.Parent      := Tile;
  TopRow.Align       := alTop;
  TopRow.AlignWithMargins := True;
  // 2px Abstand zum 2-Pixel-Tile-Rahmen. Bewusst NICHT DPI-skaliert -
  // der Rahmen ist auch fix 2 px breit, beides muss matchen damit
  // TopRow nicht ueber die innere Pixelreihe des Rahmens laeuft.
  // Unten = 0 (TopRow stoesst direkt an die CapLbl-Marge, kein Spalt).
  TopRow.Margins.SetBounds(2, 2, 2, 0);
  TopRow.Height      := ScaleByPPI(Parent, 20);
  TopRow.BevelOuter  := bvNone;
  TopRow.ParentBackground := False;
  // Muss zu Tile.Color passen (IDE_BG_CONTENT), sonst sieht man eine
  // Naht zwischen Icon-Zeile und Caption.
  TopRow.Color       := IDE_BG_CONTENT;

  IconLbl := TLabel.Create(AOwner);
  IconLbl.Parent      := TopRow;
  IconLbl.Align       := alLeft;
  IconLbl.Width       := ScaleByPPI(Parent, 20);
  IconLbl.Caption     := Glyph;
  IconLbl.Alignment   := taCenter;
  IconLbl.Layout      := tlCenter;
  IconLbl.Transparent := True;
  IconLbl.Font.Name   := 'Segoe Fluent Icons';
  IconLbl.Font.Size   := 12;
  IconLbl.Font.Color  := IconColor;

  CountLbl := TLabel.Create(AOwner);
  CountLbl.Parent      := TopRow;
  CountLbl.Align       := alClient;
  CountLbl.Caption     := '0';
  CountLbl.Alignment   := taLeftJustify;
  CountLbl.Layout      := tlCenter;
  CountLbl.Transparent := True;
  CountLbl.Font.Name   := 'Segoe UI';
  CountLbl.Font.Size   := 12;
  CountLbl.Font.Style  := [fsBold];
  CountLbl.Font.Color  := IDE_FG_CHROME; // theme-konformer Vordergrund

  // Caption unten, ueber volle Tile-Breite zentriert.
  // Margins(2,0,2,2) - 2px Abstand auf links/rechts/unten passend zum
  // 2-Pixel-Tile-Rahmen. Oben = 0 (stoesst direkt an TopRow).
  CapLbl := TLabel.Create(AOwner);
  CapLbl.Parent      := Tile;
  CapLbl.Align       := alClient;
  CapLbl.AlignWithMargins := True;
  CapLbl.Margins.SetBounds(2, 0, 2, 2);
  CapLbl.Caption     := Caption;
  CapLbl.Alignment   := taCenter;
  CapLbl.Layout      := tlTop;
  CapLbl.Transparent := True;
  CapLbl.Font.Name   := 'Segoe UI';
  CapLbl.Font.Size   := 7;
  CapLbl.Font.Color  := IDE_FG_DIM; // gedaempfter Themed-Caption-Ton

  Result := CountLbl;
end;

class procedure TStatsTilesBuilder.Build(AOwner: TComponent; Parent: TPanel;
  out TileError, TileWarn, TileHint, TileFileSev: TLabel;
  out TileBug, TileVuln, TileDup, TileCyclomatic, TileScore: TLabel);
const
  // Glyph-Akzentfarben kommen aus uAnalyserPalette (ICON_ERROR, ICON_WARN ...).
  // Hier nur die Glyph-Codepoints aus Segoe Fluent Icons / MDL2 Assets.
  GLYPH_ERROR    = #$E783; // ErrorBadge
  GLYPH_WARN     = #$E7BA; // Warning (Dreieck mit !)
  GLYPH_INFO     = #$E946; // Info (i im Kreis)
  GLYPH_FILEERR  = #$E711; // Cancel (X)
  GLYPH_BUG      = #$EBE8; // Bug
  GLYPH_VULN     = #$E72E; // Lock - "Sicherheit"
  GLYPH_DUP      = #$E8C8; // Copy - "Duplikate"
  GLYPH_CYCLO    = #$EBE7; // Diagnostic / Branch - "Komplexitaet"
  GLYPH_SCORE    = #$EB91; // Flame - "Codequalitaet"

  // Tile-Breite passend zum 3-Stufen-Layout in uIDEAnalyserForm:
  // 9 Tiles + 8 Margins (je 3 px) = 9 * 55 + 24 = 519 px Gesamt-Reihe.
  // Tier-Verteilung:
  //   NARROW (<500): 4 Tiles = 4*55 + 3*3 = 229 px
  //   MEDIUM (500-849): 6 Tiles = 6*55 + 5*3 = 345 px
  //   FULL (>=850): 9 Tiles = 519 px (passt in 842 px ClientWidth bei 850 px Frame)
  // Alle Tiles gleich breit -> visuelle Gleichmaessigkeit der Sonar-Reihe.
  TILE_W       = 55;
  TILE_W_CYCLO = 55;
  TILE_W_SCORE = 55;
begin
  // Container leeren falls bereits aufgebaut.
  while Parent.ControlCount > 0 do
    Parent.Controls[0].Free;

  // Reihenfolge: alLeft = das zuerst erstellte landet ganz links.
  // Captions matchen das Datenmodell (TFindingType, TLeakSeverity).
  // Code Smell und Hotspot bewusst weggelassen - die zaehlen weiterhin in den
  // Quality-Score (siehe UpdateStats), bekommen aber keine eigene Kachel.
  // Cyclomatic ist eine Detector-spezifische Kachel zwischen den Type- und
  // Score-Buckets - mehr Detector-Kacheln koennen spaeter analog folgen.
  // Tile-Captions ueber _() lokalisierbar.
  TileError      := MakeTile(AOwner, Parent, _('Errors'),       GLYPH_ERROR,   ICON_ERROR,   TILE_W);
  TileWarn       := MakeTile(AOwner, Parent, _('Warnings'),     GLYPH_WARN,    ICON_WARN,    TILE_W);
  TileHint       := MakeTile(AOwner, Parent, _('Hints'),        GLYPH_INFO,    ICON_INFO,    TILE_W);
  TileFileSev    := MakeTile(AOwner, Parent, _('Read errors'),  GLYPH_FILEERR, ICON_FILEERR, TILE_W);
  TileBug        := MakeTile(AOwner, Parent, _('Bugs'),         GLYPH_BUG,     ICON_BUG,     TILE_W);
  TileVuln       := MakeTile(AOwner, Parent, _('Security'),     GLYPH_VULN,    ICON_VULN,    TILE_W);
  TileDup        := MakeTile(AOwner, Parent, _('Duplicates'),   GLYPH_DUP,     ICON_DUP,     TILE_W);
  TileCyclomatic := MakeTile(AOwner, Parent, _('Cyclomatic'),   GLYPH_CYCLO,   ICON_SMELL,   TILE_W_CYCLO);
  TileScore      := MakeTile(AOwner, Parent, _('Quality'),      GLYPH_SCORE,   ICON_SCORE,   TILE_W_SCORE);
end;

{ TResponsiveLayoutController }

constructor TResponsiveLayoutController.Create(AOwner: TComponent;
  ARoot: TWinControl; AMediumPx, AFullPx: Integer);
begin
  inherited Create(AOwner);
  FRoot              := ARoot;
  FEntries           := TList<TEntry>.Create;
  FMediumThresholdPx := AMediumPx;
  FFullThresholdPx   := AFullPx;
  FFirstApply        := True;

  // OnResize-Hook chainen: bestehenden Handler nicht ueberschreiben.
  // Cast ueber TControlAccess weil TWinControl.OnResize protected ist.
  FOriginalOnResize  := TControlAccess(ARoot).OnResize;
  TControlAccess(ARoot).OnResize := HandleResize;

  // Erstanwendung erfolgt NICHT hier - die Caller registriert noch alle
  // Controls. Nach dem letzten RegisterCtrl: ForceUpdate aufrufen.
end;

destructor TResponsiveLayoutController.Destroy;
begin
  if Assigned(FRoot) then
    TControlAccess(FRoot).OnResize := FOriginalOnResize;
  FEntries.Free;
  inherited;
end;

procedure TResponsiveLayoutController.RegisterCtrl(AControl: TControl;
  AMinStage: TUiStage = usNarrow; AMaxStage: TUiStage = usFull);
var
  E : TEntry;
begin
  if not Assigned(AControl) then Exit;
  E.Control  := AControl;
  E.MinStage := AMinStage;
  E.MaxStage := AMaxStage;
  FEntries.Add(E);
end;

function TResponsiveLayoutController.ScaleByPPI(AValue: Integer): Integer;
var
  PPI : Integer;
begin
  if not Assigned(FRoot) then Exit(AValue);
  PPI := FRoot.CurrentPPI;
  if PPI <= 0 then PPI := 96;
  Result := MulDiv(AValue, PPI, 96);
end;

function TResponsiveLayoutController.CurrentStage: TUiStage;
var
  W : Integer;
begin
  W := FRoot.ClientWidth;
  if W >= ScaleByPPI(FFullThresholdPx)   then Exit(usFull);
  if W >= ScaleByPPI(FMediumThresholdPx) then Exit(usMedium);
  Result := usNarrow;
end;

procedure TResponsiveLayoutController.HandleResize(Sender: TObject);
begin
  ApplyVisibility;
  if Assigned(FOriginalOnResize) then
    FOriginalOnResize(Sender);
end;

procedure TResponsiveLayoutController.ApplyVisibility;
var
  Stage  : TUiStage;
  E      : TEntry;
  Target : Boolean;
begin
  if not Assigned(FRoot) then Exit;
  Stage := CurrentStage;
  // Visibility nur toggeln wenn sich die Stage geaendert hat oder beim
  // ersten Apply (Initial-Visibility setzen). Spart unnoetige Repaints.
  if FFirstApply or (Stage <> FLastStage) then
  begin
    FFirstApply := False;
    FLastStage  := Stage;
    for E in FEntries do
    begin
      Target := (Stage >= E.MinStage) and (Stage <= E.MaxStage);
      if E.Control.Visible <> Target then
        E.Control.Visible := Target;
    end;
  end;

  // AfterApply IMMER feuern (auch ohne Stage-Wechsel) - Subpanel-Width-
  // Anpassungen oder dynamische MinWidth-Berechnungen haengen an der
  // tatsaechlichen ClientWidth, nicht nur am Stage-Wechsel.
  if Assigned(FAfterApply) then
    FAfterApply(Self);
end;

procedure TResponsiveLayoutController.ForceUpdate;
begin
  FFirstApply := True; // erzwingt vollen Apply auch wenn Stage gleich
  ApplyVisibility;
end;

end.
