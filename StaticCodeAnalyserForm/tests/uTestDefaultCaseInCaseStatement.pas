unit uTestDefaultCaseInCaseStatement;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDefaultCaseInCaseStatement = class
  public
    [Test] procedure CaseWithoutElse_Reported;
    [Test] procedure CaseWithElse_NotReported;
    [Test] procedure CaseWithEmptyElse_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDefaultCaseInCaseStatement.CaseWithoutElse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  case x of'#13#10 +
  '    1: DoOne;'#13#10 +
  '    2: DoTwo;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkDefaultCaseInCaseStatement) >= 1,
      'case ohne else muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDefaultCaseInCaseStatement.CaseWithElse_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  case x of'#13#10 +
  '    1: DoOne;'#13#10 +
  '  else'#13#10 +
  '    DoOther;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDefaultCaseInCaseStatement),
      'case mit else darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDefaultCaseInCaseStatement.CaseWithEmptyElse_NotReported;
// `else ;` ist explizite Default-No-Op-Markierung -> kein FP.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  case x of'#13#10 +
  '    1: DoOne;'#13#10 +
  '  else'#13#10 +
  '    ;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDefaultCaseInCaseStatement),
      'leeres else ist akzeptierte Default-Markierung');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDefaultCaseInCaseStatement);

end.
