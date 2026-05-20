unit uTestNilComparison;

// Tests fuer den TNilComparisonDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNilComparison = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure EqualsNil_Reported;
    [Test] procedure NotEqualsNil_Reported;
    [Test] procedure InIfCondition_Reported;
    [Test] procedure InWhileCondition_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure AssignedCall_NoFinding;
    [Test] procedure AssignmentToNil_NoFinding;
    [Test] procedure NilInsideStringLiteral_NoFinding;
    [Test] procedure NilSuffixIdentifier_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNilComparison.EqualsNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x = nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.NotEqualsNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x <> nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.InIfCondition_Reported;
// Complex condition: nil-Compare als Teil einer groesseren Expression.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x, y: TObject);'#13#10 +
  'begin if (x <> nil) and (y <> nil) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilComparison) >= 1);
  finally F.Free; end;
end;

procedure TTestNilComparison.InWhileCondition_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin while x <> nil do x := x.Next; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.AssignedCall_NoFinding;
// Korrekter Pattern - kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if Assigned(x) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.AssignmentToNil_NoFinding;
// `x := nil` ist eine Zuweisung, kein Vergleich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin x := nil; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.NilInsideStringLiteral_NoFinding;
// 'nil' in einem String-Literal soll nicht matchen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin s := ''= nil''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.NilSuffixIdentifier_NoFinding;
// 'NilFoo' / 'foonil' sind keine nil-Compare-Patterns.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var nilable: Boolean;'#13#10 +
  'begin if nilable then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilComparison));
  finally F.Free; end;
end;

procedure TTestNilComparison.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x = nil then DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkNilComparison then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkNilComparison finding expected');
    Assert.AreEqual(fkNilComparison, Hit.Kind);
    Assert.AreEqual(lsHint,          Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNilComparison);

end.
