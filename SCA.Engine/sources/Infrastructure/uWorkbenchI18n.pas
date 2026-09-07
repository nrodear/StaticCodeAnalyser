unit uWorkbenchI18n;

// Die Oberflaechentexte BEIDER Workbench-HTML-Seiten in de/en/fr
// (Nutzerauftrag 07.09.: "die neuen html Seiten in alle Sprachen en
// und fr uebersetzen"). Schwester von uWorkbenchStyle: dort das
// geteilte CSS, hier der geteilte Text.
//
// WARUM SERVERSEITIG GEBACKEN statt Laufzeit-Umschalter wie im
// V1-Report: eine Workbench-Seite traegt ihre Sprache in MEHR als den
// Labels - die Badge-Woerter stehen zusaetzlich im Sortier- und im
// Such-Blob (data-search). Ein Umschalter, der nur die Labels dreht,
// liesse den Nutzer im englischen UI vergeblich nach "error" suchen,
// weil der Blob deutsch gebacken waere. Eine Datei = eine Sprache
// haelt Anzeige, Suche, Sortierung und die Regeltexte aus
// TRuleCatalog.GetRule(K, ALang) konsistent. Der Preis ist bewusst:
// wer die Sprache wechseln will, exportiert erneut.
//
// SPRACHCODE: 'de' | 'en' | 'fr'; jeder andere Wert faellt auf 'en'
// zurueck (Vertrag von SprachIndex). Das deckt sich mit dem
// Feld-Rueckfall von TRuleCatalog.GetRule.
//
// NICHT uebersetzt und bewusst gleich in allen Sprachen: die
// Sonar-Typbegriffe (Bug, Vulnerability, Security Hotspot, Code
// Smell, Code Duplication) - sie sind im ganzen Projekt englische
// Fachbegriffe (Grid, SARIF, Katalog) - sowie 'noinspection',
// 'CWE' und die SCA-IDs.

interface

type
  // Alle Textbausteine beider Seiten. Reihenfolge = Reihenfolge in
  // WB_TEXTE; eine neue Konstante braucht dort eine neue Zeile
  // (der Compiler erzwingt die Vollstaendigkeit).
  TWbText = (
    // -- gemeinsame Bedienelemente ------------------------------------
    wtSuchePlatzhalterKatalog, wtSuchePlatzhalterFunde,
    wtSucheAria, wtFilterReset, wtKeineTreffer, wtZaehlerDetektoren,
    wtZaehlerFunde, wtStrgTaste,
    // -- Chip-Gruppen --------------------------------------------------
    wtGruppeTyp, wtGruppeSchweregrad, wtGruppeKonfidenz,
    wtGruppeProfil, wtChipLesefehler,
    // -- Schweregrad / Konfidenz / Profil ------------------------------
    wtSevFehler, wtSevWarnung, wtSevHinweis, wtLesefehler,
    wtKonfNiedrig, wtKonfMittel, wtKonfHoch, wtProfilAn, wtProfilAus,
    // -- Spaltenkoepfe -------------------------------------------------
    wtSpScaId, wtSpName, wtSpNoinspection, wtSpTyp, wtSpSchweregrad,
    wtSpKonfidenz, wtSpProfil, wtSpTags, wtSpZeile, wtSpMethode,
    wtSpRegel, wtSpDetail,
    // -- Kacheln -------------------------------------------------------
    wtKaDetektoren, wtKaFehler, wtKaWarnungen, wtKaHinweise,
    wtKaSecurityRegeln, wtKaMitCwe, wtKaDefaultAn, wtKaDefaultAus,
    wtKaFunde, wtKaSecurityFunde, wtKaDateien, wtKaRegeln,
    wtKaLesefehler,
    // -- Drawer ---------------------------------------------------------
    wtDrawerAria, wtDrawerSchliessen, wtWasWirdErkannt,
    wtWarumRelevant, wtHinweisZuFund, wtVorher, wtNachher, wtKopieren,
    wtKopiert, wtUnterdruecken, wtUnterdrueckenText, wtKalibrierung,
    wtKalibrierungText, wtKeineKalibrierung, wtKonfidenzLabel,
    wtProfilLabel, wtRegelDefault, wtDetektorUnit, wtTagsLabel,
    // -- Rollenblock (nur Katalogseite) ---------------------------------
    wtRollenTitel, wtRolleDev, wtRolleDevText, wtRolleQa, wtRolleQaText,
    wtRolleOwner, wtRolleOwnerText,
    // -- Seitenkopf ------------------------------------------------------
    wtTitelKatalog, wtUntertitelKatalog, wtTitelFunde,
    wtUntertitelFunde, wtKuerzungsbanner, wtKeineFundeImLauf
  );

  TWorkbenchI18n = class
  public
    // Liefert den Textbaustein in der Sprache ALang ('de'/'en'/'fr',
    // sonst 'en'). Die Texte enthalten HTML-Entities (&uuml; etc.) -
    // sie gehen direkt ins Markup, NICHT durch HtmlEscape.
    class function T(AText: TWbText; const ALang: string): string; static;
    // Wie T, aber fuer JS-STRING-LITERALE: die HTML-Entities der
    // Tabelle werden zu \uXXXX-Escapes. Zwingend ueberall, wo der Text
    // per textContent gesetzt wird - dort interpretiert der Browser
    // KEINE Entities und zeigte sonst woertlich 'copi&eacute;'.
    // Die Rueckgabe ist reines ASCII und damit auch in einer
    // ASCII-Quelldatei ungefaehrlich.
    class function TJs(AText: TWbText; const ALang: string): string;
      static;
    // 'de' -> True: nur fuer Aufrufer, die eine Sprachwahl anbieten.
    class function IstBekannt(const ALang: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

type
  TWbZeile = array[0..2] of string;   // 0=de, 1=en, 2=fr

const
  // Die Tabelle. Reihenfolge MUSS TWbText entsprechen - Delphi prueft
  // nur die Anzahl, darum steht der Enum-Name als Kommentar an jeder
  // Zeile (bei einer Einfuegung beide Stellen anfassen).
  WB_TEXTE : array[TWbText] of TWbZeile = (
    // ---- gemeinsame Bedienelemente ----------------------------------
    ('SCA-ID, Regelname, noinspection, CWE, Tag oder Begriff suchen ...',
     'Search rule ID, name, noinspection, CWE, tag or any term ...',
     'Rechercher ID SCA, nom de r&egrave;gle, noinspection, CWE, tag ...'),
    ('Datei, Methode, Regel, SCA-ID, CWE oder Begriff suchen ...',
     'Search file, method, rule, SCA ID, CWE or any term ...',
     'Rechercher fichier, m&eacute;thode, r&egrave;gle, ID SCA, CWE ...'),
    ('Durchsuchen', 'Search', 'Rechercher'),
    ('Filter zur&uuml;cksetzen', 'Reset filters',
     'R&eacute;initialiser les filtres'),
    ('Keine Treffer.', 'No matches.', 'Aucun r&eacute;sultat.'),
    ('%d von %d Detektoren', '%d of %d detectors',
     '%d sur %d d&eacute;tecteurs'),
    ('%d von %d Funden', '%d of %d findings',
     '%d sur %d r&eacute;sultats'),
    ('Strg', 'Ctrl', 'Ctrl'),
    // ---- Chip-Gruppen -------------------------------------------------
    ('Typ', 'Type', 'Type'),
    ('Schweregrad', 'Severity', 'S&eacute;v&eacute;rit&eacute;'),
    ('Konfidenz', 'Confidence', 'Confiance'),
    ('Default-Profil', 'Default profile', 'Profil par d&eacute;faut'),
    ('Lesefehler', 'Read error', 'Erreur de lecture'),
    // ---- Schweregrad / Konfidenz / Profil ------------------------------
    ('Fehler', 'Error', 'Erreur'),
    ('Warnung', 'Warning', 'Avertissement'),
    ('Hinweis', 'Hint', 'Indication'),
    ('Lesefehler', 'Read error', 'Erreur de lecture'),
    ('niedrig', 'low', 'faible'),
    ('mittel', 'medium', 'moyenne'),
    ('hoch', 'high', '&eacute;lev&eacute;e'),
    ('an', 'on', 'activ&eacute;'),
    ('aus', 'off', 'd&eacute;sactiv&eacute;'),
    // ---- Spaltenkoepfe --------------------------------------------------
    ('SCA-ID', 'SCA ID', 'ID SCA'),
    ('Name', 'Name', 'Nom'),
    ('noinspection', 'noinspection', 'noinspection'),
    ('Typ', 'Type', 'Type'),
    ('Schweregrad', 'Severity', 'S&eacute;v&eacute;rit&eacute;'),
    ('Konfidenz', 'Confidence', 'Confiance'),
    ('Default-Profil', 'Default profile', 'Profil par d&eacute;faut'),
    ('Tags', 'Tags', 'Tags'),
    ('Zeile', 'Line', 'Ligne'),
    ('Methode', 'Method', 'M&eacute;thode'),
    ('Regel', 'Rule', 'R&egrave;gle'),
    ('Detail', 'Detail', 'D&eacute;tail'),
    // ---- Kacheln ---------------------------------------------------------
    ('Detektoren', 'Detectors', 'D&eacute;tecteurs'),
    ('Fehler', 'Errors', 'Erreurs'),
    ('Warnungen', 'Warnings', 'Avertissements'),
    ('Hinweise', 'Hints', 'Indications'),
    ('Security-Regeln', 'Security rules',
     'R&egrave;gles de s&eacute;curit&eacute;'),
    ('mit CWE-Bezug', 'with CWE reference', 'avec r&eacute;f&eacute;rence CWE'),
    ('Default an', 'Default on', 'Par d&eacute;faut activ&eacute;'),
    ('Default aus', 'Default off', 'Par d&eacute;faut d&eacute;sactiv&eacute;'),
    ('Funde', 'Findings', 'R&eacute;sultats'),
    ('Security-Funde', 'Security findings',
     'R&eacute;sultats de s&eacute;curit&eacute;'),
    ('Dateien', 'Files', 'Fichiers'),
    ('Regeln', 'Rules', 'R&egrave;gles'),
    ('Lesefehler', 'Read errors', 'Erreurs de lecture'),
    // ---- Drawer -----------------------------------------------------------
    ('Detektor-Details', 'Detector details', 'D&eacute;tails du d&eacute;tecteur'),
    ('Details schliessen', 'Close details', 'Fermer les d&eacute;tails'),
    ('Was wird erkannt?', 'What is detected?',
     'Qu''est-ce qui est d&eacute;tect&eacute; ?'),
    ('Warum ist das relevant?', 'Why does it matter?',
     'Pourquoi est-ce pertinent ?'),
    ('Hinweis zu diesem Fund', 'Note on this finding',
     'Remarque sur cette occurrence'),
    ('Vorher (problematisch)', 'Before (problematic)',
     'Avant (probl&eacute;matique)'),
    ('Nachher (empfohlen)', 'After (recommended)',
     'Apr&egrave;s (recommand&eacute;)'),
    ('Kopieren', 'Copy', 'Copier'),
    ('kopiert', 'copied', 'copi&eacute;'),
    ('Einzelfund unterdr&uuml;cken', 'Suppress a single finding',
     'Supprimer une occurrence'),
    ('Unterdr&uuml;ckt diesen konkreten Fund an der markierten Stelle. '
     + 'Die Regel bleibt projektweit aktiv.',
     'Suppresses this one finding at the marked position. The rule '
     + 'stays active across the project.',
     'Supprime cette occurrence pr&eacute;cise &agrave; l''endroit '
     + 'marqu&eacute;. La r&egrave;gle reste active dans tout le projet.'),
    ('Projektweite Kalibrierung', 'Project-wide calibration',
     'Calibrage &agrave; l''&eacute;chelle du projet'),
    ('Kalibriert den Detektor projektweit (analyser.ini) - bewusst '
     + 'getrennt von der Einzelfund-Unterdr&uuml;ckung.',
     'Calibrates the detector across the project (analyser.ini) - '
     + 'deliberately separate from suppressing a single finding.',
     'Calibre le d&eacute;tecteur dans tout le projet (analyser.ini) - '
     + 'volontairement distinct de la suppression d''une occurrence.'),
    ('Keine projektweite Konfiguration - die Regel meldet ohne '
     + 'Schwellwerte.',
     'No project-wide configuration - the rule reports without '
     + 'thresholds.',
     'Aucune configuration globale - la r&egrave;gle signale sans seuils.'),
    ('Konfidenz %s', 'Confidence %s', 'Confiance %s'),
    ('Default-Profil %s', 'Default profile %s',
     'Profil par d&eacute;faut %s'),
    ('Regel-Default %s', 'Rule default %s',
     'Valeur par d&eacute;faut %s'),
    ('Detektor-Unit', 'Detector unit', 'Unit&eacute; du d&eacute;tecteur'),
    ('Tags', 'Tags', 'Tags'),
    // ---- Rollenblock -------------------------------------------------------
    ('Wof&uuml;r diese Seite? (Entwicklung, QA, Product Owner)',
     'What is this page for? (Development, QA, Product Owner)',
     '&Agrave; quoi sert cette page ? (D&eacute;veloppement, QA, '
     + 'Product Owner)'),
    ('Entwicklung', 'Development', 'D&eacute;veloppement'),
    ('Wenn ein Scan eine SCA-Regel meldet, steht hier, was sie '
     + 'pr&uuml;ft und warum, mit dem Vorher/Nachher-Beispiel als '
     + 'Fix-Muster. Der noinspection-Name unterdr&uuml;ckt einen '
     + 'Einzelfund begr&uuml;ndet im Code; der Konfigurations-'
     + 'Schl&uuml;ssel kalibriert den Detektor projektweit.',
     'When a scan reports an SCA rule, this page explains what it '
     + 'checks and why, with the before/after example as the fix '
     + 'pattern. The noinspection name suppresses a single finding '
     + 'with a reason in the code; the configuration key calibrates '
     + 'the detector across the project.',
     'Lorsqu''un scan signale une r&egrave;gle SCA, cette page '
     + 'explique ce qu''elle v&eacute;rifie et pourquoi, avec '
     + 'l''exemple avant/apr&egrave;s comme mod&egrave;le de '
     + 'correction. Le nom noinspection supprime une occurrence de '
     + 'mani&egrave;re justifi&eacute;e dans le code ; la cl&eacute; '
     + 'de configuration calibre le d&eacute;tecteur pour tout le projet.'),
    ('QA / Test', 'QA / Test', 'QA / Test'),
    ('Der Pr&uuml;fumfang auf einen Blick: welche Regel mit welchem '
     + 'Typ, Schweregrad und welcher Konfidenz meldet und ob sie im '
     + 'Default-Profil aktiv ist. SCA-IDs aus Berichten oder Tickets '
     + 'lassen sich per Suche nachschlagen und fachlich einordnen.',
     'The test scope at a glance: which rule reports with which type, '
     + 'severity and confidence, and whether it is active in the '
     + 'default profile. SCA IDs from reports or tickets can be looked '
     + 'up via the search and put in context.',
     'La couverture en un coup d''oeil : quelle r&egrave;gle signale '
     + 'avec quel type, quelle s&eacute;v&eacute;rit&eacute; et quelle '
     + 'confiance, et si elle est active dans le profil par '
     + 'd&eacute;faut. Les ID SCA issus de rapports ou de tickets se '
     + 'retrouvent par la recherche.'),
    ('Product Owner', 'Product Owner', 'Product Owner'),
    ('Die Qualit&auml;ts-Politik des Projekts: was abgedeckt ist '
     + '(Bugs, Sicherheit inkl. CWE-Bezug, Wartbarkeit), was das '
     + 'Default-Profil bewusst ausl&auml;sst - die Grundlage, um '
     + 'Profil-Entscheidungen und Regel-Ausnahmen zu diskutieren.',
     'The project''s quality policy: what is covered (bugs, security '
     + 'including CWE references, maintainability) and what the '
     + 'default profile deliberately leaves out - the basis for '
     + 'discussing profile decisions and rule exceptions.',
     'La politique qualit&eacute; du projet : ce qui est couvert '
     + '(bugs, s&eacute;curit&eacute; avec r&eacute;f&eacute;rences '
     + 'CWE, maintenabilit&eacute;) et ce que le profil par '
     + 'd&eacute;faut laisse volontairement de c&ocirc;t&eacute; - la '
     + 'base pour discuter des profils et des exceptions.'),
    // ---- Seitenkopf ---------------------------------------------------------
    ('SCA Detektor-Katalog', 'SCA Detector Catalog',
     'Catalogue des d&eacute;tecteurs SCA'),
    ('%s %s &middot; %d Detektoren &middot; Spalten-Klick sortiert; das '
     + 'Suchfeld filtert &uuml;ber den gesamten Inhalt (auch '
     + 'Beschreibungen und Codebeispiele). Schweregrad ist der '
     + 'Regel-Default: Fehler-Funde setzen in der Standard-Politik '
     + 'Konfidenz &quot;hoch&quot; voraus (Evidenz-Deckel), sonst '
     + 'meldet der Lauf eine Stufe darunter.',
     '%s %s &middot; %d detectors &middot; click a column to sort; the '
     + 'search box filters the entire content (including descriptions '
     + 'and code examples). Severity is the rule default: under the '
     + 'standard policy an error finding requires &quot;high&quot; '
     + 'confidence (evidence cap), otherwise the run reports one level '
     + 'lower.',
     '%s %s &middot; %d d&eacute;tecteurs &middot; cliquez sur une '
     + 'colonne pour trier ; le champ de recherche filtre tout le '
     + 'contenu (descriptions et exemples de code inclus). La '
     + 's&eacute;v&eacute;rit&eacute; est celle par d&eacute;faut de la '
     + 'r&egrave;gle : dans la politique standard, une erreur exige une '
     + 'confiance &quot;&eacute;lev&eacute;e&quot;, sinon le rapport '
     + 'descend d''un niveau.'),
    ('SCA Funde', 'SCA Findings', 'R&eacute;sultats SCA'),
    ('%s %s &middot; %d Funde &middot; Klick auf einen Fund '
     + '&ouml;ffnet die Details rechts (Regel-Erkl&auml;rung, '
     + 'Fix-Muster, noinspection); Spalten-Klick sortiert, das '
     + 'Suchfeld filtert &uuml;ber Datei, Methode, Regel und '
     + 'Beschreibung.',
     '%s %s &middot; %d findings &middot; click a finding to open its '
     + 'details on the right (rule explanation, fix pattern, '
     + 'noinspection); click a column to sort, the search box filters '
     + 'by file, method, rule and description.',
     '%s %s &middot; %d r&eacute;sultats &middot; cliquez sur un '
     + 'r&eacute;sultat pour ouvrir ses d&eacute;tails &agrave; droite '
     + '(explication de la r&egrave;gle, mod&egrave;le de correction, '
     + 'noinspection) ; cliquez sur une colonne pour trier, le champ '
     + 'de recherche filtre par fichier, m&eacute;thode, r&egrave;gle '
     + 'et description.'),
    ('Tabelle auf %d Zeilen gek&uuml;rzt - %d weitere Funde sind nicht '
     + 'gerendert. Die Kacheln oben z&auml;hlen ALLE Funde; f&uuml;r '
     + 'den Volltext-Bericht die V1 nutzen oder das Zeilenbudget '
     + 'erh&ouml;hen.',
     'Table truncated to %d rows - %d further findings are not '
     + 'rendered. The tiles above count ALL findings; use the V1 report '
     + 'for the full text or raise the row budget.',
     'Tableau limit&eacute; &agrave; %d lignes - %d r&eacute;sultats '
     + 'suppl&eacute;mentaires ne sont pas affich&eacute;s. Les tuiles '
     + 'ci-dessus comptent TOUS les r&eacute;sultats ; utilisez le '
     + 'rapport V1 pour le texte int&eacute;gral ou augmentez le budget '
     + 'de lignes.'),
    ('Keine Funde in diesem Lauf.', 'No findings in this run.',
     'Aucun r&eacute;sultat dans cette analyse.')
  );

function SprachIndex(const ALang: string): Integer;
// 'de'/'en'/'fr' -> 0/1/2; alles andere -> 1 (en), wie der
// Feld-Rueckfall von TRuleCatalog.GetRule.
begin
  if SameText(ALang, 'de') then Exit(0);
  if SameText(ALang, 'fr') then Exit(2);
  Result := 1;
end;

class function TWorkbenchI18n.T(AText: TWbText;
  const ALang: string): string;
begin
  Result := WB_TEXTE[AText][SprachIndex(ALang)];
end;

class function TWorkbenchI18n.TJs(AText: TWbText;
  const ALang: string): string;
// Entity -> \uXXXX. Die Liste deckt GENAU die in WB_TEXTE benutzten
// Entities ab; eine neue Entity in der Tabelle gehoert hier ergaenzt.
// Der Waechtertest I18n_JsTexteOhneEntities haelt das zusammen: er
// prueft, dass nach der Wandlung KEIN '&...;' mehr uebrig ist.
// \uXXXX statt der echten Zeichen: die Quelldatei bleibt reines ASCII
// (Projektstil), und der JS-Parser erzeugt daraus dasselbe Zeichen.
const
  ENTITIES : array[0..10] of array[0..1] of string = (
    ('&eacute;', '\u00e9'), ('&egrave;', '\u00e8'),
    ('&agrave;', '\u00e0'), ('&ccedil;', '\u00e7'),
    ('&ocirc;', '\u00f4'),  ('&Agrave;', '\u00c0'),
    ('&uuml;', '\u00fc'),   ('&auml;', '\u00e4'),
    ('&ouml;', '\u00f6'),   ('&middot;', '\u00b7'),
    ('&quot;', '\"')
  );
var
  i : Integer;
begin
  Result := T(AText, ALang);
  for i := Low(ENTITIES) to High(ENTITIES) do
    Result := StringReplace(Result, ENTITIES[i][0], ENTITIES[i][1],
      [rfReplaceAll]);
end;

class function TWorkbenchI18n.IstBekannt(const ALang: string): Boolean;
begin
  Result := SameText(ALang, 'de') or SameText(ALang, 'en')
            or SameText(ALang, 'fr');
end;

end.
