unit uTestNestedRoutines;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNestedRoutines = class
  public
    [Test] procedure FlatRoutines_NoFinding;
    [Test] procedure NestedProc_Reported;
    [Test] procedure NestedRoutines_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNestedRoutines.FlatRoutines_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure InnerHelper;'#13#10 +
  'begin'#13#10 +
  '  DoX;'#13#10 +
  'end;'#13#10 +
  'procedure Outer;'#13#10 +
  'begin'#13#10 +
  '  InnerHelper;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedProc_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    DoX;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedRoutine) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedRoutines_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkNestedRoutine then
      begin
        Assert.AreEqual<TFindingKind>(fkNestedRoutine, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkNestedRoutine finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNestedRoutines);

end.
