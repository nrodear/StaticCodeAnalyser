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
    // --- Welle 1 (2026-07-25): nearest-decl-Gate auf den Resolver-
    //     Disjunkten; der Komma-Listen-Decl-Fix wurde zurueckgebaut
    //     (Entscheid 2026-07-25, siehe CommaListDecl_KnownFnNotReported) ---
    [Test] procedure CommaListDecl_KnownFnNotReported;               // bewusste FN-Klasse
    [Test] procedure NestedDoubleShadowsIntegerParam_StillReported;  // TP-Gegenprobe
    // --- ADD-Sampling Welle 1b (2026-07-25): Zusatz-Gates aus dem Komma-
    //     Listen-FN-Close (+222 ADDs; FN-Close zurueckgebaut, die Gates
    //     bleiben), alle rein suppressiv ---
    [Test] procedure IntDomainAllIntAssigns_NotReported;             // Gate 1
    [Test] procedure IntDomainFieldAccessRhs_StillReported;          // TP-Gegenprobe
    [Test] procedure ComparatorPrimitiveSameFunc_NotReported;        // Gate 2a
    [Test] procedure ComparatorNameWithoutPrimitiveBody_StillReported; // TP-Gegenprobe
    [Test] procedure NonComparatorNamePrimitiveBody_StillReported;   // TP-Gegenprobe
    // Review-Fix Gate 2a (2026-07-25): ignorierter Epsilon-Parameter beweist
    // Toleranz-Absicht - kaputte SameValue-Nachbauten bleiben Fund.
    [Test] procedure SameValueRebuildIgnoredEpsilon_StillReported;   // TP-Gegenprobe
    [Test] procedure MaxMinIdentity_NotReported;                     // Gate 2b
    [Test] procedure MaxMinWithoutOtherOperand_StillReported;        // TP-Gegenprobe
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
// Fixture-Form: getrennte Deklarationen (weiterhin EIN var-Block) - Komma-
// Listen-Decls sind seit dem Rueckbau des Decl-Fixes bewusste FN-Klasse
// (Entscheid 2026-07-25, siehe CommaListDecl_KnownFnNotReported); dieser
// Test ist damit die Abdeckung des Demote-Accept-Pfads inkl. beweisbarer
// Local-Ident-RHS ('Seed').
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

// --- Welle 1 (2026-07-25): Komma-Listen-Rueckbau + nearest-decl-Gate ---

procedure TTestFloatEquality.CommaListDecl_KnownFnNotReported;
// Bewusste FN-Klasse (Entscheid 2026-07-25): Komma-Listen-Decls werden
// NICHT erfasst - in 'var Best, Seed: Double;' landet nur der kolon-
// adjazente Ident ('Seed') in FloatVars, 'Best = 0.5' ist ein BEKANNTES,
// akzeptiertes False Negative. Der FN-Close (Welle 1) erzeugte +222
// Korpus-Funde mit 0/16 Hart-TP-Sample und 69% Klassik-FP (Kette after88
// 440 -> after89 662 -> after90 654, die Zusatz-Gates holten nur -8) und
// wurde deshalb zurueckgebaut; Begruendung am Decl-Pattern RE_FLOAT_DECL
// in uFloatEquality. Der Test pinnt den Entscheid:
// schlaegt er fehl, wurde die FN-Klasse ohne die geforderte Wertedomaenen-
// Analyse re-geoeffnet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Best, Seed: Double;'#13#10 +
  'begin'#13#10 +
  '  if Best = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Komma-Listen-Ident (Best) ist bewusste FN-Klasse (Entscheid ' +
        '2026-07-25) - kein Fund ohne Wertedomaenen-Analyse');
  finally F.Free; end;
end;

procedure TTestFloatEquality.NestedDoubleShadowsIntegerParam_StillReported;
// Welle 1 (2026-07-25), nearest-decl-Gate auf den Resolver-Disjunkten:
// uParser2 verwirft nested routines aus dem AST, der TTypeResolver loeste
// fuer den Double-Param der GESCHACHTELTEN 'function Inner' die AEUSSERE
// Integer-Deklaration von Outer auf -> ResolvesToKnownNonFloat droppte den
// ECHTEN Double-Vergleich (dieselbe Shadowing-Blindheit wie beim Variant-
// Disjunkt, Korpus dwsUtils.pas:2776). Nearest-decl-wins: die naechst-
// gelegene Deklaration vor der Fundstelle ist 'Ratio: Double' (nested
// Signatur) -> beweisbar Float, der Drop wird blockiert, der Fund bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'function Outer(const Ratio: Integer): Integer;'#13#10 +
  '  function Inner(const Ratio: Double): Boolean;'#13#10 +
  '  begin'#13#10 +
  '    Result := Ratio = 0.5;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := 0;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'nested Double-Param shadowt den aeusseren Integer-Param - der echte ' +
      'Double-Vergleich darf nicht ueber die Outer-Deklaration gedroppt werden');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      '0.5 ist kein Sentinel-Zero - volle Confidence bleibt');
  finally F.Free; end;
end;

// --- ADD-Sampling Welle 1b (2026-07-25): Zusatz-Gates (aus dem Komma-
//     Listen-FN-Close; dieser wurde zurueckgebaut, die Gates bleiben) ---

procedure TTestFloatEquality.IntDomainAllIntAssigns_NotReported;
// Gate 1 (ADD-Sampling Welle 1b, 2026-07-25, JvDrawImage-Klasse): 'dx' ist
// ein lokales Double, dessen EINZIGE Zuweisung 'dx := X - Y' nur aus den
// Integer-Params X, Y besteht -> die Wertedomaene ist beweisbar ganzzahlig,
// jeder Wert exakt darstellbar, 'dx = 0' ist zuverlaessig -> Suppress
// (kein IEEE-754-Rundungsrisiko, kein Fund).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(X, Y: Integer);'#13#10 +
  'var dx: Double;'#13#10 +
  'begin'#13#10 +
  '  dx := X - Y;'#13#10 +
  '  if dx = 0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'beweisbare Integer-Wertedomaene (nur Integer-Params/-Literale, ' +
        'kein "/", keine Calls) -> exakter Vergleich zuverlaessig, kein Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.IntDomainFieldAccessRhs_StillReported;
// TP-Gegenprobe Gate 1 (ADD-Sampling Welle 1b, 2026-07-25): 'myorigin.X'
// ist ein FELD-Zugriff - Feld-Typen sind lexikalisch nicht beweisbar (das
// Feld koennte selbst Single sein). Die RHS ist damit unklar -> KEIN
// Suppress, der Fund bleibt mit voller Confidence (lieber weniger Drops
// als ein maskierter TP).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(X: Integer);'#13#10 +
  'var dx: Double;'#13#10 +
  'begin'#13#10 +
  '  dx := X - myorigin.X;'#13#10 +
  '  if dx = 0 then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Feld-Zugriff in der RHS ist nicht beweisbar integer-wertig - der Fund bleibt');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'berechnete RHS -> auch kein Sentinel-Demote, volle Confidence bleibt');
  finally F.Free; end;
end;

procedure TTestFloatEquality.ComparatorPrimitiveSameFunc_NotReported;
// Gate 2a (ADD-Sampling Welle 1b, 2026-07-25, JclAlgorithms-Klasse):
// 'function SameScale' traegt 'Same' im Namen und ihr Body ist im Kern
// GENAU 'Result := A = B;' - Gleichheit ist hier die vertragliche SEMANTIK
// der Funktion, kein versehentlicher IEEE-754-Bug -> Suppress.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse
// (sonst waere der Test vakuum-gruen: 0 Funde, weil 'A' nie in FloatVars
// landet und der Praezisions-Guard schon VOR Gate 2a droppt).
const SRC =
  'unit t; implementation'#13#10 +
  'function SameScale(const A: Double; const B: Double): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := A = B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Comparator-Primitiv (Same*-Funktion, Body = Result := A = B) ist ' +
        'die Gleichheits-Semantik selbst, kein Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.ComparatorNameWithoutPrimitiveBody_StillReported;
// TP-Gegenprobe Gate 2a (ADD-Sampling Welle 1b, 2026-07-25): der Name
// traegt zwar 'Same', aber der Body ist KEIN 1-2-Statement-Primitiv mehr
// (mehrere Statements vor dem Vergleich) - der '='-Vergleich ist dort
// nicht mehr die blosse Funktions-Semantik, der Fund bleibt.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'function SameState(const A: Double; const B: Double): Boolean;'#13#10 +
  'var T: Double;'#13#10 +
  'begin'#13#10 +
  '  T := A;'#13#10 +
  '  T := B;'#13#10 +
  '  Beep;'#13#10 +
  '  Result := A = B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'Same*-Name allein reicht nicht - ohne Primitiv-Body bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.NonComparatorNamePrimitiveBody_StillReported;
// TP-Gegenprobe Gate 2a (ADD-Sampling Welle 1b, 2026-07-25): identisches
// Primitiv 'Result := A = B;', aber der Funktionsname enthaelt weder
// Compare noch Same noch Equal - das Gate haengt an der per NAMEN
// deklarierten Vergleichs-Semantik und darf hier nicht greifen.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'function CheckVals(const A: Double; const B: Double): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := A = B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'ohne Compare/Same/Equal im Namen bleibt das Primitiv ein Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.SameValueRebuildIgnoredEpsilon_StillReported;
// Review-Fix Gate 2a (2026-07-25): kaputter SameValue-Nachbau. Der
// Epsilon-Parameter in der Signatur BEWEIST, dass Toleranz gewollt war -
// der Body 'Result := A = B' IGNORIERT ihn aber. Genau diese Klasse ist
// Kernbeute des Detektors; das Comparator-Primitiv-Gate darf hier trotz
// Same*-Name und Primitiv-Body NICHT unterdruecken.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'function SameValue(const A: Double; const B: Double; const Epsilon: Double): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := A = B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
        'ignorierter Epsilon-Parameter widerlegt den Exakt-Vergleichs-' +
        'Vertrag - der kaputte SameValue-Nachbau bleibt Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.MaxMinIdentity_NotReported;
// Gate 2b (ADD-Sampling Welle 1b, 2026-07-25, HSL/HSV-Klasse): 'cmax' wird
// ausschliesslich als REINER Max(...)-Call zugewiesen, dessen Argliste 'r'
// als nacktes Argument enthaelt (auch geschachtelt: Max(r, Max(g, b))).
// Max SELEKTIERT bit-identisch (keine Arithmetik) - 'cmax = r' fragt exakt
// 'war r das Maximum?' und ist zuverlaessig -> Suppress.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse
// (sonst waere der Test vakuum-gruen: 'r' fehlte in FloatVars, der
// Praezisions-Guard droppte schon VOR Gate 2b).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(r: Double; g: Double; b: Double);'#13#10 +
  'var cmax: Double;'#13#10 +
  'begin'#13#10 +
  '  cmax := Max(r, Max(g, b));'#13#10 +
  '  if cmax = r then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatEquality),
        'Max/Min-Selektions-Identitaet (cmax = r mit cmax := Max(r, ...)) ' +
        'ist ein zuverlaessiger Vergleich, kein Fund');
  finally F.Free; end;
end;

procedure TTestFloatEquality.MaxMinWithoutOtherOperand_StillReported;
// TP-Gegenprobe Gate 2b (ADD-Sampling Welle 1b, 2026-07-25): die Argliste
// des Max-Calls enthaelt 'r' NICHT ('cmax := Max(g, b)') - es gibt keine
// Selektions-Identitaet zwischen cmax und r, der exakte Vergleich zweier
// unabhaengiger Floats bleibt ein echter IEEE-754-Kandidat.
// Einzel-Decls: Komma-Listen sind seit dem Capture-Revert bewusste FN-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(r: Double; g: Double; b: Double);'#13#10 +
  'var cmax: Double;'#13#10 +
  'begin'#13#10 +
  '  cmax := Max(g, b);'#13#10 +
  '  if cmax = r then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'ohne den anderen Operanden in der Max-Argliste bleibt der Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'kein Zero-Literal, kein Sentinel-Demote - volle Confidence bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFloatEquality);

end.
