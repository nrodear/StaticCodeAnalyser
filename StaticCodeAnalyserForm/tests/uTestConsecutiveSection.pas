unit uTestConsecutiveSection;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsecutiveSection = class
  public
    [Test] procedure SingleSection_NoFinding;
    [Test] procedure ConstThenConst_Reported;
    [Test] procedure TypeThenType_Reported;
    [Test] procedure VarThenVar_Reported;
    [Test] procedure SectionAcrossProcedure_NoFinding;
    [Test] procedure ConsecutiveSection_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConsecutiveSection.SingleSection_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  A = 1;'#13#10 +
  '  B = 2;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveSection));
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.ConstThenConst_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  A = 1;'#13#10 +
  'const'#13#10 +
  '  B = 2;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConsecutiveSection));
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.TypeThenType_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = Integer;'#13#10 +
  'type'#13#10 +
  '  TBar = Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConsecutiveSection));
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.VarThenVar_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'var'#13#10 +
  '  A: Integer;'#13#10 +
  'var'#13#10 +
  '  B: Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConsecutiveSection));
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.SectionAcrossProcedure_NoFinding;
// `const` (Unit-Level), dann `procedure`, dann `const` innerhalb der
// Methode - LastSection wird durch `procedure` resettet, also kein
// Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  A = 1;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  B = 2;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveSection));
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.ConsecutiveSection_KindAndSeverity;
const SRC =
  'unit t; interface const A = 1; const B = 2; implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  // Da im Single-Line die Section-Keywords nicht am Zeilenstart sind,
  // wird hier kein Finding emittiert. Spezial-Test mit Multi-Line:
  F := TFindingHelper.FindingsOfFile(
    'unit t;'#13#10 +
    'interface'#13#10 +
    'const A = 1;'#13#10 +
    'const B = 2;'#13#10 +
    'implementation end.');
  try
    for Fnd in F do
      if Fnd.Kind = fkConsecutiveSection then
      begin
        Assert.AreEqual<TFindingKind>(fkConsecutiveSection, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,              Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkConsecutiveSection finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsecutiveSection);

end.
