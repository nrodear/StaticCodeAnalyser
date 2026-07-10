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
    [Test] procedure TryEnclosesLock_NoFinding;
    [Test] procedure BareLockNoTry_StillReported;
    // Real-World FP-Audit 2026-07-10: 'declaration-not-call' (15/19 FP)
    [Test] procedure LockMethodDeclaration_NotReported;
    [Test] procedure InterfaceForwardDecl_NotReported;
    [Test] procedure AcquireFunctionDeclaration_NotReported;
    [Test] procedure MethodNamedLockWithRealAcquire_StillReported;
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

// FP-Guard (2026-06-29): das try/finally UMSCHLIESST den Lock - `try` steht VOR
// dem Acquire und ist noch offen (kein finally/except/end dazwischen). Der Lock
// liegt im try-Body -> Exception leakt ihn nicht -> kein bare-Lock.
procedure TTestUnpairedLock.TryEnclosesLock_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS := TCriticalSection.Create;'#13#10 +
  '  try'#13#10 +
  '    FCS.Acquire;'#13#10 +
  '    DoStuff;'#13#10 +
  '  finally'#13#10 +
  '    FCS.Release;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

// Kein try ueberhaupt: Acquire ... Release ohne Schutz -> Finding bleibt.
procedure TTestUnpairedLock.BareLockNoTry_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

// ============================================================
// Real-World FP-Audit 2026-07-10: 'declaration-not-call'
// 'procedure Lock;' / 'function Acquire(...)' / Interface-Forward-Decls
// matchen den Regex, sind aber Methodennamen, keine Acquire-Aufrufe.
// ============================================================

procedure TTestUnpairedLock.LockMethodDeclaration_NotReported;
// 'procedure Lock;' gefolgt von 'procedure UnLock;' in der Klassen-Decl sah
// wie ein bare-Lock aus (Lookahead fand 'unlock' im UnLock-Header).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Lock;'#13#10 +
  '    procedure UnLock;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'procedure Lock; ist eine Deklaration, kein Acquire-Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.InterfaceForwardDecl_NotReported;
// Interface-Section-Forward-Decls von EnterCriticalSection/LeaveCriticalSection.
const SRC =
  'unit t; interface'#13#10 +
  'procedure EnterCriticalSection(var cs: TRTLCriticalSection); stdcall;'#13#10 +
  'procedure LeaveCriticalSection(var cs: TRTLCriticalSection); stdcall;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'EnterCriticalSection(...) Forward-Decl ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.AcquireFunctionDeclaration_NotReported;
// 'function Acquire(...): Boolean;' Method-Decl, gefolgt von 'procedure Release;'.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TConn = class'#13#10 +
  '  public'#13#10 +
  '    function Acquire(Op: TObject): Boolean;'#13#10 +
  '    procedure Release;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'function Acquire(...) Deklaration ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.MethodNamedLockWithRealAcquire_StillReported;
// Gegenprobe: der Impl-Header 'procedure TFoo.Lock;' wird uebersprungen, ein
// ECHTER bare-Acquire im Rumpf bleibt aber ein Fund (kein Over-Suppress).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Lock;'#13#10 +
  'begin'#13#10 +
  '  FInner.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FInner.UnLock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1,
    'echter bare FInner.Lock im Rumpf bleibt SCA153');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnpairedLock);

end.
