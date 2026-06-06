unit uTestRedundantParentheses;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantParentheses = class
  public
    [Test] procedure SingleParen_NoFinding;
    [Test] procedure DoubleParenIdent_Reported;
    [Test] procedure DoubleParenNumber_Reported;
    [Test] procedure ComplexExpression_NotReported;
    [Test] procedure ParenInString_NotReported;
    [Test] procedure MethodChain_NotReported;
    [Test] procedure RedundantParentheses_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantParentheses.SingleParen_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if (Active) then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.DoubleParenIdent_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if ((Active)) then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.DoubleParenNumber_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; X := ((42)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.ComplexExpression_NotReported;
// `((A + B))` mit Operator -> innere Parens potenziell relevant fuer
// Praezedenz, NICHT flaggen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; X := ((A + B)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.ParenInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; WriteLn(''((Hello))''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.MethodChain_NotReported;
// `((Obj)).Field` - hier ist die zweite `)` als Cast/Access-Kontext
// moeglich (e.g., `(TFoo(X)).Bar` wird zu `((TFoo)(X)).Bar` - nicht
// unbedingt redundant). Konservativ NICHT flaggen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; Y := ((Obj)).Field; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantParentheses));
  finally F.Free; end;
end;

procedure TTestRedundantParentheses.RedundantParentheses_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if ((Active)) then DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantParentheses then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantParentheses, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantParentheses finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantParentheses);

end.
