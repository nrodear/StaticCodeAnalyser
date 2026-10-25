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
    // Voll-Review 2026-09-12 (Major 72): Mehrfach-Deklarationen
    [Test] procedure MultiDecl_FirstIdentIsTarget_Reported;
    [Test] procedure MultiDecl_FirstIdentOperand_NoFinding;
    // Charge P 2026-10-25 (Tempo-Umbau, Verhalten identisch): Waechter
    // fuer die Typnamen-Vorpruefung und das (*SKIP) der Deklarations-Regex.
    [Test] procedure UpperCaseDecl_PrefilterStillReported;
    [Test] procedure QWordTarget_PrefilterStillReported;
    [Test] procedure MultiDecl_AcrossLines_Reported;
    [Test] procedure LongNumberTableBeforeDecl_Reported;
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

procedure TTestIntegerOverflow.MultiDecl_FirstIdentIsTarget_Reported;
// Voll-Review 2026-09-12 (Major 72, FN-Richtung): der alte Ein-Ident-
// Match registrierte aus 'Total, Sum: Int64' nur 'Sum' - 'Total' war
// kein Int64-Ziel und das Kernpattern blieb ungemeldet (Bestands-Exe:
// 0 Funde auf dieser Fixture, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Total, Sum: Int64;'#13#10 +
  '    SectorCount, SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  Total := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkIntegerOverflow),
    'auch der ERSTE Ident einer Mehrfach-Deklaration ist ein Int64-Ziel');
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.MultiDecl_FirstIdentOperand_NoFinding;
// FP-Richtung desselben Defekts: 'A' aus 'A, F: Int64' stand nicht in
// Int64Vars, das Operand-Promotion-Gate griff nicht - lsError-Fund
// 'cast one operand to Int64', obwohl der Compiler korrekt promoted
// (Bestands-Exe: 1 FP auf dieser Fixture, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var A, B: Int64;'#13#10 +
  '    R: Int64;'#13#10 +
  '    C: Integer;'#13#10 +
  'begin'#13#10 +
  '  R := A * C;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIntegerOverflow),
    'Int64-Operand aus Mehrfach-Deklaration promoted die Multiplikation');
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.UpperCaseDecl_PrefilterStillReported;
// Die Vorpruefung sucht 'nt64' im kleingeschriebenen Code - eine
// GROSS geschriebene Deklaration muss sie passieren wie bisher die
// (?i)-Regex.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var TOTAL: INT64;'#13#10 +
  '    SectorCount, SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  TOTAL := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkIntegerOverflow),
    'INT64 in Grossbuchstaben ist dieselbe Deklaration');
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.QWordTarget_PrefilterStillReported;
// Ohne 'nt64' im Text traegt nur der zweite Vorpruefungs-Zweig 'qword'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Total: QWord;'#13#10 +
  '    SectorCount, SectorSize: Cardinal;'#13#10 +
  'begin'#13#10 +
  '  Total := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkIntegerOverflow),
    'QWord-Ziel ohne Int64 im Text');
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.MultiDecl_AcrossLines_Reported;
// Die Ident-Liste darf ueber Zeilen laufen (\s faengt den Umbruch); das
// (*SKIP) setzt erst am Listenende an und verliert den ersten Ident nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  Total,'#13#10 +
  '  Sum: Int64;'#13#10 +
  '  SectorCount, SectorSize: Integer;'#13#10 +
  'begin'#13#10 +
  '  Total := SectorCount * SectorSize;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkIntegerOverflow),
    'Mehrfach-Deklaration ueber zwei Zeilen');
  finally F.Free; end;
end;

procedure TTestIntegerOverflow.LongNumberTableBeforeDecl_Reported;
// Der Laufzeit-Fall: eine lange Komma-Liste ohne ': Int64' (Zahlentabelle)
// direkt vor der echten Deklaration. Vorher quadratisch, mit (*SKIP)
// linear - die Deklaration dahinter wird weiter gefunden.
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('unit t; implementation'#13#10);
    SB.Append('const Tab: array[0..1999] of Integer = (');
    for i := 0 to 1999 do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(i);
    end;
    SB.Append(');'#13#10);
    SB.Append('procedure Foo;'#13#10 +
              'var Total, Sum: Int64;'#13#10 +
              '    SectorCount, SectorSize: Integer;'#13#10 +
              'begin'#13#10 +
              '  Total := SectorCount * SectorSize;'#13#10 +
              'end;');
    F := TFindingHelper.FindingsOfFile(SB.ToString);
  finally
    SB.Free;
  end;
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkIntegerOverflow),
    'Deklaration hinter einer langen Zahlentabelle');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIntegerOverflow);

end.
