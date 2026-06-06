unit uTestWithMultipleTargets;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWithMultipleTargets = class
  public
    [Test] procedure WithTwoTargets_Reported;
    [Test] procedure WithThreeTargets_Reported;
    [Test] procedure WithSingleTarget_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestWithMultipleTargets.WithTwoTargets_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Form1, List1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithThreeTargets_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with A, B, C do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithSingleTarget_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Form1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with A, B do DoStuff;'#13#10 +
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
      if Fnd.Kind = fkWithMultipleTargets then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkWithMultipleTargets finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWithMultipleTargets);

end.
