unit uTestInterfaceName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInterfaceName = class
  public
    [Test] procedure IPrefix_NoFinding;
    [Test] procedure NoIPrefix_Reported;
    [Test] procedure DispInterface_Checked;
    [Test] procedure InterfaceName_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInterfaceName.IPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IService = interface end;'#13#10 +
  '  IFoo = interface(IUnknown) end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.NoIPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = interface end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.DispInterface_Checked;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = dispinterface end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.InterfaceName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = interface end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkInterfaceName then
      begin
        Assert.AreEqual<TFindingKind>(fkInterfaceName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkInterfaceName finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInterfaceName);

end.
