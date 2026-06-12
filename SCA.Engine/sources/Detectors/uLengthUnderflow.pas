unit uLengthUnderflow;

// Detektor: `Length(s) - X` / `.Count - X` ohne vorausgehenden Guard.
//
// Pascal's `Length` und `.Count` liefern Native-Int. Wenn der Wert 0 ist
// und man subtrahiert, gibt das eine ganz normale negative Zahl - aber
// die wird haeufig sofort als Index oder Range verwendet:
//
//   for i := 0 to Length(s) - 1 do ...        // Length(s)=0 -> 0 to -1 -> 0 Iter (OK)
//   k := Length(s) - 1;                       // k = -1 wenn s leer
//   for i := 0 to Length(s) - 2 do            // Length(s)<=1 -> -2 oder -1
//   Move(s[Length(s) - 4], buf, 4);           // CRASH wenn Length(s) < 4
//
// Der erste Fall ist OK (0 to -1 hat 0 Iterationen). Die anderen sind
// klassische String-Slicing-Bugs.
//
// Heuristik (file-scan, weil der Parser Length/.Count nicht als AST-Knoten
// auffaltet, sondern als Token-String in TypeRef):
//   * RHS / Range-Expression enthaelt 'Length(' oder '.Count' / '.Length'
//     gefolgt von einem Whitespace-toleranten ' - <ConstOrVar>'.
//   * Schwelle ConstOrVar > 1: bei -1 ist es das `for ... to Length-1`
//     Idiom (siehe oben), das ist statistisch fast immer sauber.
//   * `Length(s) - K` mit `K > 1` ist verdaechtig -> Treffer.
//   * Wir koennen statisch nicht checken, ob ein Guard `if Length(s) >= K`
//     vorausgeht; deshalb nur als Hint melden (lsHint).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLengthUnderflowDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;
  // Schwelle: bei -1 ist es das Loop-Idiom `0 to Length-1`, bei -2 etc.
  // wird es verdaechtig (oder bei dynamisch berechnetem K).
  MIN_OFFSET_TO_FLAG = 2;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Sucht ab Position StartIdx in S das naechste vollstaendige Match
// `<Length-or-Count-Expr> - <numeric>` ausserhalb von Strings/Comments.
// Liefert Treffer-Spalte (1-basiert) oder 0.
function FindMatch(const S: string; var InStr: Boolean;
  var Offset: Integer; out MatchCol: Integer; out Detail: string): Boolean;
var
  i, n, p : Integer;
  c : Char;
  Token : string;
  Start: Integer;
  NumStart: Integer;
begin
  Result := False;
  MatchCol := 0;
  Offset := 0;
  Detail := '';
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    c := S[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (S[i+1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;

    case c of
      '''':
        begin InStr := True; Inc(i); Continue; end;
      '/':
        if (i < n) and (S[i+1] = '/') then Exit;     // Rest ist Kommentar
    end;

    // Match `Length(` als ganzes Wort, oder `.count`/`.length` als
    // Property-Access. Token wird fuer das Finding-Detail gebraucht;
    // welche Variante gematcht hat, ist danach nicht mehr relevant.
    Token := '';
    if (i + 6 <= n) and SameText(Copy(S, i, 6), 'length') and
       ((i = 1) or (not IsIdent(S[i - 1]))) and
       (S[i + 6] = '(') then
    begin
      // Klammern paaren
      p := i + 7;
      var Depth := 1;
      while (p <= n) and (Depth > 0) do
      begin
        case S[p] of
          '(': Inc(Depth);
          ')': Dec(Depth);
        end;
        Inc(p);
      end;
      if Depth <> 0 then Exit;     // unbalanced
      Token := Copy(S, i, p - i);
      Start := i;
      i := p;
    end
    // Match `.count` / `.length` als ganzes Wort
    else if (c = '.') and
            ((i + 5 <= n) and SameText(Copy(S, i + 1, 5), 'count') and
             ((i + 6 > n) or (not IsIdent(S[i + 6])))) then
    begin
      Token := Copy(S, i, 6);
      Start := i;
      Inc(i, 6);
    end
    else if (c = '.') and
            ((i + 6 <= n) and SameText(Copy(S, i + 1, 6), 'length') and
             ((i + 7 > n) or (not IsIdent(S[i + 7])))) then
    begin
      Token := Copy(S, i, 7);
      Start := i;
      Inc(i, 7);
    end
    else
    begin
      Inc(i);
      Continue;
    end;

    // Ab hier: gerade Length(...) oder .Count gesehen. Pruefen ob ' - <num>'
    // folgt.
    p := i;
    while (p <= n) and (S[p] = ' ') do Inc(p);
    if (p > n) or (S[p] <> '-') then Continue;
    Inc(p);
    while (p <= n) and (S[p] = ' ') do Inc(p);
    NumStart := p;
    while (p <= n) and IsDigit(S[p]) do Inc(p);
    if p = NumStart then Continue;     // kein numerischer Offset

    var NumStr := Copy(S, NumStart, p - NumStart);
    var NVal : Integer;
    if not TryStrToInt(NumStr, NVal) then Continue;
    if NVal < MIN_OFFSET_TO_FLAG then Continue;

    MatchCol := Start;
    Offset   := NVal;
    Detail   := Token + ' - ' + NumStr;
    Result   := True;
    Exit;
  end;

  // ggf. InStr bleibt erhalten fuer naechste Iteration (nicht hier relevant -
  // wir scannen pro Zeile)
end;

class procedure TLengthUnderflowDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines : TStringList;
  i, MatchCol : Integer;
  Offset : Integer;
  Detail, Line : string;
  InStr : Boolean;
  F : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InStr := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      // Wir scannen jede Zeile separat - String-Literale ueber Zeilengrenzen
      // sind in Pascal nicht ueblich. InStr wird trotzdem mitgefuehrt, weil
      // der Lexer normalerweise so arbeitet.
      var LinePos := 1;
      while LinePos <= Length(Line) do
      begin
        var Sub := Copy(Line, LinePos, MaxInt);
        if not FindMatch(Sub, InStr, Offset, MatchCol, Detail) then Break;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Possible underflow: %s (no guard for empty string/list?)',
          [Detail]);
        F.SetKind(fkLengthUnderflow);
        Results.Add(F);

        // MatchCol ist die 1-basierte Position des Matches IN `Sub`. Die
        // entsprechende Position in `Line` ist `LinePos + MatchCol - 1`.
        // Die naechste Scan-Position liegt direkt nach dem Match:
        //   LinePos + MatchCol - 1 + Length(Detail).
        // Frueher: ohne das "-1" - das hat 1 Zeichen pro Treffer
        // uebersprungen und konnte direkt-angrenzende Matches verlieren.
        LinePos := LinePos + MatchCol - 1 + Length(Detail);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
