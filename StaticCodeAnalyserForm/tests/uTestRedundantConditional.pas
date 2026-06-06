unit uTestRedundantConditional;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantConditional = class
  public
    [Test] procedure NormalCond_NoFinding;
    [Test] procedure IfTrueElseFalse_Reported;
    [Test] procedure IfFalseElseTrue_Reported;
    [Test] procedure DifferentTargets_NoFinding;
    [Test] procedure BothSameBool_NoFinding;
    [Test] procedure RedundantConditional_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantConditional.NormalCond_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then DoStuff else DoOther;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantConditional));
  finally F.Free; end;
end;

procedure TTestRedundantConditional.IfTrueElseFalse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then Result := True else Result := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantConditional));
  finally F.Free; end;
end;

procedure TTestRedundantConditional.IfFalseElseTrue_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then Result := False else Result := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantConditional));
  finally F.Free; end;
end;

procedure TTestRedundantConditional.DifferentTargets_NoFinding;
// `if X then A := True else B := False` - unterschiedliche Targets,
// kein redundant (eigene Logik).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if X then A := True else B := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantConditional));
  finally F.Free; end;
end;

procedure TTestRedundantConditional.BothSameBool_NoFinding;
// Beide Branches True (oder beide False) - das ist kein "polarity flip"
// sondern ein anderes Pattern (vermutlich Bug aber nicht das, was wir
// hier detektieren).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if X then Result := True else Result := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantConditional));
  finally F.Free; end;
end;

procedure TTestRedundantConditional.RedundantConditional_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if X then R := True else R := False; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantConditional then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantConditional, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantConditional finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantConditional);

end.
