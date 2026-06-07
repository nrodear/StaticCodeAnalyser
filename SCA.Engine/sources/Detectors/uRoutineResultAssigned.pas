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
  uAstNode, uSCAConsts, uMethodd12;

type
  TRoutineResultAssignedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

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

// Letztes Segment eines qualifizierten Methodennamens.
// 'TFoo.Bar' -> 'Bar'; 'Bar' -> 'Bar'; 'TFoo<T>.Bar' -> 'Bar'.
function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

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
  Result := CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
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

class procedure TRoutineResultAssignedDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
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
  // Interface-Method-Deklaration / Klassen-Method-Deklaration im Typ-Section
  // -> kein Body, Implementation kommt anderswo. Nicht flaggen.
  if not HasBodyStatement(MethodNode) then Exit;

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
         StartsText('raise', CallNameLow) then
        Exit;
    end;
  finally
    RaiseHelperCalls.Free;
  end;

  // Pruefe alle nkAssign auf LHS = 'result' oder <FunctionName>.
  FnNameLow := LowerCase(UnqualifiedName(MethodNode.Name));
  HasResult := False;

  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      LhsLow := NormalizeLhs(N.Name);
      if IsResultLhs(LhsLow, FnNameLow) then
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

  if HasResult then Exit;

  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethodNode.Name;
  F.LineNumber := IntToStr(MethodNode.Line);
  F.MissingVar := Format(
    'Function %s never assigns Result (return value undefined)',
    [UnqualifiedName(MethodNode.Name)]);
  F.SetKind(fkRoutineResultUnassigned);
  Results.Add(F);
end;

class procedure TRoutineResultAssignedDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
