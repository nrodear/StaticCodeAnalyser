unit uTestFormatMismatch;

// Tests fuer den TFormatMismatchDetector (Basis und Erweiterungen).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- FormatMismatch (TFormatMismatchDetector) --------------------------------------
  [TestFixture]
  TTestFormatMismatch = class
  public
    [Test] procedure Format_MorePlaceholdersThanArgs_ReportsError;
    [Test] procedure Format_MoreArgsThanPlaceholders_ReportsError;
    [Test] procedure Format_Matching_NoFinding;
    [Test] procedure Format_EscapedPercent_NotCounted;
    [Test] procedure Format_NoArgs_NoPlaceholders_NoFinding;
    [Test] procedure Format_WidthSpecifier_CorrectCount;
    [Test] procedure Format_NestedInsideAdd_NoFinding;
    [Test] procedure Format_StringContentParsed_CorrectCount;
    [Test] procedure Format_EscapedQuoteInString_CorrectCount;
    // Real-world Pattern aus mORMot-artigen deutschen Meldungen mit
    // mehreren eingebetteten Apostrophen
    [Test] procedure Format_MultipleEscapedQuotes_CorrectCount;
  end;

  // ---- FormatMismatch Erweiterung ----------------------------------------------------
  [TestFixture]
  TTestFormatMismatchExt = class
  public
    [Test] procedure Format_OnePlaceholderTwoArgs_ReportsError;
    // Vorgaenger-Filter erlaubt nicht nur '.' - 'Result := Format(...)' wird erkannt
    [Test] procedure Format_AssignmentWithoutDot_ReportsError;
  end;

  // ---- Bare-Style (mORMot FormatUtf8/FormatString) -----------------------------------
  // Diese Funktionen nutzen '%' allein als Platzhalter (kein Type-Letter).
  // Detektor muss die Counting-Strategie pro Funktionsname umschalten.
  [TestFixture]
  TTestFormatMismatchBareStyle = class
  public
    [Test] procedure FormatUtf8_TwoBarePercents_TwoArgs_NoFinding;
    [Test] procedure FormatUtf8_OneBarePercent_TwoArgs_ReportsError;
    [Test] procedure FormatString_BarePercentSeparator_NoFinding;
    // mORMot's TFormatUtf8.Parse macht KEIN '%%'-Escape - jedes '%'
    // konsumiert ein Argument. '%%' = zwei aufeinanderfolgende Args.
    [Test] procedure FormatUtf8_DoublePercent_ConsumesTwoArgs;
    // Standard-Format() bleibt unveraendert: '%_%' ist KEIN gueltiger
    // Spezifier (kein Type-Letter), zaehlt als 1 Platzhalter -> Mismatch.
    [Test] procedure StandardFormat_PercentUnderscore_StillReportsMismatch;
    // String-Literal-Konkatenation: 'a' + 'b' wird zusammengefuehrt bevor
    // gezaehlt wird. Ohne den Merge wuerde nur 'a' analysiert -> False
    // Positive (typisch fuer mehrzeilige SQL-Strings).
    [Test] procedure FormatUtf8_ConcatenatedLiteral_AllPlaceholdersCounted;
    [Test] procedure FormatUtf8_ConcatenatedLiteral_MismatchAcrossSplit_ReportsError;
  end;

implementation

{ ---- FormatMismatch ---- }

procedure TTestFormatMismatch.Format_MorePlaceholdersThanArgs_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(Name: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [Name]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      '2 Platzhalter, 1 Argument – Error');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_MoreArgsThanPlaceholders_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(A, B: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Nur %s'', [A, B]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      '1 Platzhalter, 2 Argumente – Error');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_Matching_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string; A: Integer);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [N, A]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '2 Platzhalter, 2 Argumente – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_EscapedPercent_NotCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''100%% von %s'', [N]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '%% ist kein Platzhalter – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_NoArgs_NoPlaceholders_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Kein Platzhalter'', []));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Keine Platzhalter, leeres Array – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_WidthSpecifier_CorrectCount;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(V: Double);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Wert: %8.2f'', [V]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '%8.2f = 1 Platzhalter, 1 Argument – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_NestedInsideAdd_NoFinding;
// Results.Add(Format('%d %s',[v,k])) – Format ist verschachteltes Argument,
// kein eigenständiger Aufruf → kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Results.Add(Format(''%d  %s'', [Pair.Value, Pair.Key]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Format() als Argument in Add() – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_StringContentParsed_CorrectCount;
// Stellt sicher dass der Lexer den String-Inhalt korrekt liest.
// '%s ist %d Jahre alt' hat 2 Platzhalter.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string; A: Integer);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [N, A]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Lexer liest String-Inhalt korrekt: 2 Platzhalter, 2 Argumente');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_EscapedQuoteInString_CorrectCount;
// Format-String mit eingebettetem '' (maskiertes Anführungszeichen).
// 'es''s %s' hat 1 Platzhalter.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''it''''s %s'', [N]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Maskiertes '' im Format-String: 1 Platzhalter, 1 Argument');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_MultipleEscapedQuotes_CorrectCount;
// Real-world mORMot-Pattern: deutsche Meldung mit zwei `'`-eingerahmten
// Bezeichnern UND einem `%s` am Ende. Der Lexer resolved `''` -> `'` und
// vor dem QuoteStrLit-Fix verlor die Stringserialisierung die Boundaries
// -> der Detektor zaehlte 0 Platzhalter statt 1 -> False-Positive
// "Format: 0 placeholders, 1 arguments".
const SRC =
  'unit t; implementation'#13#10+
  'procedure TPmtInf_CCT.plausiOK;'#13#10+
  'begin'#13#10+
  '  Self.addMessage(Format(''Eintrag ''''BIC des Zahlers'''' fehlt: '+
                            '<DbtrAgt><FinInstnId><BIC>%s'', [Self.FBIC]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Zwei eingebettete '' + %s am Ende: 1 Platzhalter, 1 Argument');
  finally F.Free; end;
end;

// =============================================================================
// FormatMismatch-Erweiterung
// =============================================================================

procedure TTestFormatMismatchExt.Format_OnePlaceholderTwoArgs_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := Format(''%s'', [a, b]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFormatMismatch) >= 1);
  finally F.Free; end;
end;

procedure TTestFormatMismatchExt.Format_AssignmentWithoutDot_ReportsError;
// Vor dem Fix in TryExtractFormatString akzeptierte der Vorgaenger-Filter
// nur '.' - 'Result := Format(...)' (Whitespace davor) wurde uebersehen.
// Jetzt: alles was kein Identifier-Char ist, ist erlaubt.
const SRC =
  'unit t; implementation'#13#10+
  'function Foo(v: Integer): string;'#13#10+
  'begin'#13#10+
  '  Result := Format(''%d %s'', [v]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFormatMismatch) >= 1,
      'Format() direkt nach := muss als Mismatch erkannt werden');
  finally F.Free; end;
end;

// =============================================================================
// Bare-Style (mORMot FormatUtf8/FormatString)
// =============================================================================

procedure TTestFormatMismatchBareStyle.FormatUtf8_TwoBarePercents_TwoArgs_NoFinding;
// Real-world Pattern aus mORMot: '%_%' = 2 Platzhalter, durch literales '_'
// getrennt. Mit Standard-Format()-Counting waere '%' ohne Type-Letter
// uebersprungen worden -> 1 Platzhalter -> False-Positive.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(name: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatUtf8(''%_%'', [NowUtc, name]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'FormatUtf8 Bare-%: 2 Platzhalter, 2 Argumente - kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.FormatUtf8_OneBarePercent_TwoArgs_ReportsError;
// Echter Mismatch: 1 Bare-% vs 2 Argumente.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(a, b: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatUtf8(''only %'', [a, b]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      'FormatUtf8 Bare-%: 1 Platzhalter, 2 Argumente - Error');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.FormatString_BarePercentSeparator_NoFinding;
// FormatString akzeptiert dasselbe Bare-%-Pattern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(a, b: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatString(''% + %'', [a, b]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'FormatString Bare-%: 2 Platzhalter, 2 Argumente - kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.FormatUtf8_DoublePercent_ConsumesTwoArgs;
// mORMot's TFormatUtf8.Parse macht KEIN '%%'-Escape: jedes '%' konsumiert
// das naechste Argument. '%%' = 2 Platzhalter, nicht 1 Escape.
// Real-world Pattern aus mORMot: FormatUtf8('%%>=:(%):...', [Where, FieldName, ...])
// haengt Where und FieldName ohne Trenner aneinander.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(prev, field: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatUtf8(''%%>='', [prev, field]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'mORMot: %% = 2 Platzhalter, 2 Argumente - kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.StandardFormat_PercentUnderscore_StillReportsMismatch;
// Wichtige Nicht-Regression: Standard-Format() darf NICHT als Bare-Style
// behandelt werden. '%_%' im normalen Format() = 1 unvollstaendiger
// Spezifier (verschluckt das _ und das nachfolgende %), 0 oder 1 Platzhalter
// vs 2 Argumente -> Mismatch erwartet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(a, b: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := Format(''%_%'', [a, b]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFormatMismatch) >= 1,
      'Standard-Format() bleibt streng - %_% ohne Type-Letter ist Mismatch');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.FormatUtf8_ConcatenatedLiteral_AllPlaceholdersCounted;
// Real-world Pattern aus mORMot-Demos: SQL-String aufgeteilt ueber mehrere
// Zeilen via 'SELECT...' + 'WHERE %=...'. Beide Teile muessen zusammen-
// gefuehrt werden bevor Platzhalter gezaehlt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(id: Integer);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatUtf8(''SELECT * FROM Customer '' +'#13#10+
  '         ''WHERE Id=%'', [id]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'String-Konkatenation: 1 Bare-% im 2. Literal-Teil, 1 Argument - kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatchBareStyle.FormatUtf8_ConcatenatedLiteral_MismatchAcrossSplit_ReportsError;
// Detector muss auch echte Mismatches in zusammengesetzten Literalen finden.
// 'a%' + '%b' = 2 Platzhalter, 1 Argument -> Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(x: string);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := FormatUtf8(''SELECT % '' + ''WHERE %=1'', [x]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      'Konkatenation mit echtem Mismatch: 2 Platzhalter, 1 Argument - Befund');
  finally F.Free; end;
end;

end.
