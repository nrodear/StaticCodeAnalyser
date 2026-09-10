unit uFindingsWorkbenchExport;

// Funde-Export VARIANTE 2 (Nutzerauftrag 07.09.): der Scan-Bericht auf
// der ARCHITEKTUR der Detektor-Info-Seite (uDetectorInfoExport) - die
// bestehende V1 (uExportHtml) bleibt unveraendert daneben bestehen.
// Konzept: Konzept_FundeExportV2_2026-09-07.md (lokal).
//
// KERNIDEE gegenueber V1: ein <tbody> je FUND (Filter/Sortierung ohne
// Zeilen-Paar-Logik) und die Regel-Doku DEDUPLIZIERT - je vorkommender
// Regel EIN <template id="tpl-SCAxxx"> mit dem Katalog-Drawer-Inhalt
// (Was wird erkannt? / Warum relevant? / kanonische Codekarten /
// noinspection / Kalibrierung / CWE+Tags+Unit). Der Drawer zeigt oben
// die konkrete Fundstelle ("Dieser Fund": Pfad:Zeile, Methode, Detail,
// optionaler FixHint-Text aus data-hinweis) und darunter den
// Template-Klon. V1 wiederholt dieselbe Regel-Doku je Fund - bei 500
// gleichen Funden 500 Kopien; V2 traegt sie einmal.
//
// SPRACHE: deutsch-sprachfix wie die Katalogseite (BEWUSST kein _();
// EN/FR laut Backlog zusammen mit der Katalogseite). EIN Theme
// (Workbench hell) - keine dark/sepia-Ableitungsmechanik.
//
// BEWUSST NICHT im Start (Ausbauliste im Konzept): Quell-Snippet je
// Fund (braucht den SourceCache der V1), variantengenaue Vorher/
// Nachher je Fund (der Start zeigt die kanonischen Regel-Beispiele),
// Baseline/QuickFix/Charts/Health/i18n/Themes. KEIN Zeitstempel im
// Kopf: die Seite ist dadurch ohne Pinning byte-stabil - mit EINER
// dokumentierten Ausnahme: der fundspezifische data-hinweis kommt aus
// dem _()-lokalisierten FixHint und folgt damit der App-Sprache
// (byte-stabil je Sprachzustand; sprachfix ginge nur ueber einen
// FixHint-API-Umbau, Review 07.09.).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TFindingsWorkbenchExport = class
  public
    // Baut die komplette Seite. ABaseDir steuert nur die ANZEIGE der
    // Pfade (relativ zur Wurzel, sonst Basisname - Vertrag wie V1).
    // AMaxRows: -1 = Voreinstellung (20.000 wie V1), 0 = unbegrenzt;
    // bei Kuerzung sagt es ein Banner ueber der Tabelle, die
    // Dashboard-Kacheln zaehlen IMMER alle Funde.
    // ALang ('de'/'en'/'fr', sonst en): Sprache der GANZEN Seite -
    // Oberflaechentexte aus TWorkbenchI18n, Regeltexte aus
    // GetRule(K, ALang). Default 'de' haelt Bestandsaufrufer stabil.
    class function BuildHtml(AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string; AMaxRows: Integer = -1;
      const ALang: string = 'de'): string; static;
    // Schreibt BuildHtml als UTF-8 mit BOM (Konvention aller Exporte).
    class procedure Run(AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AFileName: string; AMaxRows: Integer = -1;
      const ALang: string = 'de'); static;
    // Vorschlag fuer den Save-Dialog.
    class function DefaultFileName: string; static;

  private
    // Gemeinsamer Seitenbau fuer BuildHtml (Tests) und Run (Datei):
    // Run schreibt direkt aus dem Builder (SaveBuilderUtf8WithBom) -
    // der TStringList-Umweg der ersten Fassung hielt den Bericht
    // dreifach im Speicher (V1-OOM-Lehre; Chargen-Review 07.09.).
    class procedure BauePage(ASB: TStringBuilder;
      AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string; AMaxRows: Integer;
      const ALang: string); static;
  end;

implementation

// noinspection-file DuplicateString, StringConcatInLoop, LargeClass, LongMethod
// Ein HTML-Generator wiederholt Tags bauartbedingt; die Markup-Bloecke
// (CSS, JS, Templates) sind zusammenhaengend - dieselbe begruendete
// Lage wie in uDetectorInfoExport und uExportHtml. StringConcatInLoop:
// JoinArr/ChipListe verketten Tag-/CWE-Listen mit einer Handvoll
// Elementen, kein Hot-Path (die Fund-Schleife selbst appendet in den
// TStringBuilder).

uses
  System.Generics.Defaults,   // TComparer fuer die Dropdown-Listen
  uExportHtml,     // TExporterHtml.HtmlEscape - keine dritte Escape-Kopie
  uExport,         // TExporter.SaveUtf8WithBom - EIN Ort fuer die BOM-Politik
  uFixHint,        // TFixHintResolver.FixHint - fundspezifischer Hinweistext
  uRuleCatalog,
  uWorkbenchStyle, // geteilter CSS-Kern der Workbench-Seiten
  uWorkbenchI18n;  // geteilte Oberflaechentexte de/en/fr (07.09.)

const
  SEV_CSS : array[TLeakSeverity] of string = ('err', 'warn', 'hint');
  // Die Anzeige-Woerter kommen seit dem EN/FR-Nachtrag (07.09.) aus
  // der geteilten Sprachtabelle - die frueheren deutschen Konstanten
  // waren die zweite Kopie neben uDetectorInfoExport, jetzt ist es
  // eine Quelle fuer beide Seiten.
  SEV_KEY  : array[TLeakSeverity] of TWbText =
    (wtSevFehler, wtSevWarnung, wtSevHinweis);
  CONF_KEY : array[TFindingConfidence] of TWbText =
    (wtKonfNiedrig, wtKonfMittel, wtKonfHoch);
  // Zeilenbudget wie V1 (dort HTML_MAX_ROWS_DEFAULT, proc-lokal):
  // 20.000 Zeilen sind gross, aber von Browsern beherrschbar.
  V2_MAX_ROWS_DEFAULT = 20000;
  // Sortierrang der Lesefehler-Zeilen (hinter lsHint = 2, wie V1).
  SEV_RANG_LESEFEHLER = 3;
  // Spaltenindizes der Hauptzeile (tr.haupt). Sie sind ein DREIFACHER
  // Vertrag: thead-Reihenfolge, sortiere(n) im JS und fundKopf(), das
  // die Zellen fuer den Drawer-Kopf liest. Darum benannt statt
  // gestreut - eine neue Spalte fasst hier UND an den drei Stellen an.
  SP_ZEILE    = 0;
  SP_METHODE  = 1;   // + Datei darunter
  SP_SCAID    = 2;
  SP_REGEL    = 3;   // + Detailtext darunter
  SP_TYP      = 4;
  SP_SEVERITY = 5;
  SP_KONFIDENZ = 6;
  // Die Spaltenbreiten der V3-Seite, uebernommen auf Nicos Auftrag
  // 09.09. V2 hatte GAR KEINE - die Browser-Automatik verteilte nach
  // Inhalt, und damit wanderten die Spalten von Bericht zu Bericht.
  // Die beiden Textspalten (Methode+Datei, Regel+Detail) bekommen
  // KEINE Breite: bei table-layout:fixed teilen sie sich, was die
  // festen uebrig lassen - das ist das Tabellen-Gegenstueck zu 1fr.
  SP_BREITE_ZEILE  = '64px';
  SP_BREITE_SCAID  = '92px';
  SP_BREITE_TYP    = '132px';
  SP_BREITE_SEV    = '104px';
  SP_BREITE_KONF   = '96px';
  // Zeilen vor und nach der Fundzeile im Quell-Ausschnitt (wie V1).
  SNIPPET_KONTEXT = 3;

type
  // Alles, was eine Fundzeile braucht - EIN Parameter statt sechs
  // (Selbstscan SCA013; dasselbe Muster wie TRegelDaten auf der
  // Katalogseite).
  TFundZeile = record
    Fund    : TLeakFinding;
    Meta    : TRuleMeta;
    Pfad    : string;      // Anzeigepfad = Filterwert des Dropdowns
    Hinweis : string;      // fundspezifischer FixHint-Text
    Snippet : string;      // Quell-Ausschnitt als ROHTEXT, #10-getrennt
    // Nummer der ersten Zeile des Ausschnitts. Gehoert zum Snippet: ohne
    // sie kann die Anzeige die Zeilennummern nicht beschriften, weil der
    // Rohtext keine mehr traegt.
    SnippetVon : Integer;
    Lang    : string;
  end;

  // Ein Eintrag der Auswahllisten (Datei- und Regel-Dropdown).
  TZaehlEintrag = record
    Wert    : string;    // Filterwert: Anzeigepfad bzw. SCA-ID
    Anzeige : string;    // Beschriftung inkl. Fundzahl (Dropdown)
    // Beschriftung OHNE Fundzahl - fuer die Top-Listen, die die Zahl
    // in einer eigenen Spalte fuehren. Bei Regeln ist das "SCA176
    // CognitiveComplexity", bei Dateien der Pfad. Vorher zeigten die
    // Top-Listen den WERT, und bei Regeln ist das die nackte ID -
    // "SCA176" allein sagt niemandem, worum es geht (Nico 09.09.).
    Titel   : string;
    Anzahl  : Integer;
  end;

  // Kennzahlen der Dashboard-Kacheln - ein Zaehlpass ueber ALLE Funde
  // (unabhaengig vom Zeilenbudget der Tabelle).
  TFundStat = record
    Gesamt     : Integer;
    Sev        : array[TLeakSeverity] of Integer;
    Lesefehler : Integer;
    Security   : Integer;  // Funde von Vulnerability-/Hotspot-Regeln
    Dateien    : Integer;  // verschiedene Dateien
    Regeln     : Integer;  // verschiedene Regeln (Kinds)
    // Auswahllisten fuer die Dropdowns (Feature-Abgleich 07.09.):
    // Dateien alphabetisch, Regeln nach Fundzahl absteigend - die
    // lauteste Regel zuerst ist der haeufigste Einstieg.
    DateiListe : TArray<TZaehlEintrag>;
    RegelListe : TArray<TZaehlEintrag>;
  end;

function TypText(T: TFindingType): string;
// Sonar-Typbegriffe bleiben englische Fachbegriffe (wie Katalogseite;
// zweite Kopie, s. Konstanten-Kommentar).
begin
  case T of
    ftBug             : Result := 'Bug';
    ftVulnerability   : Result := 'Vulnerability';
    ftSecurityHotspot : Result := 'Security Hotspot';
    ftCodeSmell       : Result := 'Code Smell';
    ftCodeDuplication : Result := 'Code Duplication';
    ftFileError       : Result := 'File Error';
  else
    Result := 'Code Smell';
  end;
end;

function TypCss(T: TFindingType): string;
begin
  case T of
    ftBug             : Result := 'bug';
    ftVulnerability   : Result := 'vuln';
    ftSecurityHotspot : Result := 'hotspot';
    ftCodeDuplication : Result := 'dup';
    ftFileError       : Result := 'ferr';
  else
    Result := 'smell';
  end;
end;

function JoinArr(const A: TArray<string>; const Sep: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + Sep;
    Result := Result + A[i];
  end;
end;

function H(const S: string): string;
begin
  Result := TExporterHtml.HtmlEscape(S);
end;

function HA(const S: string): string;
// Fuer MEHRZEILIGE Attributwerte (data-copy der Codekarten): H()
// bildete Umbrueche auf literales '<br>' ab - der Kopieren-Button
// lieferte damit '<br>'-Muell in die Zwischenablage (Chargen-Review
// 07.09., MAJOR). '&#10;' dekodiert der Parser im dataset zu echtem LF.
begin
  Result := TExporterHtml.HtmlAttrEscapeMultiline(S);
end;

function Einzeilig(const S: string): string;
// Umbrueche zu Leerzeichen, BEVOR HtmlEscape laeuft - der Escaper
// bildet #10 auf ein literales '<br>' ab (Elementinhalt-Vertrag);
// in ATTRIBUTEN (data-hinweis, Regel-Zusatz) waere das Datenmuell
// (genau der Fall aus dem Chargen-Review 06.09.).
begin
  Result := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function ChipListe(const A: TArray<string>; const ACss: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(A) do
    Result := Result + '<span class="chip ' + ACss + '">' + H(A[i])
      + '</span>';
end;

function QuellAusschnitt(ACache: TObjectDictionary<string, TStringList>;
  const ADatei: string; AZeile: Integer; out AErsteZeile: Integer): string;
// Quellcode-Ausschnitt um die Fundzeile, als ROHER TEXT: die Quellzeilen
// escaped und mit #10 verbunden, sonst nichts. AErsteZeile gibt die
// Nummer der ersten gelieferten Zeile zurueck - daraus zaehlt die
// Anzeige weiter.
//
// WARUM NICHT MEHR DAS FERTIGE MARKUP (Aenderung 09.09.)
// Bis hierher kam der Ausschnitt aus dem geteilten
// TExporterHtml.BuildCodeSnippet und lag als fertiges HTML in der
// Seite. Pro Zeile sind das rund 110 Zeichen Geruest - drei div, zwei
// span, Klassennamen, Nummernblock, Pfeil - um durchschnittlich vierzig
// Zeichen Code herum. Bei sieben Zeilen je Fund traegt der Bericht
// damit etwa 770 Byte Wiederholung PRO FUND. Das war der groesste
// einzelne Posten der Dateigroesse, groesser als die Fundzeile selbst.
//
// Das Geruest ist fuer jeden Ausschnitt identisch. Es steht deshalb
// jetzt EINMAL im Skript und wird beim Oeffnen des Drawers um den
// Rohtext gebaut - fuer genau den einen Ausschnitt, den der Leser
// gerade sehen will. Das Aussehen bleibt Zeichen fuer Zeichen dasselbe;
// die CSS-Klassen (.src-snippet, .src-line, .src-line-active,
// .src-line-num, .src-line-bar) sind unveraendert.
//
// Die Trennung von V1 ist damit gewollt: V1 bleibt bei fertigem Markup,
// weil ein V1-Bericht die Ausschnitte SICHTBAR nebeneinander zeigt und
// nicht einzeln auf Klick. Zwei Berichte, zwei Anzeigewege - aber
// dieselben Klassen und damit dasselbe Bild.
//
// Der Cache haelt jede Datei EINMAL: ein Bericht hat typisch viele
// Funde je Datei, und ohne Cache laese der Export dieselbe Datei
// dutzendfach. Nicht lesbare Dateien werden als nil gemerkt, damit
// ein fehlgeschlagener Zugriff nicht bei jedem Fund erneut versucht
// wird (Bericht ueber geloeschten Code ist der Normalfall).
var
  Lines            : TStringList;
  SB               : TStringBuilder;
  i, VonIdx, BisIdx: Integer;
begin
  Result      := '';
  AErsteZeile := 0;
  if (ADatei = '') or (AZeile <= 0) then Exit;
  if not ACache.TryGetValue(ADatei, Lines) then
  begin
    Lines := nil;
    if FileExists(ADatei) then
    begin
      Lines := TStringList.Create;
      try
        Lines.LoadFromFile(ADatei);
      except
        // NACKTES except mit Absicht und ohne on-Klausel: hier ist
        // JEDER Fehler dieselbe Aussage - "diese Datei liefert keinen
        // Ausschnitt" - egal ob Rechte, Sperre, Kodierung oder ein
        // Laufwerk, das zwischen FileExists und Laden verschwindet.
        // Ein 'on E: Exception' waere hier nur eine breitere Zusage
        // mit unbenutztem E; re-geworfen wird bewusst nichts, ein
        // fehlender Ausschnitt darf keinen Export scheitern lassen.
        FreeAndNil(Lines);
      end;
    end;
    ACache.AddOrSetValue(ADatei, Lines);
  end;
  if Lines = nil then Exit;
  // Fenster um die Fundzeile, an beiden Enden auf die Datei begrenzt.
  // Dieselbe Rechnung wie in BuildCodeSnippet - nur ohne das Markup.
  VonIdx := AZeile - 1 - SNIPPET_KONTEXT;
  BisIdx := AZeile - 1 + SNIPPET_KONTEXT;
  if VonIdx < 0 then VonIdx := 0;
  if BisIdx > Lines.Count - 1 then BisIdx := Lines.Count - 1;
  if VonIdx > BisIdx then Exit;
  SB := TStringBuilder.Create;
  try
    for i := VonIdx to BisIdx do
    begin
      if i > VonIdx then SB.Append(#10);
      // JEDE ZEILE EINZELN escapen, nie den fertigen Block: H() ist ein
      // ELEMENT-Vertrag und macht aus #10 ein <br>. Auf den ganzen Text
      // angewandt haette es die Zeilentrenner in Markup verwandelt -
      // genau die Falle, die am 07.09. beide Seiten getroffen hat.
      SB.Append(H(Lines[i]));
    end;
    Result      := SB.ToString;
    AErsteZeile := VonIdx + 1;
  finally
    SB.Free;
  end;
end;

function Kopf(ASpalte: Integer; AText: TWbText;
  const ALang: string): string;
// Ein sortierbarer Spaltenkopf; der Index ist der JS-Vertrag
// (sortiere(n) zaehlt die Zellen der Hauptzeile).
begin
  Result := Format('<th onclick="sortiere(%d)">%s'
    + '<span class="pfeil"></span></th>',
    [ASpalte, TWorkbenchI18n.T(AText, ALang)]);
end;

function AnzeigePfad(const AFileName, ABaseDir: string): string;
// VOLLER Anzeige-Pfad: relativ zur Wurzel via geteilter TExporter-
// Logik (Review 07.09.: keine dritte Prefix-Kopie), sonst der
// Fund-Pfad unveraendert. KEIN Basisname-Fallback mehr: seit dem
// Zwei-Zeilen-Layout (Nutzerauftrag 07.09.) steht der Dateiname
// ohnehin VOR dem Pfad in der Datei-Zeile.
begin
  Result := TExporter.RelativeDisplayPath(AFileName, ABaseDir);
end;

function DunkelRegeln(const ASel: string): string;
// Der KOMPLETTE Dunkel-Regelsatz unter einem frei waehlbaren
// Selektor: einmal fuer die ausdrueckliche Wahl
// (:root[data-theme="dark"]), einmal fuer die Systempraeferenz im
// @media-Block. EINE Quelle - zwei handgepflegte Kopien liefen im
// V1-Report schon auseinander (dort "Ableitungs-Invariante").
//
// FARBWAHL (Ueberarbeitung 07.09. auf Nutzerbefund): blaustichiges
// Grau statt neutralem Schwarzgrau, weil der Seitenkopf #20303f in
// JEDEM Theme bleibt und ein neutrales Grau daneben schmutzig wirkt.
// Entscheidend sind aber die FLAECHEN-Tokens: die Badges, Pills und
// Chips trugen ihre hellen Pastellfarben aus dem geteilten CSS-Kern
// und leuchteten auf dunklem Grund wie Textmarker. Regel fuer jede
// Farbfamilie: gedaempfter dunkler Grund, heller Text DERSELBEN
// Familie, Rand eine Stufe heller als der Grund - die Bedeutung
// (rot/gelb/blau/lila/gruen) bleibt lesbar, ohne zu blenden.
var
  SB : TStringBuilder;

  procedure Regel(const AInner, ADekl: string);
  begin
    if AInner = '' then
      SB.AppendLine(ASel + '{' + ADekl + '}')
    else
      SB.AppendLine(ASel + ' ' + AInner + '{' + ADekl + '}');
  end;

begin
  SB := TStringBuilder.Create;
  try
    Regel('', '--grund:#171b21;--karte:#1e242c;--tinte:#dde3ea;'
      + '--dezent:#94a1b0;--rand:#333c47;--akzent:#6aa9e9;'
      + '--f-err-bg:#3d201d;--f-err-fg:#f2a9a1;--f-err-br:#5e2f2a;'
      + '--f-warn-bg:#3b2f18;--f-warn-fg:#e8c07a;--f-warn-br:#5c4826;'
      + '--f-info-bg:#1b2c3d;--f-info-fg:#8fc1ee;--f-info-br:#2b4560;'
      + '--f-neutral-bg:#2a323b;--f-neutral-fg:#c2ccd7;'
      + '--f-lila-bg:#2e2440;--f-lila-fg:#c4a6ea;--f-lila-br:#463763;'
      + '--f-gut-bg:#1c3320;--f-gut-fg:#8fcf95;'
      + '--f-aus-bg:#3d201d;--f-aus-fg:#e8a49c;'
      + '--f-chip-bg:#2a323b;--f-flaeche:#232a33;'
      + '--f-code-bg:#12161b;--f-code-fg:#dbe1e8;');
    // Was KEIN Token hat: Tabellenkopf, Hover, Auswahl, Tastenkappen.
    // th braucht seit 09.09. KEINE eigene Dunkel-Regel mehr: die
    // Flaeche kommt aus --f-flaeche, und das dreht dieses Theme
    // ohnehin ein paar Zeilen weiter oben.
    // ACHTUNG Spezifitaet: der Hover liegt seit dem Zwei-Zeilen-Umbau
    // auf '#funde tbody:hover tr' (ID + 2 Elemente). Eine Dark-Regel
    // auf 'tr.haupt:hover' verliert dagegen und die Zeile bliebe im
    // dunklen Thema hellblau - beim Nachpruefen aufgefallen.
    Regel('#funde tbody:hover tr', 'background:#232c36;');
    Regel('.kbd', 'background:#2a323b;');
    Regel('#gekuerzt', 'background:var(--f-warn-bg);'
      + 'border-color:var(--f-warn-br);color:var(--f-warn-fg);');
    Regel('.topliste li:hover', 'background:#232c36;');
    Regel('.tl-bar', 'background:#2a323b;');
    Regel('.src-line-active', 'background:#3b2f18;');
    Regel('.src-line-num', 'color:#6e7b8a;');
    // Health-Ampel: die kraeftigen Textfarben des hellen Modus sind
    // auf dunklem Grund unlesbar - Rahmen bleiben satt, die Zahl
    // wird aufgehellt.
    Regel('.health-gruen', 'border-left-color:#3f8a4b;');
    Regel('.health-gruen .health-zahl', 'color:#8fcf95;');
    Regel('.health-gelb', 'border-left-color:#b8862b;');
    Regel('.health-gelb .health-zahl', 'color:#e8c07a;');
    Regel('.health-rot', 'border-left-color:#c0483a;');
    Regel('.health-rot .health-zahl', 'color:#f2a9a1;');
    Regel('.secpanel', 'border-left-color:#8a63c4;');
    // Inspector im Dunkeln: der Auswahl-Hintergrund der Zeile muss
    // sich vom Hover unterscheiden (drei Zustaende!), und der
    // Close-Button darf beim Ueberfahren nicht schwarz werden.
    // Diese Regel ist die EINZIGE Auswahlfarbe des Themas - eine
    // zweite ohne '#funde' waere durch die Spezifitaet tot und bei
    // der naechsten Farbarbeit eine Stolperfalle (Review 08.09.).
    Regel('#funde tbody.gewaehlt tr', 'background:#27323f;');
    Regel('#drawer-schliessen:hover',
      'background:#2f3945;color:var(--tinte);');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SeiteStyle: string;
// Workbench-Kern + Seitenspezifisches. Tabelle, Chips, Kacheln und
// Codekarten sind bewusst deckungsgleich mit der Katalogseite
// ("gleich anfuehlen"); der DRAWER weicht seit dem IDE-Focus-
// Redesign (08.09.) ab - er ist hier ein Inspector mit Hero und
// gestaffelten Ebenen, waehrend die Katalogseite ihren Regel-Drawer
// behaelt (dort gibt es keinen Fund, dessen Werte oben stuenden).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<style>');
    SB.Append(TWorkbenchStyle.BasisCss);
    // Angepinnter Kopf: CSS und JS sind ein PAAR - wer das eine
    // einbindet, bindet das andere (s. Deklarationen in
    // uWorkbenchStyle; der CLI-Report bekommt bewusst keins von
    // beiden).
    SB.Append(TWorkbenchStyle.KopfAngepinntCss);
    SB.AppendLine('main{padding:14px 20px;}');
    // ---- Command-Bar + Chips (Katalog-Zwilling) -----------------------
    SB.AppendLine('.cmdbar{display:flex;gap:10px;align-items:center;'
      + 'flex-wrap:wrap;margin:4px 0 8px 0;}');
    SB.AppendLine('#suche{flex:1 1 26em;max-width:44em;padding:9px 12px;'
      + 'font-size:1em;border:1px solid var(--rand);border-radius:8px;'
      + 'background:var(--karte);}');
    SB.AppendLine('#suche:focus-visible,button:focus-visible,'
      + 'tr.haupt:focus-visible{outline:2px solid '
      + 'var(--akzent);outline-offset:1px;}');
    SB.AppendLine('.kbd{border:1px solid var(--rand);border-bottom-width:'
      + '2px;border-radius:4px;padding:0 5px;background:#eef2f6;'
      + 'font-size:0.85em;}');
    SB.AppendLine('#zaehler{color:var(--dezent);font-size:0.92em;}');
    SB.AppendLine('.chips{display:flex;gap:6px;flex-wrap:wrap;'
      + 'align-items:center;margin:0 0 10px 0;}');
    SB.AppendLine('.chips .gruppe{color:var(--dezent);font-size:0.85em;'
      + 'margin-left:6px;}');
    SB.AppendLine('button.fchip{border:1px solid var(--rand);'
      + 'background:var(--karte);border-radius:999px;padding:3px 10px;'
      + 'font-size:0.88em;cursor:pointer;color:var(--tinte);}');
    SB.AppendLine('button.fchip[aria-pressed="true"]{background:'
      + 'var(--akzent);border-color:var(--akzent);color:#fff;}');
    SB.AppendLine('#reset{display:none;border:none;background:none;'
      + 'color:var(--akzent);cursor:pointer;font-size:0.88em;'
      + 'text-decoration:underline;}');
    SB.AppendLine('.cmdbar.auswahl{margin:0 0 10px 0;}');
    SB.AppendLine('.cmdbar select{max-width:32em;padding:5px 8px;'
      + 'border:1px solid var(--rand);border-radius:6px;'
      + 'background:var(--karte);color:var(--tinte);font-size:0.9em;}');
    // ---- Health / Security / Top-Listen (Feature-Abgleich 07.09.) -----
    SB.AppendLine('.panels{display:flex;gap:10px;flex-wrap:wrap;'
      + 'margin:0 0 12px 0;}');
    SB.AppendLine('.health,.secpanel{flex:1 1 300px;display:flex;'
      + 'gap:12px;align-items:center;background:var(--karte);'
      + 'border:1px solid var(--rand);border-radius:8px;'
      + 'padding:10px 14px;box-shadow:0 1px 2px rgba(16,32,48,0.06);}');
    SB.AppendLine('.health-zahl{font-size:1.7em;font-weight:700;}');
    SB.AppendLine('.health-txt{color:var(--dezent);font-size:0.86em;}');
    SB.AppendLine('.health-gruen{border-left:4px solid #1d6b2a;}');
    SB.AppendLine('.health-gruen .health-zahl{color:#1d6b2a;}');
    SB.AppendLine('.health-gelb{border-left:4px solid #8a5a00;}');
    SB.AppendLine('.health-gelb .health-zahl{color:#8a5a00;}');
    SB.AppendLine('.health-rot{border-left:4px solid #9c2317;}');
    SB.AppendLine('.health-rot .health-zahl{color:#9c2317;}');
    SB.AppendLine('.secpanel{border-left:4px solid #5b2d91;'
      + 'justify-content:space-between;}');
    SB.AppendLine('#btnSec{border:1px solid var(--rand);'
      + 'background:var(--karte);color:var(--tinte);border-radius:6px;'
      + 'cursor:pointer;font-size:0.86em;padding:4px 10px;'
      + 'white-space:nowrap;}');
    SB.AppendLine('.toplisten{display:flex;gap:10px;flex-wrap:wrap;'
      + 'margin:0 0 12px 0;}');
    SB.AppendLine('.topliste{flex:1 1 320px;background:var(--karte);'
      + 'border:1px solid var(--rand);border-radius:8px;'
      + 'padding:8px 12px;box-shadow:0 1px 2px rgba(16,32,48,0.06);}');
    SB.AppendLine('.topliste h2{font-size:0.98em;margin:4px 0 6px 0;}');
    SB.AppendLine('.topliste ul{list-style:none;margin:0;padding:0;}');
    SB.AppendLine('.topliste li{display:flex;align-items:center;gap:8px;'
      + 'padding:2px 0;cursor:pointer;font-size:0.86em;}');
    SB.AppendLine('.topliste li:hover{background:#f2f6fb;}');
    SB.AppendLine('.tl-name{flex:1 1 auto;overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;'
      + 'font-family:Consolas,monospace;}');
    SB.AppendLine('.tl-bar{flex:0 0 90px;height:8px;background:#eef2f6;'
      + 'border-radius:4px;overflow:hidden;}');
    SB.AppendLine('.tl-fill{display:block;height:100%;'
      + 'background:var(--akzent);}');
    SB.AppendLine('.tl-zahl{flex:0 0 3em;text-align:right;'
      + 'color:var(--dezent);font-variant-numeric:tabular-nums;}');
    // ---- Kuerzungsbanner ----------------------------------------------
    SB.AppendLine('#gekuerzt{background:#fef4e5;border:1px solid '
      + '#f1d9ad;border-radius:8px;padding:8px 12px;margin:0 0 10px 0;'
      + 'color:#8a5a00;}');
    // ---- Filterleiste: bleibt beim Scrollen erreichbar ---------------
    // Suche, Dropdowns und Chips stehen im Dokument direkt ueber der
    // Liste - beim Scrollen durch 20.000 Zeilen waeren sie sonst weg
    // (Nicos Wunsch 09.09.: "sollen auch oben sichtbar sein, unter dem
    // header").
    //
    // HIER ist var(--kopf-h) RICHTIG, anders als beim Spaltenkopf der
    // Tabelle: dieser Block liegt AUSSERHALB der .listwrap, sein
    // Scroll-Container ist also das Fenster, und der Seitenkopf klebt
    // davor. Die Variable haelt TWorkbenchStyle.KopfVerhaltenJs auf der
    // aktuellen Kopfhoehe - der Kopf schrumpft beim Scrollen, die
    // Filterleiste rueckt entsprechend nach.
    //
    // Der Hintergrund ist NICHT schmueckend: ohne ihn scrollt der
    // Listeninhalt sichtbar durch die angepinnte Leiste hindurch.
    // z-index 4 haelt sie unter dem Seitenkopf (5) und dem Drawer (10).
    // padding-bottom statt Abstand darunter: der Chip-Block ist das
    // letzte Kind und traegt margin-bottom:10px. Ein Kind-Aussenabstand
    // faellt aus dem Elternteil HERAUS, wenn dieses unten weder Polster
    // noch Rahmen hat - die zehn Pixel lagen also UNTER der bemalten
    // Flaeche und blieben durchsichtig. Genau dort sah man die Funde
    // durchlaufen (Nicos Befund 10.09.). Als Polster gehoeren sie zur
    // Leiste, werden mitbemalt und zaehlen in --filter-h.
    SB.AppendLine('#bereich-filter{position:sticky;'
      + 'top:var(--kopf-h,0px);z-index:4;background:var(--grund);'
      + 'padding-top:6px;padding-bottom:4px;}');
    // Und der Aussenabstand des Chip-Blocks entfaellt - er ist jetzt
    // das Polster der Leiste. Bliebe er stehen, waere der Abstand
    // doppelt so gross wie vorher.
    SB.AppendLine('#bereich-filter .chips{margin-bottom:0;}');
    // ---- Liste --------------------------------------------------------
    // EIN SCROLLER, UND DAS IST DIE SEITE (Nicos Befund 10.09.).
    //
    // Vorher hatte die Liste eine eigene Hoehe und ein eigenes
    // overflow:auto. Damit gab es ZWEI Scroller, und der Browser
    // bedient immer den unter dem Mauszeiger: wer ueber der Liste
    // scrollte, bewegte nur sie. Die Seite blieb stehen, also blieben
    // Ampel, Kacheln und Toplisten stehen, und Seitenkopf wie
    // Filterleiste rasteten nie ein - obwohl beide sticky sind.
    //
    // Nicos Vorgabe: solange die Kopfbereiche noch nicht angepinnt
    // sind, soll die ganze Seite nach oben scrollen. Das ist mit einem
    // zweiten Scroller nicht zu haben - er faengt das Rad vorher ab.
    // Ohne ihn ergibt sich die gewuenschte Reihenfolge von selbst:
    // erst scrollen die oberen Bereiche weg, dabei rasten Kopf,
    // Filterleiste und Spaltenzeile der Reihe nach ein, und danach
    // laeuft die Liste unter ihnen durch.
    //
    // KEIN overflow mehr - auch kein hidden. Schon overflow:hidden
    // macht das Element wieder zum Scroll-Container und wuerde die
    // Spaltenzeile erneut an die Box binden statt ans Fenster. Die
    // runden Ecken uebernehmen deshalb die aeusseren Kopfzellen (s.u.).
    SB.AppendLine('.listwrap{background:var(--karte);border:1px solid '
      + 'var(--rand);border-radius:8px;'
      + 'box-shadow:0 1px 2px rgba(16,32,48,0.06);}');
    // table-layout:fixed traegt die Spaltenbreiten (Nicos Auftrag
    // 09.09., Werte aus der V3-Seite). OHNE fixed verteilt der Browser
    // nach INHALT - dann wandern die Spalten von Bericht zu Bericht,
    // je nachdem wie lang der laengste Regelname gerade ist, und die
    // Ellipse greift nie, weil die Zelle einfach breiter wird.
    SB.AppendLine('table{border-collapse:collapse;width:100%;'
      + 'table-layout:fixed;}');
    // Die festen Spalten. Die beiden TEXT-Spalten (Methode+Datei,
    // Regel+Detail) bekommen bewusst keine Breite und teilen sich den
    // Rest - das Tabellen-Gegenstueck zu 1fr im Grid von V3.
    SB.AppendLine('th:nth-child(' + IntToStr(SP_ZEILE + 1)
      + '){width:' + SP_BREITE_ZEILE + ';}');
    SB.AppendLine('th:nth-child(' + IntToStr(SP_SCAID + 1)
      + '){width:' + SP_BREITE_SCAID + ';}');
    SB.AppendLine('th:nth-child(' + IntToStr(SP_TYP + 1)
      + '){width:' + SP_BREITE_TYP + ';}');
    SB.AppendLine('th:nth-child(' + IntToStr(SP_SEVERITY + 1)
      + '){width:' + SP_BREITE_SEV + ';}');
    SB.AppendLine('th:nth-child(' + IntToStr(SP_KONFIDENZ + 1)
      + '){width:' + SP_BREITE_KONF + ';}');
    SB.AppendLine('th,td{padding:7px 10px;text-align:left;'
      + 'vertical-align:top;font-size:0.92em;border:0;}');
    // DIE DRITTE KLEBE-EBENE. Seitenkopf (top:0), Filterleiste
    // (top:--kopf-h), Spaltenzeile (top:--kopf-h + --filter-h): jede
    // rastet unter der vorigen ein, in genau dieser Reihenfolge.
    //
    // Diese Zeile stand zwischendurch auf top:0, und das war damals
    // richtig: solange .listwrap ein eigenes overflow:auto trug, war
    // SIE der naechste Scroll-Container, und ein top von der Hoehe des
    // SEITEN-Kopfes rueckte die Zeile um genau diesen Betrag in die
    // Liste hinein statt unter den Kopf ("rutscht runter", 09.09.).
    //
    // Mit dem Wegfall des zweiten Scrollers (s. .listwrap) ist der
    // Bezug wieder das FENSTER - und damit ist der Kopfversatz nicht
    // nur erlaubt, sondern noetig. Wer hier wieder ein overflow an
    // .listwrap haengt, muss diese Zeile mit zurueckdrehen; die beiden
    // gehoeren zusammen.
    //
    // z-index 2 haelt die Zeile ueber den Datenzeilen, aber unter
    // Filterleiste (4) und Seitenkopf (5) - sonst schoebe sie sich
    // beim Einrasten vor die Leiste, unter der sie stehen soll.
    //
    // FLAECHE ALS TOKEN, nicht als Hexwert (Nicos Auftrag 09.09., aus
    // der V3-Seite uebernommen): der Kopf stand mit #eef2f6 fest und
    // brauchte je Theme eine eigene Ueberschreibung - eine im
    // Dunkel-Regelsatz, eine bei Sepia. Beide sind damit entfallen.
    // Drei Stellen fuer eine Flaeche waren zwei zu viel; genau das
    // Token-Prinzip, das uWorkbenchStyle im Kopf beschreibt.
    //
    // Schriftgroesse und Innenabstand kommen ebenfalls von V3 - dort
    // ist die Spaltenzeile kompakter als die Datenzeilen, was sie als
    // Kopf lesbar macht statt als weitere Zeile.
    SB.AppendLine('th{background:var(--f-flaeche);font-weight:600;'
      + 'font-size:12px;padding:8px 12px;'
      + 'cursor:pointer;position:sticky;z-index:2;'
      // MINUS EIN PIXEL - Absicht, kein Rechenfehler. Auch mit
      // gebrochen gemessenen Hoehen rastert der Browser jede
      // angepinnte Box fuer sich; zwischen zweien bleibt bei krummen
      // Zoomstufen gern eine Haarlinie stehen, und durch die sieht man
      // die Zeilen laufen. Die Ueberdeckung kostet nichts: die
      // Filterleiste liegt mit z-index 4 darueber und ist undurchsichtig,
      // verdeckt also diesen einen Pixel der Spaltenzeile.
      + 'top:calc(var(--kopf-h,0px) + var(--filter-h,0px) - 1px);'
      + 'white-space:nowrap;user-select:none;'
      + 'box-shadow:inset 0 -1px 0 var(--rand);}');
    // Die runden Ecken der Liste liegen auf den AEUSSEREN Kopfzellen,
    // weil .listwrap seit 10.09. nichts mehr abschneiden darf (ein
    // overflow wuerde sie zum Scroll-Container machen). Ohne das
    // stiesse die graue Kopfflaeche eckig in die runde Umrandung.
    SB.AppendLine('th:first-child{border-top-left-radius:8px;}');
    SB.AppendLine('th:last-child{border-top-right-radius:8px;}');
    SB.AppendLine('th .pfeil{color:var(--akzent);font-size:0.8em;'
      + 'margin-left:3px;}');
    SB.AppendLine('tr.haupt{border-top:1px solid var(--rand);'
      + 'cursor:pointer;}');
    // tr.datei ist am 09.09. entfallen - die Datei steht jetzt in der
    // Methoden-Zelle (V3-Formatierung). Die Regel stand hier fuer den
    // Zeiger auf der eigenen Dateizeile; die gibt es nicht mehr.
    // DREI unterscheidbare Zustaende (IDE-Focus-Redesign 08.09.):
    //   HOVER     - nur ein Hauch Flaeche, kein Rail
    //   FOCUS     - Tastatur: sichtbarer Ring, unabhaengig von Auswahl
    //   AUSWAHL   - 4px Rail in der SEVERITY-Farbe + ruhige Flaeche
    // Hover und Auswahl liegen auf dem TBODY, damit Haupt- und
    // Datei-Zeile eines Fundes als EIN Block wirken.
    SB.AppendLine('#funde tbody:hover tr{background:#f2f6fb;}');
    // Weiche Uebergaenge auf Hover, Chips und Top-Listen (UI-Konzept:
    // 150-200 ms). Bisher hatte nur der Inspector einen - alles
    // andere sprang hart um. NICHT auf border-left animieren: der
    // Auswahl-Rail soll SOFORT da sein (Akzeptanzkriterium "innerhalb
    // von ca. 100 ms eindeutig erkennbar").
    SB.AppendLine('#funde tbody tr{transition:background 150ms ease;}');
    SB.AppendLine('button.fchip{transition:background 150ms ease,'
      + 'border-color 150ms ease,color 150ms ease;}');
    SB.AppendLine('.topliste li{transition:background 150ms ease;}');
    SB.AppendLine('button.copy,#btnTheme,#btnSec{'
      + 'transition:background 150ms ease;}');
    // Reduzierte Bewegung: ALLE Uebergaenge aus, nicht nur der
    // Inspector (die engere Regel weiter unten bleibt als Doku).
    SB.AppendLine('@media (prefers-reduced-motion:reduce){'
      + '*{transition:none !important;}}');
    SB.AppendLine('#funde tbody.gewaehlt tr{background:#eaf1fa;}');
    // Der Rail sitzt als border-left an der Hauptzeile - anders als
    // ein box-shadow verschiebt er nichts und bleibt beim Scrollen
    // exakt an der Zeile. 4px statt 3px: er soll aus zwei Metern
    // Abstand erkennbar sein (Akzeptanzkriterium 1).
    // Der Rail laeuft ueber BEIDE Zeilen des Fund-Blocks (Haupt- und
    // Datei-Zeile) - nur an der Hauptzeile wirkte die Auswahl
    // zerrissen.
    SB.AppendLine('#funde tbody tr td:first-child{'
      + 'border-left:4px solid transparent;}');
    SB.AppendLine('#funde tbody.gewaehlt tr td:first-child{'
      + 'border-left-color:var(--akzent);}');
    // Die SEVERITY faerbt den Rail - so sagt die Auswahl zugleich,
    // WIE schwer der aktive Fund wiegt (Variante A: "Severity
    // unterstuetzt den Rail"). data-sev traegt den Rang am tbody.
    SB.AppendLine('#funde tbody.gewaehlt[data-sev="0"] tr '
      + 'td:first-child{border-left-color:var(--f-err-fg);}');
    SB.AppendLine('#funde tbody.gewaehlt[data-sev="1"] tr '
      + 'td:first-child{border-left-color:var(--f-warn-fg);}');
    SB.AppendLine('#funde tbody.gewaehlt[data-sev="2"] tr '
      + 'td:first-child{border-left-color:var(--f-info-fg);}');
    // Rang 3 = LESEFEHLER: eigene, neutrale Rail-Farbe. Ohne diese
    // Regel fiele er auf var(--akzent) zurueck - und das ist im
    // hellen Thema BYTE-GLEICH mit var(--f-info-fg), ein Lesefehler
    // saehe also aus wie ein Hinweis (Review 08.09.).
    SB.AppendLine('#funde tbody.gewaehlt[data-sev="3"] tr '
      + 'td:first-child{border-left-color:var(--dezent);}');
    // Auswahl hebt den REGELNAMEN an - nicht mehr, sonst springt die
    // Zeilenhoehe. Der Index kommt aus SP_REGEL statt als nackte Zahl:
    // der erste Wurf stand auf nth-child(5) und traf damit die TYP-
    // Zelle (Zellfolge: 1 Zeile, 2 Methode, 3 SCA-ID, 4 Regel, 5 Typ) -
    // sichtbar wurde nur ein halbfetter Typ-Badge, der Titel des
    // Fundes blieb unveraendert (Chargen-Review 08.09., MAJOR).
    // td.id ist bewusst NICHT dabei: es traegt bereits font-weight:600.
    // Nur die REGEL-Zeile der Zelle, nicht die ganze Zelle: sonst
    // wuerde auch der Detailtext darunter fett - der ist bewusst
    // gedaempft.
    SB.AppendLine('#funde tbody.gewaehlt tr.haupt td:nth-child('
      + IntToStr(SP_REGEL + 1) + ') .zl-regel{font-weight:700;}');
    // Methode und Datei stehen seit 09.09. in EINER Zelle
    // uebereinander (V3-Formatierung). Beide Zeilen kuerzen mit
    // Ellipse statt umzubrechen - max-width:0 laesst die uebrigen
    // Zellen die Breite bestimmen (Tabellen-Ellipsis-Muster), das
    // title-Attribut zeigt den vollen Pfad.
    //
    // Die Klassen heissen NEUTRAL (zl- statt v2-/v3-), weil beide
    // Berichte denselben Style-Block teilen und dieselbe Zeile
    // zeichnen sollen.
    SB.AppendLine('tr.haupt>td:nth-child('
      + IntToStr(SP_METHODE + 1) + '),tr.haupt>td:nth-child('
      + IntToStr(SP_REGEL + 1) + '){max-width:0;}');
    SB.AppendLine('.zl-methode{overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;}');
    SB.AppendLine('.zl-datei{overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;'
      + 'font-family:Consolas,monospace;font-size:0.85em;'
      + 'color:var(--dezent);padding-top:2px;}');
    // Regel und Detailtext stehen seit 09.09. ebenfalls uebereinander
    // (Nicos Auftrag): beide sind oft lang und haben sich als
    // Nachbarspalten gegenseitig die Breite genommen. Beide kuerzen
    // mit Ellipse - der volle Text steht im Inspector.
    SB.AppendLine('.zl-regel{overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;font-weight:600;}');
    SB.AppendLine('.zl-detail{overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;'
      + 'font-size:0.85em;color:var(--dezent);padding-top:2px;}');
    SB.AppendLine('td.id{font-family:Consolas,monospace;font-weight:600;'
      + 'white-space:nowrap;}');
    SB.AppendLine('td.num{text-align:right;font-variant-numeric:'
      + 'tabular-nums;color:var(--dezent);}');
    // ---- Quell-Ausschnitt (Markup-Vertrag mit V1) ----------------------
    // Die Klassennamen sind zwischen V1 und V2 geteilt - hier nur die
    // Optik. WER sie setzt, ist seit 09.09. verschieden: V1 schreibt
    // sie beim Export (TExporterHtml.BuildCodeSnippet), V2 laesst sie
    // beim Oeffnen bauen (baueAusschnitt im Seitenskript). Das Bild ist
    // dasselbe; aendert sich hier eine Klasse, muessen BEIDE nach.
    SB.AppendLine('tr.snippet{display:none;}');
    SB.AppendLine('.src-snippet{background:#23272e;color:#e6e6e6;'
      + 'border-radius:6px;padding:6px 0;margin:8px 0;overflow-x:auto;'
      + 'font-family:Consolas,monospace;font-size:0.84em;}');
    SB.AppendLine('.src-line{white-space:pre;padding:0 8px;}');
    SB.AppendLine('.src-line-active{background:#3a2f1c;}');
    SB.AppendLine('.src-line-num{color:#7d8794;user-select:none;}');
    SB.AppendLine('.src-line-bar{color:#e8b339;}');
    // ---- Empty-State --------------------------------------------------
    SB.AppendLine('#leer{display:none;padding:26px;text-align:center;'
      + 'color:var(--dezent);}');
    // ---- Drawer (Katalog-Zwilling) ------------------------------------
    // Inspector statt Web-Drawer: 41 % Breite (Zielband 38-44 %),
    // kein Schlagschatten mehr, sondern eine feste Kante zur Tabelle
    // wie ein angedocktes IDE-Panel.
    SB.AppendLine('#drawer{position:fixed;top:0;right:0;height:100%;'
      + 'width:41%;min-width:340px;max-width:46em;background:'
      + 'var(--karte);border-left:1px solid var(--rand);'
      + 'box-shadow:-1px 0 0 var(--rand),-12px 0 24px '
      + 'rgba(16,32,48,0.10);'
      + 'transform:translateX(102%);transition:transform 200ms '
      + 'cubic-bezier(0.22,0.61,0.36,1);'
      + 'overflow-y:auto;padding:16px 20px 24px 20px;z-index:10;}');
    // Wer Bewegung reduziert haben will, bekommt sie nicht.
    SB.AppendLine('@media (prefers-reduced-motion:reduce){'
      + '#drawer{transition:none;}}');
    SB.AppendLine('#drawer.offen{transform:translateX(0);}');
    SB.AppendLine('#drawer h3{margin:0 0 4px 0;font-size:0.92em;'
      + 'letter-spacing:0.02em;color:var(--dezent);'
      + 'text-transform:uppercase;}');
    // Die Karten-Ueberschriften tragen den Kopieren-BUTTON in sich -
    // ohne diese Ruecknahme staende dort 'KOPIEREN'/'KOPIERT',
    // waehrend dieselben Buttons in den Codekarten normal aussehen
    // (Review 08.09.). Auch die Farbe zuruecknehmen: ein Button in
    // Dezent-Grau liest sich wie deaktiviert.
    SB.AppendLine('#drawer h3 button.copy{text-transform:none;'
      + 'letter-spacing:normal;color:var(--tinte);}');
    // Close-Button: integriert statt dominant - kein Rahmen, erst
    // beim Ueberfahren eine Flaeche (TODO-Punkt B).
    SB.AppendLine('#drawer-schliessen{float:right;border:0;'
      + 'background:none;color:var(--dezent);border-radius:6px;'
      + 'cursor:pointer;font-size:1.15em;line-height:1;'
      + 'padding:4px 8px;margin:-4px -6px 0 0;}');
    SB.AppendLine('#drawer-schliessen:hover{background:var(--rand);'
      + 'color:var(--tinte);}');
    // ---- Inspector-Kopf (Aufbau der V3-Seite, 09.09.) ----------------
    // Badges - Ueberschrift - Fundort, alles auf einer Ebene. Der
    // frueher hier stehende Hero-Block mit eigener Kopfzeile, farbigem
    // Severity-Punkt und separater ID ist entfallen: der Punkt trug
    // die Severity ein zweites Mal, die direkt daneben als Badge
    // steht, und die Verschachtelung brachte nichts, was die flache
    // Folge nicht auch zeigt.
    SB.AppendLine('.insp-badges{display:flex;gap:6px;flex-wrap:wrap;}');
    SB.AppendLine('.insp-titel{font-size:1.14em;font-weight:600;'
      + 'line-height:1.25;margin:8px 0 0 0;}');
    // Der Fundort nutzt metarow (die Klasse gibt es weiter unten schon)
    // plus eine eigene Ergaenzung: monospace und harter Umbruch, weil
    // dort ein Dateipfad steht. Bewusst als ZUSATZ-Selektor statt als
    // zweite .metarow-Regel - zwei gleichnamige Regeln haetten sich je
    // nach Reihenfolge gegenseitig ueberschrieben.
    SB.AppendLine('#drawer-inhalt .metarow{font-family:Consolas,'
      + 'monospace;font-size:0.85em;word-break:break-all;}');
    // ---- Inspector: Abschnitte (Ebenen 4-8) ---------------------------
    // Gestaffelte Ebenen statt einer Textwueste: jede Section ein
    // eigener Block mit ruhiger Ueberschrift.
    SB.AppendLine('.insp-block{margin:16px 0 0 0;}');
    SB.AppendLine('.insp-block p{margin:0 0 6px 0;font-size:0.94em;}');
    // Der FIX ist die Handlung - er bekommt sichtbares Gewicht.
    SB.AppendLine('.insp-fix{margin-top:18px;padding-top:14px;'
      + 'border-top:2px solid var(--rand);}');
    // Suppression/Konfiguration sind sekundaer (TODO-Punkt D):
    // kleinere Schrift, gedaempft, aber vollstaendig.
    SB.AppendLine('.insp-sekundaer{margin-top:16px;opacity:0.92;}');
    SB.AppendLine('.insp-sekundaer .karte{font-size:0.9em;}');
    SB.AppendLine('.metarow{margin-top:12px;color:var(--dezent);'
      + 'font-size:0.88em;}');
    // ---- Themes (Feature-Abgleich 07.09.) ------------------------------
    // Seit dem Workbench-Umbau haengt fast alles an sechs Tokens -
    // ein Theme ist deshalb genau EIN Ueberschreibungsblock und keine
    // Parallelwelt. Der dunkle Kopf (header.kopf) bleibt in allen
    // Themes dunkel, das ist die Marke der Seite. Ohne data-theme
    // greift die Systempraeferenz (@media), mit Attribut gewinnt die
    // Wahl des Nutzers - beide Richtungen ausgeschrieben, damit der
    // Umschalter in JEDE Richtung sticht.
    SB.Append(DunkelRegeln(':root[data-theme="dark"]'));
    // SEPIA bleibt ein HELLES Thema - die Badge-Farben muessen also
    // nicht gedreht, nur waermer gestimmt werden, damit sie nicht
    // kalt aus dem beigen Grund stechen. Der Code-Block bleibt dunkel
    // (Lesbarkeit von Quelltext), nur eine Spur waermer.
    SB.AppendLine(':root[data-theme="sepia"]{--grund:#f4ead2;'
      + '--karte:#faf3e0;--tinte:#3d2e1a;--dezent:#7a6648;'
      + '--rand:#d9c9a8;--akzent:#7a4a1f;'
      + '--f-err-bg:#f7ded6;--f-err-fg:#8c2f1f;--f-err-br:#e0bcae;'
      + '--f-warn-bg:#f7ecd0;--f-warn-fg:#7a5410;--f-warn-br:#ddc79a;'
      + '--f-info-bg:#e8e6d8;--f-info-fg:#4a5a6b;--f-info-br:#c9c6b4;'
      + '--f-neutral-bg:#efe6d0;--f-neutral-fg:#5a4a33;'
      + '--f-lila-bg:#eee2e6;--f-lila-fg:#6b3a5e;--f-lila-br:#d5c2c8;'
      + '--f-gut-bg:#e5edd6;--f-gut-fg:#3f6124;'
      + '--f-aus-bg:#f2e2da;--f-aus-fg:#8a4126;'
      + '--f-chip-bg:#efe6d0;--f-flaeche:#f7efdc;'
      + '--f-code-bg:#2b2419;--f-code-fg:#e8dfc9;}');
    // s. Dunkel-Regelsatz: die Kopf-Flaeche haengt am Token, eine
    // eigene Sepia-Regel dafuer ist entfallen.
    // dieselbe Spezifitaets-Falle wie im Dunkel-Thema (s. dort).
    SB.AppendLine(':root[data-theme="sepia"] #funde tbody:hover tr{'
      + 'background:#f0e4c8;}');
    SB.AppendLine(':root[data-theme="sepia"] .kbd{background:#efe3c6;}');
    SB.AppendLine(':root[data-theme="sepia"] .tl-bar{'
      + 'background:#e8dcc0;}');
    SB.AppendLine(':root[data-theme="sepia"] .topliste li:hover{'
      + 'background:#f0e4c8;}');
    SB.AppendLine(':root[data-theme="sepia"] #funde tbody.gewaehlt tr{'
      + 'background:#ecdfbd;}');
    SB.AppendLine(':root[data-theme="sepia"] #drawer-schliessen:hover{'
      + 'background:#e6d8b6;color:var(--tinte);}');
    // Systempraeferenz: DERSELBE Regelsatz, nur unter einem anderen
    // Selektor. Er wird aus derselben Quelle erzeugt (DunkelRegeln) -
    // zwei handgepflegte Kopien waeren mit der naechsten Farbaenderung
    // auseinandergelaufen, und genau diese Divergenz-Gefahr ist im
    // V1-Report als "Ableitungs-Invariante" dokumentiert.
    SB.AppendLine('@media (prefers-color-scheme:dark){');
    SB.Append(DunkelRegeln(':root:not([data-theme="light"])'
      + ':not([data-theme="sepia"])'));
    SB.AppendLine('}');
    SB.AppendLine('#btnTheme{border:1px solid var(--rand);'
      + 'background:var(--karte);color:var(--tinte);border-radius:6px;'
      + 'cursor:pointer;font-size:0.86em;padding:3px 10px;}');
    // ---- Responsive ---------------------------------------------------
    SB.AppendLine('@media (max-width:900px){');
    SB.AppendLine('#drawer{width:100%;min-width:0;max-width:none;}');
    SB.AppendLine('}');
    SB.AppendLine('</style>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function Auswahlliste(const AId, AAlleText: string;
  const AEintraege: TArray<TZaehlEintrag>): string;
// Ein Dropdown mit "alle"-Eintrag. Leere Liste -> gar kein Markup:
// ein Filter ueber genau eine Moeglichkeit ist nur Platzverbrauch.
var
  SB : TStringBuilder;
  E  : TZaehlEintrag;
begin
  if Length(AEintraege) < 2 then Exit('');
  SB := TStringBuilder.Create;
  try
    SB.Append('<select id="' + AId + '" onchange="suche()">');
    SB.Append('<option value="">' + AAlleText + '</option>');
    for E in AEintraege do
      SB.Append('<option value="' + H(E.Wert) + '">'
        + H(E.Anzeige) + '</option>');
    SB.Append('</select>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CommandUndChips(ALesefehler: Integer;
  const AStat: TFundStat; const ALang: string): string;
// Search-Command-Bar + Filter-Chips (Typ/Schweregrad/Konfidenz).
// KEINE Profil-Chips: der Bericht zeigt einen GELAUFENEN Scan, das
// Profil ist bereits angewendet. Lesefehler bekommen ihren eigenen
// Typ-Chip (nur wenn welche da sind, wie die Kachel) - sonst waeren
// sie bei aktivem Typ-Filter unerreichbar (Review 07.09.). BEWUSST
// kein Schweregrad-Chip fuer sie: ein aktiver Schweregrad-Filter
// blendet Lesefehler aus, wie sie auch in keine Severity-Kachel
// zaehlen (V1-Politik).
var
  SB : TStringBuilder;
  S  : TLeakSeverity;
  C  : TFindingConfidence;
begin
  SB := TStringBuilder.Create;
  try
    // Gemeinsame Huelle um Suche, Dropdowns und Chips: sie
    // traegt das sticky, damit die Filter beim Scrollen durch
    // die Liste erreichbar bleiben (Nicos Wunsch 09.09.).
    // Einzeln angepinnt wuerden sich die drei ueberlagern -
    // sie klebten alle am selben top.
    SB.AppendLine('<div id="bereich-filter">');
    SB.AppendLine('<div class="cmdbar" id="bereich-suche">');
    SB.AppendLine('<input id="suche" type="search" '
      + 'aria-label="' + TWorkbenchI18n.T(wtSucheAria, ALang) + '" '
      + 'placeholder="'
      + TWorkbenchI18n.T(wtSuchePlatzhalterFunde, ALang)
      + '" oninput="suche()">');
    SB.AppendLine('<span><span class="kbd">'
      + TWorkbenchI18n.T(wtStrgTaste, ALang)
      + '</span>+<span class="kbd">K</span></span>');
    SB.AppendLine('<span id="zaehler"></span>');
    SB.AppendLine('<button id="reset" onclick="filterReset()">'
      + TWorkbenchI18n.T(wtFilterReset, ALang) + '</button>');
    SB.AppendLine('<button id="btnTheme" type="button" title="'
      + TWorkbenchI18n.T(wtThemaWechseln, ALang) + '">'
      + TWorkbenchI18n.T(wtThema, ALang) + '</button>');
    SB.AppendLine('</div>');

    // Datei- und Regel-Auswahl (Feature-Abgleich 07.09.): der
    // schnellste Weg durch einen grossen Bericht - vorher ging das
    // nur ueber die Freitextsuche.
    SB.AppendLine('<div class="cmdbar auswahl" '
      + 'id="bereich-dropdowns">');
    SB.AppendLine(Auswahlliste('dateiFilter',
      Format(TWorkbenchI18n.T(wtAlleDateien, ALang), [AStat.Dateien]),
      AStat.DateiListe));
    SB.AppendLine(Auswahlliste('regelFilter',
      Format(TWorkbenchI18n.T(wtAlleRegeln, ALang), [AStat.Regeln]),
      AStat.RegelListe));
    SB.AppendLine('</div>');

    SB.AppendLine('<div class="chips" id="chips">');
    SB.AppendLine('<span class="gruppe">'
      + TWorkbenchI18n.T(wtGruppeTyp, ALang) + '</span>');
    SB.AppendLine('<button class="fchip" data-gruppe="typ" '
      + 'data-wert="bug" aria-pressed="false" onclick="chip(this)">'
      + 'Bug</button>');
    SB.AppendLine('<button class="fchip" data-gruppe="typ" '
      + 'data-wert="vuln" aria-pressed="false" onclick="chip(this)">'
      + 'Vulnerability</button>');
    SB.AppendLine('<button class="fchip" data-gruppe="typ" '
      + 'data-wert="hotspot" aria-pressed="false" onclick="chip(this)">'
      + 'Security Hotspot</button>');
    SB.AppendLine('<button class="fchip" data-gruppe="typ" '
      + 'data-wert="smell" aria-pressed="false" onclick="chip(this)">'
      + 'Code Smell</button>');
    SB.AppendLine('<button class="fchip" data-gruppe="typ" '
      + 'data-wert="dup" aria-pressed="false" onclick="chip(this)">'
      + 'Duplication</button>');
    if ALesefehler > 0 then
      SB.AppendLine('<button class="fchip" data-gruppe="typ" '
        + 'data-wert="ferr" aria-pressed="false" onclick="chip(this)">'
        + TWorkbenchI18n.T(wtChipLesefehler, ALang) + '</button>');
    SB.AppendLine('<span class="gruppe">'
      + TWorkbenchI18n.T(wtGruppeSchweregrad, ALang) + '</span>');
    for S := Low(TLeakSeverity) to High(TLeakSeverity) do
      SB.AppendLine(Format('<button class="fchip" data-gruppe="sev" '
        + 'data-wert="%d" aria-pressed="false" onclick="chip(this)">'
        + '%s</button>',
        [Ord(S), TWorkbenchI18n.T(SEV_KEY[S], ALang)]));
    SB.AppendLine('<span class="gruppe">'
      + TWorkbenchI18n.T(wtGruppeKonfidenz, ALang) + '</span>');
    for C := High(TFindingConfidence) downto Low(TFindingConfidence) do
      SB.AppendLine(Format('<button class="fchip" data-gruppe="konf" '
        + 'data-wert="%d" aria-pressed="false" onclick="chip(this)">'
        + '%s</button>',
        [Ord(C), TWorkbenchI18n.T(CONF_KEY[C], ALang)]));
    SB.AppendLine('</div>');
    SB.AppendLine('</div>');   // bereich-filter
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TopListe(const AId, ATitel, AZielDropdown: string;
  const AEintraege: TArray<TZaehlEintrag>): string;
// Top-10-Liste als klickbarer Filter (V1-Feature): ein Klick setzt
// das zugehoerige Dropdown und filtert. Verwertet die vorhandenen
// Auswahllisten - kein zweiter Zaehlpass. SORTIERT SELBST nach
// Fundzahl: die Datei-Liste kommt alphabetisch herein (so gehoert
// sie ins Dropdown), fuer eine TOP-Liste waere das falsch, und die
// Balkenbreite braucht ohnehin das Maximum an Position 0.
const
  TOP_N = 10;
var
  SB    : TStringBuilder;
  Liste : TArray<TZaehlEintrag>;
  i, n  : Integer;
  Max   : Integer;
  Breit : Integer;
begin
  if Length(AEintraege) < 2 then Exit('');
  Liste := Copy(AEintraege, 0, Length(AEintraege));
  TArray.Sort<TZaehlEintrag>(Liste, TComparer<TZaehlEintrag>.Construct(
    function(const A, B: TZaehlEintrag): Integer
    begin
      Result := B.Anzahl - A.Anzahl;
      if Result = 0 then Result := AnsiCompareText(A.Wert, B.Wert);
    end));
  n := Length(Liste);
  if n > TOP_N then n := TOP_N;
  Max := Liste[0].Anzahl;
  if Max < 1 then Max := 1;
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="topliste" id="' + AId + '">');
    SB.AppendLine('<h2>' + ATitel + '</h2><ul>');
    for i := 0 to n - 1 do
    begin
      Breit := Round(100 * Liste[i].Anzahl / Max);
      SB.AppendLine(Format('<li tabindex="0" role="button" '
        + 'data-ziel="%s" data-wert="%s" onclick="topKlick(this)">'
        + '<span class="tl-name" title="%s">%s</span>'
        + '<span class="tl-bar"><span class="tl-fill" '
        + 'style="width:%d%%"></span></span>'
        + '<span class="tl-zahl">%d</span></li>',
        [AZielDropdown, H(Liste[i].Wert),
         HA(Liste[i].Titel), H(Liste[i].Titel),
         Breit, Liste[i].Anzahl]));
    end;
    SB.AppendLine('</ul></div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function HealthUndSecurity(const AStat: TFundStat;
  const ALang: string): string;
// Health-Ampel und Security-Hinweis (V1-Features). Der Score ist
// derselbe wie in V1 (Err*100 + Warn*10 + Hint*1) mit denselben
// Schwellen 49 / 499 - eine zweite Rechnung waere ein zweiter
// Massstab, und dann streiten die beiden Berichte ueber dieselbe
// Codebasis.
const
  W_ERR      = 100;
  W_WARN     = 10;
  W_HINT     = 1;
  GRUEN_MAX  = 49;
  GELB_MAX   = 499;
var
  SB    : TStringBuilder;
  Score : Integer;
  Cls   : string;
  Txt   : TWbText;
begin
  Score := AStat.Sev[lsError] * W_ERR + AStat.Sev[lsWarning] * W_WARN
           + AStat.Sev[lsHint] * W_HINT;
  if Score <= GRUEN_MAX then
  begin
    Cls := 'gruen';
    Txt := wtHealthGruen;
  end
  else if Score <= GELB_MAX then
  begin
    Cls := 'gelb';
    Txt := wtHealthGelb;
  end
  else
  begin
    Cls := 'rot';
    Txt := wtHealthRot;
  end;
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="panels" id="bereich-ampel">');
    SB.AppendLine(Format('<div class="health health-%s">'
      + '<div class="health-zahl">%d</div>'
      + '<div><b>%s</b><div class="health-txt">%s</div></div></div>',
      [Cls, Score, TWorkbenchI18n.T(Txt, ALang),
       Format(TWorkbenchI18n.T(wtHealthFormel, ALang),
         [AStat.Sev[lsError], AStat.Sev[lsWarning],
          AStat.Sev[lsHint]])]));
    // Security-Panel nur, wenn es etwas zu sagen hat.
    if AStat.Security > 0 then
      SB.AppendLine(Format('<div class="secpanel">'
        + '<div><b>%s</b><div class="health-txt">%s</div></div>'
        + '<button type="button" id="btnSec" onclick="zeigeSecurity()">'
        + '%s</button></div>',
        [Format(TWorkbenchI18n.T(wtSecurityTitel, ALang),
           [AStat.Security]),
         TWorkbenchI18n.T(wtSecurityText, ALang),
         TWorkbenchI18n.T(wtSecurityZeigen, ALang)]));
    SB.AppendLine('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function Dashboard(const AStat: TFundStat; const ALang: string): string;
// Kennzahlen-Kacheln ueber ALLE Funde (auch bei gekuerzter Tabelle).
var
  SB : TStringBuilder;

  procedure Kachel(AZahl: Integer; AWofuer: TWbText);
  begin
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">%s</div></div>',
      [AZahl, TWorkbenchI18n.T(AWofuer, ALang)]));
  end;

begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="dash" id="bereich-kacheln">');
    Kachel(AStat.Gesamt,         wtKaFunde);
    Kachel(AStat.Sev[lsError],   wtKaFehler);
    Kachel(AStat.Sev[lsWarning], wtKaWarnungen);
    Kachel(AStat.Sev[lsHint],    wtKaHinweise);
    Kachel(AStat.Security,       wtKaSecurityFunde);
    Kachel(AStat.Dateien,        wtKaDateien);
    Kachel(AStat.Regeln,         wtKaRegeln);
    if AStat.Lesefehler > 0 then
      Kachel(AStat.Lesefehler,   wtKaLesefehler);
    SB.AppendLine('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SeitenJs(const ALang: string): string;
// Seiten-JS: Katalog-Mechanik (tbody-Sortierung, Suche + Chips,
// Trefferzaehler, Empty-State, Tastatur, Deep-Link, Copy-Fallback);
// der Drawer baut zusaetzlich den "Dieser Fund"-Kopf aus den Zellen
// und klont danach das REGEL-Template (dedupliziert je Regel).
// ZWEITE KOPIE der Katalog-JS-Mechanik (uDetectorInfoExport.DrawerJs)
// mit gewollten Abweichungen (Drawer-folgt-Filter, Fund-Kopf,
// Tastatur-Fixes) - bei einer DRITTEN Workbench-Seite den JS-Kern
// analog TWorkbenchStyle.BasisCss heben (Review 07.09.; die Historie
// zeigt, dass Fixes sonst je Seite einzeln nachgezogen werden).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<script>');
    SB.AppendLine('var richtung = {};');
    SB.AppendLine('var aktiveFilter = {typ:[], sev:[], konf:[]};');
    SB.AppendLine('var gewaehlt = null;');
    SB.AppendLine('function alleTbodies() {');
    SB.AppendLine('  return Array.prototype.slice.call('
      + 'document.querySelectorAll("#funde tbody"));');
    SB.AppendLine('}');
    SB.AppendLine('function zellwert(tb, spalte) {');
    SB.AppendLine('  var td = tb.rows[0].cells[spalte];');
    // data-sort kann seit 09.09. auch ein TEXT sein: die Methodenzelle
    // traegt dort den reinen Methodennamen, weil ihr textContent jetzt
    // auch den Dateipfad enthaelt (V3-Formatierung). Ein blindes
    // parseInt haette daraus NaN gemacht, und NaN vergleicht sich mit
    // allem als false - die Spalte waere unsortierbar geworden, ohne
    // dass es auffaellt.
    SB.AppendLine('  var d = td.dataset.sort;');
    SB.AppendLine('  if (d !== undefined) {');
    SB.AppendLine('    var n = parseInt(d, 10);');
    SB.AppendLine('    return isNaN(n) ? d.toLowerCase() : n;');
    SB.AppendLine('  }');
    SB.AppendLine('  return td.textContent.toLowerCase();');
    SB.AppendLine('}');
    SB.AppendLine('function sortiere(spalte) {');
    SB.AppendLine('  var tab = document.getElementById("funde");');
    SB.AppendLine('  var auf = !(richtung[spalte] || false);');
    SB.AppendLine('  richtung = {}; richtung[spalte] = auf;');
    SB.AppendLine('  var koepfe = tab.tHead.rows[0].cells;');
    SB.AppendLine('  for (var k = 0; k < koepfe.length; k++) {');
    SB.AppendLine('    var pf = koepfe[k].querySelector(".pfeil");');
    SB.AppendLine('    if (pf) pf.textContent = (k === spalte) ? '
      + '(auf ? String.fromCharCode(9650) : String.fromCharCode(9660)) '
      + ': "";');
    // aria-sort an der ZELLE: die Richtung stand bisher nur im
    // Pfeil-Zeichen und war fuer Screenreader unsichtbar
    // (A11y-Restpunkt des UI-Konzept-Abgleichs 07.09.).
    SB.AppendLine('    if (k === spalte)');
    SB.AppendLine('      koepfe[k].setAttribute("aria-sort", '
      + 'auf ? "ascending" : "descending");');
    SB.AppendLine('    else koepfe[k].removeAttribute("aria-sort");');
    SB.AppendLine('  }');
    SB.AppendLine('  var tbs = alleTbodies();');
    SB.AppendLine('  tbs.sort(function(a, b) {');
    SB.AppendLine('    var x = zellwert(a, spalte), y = zellwert(b, spalte);');
    SB.AppendLine('    if (x < y) return auf ? -1 : 1;');
    SB.AppendLine('    if (x > y) return auf ? 1 : -1;');
    SB.AppendLine('    // Gleichstand beim SEVERITY-Sort: sekundaer nach');
    SB.AppendLine('    // Konfidenz (hoch=2 zuerst, darum umgekehrt) -');
    SB.AppendLine('    // aus 400 gleich schweren Funden sind die');
    SB.AppendLine('    // belastbaren die, die man zuerst ansieht');
    SB.AppendLine('    // (V1-Verhalten, Feature-Abgleich 07.09.).');
    SB.AppendLine('    if (spalte === ' + IntToStr(SP_SEVERITY) + ') {');
    SB.AppendLine('      var ka = parseInt(a.dataset.konf, 10);');
    SB.AppendLine('      var kb = parseInt(b.dataset.konf, 10);');
    SB.AppendLine('      if (!isNaN(ka) && !isNaN(kb) && ka !== kb)');
    SB.AppendLine('        return kb - ka;');
    SB.AppendLine('    }');
    SB.AppendLine('    return 0;');
    SB.AppendLine('  });');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++) '
      + 'tab.appendChild(tbs[i]);');
    SB.AppendLine('}');
    SB.AppendLine('function passtChips(tb) {');
    SB.AppendLine('  var g, w, ok;');
    SB.AppendLine('  for (g in aktiveFilter) {');
    SB.AppendLine('    if (!aktiveFilter[g].length) continue;');
    SB.AppendLine('    w = tb.dataset[g];');
    SB.AppendLine('    ok = aktiveFilter[g].indexOf(w) >= 0;');
    SB.AppendLine('    if (!ok) return false;');
    SB.AppendLine('  }');
    SB.AppendLine('  return true;');
    SB.AppendLine('}');
    // Wert eines Dropdowns; fehlt das Element (Liste zu kurz zum
    // Anzeigen), gilt "kein Filter".
    SB.AppendLine('function auswahl(id) {');
    SB.AppendLine('  var el = document.getElementById(id);');
    SB.AppendLine('  return el ? el.value : "";');
    SB.AppendLine('}');
    // Die Suchbasis eines Fundes - beim ERSTEN Bedarf aus der Zeile
    // gelesen und danach am Knoten gemerkt. Sie stand bis 09.09. fertig
    // in data-search bei jedem Fund; das waren rund 225 Byte, die nichts
    // enthielten, was nicht in derselben Zeile schon sichtbar war.
    //
    // Der Zeilentext wird ZELLE FUER ZELLE geholt und mit Leerzeichen
    // verbunden, nicht als textContent der ganzen Zeile: der klebt die
    // Zellen aneinander ("42DoFoo"), und wo eine Zelle zwei Zeilen
    // fuehrt (Methode/Datei, Regel/Detail), klebt er auch die. Kleben
    // erzeugt zwar keine fehlenden, aber falsche Treffer an den
    // Nahtstellen.
    SB.AppendLine('function suchtext(tb) {');
    SB.AppendLine('  if (tb._s !== undefined) return tb._s;');
    SB.AppendLine('  var h = tb.querySelector("tr.haupt"), t = "";');
    SB.AppendLine('  if (h) for (var j = 0; j < h.children.length; j++) {');
    SB.AppendLine('    var z = h.children[j];');
    SB.AppendLine('    if (z.children.length)');
    SB.AppendLine('      for (var k = 0; k < z.children.length; k++)');
    SB.AppendLine('        t += z.children[k].textContent + " ";');
    SB.AppendLine('    else t += z.textContent + " ";');
    SB.AppendLine('  }');
    // RSUCH steht im Dokument VOR diesem Skript, ist aber notfalls
    // auch leer verkraftbar: dann faellt nur die Suche nach Kind-Name,
    // CWE und Tags aus, nicht die ganze Suche.
    SB.AppendLine('  t += (typeof RSUCH === "object" && '
      + 'RSUCH[tb.dataset.rid]) || "";');
    // EINMAL senken, ueber alles. Solange Zeilentext und Zusatz
    // dieselbe Senkung sehen, koennen sie nicht auseinanderlaufen -
    // das war der Grund fuer die AnsiLowerCase-Auflage von frueher.
    SB.AppendLine('  tb._s = t.toLowerCase();');
    SB.AppendLine('  return tb._s;');
    SB.AppendLine('}');
    SB.AppendLine('function suche() {');
    SB.AppendLine('  var q = document.getElementById("suche")'
      + '.value.toLowerCase();');
    SB.AppendLine('  var datei = auswahl("dateiFilter");');
    SB.AppendLine('  var regel = auswahl("regelFilter");');
    SB.AppendLine('  var tbs = alleTbodies(), sichtbar = 0;');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++) {');
    SB.AppendLine('    var hit = (q === "" || '
      + 'suchtext(tbs[i]).indexOf(q) >= 0) && passtChips(tbs[i])');
    SB.AppendLine('      && (datei === "" || tbs[i].dataset.pfad === datei)');
    SB.AppendLine('      && (regel === "" || tbs[i].dataset.rid === regel);');
    SB.AppendLine('    tbs[i].style.display = hit ? "" : "none";');
    SB.AppendLine('    if (hit) sichtbar++;');
    SB.AppendLine('  }');
    SB.AppendLine('  var ges = tbs.length;');
    SB.AppendLine('  document.getElementById("zaehler").textContent =');
    // Zaehlertext aus der Sprachtabelle - die beiden %d werden zum
    // JS-Ausdruck, damit die Wortstellung der Sprache erhalten bleibt
    // (frz.: '%d sur %d resultats').
    SB.AppendLine('    ' + StringReplace(StringReplace(
      '"' + TWorkbenchI18n.TJs(wtZaehlerFunde, ALang) + '"',
      '%d', '" + sichtbar + "', []), '%d', '" + ges + "', []) + ';');
    SB.AppendLine('  document.getElementById("leer").style.display =');
    SB.AppendLine('    sichtbar === 0 ? "block" : "none";');
    SB.AppendLine('  var ohneFunde = ges === 0;');
    SB.AppendLine('  document.getElementById("leer-suche").style.display '
      + '= ohneFunde ? "none" : "";');
    SB.AppendLine('  document.getElementById("leer-lauf").style.display '
      + '= ohneFunde ? "" : "none";');
    SB.AppendLine('  var aktiv = q !== "" || datei !== "" '
      + '|| regel !== "";');
    SB.AppendLine('  for (var g2 in aktiveFilter) '
      + 'if (aktiveFilter[g2].length) aktiv = true;');
    SB.AppendLine('  document.getElementById("reset").style.display =');
    SB.AppendLine('    aktiv ? "inline" : "none";');
    SB.AppendLine('  if (gewaehlt && gewaehlt.style.display '
      + '=== "none") schliesseDrawer();');
    SB.AppendLine('}');
    // Klick auf einen Top-Listen-Eintrag: setzt das zugehoerige
    // Dropdown und filtert. Fehlt das Dropdown (zu kurze Liste), tut
    // der Klick nichts - besser als ein Filter, den man nicht mehr
    // sieht und nicht zuruecknehmen kann.
    SB.AppendLine('function topKlick(el) {');
    SB.AppendLine('  var dd = document.getElementById(el.dataset.ziel);');
    SB.AppendLine('  if (!dd) return;');
    SB.AppendLine('  dd.value = el.dataset.wert;');
    SB.AppendLine('  suche();');
    SB.AppendLine('  var tab = document.getElementById("funde");');
    SB.AppendLine('  if (tab) tab.scrollIntoView({block:"start"});');
    SB.AppendLine('}');
    // Security-Knopf: setzt die beiden Typ-Chips, die als Security
    // gelten (Vulnerability + Hotspot), statt einen eigenen Filter zu
    // erfinden - so bleibt EIN Filterweg sichtbar und ruecknehmbar.
    SB.AppendLine('function zeigeSecurity() {');
    SB.AppendLine('  aktiveFilter.typ = ["vuln", "hotspot"];');
    // Apostrophe im JS-Selektor als '' verdoppelt - Delphi escapt
    // mit doppeltem Apostroph, NICHT mit Backslash (der erste Wurf
    // stand auf \' und war ein Compilerfehler).
    SB.AppendLine('  var bts = document.querySelectorAll('
      + '"button.fchip[data-gruppe=''typ'']");');
    SB.AppendLine('  for (var i = 0; i < bts.length; i++)');
    SB.AppendLine('    bts[i].setAttribute("aria-pressed",');
    SB.AppendLine('      aktiveFilter.typ.indexOf(bts[i].dataset.wert) '
      + '>= 0 ? "true" : "false");');
    SB.AppendLine('  suche();');
    SB.AppendLine('}');
    SB.AppendLine('function chip(btn) {');
    SB.AppendLine('  var g = btn.dataset.gruppe, w = btn.dataset.wert;');
    SB.AppendLine('  var liste = aktiveFilter[g];');
    SB.AppendLine('  var p = liste.indexOf(w);');
    SB.AppendLine('  if (p >= 0) liste.splice(p, 1); else liste.push(w);');
    SB.AppendLine('  btn.setAttribute("aria-pressed", '
      + 'p >= 0 ? "false" : "true");');
    SB.AppendLine('  suche();');
    SB.AppendLine('}');
    SB.AppendLine('function filterReset() {');
    SB.AppendLine('  aktiveFilter = {typ:[], sev:[], konf:[]};');
    SB.AppendLine('  var bts = document.querySelectorAll("button.fchip");');
    SB.AppendLine('  for (var i = 0; i < bts.length; i++) '
      + 'bts[i].setAttribute("aria-pressed", "false");');
    SB.AppendLine('  document.getElementById("suche").value = "";');
    // Auch die Dropdowns zuruecksetzen - sonst behauptet der
    // Reset-Knopf mehr, als er tut.
    SB.AppendLine('  var dd = document.getElementById("dateiFilter");');
    SB.AppendLine('  if (dd) dd.value = "";');
    SB.AppendLine('  var dr = document.getElementById("regelFilter");');
    SB.AppendLine('  if (dr) dr.value = "";');
    SB.AppendLine('  suche();');
    SB.AppendLine('}');
    // ---- Drawer: Fund-Kopf + Regel-Template ---------------------------
    // fundKopf baut die Ebenen 2 bis 5 der Inspector-Hierarchie
    // (IDE-Focus-Redesign 08.09.): HERO (Severity-Punkt, SCA-ID,
    // Titel, Badges) -> LOCATION -> Fund-Detail -> QUELLCODE ->
    // Hinweis. Alles kommt aus der ZEILE, also aus den Fund-Werten;
    // die Regel-Doku liefert danach das geteilte Template.
    // Die Badges werden aus den Zellen GEKLONT statt neu gebaut -
    // so bleibt ihre Optik automatisch dieselbe wie in der Tabelle.
    // Das Geruest des Quell-Ausschnitts - EINMAL im Skript statt bei
    // jedem Fund in der Seite (s. QuellAusschnitt). Es baut aus dem
    // Rohtext der unsichtbaren Zeile genau das Markup, das frueher
    // TExporterHtml.BuildCodeSnippet geschrieben hat: dieselben Klassen,
    // dieselbe vierstellige rechtsbuendige Nummer, derselbe Pfeil,
    // dieselben Leerzeichen dazwischen. Wer hier etwas aendert, aendert
    // das Bild - der Vergleichspunkt ist BuildCodeSnippet in uExportHtml.
    //
    // Aufbau ueber das DOM und nicht ueber innerHTML: der Rohtext ist
    // zwar escaped, aber er GEHOERT in einen Textknoten. Ueber
    // innerHTML wuerde er ein zweites Mal als Markup gelesen, und aus
    // dem escapten &lt;div&gt; einer Quellzeile wuerde wieder ein Tag.
    SB.AppendLine('function baueAusschnitt(td) {');
    SB.AppendLine('  var von = parseInt(td.dataset.l, 10) || 1;');
    SB.AppendLine('  var akt = parseInt(td.dataset.a, 10) || 0;');
    SB.AppendLine('  var wrap = document.createElement("div");');
    SB.AppendLine('  wrap.className = "src-snippet";');
    // String.fromCharCode statt der Escape-Folgen: Backslashes
    // ueberleben den Weg durch die Werkzeugkette nicht zuverlaessig
    // (mehrfach belegt), und ein verlorener Backslash macht aus dem
    // Zeilentrenner ein stilles "n".
    SB.AppendLine('  var zeilen = td.textContent.split('
      + 'String.fromCharCode(10));');
    SB.AppendLine('  for (var i = 0; i < zeilen.length; i++) {');
    SB.AppendLine('    var nr = von + i;');
    SB.AppendLine('    var aktiv = (nr === akt);');
    SB.AppendLine('    var d = document.createElement("div");');
    SB.AppendLine('    d.className = aktiv ? '
      + '"src-line src-line-active" : "src-line";');
    SB.AppendLine('    var sn = document.createElement("span");');
    SB.AppendLine('    sn.className = "src-line-num";');
    // Vierstellig rechtsbuendig wie Format('%4d'). Eine Schleife statt
    // padStart: der Rest des Skripts kommt ohne ES2017 aus, und der
    // Bericht soll auch in einem eingebetteten Browser lesbar sein.
    SB.AppendLine('    var s = String(nr);');
    SB.AppendLine('    while (s.length < 4) s = " " + s;');
    SB.AppendLine('    sn.textContent = s;');
    SB.AppendLine('    d.appendChild(sn);');
    SB.AppendLine('    d.appendChild(document.createTextNode(" "));');
    SB.AppendLine('    var sb = document.createElement("span");');
    SB.AppendLine('    sb.className = "src-line-bar";');
    // 9658 = der Pfeil nach rechts (frueher &#9658;), 160 = das
    // geschuetzte Leerzeichen (frueher &nbsp;). Beide halten die
    // Spalte, damit der Code aller Zeilen buendig steht.
    SB.AppendLine('    sb.textContent = aktiv ? '
      + 'String.fromCharCode(9658) : String.fromCharCode(160);');
    SB.AppendLine('    d.appendChild(sb);');
    SB.AppendLine('    d.appendChild(document.createTextNode(" "));');
    SB.AppendLine('    d.appendChild(document.createTextNode('
      + 'zeilen[i]));');
    SB.AppendLine('    wrap.appendChild(d);');
    SB.AppendLine('  }');
    SB.AppendLine('  return wrap;');
    SB.AppendLine('}');
    SB.AppendLine('function fundKopf(tb) {');
    // AUFBAU AUS DER V3-SEITE uebernommen (Nicos Auftrag 09.09.):
    // Badges - Ueberschrift - Fundort - Fundtext, alles auf EINER
    // Ebene. Vorher lag darum ein insp-hero mit einer eigenen
    // insp-kopfzeile, in der ein farbiger Punkt vor der ID stand und
    // der Regelname darunter umbrach.
    //
    // WAS DABEI BLEIBT: alle drei Badges (Typ, Schweregrad,
    // Konfidenz), ID, Regelname, Fundort und Fundtext - die
    // Information ist dieselbe, nur flacher gesetzt.
    // WAS ENTFAELLT: der farbige Punkt vor der ID. Er trug die
    // Severity ein zweites Mal, die daneben schon als Badge steht.
    //
    // Der Regel-Block (Was wird erkannt / Warum relevant, Vorher/
    // Nachher mit Copy, CWE, Tags) haengt UNVERAENDERT hinten dran -
    // er kommt aus dem Template je Regel, nicht von hier. V3 hat ihn
    // nicht; ihn mit zu uebernehmen hiesse, ihn zu verlieren.
    SB.AppendLine('  var z = tb.rows[0];');
    SB.AppendLine('  var kopf = document.createElement("div");');
    // Badges zuerst - Typ, Severity, Konfidenz, geklont aus den Zellen.
    SB.AppendLine('  var badges = document.createElement("div");');
    SB.AppendLine('  badges.className = "insp-badges";');
    SB.AppendLine('  [' + IntToStr(SP_TYP) + ', '
      + IntToStr(SP_SEVERITY) + ', ' + IntToStr(SP_KONFIDENZ)
      + '].forEach(function(sp) {');
    SB.AppendLine('    var b = z.cells[sp].querySelector(".badge");');
    SB.AppendLine('    if (b) badges.appendChild(b.cloneNode(true));');
    SB.AppendLine('  });');
    SB.AppendLine('  kopf.appendChild(badges);');
    // Ueberschrift: ID und Regelname in EINER Zeile, wie in V3.
    SB.AppendLine('  var titel = document.createElement("h2");');
    SB.AppendLine('  titel.className = "insp-titel";');
    // NUR .zl-regel, nicht die ganze Zelle: dort steht seit 09.09.
    // auch der Detailtext. Ein blosses textContent haette den
    // Titel zu "SCA168 case statement without else branchcase
    // statement without else - unhandled..." gemacht.
    SB.AppendLine('  var rn = z.cells[' + IntToStr(SP_REGEL)
      + '].querySelector(".zl-regel");');
    SB.AppendLine('  titel.textContent = z.cells[' + IntToStr(SP_SCAID)
      + '].textContent + " " + (rn ? rn.textContent : "");');
    SB.AppendLine('  kopf.appendChild(titel);');
    // Fundort: Datei:Zeile - Methode. Klasse metarow wie in V3.
    SB.AppendLine('  var ort = document.createElement("div");');
    SB.AppendLine('  ort.className = "metarow";');
    SB.AppendLine('  var t = (tb.dataset.pfad || "") + ":" '
      + '+ z.cells[' + IntToStr(SP_ZEILE) + '].textContent;');
    // NUR die Methode, nicht die ganze Zelle: seit dem Umbau auf die
    // V3-Formatierung (09.09.) steht in dieser Zelle auch der
    // Dateipfad. Ein blosses textContent haette daraus
    // "pfad:zeile - TFoo.BarMeineUnit.pas; src/MeineUnit.pas"
    // gemacht - der Pfad stuende dann zweimal in einer Zeile.
    SB.AppendLine('  var meth = z.cells[' + IntToStr(SP_METHODE)
      + '].querySelector(".zl-methode");');
    SB.AppendLine('  if (meth && meth.textContent) '
      + 't += " " + String.fromCharCode(183) + " " + meth.textContent;');
    SB.AppendLine('  ort.textContent = t;');
    SB.AppendLine('  kopf.appendChild(ort);');
    // Der Fundtext als insp-block - dieselbe Huelle, die V3 dafuer
    // nimmt und die auch der Regel-Block darunter verwendet.
    // Der Detailtext steht seit 09.09. als zweite Zeile IN der
    // Regelzelle - eine eigene Detail-Spalte gibt es nicht mehr.
    SB.AppendLine('  var dv = z.cells[' + IntToStr(SP_REGEL)
      + '].querySelector(".zl-detail");');
    SB.AppendLine('  var det = dv ? dv.textContent : "";');
    SB.AppendLine('  if (det) {');
    SB.AppendLine('    var db = document.createElement("div");');
    SB.AppendLine('    db.className = "insp-block";');
    SB.AppendLine('    var p = document.createElement("p");');
    SB.AppendLine('    p.textContent = det;');
    SB.AppendLine('    db.appendChild(p);');
    SB.AppendLine('    kopf.appendChild(db);');
    SB.AppendLine('  }');
    // Quell-Ausschnitt FRUEH (Ebene 4): fuer den Entwickler ist die
    // Codezeile der visuelle Anker. Er liegt als unsichtbare
    // tr.snippet beim Fund und wird geklont, nicht verschoben - die
    // Zeile bleibt Datenquelle fuer das naechste Oeffnen.
    // Aus dem Rohtext der unsichtbaren Zeile das Geruest bauen. Es
    // entsteht fuer GENAU den Ausschnitt, den der Leser gerade oeffnet -
    // vorher stand es fertig bei jedem einzelnen Fund in der Datei.
    // Das erzeugte Markup ist Zeichen fuer Zeichen dasselbe wie vorher.
    SB.AppendLine('  var sz = tb.querySelector("tr.snippet td");');
    SB.AppendLine('  if (sz) kopf.appendChild(baueAusschnitt(sz));');
    SB.AppendLine('  if (tb.dataset.hinweis) {');
    SB.AppendLine('    var blk = document.createElement("div");');
    SB.AppendLine('    blk.className = "insp-block";');
    SB.AppendLine('    var h3 = document.createElement("h3");');
    SB.AppendLine('    h3.textContent = "'
      + TWorkbenchI18n.TJs(wtHinweisZuFund, ALang) + '";');
    SB.AppendLine('    blk.appendChild(h3);');
    SB.AppendLine('    var hp = document.createElement("p");');
    SB.AppendLine('    hp.textContent = tb.dataset.hinweis;');
    SB.AppendLine('    blk.appendChild(hp);');
    SB.AppendLine('    kopf.appendChild(blk);');
    SB.AppendLine('  }');
    SB.AppendLine('  return kopf;');
    SB.AppendLine('}');
    SB.AppendLine('function oeffneDrawer(tb) {');
    SB.AppendLine('  var tpl = document.getElementById('
      + '"tpl-" + tb.dataset.rid);');
    SB.AppendLine('  if (!tpl) return;');
    SB.AppendLine('  var korb = document.getElementById("drawer-inhalt");');
    SB.AppendLine('  korb.innerHTML = "";');
    SB.AppendLine('  korb.appendChild(fundKopf(tb));');
    SB.AppendLine('  korb.appendChild(tpl.content.cloneNode(true));');
    SB.AppendLine('  var dw = document.getElementById("drawer");');
    SB.AppendLine('  dw.classList.add("offen");');
    SB.AppendLine('  dw.scrollTop = 0;');
    SB.AppendLine('  // Auswahl liegt am TBODY - markiert Haupt- UND');
    SB.AppendLine('  // Datei-Zeile als einen Block (CSS tbody.gewaehlt).');
    SB.AppendLine('  if (gewaehlt) gewaehlt.classList.remove("gewaehlt");');
    SB.AppendLine('  gewaehlt = tb;');
    SB.AppendLine('  gewaehlt.classList.add("gewaehlt");');
    SB.AppendLine('}');
    SB.AppendLine('function schliesseDrawer() {');
    SB.AppendLine('  document.getElementById("drawer").classList'
      + '.remove("offen");');
    SB.AppendLine('  if (gewaehlt) { gewaehlt.classList.remove('
      + '"gewaehlt"); gewaehlt = null; }');
    SB.AppendLine('}');
    SB.AppendLine('function kopiere(btn) {');
    SB.AppendLine('  // navigator.clipboard braucht Secure Context - '
      + 'file:// ist keiner.');
    SB.AppendLine('  var quelle = btn.closest("[data-copy]");');
    SB.AppendLine('  if (!quelle) return;');
    SB.AppendLine('  var txt = quelle.dataset.copy;');
    SB.AppendLine('  var ta = document.createElement("textarea");');
    SB.AppendLine('  ta.value = txt; document.body.appendChild(ta);');
    SB.AppendLine('  ta.select();');
    SB.AppendLine('  try { document.execCommand("copy"); '
      + 'btn.textContent = "'
      + TWorkbenchI18n.TJs(wtKopiert, ALang) + '"; } catch (e) {}');
    SB.AppendLine('  document.body.removeChild(ta);');
    SB.AppendLine('  setTimeout(function(){ btn.textContent = '
      + '"' + TWorkbenchI18n.TJs(wtKopieren, ALang) + '"; }, 1200);');
    SB.AppendLine('}');
    // ---- Tastatur + Deep-Link ----------------------------------------
    SB.AppendLine('function sichtbareZeilen() {');
    SB.AppendLine('  return alleTbodies().filter(function(tb){ '
      + 'return tb.style.display !== "none"; });');
    SB.AppendLine('}');
    SB.AppendLine('document.addEventListener("keydown", function(ev) {');
    SB.AppendLine('  if (ev.ctrlKey && (ev.key === "k" || '
      + 'ev.key === "K")) {');
    SB.AppendLine('    ev.preventDefault();');
    SB.AppendLine('    document.getElementById("suche").focus();');
    SB.AppendLine('    return;');
    SB.AppendLine('  }');
    SB.AppendLine('  if (ev.key === "Escape") { schliesseDrawer(); '
      + 'return; }');
    SB.AppendLine('  if (ev.key !== "ArrowDown" && ev.key !== "ArrowUp" '
      + '&& ev.key !== "Enter") return;');
    SB.AppendLine('  if (ev.target && ev.target.id === "suche" && '
      + 'ev.key === "Enter") return;');
    SB.AppendLine('  // Buttons behalten ihre Enter-Aktivierung - ohne');
    SB.AppendLine('  // den Ausstieg schluckte preventDefault den Klick');
    SB.AppendLine('  // und oeffnete stattdessen die erste Zeile');
    SB.AppendLine('  // (Review 07.09., Tastatur-Bedienung der Chips).');
    SB.AppendLine('  if (ev.target && ev.target.tagName === "BUTTON") '
      + 'return;');
    SB.AppendLine('  // Enter auf einer per Tab fokussierten Zeile');
    SB.AppendLine('  // oeffnet DIESE Zeile, nicht die gewaehlt-/erste.');
    SB.AppendLine('  if (ev.key === "Enter" && ev.target '
      + '&& ev.target.classList '
      + '&& ev.target.classList.contains("haupt")) {');
    SB.AppendLine('    ev.preventDefault();');
    SB.AppendLine('    oeffneDrawer(ev.target.parentNode);');
    SB.AppendLine('    return;');
    SB.AppendLine('  }');
    SB.AppendLine('  var zeilen = sichtbareZeilen();');
    SB.AppendLine('  if (!zeilen.length) return;');
    SB.AppendLine('  var idx = -1;');
    SB.AppendLine('  for (var i = 0; i < zeilen.length; i++)');
    SB.AppendLine('    if (gewaehlt && zeilen[i] === gewaehlt) '
      + '{ idx = i; break; }');
    SB.AppendLine('  if (ev.key === "ArrowDown") idx++;');
    SB.AppendLine('  if (ev.key === "ArrowUp") idx--;');
    SB.AppendLine('  if (idx < 0) idx = 0;');
    SB.AppendLine('  if (idx >= zeilen.length) idx = zeilen.length - 1;');
    SB.AppendLine('  if (ev.key === "Enter" && gewaehlt) '
      + '{ oeffneDrawer(zeilen[idx]); return; }');
    SB.AppendLine('  ev.preventDefault();');
    SB.AppendLine('  oeffneDrawer(zeilen[idx]);');
    SB.AppendLine('  zeilen[idx].rows[0].scrollIntoView('
      + '{block:"nearest"});');
    SB.AppendLine('});');
    SB.AppendLine('function deepLink() {');
    SB.AppendLine('  // #SCAxxx oeffnet den ERSTEN Fund der Regel - der');
    SB.AppendLine('  // Anker aus Ticket oder Bericht ist die SCA-ID.');
    SB.AppendLine('  var h = location.hash.replace("#", "");');
    SB.AppendLine('  if (!h) return;');
    SB.AppendLine('  var tbs = alleTbodies();');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++)');
    SB.AppendLine('    if (tbs[i].dataset.rid === h) {');
    SB.AppendLine('      oeffneDrawer(tbs[i]);');
    SB.AppendLine('      tbs[i].rows[0].scrollIntoView('
      + '{block:"center"});');
    SB.AppendLine('      return;');
    SB.AppendLine('    }');
    SB.AppendLine('}');
    // ---- Thema hell/dunkel/sepia (Feature-Abgleich 07.09.) -----------
    // Drei-Wege-Zyklus wie im V1-Report, inklusive Speicherung. Ein
    // fremder oder korrupter localStorage-Wert wird verworfen, statt
    // als Attribut-Muell zu landen; ohne gespeicherte Wahl entscheidet
    // die Systempraeferenz (die CSS-@media-Regel greift dann von
    // selbst, darum wird NICHTS gesetzt). localStorage kann werfen
    // (file://, geblockte Site-Daten) - alle Zugriffe gekapselt.
    SB.AppendLine('(function(){');
    SB.AppendLine('  var KEY = "sca-v2-theme";');
    SB.AppendLine('  var THEMEN = ["light", "dark", "sepia"];');
    SB.AppendLine('  var gespeichert = null;');
    SB.AppendLine('  try { gespeichert = localStorage.getItem(KEY); } '
      + 'catch (e) {}');
    // Redundant, seit der Anti-Blitz-Block im <head> dasselbe tut -
    // und bewusst stehengeblieben: er ist der Rueckfall, falls dort
    // etwas scheitert, und idempotent (dasselbe Attribut, derselbe
    // Wert). Wer ihn entfernt, muss den Head-Block als einzige Quelle
    // pruefen. Denselben doppelten Boden fuehrt der V1-Report.
    SB.AppendLine('  if (THEMEN.indexOf(gespeichert) >= 0)');
    SB.AppendLine('    document.documentElement.setAttribute('
      + '"data-theme", gespeichert);');
    SB.AppendLine('  var bt = document.getElementById("btnTheme");');
    SB.AppendLine('  if (bt) bt.addEventListener("click", function(){');
    SB.AppendLine('    var jetzt = document.documentElement'
      + '.getAttribute("data-theme");');
    SB.AppendLine('    var next = THEMEN[(THEMEN.indexOf(jetzt) + 1) '
      + '% THEMEN.length];');
    SB.AppendLine('    document.documentElement.setAttribute('
      + '"data-theme", next);');
    SB.AppendLine('    try { localStorage.setItem(KEY, next); } '
      + 'catch (e) {}');
    SB.AppendLine('  });');
    SB.AppendLine('})();');
    SB.AppendLine('window.addEventListener("hashchange", deepLink);');
    // Initialsortierung nach Severity (aufsteigend = Rang 0 zuerst =
    // Fehler oben). Ohne sie stand der Bericht in Eingangsreihenfolge
    // da; V1 sortiert seit jeher nach Risiko - "hoechstes Risiko
    // zuerst" ist die Gewohnheit der Leser (Feature-Abgleich 07.09.).
    SB.AppendLine('sortiere(' + IntToStr(SP_SEVERITY) + ');');
    SB.AppendLine('suche();');
    SB.AppendLine('deepLink();');
    // Angepinnter Kopf mit zwei Zustaenden - EINE Quelle fuer
    // alle drei Seiten (Nutzerauftrag 09.09.).
    SB.Append(TWorkbenchStyle.KopfVerhaltenJs);
    // --filter-h: die Hoehe der angepinnten Filterleiste. Sie sagt der
    // Spaltenzeile, wie weit unter dem Fensterrand sie einrasten muss -
    // naemlich unter Seitenkopf UND Filterleiste (s. th).
    //
    // Eigener Block statt im geteilten Kopf-Verhalten: die
    // Filterleiste gibt es nur auf DIESER Seite. Die Hoehe aendert
    // sich mit der Fensterbreite, weil die Chips umbrechen - deshalb
    // auch am resize.
    SB.AppendLine('(function(){');
    SB.AppendLine('  var fl=document.getElementById("bereich-filter");');
    SB.AppendLine('  if(!fl)return;');
    SB.AppendLine('  function merken(){');
    SB.AppendLine('    document.documentElement.style.setProperty('
    // Bruchteile statt gerundeter Pixel - Begruendung wie bei --kopf-h
    // in TWorkbenchStyle.KopfVerhaltenJs.
      + '"--filter-h",fl.getBoundingClientRect().height+"px");');
    SB.AppendLine('  }');
    SB.AppendLine('  window.addEventListener("resize",merken);');
    // Die Chips-Leiste aendert ihre Hoehe auch OHNE resize: ein
    // Lesefehler-Chip kommt hinzu, ein Filter blendet Chips aus.
    // ResizeObserver faengt das; wo es ihn nicht gibt, bleibt es beim
    // Startwert - dann ist die Liste hoechstens etwas zu hoch.
    SB.AppendLine('  if(window.ResizeObserver)'
      + 'new ResizeObserver(merken).observe(fl);');
    SB.AppendLine('  merken();');
    SB.AppendLine('})();');
    SB.AppendLine('</script>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SuchZusatzRegel(K: TFindingKind;
  const AMeta: TRuleMeta): string;
// Was zur Suche gehoert, aber NICHT in der Fundzeile steht: der
// technische Kind-Name und die Metadaten CWE und Tags. Der Rest -
// Pfad, Zeile, Methode, Detail, ID, Regelname, Typ, Schweregrad,
// Konfidenz - ist sichtbar, und die Anzeige liest ihn direkt aus der
// Zeile.
//
// WARUM NICHT MEHR JE FUND (Aenderung 09.09.)
// Bis hierher trug jeder Fund einen fertigen Suchblob in data-search:
// alles Sichtbare noch einmal, kleingeschrieben. Rund 225 Byte pro
// Fund, die nichts enthielten, was nicht drei Zentimeter weiter rechts
// schon stand. Bei vierzigtausend Funden sind das neun Megabyte, die
// der Browser laedt und parst, damit die Suche sich einen DOM-Zugriff
// spart.
//
// Was BLEIBT, ist je REGEL gleich - also steht es jetzt einmal je
// Regel in einer Tabelle, nicht einmal je Fund in der Zeile.
//
// Kleingeschrieben wird nicht mehr hier, sondern in der Anzeige: sie
// muss den Zeilentext ohnehin senken, und ein toLowerCase ueber alles
// kann nicht auseinanderlaufen. Die alte AnsiLowerCase-Auflage - sie
// stammte daher, dass Pascal und JS verschieden senken (Chargen-Review
// 06.09.) - ist damit gegenstandslos.
begin
  Result := Einzeilig(KIND_META[K].Name + ' '
    + JoinArr(AMeta.CWE, ' ') + ' ' + JoinArr(AMeta.Tags, ' '));
end;

function Snippetblock(const ASnippet: string;
  AErsteZeile, AFundZeile: Integer): string;
// Traegerzeile fuer den Quell-Ausschnitt. Eine eigene, dauerhaft
// unsichtbare tr haelt das tbody-Modell intakt (nur tr-Kinder) -
// ein <template> direkt im tbody waere nach der HTML-Parser-Regel
// fuer Tabellen aus der Tabelle herausgehoben worden.
//
// Die Zelle traegt seit dem 09.09. nur noch den ROHEN Quelltext; das
// Geruest baut das Skript beim Oeffnen (s. QuellAusschnitt). Zwei
// Zahlen reichen ihm dafuer:
//   data-l  Nummer der ERSTEN Zeile - ab hier wird weitergezaehlt
//   data-a  Nummer der Fundzeile - sie bekommt Pfeil und Hervorhebung
// data-a getrennt zu fuehren und nicht aus der Fundzeile der Hauptzeile
// zu lesen kostet zwoelf Zeichen und macht die Zelle fuer sich
// verstaendlich: der Ausschnitt bleibt richtig, auch wenn sich an der
// Spaltenaufteilung wieder etwas aendert.
//
// KEIN colspan mehr: die Zeile ist display:none, sie hat nie etwas
// ausgerichtet. Das Attribut war reine Gewohnheit aus der Zeit, als
// der Ausschnitt aufgeklappt IN der Tabelle stand.
begin
  if ASnippet = '' then Exit('');
  Result := Format('<tr class="snippet"><td data-l="%d" data-a="%d">',
      [AErsteZeile, AFundZeile])
    + ASnippet
    + '</td></tr>'#13#10;
end;

function ZeileFuerFund(const Z: TFundZeile): string;
// Ein tbody je Fund mit EINER sichtbaren Zeile (Stand 09.09.):
//   tr.haupt: Zeile, Methode+Datei, SCA-ID, Regel, Typ, Schweregrad,
//             Konfidenz, Detail
// Methode und Datei stehen in DERSELBEN Zelle uebereinander - die
// Formatierung der V3-Seite, uebernommen auf Nicos Wunsch. Bis dahin
// war die Datei eine eigene tr mit colspan=8; das kostete je Fund
// eine ganze Tabellenzeile.
//
// ZWEI Stellen haengen daran und muessten mitwandern, wenn sich das
// wieder aendert: die Methodenzelle traegt ihren Sortierschluessel in
// data-sort (ihr textContent enthaelt jetzt auch den Pfad), und
// fundKopf() liest fuer die Fundort-Zeile gezielt .zl-methode statt
// der ganzen Zelle.
//
// Die Datei stand ganz frueher als umbrechende Schmalspalte VOR der Zeile -
// unlesbar bei tiefen Pfaden (Screenshot-Befund). data-pfad am tbody
// versorgt den Drawer-Fundort. Die Datei-Spalte ist damit nicht mehr
// per Kopfklick sortierbar (kein Kopf) - Suche und Suchblob decken
// den Datei-Zugriff.
var
  SevTxt, SevBadge : string;
  SevRang          : Integer;
  HinweisAttr      : string;
  DateiName        : string;
  DateiZeile       : string;
begin
  if Z.Fund.Kind = fkFileReadError then
  begin
    // Lesefehler: kein Schweregrad-Wort der Skala; eigener Rang hinter
    // den Hinweisen, neutraler Badge (wie die readerr-Politik der V1).
    SevTxt   := TWorkbenchI18n.T(wtLesefehler, Z.Lang);
    SevBadge := Format('<span class="badge typ ferr">%s</span>',
      [SevTxt]);
    SevRang  := SEV_RANG_LESEFEHLER;
  end
  else
  begin
    SevTxt   := TWorkbenchI18n.T(SEV_KEY[Z.Fund.Severity], Z.Lang);
    SevBadge := Format('<span class="badge sev-%s">%s</span>',
      [SEV_CSS[Z.Fund.Severity], SevTxt]);
    SevRang  := Ord(Z.Fund.Severity);
  end;
  if Z.Hinweis <> '' then
    HinweisAttr := Format(' data-hinweis="%s"',
      [H(Einzeilig(Z.Hinweis))])
  else
    HinweisAttr := '';
  // "Dateiname; voller Pfad" - das Doppel entfaellt, wenn der Fund
  // ohnehin nur den Basisnamen traegt. ExtractFileName laeuft auf dem
  // ORIGINAL-Pfad (Windows-Trenner), nicht auf dem Anzeige-Pfad.
  DateiName := ExtractFileName(Z.Fund.FileName);
  if Z.Pfad = DateiName then
    DateiZeile := H(DateiName)
  else
    DateiZeile := H(DateiName) + '; ' + H(Z.Pfad);
  Result :=
    // KEIN data-search mehr (seit 09.09.): die Suche liest den
    // Zeilentext und holt sich den Rest aus der Regel-Tabelle RSUCH.
    Format('<tbody data-rid="%s" data-typ="%s" '
      + 'data-sev="%d" data-konf="%d" data-pfad="%s"%s>'#13#10,
      [H(Z.Meta.ID),
       TypCss(Z.Meta.FindingType), SevRang, Ord(Z.Fund.Confidence),
       H(Z.Pfad), HinweisAttr])
    + '<tr class="haupt" tabindex="0" '
    + 'onclick="oeffneDrawer(this.parentNode)">'
    + Format('<td class="num" data-sort="%d">%s</td>',
        [StrToIntDef(Z.Fund.LineNumber, 0), H(Z.Fund.LineNumber)])
    // Methode UND Datei in EINER Zelle, zweizeilig (V3-Formatierung,
    // uebernommen am 09.09. auf Nicos Wunsch). Vorher war die Datei
    // eine eigene tr mit colspan=8 - das kostete je Fund eine ganze
    // Tabellenzeile, also ein Viertel der Zeilen des Berichts.
    //
    // data-sort traegt den REINEN Methodennamen: ohne ihn liest
    // zellwert() den textContent der Zelle, und der enthaelt jetzt
    // auch den Dateipfad - sortiert wuerde dann nach "Methode plus
    // Datei" statt nach der Methode.
    + Format('<td data-sort="%s"><div class="zl-methode">%s</div>'
        + '<div class="zl-datei" title="%s">%s</div></td>',
        [HA(Z.Fund.MethodName), H(Z.Fund.MethodName),
         HA(Z.Pfad), DateiZeile])
    + '<td class="id">' + H(Z.Meta.ID) + '</td>'
    // Regelname UND Detailtext in EINER Zelle, untereinander (Nicos
    // Auftrag 09.09.). Beide sind oft lang; nebeneinander in zwei
    // Spalten haben sie sich gegenseitig die Breite genommen.
    //
    // data-sort traegt den REINEN Regelnamen - aus demselben Grund wie
    // bei der Methodenzelle: der textContent enthaelt jetzt auch den
    // Detailtext, sortiert wuerde also nach beidem.
    + Format('<td data-sort="%s"><div class="zl-regel">%s</div>'
        + '<div class="zl-detail">%s</div></td>',
        [HA(Z.Meta.Name), H(Z.Meta.Name), H(Z.Fund.MissingVar)])
    + Format('<td><span class="badge typ %s">%s</span></td>',
        [TypCss(Z.Meta.FindingType), H(TypText(Z.Meta.FindingType))])
    + Format('<td data-sort="%d">%s</td>', [SevRang, SevBadge])
    + Format('<td data-sort="%d"><span class="badge konf">%s'
        + '</span></td>', [Ord(Z.Fund.Confidence),
           TWorkbenchI18n.T(CONF_KEY[Z.Fund.Confidence], Z.Lang)])
    + '</tr>'#13#10
    // Der Quell-Ausschnitt liegt als Rohtext in einer unsichtbaren
    // Zeile bei diesem Fund - nicht in einem Attribut, weil Zeilen-
    // umbrueche dort nur als Entity ueberleben und je Zeile fuenf
    // Zeichen kosten wuerden. Der Drawer baut daraus das Geruest.
    + Snippetblock(Z.Snippet, Z.SnippetVon,
        StrToIntDef(Z.Fund.LineNumber, 0))
    + '</tbody>';
end;

function TemplateFuerRegel(K: TFindingKind; const AMeta: TRuleMeta;
  const ALang: string): string;
// Regel-Doku als geteiltes Template - EINMAL je vorkommender Regel
// (der Deduplikations-Kern der V2, s. Unit-Kopf). Seit dem
// IDE-Focus-Redesign (08.09.) OHNE Titel und Status-Badges: die
// stehen im Hero des Inspectors und zeigen dort die Werte des
// konkreten FUNDES. Damit entfiel auch der frueher uebergebene
// Regel-Default-Schweregrad - ein Parameter, den niemand mehr las.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('<template id="tpl-%s">', [H(AMeta.ID)]));
    // KEIN Titel und KEINE Status-Badges mehr: die stehen seit dem
    // IDE-Focus-Redesign (08.09.) im HERO des Inspectors und zeigen
    // dort die Werte DIESES FUNDES statt der Regel-Defaults. Das
    // Template liefert ab hier nur noch die Regel-Doku - Erklaerung,
    // Fix, Suppression, Metadaten - in genau dieser Staffelung.
    SB.AppendLine('<div class="insp-block">');
    SB.AppendLine('<h3>' + TWorkbenchI18n.T(wtWasWirdErkannt, ALang)
      + '</h3>');
    SB.AppendLine('<p>' + H(AMeta.ShortDescription) + '</p>');
    SB.AppendLine('</div>');
    if AMeta.FullDescription <> '' then
    begin
      SB.AppendLine('<div class="insp-block">');
      SB.AppendLine('<h3>' + TWorkbenchI18n.T(wtWarumRelevant, ALang)
        + '</h3>');
      SB.AppendLine('<p>' + H(AMeta.FullDescription) + '</p>');
      SB.AppendLine('</div>');
    end;
    if (AMeta.BadExample <> '') or (AMeta.GoodExample <> '') then
    begin
      // Der FIX ist die Handlung - eigener Block mit Trennlinie
      // darueber, damit er sich vom Verstehen-Teil abhebt.
      SB.AppendLine('<div class="insp-fix">');
      SB.AppendLine('<h3>' + TWorkbenchI18n.T(wtFixMuster, ALang)
        + '</h3>');
      SB.AppendLine('<div class="codekarten">');
      // #10#10 vor </pre>: zwei Leerzeilen Luft am Blockende (gleicher
      // Nutzerwunsch wie Katalog und V1). data-copy = der reine Code
      // via HA(): Umbrueche als '&#10;', nicht als '<br>'-Token.
      if AMeta.BadExample <> '' then
        SB.AppendLine(Format('<div class="codekarte schlecht" '
          + 'data-copy="%s"><div class="karte-titel">'
          + TWorkbenchI18n.T(wtVorher, ALang)
          + '<button class="copy" onclick="kopiere(this)">'
          + TWorkbenchI18n.T(wtKopieren, ALang)
          + '</button></div><pre>%s' + #10#10'</pre></div>',
          [HA(AMeta.BadExample), H(AMeta.BadExample)]));
      if AMeta.GoodExample <> '' then
        SB.AppendLine(Format('<div class="codekarte gut" '
          + 'data-copy="%s"><div class="karte-titel">'
          + TWorkbenchI18n.T(wtNachher, ALang)
          + '<button class="copy" onclick="kopiere(this)">'
          + TWorkbenchI18n.T(wtKopieren, ALang)
          + '</button></div><pre>%s' + #10#10'</pre></div>',
          [HA(AMeta.GoodExample), H(AMeta.GoodExample)]));
      SB.AppendLine('</div>');   // .codekarten
      SB.AppendLine('</div>');   // .insp-fix
    end;
    // Suppression und Kalibrierung: vollstaendig, aber SEKUNDAER -
    // sie beantworten nicht "was ist das Problem", sondern "wie
    // stelle ich es leiser" (TODO-Punkt D).
    SB.AppendLine('<div class="insp-sekundaer">');
    SB.AppendLine(Format('<div class="karte" data-copy="// noinspection '
      + '%s"><h3>' + TWorkbenchI18n.T(wtUnterdruecken, ALang)
      + ' <button class="copy" onclick="kopiere(this)">'
      + TWorkbenchI18n.T(wtKopieren, ALang) + '</button></h3>'
      + '<pre>// noinspection %s</pre>'
      + '<p>' + TWorkbenchI18n.T(wtUnterdrueckenText, ALang)
      + '</p></div>',
      [H(KIND_META[K].Name), H(KIND_META[K].Name)]));
    if AMeta.ConfigKey <> '' then
      SB.AppendLine(Format('<div class="karte" data-copy="%s">'
        + '<h3>' + TWorkbenchI18n.T(wtKalibrierung, ALang)
        + ' <button class="copy" onclick="kopiere(this)">'
        + TWorkbenchI18n.T(wtKopieren, ALang) + '</button></h3>'
        + '<pre>%s</pre>'
        + '<p>' + TWorkbenchI18n.T(wtKalibrierungText, ALang)
        + '</p></div>',
        [H(AMeta.ConfigKey), H(AMeta.ConfigKey)]));
    SB.AppendLine('</div>');   // .insp-sekundaer
    SB.AppendLine('<div class="metarow">'
      + 'CWE: ' + ChipListe(AMeta.CWE, 'cwe')
      + ' &middot; ' + TWorkbenchI18n.T(wtTagsLabel, ALang) + ': '
      + ChipListe(AMeta.Tags, 'tag')
      + ' &middot; ' + TWorkbenchI18n.T(wtDetektorUnit, ALang)
      + ': <span class="mono">'
      + H(AMeta.DetectorUnit) + '</span></div>');
    SB.AppendLine('</template>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TFindingsWorkbenchExport.DefaultFileName: string;
// Vorschlag fuer den Save-Dialog: sca_codereview_2026-09-06.html
// (Nicos Auftrag 10.09.).
//
// MIT DATUM, und das ist der Punkt. Der bisherige feste Name
// 'sca-funde-v2.html' liess jeden Export den vorigen ueberschreiben -
// zwei Staende nebeneinanderzulegen ging nur, wenn man im Dialog von
// Hand umbenannte. Das Datum macht den Bericht ausserdem ohne Oeffnen
// zuordenbar. Die Versionsnummer faellt weg; es gibt seit dem 09.09.
// nur noch einen HTML-Fundbericht.
//
// Gebaut wird der Name von V1, nicht hier nachgebaut. Der Parameter
// heisst dort SourceFile, dient aber genau als BASISNAME - leer ergibt
// 'analyse', 'sca' ergibt 'sca'. Mitgeliefert bekommt man damit zwei
// Dinge, die man sonst kopieren muesste: die Pinnung ueber
// SCA_REPORT_TIMESTAMP (deterministische Bauten) und das Ersetzen der
// unter Windows verbotenen Zeichen - ein ISO-Zeitstempel bringt einen
// Doppelpunkt mit, und ab dem liest Windows einen alternativen
// Datenstrom (Modul-Codereview 08.09.).
begin
  Result := TExporterHtml.DefaultFileName('sca', '');
end;

class procedure TFindingsWorkbenchExport.Run(
  AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AFileName: string; AMaxRows: Integer;
  const ALang: string);
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    BauePage(SB, AFindings, ABaseDir, AMaxRows, ALang);
    // Direkt aus dem Builder schreiben (BOM-Politik + Stueckgrenze im
    // Helfer): kein ToString, keine TStringList - beides waeren
    // Vollkopien des Berichts, und SL.Text normalisierte obendrein
    // die bewusste #10#10-Anzeige-Luft der Codekarten zu CRLF
    // (Chargen-Review 07.09.; V1-OOM-Lehre, genau dafuer ist
    // SaveBuilderUtf8WithBom public).
    TExporterHtml.SaveBuilderUtf8WithBom(SB, AFileName);
  finally
    SB.Free;
  end;
end;

function DateiEintraege(
  ADateien: TDictionary<string, Integer>): TArray<TZaehlEintrag>;
// Datei-Dropdown: alphabetisch, mit Fundzahl in Klammern. Der WERT
// ist der Anzeigepfad - identisch mit data-pfad an der Zeile.
var
  P : TPair<string, Integer>;
  i : Integer;
begin
  SetLength(Result, ADateien.Count);
  i := 0;
  for P in ADateien do
  begin
    Result[i].Wert    := P.Key;
    Result[i].Anzahl  := P.Value;
    Result[i].Anzeige := Format('%s (%d)', [P.Key, P.Value]);
    Result[i].Titel   := P.Key;
    Inc(i);
  end;
  TArray.Sort<TZaehlEintrag>(Result, TComparer<TZaehlEintrag>.Construct(
    function(const A, B: TZaehlEintrag): Integer
    begin
      Result := AnsiCompareText(A.Wert, B.Wert);
    end));
end;

function RegelEintraege(const AJeKind: array of Integer;
  ARegeln: TFindingKinds; const ALang: string): TArray<TZaehlEintrag>;
// Regel-Dropdown: nach Fundzahl ABSTEIGEND (die lauteste Regel
// zuerst - der haeufigste Einstieg in einen grossen Bericht), bei
// Gleichstand nach SCA-ID. Der Wert ist die SCA-ID = data-rid.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  n    : Integer;
begin
  SetLength(Result, 0);
  n := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
    if K in ARegeln then
    begin
      Meta := TRuleCatalog.GetRule(K, ALang);
      SetLength(Result, n + 1);
      Result[n].Wert    := Meta.ID;
      Result[n].Anzahl  := AJeKind[Ord(K)];
      Result[n].Anzeige := Format('%s %s (%d)',
        [Meta.ID, Meta.Name, AJeKind[Ord(K)]]);
      Result[n].Titel   := Trim(Meta.ID + ' ' + Meta.Name);
      Inc(n);
    end;
  TArray.Sort<TZaehlEintrag>(Result, TComparer<TZaehlEintrag>.Construct(
    function(const A, B: TZaehlEintrag): Integer
    begin
      Result := B.Anzahl - A.Anzahl;
      if Result = 0 then Result := AnsiCompareText(A.Wert, B.Wert);
    end));
end;

procedure ZaehleFunde(AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, ALang: string;
  out AStat: TFundStat; out ARegeln: TFindingKinds);
// Zaehlpass ueber ALLE Funde - die Kacheln bleiben auch bei
// gekuerzter Tabelle die Wahrheit ueber den ganzen Lauf. ARegeln
// steuert zusaetzlich, welche Regel-Templates emittiert werden.
var
  F       : TLeakFinding;
  K       : TFindingKind;
  Dateien : TDictionary<string, Integer>;
  JeKind  : array[TFindingKind] of Integer;
  Pfad    : string;
  Vorher  : Integer;
begin
  AStat := Default(TFundStat);
  ARegeln := [];
  FillChar(JeKind, SizeOf(JeKind), 0);
  Dateien := TDictionary<string, Integer>.Create;
  try
    for F in AFindings do
    begin
      Inc(AStat.Gesamt);
      if F.Kind = fkFileReadError then
        Inc(AStat.Lesefehler)
      else
        Inc(AStat.Sev[F.Severity]);
      // Sprachneutral: gezaehlt wird der FindingType, kein Text -
      // GetRule ohne Overlay reicht und spart 3 Katalog-Lookups je Fund.
      if TRuleCatalog.GetRuleCanonical(F.Kind).FindingType in
        [ftVulnerability, ftSecurityHotspot] then
        Inc(AStat.Security);
      // Dateien MIT Fundzahl, geschluesselt auf dem ANZEIGE-Pfad -
      // derselbe Wert steht als data-pfad an der Zeile und ist damit
      // der Filterwert des Dropdowns (Feature-Abgleich 07.09.).
      Pfad := AnzeigePfad(F.FileName, ABaseDir);
      if not Dateien.TryGetValue(Pfad, Vorher) then Vorher := 0;
      Dateien.AddOrSetValue(Pfad, Vorher + 1);
      Inc(JeKind[F.Kind]);
      Include(ARegeln, F.Kind);
    end;
    AStat.Dateien := Dateien.Count;
    for K := Low(TFindingKind) to High(TFindingKind) do
      if K in ARegeln then Inc(AStat.Regeln);
    AStat.DateiListe := DateiEintraege(Dateien);
    AStat.RegelListe := RegelEintraege(JeKind, ARegeln, ALang);
  finally
    Dateien.Free;
  end;
end;

class function TFindingsWorkbenchExport.BuildHtml(
  AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string; AMaxRows: Integer;
  const ALang: string): string;
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    BauePage(SB, AFindings, ABaseDir, AMaxRows, ALang);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class procedure TFindingsWorkbenchExport.BauePage(ASB: TStringBuilder;
  AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string; AMaxRows: Integer; const ALang: string);
var
  SB          : TStringBuilder;
  F           : TLeakFinding;
  Stat        : TFundStat;
  Regeln      : TFindingKinds;
  K           : TFindingKind;
  Meta        : TRuleMeta;
  MaxRows     : Integer;
  RowsEmitted : Integer;
  RowsDropped : Integer;
  QuellCache  : TObjectDictionary<string, TStringList>;
  Zeile       : TFundZeile;
  Zusatz      : TStringBuilder;
  Erste       : Boolean;
begin
  if AMaxRows < 0 then
    MaxRows := V2_MAX_ROWS_DEFAULT
  else
    MaxRows := AMaxRows;

  ZaehleFunde(AFindings, ABaseDir, ALang, Stat, Regeln);

  RowsEmitted := 0;
  RowsDropped := 0;
  if (MaxRows > 0) and (Stat.Gesamt > MaxRows) then
    RowsDropped := Stat.Gesamt - MaxRows;

  // Der Rumpf appendet in den UEBERGEBENEN Builder - lokal nur als
  // Alias, damit die Emit-Zeilen unveraendert lesbar bleiben.
  SB := ASB;
  begin
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html lang="' + LowerCase(Copy(ALang, 1, 2)) + '">');
    SB.AppendLine('<head>');
    SB.AppendLine('<meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width, '
      + 'initial-scale=1">');
    SB.AppendLine('<title>' + TWorkbenchI18n.T(wtTitelFunde, ALang)
      + '</title>');
    SB.Append(SeiteStyle);
    // Anti-Blitz: die gespeicherte Theme-Wahl muss VOR dem ersten Paint
    // am <html>-Element stehen. Das grosse Skript am Body-Ende reicht
    // NICHT - bis dahin hat der @media-Block laengst nach der
    // SYSTEM-Praeferenz gemalt. Wer "light" oder "sepia" gewaehlt hat
    // und ein dunkles OS fuehrt, sah den Bericht erst dunkel aufbauen
    // und dann umkippen; mit "dark" auf hellem OS umgekehrt weiss.
    //
    // Je groesser der Bericht, desto laenger steht das falsche Thema:
    // bei einem 60-MB-Export liegen Sekunden zwischen erstem Paint und
    // dem Skript am Ende. Genau daran ist es aufgefallen.
    //
    // Der V1-Report hat diesen Block seit dem 19.08.; beim Bau der
    // V2-Seite ist er nicht mitgewandert - dieselbe Gattung Fehler wie
    // die geerbte OOM-Falle aus Charge 18, nur andersherum: hier wurde
    // eine vorhandene LOESUNG nicht mitgenommen.
    //
    // Whitelist statt Blindanwendung, damit ein korrupter
    // localStorage-Wert nicht als Attribut-Muell endet. Absichtlich
    // winzig und try/catch-gekapselt: scheitert es, gilt wieder der
    // bisherige Weg (Body-Skript + @media).
    SB.AppendLine('<script>try{var t=localStorage.getItem('
      + '"sca-v2-theme");');
    SB.AppendLine('if(["light","dark","sepia"].indexOf(t)>=0)');
    SB.AppendLine('document.documentElement.setAttribute('
      + '"data-theme",t);}catch(e){}</script>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    // IDs an allen Bereichen (Nicos Auftrag 09.09.): damit im
    // Gespraech benennbar ist, WO etwas stehen soll - "in
    // #bereich-kacheln" statt "oben rechts". Die Namen sind
    // deutsch und beschreiben den ZWECK, nicht die Optik.
    SB.AppendLine('<header class="kopf" id="bereich-seitenkopf">');
    SB.AppendLine('<h1>' + TWorkbenchI18n.T(wtTitelFunde, ALang)
      + '</h1>');
    SB.AppendLine(Format('<div class="sub">'
      + TWorkbenchI18n.T(wtUntertitelFunde, ALang) + '</div>',
      [H(TRuleCatalog.ToolName), H(TRuleCatalog.ToolVersion),
       Stat.Gesamt]));
    SB.AppendLine('</header>');
    SB.AppendLine('<main id="bereich-inhalt">');
    // REIHENFOLGE (Nicos Vorgabe 09.09.): erst die Lage, dann die
    // Werkzeuge. Ampel und Zahlen beantworten "wie steht es?", die
    // Top-Listen "wo drueckt es?" - und die Filterleiste steht direkt
    // ueber der Liste, auf die sie wirkt.
    //
    // Vorher stand die Filterleiste ganz oben, noch vor jeder Zahl:
    // der Leser bekam Werkzeuge in die Hand, bevor er wusste, wofuer.
    SB.Append(HealthUndSecurity(Stat, ALang));
    SB.Append(Dashboard(Stat, ALang));
    // Top-Listen nebeneinander; beide sind Ausschnitte der bereits
    // sortierten Auswahllisten und filtern per Klick.
    SB.AppendLine('<div class="toplisten" id="bereich-toplisten">');
    SB.Append(TopListe('topRegeln',
      TWorkbenchI18n.T(wtTopRegeln, ALang), 'regelFilter',
      Stat.RegelListe));
    SB.Append(TopListe('topDateien',
      TWorkbenchI18n.T(wtTopDateien, ALang), 'dateiFilter',
      Stat.DateiListe));
    SB.AppendLine('</div>');

    // Filterleiste (Suche, Zaehler, Reset, Thema, Dropdowns, Chips)
    // direkt ueber der Liste, auf die sie wirkt - s. Reihenfolge oben.
    SB.Append(CommandUndChips(Stat.Lesefehler, Stat, ALang));

    if RowsDropped > 0 then
      SB.AppendLine(Format('<div id="gekuerzt">'
        + TWorkbenchI18n.T(wtKuerzungsbanner, ALang) + '</div>',
        [MaxRows, RowsDropped]));

    SB.AppendLine('<div class="listwrap" id="bereich-fundliste">');
    SB.AppendLine('<table id="funde">');
    // Keine Datei-Spalte mehr: die Datei steht seit 09.09. in DERSELBEN
    // Zelle wie die Methode, zweizeilig (s. ZeileFuerFund). SIEBEN
    // Koepfe = die Zellen der tr.haupt-Zeile, Indizes 0..6: seit
    // 09.09. teilt sich der Detailtext die Zelle mit dem Regelnamen,
    // eine eigene Detail-Spalte gibt es nicht mehr.
    SB.AppendLine('<thead><tr>'
      + Kopf(SP_ZEILE, wtSpZeile, ALang)
      + Kopf(SP_METHODE, wtSpMethode, ALang)
      + Kopf(SP_SCAID, wtSpScaId, ALang)
      + Kopf(SP_REGEL, wtSpRegel, ALang)
      + Kopf(SP_TYP, wtSpTyp, ALang)
      + Kopf(SP_SEVERITY, wtSpSchweregrad, ALang)
      + Kopf(SP_KONFIDENZ, wtSpKonfidenz, ALang)
      + '</tr></thead>');

    QuellCache := TObjectDictionary<string, TStringList>.Create(
      [doOwnsValues]);
    try
      for F in AFindings do
      begin
        if (MaxRows > 0) and (RowsEmitted >= MaxRows) then Break;
        Inc(RowsEmitted);
        Zeile.Fund    := F;
        Zeile.Meta    := TRuleCatalog.GetRule(F.Kind, ALang);
        Zeile.Pfad    := AnzeigePfad(F.FileName, ABaseDir);
        Zeile.Hinweis := TFixHintResolver.FixHint(F).Description;
        Zeile.Snippet := QuellAusschnitt(QuellCache, F.FileName,
          StrToIntDef(F.LineNumber, 0), Zeile.SnippetVon);
        Zeile.Lang    := ALang;
        SB.AppendLine(ZeileFuerFund(Zeile));
      end;
    finally
      QuellCache.Free;
    end;

    SB.AppendLine('</table>');
    SB.AppendLine('</div>');
    // Zwei Leer-Botschaften: ein Lauf OHNE Funde ist kein
    // Filter-Problem - 'Keine Treffer + Reset' saehe dort aus wie
    // eine verunglueckte Suche (Review 07.09.). Das JS waehlt.
    SB.AppendLine('<div id="leer">'
      + '<span id="leer-suche">'
      + TWorkbenchI18n.T(wtKeineTreffer, ALang)
      + ' <button id="leer-reset" onclick="filterReset()">'
      + TWorkbenchI18n.T(wtFilterReset, ALang) + '</button></span>'
      + '<span id="leer-lauf" style="display:none">'
      + TWorkbenchI18n.T(wtKeineFundeImLauf, ALang) + '</span></div>');

    // Regel-Templates NACH der Tabelle, EINMAL je vorkommender Regel -
    // hier liegt die Deduplikation gegenueber der V1 (s. Unit-Kopf).
    // Im selben Durchgang entsteht die Sucherweiterung: was zur Suche
    // gehoert, aber nicht in der Fundzeile steht (s. SuchZusatzRegel).
    Zusatz := TStringBuilder.Create;
    try
      Zusatz.Append('<script>var RSUCH={');
      Erste := True;
      for K := Low(TFindingKind) to High(TFindingKind) do
        if K in Regeln then
        begin
          Meta := TRuleCatalog.GetRule(K, ALang);
          SB.Append(TemplateFuerRegel(K, Meta, ALang));
          if not Erste then Zusatz.Append(',');
          Erste := False;
          // Die Anfuehrungszeichen kommen HIER dazu: JsonForScript
          // escapet nur den Inhalt, es klammert ihn nicht. Ohne diese
          // beiden Paare stuende dort {SCA001:MemoryLeak } - kein
          // gueltiges JavaScript, und die ganze Tabelle waere tot.
          Zusatz.Append('"');
          Zusatz.Append(TExporterHtml.JsonForScript(Meta.ID));
          Zusatz.Append('":"');
          Zusatz.Append(TExporterHtml.JsonForScript(
            SuchZusatzRegel(K, Meta)));
          Zusatz.Append('"');
        end;
      Zusatz.AppendLine('};</script>');
      SB.Append(Zusatz.ToString);
    finally
      Zusatz.Free;
    end;

    SB.AppendLine('</main>');
    // wtDrawerAriaFunde, NICHT wtDrawerAria: hier stehen FUND-Details,
    // nicht die Detektor-Details der Katalogseite (der erste Wurf griff
    // zum Katalog-Text und machte den Scaffolding-Test rot).
    SB.AppendLine('<aside id="drawer" aria-label="'
      + TWorkbenchI18n.T(wtDrawerAriaFunde, ALang) + '">');
    SB.AppendLine('<button id="drawer-schliessen" aria-label="'
      + TWorkbenchI18n.T(wtDrawerSchliessen, ALang)
      + '" onclick="schliesseDrawer()">&times;</button>');
    SB.AppendLine('<div id="drawer-inhalt"></div>');
    SB.AppendLine('</aside>');
    SB.Append(SeitenJs(ALang));
    SB.AppendLine('</body></html>');
  end;
end;

end.
