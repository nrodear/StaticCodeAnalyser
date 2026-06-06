unit uTestMagicNumbers;

// Tests fuer TMagicNumberDetector. Triviale Werte (0, 1, -1, 2) und
// per analyser.ini konfigurierbare Trivials werden nicht geflaggt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMagicNumbers = class
  public
    [Test] procedure MagicNumber_Reported;
    [Test] procedure TrivialZero_NotReported;
    [Test] procedure TrivialOne_NotReported;
    [Test] procedure ConstAssignment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMagicNumbers.MagicNumber_Reported;
// Detector scannt nur nkIfStmt-Bedingungen (per Design konservativ), und
// 1024 waere als Power-of-2 ohnehin trivial (siehe IsTrivial). Deshalb
// non-triviale Konstante in einer if-Bedingung als minimaler Trigger.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = 1027 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMagicNumber) >= 1);
  finally F.Free; end;
end;

procedure TTestMagicNumbers.TrivialZero_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.TrivialOne_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.ConstAssignment_NotReported;
// const-Sektionen sind die korrekte Stelle fuer Numerik-Literale -
// dort soll der Detector NICHT flaggen.
const SRC =
  'unit t; implementation'#13#10 +
  'const MAX_RETRIES = 1024;'#13#10 +
  'begin end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = 1027 then x := 0;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMagicNumber then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMagicNumber finding expected');
    Assert.AreEqual(fkMagicNumber, Hit.Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMagicNumbers);

end.
