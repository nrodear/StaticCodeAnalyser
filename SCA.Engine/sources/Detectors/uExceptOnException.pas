unit uExceptOnException;

// Detektor fuer `except on E: Exception do ...` - das Fangen der Basis-
// Klasse `Exception` ist fast immer ein Code-Smell.
//
// SonarDelphi-Aequivalent: Aehnlich zu communitydelphi:CatchAllException
// (Variante davon). Begruendung:
//   * `Exception` ist die Wurzelklasse aller Delphi-Ausnahmen - inkl.
//     EAccessViolation, EOutOfMemory etc., bei denen man fast nie
//     einfach weitermachen kann ohne den Prozess neu zu starten.
//   * Spezifischere Klassen (EDatabaseError, EFOpenError, EConvertError)
//     ermoeglichen gezielten Recovery.
//
// Erkennung: lexikalisch. Pattern `on` (Wort) -> Identifier(`E`/`...`)
// -> `:` -> `Exception` (Wort exakt, nicht E*Subclass) -> `do`.
// String-/Kommentar-Awareness.
//
// Schweregrad: lsWarning - klares Bug-Risiko bei Recovery, aber Code
// laeuft. Suppression via `// noinspection` direkt vor dem on-Block.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TExceptOnExceptionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
end;

// Sucht Spalte von `on` (Wort) wenn ein `on E: Exception do`-Pattern
// gefunden wurde.
function FindOnException(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j  : Integer;
  InStr    : Boolean;
  pClose   : Integer;
  c        : Char;
  OnCol    : Integer;
  Word     : string;
  wStart   : Integer;
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
    // Wort `on`?
    if CharInSet(c, ['O', 'o']) and (i + 1 <= n) and
       SameText(Copy(Line, i, 2), 'on') then
    begin
      if (i > 1) and IsIdent(Line[i - 1]) then begin Inc(i); Continue; end;
      if (i + 2 <= n) and IsIdent(Line[i + 2]) then begin Inc(i); Continue; end;
      OnCol := i;
      // Skip whitespace
      j := i + 2;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Identifier (Binding-Variable, Name wird nicht gebraucht)
      if (j > n) or not IsIdentStart(Line[j]) then begin Inc(i); Continue; end;
      while (j <= n) and IsIdent(Line[j]) do Inc(j);
      // `:`
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j > n) or (Line[j] <> ':') then begin Inc(i); Continue; end;
      Inc(j);
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // `Exception` Wort (exakt, ohne Suffix)
      if (j > n) or not IsIdentStart(Line[j]) then begin Inc(i); Continue; end;
      wStart := j;
      while (j <= n) and IsIdent(Line[j]) do Inc(j);
      Word := Copy(Line, wStart, j - wStart);
      if SameText(Word, 'Exception') then
      begin
        Result := OnCol;
        Exit;
      end;
      Inc(i); Continue;
    end;
    Inc(i);
  end;
end;

class procedure TExceptOnExceptionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindOnException(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('`on E: Exception` at column %d catches the root class ' +
               '(incl. AV/OOM) - prefer a specific exception type.', [Col]),
        fkExceptOnException));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
