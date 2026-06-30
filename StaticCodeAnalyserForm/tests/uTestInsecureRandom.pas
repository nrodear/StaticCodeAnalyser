unit uTestInsecureRandom;

// Tests fuer TInsecureRandomDetector (SCA167).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInsecureRandom = class
  public
    [Test] procedure RandomWithoutRandomize_Reported;
    [Test] procedure RandomRangeWithoutRandomize_Reported;
    [Test] procedure RandomWithRandomize_NotReported;
    [Test] procedure QualifiedRandomize_AlsoCounts;
    [Test] procedure SelfDotRandomCall_StillReported;
    [Test] procedure ForeignObjectRandom_NoFinding;
    [Test] procedure BareRandomRange_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInsecureRandom.RandomWithoutRandomize_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Random(100) ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomRangeWithoutRandomize_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := RandomRange(1, 6);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'RandomRange ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomWithRandomize_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Init;'#13#10 +
  'begin'#13#10 +
  '  Randomize;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'Randomize-Aufruf irgendwo in der Unit unterdrueckt Findings');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.QualifiedRandomize_AlsoCounts;
// System.Randomize / Self.Randomize sollten ebenfalls zaehlen (Bare-Name-Strip).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Init;'#13#10 +
  'begin'#13#10 +
  '  System.Randomize;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'System.Randomize muss als Randomize zaehlen');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.SelfDotRandomCall_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Init;'#13#10 +
  'begin'#13#10 +
  '  i := Self.Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Self.Random muss als Random-Call zaehlen');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.ForeignObjectRandom_NoFinding;
// FP-Guard (2026-06-28/29): object-qualified Custom-RNG (FRng.Random) verwaltet
// einen EIGENEN Seed -> keine deterministische RTL-Random -> darf NICHT melden,
// auch wenn nirgends Randomize aufgerufen wird.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Roll;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := FRng.Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'FRng.Random ist Custom-RNG, kein InsecureRandom');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.BareRandomRange_StillReported;
// Unqualified RandomRange ohne Randomize bleibt globale RTL-Random -> Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Roll;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := RandomRange(1, 6);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'bare RandomRange ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInsecureRandom);

end.
