unit uReversedForRange;

// Detektor fuer `for i := A to B do` mit numerischen Literalen, A > B.
// Klassischer `downto`-vergessen-Tippfehler: Schleife hat 0 Iterationen,
// kein Compiler-Warning, sehr stiller Bug.
//
// Beispiele:
//   for i := 10 to 1   do ...  // Treffer (sollte downto sein)
//   for i := 10 downto 1 do ... // OK
//   for i := 0  to High(Arr) do // OK (nicht matchbar, kein Numeric-Literal)
//
// Erkennung: File-basierter Scan (analog uWithStatement), weil der Parser
// die Range-Expressions nicht strukturell ablegt (SkipTo([tkKwDo,...])).
// Konservatives Match: nur wenn BEIDE Grenzen numerische Literale sind.
// Negative Zahlen werden mitberuecksichtigt (for i := -5 to -10 do).
//
// Schweregrad: lsError - das ist ein sicherer Bug, keine Stilfrage.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TReversedForRangeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CommentedOutCode, ConsecutiveSection, CyclomaticComplexity, DuplicateBlock, GroupedDeclaration, IfElseBegin, LongMethod, LongParamList, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

// Findet alle for-to-Range-Verletzungen in einer Code-Zeile.
// Liefert die 1-basierte Spalte des `for`-Keywords plus die From/To-Werte
// in `Snippet` zurueck. Wert 0 = kein Match.
//
// Pattern: `for` <ident> `:=` <int> `to` <int> `do`
// Beide Ints muessen literal-numerisch (optional vorzeichen-`-`) sein.
// Wenn From > To: Treffer.
//
// InBlockComm / InParenStarComm werden vom Caller ueber Zeilen hinweg
// mitgefuehrt - analog uWithStatement.
function ScanLine(const Line: string;
  var InBlockComm, InParenStarComm: Boolean;
  out MatchCol: Integer; out FromVal, ToVal: Int64;
  out Snippet: string): Boolean;
var
  i, n, p, q : Integer;
  InStr : Boolean;
  c : Char;
  NumStr : string;
  Start : Integer;
begin
  Result   := False;
  MatchCol := 0;
  FromVal  := 0;
  ToVal    := 0;
  Snippet  := '';

  InStr := False;
  i := 1;
  n := Length(Line);

  while i <= n do
  begin
    if InBlockComm then
    begin
      p := Pos('}', Line, i);
      if p = 0 then Exit;
      InBlockComm := False;
      i := p + 1;
      Continue;
    end;
    if InParenStarComm then
    begin
      p := Pos('*)', Line, i);
      if p = 0 then Exit;
      InParenStarComm := False;
      i := p + 2;
      Continue;
    end;

    c := Line[i];

    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i+1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;

    case c of
      '''':
        begin InStr := True; Inc(i); Continue; end;
      '/':
        if (i < n) and (Line[i+1] = '/') then Exit;
      '{':
        begin
          p := Pos('}', Line, i + 1);
          if p = 0 then
          begin
            InBlockComm := True;
            Exit;
          end;
          i := p + 1;
          Continue;
        end;
      '(':
        if (i < n) and (Line[i+1] = '*') then
        begin
          p := Pos('*)', Line, i + 2);
          if p = 0 then
          begin
            InParenStarComm := True;
            Exit;
          end;
          i := p + 2;
          Continue;
        end;
    end;

    // Versuche, ein `for ... to ... do` ab Position i zu matchen.
    if (i + 3 <= n) and SameText(Copy(Line, i, 3), 'for') and
       ((i = 1) or (not IsIdent(Line[i - 1]))) and
       ((i + 3 > n) or (not IsIdent(Line[i + 3]))) then
    begin
      // Variable einlesen
      p := i + 3;
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      // Schleifenvariable - skip `var` Inline-Decl
      if (p + 3 <= n) and SameText(Copy(Line, p, 3), 'var') and
         ((p + 3 > n) or (not IsIdent(Line[p + 3]))) then
      begin
        Inc(p, 3);
        while (p <= n) and (Line[p] = ' ') do Inc(p);
      end;
      Start := p;
      while (p <= n) and IsIdent(Line[p]) do Inc(p);
      if p = Start then
      begin
        Inc(i); Continue;
      end;
      // Optionaler ': Typ' bei 'for var x: T :=' - bis zum := skippen
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      if (p <= n) and (Line[p] = ':') and ((p = n) or (Line[p + 1] <> '=')) then
      begin
        // Typ-Annotation - bis ':=' weiterlaufen
        Inc(p);
        while (p < n) and not ((Line[p] = ':') and (Line[p + 1] = '=')) do Inc(p);
      end;

      // ':='
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      if (p + 1 > n) or (Line[p] <> ':') or (Line[p+1] <> '=') then
      begin
        Inc(i); Continue;
      end;
      Inc(p, 2);

      // From-Wert: optionales '-', dann Ziffern
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      Start := p;
      if (p <= n) and (Line[p] = '-') then Inc(p);
      q := p;
      while (p <= n) and IsDigit(Line[p]) do Inc(p);
      if p = q then
      begin
        Inc(i); Continue;     // kein numerisches From -> kein Match
      end;
      NumStr := Copy(Line, Start, p - Start);
      FromVal := StrToInt64Def(NumStr, 0);

      // `to` (Word-Boundary). p + 2 <= n stellt schon sicher dass
      // Line[p + 2] existiert (p + 2 > n waere tot durch das erste
      // Guard); deshalb nur ein IsIdent-Check.
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      if not ((p + 2 <= n) and SameText(Copy(Line, p, 2), 'to') and
              not IsIdent(Line[p + 2])) then
      begin
        Inc(i); Continue;
      end;
      Inc(p, 2);

      // To-Wert
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      Start := p;
      if (p <= n) and (Line[p] = '-') then Inc(p);
      q := p;
      while (p <= n) and IsDigit(Line[p]) do Inc(p);
      if p = q then
      begin
        Inc(i); Continue;
      end;
      NumStr := Copy(Line, Start, p - Start);
      ToVal := StrToInt64Def(NumStr, 0);

      // `do` (mit Word-Boundary). Analog zur `to`-Pruefung oben:
      // p + 2 <= n macht den (p + 2 > n)-Pfad tot, deshalb nur IsIdent.
      while (p <= n) and (Line[p] = ' ') do Inc(p);
      if not ((p + 2 <= n) and SameText(Copy(Line, p, 2), 'do') and
              not IsIdent(Line[p + 2])) then
      begin
        // Range mehrzeilig - Konservativ: kein Match
        Inc(i); Continue;
      end;

      if FromVal > ToVal then
      begin
        MatchCol := i;
        Snippet  := Trim(Copy(Line, i, p + 2 - i));
        Result   := True;
        Exit;
      end;
      // Sonst weiter scannen - vielleicht gibt es spaeter noch ein for
    end;

    Inc(i);
  end;
end;

class procedure TReversedForRangeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines : TStringList;
  i, MatchCol : Integer;
  FromVal, ToVal : Int64;
  Snippet, Line : string;
  InBlockComm, InParenStarComm : Boolean;
  F : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlockComm     := False;
    InParenStarComm := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if ScanLine(Line, InBlockComm, InParenStarComm,
                  MatchCol, FromVal, ToVal, Snippet) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Reversed for-range: %d > %d (use `downto`?) - %s',
          [FromVal, ToVal, Snippet]);
        F.SetKind(fkReversedForRange);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
