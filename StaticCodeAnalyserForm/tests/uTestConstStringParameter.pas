unit uTestConstStringParameter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstStringParameter = class
  public
    [Test] procedure StringParam_NoConst_Reported;
    [Test] procedure StringParam_WithConst_NotReported;
    [Test] procedure StringParam_WithVar_NotReported;
    [Test] procedure IntegerParam_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstStringParameter.StringParam_NoConst_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Hash(s: string): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Hash(s: string): Integer;'#13#10 +
  'begin Result := Length(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkConstStringParameter) >= 1,
      's: string ohne const muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.StringParam_WithConst_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Hash(const s: string): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Hash(const s: string): Integer;'#13#10 +
  'begin Result := Length(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'const s: string ist OK');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.StringParam_WithVar_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Modify(var s: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Modify(var s: string);'#13#10 +
  'begin s := UpperCase(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'var s: string ist explizite Mutation - OK');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.IntegerParam_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Foo(i: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Foo(i: Integer): Integer;'#13#10 +
  'begin Result := i * 2; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'Integer-Param ist kein string - kein Finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstStringParameter);

end.
