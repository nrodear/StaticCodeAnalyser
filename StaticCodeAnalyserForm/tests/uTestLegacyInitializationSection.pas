unit uTestLegacyInitializationSection;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLegacyInitializationSection = class
  public
    [Test] procedure NoInitBlock_NoFinding;
    [Test] procedure ModernInitialization_NoFinding;
    [Test] procedure LegacyBeginInit_Reported;
    [Test] procedure LegacyInit_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLegacyInitializationSection.NoInitBlock_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.ModernInitialization_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'initialization'#13#10 +
  '  RegisterClass(TFoo);'#13#10 +
  'finalization'#13#10 +
  '  Cleanup;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.LegacyBeginInit_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  '  RegisterClass(TFoo);'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.LegacyInit_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkLegacyInitializationSection then
      begin
        Assert.AreEqual<TFindingKind>(fkLegacyInitializationSection, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkLegacyInitializationSection finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLegacyInitializationSection);

end.
