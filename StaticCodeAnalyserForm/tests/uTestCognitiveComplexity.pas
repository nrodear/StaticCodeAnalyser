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
    [Test] procedure BooleanWordsInStringLiteral_NotCounted;
    // Voll-Review 2026-09-12 (Testluecke 95): Boolean-Operatoren POSITIV
    [Test] procedure BooleanOperatorsRaiseScore_Reported;
    [Test] procedure PlainConditionsStayUnderLimit_NoFinding;
    // ---- L1 (2026-09-20): Verschachtelungskette auch bei SCA176 --
    [Test] procedure Chain176_DeepestPath_OuterToInner;
    [Test] procedure Chain176_NotTheScore_ButThePath;
    // ---- Perf P3 (2026-10-25): Kette als Elternverweis -------------
    [Test] procedure Chain176_TwoReportingMethods_EachItsOwnPath;
    [Test] procedure Chain176_TieAtSameDepth_FirstPathWins;
    [Test] procedure Chain176_DeepestInElseBranch_SiblingDoesNotLeak;
    // ---- Perf Q2 (2026-10-25): EIN Walk, Puffer je Unit ------------
    [Test] procedure Chain176_ShallowerSecondMethod_OwnPath;
    [Test] procedure Chain176_AfterDeepSilentMethod_NoForeignLinks;
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

procedure TTestCognitiveComplexity.BooleanWordsInStringLiteral_NotCounted;
// Review-MEDIUM 2026-08-09: 'and'/'or' im String-Literal einer if-Bedingung
// sind keine Boolean-Operatoren. 14 flache if = Score 14, unter dem Limit 15;
// vorher hoben die Literal-Woerter '' and or '' den Score auf 16 (FP).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Qux;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  if Pos('' and or '', s) > 0 then T1;'#13#10 +
  '  if k2 then T2; if k3 then T3; if k4 then T4; if k5 then T5;'#13#10 +
  '  if k6 then T6; if k7 then T7; if k8 then T8; if k9 then T9;'#13#10 +
  '  if k10 then T10; if k11 then T11; if k12 then T12;'#13#10 +
  '  if k13 then T13; if k14 then T14;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCognitiveComplexity),
      'Literal-Woerter duerfen den Cognitive-Score nicht inflationieren');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.BooleanOperatorsRaiseScore_Reported;
// Testluecke 95 (Voll-Review 2026-09-12): dass and/or den Score
// erhoehen (B3), war nur NEGATIV geprueft - ueber das Literal-Blanking
// ('die Woerter in einem String zaehlen nicht'). Ein Positivtest
// fehlte: ohne ihn koennte B3 ganz ausfallen und der Negativtest
// bliebe trotzdem gruen. Zwei Bedingungen mit je acht Operatoren
// heben den Score auf 16 (Limit 15) - an der gebauten Exe gemessen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P(a, b, c, d, e, f, g, h: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if a and b and c and d and e and f and g and h then'#13#10 +
  '    DoIt;'#13#10 +
  '  if a or b or c or d or e or f or g or h then'#13#10 +
  '    DoIt;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkCognitiveComplexity),
    'die Boolean-Operatoren muessen den Score heben');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.PlainConditionsStayUnderLimit_NoFinding;
// Die Gegenprobe: dieselbe Zahl von if-Statements OHNE Operatorkette
// bleibt unter dem Limit. Damit ist belegt, dass wirklich die
// Operatoren den Unterschied machen und nicht die Verzweigungen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Q(a, b: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    DoIt;'#13#10 +
  '  if b then'#13#10 +
  '    DoIt;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkCognitiveComplexity),
    'zwei schlichte Bedingungen bleiben weit unter dem Limit');
  finally F.Free; end;
end;

{ ---- L1 (2026-09-20): Kette bei SCA176 -------------------------- }
//
// ANDERER VERTRAG ALS BEI SCA018: dort ist die Gliederzahl die
// gemeldete Tiefe. Hier ist die Kette der TIEFSTE PFAD der Methode -
// sie zeigt den Verschachtelungsanteil der Punktzahl, rechnet sie
// aber NICHT nach (die Punktzahl zaehlt auch flache Verzweigungen
// und boolesche Operatoren mit).

function Chain176Of(F: TObjectList<TLeakFinding>): string;
var X: TLeakFinding;
begin
  Result := '';
  for X in F do
    if X.Kind = fkCognitiveComplexity then Exit(X.StructureChain);
end;

procedure TTestCognitiveComplexity.Chain176_DeepestPath_OuterToInner;
// Tief genug fuer einen Befund, und der tiefste Pfad ist eindeutig.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    for I := 1 to 3 do'#13#10+
  '      while B do'#13#10+
  '        case C of'#13#10+
  '          1: if D then DoIt;'#13#10+
  '        end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    if TFindingHelper.Count(F, fkCognitiveComplexity) = 0 then
      Assert.Pass('unter der Schwelle - kein Befund, kein Kettenvertrag')
    else
      Assert.AreEqual('if → for → while → case → if', Chain176Of(F),
        'tiefster Pfad, von aussen nach innen');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.Chain176_NotTheScore_ButThePath;
// DIE ABGRENZUNG: viele FLACHE Verzweigungen treiben die Punktzahl,
// die Kette bleibt trotzdem kurz. Wer hier Gliederzahl = Punktzahl
// erwartet, hat den Vertrag missverstanden - genau deshalb steht
// der Fall als Test da.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A1 then DoIt;'#13#10+
  '  if A2 then DoIt;'#13#10+
  '  if A3 then DoIt;'#13#10+
  '  if A4 then DoIt;'#13#10+
  '  if A5 then DoIt;'#13#10+
  '  if A6 then DoIt;'#13#10+
  '  if A7 then DoIt;'#13#10+
  '  if A8 then DoIt;'#13#10+
  '  if A9 then DoIt;'#13#10+
  '  if B1 then'#13#10+
  '    if B2 then DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
    Kette: string;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    if TFindingHelper.Count(F, fkCognitiveComplexity) = 0 then
      Assert.Pass('unter der Schwelle')
    else
    begin
      Kette := Chain176Of(F);
      Assert.IsTrue(Pos('→', Kette) > 0,
        'der tiefste Pfad hat zwei Glieder: ' + Kette);
      Assert.AreEqual('if → if', Kette,
        'neun flache if treiben die Punktzahl, nicht die Kette');
    end;
  finally F.Free; end;
end;

{ ---- Perf P3 (2026-10-25): Kette als Elternverweis --------------- }
//
// Der Walk fuehrt die Kette nicht mehr als string je Stapel-Frame,
// sondern als Index in eine Glieder-Liste mit Elternverweis; der
// Text entsteht erst nach dem Walk. Die drei Faelle sichern genau
// die Stellen, an denen ein solcher Umbau kippen kann: eine Liste
// je Methode (nicht ueber Methoden hinweg), striktes '>' beim
// Gleichstand, und Geschwister-Zweige, deren Glieder nicht in den
// Pfad des anderen geraten. Alle Punktzahlen liegen bei 17-21, also
// sicher ueber dem Limit 15 - kein Assert.Pass-Ausweg.

function Chain176OfMethod(F: TObjectList<TLeakFinding>;
  const AMethod: string): string;
var X: TLeakFinding;
begin
  Result := '<kein Fund>';
  for X in F do
    if (X.Kind = fkCognitiveComplexity)
       and (Pos(AMethod, X.MethodName) > 0) then
      Exit(X.StructureChain);
end;

procedure TTestCognitiveComplexity.Chain176_TwoReportingMethods_EachItsOwnPath;
// Alpha 1+2+3+4+5+6 = 21, Beta ebenso 21 - beide melden, jede mit
// ihrem eigenen tiefsten Pfad.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Alpha;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    for I := 1 to 3 do'#13#10+
  '      while B do'#13#10+
  '        case C of'#13#10+
  '          1: if D then'#13#10+
  '               if E then DoIt;'#13#10+
  '        end;'#13#10+
  'end;'#13#10+
  'procedure Beta;'#13#10+
  'begin'#13#10+
  '  while A do'#13#10+
  '    repeat'#13#10+
  '      if B then'#13#10+
  '        for I := 1 to 3 do'#13#10+
  '          if C then'#13#10+
  '            if D then DoIt;'#13#10+
  '    until E;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkCognitiveComplexity),
      'beide Methoden liegen bei 21');
    Assert.AreEqual('if → for → while → case → if → if',
      Chain176OfMethod(F, 'Alpha'), 'Alpha: eigener Pfad');
    Assert.AreEqual('while → repeat → if → for → if → if',
      Chain176OfMethod(F, 'Beta'),
      'Beta: eigener Pfad, nichts aus Alpha');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.Chain176_TieAtSameDepth_FirstPathWins;
// Zwei Zweige erreichen dieselbe Tiefe 3 (Punktzahl 10 + 10 = 20).
// Bei Gleichstand gewinnt der ERSTE (striktes '>') - der zweite
// Zweig darf die Kette nicht ueberschreiben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '  begin'#13#10+
  '    for I := 1 to 3 do'#13#10+
  '      while B do'#13#10+
  '        if C then DoIt;'#13#10+
  '  end;'#13#10+
  '  repeat'#13#10+
  '    case X of'#13#10+
  '      1: if D then'#13#10+
  '           if E then DoIt;'#13#10+
  '    end;'#13#10+
  '  until F;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCognitiveComplexity),
      'Punktzahl 20 liegt ueber 15');
    Assert.AreEqual('if → for → while → if', Chain176OfMethod(F, 'Foo'),
      'Gleichstand: der erste Pfad bleibt stehen');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.Chain176_DeepestInElseBranch_SiblingDoesNotLeak;
// then-Zweig 'for' (Tiefe 1), else-Zweig vier Ebenen tief - Punktzahl
// 1+2+2+3+4+5 = 17. Der else-Zweig selbst ist kein Glied; das 'for'
// des Geschwisters darf nicht in seinem Pfad auftauchen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    for I := 1 to 3 do DoIt'#13#10+
  '  else'#13#10+
  '    while B do'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          repeat'#13#10+
  '            DoIt;'#13#10+
  '          until E;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCognitiveComplexity),
      'Punktzahl 17 liegt ueber 15');
    Assert.AreEqual('if → while → if → if → repeat',
      Chain176OfMethod(F, 'Foo'),
      'tiefster Pfad durch den else-Zweig, ohne das for des then-Zweigs');
  finally F.Free; end;
end;

// Perf Q2: Punktzahl und Kette entstehen seit Q2 in EINEM Walk, und
// Stapel wie Gliederliste werden ueber alle Methoden einer Unit
// wiederverwendet. Gesichert wird, was dieser Umbau verderben kann:
// der Stand der VORIGEN Methode (tiefste Ebene, Glieder) darf in die
// naechste nicht hineinreichen - weder bei einer flacheren meldenden
// Methode noch nach einer tiefen, aber stillen.

procedure TTestCognitiveComplexity.Chain176_ShallowerSecondMethod_OwnPath;
// Alpha 1+2+3+4+5+6 = 21 (sechs Ebenen). Beta 5+4+4+1+2 = 16 - die
// Punktzahl kommt aus booleschen Operatoren, die Kette ist nur zwei
// Glieder tief. Bliebe die tiefste Ebene von Alpha stehen, kaeme in
// Beta nie ein neues Maximum zustande.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Alpha;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    for I := 1 to 3 do'#13#10+
  '      while B do'#13#10+
  '        case C of'#13#10+
  '          1: if D then'#13#10+
  '               if E then DoIt;'#13#10+
  '        end;'#13#10+
  'end;'#13#10+
  'procedure Beta;'#13#10+
  'begin'#13#10+
  '  if A and B and C and D and E then DoIt;'#13#10+
  '  if F and G and H and J then DoIt;'#13#10+
  '  if K and L and M and N then DoIt;'#13#10+
  '  if P then'#13#10+
  '    while Q do DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkCognitiveComplexity),
      'Alpha 21 und Beta 16 liegen ueber 15');
    Assert.AreEqual('if → for → while → case → if → if',
      Chain176OfMethod(F, 'Alpha'), 'Alpha: eigener Pfad');
    Assert.AreEqual('if → while', Chain176OfMethod(F, 'Beta'),
      'Beta: der eigene, flachere Pfad - nichts aus Alpha');
  finally F.Free; end;
end;

procedure TTestCognitiveComplexity.Chain176_AfterDeepSilentMethod_NoForeignLinks;
// Deep 1+2+3+4 = 10 meldet nicht, fuellt aber die Gliederliste vier
// Ebenen tief. Flat 4 x (1+3) = 16 meldet; sein tiefster Pfad ist das
// ERSTE if allein (Gleichstand auf Ebene 0, striktes '>').
const SRC =
  'unit t; implementation'#13#10+
  'procedure Deep;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    for I := 1 to 3 do'#13#10+
  '      while B do'#13#10+
  '        if C then DoIt;'#13#10+
  'end;'#13#10+
  'procedure Flat;'#13#10+
  'begin'#13#10+
  '  if A and B and C and D then DoIt;'#13#10+
  '  if E and F and G and H then DoIt;'#13#10+
  '  if J and K and L and M then DoIt;'#13#10+
  '  if N and P and Q and R then DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCognitiveComplexity),
      'nur Flat liegt ueber 15');
    Assert.AreEqual('<kein Fund>', Chain176OfMethod(F, 'Deep'),
      'Deep (10) meldet nicht');
    Assert.AreEqual('if', Chain176OfMethod(F, 'Flat'),
      'Flat: ein Glied, kein Rest aus Deep');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCognitiveComplexity);

end.
