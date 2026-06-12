unit uPointerName;

// Detektor fuer Pointer-Typen, deren Name nicht mit `P` beginnt.
//
// SonarDelphi-Aequivalent: communitydelphi:PointerName (Naming-
// Convention). Delphi-Konvention seit Anfang: ein Pointer-Alias auf
// `TXxx` heisst `PXxx` - so erkennt der Leser am Namen die Indirektion.
//   * GUT:   PInteger = ^Integer;
//   * SCHLECHT: TIntPtr = ^Integer;
//
// Erkennung: lexikalisch ueber komment-bereinigten Code. Pattern
//   `<Ident> = ^<Type>` wo `<Ident>` nicht mit `P`/`p` beginnt.
//
// Schweregrad: lsHint - reines Convention/Naming.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TPointerNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

// Liefert Spalte des Ident wenn die Zeile ein Pointer-Typ-Alias
// definiert dessen Name NICHT mit `P` beginnt.
function FindBadPointerName(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j  : Integer;
  InStr    : Boolean;
  pClose   : Integer;
  c        : Char;
  Start    : Integer;
  Name     : string;
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
    if IsIdentStart(c) then
    begin
      Start := i;
      while (i <= n) and IsIdent(Line[i]) do Inc(i);
      Name := Copy(Line, Start, i - Start);
      // Skip whitespace
      j := i;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `=`
      if (j > n) or (Line[j] <> '=') then Continue;
      Inc(j);
      // Skip whitespace
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `^`
      if (j > n) or (Line[j] <> '^') then Continue;
      Inc(j);
      // Skip whitespace
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte einen Identifier (oder qualifizierte Type-Ref)
      if (j > n) or not IsIdentStart(Line[j]) then Continue;
      // Pruefe Name: muss mit `P`/`p` beginnen.
      if (Length(Name) >= 1) and CharInSet(Name[1], ['P', 'p']) then Continue;
      Result := Start;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TPointerNameDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindBadPointerName(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Pointer-type alias at column %d does not follow `P<TypeName>` ' +
        'naming convention - rename to start with `P`.', [Col]);
      F.SetKind(fkPointerName);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
