unit uTestLockWithoutTryFinally;

// Tests fuer den TLockWithoutTryFinallyDetector (SCA109).
// Lock-Acquire (Enter/Acquire/BeginWrite/EnterCriticalSection) ohne
// umschliessendes try..finally mit matchendem Release.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLockWithoutTryFinally = class
  public
    [Test] procedure EnterWithoutTryFinally_Reported;
    [Test] procedure EnterWithTryFinally_NotReported;
    [Test] procedure AcquireWithoutTryFinally_Reported;
    [Test] procedure BeginWriteWithoutTryFinally_Reported;
    [Test] procedure EnterCriticalSection_WinAPI_Reported;
    [Test] procedure EnterInString_NotReported;
    [Test] procedure EnterInComment_NotReported;
    [Test] procedure LockWithoutTryFinally_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLockWithoutTryFinally.EnterWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  FLock.Enter;'#13#10 +
  '  DoWork;'#13#10 +
  '  FLock.Leave;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterWithTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  FLock.Enter;'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  finally'#13#10 +
  '    FLock.Leave;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally));
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.AcquireWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoWork;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.BeginWriteWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  FRWLock.BeginWrite;'#13#10 +
  '  DoWriteWork;'#13#10 +
  '  FRWLock.EndWrite;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterCriticalSection_WinAPI_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  EnterCriticalSection(FCS);'#13#10 +
  '  DoWork;'#13#10 +
  '  LeaveCriticalSection(FCS);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterInString_NotReported;
// .Enter in einem Stringliteral darf nicht triggern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure LogIt;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''FLock.Enter; DoWork; FLock.Leave;'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally));
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterInComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // FLock.Enter; DoWork; FLock.Leave;'#13#10 +
  '  DoSomethingElse;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally));
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.LockWithoutTryFinally_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  FLock.Enter;'#13#10 +
  '  DoWork;'#13#10 +
  '  FLock.Leave;'#13#10 +
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
      if Fnd.Kind = fkLockWithoutTryFinally then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkLockWithoutTryFinally finding expected');
    Assert.AreEqual(lsError, Hit.Severity,
      'Lock-Leak-Pattern muss als Error emittieren (Deadlock-Risiko)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLockWithoutTryFinally);

end.
