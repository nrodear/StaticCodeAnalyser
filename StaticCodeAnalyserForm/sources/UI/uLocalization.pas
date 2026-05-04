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
