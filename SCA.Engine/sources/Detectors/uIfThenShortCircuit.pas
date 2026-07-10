unit uIfThenShortCircuit;

// Detektor: `IfThen(cond, A(), B())` - sieht aus wie if-then-else, aber
// die "Arme" sind FUNCTION ARGUMENTS und werden BEIDE evaluiert,
// unabhaengig von cond.
//
// Pattern (Bug / Performance / Side-Effects):
//   x := Math.IfThen(IsCacheHit, FetchFromCache, FetchFromDb);
//   //                          ^^^^^^^^^^^^^^  ^^^^^^^^^^^^
//   //                          beide Calls laufen IMMER!
//
//   x := IfThen(WantSafeMode, RiskyOperation, SafeOperation);
//   //                        ^^^^^^^^^^^^^^  RiskyOp laeuft AUCH wenn
//   //                                        WantSafeMode True ist!
//
// Korrekt: klassisches if-then-else mit Short-Circuit-Semantik.
//   if IsCacheHit then
//     x := FetchFromCache
//   else
//     x := FetchFromDb;
//
// Warum: Sowohl `Math.IfThen` (Integer/Double) als auch `StrUtils.IfThen`
// (String) sind normale Funktionen mit drei Argumenten. Pascal-Calling-
// Conventions evaluieren alle Argumente VOR dem Call. Die Funktion erhaelt
// nur die fertigen Werte - sie kann den nicht-gewaehlten Pfad nicht mehr
// "ueberspringen". Bei Funktionen mit Side-Effects (DB-Read, File-IO,
// State-Mutation) oder schwerer Performance fuehrt das zu Bugs.
//
// Erkennung (AST-basiert):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn der Call-Name dem Pattern `IfThen(...)` entspricht
//     (auch qualifiziert: `Math.IfThen`, `StrUtils.IfThen`).
//   * Innerhalb der Argument-Liste: pruefe ob nested `(...)` vorkommt,
//     d.h. einer der Arme ist ein Funktions-/Method-Call.
//   * String-Literale werden vor der Klammern-Zaehlung entfernt -
//     `IfThen(c, 'a(b)', 'x')` ist kein Funktions-Call.
//
// Sonar-Pendant: IfThenShortCircuitCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   IfThenShortCircuitCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TIfThenShortCircuitDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// True wenn CallName ein IfThen-Call ist (bare `IfThen(` oder qualifiziert
// `Math.IfThen(` / `StrUtils.IfThen(` / `System.Math.IfThen(` ...).
function IsIfThenCall(const CallName: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(TrimLeft(CallName));
  Result := (Pos('ifthen(',         Lower) = 1) or
            (Pos('math.ifthen(',    Lower) > 0) or
            (Pos('strutils.ifthen(', Lower) > 0);
  // Defensive: `xifthen(` wuerde matchen via `ifthen(` Substring-Pos=2+,
  // aber das schliessen wir aus (Pos = 1 only fuer den bare-Case).
  if not Result then Exit;
  // Pruefe dass keine Identifier-Zeichen vor 'ifthen(' stehen wenn der
  // Match nicht am Anfang ist.
  if Pos('ifthen(', Lower) = 1 then Exit(True);
  // Qualifiziert: muss '.ifthen(' sein, kein 'xifthen('.
  Result := (Pos('.ifthen(', Lower) > 0);
end;

// Extrahiert den Args-Teil zwischen aeusserer '(' und schliessender ')'.
// Geht von balancierten Parens aus.
function ExtractOuterArgs(const CallName: string): string;
var
  Open, Close, Depth, i : Integer;
begin
  Result := '';
  Open := Pos('(', CallName);
  if Open <= 0 then Exit;
  Depth := 0;
  Close := 0;
  for i := Open to Length(CallName) do
  begin
    case CallName[i] of
      '(': Inc(Depth);
      ')': begin
             Dec(Depth);
             if Depth = 0 then
             begin
               Close := i;
               Break;
             end;
           end;
    end;
  end;
  if Close <= Open then Exit;
  Result := Copy(CallName, Open + 1, Close - Open - 1);
end;

// Splittet den Args-String an TOP-LEVEL-Kommas (respektiert nested Parens +
// String-Literale). IfThen(cond, a, b) -> ['cond', ' a', ' b'].
function SplitTopLevelArgs(const Args: string): TArray<string>;
var
  parts : TList<string>;
  i, depth, start : Integer;
  inStr : Boolean;
  c : Char;
begin
  parts := TList<string>.Create;
  try
    depth := 0; inStr := False; start := 1;
    for i := 1 to Length(Args) do
    begin
      c := Args[i];
      if inStr then
      begin
        if c = '''' then inStr := False;
      end
      else if c = '''' then inStr := True
      else if c = '(' then Inc(depth)
      else if c = ')' then Dec(depth)
      else if (c = ',') and (depth = 0) then
      begin
        parts.Add(Copy(Args, start, i - start));
        start := i + 1;
      end;
    end;
    parts.Add(Copy(Args, start, Length(Args) - start + 1));
    Result := parts.ToArray;
  finally
    parts.Free;
  end;
end;

// Lowercased Identifier direkt vor '(' an ParenPos; '' bei Grouping-Paren
// '(expr)' (dann steht kein Bezeichner unmittelbar davor).
function IdentBeforeParen(const S: string; ParenPos: Integer): string;
var
  e, b : Integer;
begin
  Result := '';
  e := ParenPos - 1;
  while (e >= 1) and CharInSet(S[e], [' ', #9]) do Dec(e);
  b := e;
  while (b >= 1) and CharInSet(S[b], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Dec(b);
  if e >= b + 1 then Result := LowerCase(Copy(S, b + 1, e - b));
end;

function IsPureBuiltin(const IdentLow: string): Boolean;
const
  PURE : array[0..23] of string = (
    'copy', 'ord', 'chr', 'length', 'high', 'low', 'sizeof', 'abs', 'sqr',
    'succ', 'pred', 'trunc', 'round', 'frac', 'int', 'inttostr', 'inttohex',
    'floattostr', 'strtoint', 'uppercase', 'lowercase', 'trim', 'pos', 'assigned');
var
  S : string;
begin
  Result := False;
  for S in PURE do
    if IdentLow = S then Exit(True);
end;

// True wenn EIN VALUE-Branch (2./3. Argument, NICHT die Kondition) einen
// SEITENEFFEKT-Call enthaelt: ein '(' das von einem Bezeichner (Call) angefuehrt
// wird und KEIN reiner RTL-Builtin ist. Grouping-Parens '(expr)' und pure
// Builtins (Copy/Ord/Length/...) zaehlen nicht. Real-World-FP-Audit 2026-07-10:
// die Kondition laeuft ohnehin einmal, konstante/arithmetische Value-Arme sind
// harmlos (dominante SCA131-FP-Klasse).
function ValueBranchHasSideEffectCall(const Args: string): Boolean;
var
  parts : TArray<string>;
  k, i  : Integer;
  cleaned, id : string;
begin
  Result := False;
  parts := SplitTopLevelArgs(Args);
  if Length(parts) < 2 then Exit;   // keine Value-Branches
  for k := 1 to High(parts) do      // Index 0 = Kondition, ausgeschlossen
  begin
    cleaned := TDetectorUtils.StripStringLiterals(parts[k]);
    for i := 1 to Length(cleaned) do
      if cleaned[i] = '(' then
      begin
        id := IdentBeforeParen(cleaned, i);
        if (id <> '') and not IsPureBuiltin(id) then Exit(True);
      end;
  end;
end;

// Pruefen ob `Text` ein `IfThen(...)`-Call mit verschachteltem Call-
// Argument ist. Wird fuer nkCall (bare) UND nkAssign.TypeRef (RHS einer
// Zuweisung wie `r := IfThen(c, A(), B())`) aufgerufen - sonst silent
// miss aller Assignment-Form-Treffer (Audit V5, 2026-05-30).
procedure CheckIfThenText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  F        : TLeakFinding;
  MethName : string;
  Args     : string;
begin
  if not IsIfThenCall(Text) then Exit;
  Args := ExtractOuterArgs(Text);
  if not ValueBranchHasSideEffectCall(Args) then Exit;
  if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
  else MethName := '';
  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethName;
  F.LineNumber := IntToStr(Node.Line);
  F.MissingVar :=
    'IfThen() always evaluates both branches - use if/then/else for side-effecting calls';
  F.SetKind(fkIfThenShortCircuit);
  Results.Add(F);
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS - siehe Audit_jvcl_segfault.
type TFrame = record N, M: TAstNode; end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
  NextMeth : TAstNode;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.M := CurrentMethod;
    Stack.Add(F);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case Cur.N.Kind of
        nkCall:   CheckIfThenText(Cur.N.Name,    Cur.N, Cur.M, FileName, Results);
        nkAssign: CheckIfThenText(Cur.N.TypeRef, Cur.N, Cur.M, FileName, Results);
      end;
      if Cur.N.Kind = nkMethod then NextMeth := Cur.N else NextMeth := Cur.M;
      for i := Cur.N.Children.Count - 1 downto 0 do
      begin
        F.N := Cur.N.Children[i]; F.M := NextMeth;
        Stack.Add(F);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TIfThenShortCircuitDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
