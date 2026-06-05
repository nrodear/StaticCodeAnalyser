unit uUninitVar;

// Detector: SCA166 fkUninitVar — lokale Variable wird auf einem Pfad
// gelesen bevor sie auf demselben Pfad geschrieben wurde.
//
// Konservatives MVP nach Konzept_SCA166_UninitVar.md (§5+§7):
//   * Single-Method-Scope (kein Cross-Procedure-Flow).
//   * Sequentielle Source-Line-Ordnung pro Methode.
//   * Writes erkannt aus nkAssign (LHS), nkForStmt (Loop-Var) und
//     nkCall mit Name in WRITE_ALLOWLIST (Read/ReadLn/FillChar/Move/
//     Initialize/New/GetMem/ZeroMemory).
//   * Reads = jede andere Erwaehnung der Variable im Body (Wort-
//     grenzen-Match analog uUnusedLocal).
//   * Klassifikation:
//       - Variable referenziert + KEIN Write -> fcHigh
//       - First-Read-Line < First-Write-Line  -> fcMedium
//   * Skip-Regeln (FP-Guards §5.E):
//       - Name beginnt mit '_'
//       - Managed types (string, dynamic array, interface) ohne
//         expliziten Opt-In
//       - Method ist asm-Block
//       - Method-Header passt nicht zu LocalVar-Decl (Parser-Artefakt
//         analog uUnusedLocal.LooksLikeRealLocalVar)
//       - Method ueberschreitet Hard-Caps (MaxLocalVars, MaxStatements)
//
// Phase-2-Erweiterung (siehe Konzept §11): Sibling-Write-Check fuer
// if-then-else mit beidseitigem Write. Phase-3 (CFG) und Phase-4
// (Symboltabelle) sind im Konzept dokumentiert.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUninitVarDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache, uDetectorUtils;

// Hard-Caps werden zur Laufzeit aus uSCAConsts.DetectorMaxLocalVars /
// DetectorMaxChildrenRecursive gelesen (konfigurierbar via analyser.ini
// [Detectors]). Default 200 / 5000.

const
  // RTL-Routinen die ihren Argumenten Werte zuweisen (out/var). Wenn
  // einer dieser Calls eine Variable als Arg hat, gilt das als Write.
  WRITE_ALLOWLIST : array[0..11] of string = (
    'read', 'readln', 'blockread',
    'fillchar', 'move', 'zeromemory',
    'initialize', 'new', 'getmem',
    'setlength', 'setstring',
    'tryfromstring'         // TBytes.TryFromString und Verwandte
  );

  // Read-Only-Routinen die ihre Args garantiert NICHT schreiben.
  // Wenn ein Call in dieser Liste eine Variable als Arg hat, gilt das
  // als Read (= Variable muss VORHER assigned sein).
  // Default fuer alle ANDEREN Calls (z.B. 'Helper.Init(X)') ist
  // pessimistic-Write - akzeptiert FNs zugunsten weniger FPs.
  READ_ALLOWLIST : array[0..57] of string = (
    // --- Output ---
    'write', 'writeln', 'showmessage', 'showmessagefmt',
    'outputdebugstring', 'outputdebugstringa', 'outputdebugstringw',
    // --- Typ-Konvertierung / Inspektion (gibt nur einen Wert zurueck) ---
    'inttostr', 'inttohex', 'floattostr', 'datetostr', 'timetostr',
    'datetimetostr', 'formatfloat', 'formatdatetime', 'format',
    'inttoidentstr', 'identtoint', 'strtoint', 'strtointdef',
    'strtofloat', 'strtofloatdef', 'strtodatetime', 'strtodate',
    // --- String/Array-Inspektion ---
    'length', 'sizeof', 'high', 'low', 'ord', 'chr',
    'copy', 'pos', 'posex', 'trim', 'trimleft', 'trimright',
    'uppercase', 'lowercase', 'sametext', 'comparetext', 'comparestr',
    // --- Boolean-Inspektion ---
    'assigned', 'isdebuggerpresent',
    // --- Windows-API Read-Only (Phase 2.5) ---
    'sleep', 'sleepex', 'gettickcount', 'gettickcount64',
    'getlasterror', 'getcurrentthreadid', 'getcurrentprocessid',
    'waitforsingleobject', 'waitformultipleobjects',
    'closehandle', 'freelibrary',
    'releasedc', 'deletedc', 'deleteobject', 'deletecriticalsection'
  );

  // Managed types die Pascal auto-initialisiert. Wir flaggen sie nur,
  // wenn der User explizit `UninitVarFlagManagedTypes` aktiviert.
  MANAGED_TYPE_PREFIXES : array[0..5] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring',
    'tarray<',              // TArray<T> generic dynamic array
    'iinterface'            // sehr defensive Annaehrung an ALLE Interfaces
  );

  // Methoden-Body wird als asm-Block gekennzeichnet wenn das TypeRef
  // des nkMethod-Knotens einen ';asm'-Marker enthaelt (analog dem
  // virtual/override-Pattern in uVisibilityCheck).
  ASM_MARKER = ';asm';

type
  TVarInfo = record
    Name             : string;
    NameLow          : string;
    TypeLow          : string;
    DeclLine         : Integer;
    FirstWriteLine   : Integer;     // 0 = nie geschrieben
    FirstReadLine    : Integer;     // 0 = nie gelesen (= Variable ist UnusedLocal-Domain)
    RefCount         : Integer;     // Anzahl Wortgrenzen-Matches im Body inkl. Decl
    IsManaged        : Boolean;
  end;
  PVarInfo = ^TVarInfo;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

type
  // State fuer Zeilen-uebergreifende Block-Kommentar-Verfolgung.
  // String-Literale ('...') koennen in klassischem Delphi nicht ueber
  // Zeilengrenzen hinweg gehen - daher kein InString-State.
  // Delphi-12-Multi-Line-Strings ('''...''') werden bewusst NICHT
  // getrackt - rare Edge-Case, FN akzeptabel.
  TLineStripState = record
    InBrace : Boolean;   // True wenn vorige Zeile mit offenem '{' endete
    InParen : Boolean;   // True wenn vorige Zeile mit offenem '(*' endete
  end;

function StripLineEx(const Line: string; var State: TLineStripState): string;
// Stripper mit Zeilen-uebergreifendem State - State.InBrace/InParen
// werden VOR der Zeile aus dem Caller-State gelesen und NACH der Zeile
// zurueckgeschrieben. So funktionieren auch Multi-Line-Comments wie
//   { Foo bar
//     baz }
// als Stripping ueber alle drei Zeilen.
var
  Buf : array of Char;
  i, L : Integer;
  InString : Boolean;
  C, Next : Char;
begin
  L := Length(Line);
  if L = 0 then Exit('');
  SetLength(Buf, L);
  InString := False;       // Strings koennen sich nicht ueber Zeilen ziehen
  i := 1;
  while i <= L do
  begin
    C := Line[i];
    if i < L then Next := Line[i + 1] else Next := #0;

    if State.InBrace then
    begin
      Buf[i - 1] := ' ';
      if C = '}' then State.InBrace := False;
      Inc(i);
    end
    else if State.InParen then
    begin
      Buf[i - 1] := ' ';
      if (C = '*') and (Next = ')') then
      begin
        Buf[i] := ' ';
        Inc(i, 2);
        State.InParen := False;
      end
      else
        Inc(i);
    end
    else if InString then
    begin
      Buf[i - 1] := ' ';
      if C = '''' then
      begin
        if Next = '''' then    // '' Escape innerhalb String
        begin
          Buf[i] := ' ';
          Inc(i, 2);
        end
        else
        begin
          InString := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
    end
    else
    begin
      if (C = '/') and (Next = '/') then
      begin
        // Line-Comment: Rest der Zeile zu Spaces.
        while i <= L do
        begin
          Buf[i - 1] := ' ';
          Inc(i);
        end;
        Break;
      end
      else if C = '{' then
      begin
        Buf[i - 1] := ' ';
        State.InBrace := True;
        Inc(i);
      end
      else if (C = '(') and (Next = '*') then
      begin
        Buf[i - 1] := ' ';
        Buf[i]     := ' ';
        Inc(i, 2);
        State.InParen := True;
      end
      else if C = '''' then
      begin
        Buf[i - 1] := ' ';
        InString := True;
        Inc(i);
      end
      else
      begin
        Buf[i - 1] := C;
        Inc(i);
      end;
    end;
  end;
  SetString(Result, PChar(Buf), L);
end;

function StripCommentsAndStrings(const Line: string): string;
// Stateless single-line convenience-Wrapper (Alt-API).
// Multi-Line-Block-Comments werden in dieser Variante NICHT erkannt.
// Verwendung nur fuer Stellen ohne Zeilen-iterierenden Scan.
var
  State : TLineStripState;
begin
  State.InBrace := False;
  State.InParen := False;
  Result := StripLineEx(Line, State);
end;

function CountWholeWordOccurrences(const NeedleLow, HaystackLow: string;
  out FirstMatchPos: Integer): Integer;
// Wortgrenz-Match analog uUnusedLocal. FirstMatchPos = 1-basierte
// Position des ersten Matches (0 wenn keiner). Result = Anzahl Matches.
var
  P, NL, HL : Integer;
  Before, After : Char;
begin
  Result := 0;
  FirstMatchPos := 0;
  NL := Length(NeedleLow);
  HL := Length(HaystackLow);
  if (NL = 0) or (HL < NL) then Exit;

  P := 1;
  while True do
  begin
    P := PosEx(NeedleLow, HaystackLow, P);
    if P = 0 then Break;
    Before := #0;
    if P > 1 then Before := HaystackLow[P - 1];
    After := #0;
    if P + NL - 1 < HL then After := HaystackLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then
    begin
      Inc(Result);
      if FirstMatchPos = 0 then FirstMatchPos := P;
    end;
    P := P + NL;
  end;
end;

function IsManagedType(const TypeRef: string): Boolean;
var
  T : string;
  Prefix : string;
begin
  Result := False;
  T := LowerCase(Trim(TypeRef));
  if T = '' then Exit;
  for Prefix in MANAGED_TYPE_PREFIXES do
    if T.StartsWith(Prefix) then Exit(True);
end;

function IsAsmMethod(MethodNode: TAstNode): Boolean;
begin
  Result := (MethodNode <> nil)
        and (Pos(ASM_MARKER, LowerCase(MethodNode.TypeRef)) > 0);
end;

type
  TLineRange = record
    StartLine, EndLine : Integer;
  end;

// Note: AST-basierte Nested-Method-Detection wurde im Block-1-Cleanup
// entfernt — der Parser entfernt den Outer-MethodNode bei
// 'Headless-Method'-Pattern (ParseMethodImpl), nested-Procedures landen
// NICHT als nkMethod-Children. Audit zeigte -4 Findings Effekt.
// Phase 2.6 (CollectNestedMethodRangesViaSource unten) ist die effektive
// Alternative.

function IsLineInRanges(Line: Integer;
  const Ranges: TList<TLineRange>): Boolean;
var
  i : Integer;
begin
  Result := False;
  if (Ranges = nil) or (Line <= 0) then Exit;
  for i := 0 to Ranges.Count - 1 do
    if (Line >= Ranges[i].StartLine) and (Line <= Ranges[i].EndLine) then
      Exit(True);
end;

procedure CollectNestedMethodRangesViaSource(Lines: TStringList;
  MethodStartLine, MethodEndLine: Integer;
  Ranges: TList<TLineRange>);
// Phase 2.6 - source-line-based Nested-Method-Detection.
//
// Hintergrund: Phase 2.4 (AST-basiert) wirkt nur wenn der Parser
// nested-Procedures als nkMethod-Children unter dem Outer-MethodNode
// ablegt. ParseMethodImpl entfernt aber bei 'Headless-Method'-Pattern
// den Outer-Knoten - nested-Pattern wird damit AST-seitig verloren.
//
// Source-basierter Workaround: scanne Lines im Range
// [MethodStartLine..MethodEndLine] nach Pattern
//   ^\s{2,}(procedure|function|constructor|destructor)\s+\w+
// (nested = mindestens 2 Leading-Spaces, distinct vom 0-indent Outer-
// Header). Pro nested-Header: count begin/end-Paare bis matching
// outer 'end;', dann Range eintragen.
var
  i, EndLine, Depth : Integer;
  L, LTrim : string;
  StartCol : Integer;
  Started : Boolean;
  R : TLineRange;

  function LineLooksLikeNestedHeader(const RawLine: string;
    out LeadingSpaces: Integer): Boolean;
  var
    j : Integer;
    Low : string;
  begin
    Result := False;
    LeadingSpaces := 0;
    for j := 1 to Length(RawLine) do
      if RawLine[j] = ' ' then Inc(LeadingSpaces)
      else if RawLine[j] = #9 then Inc(LeadingSpaces, 2)
      else Break;
    if LeadingSpaces < 2 then Exit;
    Low := LowerCase(TrimLeft(RawLine));
    Result := Low.StartsWith('procedure ')   or Low.StartsWith('procedure(') or
              Low.StartsWith('function ')    or Low.StartsWith('function(')  or
              Low.StartsWith('constructor ') or Low.StartsWith('destructor ');
  end;

begin
  if (Lines = nil) or (Ranges = nil) then Exit;
  if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;

  i := MethodStartLine - 1;
  while (i < Lines.Count) and (i < MethodEndLine) do
  begin
    L := Lines[i];
    if LineLooksLikeNestedHeader(L, StartCol) then
    begin
      R.StartLine := i + 1;
      // Suche begin/end-balanced bis matching 'end;' auf dem Sub-Indent
      Depth := 0;
      Started := False;
      EndLine := i + 1;
      while (i < Lines.Count) and (i < MethodEndLine) do
      begin
        LTrim := LowerCase(TrimLeft(Lines[i]));
        // begin- und end-Tokens zaehlen (Wortgrenz-Match einfach reicht)
        if LTrim.StartsWith('begin') or (Pos(' begin ', ' ' + LTrim + ' ') > 0) then
        begin
          Inc(Depth);
          Started := True;
        end;
        // 'end' kommt am Zeilenanfang oder als 'end;' am Ende
        if LTrim.StartsWith('end;') or LTrim.StartsWith('end ')
           or (LTrim = 'end') then
        begin
          Dec(Depth);
          if Started and (Depth <= 0) then
          begin
            EndLine := i + 1;
            Break;
          end;
        end;
        Inc(i);
      end;
      R.EndLine := EndLine;
      Ranges.Add(R);
    end;
    Inc(i);
  end;
end;

procedure SinglePassCollectByKind(Root: TAstNode;
  Assigns, Calls, Fors, Ifs, Whiles, Cases: TList<TAstNode>);
// P1: Statt 8x MethodNode.FindAll(...) ueber den AST zu walken,
// einen einzigen DFS-Walk der Knoten in 6 Buckets verteilt. Spart
// ~7/8 der Tree-Walks pro Methode.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      case Cur.Kind of
        nkAssign:    if Assigns <> nil then Assigns.Add(Cur);
        nkCall:      if Calls   <> nil then Calls.Add(Cur);
        nkForStmt:   if Fors    <> nil then Fors.Add(Cur);
        nkIfStmt:    if Ifs     <> nil then Ifs.Add(Cur);
        nkWhileStmt: if Whiles  <> nil then Whiles.Add(Cur);
        nkCaseStmt:  if Cases   <> nil then Cases.Add(Cur);
      end;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function CountChildrenRecursive(Node: TAstNode; Cap: Integer): Integer;
// Iterativ + Early-Exit bei Cap-Ueberschreitung. Verhindert
// Pathological-Method-Cost-Eskalation in der Inventur-Phase.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := 0;
  if Node = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Node);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      Inc(Result);
      if Result > Cap then Exit;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

// Identifier-Extraktion aus dem nkAssign.Name. Parser liefert hier
// LHS-Expression, z.B. 'X', 'Obj.X', 'X[i]'. Wir nehmen den linken
// nackten Identifier vor dem ersten Punkt/Bracket.
function ExtractBareIdent(const ExprName: string): string;
var
  i : Integer;
  C : Char;
begin
  Result := '';
  for i := 1 to Length(ExprName) do
  begin
    C := ExprName[i];
    if IsIdentChar(C) then
      Result := Result + C
    else
      Break;
  end;
end;

procedure CollectBodyTokens(Root: TAstNode; SB: TStringBuilder);
// Iterativ analog uUnusedLocal.CollectAllTokens - sammelt Name+TypeRef.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function LooksLikeRealLocalVar(Lines: TStringList; LineNo1: Integer): Boolean;
// Filtert nested-Routine-Headers die der Parser als nkLocalVar liefert
// (siehe uUnusedLocal.LooksLikeRealLocalVar). Wenn Lines fehlt -> akzeptieren.
var
  S, T : string;
begin
  Result := True;
  if (Lines = nil) or (LineNo1 <= 0) or (LineNo1 > Lines.Count) then Exit;
  S := Lines[LineNo1 - 1];
  T := LowerCase(TrimLeft(S));
  if T.StartsWith('procedure ')   or T.StartsWith('procedure(') or
     T.StartsWith('function ')    or T.StartsWith('function(')  or
     T.StartsWith('constructor ') or T.StartsWith('destructor ')or
     T.StartsWith('operator ')    or T.StartsWith('class procedure ') or
     T.StartsWith('class function ') then
    Exit(False);
end;

// ExtractCallFunctionName + ExtractCallArgsRaw wurden nach
// uDetectorUtils verschoben (Block 1b - geteilte Expression-Helper).
// Aufrufe via TDetectorUtils.ExtractCallFunctionName / .ExtractCallArgsRaw.

function ExtractForLoopVar(const ForTypeRef: string): string;
// TypeRef von nkForStmt enthaelt den Loop-Header, z.B.:
//   'i := 0 to 10'
//   'var x: Integer := 0 to 10'    (inline-var Form, aber inline-var hat
//                                   auch nkLocalVar-Child)
//   'i in container'
//   'VAR\tx := 0 to 10'             (Tab statt Space, case-mixed)
// Wir extrahieren den ersten Identifier nach optionalem 'var'-Keyword.
var
  S, Token : string;
  i, Start, KwLen : Integer;
begin
  Result := '';
  S := Trim(ForTypeRef);
  if S = '' then Exit;
  // Optional 'var'-Keyword (case-insensitive) ueberspringen — mit
  // beliebigem Whitespace (Space oder Tab) als Trennzeichen.
  if (Length(S) >= 4)
     and SameText(Copy(S, 1, 3), 'var')
     and (S[4] <= ' ') then
  begin
    KwLen := 3;
    while (KwLen + 1 <= Length(S)) and (S[KwLen + 1] <= ' ') do Inc(KwLen);
    S := Copy(S, KwLen + 1, MaxInt);
  end;
  // Erstes Token = Identifier-Chars + optional Punkt-Qualifier brechen wir
  // an Non-IdentChar ab.
  Start := 1;
  while (Start <= Length(S)) and (S[Start] <= ' ') do Inc(Start);
  i := Start;
  while (i <= Length(S)) and IsIdentChar(S[i]) do Inc(i);
  Token := Copy(S, Start, i - Start);
  Result := Token;
end;

function IsWriteAllowlistCall(const CallName: string): Boolean;
var
  FnName, Allow : string;
begin
  Result := False;
  FnName := LowerCase(TDetectorUtils.ExtractCallFunctionName(CallName));
  if FnName = '' then Exit;
  for Allow in WRITE_ALLOWLIST do
    if FnName = Allow then Exit(True);
end;

function IsReadOnlyCall(const CallName: string): Boolean;
// True wenn der Call seine Args garantiert NICHT schreibt. Default
// (weder Read- noch Write-Allowlist) = pessimistic-Write.
var
  FnName, Allow : string;
begin
  Result := False;
  FnName := LowerCase(TDetectorUtils.ExtractCallFunctionName(CallName));
  if FnName = '' then Exit;
  for Allow in READ_ALLOWLIST do
    if FnName = Allow then Exit(True);
end;

// TExprCall + ParseCallsInExpr nach uDetectorUtils verschoben (Block 1b).
// IsIdentStart-Helper damit ebenfalls obsolet (war nur fuer ParseCallsInExpr).

function FindIdentInArgList(const ArgsLow, NeedleLow: string): Boolean;
// Wortgrenz-Match fuer einen Identifier in der (lowercase) Arg-Liste.
var
  P, NL, L : Integer;
  Before, After : Char;
begin
  Result := False;
  NL := Length(NeedleLow);
  L  := Length(ArgsLow);
  if (NL = 0) or (L < NL) then Exit;
  P := 1;
  while True do
  begin
    P := PosEx(NeedleLow, ArgsLow, P);
    if P = 0 then Exit;
    Before := #0;
    if P > 1 then Before := ArgsLow[P - 1];
    After := #0;
    if P + NL - 1 < L then After := ArgsLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then Exit(True);
    P := P + NL;
  end;
end;

// ============================================================
// HAUPT-LOGIK
// ============================================================

class procedure TUninitVarDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  LocalVars        : TList<TAstNode>;
  Assigns, Calls, Fors : TList<TAstNode>;
  VarMap           : TDictionary<string, Integer>;
  VarList          : TList<TVarInfo>;
  Lines            : TStringList;
  Cached           : Boolean;
  BodySB           : TStringBuilder;
  BodyLow          : string;
  NestedRanges     : TList<TLineRange>;

  procedure RegisterWrite(Idx: Integer; Line: Integer);
  var
    P : PVarInfo;
  begin
    if (Idx < 0) or (Idx >= VarList.Count) or (Line <= 0) then Exit;
    P := @VarList.List[Idx];
    if (P.FirstWriteLine = 0) or (Line < P.FirstWriteLine) then
      P.FirstWriteLine := Line;
  end;

  function VarIndexFor(const NameLow: string): Integer;
  var
    Tmp : Integer;
  begin
    if VarMap.TryGetValue(NameLow, Tmp) then Result := Tmp else Result := -1;
  end;

  procedure ProcessAssign(A: TAstNode);
  var
    LhsBare : string;
    Idx     : Integer;
  begin
    if A = nil then Exit;
    // Phase 2.4: Hits aus nested-Methods ignorieren - die haben ihren
    // eigenen AnalyzeMethod-Aufruf, dort wird die Vars-Inventur korrekt
    // gemacht.
    if IsLineInRanges(A.Line, NestedRanges) then Exit;
    LhsBare := ExtractBareIdent(A.Name);
    if LhsBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LhsBare));
    if Idx >= 0 then RegisterWrite(Idx, A.Line);
  end;

  procedure RegisterArgVarsAsWrites(const ArgsLow: string; Line: Integer);
  // P2: Single-Pass-Tokenizer ueber ArgsLow. Pro Identifier-Token
  // Dictionary-Lookup in VarMap (O(args-Length) statt O(N x M) wie
  // vorher mit FindIdentInArgList-pro-Var). Pessimistic-Write Hit ->
  // RegisterWrite.
  var
    P, Start, Len : Integer;
    Idx : Integer;
    Token : string;
  begin
    Len := Length(ArgsLow);
    P := 1;
    while P <= Len do
    begin
      if IsIdentChar(ArgsLow[P]) then
      begin
        Start := P;
        while (P <= Len) and IsIdentChar(ArgsLow[P]) do Inc(P);
        Token := Copy(ArgsLow, Start, P - Start);
        Idx := VarIndexFor(Token);     // VarMap-Lookup, O(1) avg
        if Idx >= 0 then RegisterWrite(Idx, Line);
      end
      else
        Inc(P);
    end;
  end;

  procedure ProcessCall(C: TAstNode);
  var
    ArgsLow : string;
  begin
    if C = nil then Exit;
    if IsLineInRanges(C.Line, NestedRanges) then Exit;
    // Drei-Klassen-Modell (Konzept §6):
    //   1. READ_ALLOWLIST  (WriteLn, Assigned, Length, ...) -> KEIN Write
    //      registrieren. Var-Arg ist ein Read, das spaeter ueber Source-
    //      Line-Scan erkannt wird.
    //   2. WRITE_ALLOWLIST (ReadLn, FillChar, ...) -> Write registrieren.
    //   3. UNKNOWN-Calls (Helper.Init, MyProc, ...) -> pessimistic-Write
    //      registrieren (akzeptiert FNs, reduziert FPs bei OOP-Code).
    if IsReadOnlyCall(C.Name) then Exit;
    ArgsLow := LowerCase(TDetectorUtils.ExtractCallArgsRaw(C.Name));
    if ArgsLow = '' then Exit;
    RegisterArgVarsAsWrites(ArgsLow, C.Line);
  end;

  procedure ProcessConditionCalls(Node: TAstNode);
  // Phase 2.2 + 2.3: Calls innerhalb von Expression-tragenden Knoten
  // (nkIfStmt/nkWhileStmt/nkCaseStmt fuer Conditions, nkAssign/nkForStmt
  // fuer RHS-Ausdruecke) sind im Parser nicht als nkCall-Knoten abgelegt
  // sondern als TypeRef-String. Wir tokenisieren den String, finden alle
  // 'name(args)'-Pattern und behandeln sie wie ProcessCall
  // (READ_ALLOWLIST -> kein Write; sonst pessimistic-Write pro
  // Var-Identifier in den Args).
  //
  // Nested-procedure statt anonymous-method (greift auf Outer-Scope
  // VarList und RegisterWrite zu - anonymous procs koennen das nicht
  // erfassen, siehe E2555).
  var
    Calls   : TList<TExprCall>;
    Call    : TExprCall;
    ArgsLow : string;
  begin
    if (Node = nil) or (Node.TypeRef = '') then Exit;
    if IsLineInRanges(Node.Line, NestedRanges) then Exit;
    Calls := TList<TExprCall>.Create;
    try
      TDetectorUtils.ParseCallsInExpr(Node.TypeRef, Calls);
      for Call in Calls do
      begin
        // IsReadOnlyCall erwartet 'FuncName(...)' - wir bauen Stub.
        if IsReadOnlyCall(Call.FuncNameLow + '(') then Continue;
        ArgsLow := LowerCase(Call.ArgsRaw);
        if ArgsLow = '' then Continue;
        // P2: Single-Pass-Tokenizer + Dict-Lookup statt O(N) Inner-Loop.
        RegisterArgVarsAsWrites(ArgsLow, Node.Line);
      end;
    finally
      Calls.Free;
    end;
  end;

  procedure ProcessForStmt(F: TAstNode);
  var
    LoopBare : string;
    Idx : Integer;
    Child : TAstNode;
  begin
    if F = nil then Exit;
    if IsLineInRanges(F.Line, NestedRanges) then Exit;
    // Inline-var Form: 'for var x := ...' legt nkLocalVar als Child an.
    // Die Loop-Variable bekommt damit eine eigene Var-Inventur-Eintrag,
    // hier nichts zu tun (RegisterWrite waere doppelt).
    for Child in F.Children do
      if Child.Kind = nkLocalVar then Exit;

    // Klassische Form: TypeRef enthaelt 'i := 0 to 10' o.ae.
    // Loop-Var = erstes Token.
    LoopBare := ExtractForLoopVar(F.TypeRef);
    if LoopBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LoopBare));
    if Idx >= 0 then RegisterWrite(Idx, F.Line);
  end;

  function IsVarDeclLine(const LineLow: string): Boolean;
  // Heuristik: erkennt reine Var-Deklarationszeilen wie
  //   'sum: double;'
  //   's, sum: double;'
  //   'a, b, c: integer;'
  // ohne Init-Wert. Pattern: vor dem ersten ':' nur Ident-Chars/Komma/
  // Whitespace, ':' nicht direkt von '=' gefolgt (sonst ':=' Assignment),
  // endet mit ';'.
  //
  // Var-Decl MIT Init (':' Type = Wert;) zaehlt nicht als "reine Decl" -
  // wird via FirstWriteLine-Skip behandelt (gleiche Zeile wie Decl).
  var
    Trimmed : string;
    Cp, i, L : Integer;
    C : Char;
  begin
    Result := False;
    Trimmed := Trim(LineLow);
    L := Length(Trimmed);
    if L < 4 then Exit;
    if Trimmed[L] <> ';' then Exit;
    // Erste ':' suchen
    Cp := Pos(':', Trimmed);
    if (Cp = 0) or (Cp = L) then Exit;
    // ':=' = Assignment, KEINE Decl
    if Trimmed[Cp + 1] = '=' then Exit;
    // Vor dem ':' nur Ident-Chars, Komma, Whitespace
    for i := 1 to Cp - 1 do
    begin
      C := Trimmed[i];
      if not (CharInSet(C, ['a'..'z', '0'..'9', '_', ',', ' ', #9])) then
        Exit;
    end;
    // Nach dem ':' bis ';': Type (darf '=' enthalten falls Init, dann
    // ist's keine reine Decl).
    for i := Cp + 1 to L - 1 do
      if Trimmed[i] = '=' then Exit;
    Result := True;
  end;

  function FindFirstReadLine(const NameLow: string;
    DeclLine, FirstWriteLine, MethodStartLine, MethodEndLine: Integer): Integer;
  // Findet die erste Source-Zeile MIT einem Identifier-Match INNERHALB
  // der Method-Boundary [MethodStartLine..MethodEndLine] die NICHT die
  // Var-Deklaration, NICHT die Write-Zeile UND NICHT innerhalb einer
  // nested-Method ist (Phase 2.4).
  //
  // Method-Boundary ist KRITISCH: ohne sie wuerde der Scan ueber die
  // ganze Unit laufen und ein Field-Decl im Interface mit gleichem
  // Namen als "Read" werten (Faktor 30x FP-Explosion in der Praxis).
  //
  // FP-Fix (doublecmd-Audit): Multi-line Var-Decls mit Komma-Auflistung
  // wie 's,\n  sum: Double;' werden vom Parser nur mit EINER DeclLine
  // gemeldet. Die Zeilen wo die nachfolgenden Idents stehen werden
  // sonst als Read interpretiert. IsVarDeclLine-Heuristik erkennt
  // reine Decl-Zeilen und skippt sie.
  var
    i : Integer;
    L : string;
    P, NL, LL, From0, To0 : Integer;
    Before, After : Char;
    StripState : TLineStripState;
  begin
    Result := 0;
    if Lines = nil then Exit;
    NL := Length(NameLow);
    if NL = 0 then Exit;
    if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;
    From0 := MethodStartLine - 1;
    To0   := MethodEndLine - 1;
    if From0 < 0 then From0 := 0;
    if To0 > Lines.Count - 1 then To0 := Lines.Count - 1;
    // FP-Fix: State (InBrace/InParen) muss ueber alle Zeilen mitlaufen,
    // damit Multi-Line-Block-Comments { ... \n ... } und (* ... \n ... *)
    // korrekt geclipped werden. Annahme: bei MethodStartLine ist kein
    // Block-Comment offen (sehr seltene Verletzung in pathologischen
    // Files - akzeptabler Edge-Case).
    StripState.InBrace := False;
    StripState.InParen := False;
    for i := From0 to To0 do
    begin
      // IMMER strippen - auch bei skip - damit State korrekt mitwandert.
      L := LowerCase(StripLineEx(Lines[i], StripState));
      if (i + 1 = DeclLine) or (i + 1 = FirstWriteLine) then Continue;
      if IsLineInRanges(i + 1, NestedRanges) then Continue;
      // Skip wenn Zeile eine reine Var-Decl ist (Multi-line-Decl-Fix)
      if IsVarDeclLine(L) then Continue;
      LL := Length(L);
      P := 1;
      while True do
      begin
        P := PosEx(NameLow, L, P);
        if P = 0 then Break;
        Before := #0;
        if P > 1 then Before := L[P - 1];
        After := #0;
        if P + NL - 1 < LL then After := L[P + NL];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
        begin
          Exit(i + 1);
        end;
        P := P + NL;
      end;
    end;
  end;

  function CalcMethodEndLine(Node: TAstNode): Integer;
  // Method-Body-Ende = max(Line) ueber alle Descendants. Iterativer
  // Walk, Stack-safe auch fuer tiefe ASTs.
  var
    Stack : TStack<TAstNode>;
    Cur   : TAstNode;
    i     : Integer;
  begin
    Result := 0;
    if Node = nil then Exit;
    Result := Node.Line;
    Stack := TStack<TAstNode>.Create;
    try
      Stack.Push(Node);
      while Stack.Count > 0 do
      begin
        Cur := Stack.Pop;
        if Cur.Line > Result then Result := Cur.Line;
        for i := 0 to Cur.Children.Count - 1 do
          Stack.Push(Cur.Children[i]);
      end;
    finally
      Stack.Free;
    end;
  end;

  procedure PhaseA_VarInventur;
  // Aus FindAll(nkLocalVar) die Var-Inventur aufbauen + Skip-Regeln
  // anwenden (underscore-Prefix, Parser-Artefakt, Duplikate).
  var
    LV : TAstNode;
    VarRec : TVarInfo;
  begin
    for LV in LocalVars do
    begin
      if Trim(LV.Name) = '' then Continue;
      if LV.Name.StartsWith('_') then Continue;
      if not LooksLikeRealLocalVar(Lines, LV.Line) then Continue;
      VarRec.Name           := LV.Name;
      VarRec.NameLow        := LowerCase(LV.Name);
      VarRec.TypeLow        := LowerCase(LV.TypeRef);
      VarRec.DeclLine       := LV.Line;
      VarRec.FirstWriteLine := 0;
      VarRec.FirstReadLine  := 0;
      VarRec.RefCount       := 0;
      VarRec.IsManaged      := IsManagedType(LV.TypeRef);
      // Duplikate (same name in nested-scope - selten, defensive skip)
      if VarMap.ContainsKey(VarRec.NameLow) then Continue;
      VarMap.Add(VarRec.NameLow, VarList.Count);
      VarList.Add(VarRec);
    end;
  end;

  procedure PhaseB_AstWalks;
  // P1: Single-Pass DFS - 1x walken, 6 Buckets gleichzeitig fuellen.
  // Vorher: 8x MethodNode.FindAll mit jeweils komplettem Tree-Walk.
  //
  // Phase B (Writes aus nkAssign/nkCall/nkForStmt) + Phase 2.2+2.3
  // (Calls innerhalb if/while/case/assign-RHS/for-Range TypeRef-
  // Strings, via ParseCallsInExpr + pessimistic-Write).
  var
    Ifs, Whiles, Cases : TList<TAstNode>;
    i : Integer;
  begin
    Assigns := TList<TAstNode>.Create;
    Calls   := TList<TAstNode>.Create;
    Fors    := TList<TAstNode>.Create;
    Ifs     := TList<TAstNode>.Create;
    Whiles  := TList<TAstNode>.Create;
    Cases   := TList<TAstNode>.Create;
    try
      SinglePassCollectByKind(MethodNode, Assigns, Calls, Fors,
                              Ifs, Whiles, Cases);
      // Phase B - direkter Write aus AST-Knoten
      for i := 0 to Assigns.Count - 1 do ProcessAssign(Assigns[i]);
      for i := 0 to Calls.Count   - 1 do ProcessCall(Calls[i]);
      for i := 0 to Fors.Count    - 1 do ProcessForStmt(Fors[i]);
      // Phase 2.2+2.3 - Calls in TypeRef-Strings
      for i := 0 to Ifs.Count     - 1 do ProcessConditionCalls(Ifs[i]);
      for i := 0 to Whiles.Count  - 1 do ProcessConditionCalls(Whiles[i]);
      for i := 0 to Cases.Count   - 1 do ProcessConditionCalls(Cases[i]);
      for i := 0 to Assigns.Count - 1 do ProcessConditionCalls(Assigns[i]);
      for i := 0 to Fors.Count    - 1 do ProcessConditionCalls(Fors[i]);
    finally
      Cases.Free;
      Whiles.Free;
      Ifs.Free;
      Fors.Free;
      Calls.Free;
      Assigns.Free;
    end;
  end;

  procedure PhaseC_BodyTokenAndReads;
  // BodyToken-Sammlung fuer RefCount + Source-Line-Scan fuer FirstRead.
  // Method-Boundary [Start..End] limitiert den Scan - sonst matcht
  // Field-Decl im Interface mit gleichem Namen (FP-Faktor ~30x).
  var
    MethodStartLine, MethodEndLine, FirstMatchPos, i : Integer;
    P : PVarInfo;
  begin
    CollectBodyTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);
    MethodStartLine := MethodNode.Line;
    MethodEndLine   := CalcMethodEndLine(MethodNode);
    for i := 0 to VarList.Count - 1 do
    begin
      P := @VarList.List[i];
      P.RefCount := CountWholeWordOccurrences(P.NameLow, BodyLow,
                                              FirstMatchPos);
      // RefCount<=1 -> nur Deklaration = UnusedLocal-Domain (SCA019).
      if P.RefCount <= 1 then Continue;
      P.FirstReadLine := FindFirstReadLine(P.NameLow, P.DeclLine,
                                           P.FirstWriteLine,
                                           MethodStartLine, MethodEndLine);
    end;
  end;

  procedure PhaseD_Emit;
  // Klassifikation pro Var + Emit Findings.
  // Vier Skip-Pfade (UnusedLocal-Domain, managed types, nur Writes,
  // clean Read>=Write). Zwei Emit-Pfade:
  //   - FirstWrite = 0 + Refs > 0  -> 'never written' fcHigh
  //   - FirstRead < FirstWrite     -> 'read vor write' fcMedium
  var
    i : Integer;
    P : PVarInfo;
    F : TLeakFinding;
  begin
    for i := 0 to VarList.Count - 1 do
    begin
      P := @VarList.List[i];
      if P.RefCount <= 1 then Continue;        // UnusedLocal-Domain
      if P.IsManaged then Continue;            // managed types: opt-in
      if P.FirstReadLine = 0 then Continue;    // nur Writes - clean

      if P.FirstWriteLine = 0 then
      begin
        // Referenced + never written - UninitVar fcHigh.
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.DeclLine);
        F.MissingVar := Format(
          'Uninitialised variable: %s is read on line %d but never ' +
          'assigned in this method. Add an explicit initialiser ' +
          '(%s := Default; / Create; / SetLength(...)).',
          [P.Name, P.FirstReadLine, P.Name]);
        F.SetKind(fkUninitVar, fcHigh);
        Results.Add(F);
        Continue;
      end;

      if P.FirstReadLine < P.FirstWriteLine then
      begin
        // Read vor Write - konservativ fcMedium (Phase 2.1 Sibling-
        // Write-Check obsolet weil pessimistic-Write sowieso jeden
        // Write registriert, kein Confidence-Downgrade-Pfad).
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.FirstReadLine);
        F.MissingVar := Format(
          'Potential uninitialised read: %s read on line %d before its ' +
          'first assignment on line %d. Move the assignment up or add ' +
          'an explicit default before the first use.',
          [P.Name, P.FirstReadLine, P.FirstWriteLine]);
        F.SetKind(fkUninitVar, fcMedium);
        Results.Add(F);
      end;
    end;
  end;

var
  ChildCount : Integer;
begin
  // ------------------------------------------------------------------
  // ORCHESTRATOR: Fast-Outs + 4 Phasen (A, B, C, D)
  // ------------------------------------------------------------------
  if MethodNode = nil then Exit;
  // Fast-Out 1: asm-Block - kein Body zum Parsen.
  if IsAsmMethod(MethodNode) then Exit;
  // Fast-Out 2: pathologisch grosse Methode - Hard-Cap.
  ChildCount := CountChildrenRecursive(MethodNode, DetectorMaxChildrenRecursive);
  if ChildCount > DetectorMaxChildrenRecursive then Exit;

  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    if LocalVars.Count = 0 then Exit;
    if LocalVars.Count > DetectorMaxLocalVars then Exit;

    VarList      := TList<TVarInfo>.Create;
    VarMap       := TDictionary<string, Integer>.Create;
    BodySB       := TStringBuilder.Create;
    NestedRanges := TList<TLineRange>.Create;
    Lines        := AcquireLines(FileName, Cached);
    try
      // Phase 2.6: source-line-basierte Nested-Method-Detection.
      if Lines <> nil then
        CollectNestedMethodRangesViaSource(Lines, MethodNode.Line,
          CalcMethodEndLine(MethodNode), NestedRanges);

      PhaseA_VarInventur;
      if VarList.Count = 0 then Exit;

      PhaseB_AstWalks;
      PhaseC_BodyTokenAndReads;
      PhaseD_Emit;
    finally
      ReleaseLines(Lines, Cached);
      NestedRanges.Free;
      BodySB.Free;
      VarMap.Free;
      VarList.Free;
    end;
  finally
    LocalVars.Free;
  end;
end;

class procedure TUninitVarDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M : TAstNode;
begin
  if UnitNode = nil then Exit;
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
