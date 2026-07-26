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
    // 'else if'-Korrektur 2026-07-26 (Metrik-Verfaelschung, quadratischer Score)
    [Test] procedure ElseIfChain_ScoresLinear;
    [Test] procedure ElseIfChain5_StaysUnderLimit;
    [Test] procedure NestedIfs_KeepNestingPenalty;
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

procedure TTestCognitiveComplexity.ElseIfChain_ScoresLinear;
// Regressions-Anker fuer die 'else if'-Korrektur (2026-07-26).
//
// Der Parser haengt den else-Zweig als nkElseBranch UNTER das nkIfStmt
// (uParser2.ParseIfStmt). nkElseBranch zaehlt selbst nicht, reichte aber
// die vom umgebenden if bereits ERHOEHTE Tiefe an sein Kind weiter - ein
// 'else if' galt dadurch als verschachteltes if.
//
// Herleitung fuer die Kette unten (1 fuehrendes if + 19 else-if = 20 if):
//   VORHER (quadratisch): Tiefen 0,1,2,...,19
//     Summe (1 + Tiefe) = 20 + (0+1+...+19) = 20 + 190 = 210
//     (allgemein N*(N+1)/2 - fuer uUnusedUses.pas:139 mit 121 else-if
//      ergab das 7575 statt ~194)
//   NACHHER (Sonar: 'else if' = +1 OHNE Nesting-Zuschlag): alle 20 if
//     liegen auf Level 0 -> Summe = 20 * (1 + 0) = 20
//
// 20 liegt ueber dem Limit 15, der Fund existiert also weiterhin - nur
// mit dem korrekten Wert. Der Assert prueft den Wert exakt (inklusive
// des folgenden ' (limit'), damit '20' nicht versehentlich als Praefix
// von '210' durchgeht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: Integer;'#13#10 +
  'begin'#13#10 +
  '  if a = 1 then DoS1'#13#10 +
  '  else if a = 2 then DoS2'#13#10 +
  '  else if a = 3 then DoS3'#13#10 +
  '  else if a = 4 then DoS4'#13#10 +
  '  else if a = 5 then DoS5'#13#10 +
  '  else if a = 6 then DoS6'#13#10 +
  '  else if a = 7 then DoS7'#13#10 +
  '  else if a = 8 then DoS8'#13#10 +
  '  else if a = 9 then DoS9'#13#10 +
  '  else if a = 10 then DoS10'#13#10 +
  '  else if a = 11 then DoS11'#13#10 +
  '  else if a = 12 then DoS12'#13#10 +
  '  else if a = 13 then DoS13'#13#10 +
  '  else if a = 14 then DoS14'#13#10 +
  '  else if a = 15 then DoS15'#13#10 +
  '  else if a = 16 then DoS16'#13#10 +
  '  else if a = 17 then DoS17'#13#10 +
  '  else if a = 18 then DoS18'#13#10 +
  '  else if a = 19 then DoS19'#13#10 +
  '  else if a = 20 then DoS20;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkCognitiveComplexity);
    Assert.IsNotNull(Hit,
      'Kette aus 20 if kostet 20 und liegt damit ueber dem Limit 15');
    Assert.IsTrue(Pos('complexity 20 (limit', Hit.MissingVar) > 0,
      'Flache else-if-Kette muss linear scoren (20), nicht quadratisch ' +
      '(210) - gemeldet wurde: ' + Hit.MissingVar);
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.ElseIfChain5_StaysUnderLimit;
// Sonar-Lehrbuchfall: eine else-if-Kette der Laenge 5 kostet 5
// (5 * (1 + 0) = 5) und bleibt damit klar unter dem Limit 15.
// Vor der Korrektur waren es 1+2+3+4+5 = 15 - ebenfalls nicht ueber 15,
// deshalb ist dieser Test allein NICHT unterscheidungsfaehig; er haelt
// den Lehrbuchfall fest und wirkt als ADD-Riegel (jede kuenftige
// Zaehl-Erweiterung, die diese Kette ueber 15 hebt, faellt hier auf).
// Der eigentliche Regressions-Anker ist ElseIfChain_ScoresLinear.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: Integer;'#13#10 +
  'begin'#13#10 +
  '  if a = 1 then DoS1'#13#10 +
  '  else if a = 2 then DoS2'#13#10 +
  '  else if a = 3 then DoS3'#13#10 +
  '  else if a = 4 then DoS4'#13#10 +
  '  else if a = 5 then DoS5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCognitiveComplexity),
      'else-if-Kette der Laenge 5 kostet 5 und bleibt unter dem Limit');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.NestedIfs_KeepNestingPenalty;
// Gegenprobe zur 'else if'-Korrektur: ECHTE Verschachtelung behaelt
// ihren Nesting-Zuschlag unveraendert.
// 6 ineinander liegende if -> Tiefen 0..5 -> Summe (1 + Tiefe)
//   = 1+2+3+4+5+6 = 21 (vor UND nach der Korrektur identisch, weil hier
//   kein nkElseBranch im Spiel ist).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c, d, e, f: Integer;'#13#10 +
  'begin'#13#10 +
  '  if a > 0 then'#13#10 +
  '    if b > 0 then'#13#10 +
  '      if c > 0 then'#13#10 +
  '        if d > 0 then'#13#10 +
  '          if e > 0 then'#13#10 +
  '            if f > 0 then'#13#10 +
  '              DoStuff;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkCognitiveComplexity);
    Assert.IsNotNull(Hit, 'Sechsfach verschachteltes if muss melden');
    Assert.IsTrue(Pos('complexity 21 (limit', Hit.MissingVar) > 0,
      'Echte Verschachtelung behaelt den Nesting-Zuschlag (21) - ' +
      'gemeldet wurde: ' + Hit.MissingVar);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCognitiveComplexity);

end.
