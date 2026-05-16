unit uTestTwiceInheritedCalls;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTwiceInheritedCalls = class
  public
    [Test] procedure SingleInherited_NoFinding;
    [Test] procedure TwoInherited_Reported;
    [Test] procedure NoInherited_NoFinding;
    [Test] procedure TwiceInheritedCalls_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTwiceInheritedCalls.SingleInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwoInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.NoInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwiceInheritedCalls_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTwiceInheritedCalls then
      begin
        Assert.AreEqual<TFindingKind>(fkTwiceInheritedCalls, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTwiceInheritedCalls finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTwiceInheritedCalls);

end.
