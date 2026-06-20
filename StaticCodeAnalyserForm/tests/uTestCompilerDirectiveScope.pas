unit uTestCompilerDirectiveScope;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCompilerDirectiveScope = class
  public
    [Test] procedure WarningsOffWithoutOn_Reported;
    [Test] procedure WarningsOffAndOn_NotReported;
    [Test] procedure RangeChecksOffWithoutOn_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCompilerDirectiveScope.WarningsOffWithoutOn_Reported;
const SRC =
  '{$WARNINGS OFF}'#13#10 +
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCompilerDirectiveScope) >= 1,
      '{$WARNINGS OFF} ohne ON muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.WarningsOffAndOn_NotReported;
const SRC =
  '{$WARNINGS OFF}'#13#10 +
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  '{$WARNINGS ON}'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCompilerDirectiveScope),
      'OFF + ON ist balanced - kein Finding');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.RangeChecksOffWithoutOn_Reported;
const SRC =
  'unit t; interface'#13#10 +
  '{$RANGECHECKS OFF}'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCompilerDirectiveScope) >= 1,
      '{$RANGECHECKS OFF} ohne ON muss gemeldet werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCompilerDirectiveScope);

end.
