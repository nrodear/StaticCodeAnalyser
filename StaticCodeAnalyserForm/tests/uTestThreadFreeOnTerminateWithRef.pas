unit uTestThreadFreeOnTerminateWithRef;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestThreadFreeOnTerminateWithRef = class
  public
    [Test] procedure AccessAfterFreeOnTerminate_Reported;
    [Test] procedure NoAccessAfterFreeOnTerminate_NotReported;
    [Test] procedure FreeOnTerminateFalse_NotReported;
    [Test] procedure ConfigBeforeStart_NotReported;
    [Test] procedure ResumeIsStart_NotReported;
    // --- Real-World-Audit 2026-07-31: Branch-Exklusivitaet ---
    [Test] procedure ThenElseExclusiveBranches_NotReported;
    [Test] procedure SameThenBranchWithElse_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestThreadFreeOnTerminateWithRef.AccessAfterFreeOnTerminate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var T: TMyThread;'#13#10 +
  'begin'#13#10 +
  '  T := TMyThread.Create(True);'#13#10 +
  '  T.FreeOnTerminate := True;'#13#10 +
  '  T.Start;'#13#10 +
  '  T.WaitFor;'#13#10 +     // gefaehrlich: Thread kann schon zerstoert sein
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef) >= 1,
      'WaitFor nach Start+FreeOnTerminate=True muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.ConfigBeforeStart_NotReported;
// FP-Fix (Real-World 2026-06-21): Config-Assignments ZWISCHEN
// FreeOnTerminate und Start sind sicher - der Thread laeuft noch nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var T: TMyThread;'#13#10 +
  'begin'#13#10 +
  '  T := TMyThread.Create(True);'#13#10 +
  '  T.FreeOnTerminate := True;'#13#10 +
  '  T.Priority := tpNormal;'#13#10 +
  '  T.OnTerminate := HandleDone;'#13#10 +
  '  T.Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef),
      'Config vor Start ist sicher - kein Finding');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.ResumeIsStart_NotReported;
// FP-Fix (Real-World 2026-06-21): Resume IST der (pre-XE2) Start-Call,
// kein gefaehrlicher Post-Mortem-Zugriff.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var T: TMyThread;'#13#10 +
  'begin'#13#10 +
  '  T := TMyThread.Create(True);'#13#10 +
  '  T.FreeOnTerminate := True;'#13#10 +
  '  T.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef),
      'Resume ist der Start - kein Finding');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.NoAccessAfterFreeOnTerminate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var T: TMyThread;'#13#10 +
  'begin'#13#10 +
  '  T := TMyThread.Create(True);'#13#10 +
  '  T.FreeOnTerminate := True;'#13#10 +
  '  T.Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef),
      'Letzter T-Zugriff Start vor FoT war OK, danach kein Access -> kein Finding');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.FreeOnTerminateFalse_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var T: TMyThread;'#13#10 +
  'begin'#13#10 +
  '  T := TMyThread.Create(True);'#13#10 +
  '  T.FreeOnTerminate := False;'#13#10 +
  '  T.Start;'#13#10 +
  '  T.WaitFor;'#13#10 +
  '  T.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef),
      'FreeOnTerminate := False ist sicheres Manual-Management');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.ThenElseExclusiveBranches_NotReported;
// FP-Fix (Real-World-Audit 2026-07-31, Indy IdSchedulerOfThreadDefault /
// IdSchedulerOfThreadPool): FreeOnTerminate := True steht im then-Zweig,
// die geflaggten Zugriffe (WaitFor/Free) im else-Zweig DESSELBEN if - die
// Pfade schliessen sich aus, es gibt keinen Zugriff nach dem Ownership-
// Transfer. Ohne das Gate meldet der Detektor hier 2 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(T: TMyThread);'#13#10 +
  'begin'#13#10 +
  '  if IsCurrentThread(T) then'#13#10 +
  '  begin'#13#10 +
  '    T.FreeOnTerminate := True;'#13#10 +
  '  end'#13#10 +
  '  else'#13#10 +
  '  begin'#13#10 +
  '    T.Resume;'#13#10 +
  '    T.WaitFor;'#13#10 +
  '    T.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef),
      'then/else schliessen sich aus - kein Finding');
  finally F.Free; end;
end;

procedure TTestThreadFreeOnTerminateWithRef.SameThenBranchWithElse_StillReported;
// TP-Gegenprobe zum Branch-Exklusivitaets-Gate: FreeOnTerminate UND Zugriff
// liegen im GLEICHEN then-Zweig (das if hat trotzdem einen else-Zweig) -
// der Zugriff nach dem Start bleibt gefaehrlich und muss gemeldet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(T: TMyThread; Flag: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if Flag then'#13#10 +
  '  begin'#13#10 +
  '    T.FreeOnTerminate := True;'#13#10 +
  '    T.Start;'#13#10 +
  '    T.WaitFor;'#13#10 +
  '  end'#13#10 +
  '  else'#13#10 +
  '    DoSomethingElse;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkThreadFreeOnTerminateWithRef) >= 1,
      'Zugriff im SELBEN Zweig wie FreeOnTerminate bleibt ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestThreadFreeOnTerminateWithRef);

end.
