unit uTestBooleanParam;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBooleanParam = class
  public
    [Test] procedure BoolParamUsedInIf_Reported;
    [Test] procedure BoolParamPassedThrough_NotReported;
    [Test] procedure NoBoolParam_NotReported;
    [Test] procedure Setter_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBooleanParam.BoolParamUsedInIf_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SendMsg(const M: string; IsError: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if IsError then'#13#10 +
  '    NotifyRed(M)'#13#10 +
  '  else'#13#10 +
  '    NotifyBlack(M);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBooleanParam) >= 1);
  finally F.Free; end;
end;

procedure TTestBooleanParam.BoolParamPassedThrough_NotReported;
// Bool wird nur weitergegeben - kein internes Branching -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetVisible(V: Boolean);'#13#10 +
  'begin'#13#10 +
  '  DoSomething(V);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.NoBoolParam_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(N: Integer);'#13#10 +
  'begin'#13#10 +
  '  if N > 0 then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.Setter_NotReported;
// Property-Setter mit Boolean-Param ist Konvention - kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.SetEnabled(Value: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if Value then DoEnable else DoDisable;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(IsError: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if IsError then DoA else DoB;'#13#10 +
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
      if Fnd.Kind = fkBooleanParam then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkBooleanParam finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBooleanParam);

end.
