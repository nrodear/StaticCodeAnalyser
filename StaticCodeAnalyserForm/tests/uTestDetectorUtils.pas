unit uTestDetectorUtils;

// Direkte Unit-Tests fuer die zentrale String-/Kommentar-Zustandsmaschine
// in TDetectorUtils (ScanCodeLine / StripStringsAndComments). Diese Logik
// war frueher in uFloatEquality und uNoSonarMarker dupliziert - jeder
// Drift dort war ein potenzieller False-Positive. Die Tests pinnen das
// Verhalten fest, damit beide Detektoren auf einer gepruefen Basis stehen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDetectorUtils = class
  public
    // ---- ScanCodeLine ----
    [Test] procedure PlainCode_NoCommentNoChange;
    [Test] procedure LineComment_TruncatedAndColReported;
    [Test] procedure StringLiteral_FilledNotComment;
    [Test] procedure SlashSlashInsideString_NotAComment;
    [Test] procedure BraceComment_Removed;
    [Test] procedure EscapedQuote_StringStaysOpen;
    [Test] procedure MultiLineBraceComment_StateCarried;
    [Test] procedure MultiLineParenStarComment_StateCarried;
    // ---- StripStringsAndComments ----
    [Test] procedure Strip_LineForCharMapsToSourceLine;
    [Test] procedure Strip_EmptyStringKeepsFollowingKeyword;
    [Test] procedure Strip_NewlinePerSourceLine;
    // ---- BlankStringLiterals vs. StripStringLiterals (Fund 4) ----
    [Test] procedure Blank_KeepsLengthAndPositions;
    [Test] procedure Blank_EscapedQuoteBlankedAndLengthKept;
    [Test] procedure Strip_ShiftsPositions_GegenprobeZuBlank;
    // ---- IsTestFixturePath / Strenge-Stufen (Fund 3) ----
    [Test] procedure TestPath_SecretLevel_SpecDirIsTest;
    [Test] procedure TestPath_SecretLevel_UtestimonialsIsNotTest;
    [Test] procedure TestPath_SecretLevel_UtestDirAndUtestFileStillTest;
    [Test] procedure TestPath_SecretLevel_TestSuffixFilesStillTest;
    [Test] procedure TestPath_LevelsStayDifferent_SampleAndDemo;
    [Test] procedure TestPath_FixtureLevel_UnchangedPatterns;
    // ---- MergeAdjacentStringLiterals ----
    [Test] procedure Merge_SimpleConcat;
    [Test] procedure Merge_NoSpaceAroundPlus;
    [Test] procedure Merge_ChainedThreeLiterals;
    [Test] procedure Merge_EscapedQuotePreservedInsideLiteral;
    [Test] procedure Merge_PlusOutsideLiterals_Untouched;
    [Test] procedure Merge_NoLiterals_Unchanged;
    // ---- UnqualifiedNameLast (Restschulden-Audit 2026-07-26) ----
    [Test] procedure Unqualified_SimpleQualified_LastSegment;
    [Test] procedure Unqualified_NestedType_TakesLastDotNotFirst;
    [Test] procedure Unqualified_NoDot_Unchanged;
    [Test] procedure Unqualified_EmptyAndTrailingDot;
    [Test] procedure Unqualified_LowerVariant_LowercasesLastSegment;
    // ---- IsIdentChar / Zeichenklasse (Backlog-Welle 1, 2026-07-26) ----
    [Test] procedure IdentChar_LettersAndDigitsAndUnderscore;
    [Test] procedure IdentChar_RangeNeighboursAreNoIdent;
    [Test] procedure IdentChar_DotAndDollarAreNoIdent;
    [Test] procedure IdentChar_UmlautAndNonAsciiAreNoIdent;

    // --- Besitzertyp einer Methode (2026-07-27) ---
    [Test] procedure OwnerType_SingleQualifier_IsTheClass;
    [Test] procedure OwnerType_NestedType_IsTheInnerType;
    [Test] procedure OwnerType_Unqualified_IsEmpty;
    [Test] procedure OwnerType_EdgeCases_AreBounded;
    [Test] procedure IsNestedTypeMethodName_CountsQualifiers;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils;

{ ---- ScanCodeLine ---- }

procedure TTestDetectorUtils.PlainCode_NoCommentNoChange;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('x := y + 1;', State, Col);
  Assert.AreEqual('x := y + 1;', R);
  Assert.AreEqual<Integer>(0, Col);
end;

procedure TTestDetectorUtils.LineComment_TruncatedAndColReported;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // 'DoStuff; // NOSONAR' -> '//' beginnt auf Spalte 10 (1-basiert).
  R := TDetectorUtils.ScanCodeLine('DoStuff; // NOSONAR', State, Col);
  Assert.AreEqual<Integer>(10, Col);
  Assert.IsTrue(R.StartsWith('DoStuff;'), 'Code vor // bleibt erhalten');
  Assert.AreEqual<Integer>(0, Pos('NOSONAR', R), 'Kommentartext darf nicht im Code sein');
end;

procedure TTestDetectorUtils.StringLiteral_FilledNotComment;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('s := ''hello'';', State, Col);
  Assert.AreEqual<Integer>(0, Col, 'kein Zeilenkommentar');
  Assert.AreEqual<Integer>(0, Pos('hello', R), 'String-Inhalt wird ersetzt');
  Assert.IsTrue(Pos('~', R) > 0, 'Fuellzeichen steht fuer den String');
end;

procedure TTestDetectorUtils.SlashSlashInsideString_NotAComment;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // Das `//` steckt im String-Literal - es ist KEIN Zeilenkommentar.
  R := TDetectorUtils.ScanCodeLine('s := ''// not a comment'';', State, Col);
  Assert.AreEqual<Integer>(0, Col, '// im String ist kein Kommentar');
  Assert.AreEqual<Integer>(0, Pos('/', R), 'kein Slash bleibt uebrig (String gefuellt)');
end;

procedure TTestDetectorUtils.BraceComment_Removed;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('a := 1; { note } b := 2;', State, Col);
  Assert.AreEqual<Integer>(0, Col);
  Assert.AreEqual<Integer>(0, Pos('note', R), 'Block-Kommentar entfernt');
  Assert.IsTrue(Pos('b := 2;', R) > 0, 'Code nach } bleibt erhalten');
  Assert.IsFalse(State.InBraceComment, 'Block auf derselben Zeile geschlossen');
end;

procedure TTestDetectorUtils.EscapedQuote_StringStaysOpen;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // 'it''s' ist EIN String mit verdoppeltem Apostroph - bleibt offen bis
  // zum echten Schluss-Quote. Danach ist ';' wieder Code.
  R := TDetectorUtils.ScanCodeLine('s := ''it''''s'';', State, Col);
  Assert.AreEqual<Integer>(0, Col);
  Assert.AreEqual<Integer>(0, Pos('it', R), 'String-Inhalt komplett ersetzt');
  Assert.IsTrue(R.EndsWith(';'), 'Code nach String wieder sichtbar');
end;

procedure TTestDetectorUtils.MultiLineBraceComment_StateCarried;
var
  State : TCommentScanState;
  Col   : Integer;
  R1, R2: string;
begin
  State := Default(TCommentScanState);
  R1 := TDetectorUtils.ScanCodeLine('code1 { open block', State, Col);
  Assert.IsTrue(State.InBraceComment, 'offener {-Block wird getragen');
  Assert.IsTrue(R1.StartsWith('code1'), 'Code vor { bleibt');

  R2 := TDetectorUtils.ScanCodeLine('still comment } code2;', State, Col);
  Assert.IsFalse(State.InBraceComment, 'Block auf Folgezeile geschlossen');
  Assert.AreEqual<Integer>(0, Pos('comment', R2), 'Kommentar-Rest entfernt');
  Assert.IsTrue(Pos('code2;', R2) > 0, 'Code nach } sichtbar');
end;

procedure TTestDetectorUtils.MultiLineParenStarComment_StateCarried;
var
  State : TCommentScanState;
  Col   : Integer;
  R2    : string;
begin
  State := Default(TCommentScanState);
  TDetectorUtils.ScanCodeLine('x := 1; (* open', State, Col);
  Assert.IsTrue(State.InParenComment, 'offener (*-Block wird getragen');

  R2 := TDetectorUtils.ScanCodeLine('inside *) y := 2;', State, Col);
  Assert.IsFalse(State.InParenComment, '(*-Block geschlossen');
  Assert.AreEqual<Integer>(0, Pos('inside', R2), 'Kommentar-Rest entfernt');
  Assert.IsTrue(Pos('y := 2;', R2) > 0, 'Code nach *) sichtbar');
end;

{ ---- StripStringsAndComments ---- }

procedure TTestDetectorUtils.Strip_LineForCharMapsToSourceLine;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
  P       : Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('x := ''abc'';');   // Zeile 0
    Lines.Add('// comment');      // Zeile 1
    Lines.Add('y := 1;');         // Zeile 2
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);

    Assert.AreEqual<NativeInt>(Length(Code), Length(LineFor),
      'pro Zeichen genau ein Zeilen-Mapping');
    Assert.AreEqual<Integer>(0, Pos('abc', Code), 'String-Inhalt ersetzt');
    Assert.AreEqual<Integer>(0, Pos('comment', Code), 'Zeilenkommentar entfernt');

    P := Pos('y', Code);
    Assert.IsTrue(P > 0, 'y vorhanden');
    Assert.AreEqual<Integer>(2, LineFor[P - 1], 'y stammt aus Quellzeile 2');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtils.Strip_EmptyStringKeepsFollowingKeyword;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
begin
  // Regression (vgl. uFloatEquality): `aValue = '' then` darf nach dem
  // Strippen NICHT als `aValue =   then` erscheinen, sonst kassiert eine
  // `[\w.]+`-Regex das Keyword `then` als RHS. Mit ~~ als Fueller bleibt
  // `then` ein eigenes Token und der Match scheitert korrekt am ersten ~.
  Lines := TStringList.Create;
  try
    Lines.Add('if aValue = '''' then Exit;');
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
    Assert.IsTrue(Pos('~~', Code) > 0, 'leerer String wird zu Fuellzeichen');
    Assert.IsTrue(Pos('then', Code) > 0, 'Keyword then bleibt erhalten');
    Assert.AreEqual<Integer>(0, Pos('''', Code), 'keine Apostrophe mehr im Code');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtils.Strip_NewlinePerSourceLine;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
  i, NL   : Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('a;');
    Lines.Add('b;');
    Lines.Add('c;');
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
    NL := 0;
    for i := 1 to Length(Code) do
      if Code[i] = #10 then Inc(NL);
    Assert.AreEqual<Integer>(3, NL, 'ein #10 pro Quellzeile');
  finally
    Lines.Free;
  end;
end;

{ ---- BlankStringLiterals vs. StripStringLiterals (Fund 4) ---- }

// Fund 4 (Restschulden-Audit 2026-07-26): die beiden Funktionen heissen fast
// gleich, tun aber beim Layout das GEGENTEIL. Genau diese Differenz wird hier
// festgenagelt - wer eine der beiden fuer redundant haelt und den Aufruf
// tauscht, bekommt sonst still verschobene Zeilen-/Spaltenangaben.
// Quelltext-Beispiel (Pascal): a := 'lit' + b;

procedure TTestDetectorUtils.Blank_KeepsLengthAndPositions;
const
  SRC = 'a := ''lit'' + b;';   // = Pascal-Text:  a := 'lit' + b;
var
  Blanked : string;
begin
  Blanked := TDetectorUtils.BlankStringLiterals(SRC);
  Assert.AreEqual<Integer>(Length(SRC), Length(Blanked),
    'BlankStringLiterals MUSS die Laenge erhalten');
  Assert.AreEqual<Integer>(Pos('b', SRC), Pos('b', Blanked),
    'Position hinter dem Literal bleibt unveraendert');
  Assert.AreEqual<Integer>(0, Pos('lit', Blanked),
    'Literal-Inhalt ist ausgeblendet');
  Assert.AreEqual<Integer>(2, Length(SRC) - Length(SRC.Replace('''', '')),
    'Selbstpruefung des Testdatums: genau zwei Quotes im Quelltext');
  Assert.AreEqual<Integer>(6, Pos('''', Blanked),
    'die Quotes selbst bleiben als Positions-Marker stehen');
end;

procedure TTestDetectorUtils.Blank_EscapedQuoteBlankedAndLengthKept;
const
  // Pascal-Text:  s := 'it''s' ; b
  SRC = 's := ''it''''s'' ; b';
var
  Blanked : string;
begin
  Blanked := TDetectorUtils.BlankStringLiterals(SRC);
  Assert.AreEqual<Integer>(Length(SRC), Length(Blanked),
    'auch mit ''''-Escape bleibt die Laenge gleich');
  Assert.AreEqual<Integer>(0, Pos('it', Blanked),
    'Literal-Inhalt inkl. Escape ausgeblendet');
  Assert.AreEqual<Integer>(Pos('b', SRC), Pos('b', Blanked),
    'Code hinter dem Literal behaelt seine Position');
end;

procedure TTestDetectorUtils.Strip_ShiftsPositions_GegenprobeZuBlank;
// GEGENPROBE zur Namensfalle: die entfernende Variante verschiebt alles
// hinter dem Literal. Das ist KEIN Bug - es ist der dokumentierte
// Unterschied, und dieser Test verhindert, dass jemand die beiden
// Funktionen fuer austauschbar haelt.
const
  SRC = 'a := ''lit'' + b;';
var
  Stripped : string;
begin
  Stripped := TDetectorUtils.StripStringLiterals(SRC);
  Assert.IsTrue(Length(Stripped) < Length(SRC),
    'StripStringLiterals ENTFERNT Zeichen');
  Assert.IsTrue(Pos('b', Stripped) < Pos('b', SRC),
    'Positionen hinter dem Literal verschieben sich - deshalb ist Strip fuer '
    + 'positionsempfindliche Detektoren (uDivByZero) verboten');
end;

{ ---- IsTestFixturePath / Strenge-Stufen (Fund 3) ---- }

// Fund 3 (Restschulden-Audit 2026-07-26): eine Musterliste, zwei Stufen.
// THardcodedSecretDetector.IsTestFilePath ist nur noch ein duenner Aufrufer
// von IsTestFixturePath(.., tplSecret) - deshalb pinnen diese Tests die
// Secret-Sicht direkt an der zentralen Funktion.

procedure TTestDetectorUtils.TestPath_SecretLevel_SpecDirIsTest;
begin
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\spec\uConfig.pas', '', tplSecret),
    '/spec/ ist eine Test-Konvention (rspec-Stil)');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\fixtures\uConfig.pas', '', tplSecret),
    '/fixtures/ ebenso');
end;

procedure TTestDetectorUtils.TestPath_SecretLevel_UtestimonialsIsNotTest;
// FP-FIX: frueher Pos('/utest', Norm) ohne Verankerung - '/utestimonials/'
// traf zu und der Secret-Detektor schwieg dort komplett.
begin
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath(
    'd:\repo\utestimonials\uConfig.pas', '', tplSecret),
    '/utestimonials/ ist KEIN Testverzeichnis - der unverankerte /utest-'
    + 'Match war ein False-Positive der Test-Erkennung');
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath(
    'd:\repo\utestimonials\uConfig.pas', '', tplFixture),
    'auch in der Fixture-Stufe nicht');
end;

procedure TTestDetectorUtils.TestPath_SecretLevel_UtestDirAndUtestFileStillTest;
// GEGENPROBE zum FP-Fix: die gemeinte Konvention bleibt erkannt - als
// Verzeichnis 'utest'/'utests' und als Dateiname 'uTestXxx.pas'.
begin
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\utest\uConfig.pas', '', tplSecret), 'Verzeichnis /utest/');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\utests\uConfig.pas', '', tplSecret), 'Verzeichnis /utests/');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\uTestHelpers.pas', '', tplSecret), 'Dateiname uTestXxx.pas');
end;

procedure TTestDetectorUtils.TestPath_SecretLevel_TestSuffixFilesStillTest;
// Die aus uHardcodedSecret uebernommenen Muster gelten unveraendert weiter.
// MatchesMask vergleicht case-insensitiv, deshalb reichen Kleinschreib-Masken.
begin
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\FrameworkTestsU.pas', '', tplSecret), '*TestsU.pas');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\AuthSpec.pas', '', tplSecret), '*Spec.pas');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\LoginTest.pas', '', tplSecret), '*Test.pas');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\unittests\uConfig.pas', '', tplSecret), 'Segment-Anfang unittest*');
end;

procedure TTestDetectorUtils.TestPath_LevelsStayDifferent_SampleAndDemo;
// Kern der Strenge-Stufe: EINE Liste, aber die Konsumenten bleiben
// unterschiedlich streng. Demo-/Sample-Files sind Fixtures (Post-Filter),
// aber KEIN Freibrief fuer hardcodierte Secrets.
begin
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\uOrderSample.pas', '', tplFixture),
    'Sample ist ein Fixture-Pattern');
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath(
    'd:\repo\src\uOrderSample.pas', '', tplSecret),
    'in der Secret-Sicht ist ein Sample-File KEIN Test - ein echtes Secret '
    + 'dort bleibt meldepflichtig');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath(
    'd:\repo\demos\uMain.pas', '', tplFixture), '/demos/ ist Fixture');
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath(
    'd:\repo\demos\uMain.pas', '', tplSecret), '/demos/ ist kein Secret-Skip');
end;

procedure TTestDetectorUtils.TestPath_FixtureLevel_UnchangedPatterns;
// Regressions-Anker: die Default-Stufe muss sich exakt wie vor der
// Zusammenlegung verhalten (Konsumenten: Console-Runner, uUninitVar).
begin
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath('d:\repo\src\uTestFoo.pas'),
    'uTest*.pas');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath('d:\repo\src\Foo_Tests.pas'),
    '*_Tests.pas');
  Assert.IsTrue(TDetectorUtils.IsTestFixturePath('d:\repo\resources\uFoo.pas'),
    '/resources/');
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath('d:\repo\src\uOrders.pas'),
    'normale Unit ist kein Fixture');
  // BaseDir-Anchoring bleibt: '/tests/' ausserhalb der Repo-Wurzel zaehlt nicht.
  Assert.IsFalse(TDetectorUtils.IsTestFixturePath(
    'd:\projects\company-tests\src\auth.pas', 'd:\projects\company-tests'),
    'Segment ausserhalb von BaseDir darf nicht matchen');
end;

{ ---- MergeAdjacentStringLiterals ---- }

procedure TTestDetectorUtils.Merge_SimpleConcat;
// 'foo' + 'bar' -> 'foobar'  - der Klassiker.
const Source = '''foo'' + ''bar''';
const Expected = '''foobar''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_NoSpaceAroundPlus;
// 'foo'+'bar' (kein Space) - exakt die Form die uSqlDangerousStatement
// im AST-Lowercase sieht und an der die WHERE-Erkennung scheiterte.
const Source = '''foo''+''bar''';
const Expected = '''foobar''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_ChainedThreeLiterals;
// 'a' + 'b' + 'c' -> 'abc' - Kette wird bis zum Ende aufgeloest.
const Source = '''a'' + ''b'' + ''c''';
const Expected = '''abc''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_EscapedQuotePreservedInsideLiteral;
// Verdoppelte Apostrophen ('') innerhalb des Literals duerfen NICHT als
// Literal-Ende interpretiert werden - sie sind ein Escape und bleiben
// als '' im Output. Quelle: 'a''b' + 'c' -> 'a''bc'.
const Source = '''a''''b'' + ''c''';
const Expected = '''a''''bc''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_PlusOutsideLiterals_Untouched;
// '+' das nicht zwischen zwei Literalen steht (z.B. zwischen Literal
// und Variable) bleibt unangetastet - sonst wuerden wir Ausdruecke
// faelschlich zusammenkleben.
const Source = '''foo'' + xVar';
const Expected = '''foo'' + xVar';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_NoLiterals_Unchanged;
// Komplett ohne String-Literale - identitaet.
const Source = 'a + b + c';
const Expected = 'a + b + c';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

{ ---- UnqualifiedNameLast ---- }
// Restschulden-Audit 2026-07-26: die Routine war in 8 Detektoren kopiert -
// 7x als Rueckwaerts-Scan (LETZTER Punkt), 1x in uCanBeClassMethod als
// Pos('.') (ERSTER Punkt). Diese Tests pinnen die zentrale Semantik fest,
// damit die Abweichung nicht ueber eine neue Kopie zurueckkommt.

procedure TTestDetectorUtils.Unqualified_SimpleQualified_LastSegment;
begin
  Assert.AreEqual('Bar', TDetectorUtils.UnqualifiedNameLast('TFoo.Bar'));
end;

procedure TTestDetectorUtils.Unqualified_NestedType_TakesLastDotNotFirst;
// DER Bugfix-Fall: bei mehr als einem Punkt (nested type) lieferte die
// Pos-Fassung 'TInner.DoIt'. Erwartet ist das LETZTE Segment.
begin
  Assert.AreEqual('DoIt',
    TDetectorUtils.UnqualifiedNameLast('TOuter.TInner.DoIt'),
    'nested type: es zaehlt der LETZTE Punkt, nicht der erste');
  Assert.AreEqual('Bar',
    TDetectorUtils.UnqualifiedNameLast('TUnit.TOuter.TInner.Bar'));
end;

procedure TTestDetectorUtils.Unqualified_NoDot_Unchanged;
// Gegenprobe: ohne Punkt bleibt der Name unveraendert (Interface-Decls
// tragen den blanken Member-Namen).
begin
  Assert.AreEqual('Bar', TDetectorUtils.UnqualifiedNameLast('Bar'));
end;

procedure TTestDetectorUtils.Unqualified_EmptyAndTrailingDot;
// Randfaelle: Leerstring bleibt leer, Punkt am Ende ergibt ein leeres
// Segment (die Aufrufer pruefen deshalb auf '' bevor sie indizieren).
begin
  Assert.AreEqual('', TDetectorUtils.UnqualifiedNameLast(''));
  Assert.AreEqual('', TDetectorUtils.UnqualifiedNameLast('TFoo.'));
end;

procedure TTestDetectorUtils.Unqualified_LowerVariant_LowercasesLastSegment;
// Lower-Variante = LowerCase(UnqualifiedNameLast) - ersetzt die
// LastDelimiter+LowerCase-Fassung aus uConstStringParameter 1:1.
begin
  Assert.AreEqual('bar', TDetectorUtils.UnqualifiedNameLastLower('TFoo.Bar'));
  Assert.AreEqual('doit',
    TDetectorUtils.UnqualifiedNameLastLower('TOuter.TInner.DoIt'));
  Assert.AreEqual('bar', TDetectorUtils.UnqualifiedNameLastLower('Bar'));
end;

{ ---- IsIdentChar / Zeichenklasse (Backlog-Welle 1, 2026-07-26) ---- }
// Diese vier Tests pinnen die Zeichenklasse fest, auf die in dieser Welle
// 46 lokale Ausrollungen in Detektor-Units zusammengefuehrt wurden. Jede
// spaetere Erweiterung der Klasse (z.B. Punkt oder Umlaute) verschiebt
// Wortgrenzen und damit Fundgrenzen in ALLEN diesen Detektoren - die Tests
// sind dafuer die Reissleine.

procedure TTestDetectorUtils.IdentChar_LettersAndDigitsAndUnderscore;
// Positivfall inkl. der Bereichsgrenzen selbst.
//
// EHRLICHE EINORDNUNG (Review-Fund A-2, Backlog-Welle 1): diese Tests waren
// auch VOR der Zentralisierung gruen - sie pruefen TDetectorUtils.IsIdentChar,
// und genau diese Funktion wurde nicht angefasst. Sie beweisen also NICHT,
// dass die 46 ersetzten Wrapper-Rueumpfe korrekt sind; dieser Nachweis lief
// ueber den erschoepfenden Zeichenmengen-Vergleich aller 46 Ausgangsformen
// gegen HEAD (6 verschiedene Schreibweisen, alle mengengleich) plus das
// byte-identische Korpus-A/B.
// Ihr Wert ist ein anderer und seit der Welle GROESSER: die Zeichenklasse
// dieser einen Funktion traegt jetzt 46 Units. Wer sie hier um '.' oder '$'
// erweitert, verschiebt Wortgrenzen in allen 46 gleichzeitig - deshalb sind
// die Grenzfaelle unten festgenagelt. Die lokalen Wrapper selbst sind
// implementation-level und von aussen nicht testbar.
begin
  Assert.IsTrue(TDetectorUtils.IsIdentChar('a'), 'a');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('z'), 'z');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('A'), 'A');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('Z'), 'Z');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('0'), 'Ziffer 0');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('9'), 'Ziffer 9');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('5'), 'Ziffer mittendrin');
  Assert.IsTrue(TDetectorUtils.IsIdentChar('_'),
    'Unterstrich gehoert zum Identifier');
end;

procedure TTestDetectorUtils.IdentChar_RangeNeighboursAreNoIdent;
// Off-by-one-Gegenprobe: das Zeichen direkt VOR und direkt HINTER jedem
// Bereich muss False liefern. Bewusst als Ordinal-Literale notiert, damit
// der Test nicht von der Quelltext-Codierung abhaengt.
begin
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#47), 'vor 0');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#58), 'hinter 9');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#64), 'vor A');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#91), 'hinter Z');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#94), 'vor _');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#96), 'hinter _ bzw. vor a');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#123), 'hinter z');
end;

procedure TTestDetectorUtils.IdentChar_DotAndDollarAreNoIdent;
// Der Punkt ist der wichtigste Fall: er zaehlt NICHT mit, damit in
// 'mytable.sql' rechts vom Punkt eine Wortgrenze erkannt wird. Das
// Dollarzeichen (Hex-Praefix) gehoert ebenfalls nicht zum Identifier.
begin
  Assert.IsFalse(TDetectorUtils.IsIdentChar('.'),
    'Punkt ist Qualifier-Trenner, kein Identifier-Zeichen');
  Assert.IsFalse(TDetectorUtils.IsIdentChar('$'), 'Dollar');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(' '), 'Leerzeichen');
  Assert.IsFalse(TDetectorUtils.IsIdentChar('('), 'Klammer auf');
end;

procedure TTestDetectorUtils.IdentChar_UmlautAndNonAsciiAreNoIdent;
// Umlaute sind in Delphi zwar gueltige Identifier-Zeichen, die zentrale
// Fassung ist aber bewusst ASCII-only - genau wie alle 46 zusammen-
// gefuehrten lokalen Fassungen (CharInSet liefert fuer WideChar > #255
// ebenfalls False). Diese Gleichheit ist die Neutralitaets-Zusicherung
// der Zusammenfuehrung und wird hier festgenagelt.
begin
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#$00E4), 'kleines a-Umlaut');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#$00C4), 'grosses A-Umlaut');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#$00DF), 'scharfes s');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#$0100), 'Latin Extended-A');
  Assert.IsFalse(TDetectorUtils.IsIdentChar(#$20AC), 'Euro-Zeichen');
end;

{ ---- Besitzertyp einer Methode (2026-07-27) ----

  OwnerTypeName liefert das VORLETZTE Segment eines qualifizierten
  Methodennamens. Der Unterschied zu 'alles vor dem letzten Punkt' zeigt sich
  erst bei nested types - und genau dort liefen vier Detektor-Guards ins
  Leere, weil sie einen gepunkteten String als Typnamen nachschlugen.        }

procedure TTestDetectorUtils.OwnerType_SingleQualifier_IsTheClass;
// Der Normalfall - hier sind beide Semantiken gleich, das muss so bleiben.
begin
  Assert.AreEqual('TFoo', TDetectorUtils.OwnerTypeName('TFoo.Bar'),
    'bei einem Qualifizierer ist der Besitzer die Klasse');
  Assert.AreEqual('tfoo', TDetectorUtils.OwnerTypeNameLower('TFoo.Bar'),
    'Lower-Variante muss kleinschreiben');
end;

procedure TTestDetectorUtils.OwnerType_NestedType_IsTheInnerType;
// Der Kern: Besitzer ist der INNERE Typ, nicht der aeussere und nicht der
// gepunktete Pfad.
begin
  Assert.AreEqual('TInner', TDetectorUtils.OwnerTypeName('TOuter.TInner.DoIt'),
    'Besitzer einer nested-type-Methode ist der innere Typ');
  Assert.AreEqual('TC', TDetectorUtils.OwnerTypeName('TA.TB.TC.Run'),
    'bei drei Qualifizierern zaehlt ebenfalls das vorletzte Segment');
  Assert.AreNotEqual('TOuter.TInner',
    TDetectorUtils.OwnerTypeName('TOuter.TInner.DoIt'),
    'ein gepunkteter Pfad matcht gegen keinen Typnamen - genau der Fehler');
end;

procedure TTestDetectorUtils.OwnerType_Unqualified_IsEmpty;
// Freistehende Routine: kein Besitzertyp.
begin
  Assert.AreEqual('', TDetectorUtils.OwnerTypeName('FreieRoutine'),
    'ohne Qualifizierer gibt es keinen Besitzertyp');
end;

procedure TTestDetectorUtils.OwnerType_EdgeCases_AreBounded;
// Kaputte/entartete Eingaben duerfen nicht ueberlaufen.
begin
  Assert.AreEqual('', TDetectorUtils.OwnerTypeName(''),
    'leerer Name');
  Assert.AreEqual('', TDetectorUtils.OwnerTypeName('.Foo'),
    'fuehrender Punkt hat kein vorletztes Segment');
  Assert.AreEqual('TFoo', TDetectorUtils.OwnerTypeName('TFoo.'),
    'nachgestellter Punkt: davor steht der Besitzer');
  Assert.AreEqual('', TDetectorUtils.OwnerTypeName('..'),
    'nur Punkte ergeben keinen Namen');
end;

procedure TTestDetectorUtils.IsNestedTypeMethodName_CountsQualifiers;
begin
  Assert.IsFalse(TDetectorUtils.IsNestedTypeMethodName('FreieRoutine'),
    'ohne Punkt kein nested type');
  Assert.IsFalse(TDetectorUtils.IsNestedTypeMethodName('TFoo.Bar'),
    'ein Qualifizierer ist der Normalfall, kein nested type');
  Assert.IsTrue(TDetectorUtils.IsNestedTypeMethodName('TOuter.TInner.DoIt'),
    'zwei Qualifizierer = nested type');
  Assert.IsTrue(TDetectorUtils.IsNestedTypeMethodName('TA.TB.TC.Run'),
    'drei Qualifizierer ebenfalls');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDetectorUtils);

end.
