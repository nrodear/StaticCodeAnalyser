unit uFixArgs;

// Fix-Datenfeld (Konzept_FixDatenfeld_2026-10-28.md, Abschnitt 4.1) - S0:
// nur der Werttyp + das Feld, noch ohne Aufrufer. Haengt nur von SysUtils ab
// (FPC-tauglich, anders als uSCAConsts - das hat der FPC-Pruefstand nie
// uebersetzt) - Grund: reDelphix soll den Fix-Weg eines Regel-Treffers
// (Spalte, Bezeichner, Wert, Form) kuenftig aus diesem Feld lesen statt den
// Meldungstext zu zerlegen, ohne den Pascal-Parser dafuer zu brauchen.
//
// Werttyp, kein Objekt: keine Freigabe, kein Klonzwang je Kopie - eine
// Record-Zuweisung (z.B. in TLeakFinding.CopyFrom) kopiert das Feld richtig.
// Put kopiert das Pairs-Array VOR dem Anhaengen (copy-on-write) - eine
// Record-Zuweisung teilt das dynamische Array sonst mit dem Original, und
// ein Put am Klon aenderte dann das Original mit.

interface

uses
  System.SysUtils;

const
  FA_NAME  = 'name';
  FA_NAME2 = 'name2';
  FA_TYPE  = 'type';
  FA_VALUE = 'value';
  FA_EXPR  = 'expr';
  FA_EXPR2 = 'expr2';
  FA_OP    = 'op';
  FA_COUNT = 'count';
  FA_LINE  = 'line';
  FA_FORM  = 'form';

type
  TFixArgs = record
    Col   : Integer;        // 1-basierte Spalte des Treffers, 0 = keine
    Pairs : TArray<string>; // Schluessel, Wert, Schluessel, Wert ...; nil = leer
    function TryGet(const AKey: string; out AValue: string): Boolean;
    function Get(const AKey: string; const ADefault: string = ''): string;
    procedure Put(const AKey, AValue: string);
    function IsEmpty: Boolean;
    function SameAs(const B: TFixArgs): Boolean; // reihenfolgefrei
  end;

implementation

function TFixArgs.TryGet(const AKey: string; out AValue: string): Boolean;
var
  i: Integer;
begin
  i := 0;
  while i + 1 <= High(Pairs) do
  begin
    if Pairs[i] = AKey then
    begin
      AValue := Pairs[i + 1];
      Exit(True);
    end;
    Inc(i, 2);
  end;
  AValue := '';
  Result := False;
end;

function TFixArgs.Get(const AKey: string; const ADefault: string): string;
begin
  if not TryGet(AKey, Result) then
    Result := ADefault;
end;

procedure TFixArgs.Put(const AKey, AValue: string);
var
  i: Integer;
  Copied: TArray<string>;
begin
  i := 0;
  while i + 1 <= High(Pairs) do
  begin
    if Pairs[i] = AKey then
    begin
      // Copy-on-write auch hier: eine geteilte Kopie des Arrays (nach einer
      // Record-Zuweisung) bleibt unberuehrt, nur der eigene Klon aendert sich.
      Copied := Copy(Pairs);
      Copied[i + 1] := AValue;
      Pairs := Copied;
      Exit;
    end;
    Inc(i, 2);
  end;
  Copied := Copy(Pairs);
  SetLength(Copied, Length(Copied) + 2);
  Copied[High(Copied) - 1] := AKey;
  Copied[High(Copied)] := AValue;
  Pairs := Copied;
end;

function TFixArgs.IsEmpty: Boolean;
begin
  Result := (Col = 0) and (Length(Pairs) = 0);
end;

function TFixArgs.SameAs(const B: TFixArgs): Boolean;
var
  i: Integer;
  V: string;
begin
  if Col <> B.Col then Exit(False);
  if Length(Pairs) <> Length(B.Pairs) then Exit(False);
  i := 0;
  while i + 1 <= High(Pairs) do
  begin
    if not B.TryGet(Pairs[i], V) or (V <> Pairs[i + 1]) then
      Exit(False);
    Inc(i, 2);
  end;
  Result := True;
end;

end.
