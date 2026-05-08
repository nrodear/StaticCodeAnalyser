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

  // Responsive Layout: blendet "optionale" Controls aus wenn der Parent-
  // Container schmal wird (typisch: Plugin gedockt in einem schmalen
  // Tool-Panel statt im Hauptfenster). Visible:=False entfernt das Control
  // aus der alLeft/alRight-Anordnung; die verbleibenden ruecken automatisch
  // nach. TComponent-Ownership: lebt mit dem Frame, wird beim Frame-Destroy
  // mit freigegeben.
  //
  // Universell: nimmt alle TControl-Subclasses an (Buttons, Labels,
  // Tile-Panels, ComboBoxen ...). Im Aufrufer ggf. Tile-Labels via
  // Label.Parent.Parent zu ihren TilePanels aufloesen.
  //
  // AInverse=False (Default): Controls hide bei narrow, show bei wide.
  // AInverse=True: Controls hide bei wide, show bei narrow (z.B. Hamburger-
  // Button der nur im gedockten Modus auftaucht).
  TResponsiveVisibilityController = class(TComponent)
  private
    FParent             : TPanel;
    FOptional           : TList<TControl>;
    FThresholdWidth     : Integer;
    FInverse            : Boolean;
    FOriginalOnResize   : TNotifyEvent;
    procedure HandleResize(Sender: TObject);
    procedure ApplyVisibility;
  public
    constructor Create(AOwner: TComponent; AParent: TPanel;
      AOptional: array of TControl; AThresholdWidth: Integer;
      AInverse: Boolean = False); reintroduce;
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows, uAnalyserPalette, uLocalization;

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
begin
  inherited; // zeichnet Hintergrund (Color) und Bevel
  Canvas.Brush.Style := bsClear;
  // BorderColor ist ein System-Color-Index (z. B. cl3DDkShadow). Canvas.Pen
  // resolved nur ueber GetSysColor (Windows nativ), nicht ueber den aktiven
  // VCL-Style. Daher hier explizit ueber StyleServices aufloesen.
  Canvas.Pen.Color := StyleServices.GetSystemColor(FBorderColor);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(ClientRect);
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
  Tile.Color       := clBtnFace;
  Tile.BorderColor := cl3DDkShadow;
  Tile.ShowHint    := True;
  Tile.Hint        := Caption;

  // Top-Row: Icon links + Zahl direkt daneben
  TopRow := TPanel.Create(AOwner);
  TopRow.Parent      := Tile;
  TopRow.Align       := alTop;
  TopRow.AlignWithMargins := True;
  // 1px Abstand zum Tile-Rahmen - bewusst NICHT skaliert (1 px sieht
  // auch bei 200% DPI noch als duennes Inset OK aus, 2 px waere zu fett).
  TopRow.Margins.SetBounds(1, 1, 1, 0);
  TopRow.Height      := ScaleByPPI(Parent, 20);
  TopRow.BevelOuter  := bvNone;
  TopRow.ParentBackground := False;
  TopRow.Color       := clBtnFace;

  IconLbl := TLabel.Create(AOwner);
  IconLbl.Parent      := TopRow;
  IconLbl.Align       := alLeft;
  IconLbl.Width       := ScaleByPPI(Parent, 20);
  IconLbl.Caption     := Glyph;
  IconLbl.Alignment   := taCenter;
  IconLbl.Layout      := tlCenter;
  IconLbl.Transparent := True;
  IconLbl.Font.Name   := 'Segoe Fluent Icons';
  IconLbl.Font.Size   := 11;
  IconLbl.Font.Color  := IconColor;

  CountLbl := TLabel.Create(AOwner);
  CountLbl.Parent      := TopRow;
  CountLbl.Align       := alClient;
  CountLbl.Caption     := '0';
  CountLbl.Alignment   := taLeftJustify;
  CountLbl.Layout      := tlCenter;
  CountLbl.Transparent := True;
  CountLbl.Font.Name   := 'Segoe UI';
  CountLbl.Font.Size   := 11;
  CountLbl.Font.Style  := [fsBold];
  CountLbl.Font.Color  := clBtnText; // theme-konformer Vordergrund

  // Caption unten, ueber volle Tile-Breite zentriert.
  // AlignWithMargins/Margins(1,0,1,1) damit der Tile-Rahmen sichtbar bleibt.
  CapLbl := TLabel.Create(AOwner);
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
  CapLbl.Font.Color  := clGrayText; // gedaempfter Themed-Caption-Ton

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

  TILE_W       = 65;
  TILE_W_CYCLO = 72; // "Cyclomatic" ist breiter als die Standard-Kacheln
  TILE_W_SCORE = 72; // letzter Tile etwas breiter (laengeres Wort)
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
  TileScore      := MakeTile(AOwner, Parent, _('Code Quality'), GLYPH_SCORE,   ICON_SCORE,   TILE_W_SCORE);
end;

{ TResponsiveVisibilityController }

constructor TResponsiveVisibilityController.Create(AOwner: TComponent;
  AParent: TPanel; AOptional: array of TControl; AThresholdWidth: Integer;
  AInverse: Boolean = False);
// AOptional = die OPTIONALEN Controls (Buttons, Labels, Panels), die im
// schmalen Modus ausgeblendet werden duerfen (AInverse=False, Default).
// Bei AInverse=True umgekehrt: nur im schmalen Modus sichtbar (z.B.
// Hamburger-Button der die ausgeblendeten Aktionen ersetzt).
var
  i : Integer;
begin
  inherited Create(AOwner);
  FParent         := AParent;
  FOptional       := TList<TControl>.Create;
  FThresholdWidth := AThresholdWidth;
  FInverse        := AInverse;

  for i := Low(AOptional) to High(AOptional) do
    if Assigned(AOptional[i]) then
      FOptional.Add(AOptional[i]);

  // OnResize-Hook: bestehenden Handler chainen, sodass wir niemanden
  // ueberschreiben (Frame koennte selbst etwas hooken).
  FOriginalOnResize := AParent.OnResize;
  AParent.OnResize  := HandleResize;

  // Erste Anwendung beim Konstruieren - damit die Controls nicht erst beim
  // ersten Resize-Event sichtbar/unsichtbar werden.
  ApplyVisibility;
end;

destructor TResponsiveVisibilityController.Destroy;
begin
  // OnResize wieder herstellen falls Parent noch lebt - sonst zeigt der
  // Hook ggf. auf einen freed Self.
  if Assigned(FParent) then
    FParent.OnResize := FOriginalOnResize;
  FOptional.Free;
  inherited;
end;

procedure TResponsiveVisibilityController.HandleResize(Sender: TObject);
begin
  ApplyVisibility;
  if Assigned(FOriginalOnResize) then
    FOriginalOnResize(Sender);
end;

procedure TResponsiveVisibilityController.ApplyVisibility;
var
  Ctrl    : TControl;
  IsWide  : Boolean;
  Target  : Boolean;
begin
  if not Assigned(FParent) then Exit;
  // ClientWidth (nicht Width) - schliesst Border/Scrollbars aus, zeigt
  // den tatsaechlich nutzbaren Innenraum.
  IsWide := FParent.ClientWidth >= FThresholdWidth;
  // Default: zeige bei wide. AInverse=True: zeige bei narrow.
  if FInverse then
    Target := not IsWide
  else
    Target := IsWide;
  for Ctrl in FOptional do
    if Assigned(Ctrl) and (Ctrl.Visible <> Target) then
      Ctrl.Visible := Target;
end;

end.
