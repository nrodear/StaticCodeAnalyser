unit uTestFindingsWorkbenchExport;

// Vertragstests der Funde-Export-VARIANTE 2 (uFindingsWorkbenchExport,
// Nutzerauftrag 07.09.): Workbench-Architektur der Detektor-Info-Seite
// auf dem Scan-Bericht. Kernvertraege: ein tbody je Fund, Regel-Doku
// DEDUPLIZIERT (ein Template je vorkommender Regel - egal wie viele
// Funde sie hat), Suche ueber den Zeilentext statt ueber einen
// Blob je Fund, Zeilenbudget mit Banner,
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
    // Ein Bericht mit genau EINEM Standardfund - der Aufbau, den
    // die meisten Tests brauchen. Ausgelagert, weil er sonst in
    // jedem Test dieselben acht Zeilen kostet (der eigene Scan
    // meldete ihn als SCA021).
    function EinFundHtml: string;
  public
    [Test] procedure OneTbodyPerFinding_TemplatesDeduplicated;
    [Test] procedure WorkbenchScaffolding_WiredCompletely;
    [Test] procedure SearchBlob_IsAnsiLowered;
    [Test] procedure SearchBlob_RuleExtrasSharedNotPerFinding;
    [Test] procedure MaxRows_TruncatesWithBanner_TilesKeepTotals;
    [Test] procedure FileReadError_NeutralBadgeAndOwnRank;
    [Test] procedure Run_WritesUtf8WithBom;
    [Test] procedure DefaultFileName_TraegtDatumUndBleibtWindowstauglich;
    [Test] procedure FindingFields_AreHtmlEscaped;
    [Test] procedure DataCopy_CarriesRealNewlines_NoBrTokens;
    [Test] procedure EmptyRun_SaysNoFindings_NotNoMatches;
    [Test] procedure Run_MatchesBuildHtml_ByteForByte;
    // Nutzerauftrag 07.09. (Screenshot): Datei als eigene Zeile UNTER
    // Zeile+Methode - "Dateiname; voller Pfad" mit Ellipse.
    [Test] procedure FileRow_UnderMainRow_NameFirstThenFullPath;
    // Die Methodenzelle traegt seit 09.09. zwei Texte (V3-Formatierung).
    [Test] procedure Methodenzelle_SortiertOhneDenPfad;
    // Regel und Detail untereinander, feste Spaltenbreiten (09.09.).
    [Test] procedure Regelzelle_TraegtRegelUndDetailUntereinander;
    [Test] procedure Spaltenbreiten_SindFestWieInV3;
    [Test] procedure Spaltenzeile_UndListenOverflow_GehoerenZusammen;
    [Test] procedure Bereiche_HabenBenennbareIds;
    [Test] procedure Bereiche_StehenInDerVorgegebenenReihenfolge;
    [Test] procedure Filterleiste_BleibtBeimScrollenSichtbar;
    [Test] procedure Spaltenkopf_BleibtBeimScrollenSichtbar;
    // Angepinnter Kopf mit zwei Zustaenden (Nutzerauftrag 09.09.).
    [Test] procedure Kopf_IstAngepinntUndSchrumpftBeimScrollen;
    // EN/FR-Nachtrag 07.09.: Seite in drei Sprachen, Token unberuehrt.
    [Test] procedure Language_TranslatesPageButKeepsTokens;
    // Feature-Abgleich V1->V2 (Todo_FeatureListe..., 07.09.):
    [Test] procedure InitialSort_BySeverity_WithConfidenceTiebreak;
    [Test] procedure Themes_DarkAndSepiaAsTokenOverrides;
    // Der Theme-Blitz beim Laden (Nico-Befund 09.09.).
    [Test] procedure Theme_AntiBlitzStehtImHead;
    [Test] procedure Dropdowns_FileAndRule_FilterAndReset;
    [Test] procedure TopLists_SortedByCount_AndClickable;
    [Test] procedure HealthAndSecurity_ScoreMatchesV1Formula;
    [Test] procedure SourceSnippet_RendersAroundFindingLine;
    [Test] procedure SourceSnippet_LiestUtf8OhneBom;
    // IDE-Focus-Redesign 08.09. (Variante A des UI-TODO): Selection
    // mit Severity-Rail, Inspector mit Hero und gestaffelten Ebenen.
    [Test] procedure IdeInspector_HeroHierarchyAndSelectionStates;
  end;

implementation

// noinspection-file DuplicateString, LargeClass, GodClass
// Fixture-Ausnahme des Profils: HTML-Anker ('</template>', 'tpl-')
// wiederholen sich als Pruefgegenstand bewusst variiert.
// GodClass seit dem IDE-Focus-Redesign (08.09.): 19 [Test]-Methoden
// plus die zwei Helfer MakeFinding und Render = 21 Methoden, und
// SCA138 zaehlt ALLE Methoden gegen die Schwelle 20 (vorher 20 -
// der Detektor schwieg auf den Punkt genau).
// eine DUnitX-Fixture waechst mit jedem Vertragsfall, und genau das
// SOLL sie - die Methoden SIND der Katalog der Zusagen dieser Seite.
// Eine Aufspaltung duplizierte nur MakeFinding und Render und
// zerrisse die Ablesbarkeit dessen, was der Export garantiert
// (gleiche Lage und Begruendung wie in uTestExportHtml).

uses
  System.IOUtils,
  uFindingsWorkbenchExport, uRuleCatalog,
  uExportHtml; // HtmlEscape - Erwartungsbau des data-copy-Vertrags

procedure AssertReihenfolge(const AHtml, AErst, ADann, AMsg: string);
// Prueft, dass BEIDE Anker vorkommen UND AErst vor ADann steht.
// Ein blosses 'Pos(A) < Pos(B)' ist VAKUUM-GRUEN: fehlt A, liefert
// Pos 0 und die Bedingung ist trivial wahr - der Test bestaende
// also gerade dann, wenn das Gepruefte verschwunden ist
// (Chargen-Review 08.09., MAJOR; betraf mehrere Stellen dieser
// Fixture, darum ein Helfer statt einzelner Flicken).
begin
  Assert.IsTrue(Pos(AErst, AHtml) > 0,
    AMsg + ' - der erste Anker fehlt ueberhaupt: ' + AErst);
  Assert.IsTrue(Pos(ADann, AHtml) > 0,
    AMsg + ' - der zweite Anker fehlt ueberhaupt: ' + ADann);
  Assert.IsTrue(Pos(AErst, AHtml) < Pos(ADann, AHtml), AMsg);
end;

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

function TTestFindingsWorkbenchExport.EinFundHtml: string;
// Begruendung an der Deklaration.
var
  Findings : TObjectList<TLeakFinding>;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Result := Render(Findings);
  finally
    Findings.Free;
  end;
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
  // Mit Bereichs-ID: die haben alle Hauptbloecke seit 09.09., damit
  // im Gespraech benennbar ist, WO etwas stehen soll.
  Assert.IsTrue(
    Pos('<header class="kopf" id="bereich-seitenkopf">', Html) > 0,
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
// Die Suche muss Woerter mit grossen Umlauten in JEDER Schreibweise
// finden. Wie das erreicht wird, hat sich am 09.09. umgedreht:
//
// FRUEHER trug jeder Fund einen fertig gesenkten Suchblob in
// data-search, und der musste mit AnsiLowerCase gesenkt sein - mit
// LowerCase waeren grosse Umlaute stehen geblieben, waehrend die
// JS-Seite die Eingabe Unicode-korrekt senkt (Chargen-Review 06.09.).
// Zwei Senkungen, die auseinanderlaufen konnten.
//
// HEUTE gibt es nur noch EINE Senkung, und sie liegt im Browser:
// suchtext() liest den Zeilentext und senkt ihn mit demselben
// toLowerCase, das auch die Eingabe senkt. Die Falle ist damit nicht
// mehr behoben, sondern baulich unmoeglich - und genau das prueft
// dieser Test.
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
  // Der Text steht EINMAL in der Seite, in seiner Originalschreibung -
  // sichtbar in der Zeile. Kein zweites, gesenktes Exemplar daneben.
  Assert.IsTrue(Pos('PR'#$DC'FUNG offen', Html) > 0,
    'der Detailtext fehlt in der Fundzeile');
  Assert.AreEqual<Integer>(0, Pos('data-search="', Html),
    'der Suchblob je Fund ist zurueck - er verdoppelt die Zeile');
  Assert.AreEqual<Integer>(0, Pos('pr'#$FC'fung offen', Html),
    'gesenktes Zweitexemplar des Detailtexts in der Seite');
  // Beide Seiten des Vergleichs senken mit DEMSELBEN toLowerCase.
  Assert.IsTrue(Pos('tb._s = t.toLowerCase();', Html) > 0,
    'die Suchbasis wird nicht gesenkt');
  Assert.IsTrue(
    Pos('document.getElementById("suche").value.toLowerCase()', Html) > 0,
    'die Eingabe wird nicht mit derselben Senkung behandelt');
end;

procedure TTestFindingsWorkbenchExport.SearchBlob_RuleExtrasSharedNotPerFinding;
// Was zur Suche gehoert, aber nicht in der Fundzeile steht - Kind-Name,
// CWE, Tags - liegt EINMAL JE REGEL in RSUCH, nicht einmal je Fund.
//
// Der Test nimmt DREI Funde DERSELBEN Regel. Damit trennt er die
// Ersparnis vom blossen Vorhandensein: eine Umsetzung, die den Zusatz
// weiterhin bei jedem Fund fuehrt, wuerde ihn dreimal schreiben und
// faellt hier durch. Mit nur einem Fund waere beides ununterscheidbar.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  i, N, P  : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to 3 do
      Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', i * 10, 'x'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('var RSUCH={', Html) > 0,
    'die Such-Zusatztabelle fehlt');
  // Der Kind-Name steht NICHT in der Zeile - ohne ihn waere die Suche
  // nach dem technischen Namen tot. Er ist der Grund, dass es die
  // Tabelle ueberhaupt gibt.
  // Mit fuehrendem Anfuehrungszeichen UND Leerzeichen dahinter: so
  // steht der Name nur am Anfang eines Zusatz-Werts. Ohne die Klammer
  // wuerde ein gleichlautender Tag mitgezaehlt, und der Test haenge
  // daran, was der Regelkatalog gerade fuehrt.
  Assert.IsTrue(Pos('"MemoryLeak ', Html) > 0,
    'der Kind-Name fehlt in der Such-Zusatztabelle');
  // EINMAL, nicht dreimal.
  N := 0;
  P := Pos('"MemoryLeak ', Html);
  while P > 0 do
  begin
    Inc(N);
    P := Pos('"MemoryLeak ', Html, P + 1);
  end;
  Assert.AreEqual<Integer>(1, N,
    'der Kind-Name steht mehrfach - der Zusatz haengt wieder am Fund');
  // Und die Anzeige nutzt ihn auch.
  Assert.IsTrue(Pos('suchtext(tbs[i]).indexOf(q) >= 0', Html) > 0,
    'die Suche liest die Zeile nicht ueber suchtext()');
  Assert.IsTrue(Pos('RSUCH[tb.dataset.rid]', Html) > 0,
    'suchtext() zieht den Regel-Zusatz nicht heran');
  // Zelle fuer Zelle, nicht als textContent der ganzen Zeile: sonst
  // kleben "42" und "DoFoo" zu "42DoFoo" und erzeugen Falschtreffer.
  Assert.IsTrue(Pos('z.children[k].textContent + " "', Html) > 0,
    'der Zeilentext wird nicht zellenweise getrennt gelesen');
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

procedure TTestFindingsWorkbenchExport.DefaultFileName_TraegtDatumUndBleibtWindowstauglich;
// Nicos Auftrag 10.09.: "sca_codereview_2026-09-06.html".
//
// Geprueft wird die FORM, nicht das Datum von heute - sonst haenge der
// Test an der Uhr und an SCA_REPORT_TIMESTAMP. Die Umgebungsvariable
// hier zu setzen waere die genauere, aber schlechtere Wahl: sie ist
// globaler Zustand, und jeder Test, der ihn setzt, muss ihn wieder
// herstellen (Lehre aus der Lexer-Kontamination, sechs rote Tests).
var
  Name : string;
  i    : Integer;
begin
  Name := TFindingsWorkbenchExport.DefaultFileName;

  Assert.IsTrue(Name.StartsWith('sca_codereview_'),
    'der Vorschlag heisst nicht mehr sca_codereview_...: ' + Name);
  Assert.IsTrue(Name.EndsWith('.html'),
    'der Vorschlag traegt keine .html-Endung: ' + Name);
  // Zwischen Praefix und Endung MUSS etwas stehen - sonst waere der
  // Name wieder fest und jeder Export ueberschriebe den vorigen.
  Assert.IsTrue(
    Length(Name) > Length('sca_codereview_') + Length('.html'),
    'zwischen Praefix und Endung steht nichts - der Name traegt kein '
    + 'Datum, und zwei Exporte ueberschreiben sich gegenseitig');
  // WINDOWS-TAUGLICH. Das ist kein Formalismus: SCA_REPORT_TIMESTAMP
  // darf einen ISO-Zeitstempel liefern, und dessen Doppelpunkt macht
  // aus dem Rest einen alternativen Datenstrom - die Datei ist dann
  // nicht falsch benannt, sondern unauffindbar (Modul-Codereview
  // 08.09.). Der Vorschlag geht durch V1s Sanitizer; dieser Test
  // haelt fest, dass er das weiterhin tut.
  for i := 1 to Length(Name) do
    Assert.IsFalse(
      CharInSet(Name[i], ['<', '>', ':', '"', '/', '\', '|', '?', '*'])
      or (Ord(Name[i]) < 32),
      'unter Windows verbotenes Zeichen im Vorschlag: ' + Name);
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
  // Seit 09.09. steht die Datei in DERSELBEN Zelle wie die Methode,
  // zweizeilig - die Formatierung der V3-Seite (Nicos Wunsch). Die
  // eigene tr.datei mit colspan=8 gibt es nicht mehr.
  Assert.IsTrue(
    Pos('<div class="zl-datei" title="src\A.pas">A.pas; src\A.pas'
      + '</div>', Html) > 0,
    'Datei-Zeile "Name; voller Pfad" mit title fehlt in der '
    + 'Methodenzelle');
  Assert.IsTrue(
    Pos('<div class="zl-datei" title="B.pas">B.pas</div>', Html) > 0,
    'bei blossem Basisnamen darf kein "Name; Name"-Doppel stehen');
  Assert.AreEqual<Integer>(0, Pos('<tr class="datei"', Html),
    'die eigene Datei-Zeile ist entfallen - sie kostete je Fund eine '
    + 'ganze Tabellenzeile');
  Assert.AreEqual<Integer>(0, Pos('class="pfadzeile"', Html),
    'die alte Pfadzeilen-Klasse darf nicht mehr vorkommen');
  Assert.IsTrue(Pos('data-pfad="src\A.pas"', Html) > 0,
    'data-pfad (Drawer-Fundort) fehlt am tbody');
  Assert.IsTrue(
    Pos('.zl-datei{overflow:hidden;text-overflow:ellipsis;'
      + 'white-space:nowrap;', Html) > 0,
    'Ellipse-CSS der Datei-Zeile fehlt');
end;

procedure TTestFindingsWorkbenchExport.Regelzelle_TraegtRegelUndDetailUntereinander;
// Nutzerauftrag 09.09.: Regelname und Detailtext sind beide oft lang
// und haben sich als Nachbarspalten gegenseitig die Breite genommen.
// Jetzt stehen sie in EINER Zelle untereinander, beide mit Ellipse.
//
// Der Test haelt auch die drei Folgen fest, die man sonst erst im
// Browser sieht: die Detail-Spalte ist weg (sieben Spalten statt
// acht), der Sortierschluessel traegt nur den Regelnamen, und der
// Drawer liest gezielt die Teilzeilen statt der ganzen Zelle.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10,
      'list not freed'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;

  Assert.IsTrue(Pos('<div class="zl-regel">', Html) > 0,
    'die Regel-Zeile der Zelle fehlt');
  Assert.IsTrue(Pos('<div class="zl-detail">list not freed</div>',
    Html) > 0, 'der Detailtext steht nicht unter der Regel');
  Assert.IsTrue(Pos('.zl-detail{overflow:hidden;text-overflow:ellipsis;',
    Html) > 0, 'der Detailtext kuerzt nicht mit Ellipse');
  // GAR KEIN colspan mehr. Es sass auf der Ausschnitt-Zeile, und die
  // ist display:none - sie hat nie etwas ausgerichtet. Bis 09.09. stand
  // dort erst 8, dann 7; beide Zahlen waren Gewohnheit aus der Zeit, als
  // der Ausschnitt aufgeklappt IN der Tabelle stand. Die Pruefung faengt
  // damit auch den Rueckfall auf die alte Achtspaltigkeit.
  Assert.AreEqual<Integer>(0, Pos('colspan=', Html),
    'eine Zelle spannt ueber mehrere Spalten - die Tabelle hat seit '
    + '09.09. keine solche Zeile mehr');
  // Der Drawer darf nicht die ganze Zelle lesen - sonst stuende im
  // Titel "SCA001 MemoryLeakObject created but not..." am Stueck.
  Assert.IsTrue(Pos('.querySelector(".zl-regel")', Html) > 0,
    'der Drawer liest den Regelnamen nicht gezielt');
  Assert.IsTrue(Pos('.querySelector(".zl-detail")', Html) > 0,
    'der Drawer liest den Detailtext nicht gezielt');
end;

procedure TTestFindingsWorkbenchExport.Spaltenbreiten_SindFestWieInV3;
// Nicos Review 09.09.: "die spaltenbreiten sind nicht richtig aus V3
// uebernommen worden" - sie waren es gar nicht. V2 hatte NUR
// table{width:100%}, den Rest machte die Browser-Automatik nach
// Inhalt. Damit wanderten die Spalten von Bericht zu Bericht, und die
// Ellipse griff nie: eine Zelle ohne feste Breite wird einfach
// breiter, statt zu kuerzen.
//
// table-layout:fixed ist deshalb der TRAGENDE Teil - ohne ihn haetten
// die width-Angaben keine Wirkung.
var
  Html : string;
begin
  Html := EinFundHtml;

  Assert.IsTrue(Pos('table-layout:fixed;', Html) > 0,
    'ohne table-layout:fixed wirken die Spaltenbreiten nicht und die '
    + 'Ellipse greift nie');
  // Die Werte stammen aus dem Grid der V3-Seite.
  Assert.IsTrue(Pos('th:nth-child(1){width:64px;}', Html) > 0,
    'Zeilen-Spalte ohne feste Breite');
  Assert.IsTrue(Pos('th:nth-child(3){width:92px;}', Html) > 0,
    'SCA-ID-Spalte ohne feste Breite');
  Assert.IsTrue(Pos('th:nth-child(5){width:132px;}', Html) > 0,
    'Typ-Spalte ohne feste Breite');
  Assert.IsTrue(Pos('th:nth-child(6){width:104px;}', Html) > 0,
    'Schweregrad-Spalte ohne feste Breite');
  Assert.IsTrue(Pos('th:nth-child(7){width:96px;}', Html) > 0,
    'Konfidenz-Spalte ohne feste Breite');
  // Die beiden TEXT-Spalten bekommen bewusst KEINE Breite - sie
  // teilen sich den Rest (Gegenstueck zu 1fr im Grid).
  Assert.AreEqual<Integer>(0, Pos('th:nth-child(2){width:', Html),
    'die Methoden-Spalte darf keine feste Breite haben');
  Assert.AreEqual<Integer>(0, Pos('th:nth-child(4){width:', Html),
    'die Regel-Spalte darf keine feste Breite haben');
end;

procedure TTestFindingsWorkbenchExport.Spaltenzeile_UndListenOverflow_GehoerenZusammen;
// ZWEI EINSTELLUNGEN, DIE NUR GEMEINSAM RICHTIG SIND.
//
// position:sticky bezieht sich auf den naechsten SCROLL-CONTAINER.
// Davon haengt ab, welches top an der Spaltenzeile stimmt:
//
//   .listwrap MIT overflow  -> sie ist der Scroller -> th top:0
//                              (ein Kopfversatz schoebe die Zeile in
//                              die Liste hinein: "rutscht runter",
//                              Nico-Befund 09.09.)
//   .listwrap OHNE overflow -> das FENSTER ist der Scroller -> th
//                              braucht den Versatz um Kopf und
//                              Filterleiste, sonst verschwindet die
//                              Zeile hinter beiden
//
// Das Projekt hat beide Faelle erlebt, in dieser Reihenfolge, und
// jedes Mal war die eine Aenderung ohne die andere falsch. Seit dem
// 10.09. gilt der zweite Fall: es gibt nur noch einen Scroller (s.
// Spaltenkopf_BleibtBeimScrollenSichtbar).
//
// Dieser Test sichert nicht das Verhalten - das tut der andere - er
// sichert die KOPPLUNG. Wer .listwrap wieder ein overflow gibt, faellt
// hier durch und wird auf das th gestossen.
var
  Html  : string;
  Regel : string;
  P, E  : Integer;
begin
  Html := EinFundHtml;

  // AUF DIE REGEL ZIELEN, nicht aufs Dokument. Der erste Wurf suchte
  // 'border-radius:8px;overflow' im ganzen HTML - und traf .codekarte
  // aus dem geteilten Designsystem, die genau so anfaengt. Eine
  // Zusicherung ueber das ganze Dokument ist bei CSS fast immer zu
  // weit; hier wird der Rumpf von .listwrap ausgeschnitten und NUR
  // der geprueft.
  P := Pos('.listwrap{', Html);
  Assert.IsTrue(P > 0, 'die Regel fuer die Fundliste fehlt ganz');
  E := Pos('}', Html, P);
  Assert.IsTrue(E > P, 'die Regel fuer die Fundliste ist offen');
  Regel := Copy(Html, P, E - P + 1);
  Assert.AreEqual<Integer>(0, Pos('overflow', Regel),
    'die Liste hat wieder ein overflow - dann ist SIE der Scroller, '
    + 'und das top am th muss zurueck auf 0');
  Assert.AreEqual<Integer>(0, Pos('max-height', Regel),
    'die Liste hat wieder eine eigene Hoehe - zusammen mit einem '
    + 'overflow macht das den zweiten Scroller');
  Assert.AreEqual<Integer>(0, Pos('position:sticky;z-index:2;top:0;',
    Html),
    'die Spaltenzeile klebt am oberen Fensterrand - dort verschwindet '
    + 'sie hinter Seitenkopf und Filterleiste');
  Assert.IsTrue(
    Pos('top:calc(var(--kopf-h,0px) + var(--filter-h,0px) - 1px);',
    Html) > 0,
    'die Spaltenzeile traegt nicht den Versatz um die beiden Bloecke, '
    + 'die ueber ihr kleben');
end;

procedure TTestFindingsWorkbenchExport.Bereiche_HabenBenennbareIds;
// Nutzerauftrag 09.09.: die Bereiche der Seite brauchen Namen, damit
// im Gespraech benennbar ist, WO etwas stehen soll - "in
// #bereich-kacheln" statt "oben rechts".
//
// Der Test haelt die Namen fest, weil sie ab jetzt eine Zusage nach
// aussen sind: wer einen umbenennt, bricht die Verstaendigung darueber.
const
  BEREICHE : array[0..7] of string = (
    'bereich-seitenkopf', 'bereich-inhalt', 'bereich-kacheln',
    'bereich-ampel', 'bereich-toplisten', 'bereich-suche',
    'bereich-dropdowns', 'bereich-fundliste');
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  i        : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;

  for i := Low(BEREICHE) to High(BEREICHE) do
    Assert.IsTrue(Pos('id="' + BEREICHE[i] + '"', Html) > 0,
      'der Bereich ' + BEREICHE[i] + ' hat keine ID');
  // Jede ID darf nur EINMAL vorkommen - doppelte ID ist ungueltiges
  // HTML, und querySelector faende dann die falsche.
  for i := Low(BEREICHE) to High(BEREICHE) do
    Assert.AreEqual<Integer>(1, VorkommenIn(Html,
      'id="' + BEREICHE[i] + '"'),
      'die ID ' + BEREICHE[i] + ' kommt mehrfach vor');
end;

procedure TTestFindingsWorkbenchExport.Bereiche_StehenInDerVorgegebenenReihenfolge;
// Nicos Vorgabe 09.09. fuer den Seitenaufbau:
//   Seitenkopf - Ampel - Kacheln - Toplisten - Suche/Dropdowns - Liste
//
// Erst die LAGE, dann die WERKZEUGE. Vorher stand die Filterleiste
// ganz oben, noch vor jeder Zahl - der Leser bekam Werkzeuge in die
// Hand, bevor er wusste wofuer; und sie stand weit weg von der Liste,
// auf die sie wirkt.
//
// Der Test prueft die Kette PAARWEISE. Eine einzelne Reihenfolge zu
// pruefen wuerde nicht auffallen, wenn ein Bereich in die Mitte
// rutscht.
var
  Html : string;
begin
  Html := EinFundHtml;

  AssertReihenfolge(Html, 'id="bereich-seitenkopf"', 'id="bereich-ampel"',
    'der Seitenkopf steht nicht vor der Ampel');
  AssertReihenfolge(Html, 'id="bereich-ampel"', 'id="bereich-kacheln"',
    'die Ampel steht nicht vor den Kacheln');
  AssertReihenfolge(Html, 'id="bereich-kacheln"', 'id="bereich-toplisten"',
    'die Kacheln stehen nicht vor den Top-Listen');
  AssertReihenfolge(Html, 'id="bereich-toplisten"', 'id="bereich-suche"',
    'die Top-Listen stehen nicht vor der Suche');
  AssertReihenfolge(Html, 'id="bereich-suche"', 'id="bereich-dropdowns"',
    'die Suche steht nicht vor den Dropdowns');
  AssertReihenfolge(Html, 'id="bereich-dropdowns"',
    'id="bereich-fundliste"',
    'die Filterleiste steht nicht direkt ueber der Liste');
end;

procedure TTestFindingsWorkbenchExport.Filterleiste_BleibtBeimScrollenSichtbar;
// Nicos Wunsch 09.09.: Suche, Dropdowns und Chips sollen auch oben
// sichtbar sein, unter dem Header. Im Dokument stehen sie direkt ueber
// der Liste; beim Scrollen durch 20.000 Zeilen waeren sie sonst weg.
//
// Drei Dinge muessen zusammenkommen, und zwei davon sieht man erst,
// wenn sie FEHLEN:
//   1. eine gemeinsame Huelle - einzeln angepinnt wuerden sich die
//      drei Bloecke am selben top ueberlagern
//   2. ein Hintergrund - sonst scrollt der Listeninhalt sichtbar
//      durch die angepinnte Leiste hindurch
//   3. top an der KOPFHOEHE, nicht 0: hier liegt der Block ausserhalb
//      der .listwrap, sein Bezug ist also das Fenster, und der
//      Seitenkopf klebt davor
var
  Html : string;
begin
  Html := EinFundHtml;

  Assert.IsTrue(Pos('<div id="bereich-filter">', Html) > 0,
    'die gemeinsame Huelle um Suche, Dropdowns und Chips fehlt');
  Assert.IsTrue(Pos('#bereich-filter{position:sticky;'
    + 'top:var(--kopf-h,0px);', Html) > 0,
    'die Filterleiste ist nicht unter dem Seitenkopf angepinnt');
  Assert.IsTrue(Pos('z-index:4;background:var(--grund);', Html) > 0,
    'ohne eigenen Hintergrund scrollt der Listeninhalt sichtbar durch '
    + 'die angepinnte Leiste');
  // Die Huelle umschliesst wirklich alle drei - sonst klebt nur ein
  // Teil und der Rest scrollt weg.
  AssertReihenfolge(Html, 'id="bereich-filter"', 'id="bereich-suche"',
    'die Suche liegt nicht in der Huelle');
  AssertReihenfolge(Html, 'id="bereich-dropdowns"', 'id="chips"',
    'die Chips stehen nicht hinter den Dropdowns');
  AssertReihenfolge(Html, 'id="chips"', 'id="bereich-fundliste"',
    'die Huelle reicht ueber die Liste hinaus');
end;

procedure TTestFindingsWorkbenchExport.Spaltenkopf_BleibtBeimScrollenSichtbar;
// Zwei Wuensche, die zusammen NUR mit einem einzigen Scroller gehen:
//   09.09. "der header der funde soll auch sichtbar bleiben beim hoch
//          scrollen"
//   10.09. "solange die oben fixierbaren Header noch nicht fixiert
//          sind, soll die ganze HTML noch nach oben scrollen"
//
// Der erste Wurf gab der Liste eine eigene Hoehe und ein eigenes
// overflow. Damit gab es ZWEI Scroller, und der Browser bedient immer
// den unter dem Mauszeiger: wer ueber der Liste scrollte, bewegte nur
// sie. Die Seite blieb stehen, also rasteten Kopf und Filterleiste nie
// ein - Nicos Befund vom 10.09.
//
// Der Test prueft die KETTE, denn jedes Glied allein ist wertlos:
//   1. es gibt genau EINEN Scroller - die Liste ist keiner mehr
//   2. drei Klebe-Ebenen, jede unter der vorigen: Kopf (0),
//      Filterleiste (--kopf-h), Spaltenzeile (--kopf-h + --filter-h)
//   3. das Skript pflegt beide Groessen, sonst rechnet Ebene 3 mit 0
var
  Html : string;
begin
  Html := EinFundHtml;

  // 1. EIN SCROLLER. Die vollstaendige Regel, damit weder ein
  // overflow noch eine max-height zurueckkommen kann: beide machten
  // die Liste wieder zum zweiten Scroller und Nicos Befund waere
  // zurueck. Auch overflow:hidden - schon das genuegt dafuer.
  Assert.IsTrue(Pos('.listwrap{background:var(--karte);border:1px solid '
    + 'var(--rand);border-radius:8px;'
    + 'box-shadow:0 1px 2px rgba(16,32,48,0.06);}', Html) > 0,
    'die Liste ist wieder ein eigener Scroller - dann scrollt sie '
    + 'statt der Seite, und die Kopfbereiche rasten nie ein');
  // 2. Die dritte Klebe-Ebene sitzt unter den beiden anderen.
  Assert.IsTrue(Pos('position:sticky;z-index:2;'
    + 'top:calc(var(--kopf-h,0px) + var(--filter-h,0px) - 1px);',
    Html) > 0,
    'die Spaltenzeile rastet nicht unter Kopf UND Filterleiste ein');
  // Die Filterleiste bemalt ihren Fussbereich selbst. Ohne das faellt
  // der Aussenabstand des Chip-Blocks aus ihr heraus und bleibt
  // durchsichtig - der Spalt, durch den Nico am 10.09. die Funde sah.
  Assert.IsTrue(Pos('padding-top:6px;padding-bottom:4px;', Html) > 0,
    'die Filterleiste bemalt ihren Fussbereich nicht');
  Assert.IsTrue(Pos('#bereich-filter .chips{margin-bottom:0;}', Html) > 0,
    'der Chip-Block traegt weiter einen Aussenabstand - der faellt aus '
    + 'der Leiste heraus und wird nicht mitbemalt');
  Assert.IsTrue(Pos('#bereich-filter{position:sticky;'
    + 'top:var(--kopf-h,0px);z-index:4;', Html) > 0,
    'die Filterleiste rastet nicht unter dem Seitenkopf ein');
  // 3. Beide Groessen werden gepflegt.
  // GEBROCHEN messen, nicht gerundet: offsetHeight liefert ganze
  // Pixel, und unter Windows-Skalierung sind Layouthoehen fast immer
  // krumm. Aus zwei gerundeten Hoehen einen Versatz zu rechnen setzt
  // die Spaltenzeile leicht zu tief - und durch den Spalt sieht man
  // die Funde durchlaufen (Nicos Befund 10.09.).
  Assert.IsTrue(
    Pos('"--filter-h",fl.getBoundingClientRect().height+"px"', Html) > 0,
    'die Hoehe der Filterleiste wird nicht gebrochen gemessen - '
    + 'gerundet rastet die Spaltenzeile um Bruchteile daneben ein');
  // Die Chips brechen je nach Fensterbreite um; ohne Nachmessen waere
  // die Liste danach zu hoch oder zu niedrig.
  Assert.IsTrue(Pos('new ResizeObserver(merken).observe(fl)', Html) > 0,
    'die Filterleiste wird nicht auf Hoehenaenderungen beobachtet');
end;

procedure TTestFindingsWorkbenchExport.Kopf_IstAngepinntUndSchrumpftBeimScrollen;
// Nutzerauftrag 09.09.: der Kopf bleibt oben stehen und zeigt beim
// Scrollen nur noch die Ueberschrift.
//
// Der Test haelt die drei Teile fest, die zusammen wirken muessen -
// und besonders den dritten, weil er sonst niemandem auffiele:
//   1. der Kopf ist angepinnt und hat einen mini-Zustand
//   2. das Umschalten passiert im Skript
//   3. die angepinnte FILTERLEISTE haengt an der Kopfhoehe. Stuende
//      sie bei top:0, verschwaende sie hinter dem angepinnten Kopf -
//      sichtbar erst, wenn man in einem langen Bericht scrollt.
//      (Die Spaltenzeile darunter prueft
//      Spaltenkopf_BleibtBeimScrollenSichtbar.)
var
  Html : string;
begin
  Html := EinFundHtml;

  // ZWEI Regeln, kein Kombi-String mehr: die Optik kommt aus BasisCss,
  // das Anpinnen aus KopfAngepinntCss. Getrennt, weil der CLI-Report
  // BasisCss einbindet, aber keinen klemmenden Kopf will - dort begrub
  // das Anpinnen die eigenen top:0-Spaltenkoepfe (Review 10.09.,
  // Blocker). Diese Seite muss BEIDE Teile tragen.
  Assert.IsTrue(Pos('header.kopf{background:#20303f;color:#f2f6fa;'
    + 'padding:14px 20px;}', Html) > 0,
    'die Kopf-Optik aus BasisCss fehlt');
  Assert.IsTrue(Pos('header.kopf{position:sticky;top:0;z-index:5;',
    Html) > 0,
    'der Kopf ist nicht angepinnt (KopfAngepinntCss fehlt)');
  Assert.IsTrue(Pos('header.kopf.mini .sub{max-height:0;opacity:0;',
    Html) > 0,
    'der minimierte Zustand blendet die Unterzeile nicht aus');
  Assert.IsTrue(Pos('kopf.classList.toggle("mini",runter);', Html) > 0,
    'es gibt keine Umschaltung zwischen den beiden Zustaenden');
  Assert.IsTrue(Pos('top:var(--kopf-h,0px)', Html) > 0,
    'die Filterleiste haengt nicht an der Kopfhoehe - sie wuerde beim '
    + 'Scrollen hinter dem angepinnten Kopf verschwinden');
  // Die Hoehe muss auch NACH der Animation stimmen, sonst bleiben
  // Filterleiste und Spaltenzeile um die Differenz verschoben.
  Assert.IsTrue(
    Pos('kopf.addEventListener("transitionend",hoeheMerken);', Html) > 0,
    'die Kopfhoehe wird nach dem Uebergang nicht nachgezogen');
end;

procedure TTestFindingsWorkbenchExport.Methodenzelle_SortiertOhneDenPfad;
// Die Methodenzelle enthaelt seit 09.09. ZWEI Texte. Ohne eigenen
// Sortierschluessel liest zellwert() ihren textContent - und damit
// wuerde nach "Methode plus Dateipfad" sortiert, also faktisch nach
// der Datei. Der Test haelt fest, dass data-sort den REINEN
// Methodennamen traegt.
var
  Html : string;
begin
  Html := EinFundHtml;

  // 'TestMethod' ist der Methodenname des Standardfundes - NACHGESEHEN,
  // nicht angenommen. Die erste Fassung dieses Tests stand auf einem
  // erfundenen 'TFoo.Bar' und war damit von Geburt an rot; gemerkt hat
  // es niemand, weil zwischen Schreiben und Bau eine ganze Charge lag.
  //
  // Der Vertrag ist unveraendert geprueft: der Standardfund liegt in
  // src/A.pas, Methodenname und Pfad sind also verschieden. Genau das
  // muss der Test zeigen - data-sort traegt den einen, nicht beide.
  Assert.IsTrue(Pos('<td data-sort="TestMethod"><div class="zl-methode">'
    + 'TestMethod</div>', Html) > 0,
    'die Methodenzelle traegt keinen eigenen Sortierschluessel - '
    + 'sortiert wuerde dann nach Methode UND Pfad');
  // Und die Gegenseite: zellwert muss einen TEXT-Schluessel
  // verkraften. Ein blindes parseInt liefert NaN, und NaN vergleicht
  // sich mit allem als false - die Spalte waere unsortierbar, ohne
  // dass es auffaellt.
  Assert.IsTrue(Pos('return isNaN(n) ? d.toLowerCase() : n;', Html) > 0,
    'zellwert() faellt bei nicht-numerischem data-sort nicht auf den '
    + 'Textvergleich zurueck');
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

  function OhneSkript(const AHtml: string): string;
  // Das Dokument OHNE seine script-Bloecke. Die Sprachpruefungen zielen
  // auf SICHTBARE Oberflaechentexte; das eingebettete JS traegt deutsche
  // CODE-KOMMENTARE (Projektkonvention, wie der Pascal-Quelltext auch) -
  // ein Assert ueber das ganze Dokument stolpert darueber und meldet
  // einen Uebersetzungsfehler, wo keiner ist.
  //
  // BIS 09.09. SCHNITT DIESE FUNKTION AM ERSTEN '<script' AB, und das
  // ging gut, solange das erste Skript am Dokumentende stand. An
  // diesem Tag kam eines in den <head> - der Themenschalter, damit die
  // Seite nicht sichtbar umspringt. Von da an lieferte OhneSkript nur
  // noch den Kopf, und ALLE Sprachpruefungen darunter waren blind:
  // gruen, ohne je den Seiteninhalt gesehen zu haben.
  //
  // Deshalb jetzt jeden Block einzeln herausschneiden statt am ersten
  // abzuschneiden. Der Test ist damit wieder scharf - und wenn er
  // etwas findet, hat er es die ganze Zeit ueber nicht gesehen.
  var
    P, E : Integer;
  begin
    Result := AHtml;
    P := Pos('<script', Result);
    while P > 0 do
    begin
      E := Pos('</script>', Result, P);
      if E = 0 then
      begin
        // Unabgeschlossen: der Rest gehoert zum Skript.
        Result := Copy(Result, 1, P - 1);
        Break;
      end;
      Delete(Result, P, E + Length('</script>') - P);
      P := Pos('<script', Result);
    end;
  end;

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
  Assert.IsTrue(Pos('var RSUCH={', En) > 0, 'Such-Zusatztabelle fehlt');
  Assert.AreEqual<Integer>(0, Pos('Warnung', OhneSkript(En)),
    'deutsches Severity-Wort im englischen Dokument');
  Assert.AreEqual<Integer>(0, Pos('warnung', OhneSkript(En)),
    'deutsches Severity-Wort im englischen Suchblob');
  Assert.AreEqual<Integer>(0, Pos('Hinweis', OhneSkript(En)),
    'deutsches Severity-Wort im englischen Dokument');
  Assert.AreEqual<Integer>(0, Pos('Konfidenz', OhneSkript(Fr)),
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

procedure TTestFindingsWorkbenchExport.InitialSort_BySeverity_WithConfidenceTiebreak;
// V1-Verhalten nachgezogen: der Bericht steht beim Oeffnen nach
// Risiko sortiert (Fehler oben), nicht in Eingangsreihenfolge - und
// bei gleicher Severity entscheidet die Konfidenz (hoch zuerst).
// Geprueft wird die VERDRAHTUNG: der Aufruf am Skriptende und der
// Tiebreak-Zweig; die Sortierung selbst laeuft im Browser.
var
  Html : string;
begin
  Html := EinFundHtml;
  // Severity ist Spalte 5 (Zeile, Methode, SCA-ID, Regel, Typ, Sev).
  Assert.IsTrue(Pos('sortiere(5);', Html) > 0,
    'Initialsortierung nach Severity fehlt - ohne den AUFRUF steht '
    + 'der Bericht in Eingangsreihenfolge da');
  AssertReihenfolge(Html, 'sortiere(5);', 'deepLink();',
    'die Sortierung muss vor dem Deep-Link laufen, sonst scrollt er '
    + 'auf eine Zeile, die gleich verschoben wird');
  Assert.IsTrue(Pos('if (spalte === 5) {', Html) > 0,
    'Tiebreak-Zweig des Severity-Sorts fehlt');
  // A11y (Restpunkt des UI-Abgleichs): die Sortierrichtung darf
  // nicht nur im Pfeil-ZEICHEN stecken - Screenreader lesen
  // aria-sort an der Kopfzelle.
  Assert.IsTrue(Pos('koepfe[k].setAttribute("aria-sort", '
    + 'auf ? "ascending" : "descending");', Html) > 0,
    'aria-sort wird beim Sortieren nicht gesetzt');
  Assert.IsTrue(Pos('koepfe[k].removeAttribute("aria-sort");', Html) > 0,
    'aria-sort bleibt an der alten Spalte stehen');
  Assert.IsTrue(Pos('return kb - ka;', Html) > 0,
    'Konfidenz-Tiebreak muss absteigend sein (hoch zuerst)');
  // Der Spaltenkopf 5 muss auch wirklich der Schweregrad sein -
  // sonst sortiert die Seite still nach der falschen Spalte.
  Assert.IsTrue(
    Pos('<th onclick="sortiere(5)">Schweregrad', Html) > 0,
    'Spalte 5 ist nicht der Schweregrad - Sortiervertrag gebrochen');
end;

procedure TTestFindingsWorkbenchExport.Theme_AntiBlitzStehtImHead;
// Waechter fuer Nicos Befund vom 09.09.: die Seite schaltete das Thema
// NACH dem Laden sichtbar um. Ursache war, dass data-theme erst im
// grossen Skript am Body-Ende gesetzt wurde - bis dahin hatte der
// @media-Block laengst nach der SYSTEM-Praeferenz gemalt.
//
// Der V1-Report loest das seit dem 19.08. mit einem winzigen
// Head-Skript; bei V2 war es nicht mitgewandert. Genau diese Stellung
// haelt der Test fest: das Lesen der gespeicherten Wahl muss VOR
// </head> stehen, also vor dem ersten Paint.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'list'));
    Html := TFindingsWorkbenchExport.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  AssertReihenfolge(Html, 'localStorage.getItem("sca-v2-theme")',
    '</head>',
    'die gespeicherte Theme-Wahl wird erst NACH dem Head gelesen - '
    + 'dann hat der Browser bereits im Systemthema gemalt und kippt '
    + 'sichtbar um');
  // Die Whitelist gehoert dazu: ohne sie landet ein korrupter
  // localStorage-Wert als Attribut-Muell im html-Element.
  AssertReihenfolge(Html, '["light","dark","sepia"].indexOf(t)',
    '</head>',
    'der Head-Block prueft den gespeicherten Wert nicht gegen die '
    + 'Whitelist');
end;

procedure TTestFindingsWorkbenchExport.Themes_DarkAndSepiaAsTokenOverrides;
// V1 hat drei Themes, V2 hatte nur hell. Seit dem Workbench-Umbau ist
// ein Theme ein reiner Token-Block - genau das wird hier festgehalten,
// damit spaetere Farbarbeit nicht wieder in Einzelregeln zerfaellt.
var
  Html : string;
begin
  Html := EinFundHtml;
  Assert.IsTrue(Pos(':root[data-theme="dark"]{--grund:#171b21;', Html) > 0,
    'Dark-Theme ueberschreibt die Tokens nicht');
  Assert.IsTrue(Pos(':root[data-theme="sepia"]{--grund:#f4ead2;', Html) > 0,
    'Sepia-Theme ueberschreibt die Tokens nicht');
  Assert.IsTrue(Pos('@media (prefers-color-scheme:dark){', Html) > 0,
    'Systempraeferenz wird nicht beachtet');
  // Farb-Ueberarbeitung 07.09.: JEDES Thema muss auch die
  // FLAECHEN-Tokens drehen. Ohne sie zoegen Badges, Pills und Chips
  // ihre hellen Pastellfarben aus dem geteilten CSS-Kern und
  // leuchteten auf dunklem Grund wie Textmarker - genau der Befund,
  // der die Ueberarbeitung ausgeloest hat.
  Assert.IsTrue(Pos('--f-err-bg:#3d201d;', Html) > 0,
    'Dark dreht die Fehler-Flaeche nicht mit');
  Assert.IsTrue(Pos('--f-lila-bg:#2e2440;', Html) > 0,
    'Dark dreht die CWE-/Vulnerability-Flaeche nicht mit');
  Assert.IsTrue(Pos('--f-code-bg:#12161b;', Html) > 0,
    'Dark dreht den Codeblock nicht mit');
  Assert.IsTrue(Pos('--f-err-bg:#f7ded6;', Html) > 0,
    'Sepia dreht die Fehler-Flaeche nicht mit');
  // Der geteilte Kern MUSS die Flaechen ueber Tokens beziehen -
  // sonst laeuft die Themenarbeit ins Leere.
  Assert.IsTrue(
    Pos('.badge.sev-err{background:var(--f-err-bg);', Html) > 0,
    'der CSS-Kern nutzt fuer die Badges keine Tokens');
  Assert.IsTrue(Pos('.chip{display:inline-block;'
    + 'background:var(--f-chip-bg);', Html) > 0,
    'der CSS-Kern nutzt fuer die Chips keine Tokens');
  // Systempraeferenz-Block traegt DENSELBEN Satz (eine Quelle).
  Assert.IsTrue(
    Pos(':root:not([data-theme="light"]):not([data-theme="sepia"])'
      + '{--grund:#171b21;', Html) > 0,
    'der @media-Block traegt nicht denselben Regelsatz');
  // Spezifitaets-Falle: der Hover haengt an '#funde tbody:hover tr'.
  Assert.IsTrue(
    Pos(':root[data-theme="dark"] #funde tbody:hover tr{', Html) > 0,
    'der Dark-Hover muss den ID-Selektor tragen, sonst gewinnt die '
    + 'helle Regel');
  Assert.IsTrue(Pos('id="btnTheme"', Html) > 0, 'Umschalter fehlt');
  Assert.IsTrue(Pos('var THEMEN = ["light", "dark", "sepia"];', Html) > 0,
    'Drei-Wege-Zyklus fehlt');
  Assert.IsTrue(Pos('sca-v2-theme', Html) > 0,
    'die Wahl wird nicht gespeichert');
  // localStorage kann werfen (file://, geblockte Site-Daten) - beide
  // Zugriffe MUESSEN gekapselt sein, sonst stirbt das Init-Skript und
  // mit ihm Suche, Sortierung und Drawer.
  Assert.IsTrue(
    Pos('try { gespeichert = localStorage.getItem(KEY); } catch',
      Html) > 0, 'localStorage-Lesen ohne try/catch');
  Assert.IsTrue(Pos('try { localStorage.setItem(KEY, next); } catch',
    Html) > 0, 'localStorage-Schreiben ohne try/catch');
end;

procedure TTestFindingsWorkbenchExport.Dropdowns_FileAndRule_FilterAndReset;
// Datei- und Regel-Dropdown (V1-Feature, in V2 nachgezogen). Wichtig
// sind drei Dinge: die Optionswerte muessen zu den data-Attributen
// der Zeilen passen (sonst filtert die Auswahl ins Leere), die
// Filterlogik muss in suche() haengen, und filterReset muss sie
// mit zuruecksetzen.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 20, 'b'));
    Findings.Add(MakeFinding(fkDebugOutput, 'src\B.pas', 30, 'c'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('id="dateiFilter"', Html) > 0,
    'Datei-Dropdown fehlt');
  Assert.IsTrue(Pos('id="regelFilter"', Html) > 0,
    'Regel-Dropdown fehlt');
  // Der Optionswert MUSS dem data-pfad der Zeile entsprechen. Bei
  // leerem BaseDir ist der Anzeigepfad der VOLLE Fundpfad
  // ('src\A.pas', nicht 'A.pas') - belegt ueber
  // TExporter.RelativeDisplayPath, das ohne Wurzel unveraendert
  // durchreicht (derselbe Wert steht im FileRow-Test im title).
  Assert.IsTrue(
    Pos('<option value="src\A.pas">src\A.pas (2)</option>', Html) > 0,
    'Datei-Option mit Fundzahl fehlt oder Wert passt nicht');
  Assert.IsTrue(Pos('data-pfad="src\A.pas"', Html) > 0,
    'Zeilen-Attribut passt nicht zum Optionswert');
  // Regeln nach Fundzahl absteigend - GEZIELT ueber die IDs geprueft:
  // SCA001 (MemoryLeak, 2 Funde) muss vor SCA017 (DebugOutput, 1)
  // stehen. Ein blosser Vergleich der Zeichenketten '(2)' und '(1)'
  // haette die DATEI-Liste erwischt, die alphabetisch sortiert ist -
  // der Test haette zufaellig gestimmt, ohne die Regel-Sortierung
  // zu pruefen.
  Assert.IsTrue(Pos('<option value="SCA001">', Html) > 0,
    'Regel-Option SCA001 fehlt');
  Assert.IsTrue(Pos('<option value="SCA017">', Html) > 0,
    'Regel-Option SCA017 fehlt');
  AssertReihenfolge(Html, '<option value="SCA001">',
    '<option value="SCA017">',
    'Regel-Dropdown muss nach Fundzahl absteigend sortiert sein '
    + '(SCA001 mit 2 Funden vor SCA017 mit 1)');
  // Verdrahtung in suche() und im Reset.
  Assert.IsTrue(Pos('tbs[i].dataset.pfad === datei', Html) > 0,
    'Datei-Filter haengt nicht in suche()');
  Assert.IsTrue(Pos('tbs[i].dataset.rid === regel', Html) > 0,
    'Regel-Filter haengt nicht in suche()');
  Assert.IsTrue(Pos('if (dd) dd.value = "";', Html) > 0,
    'filterReset setzt das Datei-Dropdown nicht zurueck');
  Assert.IsTrue(Pos('q !== "" || datei !== "" || regel !== ""',
    Html) > 0, 'der Reset-Knopf erscheint bei Dropdown-Auswahl nicht');
end;

procedure TTestFindingsWorkbenchExport.TopLists_SortedByCount_AndClickable;
// Top-Listen (V1-Feature): nach Fundzahl absteigend UND klickbar.
// Der Sortier-Assert zielt auf die DATEI-Liste, weil sie im Dropdown
// alphabetisch steht - genau dort faellt auf, wenn die Top-Liste die
// Eingangsreihenfolge uebernimmt statt selbst zu sortieren.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  i        : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    // 'z.pas' bekommt MEHR Funde als 'a.pas' - alphabetisch stuende
    // a.pas vorn, nach Fundzahl muss z.pas gewinnen.
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\a.pas', 1, 'x'));
    for i := 1 to 3 do
      Findings.Add(MakeFinding(fkDebugOutput, 'src\z.pas', i, 'y'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('id="topRegeln"', Html) > 0, 'Top-Regeln fehlen');
  Assert.IsTrue(Pos('id="topDateien"', Html) > 0, 'Top-Dateien fehlen');
  // Beschriftung mit NAMEN, nicht nur der ID (Nico 09.09.): "SCA001"
  // allein sagt niemandem, worum es geht. Der Filterwert bleibt die
  // reine ID - nur die Anzeige wird laenger.
  //
  // Geprueft wird die STRUKTUR, nicht der konkrete Name: der kommt aus
  // dem Regelkatalog und haengt an der Sprache UND daran, ob die
  // rules-JSON zur Laufzeit gefunden wird (sonst greift der
  // einkompilierte Fallback mit anderen Texten). Ein Test auf
  // "SCA001 MemoryLeak" waere je nach Fundort der JSON rot - der
  // deutsche Katalog sagt dort "Objekt ohne ausnahmesichere Freigabe
  // erzeugt".
  Assert.IsTrue(Pos('<span class="tl-name" title="SCA001 ', Html) > 0,
    'die Top-Regeln zeigen nur die SCA-ID statt ID und Regelname');
  Assert.AreEqual<Integer>(0,
    Pos('<span class="tl-name" title="SCA001">', Html),
    'der Titel besteht nur aus der ID - der Regelname fehlt');
  Assert.IsTrue(Pos('data-wert="SCA001"', Html) > 0,
    'der Filterwert muss die reine SCA-ID bleiben - das Dropdown '
    + 'kennt keine Namen');
  // Die Ellipse war schon da; sie traegt jetzt aber erst, weil der
  // Text lang genug wird.
  Assert.IsTrue(Pos('.tl-name{flex:1 1 auto;overflow:hidden;'
    + 'text-overflow:ellipsis;white-space:nowrap;', Html) > 0,
    'die Beschriftung der Top-Listen kuerzt nicht mit Ellipse');
  AssertReihenfolge(Html,
    'data-ziel="dateiFilter" data-wert="src\z.pas"',
    'data-ziel="dateiFilter" data-wert="src\a.pas"',
    'die Top-Dateien muessen nach Fundzahl sortiert sein, nicht '
    + 'alphabetisch (z.pas mit 3 vor a.pas mit 1)');
  Assert.IsTrue(Pos('function topKlick(el)', Html) > 0,
    'Klick-Handler der Top-Listen fehlt');
  Assert.IsTrue(Pos('onclick="topKlick(this)"', Html) > 0,
    'Top-Eintraege sind nicht verdrahtet');
  Assert.IsTrue(Pos('dd.value = el.dataset.wert;', Html) > 0,
    'der Klick setzt das Dropdown nicht');
  // Balken: der groesste Eintrag hat 100 %.
  Assert.IsTrue(Pos('style="width:100%"', Html) > 0,
    'Balkenbreite fehlt oder ist nicht relativ zum Maximum');
end;

procedure TTestFindingsWorkbenchExport.HealthAndSecurity_ScoreMatchesV1Formula;
// Health-Ampel mit der V1-FORMEL (Err*100 + Warn*10 + Hint*1) und
// den V1-Schwellen - eine zweite Rechnung waere ein zweiter Massstab
// fuer dieselbe Codebasis. Fixture: 1x fkMemoryLeak = lsError
// (KIND_META, belegt) -> Score 100 -> ueber 49, unter 500 -> "gelb".
var
  Html : string;
begin
  Html := EinFundHtml;
  Assert.IsTrue(Pos('class="health health-gelb"', Html) > 0,
    'ein Fehler ergibt Score 100 -> Ampel gelb (49 < 100 <= 499)');
  Assert.IsTrue(Pos('<div class="health-zahl">100</div>', Html) > 0,
    'Score-Wert stimmt nicht mit der V1-Formel ueberein');
  Assert.IsTrue(Pos('Beobachten', Html) > 0, 'Ampel-Text fehlt');
  // Security-Panel: fkMemoryLeak ist ftBug, also KEIN Security-Fund -
  // das Panel darf dann gar nicht erscheinen.
  Assert.AreEqual<Integer>(0, Pos('id="btnSec"', Html),
    'ohne Security-Funde darf kein Security-Panel erscheinen');
  Assert.IsTrue(Pos('function zeigeSecurity()', Html) > 0,
    'der Security-Handler gehoert trotzdem ins Skript');
  Assert.IsTrue(
    Pos('aktiveFilter.typ = ["vuln", "hotspot"];', Html) > 0,
    'der Security-Knopf muss die bestehenden Typ-Chips setzen, '
    + 'keinen eigenen Filterweg erfinden');
end;

procedure TTestFindingsWorkbenchExport.SourceSnippet_LiestUtf8OhneBom;
// Blocker 2 des Chargen-Reviews 10.09.: der Ausschnitt lud ohne
// Encoding. LoadFromFile erkennt dann nur ein BOM und dekodiert
// UTF-8 OHNE BOM still als ANSI - aus einem 'ü' im Quelltext wird
// Zwei-Zeichen-Muell im Drawer. UTF-8 ohne BOM ist der Normalfall in
// fremden Repos (das eigene brauchte am 20.08. einen BOM-Fix fuer
// 743 Dateien).
//
// Die Fixture schreibt deshalb GEZIELT ohne BOM (WriteBOM=False).
// Mit BOM waere der Test auch am alten, kaputten Lader gruen gewesen
// - die BOM-Erkennung von LoadFromFile haette ihn gerettet und der
// Test haette nichts geprueft.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Datei    : string;
  SL       : TStringList;
  i        : Integer;
begin
  Datei := TPath.Combine(TPath.GetTempPath,
    'sca-utf8-' + TGUID.NewGuid.ToString + '.pas');
  SL := TStringList.Create;
  try
    for i := 1 to 5 do
      SL.Add('zeile' + IntToStr(i) + ' pr'#$FC'ft Gr'#$F6#$DF'e;');
    SL.WriteBOM := False;
    SL.SaveToFile(Datei, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, Datei, 3, 'a'));
    Html := Render(Findings);
  finally
    Findings.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
  Assert.IsTrue(Pos('zeile3 pr'#$FC'ft Gr'#$F6#$DF'e;', Html) > 0,
    'die Umlaute des UTF-8-ohne-BOM-Quelltexts kommen nicht heil im '
    + 'Ausschnitt an - der Lader dekodiert als ANSI');
  Assert.AreEqual<Integer>(0, Pos('pr'#$C3#$BC'ft', Html),
    'Mojibake im Ausschnitt - genau die Doppel-Zeichen-Folge einer '
    + 'ANSI-Fehldekodierung');
end;

procedure TTestFindingsWorkbenchExport.SourceSnippet_RendersAroundFindingLine;
// Der Quell-Ausschnitt war die groesste Luecke der V2 gegenueber V1.
// Geprueft mit einer ECHTEN Datei (sonst prueft der Test nur, dass
// nichts passiert): 10 Zeilen, Fund auf Zeile 5, Kontext 3 -> die
// Zeilen 2..8 muessen erscheinen, 1 und 9 nicht, und Zeile 5 traegt
// die Hervorhebung.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Datei    : string;
  SL       : TStringList;
  i        : Integer;
begin
  Datei := TPath.Combine(TPath.GetTempPath,
    'sca-snip-' + TGUID.NewGuid.ToString + '.pas');
  SL := TStringList.Create;
  try
    for i := 1 to 10 do
      SL.Add('zeile' + IntToStr(i) + ' inhalt;');
    SL.SaveToFile(Datei);
  finally
    SL.Free;
  end;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, Datei, 5, 'a'));
    Html := Render(Findings);
  finally
    Findings.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
  // DER INHALT - unveraendert gegenueber frueher.
  Assert.IsTrue(Pos('zeile5 inhalt;', Html) > 0,
    'die Fundzeile selbst fehlt im Ausschnitt');
  Assert.IsTrue(Pos('zeile2 inhalt;', Html) > 0,
    'Kontext davor fehlt (3 Zeilen)');
  Assert.IsTrue(Pos('zeile8 inhalt;', Html) > 0,
    'Kontext danach fehlt (3 Zeilen)');
  Assert.AreEqual<Integer>(0, Pos('zeile1 inhalt;', Html),
    'Zeile 1 liegt ausserhalb des Kontexts und darf nicht erscheinen');
  Assert.AreEqual<Integer>(0, Pos('zeile9 inhalt;', Html),
    'Zeile 9 liegt ausserhalb des Kontexts und darf nicht erscheinen');
  // DIE FORM - seit 09.09. Rohtext statt fertigem Markup.
  Assert.IsTrue(Pos('<tr class="snippet">', Html) > 0,
    'Traegerzeile des Ausschnitts fehlt');
  Assert.IsTrue(Pos('tr.snippet{display:none;}', Html) > 0,
    'der Ausschnitt darf in der Tabelle nicht sichtbar sein');
  // Die beiden Zahlen, aus denen die Anzeige die Nummern rechnet:
  // Fund auf 5, Kontext 3 -> erste Zeile ist die 2.
  Assert.IsTrue(Pos('<td data-l="2" data-a="5">zeile2 inhalt;', Html) > 0,
    'die Traegerzelle fuehrt nicht Startzeile, Fundzeile und Rohtext');
  // DIE ERSPARNIS - und der einzige Grund fuer den Umbau. Ohne diese
  // Gegenprobe waere ein Rueckfall auf fertiges Markup gruen: der
  // Inhalt stimmte ja weiter, nur die Datei waere wieder dreimal so
  // gross. Das Geruest darf in der SEITE nicht mehr vorkommen -
  // ausser dort, wo das Skript es baut.
  Assert.AreEqual<Integer>(0, Pos('<div class="src-line">', Html),
    'das Zeilen-Geruest steht wieder in der Seite statt im Skript');
  Assert.AreEqual<Integer>(0, Pos('<span class="src-line-num">', Html),
    'der Nummernblock steht wieder in der Seite statt im Skript');
  // DER BAUER - er ersetzt das Geruest und muss die Klassen fuehren,
  // sonst faellt der Ausschnitt aus dem CSS heraus.
  Assert.IsTrue(Pos('function baueAusschnitt(td) {', Html) > 0,
    'die Anzeige-Funktion fuer den Ausschnitt fehlt');
  Assert.IsTrue(Pos('wrap.className = "src-snippet";', Html) > 0,
    'der gebaute Ausschnitt traegt die Rahmenklasse nicht');
  Assert.IsTrue(Pos('"src-line src-line-active" : "src-line"', Html) > 0,
    'der gebaute Ausschnitt hebt die Fundzeile nicht hervor');
  Assert.IsTrue(Pos('kopf.appendChild(baueAusschnitt(sz));', Html) > 0,
    'der Drawer baut den Ausschnitt nicht');
end;

procedure TTestFindingsWorkbenchExport.IdeInspector_HeroHierarchyAndSelectionStates;
// Variante A "IDE Focus": die Auswahl traegt einen 4px-Rail in der
// SEVERITY-Farbe und ist von Hover und Focus unterscheidbar; der
// Inspector beginnt mit einem Hero (Punkt, ID, Titel, Badges), zeigt
// den Quellcode frueh und staffelt Erklaerung, Fix und die
// sekundaeren Karten. Geprueft wird die STRUKTUR - die Optik selbst
// sieht nur Nico.
var
  Html : string;
begin
  Html := EinFundHtml;
  // --- Selection ------------------------------------------------------
  // NEU ist hier nur der Rail; die Asserts auf Hover und Focus sind
  // REGRESSIONS-Waechter fuer Bestandsregeln, die zusammen mit dem
  // Rail die drei Zustaende bilden - sie waren vor diesem Umbau schon
  // gruen und belegen ihn nicht (Review 08.09.).
  Assert.IsTrue(Pos('#funde tbody tr td:first-child{'
    + 'border-left:4px solid transparent;}', Html) > 0,
    'der 4px-Rail-Platzhalter fehlt (sonst springt das Layout beim '
    + 'Auswaehlen)');
  Assert.IsTrue(Pos('#funde tbody.gewaehlt[data-sev="0"] tr '
    + 'td:first-child{border-left-color:var(--f-err-fg);}', Html) > 0,
    'der Rail wird nicht von der Severity gefaerbt');
  // Rang 3 (Lesefehler) braucht eine EIGENE Farbe: der Rueckfall auf
  // --akzent ist im hellen Thema byte-gleich mit --f-info-fg, ein
  // Lesefehler saehe aus wie ein Hinweis (Review 08.09.).
  Assert.IsTrue(Pos('#funde tbody.gewaehlt[data-sev="3"] tr '
    + 'td:first-child{border-left-color:var(--dezent);}', Html) > 0,
    'Lesefehler-Rail fehlt und faellt auf die Hinweis-Farbe zurueck');
  // Die Auswahl hebt den REGELNAMEN an - Spalte 4, nicht 5 (5 waere
  // die Typ-Zelle; der erste Wurf machte nur den Badge fett).
  // Seit 09.09. gezielt die .zl-regel-Zeile: in derselben Zelle steht
  // darunter der Detailtext, und der ist bewusst gedaempft.
  Assert.IsTrue(Pos('#funde tbody.gewaehlt tr.haupt td:nth-child(4) '
    + '.zl-regel{font-weight:700;}', Html) > 0,
    'die Auswahl hebt nicht den Regelnamen an');
  Assert.AreEqual<Integer>(0,
    Pos('tr.haupt td:nth-child(5){font-weight', Html),
    'nth-child(5) ist die Typ-Zelle - diese Regel darf es nicht geben');
  Assert.IsTrue(Pos('#funde tbody:hover tr{', Html) > 0,
    'Hover-Zustand fehlt');
  Assert.IsTrue(Pos('tr.haupt:focus-visible{', Html) > 0,
    'Focus-Zustand fehlt - Tastaturbedienung braucht ihn eigenstaendig');
  // --- Inspector-Kopf (Aufbau der V3-Seite, 09.09.) ------------------
  // Der verschachtelte Hero-Block ist entfallen: Badges, Ueberschrift
  // und Fundort stehen jetzt flach nebeneinander, wie in V3. Der
  // Severity-Punkt ist weg, weil das Badge daneben dasselbe sagt.
  Assert.IsTrue(Pos('badges.className = "insp-badges";', Html) > 0,
    'Badge-Zeile fehlt');
  Assert.IsTrue(Pos('titel.className = "insp-titel";', Html) > 0,
    'Ueberschrift fehlt');
  Assert.IsTrue(Pos('ort.className = "metarow";', Html) > 0,
    'Fundort fehlt oder nutzt nicht die geteilte metarow-Klasse');
  Assert.AreEqual<Integer>(0, Pos('insp-hero', Html),
    'der verschachtelte Hero-Block ist entfallen');
  Assert.AreEqual<Integer>(0, Pos('insp-punkt', Html),
    'der Severity-Punkt ist entfallen - das Badge sagt dasselbe');
  // Die Ueberschrift traegt ID UND Regelname in einer Zeile.
  // Der Regelname kommt aus .zl-regel, NICHT aus dem textContent der
  // Zelle: die traegt seit 09.09. auch den Detailtext, und der gehoert
  // nicht in die Ueberschrift.
  Assert.IsTrue(
    Pos('var rn = z.cells[3].querySelector(".zl-regel");', Html) > 0,
    'der Regelname wird nicht aus seinem eigenen Block geholt');
  Assert.IsTrue(Pos('titel.textContent = z.cells[2].textContent + " " '
    + '+ (rn ? rn.textContent : "");', Html) > 0,
    'die Ueberschrift setzt nicht ID und Regelname zusammen');
  // Die Badges werden GEKLONT - so bleibt ihre Optik automatisch
  // dieselbe wie in der Tabelle.
  Assert.IsTrue(Pos('badges.appendChild(b.cloneNode(true));', Html) > 0,
    'die Badges werden nicht aus den Zellen geklont');
  // --- Reihenfolge: Kopf VOR Quellcode VOR Regel-Doku ---------------
  // Der Ausschnitt wird seit 09.09. GEBAUT statt geklont: er liegt als
  // Rohtext bei der Zeile, nicht als fertiges Markup (s.
  // SourceSnippet_RendersAroundFindingLine). Der Anker heisst deshalb
  // anders - die gepruefte Reihenfolge ist dieselbe.
  AssertReihenfolge(Html, 'kopf.appendChild(ort);',
    'kopf.appendChild(baueAusschnitt(sz));',
    'der Quellcode muss NACH dem Fundort kommen');
  AssertReihenfolge(Html, 'korb.appendChild(fundKopf(tb));',
    'korb.appendChild(tpl.content.cloneNode(true));',
    'die Regel-Doku muss NACH dem Fund-Kopf kommen');
  // --- Template: kein doppelter Titel mehr, dafuer Staffelung -------
  Assert.AreEqual<Integer>(0, Pos('<div class="drawer-status">', Html),
    'die alten Status-Badges des Templates muessen weg sein - sie '
    + 'zeigten Regel-Defaults statt der Werte DIESES Fundes');
  Assert.IsTrue(Pos('<div class="insp-fix">', Html) > 0,
    'der Fix-Block fehlt');
  Assert.IsTrue(Pos('<div class="insp-sekundaer">', Html) > 0,
    'noinspection/Kalibrierung sind nicht als sekundaer gekennzeichnet');
  Assert.IsTrue(Pos('<h3>Fix-Muster</h3>', Html) > 0,
    'die Fix-Ueberschrift fehlt');
  // Die h3-Grossschreibung darf die Kopieren-Buttons IN den
  // Karten-Ueberschriften nicht erfassen (sonst 'KOPIEREN').
  Assert.IsTrue(Pos('#drawer h3 button.copy{text-transform:none;',
    Html) > 0,
    'die Uppercase-Ruecknahme fuer Buttons in h3 fehlt');
  // --- Bewegung + Breite --------------------------------------------
  Assert.IsTrue(
    Pos('@media (prefers-reduced-motion:reduce){#drawer{transition:none;}}',
      Html) > 0, 'reduzierte Bewegung wird nicht beachtet');
  Assert.IsTrue(Pos('width:41%;', Html) > 0,
    'Inspector-Breite ausserhalb des Zielbands 38-44 %');
  // Inhalte bleiben vollstaendig (Akzeptanzkriterium 8).
  Assert.IsTrue(Pos('<h3>Was wird erkannt?</h3>', Html) > 0,
    'Erklaerung verloren');
  Assert.IsTrue(Pos('// noinspection', Html) > 0,
    'noinspection-Karte verloren');
  Assert.IsTrue(Pos('class="metarow"', Html) > 0,
    'Metadaten-Zeile verloren');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingsWorkbenchExport);

end.
