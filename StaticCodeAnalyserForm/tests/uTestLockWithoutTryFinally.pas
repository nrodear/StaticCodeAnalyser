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
    [Test] procedure LockWrapperMethod_NotReported;
    [Test] procedure EnterLocalLog_NotReported;
    [Test] procedure AcquireWithoutTryFinally_Reported;
    [Test] procedure BeginWriteWithoutTryFinally_Reported;
    [Test] procedure EnterCriticalSection_WinAPI_Reported;
    [Test] procedure EnterInString_NotReported;
    [Test] procedure EnterInComment_NotReported;
    [Test] procedure LockWithoutTryFinally_KindAndSeverity;
    // Real-World 2026-06-26 FP-Klassen:
    // CEF4Delphi-Idiom 'try / if (X<>nil) then / begin / X.Acquire' (Cause A)
    // und '.Enter' als boolescher Ausdruck (ICefv8Context, Cause C).
    [Test] procedure TryGuardBeginAcquire_NotReported;
    [Test] procedure EnterAsBooleanExpression_NotReported;
    // Gegenkontrolle: 'begin' einer Schleife (ohne try) darf NICHT suppressen.
    [Test] procedure LoopBeginNoTry_Reported;
    // Real-World 2026-06-28: exception-freier Getter/Setter (nur Zuweisung
    // zwischen Enter/Leave) braucht kein try/finally.
    [Test] procedure ExceptionFreeGetter_NotReported;
    [Test] procedure CallBetweenEnterLeave_StillReported;
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLockWithoutTryFinally),
      'genau 1 Lock-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FLock.Enter'),
      TFindingHelper.FirstOf(F, fkLockWithoutTryFinally).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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

procedure TTestLockWithoutTryFinally.LockWrapperMethod_NotReported;
// Regression mORMot TOSLock.Lock (35+ FPs auf einen Schlag):
// Wrapper-Method die nur das Enter delegiert - try/finally landet
// beim Caller.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TOSLock.Lock;'#13#10 +
  'begin'#13#10 +
  '  FCS.Enter;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally),
    'Lock-Wrapper-Methode (Enter ist letzte Anweisung) darf kein Finding werfen');
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterLocalLog_NotReported;
// Regression mORMot fLog.EnterLocal(log, ...) - 40+ FPs:
// EnterLocal/EnterMethod sind keine Critical-Section-Enter sondern
// Logging-Scope-Helper. Regex muss '\b' nach Enter haben um nicht
// 'EnterLocal' faelschlich zu matchen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'var log: ISynLog;'#13#10 +
  'begin'#13#10 +
  '  fLog.EnterLocal(log, ''Destroy'', [], self);'#13#10 +
  '  DoWork;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally),
    'EnterLocal ist kein Critical-Section-Enter');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLockWithoutTryFinally),
      'genau 1 Lock-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FCS.Acquire'),
      TFindingHelper.FirstOf(F, fkLockWithoutTryFinally).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLockWithoutTryFinally),
      'genau 1 Lock-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FRWLock.BeginWrite'),
      TFindingHelper.FirstOf(F, fkLockWithoutTryFinally).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLockWithoutTryFinally),
      'genau 1 Lock-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'EnterCriticalSection(FCS'),
      TFindingHelper.FirstOf(F, fkLockWithoutTryFinally).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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

procedure TTestLockWithoutTryFinally.TryGuardBeginAcquire_NotReported;
// CEF4Delphi-Idiom (ueber alle Demos wiederholt): das umschliessende try
// liegt hinter 'if (X<>nil) then begin', Release im finally. Darf NICHT
// flaggen - NearestBoundaryIsTry erkennt das umschliessende try.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.DoResize;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    if (FResizeCS <> nil) then'#13#10 +
  '      begin'#13#10 +
  '        FResizeCS.Acquire;'#13#10 +
  '        DoWork;'#13#10 +
  '      end;'#13#10 +
  '  finally'#13#10 +
  '    if (FResizeCS <> nil) then'#13#10 +
  '      FResizeCS.Release;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally),
    'try/if-guard/begin/Acquire mit Release im finally ist sicher');
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.EnterAsBooleanExpression_NotReported;
// ICefv8Context.Enter: Boolean - '.Enter' als Bedingung, kein Lock.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Eval;'#13#10 +
  'begin'#13#10 +
  '  if pV8Context.Enter then'#13#10 +
  '    pV8Context.Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally),
    '.Enter als boolescher Ausdruck ist kein Lock-Acquire');
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.LoopBeginNoTry_Reported;
// Gegenkontrolle: ein 'begin' (Schleifen-Body) ohne umschliessendes try
// darf den Befund NICHT unterdruecken - sonst waere NearestBoundaryIsTry
// zu breit.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Process;'#13#10 +
  'begin'#13#10 +
  '  while Cond do'#13#10 +
  '    begin'#13#10 +
  '      FLock.Enter;'#13#10 +
  '      DoWork;'#13#10 +
  '      FLock.Leave;'#13#10 +
  '    end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1,
    'Lock im Schleifen-Body ohne try muss weiterhin feuern');
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

procedure TTestLockWithoutTryFinally.ExceptionFreeGetter_NotReported;
// FP-Fix (Real-World 2026-06-28): zwischen Enter und Leave stehen nur reine
// Zuweisungen (Result := FField) - kein Call/Index/raise -> kann nicht werfen
// -> Lock kann nicht haengen -> kein try/finally noetig.
const SRC =
  'unit t; implementation'#13#10 +
  'function TFoo.GetValue: Integer;'#13#10 +
  'begin'#13#10 +
  '  FLock.Enter;'#13#10 +
  '  Result := FValue;'#13#10 +
  '  FLock.Leave;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLockWithoutTryFinally),
    'exception-freier Getter (nur Zuweisung) braucht kein try/finally');
  finally F.Free; end;
end;

procedure TTestLockWithoutTryFinally.CallBetweenEnterLeave_StillReported;
// TP-Gegenkontrolle: sobald zwischen Enter und Leave ein CALL steht (kann
// werfen), bleibt der Befund - auch ein paren-loser Call ('DoWork;').
const SRC =
  'unit t; implementation'#13#10 +
  'function TFoo.GetValue: Integer;'#13#10 +
  'begin'#13#10 +
  '  FLock.Enter;'#13#10 +
  '  Result := Compute(FValue);'#13#10 +
  '  FLock.Leave;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLockWithoutTryFinally) >= 1,
    'Call zwischen Enter/Leave kann werfen - bleibt ein Finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLockWithoutTryFinally);

end.
