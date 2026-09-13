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
    // Voll-Review 2026-09-12 (Blocker): Inline-var-Statements sind
    // keine Sections.
    [Test] procedure TwoInlineVars_NoFinding;
    [Test] procedure SectionAcrossProcedure_NoFinding;
    [Test] procedure VarParamThenBodyVar_NoFinding;
    [Test] procedure MultiLineParamThenConsecutiveVar_Reported;
    [Test] procedure ConsecutiveSection_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 48): Kommentar-Fortsetzungszeilen
    [Test] procedure CommentContinuationVar_NoFinding;
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

procedure TTestConsecutiveSection.TwoInlineVars_NoFinding;
// Zwei Inline-vars (Delphi 10.3+) im selben Rumpf sind STATEMENTS -
// vor dem Fix meldete der zweite 'Consecutive var section', weil
// LastSection beliebige Identifier-Zeilen ueberlebt. Das ':='-Gate
// trennt Statement von Section; ':=' im String-Literal zaehlt nicht
// (geblankte Zeile).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  'var A := 1;'#13#10 +
  '  Nutze(A);'#13#10 +
  'var B := 2;'#13#10 +
  '  Nutze(B);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkConsecutiveSection),
    'Inline-var-Statements duerfen keine Section-Folge melden');
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

procedure TTestConsecutiveSection.VarParamThenBodyVar_NoFinding;
// FP-Regression (Real-World, Alcinoe): mehrzeilige Methoden-Signatur mit
// `const`/`var`-PARAMETERN am Zeilenanfang, dann eine Body-`var`-Section.
// Die Parameter-Modifier sind KEINE Sections -> kein "consecutive".
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo('#13#10 +
  '  const URL: string;'#13#10 +
  '  var Stop: Boolean);'#13#10 +
  'var'#13#10 +
  '  Node: Integer;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveSection),
    'const/var-Parameter sind keine Sections - keine consecutive-Meldung');
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.MultiLineParamThenConsecutiveVar_Reported;
// TP-Gegenkontrolle: nach derselben mehrzeiligen Param-Signatur ZWEI echte
// Body-`var`-Sections -> muss weiterhin als consecutive feuern.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo('#13#10 +
  '  const URL: string;'#13#10 +
  '  var Stop: Boolean);'#13#10 +
  'var'#13#10 +
  '  A: Integer;'#13#10 +
  'var'#13#10 +
  '  B: Integer;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConsecutiveSection),
    'echte konsekutive Body-var-Sections muessen weiter feuern');
  finally F.Free; end;
end;

procedure TTestConsecutiveSection.CommentContinuationVar_NoFinding;
// Voll-Review 2026-09-12 (Major 48): der Rohzeilen-Scan las die
// Fortsetzungszeile eines mehrzeiligen Blockkommentars als Code -
// das Wort 'var' im Kommentar setzte LastSection, und die naechste
// ECHTE var-Section wurde als 'Consecutive var section' gemeldet.
// Jetzt laeuft der Scan auf ScanCodeLine-bereinigten Zeilen
// (Kommentar-Zustand ueber Zeilen).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  A = 1;'#13#10 +
  '{ Hinweis:'#13#10 +
  '  var wurde hier frueher deklariert }'#13#10 +
  'var'#13#10 +
  '  B: Integer;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConsecutiveSection),
    'das var im Kommentar ist keine Section - kein Consecutive-Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsecutiveSection);

end.
