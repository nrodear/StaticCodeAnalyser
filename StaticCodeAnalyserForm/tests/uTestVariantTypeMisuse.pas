unit uTestVariantTypeMisuse;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVariantTypeMisuse = class
  public
    [Test] procedure VariantLocalInMethodWithLoop_Reported;
    [Test] procedure VariantLocalInMethodWithoutLoop_NotReported;
    [Test] procedure IntegerLocalInLoop_NotReported;
    [Test] procedure OleVariantLocalInLoop_Reported;
    // Autopsie 2026-08-26, Gate A: In-Loop-Usage statt Methode-hat-Loop.
    [Test] procedure VariantOnlyBeforeLoop_NotReported;
    [Test] procedure VariantOnlyAfterLoop_NotReported;
    [Test] procedure VariantInWhileCondition_Reported;
    [Test] procedure NestedRoutineBlindSpot_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestVariantTypeMisuse.VariantLocalInMethodWithLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do v := v + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'Variant in Methode mit for-loop muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantLocalInMethodWithoutLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  v := 42;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Variant ohne Loop in der Methode ist kein Perf-Issue');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.IntegerLocalInLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do j := j + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Integer-Locals interessieren diesen Detektor nicht');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.OleVariantLocalInLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var ov: OleVariant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do ov := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'OleVariant zaehlt auch');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyBeforeLoop_NotReported;
// Gate A: der Variant wird nur VOR dem Loop benutzt - die dominante
// FP-Klasse der Autopsie (18/19 Stichproben-FPs, alle 14 Audit-FPs;
// 282 der 613 rw14-Funde).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i, n: Integer;'#13#10 +
  'begin'#13#10 +
  '  v := ReadConfig;'#13#10 +
  '  n := Integer(v);'#13#10 +
  '  for i := 0 to n do Work(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Variant ausserhalb des Loops ist kein Hot-Path-Problem');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyAfterLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i, s: Integer;'#13#10 +
  'begin'#13#10 +
  '  s := 0;'#13#10 +
  '  for i := 0 to 100 do s := s + i;'#13#10 +
  '  v := s;'#13#10 +
  '  Store(v);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Nutzung nur nach dem Loop');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantInWhileCondition_Reported;
// Die Loop-KOPF-Bedingung gehoert zum Loop-Teilbaum - Nutzung dort
// ist Hot-Path.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  v := Fetch;'#13#10 +
  '  while v <> Null do'#13#10 +
  '    v := Fetch;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'while-Bedingung ist In-Loop-Nutzung');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.NestedRoutineBlindSpot_StillReported;
// Guard: nested Routinen sind im AST verworfen (nkNestedRange) - die
// Nutzung im nested Loop ist unsichtbar, der Fund muss konservativ
// STEHEN bleiben (JvDBUtils-KeyValues-Familie, 36 Guard-Keeps mit
// belegten TPs - Gegenpruefung 2026-08-26).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  var k: Integer;'#13#10 +
  '  begin'#13#10 +
  '    for k := 0 to 9 do v := v + k;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 3 do Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'nested-blinde Methode bleibt konservativ gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVariantTypeMisuse);

end.
