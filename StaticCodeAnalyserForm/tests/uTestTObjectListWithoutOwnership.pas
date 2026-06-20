unit uTestTObjectListWithoutOwnership;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTObjectListWithoutOwnership = class
  public
    [Test] procedure TListAddCreate_Reported;
    [Test] procedure TObjectListAddCreate_NotReported;
    [Test] procedure TListNoAdd_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTObjectListWithoutOwnership.TListAddCreate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
      'TList<TFoo> + Add(TFoo.Create) muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.TObjectListAddCreate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TObjectList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TObjectList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
      'TObjectList ist korrekt - kein Finding');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.TListNoAdd_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
      'TList ohne Add ist kein Leak-Risk');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTObjectListWithoutOwnership);

end.
