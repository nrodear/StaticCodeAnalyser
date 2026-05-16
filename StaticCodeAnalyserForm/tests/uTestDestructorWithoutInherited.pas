unit uTestDestructorWithoutInherited;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDestructorWithoutInherited = class
  public
    [Test] procedure DtorWithInherited_NoFinding;
    [Test] procedure DtorWithoutInherited_Reported;
    [Test] procedure RegularProcedure_NoFinding;
    [Test] procedure DtorForwardDecl_NotReported;
    [Test] procedure DtorWithoutInherited_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDestructorWithoutInherited.DtorWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorWithoutInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.RegularProcedure_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorForwardDecl_NotReported;
// Regression: Forward-Deklaration im Class-Body (`destructor Destroy;
// override;`) ist keine Implementierung - der Detektor darf hier NICHT
// anschlagen. Echte Implementation steht spaeter im implementation-Teil.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorWithoutInherited_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkDestructorWithoutInherited then
      begin
        Assert.AreEqual<TFindingKind>(fkDestructorWithoutInherited, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsError,                     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkDestructorWithoutInherited finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDestructorWithoutInherited);

end.
