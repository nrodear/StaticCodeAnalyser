unit uTestAssignedAndAssignedNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAssignedAndAssignedNil = class
  public
    [Test] procedure JustAssigned_NoFinding;
    [Test] procedure AssignedAndNotNil_Reported;
    [Test] procedure AssignedAndNotNil_NoParens_Reported;
    [Test] procedure DifferentIdentifiers_NoFinding;
    [Test] procedure AssignedAndAssignedNil_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAssignedAndAssignedNil.JustAssigned_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndNotNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and (Obj <> nil) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndNotNil_NoParens_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and Obj <> nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.DifferentIdentifiers_NoFinding;
// `Assigned(A) and (B <> nil)` - unterschiedliche Identifier, kein Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(A) and (B <> nil) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndAssignedNil_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and (Obj <> nil) then DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAssignedAndAssignedNil then
      begin
        Assert.AreEqual<TFindingKind>(fkAssignedAndAssignedNil, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAssignedAndAssignedNil finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAssignedAndAssignedNil);

end.
