unit uTestAvoidOut;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAvoidOut = class
  public
    [Test] procedure NoOutParam_NoFinding;
    [Test] procedure OutParam_Reported;
    [Test] procedure VarParam_NoFinding;
    [Test] procedure AvoidOut_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAvoidOut.NoOutParam_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.OutParam_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(out S: string); begin S := ''hi''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.VarParam_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(var S: string); begin S := ''hi''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.AvoidOut_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(out X: Integer); begin X := 0; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAvoidOut then
      begin
        Assert.AreEqual<TFindingKind>(fkAvoidOut, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,    Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAvoidOut finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAvoidOut);

end.
