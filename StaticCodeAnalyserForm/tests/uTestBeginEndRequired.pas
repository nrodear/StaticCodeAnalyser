unit uTestBeginEndRequired;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBeginEndRequired = class
  public
    [Test] procedure ThenBegin_NoFinding;
    [Test] procedure ThenBareStmt_Reported;
    [Test] procedure ElseIfChain_NoFinding;
    [Test] procedure ThenRaise_NoFinding;
    [Test] procedure ThenExit_NoFinding;
    [Test] procedure DoBareStmt_Reported;
    [Test] procedure BeginEndRequired_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBeginEndRequired.ThenBegin_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then begin DoStuff; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenBareStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBeginEndRequired) >= 1);
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ElseIfChain_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then begin DoA; end'#13#10 +
  '  else if B then begin DoB; end'#13#10 +
  '  else begin DoC; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Failed then raise EError.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenExit_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if not Ready then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.DoBareStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  for i := 1 to N do DoStuff(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBeginEndRequired) >= 1);
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.BeginEndRequired_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if X then DoY; end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkBeginEndRequired then
      begin
        Assert.AreEqual<TFindingKind>(fkBeginEndRequired, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkBeginEndRequired finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBeginEndRequired);

end.
