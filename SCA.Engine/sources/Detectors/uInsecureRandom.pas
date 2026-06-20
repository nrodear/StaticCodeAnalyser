unit uInsecureRandom;

// Detektor: Aufruf von Random / RandomRange / RandomFrom ohne dass im File
// irgendwo Randomize aufgerufen wird.
//
// Hintergrund: Delphi initialisiert den Random-Seed auf 0 beim Programm-
// start. Solange kein Randomize() den Seed aus dem System-Timer setzt,
// liefert Random() bei JEDEM Lauf dieselbe deterministische Sequenz.
// Typische Bugs:
//   * "Zufaellige" UI-Effekte sind in Wahrheit immer gleich
//   * Test-Daten / Mock-IDs kollidieren ueber Re-Runs hinweg
//   * Schwache "Generate-Token"-Helper liefern reproduzierbare Werte
//
// Erkennung (AST-basiert):
//   * Pass 1: nkCall mit Name == 'Randomize' irgendwo im UnitNode? Dann
//     STOP - die ganze Unit ist als initialisiert anzunehmen.
//   * Pass 2a: pro nkCall mit Name == 'Random'/'RandomRange'/'RandomFrom'
//     (case-insensitive, Qualifier-Strip Self.Random -> random) ein Finding -
//     STATEMENT-Level-Aufruf (rare in der Praxis - Result-Verwerfung).
//   * Pass 2b: pro nkAssign deren TypeRef das `\bRandom(`-Pattern enthaelt
//     ein Finding - das ist die uebliche Form `i := Random(100);`. uParser2
//     emittiert nkAssign mit ganzer RHS in TypeRef, NICHT mehrere
//     verschachtelte nkCall-Knoten. Regex-Scan auf TypeRef.
//
// FP-Risiken / Limitierungen:
//   * Cross-Unit-Randomize wird nicht erkannt - z.B. Randomize im
//     Initialization-Block einer use'd Unit oder im Program-Block. User
//     suppressiert mit `// noinspection InsecureRandom` bei FP.
//   * Random fuer SECURITY-Kontexte (Token / Salt / Password / Session-ID)
//     ist auch MIT Randomize unsicher - das prueft dieser Detektor NICHT.
//     Ein separater Detektor 'CryptoRandomUsage' waere die richtige
//     Antwort fuer kryptografische Use-Cases.
//
// Severity: lsWarning, Type: ftBug (KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInsecureRandomDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Liefert das letzte Punkt-Segment in Lower-Case ('Self.Random' -> 'random').
    class function BareNameLower(const FullName: string): string; static;
    // True wenn TypeRef irgendwo das Pattern `\b(Random|RandomRange|RandomFrom)\(`
    // enthaelt. AHit = welcher Token gematched (Original-Casing aus Source).
    class function FindRandomCallInExpr(const Expr: string;
      out AHit: string): Boolean; static;
  end;

implementation

uses
  System.RegularExpressions;

class function TInsecureRandomDetector.BareNameLower(
  const FullName: string): string;
// uParser2 nkCall.Name enthaelt die ganze Call-Expression mit '(args)',
// nicht nur den Identifier. Wir extrahieren erst alles vor dem ersten
// '(', dann das letzte Punkt-Segment.
var
  Bare   : string;
  ParenP : Integer;
  DotPos : Integer;
begin
  Bare   := FullName;
  ParenP := Pos('(', Bare);
  if ParenP > 1 then
    Bare := Copy(Bare, 1, ParenP - 1);
  DotPos := LastDelimiter('.', Bare);
  if DotPos > 0 then
    Result := LowerCase(Copy(Bare, DotPos + 1, MaxInt))
  else
    Result := LowerCase(Bare);
end;

class function TInsecureRandomDetector.FindRandomCallInExpr(
  const Expr: string; out AHit: string): Boolean;
const
  // Longest-first damit RandomRange/RandomFrom nicht von Random geclobbert
  // werden (in PCRE-Backtracking-Modus eigentlich egal, aber klarer).
  RANDOM_RE = '\b(RandomRange|RandomFrom|Random)\s*\(';
var
  M : TMatch;
begin
  Result := False;
  AHit   := '';
  if Expr = '' then Exit;
  M := TRegEx.Match(Expr, RANDOM_RE, [roIgnoreCase]);
  if M.Success then
  begin
    AHit   := M.Groups[1].Value;  // Original-Casing
    Result := True;
  end;
end;

class procedure TInsecureRandomDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls, Assigns : TList<TAstNode>;
  N              : TAstNode;
  Bare, Hit      : string;
  HasRandomize   : Boolean;
  F              : TLeakFinding;

  procedure Emit(ALine: Integer; const ACallName: string);
  var L: TLeakFinding;
  begin
    L            := TLeakFinding.Create;
    L.FileName   := FileName;
    L.MethodName := '';
    L.LineNumber := IntToStr(ALine);
    L.MissingVar := ACallName + '(...) without prior Randomize - ' +
                    'deterministic sequence (Seed=0 until Randomize)';
    L.SetKind(fkInsecureRandom);
    Results.Add(L);
  end;

begin
  // Pass 1: ist Randomize irgendwo aufgerufen? Standalone-Statement-Form
  // landet als nkCall, qualified (System.Randomize) auch.
  Calls := UnitNode.FindAll(nkCall);
  try
    HasRandomize := False;
    for N in Calls do
      if BareNameLower(N.Name) = 'randomize' then
      begin
        HasRandomize := True;
        Break;
      end;
    if HasRandomize then Exit;

    // Pass 2a: nkCall mit Random*-Name (Statement-Level, result-verworfen).
    for N in Calls do
    begin
      Bare := BareNameLower(N.Name);
      if (Bare = 'random') or (Bare = 'randomrange') or (Bare = 'randomfrom') then
        Emit(N.Line, N.Name);
    end;
  finally
    Calls.Free;
  end;

  // Pass 2b: nkAssign mit Random* in TypeRef (RHS-Expression). uParser2
  // emittiert nkAssign mit der ganzen RHS als String im TypeRef-Feld;
  // verschachtelte Calls werden NICHT als eigene nkCall-Nodes ausgegeben.
  Assigns := UnitNode.FindAll(nkAssign);
  try
    for N in Assigns do
      if FindRandomCallInExpr(N.TypeRef, Hit) then
        Emit(N.Line, Hit);
  finally
    Assigns.Free;
  end;
end;

end.
