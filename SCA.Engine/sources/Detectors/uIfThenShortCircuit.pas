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
//     (auch qualifiziert: `Math.IfThen`, `StrUtils.IfThen`) - seit
//     Voll-Review 2026-09-12 (Major 70) auch EINGEBETTET in einen
//     umgebenden Call (`ShowMessage(IfThen(...))`) bzw. eine
//     umhuellende Funktion (`x := Trim(IfThen(...))`): der Parser
//     emittiert verschachtelte Calls nicht als eigene nkCall-Knoten,
//     der Text des aeusseren Knotens ist die einzige Sicht darauf.
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

uses
  uAstSpans;   // CollectWithMethodScope (Voll-Review 2026-09-12)

// True wenn S an APos (1-basiert, Zeichen VOR einem '.') rueckwaerts auf
// das Namens-Segment ASegLow endet und davor eine Segmentgrenze steht -
// 'math' trifft 'Math.' und 'System.Math.', nicht 'MyMath.'.
function EndetAufSegment(const S: string; AEnd: Integer;
  const ASegLow: string): Boolean;
var
  b : Integer;
begin
  Result := False;
  b := AEnd - Length(ASegLow);
  if b < 0 then Exit;
  if LowerCase(Copy(S, b + 1, Length(ASegLow))) <> ASegLow then Exit;
  Result := (b = 0) or not TDetectorUtils.IsIdentChar(S[b]);
end;

// Liefert die Position der oeffnenden '(' des ERSTEN gueltigen
// IfThen-Vorkommens in Text, 0 wenn keines. Gueltig ist:
//   * bare `IfThen(` mit linker Nicht-Ident-Grenze - auch EINGEBETTET
//     als Argument eines umgebenden Calls oder in einer umhuellenden
//     Funktion (Voll-Review 2026-09-12, Major 70: der alte Anker
//     Pos=1 liess `ShowMessage(IfThen(b, 'x', LoadCfg()))` und
//     `x := Trim(IfThen(...))` komplett durchrutschen - der Parser
//     emittiert verschachtelte Calls nicht als eigene nkCall-Knoten,
//     der Text ist also die einzige Sicht auf die eingebettete Form);
//   * qualifiziert `Math.IfThen(` / `StrUtils.IfThen(` (auch
//     `System.Math.` etc.) - ein FREMDER Qualifier (`Foo.IfThen(`)
//     zaehlt weiterhin NICHT: eine fremde IfThen-Methode kann echte
//     Lazy-Semantik haben, das war schon der Vertrag des Vorgaengers.
// Suche am geblankten Text (Literale zaehlen nicht), Positionen passen
// aufs Original, weil BlankStringLiterals laengenerhaltend ist.
function FindIfThenOpenParen(const Text: string): Integer;
const
  KW = 'ifthen(';
var
  Lower : string;
  p     : Integer;
  Ok    : Boolean;
begin
  Result := 0;
  Lower := LowerCase(TDetectorUtils.BlankStringLiterals(Text));
  p := Pos(KW, Lower);
  while p > 0 do
  begin
    if (p = 1) or not (TDetectorUtils.IsIdentChar(Lower[p - 1])
                       or (Lower[p - 1] = '.')) then
      Ok := True   // bare Form an Wortgrenze
    else if Lower[p - 1] = '.' then
      Ok := EndetAufSegment(Lower, p - 1, 'math')
            or EndetAufSegment(Lower, p - 1, 'strutils')
    else
      Ok := False; // 'xifthen(' - Teil eines anderen Bezeichners
    if Ok then
      Exit(p + Length(KW) - 1);   // Position der '('
    p := Pos(KW, Lower, p + 1);
  end;
end;

// Extrahiert den Args-Teil zwischen der '(' an AOpenPos und ihrer
// schliessenden ')'. Geht von balancierten Parens aus. AOpenPos kommt
// aus FindIfThenOpenParen - vorher setzte die Extraktion an der ERSTEN
// '(' des Gesamttexts an und lieferte bei eingebetteten Formen die
// Argumente des UMHUELLENDEN Calls (ein Top-Level-Argument, Laenge<2,
// stiller Exit in ValueBranchHasSideEffectCall - Major 70).
function ExtractOuterArgs(const CallName: string; AOpenPos: Integer): string;
var
  Open, Close, Depth, i : Integer;
  Blanked : string;
begin
  Result := '';
  // Review-MEDIUM 2026-08-09: Literale blanken - '('/')' in Stringliteralen
  // duerfen die Klammertiefe nicht verschieben (laengenerhaltend, damit die
  // Copy-Positionen weiter aufs Original passen).
  Blanked := TDetectorUtils.BlankStringLiterals(CallName);
  Open := AOpenPos;
  if (Open <= 0) or (Open > Length(Blanked)) or (Blanked[Open] <> '(') then Exit;
  Depth := 0;
  Close := 0;
  for i := Open to Length(Blanked) do
  begin
    case Blanked[i] of
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

// Der Top-Level-Argument-Split lebt seit Voll-Review 2026-09-12
// (Posten 71) byte-identisch in TDetectorUtils.SplitTopLevelArgs -
// uInheritedMethodEmpty war die dritte Kopie-Anwaerterin.

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
  parts := TDetectorUtils.SplitTopLevelArgs(Args);
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
  OpenPos  : Integer;
begin
  OpenPos := FindIfThenOpenParen(Text);
  if OpenPos = 0 then Exit;
  Args := ExtractOuterArgs(Text, OpenPos);
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

procedure WalkAndCheck(Node: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Seit Voll-Review 2026-09-12 ueber den zentralen Scope-Walk
// (TAstSpans.CollectWithMethodScope) - Mechanik, Besuchsreihenfolge
// und Hardening v4 (iterative DFS, Audit_jvcl_segfault) identisch
// zur frueheren lokalen Kopie.
var
  P : TNodeScopePair;
begin
  for P in TAstSpans.CollectWithMethodScope(Node, [nkCall, nkAssign]) do
    case P.Node.Kind of
      nkCall:   CheckIfThenText(P.Node.Name,    P.Node, P.Method, FileName, Results);
      nkAssign: CheckIfThenText(P.Node.TypeRef, P.Node, P.Method, FileName, Results);
    end;
end;

class procedure TIfThenShortCircuitDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, FileName, Results);
end;

end.
