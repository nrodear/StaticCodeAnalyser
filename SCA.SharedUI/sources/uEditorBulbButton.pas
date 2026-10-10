unit uEditorBulbButton;

// Editor-Gluehbirne - das Steuerelement (Konzept_GluehbirneAnzeige_2026-10-08,
// Weg C; uebernommen aus dem Prototyp EditorLamp, mess/editor-bulb f8917083).
//
// Ein TCustomControl in Gluehbirnenform. Die Form ist eine Fensterregion
// (Glaskolben + Sockel): ausserhalb der Birne gehoert die Flaeche nicht
// zum Fenster, der Editor darunter bleibt sichtbar - in hellem wie dunklem
// Thema, ohne dass die Birne die Gutter-Farbe kennen muss.
//
// Klick (links) und Kontextmenue (rechts / Menue-Taste) oeffnen
// DropdownMenu unter der Birne. Das Menue oeffnet aus dem EIGENEN Klick,
// nie aus einem Editor-Rueckruf: so geht die IDE mit ihrem SyncEdit-Knopf
// und CnPack mit seinem Schwebeknopf vor. WM_CONTEXTMENU wird hier
// beantwortet und NICHT an den Elternteil (den Editor) weitergereicht -
// sonst oeffnete zusaetzlich das Editor-Kontextmenue. Gemessen im
// Prototyp: 20 Links- und 20 Rechtsklicks ohne IDE-Meldung (C3).
//
// Name bleibt leer, Owner setzt der Benutzer (im Plugin nil): ein Name im
// fremden Owner war die Ursache von "ecSwapCppHdrFiles existiert bereits".

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Types, Vcl.Controls, Vcl.Graphics, Vcl.Menus;

type
  TSCABulbButton = class(TCustomControl)
  private
    FHot          : Boolean;
    FDown         : Boolean;
    FBulbColor    : TColor;
    FOutlineColor : TColor;
    FDropdownMenu : TPopupMenu;
    FOnBeforeMenu : TNotifyEvent;
    procedure UpdateRegion;
    procedure SetBulbColor(AValue: TColor);
    procedure SetOutlineColor(AValue: TColor);
    procedure SetDropdownMenu(AValue: TPopupMenu);
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
    procedure WMContextMenu(var Msg: TWMContextMenu); message WM_CONTEXTMENU;
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure CreateWnd; override;
    procedure Resize; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Oeffnet DropdownMenu unter der Birne (ruft vorher OnBeforeMenu).
    procedure ShowMenu;
    // Menue, das Klick, Rechtsklick und Menue-Taste unter der Birne oeffnen.
    property DropdownMenu: TPopupMenu read FDropdownMenu write SetDropdownMenu;
    // Fuellfarbe des Glaskolbens (beim Ueberfahren heller).
    property BulbColor: TColor read FBulbColor write SetBulbColor;
    // Umrissfarbe; der Standard ist auf hellem und dunklem Grund lesbar.
    property OutlineColor: TColor read FOutlineColor write SetOutlineColor;
    // Vor dem Oeffnen: der Besitzer fuellt das Menue fuer die aktuelle Zeile.
    property OnBeforeMenu: TNotifyEvent read FOnBeforeMenu write FOnBeforeMenu;
  end;

implementation

// Die Zahlen in BulbShapeOf und Paint sind Proportionen der
// Gluehbirnenform (Prozent der Kantenlaenge), keine Konfigurationswerte.

type
  // Lage von Glaskolben und Sockel in einem S x S grossen Steuerelement.
  // EINE Quelle fuer Fensterregion und Zeichnung - sonst schnitte die
  // Region die gemalte Form an.
  TBulbShape = record
    GlassLeft  : Integer;   // Kolben: Kreis im Quadrat GlassLeft..+GlassSize, 0..GlassSize
    GlassSize  : Integer;
    BaseLeft   : Integer;   // Sockel: Rechteck BaseLeft..BaseRight, BaseTop..S
    BaseRight  : Integer;
    BaseTop    : Integer;
  end;

// Der Kolben ist ein KREIS (Nico 2026-10-08: "die Birne ist nicht rund" -
// bis dahin eine Ellipse ueber die volle Breite bei 74 % Hoehe), mittig
// ueber einem schmaleren Sockel, der ein Stueck unter den Kreis reicht.
function BulbShapeOf(S: Integer): TBulbShape;
begin
  Result.GlassSize := (S * 76) div 100;
  if Result.GlassSize < 4 then Result.GlassSize := 4;
  Result.GlassLeft := (S - Result.GlassSize) div 2;
  Result.BaseLeft  := (S * 34) div 100;
  Result.BaseRight := S - 1 - Result.BaseLeft;
  Result.BaseTop   := Result.GlassSize - (S * 12) div 100;
end;

const
  CLR_BULB_DEFAULT    = $0040C8FF;   // BGR: warmes Gelb
  CLR_BULB_HOT        = $0080E0FF;   // heller beim Ueberfahren
  CLR_OUTLINE_DEFAULT = $00406080;   // BGR: Braun-Grau, auf hell und dunkel lesbar
  CLR_BASE            = $00909090;   // Sockel
  MIN_REGION_SIZE     = 6;

constructor TSCABulbButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption, csDoubleClicks];
  FBulbColor    := CLR_BULB_DEFAULT;
  FOutlineColor := CLR_OUTLINE_DEFAULT;
  Width  := 14;
  Height := 14;
  Cursor := crHandPoint;
  ShowHint := True;
  TabStop := False;
  Visible := False;
end;

procedure TSCABulbButton.CreateWnd;
begin
  inherited CreateWnd;
  UpdateRegion;
end;

procedure TSCABulbButton.Resize;
begin
  inherited Resize;
  if HandleAllocated then
    UpdateRegion;
end;

// Fensterregion = Glaskolben (Kreis) + Sockel (Rechteck). SetWindowRgn
// uebernimmt das Handle - nicht selbst freigeben.
procedure TSCABulbButton.UpdateRegion;
var
  S     : Integer;
  Shape : TBulbShape;
  Glass, Base : HRGN;
begin
  S := Width;
  if (S < MIN_REGION_SIZE) or (Height < MIN_REGION_SIZE) then Exit;
  Shape := BulbShapeOf(S);
  // +1: die Region schliesst rechts/unten aus, der Umriss liegt aber auf
  // der letzten Spalte/Zeile des Kreises.
  Glass := CreateEllipticRgn(Shape.GlassLeft, 0,
    Shape.GlassLeft + Shape.GlassSize + 1, Shape.GlassSize + 1);
  Base  := CreateRectRgn(Shape.BaseLeft, Shape.BaseTop,
    Shape.BaseRight + 1, S);
  CombineRgn(Glass, Glass, Base, RGN_OR);
  DeleteObject(Base);
  SetWindowRgn(Handle, Glass, True);
end;

procedure TSCABulbButton.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;   // Paint deckt die ganze Region ab - kein Flackern
end;

procedure TSCABulbButton.Paint;
var
  S, G, X, BaseH : Integer;
  Shape : TBulbShape;
begin
  S     := Width;
  Shape := BulbShapeOf(S);
  G     := Shape.GlassSize;
  X     := Shape.GlassLeft;
  BaseH := S - Shape.BaseTop;

  // Sockel zuerst - der Kolben ueberdeckt danach seine Oberkante
  Canvas.Pen.Color := FOutlineColor;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := CLR_BASE;
  Canvas.Rectangle(Shape.BaseLeft, Shape.BaseTop, Shape.BaseRight + 1, S);
  Canvas.MoveTo(Shape.BaseLeft, Shape.BaseTop + (2 * BaseH) div 3);
  Canvas.LineTo(Shape.BaseRight, Shape.BaseTop + (2 * BaseH) div 3);

  // Glaskolben: Kreis
  if FHot or FDown then
    Canvas.Brush.Color := CLR_BULB_HOT
  else
    Canvas.Brush.Color := FBulbColor;
  Canvas.Ellipse(X, 0, X + G, G);

  // Glanzpunkt oben links im Kreis
  Canvas.Pen.Color := clWhite;
  Canvas.Arc(X + G div 5, G div 5, X + (G * 3) div 5, (G * 3) div 5,
    X + G div 2, G div 5, X + G div 5, G div 2);
end;

procedure TSCABulbButton.CMMouseEnter(var Msg: TMessage);
begin
  inherited;
  FHot := True;
  Invalidate;
end;

procedure TSCABulbButton.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  FHot := False;
  FDown := False;
  Invalidate;
end;

procedure TSCABulbButton.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    FDown := True;
    Invalidate;
  end;
end;

procedure TSCABulbButton.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  WasDown : Boolean;
begin
  inherited;
  WasDown := FDown;
  FDown := False;
  Invalidate;
  if (Button = mbLeft) and WasDown and PtInRect(ClientRect, Point(X, Y)) then
    ShowMenu;
end;

procedure TSCABulbButton.WMContextMenu(var Msg: TWMContextMenu);
begin
  // Beantworten, nicht weiterreichen: der Editor darunter soll KEIN
  // eigenes Kontextmenue oeffnen.
  ShowMenu;
  Msg.Result := 1;
end;

procedure TSCABulbButton.ShowMenu;
var
  P : TPoint;
begin
  if Assigned(FOnBeforeMenu) then
    FOnBeforeMenu(Self);
  if not Assigned(FDropdownMenu) then Exit;
  P := ClientToScreen(Point(0, Height));
  FDropdownMenu.PopupComponent := Self;
  FDropdownMenu.Popup(P.X, P.Y);
end;

procedure TSCABulbButton.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FDropdownMenu) then
    FDropdownMenu := nil;
end;

procedure TSCABulbButton.SetDropdownMenu(AValue: TPopupMenu);
begin
  if FDropdownMenu = AValue then Exit;
  if Assigned(FDropdownMenu) then
    FDropdownMenu.RemoveFreeNotification(Self);
  FDropdownMenu := AValue;
  if Assigned(FDropdownMenu) then
    FDropdownMenu.FreeNotification(Self);
end;

procedure TSCABulbButton.SetBulbColor(AValue: TColor);
begin
  if FBulbColor = AValue then Exit;
  FBulbColor := AValue;
  Invalidate;
end;

procedure TSCABulbButton.SetOutlineColor(AValue: TColor);
begin
  if FOutlineColor = AValue then Exit;
  FOutlineColor := AValue;
  Invalidate;
end;

end.
