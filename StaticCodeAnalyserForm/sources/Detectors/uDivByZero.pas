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
//   - Assigned(varname)  (fuer Pointer-Divisor)
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
    class procedure CollectIntegerVars(MethodNode: TAstNode;
      Names: TStringList); static;
  end;

implementation

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
      // Equality-Guard: 'if x = 0 then ...' schuetzt nur wenn der
      // THEN-Zweig den Code-Pfad verlaesst (Exit oder Raise).
      // 'if x = 0 then DoOther' ist KEIN Guard - x kann danach noch 0
      // sein und im Divisor crashen.
      if TDetectorUtils.ContainsWholeWordLower(VarLow + ' = 0',  Low)  or
         TDetectorUtils.ContainsWholeWordLower(VarLow + '=0',    Low)  then
        if ThenBranchExitsOrRaises(IfN) then
          Exit(True);
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
        ExprLow := N.Name.ToLower;
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
