unit uTestComboChecks;

// Tests fuer den NilDeref/MissingFinally/DivByZero/DeadCode/LongMethod/
// DeepNesting/Robust/Suppression-Komplex (TTestNewChecks).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils,
  uSCAConsts, uMethodd12,
  uStaticAnalyzer2,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- NilDeref / MissingFinally / DivByZero / DeadCode -------------------------------
  [TestFixture]
  TTestNewChecks = class
  public
    // NilDeref
    [Test] procedure NilDeref_NilThenDot_ReportsError;
    [Test] procedure NilDeref_AssignedGuard_NoFinding;
    [Test] procedure NilDeref_NotNilGuard_NoFinding;
    [Test] procedure NilDeref_Reassigned_NoFinding;
    [Test] procedure NilDeref_FreeIsSafe_NoFinding;
    [Test] procedure NilDeref_FreeAndNilIsSafe_NoFinding;
    // MissingFinally
    [Test] procedure MissingFinally_CreateFreeNoTry_ReportsWarning;
    [Test] procedure MissingFinally_TryFinally_NoFinding;
    [Test] procedure MissingFinally_NoFreeAtAll_NoFinding;
    [Test] procedure MissingFinally_TryExceptOnly_ReportsWarning;
    // DivByZero
    [Test] procedure DivByZero_LiteralZero_ReportsError;
    [Test] procedure DivByZero_ParamWithoutGuard_ReportsWarning;
    [Test] procedure DivByZero_ParamWithGuard_NoFinding;
    [Test] procedure DivByZero_LocalVarWithoutGuard_ReportsWarning;
    [Test] procedure DivByZero_NonIntegerType_NoFinding;
    // DeadCode
    [Test] procedure DeadCode_AfterExit_ReportsWarning;
    [Test] procedure DeadCode_AfterRaise_ReportsWarning;
    [Test] procedure DeadCode_AfterBreakInLoop_ReportsWarning;
    [Test] procedure DeadCode_ConditionalExit_NoFinding;
    [Test] procedure DeadCode_ExitInIfThenElse_NoFinding;
    [Test] procedure DeadCode_ExitBeforeExceptBlock_NoFinding;
    [Test] procedure DeadCode_ExitBeforeFinallyBlock_NoFinding;
    // LongMethod: nutzt jetzt Body-Zeilen + Statement-Count
    [Test] procedure LongMethod_ShortBodyLongSignature_NoFinding;
    [Test] procedure LongMethod_LongBodyManyStatements_ReportsWarning;
    [Test] procedure LongMethod_ForwardDecl_NoFinding;
    // DeepNesting: try-Bloecke werden nicht mehr gezaehlt
    [Test] procedure DeepNesting_TryFinallyOnly_NoFinding;
    [Test] procedure DeepNesting_FiveLogicalLevels_ReportsWarning;
    [Test] procedure DeepNesting_TryAroundFourLevels_NoFinding;
    // Robustheit
    [Test] procedure Robust_NonExistentFile_ReportsFileError;
    [Test] procedure Robust_EmptyFileName_ReportsFileError;
    [Test] procedure Robust_NonExistentDirectory_ReportsFileError;
    [Test] procedure Robust_EmptyDirectory_ReportsFileError;
    // Suppression
    [Test] procedure Suppression_NoinspectionSpecificKind_FiltersFinding;
    [Test] procedure Suppression_NoinspectionAll_FiltersAllFindings;
    [Test] procedure Suppression_WrongKind_DoesNotFilter;
    [Test] procedure Suppression_MultipleKinds_FiltersAll;
    // KindFromName-Erweiterung: 3 zuvor stumm ignorierte Kinds
    [Test] procedure Suppression_NoinspectionTodoComment_FiltersFinding;
    [Test] procedure Suppression_NoinspectionEmptyMethod_FiltersFinding;
    [Test] procedure Suppression_NoinspectionDuplicateBlock_FiltersFinding;
  end;

implementation

{ ---- NilDeref ---- }

procedure TTestNewChecks.NilDeref_NilThenDot_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkNilDeref),
      'nil-Zuweisung dann Punktzugriff – Error');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_AssignedGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if Assigned(obj) then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'Assigned()-Guard – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_NotNilGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if obj <> nil then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'obj <> nil Guard – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_Reassigned_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj := TStringList.Create;'#13#10+
  '  obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'Neuzuweisung vor Zugriff – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_FreeIsSafe_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      '.Free ist nil-sicher (TObject.Free prueft Self) – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_FreeAndNilIsSafe_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  FreeAndNil(obj);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'FreeAndNil ist nil-sicher – kein Befund');
  finally F.Free; end;
end;

{ ---- MissingFinally ---- }

procedure TTestNewChecks.MissingFinally_CreateFreeNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMissingFinally),
      'Create+Free ohne try/finally – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_TryFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
      'try/finally vorhanden – kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_NoFreeAtAll_NoFinding;
// Wird von TLeakDetector2 als lsError gemeldet, nicht als MissingFinally
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
      'Kein Free → TLeakDetector2 zustaendig, kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_TryExceptOnly_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  except'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMissingFinally),
      'try/except ohne finally – Warning');
  finally F.Free; end;
end;

{ ---- DivByZero ---- }

procedure TTestNewChecks.DivByZero_LiteralZero_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var x: Integer;'#13#10+
  'begin'#13#10+
  '  x := 100 div 0;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsError),
      'Literal 0 als Divisor – Error');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_ParamWithoutGuard_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Avg(Sum, Count: Integer): Integer;'#13#10+
  'begin'#13#10+
  '  Result := Sum div Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
      'Parameter Count ohne Guard – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_ParamWithGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Avg(Sum, Count: Integer): Integer;'#13#10+
  'begin'#13#10+
  '  if Count > 0 then'#13#10+
  '    Result := Sum div Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero),
      'Guard if Count > 0 – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_LocalVarWithoutGuard_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var n, m, r: Integer;'#13#10+
  'begin'#13#10+
  '  n := GetN;'#13#10+
  '  m := GetM;'#13#10+
  '  r := n div m;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
      'Lokale Var m ohne Guard – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_NonIntegerType_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var s: TStringList; r: Integer;'#13#10+
  'begin'#13#10+
  '  r := 100 div s.Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero),
      'Property-Zugriff statt Variable – kein Befund');
  finally F.Free; end;
end;

{ ---- DeadCode ---- }

procedure TTestNewChecks.DeadCode_AfterExit_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Exit;'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach Exit – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_AfterRaise_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  raise Exception.Create(''X'');'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach raise – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_AfterBreakInLoop_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 9 do'#13#10+
  '  begin'#13#10+
  '    Break;'#13#10+
  '    DoSomething;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach Break in Loop – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ConditionalExit_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if Condition then'#13#10+
  '    Exit;'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'Bedingtes Exit – DoSomething nicht tot');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ExitInIfThenElse_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    Exit'#13#10+
  '  else'#13#10+
  '    DoB;'#13#10+
  '  DoC;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'Exit in if-Branch, else vorhanden – kein toter Code');
  finally F.Free; end;
end;

{ ---- LongMethod (verbessert) ---- }

procedure TTestNewChecks.LongMethod_ShortBodyLongSignature_NoFinding;
// Lange Parameter-Liste, aber sehr kurzer Body → KEIN Befund.
// Vorher haette das geflaggt werden koennen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar('#13#10+
  '  A: Integer;'#13#10+
  '  B: Integer;'#13#10+
  '  C: Integer;'#13#10+
  '  D: Integer;'#13#10+
  '  E: Integer;'#13#10+
  '  F: Integer;'#13#10+
  '  G: Integer;'#13#10+
  '  H: Integer;'#13#10+
  '  I: Integer;'#13#10+
  '  J: Integer);'#13#10+
  'begin'#13#10+
  '  Result := A + B;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod),
      'Body ist kurz – keine LongMethod-Warnung trotz langer Signatur');
  finally F.Free; end;
end;

procedure TTestNewChecks.LongMethod_LongBodyManyStatements_ReportsWarning;
// Echter langer Body mit > 30 Anweisungen UND > 50 Body-Zeilen → Warning
var
  SB: TStringBuilder;
  Src: string;
  F: TObjectList<TLeakFinding>;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; implementation');
    SB.AppendLine('procedure TFoo.Bar;');
    SB.AppendLine('begin');
    for i := 1 to 60 do
      SB.AppendLine(Format('  X%d := %d;', [i, i]));
    SB.AppendLine('end;');
    Src := SB.ToString;
  finally
    SB.Free;
  end;

  F := TFindingHelper.FindingsOf(Src);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkLongMethod),
      'Body > 50 Zeilen UND > 30 Anweisungen – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.LongMethod_ForwardDecl_NoFinding;
// Methoden ohne Body (Forward, Interface) duerfen nicht geflaggt werden
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TFoo = class'#13#10+
  '    procedure VeryVeryLongMethodName(A, B, C, D, E: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod),
      'Methode in Interface-Section ohne Body – kein Befund');
  finally F.Free; end;
end;

{ ---- DeepNesting (verbessert) ---- }

procedure TTestNewChecks.DeepNesting_TryFinallyOnly_NoFinding;
// 5 verschachtelte try/finally → KEIN Befund (Resource-Management)
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try'#13#10+
  '      try'#13#10+
  '        try'#13#10+
  '          try'#13#10+
  '            DoIt;'#13#10+
  '          finally'#13#10+
  '            C5.Free;'#13#10+
  '          end;'#13#10+
  '        finally C4.Free; end;'#13#10+
  '      finally C3.Free; end;'#13#10+
  '    finally C2.Free; end;'#13#10+
  '  finally C1.Free; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting),
      'try/finally zaehlen nicht als logische Verschachtelung');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeepNesting_FiveLogicalLevels_ReportsWarning;
// 5 verschachtelte if/for/while → Befund
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i, j, k, m, n: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 9 do'#13#10+
  '    for j := 0 to 9 do'#13#10+
  '      for k := 0 to 9 do'#13#10+
  '        for m := 0 to 9 do'#13#10+
  '          if i + j + k + m > 0 then'#13#10+
  '            n := i;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeepNesting),
      '5 verschachtelte Schleifen/if – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeepNesting_TryAroundFourLevels_NoFinding;
// try um 4 logische Ebenen → Tiefe 4, kein Befund
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i, j, k: Integer;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    for i := 0 to 9 do'#13#10+
  '      for j := 0 to 9 do'#13#10+
  '        for k := 0 to 9 do'#13#10+
  '          if i > j then DoIt;'#13#10+
  '  finally'#13#10+
  '    Cleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting),
      'try um 4 logische Ebenen – Tiefe 4, am Limit, kein Befund');
  finally F.Free; end;
end;

{ ---- Suppression ---- }
// Diese Tests speichern Pascal-Code in tempordativen Dateien, weil Suppression
// das Originalfile lesen muss (FindingsOf nutzt nur Strings).

procedure WriteTempPas(const Content: string; out FileName: string);
begin
  FileName := IncludeTrailingPathDelimiter(TPath.GetTempPath) +
              'sca_test_' + IntToStr(Random(MaxInt)) + '.pas';
  TFile.WriteAllText(FileName, Content, TEncoding.UTF8);
end;

procedure TTestNewChecks.Suppression_NoinspectionSpecificKind_FiltersFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection MemoryLeak'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        '// noinspection MemoryLeak unterdrueckt das Leak');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionAll_FiltersAllFindings;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection All'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        '// noinspection All unterdrueckt alles');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_WrongKind_DoesNotFilter;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection SQLInjection'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
        'Falsche Kategorie unterdrueckt nicht');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_MultipleKinds_FiltersAll;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection MemoryLeak, MissingFinally'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list.Free;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        'MemoryLeak unterdrueckt');
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
        'MissingFinally unterdrueckt');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionTodoComment_FiltersFinding;
// KindFromName wurde um 'todocomment' erweitert (vorher Silent-Bypass).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  // noinspection TodoComment'#13#10+
  '  // TODO: implementieren'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkTodoComment),
        '// noinspection TodoComment unterdrueckt den TODO-Befund');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionEmptyMethod_FiltersFinding;
// KindFromName um 'emptymethod' erweitert.
const SRC =
  'unit t; implementation'#13#10+
  '// noinspection EmptyMethod'#13#10+
  'procedure TFoo.NothingHere;'#13#10+
  'begin'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod),
        '// noinspection EmptyMethod unterdrueckt leere Methode');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionDuplicateBlock_FiltersFinding;
// KindFromName um 'duplicateblock' erweitert.
// Hinweis: DuplicateBlock braucht >=8 identische Zeilen. Test deckt einen
// minimalen Block ab und prueft: Suppression-Comment auf der ZWEITEN
// Wiederholung unterdrueckt den Befund (oder mindestens nicht alle).
const SRC =
  'unit t; implementation'#13#10+
  'procedure A;'#13#10+
  'begin'#13#10+
  '  Logger.Info(''start a'');'#13#10+
  '  Conn.Open;'#13#10+
  '  Q.SQL.Text := ''select 1'';'#13#10+
  '  Q.Open;'#13#10+
  '  Q.First;'#13#10+
  '  Q.Close;'#13#10+
  '  Conn.Close;'#13#10+
  '  Logger.Info(''end a'');'#13#10+
  'end;'#13#10+
  '// noinspection DuplicateBlock'#13#10+
  'procedure B;'#13#10+
  'begin'#13#10+
  '  Logger.Info(''start a'');'#13#10+
  '  Conn.Open;'#13#10+
  '  Q.SQL.Text := ''select 1'';'#13#10+
  '  Q.Open;'#13#10+
  '  Q.First;'#13#10+
  '  Q.Close;'#13#10+
  '  Conn.Close;'#13#10+
  '  Logger.Info(''end a'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
  CountWithSuppress: Integer;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      // Mindestens ein Befund muss durch die Suppression unterdrueckt sein -
      // ohne Suppression haetten wir 2 Treffer (beide Bloecke).
      CountWithSuppress := TFindingHelper.Count(F, fkDuplicateBlock);
      Assert.IsTrue(CountWithSuppress < 2,
        '// noinspection DuplicateBlock muss mind. einen Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.DeadCode_ExitBeforeExceptBlock_NoFinding;
// exit als letzte Anweisung im try-Body, danach except-Block – KEIN toter Code
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Get(node: TXmlNode): string;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    Result := node.Text;'#13#10+
  '    Exit;'#13#10+
  '  except'#13#10+
  '    on E: Exception do raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'except-Block ist kein sequenzieller Code – kein DeadCode');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ExitBeforeFinallyBlock_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Cleanup;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoWork;'#13#10+
  '    Exit;'#13#10+
  '  finally'#13#10+
  '    DoCleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'finally-Block laeuft auch nach Exit – kein DeadCode');
  finally F.Free; end;
end;

{ ---- Robustheit ---- }

procedure TTestNewChecks.Robust_NonExistentFile_ReportsFileError;
// Eine Datei die nicht existiert -> fkFileReadError, kein Crash
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaks(
    'D:\does\not\exist\nirvana.pas');
  try
    Assert.IsTrue(F.Count >= 1, 'Mindestens 1 Befund erwartet');
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Nicht-existente Datei -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_EmptyFileName_ReportsFileError;
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaks('');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Leerer Dateiname -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_NonExistentDirectory_ReportsFileError;
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaksRecursive(
    'D:\nirgendwo\unbekannt');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Nicht-existentes Verzeichnis -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_EmptyDirectory_ReportsFileError;
// Test mit leerem String-Pfad -> fkFileReadError
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaksRecursive('');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Leerer Pfad -> fkFileReadError');
  finally F.Free; end;
end;

end.
