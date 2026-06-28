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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TCommentedOutCodeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
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

// Wortgrenz-Match (case-insensitive) eines Keywords im (lowercase) Inhalt.
function ContainsWordCI(const Lower, W: string): Boolean;
var k, lenW, lenS : Integer;
begin
  Result := False;
  lenW := Length(W); lenS := Length(Lower);
  if lenW = 0 then Exit;
  k := 1;
  while k <= lenS - lenW + 1 do
  begin
    if Copy(Lower, k, lenW) = W then
      if ((k = 1) or not IsIdentChar(Lower[k - 1])) and
         ((k + lenW > lenS) or not IsIdentChar(Lower[k + lenW])) then
        Exit(True);
    Inc(k);
  end;
end;

// True wenn der Inhalt einen UNZWEIDEUTIGEN Pascal-Marker traegt, der in
// englischer Prosa praktisch nie vorkommt: ':=', Inhalt endet mit ';', oder
// 'begin'/'procedure'/'function' als Wort. Die schwachen Keywords
// (if/then/for/while/end) sind prosa-haeufig und reichen ALLEIN nicht -
// sonst flaggt z.B. "if the value is nil then return" reine Prosa als Code
// (dominante SCA070-FP-Klasse, Real-World 2026-06-28).
function HasStrongCodeMarker(const Raw: string): Boolean;
var Content, Lower, Trimmed : string;
begin
  Content := StripBacktickCodeSpans(Raw);
  Lower   := LowerCase(Content);
  Trimmed := Trim(Content);
  Result := ((Trimmed <> '') and (Trimmed[Length(Trimmed)] = ';'))
            or (Pos(':=', Content) > 0)
            or ContainsWordCI(Lower, 'begin')
            or ContainsWordCI(Lower, 'procedure')
            or ContainsWordCI(Lower, 'function');
end;

// Zaehlt code-typische Marker im Kommentar-Inhalt (starke + schwache).
function ScoreCodeMarkers(const Raw: string): Integer;
var
  Content : string;
  Lower   : string;
  Trimmed : string;
begin
  Result := 0;
  // Backtick-Code-Spans entfernen BEVOR die Marker gezaehlt werden.
  Content := StripBacktickCodeSpans(Raw);
  Lower := LowerCase(Content);
  Trimmed := Trim(Content);
  if (Trimmed <> '') and (Trimmed[Length(Trimmed)] = ';') then Inc(Result);
  if Pos(':=', Content) > 0 then Inc(Result);
  if ContainsWordCI(Lower, 'begin')     then Inc(Result);
  if ContainsWordCI(Lower, 'end')       then Inc(Result);
  if ContainsWordCI(Lower, 'procedure') then Inc(Result);
  if ContainsWordCI(Lower, 'function')  then Inc(Result);
  if ContainsWordCI(Lower, 'if')        then Inc(Result);
  if ContainsWordCI(Lower, 'then')      then Inc(Result);
  if ContainsWordCI(Lower, 'for')       then Inc(Result);
  if ContainsWordCI(Lower, 'while')     then Inc(Result);
end;

// True wenn der Kommentar-Inhalt nach Code aussieht: >=2 Marker UND mind. ein
// STARKER (Pascal-spezifischer) Marker. Der Strong-Zwang killt die dominante
// FP-Klasse (englische Prosa mit if/then/for/while/end). Echter commented-out
// Code hat fast immer ':=', ';' oder begin/procedure/function.
function LooksLikeCommentedCode(const Raw: string): Boolean;
begin
  Result := (ScoreCodeMarkers(Raw) >= 2) and HasStrongCodeMarker(Raw);
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
        if LooksLikeCommentedCode(CmtContent) then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i, pClose - i);
      if (Result = 0) and (LooksLikeCommentedCode(CmtContent)) then Result := i;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then
      begin
        CmtContent := Copy(Line, i, n - i + 1);
        if LooksLikeCommentedCode(CmtContent) then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i, pClose - i);
      if (Result = 0) and (LooksLikeCommentedCode(CmtContent)) then Result := i;
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
      if LooksLikeCommentedCode(CmtContent) then Result := i;
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
        if LooksLikeCommentedCode(CmtContent) then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i + 1, pClose - i - 1);
      if (Result = 0) and (LooksLikeCommentedCode(CmtContent)) then Result := i;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then
      begin
        InParenStarComm := True;
        CmtContent := Copy(Line, i + 2, n - i - 1);
        if LooksLikeCommentedCode(CmtContent) then Result := i;
        Exit;
      end;
      CmtContent := Copy(Line, i + 2, pClose - i - 2);
      if (Result = 0) and (LooksLikeCommentedCode(CmtContent)) then Result := i;
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
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
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
