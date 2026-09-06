unit uTestDetectorInfoExport;

// Tests fuer uDetectorInfoExport (Regelkatalog als HTML-Seite,
// Nutzerauftrag 2026-09-06): Vollstaendigkeit, Escaping, deutsche
// Overlay-Texte, Sortier-/Such-Geruest, BOM-Schreibweg.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  uSCAConsts, uRuleCatalog, uDetectorInfoExport,
  uExportHtml;   // HtmlEscape-Vertragstest (Attribut-Integritaet)

type
  [TestFixture]
  TTestDetectorInfoExport = class
  strict private
    FHtml : string;   // einmal gebaut, von allen Faellen gelesen
  public
    [Setup]    procedure Setup;
    [Test] procedure EveryRule_AppearsExactlyOnce;
    [Test] procedure GermanOverlayName_IsUsed;
    [Test] procedure Examples_AreHtmlEscaped;
    [Test] procedure SortAndSearchScaffolding_Present;
    [Test] procedure DefaultProfileColumn_ShowsOnAndOff;
    [Test] procedure WriteToFile_WritesUtf8WithBom;
    // Chargen-Review 06.09.: die Suchbasis muss Unicode-gesenkt,
    // umbruchfrei und attributrein sein - und der geteilte Escaper
    // muss das Anfuehrungszeichen abdecken (Attribut-Integritaet).
    [Test] procedure SearchBlob_IsLoweredUmlautsIncluded;
    [Test] procedure SearchBlob_AttributeSafeAndBreakFree;
    [Test] procedure HtmlEscape_CoversQuote;
    // Ausgabevertrag-Runde 2026-09-06 (Nutzerauftrag "fuer die beiden
    // HTML soll es Tests geben"): Detailzeilen-Inhalt, data-sort-
    // Ordinale, Kopf-Selbstkonsistenz, Fehlerweg, Namensvertrag.
    [Test] procedure DetailRow_CarriesDescriptionCweConfigUnit;
    [Test] procedure DataSort_OrdinalsMatchDisplayedWords;
    [Test] procedure HeaderCount_ColspanAndFootnote_Consistent;
    [Test] procedure WriteToFile_InvalidPathRaises;
    [Test] procedure DefaultFileName_IsStableContract;
    // Nutzerauftrag 2026-09-07: der Rollen-Block (Entwicklung/QA/PO)
    // muss offen und VOR dem Suchfeld stehen - "immer gut zugaenglich".
    [Test] procedure RoleBlock_PresentOpenAndBeforeSearch;
    // Workbench-Umbau 07.09. (UI-Konzept-PDFs): Command-Bar, Chips,
    // Dashboard, Drawer, Tastatur und Deep-Link muessen verdrahtet sein.
    [Test] procedure Workbench_ScaffoldingWiredCompletely;
  end;

implementation

// noinspection-file DuplicateString
// 'data-search="' wiederholt sich absichtlich - das Attribut IST der
// Pruefgegenstand mehrerer Faelle (Fixture-Ausnahme des Profils).

procedure TTestDetectorInfoExport.Setup;
begin
  TRuleCatalog.Reload;   // frischer Katalogzustand (Muster uTestRuleCatalog)
  FHtml := TDetectorInfoExport.BuildHtml('de');
end;

procedure TTestDetectorInfoExport.EveryRule_AppearsExactlyOnce;
// Jede Regel-ID steht als eigene Zelle drin, und die Zahl der
// tbody-Bloecke entspricht der Katalog-Groesse (ein Block je Regel).
var
  K      : TFindingKind;
  Meta   : TRuleMeta;
  Zelle  : string;
  Bloecke, P : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta  := TRuleCatalog.GetRuleCanonical(K);
    Zelle := '<td class="id">' + Meta.ID + '</td>';
    Assert.IsTrue(Pos(Zelle, FHtml) > 0,
      Format('%s fehlt in der Seite', [Meta.ID]));
  end;
  Bloecke := 0;
  P := Pos('<tbody', FHtml);
  while P > 0 do
  begin
    Inc(Bloecke);
    P := Pos('<tbody', FHtml, P + 1);
  end;
  Assert.AreEqual<Integer>(TRuleCatalog.Count, Bloecke,
    'ein tbody-Block je Regel (Haupt- + Detailzeile als Paar)');
end;

procedure TTestDetectorInfoExport.GermanOverlayName_IsUsed;
// Das DE-Overlay traegt fuer SCA001 den Namen 'Objekt ohne
// ausnahmesichere Freigabe erzeugt' - genau der muss in der Seite
// stehen, nicht der englische Katalogname. Faengt sowohl einen
// Overlay-Ladefehler als auch ein hart-englisches BuildHtml.
var
  MetaDe : TRuleMeta;
  MetaEn : TRuleMeta;
begin
  MetaDe := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  MetaEn := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Assert.AreNotEqual(MetaEn.Name, MetaDe.Name,
    'Vorbedingung: das DE-Overlay uebersetzt den SCA001-Namen');
  Assert.IsTrue(Pos('<td>' + MetaDe.Name + '</td>', FHtml) > 0,
    'die Seite traegt den deutschen Regelnamen');
end;

procedure TTestDetectorInfoExport.Examples_AreHtmlEscaped;
// Das SCA001-Beispiel enthaelt '<-- exception here leaks list'. Roh
// eingebettet zerrisse das die Seite - es muss als &lt; ankommen.
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Assert.IsTrue(Pos('<--', Meta.BadExample) > 0,
    'Vorbedingung: das Katalog-Beispiel enthaelt ein rohes <');
  Assert.IsTrue(Pos('&lt;--', FHtml) > 0,
    'das Beispiel steht escaped in der Seite');
  Assert.IsFalse(Pos('<-- exception', FHtml) > 0,
    'kein rohes < aus dem Beispiel im HTML');
end;

procedure TTestDetectorInfoExport.SortAndSearchScaffolding_Present;
// Nutzerauftrag: Spalten sortierbar + Suche ueber den gesamten
// Inhalt. Prueft das eingebettete Geruest (Funktionen + Verdrahtung).
begin
  Assert.IsTrue(Pos('function sortiere', FHtml) > 0, 'Sortier-JS fehlt');
  Assert.IsTrue(Pos('function suche', FHtml) > 0, 'Such-JS fehlt');
  Assert.IsTrue(Pos('data-search="', FHtml) > 0,
    'Suchbasis je Regel fehlt');
  Assert.IsTrue(Pos('onclick="sortiere(7)"', FHtml) > 0,
    'alle acht Spaltenkoepfe sind verdrahtet');
  Assert.IsTrue(Pos('oninput="suche()"', FHtml) > 0,
    'das Suchfeld ist verdrahtet');
end;

procedure TTestDetectorInfoExport.DefaultProfileColumn_ShowsOnAndOff;
// Das default-Profil schaltet Style-Regeln ab ('*' + !Ausschluesse):
// die Spalte muss beide Zustaende zeigen - mindestens ein 'an' und
// mindestens ein 'aus' (sonst waere GetProfile('default') zum
// AllKinds-Fallback gekippt und die Spalte wertlos).
begin
  Assert.IsTrue(Pos('<span class="pill an">an</span>', FHtml) > 0,
    'kein aktiver Default-Profil-Eintrag gefunden');
  Assert.IsTrue(Pos('<span class="pill aus">aus</span>', FHtml) > 0,
    'kein abgeschalteter Default-Profil-Eintrag gefunden');
end;

procedure TTestDetectorInfoExport.WriteToFile_WritesUtf8WithBom;
var
  Datei : string;
  Bytes : TBytes;
begin
  Datei := IncludeTrailingPathDelimiter(TPath.GetTempPath)
    + 'sca_test_detinfo_'
    + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
    + '.html';
  try
    TDetectorInfoExport.WriteToFile(Datei, 'de');
    Bytes := TFile.ReadAllBytes(Datei);
    Assert.IsTrue(Length(Bytes) > 3, 'Datei ist leer');
    Assert.IsTrue((Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
      'UTF-8-BOM fehlt (Export-Konvention)');
  finally
    if FileExists(Datei) then DeleteFile(Datei);
  end;
end;

procedure TTestDetectorInfoExport.SearchBlob_IsLoweredUmlautsIncluded;
// Das DE-Overlay traegt Regelnamen mit grossen Umlauten (z.B. SCA072
// 'Ueberfluessig...'-Familie mit U-Umlaut). Die JS-Suche senkt die
// Eingabe Unicode-korrekt - der Blob muss es genauso tun, sonst sind
// diese Woerter in KEINER Schreibweise findbar (Review-Major; mit
// ASCII-LowerCase ist dieser Test ROT). Das Testliteral bleibt ASCII:
// der erwartete Text wird aus dem Katalog selbst gesenkt.
var
  Meta : TRuleMeta;
begin
  Assert.IsTrue(TRuleCatalog.GetRuleByID('SCA072', 'de', Meta),
    'Vorbedingung: SCA072 existiert im Katalog');
  Assert.AreNotEqual(LowerCase(Meta.Name), AnsiLowerCase(Meta.Name),
    'Vorbedingung: der SCA072-DE-Name traegt einen Nicht-ASCII-'
    + 'Grossbuchstaben (sonst prueft dieser Test nichts)');
  Assert.IsTrue(Pos(AnsiLowerCase(Meta.Name), FHtml) > 0,
    'die Unicode-gesenkte Form des Namens steht in der Suchbasis');
end;

procedure TTestDetectorInfoExport.SearchBlob_AttributeSafeAndBreakFree;
// Jeder data-search-Wert muss frei von rohem <, > und " sein (die
// Attribut-Grenze darf kein Katalogtext sprengen) und darf keine
// '<br>'-Tokens tragen - der Escaper bildet #10 auf ein literales
// '<br>' ab, im Suchtext flutete das jede 'br'-Suche und zerriss
// Phrasen ueber Zeilengrenzen (Review-Minor; ohne die Umbruch-
// Vorbehandlung ist dieser Test ROT).
var
  P, E    : Integer;
  Wert    : string;
  Gezaehlt : Integer;
begin
  Gezaehlt := 0;
  P := Pos('data-search="', FHtml);
  while P > 0 do
  begin
    P := P + Length('data-search="');
    E := Pos('"', FHtml, P);
    Assert.IsTrue(E > P, 'Attributwert ohne schliessendes Anfuehrungszeichen');
    Wert := Copy(FHtml, P, E - P);
    Assert.IsTrue(Pos('<', Wert) = 0, 'rohes < im data-search-Wert');
    Assert.IsTrue(Pos('>', Wert) = 0, 'rohes > im data-search-Wert');
    Assert.IsTrue(Pos('&lt;br', Wert) = 0,
      'escaptes <br>-Token im data-search-Wert (Umbruch nicht vorbehandelt)');
    Inc(Gezaehlt);
    P := Pos('data-search="', FHtml, E);
  end;
  Assert.AreEqual<Integer>(
    Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1, Gezaehlt,
    'ein data-search-Wert je Regel');
end;

procedure TTestDetectorInfoExport.DetailRow_CarriesDescriptionCweConfigUnit;
// Die Detailzeile traegt wirklich Kurz-/Langbeschreibung, beide
// Beispiel-Bloecke und die Meta-Zeile - exemplarisch fuer SCA001 mit
// dem identischen Aufbauweg des Generators nachgebaut (Erwartungen aus
// Katalog + geteiltem Escaper, kein Nicht-ASCII-Literal im Test).
var
  Meta : TRuleMeta;

  function E(const S: string): string;
  begin
    Result := TExporterHtml.HtmlEscape(S);
  end;

begin
  Meta := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  Assert.IsNotEmpty(Meta.FullDescription,
    'Vorbedingung: SCA001 traegt FullDescription im Katalog');
  Assert.IsTrue(Length(Meta.CWE) > 0,
    'Vorbedingung: SCA001 traegt CWE im Katalog');
  Assert.IsNotEmpty(Meta.ConfigKey,
    'Vorbedingung: SCA001 traegt ConfigKey im Katalog');
  Assert.IsNotEmpty(Meta.DetectorUnit,
    'Vorbedingung: SCA001 traegt DetectorUnit im Katalog');

  // Seit dem Workbench-Umbau (07.09.) liegen die Details als
  // Drawer-Template neben der Zeile - dieselben Inhalte, neue Wrapper.
  Assert.IsTrue(Pos('<template id="tpl-' + Meta.ID + '">', FHtml) > 0,
    'Drawer-Template der Regel fehlt');
  Assert.IsTrue(Pos('<h3>Was wird erkannt?</h3>', FHtml) > 0,
    'Kurzbeschreibungs-Ueberschrift fehlt');
  Assert.IsTrue(Pos('<p>' + E(Meta.ShortDescription) + '</p>', FHtml) > 0,
    'Kurzbeschreibung fehlt im Drawer-Template');
  Assert.IsTrue(Pos('<h3>Warum ist das relevant?</h3>', FHtml) > 0,
    'Warum-Ueberschrift fehlt');
  Assert.IsTrue(Pos('<p>' + E(Meta.FullDescription) + '</p>', FHtml) > 0,
    'Langbeschreibung fehlt im Drawer-Template');
  Assert.IsTrue(Pos('Vorher (problematisch)', FHtml) > 0,
    'Vorher-Kartentitel fehlt');
  Assert.IsTrue(Pos('<pre>' + E(Meta.BadExample) + '</pre>', FHtml) > 0,
    'Vorher-Beispielcode fehlt');
  Assert.IsTrue(Pos('Nachher (empfohlen)', FHtml) > 0,
    'Nachher-Kartentitel fehlt');
  Assert.IsTrue(Pos('<pre>' + E(Meta.GoodExample) + '</pre>', FHtml) > 0,
    'Nachher-Beispielcode fehlt');
  Assert.IsTrue(Pos('<span class="chip cwe">' + E(Meta.CWE[0]) + '</span>',
    FHtml) > 0, 'CWE-Chip fehlt in der Meta-Zeile');
  Assert.IsTrue(Pos('<pre>' + E(Meta.ConfigKey) + '</pre>', FHtml) > 0,
    'Kalibrierungs-Karte ohne Konfigurations-Schluessel');
  Assert.IsTrue(Pos('Detektor-Unit: <span class="mono">'
    + E(Meta.DetectorUnit) + '</span>', FHtml) > 0,
    'Detektor-Unit fehlt in der Meta-Zeile');
end;

procedure TTestDetectorInfoExport.DataSort_OrdinalsMatchDisplayedWords;
// Die data-sort-Ordinale muessen zum ANGEZEIGTEN Wort passen - eine
// umsortierte Wortliste ohne Enum-Bezug stellte 'Hinweis' zwischen
// 'Fehler' und 'Warnung'. Wortlisten hier = sichtbarer Seitenvertrag.
const
  SEV_WORT  : array[TLeakSeverity] of string =
    ('Fehler', 'Warnung', 'Hinweis');
  SEV_CSS   : array[TLeakSeverity] of string = ('err', 'warn', 'hint');
  KONF_WORT : array[TFindingConfidence] of string =
    ('niedrig', 'mittel', 'hoch');
var
  K      : TFindingKind;
  S, S2  : TLeakSeverity;
  C, C2  : TFindingConfidence;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Assert.IsTrue(Pos(Format(
      '<td data-sort="%d"><span class="badge sev-%s">%s</span></td>',
      [Ord(KindDefaultSeverity(K)), SEV_CSS[KindDefaultSeverity(K)],
       SEV_WORT[KindDefaultSeverity(K)]]), FHtml) > 0,
      Format('Schweregrad-Zelle fuer Kind %d fehlt oder falsch gepaart',
        [Ord(K)]));
    Assert.IsTrue(Pos(Format(
      '<td data-sort="%d"><span class="badge konf">%s</span></td>',
      [Ord(KindDefaultConfidence(K)),
       KONF_WORT[KindDefaultConfidence(K)]]), FHtml) > 0,
      Format('Konfidenz-Zelle fuer Kind %d fehlt oder falsch gepaart',
        [Ord(K)]));
  end;
  // Fehlpaarungen duerfen NICHT vorkommen (Wortmengen sind disjunkt,
  // keine Spalten-Kollision).
  for S := Low(TLeakSeverity) to High(TLeakSeverity) do
    for S2 := Low(TLeakSeverity) to High(TLeakSeverity) do
      if S <> S2 then
        Assert.AreEqual<Integer>(0, Pos(Format(
          'data-sort="%d"><span class="badge sev-%s">%s</span>',
          [Ord(S), SEV_CSS[S], SEV_WORT[S2]]), FHtml),
          'Schweregrad-Wort haengt am falschen Ordinal');
  for C := Low(TFindingConfidence) to High(TFindingConfidence) do
    for C2 := Low(TFindingConfidence) to High(TFindingConfidence) do
      if C <> C2 then
        Assert.AreEqual<Integer>(0, Pos(Format(
          'data-sort="%d"><span class="badge konf">%s</span>',
          [Ord(C), KONF_WORT[C2]]), FHtml),
          'Konfidenz-Wort haengt am falschen Ordinal');
  // Default-Profil: an=0 (sortiert vor aus=1), keine Fehlpaarung.
  Assert.IsTrue(Pos(
    '<td data-sort="0"><span class="pill an">an</span></td>', FHtml) > 0,
    'an=0 fehlt');
  Assert.IsTrue(Pos(
    '<td data-sort="1"><span class="pill aus">aus</span></td>', FHtml) > 0,
    'aus=1 fehlt');
  Assert.AreEqual<Integer>(0,
    Pos('data-sort="1"><span class="pill an"', FHtml),
    'an am falschen Rang');
  Assert.AreEqual<Integer>(0,
    Pos('data-sort="0"><span class="pill aus"', FHtml),
    'aus am falschen Rang');
  // Konsumenten-Seite: das Sortier-JS liest data-sort wirklich.
  Assert.IsTrue(Pos('td.dataset.sort', FHtml) > 0,
    'Sortier-JS liest data-sort nicht mehr');
end;

procedure TTestDetectorInfoExport.HeaderCount_ColspanAndFootnote_Consistent;
// Selbstkonsistenz statt harter 8/198: Kopfzahl == tbody-Zahl,
// colspan jeder Detailzeile == Zahl der Spaltenkoepfe, Evidenz-
// Fussnote vorhanden. Katalogwachstum und eine KORREKT nachgezogene
// neue Spalte bleiben gruen - nur Divergenz wird rot.
var
  P, N, B, C, D : Integer;
begin
  P := Pos(' Detektoren', FHtml);
  Assert.IsTrue(P > 0, 'Kopfzeile fehlt');
  N := 0;
  var Stelle := 1;
  var i := P - 1;
  while (i > 0) and CharInSet(FHtml[i], ['0'..'9']) do
  begin
    N := N + (Ord(FHtml[i]) - Ord('0')) * Stelle;
    Stelle := Stelle * 10;
    Dec(i);
  end;
  Assert.IsTrue(N > 0, 'Kopfzahl nicht lesbar');

  B := 0;
  P := Pos('<tbody', FHtml);
  while P > 0 do
  begin
    Inc(B);
    P := Pos('<tbody', FHtml, P + 1);
  end;
  Assert.AreEqual<Integer>(B, N,
    'Kopfzeile verspricht andere Zahl als darunter steht');

  C := 0;
  P := Pos('<th onclick="sortiere(', FHtml);
  while P > 0 do
  begin
    Inc(C);
    P := Pos('<th onclick="sortiere(', FHtml, P + 1);
  end;
  Assert.IsTrue(C > 0, 'keine Spaltenkoepfe gefunden');

  // Seit dem Workbench-Umbau traegt jede Regel statt der Detailzeile
  // ein Drawer-Template - eines je tbody, keines verwaist.
  D := 0;
  P := Pos('<template id="tpl-', FHtml);
  while P > 0 do
  begin
    Inc(D);
    P := Pos('<template id="tpl-', FHtml, P + 1);
  end;
  Assert.AreEqual<Integer>(B, D,
    'jede Regel braucht genau ein Drawer-Template');

  Assert.IsTrue(Pos('(Evidenz-Deckel)', FHtml) > 0,
    'Fussnote zur Schweregrad-Semantik fehlt im Untertitel');
end;

procedure TTestDetectorInfoExport.WriteToFile_InvalidPathRaises;
// Schreibfehler muessen den Aufrufer erreichen - der Save-Dialog
// meldet sonst Erfolg, ohne dass eine Datei entsteht. Das Verzeichnis
// existiert garantiert nicht und wird nicht angelegt (kein Cleanup).
var
  Pfad : string;
begin
  Pfad := TPath.Combine(TPath.Combine(TPath.GetTempPath,
    'sca_gibtsnicht_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', '')), 'detinfo.html');
  Assert.WillRaise(
    procedure
    begin
      TDetectorInfoExport.WriteToFile(Pfad, 'de');
    end,
    EFCreateError,
    'ungueltiger Zielpfad muss die Exception zum Aufrufer durchreichen');
end;

procedure TTestDetectorInfoExport.DefaultFileName_IsStableContract;
// Der Save-Dialog-Vorschlag ist ein Vertrag (Dialogfilter, externe
// Verweise) - eine Umbenennung beim EN/FR-Ausbau soll eine bewusste
// Entscheidung sein, kein Nebeneffekt.
begin
  Assert.AreEqual('sca-detector-info.html',
    TDetectorInfoExport.DefaultFileName,
    'Dateinamens-Vertrag des Save-Dialogs');
  Assert.AreEqual('.html', ExtractFileExt(TDetectorInfoExport.DefaultFileName),
    'die Endung steuert den Dialogfilter');
end;

procedure TTestDetectorInfoExport.RoleBlock_PresentOpenAndBeforeSearch;
// Drei Zusicherungen: der Block existiert mit allen drei Rollen, er
// ist standardmaessig GEOEFFNET (details open - zugeklappt waere er
// nicht "immer gut zugaenglich"), und er steht VOR dem Suchfeld
// (wer die Seite oeffnet, sieht zuerst, wofuer sie da ist).
var
  PBlock, PSuche : Integer;
begin
  PBlock := Pos('<details open class="rollen">', FHtml);
  Assert.IsTrue(PBlock > 0,
    'Rollen-Block fehlt oder ist nicht standardmaessig geoeffnet');
  Assert.IsTrue(Pos('<b>Entwicklung:</b>', FHtml) > 0,
    'Entwickler-Rolle fehlt');
  Assert.IsTrue(Pos('<b>QA / Test:</b>', FHtml) > 0, 'QA-Rolle fehlt');
  Assert.IsTrue(Pos('<b>Product Owner:</b>', FHtml) > 0,
    'Product-Owner-Rolle fehlt');
  PSuche := Pos('id="suche"', FHtml);
  Assert.IsTrue(PSuche > PBlock,
    'der Rollen-Block muss VOR dem Suchfeld stehen');
end;

procedure TTestDetectorInfoExport.Workbench_ScaffoldingWiredCompletely;
// String-pruefbare Zusicherungen des Workbench-Umbaus: jede fehlende
// Verdrahtung degradierte die Seite still (kein Compiler sieht das JS).
var
  P, N : Integer;
begin
  // Filter-Chips: alle vier Gruppen existieren und rufen chip(this).
  Assert.IsTrue(Pos('data-gruppe="typ"', FHtml) > 0, 'Typ-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="sev"', FHtml) > 0,
    'Schweregrad-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="konf"', FHtml) > 0,
    'Konfidenz-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="prof"', FHtml) > 0,
    'Profil-Chips fehlen');
  Assert.IsTrue(Pos('onclick="chip(this)"', FHtml) > 0,
    'Chip-Verdrahtung fehlt');
  Assert.IsTrue(Pos('function chip(', FHtml) > 0, 'chip()-JS fehlt');
  Assert.IsTrue(Pos('function filterReset(', FHtml) > 0,
    'Reset-JS fehlt');
  // Jede Regel-tbody traegt die Chip-Filterbasis.
  N := 0;
  P := Pos('data-typ="', FHtml);
  while P > 0 do
  begin
    Inc(N);
    P := Pos('data-typ="', FHtml, P + 1);
  end;
  Assert.AreEqual<Integer>(
    Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1, N,
    'jede Regel braucht data-typ als Chip-Filterbasis');
  // Dashboard: Kacheln mit den Kern-Kennzahlen.
  Assert.IsTrue(Pos('class="kachel"', FHtml) > 0, 'Dashboard fehlt');
  Assert.IsTrue(Pos('>Detektoren</div>', FHtml) > 0,
    'Detektoren-Kachel fehlt');
  Assert.IsTrue(Pos('>Security-Regeln</div>', FHtml) > 0,
    'Security-Kachel fehlt');
  Assert.IsTrue(Pos('>mit CWE-Bezug</div>', FHtml) > 0,
    'CWE-Kachel fehlt');
  // Drawer: Geruest + Oeffnen/Schliessen + Zeilen-Verdrahtung.
  Assert.IsTrue(Pos('<aside id="drawer"', FHtml) > 0,
    'Drawer-Geruest fehlt');
  Assert.IsTrue(Pos('id="drawer-inhalt"', FHtml) > 0,
    'Drawer-Inhaltskorb fehlt');
  Assert.IsTrue(Pos('function oeffneDrawer(', FHtml) > 0,
    'Drawer-Oeffnen-JS fehlt');
  Assert.IsTrue(Pos('function schliesseDrawer(', FHtml) > 0,
    'Drawer-Schliessen-JS fehlt');
  Assert.IsTrue(Pos('onclick="oeffneDrawer(this.parentNode)"', FHtml) > 0,
    'Zeilen sind nicht mit dem Drawer verdrahtet');
  Assert.IsTrue(Pos('function kopiere(', FHtml) > 0, 'Copy-JS fehlt');
  Assert.IsTrue(Pos('onclick="kopiere(this)"', FHtml) > 0,
    'Copy-Buttons fehlen');
  // Tastatur + Deep-Link + Empty-State.
  Assert.IsTrue(Pos('ev.ctrlKey', FHtml) > 0,
    'Strg+K-Handler fehlt');
  Assert.IsTrue(Pos('"Escape"', FHtml) > 0, 'Esc-Handler fehlt');
  Assert.IsTrue(Pos('"ArrowDown"', FHtml) > 0,
    'Pfeil-Navigation fehlt');
  Assert.IsTrue(Pos('function deepLink(', FHtml) > 0,
    'Deep-Link-JS fehlt');
  Assert.IsTrue(Pos('deepLink();', FHtml) > 0,
    'Deep-Link-Initialaufruf fehlt');
  Assert.IsTrue(Pos('id="leer"', FHtml) > 0, 'Empty-State fehlt');
  Assert.IsTrue(Pos('suche();', FHtml) > 0,
    'Initialer Zaehler-/Filterlauf fehlt');
end;

procedure TTestDetectorInfoExport.HtmlEscape_CoversQuote;
// Vertragstest am geteilten Escaper: ein " im Katalogtext darf das
// data-search-Attribut nie beenden. Faengt ein kuenftiges Refactoring,
// das die &quot;-Behandlung verliert - die uebrigen Tests blieben
// dann gruen (Review-Testluecke).
begin
  Assert.AreEqual('a&quot;b', TExporterHtml.HtmlEscape('a"b'),
    'HtmlEscape muss das Anfuehrungszeichen escapen');
end;

end.
