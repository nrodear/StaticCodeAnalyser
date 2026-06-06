unit uTestMissingOverride;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingOverride = class
  public
    [Test] procedure MissingOverride_Reported;
    [Test] procedure WithOverride_NotReported;
    [Test] procedure WithReintroduce_NotReported;
    [Test] procedure NonVirtualParent_NotReported;
    [Test] procedure CrossUnitParent_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingOverride.MissingOverride_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingOverride) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingOverride.WithOverride_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork; override;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.WithReintroduce_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork; reintroduce;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.NonVirtualParent_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.CrossUnitParent_NotReported;
// Parent in anderer Unit (TForm) - Detektor erkennt es nicht, KEIN Finding.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TMyForm = class(TForm)'#13#10 +
  '    procedure Paint;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
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
      if Fnd.Kind = fkMissingOverride then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingOverride finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingOverride);

end.
