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
    [Test] procedure MissingFinally_ExceptReraise_NotReported;
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
    // Neue Detektoren - Suppression-Coverage einziehen
    [Test] procedure Suppression_NoinspectionConcatToFormat_FiltersFinding;
    [Test] procedure Suppression_NoinspectionWithStatement_FiltersFinding;
    [Test] procedure Suppression_NoinspectionReversedForRange_FiltersFinding;
    [Test] procedure Suppression_NoinspectionSelfAssignment_FiltersFinding;
    [Test] procedure Suppression_NoinspectionLengthUnderflow_FiltersFinding;
    [Test] procedure Suppression_NoinspectionCanBePrivate_FiltersFinding;
    // Coverage-Aufholjagd fuer die Schwaechsten 5
    [Test] procedure Suppression_NoinspectionCyclomaticComplexity_FiltersFinding;
    [Test] procedure Suppression_NoinspectionHardcodedPath_FiltersFinding;
    [Test] procedure Suppression_NoinspectionHardcodedSecret_FiltersFinding;
    [Test] procedure Suppression_NoinspectionSQLInjection_FiltersFinding;
    // DetectorMinSeverity - Post-Filter ueber TStaticAnalyzer2
    [Test] procedure Severity_MinError_DropsWarningsAndHints;
    [Test] procedure Severity_MinWarning_DropsHintsKeepsWarningsAndErrors;
    [Test] procedure Severity_MinHint_KeepsEverything;
    // MethodName-Nachtrag fuer line-basierte Befunde (Grid-Anzeige)
    [Test] procedure MethodName_FilledForLineBasedFinding;
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingFinally),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingFinally),
      'try/except ohne finally – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_ExceptReraise_NotReported;
// FP-Fix (Self-Scan 2026-06-21): `Obj := Create; try Build; except Obj.Free;
// raise; end` ist das Cleanup-und-Reraise-Idiom - bei Erfolg wird Obj
// behalten/transferiert (hier: zurueckgegeben), ein try/finally waere FALSCH.
// Bare re-raise im except -> kein MissingFinally.
// Unterschied zum MissingFinally_TryExceptOnly_ReportsWarning-Test ist GENAU
// das `raise;` - lokale Var, kein Return/Owner-Transfer, nur das bare re-raise
// im except unterscheidet die beiden Faelle.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var owned: TStringList;'#13#10+
  'begin'#13#10+
  '  owned := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    DoSomething(owned);'#13#10+
  '  except'#13#10+
  '    owned.Free;'#13#10+
  '    raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
      'except + bare raise = Cleanup-Reraise-Idiom, kein MissingFinally');
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
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkDivByZero, lsError),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLongMethod),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLongMethod),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLongMethod),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeepNesting),
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
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDeepNesting),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeepNesting),
      'try um 4 logische Ebenen – Tiefe 4, am Limit, kein Befund');
  finally F.Free; end;
end;

{ ---- Suppression ---- }
// Diese Tests speichern Pascal-Code in tempordativen Dateien, weil Suppression
// das Originalfile lesen muss (FindingsOf nutzt nur Strings).

procedure WriteTempPas(const Content: string; out FileName: string);
begin
  FileName := IncludeTrailingPathDelimiter(TPath.GetTempPath) +
              'sca_test_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','') + '.pas';
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
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
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
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
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
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
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
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
        'MemoryLeak unterdrueckt');
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
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
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
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
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
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

procedure TTestNewChecks.Suppression_NoinspectionConcatToFormat_FiltersFinding;
// fkConcatToFormat haengt am AST-Pfad. Suppression-Marker direkt ueber der
// Concat-Zeile muss den Refactor-Hint stillschalten.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: string; r: string;'#13#10+
  'begin'#13#10+
  '  // noinspection ConcatToFormat'#13#10+
  '  r := ''a'' + x + ''b'';'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConcatToFormat),
        '// noinspection ConcatToFormat muss den Hint unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionWithStatement_FiltersFinding;
// fkWithStatement ist file-scan-basiert. Marker auf der Zeile davor.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection WithStatement'#13#10+
  '  with L do Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithStatement),
        '// noinspection WithStatement muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionReversedForRange_FiltersFinding;
// fkReversedForRange ist file-scan-basiert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var i: Integer;'#13#10+
  'begin'#13#10+
  '  // noinspection ReversedForRange'#13#10+
  '  for i := 10 to 1 do Bar(i);'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange),
        '// noinspection ReversedForRange muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionSelfAssignment_FiltersFinding;
// fkSelfAssignment ist AST-basiert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin'#13#10+
  '  // noinspection SelfAssignment'#13#10+
  '  x := x;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
        '// noinspection SelfAssignment muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionLengthUnderflow_FiltersFinding;
// fkLengthUnderflow ist file-scan-basiert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const s: string);'#13#10+
  'var i: Integer;'#13#10+
  'begin'#13#10+
  '  // noinspection LengthUnderflow'#13#10+
  '  i := Length(s) - 3;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow),
        '// noinspection LengthUnderflow muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionCyclomaticComplexity_FiltersFinding;
// fkCyclomaticComplexity ist AST-basiert. Marker direkt ueber der
// Methoden-Deklaration (uSuppression mappt auf naechste non-comment Zeile).
const SRC =
  'unit t; implementation'#13#10+
  '// noinspection CyclomaticComplexity'#13#10+
  'procedure TFoo.Complex;'#13#10+
  'begin'#13#10+
  '  if a1 then x; if a2 then x; if a3 then x; if a4 then x;'#13#10+
  '  if a5 then x; if a6 then x; if a7 then x; if a8 then x;'#13#10+
  '  if a9 then x; if a10 then x; if a11 then x;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCyclomaticComplexity),
        '// noinspection CyclomaticComplexity muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionHardcodedPath_FiltersFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin'#13#10+
  '  // noinspection HardcodedPath'#13#10+
  '  p := ''C:\Windows\System32'';'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath),
        '// noinspection HardcodedPath muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionHardcodedSecret_FiltersFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  // noinspection HardcodedSecret'#13#10+
  '  FPassword := ''geheim123'';'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
        '// noinspection HardcodedSecret muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionSQLInjection_FiltersFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var q: TFDQuery; UserId: string;'#13#10+
  'begin'#13#10+
  '  // noinspection SQLInjection'#13#10+
  '  q.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
        '// noinspection SQLInjection muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionCanBePrivate_FiltersFinding;
// fkCanBeStrictPrivate ist AST-basiert (Helper wird nur in TFoo.Run gerufen
// -> klassisches strict-private-Setup). Test geht direkt ueber AnalyzeLeaks
// (single-file ohne gSymbolRefIndex - der Detektor laeuft jetzt sowieso
// nur single-file).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type TFoo = class'#13#10+
  '  public'#13#10+
  '    // noinspection CanBeStrictPrivate'#13#10+
  '    procedure Helper;'#13#10+
  '    procedure Run;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Helper; begin end;'#13#10+
  'procedure TFoo.Run; begin Helper; end;'#13#10+
  'end.';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeStrictPrivate),
        '// noinspection CanBeStrictPrivate muss den Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

{ ---- DetectorMinSeverity - Post-Filter ueber TStaticAnalyzer2 ---- }

// Helper: laeuft die Detector-Pipeline ueber TFindingHelper.FindingsOf
// (das ruft die Detektoren direkt auf, ohne Catalog-abhaengigen Gate-Skip),
// und appliziert dann den MinSeverity-Filter manuell - genau wie der
// Post-Filter in TStaticAnalyzer2 ihn anwendet.
//
// Warum nicht TStaticAnalyzer2.AnalyzeLeaks: dessen Pre-Filter liest die
// DefaultSeverity aus dem Rule-Catalog (rules\sca-rules.json). Im Test-
// Runtime liegt der Working-Dir tief in tests\Win32\Debug\, und der
// Catalog-Walker findet die JSON nicht (max 3 Levels hoch). Dann faellt
// die Default-Severity auf lsWarning zurueck (Fallback), und alle
// Detektoren werden bei MinSeverity=lsError am Gate geskippt - der
// Post-Filter (den wir hier eigentlich testen wollen) wird nie erreicht.
procedure RunWithMinSeverity(const SRC: string; MinSev: TLeakSeverity;
  out HasError, HasWarning, HasHint: Boolean);
var
  F : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  HasError   := False;
  HasWarning := False;
  HasHint    := False;
  F := TFindingHelper.FindingsOf(SRC);
  try
    for Fnd in F do
    begin
      // Post-Filter-Logik analog uStaticAnalyzer2.AnalyzeLeaks:
      // "Severity strenger als MinSeverity -> raus"
      if Ord(Fnd.Severity) > Ord(MinSev) then Continue;
      case Fnd.Severity of
        lsError   : HasError   := True;
        lsWarning : HasWarning := True;
        lsHint    : HasHint    := True;
      end;
    end;
  finally
    F.Free;
  end;
end;

// SRC mit Mix-Severities ueber rein AST-basierte Detektoren (damit der
// TFindingHelper.FindingsOf-Pfad das ohne Temp-File abdeckt):
//   * MemoryLeak (Error)    - TStringList.Create ohne Free in qualifizierter Methode
//   * LongParamList (Hint)  - 7 Parameter > DetectorMaxParams (=5 Default)
// (uMagicNumbers feuert NUR in if-Conditions, daher hier nicht nutzbar -
//  uLongParamList war urspruengliche Wahl, ist verlaesslich.)
const SEVERITY_MIX_SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(a, b, c, d, e, f, g: Integer);'#13#10+   // 7 params -> Hint
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+   // Error (MemoryLeak, no Free)
  '  list.Add(''x'');'#13#10+
  'end;';

procedure TTestNewChecks.Severity_MinError_DropsWarningsAndHints;
// MinSeverity=lsError -> nur Error-Findings bleiben uebrig.
var H_Err, H_Warn, H_Hint: Boolean;
begin
  RunWithMinSeverity(SEVERITY_MIX_SRC, lsError, H_Err, H_Warn, H_Hint);
  Assert.IsTrue(H_Err, 'Errors bleiben bei MinSeverity=lsError');
  Assert.IsFalse(H_Hint, 'Hints muessen bei MinSeverity=lsError gefiltert werden');
end;

procedure TTestNewChecks.Severity_MinWarning_DropsHintsKeepsWarningsAndErrors;
var H_Err, H_Warn, H_Hint: Boolean;
begin
  RunWithMinSeverity(SEVERITY_MIX_SRC, lsWarning, H_Err, H_Warn, H_Hint);
  Assert.IsTrue(H_Err, 'Errors duerfen bei MinSeverity=lsWarning nicht gefiltert werden');
  Assert.IsFalse(H_Hint, 'Hints muessen bei MinSeverity=lsWarning gefiltert werden');
end;

procedure TTestNewChecks.Severity_MinHint_KeepsEverything;
// Default-Pfad: lsHint laesst alles durch (lsHint > alle anderen Severities).
var H_Err, H_Warn, H_Hint: Boolean;
begin
  RunWithMinSeverity(SEVERITY_MIX_SRC, lsHint, H_Err, H_Warn, H_Hint);
  Assert.IsTrue(H_Err,  'lsHint laesst Errors durch');
  Assert.IsTrue(H_Hint, 'lsHint laesst Hints durch');
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
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
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
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

{ ---- MethodName-Nachtrag (Grid-Anzeige) ---- }

procedure TTestNewChecks.MethodName_FilledForLineBasedFinding;
// User-Report: im Grid fehlte bei line-basierten Befunden (z.B.
// AttributeDuplicate) die Methode, obwohl die Zeile in einer Methode liegt.
// Line-basierte Detektoren setzen MethodName=''; der zentrale Post-Pass
// FillMissingMethodNames in RunAllDetectors traegt die einschliessende
// Methode aus dem AST nach. Hier ueber HardcodedPath (line-basiert,
// MethodName='') in TFoo.Bar verifiziert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var p: string;'#13#10+
  'begin'#13#10+
  '  p := ''C:\Windows\System32'';'#13#10+
  'end;';
var
  FName : string;
  F     : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkHardcodedPath then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkHardcodedPath-Befund erwartet');
      Assert.AreNotEqual('', Hit.MethodName,
        'line-basierter Befund muss die einschliessende Methode tragen');
      Assert.IsTrue(Hit.MethodName.Contains('Bar'),
        'MethodName muss die Methode Bar nennen, war: ' + Hit.MethodName);
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

end.
