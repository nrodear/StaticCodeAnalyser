unit uTestConstantReturn;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstantReturn = class
  public
    [Test] procedure SameLiteralEveryPath_Reported;
    [Test] procedure DifferentLiterals_NotReported;
    [Test] procedure SingleAssignment_NotReported;
    [Test] procedure NonLiteralRhs_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstantReturn.SameLiteralEveryPath_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then'#13#10 +
  '    Result := 30'#13#10 +
  '  else'#13#10 +
  '    Result := 30;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1);
  finally F.Free; end;
end;

procedure TTestConstantReturn.DifferentLiterals_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then Result := 30 else Result := 60;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.SingleAssignment_NotReported;
// Eine einzige Result-Zuweisung -> trivial, kein Smell.
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 30;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.NonLiteralRhs_NotReported;
// Variable/Konstante als RHS -> kein klares "always returns literal X".
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then Result := DEFAULT_TIMEOUT else Result := DEFAULT_TIMEOUT;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin'#13#10 +
  '  if X then Result := 1 else Result := 1;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkConstantReturn then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkConstantReturn finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstantReturn);

end.
