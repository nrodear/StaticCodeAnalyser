unit uTestExportHtml;

// Tests fuer TExporterHtml (Infrastructure/uExportHtml.pas).
// Fokus: FR-i18n-Unicode-Escapes (Bug Doku_06_CLI_LSP_Reporting.md #21).
// Delphi-Strings kennen kein Backslash-Escaping - ein '\\u00e9' im
// Pascal-Literal landet als Doppel-Backslash im generierten JS und wird
// dort zum literalen Text '\u00e9' statt zum Akzentzeichen.
// Strategie: Report in eine Temp-Datei schreiben, als UTF-8 zuruecklesen
// und den JS-I18N-Block auf korrekte Escapes pruefen (Datei-Harness,
// da TExporterHtml.Run direkt auf Datei schreibt).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts, uExportHtml;

type
  [TestFixture]
  TTestExportHtml = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
    function RenderReport: string;
  public
    // Fix-Test: FR-Block emittiert \uXXXX mit genau EINEM Backslash.
    [Test] procedure FrI18nEscapesHaveSingleBackslash;
    // TP-Gegenprobe: legitime JS-Escapes (\" fuer Anfuehrungszeichen im
    // JS-String) bleiben vom Fix unberuehrt.
    [Test] procedure JsQuoteEscapesStayIntact;
    // T1 (HTML-Review 2026-08-05): Zeilenbudget gegen den OOM und der
    // stueckweise Schreiber, der die drei Vollkopien abloest.
    [Test] procedure MaxRows_Truncates_AndNamesTheGap;
    [Test] procedure MaxRows_Zero_RendersEverything;
    [Test] procedure MaxRows_BelowLimit_ShowsNoBanner;
    [Test] procedure ChunkedWrite_SplitsBetweenSurrogates_Intact;
    // T6 (HTML-Review 2026-08-05): ein zerlegter Teilen-Link darf die
    // Initialisierung nicht kippen.
    [Test] procedure UrlHash_NoValueInsideSelector;
    [Test] procedure UrlHash_BlockCatchesExceptions;
    // Aggregierter Regel-Report (2026-08-26): eine Zeile je REGEL,
    // Severity-/Konfidenz-Aufteilung, Anteil ohne Locale-Dezimal-
    // trenner (dieselbe Ganzzahl-Regel wie beim Donut).
    [Test] procedure RuleReport_AggregatesPerRule;
    [Test] procedure RuleReport_ShareUsesIntegerMath;
    // Schwesterpfad-Probe zum Baseline-Befund (2026-08-28).
    [Test] procedure ControlCharInMessage_NoRawControlCharInReport;
    // Ausgabevertrag-Runde 2026-09-06 (Nutzerauftrag "fuer die beiden
    // HTML soll es Tests geben"): Escaping der Fund-Felder, JS-Geruest
    // samt Init-Aufrufen, Sonderfaelle und Determinismus-Kette.
    [Test] procedure FindingFields_ScriptPayload_EscapedEverywhere;
    [Test] procedure FileNameSpecialChars_EscapedInDropdownAndRowAttrs;
    [Test] procedure JsSkeleton_CoreFunctionsWiredAndInitialized;
    [Test] procedure FileReadError_OwnRowClass_NotCountedAsError;
    [Test] procedure EmptyFindings_SkeletonValid_ChartsSuppressed;
    [Test] procedure ReportFile_HasUtf8Bom_AndDecodesAsUtf8;
    [Test] procedure DefaultFileName_SchemeAndTimestampPinning;
    // Der ISO-Zeitstempel, der den Report unauffindbar machte.
    [Test] procedure DefaultFileName_IsoZeitstempelWirdEntschaerft;
    [Test] procedure PinnedTimestamp_SameValueInMetaLineAndJson;
    [Test] procedure SearchBlob_LowersUmlautsLikeTheJsQuery;
    // Nutzerwunsch 07.09.: Vorher/Nachher in der Hint-Zeile stehen
    // UNTEREINANDER und jeder Codeblock traegt zwei Leerzeilen Luft.
    [Test] procedure HintCodePair_StackedWithTrailingBlankLines;
    // Charge 18 (07.09., "alles soll sich gleich anfuehlen"): der
    // Report traegt das Workbench-Designsystem der Detector-Info-Seite.
    [Test] procedure Report_WearsWorkbenchLook;
    // Charge 18 (07.09., Nachauftrag): Befund-Details oeffnen seitlich
    // im Drawer wie im Detektor-Katalog - die Klappzeile ist Geschichte.
    [Test] procedure FindingDetails_OpenInSideDrawer;
  end;


implementation

// noinspection-file DuplicateString, HardcodedPath, GodClass, LargeClass
// Fixture-Ausnahme des Profils: '.html'/'x not freed' wiederholen sich
// als Pruefgegenstand; die C:-Pfade im DefaultFileName-Fall SIND der
// getestete Namensvertrag. GodClass/LargeClass: eine DUnitX-Fixture
// waechst mit jedem Vertragsfall (inzwischen 23) - die Testmethoden
// sind der Katalog, eine Aufspaltung duplizierte nur die Render-Helfer.

uses
  System.IOUtils, Winapi.Windows;

// Der Pfad steht in drei Fixtures - einmal benannt statt dreimal
// getippt (sonst meldet der Selfscan DuplicateString).
const
  FIXTURE_PAS = 'src\Foo.pas';

function NeueTempDatei(const APrefix, AExt: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    APrefix + TGUID.NewGuid.ToString + AExt);
end;

function RenderCapped(ACount, AMaxRows: Integer): string;
// ACount Funde ueber den ganzen Bericht - SourceFile bleibt leer,
// sonst filtert die Tabelle schon vor dem Budget weg.
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  i        : Integer;
  Fnd      : TLeakFinding;
begin
  Result   := '';
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to ACount do
    begin
      Fnd := TLeakFinding.Create;
      Fnd.SetKind(fkMemoryLeak);
      Fnd.FileName   := FIXTURE_PAS;
      Fnd.LineNumber := IntToStr(i);
      Fnd.MissingVar := 'list' + IntToStr(i) + ' not freed';
      Fnd.MethodName := 'TestMethod';
      Findings.Add(Fnd);
    end;
    Fn := NeueTempDatei('sca-test-cap-', '.html');
    TExporterHtml.Run(Findings, '', Fn, '', AMaxRows);
    Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
    if TFile.Exists(Fn) then
    begin
      TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
end;

function RoundTripBuilder(ABuilder: TStringBuilder): string;
// Puffer wegschreiben und zurueckholen. Eigene Routine, damit der
// Test nicht zwei ineinander liegende try-Bloecke braucht.
var
  Fn : string;
begin
  Fn := NeueTempDatei('sca-test-chunk-', '.txt');
  try
    TExporterHtml.SaveBuilderUtf8WithBom(ABuilder, Fn);
    Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
  finally
    if TFile.Exists(Fn) then
    begin
      TFile.Delete(Fn);
    end;
  end;
end;

function RenderFindings(Findings: TObjectList<TLeakFinding>): string;
// Beliebige Fixture-Liste rendern und zuruecklesen (Repo-Modus,
// SourceFile leer - sonst filtert die Tabelle, Kommentar an
// RenderCapped). Die Liste gehoert dem AUFRUFER.
var
  Fn : string;
begin
  Fn := NeueTempDatei('sca-test-vertrag-', '.html');
  try
    TExporterHtml.Run(Findings, '', Fn, '');
    Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
  finally
    if TFile.Exists(Fn) then
    begin
      TFile.Delete(Fn);
    end;
  end;
end;

procedure MitGepinntemZeitstempel(const APin: string; AProc: TProc);
// SCA_REPORT_TIMESTAMP setzen, AProc laufen lassen, IMMER restaurieren -
// Prozess-Umgebung ist globaler State, den jeder Lauf zuruecknehmen
// muss (Lexer-Kontaminations-Lehre der Chargen 13).
//
// RESTAURIEREN heisst seit dem 08.09. wirklich restaurieren: bis dahin
// LOESCHTE das finally die Variable, statt den vorherigen Wert
// zurueckzuschreiben. In einem CI-Lauf, der SCA_REPORT_TIMESTAMP
// prozessweit setzt - genau der Anwendungsfall, fuer den es die
// Variable gibt -, riss der erste Aufruf sie fuer alle nachfolgenden
// Tests ab (Chargen-Review, MINOR).
var
  Vorher    : string;
  WarGesetzt: Boolean;
begin
  // QUALIFIZIERT: Winapi.Windows steht in dieser Unit ZULETZT im uses
  // und bringt ein gleichnamiges GetEnvironmentVariable mit voellig
  // anderer Signatur (lpName, lpBuffer, nSize: DWORD) mit. Unqualifiziert
  // gewinnt die - und das ist ein Uebersetzungsfehler, kein stiller.
  Vorher     := System.SysUtils.GetEnvironmentVariable(
                  'SCA_REPORT_TIMESTAMP');
  WarGesetzt := Vorher <> '';
  Winapi.Windows.SetEnvironmentVariable('SCA_REPORT_TIMESTAMP',
    PChar(APin));
  try
    AProc;
  finally
    if WarGesetzt then
      Winapi.Windows.SetEnvironmentVariable('SCA_REPORT_TIMESTAMP',
        PChar(Vorher))
    else
      Winapi.Windows.SetEnvironmentVariable('SCA_REPORT_TIMESTAMP', nil);
  end;
end;

function TTestExportHtml.MakeFinding(Kind: TFindingKind; const Path: string;
  Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName   := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MissingVar := Msg;
  Result.MethodName := 'TestMethod';
end;

function TTestExportHtml.RenderReport: string;
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, FIXTURE_PAS, 42, 'list1 not freed'));
    Fn := TPath.Combine(TPath.GetTempPath,
      'sca-test-html-' + TGUID.NewGuid.ToString + '.html');
    try
      TExporterHtml.Run(Findings, FIXTURE_PAS, Fn);
      Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
    finally
      if TFile.Exists(Fn) then
        TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportHtml.FrI18nEscapesHaveSingleBackslash;
var
  Html : string;
begin
  Html := RenderReport;
  // Positiv: FR-Uebersetzung mit einfachem Backslash-Escape vorhanden
  // ('\u00e9' ist hier ein 6-Zeichen-ASCII-Literal, kein Escape).
  Assert.IsTrue(Pos('M\u00e9thode', Html) > 0,
    'FR-I18N-Block muss "M\u00e9thode" mit einfachem Backslash enthalten');
  // Negativ: kein Doppel-Backslash vor uXXXX mehr im gesamten Report -
  // der wuerde im Browser als literaler Text "\u00e9" gerendert.
  Assert.AreEqual(0, Pos('\\u00e9', Html),
    'Doppel-Backslash-Escape \\u00e9 darf nicht mehr vorkommen');
  Assert.AreEqual(0, Pos('\\u00a0', Html),
    'Doppel-Backslash-Escape \\u00a0 darf nicht mehr vorkommen');
end;

procedure TTestExportHtml.JsQuoteEscapesStayIntact;
var
  Html : string;
begin
  Html := RenderReport;
  // Gegenprobe: \" (escaptes Anfuehrungszeichen IN einem JS-String) ist
  // ein legitimer Einfach-Backslash-Escape und muss erhalten bleiben -
  // der FR-i18n-Fix betraf ausschliesslich \\u vor 4 Hex-Ziffern.
  Assert.IsTrue(Pos('class=\"td-qf\"', Html) > 0,
    'Legitimes JS-Quote-Escape class=\"td-qf\" muss erhalten bleiben');
end;

// Das Suchmuster steht in drei Tests - einmal benannt statt dreimal
// getippt (der Selfscan meldet sonst DuplicateString).
const
  BANNER_MARKER = 'class="trunc-banner"';

procedure TTestExportHtml.MaxRows_Truncates_AndNamesTheGap;
// Fuenf Funde, Budget zwei: drei fehlen - und der Bericht MUSS das
// sagen. Stillschweigend zu kuerzen waere schlimmer als der OOM,
// weil der Leser die Luecke dann nicht sieht.
var
  H : string;
begin
  H := RenderCapped(5, 2);
  Assert.IsTrue(H.Contains(BANNER_MARKER),
    'gekuerzter Bericht ohne sichtbaren Banner');
  Assert.IsTrue(H.Contains('data-hidden="3"'),
    'der Banner muss die Zahl der fehlenden Funde nennen');
  // Die Zusammenfassung zaehlt weiterhin ALLE Funde - genau das sagt
  // der Bannertext zu, und genau das darf nicht kippen.
  Assert.IsTrue(H.Contains('data-count="5"'),
    'die Zusammenfassung muss alle fuenf Funde zaehlen');
end;

procedure TTestExportHtml.MaxRows_Zero_RendersEverything;
// 0 ist die Notluke fuer den, der wirklich alles will.
var
  H : string;
begin
  H := RenderCapped(5, 0);
  Assert.IsFalse(H.Contains(BANNER_MARKER),
    'ohne Budget darf kein Banner erscheinen');
end;

procedure TTestExportHtml.MaxRows_BelowLimit_ShowsNoBanner;
// Gegenprobe: der Normalfall darf sich nicht veraendert haben.
var
  H : string;
begin
  H := RenderCapped(3, 10);
  Assert.IsFalse(H.Contains(BANNER_MARKER),
    'ein Bericht unter dem Budget ist nicht gekuerzt');
end;

procedure TTestExportHtml.ChunkedWrite_SplitsBetweenSurrogates_Intact;
// KERN von T1: der Schreiber holt den Puffer in Stuecken von 1 Mi
// Zeichen. Hier liegt die Grenze GENAU zwischen den beiden Haelften
// eines Surrogatpaares. Ohne die Ruecknahme um ein Zeichen kodiert
// GetBytes jede Haelfte fuer sich und schreibt zwei Ersatzzeichen -
// die Datei waere an dieser Stelle still kaputt.
const
  CHUNK = 1024 * 1024;
  HI    = #$D83D;   // erste Haelfte von U+1F600
  LO    = #$DE00;   // zweite Haelfte
var
  SB   : TStringBuilder;
  Back : string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(StringOfChar('a', CHUNK - 1));
    SB.Append(HI);          // steht auf Position CHUNK - die Grenze
    SB.Append(LO);
    SB.Append('ende');
    Back := RoundTripBuilder(SB);
    Assert.AreEqual<Integer>(SB.Length, Length(Back),
      'Laenge nach dem Rueckweg verschoben - Paar zerschnitten?');
    Assert.IsTrue(Back.Contains(HI + LO),
      'das Surrogatpaar hat die Stueckgrenze nicht heil ueberlebt');
    Assert.IsTrue(Back.EndsWith('ende'),
      'der Teil hinter der Grenze fehlt');
  finally
    SB.Free;
  end;
end;

procedure TTestExportHtml.UrlHash_NoValueInsideSelector;
// params.rule und params.file kommen aus dem URL-Hash und sind
// beliebig. Wer sie in einen querySelector einsetzt, laesst sich
// injizieren - '#rule="]' reicht. Die Option wird deshalb ueber die
// options-Liste gesucht, nicht ueber einen zusammengebauten Selektor.
var
  Html : string;
begin
  Html := RenderReport;
  Assert.IsFalse(Html.Contains('params.rule + '),
    'params.rule darf in keinen Selektor einmontiert werden');
  Assert.IsFalse(Html.Contains('params.file.replace'),
    'auch der Ersatz von Anfuehrungszeichen ist kein Schutz - '  +
    'Dateinamen unter Windows sind voll von Backslashes');
  Assert.IsTrue(Html.Contains('ruleSel.options[oi].value === params.rule'),
    'die Option muss ueber einen Wertvergleich gefunden werden');
end;

procedure TTestExportHtml.UrlHash_BlockCatchesExceptions;
// Der Block hatte nur finally. Eine Ausnahme verliess damit
// loadFromUrlHash() und riss Sprache, Theme, Tastaturbedienung und
// Baseline mit - die Seite stand still auf Deutsch und hell da.
// Schlimmstenfalls darf ein unbrauchbarer Link bedeuten, dass KEIN
// Filter gesetzt wird.
var
  Html : string;
  P    : Integer;
begin
  Html := RenderReport;
  P := Pos('function loadFromUrlHash()', Html);
  Assert.IsTrue(P > 0, 'loadFromUrlHash nicht im Bericht gefunden');
  // Der catch-Zweig muss VOR dem finally desselben Blocks stehen.
  Assert.IsTrue(Pos('} catch(e) {', Html, P) > 0,
    'der URL-Hash-Block braucht einen catch-Zweig');
  Assert.IsTrue(Pos('} catch(e) {', Html, P) <
                Pos('suspendHashSync = false;', Html, P + 1),
    'der catch muss vor dem finally des Hash-Blocks liegen');
end;


function RenderMixed: string;
// Drei Regeln mit unterschiedlichen Severities/Konfidenzen - Basis
// fuer die Aggregat-Pruefungen. SourceFile leer = Repo-Modus.
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  i        : Integer;
  Fnd      : TLeakFinding;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to 3 do
    begin
      Fnd := TLeakFinding.Create;
      Fnd.SetKind(fkMemoryLeak);          // lsError laut Katalog
      Fnd.FileName   := FIXTURE_PAS;
      Fnd.LineNumber := IntToStr(i);
      Fnd.MissingVar := 'leak' + IntToStr(i);
      Fnd.Confidence := fcHigh;
      Fnd.Severity   := lsError;
      Findings.Add(Fnd);
    end;
    Fnd := TLeakFinding.Create;
    Fnd.SetKind(fkTodoComment);           // lsHint
    Fnd.FileName   := FIXTURE_PAS;
    Fnd.LineNumber := '10';
    Fnd.MissingVar := 'TODO: x';
    Fnd.Confidence := fcMedium;
    Fnd.Severity   := lsHint;
    Findings.Add(Fnd);
    Fn := NeueTempDatei('sca-test-rr-', '.html');
    TExporterHtml.Run(Findings, '', Fn, '');
    Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
    if TFile.Exists(Fn) then TFile.Delete(Fn);
  finally
    Findings.Free;
  end;
end;

procedure TTestExportHtml.RuleReport_AggregatesPerRule;
// Der Block existiert, traegt beide Regeln und zaehlt je Regel
// richtig: MemoryLeak 3 Funde/3 Fehler, TodoComment 1 Hinweis.
var
  H : string;
begin
  H := RenderMixed;
  Assert.IsTrue(H.Contains('class="rule-report"'),
    'Regel-Report-Block muss im Bericht stehen');
  Assert.IsTrue(H.Contains('data-i18n="hdr-rule-report"'),
    'Ueberschrift traegt den i18n-Schluessel');
  Assert.IsTrue(H.Contains('data-kind="MemoryLeak"'),
    'MemoryLeak-Zeile fehlt');
  Assert.IsTrue(H.Contains('data-kind="TodoComment"'),
    'TodoComment-Zeile fehlt');
  // Die MemoryLeak-Zeile traegt Summe 3 und 3 Fehler; der Vergleich
  // laeuft ueber das Zellen-Muster, nicht ueber die ganze Zeile
  // (Spaltenreihenfolge darf sich aendern, die Werte nicht).
  Assert.IsTrue(H.Contains('<b>3</b></td><td class="num rr-e">3<'),
    'MemoryLeak: Summe 3 / Fehler 3 erwartet');
  Assert.IsTrue(H.Contains('<b>1</b></td><td class="num rr-e">0<'),
    'TodoComment: Summe 1 / Fehler 0 erwartet');
end;

procedure TTestExportHtml.RuleReport_ShareUsesIntegerMath;
// Der Anteil wird als Ganzzahl-Promille gerechnet und mit Komma
// ausgegeben - nie ueber Float/FormatFloat, deren Dezimaltrenner
// von der Locale des Laufs abhinge (Determinismus-Regel des
// Berichts, s. Donut).
var
  H : string;
begin
  H := RenderMixed;
  Assert.IsTrue(H.Contains('rr-share">75,0 %'),
    '3 von 4 Funden = 75,0 % (Ganzzahl-Promille, Komma)');
  Assert.IsTrue(H.Contains('rr-share">25,0 %'),
    '1 von 4 Funden = 25,0 %');
end;

procedure TTestExportHtml.ControlCharInMessage_NoRawControlCharInReport;
// SCHWESTERPFAD-PROBE zum Baseline-Befund (2026-08-28): der
// Baseline-Writer schrieb Steuerzeichen aus dem Meldetext ROH heraus und
// machte seine Datei damit fuer jeden strikten JSON-Parser unlesbar. Der
// HTML-Report war an dieser Stelle bereits dicht - HtmlEscape
// (uExportHtml.pas:169-170) macht &#N; daraus, und der sca-meta-Block
// geht ueber JsonForScript -> TExporter.JsonEscape - aber ungeprueft.
// Dieser Test haelt fest, dass es so bleibt; er ist vor und nach dem
// Baseline-Fix gruen.
//
// Tab bleibt bewusst roh (HtmlEscape :165) und wird deshalb nicht
// mitgezaehlt - im Markup ist er Whitespace, kein Problem.
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  Html     : string;
  Ch       : Char;
  Raw      : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, FIXTURE_PAS, 7,
      'Literal '#0' und '#4' im Text'));
    Fn := NeueTempDatei('sca-test-ctl-', '.html');
    try
      TExporterHtml.Run(Findings, FIXTURE_PAS, Fn);
      Html := TFile.ReadAllText(Fn, TEncoding.UTF8);
    finally
      if TFile.Exists(Fn) then
      begin
        TFile.Delete(Fn);
      end;
    end;
  finally
    Findings.Free;
  end;
  Raw := 0;
  for Ch in Html do
  begin
    if (Ord(Ch) < 32) and (Ch <> #13) and (Ch <> #10) and (Ch <> #9) then
    begin
      Inc(Raw);
    end;
  end;
  Assert.AreEqual(0, Raw, 'rohes Steuerzeichen im HTML-Report');
  Assert.IsTrue(Html.Contains('&#0;'),
    '#0 muss als NCR im Markup stehen');
  Assert.IsTrue(Html.Contains('&#4;'),
    '#4 muss als NCR im Markup stehen');
end;

procedure TTestExportHtml.FindingFields_ScriptPayload_EscapedEverywhere;
// XSS-Vertrag: MissingVar (Detail-Zelle), MethodName (Zelle + Blob)
// laufen durch HtmlEscape - ein <script> aus einem Fund-Text (Meldetexte
// tragen fremden Quelltext-Inhalt) darf NIE als Tag ankommen. Negativ
// bewusst auf '<script>alert' statt '<script>' - der Report traegt drei
// legitime Script-Tags (Head, sca-meta, Body-JS).
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, FIXTURE_PAS, 5,
      'x <script>alert(1)</script> & "q" ' + '''' + 'tick' + '''');
    Fnd.MethodName := 'Do<Evil>';
    Findings.Add(Fnd);
    Html := RenderFindings(Findings);
  finally
    Findings.Free;
  end;
  Assert.AreEqual<Integer>(0, Pos('<script>alert', Html),
    'Payload darf nirgends roh stehen');
  Assert.AreEqual<Integer>(0, Pos('Do<Evil>', Html),
    'Methodenname darf in keiner Zelle roh stehen');
  Assert.AreEqual<Integer>(0, Pos('do<evil>', Html),
    'Methodenname darf auch im lowercased Suchblob nicht roh stehen');
  Assert.IsTrue(Html.Contains('&lt;script&gt;alert(1)&lt;/script&gt;'),
    'Payload steht escaped in der Detail-Zelle');
  Assert.IsTrue(Html.Contains('&amp; &quot;q&quot;'),
    'Ampersand und Anfuehrungszeichen escaped');
  Assert.IsTrue(Html.Contains('&#39;tick&#39;'),
    'Apostroph escaped');
  Assert.IsTrue(Html.Contains('Do&lt;Evil&gt;'),
    'Methoden-Zelle escaped');
  Assert.IsTrue(Html.Contains('do&lt;evil&gt;'),
    'Suchblob (lowercased) escaped');
end;

procedure TTestExportHtml.FileNameSpecialChars_EscapedInDropdownAndRowAttrs;
// & und Apostroph sind unter Windows gueltige Dateinamens-Zeichen. Der
// JS-Datei-Filter vergleicht option.value exakt gegen data-file - ein
// ungeescapetes & braeche genau diese Dateien. Die Assertions sind
// praefix-agnostisch (Suffix des Anzeigenamens), damit sie nicht an
// der RelDisplayPath-Darstellung haengen.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak,
      'src\Foo & Bar' + '''' + 's.pas', 3, 'x not freed'));
    Html := RenderFindings(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Html.Contains('&amp; Bar&#39;s.pas"'),
    'Dateiname escaped in option value / data-file');
  Assert.IsTrue(Html.Contains('data-base="'),
    'Gruppen-Attribut existiert');
  Assert.IsTrue(Html.Contains('&amp; Bar&#39;s"'),
    'Basisname (ohne Extension) escaped in data-base');
  Assert.AreEqual<Integer>(0, Pos('Foo & Bar', Html),
    'der Rohname (mit rohem &) darf nirgends stehen');
end;

procedure TTestExportHtml.JsSkeleton_CoreFunctionsWiredAndInitialized;
// Kein Compiler sieht das eingebettete JS - nur dieser Test. Geprueft
// werden Kernfunktionen, Datenstrukturen UND die drei Initialisierungs-
// AUFRUFE am Script-Ende (der bestehende UrlHash-Test prueft nur den
// Funktions-KOERPER; ohne den Aufruf waeren geteilte Filter-Links tot).
var
  Html : string;
begin
  Html := RenderReport;
  Assert.IsTrue(Pos('function applyFilter()', Html) > 0, 'applyFilter fehlt');
  Assert.IsTrue(Pos('function sortBy(col)', Html) > 0, 'sortBy fehlt');
  Assert.IsTrue(Pos('function applyLanguage(lang)', Html) > 0,
    'applyLanguage fehlt');
  Assert.IsTrue(Pos('var I18N = {', Html) > 0, 'I18N-Tabelle fehlt');
  Assert.IsTrue(Pos('var ALL_KINDS = [', Html) > 0, 'ALL_KINDS fehlt');
  Assert.IsTrue(Pos('var PROFILES = {', Html) > 0, 'PROFILES fehlt');
  Assert.IsTrue(Pos('id="findingsTable"', Html) > 0, 'Tabellen-Anker fehlt');
  Assert.IsTrue(
    Pos('document.querySelectorAll(''tr.finding'').forEach(wireToggle);',
      Html) > 0, 'Toggle-Verdrahtung fehlt');
  Assert.IsTrue(Pos('sortBy(''sev'');', Html) > 0,
    'Initial-Sort-AUFRUF fehlt (Definition allein sortiert nichts)');
  // A11y (08.09.): die Sortierrichtung steckte nur in der CSS-Klasse
  // und im daraus erzeugten Pfeil - fuer Screenreader unsichtbar.
  Assert.IsTrue(Pos('th.setAttribute(''aria-sort'', '
    + 'desc ? ''descending'' : ''ascending'');', Html) > 0,
    'aria-sort wird beim Sortieren nicht gesetzt');
  Assert.IsTrue(Pos('th.removeAttribute(''aria-sort'');', Html) > 0,
    'aria-sort bleibt an der alten Spalte stehen');
  Assert.IsTrue(Pos('loadFromUrlHash();', Html) > 0,
    'loadFromUrlHash-AUFRUF fehlt');
  Assert.IsTrue(Pos('applyLanguage(SCA_LANG);', Html) > 0,
    'Sprach-Initialisierung fehlt');
end;

procedure TTestExportHtml.FileReadError_OwnRowClass_NotCountedAsError;
// A3-Vertrag (Export-Audit 2026-08-22): fkFileReadError ist eine
// Lauf-Diagnose - zaehlt in total, nicht in error, bewegt den
// Health-Score nicht, traegt Zeilenklasse 'readerr' und Sortierrang 3.
// LineNumber bewusst '7', damit kein data-sort="3" der Zeilen-Spalte
// mit dem Severity-Rang kollidiert.
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkFileReadError, 'src\Locked.pas', 7,
      'Datei nicht lesbar');
    Fnd.Severity := lsError;
    Findings.Add(Fnd);
    Html := RenderFindings(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Html.Contains('class="finding readerr"'),
    'eigene Zeilenklasse statt finding err');
  Assert.IsTrue(Html.Contains('"total":1'), 'sca-meta total zaehlt ihn');
  Assert.IsTrue(Html.Contains(',"error":0'), 'sca-meta error zaehlt ihn NICHT');
  Assert.IsTrue(Html.Contains('class="health-panel health-green"'),
    'Health bleibt gruen trotz lsError-Diagnose');
  Assert.IsTrue(Html.Contains('class="health-num">0</span>'),
    'Score bleibt 0');
  Assert.IsTrue(Html.Contains('<td class="sev" data-sort="3">'),
    'Sortierrang 3 (Tabellenende)');
  Assert.IsTrue(Html.Contains('id="count-err">0<'),
    'Fehler-Kachel bleibt 0');
end;

procedure TTestExportHtml.EmptyFindings_SkeletonValid_ChartsSuppressed;
// 0-Funde-Vertrag: vollstaendiges Dokument mit leerem Tabellen-Skelett
// (das JS greift unbedingt auf findingsTable zu), health-green,
// Zaehler 0 - und die datenabhaengigen Bloecke fehlen (deren Guards
// schuetzen auch vor der Division durch nTotal=0 im Donut).
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Html := RenderFindings(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Html.StartsWith('<!DOCTYPE html>'),
    'vollstaendiges Dokument (BOM schluckt ReadAllText)');
  Assert.IsTrue(Html.Contains('"total":0'), 'sca-meta total 0');
  Assert.IsTrue(Html.Contains('"files":0}'), 'sca-meta files 0');
  Assert.IsFalse(Html.Contains('class="chart-panel"'),
    'Donut-Block entfaellt ohne Funde');
  Assert.IsFalse(Html.Contains('class="top-detectors"'),
    'Top-Detektoren entfallen');
  Assert.IsFalse(Html.Contains('class="top-files"'),
    'Top-Dateien entfallen');
  Assert.IsTrue(Html.Contains('id="findingsTable"'),
    'Tabellen-Skelett bleibt');
  Assert.IsTrue(Html.Contains('</tbody>'), 'tbody bleibt (leer)');
  Assert.IsTrue(Html.Contains('data-count="0">0 Befunde'),
    'Zeilenzaehler 0');
  Assert.IsTrue(Html.Contains('class="health-panel health-green"'),
    'Health gruen');
end;

procedure TTestExportHtml.ReportFile_HasUtf8Bom_AndDecodesAsUtf8;
// Byte-Ebene: EF BB BF am Anfang, und das c-cedille der Sprachauswahl
// ('Fran'#$E7'ais', vom Generator emittiert) liegt als UTF-8 auf
// Platte. Der Chunked-Write-Test liest nur Text zurueck und KANN den
// BOM nicht sehen (ReadAllText schluckt ihn).
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  Bytes    : TBytes;
  Txt      : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, FIXTURE_PAS, 1, 'x not freed'));
    Fn := NeueTempDatei('sca-test-bom-', '.html');
    try
      TExporterHtml.Run(Findings, '', Fn, '');
      Bytes := TFile.ReadAllBytes(Fn);
      Txt   := TFile.ReadAllText(Fn, TEncoding.UTF8);
    finally
      if TFile.Exists(Fn) then
      begin
        TFile.Delete(Fn);
      end;
    end;
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Length(Bytes) > 3, 'Datei nicht leer');
  Assert.IsTrue((Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
    'UTF-8-BOM fehlt (Export-Konvention)');
  Assert.IsTrue(Txt.Contains('Fran' + #$E7 + 'ais'),
    'Nicht-ASCII-Inhalt liegt als gueltiges UTF-8 auf Platte');
end;

procedure TTestExportHtml.DefaultFileName_IsoZeitstempelWirdEntschaerft;
// Waechter des MAJOR vom 08.09.: ein CI-Job, der SCA_REPORT_TIMESTAMP
// mit einem ISO-Zeitstempel speist, bekam den ':' VERBATIM in den
// Dateinamen. Unter Windows ist alles ab dem ':' ein alternativer
// Datenstrom - der Report war danach nicht falsch benannt, sondern
// gar nicht mehr auffindbar.
//
// Geprueft wird beides: dass kein verbotenes Zeichen uebrig bleibt UND
// dass die Information erhalten bleibt (der Name darf nicht einfach
// abgeschnitten werden).
begin
  MitGepinntemZeitstempel('2026-09-08T14:30:00Z',
    procedure
    var
      Name : string;
    begin
      Name := TExporterHtml.DefaultFileName('', '');
      Assert.AreEqual<Integer>(0, Pos(':', Name),
        'ein Doppelpunkt im Dateinamen oeffnet unter Windows einen '
        + 'alternativen Datenstrom - der Report verschwindet still');
      Assert.AreEqual('analyse_codereview_2026-09-08T14-30-00Z.html',
        Name,
        'die verbotenen Zeichen werden ersetzt, nicht der Rest '
        + 'abgeschnitten - der Zeitstempel bleibt lesbar');
    end);
end;

procedure TTestExportHtml.DefaultFileName_SchemeAndTimestampPinning;
// Der public Namensvertrag (CLI + Form leiten den Speichernamen ab):
// analyse-Fallback, Basisname ohne Extension, _codereview_-Schema,
// TargetDir-Delimiter - und SCA_REPORT_TIMESTAMP pinnt verbatim, solange
// der Wert dateinamentauglich ist (fuer den Gegenfall siehe
// DefaultFileName_IsoZeitstempelWirdEntschaerft).
begin
  MitGepinntemZeitstempel('PIN2026',
    procedure
    begin
      Assert.AreEqual('analyse_codereview_PIN2026.html',
        TExporterHtml.DefaultFileName('', ''),
        'Fallback-Schema ohne SourceFile/TargetDir');
      Assert.AreEqual('C:\out\uFoo_codereview_PIN2026.html',
        TExporterHtml.DefaultFileName('C:\src\uFoo.pas', 'C:\out'),
        'Basisname + TargetDir mit Pfadtrenner');
    end);
end;

procedure TTestExportHtml.PinnedTimestamp_SameValueInMetaLineAndJson;
// Determinismus-Kette: der Zeitstempel wird EINMAL berechnet und
// identisch in data-when, den sichtbaren Erstellt-Text und generatedAt
// getragen - kein Konsument darf sich Now() neu holen.
var
  Html : string;
begin
  MitGepinntemZeitstempel('PIN-TS',
    procedure
    var
      Findings : TObjectList<TLeakFinding>;
    begin
      Findings := TObjectList<TLeakFinding>.Create(True);
      try
        Findings.Add(MakeFinding(fkMemoryLeak, FIXTURE_PAS, 1,
          'x not freed'));
        Html := RenderFindings(Findings);
      finally
        Findings.Free;
      end;
    end);
  Assert.IsTrue(Html.Contains('data-when="PIN-TS"'), 'data-when gepinnt');
  Assert.IsTrue(Html.Contains('Erstellt: PIN-TS</span>'),
    'sichtbarer Text gepinnt');
  Assert.IsTrue(Html.Contains('"generatedAt":"PIN-TS"'),
    'sca-meta generatedAt gepinnt');
end;

procedure TTestExportHtml.SearchBlob_LowersUmlautsLikeTheJsQuery;
// Schwesterfall zum Detector-Info-Major (Chargen-Review 06.09.): die
// JS-Suche senkt die Eingabe Unicode-korrekt, der Blob muss es genauso
// tun - mit ASCII-LowerCase blieb ein grosses Ue (#$DC) stehen und der
// Fund war ueber dieses Wort unauffindbar. Ohne den AnsiLowerCase-Fix
// ist dieser Test ROT. Nicht-ASCII nur als Char-Codes (ASCII-Testdatei).
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, FIXTURE_PAS, 9, 'x not freed');
    Fnd.MethodName := 'PR' + #$DC + 'FUNG';   // grosses Ue
    Findings.Add(Fnd);
    Html := RenderFindings(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('pr' + #$FC + 'fung', Html) > 0,
    'Blob traegt die Unicode-gesenkte Form (kleines ue)');
  Assert.AreEqual<Integer>(0, Pos('pr' + #$DC + 'fung', Html),
    'kein stehengebliebenes grosses Ue im gesenkten Blob');
end;

procedure TTestExportHtml.HintCodePair_StackedWithTrailingBlankLines;
// "Untereinander" haengt am CSS (display:block statt flex), die
// "immer 2 Zeilen mehr" an JEDEM der vier Vorher/Nachher-Emits -
// darum wird gezaehlt: jedes '</pre></div>' der Codebloecke muss die
// beiden Leerzeilen davor tragen, nicht nur eines.
var
  Html : string;
  Alle, MitLuft, P : Integer;
begin
  Html := RenderReport;
  Assert.IsTrue(Pos('class="code-pair"', Html) > 0,
    'Vorbedingung: der Report traegt einen Vorher/Nachher-Block');
  Assert.IsTrue(Pos('.code-pair { display: block', Html) > 0,
    'die Codebloecke muessen untereinander stehen (kein flex)');
  Alle := 0;
  P := Pos('</pre></div>', Html);
  while P > 0 do
  begin
    Inc(Alle);
    P := Pos('</pre></div>', Html, P + 1);
  end;
  MitLuft := 0;
  P := Pos(#10#10'</pre></div>', Html);
  while P > 0 do
  begin
    Inc(MitLuft);
    P := Pos(#10#10'</pre></div>', Html, P + 1);
  end;
  Assert.IsTrue(Alle > 0, 'kein Codeblock im Report gefunden');
  Assert.AreEqual<Integer>(Alle, MitLuft,
    'JEDER Vorher/Nachher-Codeblock endet mit zwei Leerzeilen');
end;

procedure TTestExportHtml.Report_WearsWorkbenchLook;
// Geteilter Kern (uWorkbenchStyle) + die Struktur-Anker des Umbaus:
// Tokens, dunkler Kopf mit Titel+Meta, main-Wrapper, Theme-Token-
// Overrides (Ableitungs-Invariante: Selektor je Zeile - die erste
// Dark-Token-Zeile muss darum den vollen Selektor tragen).
var
  Html : string;
begin
  Html := RenderReport;
  Assert.IsTrue(Pos('--akzent:#1a5da6', Html) > 0,
    'Workbench-Tokens fehlen (uWorkbenchStyle nicht eingebunden)');
  Assert.IsTrue(Pos('<header class="kopf">', Html) > 0,
    'dunkler Workbench-Kopf fehlt');
  Assert.IsTrue(Pos('</header>', Html) > 0, 'Kopf nicht geschlossen');
  Assert.IsTrue(Pos('<main>', Html) > 0, 'main-Wrapper fehlt');
  Assert.IsTrue(Pos('</main>', Html) > 0, 'main nicht geschlossen');
  Assert.IsTrue(Pos('<header class="kopf">', Html) < Pos('<main>', Html),
    'Kopf steht vor dem Inhalt');
  Assert.IsTrue(
    Pos(':root[data-theme="dark"] { --grund: #1e1e1e;', Html) > 0,
    'Dark-Theme ueberschreibt die Tokens nicht');
  Assert.IsTrue(
    Pos(':root[data-theme="sepia"] { --grund: #f4ead2;', Html) > 0,
    'Sepia-Theme ueberschreibt die Tokens nicht');
end;

procedure TTestExportHtml.FindingDetails_OpenInSideDrawer;
// Drawer-Vertrag des Reports (Nachauftrag 07.09.): Markup-Anker,
// JS-Funktionen samt Verdrahtung, Drawer-CSS inkl. Responsive-Fall -
// und als Gegenprobe, dass die alte Klappzeilen-Anzeige WEG ist
// (ohne die Gegenprobe waere ein Doppel-UI aus Drawer UND Klappzeile
// fuer diesen Test unsichtbar).
var
  Html : string;
begin
  Html := RenderReport;
  Assert.IsTrue(Pos('<aside id="drawer" aria-label="Befund-Details">',
    Html) > 0, 'Drawer-Markup fehlt');
  Assert.IsTrue(Pos('id="drawer-schliessen"', Html) > 0,
    'Close-Button fehlt');
  Assert.IsTrue(Pos('id="drawer-kopf"', Html) > 0, 'Drawer-Kopf fehlt');
  Assert.IsTrue(Pos('id="drawer-inhalt"', Html) > 0,
    'Drawer-Inhalt fehlt');
  Assert.IsTrue(Pos('function openDrawer(row, hint)', Html) > 0,
    'openDrawer fehlt');
  Assert.IsTrue(Pos('function closeDrawer()', Html) > 0,
    'closeDrawer fehlt');
  Assert.IsTrue(Pos('openDrawer(row, hint);', Html) > 0,
    'wireToggle ruft openDrawer nicht (Definition allein oeffnet nichts)');
  Assert.IsTrue(Pos('#drawer { position: fixed; top: 0; right: 0;',
    Html) > 0, 'Drawer-CSS fehlt');
  Assert.IsTrue(
    Pos('@media (max-width: 900px) { #drawer { width: 100%;', Html) > 0,
    'Responsive-Vollbild des Drawers fehlt');
  // Gegenproben: die Klappzeile darf nie wieder sichtbar werden.
  Assert.AreEqual<Integer>(0,
    Pos('tr.finding-hint.open { display: table-row; }', Html),
    'alte Klappzeilen-Anzeige lebt noch');
  Assert.IsTrue(Pos('tr.finding-hint { display: none; }', Html) > 0,
    'Hint-Zeile muss dauerhaft unsichtbare Datenquelle bleiben');
  // Katalog-Parallele (Nachauftrag 07.09.): "Was wird erkannt?" und
  // "Warum ist das relevant?" stehen in den Befund-Details - SCA001
  // traegt beide Beschreibungen im Katalog, die Abschnitte muessen
  // also erscheinen, in Katalog-Reihenfolge (Was vor Warum).
  Assert.IsTrue(
    Pos('<h3 data-i18n="hint-what">Was wird erkannt?</h3>', Html) > 0,
    '"Was wird erkannt?"-Abschnitt fehlt in den Befund-Details');
  Assert.IsTrue(
    Pos('<h3 data-i18n="hint-why">Warum ist das relevant?</h3>', Html) > 0,
    '"Warum ist das relevant?"-Abschnitt fehlt in den Befund-Details');
  Assert.IsTrue(
    Pos('<h3 data-i18n="hint-what">', Html) <
    Pos('<h3 data-i18n="hint-why">', Html),
    'Katalog-Reihenfolge verletzt: Was? gehoert vor Warum?');
  // Die Ueberschriften sind uebersetzbar: alle drei Sprachbloecke
  // tragen die Schluessel (hint-this deckt den fundspezifischen
  // Hinweis ab, dessen Anzeige vom FixHint-Zweig abhaengt).
  Assert.IsTrue(Pos('"hint-what": "What is detected?"', Html) > 0,
    'en-Schluessel hint-what fehlt');
  Assert.IsTrue(Pos('"hint-this": "Note on this finding"', Html) > 0,
    'en-Schluessel hint-this fehlt');
  Assert.IsTrue(Pos('"hint-this": "Remarque sur cette occurrence"',
    Html) > 0, 'fr-Schluessel hint-this fehlt');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportHtml);

end.
