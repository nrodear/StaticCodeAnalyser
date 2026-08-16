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
    [Test] procedure Self_WhitespaceDifference_StillReported;
    [Test] procedure Self_CaseDifference_StillReported;
    // FP-Audit Stufe 2 (2026-08-16): gemeldet wird nur ein beweisbarer
    // Speicher-Slot - Local/Param/Result oder ein Feld DIESER Unit.
    [Test] procedure Self_ResultAssignment_Reported;
    [Test] procedure Self_FieldOfSameUnit_Reported;
    [Test] procedure Self_ParameterTarget_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure NoSelf_DifferentVar_NoFinding;
    [Test] procedure NoSelf_ExpressionWithSameVar_NoFinding;
    [Test] procedure NoSelf_DifferentFieldOnSameObject_NoFinding;
    [Test] procedure NoSelf_AssignFromCall_NoFinding;
    // Core-Audit 2026-07-17 (SCA047): Keyword-Operator-RHS an Wortgrenze
    // ('not Ready') darf nicht mit gleichnamiger LHS ('NotReady') kollabieren.
    [Test] procedure NoSelf_KeywordOperatorRHS_NoFinding;
    [Test] procedure Self_MultipleHits_AllReported;
    // FP-Audit Stufe 2 (2026-08-16): Property-Ziele, Member-Pfade und in der
    // Unit nicht aufloesbare Namen sind kein belegbares No-op mehr.
    [Test] procedure Self_PropertyTarget_NotReported;
    [Test] procedure Self_DottedFieldAccess_NotReported;
    [Test] procedure Self_ThreeLevelDottedAccess_NotReported;
    [Test] procedure Self_UnresolvableInheritedMember_NotReported;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Self_Finding_KindAndSeverity;
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

procedure TTestSelfAssignment.Self_WhitespaceDifference_StillReported;
// Zusaetzliche Spaces um den Bezeichner werden wegnormalisiert.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x :=   x ; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_ResultAssignment_Reported;
// 'Result := Result' ist ein beweisbarer Slot (Hint-Suppression-Idiom, im
// Audit als TP gewertet).
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Result := Result; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_FieldOfSameUnit_Reported;
// Ein Feld DIESER Unit ist immer ein Slot - die wertvollste TP-Klasse
// ('FFoo := FFoo' als echter Copy-Paste-Bug).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FValue: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin FValue := FValue; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment),
    'Feldzuweisung ist ein Speicher-Slot, kein Setter-Aufruf');
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_ParameterTarget_Reported;
// Parameter tragen im AST den Modifier als Praefix ('const X') - der darf
// die Aufloesung nicht verhindern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(var Value: Integer);'#13#10 +
  'begin Value := Value; end;';
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

// ============================================================
// FP-Audit Stufe 2 (2026-08-16): 73 % FP kamen daher, dass der reine
// Textvergleich eine PROPERTY-Zuweisung (Setter-Aufruf mit Wirkung) nicht
// von einem Speicher-Slot unterscheiden konnte.
// ============================================================

procedure TTestSelfAssignment.Self_PropertyTarget_NotReported;
// Clamp-/Re-Apply-Idiom: der Setter speichert einen ANDEREN Wert als der
// Getter geliefert hat (SynEdit SetTopLine, JvInspector SetTopIndex).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TEdit = class'#13#10 +
  '  private'#13#10 +
  '    FTopLine: Integer;'#13#10 +
  '    procedure SetTopLine(Value: Integer);'#13#10 +
  '  public'#13#10 +
  '    procedure Resize;'#13#10 +
  '    property TopLine: Integer read FTopLine write SetTopLine;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TEdit.Resize;'#13#10 +
  'begin TopLine := TopLine; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'Property-Zuweisung ist ein Setter-Aufruf, kein No-op');
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_DottedFieldAccess_NotReported;
// Member-Pfad: ob das letzte Segment Feld oder Property ist, haengt am Typ
// des Praefixes - ohne Cross-Unit-Typaufloesung nicht bestimmbar.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.Field := Obj.Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_ThreeLevelDottedAccess_NotReported;
// Drei-Ebenen-Zugriff, gleiche Begruendung wie beim zweistufigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Obj: TFoo;'#13#10 +
  'begin Obj.Sub.Field := Obj.Sub.Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment));
  finally F.Free; end;
end;

procedure TTestSelfAssignment.Self_UnresolvableInheritedMember_NotReported;
// 'Height' ist weder Local noch in dieser Unit deklariert - es ist eine
// geerbte VCL-Property. Ohne projektweites Wissen ist 'kein No-op' nicht
// widerlegbar.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TPanel = class(TCustomPanel)'#13#10 +
  '  public'#13#10 +
  '    procedure Rearrange;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TPanel.Rearrange;'#13#10 +
  'begin Height := Height; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'geerbtes Member: der Setter der Basisklasse ist nicht einsehbar');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelfAssignment);

end.
