unit uNilDeref;

// Detektor fuer potentielle Nil-Dereferenzierungen (Sonar-Regel #3).
//
// Erkennt Variablen, die explizit auf nil gesetzt werden und danach
// ohne zwischenzeitliche Neuzuweisung oder Guard-Pruefung mit einem
// Punkt-Zugriff (Methode/Property) verwendet werden.
//
// Erkannte Guards:
//   - obj := TFoo.Create;        (Neuzuweisung)
//   - if Assigned(obj) then ...  (in If-Bedingung)
//   - if obj <> nil then ...     (in If-Bedingung)
//   - if obj = nil then Exit;    (Early-Exit-Guard)
//   - while obj <> nil do obj.X  (Schleifenkopf guardet nur den RUMPF)
//   - b := obj <> nil; if b then obj.X   (Boolean-Zwischenvariable)
//   - .Free / .Destroy           (TObject.Free ist nil-safe)
//   - Foo(obj) / x := Foo(obj)   (Uebergabe als Argument = potentielle
//                                 var/out-Zuweisung, beendet nil-Zustand)
//   - for obj in ... / for obj := (Schleife weist obj zu)
//
// Nicht erkannt (bewusst):
//   - obj.field := nil           (Cleanup-Muster)
//   - obj[i] := nil              (Element-Tracking ueber Indizes ist unsound)
//   - Werttypen (array of T / TArray<T> / Nullable<T>) - dort ist nil ein
//     WERT, kein Zeiger; ein Deref darauf kann nie eine AV sein
//   - Selbstreferenzen (Self.X)

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TNilDerefDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; const ADirLines: TArray<Integer>);
  private
    // Pruefung ob ein If-Block der Methode einen Guard fuer VarLow enthaelt.
    // ADerefNode (Autopsie 2026-08-27): schaltet zusaetzlich den while-Kopf-
    // Guard frei - der gilt NUR fuer Derefs im Schleifenrumpf, dafuer braucht
    // die Pruefung den Deref-Knoten. Ohne ihn arbeitet sie wie bisher.
    class function HasGuardingIf(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer;
      ADerefNode: TAstNode = nil): Boolean; static;
    // Erkennt ob ein Call ein nil-sicherer Aufruf ist (.Free, .Destroy)
    class function IsNilSafeCall(const CallNameLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - VarLow kommt in TextLow als
    // eigenstaendiges Argument nach einer oeffnenden Klammer vor
    class function HasBareArgUse(const TextLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - Uebergabe als Argument
    // zwischen nil-Zuweisung und Zugriff zaehlt als Zuweisung.
    // AExcludeCondA/B (Review 2026-07-30): if-Knoten, deren EIGENE
    // Bedingung nicht als var/out-Uebergabe zaehlen darf - das
    // Korrelations-Paar aus IsInCorrelatedExclusiveIfs hat die
    // ParseCorrelatedCond-Whitelist passiert und ist nebenwirkungsfrei.
    class function IsPassedAsArgBetween(MethodNode: TAstNode;
      Calls, Assigns: TList<TAstNode>;
      const VarLow: string; AfterLine, BeforeLine: Integer;
      AExcludeCondA: TAstNode = nil;
      AExcludeCondB: TAstNode = nil): Boolean; static;
    // FP-Gate (2026-07-04): for-in-loop-assign - Schleifenkopf weist VarLow zu
    // FP-Gate (Auto-Runde 2026-07-19): mutually-exclusive-branches (syntactic-
    // sibling) - nil-Zuweisung und Deref in then/else-Schwesterzweigen DESSELBEN
    // if koennen auf keiner realen Ausfuehrung gemeinsam laufen. Runtime-
    // Gegenstueck zur preprocessor-Teilklasse von DirLineBetween.
    class function IsInExclusiveBranch(MethodNode, AssignNode,
      DerefNode: TAstNode): Boolean; static;
    class function IsForLoopAssigned(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
  end;

implementation

// noinspection-file CanBeStrictPrivate, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, LongMethod, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uCFG;   // #6 Inkr.2: CFG-Erreichbarkeits-Postfilter (Q1)

function DirLineBetween(const Lines: TArray<Integer>; A, B: Integer): Boolean;
// Real-World-FP-Audit 2026-07-12, FP-Klasse 'preprocessor-branch' (Teilklasse
// der 'mutually-exclusive-branches'): True wenn eine {$IFDEF}-Direktiven-Zeile
// STRIKT zwischen A und B liegt. Dann stehen nil-Zuweisung (A) und Deref (B) in
// verschiedenen bedingten Kompilierungs-Zweigen ({$IFDEF}/{$ELSE}) - auf jeder
// realen Uebersetzung existiert nur EIN Zweig, es kann also keinen nil-Deref
// geben. Identisch zu uDeadCode/uUninitVar/uTwiceInheritedCalls.DirLineBetween
// (bewusst dupliziert, additiv/isoliert - nkConditionalRange-Muster).
var d: Integer;
begin
  for d in Lines do
    if (d > A) and (d < B) then Exit(True);
  Result := False;
end;

// Subtree-Containment per Objekt-Identitaet. Die Definition steht weiter
// unten bei den Branch-Gates (Z. ~300); HasGuardingIf braucht sie aber schon
// hier fuer den while-Kopf-Guard - deshalb die Vorwaertsdeklaration statt
// eines Umzugs (der die gewachsene Reihenfolge der Gates zerreissen wuerde).
function NodeContainsRef(Root, Target: TAstNode): Boolean; forward;

{ Hilfsfunktion: prueft ob in der Bedingung ein Guard fuer varname steht.
  Verwendet TDetectorUtils.ContainsWholeWordLower fuer korrekte Wortgrenzen -
  vorher matchten 'assigned MyVar' faelschlich auch 'assigned MyVarOld'. }
function CondHasGuard(const CondLow, VarLow: string): Boolean;
const
  PATTERNS: array[0..7] of string = (
    // Assigned-Varianten
    'assigned(%s)',
    'assigned( %s )',
    'assigned (%s)',
    'assigned ( %s )',
    'assigned %s',
    // Vergleich mit nil (links und rechts)
    '%s <> nil',
    '%s<>nil',
    'nil <> %s'
  );
var
  Pat: string;
begin
  Result := False;
  for Pat in PATTERNS do
    if TDetectorUtils.ContainsWholeWordLower(Format(Pat, [VarLow]), CondLow) then
      Exit(True);
  // Sonderfall ohne Whitespaces - 'nil<>' braucht keine eigene Wortgrenze rechts
  // weil VarLow direkt folgt; ContainsWholeWord prueft trotzdem den Rand am Ende.
  if TDetectorUtils.ContainsWholeWordLower('nil<>' + VarLow, CondLow) then
    Result := True;
end;

class function TNilDerefDetector.HasGuardingIf(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer;
  ADerefNode: TAstNode): Boolean;
var
  Ifs    : TList<TAstNode>;
  Whiles : TList<TAstNode>;
  IfN    : TAstNode;
  WhN    : TAstNode;
  Low    : string;
begin
  Result := False;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  for IfN in Ifs do
  begin
    // Nur If-Statements zwischen den relevanten Zeilen
    if IfN.Line < AfterLine then Continue;
    if IfN.Line > BeforeLine then Continue;
    Low := IfN.TypeRef.ToLower;
    if Low = '' then Continue;
    if CondHasGuard(Low, VarLow) then Exit(True);
  end;

  // FP-Gate (SCA008-Autopsie 2026-08-27, 1 Drop): der Kopf einer while-
  // Schleife ist fuer JEDE Iteration ihres RUMPFS derselbe Guard wie eine
  // if-Bedingung - 'x := nil; ... while x <> nil do x.Foo' kann den Deref
  // nur mit x <> nil erreichen. Die Assigned()-Schreibweise faellt schon
  // vorher weg (IsPassedAsArgBetween scannt nkWhileStmt-Bedingungen und
  // liest 'Assigned(x)' als potentielle var/out-Uebergabe); uebrig bleibt
  // genau die klammerfreie Vergleichsform, die ParseWhileStmt per
  // JoinTokInto als 'x<>nil' ablegt - CondHasGuard hat dieses Muster.
  //
  // NodeContainsRef ist hier PFLICHT, kein Komfort: NACH der Schleife ist
  // die Bedingung per Definition falsch, die Variable also nil. Ohne den
  // Rumpf-Zwang wuerde 'x := nil; while x <> nil do Beep; x.Foo' - ein
  // echter Fund - stillschweigend gedroppt.
  if ADerefNode = nil then Exit;
  Whiles := MethodNode.FindAllRef(nkWhileStmt);
  for WhN in Whiles do
  begin
    if WhN.Line < AfterLine then Continue;
    if WhN.Line > BeforeLine then Continue;
    Low := WhN.TypeRef.ToLower;
    if Low = '' then Continue;
    if not CondHasGuard(Low, VarLow) then Continue;
    if NodeContainsRef(WhN, ADerefNode) then Exit(True);
  end;
end;

class function TNilDerefDetector.IsNilSafeCall(
  const CallNameLow, VarLow: string): Boolean;
// .Free und .Destroy sind nil-sicher (TObject.Free prueft Self <> nil)
// FreeAndNil(varname) ist ebenfalls nil-sicher.
// Wortgrenzen wichtig: 'x.free' soll NICHT 'x.freedom' matchen.
begin
  Result :=
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.free',         CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.destroy',      CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil(' + VarLow,   CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil( ' + VarLow,  CallNameLow);
end;

{ FP-Gate (2026-07-04): out-param-assign - prueft ob VarLow in TextLow als
  eigenstaendiges Argument vorkommt: nach der ersten oeffnenden Klammer, mit
  Identifier-Wortgrenzen und OHNE angrenzenden Punkt (x.var / var.y sind
  Member-Zugriffe, keine Argument-Uebergabe). String-Literale werden vorab
  entfernt, damit 'Log(''lst kaputt'')' nicht als Uebergabe von lst zaehlt
  (Real-World-Audit 2026-07-04, z.B. LoadJson(l, ...) in test.core.data). }
class function TNilDerefDetector.HasBareArgUse(const TextLow,
  VarLow: string): Boolean;
var
  Code   : string;
  ParenP : Integer;
  p, L   : Integer;
  PrevCh : Char;
  NextCh : Char;
begin
  Result := False;
  if (VarLow = '') or (TextLow = '') then Exit;
  Code   := TDetectorUtils.StripStringLiterals(TextLow);
  ParenP := Pos('(', Code);
  if ParenP = 0 then Exit; // ohne Klammer keine Argumentliste
  L := Length(VarLow);
  p := PosEx(VarLow, Code, ParenP + 1);
  while p > 0 do
  begin
    if p > 1 then PrevCh := Code[p - 1] else PrevCh := #0;
    if p + L <= Length(Code) then NextCh := Code[p + L] else NextCh := #0;
    // Wortgrenzen beidseitig; '.' zusaetzlich ausgeschlossen, damit weder
    // 'rec.varname' noch 'varname.prop' (Deref!) als Uebergabe gelten.
    if (not CharInSet(PrevCh, ['a'..'z', '0'..'9', '_', '.'])) and
       (not CharInSet(NextCh, ['a'..'z', '0'..'9', '_', '.'])) then
      Exit(True);
    p := PosEx(VarLow, Code, p + 1);
  end;
end;

{ FP-Gate (2026-07-04): out-param-assign - jede Uebergabe der Variable als
  blankes Argument an einen Aufruf zwischen nil-Zuweisung und Punkt-Zugriff
  zaehlt als Zuweisung (var/out-Parameter wie LoadJson(l, ...) oder
  TInterfaceStub.Create(TypeInfo(...), I) fuellen die Variable). Bewusst
  konservativ-grosszuegig: SCA008 hatte im Real-World-Audit 2026-07-04
  0 TPs bei 21 FPs, davon 7 aus genau diesem Muster. Gescannt werden
  sowohl Call-Statements als auch RHS-Ausdruecke fremder Zuweisungen
  (Stub := TFoo.Create(..., I)). FreeAndNil ist ausgenommen - es laesst
  die Variable nil. }
class function TNilDerefDetector.IsPassedAsArgBetween(MethodNode: TAstNode;
  Calls, Assigns: TList<TAstNode>; const VarLow: string;
  AfterLine, BeforeLine: Integer;
  AExcludeCondA: TAstNode; AExcludeCondB: TAstNode): Boolean;
var
  N       : TAstNode;
  TextLow : string;
  Kind    : TNodeKind;
  Conds   : TList<TAstNode>;
begin
  Result := False;
  for N in Calls do
  begin
    if N.Line <= AfterLine then Continue;
    if N.Line >= BeforeLine then Continue;
    TextLow := N.Name.ToLower;
    // FreeAndNil(x) setzt x auf nil - beendet den nil-Zustand NICHT
    if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
      Continue;
    if HasBareArgUse(TextLow, VarLow) then Exit(True);
  end;
  for N in Assigns do
  begin
    if N.Line <= AfterLine then Continue;
    if N.Line >= BeforeLine then Continue;
    // Neuzuweisungen an die Variable selbst behandelt der Reassigned-Check
    if N.Name.ToLower = VarLow then Continue;
    TextLow := N.TypeRef.ToLower;
    if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
      Continue;
    if HasBareArgUse(TextLow, VarLow) then Exit(True);
  end;

  // FP-Gate (Real-World-FP-Audit 2026-07-10): out-param-Finder-Aufrufe in
  // BEDINGUNGEN ('if FindProcessorByURLSegment(..., lProcessor) then') sind
  // keine nkCall-Knoten, sondern TypeRef-Strings des nkIfStmt/nkWhileStmt/
  // nkCaseStmt. Der Deref steht dann im if-true-Zweig -> die Variable IST vom
  // Finder gefuellt. Dominante SCA008-FP-Klasse 'out-param-assignment-guarded'.
  if MethodNode <> nil then
    for Kind in [nkIfStmt, nkWhileStmt, nkCaseStmt] do
    begin
      Conds := MethodNode.FindAllRef(Kind);
      for N in Conds do
      begin
        // Korrelations-Paar-Ausnahme (Review 2026-07-30): die eigenen
        // Bedingungen von IfA/IfB LESEN die Variable nur ('assigned ( a )').
        // Ohne die Ausnahme vetote IfA sich selbst, sobald AfterLine vor
        // der IfA-Zeile liegt - das Gate droppte die Assigned()-Form nie.
        if (N = AExcludeCondA) or (N = AExcludeCondB) then Continue;
        if N.Line <= AfterLine then Continue;
        if N.Line >= BeforeLine then Continue;
        TextLow := N.TypeRef.ToLower;
        if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
          Continue;
        if HasBareArgUse(TextLow, VarLow) then Exit(True);
      end;
    end;
end;

{ FP-Gate (2026-07-04): for-in-loop-assign - 'for X in ...' weist X bei
  jedem Durchlauf zu, 'for X := a to b' ebenso. Der Header steht seit
  ParseForStmt als Token-Join in TypeRef ('x in <expr>' / 'x := a to b').
  nil-Inits vor solchen Schleifen dienen typisch nur dem except-Handler
  (Real-World-Audit 2026-07-04, z.B. MVCFramework.Serializer.URLEncoded).
  Konservativ: auch ein Deref NACH der Schleife wird unterdrueckt (leere
  Collection waere der einzige Restfall - 0 TPs auf dem Korpus). }
class function TNilDerefDetector.IsForLoopAssigned(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer): Boolean;
var
  Fors : TList<TAstNode>;
  FN   : TAstNode;
  Head : string;
begin
  Result := False;
  Fors := MethodNode.FindAllRef(nkForStmt);
  for FN in Fors do
  begin
    if FN.Line <= AfterLine then Continue;
    if FN.Line > BeforeLine then Continue; // Deref darf im Loop-Body liegen
    Head := FN.TypeRef.ToLower;
    if Head.StartsWith(VarLow + ' in ') or
       Head.StartsWith(VarLow + ' := ') then
      Exit(True);
  end;
end;

function NodeContainsRef(Root, Target: TAstNode): Boolean;
// Subtree-Containment per OBJEKT-Identitaet (TAstNode hat keinen Parent-
// Pointer). Iterative DFS (Hardening-v4-Stil).
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := False;
  if (Root = nil) or (Target = nil) then Exit;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if Cur = Target then Exit(True);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function SameArmHoldsBoth(Container, A, B: TAstNode): Boolean;
// ARM-GENAUE Containment-Pruefung (SCA008-Autopsie 2026-08-27, Skeptiker-
// MAJOR zur Nested-Guard-Lockerung). NodeContainsRef allein beweist NICHT,
// dass zwei Knoten gemeinsam laufen: ein if enthaelt then- UND else-Zweig,
// ein case alle Arme. Genau daran haette die naive Fassung den TP-Fall
//   if c then x := nil else begin if x = nil then Exit end;  x.Foo
// gedroppt (Korpus-Vorbild cnwizards CnEditorToggleVar.pas:293/304/350).
// True nur wenn A UND B im GLEICHEN Arm des Containers stehen:
//   * nkIfStmt   - beide im then-Teil oder beide im else-Zweig
//   * nkCaseStmt - beide im selben nkCaseArm (Arme sind Direktkinder,
//                  ParseCaseStmt Z. ~2454/2463)
//   * Schleifen  - beide im (einzigen) Rumpf, also in derselben Iteration
//                  erreichbar
// Einer drin / einer draussen oder verschiedene Arme -> False (konservativ).
var
  ElseN            : TAstNode;
  Arm, ArmA, ArmB  : TAstNode;
  AInElse, BInElse : Boolean;
  i                : Integer;
begin
  Result := False;
  if (Container = nil) or (A = nil) or (B = nil) then Exit;
  if not NodeContainsRef(Container, A) then Exit;
  if not NodeContainsRef(Container, B) then Exit;
  case Container.Kind of
    nkIfStmt:
      begin
        ElseN := Container.FindFirstChild(nkElseBranch);
        if ElseN = nil then Exit(True);   // nur ein Arm - kein Zweig moeglich
        AInElse := NodeContainsRef(ElseN, A);
        BInElse := NodeContainsRef(ElseN, B);
        Result  := (AInElse = BInElse);
      end;
    nkCaseStmt:
      begin
        ArmA := nil;
        ArmB := nil;
        for i := 0 to Container.Children.Count - 1 do
        begin
          Arm := Container.Children[i];
          if Arm.Kind <> nkCaseArm then Continue;
          if (ArmA = nil) and NodeContainsRef(Arm, A) then ArmA := Arm;
          if (ArmB = nil) and NodeContainsRef(Arm, B) then ArmB := Arm;
        end;
        // Liegt einer der beiden ausserhalb jedes Arms (Selektor-Ausdruck,
        // Malformed-Recovery), ist die Arm-Frage nicht entscheidbar -> False.
        Result := (ArmA <> nil) and (ArmA = ArmB);
      end;
  else
    // while/for/repeat: genau ein Rumpf.
    Result := True;
  end;
end;

class function TNilDerefDetector.IsInExclusiveBranch(MethodNode, AssignNode,
  DerefNode: TAstNode): Boolean;
// FP-Gate (Auto-Runde 2026-07-19, Triage 15/18 FP - Sub-Klasse 'syntactic-
// sibling-if-else' 3/18 + JvLookOut): steht die nil-Zuweisung im then-Zweig
// eines if und der Deref im zugehoerigen else-Zweig (oder umgekehrt), laufen
// beide auf keiner realen Ausfuehrung gemeinsam - die nil-Zuweisung erreicht
// den Deref nie. AST-verifiziert: ParseIfStmt legt then-Statements als
// Descendants des nkIfStmt ab, else-Statements unter ein nkElseBranch-
// Direktkind (uParser2 ~Z.1751-1758). Rein strukturell, additiv, monoton:
// ohne trennendes if/else bleibt jeder Fund. Vorbild-FPs: Alcinoe.Common
// (Temp.DisposeOf), JvChangeNotify (FThread.WaitFor), JvGIF, JvLookOut.
// Die KORRELIERTE Separat-if-Klasse (2 verschiedene ifs mit gekoppelten
// Bedingungen) bleibt bewusst offen - braucht Mini-CFG (strukturell hart).
var
  Ifs   : TList<TAstNode>;
  IfN   : TAstNode;
  ElseN : TAstNode;
  NAInElse, CInElse, NAInThen, CInThen : Boolean;
begin
  Result := False;
  if MethodNode = nil then Exit;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  for IfN in Ifs do
  begin
    ElseN := IfN.FindFirstChild(nkElseBranch);
    if ElseN = nil then Continue;           // ohne else keine Schwester-Zweige
    // then-Zweig = im if-Subtree, aber NICHT im else-Subtree.
    NAInElse := NodeContainsRef(ElseN, AssignNode);
    CInElse  := NodeContainsRef(ElseN, DerefNode);
    NAInThen := NodeContainsRef(IfN, AssignNode) and not NAInElse;
    CInThen  := NodeContainsRef(IfN, DerefNode)  and not CInElse;
    if (NAInThen and CInElse) or (NAInElse and CInThen) then
      Exit(True);
  end;
end;

function IsPlainIdentLower(const S: string): Boolean;
// Einfacher Bezeichner (bereits gelowert): [a-z_][a-z0-9_]*. Bewusst KEINE
// dotted-/indizierten Formen - die Korrelations-Gates (#6 Inkr.3) arbeiten
// nur auf nebenwirkungsfreien, exakt trackbaren Bedingungen.
var
  i : Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not CharInSet(S[1], ['a'..'z', '_']) then Exit;
  for i := 2 to Length(S) do
    if not CharInSet(S[i], ['a'..'z', '0'..'9', '_']) then Exit;
  Result := True;
end;

function CondNormNoWs(const S: string): string;
// lowercase + saemtliche Whitespaces entfernt - eindeutig fuer Operator-/
// Klammer-Formen ('x = nil' == 'x=nil'). NICHT fuer bare/'not x'-Formen
// verwenden ('not a' wuerde zum Ident 'nota' verschmelzen).
var
  i : Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if not CharInSet(S[i], [' ', #9]) then
      // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
      // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
      // noinspection StringConcatInLoop
      Result := Result + S[i];
  Result := LowerCase(Result);
end;

function ParseCorrelatedCond(const ARaw: string; out ACore: string;
  out APos: Boolean): Boolean;
// #6 Inkr.3 (Form c): zerlegt eine if-Bedingung in (Kern-Ident, kanonische
// Polaritaet). Kanonisch True = 'Flag wahr' bzw. 'Var assigned'. NUR die
// exakte Whitelist nebenwirkungsfreier Formen (Lehre SCA001-XL: Konventions-
// Checks nur im Original-Wortlaut; alles andere => nicht korrelierbar):
//   a            -> (a, True)      not a           -> (a, False)
//   v <> nil     -> (v, True)      v = nil         -> (v, False)
//   nil <> v     -> (v, True)      nil = v         -> (v, False)
//   Assigned(v)  -> (v, True)      not Assigned(v) -> (v, False)
var
  S1, S2    : string;
  i         : Integer;
  Ch        : Char;
  PrevSpace : Boolean;
begin
  Result := False;
  ACore  := '';
  APos   := True;
  // S1: lower + Whitespace-Runs zu EINEM Blank kollabiert + getrimmt
  S1 := '';
  PrevSpace := True;
  for i := 1 to Length(ARaw) do
  begin
    Ch := ARaw[i];
    if CharInSet(Ch, [' ', #9]) then
    begin
      // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
      // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
      // noinspection StringConcatInLoop
      if not PrevSpace then S1 := S1 + ' ';
      PrevSpace := True;
    end
    else
    begin
      S1 := S1 + Ch;
      PrevSpace := False;
    end;
  end;
  S1 := LowerCase(Trim(S1));
  if S1 = '' then Exit;
  // bare Ident / 'not <ident>' auf der Blank-kollabierten Form
  if IsPlainIdentLower(S1) then
  begin
    ACore := S1;
    APos  := True;
    Exit(True);
  end;
  if S1.StartsWith('not ') and IsPlainIdentLower(Copy(S1, 5, MaxInt)) then
  begin
    ACore := Copy(S1, 5, MaxInt);
    APos  := False;
    Exit(True);
  end;
  // Operator-/Klammer-Formen auf der vollgestrippten Form
  S2 := CondNormNoWs(S1);
  if S2.StartsWith('assigned(') and S2.EndsWith(')') then
  begin
    ACore := Copy(S2, 10, Length(S2) - 10);
    APos  := True;
  end
  else if S2.StartsWith('notassigned(') and S2.EndsWith(')') then
  begin
    ACore := Copy(S2, 13, Length(S2) - 13);
    APos  := False;
  end
  else if S2.StartsWith('nil<>') then
  begin
    ACore := Copy(S2, 6, MaxInt);
    APos  := True;
  end
  else if S2.StartsWith('nil=') then
  begin
    ACore := Copy(S2, 5, MaxInt);
    APos  := False;
  end
  else if S2.EndsWith('<>nil') then
  begin
    ACore := Copy(S2, 1, Length(S2) - 5);
    APos  := True;
  end
  else if S2.EndsWith('=nil') then
  begin
    ACore := Copy(S2, 1, Length(S2) - 4);
    APos  := False;
  end
  else
    Exit(False);
  Result := IsPlainIdentLower(ACore);
end;

function HasNilTestEarlyExitBetween(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer;
  ADeref: TAstNode): Boolean;
// #6 Inkr.3 (SCA008 Form d): 'x := nil; ... if x = nil then Exit; ... x.Foo'.
// Der Header behauptete diese Abdeckung schon immer, CondHasGuard hatte das
// '= nil'-Pattern aber nie (Leser-Audit 2026-07-23). Ein nil-Test zwischen
// nil-Zuweisung und Deref, dessen then-Teil GARANTIERT terminiert (Exit/
// raise direkt oder als Direktkind des then-Blocks), toetet die nil-
// Definition auf dem Fall-through-Pfad - der Deref laeuft nur mit x <> nil.
// Konservativ: zusammengesetzte Bedingungen ('(x=nil) and ...') und nur
// MOEGLICHERWEISE terminierende then-Teile korrelieren nicht -> kein Drop.
// SOUNDNESS (Selbst-Review 2026-07-24): der Guard toetet die Definition nur,
// wenn er auf JEDEM Pfad NA->C liegt. Ein Guard, der selbst in einem anderen
// if/case/Loop geschachtelt ist, laeuft nicht auf jedem Pfad ('if y then
// begin if x = nil then Exit; end; x.Foo' - bei y=False faellt der nil-Wert
// durch; 'while c do if x = nil then Exit;' - 0 Iterationen moeglich).
// Solche geschachtelten Guards werden uebersprungen -> kein Drop.
//
// LOCKERUNG (SCA008-Autopsie 2026-08-27, 1 Drop): der Pfad-Einwand gilt nur,
// solange der DEREF ausserhalb des Containers liegt. Steht er im SELBEN ARM
// wie der Guard, fuehrt jeder Pfad zum Deref durch den Guard - und der Drop
// ist wieder sauber. Korpus-Vorbild cnwizards CnEditorToggleVar.pas:
// 'AProcInfo := nil' (Z.304), 'if AProcInfo = nil then Exit' (Z.350/351) und
// der Deref (Z.392) liegen alle im else-Arm desselben if (Z.293).
// ARM-genau, nicht Container-genau: die Container-Variante wuerde
// 'if c then x := nil else begin if x = nil then Exit end; x.Foo' droppen,
// obwohl das ein echter Fund ist (Skeptiker-MAJOR) - siehe SameArmHoldsBoth.
// ADeref = nil laesst die alte, voll konservative Fassung stehen.
var
  Ifs        : TList<TAstNode>;
  IfN        : TAstNode;
  SubCh      : TAstNode;
  GrandCh    : TAstNode;
  ThenChild  : TAstNode;
  Cond       : string;
  Terminates : Boolean;
  Nested     : Boolean;
  Kind       : TNodeKind;
  Containers : TList<TAstNode>;
  Cont       : TAstNode;
begin
  Result := False;
  if MethodNode = nil then Exit;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  for IfN in Ifs do
  begin
    if IfN.Line <= AfterLine then Continue;
    if IfN.Line >= BeforeLine then Continue;
    Cond := CondNormNoWs(IfN.TypeRef);
    if (Cond <> VarLow + '=nil') and (Cond <> 'nil=' + VarLow) and
       (Cond <> 'notassigned(' + VarLow + ')') then Continue;
    // Guard darf nicht selbst in einem Branch/Loop geschachtelt sein -
    // ausser der Deref liegt im SELBEN Arm dieses Containers (dann fuehrt
    // jeder Pfad zum Deref durch den Guard, siehe Kopfkommentar).
    Nested := False;
    for Kind in [nkIfStmt, nkCaseStmt, nkWhileStmt, nkForStmt, nkRepeatStmt] do
    begin
      Containers := MethodNode.FindAllRef(Kind);
      for Cont in Containers do
        if (Cont <> IfN) and NodeContainsRef(Cont, IfN) and
           not SameArmHoldsBoth(Cont, IfN, ADeref) then
        begin
          Nested := True;
          Break;
        end;
      if Nested then Break;
    end;
    if Nested then Continue;
    ThenChild := nil;
    for SubCh in IfN.Children do
      if SubCh.Kind <> nkElseBranch then
      begin
        ThenChild := SubCh;
        Break;
      end;
    if ThenChild = nil then Continue;
    Terminates := ThenChild.Kind in [nkExit, nkRaise];
    if (not Terminates) and (ThenChild.Kind = nkBlock) then
      for GrandCh in ThenChild.Children do
        if GrandCh.Kind in [nkExit, nkRaise] then
        begin
          Terminates := True;
          Break;
        end;
    if Terminates then Exit(True);
  end;
end;

function ParseNilPredicate(const ARaw: string; out ACore: string;
  out APos: Boolean): Boolean;
// Wie ParseCorrelatedCond, aber NUR die echten nil-PRAEDIKATE
// ('v <> nil', 'v = nil', 'nil <> v', 'nil = v', 'Assigned(v)',
// 'not Assigned(v)'). Die blanken Formen der Whitelist ('v' / 'not v')
// sind hier verboten: 'b := v' kopiert den ZEIGER, ist also kein nil-Test -
// 'if b then v.Foo' waere dann gar kein Guard, sondern ein Alias-Deref.
//
// Erkennungsmerkmal ist NICHT 'enthaelt nil' (ein Bezeichner darf so
// heissen - 'b := nilCount' waere sonst ein Praedikat), sondern die
// Struktur: bei den bare-Formen ist die vollgestrippte Bedingung exakt der
// Kern-Ident, bei 'not x' exakt 'not' davor. Alles andere der Whitelist ist
// per Konstruktion eine Vergleichs- oder Assigned-Form.
var
  S : string;
begin
  Result := ParseCorrelatedCond(ARaw, ACore, APos);
  if not Result then Exit;
  S := CondNormNoWs(ARaw);
  Result := (S <> ACore) and (S <> 'not' + ACore);
end;

function HasBoolAliasGuard(MethodNode: TAstNode;
  Calls, Assigns: TList<TAstNode>; const VarLow: string;
  ANilAssign, ADeref: TAstNode): Boolean;
// FP-Gate (SCA008-Autopsie 2026-08-27, 7 Drops): Ein-Schritt-Kopier-
// propagation ueber eine Boolean-Zwischenvariable.
//   v := nil; ... b := v <> nil; ... if b then v.Foo;
// Der Detektor sieht nur 'if b' und erkennt darin keinen nil-Guard, obwohl
// b nichts anderes ist als das gespeicherte Praedikat. Beide Polaritaeten
// werden korrekt verrechnet: im erreichten Arm gilt b = (PosCond xor
// InElse), geschuetzt ist er genau dann, wenn dieser Wert die Aussage
// 'v <> nil' traegt (b = PosRhs).
//
// *** SKEPTIKER-MAJOR (Autopsie 2026-08-27): ohne Dominanz-Zwang ist das
// Gate ein TP-FRESSER. Bei
//     Result := True; v := nil; if c then Result := v <> nil;
//     if Result then v.Foo;
// laeuft die b-Zuweisung NICHT auf jedem Pfad - bei c = False traegt
// Result noch das alte True und der Deref sieht nil. Deshalb: die
// b-Zuweisung darf in KEINEM Branch/Loop stecken, der nicht auch das
// Guard-if im selben Arm enthaelt (SameArmHoldsBoth), und b darf im
// Fenster weder neu zugewiesen noch als var/out-Argument uebergeben
// werden. ***
//
// Fenster-Rezept identisch zu IsInCorrelatedExclusiveIfs: umschliesst eine
// SCHLEIFE die b-Zuweisung oder das Guard-if, wird je Iteration neu
// ausgewertet - dann zaehlt die GANZE Methode als Mutations-Fenster, weil
// eine Mutation hinter dem Deref im naechsten Durchlauf VOR dem Guard liegt.
var
  Ifs, Loops, Containers : TList<TAstNode>;
  BA, IfN, ElseN, Cont, N : TAstNode;
  Kind                    : TNodeKind;
  BName, CoreRhs, CoreCond, NmLow : string;
  PosRhs, PosCond, InElse : Boolean;
  Nested, Mutated         : Boolean;
  WinStart, WinEnd        : Integer;
begin
  Result := False;
  if (MethodNode = nil) or (ANilAssign = nil) or (ADeref = nil) then Exit;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  for BA in Assigns do
  begin
    if BA.Line <= ANilAssign.Line then Continue;
    if BA.Line >= ADeref.Line then Continue;
    // Billig-Vorfilter vor der Normalisierung: die kuerzesten Praedikate der
    // Whitelist sind 'v=nil' und 'nil=v' - VIER Zeichen ueber dem Variablen-
    // namen (JoinTokInto setzt um '=' und '<>' kein Blank). Kuerzere RHS
    // koennen die Whitelist nie passieren.
    if Length(BA.TypeRef) < Length(VarLow) + 4 then Continue;
    BName := BA.Name.ToLower;
    // Nur einfache lokale Flags - dotted/indizierte Ziele ('rec.f', 'a[]')
    // sind nicht exakt trackbar (Lehre SCA001-XL: nur der Original-Wortlaut).
    if not IsPlainIdentLower(BName) then Continue;
    if BName = VarLow then Continue;
    if not ParseNilPredicate(BA.TypeRef, CoreRhs, PosRhs) then Continue;
    if CoreRhs <> VarLow then Continue;

    for IfN in Ifs do
    begin
      if IfN.Line < BA.Line then Continue;
      if IfN.Line > ADeref.Line then Continue;
      // Die b-Zuweisung muss VOR dem Guard-if stehen, nicht darin:
      // 'if b then begin b := v <> nil; v.Foo; end' testet das ALTE b, der
      // Deref laeuft dort unbedingt - das waere ein echter Fund.
      if NodeContainsRef(IfN, BA) then Continue;
      if not ParseCorrelatedCond(IfN.TypeRef, CoreCond, PosCond) then Continue;
      if CoreCond <> BName then Continue;
      if not NodeContainsRef(IfN, ADeref) then Continue;
      ElseN  := IfN.FindFirstChild(nkElseBranch);
      InElse := (ElseN <> nil) and NodeContainsRef(ElseN, ADeref);
      if (PosCond xor InElse) <> PosRhs then Continue;  // Arm schuetzt nicht

      // Dominanz: b-Zuweisung laeuft auf jedem Pfad zum Guard-if?
      Nested := False;
      for Kind in [nkIfStmt, nkCaseStmt, nkWhileStmt, nkForStmt,
                   nkRepeatStmt] do
      begin
        Containers := MethodNode.FindAllRef(Kind);
        for Cont in Containers do
          if NodeContainsRef(Cont, BA) and
             not SameArmHoldsBoth(Cont, BA, IfN) then
          begin
            Nested := True;
            Break;
          end;
        if Nested then Break;
      end;
      if Nested then Continue;

      // Mutations-Fenster bestimmen (Schleife -> ganze Methode).
      WinStart := BA.Line;
      WinEnd   := ADeref.Line;
      for Kind in [nkWhileStmt, nkForStmt, nkRepeatStmt] do
      begin
        Loops := MethodNode.FindAllRef(Kind);
        for N in Loops do
          if NodeContainsRef(N, BA) or NodeContainsRef(N, IfN) then
          begin
            WinStart := 0;
            WinEnd   := MaxInt;
            Break;
          end;
        if WinEnd = MaxInt then Break;
      end;

      Mutated := False;
      for N in Assigns do
      begin
        if N = BA then Continue;
        if (N.Line < WinStart) or (N.Line > WinEnd) then Continue;
        NmLow := N.Name.ToLower;
        if (NmLow = BName) or NmLow.EndsWith('.' + BName) then
        begin
          Mutated := True;
          Break;
        end;
      end;
      if Mutated then Continue;

      // var/out-Uebergabe von b. IsPassedAsArgBetween arbeitet mit OFFENEN
      // Grenzen (> AfterLine, < BeforeLine) - Start um 1 vorziehen, damit
      // eine Mutation AUF der Zuweisungszeile zaehlt. Das Guard-if ist per
      // Referenz ausgenommen: seine Bedingung hat die ParseCorrelatedCond-
      // Whitelist passiert und ist nebenwirkungsfrei; ohne die Ausnahme
      // vetote 'Assigned(b)' sich selbst (Lehre Review 2026-07-30).
      if TNilDerefDetector.IsPassedAsArgBetween(MethodNode, Calls, Assigns,
           BName, WinStart - 1, WinEnd, IfN) then Continue;

      Exit(True);
    end;
  end;
end;

function IsInCorrelatedExclusiveIfs(MethodNode: TAstNode;
  Calls, Assigns: TList<TAstNode>; AssignNode, DerefNode: TAstNode): Boolean;
// #6 Inkr.3 (SCA008 Form c): korrelierte SEPARAT-ifs - 'if a then x := nil;
// ... if not a then x.Foo'. War in IsInExclusiveBranch explizit als 'braucht
// Mini-CFG' vorgemerkt; AST-Loesung ist praeziser als CFG-Dominanz: das
// innerste einschliessende if liefert Bedingung UND Arm-Polaritaet direkt.
// Drop nur wenn ALLE Bedingungen erfuellt:
//   * NA und C haben verschiedene einschliessende ifs (gleiches if =
//     IsInExclusiveBranch), if(NA) wird VOR if(C) ausgewertet;
//   * beide Bedingungen sind exakt korrelierbar (ParseCorrelatedCond-
//     Whitelist) mit demselben Kern-Ident;
//   * die effektiven Ausfuehrungs-Polaritaeten schliessen sich aus
//     (ExecX = Pos xor InElse; exklusiv gdw. ExecA <> ExecB);
//   * die Korrelations-Variable mutiert nicht im Fenster - kein Assign
//     und keine var/out-Uebergabe; umschliesst eine SCHLEIFE auch nur
//     EINES der ifs, gilt die GANZE Methode als Fenster (je Iteration
//     neu ausgewertet - eine Mutation vor IfA/nach IfB liegt im
//     naechsten Durchlauf ZWISCHEN den Auswertungen; Review 2026-07-28).
var
  Ifs          : TList<TAstNode>;
  Loops        : TList<TAstNode>;
  IfN, ElseN   : TAstNode;
  IfA, IfB     : TAstNode;
  AInElse      : Boolean;
  BInElse      : Boolean;
  CoreA, CoreB : string;
  PosA, PosB   : Boolean;
  ExecA, ExecB : Boolean;
  WindowStart  : Integer;
  WindowEnd    : Integer;
  Kind         : TNodeKind;
  N            : TAstNode;
  NmLow        : string;
begin
  Result := False;
  if MethodNode = nil then Exit;
  IfA := nil;
  IfB := nil;
  AInElse := False;
  BInElse := False;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  for IfN in Ifs do
  begin
    ElseN := IfN.FindFirstChild(nkElseBranch);
    // innerstes einschliessendes if = das mit der GROESSTEN Startzeile
    // (Vorfahren beginnen frueher als ihre geschachtelten Kinder)
    if NodeContainsRef(IfN, AssignNode) and
       ((IfA = nil) or (IfN.Line > IfA.Line)) then
    begin
      IfA := IfN;
      AInElse := (ElseN <> nil) and NodeContainsRef(ElseN, AssignNode);
    end;
    if NodeContainsRef(IfN, DerefNode) and
       ((IfB = nil) or (IfN.Line > IfB.Line)) then
    begin
      IfB := IfN;
      BInElse := (ElseN <> nil) and NodeContainsRef(ElseN, DerefNode);
    end;
  end;
  if (IfA = nil) or (IfB = nil) or (IfA = IfB) then Exit;
  if IfA.Line >= IfB.Line then Exit;
  if not ParseCorrelatedCond(IfA.TypeRef, CoreA, PosA) then Exit;
  if not ParseCorrelatedCond(IfB.TypeRef, CoreB, PosB) then Exit;
  if CoreA <> CoreB then Exit;
  ExecA := PosA xor AInElse;
  ExecB := PosB xor BInElse;
  if ExecA = ExecB then Exit;   // gleiche Seite -> gemeinsam ausfuehrbar
  // Mutations-Fenster bestimmen. Umschliesst eine Schleife AUCH NUR EINES
  // der beiden ifs, wird je Iteration neu ausgewertet - dann zaehlt die
  // GANZE Methode als Fenster: eine Mutation VOR IfA oder NACH IfB gehoert
  // im naechsten Durchlauf ZWISCHEN die beiden Auswertungen.
  //
  // Review-Fund 2026-07-28 (5-Tage-Review, bestaetigt): die alte
  // AND-Verknuepfung verlangte die Schleife um BEIDE ifs, und die
  // Zeilenvergleiche waren exklusiv. Beides maskierte echte
  // Cross-Iteration-Bugs:
  //   if a then x := nil;
  //   while c do begin
  //     if not a then x.Foo;   // Iteration 2: x = nil
  //     a := not a;            // lag NACH IfB.Line -> unsichtbar
  //   end;
  // sowie die Einzeiler-Mutation 'if a then begin x := nil; a := False;
  // end;' (Mutation AUF IfA.Line, von '> IfA.Line' ausgeschlossen).
  WindowStart := IfA.Line;
  WindowEnd   := IfB.Line;
  for Kind in [nkWhileStmt, nkForStmt, nkRepeatStmt] do
  begin
    Loops := MethodNode.FindAllRef(Kind);
    for N in Loops do
      if NodeContainsRef(N, IfA) or NodeContainsRef(N, IfB) then
      begin
        WindowStart := 0;
        WindowEnd   := MaxInt;
        Break;
      end;
    if WindowEnd = MaxInt then Break;
  end;
  for N in Assigns do
    if (N.Line >= WindowStart) and (N.Line <= WindowEnd) then
    begin
      NmLow := N.Name.ToLower;
      if (NmLow = CoreA) or NmLow.EndsWith('.' + CoreA) then Exit;
    end;
  // IsPassedAsArgBetween prueft mit OFFENEN Grenzen (> AfterLine,
  // < BeforeLine): Start um 1 vorziehen, damit Call-Mutationen AUF der
  // IfA-Zeile zaehlen. IfA/IfB selbst sind per Referenz ausgenommen: ihre
  // Bedingungen haben die ParseCorrelatedCond-Whitelist passiert und sind
  // nebenwirkungsfrei - ohne die Ausnahme vetote IfAs eigenes
  // 'assigned ( a )' den Drop, die Assigned()-Form wurde nie gedroppt
  // (Review-Fund 2026-07-30). Das Ende bleibt exklusiv (WindowEnd+1
  // ueberliefe bei MaxInt); bekannter konservativer Rest: eine CALL-
  // Mutation exakt auf der IfB-Zeile (Mehrfach-Statement-Einzeiler)
  // bleibt unsichtbar - der Assign-Scan oben deckt nur nkAssign ab.
  if TNilDerefDetector.IsPassedAsArgBetween(MethodNode, Calls, Assigns,
       CoreA, WindowStart - 1, WindowEnd, IfA, IfB) then Exit;
  Result := True;
end;

function CfgDropsNilDeref(MethodNode: TAstNode; var ACfg: TCFG;
  ANilAssign, ADeref: TAstNode): Boolean;
// #6 Inkr.2 (SCA008 Q1, CFG Shared Service): Drop, wenn der Deref im CFG
// vom nil-Block aus UNERREICHBAR ist. Killt die zwei Formen, die die
// lexikalischen Gates nicht sehen (Leser-Audit 2026-07-23):
//   (a) nil-Zuweisung in terminierendem Zweig - 'if Fail then begin
//       x := nil; Exit; end; ... x.Foo': der nil-Block verbindet nur zu
//       Exit_ (bzw. Handler), nie zum Deref;
//   (b) case-Arm-Geschwister - 'case k of 0: x := nil; 1: x.Foo; end':
//       Arme sind nie gemeinsam ausfuehrbar; IsInExclusiveBranch deckt
//       nur then/else DESSELBEN if ab.
// Rezept = SCA134 (uUseAfterFree.CfgFilterDropsFinding), aber Block-Lookup
// primaer per AST-Node-IDENTITAET (der Builder legt exakt dieselben
// nkAssign-/nkCall-Instanzen in Block.AstNodes ab, uCFG A.4.2); Zeilen-
// Fallback nur fuer den Deref (ein nkCall als RHS-Ausdruck ist kein
// eigenes CFG-Statement, nur der umgebende nkAssign liegt im Block).
// KONSERVATIV: Lookup-Fehlschlag oder Same-Block (sequentiell erreichbar)
// => False = kein Drop. ACfg wird LAZY gebaut - erst wenn ein Kandidat
// alle billigen Gates ueberlebt hat - und gehoert dem Aufrufer (Free).
var
  B        : TCFGBlock;
  N        : TAstNode;
  NilBlk   : TCFGBlock;
  DerefBlk : TCFGBlock;
begin
  Result := False;
  if (MethodNode = nil) or (ANilAssign = nil) or (ADeref = nil) then Exit;
  if ACfg = nil then
    ACfg := TCFGBuilder.BuildFromMethod(MethodNode);
  NilBlk   := nil;
  DerefBlk := nil;
  for B in ACfg.Blocks do
    for N in B.AstNodes do
    begin
      if N = ANilAssign then NilBlk   := B;
      if N = ADeref     then DerefBlk := B;
    end;
  if DerefBlk = nil then
    // Zeilen-Fallback (erster Treffer, wie uUseAfterFree.FindBlockForLine).
    for B in ACfg.Blocks do
    begin
      for N in B.AstNodes do
        if N.Line = ADeref.Line then
        begin
          DerefBlk := B;
          Break;
        end;
      if DerefBlk <> nil then Break;
    end;
  if (NilBlk = nil) or (DerefBlk = nil) then Exit;
  if NilBlk = DerefBlk then Exit;
  Result := not ACfg.CanReach(NilBlk, DerefBlk);
end;

function DeclaredTypeIsNilValue(const ATypeLow: string): Boolean;
// True wenn der deklarierte Typ nil als WERT traegt statt als Zeiger. Dort
// ist 'v := nil' eine Leerung (Laenge 0 / kein Wert), kein Nullen einer
// Referenz - ein Member-Zugriff darauf kann konstruktiv keine AV ausloesen:
//   * dynamische Arrays  'array of T' und 'TArray<T>'
//   * Nullable<T>-Wrapper (Spring4D-Stil)
//
// ZWEI SCHREIBWEISEN, beide belegt im Parser: die klassische var-Sektion
// konkateniert die Typ-Tokens OHNE Trenner ('arrayoftobject',
// ParseVarLikeSection Z.2004 - dieselbe Form, die uUninitVar Z.551 nennt),
// Parameter / Inline-var / for-var joinen dagegen mit JoinTokInto bzw. Blank
// ('array of TObject'). Wer nur eine der beiden prueft, verfehlt die Haelfte.
//
// Konservativ ausgelassen: 'packed array of T' (kein 'arrayof'-Praefix in
// der trennerlosen Form) und qualifizierte Namen ('System.TArray<T>') -
// dort bleibt der Fund stehen. Statische Arrays matchen bewusst NICHT
// ('array[0..3]ofByte' hat weder das Praefix noch ' array of ').
begin
  Result := ATypeLow.StartsWith('tarray<') or
            ATypeLow.StartsWith('arrayof') or
            ATypeLow.StartsWith('nullable<') or
            (Pos('array of', ATypeLow) > 0);
end;

function ResolvedTypeIsNilValue(MethodNode: TAstNode;
  const VarLow: string): Boolean;
// FP-Gate (SCA008-Autopsie 2026-08-27, 5 Drops): loest den DEKLARIERTEN Typ
// der nil-gesetzten Variable im Methoden-Subtree auf (lokale Variablen und
// Parameter) und droppt, wenn nil dort ein Wert ist (DeclaredTypeIsNilValue).
//
// Findet sich KEINE Deklaration (Feld der Klasse, Unit-Variable, Import),
// bleibt der Fund stehen - der Methodenknoten traegt diese Deklarationen
// nicht, Raten waere hier eine stille Suppression. Bei MEHREREN Treffern
// gleichen Namens (verschattete Inline-vars) wird nur gedroppt, wenn JEDE
// Deklaration ein Werttyp ist; eine einzige Referenz-Deklaration macht den
// Deref wieder moeglich.
var
  Decls : TList<TAstNode>;
  D     : TAstNode;
  Kind  : TNodeKind;
  Nm    : string;
  Sp    : Integer;
  Found : Boolean;
begin
  Result := False;
  Found  := False;
  if MethodNode = nil then Exit;
  for Kind in [nkLocalVar, nkParam] do
  begin
    Decls := MethodNode.FindAllRef(Kind);
    for D in Decls do
    begin
      Nm := D.Name.ToLower;
      // nkParam.Name traegt den Modifier ('const x', 'var f', 'out o') -
      // der Bezeichner ist der Teil hinter dem letzten Blank.
      Sp := LastDelimiter(' ', Nm);
      if Sp > 0 then Nm := Copy(Nm, Sp + 1, MaxInt);
      if Nm <> VarLow then Continue;
      Found := True;
      if not DeclaredTypeIsNilValue(D.TypeRef.ToLower) then Exit(False);
    end;
  end;
  Result := Found;
end;

class procedure TNilDerefDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  const ADirLines: TArray<Integer>);
var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  NA      : TAstNode;
  VarLow  : string;
  F       : TLeakFinding;
  CfgGraph: TCFG;      // lazy (CfgDropsNilDeref), Free im finally
begin
  Assigns := MethodNode.FindAllRef(nkAssign);
  Calls   := MethodNode.FindAllRef(nkCall);
  CfgGraph := nil;
  try
    for NA in Assigns do
    begin
      // Nur direkte nil-Zuweisungen: 'varname := nil'
      if NA.TypeRef.ToLower <> 'nil' then Continue;
      // Feldwerte (obj.field := nil) ueberspringen - Cleanup-Muster
      if Pos('.', NA.Name) > 0 then Continue;
      // FP-Gate (SCA008-Autopsie 2026-08-27, 4 Drops): indizierte Ziele.
      // ParsePrimary kollabiert jeden Index-Ausdruck zu '[]' ('fItems[i]'
      // -> 'fItems[]'), der Index steht im AST also NIRGENDS. Damit sind
      // 'a[i] := nil' und 'a[j].Foo' fuer den zeilenbasierten Abgleich
      // ununterscheidbar - Element-Tracking waere hier reines Raten
      // (zusaetzlich Aliasing ueber zwei Namen auf dasselbe Array). Alle
      // vier Faelle der 40er-Stichprobe waren FP mit verifiziertem Guard
      // am tatsaechlich benutzten Element.
      if Pos('[', NA.Name) > 0 then Continue;

      VarLow := NA.Name.ToLower;
      if VarLow = '' then Continue;
      // Self oder Result als Variablenname ueberspringen
      if (VarLow = 'self') or (VarLow = 'result') then Continue;
      // FP-Gate (SCA008-Autopsie 2026-08-27, 5 Drops): Werttyp - bei
      // 'array of T' / 'TArray<T>' / 'Nullable<T>' ist nil ein WERT, kein
      // Zeiger; ein Deref darauf kann keine AV sein. Einmal je nil-
      // Zuweisung aufgeloest, nicht je Kandidatenpaar.
      if ResolvedTypeIsNilValue(MethodNode, VarLow) then Continue;

      for var C in Calls do
      begin
        if C.Line <= NA.Line then Continue;

        var NameLow := C.Name.ToLower;
        // Punkt-Zugriff 'varname.' im Call-Namen?
        // Wortgrenze pruefen: muss am Anfang oder nach Nicht-Bezeichner stehen
        var p := Pos(VarLow + '.', NameLow);
        if p = 0 then Continue;
        if p > 1 then
        begin
          var Prev := NameLow[p - 1];
          // Auto-Runde 2026-07-19: '.' in der Prev-Menge - 'fUnits[0].Editor.
          // Activate' matcht sonst die LOKALE Var 'Editor', obwohl dort der
          // MEMBER eines anderen Objekts steht (Namenskollision; analog
          // HasBareArgUse). Bei fuehrendem '.' ist es nie die lokale Var.
          if CharInSet(Prev, ['a'..'z', '0'..'9', '_', '.']) then Continue;
        end;

        // .Free / .Destroy sind nil-sicher
        if IsNilSafeCall(NameLow, VarLow) then Continue;

        // Neuzuweisung zwischen nil und Zugriff?
        var Reassigned := False;
        for var A in Assigns do
        begin
          if A = NA then Continue;
          if A.Line <= NA.Line then Continue;
          if A.Line >= C.Line  then Break;
          if A.Name.ToLower <> VarLow then Continue;
          if A.TypeRef.ToLower <> 'nil' then
          begin
            Reassigned := True;
            Break;
          end;
        end;
        if Reassigned then Continue;

        // Guard via If-Bedingung zwischen nil und Zugriff - oder via
        // while-Kopf, wenn der Deref im Schleifenrumpf liegt (Autopsie
        // 2026-08-27, 1 Drop).
        if HasGuardingIf(MethodNode, VarLow, NA.Line, C.Line, C) then Continue;

        // FP-Gate (SCA008-Autopsie 2026-08-27, 7 Drops): das nil-Praedikat
        // steht in einer Boolean-Zwischenvariable ('b := v <> nil; ...
        // if b then v.Foo'). Ein-Schritt-Kopierpropagation mit Dominanz-
        // und Mutations-Zwang - siehe HasBoolAliasGuard.
        if HasBoolAliasGuard(MethodNode, Calls, Assigns, VarLow, NA, C) then
          Continue;

        // FP-Gate (2026-07-04): out-param-assign - Variable wurde zwischen
        // nil und Zugriff als Argument uebergeben (var/out-Zuweisung)?
        if IsPassedAsArgBetween(MethodNode, Calls, Assigns, VarLow, NA.Line, C.Line) then
          Continue;

        // FP-Gate (2026-07-04): for-in-loop-assign - Variable ist
        // Schleifenvariable eines for zwischen nil und Zugriff?
        if IsForLoopAssigned(MethodNode, VarLow, NA.Line, C.Line) then
          Continue;

        // FP-Gate (Real-World-FP-Audit 2026-07-12): preprocessor-branch -
        // liegt eine {$IFDEF}-Direktiven-Grenze STRIKT zwischen nil-Zuweisung
        // und Deref, stehen beide in sich ausschliessenden Kompilierungs-
        // Zweigen ({$IFDEF x} var := nil {$ELSE} var.Method {$ENDIF}). Nur
        // die conditional-compilation-Teilklasse der mutually-exclusive-
        // branches-FPs; die runtime-if/else-Teilklasse bleibt bewusst offen
        // (braucht then/else-Scope). TP-sicher: ohne Direktive dazwischen
        // bleibt jeder Fund erhalten.
        if DirLineBetween(ADirLines, NA.Line, C.Line) then
          Continue;

        // FP-Gate (Auto-Runde 2026-07-19): mutually-exclusive-branches
        // (syntactic-sibling-if-else) - nil-Zuweisung (NA) und Deref (C) in
        // then/else-Schwesterzweigen desselben if -> nie gemeinsam ausgefuehrt.
        if IsInExclusiveBranch(MethodNode, NA, C) then
          Continue;

        // FP-Gate #6 Inkr.3 (Form d): nil-Test-Early-Exit zwischen nil
        // und Deref ('if x = nil then Exit;') toetet die nil-Definition
        // auf dem Fall-through-Pfad.
        if HasNilTestEarlyExitBetween(MethodNode, VarLow, NA.Line, C.Line, C) then
          Continue;

        // FP-Gate #6 Inkr.3 (Form c): korrelierte Separat-ifs mit exakt
        // negierten/gleichen Bedingungen auf exklusiven Seiten.
        if IsInCorrelatedExclusiveIfs(MethodNode, Calls, Assigns, NA, C) then
          Continue;

        // FP-Gate #6 Inkr.2 (2026-07-23): CFG-Erreichbarkeit (Q1) - die
        // nil-Zuweisung erreicht den Deref im Kontrollfluss nie (termi-
        // nierter Zweig / case-Arm-Geschwister). Bewusst LETZTES Gate:
        // der CFG wird nur fuer Kandidaten gebaut, die alle billigen
        // Gates ueberlebt haben (Perf-Regel der -25%-Kampagne).
        if CfgDropsNilDeref(MethodNode, CfgGraph, NA, C) then
          Continue;

        // Befund: nil-Zuweisung ohne Guard, dann Punkt-Zugriff
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(C.Line);
        F.MissingVar := NA.Name + ' := nil (line ' + IntToStr(NA.Line) + ')';
        F.SetKind(fkNilDeref);
        Results.Add(F);
        Break; // Pro nil-Zuweisung nur einmal melden
      end;
    end;
  finally
    CfgGraph.Free;   // nil-sicher; lazy gebaut in CfgDropsNilDeref
  end;
end;

class procedure TNilDerefDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods  : TList<TAstNode>;
  M        : TAstNode;
  CondR    : TList<TAstNode>;
  DirLines : TArray<Integer>;
  R        : TAstNode;
  n        : Integer;
begin
  // Real-World-FP-Audit 2026-07-12 (preprocessor-branch): {$IFDEF}-Direktiven-
  // Zeilen aus den nkConditionalRange-Markern sammeln (Start=Node.Line,
  // Ende=TypeRef). Marker liegen am Unit-Node (nicht pro Methode) - hier einmal
  // sammeln und in AnalyzeMethod durchreichen. Muster analog uDeadCode.
  CondR := UnitNode.FindAllRef(nkConditionalRange);
  n := 0;
  SetLength(DirLines, CondR.Count * 2);
  for R in CondR do
  begin
    DirLines[n] := R.Line; Inc(n);
    DirLines[n] := StrToIntDef(R.TypeRef, R.Line); Inc(n);
  end;

  Methods := UnitNode.FindAllRef(nkMethod);
  for M in Methods do
    AnalyzeMethod(M, FileName, Results, DirLines);
end;

end.
