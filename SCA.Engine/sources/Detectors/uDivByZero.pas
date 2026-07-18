unit uDivByZero;

// Detektor fuer potentielle Division-durch-Null (Sonar-Regel #6).
//
// Drei Heuristiken:
//
//   H1 – Literale Null: 'div 0' oder 'mod 0' im Ausdruck
//        Immer Fehler (EZeroDivide).
//
//   H2 – Parameter als Divisor ohne Guard:
//        Integer-Parameter wird als Divisor verwendet ohne vorherige
//        if-Bedingung wie 'param > 0' oder 'param <> 0'.
//
//   H3 – Lokale Integer-Variable als Divisor ohne Guard:
//        Wie H2 aber fuer lokale Vars statt Parameter.
//
// Erkannte Guards (in if-Bedingungen ZWISCHEN Methodenanfang und Division):
//   - varname > 0
//   - varname >= 1
//   - varname <> 0
//   - varname = 0 then Exit                (auch Raise)
//   - varname = 0 then varname := 1        (Fix-up auf nichtnull-Literal)
//   - Assigned(varname)  (fuer Pointer-Divisor)
//
// Weitere provably-nonzero-Guards (Real-World-FP-Audit 2026-07-12, SCA010
// 5/23 Sample-FP: Divisor beweisbar <> 0 ueber einen Mechanismus, den die
// obigen if-Guards nicht modellieren):
//
//   G1 - for-Schleifenvariable mit nichtnull-Unterschranke:
//        'for I := <nichtnull-Literal> to ... do ... x div I'
//        In einer AUFSTEIGENDEN (to, nicht downto) for-Schleife gilt im Rumpf
//        immer I >= Startwert. Ist der Startwert ein nichtnull-Ganzzahl-Literal
//        (>=1), kann I dort nie 0 sein. Nur Divisionen INNERHALB des Rumpfs
//        werden unterdrueckt (Knoten-Enthaltensein, nicht nur Zeilenbereich) -
//        eine Nutzung von I ausserhalb der Schleife bleibt gemeldet.
//        TP-sicher: 'for I := 0 to ...' (Startwert 0) wird NICHT unterdrueckt.
//
//   G2 - Break/Continue-Bail-Guard:
//        'if <divisor> = 0 then Break/Continue' (bzw. <=0 / <1) VOR der Division
//        IM SELBEN innersten Schleifenrumpf. Exit/Raise deckt HasGuardingIf
//        bereits methodenweit ab; Break/Continue schuetzen nur innerhalb der
//        Schleife, deshalb die Schleifen-Enthaltenseins-Pruefung (Guard-if und
//        Division muessen dieselbe innerste Schleife teilen). Blindstellen (bewusst,
//        lexikalisch): Dominanz (Guard in verschachteltem 'if a then ...'),
//        Divisor-Reassignment zwischen Guard und Division, sowie AND-Struktur
//        ('if (x=0) and (y=0)'). Mechanik identisch zum bestehenden Exit/Raise-
//        Guard; Break/Continue als Guard sind aber NEU -> schmale neue FN-Instanzen
//        derselben (akzeptierten, seltenen + smell-nahen) Klasse.
//
//   G3 - Clamp auf >= 1:
//        Divisor wird (ausschliesslich) mit 'Max(1, ...)' bzw.
//        'Round/Trunc/Floor/Ceil(Max(1, ...))' belegt. Math.Max liefert >= jedes
//        Arguments; ist ein Argument ein nichtnull-Ganzzahl-Literal, ist das
//        Ergebnis >= 1. Round/Trunc/Floor/Ceil eines Werts >= 1.0 bleibt >= 1.
//        Sehr konservativ: der GESAMTE RHS muss exakt diese Form haben.
//
// Zusaetzlich provably-nonzero (ohne if): wenn der Divisor im ganzen
// Methodenrumpf ausschliesslich beweisbar-nichtnulle Ausdruecke zugewiesen
// bekommt (nichtnull-Ganzzahl-Literale ODER Clamp G3) und mindestens einmal
// VOR der Division, kann er dort nicht 0 sein.
//
// Einschraenkungen:
//   - Floating-Point-Division (/) wird nicht geprueft
//   - Felder (Self.FCount) ohne klare Initialisierung nicht analysiert
//   - Komplexe Ausdruecke als Divisor werden uebersprungen
//   - while-guarded-copy ('Temp := B' in 'while B <> 0 do ... x div Temp')
//     wird BEWUSST NICHT modelliert: sicher waere sie nur mit einer
//     Nicht-Reassignment-Pruefung von B/Temp zwischen Kopie und Division
//     (Ordnungs-/Datenfluss-Analyse, die der lexikalische Detektor nicht hat).
//     Ohne diese Pruefung droht das Verschlucken echter Bugs (FN) - deshalb
//     ausgelassen (siehe Real-World-FP-Audit 2026-07-12, FastcodeGCDUnit.pas).

interface

uses
  System.SysUtils, System.StrUtils, System.Classes,
  System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TDivByZeroDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function ExtractDivisor(const ExprLow: string): string; static;
    class function IsIntegerType(const TypeLow: string): Boolean; static;
    class function HasGuardingIf(MethodNode: TAstNode;
      const VarLow: string; BeforeLine: Integer): Boolean; static;
    // True wenn der THEN-Zweig des if direkt mit Exit oder Raise endet
    // (ggf. via begin..end-Block). Wird gebraucht um 'if x = 0 then Exit'
    // (echter Guard) von 'if x = 0 then DoOther' (kein Guard) zu trennen.
    class function ThenBranchExitsOrRaises(IfN: TAstNode): Boolean; static;
    // Wie ThenBranchExitsOrRaises, aber fuer Break/Continue (G2). Getrennt
    // gehalten, weil Break/Continue - anders als Exit/Raise - nur INNERHALB der
    // Schleife schuetzen und deshalb eine Schleifen-Enthaltenseins-Pruefung
    // brauchen (siehe HasBreakContinueGuard).
    class function ThenBranchBreaksOrContinues(IfN: TAstNode): Boolean; static;
    // True wenn der THEN-Zweig VarLow ein nichtnull-Ganzzahl-Literal zuweist
    // (Fix-up-Idiom 'if x = 0 then x := 1'). Zusammen mit der 0-Bedingung ist
    // x danach auf beiden Pfaden nachweislich <> 0.
    class function ThenBranchAssignsNonZeroTo(IfN: TAstNode;
      const VarLow: string): Boolean; static;
    // True wenn der Divisor im Rumpf NUR beweisbar-nichtnulle Ausdruecke
    // zugewiesen bekommt (nichtnull-Ganzzahl-Literale ODER Clamp G3) und
    // mindestens einmal vor der Division (provably-nonzero).
    class function AllAssignmentsProvablyNonZero(MethodNode: TAstNode;
      const VarLow: string; BeforeLine: Integer): Boolean; static;
    // True wenn Target im Subtree von Root liegt (Knoten-Identitaet, nicht
    // Zeilenbereich). Basis fuer die Schleifen-Enthaltenseins-Pruefungen.
    class function NodeInSubtree(Root, Target: TAstNode): Boolean; static;
    // Innerste Schleife (for/while/repeat) im MethodNode, die Target enthaelt,
    // oder nil. "Innerste" = groesste Start-Zeile unter den enthaltenden
    // Schleifen (bei korrekter Verschachtelung eindeutig).
    class function InnermostLoopContaining(MethodNode,
      Target: TAstNode): TAstNode; static;
    // Extrahiert aus einer AUFSTEIGENDEN ('to') for-Schleife die (lowercase)
    // Schleifenvariable und den Startwert-Text. False bei downto / for-in /
    // fehlendem ':='. Fuer G1.
    class function TryGetAscendingForLoopVar(ForN: TAstNode;
      out LoopVarLow, StartVal: string): Boolean; static;
    // G1: Divisor ist die Variable einer aufsteigenden for-Schleife mit
    // nichtnull-Literal-Startwert und die Division liegt in deren Rumpf.
    class function IsGuardedByForLoopVar(MethodNode, DivNode: TAstNode;
      const VarLow: string): Boolean; static;
    // G2: 'if <divisor>=0 then Break/Continue' im selben innersten Schleifen-
    // rumpf VOR der Division.
    class function HasBreakContinueGuard(MethodNode, DivNode: TAstNode;
      const VarLow: string): Boolean; static;
    // G4: 'while <divisor> <> 0 do ... x div <divisor>' (bzw. > 0 / >= 1). Der
    // Divisor ist im while-KOPF direkt gegen 0 geschuetzt und die Division liegt
    // in dessen Rumpf. Sound nur, wenn der Divisor zwischen Kopf und Division
    // nicht per nkAssign umgeschrieben und nicht per Dec(..) dekrementiert wird.
    class function IsGuardedByWhileCond(MethodNode, DivNode: TAstNode;
      const VarLow: string): Boolean; static;
    class procedure CollectIntegerVars(MethodNode: TAstNode;
      Names: TStringList); static;
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, NestedTry, NilComparison, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// Ersetzt jeden Char zwischen single-quotes (inkl. ''-Escape-Handling)
// durch Leerzeichen. Quotes selbst bleiben stehen, damit String-Positionen
// 1:1 bleiben. Brauchen wir damit Pseudo-Code in String-Literalen (z.B.
// ''10 div 0'' als Konstanten-Init oder Doku-String) nicht als echte
// Division gewertet wird.
function StripStringLiterals(const S: string): string;
var
  i     : Integer;
  inStr : Boolean;
begin
  Result := S;
  inStr  := False;
  i := 1;
  while i <= Length(Result) do
  begin
    if Result[i] = '''' then
    begin
      if inStr and (i < Length(Result)) and (Result[i + 1] = '''') then
      begin
        Result[i]     := ' ';
        Result[i + 1] := ' ';
        Inc(i, 2);
        Continue;
      end;
      inStr := not inStr;
    end
    else if inStr then
      Result[i] := ' ';
    Inc(i);
  end;
end;

function IsNonZeroIntLiteral(const S: string): Boolean;
// True wenn S (nach Trim) ein reines Ganzzahl-Literal ungleich 0 ist:
// Dezimal ('1', '42', '+2') oder Hex ('$1', '$0a'). Alles andere - Ausdruecke,
// Funktionsaufrufe, Variablen, das Literal '0'/'$0' - liefert False. So
// akzeptieren wir nur nachweislich-nichtnull-Konstanten als Guard/Init und
// bleiben TP-sicher (u.a. bleibt absichtliches 'x := 0' meldepflichtig).
var
  T       : string;
  i       : Integer;
  AllZero : Boolean;
begin
  Result := False;
  T := Trim(S);
  if T = '' then Exit;
  // Fuehrendes '+' erlauben (kein '-': konservativ bleiben).
  if T[1] = '+' then
  begin
    Delete(T, 1, 1);
    T := Trim(T);
    if T = '' then Exit;
  end;
  if T[1] = '$' then
  begin
    if Length(T) < 2 then Exit;
    AllZero := True;
    for i := 2 to Length(T) do
    begin
      if not CharInSet(T[i], ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
      if T[i] <> '0' then AllZero := False;
    end;
    Result := not AllZero;
    Exit;
  end;
  AllZero := True;
  for i := 1 to Length(T) do
  begin
    if not CharInSet(T[i], ['0'..'9']) then Exit;
    if T[i] <> '0' then AllZero := False;
  end;
  Result := not AllZero;
end;

function IsClampedNonZero(const S: string): Boolean;
// G3: True wenn der Ausdruck S nachweislich >= 1 ist, weil er die Form
//   Max(<..>, <nichtnull-int-literal>, <..>)
// hat - optional umschlossen von genau einem Round/Trunc/Floor/Ceil. Math.Max
// liefert >= jedes Arguments; ist EIN Top-Level-Argument ein nichtnull-Ganzzahl-
// Literal (>=1), ist das Ergebnis >= 1. Round/Trunc/Floor/Ceil eines Werts
// >= 1.0 bleibt >= 1. SEHR konservativ: der GESAMTE (getrimmte) RHS muss exakt
// diese Form haben - ein nachgestelltes '- 1', '* 0', '+ x' o.ae. laesst die
// Pruefung scheitern (Ergebnis koennte dann 0/negativ werden). TP-sicher.
var
  T, Inner, Arg : string;
  i, Depth, ArgStart : Integer;
begin
  Result := False;
  T := Trim(StripStringLiterals(S).ToLower);
  // Optionalen numerischen Wrapper abschaelen (genau eine Ebene). Alle vier
  // Rundungsfunktionen bilden v >= 1.0 auf einen Wert >= 1 ab.
  for var W in ['round', 'trunc', 'floor', 'ceil'] do
    if T.StartsWith(W + '(') and T.EndsWith(')') then
    begin
      T := Trim(Copy(T, Length(W) + 2, Length(T) - Length(W) - 2));
      Break;
    end;
  // Danach muss der Rest EXAKT ein Max(...)-Aufruf sein.
  if not (T.StartsWith('max(') and T.EndsWith(')')) then Exit;
  // FN-Schutz (adversariale Verify 2026-07-12): sicherstellen, dass die von
  // 'max(' geoeffnete Klammer ERST am letzten Zeichen schliesst. Sonst ist T ein
  // ZUSAMMENGESETZTER Ausdruck ('Max(1,a) - Max(1,b)', 'Max(1,a) mod f(b)',
  // 'Max(1,a) * f(b)'), der trotz 'max('-Praefix + ')'-Suffix 0 werden kann ->
  // NICHT unterdruecken (sonst verschluckter div-by-zero-Crash = FN).
  Depth := 0;
  for i := 4 to Length(T) do            // ab dem '(' in 'max('
  begin
    if T[i] = '(' then Inc(Depth)
    else if T[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        if i <> Length(T) then Exit;    // schliesst vor Ende -> zusammengesetzt
        Break;
      end;
    end;
  end;
  Inner := Copy(T, 5, Length(T) - 5);   // zwischen 'max(' und schliessender ')'
  // Top-Level-Argumente per Komma trennen (verschachtelte Klammern beachten);
  // genuegt EIN nichtnull-Ganzzahl-Literal.
  Depth    := 0;
  ArgStart := 1;
  for i := 1 to Length(Inner) + 1 do
  begin
    if (i > Length(Inner)) or ((Inner[i] = ',') and (Depth = 0)) then
    begin
      Arg := Trim(Copy(Inner, ArgStart, i - ArgStart));
      if IsNonZeroIntLiteral(Arg) then Exit(True);
      ArgStart := i + 1;
    end
    else if Inner[i] = '(' then
      Inc(Depth)
    else if Inner[i] = ')' then
      Dec(Depth);
  end;
end;

class function TDivByZeroDetector.IsIntegerType(const TypeLow: string): Boolean;
begin
  Result :=
    (TypeLow = 'integer') or (TypeLow = 'cardinal') or
    (TypeLow = 'int64') or (TypeLow = 'longint') or
    (TypeLow = 'longword') or (TypeLow = 'smallint') or
    (TypeLow = 'shortint') or (TypeLow = 'byte') or
    (TypeLow = 'word') or (TypeLow = 'nativeint') or
    (TypeLow = 'nativeuint') or (TypeLow = 'uint64') or
    (TypeLow = 'uint32') or (TypeLow = 'int32') or
    (Pos('integer', TypeLow) > 0);
end;

class function TDivByZeroDetector.ExtractDivisor(
  const ExprLow: string): string;
// Gibt den Bezeichner direkt nach 'div' / 'mod' zurueck (oder '').
const
  Operators : array[0..1] of string = (' div ', ' mod ');
var
  p, Start, i : Integer;
  Ch          : Char;
  Op          : string;
begin
  Result := '';
  for Op in Operators do
  begin
    p := Pos(Op, ExprLow);
    while p > 0 do
    begin
      Start := p + Length(Op);
      var Divisor := '';
      i := Start;
      while i <= Length(ExprLow) do
      begin
        Ch := ExprLow[i];
        if CharInSet(Ch, ['a'..'z', '0'..'9', '_']) then
          Divisor := Divisor + Ch
        else
          Break;
        Inc(i);
      end;
      if Divisor <> '' then
      begin
        Result := Divisor;
        Exit;
      end;
      p := PosEx(Op, ExprLow, p + 1);
    end;
  end;
end;

class function TDivByZeroDetector.HasGuardingIf(MethodNode: TAstNode;
  const VarLow: string; BeforeLine: Integer): Boolean;
var
  Ifs : TList<TAstNode>;
  IfN : TAstNode;
  Low : string;
begin
  Result := False;
  Ifs := MethodNode.FindAll(nkIfStmt);
  try
    for IfN in Ifs do
    begin
      if IfN.Line >= BeforeLine then Continue;
      Low := IfN.TypeRef.ToLower;
      if Low = '' then Continue;
      // Strikte Guards: die Bedingung selbst schuetzt direkt vor 0.
      // Wortgrenzen-Pruefung verhindert dass z.B. 'myvar > 0' faelschlich
      // auch 'myvariant' schuetzt.
      if TDetectorUtils.ContainsWholeWordLower(VarLow + ' > 0',  Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '>0',    Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' >= 1', Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' <> 0', Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<>0',   Low)  or
         TDetectorUtils.ContainsWholeWordLower('0 < '  + VarLow, Low)  or
         TDetectorUtils.ContainsWholeWordLower('0<'    + VarLow, Low)  or
         TDetectorUtils.ContainsWholeWordLower('0 <> ' + VarLow, Low)  then
        Exit(True);
      // Exit-Guard: 'if x <bail-cond> then Exit/Raise' schuetzt nur wenn der
      // THEN-Zweig den Code-Pfad verlaesst. Erfasst das haeufige "bail wenn
      // nicht-positiv"-Idiom fuer Integer-Divisoren:
      //   if x = 0 then Exit;        (x koennte 0 sein)
      //   if x <= 0 then Exit;       (x koennte 0 oder negativ sein)
      //   if x < 1 then raise ...;   (ganzzahlig aequivalent zu <= 0)
      // Danach ist x nachweislich > 0. 'if x = 0 then DoOther' (ohne Exit/
      // Raise) ist KEIN Guard - x kann danach noch 0 sein. FP-Gate Prio 7
      // (Real-World-Audit 2026-07-04, guarded-divisor).
      if TDetectorUtils.ContainsWholeWordLower(VarLow + ' = 0',  Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '=0',    Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' <= 0', Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<=0',   Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' < 1',  Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<1',    Low)  then
      begin
        // (a) Bail: THEN-Zweig verlaesst den Pfad (Exit/Raise).
        if ThenBranchExitsOrRaises(IfN) then
          Exit(True);
        // (b) Fix-up: THEN-Zweig weist VarLow ein nichtnull-Literal zu
        //     (z.B. 'if elTime = 0 then elTime := 1'). Danach ist VarLow auf
        //     beiden Pfaden <> 0 - guarded-nonzero (Real-World-Audit 2026-07-10).
        if ThenBranchAssignsNonZeroTo(IfN, VarLow) then
          Exit(True);
      end;
    end;
  finally
    Ifs.Free;
  end;
end;

class function TDivByZeroDetector.ThenBranchExitsOrRaises(
  IfN: TAstNode): Boolean;
// Pruefung: enthaelt der THEN-Zweig ein Exit oder Raise?
// Akzeptierte Formen:
//   if x = 0 then Exit;
//   if x = 0 then raise EFoo.Create(...);
//   if x = 0 then begin LogIt; Exit; end;          (Block-Walk!)
//   if x = 0 then begin Cleanup; raise EFoo; end;
// Else-Zweig wird ignoriert (nkElseBranch).
//
// Hinweis: in einem Block reicht IRGENDEIN Exit/Raise auf erster Ebene -
// alle Statements davor sind unconditional und werden vor dem Exit/Raise
// ausgefuehrt. Wir pruefen damit "kann der Code-Pfad nach dem if noch
// erreicht werden wenn x=0 war?"
var
  i, j   : Integer;
  Branch : TAstNode;
  Stmt   : TAstNode;
begin
  Result := False;
  if IfN = nil then Exit;
  for i := 0 to IfN.Children.Count - 1 do
  begin
    Branch := IfN.Children[i];
    if Branch.Kind = nkElseBranch then Continue;
    // Direkter Exit/Raise ohne Block-Wrap.
    if (Branch.Kind = nkExit) or (Branch.Kind = nkRaise) then
      Exit(True);
    // begin..end-Block: jedes direkte Kind pruefen. Wenn IRGENDEIN
    // Statement Exit/Raise ist, verlaesst der Pfad den Code.
    if Branch.Kind = nkBlock then
    begin
      for j := 0 to Branch.Children.Count - 1 do
      begin
        Stmt := Branch.Children[j];
        if (Stmt.Kind = nkExit) or (Stmt.Kind = nkRaise) then
          Exit(True);
      end;
    end;
    // Nur das erste Then-Statement betrachten (kein Fall-Through
    // ueber Else-Branch hinaus).
    Break;
  end;
end;

class function TDivByZeroDetector.ThenBranchBreaksOrContinues(
  IfN: TAstNode): Boolean;
// Wie ThenBranchExitsOrRaises, aber fuer Break/Continue. Getrennte Kopie statt
// Refactor der getesteten Exit/Raise-Variante (kein Compiler als Netz).
// Akzeptierte Formen:
//   if x = 0 then Break;
//   if x = 0 then Continue;
//   if x = 0 then begin LogIt; Break; end;          (Block-Walk!)
var
  i, j   : Integer;
  Branch : TAstNode;
  Stmt   : TAstNode;
begin
  Result := False;
  if IfN = nil then Exit;
  for i := 0 to IfN.Children.Count - 1 do
  begin
    Branch := IfN.Children[i];
    if Branch.Kind = nkElseBranch then Continue;
    // Direkter Break/Continue ohne Block-Wrap.
    if (Branch.Kind = nkBreak) or (Branch.Kind = nkContinue) then
      Exit(True);
    // begin..end-Block: jedes direkte Kind pruefen.
    if Branch.Kind = nkBlock then
    begin
      for j := 0 to Branch.Children.Count - 1 do
      begin
        Stmt := Branch.Children[j];
        if (Stmt.Kind = nkBreak) or (Stmt.Kind = nkContinue) then
          Exit(True);
      end;
    end;
    // Nur das erste Then-Statement betrachten.
    Break;
  end;
end;

class function TDivByZeroDetector.ThenBranchAssignsNonZeroTo(
  IfN: TAstNode; const VarLow: string): Boolean;
// Erfasst das Fix-up-Idiom:
//   if elTime = 0 then elTime := 1;
//   if n <= 0 then begin Log; n := 1; end;      (Block-Walk!)
// Nur der THEN-Zweig zaehlt (nkElseBranch wird ignoriert); es genuegt EINE
// Zuweisung 'VarLow := <nichtnull-Literal>' auf erster Ebene des THEN-Zweigs.
var
  i, j   : Integer;
  Branch : TAstNode;
  Stmt   : TAstNode;

  function AssignsNonZero(N: TAstNode): Boolean;
  begin
    Result := (N.Kind = nkAssign)
          and (N.Name.ToLower = VarLow)
          and IsNonZeroIntLiteral(N.TypeRef);
  end;

begin
  Result := False;
  if IfN = nil then Exit;
  for i := 0 to IfN.Children.Count - 1 do
  begin
    Branch := IfN.Children[i];
    if Branch.Kind = nkElseBranch then Continue;
    // Direkte Fix-up-Zuweisung ohne Block-Wrap.
    if AssignsNonZero(Branch) then Exit(True);
    // begin..end-Block: jedes direkte Kind pruefen.
    if Branch.Kind = nkBlock then
      for j := 0 to Branch.Children.Count - 1 do
      begin
        Stmt := Branch.Children[j];
        if AssignsNonZero(Stmt) then Exit(True);
      end;
    // Nur das erste Then-Statement betrachten (analog ThenBranchExitsOrRaises).
    Break;
  end;
end;

class function TDivByZeroDetector.AllAssignmentsProvablyNonZero(
  MethodNode: TAstNode; const VarLow: string; BeforeLine: Integer): Boolean;
// True wenn JEDE Zuweisung an VarLow im ganzen Methodenrumpf beweisbar <> 0 ist
// (nichtnull-Ganzzahl-Literal ODER Clamp G3 wie 'Max(1,..)') UND mindestens eine
// davon vor der Division liegt. Dann ist VarLow an der Divisionsstelle
// nachweislich <> 0 (provably-nonzero: const-init auf 1/2 - SevenZipDlg; oder
// StepSize := Round(Max(1, ...)) - VirtualTrees.BaseTree).
//
// TP-Sicherheit: sobald IRGENDEINE Zuweisung (auch nach der Division, wegen
// moeglicher Schleifen-Rueckkanten) NICHT beweisbar-nichtnull ist - Null-
// Literal, gewoehnlicher Funktionsaufruf, Ausdruck, andere Variable - brechen
// wir ab und melden weiter. Damit bleiben echte Bugs und absichtliche
// 'x := 0'-Demos gemeldet.
// Bekannte (mit dem bestehenden Verhalten geteilte) Grenze: Inc/Dec via Aufruf
// sind KEINE nkAssign und werden nicht betrachtet - ein Inc haelt den Divisor
// nur groesser (unkritisch), ein hypothetisches 'Dec(x)' bis 0 saehe der
// Detektor nicht (wie schon vor dieser Aenderung).
var
  Assigns    : TList<TAstNode>;
  A          : TAstNode;
  FoundPrior : Boolean;
begin
  Result     := False;
  FoundPrior := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      if A.Name.ToLower <> VarLow then Continue;
      // Die Divisions-Zuweisung selbst (gleiche Zeile) tragt die 'div'-RHS -
      // sie darf die Pruefung nicht scheitern lassen und zaehlt nicht als
      // vorherige Init.
      if A.Line = BeforeLine then Continue;
      if not (IsNonZeroIntLiteral(A.TypeRef) or IsClampedNonZero(A.TypeRef)) then
        Exit; // Result bleibt False
      if A.Line < BeforeLine then FoundPrior := True;
    end;
  finally
    Assigns.Free;
  end;
  Result := FoundPrior;
end;

class function TDivByZeroDetector.NodeInSubtree(Root, Target: TAstNode): Boolean;
// Knoten-Identitaets-Enthaltensein: True wenn Target im Subtree von Root liegt.
// Nutzt den (gecachten) FindAll-Walk fuer Target.Kind - exakt und robust gegen
// Zeilenbereich-Artefakte.
var
  Lst : TList<TAstNode>;
begin
  Result := False;
  if (Root = nil) or (Target = nil) then Exit;
  Lst := Root.FindAll(Target.Kind);
  try
    Result := Lst.IndexOf(Target) >= 0;
  finally
    Lst.Free;
  end;
end;

class function TDivByZeroDetector.InnermostLoopContaining(
  MethodNode, Target: TAstNode): TAstNode;
var
  Best : TAstNode;

  procedure ConsiderKind(K: TNodeKind);
  var
    Loops : TList<TAstNode>;
    L     : TAstNode;
  begin
    Loops := MethodNode.FindAll(K);
    try
      for L in Loops do
        if (L <> Target) and TDivByZeroDetector.NodeInSubtree(L, Target) then
          // Bei korrekter Verschachtelung hat die innerste enthaltende Schleife
          // die groesste Start-Zeile (Vorfahren beginnen frueher).
          if (Best = nil) or (L.Line > Best.Line) then
            Best := L;
    finally
      Loops.Free;
    end;
  end;

begin
  Best := nil;
  ConsiderKind(nkForStmt);
  ConsiderKind(nkWhileStmt);
  ConsiderKind(nkRepeatStmt);
  Result := Best;
end;

class function TDivByZeroDetector.TryGetAscendingForLoopVar(ForN: TAstNode;
  out LoopVarLow, StartVal: string): Boolean;
// Zerlegt den for-Header (ForN.TypeRef; Tokens per Space gejoint vom Parser).
//   klassisch : 'i := 2 to floor ( sqrt ( cnt ) )'  -> LoopVar vor ':='
//   inline var: ':= 1 to 10'  (+ nkLocalVar-Kind 'i') -> LoopVar aus dem Kind
// NUR aufsteigend ('to'): ' downto ' enthaelt kein ' to ' (Space-Grenzen) und
// faellt korrekt durch -> bei downto/for-in liefert die Funktion False.
var
  H, Rest  : string;
  LocalVar : TAstNode;
  pAssign, pTo : Integer;
begin
  Result     := False;
  LoopVarLow := '';
  StartVal   := '';
  H := ForN.TypeRef.ToLower;
  pAssign := Pos(':=', H);
  if pAssign = 0 then Exit;                  // for-in oder unklar -> raus
  Rest := Copy(H, pAssign + 2, MaxInt);
  pTo := Pos(' to ', Rest);
  if pTo = 0 then Exit;                       // downto / kein 'to' -> raus
  StartVal := Trim(Copy(Rest, 1, pTo - 1));
  if StartVal = '' then Exit;
  // Schleifenvariable: inline 'for var X' -> nkLocalVar-Kind; sonst vor ':='.
  LocalVar := ForN.FindFirstChild(nkLocalVar);
  if LocalVar <> nil then
    LoopVarLow := LocalVar.Name.ToLower
  else
    LoopVarLow := Trim(Copy(H, 1, pAssign - 1));
  if LoopVarLow = '' then Exit;
  Result := True;
end;

class function TDivByZeroDetector.IsGuardedByForLoopVar(
  MethodNode, DivNode: TAstNode; const VarLow: string): Boolean;
// G1: Divisor ist die Variable einer aufsteigenden for-Schleife mit nichtnull-
// Literal-Startwert und die Division liegt in deren Rumpf (Knoten-Enthaltensein).
var
  Fors : TList<TAstNode>;
  ForN : TAstNode;
  LoopVarLow, StartVal : string;
begin
  Result := False;
  Fors := MethodNode.FindAll(nkForStmt);
  try
    for ForN in Fors do
    begin
      if not TryGetAscendingForLoopVar(ForN, LoopVarLow, StartVal) then Continue;
      if LoopVarLow <> VarLow then Continue;
      if not IsNonZeroIntLiteral(StartVal) then Continue;  // 'for i := 0 to' bleibt Fund
      if NodeInSubtree(ForN, DivNode) then Exit(True);
    end;
  finally
    Fors.Free;
  end;
end;

class function TDivByZeroDetector.HasBreakContinueGuard(
  MethodNode, DivNode: TAstNode; const VarLow: string): Boolean;
// G2: 'if <divisor> = 0 then Break/Continue' (bzw. <=0 / <1) VOR der Division
// und im SELBEN innersten Schleifenrumpf. Ohne die Schleifen-Gleichheit waere
// die Suppression unsound (ein Break einer inneren/anderen Schleife schuetzt die
// Division nicht).
var
  LoopOfDiv : TAstNode;
  Ifs : TList<TAstNode>;
  IfN : TAstNode;
  Low : string;
begin
  Result := False;
  LoopOfDiv := InnermostLoopContaining(MethodNode, DivNode);
  if LoopOfDiv = nil then Exit;   // Division nicht in einer Schleife -> kein Break-Schutz
  Ifs := MethodNode.FindAll(nkIfStmt);
  try
    for IfN in Ifs do
    begin
      if IfN.Line >= DivNode.Line then Continue;
      Low := IfN.TypeRef.ToLower;
      if Low = '' then Continue;
      // Bail-Bedingung auf dem Divisor (dieselbe Menge wie im Exit/Raise-Zweig
      // von HasGuardingIf).
      if not (
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' = 0',  Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '=0',    Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' <= 0', Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<=0',   Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' < 1',  Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<1',    Low) ) then
        Continue;
      if not ThenBranchBreaksOrContinues(IfN) then Continue;
      // Der Guard muss zur SELBEN innersten Schleife gehoeren wie die Division -
      // sonst schuetzt sein Break/Continue die Division nicht.
      if InnermostLoopContaining(MethodNode, IfN) = LoopOfDiv then
        Exit(True);
    end;
  finally
    Ifs.Free;
  end;
end;

class function TDivByZeroDetector.IsGuardedByWhileCond(
  MethodNode, DivNode: TAstNode; const VarLow: string): Boolean;
// G4: Der Divisor ist in der Bedingung einer while-Schleife direkt gegen 0
// geschuetzt ('while x <> 0', '> 0', '>= 1', '0 < x') UND die Division liegt in
// deren Rumpf (Knoten-Enthaltensein). Die Bedingung garantiert den Nichtnull-
// Wert nur am SchleifenKOPF - an der Division nur dann noch, wenn der Divisor
// zwischen Kopf und Division nicht veraendert wird. Deshalb TP-sicher nur, wenn
// im selben Rumpf VOR der Division:
//   - keine nkAssign an den Divisor (Reassign auf moeglichen 0-Wert), und
//   - kein Dec(divisor)-Aufruf (kann den Wert auf/unter 0 ziehen; Inc waechst
//     nur -> unkritisch).
// Reassign/Dec NACH der Division ist unkritisch: die Kopf-Bedingung greift bei
// der naechsten Iteration erneut. Ohne diese Pruefung droht ein maskierter
// echter div-by-zero (FN).
//
// AST-Form (uParser2.pas ParseWhileStmt): die Bedingung wird via JoinTokInto
// abgelegt - Operatoren stehen OHNE umgebende Leerzeichen ('x>0','x<>0'); die
// gespaceten Formen sind defensiv mitgeprueft.
var
  Whiles     : TList<TAstNode>;
  WhileN     : TAstNode;
  Low        : string;
  Lst        : TList<TAstNode>;
  N          : TAstNode;
  Reassigned : Boolean;
begin
  Result := False;
  Whiles := MethodNode.FindAll(nkWhileStmt);
  try
    for WhileN in Whiles do
    begin
      if not NodeInSubtree(WhileN, DivNode) then Continue;
      Low := WhileN.TypeRef.ToLower;
      if Low = '' then Continue;
      // Disjunktion ('while (x>0) or (y>0)') garantiert den Divisor NICHT ->
      // konservativ ueberspringen (strikt enger als der bestehende if-Guard).
      if TDetectorUtils.ContainsWholeWordLower('or', Low) then Continue;
      // Direkter Nichtnull-Guard auf dem Divisor im while-Kopf.
      if not (
         TDetectorUtils.ContainsWholeWordLower(VarLow + '>0',    Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' > 0',  Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '>=1',   Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' >= 1', Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '<>0',   Low) or
         TDetectorUtils.ContainsWholeWordLower(VarLow + ' <> 0', Low) or
         TDetectorUtils.ContainsWholeWordLower('0<'    + VarLow, Low) or
         TDetectorUtils.ContainsWholeWordLower('0 < '  + VarLow, Low) or
         TDetectorUtils.ContainsWholeWordLower('0<>'   + VarLow, Low) or
         TDetectorUtils.ContainsWholeWordLower('0 <> ' + VarLow, Low) ) then
        Continue;
      // Reassign-Pruefung: nkAssign an den Divisor im Rumpf VOR der Division.
      Reassigned := False;
      Lst := MethodNode.FindAll(nkAssign);
      try
        for N in Lst do
          if (N.Line < DivNode.Line) and (N.Name.ToLower = VarLow)
             and NodeInSubtree(WhileN, N) then
          begin
            Reassigned := True;
            Break;
          end;
      finally
        Lst.Free;
      end;
      // Dec(divisor)-Pruefung: liberaler Wort-Match ('dec' + Divisorname). Ein
      // Fehltreffer UNTERdrueckt nur NICHT (residualer FP) - maskiert nie einen
      // Bug. Inc(..) waechst nur und ist unkritisch.
      if not Reassigned then
      begin
        Lst := MethodNode.FindAll(nkCall);
        try
          for N in Lst do
            if (N.Line < DivNode.Line)
               and TDetectorUtils.ContainsWholeWordLower('dec', N.Name.ToLower)
               and TDetectorUtils.ContainsWholeWordLower(VarLow, N.Name.ToLower)
               and NodeInSubtree(WhileN, N) then
            begin
              Reassigned := True;
              Break;
            end;
        finally
          Lst.Free;
        end;
      end;
      if not Reassigned then Exit(True);
    end;
  finally
    Whiles.Free;
  end;
end;

class procedure TDivByZeroDetector.CollectIntegerVars(MethodNode: TAstNode;
  Names: TStringList);

  procedure AddIntegerNode(N: TAstNode);
  var
    PName : string;
  begin
    if not IsIntegerType(N.TypeRef.ToLower) then Exit;
    PName := N.Name.ToLower;
    // Modifier (out/var/const) entfernen
    for var Mod_ in ['out ', 'var ', 'const '] do
      if PName.StartsWith(Mod_) then
        PName := Copy(PName, Length(Mod_) + 1, MaxInt);
    if (PName <> '') and (Names.IndexOf(PName) < 0) then
      Names.Add(PName);
  end;

var
  Lst: TList<TAstNode>;
begin
  // Parameter
  Lst := MethodNode.FindAll(nkParam);
  try
    for var N in Lst do AddIntegerNode(N);
  finally
    Lst.Free;
  end;
  // Lokale Variablen
  Lst := MethodNode.FindAll(nkLocalVar);
  try
    for var N in Lst do AddIntegerNode(N);
  finally
    Lst.Free;
  end;
end;

class procedure TDivByZeroDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure Report(const Detail: string; Line: Integer; Sev: TLeakSeverity);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Detail;
    F.Severity   := Sev;
    F.Kind       := fkDivByZero;
    F.Confidence := KindDefaultConfidence(fkDivByZero);
    Results.Add(F);
  end;

var
  IntVars : TStringList;
  Nodes   : TList<TAstNode>;
  ExprLow : string;
  Divisor : string;
  Reported : TDictionary<string, Boolean>;
begin
  IntVars := TStringList.Create;
  Reported := TDictionary<string, Boolean>.Create;
  try
    CollectIntegerVars(MethodNode, IntVars);

    // ---- Pruefe nkAssign-Knoten ----
    Nodes := MethodNode.FindAll(nkAssign);
    try
      for var N in Nodes do
      begin
        ExprLow := N.TypeRef.ToLower;
        // String-Literale strippen vor den Pos-Checks - 's := ''10 div 0'''
        // soll keinen H1-Treffer geben (Inhalt ist Text, nicht Code).
        // QuoteStrLit klammert Literale mit '...' - der Stripper ersetzt
        // alles zwischen Quotes durch Spaces (laesst die Quotes als
        // Marker, damit der Index-Pos stimmt).
        ExprLow := StripStringLiterals(ExprLow);

        // H1: Literal 0
        if (Pos(' div 0', ExprLow) > 0) or (Pos(' mod 0', ExprLow) > 0) then
        begin
          var Key := IntToStr(N.Line) + ':lit';
          if not Reported.ContainsKey(Key) then
          begin
            Reported.Add(Key, True);
            Report('Division durch Literal 0', N.Line, lsError);
          end;
          Continue;
        end;

        // H2/H3: Variable als Divisor
        Divisor := ExtractDivisor(ExprLow);
        if (Divisor = '') or (IntVars.IndexOf(Divisor) < 0) then Continue;

        // Gibt es einen Guard?
        if HasGuardingIf(MethodNode, Divisor, N.Line) then Continue;

        // G1: aufsteigende for-Schleifenvariable mit nichtnull-Literal-Start -
        // im Rumpf immer >= Start >= 1 (Real-World-FP-Audit 2026-07-12).
        if IsGuardedByForLoopVar(MethodNode, N, Divisor) then Continue;

        // G2: 'if divisor = 0 then Break/Continue' im selben Schleifenrumpf vor
        // der Division (Real-World-FP-Audit 2026-07-12).
        if HasBreakContinueGuard(MethodNode, N, Divisor) then Continue;

        // G4: 'while divisor <> 0 do ... x div divisor' (bzw. > 0 / >= 1) - der
        // Divisor ist im while-Kopf direkt gegen 0 geschuetzt, die Division liegt
        // im Rumpf und der Divisor wird davor nicht veraendert (FP-Klasse SCA010
        // while-guarded-divisor, Welle 1 5%-FP-Konzept 2026-07-18).
        if IsGuardedByWhileCond(MethodNode, N, Divisor) then Continue;

        // Provably-nonzero: Divisor wird ausschliesslich mit beweisbar-nichtnullen
        // Ausdruecken belegt (nichtnull-Literale ODER Clamp 'Max(1,..)' G3) - kann
        // an der Divisionsstelle nicht 0 sein. TP-sicher, weil jede nicht-beweisbare
        // Zuweisung die Suppression aufhebt (Real-World-Audit 2026-07-10/-12).
        if AllAssignmentsProvablyNonZero(MethodNode, Divisor, N.Line) then Continue;

        var Key := IntToStr(N.Line) + ':' + Divisor;
        if Reported.ContainsKey(Key) then Continue;
        Reported.Add(Key, True);
        Report('Division durch "' + Divisor + '" ohne Pruefung auf 0',
               N.Line, lsWarning);
      end;
    finally
      Nodes.Free;
    end;

    // ---- Pruefe nkCall-Knoten (z.B. SetField(x div y)) ----
    Nodes := MethodNode.FindAll(nkCall);
    try
      for var N in Nodes do
      begin
        ExprLow := StripStringLiterals(N.Name.ToLower);
        if (Pos(' div 0', ExprLow) > 0) or (Pos(' mod 0', ExprLow) > 0) then
        begin
          var Key := IntToStr(N.Line) + ':lit';
          if not Reported.ContainsKey(Key) then
          begin
            Reported.Add(Key, True);
            Report('Division durch Literal 0', N.Line, lsError);
          end;
        end;
      end;
    finally
      Nodes.Free;
    end;
  finally
    IntVars.Free;
    Reported.Free;
  end;
end;

class procedure TDivByZeroDetector.AnalyzeUnit(UnitNode: TAstNode;
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
