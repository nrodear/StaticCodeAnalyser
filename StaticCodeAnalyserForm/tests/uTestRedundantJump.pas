unit uTestRedundantJump;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantJump = class
  public
    [Test] procedure ExitInMiddle_NoFinding;
    [Test] procedure ExitBeforeEnd_Reported;
    [Test] procedure ContinueBeforeEnd_Reported;
    [Test] procedure BreakBeforeEnd_Reported;
    [Test] procedure RedundantJump_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantJump.ExitInMiddle_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Failed then Exit;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantJump));
  finally F.Free; end;
end;

procedure TTestRedundantJump.ExitBeforeEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantJump));
  finally F.Free; end;
end;

procedure TTestRedundantJump.ContinueBeforeEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '    Continue;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRedundantJump) >= 1);
  finally F.Free; end;
end;

procedure TTestRedundantJump.BreakBeforeEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  while True do'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '    Break;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRedundantJump) >= 1);
  finally F.Free; end;
end;

procedure TTestRedundantJump.RedundantJump_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff; Exit; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantJump then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantJump, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantJump finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantJump);

end.
