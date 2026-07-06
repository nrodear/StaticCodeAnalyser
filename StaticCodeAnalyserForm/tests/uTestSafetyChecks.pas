unit uTestSafetyChecks;

// Tests fuer Sicherheits-/Korrektheits-Detektoren (Erweiterungen):
// NilDeref, MissingFinally, DivByZero, DeadCode.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- NilDeref Erweiterungen --------------------------------------------------------
  [TestFixture]
  TTestNilDerefExt = class
  public
    [Test] procedure NilDeref_AfterFreeAndDot_ReportsError;
    [Test] procedure NilDeref_TwoNilsBothReported;
    [Test] procedure NilDeref_AssignedFromCreate_NoFinding;
    [Test] procedure NilDeref_NilGuardWithBegin_NoFinding;
    // Wortgrenze: 'assigned(objOld)' darf 'obj' nicht schuetzen
    [Test] procedure NilDeref_AssignedGuardVarSubstring_StillReports;
    // FP-Gate (2026-07-04): out-param-assign - Call mit Var als Argument
    [Test] procedure NilDeref_OutParamCallBetween_NoFinding;
    // FP-Gate (2026-07-04): out-param-assign - Var als Ctor-Argument im RHS
    [Test] procedure NilDeref_CtorOutParamInAssignRhs_NoFinding;
    // FP-Gate (2026-07-04): for-in-loop-assign - for-in weist die Var zu
    [Test] procedure NilDeref_ForInLoopVar_NoFinding;
    // Gegenprobe: Call ohne die Variable (nur im String-Literal) gated NICHT
    [Test] procedure NilDeref_UnrelatedCallBetween_StillReports;
  end;

  // ---- MissingFinally Erweiterungen --------------------------------------------------
  [TestFixture]
  TTestMissingFinallyExt = class
  public
    [Test] procedure MissingFinally_TwoCreates_NoTry_BothReported;
    [Test] procedure MissingFinally_CreateAndImmediateRaise_NoFinding;
    [Test] procedure MissingFinally_FreeAndNilNoTry_ReportsWarning;
    [Test] procedure MissingFinally_NestedTryFinally_NoFinding;
    [Test] procedure MissingFinally_FreeBeforeTry_ReportsWarning;
    [Test] procedure MissingFinally_DestroyNoTry_ReportsWarning;
  end;

  // ---- DivByZero Erweiterungen -------------------------------------------------------
  [TestFixture]
  TTestDivByZeroExt = class
  public
    [Test] procedure Div_LiteralZeroMod_ReportsError;
    [Test] procedure Div_TwoZeroDivs_BothReported;
    [Test] procedure Div_NonZeroLiteral_NoFinding;
    [Test] procedure Div_GuardedLocalVar_NoFinding;
    [Test] procedure Div_StringDivisor_NoFinding;
    // FP-Gate Prio 7 (2026-07-06): "if n <= 0 then Exit"-Bail-Guard
    [Test] procedure Div_LessEqualZeroGuardExit_NoFinding;
    [Test] procedure Div_LessEqualZeroNoExit_StillReports;
  end;

  // ---- DeadCode Erweiterungen --------------------------------------------------------
  [TestFixture]
  TTestDeadCodeExt = class
  public
    [Test] procedure DeadCode_NoDeadCode_NoFinding;
    [Test] procedure DeadCode_TwoExitsBothFollowedByDead_BothReported;
    [Test] procedure DeadCode_ExitAtMethodEnd_NoFinding;
  end;

implementation

// =============================================================================
// NilDeref-Erweiterungen
// =============================================================================

procedure TTestNilDerefExt.NilDeref_AfterFreeAndDot_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := nil;'#13#10+
  '  lst.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilDeref),
      'genau 1 NilDeref-Fund erwartet');
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_TwoNilsBothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := nil;'#13#10+
  '  b := nil;'#13#10+
  '  a.Add(''x'');'#13#10+
  '  b.Add(''y'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 2);
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_AssignedFromCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  try lst.Add(''x''); finally lst.Free; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_NilGuardWithBegin_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(lst: TStringList);'#13#10+
  'begin'#13#10+
  '  if lst <> nil then'#13#10+
  '  begin'#13#10+
  '    lst.Add(''x'');'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_AssignedGuardVarSubstring_StillReports;
// Wortgrenze: 'assigned(objOld)' darf 'obj' NICHT als geguarded gelten.
// Vor dem WholeWord-Fix in CondHasGuard wuerde der Substring-Match
// 'assigned(obj' (in 'assigned(objOld)') faelschlicherweise als Guard
// fuer 'obj' anerkannt - der NilDeref-Befund bliebe damit aus.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var obj, objOld: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if assigned(objOld) then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'assigned(objOld) darf nicht als Guard fuer obj gelten');
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_OutParamCallBetween_NoFinding;
// FP-Gate (2026-07-04): out-param-assign - die Uebergabe der Variable als
// Argument an einen Aufruf zwischen nil-Zuweisung und Punkt-Zugriff zaehlt
// als Zuweisung (var/out-Parameter). Real-World-Muster: LoadJson(l, ...)
// in mORMot2 test.core.data.pas:4940 fuellt l vor l.Len (4942).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := nil;'#13#10+
  '  LoadThing(lst, 42);'#13#10+
  '  lst.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Uebergabe als Argument beendet den nil-Zustand - kein Befund');
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_CtorOutParamInAssignRhs_NoFinding;
// FP-Gate (2026-07-04): out-param-assign - die Variable steckt als
// Argument im RHS einer fremden Zuweisung. Real-World-Muster:
// Stub := TInterfaceStub.Create(TypeInfo(ICalculator), I) in mORMot2
// test.soa.core.pas:2428 fuellt I per out-Parameter vor I.Add (2441).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var stub: TObject;'#13#10+
  '  intf: ICalc;'#13#10+
  'begin'#13#10+
  '  intf := nil;'#13#10+
  '  stub := TInterfaceStub.Create(TypeInfo(ICalc), intf);'#13#10+
  '  intf.DoStuff;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Ctor-out-Argument im RHS beendet den nil-Zustand - kein Befund');
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_ForInLoopVar_NoFinding;
// FP-Gate (2026-07-04): for-in-loop-assign - 'for X in ...' weist X zu;
// der nil-Init davor dient typisch nur dem except-Handler. Real-World-
// Muster: lProp in MVCFramework.Serializer.URLEncoded.pas:306/314/330.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var itm: TObject;'#13#10+
  'begin'#13#10+
  '  itm := nil;'#13#10+
  '  for itm in FList do'#13#10+
  '    itm.DoStuff;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'for-in-Schleifenvariable gilt als zugewiesen - kein Befund');
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_UnrelatedCallBetween_StillReports;
// Gegenprobe zum out-param-assign-Gate: ein Aufruf zwischen nil und
// Zugriff, der die Variable NICHT als Argument uebergibt (hier steht
// 'lst' nur in einem String-Literal - StripStringLiterals-Pfad), darf
// den Befund nicht unterdruecken.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := nil;'#13#10+
  '  Log(''lst ist noch nil'');'#13#10+
  '  lst.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilDeref),
      'Aufruf ohne die Variable als Argument darf nicht gaten');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'lst.Add'),
      TFindingHelper.FirstOf(F, fkNilDeref).LineNumber,
      'Fund muss auf der Deref-Zeile liegen');
  finally F.Free; end;
end;

// =============================================================================
// MissingFinally-Erweiterungen
// =============================================================================

procedure TTestMissingFinallyExt.MissingFinally_TwoCreates_NoTry_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  a.Free;'#13#10+
  '  b.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 2);
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_CreateAndImmediateRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  raise Exception.Create(''boom'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_FreeAndNilNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Add(''x'');'#13#10+
  '  FreeAndNil(lst);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingFinally),
      'genau 1 MissingFinally-Fund erwartet');
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_NestedTryFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    b := TStringList.Create;'#13#10+
  '    try b.Add(''x''); finally b.Free; end;'#13#10+
  '  finally'#13#10+
  '    a.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_FreeBeforeTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Free;'#13#10+
  '  try DoStuff finally Cleanup; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingFinally),
      'genau 1 MissingFinally-Fund erwartet');
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_DestroyNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Add(''x'');'#13#10+
  '  lst.Destroy;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingFinally),
      'genau 1 MissingFinally-Fund erwartet');
  finally F.Free; end;
end;

// =============================================================================
// DivByZero-Erweiterungen
// =============================================================================

procedure TTestDivByZeroExt.Div_LiteralZeroMod_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 10 mod 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDivByZero),
      'genau 1 DivByZero-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'mod 0'),
      TFindingHelper.FirstOf(F, fkDivByZero).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_TwoZeroDivs_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 5 div 0;'#13#10+
  '  y := 7 div 0;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 2);
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_NonZeroLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 10 div 5; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_GuardedLocalVar_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, n: Integer;'#13#10+
  'begin'#13#10+
  '  if n <> 0 then'#13#10+
  '    x := 100 div n;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_StringDivisor_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := ''10 div 0''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_LessEqualZeroGuardExit_NoFinding;
// FP-Gate Prio 7 (Real-World-Audit 2026-07-04, guarded-divisor): das haeufige
// "if n <= 0 then Exit"-Bail-Idiom garantiert n > 0 danach - kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(n: Integer);'#13#10+
  'var x: Integer;'#13#10+
  'begin'#13#10+
  '  if n <= 0 then Exit;'#13#10+
  '  x := 100 div n;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'if n <= 0 then Exit -> n danach nachweislich > 0 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_LessEqualZeroNoExit_StillReports;
// Gegenprobe: "<= 0" OHNE Exit/Raise im then-Zweig ist KEIN Guard - n kann
// danach noch <= 0 sein und im Divisor crashen -> Fund bleibt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(n: Integer);'#13#10+
  'var x: Integer;'#13#10+
  'begin'#13#10+
  '  if n <= 0 then x := 1;'#13#10+
  '  x := 100 div n;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    '<= 0 ohne Exit/Raise ist kein Guard -> Fund muss bleiben');
  finally F.Free; end;
end;

// =============================================================================
// DeadCode-Erweiterungen
// =============================================================================

procedure TTestDeadCodeExt.DeadCode_NoDeadCode_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoA;'#13#10+
  '  DoB;'#13#10+
  '  DoC;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode));
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_TwoExitsBothFollowedByDead_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '  begin Exit; DoA; end;'#13#10+
  '  if B then'#13#10+
  '  begin Exit; DoB; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 2);
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_ExitAtMethodEnd_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoStuff;'#13#10+
  '  Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode));
  finally F.Free; end;
end;

end.
