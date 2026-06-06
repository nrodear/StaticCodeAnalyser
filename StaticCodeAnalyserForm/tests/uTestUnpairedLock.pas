unit uTestUnpairedLock;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnpairedLock = class
  public
    [Test] procedure LockWithoutTryFinally_Reported;
    [Test] procedure EnterCriticalSectionWithoutTry_Reported;
    [Test] procedure LockInTryFinally_NotReported;
    [Test] procedure LockWithoutMatchingUnlock_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnpairedLock.LockWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FLocker.UnLock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

procedure TTestUnpairedLock.EnterCriticalSectionWithoutTry_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  EnterCriticalSection(FCS);'#13#10 +
  '  DoStuff;'#13#10 +
  '  LeaveCriticalSection(FCS);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LockInTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  finally'#13#10 +
  '    FLocker.UnLock;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LockWithoutMatchingUnlock_NotReported;
// Wenn KEIN unlock im Lookahead-Fenster ist, skipt der Detector
// (koennte ein anderer Pattern sein, z.B. Lock-Helper).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  // viele Zeilen Code ohne unlock...'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

procedure TTestUnpairedLock.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FLocker.UnLock;'#13#10 +
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
      if Fnd.Kind = fkUnpairedLock then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnpairedLock finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnpairedLock);

end.
