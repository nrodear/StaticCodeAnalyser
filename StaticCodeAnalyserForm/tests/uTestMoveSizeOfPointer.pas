unit uTestMoveSizeOfPointer;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMoveSizeOfPointer = class
  public
    [Test] procedure MoveSizeOfPByte_Reported;
    [Test] procedure FillCharSizeOfPointer_Reported;
    [Test] procedure MoveSizeOfBuffer_NotReported;
    [Test] procedure MoveSizeOfNonPointerType_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure FillCharSizeOfSameRecordVar_NotReported;
    [Test] procedure FillCharSizeOfPointerTypeIntoBuffer_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMoveSizeOfPointer.MoveSizeOfPByte_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: array[0..255] of Byte; P: PByte;'#13#10 +
  'begin'#13#10 +
  '  Move(Buf[0], P^, SizeOf(PByte));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMoveSizeOfPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestMoveSizeOfPointer.FillCharSizeOfPointer_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PInteger;'#13#10 +
  'begin'#13#10 +
  '  FillChar(P^, SizeOf(PInteger), 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMoveSizeOfPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestMoveSizeOfPointer.MoveSizeOfBuffer_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: array[0..255] of Byte;'#13#10 +
  'begin'#13#10 +
  '  Move(Buf[0], Dest, SizeOf(Buf));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMoveSizeOfPointer));
  finally F.Free; end;
end;

procedure TTestMoveSizeOfPointer.MoveSizeOfNonPointerType_NotReported;
// SizeOf(TMyRecord) ist legitim - kein P-Prefix-Pattern -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var R: TMyRecord;'#13#10 +
  'begin'#13#10 +
  '  Move(R, Dest, SizeOf(TMyRecord));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMoveSizeOfPointer));
  finally F.Free; end;
end;

procedure TTestMoveSizeOfPointer.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  Move(Src, P^, SizeOf(PByte));'#13#10 +
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
      if Fnd.Kind = fkMoveSizeOfPointer then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMoveSizeOfPointer finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestMoveSizeOfPointer.FillCharSizeOfSameRecordVar_NotReported;
// Real-World-FP-Audit 2026-07-10 (Alcinoe.FMX.NativeView.Win.pas:311 u.a.):
// Params ist eine TCreateParams-RECORD-Variable; FillChar(Params, SizeOf(Params), 0)
// ist das kanonische Nullen-einer-Variable-Idiom - SizeOf(Params) liefert die volle
// Record-Groesse, kein Bug. Wegen (?i) matcht das Muster P[A-Z]\w+ zwar "Params", aber
// der Same-Identifier-Guard (SizeOf-Operand == erstes Call-Argument, ef3608e)
// unterdrueckt das Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Params: TCreateParams;'#13#10 +
  'begin'#13#10 +
  '  FillChar(Params, SizeOf(Params), 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMoveSizeOfPointer),
    'FillChar(Params,SizeOf(Params),0) zeroes the whole record - not a pointer-size bug');
  finally F.Free; end;
end;

procedure TTestMoveSizeOfPointer.FillCharSizeOfPointerTypeIntoBuffer_Reported;
// Must-stay TP: echter Bug - FillChar(Buf, SizeOf(PByte), 0) nullt nur die
// Pointer-Groesse (4/8 Byte) statt des Buffers. Buffer-Bezeichner (Buf) != SizeOf-
// Operand (PByte), keine '*'-Multiplikation, kein Built-in 'Pointer' -> keiner der
// drei neuen Guards greift; das Finding muss weiterhin feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: array[0..255] of Byte;'#13#10 +
  'begin'#13#10 +
  '  FillChar(Buf, SizeOf(PByte), 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMoveSizeOfPointer) >= 1,
    'FillChar(Buf,SizeOf(PByte),0) only zeroes pointer size - must still fire');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestMoveSizeOfPointer);

end.
