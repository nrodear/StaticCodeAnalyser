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
    // Inkrement A1 (Triage 2026-07-24): Idiom-Gates
    [Test] procedure IsStoredIdiom_NotReported;
    [Test] procedure StoredCompareOutsideIdiom_StillReported;
    [Test] procedure SetterChangeGuard_NotReported;
    [Test] procedure SetterWithoutFollowupAssign_StillReported;
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
    // --- G-Sent-2 (Triage 2026-07-25): Sentinel-Zero-DEMOTE auf fcLow ---
    [Test] procedure SentinelZeroLocalSimpleAssigns_DemotedToLow;
    [Test] procedure SentinelZeroParam_NotDemoted;                   // TP-Gegenprobe
    [Test] procedure SentinelZeroComputedAssign_NotDemoted;          // TP-Gegenprobe
    [Test] procedure SentinelZeroVarPassedToCall_NotDemoted;         // TP-Gegenprobe
    // Korpus-Fix jvcl JvgUtils.pas:1516: bare-Ident-RHS kann ein
    // parameterloser (nested-)Function-Call sein -> nur beweisbare Locals.
    [Test] procedure SentinelZeroRhsParameterlessFunc_NotDemoted;    // TP-Gegenprobe
    // --- Typluecken (Triage 2026-07-25): Ordinal-Alias/Variant-Operanden ---
    [Test] procedure OrdinalAliasOperand_NotReported;
    [Test] procedure VariantOperand_NotReported;
    [Test] procedure FloatAliasOperand_StillReported;                // TP-Gegenprobe
    // --- Scoping-Fix nearest-decl-wins (Korpus dwsUtils.pas:2776) ---
    [Test] procedure NestedDoubleShadowsVariantParam_StillReported;  // TP-Gegenprobe
    [Test] procedure SentinelZeroNestedVarBlock_OuterUse_NotDemoted; // TP-Gegenprobe
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

procedure TTestFloatEquality.IsStoredIdiom_NotReported;
// A1/G-Sent-1: 'function Is*Stored: Boolean' vergleicht die Property gegen
// ihren exakten Literal-Default - DFM-Streaming vergleicht selbst exakt,
// der Vergleich ist semantisch korrekt (Triage: 3/26 der Stichprobe).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  FScale: Double;'#13#10 +
  '  function IsScaleStored: Boolean;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.IsScaleStored: Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := FScale <> 1.0;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
    'IsStored-Idiom: exakter Default-Vergleich ist dort korrekt');
  finally F.Free; end;
end;

procedure TTestFloatEquality.StoredCompareOutsideIdiom_StillReported;
// TP-Gegenprobe: derselbe Vergleich in einer NICHT-*Stored-Funktion
// bleibt ein Fund (Gate haengt am Routinen-Namen, nicht am Muster).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  FScale: Double;'#13#10 +
  '  function CheckScale: Boolean;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.CheckScale: Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := FScale <> 1.0;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
    'ausserhalb des IsStored-Idioms bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SetterChangeGuard_NotReported;
// A1: 'if FScale <> Value then ... FScale := Value' in SetScale =
// VCL-Change-Detection; beide Seiten nur direkt zugewiesen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  FScale: Double;'#13#10 +
  '  procedure SetScale(const Value: Double);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.SetScale(const Value: Double);'#13#10 +
  'begin'#13#10 +
  '  if FScale <> Value then'#13#10 +
  '  begin'#13#10 +
  '    FScale := Value;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
    'Setter-Change-Guard mit Follow-up-Assign ist idiomatisch korrekt');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SetterWithoutFollowupAssign_StillReported;
// TP-Gegenprobe: ohne nachfolgende Feld-Zuweisung fehlt der Change-
// Detection-Beleg - das Gate darf NICHT greifen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  FScale: Double;'#13#10 +
  '  procedure SetScale(const Value: Double);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.SetScale(const Value: Double);'#13#10 +
  'begin'#13#10 +
  '  if FScale <> Value then'#13#10 +
  '    Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
    'Set*-Routine ohne Follow-up-Assign: Gate greift nicht, Fund bleibt');
  finally F.Free; end;
end;

// --- G-Sent-2 (Triage 2026-07-25): Sentinel-Zero-DEMOTE auf fcLow ---

procedure TTestFloatEquality.SentinelZeroLocalSimpleAssigns_DemotedToLow;
// G-Sent-2: 'Best = 0' auf einem LOKALEN var, dessen saemtliche Zuweisungen
// in der Routine direkte einfache Zuweisungen sind ('Best := 0;',
// 'Best := 1.5;', 'Best := Seed;'). Sentinel-Semantik: exakter Vergleich
// gegen den direkt zugewiesenen Wert ist korrekt -> Fund bleibt (monoton!),
// aber Confidence wird auf fcLow demotet.
// Korpus-Fix jvcl JvgUtils.pas:1516: die Ident-RHS 'Seed' ist hier bewusst
// als Local IM SELBEN var-Block deklariert - nur so ist sie beweisbar KEIN
// parameterloser Function-Call, und der Demote-Accept-Pfad fuer beweisbare
// Local-Ident-RHS bleibt abgedeckt.
// WICHTIG (Fixture-Form): KEINE Komma-Liste 'var Best, Seed: Double;' -
// Phase 1 des Detektors (CachedReDecl) faengt in Komma-Listen nur den
// kolon-adjazenten Ident (dokumentierte Bestands-Limitation), 'Best' kaeme
// nie in FloatVars und das Float-Var-Gate wuerde den Fund VOR dem
// Demote-Pfad droppen. Getrennte Deklarationen (weiterhin EIN var-Block)
// treffen ausschliesslich den Sentinel-Zero-Demote-Pfad.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Best: Double;'#13#10 +
  '    Seed: Double;'#13#10 +
  'begin'#13#10 +
  '  Seed := 2.5;'#13#10 +
  '  Best := 0;'#13#10 +
  '  if Best = 0 then'#13#10 +
  '    Best := Seed;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Sentinel-Zero wird NICHT gedroppt - der Fund muss bleiben (Demote statt Drop)');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcLow, Hit.Confidence,
      'lokales var mit nur direkten einfachen Zuweisungen gegen 0 -> fcLow-Demote');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SentinelZeroParam_NotDemoted;
// TP-Gegenprobe: '<Param> = 0' wird NIEMALS demotet - die Wert-Herkunft
// eines Parameters ist nur beim Caller sichtbar (kann berechnet sein).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const Ratio: Double);'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Parameter-Vergleich gegen 0 bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'Parameter werden nie demotet - volle Confidence bleibt');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SentinelZeroComputedAssign_NotDemoted;
// TP-Gegenprobe: die Var traegt einen BERECHNETEN Wert ('Sum := A * B;') -
// exakter 0-Vergleich darauf ist der klassische IEEE-754-Bug und behaelt
// volle Confidence/Severity.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Double);'#13#10 +
  'var Sum: Double;'#13#10 +
  'begin'#13#10 +
  '  Sum := A * B;'#13#10 +
  '  if Sum = 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'berechneter Wert gegen 0 bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'berechnete Zuweisung -> KEIN Sentinel, keine Demote');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SentinelZeroVarPassedToCall_NotDemoted;
// TP-Gegenprobe: die Var wird als Call-Argument uebergeben ('Compute(Best);')
// - var-/out-Uebergabe ist lexikalisch nicht unterscheidbar, der Wert kann
// im Call veraendert worden sein -> unklar, KEIN Demote.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Best: Double;'#13#10 +
  'begin'#13#10 +
  '  Best := 0;'#13#10 +
  '  Compute(Best);'#13#10 +
  '  if Best = 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'var-Arg-uebergebene Var gegen 0 bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'Arg-Uebergabe an Call -> Herkunft unklar, keine Demote');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SentinelZeroRhsParameterlessFunc_NotDemoted;
// Korpus-Fix (jvcl JvgUtils.pas:1516): 'Denominator := DigitsToValue;' sieht
// textuell wie ein Local-Read aus, ist aber ein PARAMETERLOSER Call der
// SIBLING-nested 'function DigitsToValue: Single' -> der Wert ist BERECHNET,
// und 'Denominator <> 0' als Divisions-Guard ist die JvCalc-Kernklasse des
// Detektors (echter TP). Bare-Ident-RHS ohne var-Block-Nachweis darf NICHT
// demoten -> volle Confidence bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'function Calc: Single;'#13#10 +
  '  function DigitsToValue: Single;'#13#10 +
  '  begin'#13#10 +
  '    Result := 3.7;'#13#10 +
  '  end;'#13#10 +
  '  function TestForMulDiv: Single;'#13#10 +
  '  var Denominator: Single;'#13#10 +
  '  begin'#13#10 +
  '    Denominator := DigitsToValue;'#13#10 +
  '    if Denominator <> 0 then'#13#10 +
  '      Result := 1 / Denominator;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := TestForMulDiv;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Divisions-Guard auf berechnetem Wert bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'RHS ist ein parameterloser nested-Function-Call, kein beweisbares ' +
      'Local -> KEIN Sentinel-Demote, volle Confidence bleibt');
  finally F.Free; end;
end;

// --- Typluecken (Triage 2026-07-25): Ordinal-Alias/Variant-Operanden ---

procedure TTestFloatEquality.OrdinalAliasOperand_NotReported;
// Massnahme 2: 'Value' ist lokal als TColor32 deklariert, und TColor32 ist
// IN DIESER UNIT beweisbar ein Ordinal-Alias ('= type Cardinal'). Der Fund
// entstuende nur ueber die FloatVars-Namenskollision mit dem Double-Param
// von AddF -> beweisbar kein Float, unterdruecken.
const SRC =
  'unit t; implementation'#13#10 +
  'type TColor32 = type Cardinal;'#13#10 +
  'procedure AddF(const Value: Double);'#13#10 +
  'begin end;'#13#10 +
  'procedure Use;'#13#10 +
  'var Value: TColor32;'#13#10 +
  'begin'#13#10 +
  '  if Value = 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'in-Unit-Ordinal-Alias (TColor32 = type Cardinal) ist beweisbar kein Float');
  finally F.Free; end;
end;

procedure TTestFloatEquality.VariantOperand_NotReported;
// Massnahme 2: der Operand ist scope-genau als Variant deklariert - der Fund
// entstuende nur ueber die Namenskollision mit dem Double-Record-Feld.
const SRC =
  'unit t; implementation'#13#10 +
  'type TRec = record Score: Double; end;'#13#10 +
  'procedure Use;'#13#10 +
  'var Score: Variant;'#13#10 +
  'begin'#13#10 +
  '  if Score = 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Variant-Operand (nur namensgleich zu einem Float-Feld) ist kein Float-Equality');
  finally F.Free; end;
end;

procedure TTestFloatEquality.FloatAliasOperand_StillReported;
// TP-Gegenprobe: die Alias-Kette endet auf einem FLOAT ('TFloat = type
// Double') - die Unterdrueckung darf NICHT greifen, der echte IEEE-754-
// Vergleich bleibt gemeldet (kein FN durch die Alias-Aufloesung).
const SRC =
  'unit t; implementation'#13#10 +
  'type TFloat = type Double;'#13#10 +
  'procedure AddF(const Ratio: Double);'#13#10 +
  'begin end;'#13#10 +
  'procedure Use;'#13#10 +
  'var Ratio: TFloat;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'Float-Alias (TFloat = type Double) bleibt ein Float-Equality-Fund');
  finally F.Free; end;
end;

// --- Scoping-Fix nearest-decl-wins (Korpus dwsUtils.pas:2776) ---

procedure TTestFloatEquality.NestedDoubleShadowsVariantParam_StillReported;
// Scoping-Fix (Korpus dwsUtils.pas:2776): 'function VarCompareSafe(const left,
// right: Variant)' enthaelt die GESCHACHTELTE 'function CompareDoubles(const
// left, right: Double)'. uParser2 verwirft nested routines aus dem AST, der
// TTypeResolver loeste fuer deren 'left = right' also die AEUSSERE Variant-
// Deklaration auf -> ResolvesToInUnitOrdinalAliasOrVariant droppte den ECHTEN
// Double-Vergleich (Shadowing maskierte einen Float-TP). Nearest-decl-wins:
// die naechstgelegene Deklaration vor der Fundstelle ist 'left/right: Double'
// (nested Signatur) -> kein Variant-Beweis, der Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'function VarCompareSafe(const left: Variant; const right: Variant): Integer;'#13#10 +
  '  function CompareDoubles(const left: Double; const right: Double): Integer;'#13#10 +
  '  begin'#13#10 +
  '    if left = right then Exit(0);'#13#10 +
  '    Result := 1;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := CompareDoubles(0, 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'nested Double-Params shadowen die aeusseren Variant-Params - der echte ' +
        'Double-Vergleich darf nicht ueber die Outer-Deklaration gedroppt werden');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SentinelZeroNestedVarBlock_OuterUse_NotDemoted;
// Analoge Schwaeche in SentinelZeroLocalDemote: die Fundstelle liegt im
// OUTER-Body NACH einer nested routine. Die Routinen-Spanne beginnt an der
// nested 'procedure Inner', deren var-Block ('var Best: Double') lieferte
// den "lokalen" Nachweis - an der Fundstelle ist 'Best' aber der OUTER-
// PARAMETER (Herkunft nur beim Caller sichtbar, wird NIE demotet). Der
// Body-geschlossen-Check (Tiefe faellt nach der nested routine auf 0
// zurueck) muss das Demote verhindern -> volle Confidence bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer(const Best: Double);'#13#10 +
  '  procedure Inner;'#13#10 +
  '  var Best: Double;'#13#10 +
  '  begin'#13#10 +
  '    Best := 0;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  '  if Best = 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Outer-Param-Vergleich gegen 0 bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'var-Block der nested routine darf den Outer-Fund nicht demoten ' +
      '(Shadowing-Fehlattribution) - volle Confidence bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFloatEquality);

end.
