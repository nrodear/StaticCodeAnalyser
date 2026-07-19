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
    // Welle 1 (TTypeResolver): QWord fehlt in der Regex-NONFLOAT_ORDINAL-Liste -
    // nur der scope-genaue AST-Resolver kennt es und unterdrueckt die Kollision.
    [Test] procedure QWordScopeCollision_ResolverOnly_NotReported;
    // --- Auto-Runde 2026-07-19: class/record-Operanden + Result-Rueckgabetyp ---
    [Test] procedure ClassRefOperandWithFloatNameElsewhere_NotReported;
    [Test] procedure FloatVarInUnitWithClasses_StillReported;        // TP-Gegenprobe A
    [Test] procedure ResultOrdinalReturnWithFloatNameElsewhere_NotReported;
    [Test] procedure ResultFloatReturn_StillReported;                // TP-Gegenprobe B
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
procedure TTestFloatEquality.QWordScopeCollision_ResolverOnly_NotReported;
// Welle 1 - Beleg fuer den scope-genauen Typ-Resolver an SCA144. 'x' ist in GetF als
// Single deklariert (-> FloatVars-Namensindex), in Use aber als QWord (Scope-Kollision).
// Die lexikalische OperandDeclaredNonFloat kennt 'qword' NICHT (fehlt in NONFLOAT_
// ORDINAL_TYPES) -> wuerde faelschlich melden. Der TTypeResolver loest x@Use -> qword
// scope-genau auf (IsKnownNonFloatTypeName) und unterdrueckt. Zeigt den Resolver-Pfad.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetF(x: Single): Boolean;'#13#10 +
  'begin Result := x > 0; end;'#13#10 +
  'procedure Use;'#13#10 +
  'var x: QWord;'#13#10 +
  'begin'#13#10 +
  '  if x = 5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
    'x@Use ist QWord - nur der AST-Resolver kennt qword -> kein Float-Equality-Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.ClassRefOperandWithFloatNameElsewhere_NotReported;
// Auto-Runde 2026-07-19 Fix A / Real-World dwsJSON.pas:2144: 'Value = aValue'
// vergleicht zwei OBJEKTE. 'Value'/'aValue' sind ANDERSWO als Double-Param
// deklariert (FloatVars-Namenskollision), loesen aber scope-genau auf eine
// lokal deklarierte KLASSE auf -> Referenzvergleich, kein Float.
const SRC =
  'unit t; implementation'#13#10 +
  'type TVal = class end;'#13#10 +
  'procedure AddF(const Value: Double; const aValue: Double);'#13#10 +
  'begin end;'#13#10 +
  'function IndexOf(const aValue: TVal): Boolean;'#13#10 +
  'var Value: TVal;'#13#10 +
  'begin'#13#10 +
  '  Result := Value = aValue;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
    'Klassen-Referenzvergleich (nur namensgleich zu Float-Params) ist kein Float-Equality');
  finally F.Free; end;
end;

procedure TTestFloatEquality.FloatVarInUnitWithClasses_StillReported;
// TP-Gegenprobe A: die class/record-Unterdrueckung darf einen ECHTEN Float-
// Operanden nicht treffen - 'Ratio: Double' loest NICHT zu einer Klasse auf.
const SRC =
  'unit t; implementation'#13#10 +
  'type TVal = class end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var Ratio: Double;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
    'echter Double-Vergleich bleibt trotz Klassen in der Unit gemeldet');
  finally F.Free; end;
end;

procedure TTestFloatEquality.ResultOrdinalReturnWithFloatNameElsewhere_NotReported;
// Auto-Runde 2026-07-19 Fix B / Real-World dwsUtils.pas:1408: 'if Result = 0'
// in einer Cardinal-Funktion. 'var Result: Double' steht TEXTUELL VOR der
// Nutzung und vergiftete die lexikalische Naechstdeklarations-Regex; der
// scope-genaue Resolver (Result -> Rueckgabetyp Cardinal) rettet den FP.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Poison;'#13#10 +
  'var Result: Double;'#13#10 +
  'begin Result := 0.0; end;'#13#10 +
  'function H: Cardinal;'#13#10 +
  'begin'#13#10 +
  '  if Result = 0 then Result := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
    'Result einer Ordinal-Funktion (nur namensgleich zu Float-Var) ist kein Float-Equality');
  finally F.Free; end;
end;

procedure TTestFloatEquality.ResultFloatReturn_StillReported;
// TP-Gegenprobe B: liefert die Funktion einen FLOAT-Typ, bleibt 'if Result = X'
// ein echter IEEE-754-Vergleich (kein FN durch die Result-Registrierung).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Poison; var Result: Double; begin Result := 0.0; end;'#13#10 +
  'function H: Double;'#13#10 +
  'begin'#13#10 +
  '  if Result = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
    'Result einer Double-Funktion gegen Literal bleibt Float-Equality');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFloatEquality);

end.
