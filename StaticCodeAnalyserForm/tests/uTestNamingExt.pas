unit uTestNamingExt;

// Tests fuer TNamingExtDetector (SCA118-119).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNamingExt = class
  public
    // ExceptionName
    [Test] procedure ExceptionWithoutEPrefix_Reported;
    [Test] procedure ExceptionWithEPrefix_NotReported;
    [Test] procedure NonExceptionClass_NotReported;

    // LocalConstantName
    [Test] procedure PascalCaseNumericConst_Reported;
    [Test] procedure UpperSnakeNumericConst_NotReported;
    [Test] procedure ShortConstName_NotReported;
    [Test] procedure StringConst_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNamingExt.ExceptionWithoutEPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkExceptionName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExceptionWithEPrefix_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type EMyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

procedure TTestNamingExt.NonExceptionClass_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyWorker = class end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

procedure TTestNamingExt.PascalCaseNumericConst_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MaxRetries = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.UpperSnakeNumericConst_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MAX_RETRIES = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.ShortConstName_NotReported;
// Sehr kurze Namen (<=2 Zeichen) sind Loop-Counter, kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  N = 10;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.StringConst_NotReported;
// Strings sind oft UI-Labels (PascalCase OK), kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MsgFileNotFound: string = ''File not found'';'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNamingExt);

end.
