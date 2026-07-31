unit uRoutineResultAssigned;

// Detektor: Function-Body endet ohne dass `Result` (oder der Function-Name)
// jemals geschrieben wurde.
//
// Pattern (Bug):
//   function Compute(x: Integer): Integer;
//   begin
//     if x > 0 then
//       LogMessage('positive');
//     // <-- Result nie gesetzt -> undefined Return-Value
//   end;
//
// Korrekt:
//   function Compute(x: Integer): Integer;
//   begin
//     Result := 0;
//     if x > 0 then
//     begin
//       Result := x * 2;
//       LogMessage('positive');
//     end;
//   end;
//
// Folge: In Release-Builds liefert die Funktion den Wert des
// stack/register-Garbages oder den Wert des letzten gleichgrossen
// Calls - klassischer "manchmal funktioniert es"-Heisenbug.
//
// Erkennung (konservativ, keine Path-Sensitivity):
//   * Nur Functions: MNode.TypeRef enthaelt ':' (= Return-Type vorhanden).
//   * Skip wenn Body abstract/forward/external/virtual+abstract (kein Body).
//   * Skip wenn IRGENDWO im Body:
//       - nkExit  - koennte Exit(value) sein (Argument vom Parser verworfen).
//       - nkRaise - Method wirft, kein Return-Pfad noetig.
//       - nkAssign mit LHS = 'result' (case-insensitive) - hier kommt
//         die Result-Zuweisung.
//       - nkAssign mit LHS = <FunctionName> (case-insensitive) - klassischer
//         Pascal-Stil: `<func> := value`.
//   * Sonst -> Finding.
//
// Bewusst nicht analysiert:
//   * Partial Coverage (Result in einem then-Zweig, aber nicht im else)
//     -> bewusst False-Negative bis CFG-Analyse implementiert ist.
//
// Sonar-Pendant: RoutineResultAssignedCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   RoutineResultAssignedCheck.java

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TRoutineResultAssignedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    // ANoReturnLow: lowercase, unqualifizierte Namen aller Routinen DIESER Unit,
    // die als `noreturn` deklariert sind (Delphi-12-Direktive). Ein Body-Call auf
    // eine solche Routine ist semantisch ein `raise` - die Funktion kehrt nie
    // regulaer zurueck, ein fehlendes `Result :=` ist dann KEIN Bug. AnalyzeUnit
    // fuellt das Set; nil => Guard inaktiv (Verhalten wie vorher).
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>;
      ANoReturnLow: TDictionary<string, Boolean> = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, MultipleExit, NestedRoutine, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,    // TStringList fuer die Quelltext-Gates (2026-07-31)
  uFileTextCache;    // AcquireLines/ReleaseLines - Lazy-Load, nur bei Kandidaten

// Liefert True wenn TypeRef einen Return-Type enthaelt (Format
// 'function:RetType[;direktive...]'). Procedures haben keinen ':' im
// Kind-Teil. Robust gegen Direktiven-Suffix.
function IsFunctionMethod(const TypeRef: string): Boolean;
var
  ColonPos, SemiPos : Integer;
begin
  ColonPos := Pos(':', TypeRef);
  if ColonPos = 0 then Exit(False);
  SemiPos := Pos(';', TypeRef);
  // ':' muss VOR dem ersten ';'-Direktiv-Trenner kommen, sonst koennte
  // ein generisches 'procedure;virtual:abstract' (theoretisch) falsch
  // matchen. In der Praxis kommt das nicht vor, defensiv trotzdem.
  Result := (SemiPos = 0) or (ColonPos < SemiPos);
end;

// True wenn TypeRef einen der Body-losen Direktiven-Marker enthaelt.
function IsBodyless(const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';abstract',  Low) > 0) or
            (Pos(';forward',   Low) > 0) or
            (Pos(';external',  Low) > 0) or
            (Pos(';dispid',    Low) > 0);
end;

// True wenn die Methode mindestens eine Statement-Art im Body hat.
// Interface-Methoden-Deklarationen + Class-Method-Deklarationen im
// Typ-Section haben KEINEN Body - nur evtl. nkParam-Children. Ohne
// diesen Filter feuert der Detektor auf jede einzelne Interface-
// Methode (Result wird ja nirgends zugewiesen - logisch, der Body
// kommt erst in der implementierenden Klasse).
function HasBodyStatement(N: TAstNode): Boolean;
const
  // nkBlock auch akzeptieren: ein leerer `begin end;` Function-Body ist
  // semantisch eine echte Implementation (function-result wird nicht
  // gesetzt -> genau der Bug den wir suchen). Ohne nkBlock wuerde der
  // leere Body als "kein Body" gewertet und wir wuerden schweigen
  // (Audit V5 / 2026-05-30).
  BODY_KINDS = [nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt,
                nkWhileStmt, nkRepeatStmt, nkTryExcept, nkTryFinally,
                nkRaise, nkExit, nkBreak, nkContinue, nkInherited,
                nkLocalVar, nkBlock];
var
  Child : TAstNode;
begin
  if N.Kind in BODY_KINDS then Exit(True);
  for Child in N.Children do
    if HasBodyStatement(Child) then Exit(True);
  Result := False;
end;

// FP-Gate 2026-07-31 (30%-Real-World-Audit, FP-Klasse "Interface-Deklaration
// statt Implementation geankert"): True nur wenn die Routine einen EIGENEN,
// tatsaechlich geparsten `begin..end`-Rumpf hat (direktes nkBlock-Kind; nur
// ParseBlock haengt eines an den Methodenknoten).
//
// Mechanismus des FPs: eine Routinen-DEKLARATION im Deklarationsteil (z.B.
// mormot.lib.gssapi ServerForceKeytab, Z.616 - der Lexer sieht wegen
// '{$ifdef OSWINDOWS} implementation {$else}' bereits die Implementation-
// Sektion) hat keinen Rumpf. ParseMethodImpl zieht danach die FOLGENDEN
// unit-level const/var-Sektionen als vermeintlich lokale Deklarationen an den
// Knoten; die nkLocalVar-Kinder liessen HasBodyStatement True werden und der
// Detektor meldete eine Deklaration, deren echte Implementation Result sehr
// wohl zuweist. Dieselbe Lage entsteht bei jedem Parse-Schaden, der den Rumpf
// verliert - ohne Rumpf hat der Detektor keine Beweisgrundlage.
//
// Nebeneffekt (gewollt): eine Routine mit reinem `asm ... end;`-Rumpf ohne
// vorangehendes `begin` bekommt vom Parser ebenfalls kein nkBlock (der
// tkKwAsm-Zweig skippt bloss) - Result kommt dort per Register.
function HasOwnBodyBlock(N: TAstNode): Boolean;
var
  Child : TAstNode;
begin
  for Child in N.Children do
    if Child.Kind = nkBlock then Exit(True);
  Result := False;
end;

// Restschulden-Audit 2026-07-26: lokale UnqualifiedName-Kopie entfernt -
// jetzt TDetectorUtils.UnqualifiedNameLast (war in 8 Detektoren dupliziert,
// eine Kopie mit abweichender Semantik). Verhalten hier unveraendert.

// Normalisiert eine LHS-String fuer Vergleich: lowercase, Whitespace raus.
function NormalizeLhs(const S: string): string;
var
  i : Integer;
  C : Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C > ' ' then
      Result := Result + LowerCase(C);
  end;
end;

// True wenn LhsLow eine Result-Zuweisung repraesentiert.
// Akzeptierte Formen (alle case-insensitive nach NormalizeLhs):
//   Result            - skalar
//   Result.Field      - Record / Object
//   Result[i]         - Array / Dynarray / String-Index
//   Result^           - Pointer-Deref (rare)
// Analog fuer den klassischen Pascal-Stil ueber den Function-Namen
//   <FnName>          - skalar
//   <FnName>.Field    - Record / Object
//   <FnName>[i]       - Array
// FnNameLow muss bereits unqualifiziert + lowercased sein.
function IsResultLhs(const LhsLow, FnNameLow: string): Boolean;

  function IsHeadOrAccess(const Head: string): Boolean;
  begin
    if Head = '' then Exit(False);
    if LhsLow = Head then Exit(True);
    if Length(LhsLow) <= Length(Head) then Exit(False);
    if Copy(LhsLow, 1, Length(Head)) <> Head then Exit(False);
    // Erstes Zeichen NACH Head muss ein Accessor sein - sonst waere es
    // ein anderer Identifier der zufaellig dasselbe Prefix hat
    // (z.B. 'resultcache' vs 'result').
    case LhsLow[Length(Head) + 1] of
      '.', '[', '^': Result := True;
    else
      Result := False;
    end;
  end;

begin
  Result := IsHeadOrAccess('result') or IsHeadOrAccess(FnNameLow);
end;

function IsIdentChar(c: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(c);
end;

// Word-boundary-Lookup von Needle in Haystack. Beide bereits lowercased.
// Behandelt `Result.Field`, `Result[i]`, `Result^` als Treffer
// (`.`, `[`, `^` sind keine Identifier-Chars und zaehlen als Boundary).
function ContainsIdentifier(const Haystack, Needle: string): Boolean;
var
  pIx           : Integer;
  Before, After : Char;
begin
  Result := False;
  if Needle = '' then Exit;
  pIx := Pos(Needle, Haystack);
  while pIx > 0 do
  begin
    if pIx = 1 then Before := ' ' else Before := Haystack[pIx - 1];
    if pIx + Length(Needle) > Length(Haystack) then After := ' '
    else After := Haystack[pIx + Length(Needle)];
    if (not IsIdentChar(Before)) and (not IsIdentChar(After)) then
      Exit(True);
    pIx := PosEx(Needle, Haystack, pIx + 1);
  end;
end;

// True wenn der Call Result (oder den Function-Namen) als Argument
// uebergibt - z.B. `FParams.TryGetValue(AKey, Result)` oder
// `TryStrToInt(s, Result)`. Wir wissen lexisch nicht ob das Argument
// `var`/`out`/by-value ist, behandeln das aber konservativ als potentielle
// Zuweisung. Eliminiert den FP-Cluster bei TryGetValue / TryParse /
// TryStrToXxx / TryEncode... bei winzigem False-Negative-Risiko fuer
// `Foo(Result)`-Calls die Result nur LESEN.
function CallPassesResultAsArg(CallNode: TAstNode; const FnNameLow: string): Boolean;
var
  S, ArgsLow    : string;
  LParen, RParen: Integer;
begin
  Result := False;
  if CallNode.Kind <> nkCall then Exit;
  S := CallNode.Name;
  LParen := Pos('(', S);
  if LParen = 0 then Exit;
  RParen := Length(S);
  while (RParen > LParen) and (S[RParen] <> ')') do Dec(RParen);
  if RParen <= LParen + 1 then Exit;
  ArgsLow := LowerCase(Copy(S, LParen + 1, RParen - LParen - 1));
  Result := ContainsIdentifier(ArgsLow, 'result');
  if (not Result) and (FnNameLow <> '') then
    Result := ContainsIdentifier(ArgsLow, FnNameLow);
end;

// True wenn die Methode eine lokale Variable mit 'absolute Result'-Alias
// deklariert (z.B. 'Bits: UInt32 absolute Result;'). Schreibzugriffe gehen
// dann ueber den Alias an den Result-Slot - der Detektor sieht nie 'Result'
// auf einer LHS und meldet faelschlich "unassigned". (Real-World 2026-06-28,
// z.B. Img32/mORMot-Bit-Manipulation; zero-FN: ein absolute-Result-Alias
// schreibt per Definition in den Return-Slot.)
function HasAbsoluteResultAlias(MethodNode: TAstNode): Boolean;
var
  LocalVars : TList<TAstNode>;
  LV : TAstNode;
  Low : string;
  p, j : Integer;
begin
  Result := False;
  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    for LV in LocalVars do
    begin
      Low := LowerCase(LV.TypeRef);
      p := Pos('absolute', Low);
      if p = 0 then Continue;
      j := p + 8;                                  // hinter 'absolute'
      while (j <= Length(Low)) and (Low[j] <= ' ') do Inc(j);
      if (Copy(Low, j, 6) = 'result')
         and ((j + 6 > Length(Low))
              or not CharInSet(Low[j + 6], ['a'..'z', '0'..'9', '_'])) then
        Exit(True);
    end;
  finally
    LocalVars.Free;
  end;
end;

function ExprWritesOrPassesResult(const SLow, FnNameLow: string): Boolean;
// Prueft einen bereits lowercased Expression-/Condition-String auf Result-
// Write-/Pass-Muster die die per-nkCall/nkAssign-Checks verfehlen (der Parser
// legt Bedingungs-Calls + RHS als TypeRef-String ab):
//   '@result'          -> Adresse genommen, Callee schreibt durch
//   ',result'          -> Result als Argument in einer Argumentliste (out/var)
//   'ident(result'     -> Result als erstes Call-Argument (out/var)
//   'result :='        -> parser-verpasste Zuweisung (goto/nested-Body)
// Word-bounded; '(result' aus reiner Gruppierung '(Result > 0)' wird NICHT
// getroffen (davor steht kein Ident). Real-World-FP-Audit 2026-07-10:
// 'result-out-param', 'result-addr-taken', teilweise 'result-assigned-parse'.
var
  n, i, k, q : Integer;
  pc : Char;

  function IsResultWordAt(pos: Integer): Boolean;
  begin
    Result := (Copy(SLow, pos, 6) = 'result')
      and ((pos = 1) or not IsIdentChar(SLow[pos - 1]))
      and ((pos + 6 > n) or not IsIdentChar(SLow[pos + 6]));
  end;

begin
  Result := False;
  n := Length(SLow);
  if n < 6 then Exit;
  for i := 1 to n - 5 do
  begin
    if (SLow[i] <> 'r') or not IsResultWordAt(i) then Continue;
    // vorheriges Non-Space-Zeichen
    k := i - 1;
    while (k >= 1) and (SLow[k] = ' ') do Dec(k);
    if k >= 1 then pc := SLow[k] else pc := #0;
    if (pc = '@') or (pc = ',') then Exit(True);
    if (pc = '(') and (k >= 2) and IsIdentChar(SLow[k - 1]) then Exit(True);
    // 'result :='
    q := i + 6;
    while (q <= n) and (SLow[q] = ' ') do Inc(q);
    if (q < n) and (SLow[q] = ':') and (SLow[q + 1] = '=') then Exit(True);
  end;
end;

function AnyNodeStringWritesResult(MethodNode: TAstNode;
  const FnNameLow: string): Boolean;
// Iterativer Walk ueber alle Descendants; prueft Name + TypeRef jedes Knotens
// mit ExprWritesOrPassesResult. Faengt Result-out-Param in Bedingungen
// (nkIfStmt.TypeRef) und '@Result' in RHS (nkAssign.TypeRef), die FindAll(nkCall)
// nicht als Call-Knoten sieht.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := False;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(MethodNode);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if (Cur.TypeRef <> '')
         and ExprWritesOrPassesResult(LowerCase(Cur.TypeRef), FnNameLow) then
        Exit(True);
      if (Cur.Name <> '')
         and ExprWritesOrPassesResult(LowerCase(Cur.Name), FnNameLow) then
        Exit(True);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

// True wenn der Function-Body effektiv leer ist (`function Foo: T; begin end;`).
// Genutzt fuer den File-Wide-Stub-Skip (AnalyzeUnit) UND den managed-Return-
// Empty-Body-Skip (AnalyzeMethod). Deshalb hier VOR AnalyzeMethod definiert.
function IsEffectivelyEmptyBody(MethodNode: TAstNode): Boolean;
var
  Child : TAstNode;
  GrandChild : TAstNode;
begin
  Result := True;
  for Child in MethodNode.Children do
  begin
    case Child.Kind of
      nkBlock:
        for GrandChild in Child.Children do
          if GrandChild.Kind in [nkAssign, nkCall, nkIfStmt, nkCaseStmt,
                                  nkForStmt, nkWhileStmt, nkRepeatStmt,
                                  nkTryExcept, nkTryFinally, nkRaise, nkExit,
                                  nkBreak, nkContinue, nkInherited] then
            Exit(False);
      nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt, nkWhileStmt,
      nkRepeatStmt, nkTryExcept, nkTryFinally, nkRaise, nkExit,
      nkBreak, nkContinue, nkInherited:
        Exit(False);
    end;
  end;
end;

// Extrahiert den Return-Typ aus dem Kind-String 'function:RetType[;direktive...]'.
function ExtractReturnType(const TypeRef: string): string;
var
  c, s : Integer;
begin
  Result := '';
  c := Pos(':', TypeRef);
  if c = 0 then Exit;
  Result := Copy(TypeRef, c + 1, MaxInt);
  s := Pos(';', Result);
  if s > 0 then Result := Copy(Result, 1, s - 1);
  Result := Trim(Result);
end;

// True wenn der Return-Typ ein compiler-MANAGED Typ ist (auto-init ''/nil/
// Unassigned): dann ist der Return-Wert bei fehlendem Result:= NICHT "undefined"
// (der Kern-Claim von SCA121), sondern der definierte Leerwert. Analog
// uUninitVar.MANAGED_TYPE_PREFIXES + Interface-Heuristik (I+Grossbuchstabe) +
// dynamisches Array (TArray<...>).
function IsManagedReturnType(const TypeRef: string): Boolean;
const
  MGD : array[0..12] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring', 'widestring',
    'rawutf8', 'rawjson', 'synunicode', 'variant', 'olevariant',
    'tbtstring', 'tbtwidestring', 'tarray<');
var
  RetType, Low, P : string;
begin
  Result := False;
  RetType := ExtractReturnType(TypeRef);
  if RetType = '' then Exit;
  Low := LowerCase(RetType);
  for P in MGD do
    if Low.StartsWith(P) then Exit(True);
  // Interface: 'I' + Grossbuchstabe (refcounted, auto-nil). 'Integer'/'Int64'
  // (I + Kleinbuchstabe) matchen NICHT.
  if (Length(RetType) >= 2) and (RetType[1] = 'I') and
     CharInSet(RetType[2], ['A'..'Z']) then
    Exit(True);
end;

class procedure TRoutineResultAssignedDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  ANoReturnLow: TDictionary<string, Boolean>);
var
  TypeRef    : string;
  FnNameLow  : string;
  Exits      : TList<TAstNode>;
  Raises     : TList<TAstNode>;
  Assigns    : TList<TAstNode>;
  N          : TAstNode;
  LhsLow     : string;
  HasResult  : Boolean;
  F          : TLeakFinding;
begin
  TypeRef := MethodNode.TypeRef;
  if not IsFunctionMethod(TypeRef) then Exit;     // procedure -> skip
  if IsBodyless(TypeRef) then Exit;               // abstract/forward/external

  // FP-Gate 2026-07-31 (30%-Real-World-Audit, FP-Klasse "asm-/assembler-
  // Routinen"): 'assembler'-Direktive -> der Rueckgabewert wird per Register
  // (EAX bzw. DX:AX) gesetzt, eine textuelle Result-Zuweisung existiert
  // naturgemaess nie. Die Direktive landet als ';assembler' im TypeRef
  // (uParser2.ParseMethodDirectives, KnownConventions). Trigger: RxDBExplorer
  // HexDump.LongMulDiv - reiner asm-Rumpf mit lokaler var-Sektion, die
  // HasBodyStatement True machte.
  if Pos(';assembler', LowerCase(TypeRef)) > 0 then Exit;

  // Interface-Method-Deklaration / Klassen-Method-Deklaration im Typ-Section
  // -> kein Body, Implementation kommt anderswo. Nicht flaggen.
  if not HasBodyStatement(MethodNode) then Exit;

  // FP-Gate 2026-07-31 (FP-Klasse "Interface-Deklaration statt Implementation
  // geankert"): nur Routinen mit eigenem geparsten begin..end-Rumpf pruefen -
  // Begruendung siehe HasOwnBodyBlock.
  if not HasOwnBodyBlock(MethodNode) then Exit;

  // Recharakterisierung after30 (2026-07-12): MANAGED-Return-Typ (auto-init
  // ''/nil/Unassigned) + EFFEKTIV LEERER Body -> der Return-Wert ist NICHT
  // "undefined" (der Kern-Claim von SCA121), sondern der definierte Leerwert;
  // ein leerer Stub/abstract-Default ist idiomatisch (CnSelectionCodeTool u.a.).
  // KRITISCH TP-safe: nur bei LEEREM Body. Ein managed-Return MIT Statements
  // (rechnet, vergisst aber Result:=) bleibt ein echter "forgot Result:="-Bug.
  if IsManagedReturnType(TypeRef) and IsEffectivelyEmptyBody(MethodNode) then Exit;

  // 'absolute Result'-Alias: Schreibzugriffe laufen ueber den Alias-Namen,
  // nie ueber 'Result' -> sonst FP.
  if HasAbsoluteResultAlias(MethodNode) then Exit;

  // Body-Inhalt: jedes Exit oder Raise reicht als Skip-Grund.
  Exits := MethodNode.FindAll(nkExit);
  try
    if Exits.Count > 0 then Exit;
  finally
    Exits.Free;
  end;

  Raises := MethodNode.FindAll(nkRaise);
  try
    if Raises.Count > 0 then Exit;
  finally
    Raises.Free;
  end;

  // FP-Fix: Call-Helper die intern raisen (RaiseNotImplemented, Abort,
  // RaiseLastOSError, NotImplemented, ...) sind semantisch aequivalent zu
  // einem nkRaise - Methode kehrt nicht regulaer zurueck. Body-Calls
  // pruefen, wenn der Name auf die ueblichen Verdaechtigen passt.
  // Trigger-Audit: delphimvcframework Serializer-Stubs:
  //   function ... ; begin RaiseNotImplemented; end;
  var RaiseHelperCalls : TList<TAstNode> := MethodNode.FindAll(nkCall);
  try
    for N in RaiseHelperCalls do
    begin
      var CallNameLow := LowerCase(N.Name);
      // Qualifizierten Praefix abschneiden: 'Self.RaiseNotImplemented' -> 'raisenotimplemented'.
      var DotPos := LastDelimiter('.', CallNameLow);
      if DotPos > 0 then CallNameLow := Copy(CallNameLow, DotPos + 1, MaxInt);
      // Args/Paren abschneiden.
      var ParenPos := Pos('(', CallNameLow);
      if ParenPos > 0 then CallNameLow := Copy(CallNameLow, 1, ParenPos - 1);
      CallNameLow := Trim(CallNameLow);
      if (CallNameLow = 'abort') or
         (CallNameLow = 'raiselastoserror') or
         (CallNameLow = 'notimplemented') or
         StartsText('raise', CallNameLow) or
         // `noreturn`-Routine dieser Unit: der Compiler garantiert, dass sie nie
         // zurueckkehrt -> raise-aequivalent, kein "vergessenes Result:=".
         ((ANoReturnLow <> nil) and ANoReturnLow.ContainsKey(CallNameLow)) then
        Exit;
    end;
  finally
    RaiseHelperCalls.Free;
  end;

  // Pruefe alle nkAssign auf LHS = 'result' oder <FunctionName>.
  FnNameLow := LowerCase(TDetectorUtils.UnqualifiedNameLast(MethodNode.Name));
  HasResult := False;

  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      LhsLow := NormalizeLhs(N.Name);
      // result als LHS-Head (Result / Result.Field / Result[i] / Result^)
      // ODER irgendwo word-bounded in der LHS - faengt Typecast- und
      // Pointer-Cast-LHS: `TColorRec(Result).R := ...`,
      // `PInteger(@Result)^ := ...`. Result steht dort IN den Klammern, der
      // Prefix-Check allein verfehlt es. Real-World-FP 2026-06-23.
      if IsResultLhs(LhsLow, FnNameLow) or
         ContainsIdentifier(LhsLow, 'result') or
         ((FnNameLow <> '') and ContainsIdentifier(LhsLow, FnNameLow)) then
      begin
        HasResult := True;
        Break;
      end;
    end;
  finally
    Assigns.Free;
  end;

  // Ergaenzung: Result koennte auch via var/out-Parameter an einen Call
  // geschrieben werden (`TryGetValue(Key, Result)`, `TryStrToInt(s, Result)`,
  // ...). Lexisch nicht von by-value-Pass unterscheidbar; konservativ als
  // potentielle Zuweisung behandeln um FP-Cluster zu eliminieren.
  if not HasResult then
  begin
    Assigns := MethodNode.FindAll(nkCall);
    try
      for N in Assigns do
        if CallPassesResultAsArg(N, FnNameLow) then
        begin
          HasResult := True;
          Break;
        end;
    finally
      Assigns.Free;
    end;
  end;

  // Ergaenzung 2: 'Result.<method>(...)' ist ein Method-Call AM Result -
  // setzt es semantisch (DUnitX.Utils NameFld -> 'Result.SetData(@Name)',
  // mORMot 'Result.Init(...)'). Lexisch behandeln wir es als Result-Write.
  if not HasResult then
  begin
    Assigns := MethodNode.FindAll(nkCall);
    try
      for N in Assigns do
      begin
        var CallNameLow := LowerCase(N.Name);
        // 'Result.<method>(...)' setzt Result lexisch. AUCH 'with Result do
        // ...': der Parser legt das with-Target als nkCall mit Name='Result'
        // (bzw. 'Result Foo' bei 'with Result.Foo do') ab. Real-World
        // 2026-06-26: Alcinoe TALFBXClientSQLParam.Create
        // 'with result do begin Value:=''''; IsNull:=false; end;'.
        if (CallNameLow = 'result') or
           StartsStr('result.', CallNameLow) or
           StartsStr('result ', CallNameLow) then
        begin
          HasResult := True;
          Break;
        end;
      end;
    finally
      Assigns.Free;
    end;
  end;

  // Ergaenzung 3 (Real-World-FP-Audit 2026-07-10): Result als out/var-Argument
  // eines Calls in einer BEDINGUNG ('if Supports(v, IFoo, Result) then'),
  // '@Result' (Adresse an einen fuellenden Callee) oder eine parser-verpasste
  // 'result :='-Zuweisung. Der Parser legt solche Ausdruecke als TypeRef-String
  // ab, nicht als nkCall/nkAssign -> von den obigen Checks verfehlt.
  if not HasResult and AnyNodeStringWritesResult(MethodNode, FnNameLow) then
    HasResult := True;

  if HasResult then Exit;

  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethodNode.Name;
  F.LineNumber := IntToStr(MethodNode.Line);
  F.MissingVar := Format(
    'Function %s never assigns Result (return value undefined)',
    [TDetectorUtils.UnqualifiedNameLast(MethodNode.Name)]);
  F.SetKind(fkRoutineResultUnassigned);
  Results.Add(F);
end;

// ===========================================================================
// Quelltext-Gates (30%-Real-World-Audit, 2026-07-31)
// ---------------------------------------------------------------------------
// Drei der Audit-FP-Klassen tragen ihre Evidenz NICHT im AST - dort ist sie
// strukturell nicht vorhanden, nicht bloss schlecht erreichbar:
//   (1) asm-Rumpf: uParser2 emittiert fuer `asm ... end` KEINE Knoten (der
//       tkKwAsm-Zweig skippt bis zum `end`); Result kommt per Register.
//   (2) Result als var/out-Argument: `Stream.Read(Result, SizeOf(Result))` -
//       `Read` ist ein Keyword-Token, ParsePrimary bricht die Suffix-Kette
//       hinter dem Punkt ab, die Argumentliste landet nie im nkCall-Namen.
//   (4) IFDEF-Twin im if-Kopf: `... then {$ELSE} ... then {$ENDIF}` ergibt
//       nach dem Direktiven-Strip ZWEI `then` zu EINEM `if`; der Parser
//       verliert dabei die Zweige mit den Result-Zuweisungen.
// Deshalb prueft AnalyzeUnit die Kandidaten am Ende gegen den Quelltext.
// SCAN-BEREICH (Fix 2026-07-31, Review-Fund Z.922): Kopfzeile bis zum naechsten
// TOP-LEVEL-Routinenkopf, ABZUEGLICH der nkNestedRange-Spans - ein `Result` in
// einer verschachtelten Routine ist das Result JENER Routine und darf den Fund
// der aeusseren Funktion nicht stillstellen.
// Streng additiv: die Gates koennen nur unterdruecken, nie melden. Der
// Datei-Zugriff passiert LAZY - nur wenn ueberhaupt ein Kandidat existiert
// (Real-World: 156 Funde auf 12821 Dateien) - und laeuft ueber den
// Prozess-Text-Cache, ist im Scan also praktisch kostenlos.
// AUSGEKLAMMERT: die FP-Klasse "Label-Statements/goto im Body" braucht einen
// nkLabel-Knoten im Parser (eigenes Inkrement, Hebel D).
// ===========================================================================

// Fix 2026-07-31 (Pre-Build-Review-Fund Z.922 "Quelltext-Gates scannen den
// Bereich verschachtelter Routinen mit"): uParser2.ParseMethodImpl (Z.1566ff)
// parst nested routines, verwirft sie aus dem AST und haengt fuer jede einen
// nkNestedRange-Marker an den Methodenknoten (Line = Startzeile, TypeRef =
// Endzeile). Ohne diese Grenzen reichte der Quelltext-Bereich einer Routine vom
// Kopf bis zum naechsten TOP-LEVEL-Kopf und schloss den ganzen Deklarationsteil
// samt nested routines ein - ein `Inc(Result)` DORT gehoert der nested function
// und stellte den echten Bug der AEUSSEREN Funktion still (TES5Edit
// Sniff/Proc/ProcFindDrawCalls.pas:77 u.a.: Error-Tier-TP-Verlust).
procedure CollectNestedSpans(AMethod: TAstNode;
  var AStarts, AEnds: TArray<Integer>);
var
  Ch  : TAstNode;
  Cnt : Integer;
begin
  AStarts := nil;
  AEnds   := nil;
  if AMethod = nil then Exit;
  Cnt := 0;
  for Ch in AMethod.Children do
    if Ch.Kind = nkNestedRange then
    begin
      Inc(Cnt);
      SetLength(AStarts, Cnt);
      SetLength(AEnds,   Cnt);
      AStarts[Cnt - 1] := Ch.Line;
      AEnds[Cnt - 1]   := StrToIntDef(Ch.TypeRef, Ch.Line);
      if AEnds[Cnt - 1] < AStarts[Cnt - 1] then
        AEnds[Cnt - 1] := AStarts[Cnt - 1];
    end;
end;

function LineIsInNestedSpan(ALine: Integer;
  const AStarts, AEnds: TArray<Integer>): Boolean;
var
  k : Integer;
begin
  for k := 0 to High(AStarts) do
    if (ALine >= AStarts[k]) and (ALine <= AEnds[k]) then Exit(True);
  Result := False;
end;

// True wenn die bereits bereinigte, lowercase Zeile wie ein Routinen-KOPF
// aussieht (`procedure|function|constructor|destructor|operator` + Whitespace +
// Bezeichner). Prozedur-TYPEN (`procedure of object`, `function(...)`) treffen
// bewusst nicht.
// Fix 2026-07-31 (Review-Fund Z.922, Sicherungsnetz): steht im Scan-Bereich ein
// solcher Kopf, den KEIN nkNestedRange-Marker abdeckt (Parser-Desync, nested
// forward-Deklaration), laesst sich der eigene Rumpf nicht sicher abgrenzen ->
// die Gates werden fuer diesen Kandidaten abgeschaltet statt zu raten. Der
// Aufrufer wertet nur Zeilen HINTER der Kopfzeile aus.
function CleanLineLooksLikeRoutineHead(const ALineLow: string): Boolean;
const
  KW : array[0..4] of string =
    ('procedure', 'function', 'constructor', 'destructor', 'operator');
var
  T, Rest : string;
  k, p    : Integer;
begin
  Result := False;
  T := TrimLeft(ALineLow);
  if StartsStr('class ', T) then T := TrimLeft(Copy(T, 7, MaxInt));
  for k := 0 to High(KW) do
    if StartsStr(KW[k] + ' ', T) then
    begin
      Rest := TrimLeft(Copy(T, Length(KW[k]) + 1, MaxInt));
      if (Rest = '') or not IsIdentChar(Rest[1]) then Exit(False);
      p := 1;
      while (p <= Length(Rest)) and IsIdentChar(Rest[p]) do Inc(p);
      // `procedure of object` / `function of object` = Typ, kein Routinen-Kopf
      if Copy(Rest, 1, p - 1) = 'of' then Exit(False);
      Exit(True);
    end;
end;

// Liefert die Zeilen [AFrom..ATo] (1-basiert, inklusiv) als EINEN lowercase-
// String, in dem Kommentare, Compiler-Direktiven ({$IFDEF} ist fuer den Lexer
// ein Kommentar) und String-Literale durch ein Leerzeichen ersetzt sind.
// Zeilenwechsel werden zu Leerzeichen, damit zeilenuebergreifende
// Argumentlisten (`Foo(` / newline / `Result, ...`) zusammenhaengend pruefbar
// sind. Bewusst dieselbe Zeichen-/Kommentarklassifikation wie uInlineAssembly.
// Fix 2026-07-31 (Review-Fund Z.922): Zeilen innerhalb der nkNestedRange-Spans
// [ASkipStarts..ASkipEnds] gehoeren zu einer verschachtelten Routine und werden
// NICHT in den Text uebernommen - ihre Zeichen laufen trotzdem durch die
// Kommentar-Statemachine, damit ein zeilenuebergreifender Kommentar korrekt
// bleibt. AUncoveredNested meldet einen Routinen-Kopf hinter AFrom, den kein
// Span abdeckt (dann kann der Aufrufer die Abgrenzung nicht garantieren).
function CleanRangeText(Lines: TStringList; AFrom, ATo: Integer;
  const ASkipStarts, ASkipEnds: TArray<Integer>;
  out AUncoveredNested: Boolean): string;
var
  SB, LineSB  : TStringBuilder;
  i, j, n, p  : Integer;
  Line, Clean : string;
  InBlock     : Boolean;   // offener {...}-Kommentar ueber Zeilengrenze
  InParenStar : Boolean;   // offener (*...*)-Kommentar ueber Zeilengrenze
  C           : Char;
begin
  Result           := '';
  AUncoveredNested := False;
  if Lines = nil then Exit;
  if AFrom < 1 then AFrom := 1;
  if ATo > Lines.Count then ATo := Lines.Count;
  if ATo < AFrom then Exit;

  SB     := TStringBuilder.Create;
  LineSB := TStringBuilder.Create;
  try
    InBlock     := False;
    InParenStar := False;
    for i := AFrom to ATo do
    begin
      LineSB.Clear;
      Line := Lines[i - 1];
      n    := Length(Line);
      j    := 1;
      while j <= n do
      begin
        if InBlock then
        begin
          p := PosEx('}', Line, j);
          if p = 0 then Break;
          InBlock := False;
          j := p + 1;
          Continue;
        end;
        if InParenStar then
        begin
          p := PosEx('*)', Line, j);
          if p = 0 then Break;
          InParenStar := False;
          j := p + 2;
          Continue;
        end;
        C := Line[j];
        if C = '{' then
        begin
          p := PosEx('}', Line, j + 1);
          if p = 0 then begin InBlock := True; Break; end;
          LineSB.Append(' ');
          j := p + 1;
          Continue;
        end;
        if (C = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          p := PosEx('*)', Line, j + 2);
          if p = 0 then begin InParenStar := True; Break; end;
          LineSB.Append(' ');
          j := p + 2;
          Continue;
        end;
        if (C = '/') and (j < n) and (Line[j + 1] = '/') then Break;  // Zeilenrest
        if C = '''' then
        begin
          Inc(j);                                   // oeffnendes Quote
          while j <= n do
            if Line[j] = '''' then
            begin
              if (j < n) and (Line[j + 1] = '''') then Inc(j, 2)      // '' im Literal
              else begin Inc(j); Break; end;
            end
            else
              Inc(j);
          LineSB.Append(' ');
          Continue;
        end;
        LineSB.Append(C);
        Inc(j);
      end;
      // Verschachtelte Routine -> Zeile verwerfen (Kommentar-Status ist oben
      // trotzdem fortgeschrieben worden). Kein Trennzeichen noetig: jede
      // uebernommene Zeile endet bereits mit einem Leerzeichen.
      if LineIsInNestedSpan(i, ASkipStarts, ASkipEnds) then Continue;
      Clean := LowerCase(LineSB.ToString);
      if (i > AFrom) and CleanLineLooksLikeRoutineHead(Clean) then
        AUncoveredNested := True;
      SB.Append(Clean);
      SB.Append(' ');                               // Zeilenende = Wortgrenze
    end;
    Result := SB.ToString;                          // bereits lowercase
  finally
    LineSB.Free;
    SB.Free;
  end;
end;

// Zaehlt wortgetrennte Vorkommen von NeedleLow in HayLow (beide lowercase).
function CountWordOccurrences(const HayLow, NeedleLow: string): Integer;
var
  p, nl, hl : Integer;
begin
  Result := 0;
  nl := Length(NeedleLow);
  hl := Length(HayLow);
  if (nl = 0) or (hl = 0) then Exit;
  p := Pos(NeedleLow, HayLow);
  while p > 0 do
  begin
    if ((p = 1) or not IsIdentChar(HayLow[p - 1])) and
       ((p + nl > hl) or not IsIdentChar(HayLow[p + nl])) then
      Inc(Result);
    p := PosEx(NeedleLow, HayLow, p + 1);
  end;
end;

// FP-Klasse (2) "Result als var/out-Argument": True wenn WordLow im Quelltext
// in ARGUMENT-Position eines Calls steht - `,result` / `ident(result` /
// `@result`. Reine Klammer-Gruppierung (`if (Result > 0) then`) trifft NICHT:
// vor der Klammer steht dort kein Identifier-Zeichen. Dieselbe Klassifikation
// wie ExprWritesOrPassesResult (AST-Strings), nur eben auf dem Quelltext, weil
// der Parser die Argumentliste bei Keyword-Membern (`Stream.Read(...)`)
// verliert.
// BEWUSST OHNE das `result :=`-Muster: parser-verpasste Zuweisungen hinter
// Label-Statements sind eine eigene FP-Klasse (Hebel D, braucht nkLabel).
// Konservativ wie der bestehende Call-Arg-Guard: `Length(Result)` liest nur,
// wird aber ebenfalls als potentielle Zuweisung gewertet (kleines FN, dafuer
// kein FP) - identische Politik wie CallPassesResultAsArg.
function SourceWordIsCallArg(const SLow, WordLow: string): Boolean;
var
  i, k, n, wl : Integer;
  pc          : Char;
begin
  Result := False;
  wl := Length(WordLow);
  n  := Length(SLow);
  if (wl = 0) or (n < wl) then Exit;
  i := Pos(WordLow, SLow);
  while i > 0 do
  begin
    if ((i = 1) or not IsIdentChar(SLow[i - 1])) and
       ((i + wl > n) or not IsIdentChar(SLow[i + wl])) then
    begin
      k := i - 1;
      while (k >= 1) and (SLow[k] <= ' ') do Dec(k);
      if k >= 1 then pc := SLow[k] else pc := #0;
      if (pc = '@') or (pc = ',') then Exit(True);
      if (pc = '(') and (k >= 2) and IsIdentChar(SLow[k - 1]) then Exit(True);
    end;
    i := PosEx(WordLow, SLow, i + 1);
  end;
end;

// FP-Klasse (4) "IFDEF-Twin im if-Kopf": in Pascal gehoert zu JEDEM `then`
// genau ein `if`. Ein `then`-Ueberschuss im Routinen-Bereich entsteht nur,
// wenn der Direktiven-Strip zwei Zweige EINES Bedingungskopfes hintereinander
// sichtbar macht (`... then {$ELSE} ... then {$ENDIF}`) - genau dort verliert
// der Parser die then/else-Zweige samt Result-Zuweisungen (JvMemDS
// FindFieldData). Der umgekehrte Fall (mehr `if` als `then`, z.B. wenn nur ein
// Zweig ein `if` enthaelt) loest bewusst NICHT aus.
function SourceHasIfdefThenTwin(const SLow: string): Boolean;
begin
  Result := CountWordOccurrences(SLow, 'then') > CountWordOccurrences(SLow, 'if');
end;

// Obergrenze der Quelltext-Reichweite einer Routine: Zeile des naechsten
// Routinen-Kopfes minus 1 (bzw. AMaxLine am Datei-Ende). Der AST-Teilbaum
// taugt als Grenze NICHT - bei genau den Parse-Schaeden, die diese FPs
// erzeugen, fehlen ihm die hinteren Zeilen (JvMemDS: die verlorenen
// then/else-Zweige liegen HINTER dem letzten Knoten der Routine).
function NextRoutineHeadLine(Methods: TList<TAstNode>; ALine, AMaxLine: Integer): Integer;
var
  M    : TAstNode;
  Best : Integer;
begin
  Best := 0;
  for M in Methods do
    if (M.Line > ALine) and ((Best = 0) or (M.Line < Best)) then Best := M.Line;
  if Best = 0 then Result := AMaxLine else Result := Best - 1;
end;

class procedure TRoutineResultAssignedDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
// FP-Fix: PScript-Stub-File-Pattern erkennen. Files wie
// cnwizards/Bin/PSDeclEx/CnWizUtils.pas haben dutzende von
// `function Foo: T; begin end;` als Pascal-Script-Bridge-Stubs;
// kein echter Bug, sondern File-Konvention. Wenn die ueberwiegende
// Mehrheit aller Function-Bodies effektiv leer ist UND mindestens
// 5 Treffer existieren, ueberspringen wir die Unit komplett.
// (Audit 2026-06-13: cnwizards CnWizUtils 199 -> 0, CnCommon 165 -> 0
// etc. Threshold konservativ: kleine Files mit 1-3 leeren Stubs
// werden weiter geflagged - selten und meistens echte Bugs.)
const
  STUB_FILE_MIN_EMPTY   = 5;
  STUB_FILE_RATIO_LIMIT = 0.7;
var
  Methods           : TList<TAstNode>;
  M                 : TAstNode;
  EmptyCount, Total : Integer;
  NoReturnLow       : TDictionary<string, Boolean>;
  Cands             : TObjectList<TLeakFinding>;
  CandNodes         : TList<TAstNode>;
  Keep              : TArray<Boolean>;
  Lines             : TStringList;
  Cached            : Boolean;
  i, EndLine        : Integer;
  RangeLow          : string;
  NStarts, NEnds    : TArray<Integer>;   // nkNestedRange-Spans (2026-07-31)
  UncoveredNested   : Boolean;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    EmptyCount := 0;
    Total      := 0;
    for M in Methods do
    begin
      if not IsFunctionMethod(M.TypeRef) then Continue;
      if IsBodyless(M.TypeRef) then Continue;
      if not HasBodyStatement(M) then Continue;
      Inc(Total);
      if IsEffectivelyEmptyBody(M) then Inc(EmptyCount);
    end;
    if (EmptyCount >= STUB_FILE_MIN_EMPTY) and (Total > 0) and
       (EmptyCount / Total > STUB_FILE_RATIO_LIMIT) then
      Exit;  // PScript-Stub-File - keine Findings emittieren

    // `noreturn`-Routinen dieser Unit einsammeln (Delphi-12-Direktive; landet via
    // ParseMethodDirectives als ';noreturn' im TypeRef). Ein Body-Call darauf ist
    // raise-aequivalent -> die aufrufende Funktion kehrt nie regulaer zurueck.
    // Praezise statt namens-heuristisch: der Compiler garantiert die Semantik.
    // Real-World-Trigger: Alcinoe.JSONDoc `AlJSONDocErrorA(...); noreturn;` -
    // 62 SCA121-FPs allein in dieser Unit.
    NoReturnLow := TDictionary<string, Boolean>.Create;
    try
      for M in Methods do
        if Pos(';noreturn', LowerCase(M.TypeRef)) > 0 then
        begin
          var NmLow := LowerCase(TDetectorUtils.UnqualifiedNameLast(M.Name));
          if NmLow <> '' then NoReturnLow.AddOrSetValue(NmLow, True);
        end;

      // Kandidaten zuerst SEPARAT sammeln (mit dem erzeugenden Methodenknoten
      // im Gleichschritt), damit die Quelltext-Gates darunter jeden Fund seiner
      // Routine zuordnen koennen. AnalyzeMethod emittiert hoechstens einen Fund
      // pro Methode; die while-Kopplung ist gegen kuenftige Mehrfach-Funde
      // robust.
      Cands     := TObjectList<TLeakFinding>.Create(True);
      CandNodes := TList<TAstNode>.Create;
      try
        for M in Methods do
        begin
          AnalyzeMethod(M, FileName, Cands, NoReturnLow);
          while CandNodes.Count < Cands.Count do CandNodes.Add(M);
        end;
        if Cands.Count = 0 then Exit;   // kein Kandidat -> kein Datei-Zugriff

        // Quelltext-Gates (2026-07-31, s. Block-Kommentar oben). Lines = nil
        // (Datei nicht lesbar / In-Memory-Analyse) -> Gates inaktiv, Verhalten
        // exakt wie vorher.
        Lines := AcquireLines(FileName, Cached);
        try
          SetLength(Keep, Cands.Count);
          for i := 0 to Cands.Count - 1 do
          begin
            Keep[i] := True;
            if Lines = nil then Continue;
            M := CandNodes[i];
            if (M.Line < 1) or (M.Line > Lines.Count) then Continue;
            // Sicherung gegen Datei/AST-Divergenz (falscher Pfad, veraltete
            // Zeilen): der Routinen-Name MUSS in der Kopfzeile stehen. Sonst
            // gehoert der Text nicht zu diesem Knoten -> Gates aus statt raten.
            if Pos(LowerCase(TDetectorUtils.UnqualifiedNameLast(M.Name)),
                   LowerCase(Lines[M.Line - 1])) = 0 then Continue;

            EndLine  := NextRoutineHeadLine(Methods, M.Line, Lines.Count);
            // Fix 2026-07-31 (Review-Fund Z.922): der Bereich reicht bis zum
            // naechsten TOP-LEVEL-Kopf und enthaelt damit auch den kompletten
            // Deklarationsteil. Die verschachtelten Routinen darin gehoeren
            // NICHT zum eigenen Rumpf - ihr `Result` ist ein fremdes. Der
            // Parser liefert die exakten Grenzen als nkNestedRange-Marker.
            CollectNestedSpans(M, NStarts, NEnds);
            RangeLow := CleanRangeText(Lines, M.Line, EndLine,
                                       NStarts, NEnds, UncoveredNested);
            // Kein Marker fuer einen sichtbaren Routinen-Kopf im Bereich ->
            // der eigene Rumpf ist nicht sicher abgrenzbar. Konservativ: Gates
            // aus (kein Drop) statt einen fremden Rumpf mitzuscannen.
            if UncoveredNested then Continue;

            // (1) asm-Block im Rumpf -> Result kommt per Register.
            if CountWordOccurrences(RangeLow, 'asm') > 0 then
            begin
              Keep[i] := False;
              Continue;
            end;
            // (2) Result in Argument-Position eines Calls (var/out/@).
            if SourceWordIsCallArg(RangeLow, 'result') then
            begin
              Keep[i] := False;
              Continue;
            end;
            // (4) IFDEF-Twin im Bedingungskopf (zweifaches 'then').
            if SourceHasIfdefThenTwin(RangeLow) then
              Keep[i] := False;
          end;
        finally
          ReleaseLines(Lines, Cached);
        end;

        // Ownership-Uebergabe: ab hier besitzt Cands die Funde nicht mehr -
        // jeder wandert entweder nach Results oder wird hier freigegeben.
        // Bewusst NACH der Gate-Schleife (die kann werfen, dieser Teil nicht).
        Cands.OwnsObjects := False;
        for i := 0 to Cands.Count - 1 do
          if Keep[i] then Results.Add(Cands[i])
          else Cands[i].Free;
      finally
        CandNodes.Free;
        Cands.Free;
      end;
    finally
      NoReturnLow.Free;
    end;
  finally
    Methods.Free;
  end;
end;

end.
