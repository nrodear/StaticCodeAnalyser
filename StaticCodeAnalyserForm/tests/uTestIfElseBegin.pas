unit uTestIfElseBegin;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIfElseBegin = class
  public
    [Test] procedure SymmetricBoth_NoFinding;
    [Test] procedure SymmetricNeither_NoFinding;
    [Test] procedure ElseIfChain_NoFinding;
    [Test] procedure AsymmetricEndElseStmt_Reported;
    [Test] procedure IfElseBegin_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestIfElseBegin.SymmetricBoth_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then'#13#10 +
  '  begin DoA; DoB; end'#13#10 +
  '  else'#13#10 +
  '  begin DoC; DoD; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.SymmetricNeither_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then DoA else DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseIfChain_NoFinding;
// `end else if` ist die idiomatische Else-If-Kette und KEIN Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then'#13#10 +
  '  begin DoA; end'#13#10 +
  '  else if B then'#13#10 +
  '  begin DoB; end'#13#10 +
  '  else'#13#10 +
  '  begin DoC; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.AsymmetricEndElseStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then'#13#10 +
  '  begin DoA; DoB; end'#13#10 +
  '  else DoC;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIfElseBegin) >= 1);
  finally F.Free; end;
end;

procedure TTestIfElseBegin.IfElseBegin_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then begin X; end else Y;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkIfElseBegin then
      begin
        Assert.AreEqual<TFindingKind>(fkIfElseBegin, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkIfElseBegin finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIfElseBegin);

end.
