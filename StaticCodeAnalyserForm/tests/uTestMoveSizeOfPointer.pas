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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMoveSizeOfPointer));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMoveSizeOfPointer));
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

initialization
  TDUnitX.RegisterTestFixture(TTestMoveSizeOfPointer);

end.
