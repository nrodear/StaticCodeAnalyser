unit uTestBoolAlwaysTrue;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBoolAlwaysTrue = class
  public
    [Test] procedure LengthGreaterEqualZero_Reported;
    [Test] procedure LengthLessZero_Reported;
    [Test] procedure ZeroLessEqualLength_Reported;
    [Test] procedure LengthGreaterZero_NotReported;
    [Test] procedure NormalComparison_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBoolAlwaysTrue.LengthGreaterEqualZero_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  if Length(s) >= 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBoolAlwaysTrue) >= 1);
  finally F.Free; end;
end;

procedure TTestBoolAlwaysTrue.LengthLessZero_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  if Length(s) < 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBoolAlwaysTrue) >= 1);
  finally F.Free; end;
end;

procedure TTestBoolAlwaysTrue.ZeroLessEqualLength_Reported;
// 0 <= Length(s) ist dieselbe Aussage wie Length(s) >= 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  if 0 <= Length(s) then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBoolAlwaysTrue) >= 1);
  finally F.Free; end;
end;

procedure TTestBoolAlwaysTrue.LengthGreaterZero_NotReported;
// Length(s) > 0 ist eine echte Check und KEIN always-true.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  if Length(s) > 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBoolAlwaysTrue));
  finally F.Free; end;
end;

procedure TTestBoolAlwaysTrue.NormalComparison_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  if x >= 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBoolAlwaysTrue));
  finally F.Free; end;
end;

procedure TTestBoolAlwaysTrue.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  if Length(s) >= 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkBoolAlwaysTrue then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkBoolAlwaysTrue finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBoolAlwaysTrue);

end.
