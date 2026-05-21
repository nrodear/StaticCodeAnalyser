unit uTestMissingUnitHeader;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingUnitHeader = class
  public
    [Test] procedure NoHeader_Reported;
    [Test] procedure WithLineComment_NotReported;
    [Test] procedure WithBlockComment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingUnitHeader.NoHeader_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingUnitHeader) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithLineComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '// Diese Unit macht XYZ.'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithBlockComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '{ Diese Unit macht XYZ }'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.Finding_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingUnitHeader then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingUnitHeader finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingUnitHeader);

end.
