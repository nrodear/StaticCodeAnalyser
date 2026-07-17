unit uTestSelfAssignment;

// Tests fuer den TSelfAssignmentDetector (AST-basiert).
// Whitespace-/Case-toleranter Vergleich von LHS und RHS.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSelfAssignment = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure Self_SimpleIdent_Reported;
    [Test] procedure Self_DottedFieldAccess_Reported;
    [Test] procedure Self_WhitespaceDifference_StillReported;
    [Test] procedure Self_CaseDifference_StillReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure NoSelf_DifferentVar_NoFinding;
    [Test] procedure NoSelf_ExpressionWithSameVar_NoFinding;
    [Test] procedure NoSelf_DifferentFieldOnSameObject_NoFinding;
    [Test] procedure NoSelf_AssignFromCall_NoFinding;
    // Core-Audit 2026-07-17 (SCA047): Keyword-Operator-RHS an Wortgrenze
    // ('not Ready') darf nicht mit gleichnamiger LHS ('NotReady') kollabieren.
    [Test] procedure NoSelf_KeywordOperatorRHS_NoFinding;
    [Test] procedure Self_MultipleHits_AllReported;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Self_Finding_KindAndSeverity;
    [Test] procedure Self_ThreeLevelDottedAccess_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSelfAssignment.Self_SimpleIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := x; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_DottedFieldAccess_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.Field := Obj.Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_WhitespaceDifference_StillReported;
// `Obj.Field := Obj . Field` (mit Spaces) wird zu identischem Normalized
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.Field := Obj . Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_CaseDifference_StillReported;
// Pascal ist case-insensitiv -> X = x
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin X := x; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.NoSelf_DifferentVar_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Integer;'#13#10 +
  'begin x := y; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.NoSelf_ExpressionWithSameVar_NoFinding;
// x := x + 1  - kein No-Op
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := x + 1; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.NoSelf_DifferentFieldOnSameObject_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.A := Obj.B; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.NoSelf_KeywordOperatorRHS_NoFinding;
// Regression Core-Audit 2026-07-17: 'NotReady := not Ready;' ist KEINE
// Selbstzuweisung. Der Parser legt den RHS via JoinTokInto als 'not Ready'
// (mit Wortgrenzen-Space) ab. Vor dem Fix kollabierte Normalize das zu
// 'notready' und verglich es mit der LHS 'NotReady'->'notready' -> falscher
// Treffer. Normalize erhaelt jetzt die Wortgrenze -> 'not ready' <> 'notready'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var NotReady, Ready: Boolean;'#13#10 +
  'begin NotReady := not Ready; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'Keyword-Operator an Wortgrenze darf nicht als Selbstzuweisung kollabieren');
  finally F.Free; end;
end;

procedure TTestSelfAssignment.NoSelf_AssignFromCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := GetX(); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_MultipleHits_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y, z: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := x;'#13#10 +
  '  y := y;'#13#10 +
  '  z := z;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := x; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSelfAssignment then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkSelfAssignment finding expected');
    Assert.AreEqual(fkSelfAssignment, Hit.Kind);
    Assert.AreEqual(lsWarning,        Hit.Severity);
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_ThreeLevelDottedAccess_StillReported;
// Drei-Ebenen-Zugriff: Obj.Sub.Field := Obj.Sub.Field
// Normalize muss die ganze Kette als identisch erkennen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.Sub.Field := Obj.Sub.Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelfAssignment);

end.
