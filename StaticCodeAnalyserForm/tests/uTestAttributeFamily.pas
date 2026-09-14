unit uTestAttributeFamily;

// Konsolidierte Tests fuer SCA179-183 (Attribute-Detector-Familie).
// Ein einziges Unit-File spart Plumbing-Overhead (5 Test-Units waeren
// 25+ Edits in TestProject.dpr/dproj).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAttributeIgnoreWithoutReason = class
  public
    [Test] procedure IgnoreNoArg_Reported;
    [Test] procedure IgnoreEmptyParens_Reported;
    [Test] procedure IgnoreWithMessage_NotReported;
    // Posten 293: IsLikelyAttributePosition wie bei den Geschwistern
    [Test] procedure ArrayIndexNamedIgnore_NoFinding;
    [Test] procedure ArrayIndexOnContinuationLine_NoFinding;
    [Test] procedure RealIgnoreAttribute_Kontrolle_Reported;
  end;

  [TestFixture]
  TTestAttributeDuplicate = class
  public
    [Test] procedure SameAttributeTwice_Reported;
    [Test] procedure DifferentArgs_NotReported;
    // Voll-Review 2026-09-12 (Testluecke 122)
    [Test] procedure IdenticalArgsTwice_Reported;
    [Test] procedure SameAttributeDifferentMembers_NotReported;
  end;

  [TestFixture]
  TTestAttributeCategoryWithoutString = class
  public
    [Test] procedure CategoryNoArg_Reported;
    [Test] procedure CategoryWithName_NotReported;
  end;

  [TestFixture]
  TTestAttributeTestFixtureWithoutTests = class
  public
    [Test] procedure FixtureNoTests_Reported;
    [Test] procedure FixtureWithTest_NotReported;
    // FP-Fix 2026-07-25 (Doku-Quickwins 2026-07-25): DUnitX-Auto-Discovery.
    [Test] procedure FixturePublishedProcNoAttr_NotReported;
    [Test] procedure FixtureWithoutAnyMethod_Reported;
    // Voll-Review 2026-09-12 (Blocker): der Fenster-Schliesser las die
    // ROHZEILE statt der kommentarbereinigten - beide Richtungen des
    // Fixes hier festgehalten.
    [Test] procedure FixtureEndWithTrailingComment_Reported;
    [Test] procedure CommentedEndInsideClass_NotReported;
    // Voll-Review 2026-09-12 (Testluecke 123)
    [Test] procedure TestCaseCountsAsTestMarker_NotReported;
    [Test] procedure InheritsCustomBase_NotReported;
  end;

  [TestFixture]
  TTestAttributeMisalignment = class
  public
    [Test] procedure AttrWithBlankLine_Reported;
    [Test] procedure AttrDirectlyBeforeMember_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ TTestAttributeIgnoreWithoutReason }

{ --- Posten 293: das FP-Gate der Attribut-Familie ---------------- }
//
// Dieser Detektor war der EINZIGE der Familie ohne
// IsLikelyAttributePosition - die vier anderen Klassen in DIESER Datei
// testen Detektoren, die das Gate seit dem FP-Fix 2026-06-21 fuehren.
// Ohne das Gate liest der Regex einen Array-Index mit einer Variablen
// namens 'Ignore' als Attribut.
//
// Alle vier an der Exe gemessen; die beiden Index-Fixturen sind heute
// ROT.
//
// KORPUSWIRKUNG 0: der Regex hat ueber alle 16.024 Quelldateien NULL
// Treffer - weder echte noch falsche. Das Gate ist Vorsorge, kein
// Aufraeumen.

procedure TTestAttributeIgnoreWithoutReason.ArrayIndexNamedIgnore_NoFinding;
// DER NACHWEIS. Heute 1 Fund, nach dem Gate 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var A: array of Integer; Ignore, X: Integer;'#13#10 +
  'begin'#13#10 +
  '  X := A[Ignore];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason),
      'ein Array-Index ist keine Attribut-Position');
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.ArrayIndexOnContinuationLine_NoFinding;
// Dieselbe Klasse ueber eine Fortsetzungszeile - genau der Fall, fuer
// den das Gate seine EXPR_CONT-Listen fuehrt. Heute 1, danach 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var A: array of Integer; Ignore, X: Integer;'#13#10 +
  'begin'#13#10 +
  '  X := 1 +'#13#10 +
  '    A[Ignore];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason),
      'eine Ausdrucks-Fortsetzung ist keine Attribut-Position');
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.RealIgnoreAttribute_Kontrolle_Reported;
// POSITIV-KONTROLLE. Gemessen: 1, und muss 1 bleiben - ein Gate, das
// zu viel wegnimmt, faellt hier auf.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFooTests = class'#13#10 +
  '    [Ignore]'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason),
      'ein echtes [Ignore] ohne Begruendung bleibt ein Fund');
  finally F.Free; end;
end;


procedure TTestAttributeIgnoreWithoutReason.IgnoreNoArg_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.IgnoreEmptyParens_Reported;
// Coverage-Fix (2026-06-21): [Ignore()] mit leeren Klammern = ebenfalls
// kein Grund - muss gemeldet werden.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore()]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason) >= 1,
    '[Ignore()] ohne Grund muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.IgnoreWithMessage_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore(''TBD ticket #1234'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason));
  finally F.Free; end;
end;

{ TTestAttributeDuplicate }

procedure TTestAttributeDuplicate.SameAttributeTwice_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeDuplicate) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeDuplicate.DifferentArgs_NotReported;
// [TestCase('A', '1')] + [TestCase('B', '2')] sind LEGITIM multi-applied.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [TestCase(''A'', ''1'')]'#13#10 +
  '    [TestCase(''B'', ''2'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeDuplicate));
  finally F.Free; end;
end;

{ TTestAttributeCategoryWithoutString }

procedure TTestAttributeCategoryWithoutString.CategoryNoArg_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Category]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeCategoryWithoutString) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeCategoryWithoutString.CategoryWithName_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Category(''Slow'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeCategoryWithoutString));
  finally F.Free; end;
end;

{ TTestAttributeTestFixtureWithoutTests }

procedure TTestAttributeTestFixtureWithoutTests.FixtureEndWithTrailingComment_Reported;
// `end; // TFooTests` beendet die Klasse GENAUSO wie ein nacktes
// `end;` - die alte Rohzeilen-Regel verlangte aber das Zeilenende
// direkt nach dem ';' und schloss das Fenster nie: die Zombie-Meldung
// entfiel, und jede weitere Fixture der Datei erbte den Zustand.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '  end; // TFooTests'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(
    TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests) >= 1,
    'Zombie-Fixture mit Kommentar hinter end; muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.CommentedEndInsideClass_NotReported;
// Ein `end;` INNERHALB eines Blockkommentars (auskommentierter Code in
// der Klasse) ist KEIN Klassenende. Die alte Rohzeilen-Regel schloss
// das Fenster dort und meldete die Fixture als Zombie, obwohl weiter
// unten ein echtes [Test] steht.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    { alter Entwurf:'#13#10 +
  '    end;'#13#10 +
  '    }'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Wirklich;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests),
    'auskommentiertes end; darf das Klassenfenster nicht schliessen');
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.FixtureNoTests_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.FixtureWithTest_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    [Test] procedure DoesX;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests));
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.FixturePublishedProcNoAttr_NotReported;
// FP-Fix 2026-07-25 (Doku-Quickwins 2026-07-25): DUnitX-Auto-Discovery
// fuehrt published-Methoden auch OHNE [Test]-Attribut aus - Fixture mit
// published-Prozedur ist kein Zombie.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  private'#13#10 +
  '    FHelper: Integer;'#13#10 +
  '  published'#13#10 +
  '    procedure DoesXWithoutAttr;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests),
    'published-Prozedur ohne [Test] wird von DUnitX auto-discovered - kein Zombie');
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.FixtureWithoutAnyMethod_Reported;
// TP-Gegenprobe (2026-07-25): Fixture ganz ohne Methoden (auch keine
// published-Sektion) bleibt eine Zombie-Fixture und wird gemeldet.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TEmptyTests = class'#13#10 +
  '  private'#13#10 +
  '    FData: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests) >= 1,
    'Fixture ohne jede Methode bleibt Zombie-Fund');
  finally F.Free; end;
end;

{ TTestAttributeMisalignment }

procedure TTestAttributeMisalignment.AttrWithBlankLine_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  ''#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeMisalignment) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeMisalignment.AttrDirectlyBeforeMember_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeMisalignment));
  finally F.Free; end;
end;

procedure TTestAttributeDuplicate.IdenticalArgsTwice_Reported;
// Testluecke 122 (Voll-Review 2026-09-12): dass ZWEI Attribute mit
// IDENTISCHEN Argumenten am selben Member ein Duplikat sind, war nicht
// gepinnt - nur der Fall ohne Argumente. An der gebauten Exe
// verifiziert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TA = class'#13#10 +
  '  public'#13#10 +
  '    [TestCase(''A'',''1'')]'#13#10 +
  '    [TestCase(''A'',''1'')]'#13#10 +
  '    procedure Doppelt;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAttributeDuplicate),
    'zweimal dasselbe Attribut mit denselben Argumenten ist ein Duplikat');
  finally F.Free; end;
end;

procedure TTestAttributeDuplicate.SameAttributeDifferentMembers_NotReported;
// Die Gegenprobe zum FP-Fix vom 2026-06-21: dasselbe Attribut an
// VERSCHIEDENEN Membern ist kein Duplikat. Das ist der Normalfall in
// delphimvcframework ([MVCInheritable] an jeder Methode) - ohne die
// TargetLine-Logik waere jede solche Unit voller Falschmeldungen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TB = class'#13#10 +
  '  public'#13#10 +
  '    [MVCInheritable]'#13#10 +
  '    function A: Integer;'#13#10 +
  '    [MVCInheritable]'#13#10 +
  '    function B: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAttributeDuplicate),
    'dasselbe Attribut an zwei Membern ist kein Duplikat');
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.TestCaseCountsAsTestMarker_NotReported;
// Testluecke 123 (Voll-Review 2026-09-12): TestCase/TestMethod zaehlen
// seit dem FP-Fix 2026-06-21 als Test-Marker (TEST_RE) - ungetestet.
// Eine Fixture, deren einzige Methode ein [TestCase] traegt, ist keine
// Zombie-Fixture.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TMitTestCase = class'#13#10 +
  '  public'#13#10 +
  '    [TestCase(''x'',''1'')]'#13#10 +
  '    procedure P;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests),
    '[TestCase] ist ein Test-Marker');
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.InheritsCustomBase_NotReported;
// Zweiter ungetesteter Pfad: leitet die Fixture von einer EIGENEN
// Basis ab, koennen die Tests dort stehen - InheritsCustom-Skip
// (FP-Fix delphimvcframework). Die Fixture endet hier ausserdem mit
// 'end; // Kommentar', deckt also zugleich den kommentarbereinigten
// Fenster-Schliesser mit ab.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TAbgeleitet = class(TEigeneBase)'#13#10 +
  '  public'#13#10 +
  '    procedure Q;'#13#10 +
  '  end; // Kommentar hinter end'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests),
    'die Tests koennen in der eigenen Basisklasse stehen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAttributeIgnoreWithoutReason);
  TDUnitX.RegisterTestFixture(TTestAttributeDuplicate);
  TDUnitX.RegisterTestFixture(TTestAttributeCategoryWithoutString);
  TDUnitX.RegisterTestFixture(TTestAttributeTestFixtureWithoutTests);
  TDUnitX.RegisterTestFixture(TTestAttributeMisalignment);

end.
