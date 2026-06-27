unit uWithStatement;

// Detektor fuer das `with X do ...` Statement.
//
// Warum gemeldet:
//   Die `with`-Anweisung loest Bezeichner zur Compile-Zeit gegen Felder
//   des with-Objekts auf. Wird spaeter in einer der beteiligten Klassen
//   ein neues Feld mit gleichem Namen hinzugefuegt, aendert sich die
//   Semantik der `with`-Bloecke still - kein Compiler-Hint, kein Warning.
//   Marco Cantu, delphi.org und Stack Overflow zaehlen das zu den
//   haeufigsten Bug-Quellen in Delphi-Code (vgl. ReDelphi-Roadmap und
//   Top-10-Delphi-Probleme-Recherche).
//
// Erkennung:
//   File-basierter Scan, NICHT AST. Der Parser mapped `with X do` aktuell
//   auf nkCall mit dem with-Ausdruck als Name - das ist von einem normalen
//   Methodenaufruf nicht unterscheidbar. Daher zeilenweise Lexing analog
//   zu uTodoComment:
//     * Pascal-String-Literale ('...' inkl. ''-Escape) ueberspringen
//     * //-Zeilenkommentar ueberspringen
//     * {...}- und (*...*)-Blockkommentare ueberspringen (mehrzeilig)
//     * Match auf `with` als ganzes Wort (linke + rechte Wortgrenze)
//
// Schweregrad: lsWarning. Kein Bug per se, aber Bug-Risiko hoch genug
// dass eine sichtbare Markierung (gelber/oranger Balken im IDE-Editor)
// gerechtfertigt ist. Suppression ueber `// noinspection` direkt vor der
// Zeile.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TWithStatementDetector = class
  public
    // UnitNode wird nicht verwendet - File-Scan. Signatur bleibt aus
    // Konsistenz mit den anderen Detektoren (RunAllDetectors-Closure).
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MagicNumber, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  KW           = 'with';
  KW_LEN       = 4;
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Findet die 1-basierte Spalte des ersten Top-Level `with`-Keywords in der
// Zeile (also: ausserhalb String-Literal, ausserhalb {..}/(*..*)/// und
// mit beidseitiger Wortgrenze). 0 wenn keines.
//
// InBlockComm wird ueber Zeilen hinweg vom Caller mitgefuehrt - True wenn
// die Zeile innerhalb eines noch offenen {...} oder (*...*) startet bzw.
// am Zeilenende noch offen ist.
function FindWith(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n  : Integer;
  InStr : Boolean;
  pClose: Integer;
  c, nx : Char;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    // {...}-Blockkommentar offen -> bis '}' skippen
    if InBlockComm then
    begin
      pClose := Pos('}', Line, i);
      if pClose = 0 then Exit;       // ganze Zeile ist Kommentar
      InBlockComm := False;
      i := pClose + 1;
      Continue;
    end;

    // (*...*)-Blockkommentar offen -> bis '*)' skippen
    if InParenStarComm then
    begin
      pClose := Pos('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2;
      Continue;
    end;

    c := Line[i];

    // String-Literal: '..'
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i+1] = '''') then
          Inc(i, 2)                  // ''-Escape
        else
        begin
          InStr := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
      Continue;
    end;

    case c of
      '''':
        begin
          InStr := True;
          Inc(i);
          Continue;
        end;
      '/':
        // '//' - Rest der Zeile ist Kommentar
        if (i < n) and (Line[i+1] = '/') then Exit;
      '{':
        begin
          // {...}-Block; pruefen ob er auf dieser Zeile schliesst
          pClose := Pos('}', Line, i + 1);
          if pClose = 0 then
          begin
            InBlockComm := True;
            Exit;
          end;
          i := pClose + 1;
          Continue;
        end;
      '(':
        // (* ... *)-Block (alter Pascal-Kommentar)?
        if (i < n) and (Line[i+1] = '*') then
        begin
          pClose := Pos('*)', Line, i + 2);
          if pClose = 0 then
          begin
            InParenStarComm := True;
            Exit;
          end;
          i := pClose + 2;
          Continue;
        end;
    end;

    // Keyword-Match: case-insensitive, mit Wortgrenze auf beiden Seiten
    if (i + KW_LEN - 1 <= n) and
       SameText(Copy(Line, i, KW_LEN), KW) then
    begin
      // Linke Grenze
      if (i > 1) and IsIdent(Line[i - 1]) then
      begin
        Inc(i);
        Continue;
      end;
      // Rechte Grenze
      if (i + KW_LEN <= n) then
      begin
        nx := Line[i + KW_LEN];
        if IsIdent(nx) then
        begin
          Inc(i);
          Continue;
        end;
      end;
      Exit(i);
    end;

    Inc(i);
  end;
end;

class procedure TWithStatementDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines           : TStringList;
  Line, Snippet   : string;
  i, MatchCol     : Integer;
  InBlockComm     : Boolean;
  InParenStarComm : Boolean;
  F               : TLeakFinding;
  Cached          : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlockComm     := False;
    InParenStarComm := False;

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];

      // Pro Zeile nur den ersten Treffer melden - mehrfaches `with` in einer
      // Zeile (selten, aber moeglich: `with a do with b do ...`) ist als
      // Stilfrage ohnehin dieselbe Befund-Klasse, ein Finding genuegt.
      MatchCol := FindWith(Line, InBlockComm, InParenStarComm);
      if MatchCol <= 0 then Continue;

      // Snippet ab `with` bis Zeilenende, getrimmt + ggf. abgeschnitten
      Snippet := Trim(Copy(Line, MatchCol, MaxInt));
      if Length(Snippet) > 80 then
        Snippet := Copy(Snippet, 1, 77) + '...';

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := 'with-Statement (Scope-Shadowing): ' + Snippet;
      F.SetKind(fkWithStatement);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
