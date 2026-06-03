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

const
  // Hard-Caps gegen pathologisch grosse Methoden (Konzept §8.7).
  // Bei Ueberschreitung wird die Methode nicht analysiert (kein Flag,
  // kein Crash) - sichert die Detector-Wall-Time gegen O(n)-Eskalation.
  MAX_LOCAL_VARS = 200;
  MAX_CHILDREN_RECURSIVE = 5000;

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
  READ_ALLOWLIST : array[0..55] of string = (
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

procedure CollectNestedMethodRanges(MethodNode: TAstNode;
  Ranges: TList<TLineRange>);
// Sammelt Line-Ranges aller nested-Methods (nkMethod-Knoten innerhalb
// MethodNode). MethodNode selbst NICHT mit aufnehmen (das ist der
// Outer-Body).
//
// Hintergrund (Phase 2.4): nkAssign/nkCall/nkForStmt-Walks auf den
// Outer-MethodNode liefern auch Knoten aus nested-Procedures. Das
// fuehrt zu FPs:
//   procedure Outer;
//   var i: Integer;
//     procedure Inner; begin Inc(i); end;   // pessimistic-Write auf Z3
//   begin
//     i := 0;                                // echter Init auf Z6
//     ...
//   end;
// Mein Detector nimmt Inc(i) als FirstWrite (kleinste Line). Z3 < Z6 ->
// flag. Echt-init auf Z6 wird ueberhaupt nicht als 'WriteLine' gewertet
// weil Z3 schon registriert ist (RegisterWrite nimmt MIN).
//
// Fix: alle Hits aus nested-Method-Ranges ueberspringen. Nested
// Procedures haben ihren eigenen AnalyzeMethod-Aufruf.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
  R     : TLineRange;

  function CalcEnd(N: TAstNode): Integer;
  var
    Inner : TStack<TAstNode>;
    Sub   : TAstNode;
    j     : Integer;
  begin
    Result := N.Line;
    Inner := TStack<TAstNode>.Create;
    try
      Inner.Push(N);
      while Inner.Count > 0 do
      begin
        Sub := Inner.Pop;
        if Sub.Line > Result then Result := Sub.Line;
        for j := 0 to Sub.Children.Count - 1 do
          Inner.Push(Sub.Children[j]);
      end;
    finally
      Inner.Free;
    end;
  end;

begin
  if (MethodNode = nil) or (Ranges = nil) then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    // Children durchgehen, MethodNode selbst NICHT (das IST der Outer-Body).
    for i := 0 to MethodNode.Children.Count - 1 do
      Stack.Push(MethodNode.Children[i]);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Kind = nkMethod then
      begin
        R.StartLine := Cur.Line;
        R.EndLine   := CalcEnd(Cur);
        Ranges.Add(R);
        // NICHT in nested-Method weiter descenden - nested-of-nested
        // ist Sub-Range der jetzigen, der Skip-Check matched trotzdem.
        Continue;
      end;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

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

function ExtractCallFunctionName(const CallExpr: string): string;
// nkCall.Name ist die ganze Call-Expression (Parser-Pattern aus
// uParser2.ParseCallOrAssign: 'ReadLn(n)' / 'TConfidenceFilter.Apply(...)' /
// 'Obj.Method(a, b)'). Wir extrahieren den Funktions-Namen rechts vom
// letzten Punkt vor dem '(' (oder den ganzen Ident wenn kein Punkt).
var
  S : string;
  ParenPos, DotPos : Integer;
begin
  S := Trim(CallExpr);
  ParenPos := Pos('(', S);
  if ParenPos > 0 then
    S := Trim(Copy(S, 1, ParenPos - 1));
  DotPos := LastDelimiter('.', S);
  if DotPos > 0 then
    S := Trim(Copy(S, DotPos + 1, MaxInt));
  Result := S;
end;

function ExtractCallArgsRaw(const CallExpr: string): string;
// Liefert den String zwischen erster '(' und passender ')' (oder ab
// '(' bis Ende falls kein matching ')'-Pair). Wir parsen die Args
// nicht semantisch - die Token-Boundary-Suche reicht.
var
  S : string;
  ParenPos, Depth, i : Integer;
begin
  Result := '';
  S := CallExpr;
  ParenPos := Pos('(', S);
  if ParenPos = 0 then Exit;
  Depth := 1;
  for i := ParenPos + 1 to Length(S) do
  begin
    if S[i] = '(' then Inc(Depth)
    else if S[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Result := Copy(S, ParenPos + 1, i - ParenPos - 1);
        Exit;
      end;
    end;
  end;
  // Kein matching ')' - alles ab '(' nehmen.
  Result := Copy(S, ParenPos + 1, MaxInt);
end;

function ExtractForLoopVar(const ForTypeRef: string): string;
// TypeRef von nkForStmt enthaelt den Loop-Header, z.B.:
//   'i := 0 to 10'
//   'var x: Integer := 0 to 10'    (inline-var Form, aber inline-var hat
//                                   auch nkLocalVar-Child)
//   'i in container'
// Wir extrahieren den ersten Identifier nach optionalem 'var'.
var
  S, Token : string;
  i, Start : Integer;
begin
  Result := '';
  S := Trim(ForTypeRef);
  if S = '' then Exit;
  // Optional 'var' (lowercase-tolerant) ueberspringen.
  if SameText(Copy(S, 1, 4), 'var ') then
    S := TrimLeft(Copy(S, 5, MaxInt));
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
  FnName := LowerCase(ExtractCallFunctionName(CallName));
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
  FnName := LowerCase(ExtractCallFunctionName(CallName));
  if FnName = '' then Exit;
  for Allow in READ_ALLOWLIST do
    if FnName = Allow then Exit(True);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

type
  TExprCall = record
    FuncNameLow : string;
    ArgsRaw     : string;
  end;

procedure ParseCallsInExpr(const Expr: string;
  Calls: TList<TExprCall>);
// Findet alle 'name(args)'-Pattern im Expr-String und fuegt sie zu
// Calls hinzu. Nested-paren-aware (Depth-Counting). Whitespace zwischen
// name und '(' wird toleriert - der Parser packt Conditions oft mit
// JoinTokInto + Space-Separator.
//
// Phase-2.2-Helper: wird genutzt um Calls in if/while/case-Conditions
// zu finden, die der AST als nkIfStmt.TypeRef-String ablegt (nicht als
// nkCall-Knoten).
//
// List-basiert statt anonymous-method-Callback weil anonymous procs
// in Delphi Nested-Procedures der enclosing Method (z.B. RegisterWrite
// in AnalyzeMethod) nicht erfassen koennen (E2555).
var
  T          : string;
  i, NameStart, NameEnd, Depth, ArgsStart : Integer;
  Entry      : TExprCall;
begin
  if Calls = nil then Exit;
  T := Expr;
  i := 1;
  while i <= Length(T) do
  begin
    if not IsIdentStart(T[i]) then
    begin
      Inc(i);
      Continue;
    end;
    NameStart := i;
    while (i <= Length(T)) and IsIdentChar(T[i]) do Inc(i);
    NameEnd := i - 1;
    while (i <= Length(T)) and (T[i] = ' ') do Inc(i);
    if (i > Length(T)) or (T[i] <> '(') then Continue;
    // OK - 'name(' Pattern; Args bis matching ')' extrahieren.
    Inc(i);                                   // hinter '('
    ArgsStart := i;
    Depth := 1;
    while (i <= Length(T)) and (Depth > 0) do
    begin
      if T[i] = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Break;
      end;
      Inc(i);
    end;
    Entry.FuncNameLow := LowerCase(Copy(T, NameStart, NameEnd - NameStart + 1));
    Entry.ArgsRaw     := Copy(T, ArgsStart, i - ArgsStart);
    Calls.Add(Entry);
    if (i <= Length(T)) and (T[i] = ')') then Inc(i);
  end;
end;

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

  procedure ProcessCall(C: TAstNode);
  var
    ArgsLow : string;
    i : Integer;
    VI : TVarInfo;
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

    ArgsLow := LowerCase(ExtractCallArgsRaw(C.Name));
    if ArgsLow = '' then Exit;
    for i := 0 to VarList.Count - 1 do
    begin
      VI := VarList[i];
      if FindIdentInArgList(ArgsLow, VI.NameLow) then
        RegisterWrite(i, C.Line);
    end;
  end;

  procedure ProcessConditionCalls(Node: TAstNode);
  // Phase 2.2: Calls in if/while/case-Conditions sind im Parser nicht
  // als nkCall-Knoten abgelegt sondern als TypeRef-String. Wir tokenisieren
  // den String, finden alle 'name(args)'-Pattern und behandeln sie wie
  // ProcessCall (READ_ALLOWLIST -> kein Write; sonst pessimistic-Write
  // pro Var-Identifier in den Args).
  //
  // Nested-procedure statt anonymous-method (greift auf Outer-Scope
  // VarList und RegisterWrite zu - anonymous procs koennen das nicht
  // erfassen, siehe E2555).
  var
    Calls   : TList<TExprCall>;
    Call    : TExprCall;
    i       : Integer;
    VI      : TVarInfo;
    ArgsLow : string;
  begin
    if (Node = nil) or (Node.TypeRef = '') then Exit;
    if IsLineInRanges(Node.Line, NestedRanges) then Exit;
    Calls := TList<TExprCall>.Create;
    try
      ParseCallsInExpr(Node.TypeRef, Calls);
      for Call in Calls do
      begin
        // IsReadOnlyCall erwartet 'FuncName(...)' - wir bauen Stub.
        if IsReadOnlyCall(Call.FuncNameLow + '(') then Continue;
        ArgsLow := LowerCase(Call.ArgsRaw);
        if ArgsLow = '' then Continue;
        for i := 0 to VarList.Count - 1 do
        begin
          VI := VarList[i];
          if FindIdentInArgList(ArgsLow, VI.NameLow) then
            RegisterWrite(i, Node.Line);
        end;
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
  var
    i : Integer;
    L : string;
    P, NL, LL, From0, To0 : Integer;
    Before, After : Char;
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
    for i := From0 to To0 do
    begin
      if (i + 1 = DeclLine) or (i + 1 = FirstWriteLine) then Continue;
      if IsLineInRanges(i + 1, NestedRanges) then Continue;
      L := LowerCase(Lines[i]);
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

var
  i : Integer;
  LV : TAstNode;
  VarRec : TVarInfo;
  ChildCount : Integer;
  P : PVarInfo;
  F : TLeakFinding;
  FirstMatchPos : Integer;
begin
  if MethodNode = nil then Exit;

  // Fast-Out 1: asm-Block - kein Body zum Parsen.
  if IsAsmMethod(MethodNode) then Exit;

  // Fast-Out 2: pathologisch grosse Methode - Hard-Cap.
  ChildCount := CountChildrenRecursive(MethodNode, MAX_CHILDREN_RECURSIVE);
  if ChildCount > MAX_CHILDREN_RECURSIVE then Exit;

  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    if LocalVars.Count = 0 then Exit;
    if LocalVars.Count > MAX_LOCAL_VARS then Exit;

    VarList      := TList<TVarInfo>.Create;
    VarMap       := TDictionary<string, Integer>.Create;
    BodySB       := TStringBuilder.Create;
    NestedRanges := TList<TLineRange>.Create;
    Lines        := AcquireLines(FileName, Cached);
    try
      CollectNestedMethodRanges(MethodNode, NestedRanges);
      // Phase A: Var-Inventur
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
      if VarList.Count = 0 then Exit;

      // Phase B: Writes registrieren aus dem AST.
      Assigns := MethodNode.FindAll(nkAssign);
      try
        for i := 0 to Assigns.Count - 1 do
          ProcessAssign(Assigns[i]);
      finally
        Assigns.Free;
      end;

      Calls := MethodNode.FindAll(nkCall);
      try
        for i := 0 to Calls.Count - 1 do
          ProcessCall(Calls[i]);
      finally
        Calls.Free;
      end;

      Fors := MethodNode.FindAll(nkForStmt);
      try
        for i := 0 to Fors.Count - 1 do
          ProcessForStmt(Fors[i]);
      finally
        Fors.Free;
      end;

      // Phase 2.2 + 2.3: Calls innerhalb von Expression-tragenden Knoten
      // (TypeRef-Strings statt nkCall) als pessimistic-Write erkennen.
      //   Phase 2.2: nkIfStmt + nkWhileStmt + nkCaseStmt
      //   Phase 2.3: nkAssign.RHS (z.B. 'Lines := AcquireLines(F, Cached)'
      //              schreibt Cached out-Param) + nkForStmt.Range
      // Alle teilen den gleichen ParseCallsInExpr-Pfad.
      var Exprs : TList<TAstNode> := MethodNode.FindAll(nkIfStmt);
      try
        for i := 0 to Exprs.Count - 1 do ProcessConditionCalls(Exprs[i]);
      finally Exprs.Free; end;
      Exprs := MethodNode.FindAll(nkWhileStmt);
      try
        for i := 0 to Exprs.Count - 1 do ProcessConditionCalls(Exprs[i]);
      finally Exprs.Free; end;
      Exprs := MethodNode.FindAll(nkCaseStmt);
      try
        for i := 0 to Exprs.Count - 1 do ProcessConditionCalls(Exprs[i]);
      finally Exprs.Free; end;
      Exprs := MethodNode.FindAll(nkAssign);
      try
        for i := 0 to Exprs.Count - 1 do ProcessConditionCalls(Exprs[i]);
      finally Exprs.Free; end;
      Exprs := MethodNode.FindAll(nkForStmt);
      try
        for i := 0 to Exprs.Count - 1 do ProcessConditionCalls(Exprs[i]);
      finally Exprs.Free; end;

      // Phase C: Body-Token-Sammlung fuer RefCount + Reads via Source-Lines.
      // Method-Boundary [Start..End] limitiert den Read-Scan auf den
      // tatsaechlichen Method-Body - sonst matcht ein Field-Decl im
      // Interface-Section mit gleichem Namen als "Read" (FP-Faktor ~30x).
      CollectBodyTokens(MethodNode, BodySB);
      BodyLow := LowerCase(BodySB.ToString);
      var MethodStartLine := MethodNode.Line;
      var MethodEndLine   := CalcMethodEndLine(MethodNode);

      for i := 0 to VarList.Count - 1 do
      begin
        P := @VarList.List[i];
        P.RefCount := CountWholeWordOccurrences(P.NameLow, BodyLow,
                                                FirstMatchPos);
        // RefCount<=1 -> nur die Deklaration; das ist UnusedLocal-Domain
        // (kein UninitVar - faellt unter SCA019).
        if P.RefCount <= 1 then Continue;

        // FirstReadLine sucht im Source-Body (NUR innerhalb der Method).
        P.FirstReadLine := FindFirstReadLine(P.NameLow, P.DeclLine,
                                             P.FirstWriteLine,
                                             MethodStartLine, MethodEndLine);
      end;

      // Phase D: Emit.
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
          // Read vor Write - konservativ fcMedium weil wir Conditional-
          // Writes nicht von Unconditional-Writes unterscheiden koennen
          // (MVP). Phase 2 erweitert das (Sibling-Write-Check).
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
