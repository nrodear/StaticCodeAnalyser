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

type
  // Kennzahlen der Dashboard-Kacheln - ein Zaehlpass ueber ALLE Funde
  // (unabhaengig vom Zeilenbudget der Tabelle).
  TFundStat = record
    Gesamt     : Integer;
    Sev        : array[TLeakSeverity] of Integer;
    Lesefehler : Integer;
    Security   : Integer;  // Funde von Vulnerability-/Hotspot-Regeln
    Dateien    : Integer;  // verschiedene Dateien
    Regeln     : Integer;  // verschiedene Regeln (Kinds)
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

function CommandUndChips(ALesefehler: Integer;
  const ALang: string): string;
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
    SB.AppendLine('function suche() {');
    SB.AppendLine('  var q = document.getElementById("suche")'
      + '.value.toLowerCase();');
    SB.AppendLine('  var tbs = alleTbodies(), sichtbar = 0;');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++) {');
    SB.AppendLine('    var hit = (q === "" || '
      + 'tbs[i].dataset.search.indexOf(q) >= 0) && passtChips(tbs[i]);');
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
    SB.AppendLine('  var aktiv = q !== "";');
    SB.AppendLine('  for (var g2 in aktiveFilter) '
      + 'if (aktiveFilter[g2].length) aktiv = true;');
    SB.AppendLine('  document.getElementById("reset").style.display =');
    SB.AppendLine('    aktiv ? "inline" : "none";');
    SB.AppendLine('  if (gewaehlt && gewaehlt.style.display '
      + '=== "none") schliesseDrawer();');
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
      + '+ z.cells[0].textContent;');
    SB.AppendLine('  if (z.cells[1].textContent) t += " " '
      + '+ String.fromCharCode(183) + " " + z.cells[1].textContent;');
    SB.AppendLine('  ort.textContent = t;');
    SB.AppendLine('  kopf.appendChild(ort);');
    SB.AppendLine('  var det = z.cells[7].textContent;');
    SB.AppendLine('  if (det) {');
    SB.AppendLine('    var p = document.createElement("p");');
    SB.AppendLine('    p.textContent = det;');
    SB.AppendLine('    kopf.appendChild(p);');
    SB.AppendLine('  }');
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
    SB.AppendLine('window.addEventListener("hashchange", deepLink);');
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

function ZeileFuerFund(F: TLeakFinding; const AMeta: TRuleMeta;
  const APfad, AHinweis, ALang: string): string;
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
  if F.Kind = fkFileReadError then
  begin
    // Lesefehler: kein Schweregrad-Wort der Skala; eigener Rang hinter
    // den Hinweisen, neutraler Badge (wie die readerr-Politik der V1).
    SevTxt   := TWorkbenchI18n.T(wtLesefehler, ALang);
    SevBadge := Format('<span class="badge typ ferr">%s</span>',
      [SevTxt]);
    SevRang  := SEV_RANG_LESEFEHLER;
  end
  else
  begin
    SevTxt   := TWorkbenchI18n.T(SEV_KEY[F.Severity], ALang);
    SevBadge := Format('<span class="badge sev-%s">%s</span>',
      [SEV_CSS[F.Severity], SevTxt]);
    SevRang  := Ord(F.Severity);
  end;
  if AHinweis <> '' then
    HinweisAttr := Format(' data-hinweis="%s"',
      [H(Einzeilig(AHinweis))])
  else
    HinweisAttr := '';
  // "Dateiname; voller Pfad" - das Doppel entfaellt, wenn der Fund
  // ohnehin nur den Basisnamen traegt. ExtractFileName laeuft auf dem
  // ORIGINAL-Pfad (Windows-Trenner), nicht auf dem Anzeige-Pfad.
  DateiName := ExtractFileName(F.FileName);
  if APfad = DateiName then
    DateiZeile := H(DateiName)
  else
    DateiZeile := H(DateiName) + '; ' + H(APfad);
  Result :=
    Format('<tbody data-rid="%s" data-search="%s" data-typ="%s" '
      + 'data-sev="%d" data-konf="%d" data-pfad="%s"%s>'#13#10,
      [H(AMeta.ID), H(SuchBlobFund(F, AMeta, APfad, SevTxt, ALang)),
       TypCss(AMeta.FindingType), SevRang, Ord(F.Confidence),
       H(APfad), HinweisAttr])
    + '<tr class="haupt" tabindex="0" '
    + 'onclick="oeffneDrawer(this.parentNode)">'
    + Format('<td class="num" data-sort="%d">%s</td>',
        [StrToIntDef(F.LineNumber, 0), H(F.LineNumber)])
    + '<td>' + H(F.MethodName) + '</td>'
    + '<td class="id">' + H(AMeta.ID) + '</td>'
    + '<td>' + H(AMeta.Name) + '</td>'
    + Format('<td><span class="badge typ %s">%s</span></td>',
        [TypCss(AMeta.FindingType), H(TypText(AMeta.FindingType))])
    + Format('<td data-sort="%d">%s</td>', [SevRang, SevBadge])
    + Format('<td data-sort="%d"><span class="badge konf">%s'
        + '</span></td>', [Ord(F.Confidence),
                           TWorkbenchI18n.T(CONF_KEY[F.Confidence], ALang)])
    + '<td>' + H(F.MissingVar) + '</td>'
    + '</tr>'#13#10
    + '<tr class="datei" onclick="oeffneDrawer(this.parentNode)">'
    + '<td class="pfadzeile" colspan="8" title="' + H(APfad) + '">'
    + DateiZeile + '</td>'
    + '</tr>'#13#10'</tbody>';
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

procedure ZaehleFunde(AFindings: TObjectList<TLeakFinding>;
  out AStat: TFundStat; out ARegeln: TFindingKinds);
// Zaehlpass ueber ALLE Funde - die Kacheln bleiben auch bei
// gekuerzter Tabelle die Wahrheit ueber den ganzen Lauf. ARegeln
// steuert zusaetzlich, welche Regel-Templates emittiert werden.
var
  F       : TLeakFinding;
  K       : TFindingKind;
  Dateien : TDictionary<string, Boolean>;
begin
  AStat := Default(TFundStat);
  ARegeln := [];
  Dateien := TDictionary<string, Boolean>.Create;
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
      Dateien.AddOrSetValue(AnsiLowerCase(F.FileName), True);
      Include(ARegeln, F.Kind);
    end;
    AStat.Dateien := Dateien.Count;
    for K := Low(TFindingKind) to High(TFindingKind) do
      if K in ARegeln then Inc(AStat.Regeln);
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
begin
  if AMaxRows < 0 then
    MaxRows := V2_MAX_ROWS_DEFAULT
  else
    MaxRows := AMaxRows;

  ZaehleFunde(AFindings, Stat, Regeln);

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
    SB.Append(CommandUndChips(Stat.Lesefehler, ALang));
    SB.Append(Dashboard(Stat, ALang));

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
      + Kopf(0, wtSpZeile, ALang)  + Kopf(1, wtSpMethode, ALang)
      + Kopf(2, wtSpScaId, ALang)  + Kopf(3, wtSpRegel, ALang)
      + Kopf(4, wtSpTyp, ALang)    + Kopf(5, wtSpSchweregrad, ALang)
      + Kopf(6, wtSpKonfidenz, ALang) + Kopf(7, wtSpDetail, ALang)
      + '</tr></thead>');

    for F in AFindings do
    begin
      if (MaxRows > 0) and (RowsEmitted >= MaxRows) then Break;
      Inc(RowsEmitted);
      Meta := TRuleCatalog.GetRule(F.Kind, ALang);
      Pfad := AnzeigePfad(F.FileName, ABaseDir);
      SB.AppendLine(ZeileFuerFund(F, Meta, Pfad,
        TFixHintResolver.FixHint(F).Description, ALang));
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
