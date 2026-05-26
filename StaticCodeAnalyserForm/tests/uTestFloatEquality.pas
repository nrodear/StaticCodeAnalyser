unit uTestFloatEquality;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFloatEquality = class
  public
    [Test] procedure DoubleEquality_Reported;
    [Test] procedure DoubleInequality_Reported;
    [Test] procedure IntegerEquality_NotReported;
    [Test] procedure Assignment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    [Test] procedure StringEqualityWithFloatVarNameElsewhere_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFloatEquality.DoubleEquality_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Ratio: Double;'#13#10 +
  'begin'#13#10 +
  '  if Ratio = 0.5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1);
  finally F.Free; end;
end;

procedure TTestFloatEquality.DoubleInequality_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Single;'#13#10 +
  'begin'#13#10 +
  '  if X <> 0.0 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1);
  finally F.Free; end;
end;

procedure TTestFloatEquality.IntegerEquality_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var N: Integer;'#13#10 +
  'begin'#13#10 +
  '  if N = 5 then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkFloatEquality));
  finally F.Free; end;
end;

procedure TTestFloatEquality.Assignment_NotReported;
// `x := 0.5` darf NICHT als `x = 0.5`-Comparison erkannt werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Double;'#13#10 +
  'begin'#13#10 +
  '  X := 0.5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkFloatEquality));
  finally F.Free; end;
end;

procedure TTestFloatEquality.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var R: Double;'#13#10 +
  'begin'#13#10 +
  '  if R = 1.0 then Exit;'#13#10 +
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
      if Fnd.Kind = fkFloatEquality then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFloatEquality finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestFloatEquality.StringEqualityWithFloatVarNameElsewhere_NotReported;
// Regression: `aValue = ''` mit String-Var darf NICHT als Float-Equality
// kassiert werden, auch wenn an anderer Stelle im File `aValue: Double`
// als Param vorkommt (file-weite FloatVars).
// Frueher: String-Strip ersetzte '' durch Leerzeichen -> die Regex bridge
// uebersprang das und kassierte das naechste Token (Keyword `then`) als RHS.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(aValue: Double): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := aValue = 0.0;'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'var aValue: string;'#13#10 +
  'begin'#13#10 +
  '  if aValue = '''' then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : Integer;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    // Foo's Float-Vergleich bleibt erlaubt; Bar's String-Vergleich darf
    // KEINEN Treffer mehr produzieren.
    Hit := 0;
    for Fnd in F do
      if (Fnd.Kind = fkFloatEquality)
         and (Pos('then', Fnd.MissingVar) > 0) then
        Inc(Hit);
    Assert.AreEqual(0, Hit, 'String-Compare gegen Keyword darf nicht ' +
      'als Float-Equality kassiert werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFloatEquality);

end.
