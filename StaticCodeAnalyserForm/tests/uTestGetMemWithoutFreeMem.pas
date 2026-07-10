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
    [Test] procedure GetMemIntoField_NoFinding;
    [Test] procedure GetMemLocalNoTry_StillReported;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World FP-Audit 2026-07-10: escape via Result / lowercase-Feld
    [Test] procedure AllocMemToResult_NoFinding;
    [Test] procedure AllocMemToLowercaseField_NoFinding;
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
      'genau 1 GetMem-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'GetMem(P, 1024'),
      TFindingHelper.FirstOf(F, fkGetMemWithoutFreeMem).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
      'genau 1 GetMem-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'AllocMem(256'),
      TFindingHelper.FirstOf(F, fkGetMemWithoutFreeMem).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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

procedure TTestGetMemWithoutFreeMem.GetMemIntoField_NoFinding;
// FP-Guard B (2026-06-29): erstes Argument ist ein FELD (FXxx-Konvention).
// Ownership liegt dann beim Objekt, FreeMem im Destruktor - ausserhalb des
// Single-Routine-Scopes dieses Detektors. Trotz fehlendem try/finally:
// kein Befund, weil das Ziel ein Feld FBuffer ist.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  GetMem(FBuffer, 1024);'#13#10 +
  '  DoStuff(FBuffer);'#13#10 +
  '  FreeMem(FBuffer);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'GetMem in ein Feld FXxx ist Objekt-Ownership -> kein Single-Routine-Leak');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemLocalNoTry_StillReported;
// Gegenprobe: lokale Variable (kleingeschrieben, kein F-Prefix, kein Feld),
// FreeMem ohne try/finally -> Leak bei Exception zwischen GetMem und FreeMem.
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkGetMemWithoutFreeMem) >= 1,
    'GetMem in lokale Var ohne try/finally bleibt ein Leak-Treffer');
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

procedure TTestGetMemWithoutFreeMem.AllocMemToResult_NoFinding;
// Real-World FP-Audit 2026-07-10 'returns-pointer': 'Result := AllocMem(...)' ist
// eine Allocator-Rueckgabe - der Buffer verlaesst die Routine, das (in einem
// SEPARATEN Dispose-Proc liegende) FreeMem ist kein lokaler Leak.
const SRC =
  'unit t; implementation'#13#10 +
  'function Alloc: Pointer;'#13#10 +
  'begin'#13#10 +
  '  Result := AllocMem(256);'#13#10 +
  'end;'#13#10 +
  'procedure DisposeIt(P: Pointer);'#13#10 +
  'begin'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'Result := AllocMem -> Buffer escaped, kein lokaler Leak');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocMemToLowercaseField_NoFinding;
// Real-World FP-Audit 2026-07-10 'field-lifetime': 'fBuf := AllocMem' (mORMot-
// Feld-Konvention lowercase f) im Ctor, FreeMem im Dtor - RAII-Feld-Lifetime.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  fBuf := AllocMem(256);'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeMem(fBuf);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'fBuf := AllocMem -> Feld-Lifetime (RAII), kein lokaler Leak');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGetMemWithoutFreeMem);

end.
