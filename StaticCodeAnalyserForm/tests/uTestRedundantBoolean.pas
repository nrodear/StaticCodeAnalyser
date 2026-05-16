unit uTestRedundantBoolean;

// Tests fuer TRedundantBooleanDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantBoolean = class
  public
    [Test] procedure NoComparison_NoFinding;
    [Test] procedure EqualsTrue_Reported;
    [Test] procedure EqualsFalse_Reported;
    [Test] procedure NotEqualsFalse_Reported;
    [Test] procedure AssignTrue_NotReported;
    [Test] procedure ConstDecl_NotReported;
    [Test] procedure GeOperator_NotReported;
    [Test] procedure RedundantBoolean_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantBoolean.NoComparison_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Active then DoStuff;'#13#10 +
  '  if not Disabled then OtherStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.EqualsTrue_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Active = True then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.EqualsFalse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active = False then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.NotEqualsFalse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active <> False then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.AssignTrue_NotReported;
// `:=` ist Assignment, kein Vergleich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Boolean;'#13#10 +
  'begin'#13#10 +
  '  X := True;'#13#10 +
  '  X := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.ConstDecl_NotReported;
// `const X = True;` ist Deklaration, nicht Vergleich.
const SRC =
  'unit t; implementation'#13#10 +
  'const Active = True; Disabled = False;'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.GeOperator_NotReported;
// `>=` und `<=` duerfen nicht versehentlich gematcht werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Count >= 10 then DoStuff;'#13#10 +
  '  if X <= 0 then OtherStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.RedundantBoolean_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active = True then DoStuff;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantBoolean then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantBoolean, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantBoolean finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantBoolean);

end.
