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
    // Core-Audit 2026-07-18 (SCA126 Welle 1): '= nil' im Deklarations-Kontext
    // (Default-Parameter, typisierte Konstante) ist Initializer, kein Vergleich.
    [Test] procedure DefaultParamNil_NoFinding;
    [Test] procedure TypedConstNil_NoFinding;

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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison));
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

procedure TTestNilComparison.DefaultParamNil_NoFinding;
// Core-Audit 2026-07-18 (SCA126 Welle 1, 5%-FP-Konzept): '= nil' als
// Default-Parameterwert ist ein Initializer, KEIN Nil-Vergleich. Der Parser
// legt den Default in nkParam.TypeRef ab ('TObject = nil'); der Node-Kind-Guard
// (Skip nkParam) unterdrueckt den frueheren FP. Groesster Actionable-Hebel des
// Konzepts (~2162 FP im Real-World-Korpus).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const AObj: TObject = nil);'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison),
    'Default-Parameter = nil ist kein Nil-Vergleich');
  finally F.Free; end;
end;

procedure TTestNilComparison.TypedConstNil_NoFinding;
// Core-Audit 2026-07-18 (SCA126 Welle 1): typisierte Konstante '= nil' ist ein
// Initializer, kein Vergleich. Der Parser legt Const-Items als nkField mit
// TypeRef 'TObject=nil' ab; der Node-Kind-Guard (Skip nkField) unterdrueckt den FP.
const SRC =
  'unit t; implementation'#13#10 +
  'const DefObj: TObject = nil;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilComparison),
    'typisierte Konstante = nil ist kein Nil-Vergleich');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNilComparison);

end.
