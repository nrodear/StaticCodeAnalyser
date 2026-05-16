unit WithStatementSample;

// Sample-Unit fuer den Detektor uWithStatement.
//
// Erwartete Treffer (WithStatement-Warning, oranger Balken im IDE-Editor):
//
//   * UseWithSingle    - einfaches `with ... do begin ... end`
//   * UseWithNested    - doppelt verschachteltes `with`
//   * UseWithInline    - `with X do Y.Foo := ...` einzeilig
//
// Erwartet KEINE Treffer (Negativ-Faelle):
//
//   * WithInString     - 'with' als Substring in einem Literal
//   * WithInComment    - 'with' nur im Kommentar
//   * WithIdent        - Bezeichner WithFoo (rechte Wortgrenze verletzt)
//   * BlockCommented   - `with` in {..}- / (*..*)-Kommentar

interface

uses
  System.SysUtils, System.Classes;

type
  TInner = class
  public
    Caption : string;
    Value   : Integer;
  end;

  TSample = class
  public
    Inner1 : TInner;
    Inner2 : TInner;

    procedure UseWithSingle;
    procedure UseWithNested;
    procedure UseWithInline;

    procedure WithInString;
    procedure WithInComment;
    procedure WithIdent;
    procedure BlockCommented;
  end;

implementation

// --- POSITIV: Erwartete Treffer ----------------------------------------

procedure TSample.UseWithSingle;
begin
  // Treffer: klassisches with-Statement
  with Inner1 do
  begin
    Caption := 'Hello';
    Value   := 42;
  end;
end;

procedure TSample.UseWithNested;
begin
  // Treffer 1 + Treffer 2: doppelt verschachteltes with -> doppelter Bug-
  // Hebel (Shadowing zwischen beiden Inner-Objekten).
  with Inner1 do
    with Inner2 do
      Caption := Caption;
end;

procedure TSample.UseWithInline;
begin
  // Treffer: einzeiliges with (ohne begin/end)
  with Inner1 do Value := Value + 1;
end;

// --- NEGATIV: Keine Treffer --------------------------------------------

procedure TSample.WithInString;
begin
  // Kein Treffer: 'with' nur als Substring im String-Literal.
  Inner1.Caption := 'connect with the server';
end;

procedure TSample.WithInComment;
begin
  // Kein Treffer: with steht nur im //-Kommentar - hier: with would be bad
  Inner1.Value := 0;
end;

procedure TSample.WithIdent;
var
  WithFoo : Integer;
  Without : Integer;
begin
  // Kein Treffer: 'with' ist Praefix in Bezeichnern, Wortgrenze rechts
  // verletzt -> Detektor matched nicht.
  WithFoo := 1;
  Without := 2;
  Inner1.Value := WithFoo + Without;
end;

procedure TSample.BlockCommented;
begin
  { Kein Treffer: das Wort with steht hier nur in einem geschweiften Block-Kommentar }
  (* Kein Treffer: das Wort with steht hier nur in einem alten Pascal-Kommentar *)
  Inner1.Value := 0;
end;

end.
