unit uTestConstructorWithoutInherited;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstructorWithoutInherited = class
  public
    [Test] procedure CtorWithInherited_NoFinding;
    [Test] procedure CtorWithoutInherited_Reported;
    [Test] procedure RegularProcedure_NoFinding;
    [Test] procedure CtorForwardDecl_NotReported;
    [Test] procedure CtorWithoutInherited_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstructorWithoutInherited.CtorWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorWithoutInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.RegularProcedure_NoFinding;
// Eine normale Methode ohne `inherited` ist KEIN Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorForwardDecl_NotReported;
// Regression: Forward-Deklaration im Class-Body (`constructor Create;`)
// hat keinen Body und darf NICHT als "fehlendes inherited" gemeldet
// werden. Implementation steht im implementation-Teil.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorWithoutInherited_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkConstructorWithoutInherited then
      begin
        Assert.AreEqual<TFindingKind>(fkConstructorWithoutInherited, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,                    Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkConstructorWithoutInherited finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstructorWithoutInherited);

end.
