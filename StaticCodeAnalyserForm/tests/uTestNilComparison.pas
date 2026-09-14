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
    // Posten 263: der Operator darf auch rechts vom nil stehen
    [Test] procedure YodaEqualsNil_Reported;
    [Test] procedure YodaNotEqualsNil_Reported;
    [Test] procedure YodaInParens_Reported;
    [Test] procedure YodaLessEqual_NoFinding;
    // Posten 182: die dokumentierten Skip-Pfade links vom nil
    [Test] procedure LessEqualNil_NoFinding;
    [Test] procedure GreaterEqualNil_NoFinding;
    [Test] procedure EqualsNil_Kontrolle_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 263: die Yoda-Form -------------------------------- }
//
// Die Operator-Suche walkte von der Fundstelle des nil nur nach
// LINKS. Steht der Operator RECHTS - `nil = x` -, findet ihn der
// Rueck-Walk nie: die Form war komplett stumm. Der Kopfkommentar
// beschreibt das Verfahren als "'= nil' oder '<> nil'" und nennt die
// Yoda-Form nicht, es war also eine unbemerkte Luecke und keine
// dokumentierte Grenze; der Sonar-Pendant meldet beide Reihenfolgen.
//
// Alle Erwartungen an der gebauten Exe gemessen: die ersten drei
// Fixturen liefern heute 0 Funde und sind damit rot.

procedure TTestNilComparison.YodaEqualsNil_Reported;
// Heute 0 Funde, nach dem Fix 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x, y: TObject);'#13#10 +
  'begin if nil = x then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNilComparison),
      'nil = x ist derselbe Vergleich wie x = nil');
  finally F.Free; end;
end;

procedure TTestNilComparison.YodaNotEqualsNil_Reported;
// Dasselbe fuer den Ungleich-Operator.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x, y: TObject);'#13#10 +
  'begin if nil <> x then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNilComparison),
      'nil <> x ist derselbe Vergleich wie x <> nil');
  finally F.Free; end;
end;

procedure TTestNilComparison.YodaInParens_Reported;
// Zwei Yoda-Vergleiche in EINER Bedingung. Gemeldet wird ein Fund
// je KNOTEN, nicht je Vorkommen - genau so liegt der Korpusfall
// (doublecmd argon2.pas:897).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x, y: TObject);'#13#10 +
  'begin if (nil = x) or (nil = y) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNilComparison),
      'ein Fund je if-Knoten, auch bei zwei Yoda-Vergleichen');
  finally F.Free; end;
end;

procedure TTestNilComparison.YodaLessEqual_NoFinding;
// WAECHTER fuer den neuen Rechts-Scan: `<=` darf nicht als `<>`
// gelesen werden. Die Pruefung verlangt '<' UND '>' - dieselbe
// Politik wie beim Links-Scan. Vor wie nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x, y: TObject);'#13#10 +
  'begin if nil <= x then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNilComparison),
      'ein <= rechts vom nil ist kein Ungleich-Vergleich');
  finally F.Free; end;
end;


{ --- Posten 182: die Skip-Pfade LINKS vom nil -------------------- }
//
// Der Kopf dokumentiert, dass ':= nil', '<= nil' und '>= nil'
// ausgesondert werden. Getestet war davon nichts. Die Yoda-Haelfte des
// Postens ist mit Charge 2 erledigt (samt Waechter fuer die RECHTE
// Seite) - hier fehlt die LINKE.
//
// Beide am gebauten Stand gemessen: 0. Die Positiv-Kontrolle daneben
// liefert 1 und schliesst aus, dass ein anderes Gate die Fixturen
// stumm stellt.

procedure TTestNilComparison.LessEqualNil_NoFinding;
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x <= nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNilComparison),
      'ein <= nil ist kein Assigned-Vergleich');
  finally F.Free; end;
end;

procedure TTestNilComparison.GreaterEqualNil_NoFinding;
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x >= nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNilComparison),
      'ein >= nil ist kein Assigned-Vergleich');
  finally F.Free; end;
end;

procedure TTestNilComparison.EqualsNil_Kontrolle_Reported;
// POSITIV-KONTROLLE zu den beiden darueber. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: TObject);'#13#10 +
  'begin if x = nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNilComparison),
      '= nil bleibt der Fund');
  finally F.Free; end;
end;


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
