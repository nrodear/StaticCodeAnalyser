unit uTestFindingsWorkbenchExport;

// Vertragstests der Funde-Export-VARIANTE 2 (uFindingsWorkbenchExport,
// Nutzerauftrag 07.09.): Workbench-Architektur der Detektor-Info-Seite
// auf dem Scan-Bericht. Kernvertraege: ein tbody je Fund, Regel-Doku
// DEDUPLIZIERT (ein Template je vorkommender Regel - egal wie viele
// Funde sie hat), Suchblob AnsiLowerCase, Zeilenbudget mit Banner,
// UTF-8-BOM, Drawer-/JS-Geruest samt Init-Aufrufen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DUnitX.TestFramework,
  uSCAConsts, uMethodd12;

type
  [TestFixture]
  TTestFindingsWorkbenchExport = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
    function Render(Findings: TObjectList<TLeakFinding>;
      const ABaseDir: string = ''; AMaxRows: Integer = -1): string;
  public
    [Test] procedure OneTbodyPerFinding_TemplatesDeduplicated;
    [Test] procedure WorkbenchScaffolding_WiredCompletely;
    [Test] procedure SearchBlob_IsAnsiLowered;
    [Test] procedure MaxRows_TruncatesWithBanner_TilesKeepTotals;
    [Test] procedure FileReadError_NeutralBadgeAndOwnRank;
    [Test] procedure Run_WritesUtf8WithBom;
    [Test] procedure FindingFields_AreHtmlEscaped;
    [Test] procedure DataCopy_CarriesRealNewlines_NoBrTokens;
    [Test] procedure EmptyRun_SaysNoFindings_NotNoMatches;
    [Test] procedure Run_MatchesBuildHtml_ByteForByte;
    // Nutzerauftrag 07.09. (Screenshot): Datei als eigene Zeile UNTER
    // Zeile+Methode - "Dateiname; voller Pfad" mit Ellipse.
    [Test] procedure FileRow_UnderMainRow_NameFirstThenFullPath;
    // EN/FR-Nachtrag 07.09.: Seite in drei Sprachen, Token unberuehrt.
    [Test] procedure Language_TranslatesPageButKeepsTokens;
  end;

implementation

// noinspection-file DuplicateString, LargeClass
// Fixture-Ausnahme des Profils: HTML-Anker ('</template>', 'tpl-')
// wiederholen sich als Pruefgegenstand bewusst variiert.

uses
  System.IOUtils,
  uFindingsWorkbenchExport, uRuleCatalog,
  uExportHtml; // HtmlEscape - Erwartungsbau des data-copy-Vertrags

function VorkommenIn(const AHtml, ATeil: string): Integer;
// Teilstring-Zaehlung - gehoben aus dem Deduplikations-Test, seit der
// Kuerzungs-Test die gerenderten tbodies mitzaehlt (Review 07.09.:
// Banner und Kacheln entstehen UNABHAENGIG vom Zeilen-Loop, erst die
// Zaehlung macht 'Truncates' zum Rot-Kriterium).
var
  P : Integer;
begin
  Result := 0;
  P := Pos(ATeil, AHtml);
  while P > 0 do
  begin
    Inc(Result);
    P := Pos(ATeil, AHtml, P + 1);
  end;
end;

function TTestFindingsWorkbenchExport.MakeFinding(Kind: TFindingKind;
  const Path: string; Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName   := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MissingVar := Msg;
  Result.MethodName := 'TestMethod';
end;

function TTestFindingsWorkbenchExport.Render(
  Findings: TObjectList<TLeakFinding>;
  const ABaseDir: string; AMaxRows: Integer): string;
begin
  Result := TFindingsWorkbenchExport.BuildHtml(Findings, ABaseDir,
    AMaxRows);
end;

procedure TTestFindingsWorkbenchExport.OneTbodyPerFinding_TemplatesDeduplicated;
// DER V2-Kern: drei Funde, davon zwei derselben Regel -> drei tbodies,
// aber nur ZWEI Regel-Templates. In der V1 stuende die Regel-Doku
// dreimal im Dokument.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  MetaLeak : TRuleMeta;
  MetaDbg  : TRuleMeta;

  function Vorkommen(const Teil: string): Integer;
  begin
    Result := VorkommenIn(Html, Teil);
  end;

begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a not freed'));
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\B.pas', 20, 'b not freed'));
    Findings.Add(MakeFinding(fkDebugOutput, 'src\A.pas', 30, 'WriteLn'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  MetaLeak := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  MetaDbg  := TRuleCatalog.GetRule(fkDebugOutput, 'de');
  Assert.AreEqual<Integer>(3, Vorkommen('<tbody data-rid="'),
    'drei Funde muessen drei tbodies ergeben');
  Assert.AreEqual<Integer>(2,
    Vorkommen('<tbody data-rid="' + MetaLeak.ID + '"'),
    'beide MemoryLeak-Funde haengen an derselben Regel-ID');
  Assert.AreEqual<Integer>(1,
    Vorkommen('<template id="tpl-' + MetaLeak.ID + '">'),
    'Regel-Template MemoryLeak muss trotz zweier Funde EINMAL stehen');
  Assert.AreEqual<Integer>(1,
    Vorkommen('<template id="tpl-' + MetaDbg.ID + '">'),
    'Regel-Template DebugOutput fehlt');
  Assert.AreEqual<Integer>(2, Vorkommen('</template>'),
    'genau zwei Templates insgesamt (Deduplikation)');
  // Die Katalog-Abschnitte stehen im Template, nicht je Fund:
  Assert.AreEqual<Integer>(2, Vorkommen('<h3>Was wird erkannt?</h3>'),
    '"Was wird erkannt?" gehoert EINMAL je Regel-Template');
end;

procedure TTestFindingsWorkbenchExport.WorkbenchScaffolding_WiredCompletely;
// Chrome + JS-Geruest: Workbench-Kopf, Command-Bar, Chips (typ/sev/
// konf, KEIN prof - der Scan ist gelaufen), Kacheln, Drawer samt
// Fund-Kopf-Bauer, Tastatur, Deep-Link und die Init-AUFRUFE.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a not freed'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('--akzent:#1a5da6', Html) > 0,
    'Workbench-Tokens fehlen (uWorkbenchStyle nicht eingebunden)');
  Assert.IsTrue(Pos('<header class="kopf">', Html) > 0,
    'dunkler Workbench-Kopf fehlt');
  Assert.IsTrue(Pos('id="suche"', Html) > 0, 'Command-Bar-Suche fehlt');
  Assert.IsTrue(Pos('data-gruppe="typ"', Html) > 0, 'Typ-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="sev"', Html) > 0, 'Sev-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="konf"', Html) > 0,
    'Konfidenz-Chips fehlen');
  Assert.AreEqual<Integer>(0, Pos('data-gruppe="prof"', Html),
    'Profil-Chips haben im Fund-Bericht nichts verloren');
  Assert.IsTrue(Pos('class="kachel"', Html) > 0,
    'Dashboard-Kacheln fehlen');
  Assert.IsTrue(Pos('<aside id="drawer" aria-label="Fund-Details">',
    Html) > 0, 'Drawer fehlt');
  Assert.IsTrue(Pos('function fundKopf(tb)', Html) > 0,
    'Fund-Kopf-Bauer fehlt (Ort/Detail/Hinweis im Drawer)');
  Assert.IsTrue(Pos('function oeffneDrawer(tb)', Html) > 0,
    'oeffneDrawer fehlt');
  Assert.IsTrue(Pos('korb.appendChild(fundKopf(tb));', Html) > 0,
    'Drawer setzt den Fund-Kopf nicht VOR das Regel-Template');
  Assert.IsTrue(Pos('ev.ctrlKey', Html) > 0, 'Strg+K fehlt');
  Assert.IsTrue(Pos('ev.target.tagName === "BUTTON"', Html) > 0,
    'Button-Ausstieg des Tastatur-Handlers fehlt (Chips per Enter)');
  Assert.IsTrue(Pos('ev.target.classList.contains("haupt")', Html) > 0,
    'Enter-auf-fokussierter-Zeile-Zweig fehlt');
  Assert.IsTrue(Pos('function deepLink()', Html) > 0, 'Deep-Link fehlt');
  Assert.IsTrue(Pos('suche();'#13#10'deepLink();', Html) > 0,
    'Init-Aufrufe fehlen (Definition allein filtert nichts)');
  Assert.IsTrue(Pos('id="leer"', Html) > 0, 'Empty-State fehlt');
  Assert.AreEqual<Integer>(0, Pos('data-wert="ferr"', Html),
    'ohne Lesefehler darf kein Lesefehler-Chip erscheinen');
end;

procedure TTestFindingsWorkbenchExport.SearchBlob_IsAnsiLowered;
// Wie Katalog und V1: der Blob muss Unicode-gesenkt sein, sonst sind
// Woerter mit grossen Umlauten in keiner Schreibweise findbar.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10,
      'PR'#$DC'FUNG offen'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('pr'#$FC'fung offen', Html) > 0,
    'Suchblob muss AnsiLowerCase nutzen (Umlaut-Senkung)');
  Assert.AreEqual<Integer>(0, Pos('PR'#$DC'FUNG offen',
    Copy(Html, Pos('data-search="', Html), 400)),
    'im Suchattribut darf der ungesenkte Text nicht stehen');
end;

procedure TTestFindingsWorkbenchExport.MaxRows_TruncatesWithBanner_TilesKeepTotals;
// Zeilenbudget-Vertrag der V2: Tabelle gekuerzt + Banner, aber die
// Funde-Kachel zaehlt weiterhin ALLE Funde.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  i        : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to 5 do
      Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', i,
        'x' + IntToStr(i)));
    Html := Render(Findings, '', 3);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('id="gekuerzt"', Html) > 0,
    'Kuerzungsbanner fehlt');
  Assert.IsTrue(Pos('2 weitere Funde', Html) > 0,
    'Banner muss die Zahl der weggelassenen Funde nennen');
  Assert.AreEqual<Integer>(3, VorkommenIn(Html, '<tbody data-rid="'),
    'die Tabelle muss WIRKLICH auf 3 Zeilen gekuerzt sein - Banner '
    + 'und Kacheln allein beweisen den Break im Zeilen-Loop nicht');
  Assert.IsTrue(
    Pos('<div class="zahl">5</div><div class="wofuer">Funde</div>',
      Html) > 0,
    'die Funde-Kachel zaehlt ALLE Funde, nicht die gerenderten');
end;

procedure TTestFindingsWorkbenchExport.FileReadError_NeutralBadgeAndOwnRank;
// Lesefehler sind kein Schweregrad der Skala: neutraler Badge,
// Sortier-Rang hinter den Hinweisen (Politik wie V1).
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, 'src\Kaputt.pas', 1,
      'read failed'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(
    Pos('<span class="badge typ ferr">Lesefehler</span>', Html) > 0,
    'Lesefehler brauchen den neutralen ferr-Badge');
  Assert.IsTrue(Pos('data-sev="3"', Html) > 0,
    'Lesefehler-Rang 3 (hinter lsHint) fehlt');
  // Review 07.09.: ohne eigenen Typ-Chip waeren ferr-Zeilen bei
  // aktivem Typ-Filter unerreichbar. Der Chip erscheint nur, wenn
  // Lesefehler da sind (der Scaffolding-Test prueft die Gegenrichtung).
  Assert.IsTrue(Pos('data-wert="ferr"', Html) > 0,
    'Lesefehler-Typ-Chip fehlt trotz vorhandener Lesefehler');
end;

procedure TTestFindingsWorkbenchExport.Run_WritesUtf8WithBom;
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  Bytes    : TBytes;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Fn := TPath.Combine(TPath.GetTempPath,
      'sca-test-v2-' + TGUID.NewGuid.ToString + '.html');
    try
      TFindingsWorkbenchExport.Run(Findings, '', Fn);
      Bytes := TFile.ReadAllBytes(Fn);
    finally
      if TFile.Exists(Fn) then TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Length(Bytes) > 3, 'Datei leer');
  Assert.AreEqual<Byte>($EF, Bytes[0], 'BOM-Byte 1');
  Assert.AreEqual<Byte>($BB, Bytes[1], 'BOM-Byte 2');
  Assert.AreEqual<Byte>($BF, Bytes[2], 'BOM-Byte 3');
end;

procedure TTestFindingsWorkbenchExport.FindingFields_AreHtmlEscaped;
// Skript-/Attribut-Sicherheit: boese Fund-Felder duerfen nirgends roh
// stehen (Datei, Methode, Detail landen in Zelle UND Suchattribut).
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Fnd      : TLeakFinding;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, 'src\<script>.pas', 10,
      '"boese" & <kaputt>');
    Fnd.MethodName := 'Do<Evil>';
    Findings.Add(Fnd);
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.AreEqual<Integer>(0, Pos('<script>.pas', Html),
    'Dateiname mit Tag muss escaped sein');
  Assert.AreEqual<Integer>(0, Pos('Do<Evil>', Html),
    'Methodenname mit Tag muss escaped sein');
  Assert.AreEqual<Integer>(0, Pos('"boese" & <kaputt>', Html),
    'Detailtext muss escaped sein');
  Assert.IsTrue(Pos('Do&lt;Evil&gt;', Html) > 0,
    'escapter Methodenname fehlt - dann fehlt die Zeile selbst');
end;

procedure TTestFindingsWorkbenchExport.DataCopy_CarriesRealNewlines_NoBrTokens;
// Chargen-Review 07.09. (MAJOR): data-copy der Codekarten lief durch
// den Element-Escaper und trug '<br>'-Tokens statt Umbruechen - der
// Kopieren-Button schrieb Muell in die Zwischenablage. Vertrag jetzt:
// Umbrueche als '&#10;' im data-copy, waehrend der <pre>-INHALT
// weiter die '<br>'-Form des Element-Vertrags traegt.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Meta     : TRuleMeta;
  Erwartet : string;
begin
  Meta := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  Assert.IsTrue(Pos(#10, Meta.BadExample) > 0,
    'Vorbedingung: SCA001-Beispiel ist mehrzeilig');
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Erwartet := StringReplace(TExporterHtml.HtmlEscape(Meta.BadExample),
    '<br>', '&#10;', [rfReplaceAll]);
  Assert.IsTrue(Pos('data-copy="' + Erwartet + '"', Html) > 0,
    'data-copy muss Umbrueche als &#10; tragen');
  Assert.AreEqual<Integer>(0,
    Pos('data-copy="' + TExporterHtml.HtmlEscape(Meta.BadExample) + '"',
      Html),
    'die alte <br>-Form darf nicht mehr emittiert werden');
end;

procedure TTestFindingsWorkbenchExport.EmptyRun_SaysNoFindings_NotNoMatches;
// Review 07.09.: ein Lauf OHNE Funde ist kein Filter-Problem - die
// Seite muss 'Keine Funde in diesem Lauf.' anbieten, nicht die
// Suche-verunglueckt-Botschaft mit wirkungslosem Reset-Button.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('Keine Funde in diesem Lauf.', Html) > 0,
    'Leerlauf-Botschaft fehlt');
  Assert.IsTrue(Pos('id="leer-suche"', Html) > 0,
    'Filter-Botschaft-Span fehlt');
  Assert.IsTrue(Pos('var ohneFunde = ges === 0;', Html) > 0,
    'JS-Weiche zwischen Leerlauf und leerer Trefferliste fehlt');
  Assert.IsTrue(Pos('</html>', Html) > 0,
    'die leere Seite muss vollstaendig schliessen');
  Assert.AreEqual<Integer>(0, VorkommenIn(Html, '<tbody data-rid="'),
    'null Funde duerfen null Zeilen ergeben');
end;

procedure TTestFindingsWorkbenchExport.Run_MatchesBuildHtml_ByteForByte;
// Review 07.09.: der TStringList-Umweg der ersten Run-Fassung
// normalisierte Zeilenenden (aus der #10#10-Anzeige-Luft wurde CRLF
// plus Trailing-Break) - Run-Datei und BuildHtml-String waren nicht
// identisch. Seit dem Builder-Pfad (SaveBuilderUtf8WithBom) muss
// beides dasselbe Dokument sein.
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  Gebaut   : string;
  Gelesen  : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Gebaut := TFindingsWorkbenchExport.BuildHtml(Findings, '');
    Fn := TPath.Combine(TPath.GetTempPath,
      'sca-test-v2ab-' + TGUID.NewGuid.ToString + '.html');
    try
      TFindingsWorkbenchExport.Run(Findings, '', Fn);
      Gelesen := TFile.ReadAllText(Fn, TEncoding.UTF8);
    finally
      if TFile.Exists(Fn) then TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
  Assert.AreEqual(Gebaut, Gelesen,
    'Run muss exakt das BuildHtml-Dokument schreiben (keine '
    + 'Zeilenende-Normalisierung durch einen Listen-Umweg)');
end;

procedure TTestFindingsWorkbenchExport.FileRow_UnderMainRow_NameFirstThenFullPath;
// Layout-Vertrag des Zwei-Zeilen-Umbaus: die Hauptzeile beginnt mit
// der Zeilennummer (keine Datei-Spalte, kein Datei-Spaltenkopf), die
// Datei folgt als colspan-Zeile "Dateiname; voller Pfad" mit
// Ellipse-CSS und title; traegt der Fund nur den Basisnamen,
// entfaellt das Doppel.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Findings.Add(MakeFinding(fkDebugOutput, 'B.pas', 20, 'w'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('<th onclick="sortiere(0)">Zeile', Html) > 0,
    'erste sortierbare Spalte muss die Zeilennummer sein');
  Assert.AreEqual<Integer>(0, Pos('>Datei<span', Html),
    'der alte Datei-Spaltenkopf muss weg sein');
  Assert.IsTrue(
    Pos('<td class="pfadzeile" colspan="8" title="src\A.pas">'
      + 'A.pas; src\A.pas</td>', Html) > 0,
    'Datei-Zeile "Name; voller Pfad" mit title fehlt');
  Assert.IsTrue(
    Pos('<td class="pfadzeile" colspan="8" title="B.pas">'
      + 'B.pas</td>', Html) > 0,
    'bei blossem Basisnamen darf kein "Name; Name"-Doppel stehen');
  Assert.IsTrue(
    Pos('<tr class="haupt"', Html) < Pos('<tr class="datei"', Html),
    'die Datei-Zeile steht UNTER der Hauptzeile');
  Assert.IsTrue(Pos('data-pfad="src\A.pas"', Html) > 0,
    'data-pfad (Drawer-Fundort) fehlt am tbody');
  Assert.IsTrue(
    Pos('td.pfadzeile{max-width:0;overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;', Html) > 0,
    'Ellipse-CSS der Datei-Zeile fehlt');
  Assert.IsTrue(
    Pos('<tr class="datei" onclick="oeffneDrawer(this.parentNode)">',
      Html) > 0,
    'auch die Datei-Zeile muss den Drawer oeffnen');
end;

procedure TTestFindingsWorkbenchExport.Language_TranslatesPageButKeepsTokens;
// Wie der Zwilling auf der Katalogseite: Sichtbares wechselt, die
// Filter-/Sortier-TOKEN bleiben. Zusaetzlich hier geprueft: der
// SUCHBLOB folgt der Seitensprache - genau dafuer wird die Seite je
// Sprache gebacken statt zur Laufzeit umgeschaltet (im englischen
// Bericht muss "error" die Fehler-Zeilen finden, nicht "Fehler").
var
  Findings : TObjectList<TLeakFinding>;
  De, En, Fr : string;

  function SevKlasse(const AHtml: string): string;
  // Liefert die Severity-CSS-Klasse der ersten Badge-Zelle, z.B.
  // 'sev-err'. Ohne Kenntnis der konkreten Severity - so prueft der
  // Aufrufer die GLEICHHEIT ueber die Sprachen statt einen Wert.
  const
    ANKER = 'class="badge sev-';
  var
    P, E : Integer;
  begin
    Result := '';
    P := Pos(ANKER, AHtml);
    if P = 0 then Exit;
    Inc(P, Length(ANKER));
    E := P;
    while (E <= Length(AHtml)) and (AHtml[E] <> '"') do Inc(E);
    Result := 'sev-' + Copy(AHtml, P, E - P);
  end;

begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    De := TFindingsWorkbenchExport.BuildHtml(Findings, '', -1, 'de');
    En := TFindingsWorkbenchExport.BuildHtml(Findings, '', -1, 'en');
    Fr := TFindingsWorkbenchExport.BuildHtml(Findings, '', -1, 'fr');
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('<h1>SCA Findings</h1>', En) > 0,
    'englischer Titel fehlt');
  Assert.IsTrue(Pos('<div class="wofuer">Findings</div>', En) > 0,
    'englische Kachel-Beschriftung fehlt');
  Assert.IsTrue(Pos('>Line<', En) > 0, 'englischer Spaltenkopf fehlt');
  Assert.IsTrue(Pos('R&eacute;sultats SCA', Fr) > 0,
    'franzoesischer Titel fehlt');
  Assert.IsTrue(Pos('<html lang="fr">', Fr) > 0, 'lang=fr fehlt');
  // Suchblob in der Seitensprache. Geprueft wird die NEGATIV-Richtung
  // (kein deutsches Severity-Wort im englischen Dokument) - sie ist
  // der eigentliche Vertrag und kommt ohne Annahme darueber aus,
  // welche Severity die Fixture traegt.
  Assert.IsTrue(Pos('data-search="', En) > 0, 'Suchblob fehlt');
  Assert.AreEqual<Integer>(0, Pos('Warnung', En),
    'deutsches Severity-Wort im englischen Dokument');
  Assert.AreEqual<Integer>(0, Pos('warnung', En),
    'deutsches Severity-Wort im englischen Suchblob');
  Assert.AreEqual<Integer>(0, Pos('Hinweis', En),
    'deutsches Severity-Wort im englischen Dokument');
  Assert.AreEqual<Integer>(0, Pos('Konfidenz', Fr),
    'deutsches Label im franzoesischen Dokument');
  // Token unveraendert.
  Assert.IsTrue(Pos('data-wert="hotspot"', Fr) > 0,
    'Typ-Token muss unuebersetzt bleiben');
  // Rang 0 = lsError: fkMemoryLeak traegt DefaultSeverity lsError
  // (KIND_META in uSCAConsts). BELEGT statt geraten - der erste Wurf
  // stand auf "1" und war rot.
  Assert.IsTrue(Pos('data-sev="0"', Fr) > 0,
    'Severity-Rang bleibt numerisch und sprachunabhaengig');
  Assert.AreEqual(
    Pos('data-sev="0"', Fr) > 0, Pos('data-sev="0"', En) > 0,
    'derselbe Fund muss in JEDER Sprache denselben Rang tragen');
  // Die Severity-CSS-Klasse muss in ALLEN Sprachen dieselbe sein.
  // Bewusst OHNE Annahme darueber, WELCHE es ist: der erste Wurf
  // stand auf 'sev-warn', tatsaechlich ist fkMemoryLeak lsError -
  // und dieselbe geratene Annahme hatte schon den data-sev-Assert
  // rot gemacht. Geprueft wird die Zusage, nicht der Beispielwert.
  Assert.AreEqual(SevKlasse(De), SevKlasse(Fr),
    'Severity-CSS-Klasse muss unuebersetzt bleiben (de vs. fr)');
  Assert.AreEqual(SevKlasse(De), SevKlasse(En),
    'Severity-CSS-Klasse muss unuebersetzt bleiben (de vs. en)');
  Assert.IsTrue(SevKlasse(De) <> '',
    'ohne Severity-Klasse prueft der Vergleich nichts');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingsWorkbenchExport);

end.
