unit uSetLengthAppendInLoop;

// Detektor: SetLength(arr, Length(arr) + 1) innerhalb einer Schleife.
//
// Pattern (Performance-Bug, O(n*n) statt O(n)):
//   for i := 0 to Source.Count - 1 do
//   begin
//     SetLength(Dest, Length(Dest) + 1);   // <-- realloc auf JEDER Iteration
//     Dest[High(Dest)] := Source[i];
//   end;
//
// Korrekt:
//   SetLength(Dest, Source.Count);         // einmal vorab
//   for i := 0 to Source.Count - 1 do
//     Dest[i] := Source[i];
//
// Folge: Realloc auf jeder Iteration kopiert n*(n+1)/2 Elemente statt n.
// Bei 10000 Elementen: 50_005_000 statt 10_000 Operationen - 5000x langsamer.
// mORMot's Performance-Profile flagt diesen Pattern als haeufigsten
// Real-World-Bottleneck in user-code, der die Library benutzt.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Vorkommen von `for|while|repeat`:
//     - 600 Zeichen Lookahead-Fenster (Schleifen-Body).
//     - Suche `SetLength(<id>, Length(<id>) + <n>)` ODER `SetLength(<id>,
//       <id>.Count + 1)`-style Pattern im Fenster.
//     - Wenn gefunden -> Finding (Position des SetLength-Calls).
//
// Limitierungen:
//   * Single-File-lexisch. Fenster-basiert (600 Zeichen) - sehr lange
//     Schleifen werden nicht voll erfasst.
//   * `SetLength(arr, Length(arr) + Constant)` (Block-Grow) wird ebenfalls
//     geflaggt - das ist OK weil Block-Grow innerhalb einer Schleife
//     ebenfalls suboptimal ist (vorher rechnen + einmal SetLength).
//
// Schweregrad: lsWarning - Performance-Bug, kein Crash aber massive
// Skalierungsfalle.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TSetLengthAppendInLoopDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, RedundantBoolean, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedLoopRE : TRegEx;
  CachedGrowRE : TRegEx;
  CachedReInit : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedLoopRE := TRegEx.Create('(?i)\b(for|while|repeat)\b');
  CachedGrowRE := TRegEx.Create(
    '(?i)\bSetLength\s*\(\s*(\w+)\s*,\s*Length\s*\(\s*(\w+)\s*\)\s*\+');
  CachedReInit := True;
end;

// Liefert das erste \w+-Token (Bezeichner ODER Zahl) in S, '' wenn keins.
function FirstWordToken(const S: string): string;
var M: TMatch;
begin
  M := TRegEx.Match(S, '\w+');
  if M.Success then Result := M.Value else Result := '';
end;

// FP-Guard A (2026-07-11): Das flache 600-Zeichen-Fenster ab dem Schleifen-
// Keyword erwischt auch SetLength-Calls in einer voellig anderen, schleifen-
// losen Routine (Append-Prozeduren wie TAPETag.AppendField / AddSortFunction -
// die naechste 'for'-Keyword liegt in einer VORHERIGEN Routine). Steht ein
// benannter Routine-Header (procedure/function/constructor/destructor <Name>)
// zwischen Schleife und SetLength, gehoert das SetLength zu einer anderen
// Routine und ist kein O(n*n)-Realloc. Der negative Lookahead schliesst anonyme
// Methoden ('procedure begin', 'procedure(Args)') aus.
// Between = gestrippter Text zwischen Schleifen-Keyword und SetLength.
//
// (Der urspruengliche Guard B - Block-Tiefe fuer 'SetLength hinter dem
// Schleifen-end;' - wurde nach adversarialem Review VERWORFEN: ein reiner
// begin/end-Zaehler kann 'die Schleife selbst ist geschlossen' nicht von 'ein
// innerer Block in einem beginless repeat/do-Body ist geschlossen' trennen und
// unterdrueckte damit echte O(n*n)-Bugs wie 'repeat case..end; SetLength(..+1)
// until'. Der WebSocket-JoinGroup-FP - Append hinter dem for-end; - bleibt
// dadurch offen und muss ggf. spaeter praeziser adressiert werden.)
function SetLengthInDifferentRoutine(const Between: string): Boolean;
begin
  Result := TRegEx.IsMatch(Between,
    '(?i)\b(?:procedure|function|constructor|destructor)\s+(?!of\b|begin\b)[A-Za-z_]');
end;

// FP-Guard C (2026-07-11): room-guarded Block-Grow. Muster (MVCFramework
// HttpSys):
//   if Length(<arr>) - <written> < <CHUNK> then
//     SetLength(<arr>, Length(<arr>) + <CHUNK>);
// Das reallociert NUR wenn der freie Platz unter die Chunk-Groesse faellt ->
// amortisiert O(n), KEIN O(n*n). Entscheidend fuer die TP-Sicherheit: dieselbe
// Konstante <CHUNK> muss im Wachstum UND in der '<'-Bedingung vorkommen. Ein
// echter Grow-by-1-Bug ('SetLength(a, Length(a)+1)') hat GrowAmount='1', das in
// keiner sinnvollen 'if Length(a) ... < 1 then'-Bedingung steht - er bleibt
// gemeldet. Ungeguardetes Block-Grow (kein vorangestelltes 'if Length(a)<CHUNK
// then') bleibt ebenfalls gemeldet.
function IsRoomGuardedBlockGrow(const Between, ArrayName, GrowAmount: string): Boolean;
var
  CapRef: string;
begin
  if (GrowAmount = '') or (ArrayName = '') then Exit(False);
  // ArrayName/GrowAmount sind \w+ (keine Regex-Metazeichen) - direkt einbettbar.
  // '[^;]*' erlaubt keinen Statement-Trenner => der Guard muss unmittelbar vor
  // dem SetLength stehen ('then' direkt vor dem Call, per \s*$ verankert).
  //
  // Original-Form (2026-07-11): freier-Platz-Check 'Length(arr) ... < CHUNK' mit
  // derselben Konstante <CHUNK> in Bedingung UND Wachstum (MVCFramework HttpSys).
  // Kapazitaetsreferenz LINKS, Operator '<'. Unveraendert.
  if TRegEx.IsMatch(Between,
       '(?i)\bif\b[^;]*\bLength\s*\(\s*' + ArrayName +
       '\s*\)[^;]*<[^;]*\b' + GrowAmount + '\b[^;]*\bthen\s*$') then
    Exit(True);

  // Real-World-FP-Audit 2026-07-12, FP-Klasse 'capacity-guarded Block-Grow':
  // Kapazitaetspruefungen, die die Original-'<CHUNK'-Form verpasst, weil sie
  // '=', '>=', '>' oder 'High(...)' benutzen und die Kapazitaet des Arrays auf
  // der RECHTEN Seite des Vergleichs steht (Overflow-Ordnung), z.B.:
  //   if <Index/Count> >= Length(<arr>) then SetLength(<arr>, Length(<arr>)+CHUNK)
  //   if <Index>       >  High(<arr>)   then ...
  //   if <Count>       =  Length(<arr>) then ...
  // Der Realloc feuert nur bei Kapazitaets-Ueberlauf, d.h. alle CHUNK Iterationen
  // -> amortisiert O(n), kein O(n*n).
  //
  // TP-Schutz 1: Grow-by-1 bleibt IMMER Fund - ein Guard mit Wachstum um genau 1
  // reallociert trotzdem jede Iteration (High(arr) waechst mit dem Index mit) und
  // ist echtes O(n*n); nur Block-Grow (>1) ist amortisiert-linear.
  // TP-Schutz 2: der Vergleichsoperator muss VOR der Kapazitaetsreferenz DESSELBEN
  // Arrays stehen (Overflow-Ordnung). Damit gilt ein reiner Nichtleer-Check
  // 'if Length(arr) > 0 then' (Kapazitaet links) NICHT als Guard, und ein echtes
  // ungeguardetes Per-Iteration-Grow wird nicht faelschlich unterdrueckt.
  // (Die '(?<![<>:])='-Lookbehind verhindert, dass das '=' aus '<=' / ':=' als
  // Gleichheits-Operator zaehlt - '<= Length(arr)' ist kein Overflow-Guard.)
  if GrowAmount = '1' then Exit(False);
  CapRef := '(?:Length\s*\(\s*' + ArrayName + '\s*\)|High\s*\(\s*' +
            ArrayName + '\s*\))';
  // (?<!<) vor '>=?' verhindert, dass das '>' aus dem Ungleich-Operator '<>'
  // als Overflow-Vergleich zaehlt (Real-World-FP-Audit 2026-07-12 Verify-Concern:
  // 'if x <> Length(arr) then blockGrow' ist KEIN Kapazitaets-Guard).
  Result := TRegEx.IsMatch(Between,
    '(?i)\bif\b[^;]*(?:(?<!<)>=?|(?<![<>:])=)[^;]*' + CapRef + '[^;]*\bthen\s*$');
end;

class procedure TSetLengthAppendInLoopDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
const
  LOOK_AHEAD = 600;  // groesseres Fenster als die anderen Detektoren -
                     // Schleifen-Bodies sind oft mehrzeilig.
var
  Lines        : TStringList;
  Cached       : Boolean;
  Code         : string;
  LineFor      : TArray<Integer>;
  LoopM        : TMatch;
  GrowM        : TMatch;
  Snippet      : string;
  ArrayName    : string;
  GrowName     : string;
  Between      : string;
  GrowAmount   : string;
  LineNo       : Integer;
  F            : TLeakFinding;
  Detail       : string;
  AbsolutePos  : Integer;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    for LoopM in CachedLoopRE.Matches(Code) do
    begin
      AbsolutePos := LoopM.Index + LoopM.Length;
      if AbsolutePos > Length(Code) then Continue;
      Snippet := Copy(Code, AbsolutePos, LOOK_AHEAD);

      for GrowM in CachedGrowRE.Matches(Snippet) do
      begin
        ArrayName := GrowM.Groups[1].Value;
        GrowName  := GrowM.Groups[2].Value;
        // Nur flaggen wenn das Array auf das gewachsen wird = dasselbe
        // Array dessen Length() abgefragt wurde.
        if not SameText(ArrayName, GrowName) then Continue;

        // FP-Guard A: SetLength steht in einer anderen, schleifen-losen Routine
        // (Routine-Header zwischen Schleifen-Keyword und SetLength).
        Between := Copy(Snippet, 1, GrowM.Index - 1);
        if SetLengthInDifferentRoutine(Between) then Continue;

        // FP-Guard C: room-guarded Block-Grow (amortisiert-linear, kein O(n*n)).
        GrowAmount := FirstWordToken(
          Copy(Snippet, GrowM.Index + GrowM.Length, 48));
        if IsRoomGuardedBlockGrow(Between, ArrayName, GrowAmount) then Continue;

        LineNo := TDetectorUtils.LineForPos(LineFor, AbsolutePos + GrowM.Index - 1);
        if LineNo <= 0 then LineNo := 1;

        Detail := Format(
          'SetLength(%s, Length(%s) + ...) inside a %s loop - quadratic realloc; grow once before the loop',
          [ArrayName, GrowName, LowerCase(LoopM.Groups[1].Value)]);

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNo);
        F.MissingVar := Detail;
        F.SetKind(fkSetLengthAppendInLoop);
        Results.Add(F);
        // Nur das ERSTE Grow pro Loop melden um Spam zu vermeiden.
        Break;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
