unit uIDEFindingActionMenu;

// VCL-Haelfte des Menue-Erzeugers (Konzept Editor-Gluehbirne 2026-10-06,
// Stufe C): ein TFindingMenuModel (uFindingActionMenu, Engine, getestet)
// wird zu TMenuItems in einem TPopupMenu. Beide heutigen Einstiege -
// das Editor-Kontextmenue und das Dock-Grid - rufen genau dies; die
// Gluehbirne und Alt+Enter kommen spaeter dazu, ohne eine zweite
// Fassung der Liste.
//
// Tags: Trenner und Kopfzeilen tragen ATagBase - 1, Aktionen
// ATagBase + ActionIndex. Der Kontextmenue-Haken nimmt ATagBase 0 (Index
// in Slot.Actions; Kopfzeile -1 wie bisher, der Trenner trug bisher 0 und
// jetzt -1 - kein Leser), das Dock-Grid GRID_ACTION_TAG (Trenner
// GRID_ACTION_TAG - 1 wie bisher, danach raeumt GridMenuPopup ab Tag
// GRID_ACTION_TAG - 1 ab).
//
// Fragte das Modell nicht alle Funde ab (Omitted > 0, Obergrenze je Menue
// aus uFindingActions), steht am Ende eine deaktivierte Hinweiszeile -
// sonst saehe der Benutzer nicht, dass Funde fehlen.

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.Menus,
  uFindingActionMenu;

// Haengt die Eintraege des Modells an APopup.Items. AOwner ist der Owner
// der Items (nil = der Aufrufer raeumt selbst ab, Muster des Kontext-
// menue-Hakens); ASink sammelt die erzeugten Items und darf nil sein.
// AOnClick haengt an jeder Aktion, auch an deaktivierten (VCL ruft es
// dort nicht).
procedure FillPopupFromModel(APopup: TPopupMenu;
  const AModel: TFindingMenuModel; AOnClick: TNotifyEvent;
  ATagBase: Integer; AOwner: TComponent; ASink: TList<TMenuItem>);

implementation

uses
  System.SysUtils, uLocalization;

procedure FillPopupFromModel(APopup: TPopupMenu;
  const AModel: TFindingMenuModel; AOnClick: TNotifyEvent;
  ATagBase: Integer; AOwner: TComponent; ASink: TList<TMenuItem>);
var
  i    : Integer;
  Item : TMenuItem;
begin
  if not Assigned(APopup) then Exit;
  for i := 0 to High(AModel.Entries) do
  begin
    Item := TMenuItem.Create(AOwner);
    case AModel.Entries[i].Kind of
      mkSeparator:
        begin
          Item.Caption := '-';
          Item.Tag     := ATagBase - 1;
        end;
      mkHeader:
        begin
          Item.Caption := AModel.Entries[i].Caption;
          Item.Enabled := False;
          Item.Tag     := ATagBase - 1;
        end;
    else
      Item.Caption := AModel.Entries[i].Caption;
      Item.Hint    := AModel.Entries[i].Hint;
      Item.Enabled := AModel.Entries[i].Enabled;
      Item.Tag     := ATagBase + AModel.Entries[i].ActionIndex;
      Item.OnClick := AOnClick;
    end;
    APopup.Items.Add(Item);
    if Assigned(ASink) then
      ASink.Add(Item);
  end;
  if AModel.Omitted > 0 then
  begin
    Item := TMenuItem.Create(AOwner);
    Item.Caption := Format(_('%d more findings on this line are not listed'),
      [AModel.Omitted]);
    Item.Enabled := False;
    Item.Tag     := ATagBase - 1;
    APopup.Items.Add(Item);
    if Assigned(ASink) then
      ASink.Add(Item);
  end;
end;

end.
