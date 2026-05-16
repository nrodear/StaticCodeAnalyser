unit uTestExceptOnException;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExceptOnException = class
  public
    [Test] procedure SpecificException_NoFinding;
    [Test] procedure OnException_Reported;
    [Test] procedure OnEDatabaseError_NotReported;
    [Test] procedure ExceptOnException_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExceptOnException.SpecificException_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: EFOpenError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnException_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: Exception do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnEDatabaseError_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: EDatabaseError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.ExceptOnException_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; try except on E: Exception do Log(E.Message); end; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkExceptOnException then
      begin
        Assert.AreEqual<TFindingKind>(fkExceptOnException, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkExceptOnException finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptOnException);

end.
