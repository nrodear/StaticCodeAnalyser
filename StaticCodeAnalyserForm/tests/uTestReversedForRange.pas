unit uTestReversedForRange;

// Tests fuer den TReversedForRangeDetector (file-basiert).
//
// Erkennt `for i := A to B do` mit A > B (beide literal-numerisch).
// `downto` ist OK. Identifier-Grenzen (High(Arr) usw.) werden nicht
// gematcht - der Parser haengt die Range-Expression nicht strukturell
// im AST ab, deshalb konservativ nur Numeric-Literal-Bounds.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestReversedForRange = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure Reversed_TenToOne_Reported;
    [Test] procedure Reversed_LargeRange_Reported;
    [Test] procedure Reversed_NegativeNumbers_Reported;
    [Test] procedure Reversed_InlineVarSyntax_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure Forward_OneToTen_NoFinding;
    [Test] procedure Downto_TenToOne_NoFinding;
    [Test] procedure FromEqualsTo_ZeroIter_NoFinding;
    [Test] procedure NonLiteralBound_HighArr_NoFinding;
    [Test] procedure InString_NotDetected;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Reversed_Finding_KindAndSeverity;
    [Test] procedure Reversed_MultipleHitsInSameMethod_AllReported;
    // Voll-Review 2026-09-12 (Blocker): do am Zeilenende war blind
    [Test] procedure Reversed_DoAtLineEnd_Reported;
    // Posten 271: Tabulator als Trennzeichen
    [Test] procedure Reversed_TabBetweenTokens_Reported;
    // Posten 270: der Exit liess den Kommentar-Zustand fallen
    [Test] procedure CommentOpenedAfterMatch_NoSecondFinding;
    [Test] procedure TwoViolationsOnOneLine_OnlyFirstReported;
    [Test] procedure TwoViolationsOnTwoLines_BothReported;
    // Paket 9008: der Vorfilter verlangte das Wort der korrekten Form
    [Test] procedure PrefilterDoesNotRequireDownto_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 270+271: Tabulatoren und der verlorene Kommentar ----- }
//
// ZWEI Defekte in ScanLine, beide an der gebauten Exe gemessen.
//
// MESSHINWEIS, weil er sonst Zeit kostet: die Regel hat im CLI-Pfad
// einen Vorfilter. Er stand bis Paket 9008 auf 'downto' - dem Wort der
// KORREKTEN Form - und blendete damit 91,2 % der .pas-Dateien aus;
// seither steht er auf 'for '. Der TEST-Harness FindingsOfFile ruft den
// Detektor direkt und kennt keinen Vorfilter, deshalb brauchen die
// Fixturen hier nichts davon. Wer einen Fall von Hand an der Exe
// nachmisst, braucht ein 'for ' in der Datei - sonst misst er 0 und
// haelt das fuer den Befund.

{ --- Paket 9008: der Vorfilter war INVERTIERT ------------------- }
//
// Der Vorfilter verlangte das Wort der KORREKTEN Form. Die Regel
// sucht aber den Fall, in dem jemand genau dieses Wort VERGESSEN
// hat - wer es vergisst, hat es womoeglich nirgends im File
// stehen. 12.244 von 13.419 .pas-Dateien waren damit blind (91,2 %).
//
// Nur die volle Pipeline sieht den Vorfilter; FindingsOfFile ruft
// den Detektor direkt und meldet auch heute schon.

procedure TTestReversedForRange.PrefilterDoesNotRequireDownto_Reported;
// Eine Datei OHNE das Wort der korrekten Form - und genau
// darum ging es. Vorher gemessen: 0. Nachher: 1.
//
// Am Korpus bringt der Fix nichts: in 13.419 Dateien gibt
// es keine einzige Schleife dieser Form. Der stille
// Nullzeilen-Bug kommt hier schlicht nicht vor - die
// Blindheit war trotzdem real.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do'#13#10 +
  '    Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkReversedForRange),
      'eine Zaehlschleife muss auch ohne das Wort downto gescannt werden');
  finally F.Free; end;
end;


procedure TTestReversedForRange.Reversed_TabBetweenTokens_Reported;
// POSTEN 271: die acht Trenner-Skips akzeptierten nur das Leerzeichen.
// Ein einziger Tabulator hinter dem for liess den Match ausfallen.
// An der Exe gemessen: heute 0 Funde, nach dem Fix 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for'#9'i := 10 to 1 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkReversedForRange),
      'ein Tabulator zwischen den Token ist ein Trenner wie das Blank');
  finally F.Free; end;
end;

procedure TTestReversedForRange.CommentOpenedAfterMatch_NoSecondFinding;
// POSTEN 270, der eigentliche Defekt: nach einem Treffer stieg ScanLine
// per Exit aus und liess ein DAHINTER geoeffnetes Blockkommentar-Zeichen
// unbemerkt. Der Caller hielt die Folgezeilen fuer Code und meldete das
// auskommentierte for gleich mit - ein FP im Error-Tier.
// An der Exe gemessen: heute 2 Funde, nach dem Fix 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i);  {'#13#10 +
  '    for i := 10 to 1 do Bar(i);'#13#10 +
  '  }'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkReversedForRange),
      'das for im Blockkommentar ist kein Code');
  finally F.Free; end;
end;

procedure TTestReversedForRange.TwoViolationsOnOneLine_OnlyFirstReported;
// POSTEN 270, die dokumentierte GRENZE: je Zeile ein Fund. Der
// Kopfkommentar versprach frueher alle. Der Waechter haelt die Grenze
// fest - und die Nachbarprobe (dieselben zwei Verstoesse auf ZWEI
// Zeilen) liefert 2, damit sichtbar bleibt, dass es an der Zeile haengt.
// An der Exe gemessen: heute 1, nach dem Fix 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i); for j := 9 to 2 do Bar(j);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkReversedForRange),
      'BEKANNTE GRENZE: der Detektor meldet je Zeile den ersten Verstoss');
  finally F.Free; end;
end;

procedure TTestReversedForRange.TwoViolationsOnTwoLines_BothReported;
// Die Nachbarprobe zur Grenze oben. Heute wie nachher 2.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i);'#13#10 +
  '  for j := 9 to 2 do Bar(j);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(2,
      TFindingHelper.Count(F, fkReversedForRange),
      'auf zwei Zeilen sind es zwei Funde');
  finally F.Free; end;
end;


procedure TTestReversedForRange.Reversed_TenToOne_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_LargeRange_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 1000 to 500 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_NegativeNumbers_Reported;
// -5 > -10 -> Reversed
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := -5 to -10 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_InlineVarSyntax_Reported;
// `for var i: Integer := 10 to 1 do` - Delphi 10.3+ Inline-Var Syntax
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  for var i: Integer := 10 to 1 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Forward_OneToTen_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to 10 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Downto_TenToOne_NoFinding;
// `downto` ist explizit korrekt - kein Befund
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 downto 1 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.FromEqualsTo_ZeroIter_NoFinding;
// `for i := 5 to 5 do` ist nicht reverse (genau 1 Iteration)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 5 to 5 do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.NonLiteralBound_HighArr_NoFinding;
// Wenn die obere Grenze ein Ausdruck wie `High(Arr)` ist, koennen wir
// statisch nicht entscheiden -> kein Befund (konservativ).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const Arr: array of Integer);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to High(Arr) do Bar(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.InString_NotDetected;
// `for i := 10 to 1 do` als Inhalt eines String-Literals -> kein Match
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := ''for i := 10 to 1 do'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReversedForRange));
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i);'#13#10 +
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
      if Fnd.Kind = fkReversedForRange then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkReversedForRange finding expected');
    Assert.AreEqual(fkReversedForRange, Hit.Kind);
    Assert.AreEqual(lsError,            Hit.Severity);
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_MultipleHitsInSameMethod_AllReported;
// Drei reversed-for in derselben Methode -> drei Findings.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j, k: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do Bar(i);'#13#10 +
  '  for j := 5 to 2 do Bar(j);'#13#10 +
  '  for k := 100 to 50 do Bar(k);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkReversedForRange),
      'Drei reversed-for in einer Methode -> 3 Findings');
  finally F.Free; end;
end;

procedure TTestReversedForRange.Reversed_DoAtLineEnd_Reported;
// Voll-Review 2026-09-12 (Blocker): endete die Zeile exakt mit 'do'
// (Body auf der Folgezeile - der Standard-Delphi-Stil), verlangte der
// Wortgrenzen-Guard ein Zeichen HINTER dem do und verwarf den
// kompletten einzeiligen for-Kopf als 'Range mehrzeilig'. Der
// klassische downto-vergessen-Bug blieb genau im haeufigsten
// Formatierungsfall ungemeldet (Bestands-Exe: 0 Funde, empirisch
// belegt). Alle bisherigen Positiv-Fixtures hatten eine Anweisung
// hinter dem do auf derselben Zeile - deshalb war die Luecke
// testgruen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 10 to 1 do'#13#10 +
  '  begin'#13#10 +
  '    Bar(i);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkReversedForRange),
    'for 10 to 1 mit do am Zeilenende muss gemeldet werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestReversedForRange);

end.
