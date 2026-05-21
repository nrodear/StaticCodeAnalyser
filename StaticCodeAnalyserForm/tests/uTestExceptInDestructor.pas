unit uTestExceptInDestructor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExceptInDestructor = class
  public
    [Test] procedure RaiseInDestructor_Reported;
    [Test] procedure RaiseInsideTryExcept_NotReported;
    [Test] procedure RaiseInRegularMethod_NotReported;
    [Test] procedure RaiseInClassDestructor_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExceptInDestructor.RaiseInDestructor_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''oops'');'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkExceptInDestructor) >= 1);
  finally F.Free; end;
end;

procedure TTestExceptInDestructor.RaiseInsideTryExcept_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    if Bad then raise EInvalidOp.Create(''oops'');'#13#10 +
  '  except'#13#10 +
  '    Log(''cleanup failed'');'#13#10 +
  '  end;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptInDestructor));
  finally F.Free; end;
end;

procedure TTestExceptInDestructor.RaiseInRegularMethod_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  if Bad then raise EInvalidOp.Create(''oops'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptInDestructor));
  finally F.Free; end;
end;

procedure TTestExceptInDestructor.RaiseInClassDestructor_NotReported;
// Class-Destruktoren haben anderes Risikoprofil - skip.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  raise EInvalidOp.Create(''oops'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptInDestructor));
  finally F.Free; end;
end;

procedure TTestExceptInDestructor.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  raise EInvalidOp.Create(''oops'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkExceptInDestructor then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkExceptInDestructor finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptInDestructor);

end.
