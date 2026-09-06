unit uDetectorInfoExport;

// "Detector Info": alle Regeln des Katalogs als eigenstaendige, offline
// funktionierende HTML-Seite - sortierbare Tabelle plus Volltextsuche
// ueber den gesamten Inhalt (Nutzerauftrag Nico, 2026-09-06).
//
// SPRACHE: die Seite ist bewusst DEUTSCH und sprachfix - Chrome-Texte
// (Titel, Spalten, Suchfeld) stehen als Konstanten hier, die Regeltexte
// kommen aus GetRule(K, 'de') mit dem dokumentierten Feld-Rueckfall auf
// Englisch (das DE-Overlay traegt Name + Kurzbeschreibung; die
// Langbeschreibungen und die Vorher/Nachher-Beispiele existieren bisher
// nur englisch). BEWUSST KEIN _(): das Artefakt soll nicht mit der
// App-Sprache kippen. SPAETER laut Nutzer-Backlog EN/FR - dann wird
// die Sprache hier parametrisiert (Chrome-Tabelle je Sprache plus
// Overlays); bis dahin ist 'de' der einzige Aufrufwert.
//
// TECHNIK: ein <tbody> je Regel (Hauptzeile + aufklappbare Detailzeile
// wandern beim Sortieren als Paar); Sortierung ueber data-sort bzw.
// Zellentext, Suche ueber ein vorgebautes data-search-Attribut je Regel
// (kompletter Text lowercase, inkl. Detailzeile). Kein CDN, kein
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

// noinspection-file DuplicateString, StringConcatInLoop
// Ein HTML-Generator wiederholt Tags ('<td>', '</td>') bauartbedingt -
// eine Konstante je Tag machte den Aufbau unlesbarer, nicht sicherer
// (dieselbe Lage wie im grossen Findings-Report uExportHtml).
// StringConcatInLoop: JoinArr verkettet Tags/CWE-Listen mit maximal
// einer Handvoll Elementen - kein Hot-Path, TStringBuilder waere
// Overhead ohne Gewinn.

uses
  uExportHtml;   // TExporterHtml.HtmlEscape - keine dritte Escape-Kopie

const
  // Anzeige-Woerter der Seite (sprachfix deutsch, s. Unit-Kopf).
  SEV_TEXT  : array[TLeakSeverity] of string =
    ('Fehler', 'Warnung', 'Hinweis');
  CONF_TEXT : array[TFindingConfidence] of string =
    ('niedrig', 'mittel', 'hoch');   // Enum-Ordnung fcLow, fcMedium, fcHigh

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

function SeiteKopf(const AToolName, AToolVersion: string;
  AAnzahl: Integer): string;
// Statischer Seitenkopf: Stil, Titel, Suchfeld, Tabellen-Header.
// Eigene Funktion, damit BuildHtml nur noch die Regel-Schleife und
// den Fuss traegt (SCA176-Vorbeugung).
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html lang="de">');
    SB.AppendLine('<head>');
    SB.AppendLine('<meta charset="utf-8">');
    SB.AppendLine('<title>SCA Detektor-Katalog</title>');
    SB.AppendLine('<style>');
    SB.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;margin:16px;'
      + 'background:#fff;color:#1c1c1c;}');
    SB.AppendLine('h1{font-size:1.4em;margin:0 0 2px 0;}');
    SB.AppendLine('.sub{color:#666;margin-bottom:12px;}');
    SB.AppendLine('#suche{width:32em;max-width:90%;padding:6px 8px;'
      + 'margin-bottom:10px;font-size:1em;}');
    SB.AppendLine('table{border-collapse:collapse;width:100%;}');
    SB.AppendLine('th,td{border:1px solid #d0d0d0;padding:4px 8px;'
      + 'text-align:left;vertical-align:top;font-size:0.92em;}');
    SB.AppendLine('th{background:#f0f0f0;cursor:pointer;position:sticky;'
      + 'top:0;white-space:nowrap;user-select:none;}');
    SB.AppendLine('tr.detail td{background:#f7f9fc;}');
    SB.AppendLine('details summary{cursor:pointer;color:#1a5da6;}');
    SB.AppendLine('pre{background:#23272e;color:#e6e6e6;padding:8px;'
      + 'border-radius:4px;overflow-x:auto;font-size:0.9em;}');
    SB.AppendLine('.meta{color:#555;font-size:0.88em;margin-top:6px;}');
    SB.AppendLine('.aus{color:#a33;}');
    SB.AppendLine('.an{color:#2a7a2a;}');
    SB.AppendLine('</style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.AppendLine('<h1>SCA Detektor-Katalog</h1>');
    SB.AppendLine(Format(
      '<div class="sub">%s %s &middot; %d Detektoren &middot; '
      + 'Spalten-Klick sortiert; das Suchfeld filtert &uuml;ber den '
      + 'gesamten Inhalt (auch Beschreibungen und Codebeispiele).</div>',
      [TExporterHtml.HtmlEscape(AToolName),
       TExporterHtml.HtmlEscape(AToolVersion), AAnzahl]));
    SB.AppendLine('<input id="suche" type="search" '
      + 'placeholder="Suchen &uuml;ber alle Inhalte ..." '
      + 'oninput="suche()"> <span id="zaehler" class="sub"></span>');
    SB.AppendLine('<table id="kat">');
    SB.AppendLine('<thead><tr>'
      + '<th onclick="sortiere(0)">SCA-ID</th>'
      + '<th onclick="sortiere(1)">Name</th>'
      + '<th onclick="sortiere(2)">noinspection</th>'
      + '<th onclick="sortiere(3)">Typ</th>'
      + '<th onclick="sortiere(4)">Schweregrad</th>'
      + '<th onclick="sortiere(5)">Konfidenz</th>'
      + '<th onclick="sortiere(6)">Default-Profil</th>'
      + '<th onclick="sortiere(7)">Tags</th>'
      + '</tr></thead>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SeiteFuss: string;
// Inline-JS: Sortierung (tbody-Paare, data-sort vor Text, Richtung je
// Spalte togglen) + Volltextsuche ueber data-search.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('</table>');
    SB.AppendLine('<script>');
    SB.AppendLine('var richtung = {};');
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
    SB.AppendLine('function suche() {');
    SB.AppendLine('  var q = document.getElementById("suche")'
      + '.value.toLowerCase();');
    SB.AppendLine('  var tbs = alleTbodies(), sichtbar = 0;');
    SB.AppendLine('  for (var i = 0; i < tbs.length; i++) {');
    SB.AppendLine('    var hit = q === "" || '
      + 'tbs[i].dataset.search.indexOf(q) >= 0;');
    SB.AppendLine('    tbs[i].style.display = hit ? "" : "none";');
    SB.AppendLine('    if (hit) sichtbar++;');
    SB.AppendLine('  }');
    SB.AppendLine('  document.getElementById("zaehler").textContent =');
    SB.AppendLine('    q === "" ? "" : sichtbar + " Treffer";');
    SB.AppendLine('}');
    SB.AppendLine('</script>');
    SB.AppendLine('</body></html>');
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
    SL.SaveToFile(AFileName, TEncoding.UTF8);   // schreibt BOM (Preamble)
  finally
    SL.Free;
  end;
end;

class function TDetectorInfoExport.BuildHtml(const ALang: string): string;
var
  SB         : TStringBuilder;
  K          : TFindingKind;
  Meta       : TRuleMeta;
  DefaultSet : TFindingKinds;
  Sev        : TLeakSeverity;
  Conf       : TFindingConfidence;
  InDefault  : Boolean;
  Tags       : string;
  ProfilTxt  : string;
  ProfilCss  : string;
  Blob       : string;

  function H(const S: string): string;
  begin
    Result := TExporterHtml.HtmlEscape(S);
  end;

begin
  DefaultSet := TRuleCatalog.GetProfile('default');

  SB := TStringBuilder.Create;
  try
    SB.Append(SeiteKopf(TRuleCatalog.ToolName, TRuleCatalog.ToolVersion,
      TRuleCatalog.Count));

    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta      := TRuleCatalog.GetRule(K, ALang);
      Sev       := KindDefaultSeverity(K);
      Conf      := KindDefaultConfidence(K);
      InDefault := K in DefaultSet;
      Tags      := JoinArr(Meta.Tags, ', ');
      if InDefault then
      begin
        ProfilTxt := 'an';
        ProfilCss := 'an';
      end
      else
      begin
        ProfilTxt := 'aus';
        ProfilCss := 'aus';
      end;

      // Suchbasis: ALLES, was die Regel ausmacht, lowercase - damit die
      // Suche "ueber den gesamten Content" geht, ohne das DOM zu lesen.
      Blob := LowerCase(
        Meta.ID + ' ' + Meta.Name + ' ' + KIND_META[K].Name + ' '
        + TypText(Meta.FindingType) + ' ' + SEV_TEXT[Sev] + ' '
        + CONF_TEXT[Conf] + ' ' + ProfilTxt + ' ' + Tags + ' '
        + JoinArr(Meta.CWE, ' ') + ' ' + Meta.ConfigKey + ' '
        + Meta.DetectorUnit + ' ' + Meta.ShortDescription + ' '
        + Meta.FullDescription + ' ' + Meta.BadExample + ' '
        + Meta.GoodExample);

      SB.AppendLine(Format('<tbody data-search="%s">', [H(Blob)]));
      SB.AppendLine('<tr class="haupt">'
        + '<td>' + H(Meta.ID) + '</td>'
        + '<td>' + H(Meta.Name) + '</td>'
        + '<td>' + H(KIND_META[K].Name) + '</td>'
        + '<td>' + H(TypText(Meta.FindingType)) + '</td>'
        + Format('<td data-sort="%d">%s</td>', [Ord(Sev), SEV_TEXT[Sev]])
        + Format('<td data-sort="%d">%s</td>', [Ord(Conf), CONF_TEXT[Conf]])
        + Format('<td data-sort="%d"><span class="%s">%s</span></td>',
            [Ord(not InDefault), ProfilCss, ProfilTxt])
        + '<td>' + H(Tags) + '</td>'
        + '</tr>');
      SB.AppendLine('<tr class="detail"><td colspan="8"><details>');
      SB.AppendLine('<summary>' + H(Meta.ShortDescription) + '</summary>');
      if Meta.FullDescription <> '' then
        SB.AppendLine('<p>' + H(Meta.FullDescription) + '</p>');
      if Meta.BadExample <> '' then
        SB.AppendLine('<div><b>Vorher (problematisch)</b><pre>'
          + H(Meta.BadExample) + '</pre></div>');
      if Meta.GoodExample <> '' then
        SB.AppendLine('<div><b>Nachher (empfohlen)</b><pre>'
          + H(Meta.GoodExample) + '</pre></div>');
      SB.AppendLine(Format(
        '<div class="meta">CWE: %s &middot; Konfiguration: %s &middot; '
        + 'Detektor-Unit: %s</div>',
        [H(JoinArr(Meta.CWE, ', ')), H(Meta.ConfigKey),
         H(Meta.DetectorUnit)]));
      SB.AppendLine('</details></td></tr>');
      SB.AppendLine('</tbody>');
    end;

    SB.Append(SeiteFuss);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
