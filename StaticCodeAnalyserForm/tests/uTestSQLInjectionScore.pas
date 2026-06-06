unit uTestSQLInjectionScore;

// Tests fuer TSQLFixScorer - bewertet den Behebungsaufwand einer
// SQL-Injection in 5 Stufen (1=Trivial bis 5=Sehr schwer).
//
// Klassifikation:
//   Strukturell (FROM/JOIN/TABLE/+) -> Score 4 oder 5
//   Funktionsaufruf-Kontext (+()    -> Score 3
//   1 Wert-Plus                     -> Score 1
//   2-3 Wert-Plus                   -> Score 2
//   4+ Wert-Plus                    -> Score 3

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSQLInjectionScore = class
  public
    // ---- Schwierigkeits-Stufen ---------------------------------------------
    [Test] procedure SinglePlus_TrivialScore1;
    [Test] procedure TwoPluses_EasyScore2;
    [Test] procedure FourPluses_MediumScore3;
    [Test] procedure FunctionCallConcat_MediumScore3;
    [Test] procedure StructuralFrom_HardScore4;
    [Test] procedure StructuralWithManyPluses_VeryHardScore5;

    // ---- Metadaten + Format ------------------------------------------------
    [Test] procedure DifficultyLabel_TrivialEqualsString;
    [Test] procedure Reason_ContainsPlusCount;
    [Test] procedure Suggestion_NotEmptyForAnyScore;
    [Test] procedure FormatShort_ContainsScoreAndLabel;

    // ---- Boundary / Defensive ---------------------------------------------
    [Test] procedure ThreePluses_BoundaryEasyScore2;
    [Test] procedure EmptyRHS_DefensiveScore1;
  end;

implementation

uses
  System.SysUtils,
  uSQLInjectionScore;

procedure TTestSQLInjectionScore.SinglePlus_TrivialScore1;
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('SELECT * FROM users WHERE id = +UserId');
  Assert.AreEqual<Integer>(1, E.Score);
  Assert.AreEqual(Ord(fdTrivial), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.TwoPluses_EasyScore2;
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('SELECT * FROM users WHERE id = +UserId AND name = +UserName');
  Assert.AreEqual<Integer>(2, E.Score);
  Assert.AreEqual(Ord(fdEasy), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.FourPluses_MediumScore3;
// 4 Wert-Verkettungen ohne strukturellen Teil -> Score 3 (Mittel)
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate(
    'WHERE a = +A AND b = +B AND c = +C AND d = +D');
  Assert.AreEqual<Integer>(3, E.Score);
  Assert.AreEqual(Ord(fdMedium), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.FunctionCallConcat_MediumScore3;
// Funktionsaufruf in Verkettung -> automatisch Medium
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('WHERE id = +(GetCurrentUser)');
  Assert.AreEqual<Integer>(3, E.Score);
  Assert.AreEqual(Ord(fdMedium), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.StructuralFrom_HardScore4;
// Tabellenname dynamisch -> Hard (4)
var E: TFixEstimate;
begin
  // STRUCTURAL-Marker matchen `'from ''+'` (Parser-Repraesentation des
  // SQL-Strings inkl. Quote-Marker). Vgl. uSQLInjectionScore.HasStructuralConcat
  E := TSQLFixScorer.Estimate('SELECT * FROM ''+TableName');
  Assert.AreEqual<Integer>(4, E.Score);
  Assert.AreEqual(Ord(fdHard), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.StructuralWithManyPluses_VeryHardScore5;
// Struktureller Teil + viele Pluses (>2) -> Very Hard (5)
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate(
    'SELECT * FROM ''+Tbl WHERE a = +A AND b = +B AND c = +C');
  Assert.AreEqual<Integer>(5, E.Score);
  Assert.AreEqual(Ord(fdVeryHard), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.DifficultyLabel_TrivialEqualsString;
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('WHERE id = +UserId');
  Assert.AreEqual('Trivial', E.Label_);
end;

procedure TTestSQLInjectionScore.Reason_ContainsPlusCount;
// Reason muss bei multiplen Pluses die Zahl der Verkettungen erwaehnen.
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate(
    'WHERE a = +A AND b = +B AND c = +C');
  Assert.Contains(E.Reason, '3',
    'Reason muss die Plus-Count erwaehnen');
end;

procedure TTestSQLInjectionScore.Suggestion_NotEmptyForAnyScore;
// Egal welcher Score - es muss eine Handlungsempfehlung geben.
var
  E : TFixEstimate;
  Cases : array of string;
  S : string;
begin
  SetLength(Cases, 4);
  Cases[0] := 'WHERE id = +X';
  Cases[1] := 'WHERE a = +A AND b = +B';
  Cases[2] := 'SELECT * FROM ''+Tbl';
  Cases[3] := 'WHERE id = +(F)';
  for S in Cases do
  begin
    E := TSQLFixScorer.Estimate(S);
    Assert.IsTrue(E.Suggestion <> '',
      Format('Suggestion darf nie leer sein (Case: "%s")', [S]));
  end;
end;

procedure TTestSQLInjectionScore.FormatShort_ContainsScoreAndLabel;
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('WHERE id = +X');
  var Short := TSQLFixScorer.FormatShort(E);
  Assert.Contains(Short, '1/5',
    'FormatShort muss den Score enthalten');
  Assert.Contains(Short, 'Trivial',
    'FormatShort muss das Label enthalten');
end;

procedure TTestSQLInjectionScore.ThreePluses_BoundaryEasyScore2;
// Genau 3 Wert-Pluses sitzt am Rand der "Easy"-Klasse (2-3 pluses -> Score 2).
// Test fixiert das Boundary-Verhalten: bei 3 noch Score 2, ab 4 dann Score 3.
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate(
    'WHERE a = +A AND b = +B AND c = +C');
  Assert.AreEqual(2, E.Score,
    '3 Wert-Pluses ohne strukturellen Teil -> Score 2 (Boundary)');
  Assert.AreEqual(Ord(fdEasy), Ord(E.Difficulty));
end;

procedure TTestSQLInjectionScore.EmptyRHS_DefensiveScore1;
// Defensive-Pfad: leere RHS (sollte vom Caller eigentlich nie kommen),
// aber Scorer darf nicht crashen. Erwartet: Score 1, defensive Reason-Text.
var E: TFixEstimate;
begin
  E := TSQLFixScorer.Estimate('');
  Assert.AreEqual<Integer>(1, E.Score);
  Assert.AreEqual(Ord(fdTrivial), Ord(E.Difficulty));
  Assert.AreEqual('Trivial', E.Label_);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSQLInjectionScore);

end.
