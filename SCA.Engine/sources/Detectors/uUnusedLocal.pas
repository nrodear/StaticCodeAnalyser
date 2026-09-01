unit uUnusedLocal;

// Detector: lokale `var X: T;` die im Methoden-Body nie referenziert wird.
//
// Pendant zur Delphi-Compiler-Warnung H2164. Der SCA-Detector hat zwei
// Vorteile gegenueber dem Compiler:
//   * funktioniert ohne Build (CI / Pre-Commit-Pfade)
//   * im Grid / Hint-Panel mit Quick-Fix-Vorschlag
//   * via `// noinspection UnusedLocalVar` unterdrueckbar
//
// Erkennung:
//   * MethodNode.FindAll(nkLocalVar) → Liste der Var-Deklarationen
//   * Pro LocalVar: zaehle Vorkommen im Body (nkCall/nkAssign/nkIfStmt etc.)
//   * Skip-Regeln:
//     - Inline-`for var i := ...` (haeufig nur als Loop-Index genutzt, der
//       Loop-Header selbst zaehlt als Referenz - sicherheitshalber skippen)
//     - Name beginnt mit `_` (Konvention fuer "intentionally unused")
//     - Method-Body ist asm-Block (nicht durch unseren Parser zerlegt)
//
// Severity: lsHint (kein Bug, nur Cleanup).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TUnusedLocalDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedRoutine
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

// Steht der Bezeichner ANameLow mit Wortgrenzen INNERHALB einer
// offenen Klammer? Beide Argumente sind bereits kleingeschrieben.
//
// Die Wortgrenzen sind der Grund fuer die Handarbeit statt Pos: 'n'
// darf nicht in 'count' treffen. Die Klammertiefe zaehlt mit, weil nur
// der Stand INNERHALB entscheidet - derselbe Name kann davor als
// Typname stehen.
function IdentInKlammern(const ACodeLow, ANameLow: string): Boolean;
var
  i, tiefe, len : Integer;
begin
  Result := False;
  len := Length(ANameLow);
  if len = 0 then Exit;
  tiefe := 0;
  for i := 1 to Length(ACodeLow) do
  begin
    if ACodeLow[i] = '(' then
      Inc(tiefe)
    else if ACodeLow[i] = ')' then
      Dec(tiefe)
    else if (tiefe > 0) and (Copy(ACodeLow, i, len) = ANameLow)
            and ((i = 1) or not TDetectorUtils.IsIdentChar(ACodeLow[i - 1]))
            and ((i + len > Length(ACodeLow))
                 or not TDetectorUtils.IsIdentChar(ACodeLow[i + len])) then
      Exit(True);
  end;
end;

// Verifiziert via Source-Line dass die LineNumber des Findings eine
// echte Var-Deklaration zeigt (Identifier ':' Type) und KEIN nested
// procedure/function-Header. Der AST kann beides als nkLocalVar liefern
// weil ParseMethodImpl-Cleanup nested-Methods nicht sauber traegt;
// dieser Filter haelt FPs am Reporting-Punkt ab.
function LooksLikeRealLocalVar(Lines: TStringList; LineNo1: Integer;
  const AName: string): Boolean;
var
  S, T, NameLow : string;
begin
  Result := True;
  if (Lines = nil) or (LineNo1 <= 0) or (LineNo1 > Lines.Count) then Exit;
  S := Lines[LineNo1 - 1];
  T := LowerCase(TrimLeft(S));
  // Nested-Routine: Zeile beginnt mit procedure/function/constructor/
  // destructor/operator/class procedure/class function -> KEINE Var-Decl.
  if T.StartsWith('procedure ')   or T.StartsWith('procedure(') or
     T.StartsWith('function ')    or T.StartsWith('function(')  or
     T.StartsWith('constructor ') or T.StartsWith('constructor(') or
     T.StartsWith('destructor ')  or T.StartsWith('destructor(')  or
     T.StartsWith('operator ')    or T.StartsWith('class ')      then
    Exit(False);

  // SIGNATURPARAMETER statt Variable (2026-08-31, Kundenfund
  // rdpwrap/src-rdpconfig/MainUnit.pas:126): steht der gemeldete
  // Bezeichner INNERHALB einer Klammer, gehoert er zu einer
  // Parameterliste und ist keine lokale Variable.
  //
  //   function DisableWowRedirection: Boolean;
  //   type
  //     TFunc = function(var Wow64FsEnableRedirection: LongBool): LongBool;
  //
  // 'Wow64FsEnableRedirection' benennt den Parameter einer SIGNATUR. Er
  // dokumentiert nur und kann per Definition nie gelesen oder
  // geschrieben werden - die Regel kann an ihm nie erfuellt sein.
  //
  // Der Zeilenanfangs-Test oben faengt das NICHT: die Zeile beginnt mit
  // 'TFunc', nicht mit 'function'. Die Klammerprobe deckt beide Formen
  // ab - den prozeduralen TYP ('X = function(..)') genauso wie die
  // Variable mit prozeduralem Typ ('var F: function(..)').
  NameLow := LowerCase(Trim(AName));
  if NameLow = '' then Exit;
  if IdentInKlammern(T, NameLow) then Exit(False);
end;

function IsIdentChar(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Wortgrenzen-Suche case-insensitive. Liefert True wenn NeedleLow als
// ganzes Wort in HayLow vorkommt.
function ContainsWord(const HayLow, NeedleLow: string): Boolean;
var
  P, NL, HL : Integer;
  Before, After : Char;
begin
  Result := False;
  NL := Length(NeedleLow);
  HL := Length(HayLow);
  if (NL = 0) or (HL < NL) then Exit;
  P := 1;
  repeat
    P := Pos(NeedleLow, HayLow, P);
    if P = 0 then Exit;
    Before := #0;
    if P > 1 then Before := HayLow[P - 1];
    After := #0;
    if P + NL - 1 < HL then After := HayLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then
      Exit(True);
    P := P + NL;
  until False;
end;

// Iterativer Walk durch alle Descendants - sammelt Name+TypeRef pro Knoten.
// Iterativ, damit tiefe ASTs (z.B. nach Parser-Fix fuer inline-record) kein
// Stack-Overflow ausloesen.
procedure CollectAllTokens(Root: TAstNode; SB: TStringBuilder);
var
  Stack : TStack<TAstNode>;
  Cur : TAstNode;
  i : Integer;
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

// ===========================================================================
// QUELLTEXT-RUECKFALL (30%-Real-World-Audit 2026-07-31: 2.233 Funde, 62 % FP)
//
// Der AST-Token-Scan oben sieht nur, was der Parser unter den Methodenknoten
// gehaengt hat. Das ist bei jeder Routine mit verschachtelten Routinen zu
// wenig: uParser2.ParseMethodImpl parst nested routines, VERWIRFT sie aus dem
// AST und laesst nur einen nkNestedRange-Marker zurueck - und desynchronisiert
// dabei haeufig auch den Rest des aeusseren Rumpfes. Beide Verluste erzeugen
// denselben Fehlbefund: die Variable ist benutzt, nur nicht im AST.
//   * Nutzung IM nested body   (outer locals sind dort sichtbar!)
//   * Nutzung im Hauptrumpf NACH der nested routine (JvMarkupLabel.pas:222:
//     `AColor, FColor: TColor;` + `if HTMLStringToColor(AVal, AColor) then`)
// Dieselbe Luecke traegt die kleineren Klassen des Audits: asm-Bloecke,
// label-Sektionen, `absolute`-Overlays, Direktiven-Keywords als Varname.
//
// Deshalb wird VOR dem Melden am Quelltext gegengezaehlt - ueber den
// Zeilenbereich der Routine, auf der gestrippten Fassung (Kommentare UND
// String-Literale sind geblankt: ein Name im Kommentar ist NIE eine Nutzung,
// Projektregel).
//
// MONOTONIE: die Pruefung kann nur unterdruecken. Beide Richtungen des
// Bereichsfehlers sind ungefaehrlich - ein zu kurzer Bereich (nicht markierte
// nested routine) unterdrueckt weniger, ein zu langer (Kopf des Nachfolgers
// nicht erkannt) unterdrueckt mehr. Nie entsteht ein neuer Fund.
// ===========================================================================

// True, wenn die lowercase Zeile wie ein Routinen-KOPF aussieht.
// Prozedur-TYPEN (`function(...)`) treffen bewusst nicht - hinter dem
// Keyword muss Whitespace und dann ein Bezeichner stehen.
// ARBEITET AUF DER ROHZEILE, nicht auf der gestrippten Fassung: ein
// auskommentiertes `procedure Foo;` beendet den Bereich damit zu frueh.
// Das ist die harmlose Richtung - der Bereich wird kuerzer, es wird WENIGER
// unterdrueckt, ein Fund kann dadurch nie neu entstehen.
function LineLooksLikeRoutineHead(const ALineLow: string): Boolean;
const
  KW : array[0..4] of string =
    ('procedure', 'function', 'constructor', 'destructor', 'operator');
var
  T  : string;
  K  : string;
  p  : Integer;
begin
  Result := False;
  T := TrimLeft(ALineLow);
  if T.StartsWith('class ') then T := TrimLeft(Copy(T, 7, MaxInt));
  for K in KW do
  begin
    if not T.StartsWith(K) then Continue;
    p := Length(K) + 1;
    if p > Length(T) then Continue;
    // Hinter dem Keyword muss Whitespace und dann ein Bezeichner folgen -
    // `function(` ist ein Prozedurtyp, kein Kopf.
    if not CharInSet(T[p], [' ', #9]) then Continue;
    while (p <= Length(T)) and CharInSet(T[p], [' ', #9]) do Inc(p);
    if (p <= Length(T)) and IsIdentChar(T[p]) then Exit(True);
  end;
end;

// Letzte Zeile des Quelltextbereichs dieser Routine: die Zeile vor dem
// naechsten Routinen-Kopf, der NICHT in einer nkNestedRange-Spanne dieser
// Routine liegt. Kein Kopf mehr -> Dateiende.
function RoutineRangeEnd(Lines: TStringList; AStart1: Integer;
  const ANestStarts, ANestEnds: TArray<Integer>): Integer;
var
  i, k : Integer;
  InNested : Boolean;
begin
  Result := Lines.Count;
  for i := AStart1 + 1 to Lines.Count do
  begin
    InNested := False;
    for k := 0 to High(ANestStarts) do
      if (i >= ANestStarts[k]) and (i <= ANestEnds[k]) then
      begin
        InNested := True;
        Break;
      end;
    if InNested then Continue;
    if LineLooksLikeRoutineHead(LowerCase(Lines[i - 1])) then
      Exit(i - 1);
  end;
end;

// nkNestedRange-Marker der Routine einsammeln (Line = Start, TypeRef = Ende).
// Format und Semantik wie in uRoutineResultAssigned.CollectNestedSpans - dort
// werden die Spannen AUSGESCHLOSSEN, hier werden sie EINGESCHLOSSEN: fuer
// `Result` gilt die innere Routine, fuer outer locals die aeussere.
procedure CollectNestedSpansLocal(AMethod: TAstNode;
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

// 1-basierter Index im gestrippten Text, an dem die 1-basierte Quellzeile
// ALine1 beginnt. ALineFor ist monoton steigend (ein Block je Quellzeile),
// deshalb Binaersuche - eine lineare Suche je Kandidat waere quadratisch
// ueber der Datei (die Falle, die SCA176 einmal 902 Sekunden gekostet hat).
// 0 = Zeile nicht abbildbar.
function StrippedLineStart(const ALineFor: TArray<Integer>;
  ALine1: Integer): Integer;
var
  Lo, Hi, Mid, Target : Integer;
begin
  Result := 0;
  Target := ALine1 - 1;                       // ALineFor ist 0-basiert
  if (Target < 0) or (Length(ALineFor) = 0) then Exit;
  if Target > ALineFor[High(ALineFor)] then Exit;
  Lo := 0;
  Hi := High(ALineFor);
  while Lo < Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if ALineFor[Mid] < Target then Lo := Mid + 1 else Hi := Mid;
  end;
  if ALineFor[Lo] <> Target then Exit;
  Result := Lo + 1;
end;

// Zaehlt Wortgrenzen-Treffer von ANeedleLow im gestrippten Text zwischen den
// Zeichen-Offsets [AFrom..ATo]. Bricht bei AMax ab - mehr als "kommt
// mindestens zweimal vor" muss niemand wissen.
function CountWordInSpan(const ACodeLow: string; AFrom, ATo: Integer;
  const ANeedleLow: string; AMax: Integer): Integer;
var
  P, NL, CL     : Integer;
  Before, After : Char;
begin
  Result := 0;
  NL := Length(ANeedleLow);
  CL := Length(ACodeLow);
  if ATo > CL then ATo := CL;
  if (NL = 0) or (AFrom < 1) or (ATo - AFrom + 1 < NL) then Exit;
  P := AFrom;
  repeat
    P := Pos(ANeedleLow, ACodeLow, P);
    if (P = 0) or (P + NL - 1 > ATo) then Exit;
    Before := #0;
    if P > 1 then Before := ACodeLow[P - 1];
    After := #0;
    if P + NL - 1 < CL then After := ACodeLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then
    begin
      Inc(Result);
      if Result >= AMax then Exit;
    end;
    P := P + NL;
  until False;
end;

// Klammertiefe zwischen zwei Offsets. > 0 am Zeilenanfang heisst: die Zeile
// steht INNERHALB einer Klammer - der vermeintliche "local" ist dann ein
// Parametername in einem prozeduralen Typ ('GetTempPathFunc: function(...;
// lpBuffer: LPWSTR): DWORD'), den der Parser als eigene Deklaration emittiert
// (Audit-Klasse 2, Beleg issrc Shared.CommonFunc.pas:757).
function ParenDepthInSpan(const ACode: string; AFrom, ATo: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  if AFrom < 1 then AFrom := 1;
  if ATo > Length(ACode) then ATo := Length(ACode);
  for i := AFrom to ATo do
    if ACode[i] = '(' then Inc(Result)
    else if ACode[i] = ')' then
    begin
      Dec(Result);
      if Result < 0 then Result := 0;
    end;
end;

class procedure TUnusedLocalDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  LocalVars : TList<TAstNode>;
  LV : TAstNode;
  Name, LowName : string;
  BodySB : TStringBuilder;
  BodyLow : string;
  RefCount : Integer;
  F : TLeakFinding;
  Lines  : TStringList;
  Cached : Boolean;
  // Quelltext-Rueckfall (Audit 2026-07-31)
  SrcLow      : string;
  SrcLineFor  : TArray<Integer>;
  SrcState    : Integer;                 // 0 unbestimmt / 1 bereit / -1 aus
  RangeLo     : Integer;
  RangeHi     : Integer;
  SpanFrom    : Integer;
  SpanTo      : Integer;
  DeclStart   : Integer;
  NestStarts  : TArray<Integer>;
  NestEnds    : TArray<Integer>;
begin
  LocalVars := MethodNode.FindAll(nkLocalVar);
  BodySB := TStringBuilder.Create;
  Lines  := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  try
    if LocalVars.Count = 0 then Exit;

    // Body-Tokens einmalig einsammeln + lowercase
    CollectAllTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);

    // Der Quelltextbereich wird LAZY bestimmt - erst wenn in dieser Routine
    // wirklich ein Fund anstuende. Sonst zahlte jede der zehntausenden
    // fundfreien Routinen den Zeilen-Vorwaertsscan von RoutineRangeEnd, und
    // der ist O(Datei) je Routine = quadratisch ueber der Datei.
    SrcState := 0;                       // 0 = unbestimmt, 1 = bereit, -1 = aus
    RangeLo  := MethodNode.Line;
    // KEIN `RangeHi := 0` - der Compiler weist es als tote Zuweisung ab
    // (H2077). RangeHi wird ausschliesslich INNERHALB der Lazy-Init gesetzt
    // und dort auch nur gelesen; ausserhalb existiert kein Pfad, der es
    // anfasst. SpanFrom/SpanTo bleiben dagegen vorbelegt: sie werden in
    // spaeteren Schleifendurchlaeufen gelesen, ohne dass die Init erneut
    // laeuft.
    SpanFrom := 0;
    SpanTo   := 0;

    for LV in LocalVars do
    begin
      Name := Trim(LV.Name);
      if Name = '' then Continue;
      if Name.StartsWith('_') then Continue;     // Convention: ignored
      LowName := LowerCase(Name);

      // Mindestens ein Vorkommen MUSS die var-Deklaration sein. Wir wollen
      // Referenzen >= 2 (Deklaration + Nutzung). Wortgrenze stellt sicher
      // dass 'foo' nicht in 'fooBar' matcht.
      RefCount := 0;
      var P := 1;
      while True do
      begin
        P := Pos(LowName, BodyLow, P);
        if P = 0 then Break;
        var Before : Char := #0;
        if P > 1 then Before := BodyLow[P - 1];
        var After  : Char := #0;
        if P + Length(LowName) - 1 < Length(BodyLow) then
          After := BodyLow[P + Length(LowName)];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
          Inc(RefCount);
        P := P + Length(LowName);
      end;

      if RefCount <= 1 then
      begin
        // Source-Verifikation: die Zeile MUSS wie eine Var-Decl aussehen.
        // Wenn dort z.B. 'procedure GetValue(...)' steht, ist das eine
        // nested Routine und KEIN unused Local - der AST-Knoten kommt
        // nur durch eine Parser-Eigenart in den nkLocalVar-Strom.
        if not LooksLikeRealLocalVar(Lines, LV.Line, LV.Name) then Continue;

        // QUELLTEXT-GEGENPROBE (Audit 2026-07-31, siehe Block oben).
        // Einmalige Lazy-Initialisierung fuer diese Routine.
        if SrcState = 0 then
        begin
          SrcState := -1;
          if (Lines <> nil) and (RangeLo > 0) then
          begin
            CollectNestedSpansLocal(MethodNode, NestStarts, NestEnds);
            RangeHi := RoutineRangeEnd(Lines, RangeLo, NestStarts, NestEnds);
            SrcLow  := LowerCase(TDetectorUtils.StripStringsAndCommentsCached(
                         Lines, SrcLineFor, AContext, FileName, ' '));
            SpanFrom := StrippedLineStart(SrcLineFor, RangeLo);
            // Ende = Anfang der Zeile HINTER dem Bereich; gibt es die nicht,
            // laeuft der Bereich bis zum Textende.
            SpanTo := StrippedLineStart(SrcLineFor, RangeHi + 1);
            if SpanTo <= 0 then SpanTo := Length(SrcLow) else Dec(SpanTo);
            if (SrcLow <> '') and (SpanFrom > 0) and (SpanTo >= SpanFrom) then
              SrcState := 1;
          end;
        end;

        if SrcState = 1 then
        begin
          DeclStart := StrippedLineStart(SrcLineFor, LV.Line);
          // (a) Parametername eines prozeduralen Typs? Dann steht die Zeile
          //     innerhalb einer offenen Klammer und ist gar keine Deklaration.
          if (DeclStart > SpanFrom) and
             (ParenDepthInSpan(SrcLow, SpanFrom, DeclStart - 1) > 0) then
            Continue;
          // (b) Kommt der Name im Quelltextbereich der Routine ein zweites Mal
          //     vor, ist er benutzt - der AST hat die Stelle nur verloren.
          if CountWordInSpan(SrcLow, SpanFrom, SpanTo, LowName, 2) >= 2 then
            Continue;
        end;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(LV.Line);
        F.MissingVar := Format(
          'Unused local variable: %s (declared but never read or written)',
          [Name]);
        F.SetKind(fkUnusedLocalVar);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
    BodySB.Free;
    LocalVars.Free;
  end;
end;

class procedure TUnusedLocalDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results, AContext);
  finally
    Methods.Free;
  end;
end;

end.
