unit uTestPublicField;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPublicField = class
  public
    [Test] procedure PrivateFieldOnly_NoFinding;
    [Test] procedure PublicField_Reported;
    [Test] procedure PublicMethod_NoFinding;
    [Test] procedure PublicProperty_NoFinding;
    [Test] procedure PublicField_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPublicField.PrivateFieldOnly_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicField_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    Count: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicMethod_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicProperty_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Count: Integer read FCount;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicField_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  'public'#13#10 +
  '  Count: Integer;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkPublicField then
      begin
        Assert.AreEqual<TFindingKind>(fkPublicField, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkPublicField finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPublicField);

end.
