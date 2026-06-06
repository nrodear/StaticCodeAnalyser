unit uTestCaseStatementSize;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCaseStatementSize = class
  public
    [Test] procedure SmallCase_NoFinding;
    [Test] procedure LargeCase_Reported;
    [Test] procedure CaseStatementSize_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCaseStatementSize.SmallCase_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A;'#13#10 +
  '    2: B;'#13#10 +
  '    3: C;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.LargeCase_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A1;  2: A2;  3: A3;  4: A4;  5: A5;'#13#10 +
  '    6: A6;  7: A7;  8: A8;  9: A9; 10: A10;'#13#10 +
  '   11: A11;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.CaseStatementSize_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A; 2: B; 3: C; 4: D; 5: E;'#13#10 +
  '    6: F; 7: G; 8: H; 9: I; 10: J;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkCaseStatementSize then
      begin
        Assert.AreEqual<TFindingKind>(fkCaseStatementSize, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,             Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkCaseStatementSize finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCaseStatementSize);

end.
