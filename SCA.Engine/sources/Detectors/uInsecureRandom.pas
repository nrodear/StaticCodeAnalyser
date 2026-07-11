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
    // FP-Guard Klasse A (Todo_FP_SCA167, 2026-07-11): scannt die Roh-Quelle
    // (Strings ausgeblendet, Kommentare entfernt) case-insensitiv auf das
    // ganze Wort 'randomize'. Faengt ein parameterloses 'Randomize;' in einer
    // initialization-/finalization-Sektion, das der nkCall-Pass1 nicht sieht
    // (uParser2 ueberspringt deren Body). Reine Verengung: nur True -> Exit.
    class function SourceHasRandomize(const FileName: string): Boolean; static;
  end;

implementation

uses
  System.Classes, System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

// True wenn das Random-Token an MatchIndex (1-basiert) ein Methoden-Aufruf auf
// einem OBJEKT ist (Obj.Random) statt der globalen RTL-Random. Unqualified,
// 'System.Random' und 'Math.Random*' sind die echten -> False. Custom-RNG-
// Klassen ('FRng.Random', 'Generator.RandomRange') verwalten ihren EIGENEN
// Seed und sind KEIN InsecureRandom -> True (Welle 3, 2026-06-28, ~35% FP).
function IsObjectQualifiedRandom(const Expr: string; MatchIndex: Integer): Boolean;
var i: Integer; Qual: string;
begin
  Result := False;
  i := MatchIndex - 1;
  while (i >= 1) and CharInSet(Expr[i], [' ', #9]) do Dec(i);
  if (i < 1) or (Expr[i] <> '.') then Exit;       // unqualified -> globale Random
  Dec(i);
  while (i >= 1) and CharInSet(Expr[i], [' ', #9]) do Dec(i);
  Qual := '';
  while (i >= 1) and CharInSet(Expr[i], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
  begin Qual := Expr[i] + Qual; Dec(i); end;
  Qual := LowerCase(Qual);
  // 'self' gilt als globale Random (Test-Vertrag SelfDotRandomCall_StillReported);
  // nur FREMDE Objekt-Refs (FRng/Generator/...) sind Custom-RNG.
  Result := (Qual <> '') and (Qual <> 'system') and (Qual <> 'math')
            and (Qual <> 'self');
end;

// Letztes Qualifier-Segment vor dem Methodennamen, lower-case. 'FRng.Random(1)'
// -> 'frng'; 'System.Random(1)' -> 'system'; 'Random(1)' -> ''.
function CallQualifierLower(const FullName: string): string;
var Bare: string; ParenP, DotPos: Integer;
begin
  Bare := FullName;
  ParenP := Pos('(', Bare);
  if ParenP > 1 then Bare := Copy(Bare, 1, ParenP - 1);
  DotPos := LastDelimiter('.', Bare);
  if DotPos <= 0 then Exit('');
  Bare := Copy(Bare, 1, DotPos - 1);              // alles vor dem Methodennamen
  DotPos := LastDelimiter('.', Bare);             // nur letztes Qualifier-Segment
  if DotPos > 0 then Bare := Copy(Bare, DotPos + 1, MaxInt);
  Result := LowerCase(Trim(Bare));
end;

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
  while M.Success do
  begin
    // Objekt-qualifizierte Custom-RNG-Methoden (FRng.Random(..)) ueberspringen -
    // nur globale RTL-Random (unqualified / System. / Math.) ist deterministisch.
    if not IsObjectQualifiedRandom(Expr, M.Index) then
    begin
      AHit   := M.Groups[1].Value;  // Original-Casing
      Exit(True);
    end;
    M := M.NextMatch;
  end;
end;

class function TInsecureRandomDetector.SourceHasRandomize(
  const FileName: string): Boolean;
var
  Lines    : TStringList;
  Cached   : Boolean;
  LineFor  : TArray<Integer>;
  Stripped : string;
begin
  Result := False;
  // In-Memory-/Single-File-Pfade ohne Datei auf Platte (Tests: FindingsOf)
  // liefern nil -> Guard neutral, der nkCall-Pass1 bleibt die Erkennung.
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    // String-Literale werden zu FillCh ('~'), Kommentar-Inhalte entfernt -
    // ein 'randomize' in einem String oder Kommentar zaehlt bewusst NICHT
    // (Kommentar != Code-Use). ContainsWholeWordLower prueft Wortgrenzen
    // links UND rechts (System.Randomize matched: '.' ist keine Ident-Grenze).
    Stripped := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
    Result := TDetectorUtils.ContainsWholeWordLower('randomize',
      LowerCase(Stripped));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

class procedure TInsecureRandomDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls, Assigns : TList<TAstNode>;
  N              : TAstNode;
  Bare, Hit      : string;
  HasRandomize   : Boolean;

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
    // FP-Guard Klasse A (Todo_FP_SCA167, 2026-07-11): parameterloses
    // 'Randomize;' in einer initialization-/finalization-Sektion emittiert
    // uParser2 NICHT als nkCall (der Sektions-Body wird ge-skipt) -> Pass1
    // verpasst es und flaggt trotzdem, obwohl der globale RTL-Seed gesetzt
    // ist. Roh-Quelle nachladen und auf das ganze Wort 'randomize' scannen.
    // Nur suppressierend (True -> Exit), nie zusaetzlich emittierend.
    if not HasRandomize then
      HasRandomize := SourceHasRandomize(FileName);
    if HasRandomize then Exit;

    // Pass 2a: nkCall mit Random*-Name (Statement-Level, result-verworfen).
    for N in Calls do
    begin
      Bare := BareNameLower(N.Name);
      if (Bare = 'random') or (Bare = 'randomrange') or (Bare = 'randomfrom') then
      begin
        // Objekt-qualifizierte Custom-RNG-Methoden (FRng.Random) ueberspringen;
        // nur unqualified / System. / Math. ist die globale RTL-Random.
        var Q := CallQualifierLower(N.Name);
        if (Q = '') or (Q = 'system') or (Q = 'math') or (Q = 'self') then
          Emit(N.Line, N.Name);
      end;
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
