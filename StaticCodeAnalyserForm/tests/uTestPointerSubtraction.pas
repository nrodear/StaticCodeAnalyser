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
    // --- SCA161-enum Cross-Unit-Opt-in (2026-07-13, Parser nkEnumType) ---
    [Test] procedure EnumOperands_ViaPipeline_NotReported;
    [Test] procedure EnumOperands_NoContext_StillReported;
    [Test] procedure PointerOperands_ViaPipeline_StillReported;
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

procedure TTestPointerSubtraction.EnumOperands_ViaPipeline_NotReported;
// SCA161-enum: 'Integer(col1)-Integer(col2)' mit col1,col2 eines ENUM-Typs ist
// valide Ordinalarithmetik, keine Pointer-Adress-Trunkierung. Der Parser emittiert
// TColor jetzt als nkEnumType -> TTypeIndex TypeKindOf=tkiEnum -> Opt-in greift
// (nur im Pipeline-Weg, der den Index baut).
const SRC =
  'unit t; interface'#13#10 +
  'type TColor = (clRed, clGreen, clBlue);'#13#10 +
  'implementation'#13#10 +
  'function Cmp: Integer;'#13#10 +
  'var col1, col2: TColor;'#13#10 +
  'begin'#13#10 +
  '  col1 := clRed; col2 := clGreen;'#13#10 +
  '  Result := Integer(col1) - Integer(col2);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerSubtraction),
    'Enum-Operanden (TColor) -> TypeIndex tkiEnum -> Ordinalarithmetik -> kein SCA161');
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.EnumOperands_NoContext_StillReported;
// Gegenprobe: DIESELBE Enum-Quelle ueber FindingsOfFile (AContext=nil, kein
// TypeIndex) -> Opt-in inaktiv, TColor ist nicht in NONPTRTYPES -> bisheriges
// Verhalten (Fund bleibt). Belegt den nil-Index-Fallback = byte-identisch.
const SRC =
  'unit t; interface'#13#10 +
  'type TColor = (clRed, clGreen, clBlue);'#13#10 +
  'implementation'#13#10 +
  'function Cmp: Integer;'#13#10 +
  'var col1, col2: TColor;'#13#10 +
  'begin'#13#10 +
  '  Result := Integer(col1) - Integer(col2);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerSubtraction) >= 1,
    'ohne TypeIndex (AContext=nil) greift das Enum-Opt-in nicht -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestPointerSubtraction.PointerOperands_ViaPipeline_StillReported;
// TP-Gegenprobe: Pointer-Operanden bleiben auch MIT aktivem TypeIndex ein Fund
// (Pointer ist kein tkiEnum) - das Enum-Opt-in streut nicht ueber Nicht-Enums.
const SRC =
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  'function ByteLen: Integer;'#13#10 +
  'var aEndPtr, aBasePtr: Pointer;'#13#10 +
  'begin'#13#10 +
  '  Result := Cardinal(aEndPtr) - Cardinal(aBasePtr);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerSubtraction) >= 1,
    'Pointer-Operanden bleiben trotz TypeIndex ein SCA161-Fund (kein tkiEnum)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerSubtraction);

end.
