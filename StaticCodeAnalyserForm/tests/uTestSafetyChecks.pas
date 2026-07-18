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
    // Real-World FP-Audit 2026-07-10 Regression (guarded/provably-nonzero)
    [Test] procedure Div_ZeroThenFixupAssign_NoFinding;
    [Test] procedure Div_ConstInitNonZeroLocal_NoFinding;
    [Test] procedure Div_ZeroInitLocalDivisor_StillReports;
    // Real-World FP-Audit 2026-07-12 (SCA010 5/23 Sample-FP), neue Guards:
    // G1 for-Schleifenvariable mit nichtnull-Unterschranke
    [Test] procedure Div_ForLoopVarNonZeroStart_NoFinding;
    [Test] procedure Div_ForLoopVarInlineTyped_NoFinding;
    // TP-Gegenprobe: 'for i := 0 to' -> i startet bei 0 -> bleibt Fund
    [Test] procedure Div_ForLoopVarZeroStart_StillReports;
    // G2 Break/Continue-Bail-Guard im selben Schleifenrumpf
    [Test] procedure Div_BreakGuardSameLoop_NoFinding;
    [Test] procedure Div_ContinueGuardSameLoop_NoFinding;
    // TP-Gegenprobe: Division NACH der Schleife wird vom Break nicht geschuetzt
    [Test] procedure Div_BreakGuardOutsideLoop_StillReports;
    // G3 Clamp-Divisor Max(1,..) / Round(Max(1,..))
    [Test] procedure Div_MaxClampDivisor_NoFinding;
    [Test] procedure Div_RoundMaxClampDivisor_NoFinding;
    // TP-Gegenprobe: Max(0,..) kann 0 sein -> bleibt Fund
    [Test] procedure Div_MaxZeroClampDivisor_StillReports;
    // TP-Gegenprobe (Verify 2026-07-12): zusammengesetzter Max-Ausdruck kann 0 sein
    [Test] procedure Div_CompositeMaxDivisor_StillReports;
    // --- G4 while-Kopf-Guard (Welle 1 5%-FP-Konzept 2026-07-18) ---
    [Test] procedure Div_WhileGuardNonZero_NoFinding;
    [Test] procedure Div_WhileGuardReassignBeforeDiv_StillReports;   // TP-Gegenprobe
    [Test] procedure Div_WhileGuardDecBeforeDiv_StillReports;        // TP-Gegenprobe
  end;

  // ---- DeadCode Erweiterungen --------------------------------------------------------
  [TestFixture]
  TTestDeadCodeExt = class
  public
    [Test] procedure DeadCode_NoDeadCode_NoFinding;
    [Test] procedure DeadCode_TwoExitsBothFollowedByDead_BothReported;
    [Test] procedure DeadCode_ExitAtMethodEnd_NoFinding;
    // Real-World FP-Audit 2026-07-10: 'raise ... at ReturnAddress' ist ein Statement
    [Test] procedure DeadCode_RaiseAtReturnAddress_NoFinding;
    // Real-World FP-Audit 2026-07-10 'continue-as-local-variable':
    // lokale var 'Continue'/'Break' ausserhalb jeder Schleife -> kein toter Code
    [Test] procedure DeadCode_ContinueLocalVarOutsideLoop_NoFinding;
    [Test] procedure DeadCode_ContinueLocalVarBeforeRepeatLoop_NoFinding;
    // TP-Guard: echtes Continue im Schleifenrumpf + Folgecode bleibt Fund
    [Test] procedure DeadCode_ContinueInForLoopFollowedByDead_Reported;
    // Welle 3 (nkConditionalRange): Exit + Folgecode in verschiedenen {$IFDEF}-Zweigen
    [Test] procedure DeadCode_IfdefElseBranch_NoFinding;
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

procedure TTestDivByZeroExt.Div_WhileGuardNonZero_NoFinding;
// 'while n > 0 do begin x := total div n; Dec(n); end' -> im Rumpf ist n am
// Divisionspunkt nachweislich > 0 (Dec liegt NACH der Division). Kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var n, x, total: Integer;'#13#10+
  'begin'#13#10+
  '  n := GetCount;'#13#10+
  '  while n > 0 do'#13#10+
  '  begin'#13#10+
  '    x := total div n;'#13#10+
  '    Dec(n);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'while n > 0 schuetzt n im Rumpf, Dec erst nach der Division -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_WhileGuardReassignBeforeDiv_StillReports;
// TP-Gegenprobe: 'n := GetNext' im Rumpf VOR der Division hebt die Kopf-Garantie
// auf - n kann dort 0 sein -> Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var n, x, total: Integer;'#13#10+
  'begin'#13#10+
  '  n := GetCount;'#13#10+
  '  while n > 0 do'#13#10+
  '  begin'#13#10+
  '    n := GetNext;'#13#10+
  '    x := total div n;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Reassign des Divisors vor der Division -> Guard greift nicht -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_WhileGuardDecBeforeDiv_StillReports;
// TP-Gegenprobe: 'Dec(n)' VOR der Division kann n auf 0 ziehen -> Fund bleibt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var n, x, total: Integer;'#13#10+
  'begin'#13#10+
  '  n := GetCount;'#13#10+
  '  while n > 0 do'#13#10+
  '  begin'#13#10+
  '    Dec(n);'#13#10+
  '    x := total div n;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Dec(n) vor der Division -> Guard greift nicht -> Fund bleibt');
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

procedure TTestDeadCodeExt.DeadCode_RaiseAtReturnAddress_NoFinding;
// Real-World FP-Audit 2026-07-10 'raise-at-clause': 'raise E.Create(m) at
// ReturnAddress;' parst als nkRaise + separater 'at'-Knoten auf DERSELBEN
// Quellzeile - kein toter Code, sondern Teil des raise-Statements.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  raise Exception.Create(''x'') at ReturnAddress;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'at ReturnAddress ist Teil des raise, kein toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_ContinueLocalVarOutsideLoop_NoFinding;
// Real-World FP-Audit 2026-07-10 'continue-as-local-variable': eine lokale
// Boolean-Variable 'Continue' mit 'Continue := True;' ausserhalb jeder
// Schleife parst der Parser als nkContinue. Kein toter Code - ein echtes
// Continue waere hier ausserdem ein Compilerfehler.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var Continue: Boolean;'#13#10+
  'begin'#13#10+
  '  Continue := True;'#13#10+
  '  DoStuff;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'Continue-Zuweisung ausserhalb einer Schleife ist kein toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_ContinueLocalVarBeforeRepeatLoop_NoFinding;
// Wie Alcinoe.AVLBinaryTree.pas:400 - 'Continue := True;' steht VOR einer
// spaeteren repeat-Schleife, also auf Methoden-Block-Ebene (Loop-Tiefe 0).
// Muss auch dann unterdrueckt werden, wenn die Methode weiter unten eine
// Schleife enthaelt (Loop-Tiefe pro Knoten, nicht pro Methode).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var Continue: Boolean;'#13#10+
  'begin'#13#10+
  '  Continue := True;'#13#10+
  '  DoInit;'#13#10+
  '  repeat'#13#10+
  '    DoStuff;'#13#10+
  '  until not Continue;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'Continue-Zuweisung vor einer Schleife ist kein toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_ContinueInForLoopFollowedByDead_Reported;
// TP-Guard: ein echtes Continue im Schleifenrumpf (Loop-Tiefe > 0) mit
// Folgeanweisung bleibt echter toter Code und muss weiter feuern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var I: Integer;'#13#10+
  'begin'#13#10+
  '  for I := 0 to 9 do'#13#10+
  '  begin'#13#10+
  '    Continue;'#13#10+
  '    DoDead;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 1,
    'Continue im Schleifenrumpf + Folgecode ist echter toter Code');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ZeroThenFixupAssign_NoFinding;
// FP guarded-nonzero (Real-World-Audit 2026-07-10, ULZMABench.pas:357): das
// Fix-up-Idiom 'if elapsed = 0 then elapsed := 1' garantiert elapsed <> 0 vor
// der Division. Init aus GetElapsed haelt die provably-nonzero-Heuristik
// bewusst draussen, damit NUR der Fix-up-Guard greift.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var elapsed, x: Integer;'#13#10+
  'begin'#13#10+
  '  elapsed := GetElapsed;'#13#10+
  '  if elapsed = 0 then'#13#10+
  '    elapsed := 1;'#13#10+
  '  x := 1000 div elapsed;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'if x = 0 then x := 1 -> x danach nachweislich <> 0 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ConstInitNonZeroLocal_NoFinding;
// FP provably-nonzero (Real-World-Audit 2026-07-10, SevenZipDlg.pas:201):
// numThreads wird nur mit nichtnull-Literalen belegt (init 1, ggf. 2) - kann
// an der Division nicht 0 sein. Kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var numThreads, x: Integer;'#13#10+
  'begin'#13#10+
  '  numThreads := 1;'#13#10+
  '  if UseMulti then'#13#10+
  '    numThreads := 2;'#13#10+
  '  x := 1000 div numThreads;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'Divisor nur mit nichtnull-Literalen belegt -> provably-nonzero -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ZeroInitLocalDivisor_StillReports;
// TP-Gegenprobe zur provably-nonzero-Heuristik: wird der Divisor mit dem
// Null-Literal belegt (absichtliche Div-durch-Null / echter Bug), darf die
// neue Suppression NICHT greifen - der Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var n, x: Integer;'#13#10+
  'begin'#13#10+
  '  n := 0;'#13#10+
  '  x := 100 div n;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Divisor := 0 ist kein nichtnull-Literal -> Suppression greift nicht -> Fund bleibt');
  finally F.Free; end;
end;

// -----------------------------------------------------------------------------
// G1 - for-Schleifenvariable mit nichtnull-Unterschranke
// (Real-World-FP-Audit 2026-07-12, CnImageListEditorFrm.pas:1547)
// -----------------------------------------------------------------------------

procedure TTestDivByZeroExt.Div_ForLoopVarNonZeroStart_NoFinding;
// 'for i := 2 to cnt' -> im Rumpf immer i >= 2 -> 'cnt div i' nie durch 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var i, cnt, x: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 2 to cnt do'#13#10+
  '    x := cnt div i;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'aufsteigende for-Var mit Startwert 2 ist im Rumpf immer >= 2 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ForLoopVarInlineTyped_NoFinding;
// Inline-typisierte Schleifenvariable: 'for var i: Integer := 2 to cnt'.
// Exerziert den nkLocalVar-Zweig von TryGetAscendingForLoopVar (die Var steht
// NICHT im Header, sondern als Kind-Knoten) - ohne Guard waere i (Typ Integer)
// als Divisor gemeldet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var cnt, x: Integer;'#13#10+
  'begin'#13#10+
  '  for var i: Integer := 2 to cnt do'#13#10+
  '    x := cnt div i;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'inline-typisierte aufsteigende for-Var mit Start 2 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ForLoopVarZeroStart_StillReports;
// TP-Gegenprobe: 'for i := 0 to cnt' -> i startet bei 0 -> erste Iteration
// 'cnt div 0' crasht. Der Guard darf NICHT greifen (Startwert 0).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var i, cnt, x: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to cnt do'#13#10+
  '    x := cnt div i;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Startwert 0 -> i kann 0 sein -> Fund muss bleiben');
  finally F.Free; end;
end;

// -----------------------------------------------------------------------------
// G2 - Break/Continue-Bail-Guard im selben Schleifenrumpf
// (Real-World-FP-Audit 2026-07-12, VirtualTrees.Header.pas:2639)
// -----------------------------------------------------------------------------

procedure TTestDivByZeroExt.Div_BreakGuardSameLoop_NoFinding;
// 'if x = 0 then Break;' vor 'y := z div x' im selben Schleifenrumpf ->
// an der Division ist x nachweislich <> 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y, z: Integer;'#13#10+
  'begin'#13#10+
  '  while z > 0 do'#13#10+
  '  begin'#13#10+
  '    x := GetNext;'#13#10+
  '    if x = 0 then Break;'#13#10+
  '    y := z div x;'#13#10+
  '    Dec(z);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'if x = 0 then Break im selben Loop vor der Division -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_ContinueGuardSameLoop_NoFinding;
// Wie Break, aber mit Continue: 'if x = 0 then Continue;' ueberspringt die
// Division bei x = 0 -> im Divisor immer x <> 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y, z: Integer;'#13#10+
  'begin'#13#10+
  '  while z > 0 do'#13#10+
  '  begin'#13#10+
  '    x := GetNext;'#13#10+
  '    if x = 0 then Continue;'#13#10+
  '    y := z div x;'#13#10+
  '    Dec(z);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'if x = 0 then Continue im selben Loop vor der Division -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_BreakGuardOutsideLoop_StillReports;
// TP-Gegenprobe: die Division steht NACH der Schleife. Der Break garantiert x
// nur INNERHALB der Schleife <> 0; danach (Loop via Break/gar nicht gelaufen)
// kann x 0 sein -> Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y, z: Integer;'#13#10+
  'begin'#13#10+
  '  while z > 0 do'#13#10+
  '  begin'#13#10+
  '    x := GetNext;'#13#10+
  '    if x = 0 then Break;'#13#10+
  '    Dec(z);'#13#10+
  '  end;'#13#10+
  '  y := 100 div x;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Division ausserhalb der Schleife -> Break schuetzt nicht -> Fund bleibt');
  finally F.Free; end;
end;

// -----------------------------------------------------------------------------
// G3 - Clamp-Divisor Max(1,..) / Round(Max(1,..))
// (Real-World-FP-Audit 2026-07-12, VirtualTrees.BaseTree.pas:8256)
// -----------------------------------------------------------------------------

procedure TTestDivByZeroExt.Div_MaxClampDivisor_NoFinding;
// 'd := Max(1, GetCount)' -> d >= 1 -> '100 div d' nie durch 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var d, x: Integer;'#13#10+
  'begin'#13#10+
  '  d := Max(1, GetCount);'#13#10+
  '  x := 100 div d;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'Divisor := Max(1, ...) ist immer >= 1 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_RoundMaxClampDivisor_NoFinding;
// 'd := Round(Max(1, a / b))' -> Max(1,..) >= 1.0, Round(>=1.0) >= 1.
// (Die Float-Division a / b prueft SCA010 bewusst nicht.)
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var d, x, a, b: Integer;'#13#10+
  'begin'#13#10+
  '  d := Round(Max(1, a / b));'#13#10+
  '  x := 100 div d;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDivByZero),
    'Divisor := Round(Max(1, ...)) ist immer >= 1 -> kein Fund');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_MaxZeroClampDivisor_StillReports;
// TP-Gegenprobe: 'd := Max(0, GetCount)' kann 0 sein (kein nichtnull-Literal-
// Argument) -> Clamp-Guard darf NICHT greifen -> Fund bleibt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var d, x: Integer;'#13#10+
  'begin'#13#10+
  '  d := Max(0, GetCount);'#13#10+
  '  x := 100 div d;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'Max(0, ...) kann 0 sein -> Clamp-Guard greift nicht -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_CompositeMaxDivisor_StillReports;
// TP-Gegenprobe (Verify 2026-07-12, G3-FN-Fix): 'd := Max(1,a) - Max(1,b)' beginnt
// mit 'max(' und endet mit ')', kann aber 0 sein (a=b). Der matching-paren-Check
// erkennt, dass die erste 'max('-Klammer VOR dem Ende schliesst -> zusammengesetzt
// -> Clamp-Guard greift NICHT -> Fund bleibt (sonst verschluckter div-by-zero).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var d, a, b, x: Integer;'#13#10+
  'begin'#13#10+
  '  d := Max(1, a) - Max(1, b);'#13#10+
  '  x := 100 div d;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1,
    'zusammengesetzter Max-Ausdruck (Max(1,a)-Max(1,b)) kann 0 sein -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_IfdefElseBranch_NoFinding;
// Welle 3 (Core-Detektoren-Architektur): 'Exit' im {$IFDEF A}-Zweig, Folgecode im
// {$ELSE}-Zweig. Bei gemergten Branches (kein Token-Skip) sieht der Parser
// 'Exit; DoStuff;', aber die {$IFDEF}-Grenze ({$ELSE}) liegt dazwischen ->
// verschiedene bedingte Kompilierungs-Zweige -> kein toter Code. Der
// nkConditionalRange-Marker laesst SCA011 den FP unterdruecken.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '{$IFDEF A}'#13#10 +
  '  Exit;'#13#10 +
  '{$ELSE}'#13#10 +
  '  DoStuff;'#13#10 +
  '{$ENDIF}'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'Exit und Folgecode in verschiedenen {$IFDEF}-Zweigen sind kein toter Code');
  finally F.Free; end;
end;

end.
