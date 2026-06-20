unit uTestCognitiveComplexity;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCognitiveComplexity = class
  public
    [Test] procedure DeepNesting_Reported;
    [Test] procedure FlatMethod_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCognitiveComplexity.DeepNesting_Reported;
// 6 fach verschachtelt -> Cognitive 1+2+3+4+5+6 = 21, deutlich ueber 15.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c, d, e, f: Integer;'#13#10 +
  'begin'#13#10 +
  '  if a > 0 then'#13#10 +
  '    if b > 0 then'#13#10 +
  '      while c > 0 do'#13#10 +
  '        for d := 0 to 10 do'#13#10 +
  '          if d mod 2 = 0 then'#13#10 +
  '            if e > 0 then'#13#10 +
  '              DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCognitiveComplexity) >= 1,
      'Tief verschachtelte Methode muss CognitiveComplexity ausloesen');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.FlatMethod_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if a then DoA;'#13#10 +
  '  if b then DoB;'#13#10 +
  '  if c then DoC;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCognitiveComplexity),
      'Flache if-Sequenz bleibt unter dem Cognitive-Limit');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCognitiveComplexity);

end.
