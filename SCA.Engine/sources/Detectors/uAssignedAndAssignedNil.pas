unit uAssignedAndAssignedNil;

// Detektor fuer redundante Pattern `Assigned(X) and (X <> nil)` bzw. die
// Variation `(X <> nil) and Assigned(X)`.
//
// SonarDelphi-Aequivalent: communitydelphi:AssignedAndAssignedNil.
// Begruendung: `Assigned(X)` ist semantisch identisch zu `X <> nil` fuer
// Pointer/Klassen-Instanzen. Die Kombination beider Checks ist also
// redundant - der zweite Check kann nie ein anderes Ergebnis liefern.
//
// Erkennung: lexikalisch. Suche nach `Assigned(<Id>)` gefolgt von ` and `
// gefolgt von `(<gleiche Id> <> nil)` (modulo Whitespace, case-
// insensitive). String-/Kommentar-Awareness.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAssignedAndAssignedNilDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
end;

// Hilfs-Funktion: parse `Assigned(<Id>)` ab Position p. Bei Erfolg:
// gibt Position direkt nach dem `)` zurueck plus extrahierten Identifier.
// Bei Misserfolg: 0.
function ParseAssignedCall(const Line: string; p: Integer; out IdName: string): Integer;
var
  n, q  : Integer;
begin
  Result := 0;
  IdName := '';
  n := Length(Line);
  if (p + 7 > n) then Exit;
  if not SameText(Copy(Line, p, 8), 'Assigned') then Exit;
  if (p > 1) and IsIdent(Line[p - 1]) then Exit;
  q := p + 8;
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q > n) or (Line[q] <> '(') then Exit;
  Inc(q);
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q > n) or not IsIdentStart(Line[q]) then Exit;
  var Start: Integer; Start := q;
  while (q <= n) and IsIdent(Line[q]) do Inc(q);
  IdName := Copy(Line, Start, q - Start);
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q > n) or (Line[q] <> ')') then Exit;
  Result := q + 1;
end;

// Hilfs-Funktion: parse `<Id> <> nil` ab Position p (innerhalb von
// `(...)`-Klammern; wir akzeptieren auch ohne Klammern). Bei Erfolg:
// Position nach `nil`. Bei Misserfolg: 0.
function ParseNotNil(const Line: string; p: Integer; const ExpectedId: string): Integer;
var
  n, q     : Integer;
  IdName   : string;
  HadParen : Boolean;
begin
  Result := 0;
  n := Length(Line);
  q := p;
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  HadParen := False;
  if (q <= n) and (Line[q] = '(') then begin HadParen := True; Inc(q); end;
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q > n) or not IsIdentStart(Line[q]) then Exit;
  var Start: Integer; Start := q;
  while (q <= n) and IsIdent(Line[q]) do Inc(q);
  IdName := Copy(Line, Start, q - Start);
  if not SameText(IdName, ExpectedId) then Exit;
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q + 1 > n) then Exit;
  if (Line[q] <> '<') or (Line[q + 1] <> '>') then Exit;
  Inc(q, 2);
  while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
  if (q + 2 > n) then Exit;
  if not SameText(Copy(Line, q, 3), 'nil') then Exit;
  if (q + 3 <= n) and IsIdent(Line[q + 3]) then Exit;
  q := q + 3;
  if HadParen then
  begin
    while (q <= n) and CharInSet(Line[q], [' ', #9]) do Inc(q);
    if (q > n) or (Line[q] <> ')') then Exit;
    Inc(q);
  end;
  Result := q;
end;

// Liefert Spalte von `Assigned` wenn `Assigned(X) and (X <> nil)` oder
// `(X <> nil) and Assigned(X)` gefunden, sonst 0.
function FindAssignedAndNil(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j    : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  Id1        : string;
  After      : Integer;
  AfterAnd   : Integer;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    // Versuche `Assigned(...)` zu parsen
    if CharInSet(c, ['A', 'a']) then
    begin
      After := ParseAssignedCall(Line, i, Id1);
      if After > 0 then
      begin
        // Skip ` and `
        j := After;
        while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
        if (j + 2 <= n) and SameText(Copy(Line, j, 3), 'and') and
           ((j + 3 > n) or not IsIdent(Line[j + 3])) then
        begin
          AfterAnd := j + 3;
          // Pruefe `(<Id1> <> nil)` oder `<Id1> <> nil`
          if ParseNotNil(Line, AfterAnd, Id1) > 0 then
          begin
            Result := i;
            Exit;
          end;
        end;
        i := After;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

class procedure TAssignedAndAssignedNilDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindAssignedAndNil(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        '`Assigned(X) and (X <> nil)` at column %d is redundant - ' +
        '`Assigned` already implies `<> nil`.', [Col]);
      F.SetKind(fkAssignedAndAssignedNil);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
