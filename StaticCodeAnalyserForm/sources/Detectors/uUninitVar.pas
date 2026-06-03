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
  // Pessimistic-Default fuer alle anderen Calls: ihre Args sind Reads.
  // Stoesst der User einen FP, hilft '// noinspection UninitVar' oder
  // ein expliziter '<var> := Default;' Anker.
  WRITE_ALLOWLIST : array[0..11] of string = (
    'read', 'readln', 'blockread',
    'fillchar', 'move', 'zeromemory',
    'initialize', 'new', 'getmem',
    'setlength', 'setstring',
    'tryfromstring'         // TBytes.TryFromString und Verwandte
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

function IsWriteAllowlistCall(const CallName: string): Boolean;
var
  NameLow, Allow : string;
  DotPos : Integer;
begin
  Result := False;
  NameLow := LowerCase(Trim(CallName));
  if NameLow = '' then Exit;
  // Bei 'Obj.Read' den qualifizierten Methodennamen rechts vom Punkt nehmen.
  DotPos := LastDelimiter('.', NameLow);
  if DotPos > 0 then NameLow := Copy(NameLow, DotPos + 1, MaxInt);
  for Allow in WRITE_ALLOWLIST do
    if NameLow = Allow then Exit(True);
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
    LhsBare := ExtractBareIdent(A.Name);
    if LhsBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LhsBare));
    if Idx >= 0 then RegisterWrite(Idx, A.Line);
  end;

  procedure ProcessCall(C: TAstNode);
  var
    i, Idx : Integer;
    ArgBare : string;
  begin
    if (C = nil) or not IsWriteAllowlistCall(C.Name) then Exit;
    // Jedes Children-Element wird als Arg behandelt. Bare-Identifier
    // extrahieren und mit VarMap matchen. ProcessCall ist konservativ:
    // wir machen den Write nur fuer Allowlist-Calls - andere Calls
    // bekommen NICHT pessimistic-Read-Vermerk (das deckt der spaetere
    // Body-Token-Pass ab).
    for i := 0 to C.Children.Count - 1 do
    begin
      ArgBare := ExtractBareIdent(C.Children[i].Name);
      if ArgBare = '' then Continue;
      Idx := VarIndexFor(LowerCase(ArgBare));
      if Idx >= 0 then RegisterWrite(Idx, C.Line);
    end;
  end;

  procedure ProcessForStmt(F: TAstNode);
  var
    LoopBare : string;
    Idx : Integer;
  begin
    if F = nil then Exit;
    // Pascal-Parser legt die Loop-Variable als nkAssign-Child oder
    // direkt im Name-Feld ab. Heuristik: zuerst Name, sonst erstes Child.
    LoopBare := ExtractBareIdent(F.Name);
    if (LoopBare = '') and (F.Children.Count > 0) then
      LoopBare := ExtractBareIdent(F.Children[0].Name);
    if LoopBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LoopBare));
    if Idx >= 0 then RegisterWrite(Idx, F.Line);
  end;

  function FindFirstReadLine(const NameLow: string;
    DeclLine, FirstWriteLine: Integer): Integer;
  // Findet die erste Source-Zeile mit einem Identifier-Match die NICHT
  // die Var-Deklaration ist. Wenn FirstWriteLine > 0, wird die Write-
  // Zeile NICHT als Read gewertet. Wenn keine Read-Zeile gefunden -> 0.
  //
  // Strategie: linear durch Lines, jede Zeile Word-Boundary-Test gegen
  // NameLow, erste passende != DeclLine und != WriteLine zurueck.
  // Vorteil: liefert echte Source-Position (besser als BodyLow-Suche).
  var
    i : Integer;
    L : string;
    P, NL, LL : Integer;
    Before, After : Char;
  begin
    Result := 0;
    if Lines = nil then Exit;
    NL := Length(NameLow);
    if NL = 0 then Exit;
    for i := 0 to Lines.Count - 1 do
    begin
      if (i + 1 = DeclLine) or (i + 1 = FirstWriteLine) then Continue;
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

    VarList := TList<TVarInfo>.Create;
    VarMap  := TDictionary<string, Integer>.Create;
    BodySB  := TStringBuilder.Create;
    Lines   := AcquireLines(FileName, Cached);
    try
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

      // Phase C: Body-Token-Sammlung fuer RefCount + Reads via Source-Lines.
      CollectBodyTokens(MethodNode, BodySB);
      BodyLow := LowerCase(BodySB.ToString);

      for i := 0 to VarList.Count - 1 do
      begin
        P := @VarList.List[i];
        P.RefCount := CountWholeWordOccurrences(P.NameLow, BodyLow,
                                                FirstMatchPos);
        // RefCount<=1 -> nur die Deklaration; das ist UnusedLocal-Domain
        // (kein UninitVar - faellt unter SCA019).
        if P.RefCount <= 1 then Continue;

        // FirstReadLine sucht im Source. Wenn KEIN Write vorhanden,
        // ist die "Read-Zeile" jede non-Decl-Erwaehnung.
        P.FirstReadLine := FindFirstReadLine(P.NameLow, P.DeclLine,
                                             P.FirstWriteLine);
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
