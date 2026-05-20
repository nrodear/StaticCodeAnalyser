unit uTestRoutineResultAssigned;

// Tests fuer den TRoutineResultAssignedDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRoutineResultAssigned = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure FunctionWithoutResult_Reported;
    [Test] procedure FunctionWithUnrelatedAssign_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure FunctionWithResult_NoFinding;
    [Test] procedure FunctionWithFunctionNameAssign_NoFinding;
    [Test] procedure FunctionWithExit_NoFinding;
    [Test] procedure FunctionWithRaise_NoFinding;
    [Test] procedure Procedure_NoFinding;
    [Test] procedure AbstractFunction_NoFinding;
    [Test] procedure ForwardFunction_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRoutineResultAssigned.FunctionWithoutResult_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithUnrelatedAssign_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Result := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithFunctionNameAssign_NoFinding;
// Pascal-Stil: `<funcname> := value` ist auch valide.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Foo := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithExit_NoFinding;
// Exit(value) wird vom Parser als nkExit gespeichert (Argument verworfen).
// Konservativ: jedes Exit deaktiviert das Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(x: Integer): Integer;'#13#10 +
  'begin if x > 0 then Exit(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithRaise_NoFinding;
// Function die immer wirft braucht kein Result.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin raise Exception.Create(''not implemented''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.Procedure_NoFinding;
// Procedure hat keinen Return-Type -> nicht relevant.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.AbstractFunction_NoFinding;
// `function ...; virtual; abstract;` hat keinen Body.
const SRC =
  'unit t; interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  function Bar: Integer; virtual; abstract;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ForwardFunction_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer; forward;'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Result := 1; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkRoutineResultUnassigned then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkRoutineResultUnassigned finding expected');
    Assert.AreEqual(fkRoutineResultUnassigned, Hit.Kind);
    Assert.AreEqual(lsError,                   Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRoutineResultAssigned);

end.
