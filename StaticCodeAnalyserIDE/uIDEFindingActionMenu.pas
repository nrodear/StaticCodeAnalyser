unit uIDEFindingActionMenu;

// VCL-Haelfte des Menue-Erzeugers (Konzept Editor-Gluehbirne 2026-10-06,
// Stufe C): ein TFindingMenuModel (uFindingActionMenu, Engine, getestet)
// wird zu TMenuItems in einem TPopupMenu. Alle drei Einstiege - das
// Editor-Kontextmenue, das Dock-Grid und die Gluehbirne (uIDEFindingBulb)
// - rufen genau dies; Alt+Enter kommt spaeter dazu, ohne eine zweite
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
// aus uFindingActions), steht hinter den Fund-Eintraegen eine deaktivierte
// Hinweiszeile - sonst saehe der Benutzer nicht, dass Funde fehlen. Traegt
// das Modell Code-Aktionen ohne Fund (Charge B, ContextEntryCount), steht
// sie VOR deren Abschnitt, nicht am Ende (uEditorContextModel.
// OmittedLineIndex); ohne sie am Ende wie bisher.
//
// Aktionsmenue nach Vorschlag 2 (Konzept 2026-10-24, Mock 2b): ein
// Eintrag mit Parent >= 0 haengt als Kind an seinem Untermenue-Kopf
// (mkSubmenu 'Unterdruecken'); nur die oberste Ebene kommt nach ASink.
// Jeder Menuepunkt traegt den Hint des Eintrags (VCL zeigt ihn beim
// Ueberfahren als Application.Hint). Der Menuetext ist die Caption des
// Anbieters ohne #9-Spalte (Nico 2026-10-25): unter den VCL-Stilen der
// IDE zeichnet VCL selbst (owner-draw, DrawText mit tfExpandTabs) und
// setzte den Teil hinter #9 als Tabulatorsprung hinter die laengste
// Caption statt rechtsbuendig in die Tastenspalte. Bilder
// (Entry.Icon) als TMenuItem.Bitmap - nie in die ImageList eines fremden
// Popups (das Editor-Kontextmenue gehoert der IDE): Birne wie am Editor-
// rand (uEditorBulbButton.DrawBulbGlyph), Auge "Hide" aus Segoe Fluent
// Icons bzw. MDL2 Assets, die SCA-Eule aus der Paket-Resource
// SCA_APP_BMP16; Auge und Eule hell auf dunklem Thema.

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
  Winapi.Windows, System.Types, System.SysUtils, Vcl.Graphics, Vcl.Forms,
  uLocalization,
  uCrashDiag,            // EStackExhausted
  uEditorContextModel,   // OmittedLineIndex - Hinweiszeile vor dem Kontextteil
  uEditorBulbButton,     // DrawBulbGlyph - dieselbe Birne wie am Editorrand
  uAnalyserTheme;        // IsActiveThemeDark - Auge und Eule hell auf dunkel

const
  // Hintergrund der Bilder: TMenuItem.Bitmap ist Transparent, diese Farbe
  // faellt weg (die Bilder zeichnen ohne Kantenglaettung - keine Saeume).
  ICON_KEY = clFuchsia;
  // Die SCA-Eule, 16 x 16, schon in der Resource des Pakets (branding\
  // sca_branding.rc, im IDE- und im Monolith-dpk gelinkt; uIDEExpert
  // nutzt sie fuer das Tools-Menue).
  OWL_RES = 'SCA_APP_BMP16';
  // Segoe Fluent Icons / Segoe MDL2 Assets: "Hide" (Auge, durchgestrichen;
  // in MDL2 Auge mit Sperrzeichen).
  GLYPH_HIDE = #$ED1A;
  ICON_FONTS : array[0..1] of string = ('Segoe Fluent Icons', 'Segoe MDL2 Assets');
  // Bildfarbe auf hellem / dunklem Menue (Auge; die Eule wird invertiert).
  ICON_INK_LIGHT = $00303030;
  ICON_INK_DARK  = $00E0E0E0;
  // Ab dieser Helligkeit (0..255) gehoert ein Pixel der Eule zum Grund.
  OWL_GROUND_LUMA = 240;

function MenuCaptionOf(const AText: string): string;
// TMenuItem deutet ein einzelnes '&' als Hotkey-Praefix (Vcl.Menus
// cHotkeyPrefix): es verschwindet und das Folgezeichen wird
// unterstrichen. Kopfzeilen tragen den Meldetext des Funds (z. B. ein
// SCA015-Literal 'Save & Exit'), Aktionen den Text des Anbieters (samt
// Grund einer gesperrten Aktion) - beides soll woertlich erscheinen, also '&'
// als '&&' maskieren (Nit 2, Audit reDelphiX 2026-10-07). Kein
// Anbieter setzt '&' absichtlich als Hotkey. Nur fuer Text aus dem
// Modell; Hint, Trenner '-' und eigene Zeilen bleiben unberuehrt.
begin
  Result := StringReplace(AText, '&', '&&', [rfReplaceAll]);
end;

function MenuHintOf(const AText: string): string;
// VCL setzt beim Ueberfahren Application.Hint := GetLongHint(Item.Hint) -
// den Teil HINTER einem '|'. Ein '|' im Hint eines Anbieters (oder in der
// Meldung eines Funds) schnitte den Anfang ab; er wird zu '/'.
begin
  Result := StringReplace(AText, '|', '/', [rfReplaceAll]);
end;

function IconSize: Integer;
// 16 Pixel bei 96 dpi wie die Bilder der IDE-Menues; VCL zentriert ein
// kleineres Bild bzw. streckt ein groesseres auf die Bildspalte.
begin
  Result := MulDiv(16, Screen.PixelsPerInch, 96);
  if Result < 16 then Result := 16;
end;

function NewKeyedBitmap(ASize: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(ASize, ASize);
  Result.Canvas.Brush.Color := ICON_KEY;
  Result.Canvas.FillRect(Rect(0, 0, ASize, ASize));
end;

procedure PaintBulb(ABmp: TBitmap);
// Etwas kleiner als das Feld: der Kolben der Birne fuellt sonst die Zeile.
var
  S, M : Integer;
begin
  S := (ABmp.Width * 7) div 8;
  M := (ABmp.Width - S) div 2;
  DrawBulbGlyph(ABmp.Canvas, M, M, S, CLR_BULB_DEFAULT, CLR_OUTLINE_DEFAULT);
end;

procedure PaintHide(ABmp: TBitmap; ADark: Boolean);
var
  i  : Integer;
  Sz : TSize;
begin
  ABmp.Canvas.Font.Name := ICON_FONTS[High(ICON_FONTS)];
  for i := 0 to High(ICON_FONTS) do
    if Screen.Fonts.IndexOf(ICON_FONTS[i]) >= 0 then
    begin
      ABmp.Canvas.Font.Name := ICON_FONTS[i];
      Break;
    end;
  ABmp.Canvas.Font.Height  := -ABmp.Height;
  ABmp.Canvas.Font.Quality := fqNonAntialiased;
  if ADark then
    ABmp.Canvas.Font.Color := ICON_INK_DARK
  else
    ABmp.Canvas.Font.Color := ICON_INK_LIGHT;
  ABmp.Canvas.Brush.Style := bsClear;
  Sz := ABmp.Canvas.TextExtent(GLYPH_HIDE);
  ABmp.Canvas.TextOut((ABmp.Width - Sz.cx) div 2, (ABmp.Height - Sz.cy) div 2,
    GLYPH_HIDE);
end;

procedure PaintOwl(ABmp: TBitmap; ADark: Boolean);
// Die Eule ist grau auf weiss: der weisse Grund faellt weg, auf dunklem
// Menue werden die Grautoene umgekehrt (hell auf dunkel).
var
  Owl  : TBitmap;
  x, y : Integer;
  C    : TColor;
  L    : Integer;
begin
  Owl := TBitmap.Create;
  try
    Owl.LoadFromResourceName(HInstance, OWL_RES);
    Owl.PixelFormat := pf24bit;
    for y := 0 to Owl.Height - 1 do
      for x := 0 to Owl.Width - 1 do
      begin
        C := ColorToRGB(Owl.Canvas.Pixels[x, y]);
        L := (GetRValue(C) + GetGValue(C) + GetBValue(C)) div 3;
        if L >= OWL_GROUND_LUMA then
          Owl.Canvas.Pixels[x, y] := ICON_KEY
        else if ADark then
          Owl.Canvas.Pixels[x, y] := RGB(255 - L, 255 - L, 255 - L);
      end;
    ABmp.Canvas.StretchDraw(Rect(0, 0, ABmp.Width, ABmp.Height), Owl);
  finally
    Owl.Free;
  end;
end;

function NewMenuIcon(AIcon: TFindingMenuIcon): TBitmap;
// nil fuer miNone - und wenn ein Bild nicht entsteht (Resource, Schrift):
// ein Bild ist Schmuck, es darf das Menue nie kosten.
begin
  Result := nil;
  if AIcon = miNone then Exit;
  try
    Result := NewKeyedBitmap(IconSize);
    case AIcon of
      miBulb     : PaintBulb(Result);
      miSuppress : PaintHide(Result, IsActiveThemeDark);
      miRule     : PaintOwl(Result, IsActiveThemeDark);
    end;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Resource fehlt, Schrift fehlt, GDI-Fehler: ohne Bild weiter.
    on Exception do
      FreeAndNil(Result);
  end;
end;

procedure SetIcon(AItem: TMenuItem; AIcon: TFindingMenuIcon);
var
  Bmp : TBitmap;
begin
  Bmp := NewMenuIcon(AIcon);
  if not Assigned(Bmp) then Exit;
  try
    AItem.Bitmap.Assign(Bmp);
    AItem.Bitmap.TransparentColor := ICON_KEY;   // tmFixed
  finally
    Bmp.Free;
  end;
end;

procedure AddOmittedLine(APopup: TPopupMenu; const AModel: TFindingMenuModel;
  ATagBase: Integer; AOwner: TComponent; ASink: TList<TMenuItem>);
// Die Hinweiszeile zu Omitted (deaktiviert, Tag wie Trenner/Kopfzeilen).
var
  Item : TMenuItem;
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

procedure FillPopupFromModel(APopup: TPopupMenu;
  const AModel: TFindingMenuModel; AOnClick: TNotifyEvent;
  ATagBase: Integer; AOwner: TComponent; ASink: TList<TMenuItem>);
var
  i       : Integer;
  Item    : TMenuItem;
  OmitAt  : Integer;
  Items   : TArray<TMenuItem>;   // je Eintrag sein Item (Parent-Aufloesung)
  E       : TFindingMenuEntry;
begin
  if not Assigned(APopup) then Exit;
  // Index in Entries, VOR dem die Hinweiszeile steht (= Length(Entries)
  // ohne Kontextteil: ans Ende wie bisher).
  OmitAt := OmittedLineIndex(AModel);
  SetLength(Items, Length(AModel.Entries));
  for i := 0 to High(AModel.Entries) do
  begin
    E := AModel.Entries[i];
    if (i = OmitAt) and (AModel.Omitted > 0) then
      AddOmittedLine(APopup, AModel, ATagBase, AOwner, ASink);
    Item := TMenuItem.Create(AOwner);
    Items[i] := Item;
    case E.Kind of
      mkSeparator:
        begin
          Item.Caption := '-';
          Item.Tag     := ATagBase - 1;
        end;
      mkHeader:
        begin
          Item.Caption := MenuCaptionOf(E.Caption);
          Item.Enabled := False;
          Item.Tag     := ATagBase - 1;
        end;
      mkSubmenu:
        begin
          // Kein OnClick: VCL ruft Click des Kopfs beim Aufklappen.
          Item.Caption := MenuCaptionOf(E.Caption);
          Item.Hint    := MenuHintOf(E.Hint);
          Item.Enabled := E.Enabled;
          Item.Tag     := ATagBase - 1;
        end;
    else
      Item.Caption := MenuCaptionOf(E.Caption);
      Item.Hint    := MenuHintOf(E.Hint);
      Item.Enabled := E.Enabled;
      Item.Tag     := ATagBase + E.ActionIndex;
      Item.OnClick := AOnClick;
    end;
    SetIcon(Item, E.Icon);
    // Ein Kind haengt an seinem Untermenue-Kopf (der steht im Modell vor
    // ihm) und gibt mit ihm frei - in ASink nur die oberste Ebene, sonst
    // gaebe ClearActionItems ein Kind nach seinem Kopf ein zweites Mal frei.
    if (E.Parent >= 0) and (E.Parent < i) and Assigned(Items[E.Parent]) then
      Items[E.Parent].Add(Item)
    else
    begin
      APopup.Items.Add(Item);
      if Assigned(ASink) then
        ASink.Add(Item);
    end;
  end;
  if (OmitAt >= Length(AModel.Entries)) and (AModel.Omitted > 0) then
    AddOmittedLine(APopup, AModel, ATagBase, AOwner, ASink);
end;

end.
