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

initialization
  TDUnitX.RegisterTestFixture(TTestVariantTypeMisuse);

end.
