unit uTestPerfHotspots;

// Tests fuer TPerfHotspotsDetector (SCA110-112).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPerfHotspots = class
  public
    // StringConcatInLoop
    [Test] procedure StringConcat_InForLoop_Reported;
    [Test] procedure StringConcat_OutsideLoop_NotReported;
    [Test] procedure StringConcat_InWhile_Reported;
    [Test] procedure StringConcat_DifferentVars_NotReported;
    // Real-World FP-Audit 2026-07-10: numerischer Akkumulator ist kein String-Concat
    [Test] procedure StringConcat_NumericAccumulator_NotReported;
    // Welle 1 (TTypeResolver): QWord fehlt in der Regex-NUMTYPES, der AST-Resolver
    // kennt es -> nur der Resolver-Pfad unterdrueckt diesen numerischen Akkumulator.
    [Test] procedure StringConcat_QWordAccumulator_ResolverOnly_NotReported;
    // Track A (2026-07-12): RHS strukturell beweisbar kein String -> suppress.
    // LHS-Typ NICHT in NUMTYPES, damit nur RhsIsProvablyNonString greift (isoliert).
    [Test] procedure StringConcat_RhsNumericLiteral_NotReported;      // N2
    [Test] procedure StringConcat_RhsArithmeticOperator_NotReported;  // N3
    [Test] procedure StringConcat_RhsSetConstructor_NotReported;      // N1
    [Test] procedure StringConcat_RhsNumericFunc_NotReported;         // N4
    // TP-Gegenproben: echte String/Char-Concats muessen weiter feuern
    [Test] procedure StringConcat_RhsCharIndexAccess_StillReported;   // s+arr[i]
    [Test] procedure StringConcat_RhsCharLiteral_StillReported;       // s+','
    [Test] procedure StringConcat_RhsCharIndexLiteralDigit_StillReported; // s+arr[0]: Bracket-Tiefe
    [Test] procedure StringConcat_RhsNumFnDotToString_StillReported;      // s+Integer(x).ToString: N4-trailing-dot

    // ParamByNameInLoop
    [Test] procedure ParamByName_InLoop_Reported;
    [Test] procedure ParamByName_OutsideLoop_NotReported;

    // FieldByNameInLoop
    [Test] procedure FieldByName_InWhileEofLoop_Reported;
    [Test] procedure FieldByName_OutsideLoop_NotReported;
    [Test] procedure SingleStmtLoop_ConcatAfterLoop_NotReported;
    [Test] procedure SingleStmtLoop_ConcatInBody_Reported;
    // --- Voll-Review 2026-09-12 (Blocker): Body-Ende-Suche ohne linke
    // Wortgrenze und ohne Tiefenzaehlung ---
    [Test] procedure AppendInLoop_ConcatBehindAppend_StillReported;
    [Test] procedure IdentWithEndSubstring_NoPhantomRangeInNextRoutine;
    [Test] procedure InnerBlockEnd_DoesNotCutRange_ConcatReported;
    // Posten 184: die dritte Schleifenart - Grundfaelle, zwei
    // behobene Defekte und die zwei Subtraktionen des Fix
    [Test] procedure Repeat_ConcatInBody_Reported;
    [Test] procedure Repeat_ConcatAfterLoop_NotReported;
    [Test] procedure Repeat_ParamByNameInBody_Reported;
    [Test] procedure Repeat_FieldByNameInBody_Reported;
    [Test] procedure Repeat_IdentContainingUntil_StillReported;
    [Test] procedure Repeat_IdentWithoutUntil_Kontrolle;
    [Test] procedure Repeat_NestedLoop_OuterTailStillReported;
    [Test] procedure Repeat_NoNestedLoop_Kontrolle;
    [Test] procedure Repeat_KeywordInComment_StillReported;
    [Test] procedure Repeat_KeywordInLiteral_StillReported;
    [Test] procedure Repeat_KeywordsInTwoLiterals_NoRange;
    [Test] procedure Repeat_RealKeywords_Kontrolle;
    [Test] procedure Repeat_DottedMemberNamed_NoPhantomRange;
    [Test] procedure Repeat_UnbalancedOuterLoop_NoRange_KnownLimit;
  end;

implementation

// noinspection-file GodClass, LargeClass, DuplicateBlock
// DuplicateBlock seit Posten 184: die vier Minimal-Differenz-Paare
// unterscheiden sich absichtlich in genau EINER Zeile - darin liegt
// ihr ganzer Beweis, sie duerfen sich nicht unterscheiden. Ein
// zeilengenauer Marker greift hier nicht: der Fund haengt an der
// ersten Zeile des Fixture-Literals, nicht am Methodenkopf.
// Eine Testklasse je Detektor ist der Projekt-Zuschnitt: SCA110-112
// teilen sich EINEN Detektor, seine Regressionen gehoeren in EINE
// Fixture-Klasse. Die Methoden-/Zeilen-Schwellen reissen hier durch
// die Blocker-Regressionen des Voll-Reviews 2026-09-12 - Aufteilen
// wuerde die Zusammengehoerigkeit der Range-Tests zerreissen.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 184: der repeat-Zweig von FindLoopRanges ------------- }
//
// Alle 23 Bestandsfixtures nutzen Zaehl- oder Kopfschleifen; die
// dritte Schleifenart hatte keine einzige. Beim Vermessen wurde aus
// der Testluecke eine Codeluecke: der Zweig suchte sein Ende mit
// einem nackten Teilstring-Vergleich, ohne Wortgrenzen und ohne
// Tiefe - genau die Signatur, die fuenf Zeilen weiter oben schon
// einmal ein Blocker war. Der Fix (FindMatchingUntil) steht in
// demselben Commit wie diese Tests.
//
// Die Erwartungen unten sind die Zahlen NACH dem Fix. Wo sie sich
// vom heutigen Stand unterscheiden, steht die Vorher-Zahl im
// Kommentar - beide sind gemessen.

procedure TTestPerfHotspots.Repeat_ConcatInBody_Reported;
// Grundfall der dritten Schleifenart. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Sammler;'#13#10 +
  'var buf: string; idx: Integer;'#13#10 +
  'begin'#13#10 +
  '  idx := 0;'#13#10 +
  '  repeat'#13#10 +
  '    buf := buf + IntToStr(idx);'#13#10 +
  '    Inc(idx);'#13#10 +
  '  until idx > 10;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'Verkettung im repeat-Rumpf ist derselbe Hotspot');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_ConcatAfterLoop_NotReported;
// Die Klammer dazu: dieselbe Struktur, die Verkettung hinter
// dem Schleifenende. Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Zaehler;'#13#10 +
  'var puffer: string; z: Integer;'#13#10 +
  'begin'#13#10 +
  '  z := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Inc(z);'#13#10 +
  '  until z > 4;'#13#10 +
  '  puffer := puffer + ''nach dem Loop'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'hinter der Schleife ist die Verkettung einmalig');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_ParamByNameInBody_Reported;
// Zweites Muster derselben Range. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Blaettern(qry: TFDQuery);'#13#10 +
  'begin'#13#10 +
  '  qry.Open;'#13#10 +
  '  repeat'#13#10 +
  '    qry.ParamByName(''id'').AsInteger := 7;'#13#10 +
  '    qry.Next;'#13#10 +
  '  until qry.Eof;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkParamByNameInLoop),
      'ParamByName im repeat-Rumpf wird gemeldet');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_FieldByNameInBody_Reported;
// Drittes Muster. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Auslesen(ds: TDataSet);'#13#10 +
  'begin'#13#10 +
  '  ds.First;'#13#10 +
  '  repeat'#13#10 +
  '    Lbl.Caption := ds.FieldByName(''Name'').AsString;'#13#10 +
  '    ds.Next;'#13#10 +
  '  until ds.Eof;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFieldByNameInLoop),
      'FieldByName im repeat-Rumpf wird gemeldet');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_IdentContainingUntil_StillReported;
// DER ERSTE DEFEKT: ein Bezeichner, der die Silbe des
// Schleifenendes enthaelt, beendete die Range mitten im
// Wort - die Verkettung dahinter lag ausserhalb.
// Vor dem Fix gemessen: 0. Nach dem Fix: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Warten;'#13#10 +
  'var zeile: string; n: Integer;'#13#10 +
  'begin'#13#10 +
  '  n := 0;'#13#10 +
  '  repeat'#13#10 +
  '    WaitUntilReady(n);'#13#10 +
  '    zeile := zeile + IntToStr(n);'#13#10 +
  '    Inc(n);'#13#10 +
  '  until n > 10;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'ein Bezeichner mit der Endsilbe beendet die Schleife nicht');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_IdentWithoutUntil_Kontrolle;
// Die Klammer: derselbe Rumpf, ein einziger Bezeichner
// anders. Vor UND nach dem Fix 1 - sie zeigt, dass die 0
// oben allein an der Endsilbe hing.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Warten;'#13#10 +
  'var zeile: string; n: Integer;'#13#10 +
  'begin'#13#10 +
  '  n := 0;'#13#10 +
  '  repeat'#13#10 +
  '    WaitForReady(n);'#13#10 +
  '    zeile := zeile + IntToStr(n);'#13#10 +
  '    Inc(n);'#13#10 +
  '  until n > 10;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'ohne die Endsilbe wurde derselbe Fall immer gemeldet');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_NestedLoop_OuterTailStillReported;
// DER ZWEITE DEFEKT, im Korpus der groessere: die aeussere
// Schleife endete am Ende der INNEREN, ihr Rest war
// unsichtbar. Vor dem Fix gemessen: 0. Nach dem Fix: 1.
//
// Korpusflaeche: 731 verkuerzte Bloecke in 210 Dateien, 30
// davon mit einem Detektor-Muster im verlorenen Stueck.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Schachteln;'#13#10 +
  'var text: string; a, b: Integer;'#13#10 +
  'begin'#13#10 +
  '  a := 0;'#13#10 +
  '  repeat'#13#10 +
  '    b := 0;'#13#10 +
  '    repeat'#13#10 +
  '      Inc(b);'#13#10 +
  '    until b > 2;'#13#10 +
  '    text := text + IntToStr(a);'#13#10 +
  '    Inc(a);'#13#10 +
  '  until a > 6;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'der Rest der aeusseren Schleife gehoert noch zu ihr');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_NoNestedLoop_Kontrolle;
// Die Klammer: dieselbe Routine ohne die innere Schleife.
// Vor UND nach dem Fix 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Schachteln;'#13#10 +
  'var text: string; a, b: Integer;'#13#10 +
  'begin'#13#10 +
  '  a := 0;'#13#10 +
  '  repeat'#13#10 +
  '    b := 0;'#13#10 +
  '    Inc(b);'#13#10 +
  '    text := text + IntToStr(a);'#13#10 +
  '    Inc(a);'#13#10 +
  '  until a > 6;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'ohne innere Schleife wurde derselbe Fall immer gemeldet');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_KeywordInComment_StillReported;
// Der Kommentar-Strip auf dem Pfad der dritten
// Schleifenart: die Endsilbe in einem Kommentar darf die
// Range nicht kappen. Gemessen: 1, vor und nach dem Fix.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Kommentiert;'#13#10 +
  'var rest: string; p: Integer;'#13#10 +
  'begin'#13#10 +
  '  p := 0;'#13#10 +
  '  repeat'#13#10 +
  '    // warten until das Geraet bereit meldet'#13#10 +
  '    rest := rest + IntToStr(p);'#13#10 +
  '    Inc(p);'#13#10 +
  '  until p > 8;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'ein Kommentar beendet die Schleife nicht');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_KeywordInLiteral_StillReported;
// Dasselbe fuer ein Zeichenkettenliteral im Rumpf.
// Gemessen: 1, vor und nach dem Fix.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Protokolliert;'#13#10 +
  'var eintrag: string; w: Integer;'#13#10 +
  'begin'#13#10 +
  '  w := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Log(''warte until bereit'');'#13#10 +
  '    eintrag := eintrag + IntToStr(w);'#13#10 +
  '    Inc(w);'#13#10 +
  '  until w > 8;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'ein Literal beendet die Schleife nicht');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_KeywordsInTwoLiterals_NoRange;
// Die Gegenrichtung zum Literal-Ausblenden: beide
// Schluesselwoerter stehen in GETRENNTEN Literalen, die
// Verkettung dazwischen. Ohne das Ausblenden umspannte die
// Phantom-Range sie. Gemessen: 0, vor und nach dem Fix.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Phantom;'#13#10 +
  'var wert: string;'#13#10 +
  'begin'#13#10 +
  '  Log(''repeat'');'#13#10 +
  '  wert := wert + ''Stueck'';'#13#10 +
  '  Log(''until'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'Literale oeffnen keine Schleife');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_RealKeywords_Kontrolle;
// Die Klammer dazu: dieselben drei Zeilen ohne
// Anfuehrungszeichen. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Phantom;'#13#10 +
  'var wert: string;'#13#10 +
  'begin'#13#10 +
  '  repeat'#13#10 +
  '  wert := wert + ''Stueck'';'#13#10 +
  '  until True;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'echte Schluesselwoerter oeffnen sehr wohl eine Schleife');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_DottedMemberNamed_NoPhantomRange;
// DIE SUBTRAKTIONS-SEITE DES FIX. Ein punktqualifiziertes
// Aufzaehlungsglied traegt denselben Namen wie das
// Schluesselwort; die linke Wortgrenze laesst es durch, weil
// der Punkt kein Bezeichnerzeichen ist. Bisher oeffnete es
// eine Range bis zum naechsten Schleifenende IRGENDWO in der
// Datei - hier quer in eine fremde Routine, und der
// ParamByName-Aufruf in KEINER Schleife wurde gemeldet.
//
// Vor dem Fix gemessen: 1 (ein Fehlfund). Nach dem Fix: 0,
// weil die Tiefenzaehlung das Ende der echten Schleife
// verbraucht. Im Korpus tragen 12 Dateien diese
// Schreibweise.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure A(q: TFDQuery);'#13#10 +
  'begin'#13#10 +
  '  SetTile(TSkTileMode.Repeat, TSkTileMode.Decal);'#13#10 +
  '  q.ParamByName(''x'').AsInteger := 1;'#13#10 +
  'end;'#13#10 +
  'procedure B;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Inc(i);'#13#10 +
  '  until i > 3;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkParamByNameInLoop),
      'ein punktqualifiziertes Glied oeffnet keine Schleife');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.Repeat_UnbalancedOuterLoop_NoRange_KnownLimit;
// Die zweite Subtraktion, und die ehrlichere: fehlt der
// aeusseren Schleife ihr Ende (unvollstaendiger Quelltext),
// verbraucht die Tiefenzaehlung das Ende der inneren und
// findet keins mehr - es entsteht GAR KEINE aeussere Range.
// Vor dem Fix gemessen: 1 (die zu kurze Range deckte die
// Verkettung noch). Nach dem Fix: 0.
//
// Das ist der Preis der Tiefenzaehlung, derselbe wie beim
// begin/end-Zwilling. Im Korpus kostet er nichts: die sieben
// Musterfunde in Bloecken ohne tiefengematchtes Ende liegen
// alle zusaetzlich in echten Schleifen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Unbalanciert;'#13#10 +
  'var s: string; i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    s := s + IntToStr(i);'#13#10 +
  '    j := 0;'#13#10 +
  '    repeat'#13#10 +
  '      Inc(j);'#13#10 +
  '    until j > 2;'#13#10 +
  '    Inc(i);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringConcatInLoop),
      'BEKANNTE GRENZE: ohne Schleifenende entsteht keine Range');
  finally F.Free; end;
end;


procedure TTestPerfHotspots.StringConcat_InForLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + IntToStr(i);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
      'genau 1 StringConcatInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 's := s + IntToStr(i)'),
      TFindingHelper.FirstOf(F, fkStringConcatInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := s + ''once'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_InWhile_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  while i < 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + ''x'';'#13#10 +
  '    Inc(i);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
      'genau 1 StringConcatInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 's := s + '),
      TFindingHelper.FirstOf(F, fkStringConcatInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_DifferentVars_NotReported;
// a := b + c ist KEIN Self-Concat -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    a := b + c;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.ParamByName_InLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    Q.ParamByName(''id'').AsInteger := i;'#13#10 +
  '    Q.ExecSQL;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkParamByNameInLoop),
      'genau 1 ParamByNameInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ParamByName'),
      TFindingHelper.FirstOf(F, fkParamByNameInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.ParamByName_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Q.ParamByName(''id'').AsInteger := 42;'#13#10 +
  '  Q.ExecSQL;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkParamByNameInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.FieldByName_InWhileEofLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Total: Currency;'#13#10 +
  'begin'#13#10 +
  '  Total := 0;'#13#10 +
  '  while not Q.Eof do'#13#10 +
  '  begin'#13#10 +
  '    Total := Total + Q.FieldByName(''Amount'').AsCurrency;'#13#10 +
  '    Q.Next;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldByNameInLoop),
      'genau 1 FieldByNameInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FieldByName'),
      TFindingHelper.FirstOf(F, fkFieldByNameInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.FieldByName_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Lbl.Caption := Q.FieldByName(''Name'').AsString;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldByNameInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_NumericAccumulator_NotReported;
// Real-World FP-Audit 2026-07-10: 'j := j + 3' mit j:Integer ist eine numerische
// Akkumulation, KEIN String-Concat (kein O(n^2)-Realloc-Bug). Der LHS-Typ wird
// aus der Deklaration aufgeloest -> numerisch -> kein Fund. Gegenstueck zum
// bestehenden StringConcat_InForLoop_Reported (s:string bleibt Fund).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var j: Integer; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    j := j + 3;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'numerischer Akkumulator (j: Integer) ist kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_QWordAccumulator_ResolverOnly_NotReported;
// Welle 1 - Beleg fuer die additive AST-Typ-Aufloesung (Core-Detektoren-Architektur).
// 'q := q + i' mit q:QWord ist numerische Akkumulation, kein O(n^2)-String-Concat.
// Die lexikalische LhsDeclaredNumeric kennt 'qword' NICHT (fehlt in ihrer NUMTYPES-
// Liste) -> wuerde faelschlich melden. Der TTypeResolver loest q -> qword auf und
// unterdrueckt (IsNumericTypeName). Zeigt, dass der Resolver-Pfad zusaetzlich greift.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: QWord; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    q := q + i;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'q: QWord ist numerisch - nur der AST-Resolver kennt qword -> kein Fund');
  finally F.Free; end;
end;

// ---- Track A: RhsIsProvablyNonString (2026-07-12) ----
// LHS-Typ bewusst 'TAcc'/'TSet' (NICHT in NUMTYPES), damit LhsDeclaredNumeric
// NICHT vorab suppress't -> ohne den neuen Guard waeren das FPs. Prueft also
// isoliert RhsIsProvablyNonString.

procedure TTestPerfHotspots.StringConcat_RhsNumericLiteral_NotReported;
// N2: Zahl-Literal-Operand -> beweisbar numerisch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + 7;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + 7 (Zahl-Literal) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsArithmeticOperator_NotReported;
// N3: numerischer Operator '*' auf Tiefe 0 -> beweisbar numerisch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + i * 2;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + i * 2 (Operator *) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsSetConstructor_NotReported;
// N1: RHS beginnt mit '[' -> Set-/Array-Konstruktor, kein String.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TSet; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + [i];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + [i] (Set-Konstruktor) ist kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsNumericFunc_NotReported;
// N4: numerischer Func-Operand Length(...) ohne trailing '.' -> Integer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + Length(s);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + Length(s) (numerische Func) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharIndexAccess_StillReported;
// TP-Gegenprobe: 's := s + arr[i]' haengt ein Char an (echtes O(n^2)-Concat).
// Die '[i]'-Ziffer liegt auf Bracket-Tiefe 1 -> darf N2 NICHT ausloesen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; arr: array of Char; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + arr[i];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    's := s + arr[i] (Char-Anhang) bleibt ein String-Concat-Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharLiteral_StillReported;
// TP-Gegenprobe: 's := s + '','' ' haengt ein Char-Literal an (echtes Concat).
// Das Literal wird uebersprungen -> keine Klausel greift -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + '','';'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    's := s + '','' (Char-Literal) bleibt ein String-Concat-Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharIndexLiteralDigit_StillReported;
// TP-Gegenprobe (Bracket-Tiefe-Lock): 's := s + arr[0]' - die Ziffer '0' liegt
// auf Bracket-Tiefe 1 und darf N2 NICHT ausloesen; s+Char(arr[0]) ist ein
// echtes Concat.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; arr: array of Char; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + arr[0];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Ziffer in arr[0] ist auf Bracket-Tiefe 1 - kein N2 - bleibt Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsNumFnDotToString_StillReported;
// TP-Gegenprobe (N4-trailing-dot-Lock): 's := s + Integer(x).ToString' - .ToString
// liefert String; das '.' nach dem NumFn-')' verhindert N4 -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; x, i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + Integer(x).ToString;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Integer(x).ToString (trailing .) ist String - N4 greift nicht - bleibt Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.SingleStmtLoop_ConcatAfterLoop_NotReported;
// Review-HIGH 2026-08-08: ein for ohne begin blieb auf dem Header-Stack
// und das begin der NAECHSTEN Routine wurde zur Loop-Range - Concat
// ausserhalb jeder Schleife galt als in-Loop.
const SRC =
  'unit t; implementation'#13#10 +
  // Namen bewusst anders als in den Bestands-Fixtures (DuplicateBlock).
  'procedure A; var k: Integer;'#13#10 +
  'begin'#13#10 +
  '  for k := 0 to 9 do'#13#10 +
  '    Ping(k);'#13#10 +
  'end;'#13#10 +
  'procedure B;'#13#10 +
  'var txt: string;'#13#10 +
  'begin'#13#10 +
  '  txt := txt + ''tail'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.SingleStmtLoop_ConcatInBody_Reported;
// Der Klassiker des O(n^2)-Bugs ist gerade die begin-lose Form -
// der Single-Statement-Body ist jetzt eine echte Loop-Range.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  // Namen bewusst ANDERS als in StringConcat_InFor_Reported - sonst
  // meldet der Self-Scan die beiden Fixtures als DuplicateBlock.
  'var acc: string; n: Integer;'#13#10 +
  'begin'#13#10 +
  '  for n := 0 to 7 do'#13#10 +
  '    acc := acc + IntToStr(n);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.AppendInLoop_ConcatBehindAppend_StillReported;
// Voll-Review 2026-09-12 (Blocker): die Body-Ende-Suche prueft nur die
// RECHTE Wortgrenze - das eingebettete 'end' in 'Append(' bestand den
// Check ('(' folgt), die Range endete mitten im Bezeichner und das
// Concat DAHINTER lag ausserhalb jeder Range (Bestands-Exe: 0 Funde,
// empirisch belegt). Ironie: genau das vom Detektor empfohlene
// TStringBuilder.Append erzeugte den blinden Fleck.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P;'#13#10 +
  'var i: Integer; s: string; SB: TStringBuilder;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    SB.Append(IntToStr(i));'#13#10 +
  '    s := s + IntToStr(i);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkStringConcatInLoop),
    'Concat hinter SB.Append im selben Loop-Body muss gemeldet werden - ' +
    'das end-Substring von Append ist kein Body-Ende');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.IdentWithEndSubstring_NoPhantomRangeInNextRoutine;
// Zweite Form desselben Blockers: scheiterte der Rechts-Check
// ('Friends' - 's' folgt), gab es KEINE Weitersuche - der Loop-Header
// blieb auf dem Stack und das begin der NAECHSTEN Routine wurde zur
// Phantom-Loop-Range: ParamByName dort galt als in-Loop (Bestands-Exe
// meldet ph2.pas:14, empirisch belegt).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure A;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    Friends.Add(i);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'procedure B(q: TFDQuery);'#13#10 +
  'begin'#13#10 +
  '  q.ParamByName(''x'').AsInteger := 1;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkParamByNameInLoop),
    'ParamByName in der naechsten Routine liegt in KEINER Schleife - ' +
    'Friends.Add darf keine Phantom-Range hinterlassen');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.InnerBlockEnd_DoesNotCutRange_ConcatReported;
// Dritte Form: das erste echte INNERE 'end' (if-Block im Loop) beendete
// die Range zu frueh - das Concat nach dem inneren Block war unsichtbar
// (Bestands-Exe: 0 Funde, empirisch belegt). Jetzt zaehlt die
// Body-Ende-Suche begin/case/try-Tiefe.
// Fixture bewusst mit anderen Namen/Grenzen als der Append-Zwilling -
// sonst meldet der Selbstscan die beiden als 8-Zeilen-DuplicateBlock.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Sammle;'#13#10 +
  'var k: Integer; txt: string;'#13#10 +
  'begin'#13#10 +
  '  for k := 1 to 5 do'#13#10 +
  '  begin'#13#10 +
  '    if k > 2 then'#13#10 +
  '    begin'#13#10 +
  '      Log(k);'#13#10 +
  '    end;'#13#10 +
  '    txt := txt + IntToStr(k);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkStringConcatInLoop),
    'Concat nach dem inneren if-Block liegt noch im Loop-Body - ' +
    'die Tiefenzaehlung darf die Range nicht am inneren end kappen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPerfHotspots);

end.
