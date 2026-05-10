unit uLocalization;

// Lokalisierungs-Wrapper fuer das Static Code Analysis Tool for Delphi.
//
// Funktionsweise:
//   * Source-Strings sind in Englisch und mit _('...') instrumentiert.
//   * Default: Pass-Through (Englisch bleibt Englisch).
//   * SetLanguage('de'): aktiviert das eingebaute DE-Dictionary unten.
//     Strings, die im Dictionary fehlen, fallen auf die Original-Englisch-
//     Version zurueck (kein Crash, kein leerer String).
//   * SetLanguage('en') oder SetLanguage(''): zurueck auf Englisch.
//
// dxgettext-Variante:
//   Falls in einem groesseren Setup .po/.mo-Dateien gewuenscht sind, kann
//   {$DEFINE USE_GETTEXT} in der dpk gesetzt werden - dann uebernimmt
//   gnugettext.dgettext (sjrd/dxgettext) die Aufgabe. Das eingebaute
//   Dictionary bleibt dann ungenutzt.
//
// Verwendung im Code:
//   Btn.Caption := _('Start analysis');
//   Status := Format(_('%d findings'), [N]);

interface

uses
  System.SysUtils, System.Generics.Collections;

// Uebersetzt einen String nach aktiver Sprache. Nicht gefundene Strings
// werden unveraendert zurueckgegeben (Identity-Fallback).
function _(const S: string): string; overload;

// Format-Variante: erst uebersetzen, dann formatieren.
function _(const FormatStr: string; const Args: array of const): string; overload;

// Setzt die aktive Sprache. Erlaubte Werte: 'de', 'en', '' (Default).
// Aufruf z.B. einmal beim Frame-/Form-Aufbau.
procedure SetLanguage(const Lang: string);

// Liefert die aktuell gesetzte Sprache zurueck (oder '' wenn Default).
function CurrentLanguage: string;

implementation

{$IFDEF USE_GETTEXT}
uses
  gnugettext;
{$ENDIF}

var
  GCurrentLang : string = '';
  GDeMap       : TDictionary<string, string> = nil;

// ---------------------------------------------------------------------------
// Eingebaute DE-Uebersetzungen. 1:1 die englischen Source-Strings als Key,
// deutsche Variante als Value. Wenn ein Source-String hier nicht vorkommt,
// wird er unveraendert (auf Englisch) zurueckgegeben.
// ---------------------------------------------------------------------------
procedure BuildDeMap;
begin
  if Assigned(GDeMap) then Exit;
  GDeMap := TDictionary<string, string>.Create;

  // ---- Strukturelle Marker ----
  GDeMap.Add('--- Errors ---',           '--- Fehler ---');
  GDeMap.Add('--- Warnings ---',         '--- Warnungen ---');
  GDeMap.Add('--- Hints ---',            '--- Hinweise ---');

  // ---- Buttons / Aktionen ----
  GDeMap.Add('Start analysis',           'Analyse starten');
  GDeMap.Add('Cancel',                   'Abbrechen');
  GDeMap.Add('Current file',             'Aktuelle Datei');
  GDeMap.Add('Branch-Changes',           'Branch-'#$C4'nderungen');
  GDeMap.Add('Choose folder',            'Ordner w'#$E4'hlen');
  GDeMap.Add('Save results',             'Ergebnisse speichern');
  GDeMap.Add('Export',                   'Export');
  GDeMap.Add('Ignore...',                'Ignorieren...');
  GDeMap.Add('Repo...',                  'Repo...');         // Legacy
  GDeMap.Add('Settings...',              'Einstellungen...');
  GDeMap.Add('Include tests',            'Tests einschlie'#$DF'en');
  GDeMap.Add('with uses check',          'mit uses-Pr'#$FC'fung');

  // ---- Felder / Labels ----
  GDeMap.Add('Project path:',            'Projektpfad:');
  GDeMap.Add('Search:',                  'Suche:');
  GDeMap.Add('Severity:',                'Schweregrad:');
  GDeMap.Add('Type:',                    'Typ:');
  GDeMap.Add('File',                     'Datei');
  GDeMap.Add('Method',                   'Methode');
  GDeMap.Add('Line',                     'Zeile');
  GDeMap.Add('Detail',                   'Detail');
  GDeMap.Add('Severity',                 'Schweregrad');
  GDeMap.Add('Type',                     'Typ');
  GDeMap.Add('Rule',                     'Regel');
  GDeMap.Add('Code Quality',             'Codequalit'#$E4't');

  // ---- Filter-Combo Eintraege ----
  GDeMap.Add('All',                      'Alle');
  GDeMap.Add('Errors',                   'Fehler');
  GDeMap.Add('Warnings',                 'Warnungen');
  GDeMap.Add('Hints',                    'Hinweise');
  GDeMap.Add('Errors (all)',             'Fehler (alle)');
  GDeMap.Add('Warnings (all)',           'Warnungen (alle)');
  GDeMap.Add('Hints (all)',              'Hinweise (alle)');
  GDeMap.Add('Bugs',                     'Bugs');
  GDeMap.Add('Security',                 'Sicherheit');
  GDeMap.Add('Duplicates',               'Duplikate');
  GDeMap.Add('Read errors',              'Lesefehler');
  GDeMap.Add('Read Error',               'Lesefehler');
  GDeMap.Add('Cyclomatic',               'Komplexit'#$E4't');
  GDeMap.Add('Cyclomatic Complexity',    'Cyclomatic Complexity');

  // ---- TypeText / SonarQube-Kategorien (Hover-Overlay Badge, Grid Spalte 'Type') ----
  GDeMap.Add('Bug',                      'Bug');               // intl. etabliert
  GDeMap.Add('Code Smell',               'Code Smell');        // intl. etabliert
  GDeMap.Add('Vulnerability',            'Sicherheitsl'#$FC'cke');
  GDeMap.Add('Security Hotspot',         'Sicherheits-Hotspot');
  GDeMap.Add('Code Duplication',         'Code-Duplikat');

  // ---- Detektor-Namen ----
  GDeMap.Add('SQL Injection',            'SQL Injection');
  GDeMap.Add('Hardcoded Secrets',        'Hartcodierte Secrets');
  GDeMap.Add('Format()',                 'Format()');
  GDeMap.Add('Nil-Deref',                'Nil-Dereferenz');
  GDeMap.Add('Div by Zero',              'Division durch Null');
  GDeMap.Add('Empty Except',             'Leerer Except');
  GDeMap.Add('Missing Finally',          'Fehlendes Finally');
  GDeMap.Add('Dead Code',                'Toter Code');
  GDeMap.Add('Unused Uses',              'Ungenutzte Uses');
  GDeMap.Add('Debug Output',             'Debug-Ausgabe');
  GDeMap.Add('Hardcoded Path',           'Hartcodierter Pfad');
  GDeMap.Add('Long Method',              'Lange Methode');
  GDeMap.Add('Many Parameters',          'Zu viele Parameter');
  GDeMap.Add('Magic Number',             'Magic Number');
  GDeMap.Add('Duplicate Strings',        'Doppelte Strings');
  GDeMap.Add('Deep Nesting',             'Tiefe Verschachtelung');
  GDeMap.Add('TODO/FIXME',               'TODO/FIXME');
  GDeMap.Add('Empty Methods',            'Leere Methoden');
  GDeMap.Add('Duplicate Code Blocks',    'Doppelte Code-Bl'#$F6'cke');

  // ---- Status-/Progress-Texte ----
  GDeMap.Add('Ready.',                   'Bereit.');
  GDeMap.Add('Done. No findings.',       'Fertig. Keine Befunde.');
  GDeMap.Add('No findings.',             'Keine Befunde.');
  GDeMap.Add('Analysis cancelled',       'Analyse abgebrochen');
  GDeMap.Add('Analysing: ',              'Analysiere: ');
  GDeMap.Add('Analysing: %s',            'Analysiere: %s');
  GDeMap.Add('Watching: %s',             'Beobachte: %s');
  GDeMap.Add('Watch: could not attach to %s',
                                         'Watch: konnte nicht an %s angeh'#$E4'ngt werden');
  GDeMap.Add('Saved, queueing analysis: %s',
                                         'Gespeichert, Analyse wird angesto'#$DF'en: %s');
  GDeMap.Add('Analysis error: ',         'Analysefehler: ');
  GDeMap.Add('Analysis running - searching for files...',
                                         'Analyse l'#$E4'uft - Dateien werden gesucht...');
  GDeMap.Add('Checking all classes...',  'Pr'#$FC'fe alle Klassen...');
  GDeMap.Add('Saved: ',                  'Gespeichert: ');
  GDeMap.Add('File not found: ',         'Datei nicht gefunden: ');
  GDeMap.Add('Please provide a valid project path.',
                                         'Bitte gib einen g'#$FC'ltigen Projektpfad an.');
  GDeMap.Add('Opened: %s  Line: %d',     'Ge'#$F6'ffnet: %s  Zeile: %d');

  // ---- Hilfe-Panel ----
  GDeMap.Add('Select a row to see the fix hint',
                                         'Zeile w'#$E4'hlen f'#$FC'r L'#$F6'sungshinweis');
  GDeMap.Add('No fix hint available.',   'Kein L'#$F6'sungshinweis verf'#$FC'gbar.');
  GDeMap.Add('Before (problem)',         'Vorher (Problem)');
  GDeMap.Add('After (solution)',         'Nachher (L'#$F6'sung)');

  // ---- Datei-Dialoge / Hints ----
  GDeMap.Add('Select Pascal file to analyse',
                                         'Pascal-Datei zur Analyse w'#$E4'hlen');
  GDeMap.Add('Pascal file (*.pas)|*.pas|All files|*.*',
                                         'Pascal-Datei (*.pas)|*.pas|Alle Dateien|*.*');
  GDeMap.Add('Filter file / method / finding...',
                                         'Filter Datei / Methode / Befund...');
  GDeMap.Add('Select project folder',    'Projektordner ausw'#$E4'hlen');
  GDeMap.Add('CSV files|*.csv|Log files|*.log',
                                         'CSV Dateien|*.csv|Log Dateien|*.log');
  GDeMap.Add('CSV file (*.csv)|*.csv',   'CSV-Datei (*.csv)|*.csv');
  GDeMap.Add('JSON file (*.json)|*.json','JSON-Datei (*.json)|*.json');
  GDeMap.Add('HTML file (*.html)|*.html','HTML-Datei (*.html)|*.html');

  // ---- Toolbar-Hints ----
  GDeMap.Add('Open ignore list (which files are NOT analysed)',
                                         'Ignore-Liste '#$F6'ffnen (welche Dateien NICHT analysiert werden)');
  GDeMap.Add('Open analyser.ini (BaseBranch, git/svn paths, custom LeakyClasses)',
                                         'analyser.ini '#$F6'ffnen (BaseBranch, git/svn-Pfad, Custom-LeakyClasses)');
  GDeMap.Add('Export: HTML, JSON, CSV, Jira markup, plain text',
                                         'Export: HTML, JSON, CSV, Jira-Markup, Plain-Text');
  GDeMap.Add('More actions (Settings, Ignore list, Branch-Changes)',
                                         'Weitere Aktionen (Einstellungen, Ignore-Liste, Branch-'#$C4'nderungen)');

  // ---- Hamburger-Menu ----
  GDeMap.Add('Ignore list...',           'Ignore-Liste...');
  GDeMap.Add('Analyse Branch-Changes',   'Branch-'#$C4'nderungen analysieren');

  // ---- Stat-Tile-Hints (Multi-Line via sLineBreak) ----
  GDeMap.Add('Real bugs / security holes (severity Error). Fix immediately.',
                                         'Sichere Bugs / Sicherheitsl'#$FC'cken (Severity Error). Sofort fixen.');
  GDeMap.Add('Click: filter grid to Errors',
                                         'Klick: Grid auf Fehler filtern');
  GDeMap.Add('Likely bugs / risky patterns. Review before merge.',
                                         'Wahrscheinliche Bugs / riskante Muster. Pr'#$FC'fen vor Merge.');
  GDeMap.Add('Click: filter grid to Warnings',
                                         'Klick: Grid auf Warnungen filtern');
  GDeMap.Add('Code smells / style. Refactoring candidates.',
                                         'Code-Smells / Stilfragen. Refactoring-Kandidaten.');
  GDeMap.Add('Click: filter grid to Hints',
                                         'Klick: Grid auf Hinweise filtern');
  GDeMap.Add('File could not be read / parsed. Check path/encoding.',
                                         'Datei konnte nicht gelesen / geparst werden. Pfad/Encoding pr'#$FC'fen.');
  GDeMap.Add('Click: filter grid to read errors',
                                         'Klick: Grid auf Lesefehler filtern');
  GDeMap.Add('Methods with McCabe complexity > threshold (default 10).',
                                         'Methoden mit McCabe-Komplexit'#$E4't > Schwellwert (Default 10).');
  GDeMap.Add('Hard to test - refactor into smaller methods.',
                                         'Schwer zu testen - in kleinere Methoden refactoren.');
  GDeMap.Add('Click: filter grid to Cyclomatic',
                                         'Klick: Grid auf Cyclomatic filtern');
  GDeMap.Add('Findings of type Bug (wrong behaviour, crash, wrong result).',
                                         'Findings vom Typ Bug (falsches Verhalten, Crash, falsches Ergebnis).');
  GDeMap.Add('Crosses severities - Bugs can be Errors OR Warnings.',
                                         'Severity-'#$FC'bergreifend - Bugs k'#$F6'nnen Errors ODER Warnings sein.');
  GDeMap.Add('Click: filter grid to Bug type',
                                         'Klick: Grid auf Bug-Type filtern');
  GDeMap.Add('Security holes (SQL injection, hardcoded secrets ...).',
                                         'Sicherheitsl'#$FC'cken (SQL-Injection, hartcodierte Secrets ...).');
  GDeMap.Add('Click: filter grid to Vulnerability type',
                                         'Klick: Grid auf Vulnerability-Type filtern');
  GDeMap.Add('Copied code (strings, blocks). Extract Method/Constant candidates.',
                                         'Kopierter Code (Strings, Bl'#$F6'cke). Extract Method/Constant Kandidaten.');
  GDeMap.Add('Click: filter grid to Duplicate type',
                                         'Klick: Grid auf Duplicate-Type filtern');
  GDeMap.Add('Weighted quality score (lower = better).',
                                         'Gewichteter Quality-Score (niedriger = besser).');
  GDeMap.Add('Weights: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.',
                                         'Gewichte: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.');
  GDeMap.Add('Click: reset filters (show everything)',
                                         'Klick: Filter zur'#$FC'cksetzen (alles anzeigen)');

  // ---- Export-Menue ----
  GDeMap.Add('HTML report (all findings)...',
                                         'HTML-Report (alle Befunde)...');
  GDeMap.Add('Jira markup -> Clipboard', 'Jira-Markup -> Clipboard');
  GDeMap.Add('Plain text -> Clipboard',  'Plain-Text -> Clipboard');

  // ---- Export-Status ----
  GDeMap.Add('Nothing to export - filter returns 0 entries.',
                                         'Nichts zu exportieren - Filter liefert 0 Eintr'#$E4'ge.');
  GDeMap.Add('CSV export',               'CSV-Export');
  GDeMap.Add('CSV saved: %s (%d entries)',
                                         'CSV gespeichert: %s (%d Eintr'#$E4'ge)');
  GDeMap.Add('CSV export failed: ',      'CSV-Export fehlgeschlagen: ');
  GDeMap.Add('JSON export',              'JSON-Export');
  GDeMap.Add('JSON saved: %s (%d entries)',
                                         'JSON gespeichert: %s (%d Eintr'#$E4'ge)');
  GDeMap.Add('JSON export failed: ',     'JSON-Export fehlgeschlagen: ');
  GDeMap.Add('HTML report saved: %s',    'HTML-Report gespeichert: %s');
  GDeMap.Add('HTML export failed: ',     'HTML-Export fehlgeschlagen: ');
  GDeMap.Add('Jira export: please select a row first (file not unambiguous).',
                                         'Jira-Export: bitte zuerst eine Zeile ausw'#$E4'hlen (Datei nicht eindeutig).');
  GDeMap.Add('Jira wiki markup for %s copied to clipboard (errors+warnings).',
                                         'Jira-Wiki-Markup f'#$FC'r %s in Zwischenablage kopiert (Fehler+Warnungen).');
  GDeMap.Add('Clipboard: please select a row first (file not unambiguous).',
                                         'Clipboard: bitte zuerst eine Zeile ausw'#$E4'hlen (Datei nicht eindeutig).');
  GDeMap.Add('Errors+warnings for %s copied to clipboard.',
                                         'Fehler+Warnungen f'#$FC'r %s in Zwischenablage kopiert.');
  GDeMap.Add('AI prompt copied to clipboard: %s, line %s (%s)',
                                         'KI-Prompt in Zwischenablage: %s, Zeile %s (%s)');
  GDeMap.Add('Done. %d findings. Click a row -> AI prompt on clipboard.',
                                         'Fertig. %d Befunde. Zeile anklicken -> KI-Prompt in der Zwischenablage.');

  // ---- Analyse-Status / Fehler ----
  GDeMap.Add('IDE editor service not available.',
                                         'IDE-Editor-Service nicht verf'#$FC'gbar.');
  GDeMap.Add('No file opened.',          'Keine Datei ge'#$F6'ffnet.');
  GDeMap.Add('Current file is not a Pascal file.',
                                         'Aktuelle Datei ist keine Pascal-Datei.');
  // 'Analysis error: ' steht bereits weiter oben in den Status-Texten.
  GDeMap.Add('Unexpected error: ',       'Unerwarteter Fehler: ');
  GDeMap.Add('Branch changes: please provide a valid project path (for repo detection).',
                                         'Branch-Changes: bitte einen g'#$FC'ltigen Projektpfad angeben (zur Repo-Erkennung).');
  GDeMap.Add('%d file(s) - running...',  '%d Datei(en) - l'#$E4'uft...');
  GDeMap.Add('File %d / %d',             'Datei %d / %d');
  GDeMap.Add('File %d / %d (%d%%)',      'Datei %d / %d (%d%%)');
  GDeMap.Add('Cancelling analysis...',   'Analyse wird abgebrochen...');
  GDeMap.Add('Could not open editor. File: ',
                                         'Konnte Editor nicht '#$F6'ffnen. Datei: ');
  GDeMap.Add('Settings: %s - changes take effect on the next analysis run.',
                                         'Einstellungen: %s - '#$C4'nderungen wirken beim n'#$E4'chsten Analyse-Lauf.');
  GDeMap.Add('More than %d files found - scan cancelled.',
                                         'Mehr als %d Dateien gefunden - Scan abgebrochen.');
  GDeMap.Add('Scanning... %d found',     'Scanne... %d gefunden');
  GDeMap.Add('Analysis cancelled - no new findings loaded',
                                         'Analyse abgebrochen - keine neuen Befunde geladen');
  GDeMap.Add('%d / %d findings',         '%d / %d Befunde');
  GDeMap.Add('Filter: %s%s',             'Filter: %s%s');
  GDeMap.Add('Search: ',                 'Suche: ');
  GDeMap.Add(' - no changed .pas files', ' - keine ge'#$E4'nderten .pas-Dateien');

  // ---- VCS-Hinweise (uVcsChanges) ----
  GDeMap.Add('git not found. Install Git for Windows (git-scm.com) ' +
             'or set the path to git.exe in analyser.ini.',
                                         'git nicht gefunden. Installiere Git for Windows ' +
                                         '(git-scm.com) oder setze in analyser.ini den Pfad zu git.exe.');
  GDeMap.Add('Git: branch vs ',          'Git: Branch vs ');
  GDeMap.Add('Git: no base branch - working tree only',
                                         'Git: kein Base-Branch - nur Working Tree');
  GDeMap.Add('svn not found. Install TortoiseSVN WITH the option ' +
             '"command line client tools" or set the path to svn.exe in analyser.ini.',
                                         'svn nicht gefunden. Installiere TortoiseSVN MIT der Option ' +
                                         '"command line client tools" oder setze in analyser.ini den Pfad zu svn.exe.');
  GDeMap.Add('SVN call failed (exit code = %d)',
                                         'SVN-Aufruf fehlgeschlagen (ExitCode=%d)');

  // ---- Jira-/Clipboard-Export (uExport) ----
  GDeMap.Add('h2. Code analysis: ',      'h2. Code-Analyse: ');
  GDeMap.Add('As of: ',                  'Stand: ');
  GDeMap.Add('Code analysis: ',          'Code-Analyse: ');
  GDeMap.Add('Findings in detail',       'Befunde im Detail');
  GDeMap.Add('Summary',                  'Zusammenfassung');
  GDeMap.Add('no findings',              'keine Befunde');
  GDeMap.Add('Error',                    'Fehler');
  GDeMap.Add('Warning',                  'Warnung');
  GDeMap.Add('Hint',                     'Hinweis');
  GDeMap.Add('ERROR',                    'FEHLER');
  GDeMap.Add('WARNING',                  'WARNUNG');
  GDeMap.Add('HINT',                     'HINWEIS');
  GDeMap.Add('Info',                     'Info');
  GDeMap.Add('Hint: ',                   'Hinweis: ');
  GDeMap.Add('Before:',                  'Vorher:');
  GDeMap.Add('After:',                   'Nachher:');
  GDeMap.Add('L. ',                      'Z. ');
  // 'in' ist in beiden Sprachen identisch - Identity-Fallback reicht.

  // ---- AI/Claude-Prompt (uClaudePrompt) ----
  GDeMap.Add('Code review request - Delphi static analysis finding',
                                         'Code-Review-Anfrage - Delphi Static-Analysis-Befund');
  GDeMap.Add('You are a senior Delphi developer reviewing the output ' +
             'of a static code analyser. Target version: Delphi 12 Athens (RTL/VCL). ' +
             'Suggest minimal, idiomatic fixes - no sweeping refactors, no style ' +
             'overhauls, no new dependencies unless strictly required.',
                                         'Du bist ein erfahrener Delphi-Entwickler und reviewst die Ausgabe ' +
                                         'eines statischen Code-Analyzers. Zielversion: Delphi 12 Athens (RTL/VCL). ' +
                                         'Schlage minimal-invasive, idiomatische Fixes vor - keine Refactor-Sprees, ' +
                                         'keine Stil-'#$DC'berarbeitungen, keine neuen Abh'#$E4'ngigkeiten ohne ' +
                                         'zwingenden Grund.');
  GDeMap.Add('Finding',                  'Befund');
  GDeMap.Add('Field',                    'Feld');
  GDeMap.Add('Value',                    'Wert');
  GDeMap.Add('Rule description',         'Regel-Beschreibung');
  GDeMap.Add('Code (>>> marks the line that triggered the rule)',
                                         'Code (>>> markiert die Zeile, die die Regel ausgel'#$F6'st hat)');
  GDeMap.Add('Reference pattern (generic example for this rule, NOT the user''s code)',
                                         'Referenz-Pattern (generisches Beispiel f'#$FC'r diese Regel, NICHT der User-Code)');
  GDeMap.Add('Anti-pattern',             'Anti-Pattern');
  GDeMap.Add('Recommended fix',          'Empfohlener Fix');
  GDeMap.Add('Please respond with three sections',
                                         'Bitte antworte in drei Abschnitten');
  GDeMap.Add('Cause',                    'Ursache');
  GDeMap.Add('1-2 sentences why the rule fires on THIS specific code (not the generic explanation above).',
                                         '1-2 S'#$E4'tze, warum die Regel bei DIESEM konkreten Code feuert (nicht die generische Erkl'#$E4'rung oben).');
  GDeMap.Add('Fix',                      'Fix');
  GDeMap.Add('the modified code as a Pascal block. Keep diff minimal: only the lines that need to change. Match surrounding indentation and naming style.',
                                         'der ge'#$E4'nderte Code als Pascal-Block. Diff minimal halten: nur die Zeilen, die sich '#$E4'ndern m'#$FC'ssen. Indent und Namensstil anpassen.');
  GDeMap.Add('Verify',                   'Verifikation');
  GDeMap.Add('what to test or check after the fix to confirm the issue is gone (and no regressions).',
                                         'was nach dem Fix zu testen ist um zu best'#$E4'tigen dass der Befund weg ist (und keine Regressionen entstanden).');
  GDeMap.Add('If the finding is a false positive, say so and explain why - then suggest a `// noinspection %s` suppression marker on the affected line.',
                                         'Falls False Positive: sag das und erkl'#$E4're warum - schlage dann einen `// noinspection %s` Suppression-Marker auf der betroffenen Zeile vor.');
end;

function _(const S: string): string;
begin
  {$IFDEF USE_GETTEXT}
  Result := gnugettext.dgettext('default', S);
  {$ELSE}
  if (GCurrentLang = 'de') and Assigned(GDeMap) then
  begin
    if not GDeMap.TryGetValue(S, Result) then
      Result := S;
  end
  else
    Result := S;
  {$ENDIF}
end;

function _(const FormatStr: string; const Args: array of const): string;
begin
  Result := Format(_(FormatStr), Args);
end;

procedure SetLanguage(const Lang: string);
begin
  GCurrentLang := Lang;
  if Lang = 'de' then BuildDeMap;
  {$IFDEF USE_GETTEXT}
  gnugettext.UseLanguage(Lang);
  {$ENDIF}
end;

function CurrentLanguage: string;
begin
  Result := GCurrentLang;
end;

initialization

finalization
  if Assigned(GDeMap) then
    FreeAndNil(GDeMap);

end.
