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
  GDeMap.Add('Memory Leak',              'Speicherleck');
  GDeMap.Add('Memory Leaks (all)',       'Speicherlecks (alle)');
  // ---- Visibility-Detektoren (single-file) ----
  GDeMap.Add('Can Be Unit Private',      'Kann unit-private sein');
  GDeMap.Add('Can Be Strict Private',    'Kann strict private sein');
  GDeMap.Add('Can Be Protected',         'Kann protected sein');
  GDeMap.Add('Unused Public Member',     'Ungenutzte public-API');

  // ---- FixHint-Description-Strings (Hilfe-Panel + Hover-Tooltips) ----
  // Diese Strings werden via _() im uFixHint.pas instrumentiert.
  // Reihenfolge analog uSCAConsts.TFindingKind, damit Wartung leichter ist.
  GDeMap.Add('Object created but never freed (memory leak)',
             'Objekt erzeugt, aber nie freigegeben (Speicherleck)');
  GDeMap.Add('Function return value is not freed by the caller',
             'R'#$FC'ckgabewert wird vom Aufrufer nicht freigegeben');
  GDeMap.Add('Free is outside the protecting finally block',
             'Free liegt au'#$DF'erhalb des sch'#$FC'tzenden finally-Blocks');
  GDeMap.Add('Empty except block silently swallows every exception',
             'Leerer except-Block schluckt jede Exception ohne Reaktion');
  GDeMap.Add('SQL command built with "+" - SQL injection risk',
             'SQL-Befehl per "+" zusammengebaut - Injection-Risiko');
  GDeMap.Add('Password / token literal in source code',
             'Passwort/Token als Stringliteral im Quellcode');
  GDeMap.Add('Format() placeholder count does not match argument count',
             'Format()-Platzhalter passen nicht zur Argument-Anzahl');
  GDeMap.Add('File could not be read or parsed',
             'Datei konnte nicht gelesen oder geparst werden');
  GDeMap.Add('Nil dereference: access through a possibly nil reference',
             'Nil-Dereferenz: Zugriff '#$FC'ber eine eventuell null-Referenz');
  GDeMap.Add('Create without try/finally - exception path leaks the object',
             'Create ohne try/finally - Exception-Pfad leakt das Objekt');
  GDeMap.Add('Division by zero: EZeroDivide or EDivByZero possible',
             'Division durch Null: EZeroDivide oder EDivByZero m'#$F6'glich');
  GDeMap.Add('Dead code: statements after Exit / raise are unreachable',
             'Toter Code: Anweisungen nach Exit/raise werden nie erreicht');
  GDeMap.Add('Method too long - splitting it improves readability and testability',
             'Methode zu lang - Aufteilen verbessert Lesbarkeit und Testbarkeit');
  GDeMap.Add('Too many parameters - introduce a parameter object / record',
             'Zu viele Parameter - Parameter-Objekt / Record einf'#$FC'hren');
  GDeMap.Add('Magic number - replace literal with a named constant',
             'Magic Number - Literal durch benannte Konstante ersetzen');
  GDeMap.Add('String literal repeated - extract to a constant or resourcestring',
             'Stringliteral mehrfach genutzt - in Konstante / resourcestring auslagern');
  GDeMap.Add('Hardcoded path - load it from configuration instead',
             'Hartcodierter Pfad - stattdessen aus Konfiguration laden');
  GDeMap.Add('Debug output left in production code',
             'Debug-Ausgabe im Produktionscode vergessen');
  GDeMap.Add('Nesting too deep - use early exit (guard clauses) or extract a method',
             'Zu tief verschachtelt - Early-Exit (Guard-Clauses) oder Methode extrahieren');
  GDeMap.Add('Cyclomatic complexity too high - too many branches; extract methods or simplify conditions',
             'Cyclomatic Complexity zu hoch - zu viele Verzweigungen; Methoden extrahieren oder Bedingungen vereinfachen');
  GDeMap.Add('Uses entry may be unused - remove to reduce coupling',
             'Uses-Eintrag m'#$F6'glicherweise ungenutzt - entfernen reduziert Kopplung');
  GDeMap.Add('Open marker (TODO / FIXME / HACK / XXX) - resolve before release',
             'Offener Marker (TODO / FIXME / HACK / XXX) - vor Release aufl'#$F6'sen');
  GDeMap.Add('Method body is empty - forgotten stub or unintentional?',
             'Methodenrumpf ist leer - vergessener Stub oder ungewollt?');
  GDeMap.Add('Multiple identical code blocks - extract a method (DRY)',
             'Mehrere identische Code-Bl'#$F6'cke - Methode extrahieren (DRY)');
  // Custom-Rule
  GDeMap.Add('Custom rule defined in analyser-rules.yml matched this code',
             'Custom-Regel aus analyser-rules.yml hat diesen Code getroffen');
  // Concat / With / Reversed / Self / Virtual / Length
  GDeMap.Add('Long string concatenation - prefer Format() for readability',
             'Lange String-Konkatenation - Format() ist lesbarer');
  GDeMap.Add('with statement can silently rebind identifiers - avoid it',
             'with-Statement bindet Bezeichner still um - vermeiden');
  GDeMap.Add('for-loop range is reversed - the loop body never runs',
             'for-Schleife-Bereich ist umgekehrt - der Body l'#$E4'uft nie');
  GDeMap.Add('Self-assignment is a no-op - usually a copy-paste mistake',
             'Selbst-Zuweisung ist ein No-Op - meist ein Copy-Paste-Fehler');
  GDeMap.Add('Virtual method called from constructor - override sees half-initialized Self',
             'Virtuelle Methode im Constructor gerufen - Override sieht halb-initialisiertes Self');
  GDeMap.Add('Length()/.Count minus a constant can underflow on empty input',
             'Length() / .Count minus Konstante kann bei leerem Input unterlaufen');
  // Visibility
  GDeMap.Add('Public member is referenced only within the current unit - Delphi-classic `private` (unit-scope) suffices',
             'Public-Member wird nur innerhalb der aktuellen Unit referenziert - Delphi-klassisches `private` (Unit-Scope) reicht');
  GDeMap.Add('Public member is used only by methods of its own class - `strict private` reaches the strongest encapsulation',
             'Public-Member wird nur von Methoden der eigenen Klasse genutzt - `strict private` ist die strengste sinnvolle Sichtbarkeit');
  GDeMap.Add('Public member is used only by subclasses - protected is tighter',
             'Public-Member nur in Subklassen genutzt - protected ist strenger');
  GDeMap.Add('Public member has no callers anywhere - dead API',
             'Public-Member hat nirgends Aufrufer - tote API');
  // Unused-Local / Unused-Param / Tautological
  GDeMap.Add('Local variable declared but never read or written',
             'Lokale Variable deklariert, aber nie gelesen oder geschrieben');
  GDeMap.Add('Parameter never read in method body',
             'Parameter wird im Methoden-Body nie gelesen');
  GDeMap.Add('Binary expression has identical left and right side - copy-paste bug?',
             'Binaer-Ausdruck mit gleicher linker und rechter Seite - Copy-Paste-Bug?');

  // ---- SonarDelphi-Import (SCA060+) FixHint-Descriptions ----
  GDeMap.Add('goto weakens structured control flow',
             'goto bricht den strukturierten Kontrollfluss');
  GDeMap.Add('Tab character in source - use spaces for indentation',
             'Tab-Zeichen im Quelltext - Einr'#$FC'ckung mit Leerzeichen');
  GDeMap.Add('Source line exceeds 120 characters - wrap or extract',
             'Zeile > 120 Zeichen - umbrechen oder Teilausdruck extrahieren');
  GDeMap.Add('Line ends with whitespace - diff hygiene',
             'Zeile endet mit Whitespace - Diff-Hygiene');
  GDeMap.Add('Pascal keyword not in lowercase',
             'Pascal-Keyword nicht in Kleinschreibung');
  GDeMap.Add('// NOSONAR suppression marker found - audit it',
             '// NOSONAR-Suppression gefunden - bitte pr'#$FC'fen');
  GDeMap.Add('Empty argument list "()" - drop the parentheses',
             'Leere Argument-Liste "()" - Klammern entfernen');
  GDeMap.Add('asm..end block - platform-specific, hard to port',
             'asm..end-Block - plattformspezifisch, schlecht portierbar');
  GDeMap.Add('Trailing comma in argument list',
             'Trailing-Komma in der Argument-Liste');
  GDeMap.Add('Large integer literal without digit grouping',
             'Gro'#$DF'es Integer-Literal ohne Tausender-Trenner');
  GDeMap.Add('Comment contains Pascal-code markers - delete it or restore it',
             'Kommentar enth'#$E4'lt Pascal-Code-Marker - l'#$F6'schen oder reaktivieren');
  GDeMap.Add('Unit-level keyword not at column 1',
             'Unit-Section-Keyword nicht in Spalte 1');
  GDeMap.Add('Boolean compared to True/False - redundant',
             'Boolean gegen True/False verglichen - redundant');
  GDeMap.Add('Interface declaration has no methods',
             'Interface-Deklaration ohne Methoden');
  GDeMap.Add('Assert() without explanatory message',
             'Assert() ohne erkl'#$E4'rende Message');
  GDeMap.Add('class(TObject) - TObject is the default base, drop it',
             'class(TObject) - TObject ist Default-Basis, redundant');
  GDeMap.Add('Grouped variable/field declaration - one per line',
             'Gruppierte Variable/Feld-Deklaration - eine pro Zeile');
  GDeMap.Add('Empty begin..end block',
             'Leerer begin..end-Block');
  GDeMap.Add('on E: Exception catches everything - too broad',
             'on E: Exception f'#$E4'ngt alles - zu breit');
  GDeMap.Add('Two consecutive const/type/var sections - merge them',
             'Zwei aufeinanderfolgende const/type/var-Sektionen - zusammenfassen');
  GDeMap.Add('Exit/Continue/Break directly before end - redundant',
             'Exit/Continue/Break direkt vor end - redundant');
  GDeMap.Add('Multiple class declarations in one unit',
             'Mehrere Klassen-Deklarationen in einer Unit');
  GDeMap.Add('Double semicolon ";;" - one is enough',
             'Doppelte Semikolons ";;" - eines reicht');
  GDeMap.Add('Empty finally block - either drop the try or add cleanup',
             'Leerer finally-Block - try entfernen oder Cleanup erg'#$E4'nzen');
  GDeMap.Add('Assigned(X) and (X <> nil) - one check is enough',
             'Assigned(X) and (X <> nil) - ein Check reicht');
  GDeMap.Add('X.Free; X := nil; -> use FreeAndNil(X)',
             'X.Free; X := nil; -> FreeAndNil(X) nutzen');
  GDeMap.Add('out parameter - prefer Result or var',
             'out-Parameter - Result oder var bevorzugen');
  GDeMap.Add('Empty visibility section in class - delete it',
             'Leere Visibility-Sektion in der Klasse - entfernen');
  GDeMap.Add('Unit ends with begin..end. - use initialization section',
             'Unit endet mit begin..end. - initialization-Section verwenden');
  GDeMap.Add('Public field - expose a property instead',
             'Public-Feld - stattdessen Property freigeben');
  GDeMap.Add('Nested try block - consider extracting a procedure',
             'Geschachtelter try-Block - Methode extrahieren');
  GDeMap.Add('case statement has many branches - consider dispatch table',
             'case-Statement mit vielen Branches - Dispatch-Tabelle erw'#$E4'gen');
  GDeMap.Add('Unit has no declarations - delete it or fill it',
             'Unit ohne Deklarationen - l'#$F6'schen oder f'#$FC'llen');
  GDeMap.Add('Method calls inherited more than once',
             'Methode ruft inherited mehrfach auf');
  GDeMap.Add('Doubled parentheses around a simple expression',
             'Doppelte Klammern um einen einfachen Ausdruck');
  GDeMap.Add('Two visibility sections with the same keyword - merge them',
             'Zwei Visibility-Sektionen mit gleichem Keyword - zusammenfassen');
  GDeMap.Add('Constructor does not call inherited - parent state uninitialized',
             'Konstruktor ruft kein inherited - Eltern-State uninitialisiert');
  GDeMap.Add('Destructor does not call inherited - resource leak',
             'Destruktor ruft kein inherited - Ressourcen-Leck');
  GDeMap.Add('if X then Y := True else Y := False - assign expression directly',
             'if X then Y := True else Y := False - Ausdruck direkt zuweisen');
  GDeMap.Add('Asymmetric begin/end in if/else - format consistently',
             'Asymmetrische begin/end in if/else - konsistent formatieren');
  GDeMap.Add('Pointer type alias should start with "P"',
             'Pointer-Typ-Alias sollte mit "P" beginnen');
  GDeMap.Add('Branch body without begin..end - add explicit block',
             'Branch-Body ohne begin..end - expliziten Block setzen');
  GDeMap.Add('Nested procedure/function - consider extracting',
             'Geschachtelte procedure/function - extrahieren');
  GDeMap.Add('Class field without "F" prefix',
             'Klassenfeld ohne "F"-Prefix');
  GDeMap.Add('Class/record type without "T" prefix',
             'Class/Record-Typ ohne "T"-Prefix');
  GDeMap.Add('Interface type without "I" prefix',
             'Interface-Typ ohne "I"-Prefix');
  GDeMap.Add('Method name not in PascalCase',
             'Methoden-Name nicht in PascalCase');

  // ---- Concurrency-Detektor-Familie (SCA108+) ----
  GDeMap.Add('Synchronize() in a destructor - worker and UI thread deadlock each other',
             'Synchronize() im Destruktor - Worker- und UI-Thread blockieren sich gegenseitig');
  GDeMap.Add('Lock acquired without try..finally release - exception leaves the lock held',
             'Lock ohne umschliessendes try..finally - bei Exception bleibt der Lock dauerhaft gesperrt');

  // ---- Performance-Hotspots (SCA110-112) ----
  GDeMap.Add('String concatenation in loop - quadratic reallocations',
             'String-Konkatenation in der Loop - quadratische Allokationen');
  GDeMap.Add('ParamByName in loop - cache the TParam reference outside',
             'ParamByName in der Loop - TParam-Referenz ausserhalb cachen');
  GDeMap.Add('FieldByName in loop - cache the TField reference outside',
             'FieldByName in der Loop - TField-Referenz ausserhalb cachen');

  // ---- Concurrency-Familie erweitert (SCA113-114) ----
  GDeMap.Add('TThread.Resume is deprecated - use TThread.Start (since Delphi 2010)',
             'TThread.Resume ist deprecated - stattdessen TThread.Start (seit Delphi 2010)');
  GDeMap.Add('TThread destroyed without Terminate+WaitFor - worker may still be running',
             'TThread zerstoert ohne Terminate+WaitFor - Worker laeuft eventuell noch');

  // ---- REST/HTTP-Security (SCA115-116) ----
  GDeMap.Add('Plaintext HTTP URL - prefer https:// for remote endpoints',
             'Plaintext-HTTP-URL - https:// fuer Remote-Endpoints bevorzugen');
  GDeMap.Add('TLS verification disabled - MITM-attack surface',
             'TLS-Validierung deaktiviert - MITM-Angriffsflaeche');

  // ---- Doc-Luecken (SCA117) ----
  GDeMap.Add('Public member missing doc comment',
             'Public-Member ohne Doku-Kommentar');

  // ---- Naming-Familie erweitert (SCA118-119) ----
  GDeMap.Add('Exception class without E-prefix',
             'Exception-Klasse ohne E-Prefix');
  GDeMap.Add('Local constant should be UPPER_SNAKE_CASE',
             'Lokale Konstante sollte UPPER_SNAKE_CASE sein');

  // ---- Diff-Mode (CLI --diff <range>) ----
  GDeMap.Add('Git diff %s: %d file(s) to analyse',
             'Git-Diff %s: %d Datei(en) zu analysieren');

  // ---- Annotation-Overlay: Multi-Finding-Summary ----
  // Wird in uIDELineHighlighter.SetAllFindings benutzt wenn mehrere
  // Befunde auf der gleichen Zeile liegen. Die Bullet-Liste der einzelnen
  // Befunde steht im Desc-Text; der Titel zeigt die Anzahl.
  GDeMap.Add('%d findings on this line',
             '%d Befunde auf dieser Zeile');

  // Filter-Combo-Eintraege
  GDeMap.Add('Unused Local Var',         'Ungenutzte lokale Variable');
  GDeMap.Add('Unused Parameter',         'Ungenutzter Parameter');
  GDeMap.Add('Tautological Expression',  'Tautologischer Ausdruck');
  // DFM Phase 4
  GDeMap.Add('MasterSource set without MasterFields/IndexFieldNames - silent cross-join',
             'MasterSource gesetzt ohne MasterFields/IndexFieldNames - stiller Cross-Join');
  GDeMap.Add('Many DB components on one form - extract into a TDataModule',
             'Viele DB-Komponenten auf einer Form - in ein TDataModule extrahieren');
  GDeMap.Add('Master-Detail Unlinked',     'Master-Detail unverlinkt');
  GDeMap.Add('Data Module Split Hint',     'DataModule-Split-Vorschlag');
  // SQL-Dangerous + Format-Locale
  GDeMap.Add('UPDATE/DELETE/TRUNCATE without WHERE - affects ALL rows',
             'UPDATE/DELETE/TRUNCATE ohne WHERE - betrifft ALLE Zeilen');
  GDeMap.Add('Float format spec without TFormatSettings - locale-dependent decimal separator',
             'Float-Format ohne TFormatSettings - Locale-abh'#$E4'ngiger Dezimal-Trenner');
  GDeMap.Add('Dangerous SQL Statement',  'Gef'#$E4'hrliches SQL-Statement');
  GDeMap.Add('Format Locale Hint',       'Format-Locale-Hinweis');
  // SonarDelphi-Migration (SCA120-131) - Filter-Combo-Labels
  GDeMap.Add('Missing Raise',                'Fehlendes Raise');
  GDeMap.Add('Result Unassigned',            'Result nicht zugewiesen');
  GDeMap.Add('Re-Raise Exception',           'Exception erneut raisen');
  GDeMap.Add('Cast And Free',                'Cast vor Free');
  GDeMap.Add('Instance-Invoked Constructor', 'Konstruktor auf Instanz');
  GDeMap.Add('Inherited (empty)',            'Inherited (leer)');
  GDeMap.Add('Nil Comparison',               'Nil-Vergleich');
  GDeMap.Add('Raising Raw Exception',        'Basis-Exception raisen');
  GDeMap.Add('Date Format Settings',         'Datumsformat-Einstellungen');
  GDeMap.Add('Unicode -> Ansi Cast',         'Unicode '#$2192' Ansi Cast');
  GDeMap.Add('Char -> PChar Cast',           'Char '#$2192' PChar Cast');
  GDeMap.Add('IfThen Short-Circuit',         'IfThen ohne Short-Circuit');
  // Tools > Options - Hotkeys-Gruppe
  GDeMap.Add('Hotkeys',                      'Tastenk'#$FC'rzel');
  GDeMap.Add('Enable finding navigation (Ctrl+Alt+Up / Ctrl+Alt+Down)',
             'Befund-Navigation aktivieren (Strg+Alt+'#$2191' / Strg+Alt+'#$2193')');
  GDeMap.Add('Jump to the next / previous highlighted finding line in the current ' +
             'editor tab (wrap-around at file end/start). Disable to release the ' +
             'shortcut to the IDE default handler.',
             'Im aktuellen Editor-Tab zur n'#$E4'chsten / vorherigen markierten ' +
             'Befund-Zeile springen (Wrap-around am Datei-Ende/-Anfang). ' +
             'Deaktivieren gibt den Shortcut wieder an die IDE-Default-Belegung frei.');
  // DFM
  GDeMap.Add('Published method looks like an event handler but no component binds it',
             'Published-Methode sieht aus wie ein Event-Handler, aber keine Komponente bindet sie');
  GDeMap.Add('Component event is wired but the handler body is empty',
             'Komponenten-Event ist gebunden, aber der Handler-Body ist leer');
  GDeMap.Add('DFM declares a component but the form class has no published field for it',
             'DFM deklariert eine Komponente, aber die Form-Klasse hat kein published-Feld daf'#$FC'r');
  GDeMap.Add('Event handler in DFM points to a method that no longer exists',
             'Event-Handler im DFM zeigt auf eine Methode, die nicht (mehr) existiert');
  GDeMap.Add('Database credentials sit in the form file - move them out',
             'DB-Credentials liegen im Form-File - aus dem DFM heraus verlagern');
  GDeMap.Add('Input control sits directly on the form - wrap it in a panel',
             'Eingabe-Control sitzt direkt auf der Form - in ein Panel einbetten');
  GDeMap.Add('A single method handles too many component events - split it up',
             'Eine einzelne Methode bedient zu viele Komponenten-Events - aufteilen');
  GDeMap.Add('Component has both Action and OnClick - the OnClick handler is dead code',
             'Komponente hat Action UND OnClick - der OnClick-Handler ist toter Code');
  GDeMap.Add('Two sibling controls share the same TabOrder - tab navigation is undefined',
             'Zwei Geschwister-Controls teilen dieselbe TabOrder - Tab-Reihenfolge undefiniert');
  GDeMap.Add('Component class is on the project-defined forbidden list',
             'Komponenten-Klasse steht auf der Projekt-Forbidden-Liste');
  GDeMap.Add('Database component sits on a Form/Frame - move to a TDataModule',
             'DB-Komponente sitzt auf einer Form/Frame - in ein TDataModule verlegen');
  GDeMap.Add('Required dataset field has no DB-control binding it',
             'Required-Feld des DataSet hat keine UI-Bindung');
  GDeMap.Add('Required field is bound only to invisible controls',
             'Required-Feld nur an unsichtbare Controls gebunden');
  GDeMap.Add('DB-control class does not fit the field data type',
             'DB-Control-Klasse passt nicht zum Field-Data-Type');
  GDeMap.Add('SQL query is built from a UI input field - parameterize instead of concatenating',
             'SQL-Query aus UI-Eingabe gebaut - parametrisieren statt konkatenieren');
  GDeMap.Add('Master-detail wiring forms a cycle - opening the dataset will loop endlessly',
             'Master-Detail-Verkabelung bildet Zyklus - Open-Call l'#$E4'uft endlos');
  GDeMap.Add('Multiple components bind the same DataSource and DataField',
             'Mehrere Komponenten binden gleiche DataSource + DataField');
  GDeMap.Add('UI text in DFM is a literal string - route it through the localization layer',
             'UI-Text im DFM ist Stringliteral - '#$FC'ber die Lokalisierungs-Schicht f'#$FC'hren');
  GDeMap.Add('Component uses the IDE default name - rename for clarity',
             'Komponente nutzt IDE-Default-Namen - f'#$FC'r Klarheit umbenennen');

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
  GDeMap.Add('DFM as text: %s  Line: %d',
                                         'DFM als Text: %s  Zeile: %d');
  GDeMap.Add('DFM finding at line %d - .pas is modified, press Alt+F12 to view DFM as text',
                                         'DFM-Befund in Zeile %d - .pas wurde ge'#$E4'ndert, Alt+F12 zeigt die DFM als Text');
  GDeMap.Add('DFM viewer: %s  Line: %d', 'DFM-Viewer: %s  Zeile: %d');
  GDeMap.Add('Cancel Analysis',          'Analyse abbrechen');
  GDeMap.Add('File not found:',          'Datei nicht gefunden:');

  // ---- Hilfe-Panel ----
  GDeMap.Add('Select a row to see the fix hint',
                                         'Zeile w'#$E4'hlen f'#$FC'r L'#$F6'sungshinweis');
  GDeMap.Add('No fix hint available.',   'Kein L'#$F6'sungshinweis verf'#$FC'gbar.');
  GDeMap.Add('Before (problem)',         'Vorher (Problem)');
  GDeMap.Add('After (solution)',         'Nachher (L'#$F6'sung)');
  // Standalone-Kurzform "After" als eigene Caption (Annotation-Overlay
  // im IDE-Plugin nutzt den Begriff ohne den Klammer-Zusatz).
  GDeMap.Add('After',                    'Nachher');

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
  GDeMap.Add('Quick-Fix + AI prompt copied to clipboard: %s, line %s (%s)',
                                         'Quick-Fix + KI-Prompt in Zwischenablage: %s, Zeile %s (%s)');
  GDeMap.Add('Quick-Fix: no provider for ''%s'' - manual fix required',
                                         'Quick-Fix: kein Provider fuer ''%s'' - manuell beheben');
  GDeMap.Add('Quick-Fix: cannot locate source line',
                                         'Quick-Fix: Quell-Zeile nicht erreichbar');
  GDeMap.Add('Quick-Fix: line out of range',
                                         'Quick-Fix: Zeilen-Nummer ausserhalb der Datei');
  GDeMap.Add('Quick-Fix: pattern not matched on line %d - manual fix required',
                                         'Quick-Fix: Pattern auf Zeile %d nicht erkannt - manuell beheben');
  GDeMap.Add('Quick-Fix applied: %s',    'Quick-Fix angewendet: %s');
  GDeMap.Add('Quick-Fix: editor write failed (file not in IDE?)',
                                         'Quick-Fix: Editor-Write fehlgeschlagen (Datei nicht in der IDE offen?)');
  GDeMap.Add('Suppress: cannot locate source line',
                                         'Suppress: Quell-Zeile nicht erreichbar');
  GDeMap.Add('Suppress inserted: %s',    'Suppress eingefuegt: %s');
  GDeMap.Add('Suppress: editor write failed (file not in IDE?)',
                                         'Suppress: Editor-Write fehlgeschlagen (Datei nicht in der IDE offen?)');
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

  // ---- IDE-Plugin Tools-Options-Page (uIDESCAOptions) ----
  GDeMap.Add('Silent Mode',              'Silent-Modus');
  GDeMap.Add('Enable silent analysis (editor right-click + Ctrl+Alt+A)',
                                         'Silent-Analyse aktivieren (Editor-Rechtsklick + Strg+Alt+A)');
  GDeMap.Add('Editor right-click + Ctrl+Alt+A trigger a single-file analysis; ' +
             'findings appear as stripes + hover overlays in the editor (no dock).',
                                         'Editor-Rechtsklick + Strg+Alt+A starten eine Einzeldatei-Analyse; ' +
                                         'Befunde erscheinen als Markierungen + Hover-Overlays im Editor (kein Dock-Fenster).');
  GDeMap.Add('Rule-Set (analyser.ini [Rules])',
                                         'Regelsatz (analyser.ini [Rules])');
  GDeMap.Add('Profile (CLI/Form):',      'Profil (CLI/Form):');
  GDeMap.Add('Min-Severity:',            'Min-Schweregrad:');
  GDeMap.Add('IDE Profile:',             'IDE-Profil:');
  GDeMap.Add('Detectors (analyser.ini [Detectors])',
                                         'Detektoren (analyser.ini [Detectors])');
  GDeMap.Add('UsesCheck - report unused entries in uses clause ' +
             '(may produce false positives)',
                                         'UsesCheck - ungenutzte Eintr'#$E4'ge in uses-Klausel melden ' +
                                         '(kann False-Positives erzeugen)');
  GDeMap.Add('IncludeTests - analyse DUnit/DUnitX test units too',
                                         'IncludeTests - auch DUnit/DUnitX-Test-Units analysieren');
  GDeMap.Add('AutoDiscoverClasses - extend LeakyClasses with ' +
             'project-specific classes',
                                         'AutoDiscoverClasses - LeakyClasses um ' +
                                         'projektspezifische Klassen erweitern');

  // ---- IDE-Plugin Editor-Popup + View-Menue (uIDEAnalyserForm) ----
  GDeMap.Add('Analyse current file (silent)',
                                         'Aktuelle Datei analysieren (Silent)');
  GDeMap.Add('Static Code Analyser: analyse this file, no dock opens',
                                         'Static Code Analyser: diese Datei analysieren, kein Dock-Fenster wird ge'#$F6'ffnet');
  GDeMap.Add('Static Code Analysis',     'Statische Code-Analyse');

  // ---- Standalone Form: BtnBranch.Hint (uMainForm) ----
  GDeMap.Add('analyse only files changed in current branch',
                                         'nur Dateien analysieren, die im aktuellen Branch ge'#$E4'ndert wurden');
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
