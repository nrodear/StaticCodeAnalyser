unit uRedundantParentheses;

// Detektor fuer doppelte/redundante Klammern um einfache Ausdruecke.
//
// SonarDelphi-Aequivalent: communitydelphi:RedundantParentheses. Ein
// `((X))` oder `((42))` ist Rauschen - ein Paar Klammern reicht, oft
// gar keins. Reine Identifier/Literale brauchen keine Klammern fuer
// Operator-Praezedenz.
//
// Erkennung: lexikalisch. Pattern `(` ws `(` ws <simple> ws `)` ws `)`
// wobei <simple> ein einzelner Identifier, eine Zahl oder ein String-
// Literal ist. Komplexere Ausdruecke (mit `+`, `-`, `*`, `,`, ...) sind
// ausgeschlossen - dort koennten innere Parens fuer Praezedenz wichtig
// sein. String-/Kommentar-Awareness aktiv.
//
// Schweregrad: lsHint - Style/Lesbarkeit.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRedundantParenthesesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
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

function IsDigit(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

// Liefert Position des aeusseren `(` wenn das Pattern `((<simple>))`
// gefunden wurde. <simple> = Identifier, Zahl, Hex-Literal oder
// String-Literal.
function FindDoubleParen(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j, k : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  HasInner   : Boolean;
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
    // Match `((`
    if (c = '(') and (i < n) and (Line[i + 1] = '(') then
    begin
      // Skip whitespace nach `((`
      j := i + 2;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if j > n then begin Inc(i); Continue; end;
      // Erwarte ein einfaches Token
      HasInner := False;
      if IsIdentStart(Line[j]) then
      begin
        while (j <= n) and IsIdent(Line[j]) do Inc(j);
        HasInner := True;
      end
      else if IsDigit(Line[j]) or (Line[j] = '$') then
      begin
        if Line[j] = '$' then Inc(j);
        while (j <= n) and IsIdent(Line[j]) do Inc(j);
        HasInner := True;
      end
      else if Line[j] = '''' then
      begin
        // String-Literal
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
        HasInner := True;
      end;
      if not HasInner then begin Inc(i); Continue; end;
      // Skip whitespace
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `))`
      if (j + 1 > n) or (Line[j] <> ')') or (Line[j + 1] <> ')') then
      begin
        Inc(i); Continue;
      end;
      // Match - aber nur wenn das Zeichen NACH `))` kein Punkt/Bracket
      // ist (z.B. `(((X)).Field)` muss vorsichtig sein). Wir akzeptieren
      // den Match einfach.
      k := j + 2;
      // Falls direkt danach `.`, `[`, `(` kommt, ist `((X))` Teil eines
      // Method-Access-Chains und vielleicht nicht redundant.
      if (k <= n) and CharInSet(Line[k], ['.', '[', '(']) then
      begin
        Inc(i); Continue;
      end;
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TRedundantParenthesesDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindDoubleParen(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Redundant double parentheses at column %d - drop the outer ' +
        '`(...)` around the simple expression.', [Col]);
      F.SetKind(fkRedundantParentheses);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
