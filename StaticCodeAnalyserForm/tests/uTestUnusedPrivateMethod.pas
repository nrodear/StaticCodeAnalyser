unit uTestUnusedPrivateMethod;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedPrivateMethod = class
  public
    [Test] procedure UnusedPrivate_Reported;
    [Test] procedure UsedPrivate_NotReported;
    [Test] procedure PublicMethod_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedPrivateMethod.UnusedPrivate_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UnusedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UnusedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPrivateMethod) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.UsedPrivate_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UsedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UsedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin UsedHelper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.PublicMethod_NotReported;
// Public-Methoden werden NICHT von diesem Detector geprueft - die koennen
// von anderen Units verwendet werden.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure PublicMaybeUnused;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.PublicMaybeUnused;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure Dead;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Dead;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedPrivateMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnusedPrivateMethod finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedPrivateMethod);

end.
