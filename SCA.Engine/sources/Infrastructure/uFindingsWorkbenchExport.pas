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
  SP_METHODE  = 1;
  SP_SCAID    = 2;
  SP_REGEL    = 3;
  SP_TYP      = 4;
  SP_SEVERITY = 5;
  SP_KONFIDENZ = 6;
  SP_DETAIL   = 7;
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
    Snippet : string;      // fertiges Quell-Ausschnitt-Markup
    Lang    : string;
  end;

  // Ein Eintrag der Auswahllisten (Datei- und Regel-Dropdown).
  TZaehlEintrag = record
    Wert    : string;    // Filterwert: Anzeigepfad bzw. SCA-ID
    Anzeige : string;    // Beschriftung inkl. Fundzahl
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
// in ATTRIBUTEN (data-search, data-hinweis) waere das Datenmuell
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
  const ADatei: string; AZeile: Integer): string;
// Quellcode-Ausschnitt um die Fundzeile (V1-Feature, groesste Luecke
// der V2 laut Feature-Abgleich). Das MARKUP kommt aus dem geteilten
// TExporterHtml.BuildCodeSnippet - eine zweite Implementierung
// haette zwei Berichte mit verschieden aussehenden Ausschnitten
// derselben Stelle ergeben.
// Der Cache haelt jede Datei EINMAL: ein Bericht hat typisch viele
// Funde je Datei, und ohne Cache laese der Export dieselbe Datei
// dutzendfach. Nicht lesbare Dateien werden als nil gemerkt, damit
// ein fehlgeschlagener Zugriff nicht bei jedem Fund erneut versucht
// wird (Bericht ueber geloeschten Code ist der Normalfall).
var
  Lines : TStringList;
begin
  Result := '';
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
  Result := TExporterHtml.BuildCodeSnippet(Lines, AZeile,
    SNIPPET_KONTEXT);
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
    Regel('th', 'background:#252d36;');
    // ACHTUNG Spezifitaet: der Hover liegt seit dem Zwei-Zeilen-Umbau
    // auf '#funde tbody:hover tr' (ID + 2 Elemente). Eine Dark-Regel
    // auf 'tr.haupt:hover' verliert dagegen und die Zeile bliebe im
    // dunklen Thema hellblau - beim Nachpruefen aufgefallen.
    Regel('#funde tbody:hover tr', 'background:#232c36;');
    Regel('tbody.gewaehlt tr', 'background:#26333f;');
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
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SeiteStyle: string;
// Workbench-Kern + Seitenspezifisches - Aufbau und Klassen bewusst
// deckungsgleich mit der Katalogseite ("gleich anfuehlen").
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<style>');
    SB.Append(TWorkbenchStyle.BasisCss);
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
    // ---- Liste --------------------------------------------------------
    SB.AppendLine('.listwrap{background:var(--karte);border:1px solid '
      + 'var(--rand);border-radius:8px;overflow:auto;'
      + 'box-shadow:0 1px 2px rgba(16,32,48,0.06);}');
    SB.AppendLine('table{border-collapse:collapse;width:100%;}');
    SB.AppendLine('th,td{padding:7px 10px;text-align:left;'
      + 'vertical-align:top;font-size:0.92em;border:0;}');
    SB.AppendLine('th{background:#eef2f6;cursor:pointer;position:sticky;'
      + 'top:0;white-space:nowrap;user-select:none;'
      + 'box-shadow:inset 0 -1px 0 var(--rand);}');
    SB.AppendLine('th .pfeil{color:var(--akzent);font-size:0.8em;'
      + 'margin-left:3px;}');
    SB.AppendLine('tr.haupt{border-top:1px solid var(--rand);'
      + 'cursor:pointer;}');
    SB.AppendLine('tr.datei{cursor:pointer;}');
    // Hover + Auswahl liegen auf dem TBODY, damit Haupt- und
    // Datei-Zeile eines Fundes als EIN Block wirken.
    SB.AppendLine('#funde tbody:hover tr{background:#f2f6fb;}');
    SB.AppendLine('tbody.gewaehlt tr{background:#e8f0fa;}');
    SB.AppendLine('tbody.gewaehlt tr.haupt{'
      + 'box-shadow:inset 3px 0 0 var(--akzent);}');
    // Datei-Zeile "Name; voller Pfad": Ellipse statt Umbruch -
    // max-width:0 laesst die uebrigen Zellen die Breite bestimmen
    // (Tabellen-Ellipsis-Muster), title zeigt den vollen Pfad.
    SB.AppendLine('td.pfadzeile{max-width:0;overflow:hidden;'
      + 'text-overflow:ellipsis;white-space:nowrap;'
      + 'font-family:Consolas,monospace;font-size:0.85em;'
      + 'color:var(--dezent);padding-top:2px;}');
    SB.AppendLine('td.id{font-family:Consolas,monospace;font-weight:600;'
      + 'white-space:nowrap;}');
    SB.AppendLine('td.num{text-align:right;font-variant-numeric:'
      + 'tabular-nums;color:var(--dezent);}');
    // ---- Quell-Ausschnitt (Markup-Vertrag mit V1) ----------------------
    // Die Klassennamen kommen aus TExporterHtml.BuildCodeSnippet und
    // sind damit zwischen V1 und V2 geteilt - hier nur die Optik.
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
    SB.AppendLine('#drawer{position:fixed;top:0;right:0;height:100%;'
      + 'width:40%;min-width:340px;max-width:44em;background:'
      + 'var(--karte);border-left:1px solid var(--rand);'
      + 'box-shadow:-4px 0 16px rgba(16,32,48,0.12);'
      + 'transform:translateX(102%);transition:transform 180ms ease;'
      + 'overflow-y:auto;padding:14px 18px;z-index:10;}');
    SB.AppendLine('#drawer.offen{transform:translateX(0);}');
    SB.AppendLine('#drawer h2{margin:0 0 2px 0;font-size:1.12em;}');
    SB.AppendLine('#drawer h3{margin:14px 0 4px 0;font-size:0.98em;}');
    SB.AppendLine('#drawer-schliessen{float:right;border:1px solid '
      + 'var(--rand);background:var(--karte);border-radius:6px;'
      + 'cursor:pointer;font-size:1em;padding:2px 9px;}');
    SB.AppendLine('.drawer-status{margin:6px 0 4px 0;display:flex;'
      + 'gap:6px;flex-wrap:wrap;}');
    SB.AppendLine('.drawer-ort{color:var(--dezent);font-size:0.88em;'
      + 'font-family:Consolas,monospace;word-break:break-all;}');
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
    SB.AppendLine(':root[data-theme="sepia"] th{background:#efe3c6;}');
    // dieselbe Spezifitaets-Falle wie im Dunkel-Thema (s. dort).
    SB.AppendLine(':root[data-theme="sepia"] #funde tbody:hover tr{'
      + 'background:#f0e4c8;}');
    SB.AppendLine(':root[data-theme="sepia"] tbody.gewaehlt tr{'
      + 'background:#eaddbe;}');
    SB.AppendLine(':root[data-theme="sepia"] .kbd{background:#efe3c6;}');
    SB.AppendLine(':root[data-theme="sepia"] .tl-bar{'
      + 'background:#e8dcc0;}');
    SB.AppendLine(':root[data-theme="sepia"] .topliste li:hover{'
      + 'background:#f0e4c8;}');
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
    SB.AppendLine('<div class="cmdbar">');
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
    SB.AppendLine('<div class="cmdbar auswahl">');
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
        + '<span class="tl-name">%s</span>'
        + '<span class="tl-bar"><span class="tl-fill" '
        + 'style="width:%d%%"></span></span>'
        + '<span class="tl-zahl">%d</span></li>',
        [AZielDropdown, H(Liste[i].Wert),
         H(Liste[i].Wert), Breit, Liste[i].Anzahl]));
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
    SB.AppendLine('<div class="panels">');
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
    SB.AppendLine('<div class="dash">');
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
    SB.AppendLine('  if (td.dataset.sort !== undefined) '
      + 'return parseInt(td.dataset.sort, 10);');
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
    SB.AppendLine('function suche() {');
    SB.AppendLine('  var q = document.getElementById("suche")'
      + '.value.toLowerCase();');
    SB.AppendLine('  var datei = auswahl("dateiFilter");');
    SB.AppendLine('  var regel = auswahl("regelFilter");');
    SB.AppendLine('  var tbs = alleTbodies(), sichtbar = 0;');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++) {');
    SB.AppendLine('    var hit = (q === "" || '
      + 'tbs[i].dataset.search.indexOf(q) >= 0) && passtChips(tbs[i])');
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
    SB.AppendLine('function fundKopf(tb) {');
    SB.AppendLine('  var z = tb.rows[0];');
    SB.AppendLine('  var kopf = document.createElement("div");');
    SB.AppendLine('  var ort = document.createElement("div");');
    SB.AppendLine('  ort.className = "drawer-ort";');
    SB.AppendLine('  // Pfad aus data-pfad (die Datei hat keine Zelle');
    SB.AppendLine('  // in der Hauptzeile mehr), Zeile/Methode/Detail');
    SB.AppendLine('  // aus den Zellen 0/1/7 der tr.haupt.');
    SB.AppendLine('  var t = (tb.dataset.pfad || "") + ":" '
      + '+ z.cells[' + IntToStr(SP_ZEILE) + '].textContent;');
    SB.AppendLine('  if (z.cells[' + IntToStr(SP_METHODE)
      + '].textContent) t += " " + String.fromCharCode(183) + " " '
      + '+ z.cells[' + IntToStr(SP_METHODE) + '].textContent;');
    SB.AppendLine('  ort.textContent = t;');
    SB.AppendLine('  kopf.appendChild(ort);');
    SB.AppendLine('  var det = z.cells[' + IntToStr(SP_DETAIL)
      + '].textContent;');
    SB.AppendLine('  if (det) {');
    SB.AppendLine('    var p = document.createElement("p");');
    SB.AppendLine('    p.textContent = det;');
    SB.AppendLine('    kopf.appendChild(p);');
    SB.AppendLine('  }');
    // Quell-Ausschnitt: liegt als unsichtbare tr.snippet beim Fund
    // und wird in den Drawer geklont (nicht verschoben - die Zeile
    // bleibt Datenquelle fuer das naechste Oeffnen).
    SB.AppendLine('  var sn = tb.querySelector("tr.snippet '
      + '.src-snippet");');
    SB.AppendLine('  if (sn) kopf.appendChild(sn.cloneNode(true));');
    SB.AppendLine('  if (tb.dataset.hinweis) {');
    SB.AppendLine('    var h3 = document.createElement("h3");');
    SB.AppendLine('    h3.textContent = "'
      + TWorkbenchI18n.TJs(wtHinweisZuFund, ALang) + '";');
    SB.AppendLine('    kopf.appendChild(h3);');
    SB.AppendLine('    var hp = document.createElement("p");');
    SB.AppendLine('    hp.textContent = tb.dataset.hinweis;');
    SB.AppendLine('    kopf.appendChild(hp);');
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
    SB.AppendLine('</script>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SuchBlobFund(F: TLeakFinding; const AMeta: TRuleMeta;
  const APfad, ASevTxt, ALang: string): string;
// Suchbasis je Fund, lowercase. AnsiLowerCase, NICHT LowerCase - die
// JS-Seite senkt Unicode-korrekt (toLowerCase); mit LowerCase blieben
// grosse Umlaute im Blob stehen (Chargen-Review 06.09., Major).
// Die Severity-/Konfidenz-Woerter stehen in der SEITENSPRACHE im Blob:
// wonach der Leser sieht, danach sucht er auch.
begin
  Result := AnsiLowerCase(Einzeilig(
    APfad + ' ' + F.LineNumber + ' ' + F.MethodName + ' '
    + F.MissingVar + ' ' + AMeta.ID + ' ' + AMeta.Name + ' '
    + KIND_META[F.Kind].Name + ' ' + TypText(AMeta.FindingType) + ' '
    + ASevTxt + ' '
    + TWorkbenchI18n.T(CONF_KEY[F.Confidence], ALang) + ' '
    + JoinArr(AMeta.CWE, ' ') + ' ' + JoinArr(AMeta.Tags, ' ')));
end;

function Snippetblock(const ASnippet: string): string;
// Traegerzeile fuer den Quell-Ausschnitt. Eine eigene, dauerhaft
// unsichtbare tr haelt das tbody-Modell intakt (nur tr-Kinder) -
// ein <template> direkt im tbody waere nach der HTML-Parser-Regel
// fuer Tabellen aus der Tabelle herausgehoben worden.
begin
  if ASnippet = '' then Exit('');
  Result := '<tr class="snippet"><td colspan="8">' + ASnippet
    + '</td></tr>'#13#10;
end;

function ZeileFuerFund(const Z: TFundZeile): string;
// Ein tbody je Fund, seit dem Nutzerauftrag 07.09. ZWEI Zeilen:
//   tr.haupt: Zeile, Methode, SCA-ID, Regel, Typ, Schweregrad,
//             Konfidenz, Detail (fundKopf() liest Zellen 0/1/7)
//   tr.datei: colspan-8-Zeile "Dateiname; voller Pfad" mit
//             CSS-Ellipse (title-Attribut traegt den vollen Pfad).
// Die Datei stand vorher als umbrechende Schmalspalte VOR der Zeile -
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
    Format('<tbody data-rid="%s" data-search="%s" data-typ="%s" '
      + 'data-sev="%d" data-konf="%d" data-pfad="%s"%s>'#13#10,
      [H(Z.Meta.ID),
       H(SuchBlobFund(Z.Fund, Z.Meta, Z.Pfad, SevTxt, Z.Lang)),
       TypCss(Z.Meta.FindingType), SevRang, Ord(Z.Fund.Confidence),
       H(Z.Pfad), HinweisAttr])
    + '<tr class="haupt" tabindex="0" '
    + 'onclick="oeffneDrawer(this.parentNode)">'
    + Format('<td class="num" data-sort="%d">%s</td>',
        [StrToIntDef(Z.Fund.LineNumber, 0), H(Z.Fund.LineNumber)])
    + '<td>' + H(Z.Fund.MethodName) + '</td>'
    + '<td class="id">' + H(Z.Meta.ID) + '</td>'
    + '<td>' + H(Z.Meta.Name) + '</td>'
    + Format('<td><span class="badge typ %s">%s</span></td>',
        [TypCss(Z.Meta.FindingType), H(TypText(Z.Meta.FindingType))])
    + Format('<td data-sort="%d">%s</td>', [SevRang, SevBadge])
    + Format('<td data-sort="%d"><span class="badge konf">%s'
        + '</span></td>', [Ord(Z.Fund.Confidence),
           TWorkbenchI18n.T(CONF_KEY[Z.Fund.Confidence], Z.Lang)])
    + '<td>' + H(Z.Fund.MissingVar) + '</td>'
    + '</tr>'#13#10
    + '<tr class="datei" onclick="oeffneDrawer(this.parentNode)">'
    + '<td class="pfadzeile" colspan="8" title="' + H(Z.Pfad) + '">'
    + DateiZeile + '</td>'
    + '</tr>'#13#10
    // Der Quell-Ausschnitt liegt als unsichtbares TEMPLATE bei der
    // Zeile, nicht in einem Attribut: er ist fertiges Markup und
    // muesste sonst doppelt escaped und im JS wieder aufgeloest
    // werden. Der Drawer klont ihn.
    + Snippetblock(Z.Snippet)
    + '</tbody>';
end;

function TemplateFuerRegel(K: TFindingKind; const AMeta: TRuleMeta;
  ASev: TLeakSeverity; const ALang: string): string;
// Regel-Doku als geteiltes Template - EINMAL je vorkommender Regel
// (der Deduplikations-Kern der V2, s. Unit-Kopf). Inhalt und Optik
// sind der Katalog-Drawer; ASev ist der Regel-Default (die konkrete
// Fund-Severity steht in der Zeile und im Fund-Kopf des Drawers).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('<template id="tpl-%s">', [H(AMeta.ID)]));
    SB.AppendLine('<h2><span class="mono">' + H(AMeta.ID) + '</span> '
      + H(AMeta.Name) + '</h2>');
    SB.AppendLine('<div class="drawer-status">'
      + Format('<span class="badge typ %s">%s</span>',
          [TypCss(AMeta.FindingType), H(TypText(AMeta.FindingType))])
      + Format('<span class="badge sev-%s">'
          + TWorkbenchI18n.T(wtRegelDefault, ALang) + '</span>',
          [SEV_CSS[ASev], TWorkbenchI18n.T(SEV_KEY[ASev], ALang)])
      + '</div>');
    SB.AppendLine('<h3>' + TWorkbenchI18n.T(wtWasWirdErkannt, ALang)
      + '</h3>');
    SB.AppendLine('<p>' + H(AMeta.ShortDescription) + '</p>');
    if AMeta.FullDescription <> '' then
    begin
      SB.AppendLine('<h3>' + TWorkbenchI18n.T(wtWarumRelevant, ALang)
        + '</h3>');
      SB.AppendLine('<p>' + H(AMeta.FullDescription) + '</p>');
    end;
    if (AMeta.BadExample <> '') or (AMeta.GoodExample <> '') then
    begin
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
      SB.AppendLine('</div>');
    end;
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
begin
  Result := 'sca-funde-v2.html';
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
  Pfad        : string;
  MaxRows     : Integer;
  RowsEmitted : Integer;
  RowsDropped : Integer;
  QuellCache  : TObjectDictionary<string, TStringList>;
  Zeile       : TFundZeile;
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
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.AppendLine('<header class="kopf">');
    SB.AppendLine('<h1>' + TWorkbenchI18n.T(wtTitelFunde, ALang)
      + '</h1>');
    SB.AppendLine(Format('<div class="sub">'
      + TWorkbenchI18n.T(wtUntertitelFunde, ALang) + '</div>',
      [H(TRuleCatalog.ToolName), H(TRuleCatalog.ToolVersion),
       Stat.Gesamt]));
    SB.AppendLine('</header>');
    SB.AppendLine('<main>');
    SB.Append(CommandUndChips(Stat.Lesefehler, Stat, ALang));
    SB.Append(Dashboard(Stat, ALang));
    SB.Append(HealthUndSecurity(Stat, ALang));
    // Top-Listen nebeneinander; beide sind Ausschnitte der bereits
    // sortierten Auswahllisten und filtern per Klick.
    SB.AppendLine('<div class="toplisten">');
    SB.Append(TopListe('topRegeln',
      TWorkbenchI18n.T(wtTopRegeln, ALang), 'regelFilter',
      Stat.RegelListe));
    SB.Append(TopListe('topDateien',
      TWorkbenchI18n.T(wtTopDateien, ALang), 'dateiFilter',
      Stat.DateiListe));
    SB.AppendLine('</div>');

    if RowsDropped > 0 then
      SB.AppendLine(Format('<div id="gekuerzt">'
        + TWorkbenchI18n.T(wtKuerzungsbanner, ALang) + '</div>',
        [MaxRows, RowsDropped]));

    SB.AppendLine('<div class="listwrap">');
    SB.AppendLine('<table id="funde">');
    // Keine Datei-Spalte mehr: die Datei steht als eigene Zeile unter
    // Zeile+Methode (tr.datei, s. ZeileFuerFund). Acht Koepfe = die
    // Zellen der tr.haupt-Zeile, Indizes 0..7.
    SB.AppendLine('<thead><tr>'
      + Kopf(SP_ZEILE, wtSpZeile, ALang)
      + Kopf(SP_METHODE, wtSpMethode, ALang)
      + Kopf(SP_SCAID, wtSpScaId, ALang)
      + Kopf(SP_REGEL, wtSpRegel, ALang)
      + Kopf(SP_TYP, wtSpTyp, ALang)
      + Kopf(SP_SEVERITY, wtSpSchweregrad, ALang)
      + Kopf(SP_KONFIDENZ, wtSpKonfidenz, ALang)
      + Kopf(SP_DETAIL, wtSpDetail, ALang)
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
          StrToIntDef(F.LineNumber, 0));
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
    for K := Low(TFindingKind) to High(TFindingKind) do
      if K in Regeln then
      begin
        Meta := TRuleCatalog.GetRule(K, ALang);
        SB.Append(TemplateFuerRegel(K, Meta, KindDefaultSeverity(K),
          ALang));
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
