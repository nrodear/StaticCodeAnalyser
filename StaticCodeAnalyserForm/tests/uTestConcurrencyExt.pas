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
    // Type-Filter: nur feuern wenn Identifier-Typ nach TThread aussieht.
    [Test] procedure FreeAndNilObjectList_NotReported;
    [Test] procedure FreeAndNilStringList_NotReported;
    [Test] procedure FreeAndNilThreadTyped_Reported;
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

procedure TTestConcurrencyExt.FreeAndNilObjectList_NotReported;
// Spiegelt den realen FP aus uIDEWatchMode.FResults: FreeAndNil auf einer
// TObjectList ist KEIN TThread-Free und darf nicht flaggen.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FResults: TObjectList<Integer>;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FResults);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilStringList_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FLines: TStringList;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FLines);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilThreadTyped_Reported;
// Typname enthaelt 'Thread' -> Detector flaggt weiterhin (echter Treffer).
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FWorker: TMyWorkerThread;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConcurrencyExt);

end.
