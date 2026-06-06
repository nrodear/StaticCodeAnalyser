unit uTestFieldName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFieldName = class
  public
    [Test] procedure FPrefix_NoFinding;
    [Test] procedure NoFPrefix_Reported;
    [Test] procedure MethodInClass_NoFinding;
    [Test] procedure UnitLevelVar_NoFinding;
    [Test] procedure FieldName_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFieldName.FPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FCount: Integer;'#13#10 +
  '    FName: string;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.NoFPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.MethodInClass_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '    function GetX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.UnitLevelVar_NoFinding;
// Unit-level Variables sind keine Klassen-Felder.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'var'#13#10 +
  '  Counter: Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.FieldName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkFieldName then
      begin
        Assert.AreEqual<TFindingKind>(fkFieldName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFieldName finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFieldName);

end.
