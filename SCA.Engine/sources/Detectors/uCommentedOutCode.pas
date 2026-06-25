unit uCommentedOutCode;

// Detektor fuer "auskommentierten Code".
//
// SonarDelphi-Aequivalent: communitydelphi:CommentedOutCode. Heuristik:
// ein Kommentar (//- oder Block-) ist verdaechtig, wenn sein Inhalt
// Pascal-syntaktische Marker enthaelt, die typisch fuer Code sind und
// nicht fuer Prosa:
//   * Semikolon am Zeilenende (`...;`)
//   * Zuweisungs-Operator `:=`
//   * `begin`/`end`-Schluesselwoerter als ganzes Wort
//   * `procedure`/`function`-Deklaration
//
// Die Heuristik ist bewusst konservativ (zwei oder mehr Marker pro
// Kommentar) - eine Kommentar-Zeile wie "use FreeAndNil; clearer than
// Free" hat nur ein `;` und ist Prosa, nicht Code. Wenn zusaetzlich `:=`
// oder `end`/`begin` drinsteht, ist es ziemlich sicher Code.
//
// Schweregrad: lsHint - kein Bug, aber tote Wartungsschuld (commented-
// out Code rottet weg, niemand traut sich es zu loeschen).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCommentedOutCodeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, IfElseBegin, LowercaseKeyword, NestedRoutine, RedundantJump, SQLInjection, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// SQLInjection: Fix-Template-Strings ('Results.Add()' o.ae.) via String-Concat
// werden faelschlich als SQL-Concat gematcht - Self-Scan-Artefakt, kein Bug.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Strippt Markdown-Inline-Code-Spans (`code`) aus dem Kommentar-Inhalt.
// Doc-Kommentare zitieren Pascal-Code via Backticks ('`for i := 1 do`')
// als Beispiel, nicht als commented-out Code. Ohne Strip schlaegt der
// Marker-Score in solchen Kommentaren immer den Threshold (`for`, `:=`, ...).
function StripBacktickCodeSpans(const S: string): string;
var
  i, n  : Integer;
  InBT  : Boolean;
  Buf   : TStringBuilder;
begin
  Buf := TStringBuilder.Create;
  try
    InBT := False;
    n := Length(S);
    i := 1;
    while i <= n do
    begin
      if S[i] = '`' then
      begin
        InBT := not InBT;
        Inc(i);
        Continue;
      end;
      if not InBT then Buf.Append(S[i]);
      Inc(i);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

// Zaehlt code-typische Marker im Kommentar-Inhalt.
function ScoreCodeMarkers(const Raw: string): Integer;
var
  Content  : string;
  Lower    : string;
  Trimmed  : string;
  pAssign  : Integer;
  function ContainsWord(const W: string): Boolean;
  var k, lenW, lenS : Integer;
  begin
    Result := False;
    lenW := Length(W); lenS := Length(Lower);
    if lenW = 0 then Exit;
    k := 1;
    while k <= lenS - lenW + 1 do
    begin
      if Copy(Lower, k, lenW) = W then
      begin
        // Wortgrenzen pruefen
        if ((k = 1) or not IsIdentChar(Lower[k - 1])) and
           ((k + lenW > lenS) or not IsIdentChar(Lower[k + lenW])) then
        begin
          Result := True;
          Exit;
        end;
      end;
      Inc(k);
    end;
  end;
begin
  Result := 0;
  // Backtick-Code-Spans entfernen BEVOR die Marker gezaehlt werden.
  Content := StripBacktickCodeSpans(Raw);
  Lower := LowerCase(Content);
  // Marker 1: Inhalt endet mit Semikolon (nach trim)
  Trimmed := Trim(Content);
  if (Trimmed <> '') and (Trimmed[Length(Trimmed)] = ';') then Inc(Result);
  // Marker 2: enthaelt `:=`-Operator (Pascal-Assign)
  pAssign := Pos(':=', Content);
  if pAssign > 0 then Inc(Result);
  // Marker 3-6: enthaelt typische Code-Keywords als Wort
  if ContainsWord('begin')     then Inc(Result);
  if ContainsWord('end')       then Inc(Result);
  if ContainsWord('procedure') then Inc(Result);
  if ContainsWord('function')  then Inc(Result);
  if ContainsWord('if')        then Inc(Result);
  if ContainsWord('then')      then Inc(Result);
  if ContainsWord('for')       then Inc(Result);
  if ContainsWord('while')     then Inc(Result);
  // Schwellwert: ab 2 Markern ist es vermutlich Code (Caller filtert).
end;

// Pro Zeile: extrahiert den //-Kommentar-Inhalt (rest nach `//`) und
// gibt Spalte des `//` zurueck wenn der Inhalt Code-Marker hat, sonst 0.
function FindCommentedOutCode(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, pClose : Integer;
  InStr        : Boolean;
  c            : Char;
  CmtContent   : string;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      // Sammle den Kommentar-Inhalt bis `}` (oder Zeilenende)
      pClose := PosEx('}', Line, i);
      if pClose = 0 then
      begin
        CmtContent := Copy(Line, i, n - i + 1);
        if ScoreCodeMarkers(CmtContent) >= 2 then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i, pClose - i);
      if (Result = 0) and (ScoreCodeMarkers(CmtContent) >= 2) then Result := i;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then
      begin
        CmtContent := Copy(Line, i, n - i + 1);
        if ScoreCodeMarkers(CmtContent) >= 2 then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i, pClose - i);
      if (Result = 0) and (ScoreCodeMarkers(CmtContent) >= 2) then Result := i;
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
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then
    begin
      // Inhalt des //-Kommentars
      CmtContent := Copy(Line, i + 2, MaxInt);
      if ScoreCodeMarkers(CmtContent) >= 2 then Result := i;
      Exit;
    end;
    if c = '{' then
    begin
      // {$...} sind Compiler-Direktiven, nicht Kommentare - Sonder-Skip.
      if (i + 1 <= n) and (Line[i + 1] = '$') then
      begin
        pClose := PosEx('}', Line, i + 2);
        if pClose = 0 then begin InBlockComm := True; Exit; end;
        i := pClose + 1; Continue;
      end;
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then
      begin
        InBlockComm := True;
        CmtContent := Copy(Line, i + 1, n - i);
        if ScoreCodeMarkers(CmtContent) >= 2 then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i + 1, pClose - i - 1);
      if (Result = 0) and (ScoreCodeMarkers(CmtContent) >= 2) then Result := i;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then
      begin
        InParenStarComm := True;
        CmtContent := Copy(Line, i + 2, n - i - 1);
        if ScoreCodeMarkers(CmtContent) >= 2 then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i + 2, pClose - i - 2);
      if (Result = 0) and (ScoreCodeMarkers(CmtContent) >= 2) then Result := i;
      i := pClose + 2; Continue;
    end;
    Inc(i);
  end;
end;

function IsPrevLineLineComment(Lines: TStringList; CurIdx: Integer): Boolean;
// True wenn die unmittelbar vorangehende Quelltext-Zeile mit '//' beginnt
// (nach Whitespace-Strip). Indikator fuer Multi-Line-Doc-Block - dort sind
// Pascal-Code-Beispiele typisch ('// Pattern: \n // procedure X; \n ...').
// Single-Line-Comments zwischen echtem Code (= isolierte //-Zeile) bleiben
// flag-faehig - das sind die echten commented-out-Kandidaten.
var
  S : string;
begin
  Result := False;
  if (CurIdx <= 0) or (CurIdx >= Lines.Count) then Exit;
  S := TrimLeft(Lines[CurIdx - 1]);
  Result := (Length(S) >= 2) and (S[1] = '/') and (S[2] = '/');
end;

function IsNextLineLineComment(Lines: TStringList; CurIdx: Integer): Boolean;
// Symmetrisch zu IsPrevLineLineComment: True wenn die naechste Zeile auch
// mit '//' beginnt. Faengt den Doc-Block-Start (erste //-Zeile, Vorzeile
// ist Code, naechste Zeile ist auch //) der von IsPrevLineLineComment nicht
// erkannt wird.
var
  S : string;
begin
  Result := False;
  if (CurIdx < 0) or (CurIdx >= Lines.Count - 1) then Exit;
  S := TrimLeft(Lines[CurIdx + 1]);
  Result := (Length(S) >= 2) and (S[1] = '/') and (S[2] = '/');
end;

function IsInlineComment(const Line: string; CommentCol: Integer): Boolean;
// True wenn vor CommentCol non-whitespace steht (Inline-Kommentar nach
// Code-Statement, z.B. 'fkXxx,  // Pascal-Keyword nicht...'). In Praxis
// fast immer Doku-Hint, nicht auskommentierter Code.
var
  i : Integer;
begin
  Result := False;
  if CommentCol <= 1 then Exit;
  for i := 1 to CommentCol - 1 do
    if not CharInSet(Line[i], [' ', #9]) then Exit(True);
end;

class procedure TCommentedOutCodeDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindCommentedOutCode(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      // FP-Schutz 1: Multi-Line-Doc-Block per '//' - Doc-Pattern mit
      // Pascal-Code-Beispielen, nicht commented-out Code. Echte
      // commented-out Zeilen stehen einzeln zwischen echtem Code.
      // Aktiv wenn die Zeile selbst mit '//' beginnt UND mind. eine
      // angrenzende Zeile auch '//' ist (Vorzeile ODER Folgezeile).
      // Look-Ahead deckt den Block-Start ab (vorher Code, danach '//').
      if (Col > 0) and Lines[i].TrimLeft.StartsWith('//') and
         (IsPrevLineLineComment(Lines, i) or
          IsNextLineLineComment(Lines, i)) then
        Continue;
      // FP-Schutz 2: Inline-Kommentar nach Code (Doku-Hint hinter Statement
      // wie 'fkXxx,  // Pascal-Keyword nicht...'). Echtes auskommentiertes
      // Code-Statement steht typischerweise allein auf seiner Zeile.
      // Pruefung nur fuer //-Kommentare; Block-Kommentare bleiben strikt.
      if (Col > 0) and Lines[i].Contains('//') and
         IsInlineComment(Lines[i], Col) then
        Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('Comment at column %d looks like commented-out code - ' +
               'delete or extract into a TODO if still relevant.', [Col]),
        fkCommentedOutCode));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
