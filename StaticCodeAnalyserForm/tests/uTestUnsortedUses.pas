unit uTestUnsortedUses;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnsortedUses = class
  public
    [Test] procedure UnsortedUses_Reported;
    [Test] procedure SortedUses_NotReported;
    [Test] procedure SingleEntry_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnsortedUses.UnsortedUses_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils, System.Classes, System.IOUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnsortedUses) >= 1);
  finally F.Free; end;
end;

procedure TTestUnsortedUses.SortedUses_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes, System.IOUtils, System.SysUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnsortedUses));
  finally F.Free; end;
end;

procedure TTestUnsortedUses.SingleEntry_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnsortedUses));
  finally F.Free; end;
end;

procedure TTestUnsortedUses.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils, System.Classes;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnsortedUses then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnsortedUses finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnsortedUses);

end.
