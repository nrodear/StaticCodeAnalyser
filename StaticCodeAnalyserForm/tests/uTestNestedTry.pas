unit uTestNestedTry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNestedTry = class
  public
    [Test] procedure SingleTry_NoFinding;
    [Test] procedure NestedTryExcept_Reported;
    [Test] procedure NestedTryFinally_Reported;
    [Test] procedure NestedTry_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNestedTry.SingleTry_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff; except Log; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNestedTry));
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTryExcept_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      DoInner;'#13#10 +
  '    except'#13#10 +
  '      LogInner;'#13#10 +
  '    end;'#13#10 +
  '  except'#13#10 +
  '    LogOuter;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedTry) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      DoStuff;'#13#10 +
  '    finally'#13#10 +
  '      CleanupA;'#13#10 +
  '    end;'#13#10 +
  '  finally'#13#10 +
  '    CleanupB;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedTry) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTry_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try try DoStuff; except Log; end; except Outer; end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkNestedTry then
      begin
        Assert.AreEqual<TFindingKind>(fkNestedTry, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkNestedTry finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNestedTry);

end.
