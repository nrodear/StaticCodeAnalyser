unit uTestLeakInConstructor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLeakInConstructor = class
  public
    [Test] procedure FieldCreateThenRaise_Reported;
    [Test] procedure FieldCreateWithoutRaise_NoFinding;
    [Test] procedure RaiseWithoutFieldCreate_NoFinding;
    [Test] procedure ProtectedByTryExcept_NoFinding;
    [Test] procedure ClassConstructor_NoFinding;
    [Test] procedure ValidateThenAllocate_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLeakInConstructor.FieldCreateThenRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1);
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.FieldCreateWithoutRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.RaiseWithoutFieldCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ProtectedByTryExcept_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    if Bad then raise EInvalidOp.Create(''bad'');'#13#10 +
  '  except'#13#10 +
  '    FreeAndNil(FList);'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ClassConstructor_NoFinding;
// class constructor laeuft einmal pro Klasse, kein Instance-Init -
// LeakInConstructor-Pattern nicht anwendbar.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FStaticThing := TStringList.Create;'#13#10 +
  '  if Bad then raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ValidateThenAllocate_NoFinding;
// Regression LoggerPro.MemoryAppender/WebhookAppender:
//   begin
//     if N < 1 then raise Exception.Create('bad');
//     FList := TList.Create;   <- raise feuert vor jeder Allocation
//   end;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(N: Integer);'#13#10 +
  'begin'#13#10 +
  '  if N < 1 then raise Exception.Create(''bad'');'#13#10 +
  '  FList := TList.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor),
    'raise VOR der ersten Allocation = nichts zum leaken');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  raise EFoo.Create(''bad'');'#13#10 +
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
      if Fnd.Kind = fkLeakInConstructor then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkLeakInConstructor finding expected');
    Assert.AreEqual(fkLeakInConstructor, Hit.Kind);
    Assert.AreEqual(lsError,             Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLeakInConstructor);

end.
