unit uTestIntegerOverflow;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIntegerOverflow = class
  public
    [Test] procedure Int64Mul_TwoIntegers_Reported;
    [Test] procedure Int64Mul_OneIs64BitVar_NoFinding;
    [Test] procedure Int64Mul_Literal_NoFinding;
    [Test] procedure IntegerTarget_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestIntegerOverflow.Int64Mul_TwoIntegers_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  SectorCount: Integer;'#13#10 +
  '  SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIntegerOverflow) >= 1);
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Int64Mul_OneIs64BitVar_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  SectorCount: Int64;'#13#10 +
  '  SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Int64Mul_Literal_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  N: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := N * 1024;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.IntegerTarget_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  Total: Integer;'#13#10 +
  '  A, B: Integer;'#13#10 +
  'begin'#13#10 +
  '  Total := A * B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  R: Int64;'#13#10 +
  '  A: Integer;'#13#10 +
  '  B: Integer;'#13#10 +
  'begin'#13#10 +
  '  R := A * B;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkIntegerOverflow then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkIntegerOverflow finding expected');
    Assert.AreEqual(fkIntegerOverflow, Hit.Kind);
    Assert.AreEqual(lsError,           Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIntegerOverflow);

end.
