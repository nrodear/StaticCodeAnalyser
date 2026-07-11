unit uTestFloatEquality;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFloatEquality = class
  public
    [Test] procedure DoubleEquality_Reported;
    [Test] procedure DoubleInequality_Reported;
    [Test] procedure IntegerEquality_NotReported;
    [Test] procedure Assignment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    [Test] procedure StringEqualityWithFloatVarNameElsewhere_NotReported;
    // FP-Regression: nil/true/false als Operand sind nie Float - der
    // Scope-blinde FloatVars-Lookup darf nicht mit Pointer-/Boolean-
    // Vergleichen kollidieren (Real-World: MVCFramework.Nullables.pas
    // 'if Value = nil' wo Value sowohl als Pointer als auch als Float-
    // Feld irgendwo im File auftaucht).
    [Test] procedure NilCompareWithFloatVarNameElsewhere_NotReported;
    [Test] procedure BooleanCompareWithFloatVarNameElsewhere_NotReported;
    // FP-Regression (Praezisions-Guard 2026-06-29): ein echter Float-Equality-
    // Bug braucht den ANDEREN Operanden ebenfalls float-kompatibel. Ein Float-
    // Var-Vergleich gegen einen gewoehnlichen Nicht-Float-Identifier (Boolean-
    // Feld o.ae., nur NAMENSGLEICH) ist Scope-Blindheit -> kein Treffer.
    [Test] procedure FloatVarVsNonFloatIdent_NoFinding;
    // Gegenprobe: Float-Var gegen numerisches Literal bleibt ein Treffer.
    [Test] procedure FloatVarVsLiteral_StillReported;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure IntegerLocalWithFloatNameElsewhere_NotReported;
    [Test] procedure FloatVarWithIntNameElsewhere_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFloatEquality.DoubleEquality_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Ratio: Double;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1);
  finally F.Free; end;
end;

procedure TTestFloatEquality.DoubleInequality_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Single;'#13#10 +
  'begin'#13#10 +
  '  if X <> 0.0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1);
  finally F.Free; end;
end;

procedure TTestFloatEquality.IntegerEquality_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var N: Integer;'#13#10 +
  'begin'#13#10 +
  '  if N = 5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality));
  finally F.Free; end;
end;

procedure TTestFloatEquality.Assignment_NotReported;
// `x := 0.5` darf NICHT als `x = 0.5`-Comparison erkannt werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Double;'#13#10 +
  'begin'#13#10 +
  '  X := 0.5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality));
  finally F.Free; end;
end;

procedure TTestFloatEquality.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var R: Double;'#13#10 +
  'begin'#13#10 +
  '  if R = 1.0 then Exit;'#13#10 +
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
      if Fnd.Kind = fkFloatEquality then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFloatEquality finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestFloatEquality.StringEqualityWithFloatVarNameElsewhere_NotReported;
// Regression: `aValue = ''` mit String-Var darf NICHT als Float-Equality
// kassiert werden, auch wenn an anderer Stelle im File `aValue: Double`
// als Param vorkommt (file-weite FloatVars).
// Frueher: String-Strip ersetzte '' durch Leerzeichen -> die Regex bridge
// uebersprang das und kassierte das naechste Token (Keyword `then`) als RHS.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(aValue: Double): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := aValue = 0.0;'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'var aValue: string;'#13#10 +
  'begin'#13#10 +
  '  if aValue = '''' then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : Integer;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    // Foo's Float-Vergleich bleibt erlaubt; Bar's String-Vergleich darf
    // KEINEN Treffer mehr produzieren.
    Hit := 0;
    for Fnd in F do
      if (Fnd.Kind = fkFloatEquality)
         and (Pos('then', Fnd.MissingVar) > 0) then
        Inc(Hit);
    Assert.AreEqual<Integer>(0, Hit, 'String-Compare gegen Keyword darf nicht ' +
      'als Float-Equality kassiert werden');
  finally F.Free; end;
end;

procedure TTestFloatEquality.NilCompareWithFloatVarNameElsewhere_NotReported;
// FP-Regression aus Real-World (MVCFramework.Nullables.pas Z.1849):
//   NullableSingle = record Value: Single; end;  -> FloatVars hat 'value'
//   class operator Implicit(const Value: Pointer): ...;
//   begin if Value = nil then ...  // <- Pointer-Compare, kein Float
const SRC =
  'unit t; implementation'#13#10 +
  'type NullableSingle = record Value: Single; end;'#13#10 +
  'procedure Foo(const Value: Pointer);'#13#10 +
  'begin'#13#10 +
  '  if Value = nil then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Pointer = nil darf nicht als Float-Equality kassiert werden');
  finally F.Free; end;
end;

procedure TTestFloatEquality.BooleanCompareWithFloatVarNameElsewhere_NotReported;
// Analog zu NilCompare aber mit Boolean-Vergleich. 'true'/'false' sind
// nie Float, auch wenn ein gleichnamiges Float-Feld im File deklariert ist.
const SRC =
  'unit t; implementation'#13#10 +
  'type TFoo = record Value: Double; end;'#13#10 +
  'procedure Bar(const Value: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if Value = True then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Boolean = True darf nicht als Float-Equality kassiert werden');
  finally F.Free; end;
end;

procedure TTestFloatEquality.FloatVarVsNonFloatIdent_NoFinding;
// Praezisions-Guard (2026-06-29): `Value <> ShowSeconds` - Value ist Double,
// aber ShowSeconds ist Boolean. Der ANDERE Operand ist kein numerisches
// Literal und keine Float-Var -> reine Namens-/Scope-Blindheit, kein Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Value: Double; ShowSeconds: Boolean;'#13#10 +
  'begin'#13#10 +
  '  if Value <> ShowSeconds then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Float-Var vs Nicht-Float-Identifier darf kein Float-Equality sein');
  finally F.Free; end;
end;

procedure TTestFloatEquality.FloatVarVsLiteral_StillReported;
// Gegenprobe zum Guard: der ANDERE Operand IST hier ein numerisches Literal
// (0.5) - das ist der klassische IEEE-754-Bug und muss weiterhin feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Ratio: Double;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1);
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestFloatEquality.IntegerLocalWithFloatNameElsewhere_NotReported;
// FP-Regression (Real-World-FP-Audit 2026-07-10/11, Alcinoe.StringUtils.pas
// Z.2872): `LResult <> 0` mit lokalem `var LResult: Integer` ist ein
// Integer-gegen-Null-Test, KEIN Float-Vergleich. Weil derselbe Name
// IRGENDWO im File als Double deklariert ist (scope-blinder FloatVars-
// Namensindex), matchte der Detektor frueher faelschlich. Der Vergleich
// ist gegen ein NUMERISCHES LITERAL (0) und passiert damit den Praezisions-
// Guard; erst die Typ-Aufloesung des NAECHSTLIEGENDEN Decls (Integer via
// OperandDeclaredNonFloat) unterdrueckt den FP.
const SRC =
  'unit t; implementation'#13#10 +
  'type TRec = record LResult: Double; end;'#13#10 +
  'function Foo: Boolean;'#13#10 +
  'var LResult: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := LResult <> 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Integer-lokale Var (nur namensgleich zu einer Float-Var) gegen 0 ist kein Float-Equality');
  finally F.Free; end;
end;

procedure TTestFloatEquality.FloatVarWithIntNameElsewhere_Reported;
// Gegenprobe zur Typ-Aufloesung (Real-World-FP-Audit 2026-07-10/11,
// Alcinoe.Common.pas Z.1967 `if Ratio = 0`, Ratio: Single): derselbe Name
// 'Ratio' ist IRGENDWO als Integer-Feld deklariert, aber die NAECHSTLIEGENDE
// Deklaration zur Nutzung ist Single. OperandDeclaredNonFloat muss zum
// Float-Typ aufloesen -> der echte IEEE-754-Bug bleibt gemeldet (keine
// Ueber-Unterdrueckung / kein FN durch den 2026-07-11-Fix).
const SRC =
  'unit t; implementation'#13#10 +
  'type TRec = record Ratio: Integer; end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var Ratio: Single;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'Float-Var mit naechstliegendem Single-Decl gegen 0 bleibt ein Float-Equality-Bug');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestFloatEquality);

end.
