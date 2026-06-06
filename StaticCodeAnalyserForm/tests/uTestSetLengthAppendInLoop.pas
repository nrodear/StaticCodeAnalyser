unit uTestSetLengthAppendInLoop;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSetLengthAppendInLoop = class
  public
    [Test] procedure ForLoopWithGrow_Reported;
    [Test] procedure WhileLoopWithGrow_Reported;
    [Test] procedure SetLengthOnceBeforeLoop_NotReported;
    [Test] procedure SetLengthOnDifferentArray_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSetLengthAppendInLoop.ForLoopWithGrow_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '  begin'#13#10 +
  '    SetLength(Dest, Length(Dest) + 1);'#13#10 +
  '    Dest[High(Dest)] := i;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.WhileLoopWithGrow_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  while More do'#13#10 +
  '  begin'#13#10 +
  '    SetLength(Buf, Length(Buf) + 1);'#13#10 +
  '    Buf[High(Buf)] := NextByte;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.SetLengthOnceBeforeLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Count: Integer);'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  SetLength(Dest, Count);'#13#10 +
  '  for i := 0 to Count - 1 do'#13#10 +
  '    Dest[i] := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop));
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.SetLengthOnDifferentArray_NotReported;
// SetLength(A, Length(B) + 1) - Detector verlangt das gleiche Array
// auf beiden Seiten; sonst ist es kein Append-Pattern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; A, B: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    SetLength(A, Length(B) + 1);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop));
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    SetLength(Dest, Length(Dest) + 1);'#13#10 +
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
      if Fnd.Kind = fkSetLengthAppendInLoop then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkSetLengthAppendInLoop finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSetLengthAppendInLoop);

end.
