unit uTestEmptyMethod;

// Tests fuer den TEmptyMethodDetector.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- EmptyMethod (TEmptyMethodDetector) --------------------------------------------
  [TestFixture]
  TTestEmptyMethod = class
  public
    [Test] procedure Empty_ProcedureBody_ReportsHint;
    [Test] procedure Empty_FunctionBody_ReportsHint;
    [Test] procedure Empty_BodyWithInherited_NoFinding;
    [Test] procedure Empty_BodyWithSingleAssign_NoFinding;
    [Test] procedure Empty_TwoEmptyMethods_BothReported;
    [Test] procedure Empty_OneFilledOneEmpty_OnlyEmptyReported;
    [Test] procedure Empty_Constructor_ReportsHint;
    [Test] procedure Empty_Destructor_ReportsHint;
    [Test] procedure Empty_BodyWithCall_NoFinding;
    [Test] procedure Empty_ForwardDecl_NoFinding;
  end;

implementation

// =============================================================================
// EmptyMethod-Tests
// =============================================================================

procedure TTestEmptyMethod.Empty_ProcedureBody_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_FunctionBody_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'function Foo: Integer;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithSingleAssign_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 5; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_TwoEmptyMethods_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo; begin end;'#13#10+
  'procedure Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_OneFilledOneEmpty_OnlyEmptyReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;'#13#10+
  'procedure Bar;'#13#10+
  'begin Foo; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_Constructor_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_Destructor_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin DoSomething; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_ForwardDecl_NoFinding;
// Forward-Declaration in der Class - dort gibt es kein nkBlock,
// also auch keine Empty-Method-Meldung.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  procedure Bar;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

end.
