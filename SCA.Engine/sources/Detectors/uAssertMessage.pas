unit uAssertMessage;

// Detektor fuer `Assert(cond);` ohne Fehlermeldung.
//
// SonarDelphi-Aequivalent: communitydelphi:AssertMessage. Ein Assert
// ohne Message liefert nur "Assertion failed at $address" - waehrend
// `Assert(cond, 'why')` dem Aufrufer sofort sagt was falsch ist.
//
// Erkennung: lexikalischer Scan. Match auf `Assert(` (Wort + `(`)
// gefolgt von einem Klammer-Inhalt, der KEIN Top-Level-Komma enthaelt
// (also nur ein Argument). String-/Kommentar-Awareness aktiv.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAssertMessageDetector = class
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

// Sucht in der Zeile (state across lines fuer Block-Comm) nach
// `Assert(`-Aufrufen mit nur einem Argument. Liefert Spalte des `Assert`
// fuer den ersten Treffer, 0 sonst.
function FindAssertSingleArg(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j     : Integer;
  InStr       : Boolean;
  pClose      : Integer;
  c           : Char;
  ArgDepth    : Integer;
  HasTopComma : Boolean;
  AssertPos   : Integer;
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
    // Match `Assert` als Wort
    if CharInSet(c, ['A', 'a']) and (i + 5 <= n) and
       SameText(Copy(Line, i, 6), 'Assert') then
    begin
      // Linke Wortgrenze
      if (i > 1) and IsIdent(Line[i - 1]) then begin Inc(i); Continue; end;
      // Rechte Wortgrenze: `(` direkt oder mit Whitespace
      j := i + 6;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j > n) or (Line[j] <> '(') then begin Inc(i); Continue; end;
      AssertPos := i;
      // Klammer-Inhalt scannen
      Inc(j);
      ArgDepth := 1;
      HasTopComma := False;
      while (j <= n) and (ArgDepth > 0) do
      begin
        c := Line[j];
        if c = '(' then Inc(ArgDepth)
        else if c = ')' then Dec(ArgDepth)
        else if (c = ',') and (ArgDepth = 1) then HasTopComma := True
        else if c = '''' then
        begin
          Inc(j);
          while j <= n do
          begin
            if Line[j] = '''' then
            begin
              if (j < n) and (Line[j + 1] = '''') then Inc(j, 2)
              else begin Inc(j); Break; end;
            end
            else Inc(j);
          end;
          Continue;
        end;
        Inc(j);
      end;
      if (ArgDepth = 0) and not HasTopComma then
      begin
        Result := AssertPos;
        Exit;
      end;
      i := j;
      Continue;
    end;
    Inc(i);
  end;
end;

class procedure TAssertMessageDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindAssertSingleArg(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Assert at column %d has no message - add a "why" string for ' +
        'easier diagnosis.', [Col]);
      F.SetKind(fkAssertMessage);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
