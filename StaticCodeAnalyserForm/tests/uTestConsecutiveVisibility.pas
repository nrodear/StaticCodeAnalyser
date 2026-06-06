unit uTestConsecutiveVisibility;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsecutiveVisibility = class
  public
    [Test] procedure SingleSectionsOnly_NoFinding;
    [Test] procedure ConsecutiveSameVisibility_Reported;
    [Test] procedure AlternatingVisibility_NoFinding;
    [Test] procedure EmptyHeaderThenSame_NotReported;
    [Test] procedure ConsecutiveVisibility_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConsecutiveVisibility.SingleSectionsOnly_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveVisibility));
  finally F.Free; end;
end;

procedure TTestConsecutiveVisibility.ConsecutiveSameVisibility_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Bar;'#13#10 +
  '  private'#13#10 +                 // <-- 2x private
  '    FY: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConsecutiveVisibility));
  finally F.Free; end;
end;

procedure TTestConsecutiveVisibility.AlternatingVisibility_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  protected'#13#10 +
  '    procedure A;'#13#10 +
  '  public'#13#10 +
  '    procedure B;'#13#10 +
  '  published'#13#10 +
  '    property X: Integer read FX;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveVisibility));
  finally F.Free; end;
end;

procedure TTestConsecutiveVisibility.EmptyHeaderThenSame_NotReported;
// `private\n private\n  FX` ist `EmptyVisibilitySection` (SCA087),
// nicht ConsecutiveVisibility. Hier darf KEIN fkConsecutiveVisibility
// kommen - der erste `private` hat keine Member, also greift die
// "HadMembers"-Bedingung nicht.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveVisibility));
  finally F.Free; end;
end;

procedure TTestConsecutiveVisibility.ConsecutiveVisibility_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  'public procedure A;'#13#10 +
  'public procedure B;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkConsecutiveVisibility then
      begin
        Assert.AreEqual<TFindingKind>(fkConsecutiveVisibility, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                 Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkConsecutiveVisibility finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsecutiveVisibility);

end.
