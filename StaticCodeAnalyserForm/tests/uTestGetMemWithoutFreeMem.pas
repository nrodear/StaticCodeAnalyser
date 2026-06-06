unit uTestGetMemWithoutFreeMem;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGetMemWithoutFreeMem = class
  public
    [Test] procedure GetMemWithoutTryFinally_Reported;
    [Test] procedure AllocMemWithoutTryFinally_Reported;
    [Test] procedure GetMemInTryFinally_NotReported;
    [Test] procedure GetMemWithoutMatchingFreeMem_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGetMemWithoutFreeMem.GetMemWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  DoStuff(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGetMemWithoutFreeMem) >= 1);
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocMemWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: Pointer;'#13#10 +
  'begin'#13#10 +
  '  P := AllocMem(256);'#13#10 +
  '  ProcessBuffer(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGetMemWithoutFreeMem) >= 1);
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemInTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  try'#13#10 +
  '    DoStuff(P);'#13#10 +
  '  finally'#13#10 +
  '    FreeMem(P);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem));
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemWithoutMatchingFreeMem_NotReported;
// Wenn KEIN FreeMem im Lookahead-Fenster ist, skipt der Detector
// (Ownership-Transfer / Custom-Allocator).
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Pointer;'#13#10 +
  'begin'#13#10 +
  '  GetMem(Result, 1024);'#13#10 +
  '  // caller takes ownership and frees it later'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem));
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  DoStuff(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
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
      if Fnd.Kind = fkGetMemWithoutFreeMem then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkGetMemWithoutFreeMem finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGetMemWithoutFreeMem);

end.
