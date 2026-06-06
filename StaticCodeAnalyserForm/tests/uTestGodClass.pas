unit uTestGodClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGodClass = class
  public
    [Test] procedure ManyMethods_Reported;
    [Test] procedure ManyFields_Reported;
    [Test] procedure SmallClass_NotReported;
    [Test] procedure AbstractClass_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGodClass.ManyMethods_Reported;
// 25 Methoden in einer Klasse > MAX_METHODS = 20.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.ManyFields_Reported;
// 20 Felder > MAX_FIELDS = 15.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFatRecord = class');
    for i := 1 to 20 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.SmallClass_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FA: Integer;'#13#10 +
  '    FB: Integer;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
  finally F.Free; end;
end;

procedure TTestGodClass.AbstractClass_NotReported;
// `class abstract` ist Designintent - selbst mit vielen Methoden kein
// Refactoring-Bedarf.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFramework = class abstract');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d; virtual; abstract;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkGodClass then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkGodClass finding expected');
      Assert.AreEqual(fkGodClass, Hit.Kind);
      Assert.AreEqual(lsWarning,  Hit.Severity);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGodClass);

end.
