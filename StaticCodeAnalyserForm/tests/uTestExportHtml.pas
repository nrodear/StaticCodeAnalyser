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
  end;


implementation

uses
  System.IOUtils;

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

initialization
  TDUnitX.RegisterTestFixture(TTestExportHtml);

end.
