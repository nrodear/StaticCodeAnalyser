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
//   - varname = 0 then Exit
//   - varname = 0 then varname := 1   (Fix-up auf nichtnull-Literal)
//   - Assigned(varname)  (fuer Pointer-Divisor)
//
// Zusaetzlich provably-nonzero (ohne if): wenn der Divisor im ganzen
// Methodenrumpf ausschliesslich nichtnull-Ganzzahl-Literale zugewiesen
// bekommt und mindestens einmal VOR der Division, kann er dort nicht 0 sein.
//
// Einschraenkungen:
//   - Floating-Point-Division (/) wird nicht geprueft
//   - Felder (Self.FCount) ohne klare Initialisierung nicht analysiert
//   - Komplexe Ausdruecke als Divisor werden uebersprungen

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
    // True wenn der THEN-Zweig VarLow ein nichtnull-Ganzzahl-Literal zuweist
    // (Fix-up-Idiom 'if x = 0 then x := 1'). Zusammen mit der 0-Bedingung ist
    // x danach auf beiden Pfaden nachweislich <> 0.
    class function ThenBranchAssignsNonZeroTo(IfN: TAstNode;
      const VarLow: string): Boolean; static;
    // True wenn der Divisor im Rumpf NUR nichtnull-Ganzzahl-Literale zugewiesen
    // bekommt und mindestens einmal vor der Division (provably-nonzero).
    class function AllAssignmentsNonZeroLiteral(MethodNode: TAstNode;
      const VarLow: string; BeforeLine: Integer): Boolean; static;
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

class function TDivByZeroDetector.AllAssignmentsNonZeroLiteral(
  MethodNode: TAstNode; const VarLow: string; BeforeLine: Integer): Boolean;
// True wenn JEDE Zuweisung an VarLow im ganzen Methodenrumpf ein nichtnull-
// Ganzzahl-Literal ist UND mindestens eine davon vor der Division liegt.
// Dann ist VarLow an der Divisionsstelle nachweislich <> 0 (provably-nonzero:
// const-init auf 1/2, spaeter nur weitere nichtnull-Literale - SevenZipDlg).
//
// TP-Sicherheit: sobald IRGENDEINE Zuweisung (auch nach der Division, wegen
// moeglicher Schleifen-Rueckkanten) KEIN nichtnull-Literal ist - Null-Literal,
// Funktionsaufruf, Ausdruck, andere Variable - brechen wir ab und melden
// weiter. Damit bleiben echte Bugs und absichtliche 'x := 0'-Demos gemeldet.
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
      // sie darf die Literal-Pruefung nicht scheitern lassen und zaehlt nicht
      // als vorherige Init.
      if A.Line = BeforeLine then Continue;
      if not IsNonZeroIntLiteral(A.TypeRef) then Exit; // Result bleibt False
      if A.Line < BeforeLine then FoundPrior := True;
    end;
  finally
    Assigns.Free;
  end;
  Result := FoundPrior;
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

        // Provably-nonzero: Divisor wird ausschliesslich mit nichtnull-Literalen
        // belegt (const-init auf 1/2 usw.) - kann an der Divisionsstelle nicht 0
        // sein. TP-sicher, weil jede Nicht-Literal-Zuweisung die Suppression
        // aufhebt (Real-World-Audit 2026-07-10, provably-nonzero).
        if AllAssignmentsNonZeroLiteral(MethodNode, Divisor, N.Line) then Continue;

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
