unit uPerfHotspots;

// Performance-Hotspot-Detektor-Familie (SCA110-112).
//
// Drei real-world Delphi-Performance-Bugs die der Compiler nicht warnt:
//
//   * fkStringConcatInLoop   - s := s + x in for/while/repeat
//   * fkParamByNameInLoop    - Query.ParamByName('x') Hot-Path
//   * fkFieldByNameInLoop    - DataSet.FieldByName('x') Hot-Path
//
// Erkennung lexikalisch (uFileTextCache + StripFileComments). Lexer
// erkennt Loop-Bloecke per Keyword-Match + Tiefe-Tracking (for/while/
// repeat..end). Innerhalb jedes Loop-Bodies werden die Pattern-Matches
// gesucht.
//
// Lexikalisch (kein AST) weil:
//   * Loop-Body-Tracking ist im AST aufwendig (nkFor + nkWhile + nkRepeat
//     muessen separat behandelt werden plus Inner-Body-Walk)
//   * Pattern-Match ist Regex-trivial
//   * False-Positive-Rate bei Strings/Comments durch StripFileComments
//     vorgefiltert
//
// Suppression: per-Zeile `// noinspection StringConcatInLoop` etc. greift
// ueber uSuppression.ApplyToFindings am Ende des Analyse-Laufs.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TPerfHotspotsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NestedRoutine, RedundantBoolean, RedundantJump, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

var
  // Lazy-Cache fuer die drei Module-konstanten Regex-Patterns. Spart 3x
  // TRegEx.Create pro File pro Scan (Round-9 Code-Review / Perf).
  CachedReConcat : TRegEx;
  CachedReParam  : TRegEx;
  CachedReField  : TRegEx;
  CachedReInit   : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReConcat := TRegEx.Create('(?i)\b([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*\1\s*\+');
  CachedReParam  := TRegEx.Create('(?i)\b\w+\.ParamByName\s*\(');
  CachedReField  := TRegEx.Create('(?i)\b\w+\.FieldByName\s*\(');
  CachedReInit   := True;
end;

function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      InStr := False;
      j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end
          else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free; Buf.Free;
  end;
end;

function IsIdent(c: Char): Boolean; inline;
begin
  Result := CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Findet Loop-Bloecke (for/while/repeat..end-of-block) und liefert ihre
// [StartPos..EndPos]-Bereiche. Tiefe-getrackt damit verschachtelte Loops
// einen Body innerhalb des aeusseren Body matchen koennen.
type
  TLoopRange = record
    StartPos : Integer;
    EndPos   : Integer;
  end;

procedure FindLoopRanges(const Code: string; out Ranges: TArray<TLoopRange>);
var
  L         : string;
  i, n      : Integer;
  Stack     : TStack<Integer>;
  RList     : TList<TLoopRange>;
  R         : TLoopRange;
  KeywordEnd: Integer;
  WordLen   : Integer;
  HdrLen    : Integer;
  DoPos     : Integer;
  TokPos    : Integer;

  function MatchKeyword(const Kw: string; AtPos: Integer): Boolean;
  begin
    Result := False;
    WordLen := Length(Kw);
    // n (outer) wird im FindLoopRanges-Body initialisiert bevor
    // MatchKeyword aufgerufen wird; FP des Nested-Closure-Pattern.
    if AtPos + WordLen - 1 > n then Exit;
    if AtPos > 1 then
      if IsIdent(L[AtPos - 1]) then Exit;
    if SameText(Copy(L, AtPos, WordLen), Kw) and
       ((AtPos + WordLen > n) or not IsIdent(L[AtPos + WordLen])) then
      Result := True;
  end;

  function FindHeaderDoPos(FromPos: Integer): Integer;
  // Sucht das Header-abschliessende 'do' eines for/while-Kopfes ab FromPos.
  // Ueberspringt String-Literale und zaehlt ()/[]-Tiefe (ein 'do' in einem
  // String oder in Klammern soll nicht faelschlich matchen). Stoppt defensiv
  // an ';' auf Tiefe 0 - das kommt in einem gueltigen Loop-Header nie vor.
  var
    p, depth : Integer;
    inStr    : Boolean;
  begin
    Result := 0;
    p := FromPos;
    depth := 0;
    inStr := False;
    while p <= n do
    begin
      if inStr then
      begin
        if L[p] = '''' then inStr := False;
        Inc(p); Continue;
      end;
      case L[p] of
        '''': begin inStr := True; Inc(p); Continue; end;
        '(', '[': begin Inc(depth); Inc(p); Continue; end;
        ')', ']': begin if depth > 0 then Dec(depth); Inc(p); Continue; end;
      end;
      if depth = 0 then
      begin
        if L[p] = ';' then Exit(0);
        if MatchKeyword('do', p) then Exit(p);
      end;
      Inc(p);
    end;
  end;

  function FirstSignificantPos(FromPos: Integer): Integer;
  // Erste Nicht-Whitespace-Position ab FromPos.
  var
    p : Integer;
  begin
    p := FromPos;
    while (p <= n) and CharInSet(L[p], [' ', #9, #10, #13]) do Inc(p);
    Result := p;
  end;

  function FindStmtEndPos(FromPos: Integer): Integer;
  // Ende einer Einzelanweisung: erste ';' auf Klammertiefe 0 ab FromPos
  // (String-Literale uebersprungen). Fallback = Dateiende.
  var
    p, depth : Integer;
    inStr    : Boolean;
  begin
    Result := n;
    p := FromPos;
    depth := 0;
    inStr := False;
    while p <= n do
    begin
      if inStr then
      begin
        if L[p] = '''' then inStr := False;
        Inc(p); Continue;
      end;
      case L[p] of
        '''': begin inStr := True; Inc(p); Continue; end;
        '(', '[': Inc(depth);
        ')', ']': if depth > 0 then Dec(depth);
        ';': if depth = 0 then Exit(p);
      end;
      Inc(p);
    end;
  end;

begin
  L := LowerCase(Code);
  n := Length(L);
  Stack := TStack<Integer>.Create;
  RList := TList<TLoopRange>.Create;
  try
    i := 1;
    while i <= n do
    begin
      // 'for X to/downto Y do' oder 'while ... do' -> Body beginnt erst
      // nach dem ersten 'begin' (oder direkt am Statement bei Single-
      // Stmt-Body). Wir tracken die Loop-Header-Position und matchen
      // dann die Body-Begin-End-Klammer.
      if MatchKeyword('for', i) or MatchKeyword('while', i) then
      begin
        // Body-Form bestimmen: begin-Block (Stack-Mechanismus wie bisher)
        // oder Einzelanweisung 'for/while ... do stmt;'. Frueher wurde IMMER
        // gepusht - bei Einzelanweisungs-Loops blieb der Header liegen und
        // verschluckte spaeter ein unabhaengiges 'begin' als vermeintlichen
        // Loop-Body -> Concats in Straight-Line-Code wurden faelschlich als
        // "in Schleife" gemeldet (FP-Klasse not-in-loop, SCA110-Audit).
        HdrLen := WordLen;   // Keyword-Laenge sichern (Peek unten ueberschreibt WordLen)
        DoPos := FindHeaderDoPos(i + HdrLen);
        if DoPos > 0 then
        begin
          TokPos := FirstSignificantPos(DoPos + 2);   // 'do' ist 2 Zeichen
          if (TokPos <= n) and MatchKeyword('begin', TokPos) then
            // begin-Body: bestehender begin-Zweig erzeugt die Range beim
            // Weiterscannen (Header-Position auf Stack).
            Stack.Push(i)
          else
          begin
            // Einzelanweisungs-Body -> Range exakt bis zum ersten ';' auf
            // Klammertiefe 0. KEIN Stack-Push, damit der Header nicht
            // liegenbleibt und nicht in Folgecode ausblutet.
            R.StartPos := TokPos;
            R.EndPos   := FindStmtEndPos(TokPos);
            if R.EndPos >= R.StartPos then
              RList.Add(R);
          end;
        end;
        Inc(i, HdrLen);
        Continue;
      end;
      if MatchKeyword('repeat', i) then
      begin
        // repeat-Body startet direkt hinter 'repeat'.
        R.StartPos := i + 6;
        // Suche das matchende 'until' - hier vereinfacht: erstes 'until'
        // auf gleicher Tiefe. Fuer MVP geht ein simpler PosEx-Match.
        KeywordEnd := PosEx('until', L, R.StartPos);
        if KeywordEnd > 0 then
        begin
          R.EndPos := KeywordEnd - 1;
          RList.Add(R);
        end;
        Inc(i, 6);
        Continue;
      end;
      // begin matched einen Loop-Header? Wir nehmen vereinfachend an:
      // wenn der Stack einen for/while-Header hat und wir auf 'begin'
      // treffen ohne ein vorheriges 'begin' fuer denselben Header
      // angefangen zu haben, dann ist DAS der Loop-Body.
      if MatchKeyword('begin', i) and (Stack.Count > 0) then
      begin
        var BodyStart := i + 5;
        var EndPos    := PosEx('end', L, BodyStart);
        if (EndPos > 0) and
           ((EndPos + 3 > n) or not IsIdent(L[EndPos + 3])) then
        begin
          R.StartPos := BodyStart;
          R.EndPos   := EndPos - 1;
          RList.Add(R);
          Stack.Pop;
          i := EndPos + 3;
          Continue;
        end;
      end;
      Inc(i);
    end;
    Ranges := RList.ToArray;
  finally
    Stack.Free; RList.Free;
  end;
end;

function PosInRanges(Pos: Integer; const Ranges: TArray<TLoopRange>): Boolean;
var
  R : TLoopRange;
begin
  Result := False;
  for R in Ranges do
    if (Pos >= R.StartPos) and (Pos <= R.EndPos) then Exit(True);
end;

function LhsDeclaredNumeric(const Code, VarName: string;
  BeforePos: Integer): Boolean;
// FP-Gate (Real-World-FP-Audit 2026-07-10): der Concat-Regex 'x := x + ...'
// matcht JEDEN Akkumulator - auch numerische ('j := j + 3', 'YHeader2 :=
// YHeader2 + Pad', 'ucs4 := ucs4 + n'). Nur STRING-Konkatenation ist der
// O(n^2)-Bug. Wir loesen den deklarierten Typ von VarName aus der
// naechstliegenden Deklaration VOR der Nutzung (var/param/Feld
// 'name[, more]: Typ') auf und unterdruecken bei numerischem Typ. Nicht
// aufloesbar oder String-Typ -> weiter melden (kein TP-Verlust).
const
  NUMTYPES : array[0..30] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'single',
    'double', 'extended', 'currency', 'comp', 'real', 'real48', 'dword',
    'ptrint', 'ptruint', 'uint32', 'int32', 'uint16', 'int16', 'uint8',
    'int8', 'tdatetime', 'tdate', 'ttime');
var
  Before, TypeLow, T : string;
  RE : TRegEx;
  MC : TMatchCollection;
begin
  Result := False;
  if (VarName = '') or (BeforePos <= 1) then Exit;
  Before := Copy(Code, 1, BeforePos);   // Deklaration steht VOR der Nutzung
  RE := TRegEx.Create('(?i)\b' + VarName +
        '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*([A-Za-z_][A-Za-z0-9_]*)');
  MC := RE.Matches(Before);
  if MC.Count = 0 then Exit;
  // naechstliegende (= letzte vor der Nutzung) Deklaration.
  TypeLow := LowerCase(MC[MC.Count - 1].Groups[1].Value);
  for T in NUMTYPES do
    if TypeLow = T then Exit(True);
end;

function RhsFirstOperandIsBracket(const Code: string; AfterPlusPos: Integer): Boolean;
// FP-Gate (clean-lexical, SCA110-FP-Audit 2026-07-11): 'x := x + [...]' ist
// Set-Union bzw. Array-Concat (`result := result + [TAuthType.Plain]`,
// `CharSet := CharSet + [C]`), KEIN String-O(n^2)-Concat. Ein '+' unmittelbar
// gefolgt von '[' kann in gueltigem Pascal nur ein Set-/Array-Konstruktor sein
// (ein Array-Index haengt an einem Bezeichner, nie direkt hinter '+'). String-
// Concat hat dort nie ein '[' -> kein TP-Verlust. AfterPlusPos = erstes Zeichen
// HINTER dem '+' des Concat-Matches.
var
  p, len : Integer;
begin
  Result := False;
  len := Length(Code);
  p := AfterPlusPos;
  while (p <= len) and CharInSet(Code[p], [' ', #9, #10, #13]) do Inc(p);
  Result := (p <= len) and (Code[p] = '[');
end;

class procedure TPerfHotspotsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  Ranges   : TArray<TLoopRange>;
  M        : TMatch;
  Matches  : TMatchCollection;
  LineNo   : Integer;
  F        : TLeakFinding;

  procedure Emit(K: TFindingKind; const Detail: string; AtPos: Integer);
  begin
    LineNo := TDetectorUtils.LineForPos(LineFor, AtPos);
    if LineNo <= 0 then LineNo := 1;
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(LineNo);
    F.MissingVar := Detail;
    F.SetKind(K);
    Results.Add(F);
  end;

begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    FindLoopRanges(Code, Ranges);
    if Length(Ranges) = 0 then Exit;

    // 1) String-Concat in Loop:  <var> := <var> + <expr>
    //    Wortgrenzen, Variable beidseitig identisch (case-insensitiv).
    Matches := CachedReConcat.Matches(Code);
    for M in Matches do
      if PosInRanges(M.Index, Ranges)
         and not LhsDeclaredNumeric(Code, M.Groups[1].Value, M.Index)
         and not RhsFirstOperandIsBracket(Code, M.Index + M.Length) then
        Emit(fkStringConcatInLoop,
          Format('String-Concat ''%s := %s + ...'' in loop body - ' +
                 'O(n^2) reallocations. Prefer TStringBuilder.Append or ' +
                 'TStringList collection + .Text afterwards.',
                 [M.Groups[1].Value, M.Groups[1].Value]),
          M.Index);

    // 2) ParamByName in Loop:   <obj>.ParamByName('...')
    Matches := CachedReParam.Matches(Code);
    for M in Matches do
      if PosInRanges(M.Index, Ranges) then
        Emit(fkParamByNameInLoop,
          'ParamByName(...) call inside loop - linear lookup per call. ' +
          'Cache the TParam reference outside the loop or use Params[Index] ' +
          'with a known position.',
          M.Index);

    // 3) FieldByName in Loop:   <obj>.FieldByName('...')
    Matches := CachedReField.Matches(Code);
    for M in Matches do
      if PosInRanges(M.Index, Ranges) then
        Emit(fkFieldByNameInLoop,
          'FieldByName(...) call inside loop - linear lookup per call. ' +
          'Cache the TField reference once before the loop and reuse it.',
          M.Index);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
