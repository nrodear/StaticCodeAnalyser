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
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure NonPointerWordOperands_NotReported;
    [Test] procedure PointerLocalOperands_Reported;
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerSubtraction));
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


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestPointerSubtraction.NonPointerWordOperands_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Cmp: Integer;'#13#10 +
  'var C1, C2: Word;'#13#10 +
  'begin'#13#10 +
  '  C1 := 65; C2 := 66;'#13#10 +
  '  Result := Integer(C1) - Integer(C2);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerSubtraction),
    'Integer(C1)-Integer(C2) mit C1,C2: Word ist Ordinal-Zeichencode-Vergleich, kein 64-Bit-Pointer - keine Win64-Truncation (Operand-Typ-Gate FP-Audit 2026-07-10)');
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.PointerLocalOperands_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function ByteLen: Integer;'#13#10 +
  'var aEndPtr, aBasePtr: Pointer;'#13#10 +
  'begin'#13#10 +
  '  Result := Cardinal(aEndPtr) - Cardinal(aBasePtr);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerSubtraction) >= 1,
    'Cardinal(aEndPtr)-Cardinal(aBasePtr) mit Pointer-Locals trunkiert 64-Bit-Adressen auf Win64 - muss weiterhin feuern (kein TP-Verlust durch Operand-Typ-Gate)');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestPointerSubtraction);

end.
