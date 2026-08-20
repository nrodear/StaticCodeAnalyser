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

initialization
  TDUnitX.RegisterTestFixture(TTestExportHtml);

end.
