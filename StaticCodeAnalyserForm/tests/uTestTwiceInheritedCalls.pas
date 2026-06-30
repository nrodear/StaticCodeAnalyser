unit uTestTwiceInheritedCalls;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTwiceInheritedCalls = class
  public
    [Test] procedure SingleInherited_NoFinding;
    [Test] procedure TwoInherited_Reported;
    [Test] procedure NoInherited_NoFinding;
    [Test] procedure TwiceInheritedCalls_KindAndSeverity;
    [Test] procedure InheritedInIfElseBranches_NoFinding;
    [Test] procedure TwoSequentialInherited_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTwiceInheritedCalls.SingleInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwoInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.NoInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwiceInheritedCalls_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTwiceInheritedCalls then
      begin
        Assert.AreEqual<TFindingKind>(fkTwiceInheritedCalls, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTwiceInheritedCalls finding');
  finally F.Free; end;
end;

// FP-Guard (2026-06-29): zwei `inherited` ueber if/else-Branches verteilt
// haengen an nkIfStmt - NICHT an einem nkBlock - und laufen mutual-exklusiv.
// Darf NICHT gemeldet werden.
procedure TTestTwiceInheritedCalls.InheritedInIfElseBranches_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  if X then inherited else inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

// Zwei sequenzielle `inherited` direkte Kinder EINES nkBlock - laufen beide,
// Parent-Side-Effekte verdoppeln sich -> bleibt ein Finding.
procedure TTestTwiceInheritedCalls.TwoSequentialInherited_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTwiceInheritedCalls) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTwiceInheritedCalls);

end.
