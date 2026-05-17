unit uTestSynchronizeInDestructor;

// Tests fuer den TSynchronizeInDestructorDetector (SCA108).
// Klassischer Threading-Deadlock: TThread.Synchronize-Aufruf im
// destructor Destroy.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSynchronizeInDestructor = class
  public
    [Test] procedure SynchronizeInDestructor_Reported;
    [Test] procedure SynchronizeOutsideDestructor_NotReported;
    [Test] procedure DestructorWithoutSynchronize_NotReported;
    [Test] procedure QualifiedSynchronize_AlsoReported;
    [Test] procedure SynchronizeInDestructor_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSynchronizeInDestructor.SynchronizeInDestructor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWorker = class'#13#10 +
  '  destructor Destroy; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'destructor TWorker.Destroy;'#13#10 +
  'begin'#13#10 +
  '  Synchronize(LogDone);'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSynchronizeInDestructor) >= 1);
  finally F.Free; end;
end;

procedure TTestSynchronizeInDestructor.SynchronizeOutsideDestructor_NotReported;
// Synchronize-Aufruf in einer normalen Methode -> kein Deadlock-Pattern,
// kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWorker = class'#13#10 +
  '  procedure NotifyUI;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWorker.NotifyUI;'#13#10 +
  'begin'#13#10 +
  '  Synchronize(LogDone);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSynchronizeInDestructor));
  finally F.Free; end;
end;

procedure TTestSynchronizeInDestructor.DestructorWithoutSynchronize_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWorker = class'#13#10 +
  '  destructor Destroy; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'destructor TWorker.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FQueue);'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSynchronizeInDestructor));
  finally F.Free; end;
end;

procedure TTestSynchronizeInDestructor.QualifiedSynchronize_AlsoReported;
// TThread.Synchronize statt bare Synchronize -> auch ein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWorker = class'#13#10 +
  '  destructor Destroy; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'destructor TWorker.Destroy;'#13#10 +
  'begin'#13#10 +
  '  TThread.Synchronize(nil, LogDone);'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSynchronizeInDestructor) >= 1);
  finally F.Free; end;
end;

procedure TTestSynchronizeInDestructor.SynchronizeInDestructor_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWorker = class'#13#10 +
  '  destructor Destroy; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'destructor TWorker.Destroy;'#13#10 +
  'begin'#13#10 +
  '  Synchronize(LogDone);'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSynchronizeInDestructor then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkSynchronizeInDestructor finding expected');
    Assert.AreEqual(lsError, Hit.Severity,
      'Concurrency-Deadlock muss als Error (nicht Hint/Warning) emittieren');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSynchronizeInDestructor);

end.
