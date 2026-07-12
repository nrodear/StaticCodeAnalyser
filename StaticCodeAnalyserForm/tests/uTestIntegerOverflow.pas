unit uTestIntegerOverflow;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIntegerOverflow = class
  public
    [Test] procedure Int64Mul_TwoIntegers_Reported;
    [Test] procedure Int64Mul_OneIs64BitVar_NoFinding;
    [Test] procedure Int64Mul_Literal_NoFinding;
    [Test] procedure IntegerTarget_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World-FP-Audit 2026-07-12, FP-Klasse 'scope-blinde file-globale
    // Var-Sammlung': ein 'var result: Int64'-Parameter einer fremden Prozedur
    // darf 'result' in einer double-Routine NICHT zum Int64-Ziel machen.
    [Test] procedure Int64Mul_ForeignParamResult_NoFinding;
    // TP-Gegenprobe: trotz fremdem 'var result: Int64'-Parameter bleibt ein
    // echter lokaler Int64-Ziel-Fund erhalten.
    [Test] procedure Int64Mul_ForeignParamPresent_LocalTargetStillReported;
    // TP-Gegenprobe: Felder (file-level, ausserhalb jeder Routine deklariert)
    // bleiben gueltige Int64-Ziele.
    [Test] procedure Int64Mul_FieldTarget_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestIntegerOverflow.Int64Mul_TwoIntegers_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  SectorCount: Integer;'#13#10 +
  '  SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIntegerOverflow) >= 1);
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Int64Mul_OneIs64BitVar_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  SectorCount: Int64;'#13#10 +
  '  SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Int64Mul_Literal_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  N: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := N * 1024;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.IntegerTarget_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  Total: Integer;'#13#10 +
  '  A, B: Integer;'#13#10 +
  'begin'#13#10 +
  '  Total := A * B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  R: Int64;'#13#10 +
  '  A: Integer;'#13#10 +
  '  B: Integer;'#13#10 +
  'begin'#13#10 +
  '  R := A * B;'#13#10 +
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
      if Fnd.Kind = fkIntegerOverflow then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkIntegerOverflow finding expected');
    Assert.AreEqual(fkIntegerOverflow, Hit.Kind);
    Assert.AreEqual(lsError,           Hit.Severity);
  finally F.Free; end;
end;

// Real-World-FP-Audit 2026-07-12, FP-Klasse 'scope-blinde file-globale
// Var-Sammlung': Frueher sammelte der Detektor 'result' file-GLOBAL aus dem
// 'var result: Int64'-PARAMETER von SetInt64/SetQWord und wandte das auf ein
// 'result' in einer voellig anderen Routine an, wo 'result' der double-Return
// ist (TLecuyer.NextDouble). COEFF32 ist double -> Gleitkomma-Multiplikation,
// kein 32-Bit-Overflow. Per-Method-Scope: der Parameter aus SetInt64 darf die
// Klassifikation in NextDouble NICHT beeinflussen -> 0 Funde.
procedure TTestIntegerOverflow.Int64Mul_ForeignParamResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetInt64(P: PChar; var result: Int64);'#13#10 +
  'begin'#13#10 +
  '  result := 0;'#13#10 +
  'end;'#13#10 +
  'function NextDouble: double;'#13#10 +
  'const'#13#10 +
  '  COEFF32: double = 0.5;'#13#10 +
  'var'#13#10 +
  '  Next: Cardinal;'#13#10 +
  'begin'#13#10 +
  '  Next := 7;'#13#10 +
  '  result := Next * COEFF32;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow));
  finally F.Free; end;
end;

// TP-Gegenprobe zur obigen FP: derselbe fremde 'var result: Int64'-Parameter
// existiert, aber eine ANDERE Routine hat ein echtes lokales Int64-Ziel
// (BytesTotal := SectorCount * SectorSize). Das Scoping darf diesen echten
// Fund NICHT unterdruecken.
procedure TTestIntegerOverflow.Int64Mul_ForeignParamPresent_LocalTargetStillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetInt64(P: PChar; var result: Int64);'#13#10 +
  'begin'#13#10 +
  '  result := 0;'#13#10 +
  'end;'#13#10 +
  'procedure Compute;'#13#10 +
  'var'#13#10 +
  '  BytesTotal: Int64;'#13#10 +
  '  SectorCount: Integer;'#13#10 +
  '  SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  BytesTotal := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIntegerOverflow) >= 1);
  finally F.Free; end;
end;

// TP-Gegenprobe: ein Klassenfeld (file-level, ausserhalb jeder Routine
// deklariert) ist ein gueltiges Int64-Ziel und muss - trotz Per-Method-Scope
// der lokalen Vars - weiterhin gefunden werden (real-world: mORMot
// fEngineExpireTimeOutTix := Value * MilliSecsPerMin).
procedure TTestIntegerOverflow.Int64Mul_FieldTarget_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    fTix: Int64;'#13#10 +
  '    procedure SetMin(Value: Cardinal);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.SetMin(Value: Cardinal);'#13#10 +
  'var'#13#10 +
  '  Factor: Integer;'#13#10 +
  'begin'#13#10 +
  '  Factor := 60000;'#13#10 +
  '  fTix := Value * Factor;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIntegerOverflow) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIntegerOverflow);

end.
