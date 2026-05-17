unit uTestConcurrencyExt;

// Tests fuer TConcurrencyExtDetector (SCA113-114).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConcurrencyExt = class
  public
    // ThreadResumeDeprecated
    [Test] procedure Resume_Reported;
    [Test] procedure Start_NotReported;
    [Test] procedure ResumeAssignment_NotReported;

    // TThreadDestroyWithoutTerminate
    [Test] procedure FreeAndNilWithoutTerminate_Reported;
    [Test] procedure FreeAndNilWithTerminateAndWait_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConcurrencyExt.Resume_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyWorker.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkThreadResumeDeprecated) >= 1);
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.Start_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyWorker.Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.ResumeAssignment_NotReported;
// `OnResume := xxx` ist eine Property-Zuweisung - das `.Resume` ist
// kein Method-Call. Detector erkennt das per Negative-Lookahead `(?!=)`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyObj.Resume := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithoutTerminate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1);
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithTerminateAndWait_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FWorker.Terminate;'#13#10 +
  '  FWorker.WaitFor;'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConcurrencyExt);

end.
