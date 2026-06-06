unit uTestExplicitTObjectInheritance;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExplicitTObjectInheritance = class
  public
    [Test] procedure ImplicitInheritance_NoFinding;
    [Test] procedure OtherAncestor_NoFinding;
    [Test] procedure ExplicitTObject_Reported;
    [Test] procedure ExplicitTObjectWithWhitespace_Reported;
    [Test] procedure ExplicitTObjectInheritance_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExplicitTObjectInheritance.ImplicitInheritance_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.OtherAncestor_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class(TComponent)'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObject_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class(TObject)'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObjectWithWhitespace_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class ( TObject )'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObjectInheritance_KindAndSeverity;
const SRC =
  'unit t; interface type TFoo = class(TObject) end; implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkExplicitTObjectInheritance then
      begin
        Assert.AreEqual<TFindingKind>(fkExplicitTObjectInheritance, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkExplicitTObjectInheritance finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExplicitTObjectInheritance);

end.
