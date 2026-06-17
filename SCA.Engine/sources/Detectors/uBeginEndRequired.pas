unit uBeginEndRequired;

// Detektor fuer Statement-Bodies, die kein `begin..end` verwenden, obwohl
// die Konvention im Projekt es vorschreiben sollte.
//
// SonarDelphi-Aequivalent: communitydelphi:BeginEndRequired. Argumentation:
//   * `if X then Y;` ist optisch leicht zu ueberlesen.
//   * Beim Hinzufuegen einer zweiten Anweisung muss der Code Reviewer
//     daran denken, `begin/end` nachzuruesten - tut er es nicht, gehoert
//     die neue Zeile NICHT zum if-Block.
//   * Konsistente begin/end-Verwendung erspart diese Fehlerklasse.
//
// Erkennung: lexikalisch. Pattern `then`/`else`/`do` (Wort) -> ws -> ein
// Token das NICHT `begin` und NICHT `if` ist (Else-If-Kette erlaubt).
// String-/Kommentar-Awareness aktiv. Pro Treffer eine Meldung.
//
// Hinweis: Style-Rule mit Debatten-Potenzial. Viele Delphi-Codebases
// nutzen die kompakte Form bewusst. Deshalb: lsHint und im Profile-
// System leicht abschaltbar.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TBeginEndRequiredDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
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

// Pruefe ob ab Position p das Wort `kw` (case-insensitive) an einer
// Wortgrenze steht. Liefert Endposition oder 0.
function MatchWord(const Line: string; p: Integer; const Kw: string): Integer;
var
  n, len : Integer;
begin
  Result := 0;
  n := Length(Line);
  len := Length(Kw);
  if (p + len - 1 > n) then Exit;
  if not SameText(Copy(Line, p, len), Kw) then Exit;
  if (p > 1) and IsIdent(Line[p - 1]) then Exit;
  if (p + len <= n) and IsIdent(Line[p + len]) then Exit;
  Result := p + len;
end;

// Liefert eine Liste von Spalten in der Zeile, wo `then`/`else`/`do`
// nicht von `begin` oder `if` (else-if) gefolgt wird.
procedure CollectBareBranches(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean; Cols: TList<Integer>);
var
  i, n, j, k : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  KwEnd      : Integer;
  KwCol      : Integer;
  IsBranch   : Boolean;
  NextWord   : string;
  Start      : Integer;
begin
  InStr := False;
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
    // Match `then`/`else`/`do` an Wortgrenze
    IsBranch := False;
    KwEnd := 0;
    KwCol := i;
    if CharInSet(c, ['t', 'T']) then
    begin
      KwEnd := MatchWord(Line, i, 'then');
      if KwEnd > 0 then IsBranch := True;
    end
    else if CharInSet(c, ['e', 'E']) then
    begin
      KwEnd := MatchWord(Line, i, 'else');
      if KwEnd > 0 then IsBranch := True;
    end
    else if CharInSet(c, ['d', 'D']) then
    begin
      KwEnd := MatchWord(Line, i, 'do');
      if KwEnd > 0 then IsBranch := True;
    end;
    if not IsBranch then begin Inc(i); Continue; end;
    // Skip whitespace
    j := KwEnd;
    while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
    if j > n then begin i := KwEnd; Continue; end;
    if not IsIdentStart(Line[j]) then
    begin
      i := KwEnd; Continue;
    end;
    // Word scannen
    Start := j;
    k := j;
    while (k <= n) and IsIdent(Line[k]) do Inc(k);
    NextWord := LowerCase(Copy(Line, Start, k - Start));
    // Erlaubt: begin, if (else-if-Kette), case, try, for, while, repeat,
    // with, asm, raise (raise as branch-body is fine).
    if (NextWord = 'begin') or (NextWord = 'if') or
       (NextWord = 'case') or (NextWord = 'try') or
       (NextWord = 'for') or (NextWord = 'while') or
       (NextWord = 'repeat') or (NextWord = 'with') or
       (NextWord = 'asm') or (NextWord = 'raise') or
       (NextWord = 'exit') or (NextWord = 'break') or
       (NextWord = 'continue') then
    begin
      i := k; Continue;
    end;
    Cols.Add(KwCol);
    i := k;
  end;
end;

class procedure TBeginEndRequiredDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  Cached : Boolean;
  i      : Integer;
  Cols   : TList<Integer>;
  Col    : Integer;
  InBlk, InParen : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  Cols := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Cols.Clear;
      CollectBareBranches(Lines[i], InBlk, InParen, Cols);
      for Col in Cols do
        Results.Add(TLeakFinding.New(FileName, '', i + 1,
          Format('Branch at column %d uses a single statement without ' +
                 '`begin..end` - explicit blocks survive future additions ' +
                 'without re-indenting errors.', [Col]),
          fkBeginEndRequired));
    end;
  finally
    Cols.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
