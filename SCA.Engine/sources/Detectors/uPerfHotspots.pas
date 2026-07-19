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
  uFileTextCache, uDetectorUtils, uTypeResolver;

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
        // Position des Loop-Headers merken
        Stack.Push(i);
        Inc(i, WordLen);
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

function RhsIsProvablyNonString(const Code: string; AfterPlusPos: Integer): Boolean;
// Track A (Konzept_StrukturellePhase 2026-07-12): True wenn die RHS eines
// 'x := x + <RHS>' STRUKTURELL kein String sein KANN. Ein Delphi-String-'+'-
// Ausdruck enthaelt ausschliesslich String/Char-Operanden, verknuepft mit '+'.
// Jede Klausel ist damit ein BEWEIS fuer Nicht-String (keine Heuristik):
//   N1  RHS beginnt (nach Whitespace) mit '['      -> Set-/Array-Konstruktor
//   N2  Depth-0-Operand ist Zahl-Literal ('123' / '$1F')
//   N3  Depth-0-Operator aus {*, /, -, div, mod, shl, shr, xor}
//   N4  Depth-0-Operand ist numerischer Cast/Func 'NumFn(...)' OHNE trailing '.'
// MONOTON: fuegt nur eine Suppression hinzu -> Fund-Zahl kann nur sinken; ein
// echtes String-Concat (nur String/Char-Operanden + '+') erfuellt KEINE Klausel
// -> 0 TP-Verlust. Scan bis Statement-Ende (';'/EOL) auf Paren-/Bracket-Tiefe 0;
// String-'..' und Char-#..-Literale werden uebersprungen. Bracket-Tiefe wird
// mitgezaehlt, damit 's + x[0]' (Char-Zugriff = echtes Concat) NICHT als N2/N3 zaehlt.
const
  NUMFN : array[0..14] of string = (
    'integer', 'int64', 'cardinal', 'word', 'byte', 'length', 'ord', 'trunc',
    'round', 'ceil', 'floor', 'abs', 'high', 'low', 'sizeof');
var
  i, L, depth, st, j, k, d2 : Integer;
  c : Char;
  firstSig, isNumFn : Boolean;
  w, nf : string;
begin
  Result := False;
  L := Length(Code);
  i := AfterPlusPos;
  depth := 0;
  firstSig := False;
  while i <= L do
  begin
    c := Code[i];
    if (depth = 0) and ((c = ';') or (c = #10) or (c = #13)) then Break;
    if CharInSet(c, [' ', #9]) then begin Inc(i); Continue; end;
    if c = '''' then                              // String-Literal ueberspringen
    begin
      firstSig := True; Inc(i);
      while (i <= L) and (Code[i] <> '''') do Inc(i);
      Inc(i); Continue;
    end;
    if c = '#' then                               // Char-Literal #NN / #$hex
    begin
      firstSig := True; Inc(i);
      if (i <= L) and (Code[i] = '$') then Inc(i);
      while (i <= L) and CharInSet(Code[i], ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(i);
      Continue;
    end;
    if c = '(' then begin firstSig := True; Inc(depth); Inc(i); Continue; end;
    if c = ')' then begin if depth > 0 then Dec(depth); Inc(i); Continue; end;
    if c = '[' then
    begin
      if (depth = 0) and (not firstSig) then Exit(True);   // N1
      firstSig := True; Inc(depth); Inc(i); Continue;
    end;
    if c = ']' then begin if depth > 0 then Dec(depth); Inc(i); Continue; end;
    if depth = 0 then
    begin
      if CharInSet(c, ['0'..'9']) or (c = '$') then Exit(True);      // N2
      if CharInSet(c, ['*', '/', '-']) then Exit(True);             // N3 (Symbol)
      if CharInSet(c, ['a'..'z', 'A'..'Z', '_']) then
      begin
        st := i;
        while (i <= L) and CharInSet(Code[i], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
          Inc(i);
        w := LowerCase(Copy(Code, st, i - st));
        if (w = 'div') or (w = 'mod') or (w = 'shl') or (w = 'shr') or (w = 'xor') then
          Exit(True);                                                // N3 (Wort)
        j := i;                                    // N4: NumFn '(' ... ')' ohne trailing '.'
        while (j <= L) and CharInSet(Code[j], [' ', #9]) do Inc(j);
        if (j <= L) and (Code[j] = '(') then
        begin
          isNumFn := False;
          // '.'-Praefix -> Member-Call (obj.High(x)), NICHT die Builtin-NumFn ->
          // kein N4 (koennte String liefern).
          if (st = 1) or (Code[st - 1] <> '.') then
            for nf in NUMFN do if w = nf then begin isNumFn := True; Break; end;
          if isNumFn then
          begin
            d2 := 1; k := j + 1;
            while (k <= L) and (d2 > 0) do
            begin
              if Code[k] = '''' then            // String-Literal im Arg skippen
              begin                             // (sonst faelscht '(' die Paren-Zaehlung)
                Inc(k);
                while (k <= L) and (Code[k] <> '''') do Inc(k);
              end
              else if Code[k] = '(' then Inc(d2)
              else if Code[k] = ')' then Dec(d2);
              Inc(k);
            end;
            while (k <= L) and CharInSet(Code[k], [' ', #9]) do Inc(k);
            if (k > L) or (Code[k] <> '.') then Exit(True);          // N4
          end;
        end;
        firstSig := True;
        Continue;
      end;
      firstSig := True;
    end;
    Inc(i);
  end;
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
  TR       : TTypeResolver;   // Welle 1: additive AST-Typ-Aufloesung (SCA110-Opt-in)

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
  TR := nil;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    FindLoopRanges(Code, Ranges);
    if Length(Ranges) = 0 then Exit;
    // Welle 1 (Core-Detektoren-Architektur): scope-genaue Typ-Aufloesung aus dem
    // AST. Ergaenzt die lexikalische LhsDeclaredNumeric additiv (Union) - faengt
    // numerische Akkumulatoren, die die Regex durch Scope-/Feld-/Param-Blindheit
    // verpasst. Nur nach dem Ranges-Check gebaut (kein Aufwand ohne Schleifen).
    TR := TTypeResolver.Create(UnitNode);

    // 1) String-Concat in Loop:  <var> := <var> + <expr>
    //    Wortgrenzen, Variable beidseitig identisch (case-insensitiv).
    Matches := CachedReConcat.Matches(Code);
    for M in Matches do
      if PosInRanges(M.Index, Ranges)
         and not LhsDeclaredNumeric(Code, M.Groups[1].Value, M.Index)
         and not TR.IsNumericLhs(M.Groups[1].Value,
                   TDetectorUtils.LineForPos(LineFor, M.Index))
         // Track A (2026-07-12): RHS strukturell beweisbar kein String -> kein
         // O(n^2)-String-Concat, sondern numerischer/Set-Akkumulator (monotoner
         // Suppress-Konjunkt, 0 TP-Verlust). M.Index+M.Length = Pos nach dem '+'.
         and not RhsIsProvablyNonString(Code, M.Index + M.Length) then
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
    TR.Free;   // nil-safe (TObject.Free); nil bei Ranges=0-Exit
    ReleaseLines(Lines, Cached);
  end;
end;

end.
