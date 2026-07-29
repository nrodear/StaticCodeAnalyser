unit uTestCanBeClassMethod;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCanBeClassMethod = class
  public
    [Test] procedure NoSelfAccess_Reported;
    [Test] procedure SelfAccess_NotReported;
    [Test] procedure FieldAccess_NotReported;
    [Test] procedure FieldViaMethodCall_NotReported;
    [Test] procedure LowercaseFieldAccess_NotReported;
    [Test] procedure AlreadyClassMethod_NotReported;
    [Test] procedure VirtualMethod_NotReported;
    [Test] procedure VirtualMethodWithSpaceBeforeDirective_NotReported;
    [Test] procedure ProcedureNoSelfAccess_SuggestsClassProcedure;
    [Test] procedure Constructor_NotReported;
    [Test] procedure SiblingInstanceMethodCall_NotReported;
    [Test] procedure NonFFieldInRhs_NotReported;
    [Test] procedure InheritedMemberAccess_NotReported;
    [Test] procedure OnlyParams_WithClassDecl_StillReported;
    [Test] procedure Finding_KindAndSeverity;
    // Restschulden-Audit 2026-07-26 (UnqualifiedName-Konsolidierung):
    // Decl<->Impl-Abgleich bei mehrfach qualifizierten Methodennamen.
    [Test] procedure NestedTypeMethod_MatchesVirtualDecl_NotReported;
    [Test] procedure SimpleQualifiedMethod_MatchesVirtualDecl_NotReported;
    [Test] procedure SimpleQualifiedMethod_WithoutPolyDecl_StillReported;
    // T2-Guards-Ruecknahme (2026-07-29):
    [Test] procedure NestedMethod_UsingOwnField_NotFlagged;
    [Test] procedure NestedMethod_NoSelfUse_Flagged;
    [Test] procedure NestedRecordMethod_NoSelfUse_Flagged;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uCanBeClassMethod,   // AST-Direkttests (s. RunDetectorOnDeclImpl)
  uTestFindingHelper;

// --- AST-Direkteinstieg fuer den Decl<->Impl-Abgleich ----------------------
// Die folgenden drei Tests bauen den AST von Hand statt ueber
// TFindingHelper.FindingsOf(SRC). Grund: uParser2.ParseMethodSignature
// konsumiert im Implementierungs-Header GENAU EINEN Punkt (`if Tok.Kind =
// tkDot`, kein Loop) - aus `procedure TOuter.TInner.DoIt;` wird deshalb
// heute der nkMethod-Name 'TOuter.TInner'. Ein quelltextbasierter Test
// wuerde also gar nicht den Pfad treffen, den dieser Fix repariert
// (er waere gruen/rot aus dem falschen Grund). Der Detektor selbst
// arbeitet ausschliesslich auf Node.Name - der AST-Einstieg prueft ihn
// exakt an der Stelle, an der die Semantik haengt. Die Parser-Luecke
// selbst ist separate Restschuld und hier bewusst NICHT angefasst.
//
// Aufbau:
//   nkUnit
//     nkInterface / nkTypeSection / nkClass(AOuterCls)
//        [nkClass(AInnerCls)] / nkMethod(ADeclName) TypeRef=ADeclTypeRef
//     nkImplementation / nkMethod(AImplName) TypeRef='procedure'
//        nkBlock / nkCall('WriteLn')      <- Body ohne Self-/Member-Bezug
function RunDetectorOnDeclImpl(const AOuterCls, AInnerCls, ADeclName,
  ADeclTypeRef, AImplName: string): Integer;
var
  Root, Impl, Cls, Inner, Meth, Blk : TAstNode;
  Res : TObjectList<TLeakFinding>;
begin
  Root := TAstNode.Create(nkUnit, 't');
  try
    Cls := Root.Add(nkInterface).Add(nkTypeSection).Add(nkClass, AOuterCls);
    if AInnerCls <> '' then
      Inner := Cls.Add(nkClass, AInnerCls)   // nested type
    else
      Inner := Cls;
    Meth         := Inner.Add(nkMethod, ADeclName, 3);
    Meth.TypeRef := ADeclTypeRef;            // z.B. 'procedure;virtual'

    Impl         := Root.Add(nkImplementation);
    Meth         := Impl.Add(nkMethod, AImplName, 10);
    Meth.TypeRef := 'procedure';             // Impl-Header traegt nie Direktiven
    Blk          := Meth.Add(nkBlock, '', 11);
    Blk.Add(nkCall, 'WriteLn', 12);

    Res := TObjectList<TLeakFinding>.Create(True);
    try
      TCanBeClassMethodDetector.AnalyzeUnit(Root, 'sample.pas', Res);
      Result := TFindingHelper.Count(Res, fkCanBeClassMethod);
    finally
      Res.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestCanBeClassMethod.NoSelfAccess_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := A + B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBeClassMethod) >= 1);
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.SelfAccess_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  Self.Update;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.FieldAccess_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  FCounter := FCounter + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.FieldViaMethodCall_NotReported;
// FP-Fix (Real-World 2026-06-21): Feldzugriff via Methode/Property/Index
// (`FList.Add(...)`) wird vom Parser als EIN Node-Name abgelegt - das
// fuehrende Segment 'FList' ist trotzdem ein Feld -> kein class method.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  FList.Add(1);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'Feldzugriff via Methode (FList.Add) ist Instance-State - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.LowercaseFieldAccess_NotReported;
// FP-Fix (Real-World 2026-06-21): lowercase-f-Feldkonvention (Alcinoe
// fOwner/fUpdateSQL) - 'f' + Grossbuchstabe ist ebenfalls ein Feld.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  fOwner.Update;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'lowercase-f-Feld (fOwner) ist Instance-State - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.AlreadyClassMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMath = class'#13#10 +
  '    class function Add(A, B: Integer): Integer; static;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.VirtualMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    function Bar(A, B: Integer): Integer; virtual;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Bar(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.VirtualMethodWithSpaceBeforeDirective_NotReported;
// FP-Fix doublecmd CharDistribution.pas: 'procedure Reset; virtual;'
// (mit Space vor 'virtual'). Pos(';virtual', ...) im alten Pattern
// matched nicht weil dort ';virtual' ohne Space gesucht wurde.
// Real-Pattern: 'procedure ; virtual' im TypeRef (Parser-Output mit
// Space-Normalisierung).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Reset; virtual;'#13#10 +     // Space vor virtual
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  // nothing'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
      'virtual mit Space davor MUSS als polymorph erkannt werden');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.ProcedureNoSelfAccess_SuggestsClassProcedure;
// FP-Fix doublecmd CharDistribution.pas: bei procedure (statt function)
// wurde 'could be declared as `class function`' empfohlen - syntaktisch
// falsch. Sollte 'class procedure' sein.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TUtil.DoIt(X: Integer);'#13#10 +
  'begin'#13#10 +
  '  WriteLn(X);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
    Fnd : TLeakFinding;
    Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCanBeClassMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkCanBeClassMethod finding expected for procedure');
    Assert.IsTrue(Pos('class procedure', Hit.MissingVar) > 0,
      'Procedure-Empfehlung muss "class procedure" enthalten, nicht "class function"');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.Constructor_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  // Konstruktor ohne Field-Access - trotzdem nicht class-methodisierbar'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.SiblingInstanceMethodCall_NotReported;
// FP-Fix (Real-World 2026-06-24): bare Aufruf einer Sibling-Instanz-Methode
// (`Helper;` ohne Self.) ist impliziter Self-Zugriff. Wird jetzt ueber die
// Klassen-Member-Liste erkannt (TStringHashMap.Remove -> FindNode/DeleteNode).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FList: TObject;'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure DoIt;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper;'#13#10 +
  'begin FList.Free; end;'#13#10 +              // Field-Zugriff -> nicht geflaggt
  'procedure TFoo.DoIt;'#13#10 +
  'begin Helper; end;'#13#10 +                  // Sibling-Call -> mein Fix
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'bare Sibling-Instanz-Methodenaufruf ist Self-Zugriff - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.NonFFieldInRhs_NotReported;
// FP-Fix (Real-World 2026-06-24): Feld OHNE F-Konvention, im RHS-Ausdruck
// (Parser legt RHS als Blob in nkAssign.TypeRef ab; alter Check sah nur
// Node.Name=LHS). Ueber die Klassen-Member-Liste wird 'Counter' im RHS erkannt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    Counter: Integer;'#13#10 +               // Non-F-Feld
  '    function Calc(X: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Calc(X: Integer): Integer;'#13#10 +
  'begin Result := X * Counter; end;'#13#10 +   // Counter steht im RHS-Blob
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'Non-F-Feld im RHS-Ausdruck ist Instance-State - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.InheritedMemberAccess_NotReported;
// SCA148 Stufe 2 (2026-06-25): bare Zugriff auf einen GEERBTEN Member (Feld der
// In-Unit-Basisklasse). Real-World: Alcinoe TALExprAbstractFuncSym.CompileFirstArg
// nutzt geerbtes Lexer/CompileParser. Der Member-Set wird jetzt entlang der
// In-Unit-Vererbungskette aufgeloest -> `Lexer` zaehlt als Instance-Zugriff.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    Lexer: TObject;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoIt;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TDerived.DoIt;'#13#10 +
  'begin Lexer.Free; end;'#13#10 +              // geerbtes Feld bare
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'Zugriff auf geerbten Member (In-Unit-Basis) ist Instance-State - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.OnlyParams_WithClassDecl_StillReported;
// Gegenprobe gegen Ueber-Suppression: Methode nutzt NUR Parameter, obwohl die
// Klasse Member hat. Member-Set-Scan darf hier NICHT matchen -> echtes Finding
// bleibt erhalten.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMath = class'#13#10 +
  '    Counter: Integer;'#13#10 +
  '    function Add(A, B: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +         // nur Params, kein Member
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBeClassMethod) >= 1,
    'Methode ohne jeden Member-Zugriff bleibt class-method-Kandidat');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := A + B;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCanBeClassMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkCanBeClassMethod finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
    // H4-Demotion 2026-06-28 (Korpus-Triage ~68% FP): SCA148 ist fcLow ->
    // faellt unter der Default-Schwelle fcMedium aus dem Standard-Profil,
    // bleibt opt-in. Lock gegen versehentliches Re-Promote.
    Assert.AreEqual(fcLow, Hit.Confidence);
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.NestedTypeMethod_MatchesVirtualDecl_NotReported;
// FIX-TEST (Restschulden-Audit 2026-07-26): Methode eines NESTED TYPE, deren
// Deklaration ';virtual' traegt. Der Implementierungs-Name hat ZWEI Punkte
// ('TOuter.TInner.DoIt'). Die frueher lokale UnqualifiedMethodName-Fassung
// nahm Pos('.') = den ERSTEN Punkt und lieferte 'TInner.DoIt'; der Lookup
// gegen das Set der polymorphen Deklarations-Namen ('doit') schlug damit
// STILL fehl, der ';virtual'-Skip lief ins Leere und SCA148 meldete die
// Methode. Mit TDetectorUtils.UnqualifiedNameLast ('DoIt') greift der Skip.
begin
  Assert.AreEqual<Integer>(0,
    RunDetectorOnDeclImpl('TOuter', 'TInner', 'DoIt', 'procedure;virtual',
                          'TOuter.TInner.DoIt'),
    'nested-type-Impl muss seine virtuelle Deklaration finden - kein Finding');
end;

procedure TTestCanBeClassMethod.SimpleQualifiedMethod_MatchesVirtualDecl_NotReported;
// GEGENPROBE 1: der einfache Fall 'TFoo.Bar' (genau EIN Punkt) verhaelt sich
// unveraendert - erster und letzter Punkt sind hier derselbe, der Skip greift
// vor wie nach der Umstellung.
begin
  Assert.AreEqual<Integer>(0,
    RunDetectorOnDeclImpl('TFoo', '', 'Bar', 'procedure;virtual', 'TFoo.Bar'),
    'einfach qualifizierte virtuelle Methode bleibt unterdrueckt');
end;

procedure TTestCanBeClassMethod.SimpleQualifiedMethod_WithoutPolyDecl_StillReported;
// GEGENPROBE 2 (gegen Ueber-Suppression): dieselbe Konstellation OHNE
// Polymorphie-Direktive an der Deklaration und ohne Member-Zugriff im Body
// bleibt ein echtes Finding - der neue Helfer darf nichts zusaetzlich
// wegschlucken.
begin
  Assert.AreEqual<Integer>(1,
    RunDetectorOnDeclImpl('TFoo', '', 'Bar', 'procedure', 'TFoo.Bar'),
    'ohne Polymorphie-Direktive bleibt der class-method-Kandidat gemeldet');
end;

procedure TTestCanBeClassMethod.NestedMethod_UsingOwnField_NotFlagged;
// Member-Guard muss nested classes aufloesen: FullDict ist ueber den
// einfachen Namen geschluesselt, ClassKeyOf liefert den Besitzertyp.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TInner = class'#13#10 +
  '        Data: Integer;'#13#10 +
  '        procedure Bump;'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TInner.Bump;'#13#10 +
  'begin'#13#10 +
  '  Data := Data + 1;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
      'bare Feldzugriff der nested class muss den Member-Guard treffen');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.NestedMethod_NoSelfUse_Flagged;
// Gegenprobe: nested Methode ohne Instanzbezug wird regulaer gemeldet
// (Paritaet zu Top-Level-Klassen).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TInner = class'#13#10 +
  '        FData: Integer;'#13#10 +
  '        procedure Util;'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TInner.Util;'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCanBeClassMethod) >= 1,
      'nested Methode ohne Instanzbezug: Fund wie bei Top-Level');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.NestedRecordMethod_NoSelfUse_Flagged;
// Die eigentliche Verhaltensaenderung der Ruecknahme: nested-RECORD-
// Methoden (Besitzer steht nicht im MemberDict) verhalten sich jetzt wie
// Top-Level-Records - Analyse ohne Member-Guard, Fund bei fehlendem
// Instanzbezug. Der NoSelfUse-Klassen-Test war schon vor der Ruecknahme
// gruen (der else-Zweig war fuer aufloesbare nested classes seit 8d36052
// toter Code) - DIESER Fall hier war der real unterdrueckte.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TRec = record'#13#10 +
  '        A: Integer;'#13#10 +
  '        procedure Util;'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TRec.Util;'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCanBeClassMethod) >= 1,
      'nested-record-Methode ohne Instanzbezug: Fund wie bei Top-Level-Records');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCanBeClassMethod);

end.
