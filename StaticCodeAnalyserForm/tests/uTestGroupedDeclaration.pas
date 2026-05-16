unit uTestGroupedDeclaration;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGroupedDeclaration = class
  public
    [Test] procedure SingleVarPerLine_NoFinding;
    [Test] procedure TwoVarsGrouped_Reported;
    [Test] procedure ThreeVarsGrouped_Reported;
    [Test] procedure ParameterGrouped_Reported;
    [Test] procedure FieldGrouped_Reported;
    [Test] procedure GroupedDeclaration_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGroupedDeclaration.SingleVarPerLine_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  A: Integer;'#13#10 +
  '  B: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.TwoVarsGrouped_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  A, B: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.ThreeVarsGrouped_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A, B, C: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.ParameterGrouped_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Integer); begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGroupedDeclaration) >= 1);
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.FieldGrouped_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FA, FB: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGroupedDeclaration) >= 1);
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.GroupedDeclaration_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var A, B: Integer; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkGroupedDeclaration then
      begin
        Assert.AreEqual<TFindingKind>(fkGroupedDeclaration, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,              Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkGroupedDeclaration finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGroupedDeclaration);

end.
