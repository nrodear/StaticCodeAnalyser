unit uTestFreeAndNilHint;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeAndNilHint = class
  public
    [Test] procedure FreeAlone_NoFinding;
    [Test] procedure FreeAndNilOnNextLine_Reported;
    [Test] procedure DifferentReceiver_NoFinding;
    // Voll-Review 2026-09-12 (Blocker): kein Blockkommentar-Tracking.
    [Test] procedure PatternInsideBlockComment_NoFinding;
    [Test] procedure FreeAndNilHint_KindAndSeverity;
    // Posten 202: Kommentar, Einzeiler, Feld und Self
    [Test] procedure FreeAndNilInMultiLineComment_NoFinding;
    [Test] procedure FreeAndNilOnSameLine_NoFinding_KnownLimit;
    [Test] procedure FreeAndNilOnField_Reported;
    [Test] procedure FreeAndNilOnSelfQualifiedField_NoFinding_KnownLimit;
    // Posten 202, zweite Runde: die zwei fehlenden Klammern und
    // drei ungeschriebene Grenzen des Zeilenvergleichs
    [Test] procedure FreeAndNilInMultiLineComment_Kontrolle;
    [Test] procedure FreeAndNilOnSeparateLines_Kontrolle;
    [Test] procedure BraceInStringLiteral_DoesNotSilenceRest_Reported;
    [Test] procedure RealBraceComment_SilencesRest_Kontrolle;
    [Test] procedure LineCommentBetweenStatements_NoFinding_KnownLimit;
    [Test] procedure DirectiveBetweenStatements_NoFinding_KnownLimit;
    [Test] procedure DirectiveAfterStatements_Kontrolle;
    [Test] procedure PatternOnlyInStringLiterals_NoFinding;
    [Test] procedure BlockCommentClosesMidLine_RestIsCode_Reported;
    [Test] procedure UnclosedBlockComment_NoFinding_Kontrolle;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 202: die vier ungepinnten Grenzen ------------------- }
//
// Der Detektor hatte vier Tests. Was fehlte, waren genau die Faelle,
// an denen sein Vertrag haengt. Alle vier hier am gebauten Stand
// gemessen und festgenagelt - keiner aendert Verhalten.

{ --- Posten 202, zweite Runde: die Klammern und drei Grenzen ----- }
//
// Die drei im Posten genannten Luecken sind seit der ersten Runde
// gepinnt. Beim Nachmessen fiel auf, dass zwei dieser Nullen keine
// Klammer hatten - und dass drei Grenzen des Zeilenvergleichs
// nirgends stehen, obwohl sie im Feld vorkommen.
//
// Alle Zahlen an der Exe gemessen.

procedure TTestFreeAndNilHint.FreeAndNilInMultiLineComment_Kontrolle;
// DIE KLAMMER zu FreeAndNilInMultiLineComment_NoFinding:
// dieselbe Fixture ohne die zwei Kommentarklammern.
// Gemessen: 1. Damit gehoert die Null dort dem Kommentar.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'ohne Kommentarklammern ist dasselbe Muster ein Fund');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnSeparateLines_Kontrolle;
// DIE KLAMMER zu FreeAndNilOnSameLine_NoFinding_KnownLimit:
// dieselben zwei Anweisungen auf zwei Zeilen. Gemessen: 1.
// Sie klammert zugleich die Zeilen-Grenzen weiter unten.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'auf zwei Zeilen wird dasselbe Muster gemeldet');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.BraceInStringLiteral_DoesNotSilenceRest_Reported;
// Die geschweifte Klammer steht in einem Literal. Das
// Literal-Ausblenden laeuft VOR der Kommentar-Erkennung
// (uDetectorUtils.pas:1287 vor :1294) - sonst oeffnete diese
// Klammer einen Kommentar und JEDER Fund bis Dateiende fiele
// weg. Am Helfer ist nur der Fall "// im Literal" gepinnt,
// die geschweifte Klammer nicht. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject; S: string;'#13#10+
  'begin'#13#10+
  '  S := ''a { b'';'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'eine Klammer im Literal oeffnet keinen Kommentar');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.RealBraceComment_SilencesRest_Kontrolle;
// Die Klammer dazu: dieselbe Zeile, die Klammer aber
// AUSSERHALB des Literals. Gemessen: 0 - jetzt ist es ein
// echter Kommentar, und der Rest der Datei liegt darin.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject; S: string;'#13#10+
  'begin'#13#10+
  '  S := ''a''; { b'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'eine Klammer ausserhalb des Literals oeffnet sehr wohl');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.LineCommentBetweenStatements_NoFinding_KnownLimit;
// GRENZE: der Zeilenscan BLANKT eine Kommentarzeile, er
// entfernt sie nicht - die leere Zeile schiebt sich zwischen
// die beiden Anweisungen, und der Vergleich prueft nur
// benachbarte Zeilen. Gemessen: 0.
//
// Die Klammer ist FreeAndNilOnSeparateLines_Kontrolle weiter
// oben: dieselbe Fixture ohne die Kommentarzeile meldet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free;'#13#10+
  '  // dazwischen'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: eine Kommentarzeile dazwischen unterbricht');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DirectiveBetweenStatements_NoFinding_KnownLimit;
// Dieselbe Grenze mit einer bedingten Uebersetzung dazwischen -
// und das ist die feldrelevante Form: so steht es in echtem
// Delphi-Code oft. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free;'#13#10+
  '  {$IFDEF DEBUG}'#13#10+
  '  L := nil;'#13#10+
  '  {$ENDIF}'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: eine Direktive dazwischen unterbricht');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DirectiveAfterStatements_Kontrolle;
// Die Klammer dazu: dieselbe Fixture, nur die oeffnende
// Direktivzeile entfaellt - die schliessende bleibt stehen,
// damit sich genau EINE Zeile unterscheidet. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  '  {$ENDIF}'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'hinter dem Paar stoert dieselbe Direktive nicht');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.PatternOnlyInStringLiterals_NoFinding;
// Der Kopfvertrag sagt woertlich zu, ein Muster in einem
// Log-Text zaehle nicht. Genau dieser Satz hatte keinen
// Test. Gemessen: 0; die Klammer ist
// FreeAndNilOnSeparateLines_Kontrolle mit denselben zwei
// Zeilen ohne Anfuehrungszeichen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject; S: string;'#13#10+
  'begin'#13#10+
  '  S := ''L.Free;'';'#13#10+
  '  S := ''L := nil;'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'das Muster in Literalen ist kein Code');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.BlockCommentClosesMidLine_RestIsCode_Reported;
// Der Kommentar endet MITTEN in der Zeile, dahinter steht
// echter Code. Der Scanner muss den Zustand zuruecksetzen und
// in derselben Zeile weiterlaufen - stuende dort ein Abbruch
// statt eines Weiter, faende er das Muster nicht.
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  { alt'#13#10+
  '  Old.Free; }  L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'nach der schliessenden Klammer ist der Zeilenrest Code');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.UnclosedBlockComment_NoFinding_Kontrolle;
// Die Klammer dazu: genau die schliessende Klammer durch ein
// Leerzeichen ersetzt, sonst identisch. Gemessen: 0 - der
// Kommentar bleibt offen und verschluckt den Rest.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TObject;'#13#10+
  'begin'#13#10+
  '  { alt'#13#10+
  '  Old.Free;    L.Free;'#13#10+
  '  L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'ohne schliessende Klammer bleibt alles Kommentar');
  finally F.Free; end;
end;


procedure TTestFreeAndNilHint.FreeAndNilInMultiLineComment_NoFinding;
// Das Muster steht KOMPLETT in einem ueber drei Zeilen offenen
// Blockkommentar. Gemessen: 0 Funde. Pinnt den Kommentar-Schutz -
// in derselben Charge hat genau dieser Zustand drei andere
// Detektoren FP produzieren lassen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+'var L: TObject;'#13#10+
  'begin'#13#10+
  '  Beep;  {'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'das Muster im Blockkommentar ist kein Code');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnSameLine_NoFinding_KnownLimit;
// DOKUMENTIERTE GRENZE: der Kopfvertrag verlangt "zwei
// aufeinanderfolgende Statements auf BENACHBARTEN ZEILEN". Auf EINER
// Zeile meldet der Detektor bewusst nicht. Gemessen: 0.
// Der Test haelt die Grenze fest, damit sie nicht als Luecke
// wiederentdeckt wird.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free; L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: das Muster auf EINER Zeile wird nicht gemeldet');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnField_Reported;
// Feld statt Lokaler - gemessen: 1 Fund. Der haeufigste reale Fall
// (Destruktoren) und bisher ohne Test.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  FObj.Free;'#13#10+
  '  FObj := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'auch auf einem Feld ist das Muster ein Fund');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnSelfQualifiedField_NoFinding_KnownLimit;
// GRENZE, hier erstmals belegt: mit Self-Qualifizierung meldet der
// Detektor NICHT (gemessen: 0), waehrend die unqualifizierte Form
// darueber 1 liefert. Der Kopfvertrag spricht von "gleicher
// Identifier X" und sagt zur Qualifizierung nichts.
//
// BEWUSST NICHT MITGEFIXT: das waere fundbewegend und braucht einen
// eigenen Bewegungsvertrag. Der Test pinnt das IST-Verhalten, damit
// die Luecke sichtbar bleibt statt unbemerkt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Self.FObj.Free;'#13#10+
  '  Self.FObj := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: Self-qualifiziert wird nicht erkannt');
  finally F.Free; end;
end;


procedure TTestFreeAndNilHint.FreeAlone_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnNextLine_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DifferentReceiver_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A.Free;'#13#10 +
  '  B := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.PatternInsideBlockComment_NoFinding;
// Mehrzeilig auskommentierter Alt-Code lieferte vor dem Fix einen
// Fund - der Roh-Scan kannte keinen Blockkommentar-Zustand
// (Projekt-Invariante: Kommentare zaehlen NIE als Code-Use).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { Alte Version:'#13#10 +
  '  FConn.Free;'#13#10 +
  '  FConn := nil;'#13#10 +
  '  }'#13#10 +
  '  DoNew;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkFreeAndNilHint),
    'auskommentierter Alt-Code darf keinen FreeAndNil-Hinweis melden');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilHint_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkFreeAndNilHint then
      begin
        Assert.AreEqual<TFindingKind>(fkFreeAndNilHint, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFreeAndNilHint finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeAndNilHint);

end.
