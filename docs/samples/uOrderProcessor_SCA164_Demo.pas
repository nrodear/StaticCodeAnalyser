unit uOrderProcessor_SCA164_Demo;

// SCA164 (UnusedRoutine) Demo-Quelltext.
//
// Diese Unit demonstriert wie der SCA164-Detektor "top-level Routine ohne
// Aufruf" arbeitet - mit zwei Klassen (TOrder, TPriceCalculator) plus
// einer Mischung aus Standalone-Routinen, die alle FP-Guards aktivieren
// oder den Detektor sauber flaggen lassen.
//
// Erwartete Findings nach SCA164-Lauf:
// * Zeile 79  fkUnusedRoutine "DebugDumpOrder"   (Standalone, kein Aufruf)
// * Zeile 95  fkUnusedRoutine "RetryWithBackoff" (rekursiv, nur Self-Call)
//
// Alle anderen Standalone-Routinen werden absichtlich nicht geflagged -
// jede demonstriert einen anderen FP-Guard.

interface

uses
  System.SysUtils, System.Classes;

type

  // --- Typ 1: Bestellung ----------------------------------------------------
  TOrder = class
  private
    FAmount: Currency;
    FCustomer: string;
    // Private Methode wird nirgends gerufen -> Domain von SCA147
    // (UnusedPrivateMethod), NICHT SCA164.
    procedure InvalidateCache;
  public
    constructor Create(AAmount: Currency; const ACustomer: string);
    destructor Destroy; override;
    function TotalWithTax: Currency;
    property Amount: Currency read FAmount;
    property Customer: string read FCustomer;
  end;

  // --- Typ 2: Preis-Rechner -------------------------------------------------
  TPriceCalculator = class
  public
    class function ApplyDiscount(Base: Currency; Pct: Double): Currency;
    class function RoundCents(V: Currency): Currency;
  end;

function test;

// Interface-Forward-Deklaration: SCA164 ueberspringt das (potenzieller
// Cross-Unit-Caller, dessen Existenz wir single-file nicht entscheiden
// koennen).
procedure ProcessOrder(O: TOrder);

implementation

function test2;
begin
  var
  order := TOrder.Create(1, 'test');
  var
  test := order.TotalWithTax;
end;

function test;
begin
  var
  order := TOrder.Create(1, 'test');
  var
  test := order.TotalWithTax;
end;

// === TPriceCalculator =======================================================

class function TPriceCalculator.ApplyDiscount(Base: Currency; Pct: Double)
  : Currency;
begin
  Result := Base * (1 - Pct);
end;

class function TPriceCalculator.RoundCents(V: Currency): Currency;
begin
  Result := Round(V * 100) / 100;
end;

// === TOrder =================================================================

constructor TOrder.Create(AAmount: Currency; const ACustomer: string);
begin
  FAmount := AAmount;
  FCustomer := ACustomer;
end;

destructor TOrder.Destroy;
begin
  inherited;
end;

procedure TOrder.InvalidateCache;
// Im Klassen-Body deklariert -> qualifizierter Name "TOrder.InvalidateCache"
// im AST -> SCA164-Filter Pos('.', Name)=0 schliesst sie aus. Diese Routine
// wuerde SCA147 (UnusedPrivateMethod) flaggen, nicht SCA164.
begin
  // ...
end;

function TOrder.TotalWithTax: Currency;
begin
  // Ruft die qualifizierten Klassen-Methoden auf - das sind NICHT die
  // SCA164-Kandidaten (alle haben Dot im Name).
  Result := TPriceCalculator.RoundCents(FAmount * 1.19);
end;

// === Standalone-Routinen (das SCA164-Spielfeld) =============================

procedure DebugDumpOrder(O: TOrder);
// 🚩 SCA164 FLAGGT DIESE.
// Ist nirgends im Unit gerufen, hat keine interface-Forward-Decl,
// keinen FP-Guard.
begin
  WriteLn(Format('[DBG] Order %s: %m', [O.Customer, O.Amount]));
end;

procedure FormatInvoiceHeader(O: TOrder; SL: TStrings);
// Wird von ProcessOrder gerufen -> kein Finding.
begin
  SL.Add('--- Invoice for ' + O.Customer + ' ---');
end;

procedure RetryWithBackoff(Attempt: Integer);
// 🚩 SCA164 FLAGGT DIESE.
// Rekursiv, ruft sich selbst - SonarDelphi-konformer Self-Call-Filter
// erkennt: Match in eigener Range zaehlt nicht als Verwendung.
begin
  if Attempt < 3 then
  begin
    Sleep(Attempt * 100);
    RetryWithBackoff(Attempt + 1); // <- Self-Call, NICHT als Use gezaehlt
  end;
end;

constructor StandaloneCtor;
// FP-Guard "IsCtorOrDtor": TypeRef beginnt mit 'constructor' -> exempt.
// (In echtem Pascal stehen Konstruktoren in Klassen; hier nur zum Zeigen
// dass der Guard greift.)
begin
end;

procedure Register;
// FP-Guard "SameText(Name, 'register')": IDE-Plugin-Bootstrap-Konvention,
// die IDE ruft Register per Pkg-Loader implizit -> exempt.
begin
  RegisterComponents('OrderPalette', [TOrder]);
end;

function MoveNext: Boolean;
// FP-Guard "Enumerator-Trio": for-in-Loops rufen MoveNext / GetEnumerator /
// Current implizit -> exempt.
begin
  Result := False;
end;

procedure ForwardDeclaredHelper; forward;
// FP-Guard "HasExternalReferenceDirective" matched ';forward' -> der
// Forward-Decl-Knoten selbst wird nicht geprueft. Die spaetere Impl
// koennte separat ein Finding sein - hier ist sie aber genutzt.

procedure ProcessOrder(O: TOrder);
// FP-Guard "InterfaceMethods.IndexOf >= 0": diese Routine ist im
// interface-Teil forward-deklariert -> exempt (potenzieller Cross-Unit-
// Caller den der Single-File-Detector nicht sehen kann).
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    FormatInvoiceHeader(O, SL); // <- Caller fuer
    // FormatInvoiceHeader
    ForwardDeclaredHelper; // <- Caller fuer den
    // spaeteren Impl
    SL.Add(Format('Total: %m', [O.TotalWithTax]));
    WriteLn(SL.Text);
  finally
    SL.Free;
  end;
end;

procedure ForwardDeclaredHelper;
// Wird von ProcessOrder gerufen -> kein Finding.
begin
  WriteLn('(helper)');
end;

end.
