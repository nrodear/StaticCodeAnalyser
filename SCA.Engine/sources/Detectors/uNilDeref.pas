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
//   - .Free / .Destroy           (TObject.Free ist nil-safe)
//   - Foo(obj) / x := Foo(obj)   (Uebergabe als Argument = potentielle
//                                 var/out-Zuweisung, beendet nil-Zustand)
//   - for obj in ... / for obj := (Schleife weist obj zu)
//
// Nicht erkannt (bewusst):
//   - obj.field := nil           (Cleanup-Muster)
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
    // Pruefung ob ein If-Block der Methode einen Guard fuer VarLow enthaelt
    class function HasGuardingIf(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
    // Erkennt ob ein Call ein nil-sicherer Aufruf ist (.Free, .Destroy)
    class function IsNilSafeCall(const CallNameLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - VarLow kommt in TextLow als
    // eigenstaendiges Argument nach einer oeffnenden Klammer vor
    class function HasBareArgUse(const TextLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - Uebergabe als Argument
    // zwischen nil-Zuweisung und Zugriff zaehlt als Zuweisung
    class function IsPassedAsArgBetween(MethodNode: TAstNode;
      Calls, Assigns: TList<TAstNode>;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
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
  const VarLow: string; AfterLine, BeforeLine: Integer): Boolean;
var
  Ifs : TList<TAstNode>;
  IfN : TAstNode;
  Low : string;
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
  AfterLine, BeforeLine: Integer): Boolean;
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
      // Feldwerte (obj.field := nil) ueberspringen – Cleanup-Muster
      if Pos('.', NA.Name) > 0 then Continue;

      VarLow := NA.Name.ToLower;
      if VarLow = '' then Continue;
      // Self oder Result als Variablenname ueberspringen
      if (VarLow = 'self') or (VarLow = 'result') then Continue;

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

        // Guard via If-Bedingung zwischen nil und Zugriff?
        if HasGuardingIf(MethodNode, VarLow, NA.Line, C.Line) then Continue;

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
