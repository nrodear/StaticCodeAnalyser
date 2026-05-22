unit uTestPointerSubtraction;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPointerSubtraction = class
  public
    [Test] procedure CardinalSubtraction_Reported;
    [Test] procedure IntegerSubtraction_Reported;
    [Test] procedure PtrUIntSubtraction_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPointerSubtraction.CardinalSubtraction_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(P1, P2: Pointer);'#13#10 +
  'var d: Integer;'#13#10 +
  'begin'#13#10 +
  '  d := Cardinal(P1) - Cardinal(P2);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerSubtraction) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.IntegerSubtraction_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(P1, P2: Pointer);'#13#10 +
  'var d: Integer;'#13#10 +
  'begin'#13#10 +
  '  d := Integer(P1) - Integer(P2);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerSubtraction) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.PtrUIntSubtraction_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(P1, P2: Pointer);'#13#10 +
  'var d: NativeInt;'#13#10 +
  'begin'#13#10 +
  '  d := PtrUInt(P1) - PtrUInt(P2);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPointerSubtraction));
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(P1, P2: Pointer);'#13#10 +
  'var d: Integer;'#13#10 +
  'begin'#13#10 +
  '  d := Cardinal(P1) - Cardinal(P2);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkPointerSubtraction then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkPointerSubtraction finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerSubtraction);

end.
