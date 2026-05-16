unit uTestEmptyInterface;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyInterface = class
  public
    [Test] procedure InterfaceWithMethods_NoFinding;
    [Test] procedure EmptyInterfaceMultiline_Reported;
    [Test] procedure EmptyInterfaceWithParent_Reported;
    [Test] procedure EmptyInterfaceWithGuid_Reported;
    [Test] procedure UnitInterfaceSection_NotReported;
    [Test] procedure EmptyInterface_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyInterface.InterfaceWithMethods_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IFoo = interface'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceMultiline_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithParent_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IService = interface(IUnknown) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithGuid_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  '  [''{12345678-1234-1234-1234-123456789012}'']'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.UnitInterfaceSection_NotReported;
// Das Unit-Section-`interface` (vor `implementation`) darf NICHT als
// EmptyInterface gemeldet werden - es hat kein `=` davor.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterface_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyInterface then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyInterface, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyInterface finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyInterface);

end.
