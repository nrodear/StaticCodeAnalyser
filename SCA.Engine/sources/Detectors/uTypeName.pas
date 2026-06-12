unit uTypeName;

// Detektor fuer Class/Record-Type-Namen, die nicht der T-Prefix-
// Konvention folgen.
//
// SonarDelphi-Aequivalent: communitydelphi:TypeName. Delphi-Konvention:
//   * Klassen-Typen heissen `TXxx`           - z.B. TStringList
//   * Records heissen `TXxx` oder `RXxx`     - z.B. TRect, RPoint
//   * Interfaces heissen `IXxx`              - z.B. IInterface
//   * Pointer-Aliasse heissen `PXxx`         - SCA100 PointerName
//   * Exceptions heissen `EXxx`              - z.B. EFOpenError
//
// Hier checken wir nur class/record (die T-Prefix-Regel). Interfaces
// und Exceptions koennten in Phase 2 als Naming-Framework dazukommen.
//
// Erkennung: lexikalischer Scan. Pattern `<Ident> = class(...)` oder
// `<Ident> = class` ohne Klammern, sowie `<Ident> = record`.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTypeNameDetector = class
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

// Liefert Position des Type-Namens wenn die Zeile `<Ident> = class`
// oder `<Ident> = record` enthaelt UND der Name nicht mit `T` beginnt.
function FindBadTypeName(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean; out Name: string): Integer;
var
  i, n, j, k : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  Start      : Integer;
  NextWord   : string;
begin
  Result := 0;
  Name   := '';
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
      // Optional generic `<...>` (Delphi-Generics)
      if (j <= n) and (Line[j] = '<') then
      begin
        Inc(j);
        while (j <= n) and (Line[j] <> '>') do Inc(j);
        if j <= n then Inc(j);
        while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      end;
      // Erwarte `=`
      if (j > n) or (Line[j] <> '=') then Continue;
      Inc(j);
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `class` oder `record`
      if (j > n) or not IsIdentStart(Line[j]) then Continue;
      k := j;
      while (k <= n) and IsIdent(Line[k]) do Inc(k);
      NextWord := LowerCase(Copy(Line, j, k - j));
      if (NextWord <> 'class') and (NextWord <> 'record') then Continue;
      // Forward-Declaration `TFoo = class;` ist OK auch ohne body
      // Ausnahme: `class of` ist ein Class-Reference-Type
      while (k <= n) and CharInSet(Line[k], [' ', #9]) do Inc(k);
      if (k + 1 <= n) and SameText(Copy(Line, k, 2), 'of') and
         ((k + 2 > n) or not IsIdent(Line[k + 2])) then Continue;
      // Pruefe Name
      if (Length(Name) >= 1) and CharInSet(Name[1], ['T', 't']) then Continue;
      // Exception-Klassen folgen der E-Prefix-Konvention (EFOpenError,
      // EYamlParseError, EArgumentException). Sind KEIN TypeName-Verstoss.
      // Heuristik: Name beginnt mit 'E' + Grossbuchstabe (CamelCase-Boundary)
      // ODER endet auf 'Error'/'Exception'/'Exc'.
      if (Length(Name) >= 2) and (Name[1] = 'E') and
         CharInSet(Name[2], ['A'..'Z']) then Continue;
      if EndsText('error', Name) or EndsText('exception', Name) then Continue;
      Result := Start;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TTypeNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
  Name   : string;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindBadTypeName(Lines[i], InBlk, InParen, Name);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Type `%s` does not follow `T<Name>` naming convention for ' +
        'class/record types - rename to start with `T`.', [Name]);
      F.SetKind(fkTypeName);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
