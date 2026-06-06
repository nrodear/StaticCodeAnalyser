unit uTestDigitGrouping;

// Tests fuer TDigitGroupingDetector (file-scan: int-Literale >= 5 digits
// ohne `_` Trennung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDigitGrouping = class
  public
    [Test] procedure SmallNumber_NoFinding;
    [Test] procedure ExactlyFourDigits_NoFinding;
    [Test] procedure FiveDigits_Reported;
    [Test] procedure GroupedNumber_NoFinding;
    [Test] procedure HexLiteral_NotReported;
    [Test] procedure FloatLiteral_NotReported;
    [Test] procedure IdentifierWithDigits_NotReported;
    [Test] procedure NumberInString_NotReported;
    [Test] procedure NumberInComment_NotReported;
    [Test] procedure DigitGrouping_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDigitGrouping.SmallNumber_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'const X = 42; Y = 1000; Z = 9999;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.ExactlyFourDigits_NoFinding;
// 4 Ziffern: noch nicht meldepflichtig (Schwelle = 5).
const SRC =
  'unit t; implementation'#13#10 +
  'const TIMEOUT = 9999;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.FiveDigits_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'const TIMEOUT = 86400;'#13#10;     // 5 Ziffern -> Treffer
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.GroupedNumber_NoFinding;
// Mit `_`-Trennzeichen: kein Treffer, das ist ja die Konvention.
const SRC =
  'unit t; implementation'#13#10 +
  'const TIMEOUT = 1_800_000;'#13#10 +
  '      MAX_BYTES = 10_485_760;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.HexLiteral_NotReported;
// Hex-Literale (`$DEADBEEF`) folgen anderer Konvention - nicht melden.
const SRC =
  'unit t; implementation'#13#10 +
  'const MASK = $FFFFFFFF;'#13#10 +
  '      MAGIC = $DEADBEEF;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.FloatLiteral_NotReported;
// Floats werden vom Mantissen-/Exponent-Skip ausgenommen.
const SRC =
  'unit t; implementation'#13#10 +
  'const PI_LONG = 3.1415926535;'#13#10 +
  '      AVOGADRO = 6.022e23;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.IdentifierWithDigits_NotReported;
// `Var123456`: identifier mit Ziffern - kein numerisches Literal.
const SRC =
  'unit t; implementation'#13#10 +
  'var Var123456: Integer; Item99999: TObject;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.NumberInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin WriteLn(''86400 seconds in a day''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.NumberInComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '// timeout 86400 seconds = 1 day'#13#10 +
  '{ Max 99999 entries }'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDigitGrouping));
  finally F.Free; end;
end;

procedure TTestDigitGrouping.DigitGrouping_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'const T = 1000000;'#13#10;
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkDigitGrouping then
      begin
        Assert.AreEqual<TFindingKind>(fkDigitGrouping, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkDigitGrouping finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDigitGrouping);

end.
