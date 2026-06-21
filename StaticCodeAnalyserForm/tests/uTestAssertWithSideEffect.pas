unit uTestAssertWithSideEffect;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAssertWithSideEffect = class
  public
    [Test] procedure AssertWithCall_Reported;
    [Test] procedure AssertPureExpression_NotReported;
    [Test] procedure AssertWithLengthCall_NotReported;
    [Test] procedure AssertWithConversionFunc_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAssertWithSideEffect.AssertWithCall_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Assert(InitializeSubsystem);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkAssertWithSideEffect) >= 1,
      'Assert mit InitXxx-Call muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAssertWithSideEffect.AssertPureExpression_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  Assert(x > 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertWithSideEffect),
      'Assert mit reiner Comparison ist OK');
  finally F.Free; end;
end;

procedure TTestAssertWithSideEffect.AssertWithLengthCall_NotReported;
// Length ist auf der Pure-Whitelist -> kein FP.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin'#13#10 +
  '  Assert(Length(s) > 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertWithSideEffect),
      'Length() ist Pure-Func, kein Finding');
  finally F.Free; end;
end;

procedure TTestAssertWithSideEffect.AssertWithConversionFunc_NotReported;
// FP-Fix (Real-World 2026-06-21): reine Conversion-Funktionen (FloatToStr
// & Co.) sind NICHT auf der Pure-Whitelist, haben aber keinen Mutations-
// Verb-Praefix -> kein Side-Effect -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Double);'#13#10 +
  'begin'#13#10 +
  '  Assert(FloatToStr(x) = ''1.0'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertWithSideEffect),
      'FloatToStr ist eine Conversion-Func, kein Side-Effect');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAssertWithSideEffect);

end.
