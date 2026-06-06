unit uTestPointerName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPointerName = class
  public
    [Test] procedure PointerWithP_NoFinding;
    [Test] procedure PointerWithoutP_Reported;
    [Test] procedure NonPointerType_NoFinding;
    [Test] procedure PointerName_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPointerName.PointerWithP_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  PInteger = ^Integer;'#13#10 +
  '  PFoo = ^TFoo;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.PointerWithoutP_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TIntPtr = ^Integer;'#13#10 +     // <-- Pointer ohne P-Prefix
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.NonPointerType_NoFinding;
// Normaler Type-Alias ohne `^` - kein Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  '  TIntArray = array of Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.PointerName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TIntPtr = ^Integer;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkPointerName then
      begin
        Assert.AreEqual<TFindingKind>(fkPointerName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkPointerName finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerName);

end.
