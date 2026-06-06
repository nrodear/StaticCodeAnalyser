unit uTestEmptyVisibilitySection;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyVisibilitySection = class
  public
    [Test] procedure FilledSections_NoFinding;
    [Test] procedure EmptyPublicBeforePrivate_Reported;
    [Test] procedure EmptyAtClassEnd_Reported;
    [Test] procedure EmptyVisibilitySection_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyVisibilitySection.FilledSections_NoFinding;
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyPublicBeforePrivate_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyAtClassEnd_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyVisibilitySection_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '  private FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyVisibilitySection then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyVisibilitySection, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyVisibilitySection finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyVisibilitySection);

end.
