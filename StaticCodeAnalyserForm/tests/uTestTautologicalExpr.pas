unit uTestTautologicalExpr;

// Tests fuer den TTautologicalExprDetector (file-scan).
//
// Pattern: `<expr> <op> <expr>` mit identischer LHS und RHS, fuer
// Boolean-/Vergleichs-/Identity-Operatoren. Mathematische Operatoren
// werden ausgeschlossen (x + x ist legitim).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTautologicalExpr = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure Equal_SameIdent_Reported;
    [Test] procedure NotEqual_SameIdent_Reported;
    [Test] procedure AndOp_SameIdent_Reported;
    [Test] procedure OrOp_SameIdent_Reported;

    // ---- Negative ---------------------------------------------------------
    [Test] procedure DifferentOperands_NoFinding;
    [Test] procedure PlusOp_SameIdent_NoFinding;
    [Test] procedure InString_NotDetected;
    [Test] procedure InComment_NotDetected;
    [Test] procedure TwoCallsWithDifferentStringArgs_NoFinding;
    [Test] procedure TwoCallsWithIdenticalStringArgs_Reported;
    [Test] procedure CaseSensitiveCharLiterals_NoFinding;
    [Test] procedure CaseSensitiveStringLiterals_NoFinding;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Taut_Finding_KindAndSeverity;
    [Test] procedure Taut_MultipleHitsInSameUnit_AllReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTautologicalExpr.Equal_SameIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = x then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 1);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.NotEqual_SameIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x <> x then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 1);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.AndOp_SameIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: Boolean;'#13#10 +
  'begin'#13#10 +
  '  if a and a then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 1);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.OrOp_SameIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var b: Boolean;'#13#10 +
  'begin'#13#10 +
  '  if b or b then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 1);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.DifferentOperands_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = y then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.PlusOp_SameIdent_NoFinding;
// `x + x` ist legitim (Verdoppelung); Plus-Operator wird vom Detector
// nicht beachtet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := x + x;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.InString_NotDetected;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := ''if x = x then nichts'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.InComment_NotDetected;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // if x = x then nichts'#13#10 +
  '  Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.TwoCallsWithDifferentStringArgs_NoFinding;
// Regression: Vor dem Fix wurden String-Literale im Strip-Pass komplett
// durch Blanks ersetzt - dadurch sahen `Foo('a')` und `Foo('b')`
// identisch aus und der Detektor meldete einen Fehlalarm. Jetzt werden
// die finalen Lhs/Rhs aus Line gezogen, der String-Inhalt bleibt im
// Norm()-Vergleich erhalten.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Lower.StartsWith(''function '') or Lower.StartsWith(''function('') then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.TwoCallsWithIdenticalStringArgs_Reported;
// Gegenstueck: wenn beide Strings WIRKLICH gleich sind, ist die
// Expression echt tautologisch - das muss weiterhin feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Lower.StartsWith(''a'') and Lower.StartsWith(''a'') then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 1);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.CaseSensitiveCharLiterals_NoFinding;
// Spiegelt den realen FP aus uFieldName.pas: idiomatic case-insensitive
// char-check, beide Literale unterscheiden sich nur im Case. Frueher hat
// Norm() alles lowercased - inklusive String-Literal-Inhalt - und damit
// 'F' und 'f' falsch als identisch behandelt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(FirstChar: Char);'#13#10 +
  'begin'#13#10 +
  '  if (FirstChar = ''F'') or (FirstChar = ''f'') then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.CaseSensitiveStringLiterals_NoFinding;
// Gleicher Bug, aber mit mehrzeichigem String-Literal.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin'#13#10 +
  '  if (s = ''Yes'') or (s = ''YES'') then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTautologicalBoolExpr));
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.Taut_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = x then Bar;'#13#10 +
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
      if Fnd.Kind = fkTautologicalBoolExpr then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkTautologicalBoolExpr finding expected');
    Assert.AreEqual(fkTautologicalBoolExpr, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestTautologicalExpr.Taut_MultipleHitsInSameUnit_AllReported;
// Zwei tautologische Expressions in verschiedenen Zeilen -> 2 Findings.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer; b: Boolean;'#13#10 +
  'begin'#13#10 +
  '  if x = x then Bar;'#13#10 +
  '  if b and b then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTautologicalBoolExpr) >= 2);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTautologicalExpr);

end.
