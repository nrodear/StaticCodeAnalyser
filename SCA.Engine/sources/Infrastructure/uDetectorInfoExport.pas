unit uDetectorInfoExport;

// "Detector Info": alle Regeln des Katalogs als eigenstaendige, offline
// funktionierende HTML-Seite - seit 07.09. als ROLLENORIENTIERTE
// WORKBENCH nach Nicos UI-Konzept (zwei PDFs, 06./07.09.):
// Rollen-Karten -> Search-Command-Bar (Strg+K, Trefferzaehler,
// Empty-State) -> Filter-Chips (Typ/Schweregrad/Konfidenz/Profil) ->
// Dashboard-Kennzahlen -> Regel-Liste mit Badges -> Detail-DRAWER
// rechts (statt aufgeklappter Tabellenzeile): Warum?, Vorher/Nachher-
// Codekarten mit Copy, noinspection- und Kalibrierungs-Karte, CWE/
// Tags/Unit. Tastatur: Strg+K, Pfeil auf/ab, Enter, Esc; Deep-Link
// #SCA003 oeffnet den Detektor direkt.
//
// BEWUSST NICHT umgesetzt (braucht IDE-Integration, im Konzept als
// optional gefuehrt): "Fix anwenden", "Zur Codezeile", "Im Editor
// oeffnen", "Alle gleichen Treffer", Syntax-Highlighting. Copy-Buttons
// nutzen einen execCommand-Fallback, weil navigator.clipboard unter
// file:// kein Secure-Context ist.
//
// SPRACHE: die Seite ist bewusst DEUTSCH und sprachfix - Chrome-Texte
// (Titel, Spalten, Suchfeld) stehen als Konstanten hier, die Regeltexte
// kommen aus GetRule(K, 'de') mit dem dokumentierten Feld-Rueckfall auf
// Englisch (das DE-Overlay traegt Name + Kurzbeschreibung; die
// Langbeschreibungen und die Vorher/Nachher-Beispiele existieren bisher
// nur englisch). BEWUSST KEIN _(): das Artefakt soll nicht mit der
// App-Sprache kippen. SPAETER laut Nutzer-Backlog EN/FR - dann wird
// die Sprache hier parametrisiert; bis dahin ist 'de' der einzige
// Aufrufwert.
//
// TECHNIK: ein <tbody> je Regel (EINE sichtbare Zeile; die Detaildaten
// liegen als nicht gerendertes <template id="tpl-SCAxxx"> daneben und
// werden vom Drawer-JS geklont). Sortierung ueber data-sort bzw.
// Zellentext, Suche + Chips ueber vorgebaute data-Attribute je Regel
// (data-search lowercase inkl. aller Detailtexte). Kein CDN, kein
// externes Asset - die Datei funktioniert vom Dateisystem.

interface

uses
  System.SysUtils, System.Classes,
  uSCAConsts, uRuleCatalog;

type
  TDetectorInfoExport = class
  public
    // Baut die komplette Seite als einen String. ALang ist die
    // Overlay-Sprache der Regeltexte ('de'; leere Overlay-Felder fallen
    // je Feld auf Englisch zurueck - Vertrag von TRuleCatalog.GetRule).
    class function BuildHtml(const ALang: string): string; static;
    // Schreibt BuildHtml als UTF-8 mit BOM (Konvention aller Exporte).
    class procedure WriteToFile(const AFileName, ALang: string); static;
    // Vorschlag fuer den Save-Dialog.
    class function DefaultFileName: string; static;
  end;

implementation

// noinspection-file DuplicateString, StringConcatInLoop, InsecureCryptoAlgorithm, LargeClass, LongMethod
// Ein HTML-Generator wiederholt Tags ('<td>', '</div>') bauartbedingt -
// eine Konstante je Tag machte den Aufbau unlesbarer, nicht sicherer
// (dieselbe Lage wie im grossen Findings-Report uExportHtml).
// StringConcatInLoop: JoinArr verkettet Tags/CWE-Listen mit maximal
// einer Handvoll Elementen - kein Hot-Path. InsecureCryptoAlgorithm:
// SCA162 haelt den deutschen ARTIKEL 'des' im Rollen-/Hinweistext fuer
// den DES-Algorithmus - reiner Fliesstext, kein Kryptobezug
// (Detektor-Notiz in HowTo_Meilensteine). LargeClass/LongMethod: die
// Seitenbausteine (Kopf, Drawer-JS) sind zusammenhaengende
// Markup-Bloecke - zerschnitten wuerde nur der Lesefluss.

uses
  uExportHtml,     // TExporterHtml.HtmlEscape - keine dritte Escape-Kopie
  uExport,         // TExporter.SaveUtf8WithBom - EIN Ort fuer die BOM-Politik
  uWorkbenchStyle; // geteilter CSS-Kern beider HTML-Exporte (07.09.)

const
  // Anzeige-Woerter der Seite (sprachfix deutsch, s. Unit-Kopf).
  SEV_TEXT  : array[TLeakSeverity] of string =
    ('Fehler', 'Warnung', 'Hinweis');
  SEV_CSS   : array[TLeakSeverity] of string = ('err', 'warn', 'hint');
  CONF_TEXT : array[TFindingConfidence] of string =
    ('niedrig', 'mittel', 'hoch');   // Enum-Ordnung fcLow, fcMedium, fcHigh

type
  // Kennzahlen des Dashboards - ein Zaehlpass ueber alle Kinds.
  TKatalogStat = record
    Gesamt   : Integer;
    Sev      : array[TLeakSeverity] of Integer;
    Security : Integer;   // Vulnerability + Security Hotspot
    MitCwe   : Integer;
    Aktiv    : Integer;   // im Default-Profil an
  end;

  // Alles, was Zeile, Suchblob und Drawer-Template einer Regel
  // brauchen - EIN Parameter statt sieben (Selbstscan SCA013).
  TRegelDaten = record
    Meta      : TRuleMeta;
    K         : TFindingKind;
    Sev       : TLeakSeverity;
    Conf      : TFindingConfidence;
    InDefault : Boolean;
    ProfilTxt : string;
    Tags      : string;
  end;

function TypText(T: TFindingType): string;
// Sonar-Typbegriffe bleiben englische Fachbegriffe (wie im Grid).
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
// Badge-Klasse je Typ; Security-Typen bekommen die Shield-Optik.
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

function ChipListe(const A: TArray<string>; const ACss: string): string;
// Kleine Chips (Tags, CWE). Leeres Array -> leerer String.
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(A) do
    Result := Result + '<span class="chip ' + ACss + '">' + H(A[i])
      + '</span>';
end;

function SeiteStyle: string;
// Komplettes CSS: ruhige helle Flaechen, Karten mit dezenten Schatten,
// Badges statt Vollflaechen, Monospace fuer ID/noinspection/Config,
// sichtbare Focus-Ringe, Drawer rechts (mobil Vollbild).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<style>');
    // Geteilter Workbench-Kern (Tokens, Kopf, Badges/Pills/Chips,
    // Kacheln, Codekarten) - danach NUR noch Seitenspezifisches.
    SB.Append(TWorkbenchStyle.BasisCss);
    SB.AppendLine('main{padding:14px 20px;}');
    // ---- Rollen-Karten ------------------------------------------------
    SB.AppendLine('.rollen{margin:0 0 12px 0;}');
    SB.AppendLine('.rollen summary{cursor:pointer;font-size:1.02em;'
      + 'padding:6px 2px;user-select:none;}');
    SB.AppendLine('.rollen-grid{display:flex;gap:12px;flex-wrap:wrap;'
      + 'margin-top:8px;}');
    SB.AppendLine('.rolle-karte{flex:1 1 260px;background:var(--karte);'
      + 'border:1px solid var(--rand);border-radius:8px;'
      + 'box-shadow:0 1px 2px rgba(16,32,48,0.06);padding:10px 12px;}');
    SB.AppendLine('.rolle-karte b{display:block;margin-bottom:4px;'
      + 'color:var(--akzent);}');
    SB.AppendLine('.rolle-karte p{margin:0;font-size:0.92em;'
      + 'color:var(--tinte);}');
    // ---- Command-Bar + Chips ------------------------------------------
    SB.AppendLine('.cmdbar{display:flex;gap:10px;align-items:center;'
      + 'flex-wrap:wrap;margin:4px 0 8px 0;}');
    SB.AppendLine('#suche{flex:1 1 26em;max-width:44em;padding:9px 12px;'
      + 'font-size:1em;border:1px solid var(--rand);border-radius:8px;'
      + 'background:var(--karte);}');
    SB.AppendLine('#suche:focus-visible,button:focus-visible,'
      + 'summary:focus-visible,tr.haupt:focus-visible{outline:2px solid '
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
    // (Dashboard-Kacheln: geteilte Basis, uWorkbenchStyle)
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
    SB.AppendLine('tr.haupt:hover{background:#f2f6fb;}');
    SB.AppendLine('tr.haupt.gewaehlt{background:#e8f0fa;'
      + 'box-shadow:inset 3px 0 0 var(--akzent);}');
    SB.AppendLine('td.id{font-family:Consolas,monospace;font-weight:600;'
      + 'white-space:nowrap;}');
    SB.AppendLine('td.noi{font-family:Consolas,monospace;'
      + 'font-size:0.85em;color:var(--dezent);}');
    // ---- Empty-State --------------------------------------------------
    SB.AppendLine('#leer{display:none;padding:26px;text-align:center;'
      + 'color:var(--dezent);}');
    // ---- Drawer -------------------------------------------------------
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
    // (pre/Codekarten/karte/copy: geteilte Basis, uWorkbenchStyle)
    SB.AppendLine('.metarow{margin-top:12px;color:var(--dezent);'
      + 'font-size:0.88em;}');
    // ---- Responsive ---------------------------------------------------
    SB.AppendLine('@media (max-width:900px){');
    SB.AppendLine('#drawer{width:100%;min-width:0;max-width:none;}');
    SB.AppendLine('.rollen-grid{flex-direction:column;}');
    SB.AppendLine('}');
    SB.AppendLine('</style>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RollenBlock: string;
// Drei Rollen-Karten, standardmaessig OFFEN, VOR dem Suchfeld
// (Nutzerauftrag "immer gut zugaenglich"; Test RoleBlock_...).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<details open class="rollen">');
    SB.AppendLine('<summary><b>Wof&uuml;r diese Seite? (Entwicklung, QA, '
      + 'Product Owner)</b></summary>');
    SB.AppendLine('<div class="rollen-grid">');
    SB.AppendLine('<div class="rolle-karte"><b>Entwicklung:</b><p>'
      + 'Wenn ein Scan eine SCA-Regel meldet, steht hier, was sie '
      + 'pr&uuml;ft und warum, mit dem Vorher/Nachher-Beispiel als '
      + 'Fix-Muster. Der noinspection-Name unterdr&uuml;ckt einen '
      + 'Einzelfund begr&uuml;ndet im Code; der Konfigurations-'
      + 'Schl&uuml;ssel kalibriert den Detektor projektweit.</p></div>');
    SB.AppendLine('<div class="rolle-karte"><b>QA / Test:</b><p>'
      + 'Der Pr&uuml;fumfang auf einen Blick: welche Regel mit welchem '
      + 'Typ, Schweregrad und welcher Konfidenz meldet und ob sie im '
      + 'Default-Profil aktiv ist. SCA-IDs aus Berichten oder Tickets '
      + 'lassen sich per Suche nachschlagen und fachlich '
      + 'einordnen.</p></div>');
    SB.AppendLine('<div class="rolle-karte"><b>Product Owner:</b><p>'
      + 'Die Qualit&auml;ts-Politik des Projekts: was abgedeckt ist '
      + '(Bugs, Sicherheit inkl. CWE-Bezug, Wartbarkeit), was das '
      + 'Default-Profil bewusst ausl&auml;sst - die Grundlage, um '
      + 'Profil-Entscheidungen und Regel-Ausnahmen zu '
      + 'diskutieren.</p></div>');
    SB.AppendLine('</div>');
    SB.AppendLine('</details>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CommandUndChips: string;
// Search-Command-Bar (Strg+K, Trefferzaehler) + Filter-Chips.
// Die Chips filtern UND-verknuepft ueber die Gruppen, ODER-verknuepft
// innerhalb einer Gruppe; "Filter zuruecksetzen" erscheint nur bei
// aktiven Filtern (UI-Konzept, Abschnitte 5+6).
var
  SB : TStringBuilder;
  S  : TLeakSeverity;
  C  : TFindingConfidence;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="cmdbar">');
    SB.AppendLine('<input id="suche" type="search" '
      + 'aria-label="Regelkatalog durchsuchen" '
      + 'placeholder="SCA-ID, Regelname, noinspection, CWE, Tag oder '
      + 'Begriff suchen ..." oninput="suche()">');
    SB.AppendLine('<span><span class="kbd">Strg</span>+<span class="kbd">'
      + 'K</span></span>');
    SB.AppendLine('<span id="zaehler"></span>');
    SB.AppendLine('<button id="reset" onclick="filterReset()">Filter '
      + 'zur&uuml;cksetzen</button>');
    SB.AppendLine('</div>');

    SB.AppendLine('<div class="chips" id="chips">');
    SB.AppendLine('<span class="gruppe">Typ</span>');
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
    SB.AppendLine('<span class="gruppe">Schweregrad</span>');
    for S := Low(TLeakSeverity) to High(TLeakSeverity) do
      SB.AppendLine(Format('<button class="fchip" data-gruppe="sev" '
        + 'data-wert="%d" aria-pressed="false" onclick="chip(this)">'
        + '%s</button>', [Ord(S), SEV_TEXT[S]]));
    SB.AppendLine('<span class="gruppe">Konfidenz</span>');
    for C := High(TFindingConfidence) downto Low(TFindingConfidence) do
      SB.AppendLine(Format('<button class="fchip" data-gruppe="konf" '
        + 'data-wert="%d" aria-pressed="false" onclick="chip(this)">'
        + '%s</button>', [Ord(C), CONF_TEXT[C]]));
    SB.AppendLine('<span class="gruppe">Default-Profil</span>');
    SB.AppendLine('<button class="fchip" data-gruppe="prof" '
      + 'data-wert="an" aria-pressed="false" onclick="chip(this)">an'
      + '</button>');
    SB.AppendLine('<button class="fchip" data-gruppe="prof" '
      + 'data-wert="aus" aria-pressed="false" onclick="chip(this)">aus'
      + '</button>');
    SB.AppendLine('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function Dashboard(const AStat: TKatalogStat): string;
// Kennzahlen-Karten: Orientierung, bevor 198 Zeilen kommen.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="dash">');
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Detektoren</div></div>', [AStat.Gesamt]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Fehler</div></div>', [AStat.Sev[lsError]]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Warnungen</div></div>',
      [AStat.Sev[lsWarning]]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Hinweise</div></div>', [AStat.Sev[lsHint]]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Security-Regeln</div></div>',
      [AStat.Security]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">mit CWE-Bezug</div></div>', [AStat.MitCwe]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Default an</div></div>', [AStat.Aktiv]));
    SB.AppendLine(Format('<div class="kachel"><div class="zahl">%d</div>'
      + '<div class="wofuer">Default aus</div></div>',
      [AStat.Gesamt - AStat.Aktiv]));
    SB.AppendLine('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function DrawerJs: string;
// Das komplette Seiten-JS: Sortierung (tbody-Verschiebung, thead bleibt
// vorn), Suche + Chip-Filter (UND ueber Gruppen, ODER in der Gruppe),
// Trefferzaehler + Empty-State, Drawer (Template klonen), Tastatur
// (Strg+K, Pfeile, Enter, Esc), Deep-Link #SCAxxx, Copy-Fallback.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<script>');
    SB.AppendLine('var richtung = {};');
    SB.AppendLine('var aktiveFilter = {typ:[], sev:[], konf:[], prof:[]};');
    SB.AppendLine('var gewaehlt = null;');
    SB.AppendLine('function alleTbodies() {');
    SB.AppendLine('  return Array.prototype.slice.call('
      + 'document.querySelectorAll("#kat tbody"));');
    SB.AppendLine('}');
    SB.AppendLine('function zellwert(tb, spalte) {');
    SB.AppendLine('  var td = tb.rows[0].cells[spalte];');
    SB.AppendLine('  if (td.dataset.sort !== undefined) '
      + 'return parseInt(td.dataset.sort, 10);');
    SB.AppendLine('  return td.textContent.toLowerCase();');
    SB.AppendLine('}');
    SB.AppendLine('function sortiere(spalte) {');
    SB.AppendLine('  var tab = document.getElementById("kat");');
    SB.AppendLine('  var auf = !(richtung[spalte] || false);');
    SB.AppendLine('  richtung = {}; richtung[spalte] = auf;');
    SB.AppendLine('  var koepfe = tab.tHead.rows[0].cells;');
    SB.AppendLine('  for (var k = 0; k < koepfe.length; k++) {');
    SB.AppendLine('    var pf = koepfe[k].querySelector(".pfeil");');
    SB.AppendLine('    if (pf) pf.textContent = '
      + '(k === spalte) ? (auf ? "\u25B2" : "\u25BC") : "";');
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
    SB.AppendLine('    sichtbar + " von " + ges + " Detektoren";');
    SB.AppendLine('  document.getElementById("leer").style.display =');
    SB.AppendLine('    sichtbar === 0 ? "block" : "none";');
    SB.AppendLine('  var aktiv = q !== "";');
    SB.AppendLine('  for (var g2 in aktiveFilter) '
      + 'if (aktiveFilter[g2].length) aktiv = true;');
    SB.AppendLine('  document.getElementById("reset").style.display =');
    SB.AppendLine('    aktiv ? "inline" : "none";');
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
    SB.AppendLine('  aktiveFilter = {typ:[], sev:[], konf:[], prof:[]};');
    SB.AppendLine('  var bts = document.querySelectorAll("button.fchip");');
    SB.AppendLine('  for (var i = 0; i < bts.length; i++) '
      + 'bts[i].setAttribute("aria-pressed", "false");');
    SB.AppendLine('  document.getElementById("suche").value = "";');
    SB.AppendLine('  suche();');
    SB.AppendLine('}');
    // ---- Drawer -------------------------------------------------------
    SB.AppendLine('function oeffneDrawer(tb) {');
    SB.AppendLine('  var id = tb.dataset.id;');
    SB.AppendLine('  var tpl = document.getElementById("tpl-" + id);');
    SB.AppendLine('  if (!tpl) return;');
    SB.AppendLine('  var korb = document.getElementById("drawer-inhalt");');
    SB.AppendLine('  korb.innerHTML = "";');
    SB.AppendLine('  korb.appendChild(tpl.content.cloneNode(true));');
    SB.AppendLine('  document.getElementById("drawer").classList'
      + '.add("offen");');
    SB.AppendLine('  if (gewaehlt) gewaehlt.classList.remove("gewaehlt");');
    SB.AppendLine('  gewaehlt = tb.rows[0];');
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
      + 'btn.textContent = "kopiert"; } catch (e) {}');
    SB.AppendLine('  document.body.removeChild(ta);');
    SB.AppendLine('  setTimeout(function(){ btn.textContent = '
      + '"Kopieren"; }, 1200);');
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
    SB.AppendLine('  // auf Chips/Reset/Copy und oeffnete stattdessen');
    SB.AppendLine('  // die erste Zeile (Review 07.09., Bestandsfix).');
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
    SB.AppendLine('    if (gewaehlt && zeilen[i].rows[0] === gewaehlt) '
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
    SB.AppendLine('  var h = location.hash.replace("#", "");');
    SB.AppendLine('  if (!h) return;');
    SB.AppendLine('  var tbs = alleTbodies();');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++)');
    SB.AppendLine('    if (tbs[i].dataset.id === h) {');
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

function SuchBlob(const R: TRegelDaten): string;
// Suchbasis: ALLES, was die Regel ausmacht, lowercase - damit die
// Suche "ueber den gesamten Content" geht, ohne das DOM zu lesen.
// AnsiLowerCase, NICHT LowerCase: die JS-Seite senkt die Eingabe
// Unicode-korrekt (toLowerCase), LowerCase senkt nur A..Z - mit ihm
// blieben grosse Umlaute im Blob stehen und Woerter wie "Ueberlauf"
// waeren in keiner Schreibweise findbar (Chargen-Review 06.09., Major).
// Umbrueche werden zu Leerzeichen, BEVOR HtmlEscape laeuft - der
// Escaper bildet #10 auf ein literales '<br>' ab (Anzeige-Vertrag fuer
// Elementinhalte); im Suchattribut wuerde das jede 'br'-Suche fluten
// und Phrasen ueber Zeilengrenzen zerreissen.
begin
  Result := AnsiLowerCase(
    R.Meta.ID + ' ' + R.Meta.Name + ' ' + KIND_META[R.K].Name + ' '
    + TypText(R.Meta.FindingType) + ' ' + SEV_TEXT[R.Sev] + ' '
    + CONF_TEXT[R.Conf] + ' ' + R.ProfilTxt + ' ' + R.Tags + ' '
    + JoinArr(R.Meta.CWE, ' ') + ' ' + R.Meta.ConfigKey + ' '
    + R.Meta.DetectorUnit + ' ' + R.Meta.ShortDescription + ' '
    + R.Meta.FullDescription + ' ' + R.Meta.BadExample + ' '
    + R.Meta.GoodExample);
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function ZeileFuerRegel(const R: TRegelDaten): string;
// Ein tbody je Regel: EINE sichtbare Badge-Zeile plus die
// data-Attribute fuer Suche, Chip-Filter und Drawer-Anker.
begin
  Result :=
    Format('<tbody data-id="%s" data-search="%s" data-typ="%s" '
      + 'data-sev="%d" data-konf="%d" data-prof="%s">'#13#10,
      [H(R.Meta.ID), H(SuchBlob(R)),
       TypCss(R.Meta.FindingType), Ord(R.Sev), Ord(R.Conf), R.ProfilTxt])
    + '<tr class="haupt" tabindex="0" '
    + 'onclick="oeffneDrawer(this.parentNode)">'
    + '<td class="id">' + H(R.Meta.ID) + '</td>'
    + '<td>' + H(R.Meta.Name) + '</td>'
    + '<td class="noi">' + H(KIND_META[R.K].Name) + '</td>'
    + Format('<td><span class="badge typ %s">%s</span></td>',
        [TypCss(R.Meta.FindingType), H(TypText(R.Meta.FindingType))])
    + Format('<td data-sort="%d"><span class="badge sev-%s">%s'
        + '</span></td>', [Ord(R.Sev), SEV_CSS[R.Sev], SEV_TEXT[R.Sev]])
    + Format('<td data-sort="%d"><span class="badge konf">%s'
        + '</span></td>', [Ord(R.Conf), CONF_TEXT[R.Conf]])
    + Format('<td data-sort="%d"><span class="pill %s">%s</span></td>',
        [Ord(not R.InDefault), R.ProfilTxt, R.ProfilTxt])
    + '<td>' + ChipListe(R.Meta.Tags, 'tag') + '</td>'
    + '</tr>'#13#10'</tbody>';
end;

function TemplateFuerRegel(const R: TRegelDaten): string;
// Drawer-Inhalt als nicht gerendertes Template neben der Zeile - das
// Drawer-JS klont es beim Oeffnen (Konzept: Detail-Drawer statt
// aufgeklappter Tabellenzeile; die Liste bleibt sichtbar).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('<template id="tpl-%s">', [H(R.Meta.ID)]));
    SB.AppendLine('<h2><span class="mono">' + H(R.Meta.ID) + '</span> '
      + H(R.Meta.Name) + '</h2>');
    SB.AppendLine('<div class="drawer-status">'
      + Format('<span class="badge typ %s">%s</span>',
          [TypCss(R.Meta.FindingType), H(TypText(R.Meta.FindingType))])
      + Format('<span class="badge sev-%s">%s</span>',
          [SEV_CSS[R.Sev], SEV_TEXT[R.Sev]])
      + Format('<span class="badge konf">Konfidenz %s</span>',
          [CONF_TEXT[R.Conf]])
      + Format('<span class="pill %s">Default-Profil %s</span>',
          [R.ProfilTxt, R.ProfilTxt])
      + '</div>');
    SB.AppendLine('<h3>Was wird erkannt?</h3>');
    SB.AppendLine('<p>' + H(R.Meta.ShortDescription) + '</p>');
    if R.Meta.FullDescription <> '' then
    begin
      SB.AppendLine('<h3>Warum ist das relevant?</h3>');
      SB.AppendLine('<p>' + H(R.Meta.FullDescription) + '</p>');
    end;
    if (R.Meta.BadExample <> '') or (R.Meta.GoodExample <> '') then
    begin
      SB.AppendLine('<div class="codekarten">');
      // #10#10 vor </pre>: zwei Leerzeilen Luft am Blockende - derselbe
      // Nutzerwunsch wie in der Hint-Zeile des Findings-Reports.
      // data-copy = der REINE Code ohne die Anzeige-Luft, via HA():
      // Umbrueche als '&#10;', nicht als '<br>'-Token (s. HA).
      if R.Meta.BadExample <> '' then
        SB.AppendLine(Format('<div class="codekarte schlecht" '
          + 'data-copy="%s"><div class="karte-titel">Vorher '
          + '(problematisch)<button class="copy" '
          + 'onclick="kopiere(this)">Kopieren</button></div><pre>%s'
          + #10#10'</pre></div>',
          [HA(R.Meta.BadExample), H(R.Meta.BadExample)]));
      if R.Meta.GoodExample <> '' then
        SB.AppendLine(Format('<div class="codekarte gut" '
          + 'data-copy="%s"><div class="karte-titel">Nachher '
          + '(empfohlen)<button class="copy" '
          + 'onclick="kopiere(this)">Kopieren</button></div><pre>%s'
          + #10#10'</pre></div>',
          [HA(R.Meta.GoodExample), H(R.Meta.GoodExample)]));
      SB.AppendLine('</div>');
    end;
    SB.AppendLine(Format('<div class="karte" data-copy="// noinspection '
      + '%s"><h3>Einzelfund unterdr&uuml;cken <button class="copy" '
      + 'onclick="kopiere(this)">Kopieren</button></h3>'
      + '<pre>// noinspection %s</pre>'
      + '<p>Unterdr&uuml;ckt diesen konkreten Fund an der markierten '
      + 'Stelle. Die Regel bleibt projektweit aktiv.</p></div>',
      [H(KIND_META[R.K].Name), H(KIND_META[R.K].Name)]));
    if R.Meta.ConfigKey <> '' then
      SB.AppendLine(Format('<div class="karte" data-copy="%s">'
        + '<h3>Projektweite Kalibrierung <button class="copy" '
        + 'onclick="kopiere(this)">Kopieren</button></h3>'
        + '<pre>%s</pre>'
        + '<p>Kalibriert den Detektor projektweit (analyser.ini) - '
        + 'bewusst getrennt von der Einzelfund-Unterdr&uuml;ckung.'
        + '</p></div>',
        [H(R.Meta.ConfigKey), H(R.Meta.ConfigKey)]))
    else
      SB.AppendLine('<div class="karte"><h3>Projektweite '
        + 'Kalibrierung</h3><p>Keine projektweite Konfiguration - '
        + 'die Regel meldet ohne Schwellwerte.</p></div>');
    SB.AppendLine('<div class="metarow">'
      + 'CWE: ' + ChipListe(R.Meta.CWE, 'cwe')
      + ' &middot; Tags: ' + ChipListe(R.Meta.Tags, 'tag')
      + ' &middot; Detektor-Unit: <span class="mono">'
      + H(R.Meta.DetectorUnit) + '</span></div>');
    SB.AppendLine('</template>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TDetectorInfoExport.DefaultFileName: string;
begin
  Result := 'sca-detector-info.html';
end;

class procedure TDetectorInfoExport.WriteToFile(const AFileName,
  ALang: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := BuildHtml(ALang);
    // Ueber den Konventions-Helfer, nicht direkt SaveToFile: die
    // BOM-Politik der Exporte lebt an EINER Stelle, und TEncoding.UTF8
    // schriebe in Delphi 12 gar kein BOM (Chargen-Review 06.09.).
    TExporter.SaveUtf8WithBom(SL, AFileName);
  finally
    SL.Free;
  end;
end;

class function TDetectorInfoExport.BuildHtml(const ALang: string): string;
var
  SB         : TStringBuilder;
  K          : TFindingKind;
  Meta       : TRuleMeta;      // nur der Dashboard-Zaehlpass
  DefaultSet : TFindingKinds;
  Stat       : TKatalogStat;
  R          : TRegelDaten;    // die Render-Schleife
  Anz        : Integer;
begin
  DefaultSet := TRuleCatalog.GetProfile('default');
  Anz := Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1;

  // Zaehlpass fuer das Dashboard (dieselbe Domaene wie die Tabelle:
  // alle Enum-Kinds, nicht TRuleCatalog.Count - der Loader ist
  // tolerant gegen gekuerzte Kataloge, Chargen-Review 06.09.).
  Stat := Default(TKatalogStat);
  Stat.Gesamt := Anz;
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRuleCanonical(K);
    Inc(Stat.Sev[KindDefaultSeverity(K)]);
    if Meta.FindingType in [ftVulnerability, ftSecurityHotspot] then
      Inc(Stat.Security);
    if Length(Meta.CWE) > 0 then Inc(Stat.MitCwe);
    if K in DefaultSet then Inc(Stat.Aktiv);
  end;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html lang="de">');
    SB.AppendLine('<head>');
    SB.AppendLine('<meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width, '
      + 'initial-scale=1">');
    SB.AppendLine('<title>SCA Detektor-Katalog</title>');
    SB.Append(SeiteStyle);
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.AppendLine('<header class="kopf">');
    SB.AppendLine('<h1>SCA Detektor-Katalog</h1>');
    SB.AppendLine(Format(
      '<div class="sub">%s %s &middot; %d Detektoren &middot; '
      + 'Spalten-Klick sortiert; das Suchfeld filtert &uuml;ber den '
      + 'gesamten Inhalt (auch Beschreibungen und Codebeispiele). '
      + 'Schweregrad ist der Regel-Default: Fehler-Funde setzen in der '
      + 'Standard-Politik Konfidenz &quot;hoch&quot; voraus '
      + '(Evidenz-Deckel), sonst meldet der Lauf eine Stufe '
      + 'darunter.</div>',
      [H(TRuleCatalog.ToolName), H(TRuleCatalog.ToolVersion), Anz]));
    SB.AppendLine('</header>');
    SB.AppendLine('<main>');
    SB.Append(RollenBlock);
    SB.Append(CommandUndChips);
    SB.Append(Dashboard(Stat));

    SB.AppendLine('<div class="listwrap">');
    SB.AppendLine('<table id="kat">');
    SB.AppendLine('<thead><tr>'
      + '<th onclick="sortiere(0)">SCA-ID<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(1)">Name<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(2)">noinspection<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(3)">Typ<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(4)">Schweregrad<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(5)">Konfidenz<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(6)">Default-Profil<span class="pfeil"></span></th>'
      + '<th onclick="sortiere(7)">Tags<span class="pfeil"></span></th>'
      + '</tr></thead>');

    // Je Regel: Badge-Zeile + Drawer-Template (Bausteine oben - haelt
    // BuildHtml unter der Komplexitaets-Grenze, Selbstscan-Fund).
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      R.Meta      := TRuleCatalog.GetRule(K, ALang);
      R.K         := K;
      R.Sev       := KindDefaultSeverity(K);
      R.Conf      := KindDefaultConfidence(K);
      R.InDefault := K in DefaultSet;
      R.Tags      := JoinArr(R.Meta.Tags, ', ');
      if R.InDefault then R.ProfilTxt := 'an' else R.ProfilTxt := 'aus';
      SB.AppendLine(ZeileFuerRegel(R));
      SB.Append(TemplateFuerRegel(R));
    end;

    SB.AppendLine('</table>');
    SB.AppendLine('</div>');
    SB.AppendLine('<div id="leer">Keine Treffer. '
      + '<button id="leer-reset" onclick="filterReset()">Filter '
      + 'zur&uuml;cksetzen</button></div>');
    SB.AppendLine('</main>');
    SB.AppendLine('<aside id="drawer" aria-label="Detektor-Details">');
    SB.AppendLine('<button id="drawer-schliessen" aria-label='
      + '"Details schliessen" onclick="schliesseDrawer()">&times;'
      + '</button>');
    SB.AppendLine('<div id="drawer-inhalt"></div>');
    SB.AppendLine('</aside>');
    SB.Append(DrawerJs);
    SB.AppendLine('</body></html>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
