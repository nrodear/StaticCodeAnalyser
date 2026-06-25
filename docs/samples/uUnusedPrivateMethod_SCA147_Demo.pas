unit uUnusedPrivateMethod_SCA147_Demo;

// noinspection-file All
// Sample-/Demo-Datei: demonstriert Detektor-Patterns - alle Findings sind Absicht.

// SCA147 (UnusedPrivateMethod) Demo-Quelltext.
//
// Komplementaer zu uUnusedRoutine_SCA164_Demo: dort sind STANDALONE-
// Top-Level-Routinen das Spielfeld, hier sind es CLASS-PRIVATE-Methoden
// (Domain von SCA147, nicht SCA164).
//
// Erwartete Findings nach SCA147-Lauf:
//   * Zeile 30  fkUnusedPrivateMethod "TShoppingCart.RecalculateTotal"
//   * Zeile 41  fkUnusedPrivateMethod "TShoppingCart.InvalidateCache"
//   * Zeile 58  fkUnusedPrivateMethod "TInvoice.FormatHeader"
//
// Alle anderen private Methoden werden absichtlich nicht geflagged -
// jede demonstriert einen anderen Use-Pfad oder Suppression-Marker.

interface

uses
  System.Generics.Collections;

type
  // --- Typ 1: Warenkorb -----------------------------------------------------
  TShoppingCart = class
  private
    FItems : TList<Currency>;
    FTotal : Currency;

    // 🚩 SCA147 FLAGGT DIESE.
    // Private Methode ohne Aufruf - typischer Refactoring-Rest.
    procedure RecalculateTotal;

    // OK: wird von Add() gerufen -> Wortgrenz-Suche findet 3 Vorkommen
    // (Decl + Impl-Header + Aufruf in Add) und SCA147 toleriert > 2.
    function ValidateItem(Price: Currency): Boolean;

    // 🚩 SCA147 FLAGGT DIESE.
    // strict private aendert nichts - SCA147 behandelt beide
    // Visibility-Sektionen gleich.
    procedure InvalidateCache;

    // OK: Property-Getter. Der Identifier 'GetItemCount' taucht in der
    // Property-Deklaration weiter unten auf - der Lexical-Scan zaehlt
    // das als Use (Property-Reads sind im File-Body sichtbar).
    function GetItemCount: Integer;

    // noinspection UnusedPrivateMethod
    // OK: explizit als "noch nicht benutzt" markiert. Der Suppression-Marker
    // wird vom Post-Filter (uSuppression.pas) entfernt - SCA147 wuerde sonst
    // flaggen.
    procedure ReservedForFutureUse;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Price: Currency);
    property ItemCount : Integer read GetItemCount;
    property Total     : Currency read FTotal;
  end;

  // --- Typ 2: Rechnung ------------------------------------------------------
  TInvoice = class
  strict private
    FCart : TShoppingCart;

    // 🚩 SCA147 FLAGGT DIESE.
    // Methode in strict private deklariert, kein interner Caller.
    procedure FormatHeader;
  public
    constructor Create(ACart: TShoppingCart);
    function ToString: string; reintroduce;
  end;

implementation

uses
  System.SysUtils;

// === TShoppingCart ==========================================================

procedure TShoppingCart.RecalculateTotal;
var
  i : Integer;
begin
  FTotal := 0;
  for i := 0 to FItems.Count - 1 do
    FTotal := FTotal + FItems[i];
end;

function TShoppingCart.ValidateItem(Price: Currency): Boolean;
begin
  Result := Price > 0;
end;

procedure TShoppingCart.InvalidateCache;
begin
  // ... ehemaliger Cache-Reset, Cache wurde aber im letzten Sprint entfernt
end;

function TShoppingCart.GetItemCount: Integer;
begin
  Result := FItems.Count;
end;

procedure TShoppingCart.ReservedForFutureUse;
begin
  // wird im naechsten Sprint gebraucht, vom Reviewer freigegeben
end;

constructor TShoppingCart.Create;
begin
  inherited Create;
  FItems := TList<Currency>.Create;
end;

destructor TShoppingCart.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TShoppingCart.Add(Price: Currency);
begin
  if ValidateItem(Price) then            // <- Caller fuer ValidateItem
    FItems.Add(Price);
end;

// === TInvoice ===============================================================

procedure TInvoice.FormatHeader;
begin
  // ehemals: WriteLn('--- Invoice ---'). Header wird jetzt vom UI-Layer
  // generiert, diese Helper-Methode aber nie aufgeraeumt.
end;

constructor TInvoice.Create(ACart: TShoppingCart);
begin
  inherited Create;
  FCart := ACart;
end;

function TInvoice.ToString: string;
begin
  Result := Format('Invoice with %d items', [FCart.ItemCount]);
end;

end.
