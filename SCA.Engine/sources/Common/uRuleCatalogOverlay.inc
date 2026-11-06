// ==========================================================================
// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.
// Quelle: rules/sca-rules.<lang>.json (dort aendern, Generator laufen lassen)
//
// Einkompilierte Sprach-Overlays (Name, ShortDescription und
// FullDescription je Regel; leer = englischer Rueckfall).
// Rangfolge im Leser (TRuleCatalog.EnsureOverlay): lose Datei schlaegt
// diese Tabelle; die Tabelle schlaegt Englisch.
// ==========================================================================

const
  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_DE : array[0..205] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objekt ohne ausnahmesichere Freigabe erzeugt';
      ShortDesc: 'Objekt erzeugt, aber nicht zuverl' + #$00E4 + 'ssig freigegeben (m' + #$00F6 +
        'gliches Speicherleck)';
      FullDesc : 'Meldet vier Varianten. (1) never-freed: das Objekt wird ' + #$00FC +
        'berhaupt nie freigegeben - Warnung. (2) freed-outside-finally: ein Free ist vorhanden, steht aber au' +
        #$00DF + 'erhalb des sch' + #$00FC +
        'tzenden try/finally, sodass jede Ausnahme innerhalb des Blocks ein Leck erzeugt - Warnung. (3) return-value-not-freed: eine Funktion gibt ein frisch erzeugtes Objekt zur' +
        #$00FC +
        'ck, und der Aufrufer gibt es nie frei - Hinweis. (4) proven-leak: nie freigegeben UND die Variable verl' +
        #$00E4 +
        'sst die Methode nachweislich nie (kein Aufrufargument, kein Zuweisungsziel, kein Konstruktor-Argument mit Owner-Verdacht, kein Interface-Typ) - die einzige Variante, die als Fehler gemeldet wird. Zu welcher Variante ein Fund geh' +
        #$00F6 + 'rt, steht in properties.variant in der SARIF-Ausgabe und im L' + #$00F6 +
        'sungshinweis, den die Oberfl' + #$00E4 + 'che zeigt; der Meldungstext selbst tr' + #$00E4 +
        'gt nur den Variablennamen.'
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Leerer except-Block';
      ShortDesc: 'Leerer except-Block schluckt jede Ausnahme ohne Reaktion';
      FullDesc : 'Ein except-Block ohne Anweisungen f' + #$00E4 +
        'ngt jede Ausnahme ab, auch unerwartete (EAccessViolation, EOutOfMemory). Bugs werden unsichtbar. Die Ausnahme mindestens protokollieren oder erneut ausl' +
        #$00F6 + 'sen.'
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'SQL-String per Verkettung gebaut';
      ShortDesc: 'SQL-String per ''+''-Verkettung mit einem nicht-literalen Operanden gebaut (Injection-Risiko, wenn dieser Operand nicht vertrauensw' +
        #$00FC + 'rdig ist)';
      FullDesc : 'SQL per ''WHERE x='' + operand zu bauen erm' + #$00F6 +
        'glicht SQL-Injection, wenn dieser Operand nicht vertrauensw' + #$00FC +
        'rdig ist. Der Detektor meldet die VERKETTUNG - er verfolgt nicht, woher der Operand stammt, daher ist ein Fund ein Pr' +
        #$00FC + 'fhinweis, kein Beweis f' + #$00FC +
        'r eine Schwachstelle. Verkettungen nur aus Literalen, Integer-Formatmasken und bekannte Sanitizer sind bereits ausgenommen. Stattdessen parametrisierte Abfragen verwenden (Params.ParamByName(...).Value := ...).'
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Hartkodierte Zugangsdaten / API-Token';
      ShortDesc: 'Passwort, API-Schl' + #$00FC + 'ssel oder Token als String-Literal im Quelltext';
      FullDesc : 'Zugangsdaten im Quelltext landen in der Versionsverwaltung, in Build-Artefakten, in Decompilern und in Stacktraces. Geheimnisse in Umgebungsvariablen, den Anmeldedatenspeicher des Betriebssystems oder eine verschl' +
        #$00FC + 'sselte Konfiguration verlagern.'
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format(): Platzhalterzahl passt nicht';
      ShortDesc: 'Zahl der Platzhalter in Format() / FormatUtf8() weicht von der Zahl der Argumente ab';
      FullDesc : 'Nicht passende Platzhalter l' + #$00F6 +
        'sen zur Laufzeit EConvertError aus. Der Detektor behandelt RTL-Format (%s/%d/...) und den mORMot-Stil mit nacktem % (FormatUtf8/FormatString).'
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Datei konnte nicht gelesen oder geparst werden';
      ShortDesc: 'Parser-/IO-Fehler - Quelldatei unlesbar oder syntaktisch defekt';
      FullDesc : 'Sonderfall-Fund (kein Code-Defekt): die Datei konnte nicht geladen werden oder Lexer/Parser sind gescheitert. Deutet oft auf Encoding-Probleme, nicht aufl' +
        #$00F6 + 'sbare Includes oder echte Syntaxfehler hin.'
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Ungenutzte Unit in der uses-Klausel';
      ShortDesc: 'uses-Eintrag vermutlich ungenutzt (kein Bezeichner daraus wird referenziert)';
      FullDesc : 'Heuristik: sucht nach irgendeinem Bezeichner aus der eingebundenen Unit. Fehlalarme sind m' +
        #$00F6 + 'glich bei Units, die nur Klassen registrieren / ' + #$00FC +
        'ber initialization-Abschnitte globalen Zustand initialisieren.'
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'M' + #$00F6 + 'gliche nil-Dereferenzierung';
      ShortDesc: 'Zugriff auf eine Variable, die an dieser Stelle nil sein kann';
      FullDesc : 'Eine lokale Variable wird explizit auf nil gesetzt und danach dereferenziert (Methodenaufruf oder Property-Zugriff), ohne dass dazwischen eine Neuzuweisung oder eine nil-Pr' +
        #$00FC + 'fung steht. St' + #$00FC +
        'rzt zur Laufzeit mit EAccessViolation ab. Der Detektor verfolgt nur explizite `obj := nil`-Zuweisungen; ein Wert, den eine Funktion zur' +
        #$00FC +
        'ckgibt, die nil liefern kann (z. B. eine Find...-Methode), wird nicht verfolgt. Erkannte Absicherungen: eine Neuzuweisung, `Assigned(obj)` oder `obj <> nil` in einer if-Bedingung, ein fr' +
        #$00FC + 'hes `if obj = nil then Exit`, die ' + #$00DC +
        'bergabe von `obj` als Argument (eine m' + #$00F6 +
        'gliche var/out-Zuweisung) und nil-sichere Aufrufe wie `obj.Free`.'
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objekt ohne sch' + #$00FC + 'tzendes try/finally erzeugt';
      ShortDesc: '.Create ohne umschlie' + #$00DF + 'endes try/finally - Leck-Risiko im Ausnahmefall';
      FullDesc : #$00C4 + 'hnlich wie MemoryLeak (SCA001), aber strukturell gepr' + #$00FC +
        'ft: eine lokale Variable einer Klasse, die der Leck-Detektor verfolgt (die Liste [Detectors] LeakyClasses, z. B. TStringList), wird mit .Create erzeugt und in derselben Methode mit .Free oder FreeAndNil freigegeben, aber kein try/finally sch' +
        #$00FC + 'tzt den Code dazwischen - eine Ausnahme dort ' + #$00FC +
        'berspringt das Free, und das Objekt leckt. Ganz ohne Free bleibt der Detektor still (dieser Fall ist SCA001). Ebenfalls nicht gemeldet: ein Objekt, das als Ergebnis zur' +
        #$00FC + 'ckgegeben oder an einen Owner ' + #$00FC +
        'bergeben wird, und ein Bereich zwischen Create und Free, der nur Member des Objekts selbst aufruft (z. B. List.Add auf einer TStringList).'
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'M' + #$00F6 + 'gliche Division durch null';
      ShortDesc: 'Ganzzahl-Division (div / mod) durch eine Variable, die null sein kann';
      FullDesc : 'Die rechte Seite eines Integer-div oder -mod ist ein Parameter oder eine lokale Variable ohne vorherige Absicherung gegen null; zur Laufzeit l' +
        #$00F6 +
        'st das EDivByZero aus. Erkannte Absicherungen: eine if-Bedingung wie `Count <> 0`, `Count > 0` oder `Count >= 1` vor der Division, `if Count = 0 then Exit` (oder raise), eine for-Schleifenvariable, die bei 1 oder h' +
        #$00F6 +
        'her beginnt, und ein Divisor, dem nur Werte ungleich null zugewiesen werden. Ein Literal `div 0` / `mod 0` wird immer gemeldet. Den Gleitkomma-Operator / pr' +
        #$00FC + 'ft diese Regel nicht.'
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Code nach Exit/Raise ist unerreichbar';
      ShortDesc: 'Anweisung nach Exit, raise oder Halt ist toter Code';
      FullDesc : 'Alles nach einer unbedingten Abbruchanweisung (Exit, raise, Halt, Continue, Break) im selben Block wird nie ausgef' +
        #$00FC +
        'hrt. Meist Codereste aus einem Refactoring. Nicht gemeldet, wenn die Abbruchanweisung selbst in einem Bereich bedingter Kompilierung steht und die folgende Anweisung nicht (`{$IFDEF DEBUG} raise ...; {$ENDIF}` gefolgt von `Exit;`): ohne das Define ex' +
        'istiert die Abbruchanweisung nicht, und die n' + #$00E4 + 'chste Anweisung ist der tats' +
        #$00E4 + 'chlich durchlaufene Pfad. Diese Absicherung ist DEFINE-ABH' + #$00C4 + 'NGIG - f' +
        #$00FC + 'r einen Build, der das Define immer setzt, w' + #$00E4 + 're der unterdr' + #$00FC +
        'ckte Fund sachlich richtig. Der Analyser kann das ohne die Projekt-Defines nicht entscheiden und entscheidet zugunsten von "erreichbar".'
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'Methode ' + #$00FC + 'berschreitet die Zeilengrenze';
      ShortDesc: 'Methodenrumpf l' + #$00E4 +
        'nger als das konfigurierte Maximum (Vorgabe: mehr als 50 Zeilen und mehr als 30 Anweisungen)';
      FullDesc : 'Lange Methoden korrelieren mit hoher Fehlerdichte (Robert C. Martin, McConnell): der Leser h' +
        #$00E4 + 'lt den Kontext im Arbeitsged' + #$00E4 + 'chtnis, und sobald die Methode ' +
        #$00FC + 'ber einen Bildschirm hinausreicht, l' + #$00E4 + 'uft dieser Kontext ' + #$00FC +
        'ber. Lange Methoden widersetzen sich au' + #$00DF +
        'erdem Unit-Tests - das Test-Setup dupliziert am Ende internen Zustand. Refactoring: zusammengeh' +
        #$00F6 + 'rige Bl' + #$00F6 +
        'cke in private Hilfsroutinen herausziehen (ParseInput/Validate/Persist) oder nach Verantwortlichkeit aufteilen (Daten holen vs. transformieren vs. ausgeben). Eine Methode wird nur gemeldet, wenn BEIDE Grenzen ' +
        #$00FC + 'berschritten sind - standardm' + #$00E4 + #$00DF +
        'ig mehr als 50 Rumpfzeilen und mehr als 30 Anweisungen, konfigurierbar ' + #$00FC +
        'ber [Detectors] LongMethodMaxBodyLines und LongMethodMaxStatements -, sodass langer, aber flacher Code wie eine Tabelleninitialisierung still bleibt. Gez' +
        #$00E4 +
        'hlt werden die Zeilen des Methodenrumpfs ab seinem `begin`, Kommentare und Leerzeilen eingeschlossen. Die Erkennung zusammengesetzter Anweisungen ignoriert verschachtelte anonyme Methoden, sodass ein Methodenrumpf, der nur eine Closure enth' +
        #$00E4 + 'lt, nicht f' + #$00E4 + 'lschlich gemeldet wird.'
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Zu viele Parameter';
      ShortDesc: 'Methode hat mehr Parameter als konfiguriert erlaubt (Vorgabe 5)';
      FullDesc : 'Hohe Parameterzahlen sind ein Fr' + #$00FC + 'hindikator f' + #$00FC +
        'r eine Verletzung des SRP: die Routine jongliert mit Belangen, die aufgeteilt geh' + #$00F6 +
        'ren. Lange Listen bringen au' + #$00DF +
        'erdem Verwechslungen bei der Position mit sich (welcher war noch mal der dritte Integer?) und zwingen Aufrufer, Vorgabewerte zu f' +
        #$00FC + 'llen, die wom' + #$00F6 + 'glich nicht zutreffen. Refactoring: zusammengeh' +
        #$00F6 + 'rige Parameter in einem Record b' + #$00FC +
        'ndeln (TOrderInput), Konfiguration in ein Builder-Muster ' + #$00FC + 'berf' + #$00FC +
        'hren (FluentQuery.Where(...).OrderBy(...)) oder die Methode entlang einer Achse aufteilen (SaveOrder + SaveOrderItems). Schwelle ' +
        #$00FC + 'ber [Detectors] LongParamListMaxParams (Vorgabe 5). out-/var-Parameter z' + #$00E4 +
        'hlen genauso wie Wertparameter; das implizite Self bei Klassenmethoden z' + #$00E4 +
        'hlt nicht.'
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Zahlenliteral ohne benannte Konstante';
      ShortDesc: 'Zahlenliteral im Ausdruck - in eine benannte Konstante herausziehen';
      FullDesc : 'Zahlenliterale, die direkt in die Gesch' + #$00E4 +
        'ftslogik eingebettet sind, tragen keine Bedeutung: `if RetryCount > 3` zwingt jeden Leser zu raten, wof' +
        #$00FC + 'r die 3 steht, und zwingt bei jeder Wartungs' + #$00E4 +
        'nderung dazu, jedes Vorkommen von Hand zu finden. Eine benannte Konstante herausziehen, damit der Wert einen dokumentierten Zweck und genau eine ma' +
        #$00DF + 'gebliche Quelle hat. Der Detektor ' + #$00FC +
        'berspringt Trivialwerte (0, 1, 2, -1, g' + #$00E4 + 'ngige Zweierpotenz-Gr' + #$00F6 +
        #$00DF + 'en, Indizierung in bekannterma' + #$00DF +
        'en winzige Collections) - die aktive Liste steht in [Detectors] MagicNumberTrivials. Schleifengrenzen gegen `Length(arr)` und der Array-Index 0 werden ebenfalls ignoriert. ' +
        #$00DC + 'ber die globale Konfiguration lassen sich projektspezifische Trivialwerte erg' +
        #$00E4 + 'nzen (z. B. eine feste PageSize).'
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'String-Literal an mehreren Stellen wiederholt';
      ShortDesc: 'Dasselbe String-Literal kommt in einer Datei dreimal oder ' + #$00F6 +
        'fter vor - in eine Konstante herausziehen';
      FullDesc : 'Wiederholte Strings sind Gefahren durch ' + #$00C4 +
        'nderungskopplung (ein Tippfehler an einer Stelle weicht still von den anderen ab). In eine const herausziehen, besonders bei Meldungen f' +
        #$00FC + 'r den Benutzer. Der Detektor z' + #$00E4 +
        'hlt String-Literale mit mindestens 4 Zeichen in den Zuweisungen und Aufrufen einer Datei und meldet ein Literal ab seinem dritten Vorkommen; Literale an anderen Stellen (zum Beispiel in raise-Anweisungen) werden nicht gez' +
        #$00E4 + 'hlt, ebenso wenig ''true'', ''false'' und ''null''.'
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Dateisystempfad als String-Literal';
      ShortDesc: 'Hartkodierter C:\-, UNC- oder Linux-Pfad im Quelltext';
      FullDesc : 'Hartkodierte Pfade verhindern Portabilit' + #$00E4 +
        't und CI-Deployment. Konfigurationsdateien, Umgebungsvariablen oder plattformbewusste Pfad-Hilfsroutinen verwenden (TPath.Combine usw.).'
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage im Produktivcode';
      ShortDesc: 'Unqualifizierter Aufruf von WriteLn, ShowMessage(Pos) oder OutputDebugString in einer Nicht-Test-Unit';
      FullDesc : 'WriteLn / ShowMessage / OutputDebugString / OutputDebugStringA in Nicht-Test-Code ist fast immer ' +
        #$00FC +
        'brig gebliebenes Debugging: besonders ShowMessage blockiert den UI-Thread und taugt f' +
        #$00FC +
        'r keinen Produktiv-Codepfad. Durch einen strukturierten Logger ersetzen (TLogger, mORMot TSynLog, log4d), damit die Aufrufstelle Schweregrad, Kategorie und Quellposition erfasst und der Betrieb die Ausf' +
        #$00FC + 'hrlichkeit zur Laufzeit regeln kann. Der Detektor ' + #$00FC +
        'berspringt Units in Test-/Sample-/Demo-Verzeichnissegmenten (die projektweite Fixture-Pfad-Definition: `test`, `tests`, `unittest`, `unittests`, `samples`, `demos`, verankert unterhalb der Scan-Wurzel) und Konsolen-/Test-Runner-Units (`*Console*`, `*' +
        'TestProject*` im Unit-Dateinamen) - Ausgaben dort sind beabsichtigt, kein ' + #$00FC +
        'brig gebliebenes Debugging. Umgesetzt am 2026-09-05, nachdem das Audit vom 2026-09-04 ergeben hatte, dass das urspr' +
        #$00FC + 'nglich versprochene ' + #$00DC +
        'berspringen nie gebaut worden war. Ein Marker `// noinspection DebugOutput` unterdr' +
        #$00FC + 'ckt einzelne Zeilen (z. B. interaktive CLI-Banner).'
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'Blockverschachtelung ' + #$00FC + 'berschreitet die Grenze';
      ShortDesc: 'Verschachtelungstiefe von if/for/while h' + #$00F6 +
        'her als konfiguriert (Vorgabe 4); eine else-if-Kette z' + #$00E4 +
        'hlt wie ein case als EINE Ebene';
      FullDesc : 'Tiefe Verschachtelung schadet der Lesbarkeit und zeigt, dass die Methode zu viel tut. Guard-Clauses (fr' +
        #$00FC + 'hes Exit) verwenden oder innere Bl' + #$00F6 +
        'cke in Hilfsmethoden herausziehen. Ein Block wird gemeldet, wenn seine Tiefe die Grenze ' +
        #$00FC + 'berschreitet - bei der Vorgabe 4 wird die f' + #$00FC +
        'nfte Verschachtelungsebene gemeldet.'
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'TODO/FIXME-Marker im Kommentar';
      ShortDesc: 'Offener TODO-, FIXME-, HACK- oder XXX-Marker - vor dem Release aufl' + #$00F6 + 'sen';
      FullDesc : 'Offene Arbeitsmarker (TODO, FIXME, HACK, XXX) bilden eine parallele Aufgabenverwaltung im Quelltext. Das Muster scheitert durch Anh' +
        #$00E4 +
        'ufung: Marker, die im Abstand von Jahren hinzukamen, werden nie gemeinsam gesichtet, der urspr' +
        #$00FC + 'ngliche Autor geht, und der n' + #$00E4 +
        'chste Leser kann nicht erkennen, ob das TODO noch relevant ist oder stillschweigend ausgeliefert wurde. SCA macht jeden solchen Marker sichtbar, damit CI-Gates einen Release-Branch ohne TODOs oder eine Sichtung zur PR-Zeit erzwingen k' +
        #$00F6 +
        'nnen. Erkannte Formen: Kommentare `// TODO` und `{ TODO ... }`, der Marker als ganzes Wort, mit optionalem Jira-ID-Suffix (`// TODO PROJ-123: ...`). TODO, FIXME und HACK treffen unabh' +
        #$00E4 + 'ngig von Gro' + #$00DF + '-/Kleinschreibung, XXX nur in Gro' + #$00DF +
        'buchstaben (ein kleingeschriebenes `xxx` ist fast immer ein Platzhalter). `(* ... *)`-Kommentare werden nicht durchsucht, und die Markermenge ist fest. Ein Marker, der bleiben muss, l' +
        #$00E4 + 'sst sich mit `// noinspection TodoComment` unterdr' + #$00FC + 'cken.'
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Leerer Methodenrumpf';
      ShortDesc: 'Methodenrumpf enth' + #$00E4 + 'lt keine Anweisung';
      FullDesc : 'Eine leere Methode kann auf eine vergessene Implementierung hinweisen, auf ein nie weiterverfolgtes TODO oder auf einen Interface-Stub. Die Absicht explizit machen (assert, Ausnahme oder Kommentar). Nicht gemeldet: ein leerer Rumpf, der bereits einen' +
        ' erkl' + #$00E4 + 'renden Kommentar tr' + #$00E4 +
        'gt ({ do nothing }, // default implementation does nothing) - das *ist* eine der drei Korrekturen, die die Regel verlangt. Nicht als Absicht gez' +
        #$00E4 +
        'hlt: Compiler-Direktiven ({$REGION}, {$IFDEF}) und auskommentierter Code (erkannt am abschlie' +
        #$00DF + 'enden Semikolon). Das schw' + #$00E4 +
        'cht die Projektregel nicht ab, dass Kommentare nie als Code-*Verwendung* z' + #$00E4 +
        'hlen - hier geht es um dokumentierte Absicht, nicht um Verwendung.'
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Duplizierter Codeblock';
      ShortDesc: 'Mehrere identische Codebl' + #$00F6 + 'cke (ab der konfigurierten Mindestzeilenzahl)';
      FullDesc : 'Erkennt N+ aufeinanderfolgende identische Zeilen, die zwei- oder mehrmals in derselben Datei vorkommen (Vorgabe-Minimum: 8 Zeilen; Kopien in verschiedenen Dateien werden nicht verglichen). Der DRY-Versto' +
        #$00DF + ' erzeugt ' + #$00C4 +
        'nderungskopplung: ein Bugfix an einer Kopie weicht still von den anderen ab, und Reviewer k' +
        #$00F6 +
        'nnen nicht leicht erkennen, dass eine Verhaltenskorrektur nur eine von N Aufrufstellen erfasst hat. Refactoring: in eine Hilfsmethode oder eine gemeinsame Konstante herausziehen. Zeilen werden normalisiert (getrimmt, kleingeschrieben, Folgen von Leer' +
        'raum zusammengefasst), damit kosmetische Unterschiede kein echtes Duplikat verdecken. Triviale Zeilen (leer, begin, end, else, try, finally, except, reine Kommentarzeilen) z' +
        #$00E4 + 'hlen nicht zu einem Block. Schwelle ' + #$00FC +
        'ber [Detectors] DuplicateBlockMinLines.'
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'Methode ' + #$00FC + 'berschreitet die McCabe-Komplexit' + #$00E4 + 't';
      ShortDesc: 'Zyklomatische Komplexit' + #$00E4 + 't ' + #$00FC +
        'ber der konfigurierten Schwelle (Vorgabe 10)';
      FullDesc : 'Die McCabe-Komplexit' + #$00E4 + 't z' + #$00E4 +
        'hlt Entscheidungspunkte (1 Basis + if + case-Zweig + for/while/repeat + on-Handler + and/or/xor). Hohe Komplexit' +
        #$00E4 + 't ist schwer zu testen und zu verstehen.'
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'Selbst definierte Regel';
      ShortDesc: 'Muster aus einer Regel getroffen, die aus analyser-rules.yml geladen wurde';
      FullDesc : 'Generische Fundart f' + #$00FC +
        'r benutzerdefinierte Regex-/AST-Regeln, die zur Laufzeit aus analyser-rules.yml geladen werden. Konkrete Regel-ID, Meldung und Schweregrad kommen aus dem YAML-Eintrag; dieser Katalogeintrag ist ein Platzhalter, damit Dispatcher und SARIF-Exporter sta' +
        'bile Metadaten haben.'
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Komponente mit Vorgabenamen';
      ShortDesc: 'Komponente tr' + #$00E4 +
        'gt noch den Assistenten-Vorgabenamen (Button1, Edit3, Panel2 ...)';
      FullDesc : 'Vorgabenamen verbergen die Absicht und vereiteln Find-Usages-/Umbenennungs-Refactorings. UI-Controls so umbenennen, dass sie ihren Zweck vermitteln (btnSave, edUserName, pnlToolbar ...).'
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Hartkodierter UI-Text im DFM';
      ShortDesc: 'Caption, Hint oder Text als Literal im DFM statt ' + #$00FC + 'ber die i18n-Schicht';
      FullDesc : 'Benutzersichtbare Strings, die in einer .dfm eingebettet sind, lassen sich nicht lokalisieren, nicht A/B-testen und nicht in einem ' +
        #$00DC + 'bersetzungskatalog f' + #$00FC +
        'hren. Beim Aufbau des Formulars aus einem resourcestring oder einer i18n-Hilfsroutine zuweisen. Nicht gemeldet: Captions aus einem einzelnen Zeichen in Symbolschriften (Webdings/Wingdings/Marlett/Symbol - Icons, kein Text), DFM-Werte, die die Formula' +
        'r-Unit aus einem resourcestring ersetzt (tote Platzhalter), und Formulare, deren Unit einen DFM-' +
        #$00DC +
        'bersetzer zur Laufzeit verwendet (gnugettext/dxgettext/JvGnugettext, TranslateComponent, Dev-Cpp MultiLangSupport, cnwizards CnLangMgr, uLocalization*) - dort IST der DFM-Text die msgid-Quelle der i18n-Schicht.'
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Hartkodierte DB-Zugangsdaten im DFM';
      ShortDesc: 'Klartext-Password oder ConnectionString mit Pwd= an einer DB-Komponente';
      FullDesc : 'In einer .dfm gespeicherte Datenbank-Zugangsdaten gelangen in die Versionsverwaltung, in Build-Artefakte und in jeden Decompiler. Geheimnisse in Umgebungsvariablen, den Anmeldedatenspeicher des Betriebssystems oder eine verschl' +
        #$00FC + 'sselte Konfiguration verlagern und zur Laufzeit zuweisen.'
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Doppelte (DataSource, DataField)-Bindung';
      ShortDesc: 'Zwei oder mehr Controls binden dasselbe Paar aus DataSource und DataField';
      FullDesc : 'Wenn der Benutzer ein gebundenes Control bearbeitet, erh' + #$00E4 +
        'lt das zweite eine parallele Aktualisierung vom Dataset - race-anf' + #$00E4 +
        'llige, schwer zu debuggende ' + #$00DC +
        'berschreibungen. Jedes (DataSource, DataField) an genau ein Control binden.'
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'DFM-Ereignisbehandler zeigt auf fehlende Methode';
      ShortDesc: 'OnClick / On... verweist auf eine Methode, die es in der Formularklasse nicht gibt';
      FullDesc : 'Das DFM-Streaming st' + #$00FC +
        'rzt beim Laden des Formulars mit *"class TForm has no published method X"* ab. Meist verursacht durch eine manuelle Umbenennung in der .pas, ohne die .dfm anzupassen.'
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Verwaister Ereignisbehandler';
      ShortDesc: 'Published-Methode in TNotifyEvent-Form hat keine DFM-Bindung';
      FullDesc : 'Die Methode sieht aus wie ein Ereignisbehandler (Sender: TObject), aber keine .dfm referenziert sie - Bindungen von Collection-Items (item ... OnAction = Foo, z. B. WebModule-Actions oder Plugin-Befehlslisten) z' +
        #$00E4 +
        'hlen als Referenzen. Bekannte Grenzen: Ereignisbehandler, die nur in einer Vorfahren-DFM au' +
        #$00DF +
        'erhalb des Scans gebunden oder im Code zugewiesen werden, werden weiterhin gemeldet. Vermutlich ein ' +
        #$00DC + 'berbleibsel eines gel' + #$00F6 + 'schten Controls - entfernen oder anbinden.'
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Leerer gebundener Ereignisbehandler';
      ShortDesc: 'Ereignis ist im DFM gebunden, die Methode existiert, der Rumpf ist leer';
      FullDesc : 'Ein leerer Ereignisbehandler mit aktiver DFM-Bindung ist fast immer ein Stub, der vergessen wurde, nachdem der Designer ihn angelegt hat. Entweder die Bindung entfernen oder den Ereignisbehandler implementieren.'
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'DFM-Komponente ohne published-Feld';
      ShortDesc: 'Komponente im DFM hat kein passendes published-Feld in der Formularklasse - veralteter DFM-Eintrag (Schema-Drift)';
      FullDesc : 'Eine benannte DFM-Komponente ohne zugeh' + #$00F6 +
        'riges published-Feld ist eine Schema-Abweichung, kein Laufzeitfehler: der Streamer l' +
        #$00F6 + 'st das Feld ' + #$00FC + 'ber FieldAddress auf, erh' + #$00E4 + 'lt nil und ' +
        #$00FC +
        'berspringt die Zuweisung still (kein EReadError). Die Komponente wird trotzdem erzeugt, ist aber aus dem Code nicht erreichbar - ein veralteter/toter DFM-Eintrag, der aufger' +
        #$00E4 + 'umt werden sollte.'
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Zyklische DataSource-/Master-Detail-Schleife';
      ShortDesc: 'Zyklus in den Kanten DataSource.DataSet / DataSet.MasterSource';
      FullDesc : 'Ein Zyklus im Master-Detail-Graphen verursacht w' + #$00E4 +
        'hrend BeforeOpen oder bei jedem Refresh eine Endlosrekursion und bringt den Prozess per Stack' +
        #$00FC + 'berlauf zum Absturz. Den Zyklus aufbrechen, indem eine der Verkn' + #$00FC +
        'pfungen entfernt wird.'
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'SQL-Property aus UI-Eingabe gebaut';
      ShortDesc: 'Query.SQL aus Text- oder Caption-Properties von Formular-Controls zusammengesetzt';
      FullDesc : 'Eine SQL-Property einer DB-Abfrage (TADOQuery / TFDQuery / TUniQuery / TZQuery / TKSQLQuery.SQL.Text) wird zusammengesetzt, indem die Property Text / Caption / Hint / EditText / ItemText eines UI-Eingabe-Controls (TEdit, TComboBox, TMaskEdit, ...) ve' +
        'rkettet wird - klassische SQL-Injection ' + #$00FC +
        'ber das Formular. Ein Benutzer, der `'' OR ''''1''''=''''1'' --` in das Suchfeld tippt, liest beliebige Zeilen; `''; DROP TABLE Users; --` ist zerst' +
        #$00F6 + 'rerisch. Refactoring: benannte Parameter binden und ' + #$00FC +
        'ber ParamByName zuweisen, nie verketten. Dieser Detektor ist das DFM-/UI-Pfad-Gegenst' +
        #$00FC + 'ck zu SCA003 (lexikalische SQL-Injection) und SCA058 (gef' + #$00E4 +
        'hrliche SQL-Anweisung).'
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Pflichtfeld ohne UI-Bindung';
      ShortDesc: 'TField mit Required=True hat kein gebundenes Eingabe-Control';
      FullDesc : 'Ein Pflichtfeld, das der Benutzer nicht erreichen kann, l' + #$00E4 +
        'sst jedes Insert mit ''Field X must have a value'' scheitern. Entweder ein Control binden oder das Required=True entfernen.'
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Pflichtfeld nur an unsichtbaren Controls';
      ShortDesc: 'TField mit Required=True ist nur an Controls mit Visible=False gebunden';
      FullDesc : 'Das Control existiert, aber der Benutzer kann es weder sehen noch bedienen - Inserts scheitern jedes Mal. Mindestens ein gebundenes Control sichtbar machen oder das Required=True entfernen.'
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'UI-Control passt nicht zum TField-Typ';
      ShortDesc: 'Klasse des DB-Controls passt nicht zu TField.DataType (TDBEdit f' + #$00FC +
        'r ein TBooleanField)';
      FullDesc : 'Der Benutzer sieht den Rohwert und kann den Typ verf' + #$00E4 + 'lschen. Ein Control w' +
        #$00E4 + 'hlen, das zum Feldtyp passt (TDBCheckBox f' + #$00FC +
        'r Booleans, TDBLookupComboBox f' + #$00FC + 'r Fremdschl' + #$00FC + 'ssel).'
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'Doppelte TabOrder unter Geschwistern';
      ShortDesc: 'Zwei Geschwister-Controls im selben Parent teilen sich denselben TabOrder-Wert';
      FullDesc : 'Die VCL-Serialisierung toleriert doppelte TabOrder, aber die Tab-Navigation h' + #$00E4 +
        'ngt dann von der Deklarationsreihenfolge ab und wird f' + #$00FC +
        'r den Benutzer unvorhersehbar. Neu nummerieren, sodass TabOrder je Parent eindeutig ist.'
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Komponente nutzt eine verbotene Klasse';
      ShortDesc: 'Komponentenklasse steht auf der ForbiddenClasses-Liste des Projekts';
      FullDesc : 'Durchsetzung des Style-Guides f' + #$00FC +
        'r projektspezifische Klassenverbote (TQuery, TLabel, wenn ein TStyledLabel vorhanden ist, ...). Der Detektor bleibt still, solange das Projekt nicht `[Components] ForbiddenClasses=...` in analyser.ini setzt.'
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'DB-Komponente auf einem UI-Formular';
      ShortDesc: 'TFDQuery / TFDConnection direkt auf einem TForm oder TFrame statt in einem DataModule';
      FullDesc : 'Datenbank-Infrastruktur auf einem UI-Formular koppelt Persistenz an Darstellung - schwer wiederzuverwenden, schwer zu testen. In ein TDataModule verschieben und vom Formular aus referenzieren.'
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Formular' + #$00FC + 'bergreifender Feldzugriff';
      ShortDesc: 'Code in Form1 liest oder schreibt Form2.<published_field> direkt';
      FullDesc : #$00DC +
        'ber Formulare hinweg auf ein Kind-Control zuzugreifen verletzt die Kapselung - jede Umbenennung in Form2 macht Form1 unbemerkt kaputt. Stattdessen eine Property oder Methode an Form2 bereitstellen.'
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Eingabe-Control direkt auf dem TForm';
      ShortDesc: 'Eingabe-Control sitzt auf dem Formular, statt in einem TPanel oder TGroupBox eingebettet zu sein';
      FullDesc : 'Ein geschichtetes Layout (Form > Panel > Group > Controls) macht Gr' + #$00F6 + #$00DF +
        'en' + #$00E4 +
        'nderung, DPI-Skalierung und Theming deutlich einfacher. Controls in einen Layout-Container einbetten. FPC-/Lazarus-Dialekt: diese Regel wird ' +
        #$00FC +
        'bersprungen, wenn der Scan mit --dialect=fpc (oder einem .lpi-/.lpk-/.lpg-Projekt) l' +
        #$00E4 + 'uft - das VCL-Schichtenmodell, das sie pr' + #$00FC + 'ft, gilt nicht f' + #$00FC +
        'r LCL-Formulare.'
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Ereignisbehandler mit zu vielen Bindungen';
      ShortDesc: 'Eine einzelne Methode h' + #$00E4 +
        'ngt an N oder mehr Komponenten-Ereignissen (Vorgabe N=5)';
      FullDesc : 'Spaghetti-Indikator: ein Ereignisbehandler, der viele unzusammenh' + #$00E4 +
        'ngende Ereignisse bedient, ist schwer zu lesen, schwer zu ' + #$00E4 +
        'ndern und hat fast immer Koh' + #$00E4 +
        'sionsprobleme. Nach Verantwortlichkeit aufteilen. Gemeldet, wenn eine Methode in einer DFM an 5 oder mehr Komponenten-Ereignisse gebunden ist und die Bindungen gemischt sind - verschiedene Komponentenklassen oder verschiedene Ereignisse. Ein Ereignis' +
        'behandler, den Komponenten einer Klasse f' + #$00FC + 'r dasselbe Ereignis teilen (zw' +
        #$00F6 + 'lf Farbbuttons mit einem OnClick), ist eine parametrisierte B' + #$00FC +
        'ndelung und wird nicht gemeldet.'
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Komponente hat Action und OnClick';
      ShortDesc: 'Action und OnClick sind beide gesetzt - der explizite OnClick gewinnt, die TAction-Verdrahtung ist tot';
      FullDesc : 'Wenn beide gesetzt sind, gewinnt zur Laufzeit der EXPLIZITE OnClick-Handler: TControl.Click ruft FOnClick auf, sobald es zugewiesen ist und nicht auf das OnExecute der Action zeigt - nur andernfalls l' +
        #$00E4 +
        'uft ActionLink.Execute (dieselbe Logik in TMenuItem.Click). Die doppelte Verdrahtung ist der Smell: einer der beiden Pfade ist tot. NICHT gemeldet, wenn der OnClick genau auf den OnExecute-Handler der gebundenen Action zeigt, die in derselben DFM/LFM' +
        ' gefunden wird - beide Pfade f' + #$00FC +
        'hren dann dieselbe Prozedur aus (die Lazarus-IDE speichert diese Kombination als Speicherartefakt in jeder LFM).'
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Lange String-Verkettung - besser Format()';
      ShortDesc: 'Mehrteilige String-Verkettung - in einen Format()-Aufruf ' + #$00FC + 'berf' + #$00FC +
        'hren';
      FullDesc : 'Ketten wie `''a'' + Var + ''b'' + IntToStr(N)` (drei oder mehr Verkettungen mit nicht-literalen Segmenten) sind schwerer zu ' +
        #$00FC + 'berblicken und schwerer zu ' + #$00FC +
        'bersetzen als `Format(''a%sb%d'', [Var, N])`: jedes IntToStr / FloatToStr / FormatDateTime mitten in einem String ist eine weitere Stelle, an der ein `resourcestring` die Meldungsvorlage nicht erfassen kann. Der Detektor betrachtet Zuweisungen, deren r' +
        'echte Seite mindestens drei `+`-Operatoren (vier oder mehr Terme) mit mindestens einem nicht-literalen Term hat, sodass triviale F' +
        #$00E4 +
        'lle (`''<'' + Name + ''>''`) still bleiben; eine Verkettung, die direkt als Aufrufargument ' +
        #$00FC + 'bergeben wird, wird nicht gepr' + #$00FC + 'ft. ' + #$00DC +
        'bersprungen werden rechte Seiten, die bereits Format aufrufen, Zuweisungen an SQL-Properties (die deckt SCA003 ab) und Zeilen unter einem aktiven `// noinspection ConcatToFormat`. Die gemeldete Form kann in performancekritischen inneren Schleifen bea' +
        'bsichtigt sein, in denen die Varargs von Format boxen; f' + #$00FC +
        'r diesen Fall ist der Unterdr' + #$00FC + 'ckungs-Marker da.'
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'with-Anweisung - Scope-Verdeckung, vor der der Compiler nicht warnt';
      FullDesc : 'Marco Cantu, delphi.org und Stack Overflow z' + #$00E4 + 'hlen `with` ' + #$00FC +
        'bereinstimmend zu den h' + #$00E4 + 'ufigsten Fehlerquellen in Delphi. Bezeichner aus dem ' +
        #$00E4 + 'u' + #$00DF +
        'eren Scope werden still von Membern des with-Ziels verdeckt. Stattdessen eine lokale Variable als Alias verwenden.'
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto fehlt';
      ShortDesc: 'for i := 10 to 1 do - der Schleifenrumpf l' + #$00E4 + 'uft nie';
      FullDesc : '`for i := 10 to 1 do` ist ein downto-vs-to-Tippfehler: in Pascal iteriert eine `to`-Schleife mit Start > Ende nullmal, sodass der Rumpf still nie l' +
        #$00E4 +
        'uft und der Bug sich als fehlende Seiteneffekte ohne Compiler-Warnung zeigt. Der Detektor vergleicht Integer-Literale auf beiden Seiten, ein optionales f' +
        #$00FC + 'hrendes Minus eingeschlossen (`for i := 5 to -1` wird gemeldet); Ausdr' + #$00FC +
        'cke und Konstanten wie `Length(L)-1` oder `High(A)` werden nicht ausgewertet. Schleifen mit variablen Grenzen sind ausgenommen - sie k' +
        #$00F6 +
        'nnen je nach Laufzeitdaten legitimerweise nichts tun. Um absteigend zu iterieren, `downto` schreiben; um "m' +
        #$00F6 + 'glicherweise leer" explizit auszudr' + #$00FC +
        'cken, mit einem `if From <= To` absichern.'
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Selbstzuweisung - wirkungslos oder ein Copy-Paste-Vertipper';
      FullDesc : 'Gemeldet nur, wenn das Ziel nachweislich ein Speicherplatz ist: eine lokale Variable, ein Parameter, Result, eine Zuweisung an den Funktionsnamen, ein in derselben Unit deklariertes Feld - oder ein Member-Pfad (Pt.Y, R^.iType), dessen Wurzel ein solc' +
        'her Speicherplatz ist und bei dem jedes Segment ein einfaches Record-Feld ist, aufgel' +
        #$00F6 + 'st ' + #$00FC +
        'ber die eigenen Record-Deklarationen der Unit plus eine kuratierte RTL-Liste (TPoint-, TRect-Felder, ...). Property-Ziele bleiben in jeder Position still - das Schreiben auf eine Property f' +
        #$00FC +
        'hrt ihren Setter aus, der den Wert begrenzen, erneut anwenden oder umformatieren kann (TopLine := TopLine begrenzt gegen das in der Gr' +
        #$00F6 + #$00DF + 'e ge' + #$00E4 +
        'nderte Fenster; TRectF.Height := TRectF.Height schreibt Bottom). Indizierte Pfade (a[i]) und Namen, die sich nicht aufl' +
        #$00F6 +
        'sen lassen, bleiben ebenfalls still. Der Kompromiss ist bewusst: unbekannte Formen werden zu falsch Negativen, nie zu Fehlalarmen. Result := Result; zum Stummschalten eines Compiler-Hints wird weiterhin gemeldet und l' +
        #$00E4 + 'sst sich mit einem // noinspection-Kommentar direkt ' + #$00FC +
        'ber der Zeile unterdr' + #$00FC + 'cken.'
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Virtueller Aufruf im Konstruktor';
      ShortDesc: 'Virtuelle Methode aus dem Konstruktor gerufen - die Ableitung sieht ein halb initialisiertes Self';
      FullDesc : 'C++ FAQ 23.5 / *Effective Java* Item 17 in Delphi-Form: ein virtueller Aufruf in einem Konstruktor f' +
        #$00FC +
        'hrt das am weitesten abgeleitete Override aus, bevor die Felder der Ableitung initialisiert sind. Auf einen nicht-virtuellen Hook nach der Konstruktion verschieben.'
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N ohne Absicherung';
      ShortDesc: '`Length(s) - K` bzw. `.Count - K` mit K >= 2 ohne Absicherung - negativer Index oder negative Anzahl, wenn die Eingabe k' +
        #$00FC + 'rzer als K ist';
      FullDesc : '`Length` und `.Count` liefern einen vorzeichenbehafteten Integer, daher ist `Length(s) - 4` bei einem String mit weniger als vier Zeichen schlicht eine negative Zahl - und diese Zahl geht meist direkt in einen Index, eine Move-Position oder eine Anza' +
        'hl: `s[Length(s) - 3]` liest vor dem ersten Zeichen (ein Bereichsfehler mit $R+, Datenm' +
        #$00FC +
        'll oder eine Access Violation ohne), `Move(s[Length(s) - 4], Buf, 4)` kopiert von au' +
        #$00DF +
        'erhalb des Strings. Der Detektor meldet `Length(...)` und `.Count` gefolgt von `- K`, wobei K ein Integer-Literal von 2 oder mehr ist. `- 1` wird ' +
        #$00FC + 'bersprungen: `for I := 0 to Length(s) - 1` l' + #$00E4 +
        'uft bei einem leeren String einfach nullmal. Es ist ein lexikalischer Hinweis - eine vorangehende Absicherung `if Length(s) >= K` wird nicht gesehen. RTL-Hilfsroutinen bevorzugen, die mit kurzer Eingabe zurechtkommen (ExtractFileExt, RightStr, EndsTe' +
        'xt), oder den Zugriff absichern.'
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Public-Member k' + #$00F6 + 'nnte unit-private sein';
      ShortDesc: 'Public-Member wird nur innerhalb der aktuellen Unit referenziert - Delphi-klassisches `private` (Unit-Scope) reicht';
      FullDesc : 'Analyse einer einzelnen Datei: das `public`-Member wird von irgendwo in derselben Unit referenziert (andere Klassen, Prozeduren auf oberster Ebene, ...), aber NICHT ausschlie' +
        #$00DF + 'lich von der deklarierenden Klasse selbst. Die Versch' + #$00E4 +
        'rfung auf Delphi-klassisches `private` (das auf die Unit beschr' + #$00E4 +
        'nkt ist, nicht auf die Klasse) ist sicher: jeder zul' + #$00E4 +
        'ssige Aufrufer innerhalb der Unit funktioniert weiter. Dieser Detektor l' + #$00E4 +
        'uft absichtlich NUR auf einzelnen Dateien - der fr' + #$00FC + 'here Unit-/projekt' +
        #$00FC +
        'bergreifende Scan erzeugte zu viele Fehlalarme (RTTI-/DFM-Streaming, benachbarte .dpk-/.dproj-Konsumenten, generische Instanziierungen, Plugin-APIs). Der Hinweis ist eine Empfehlung; konsumiert eine fremde Unit das Member, f' +
        #$00E4 + 'ngt der Compiler die gebrochene Sichtbarkeit mit E2361 ab, sobald die ' + #$00C4 +
        'nderung angewendet ist. ' + #$00DC +
        'bersprungen: published, virtual/abstract/override/dynamic, Klassenkonstruktoren/-destruktoren, RTTI-gesteuerte Basisklassen (TForm/TFrame/TDataModule/TComponent), Utility-Klassen nur aus Klassenmethoden. Zeilenweise mit `// noinspection CanBeUnitPriv' +
        'ate` unterdr' + #$00FC + 'cken, wenn die ' + #$00F6 + 'ffentliche Oberfl' + #$00E4 +
        'che beabsichtigt ist (Bibliotheks-API, Plugin-Einstiegspunkt).'
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Public-Member k' + #$00F6 + 'nnte protected sein';
      ShortDesc: 'Public-Member wird nur aus Ableitungen referenziert, nie von au' + #$00DF + 'en';
      FullDesc : 'Analyse einer einzelnen Datei: jeder sichtbare Aufrufer des public-Members ist selbst eine Methode einer Klasse, die von der deklarierenden Klasse abgeleitet ist. `protected` ist die minimale Sichtbarkeit, die alle aktuellen Aufrufstellen bedient, un' +
        'd signalisiert die Entwurfsabsicht ("das ist ein Erweiterungs-Hook, kein Teil der Konsumenten-API"). Derselbe Einzeldatei-Vorbehalt wie bei CanBeUnitPrivate / CanBeStrictPrivate: Unit-' +
        #$00FC + 'bergreifende Konsumenten sind f' + #$00FC +
        'r den Detektor unsichtbar; der Compiler pr' + #$00FC + 'ft das Refactoring ' + #$00FC +
        'ber E2361, falls ein fremder Aufrufer existiert. ' + #$00DC +
        'bersprungen: published-/RTTI-exponierte Member, virtual-/override-Wurzeln, die Teil der dokumentierten Hierarchie sind. Innerhalb des deklarierenden Projekts unbesorgt versch' +
        #$00E4 + 'rfen; bei ausgelieferten Bibliotheks-APIs externe Aufrufer zuerst manuell pr' +
        #$00FC + 'fen.'
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Ungenutztes Public-Member (tote API)';
      ShortDesc: 'Public-Member wird von keiner Ableitung und ' + #$00FC +
        'ber keine Unit-Grenze referenziert';
      FullDesc : 'Keine interne Verwendung UND keine externe Verwendung gefunden - tote API-Oberfl' + #$00E4 +
        'che. Entweder entfernen oder als absichtlich exportiert dokumentieren (z. B. f' + #$00FC +
        'r Bin' + #$00E4 + 'rkompatibilit' + #$00E4 + 't).'
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Ungenutzte lokale Variable';
      ShortDesc: 'Lokale Variable deklariert, aber im Methodenrumpf nie referenziert';
      FullDesc : 'Ein `var X: T;` in einem Methodenrumpf ist deklariert, wird aber im selben Rumpf weder gelesen noch geschrieben. Entspricht dem Delphi-Compiler-Hinweis H2164, wird aber als SCA-Fund ausgegeben, damit er sich einheitlich mit den ' +
        #$00FC + 'brigen Regeln filtern, unterdr' + #$00FC + 'cken, priorisieren und verfolgen l' +
        #$00E4 + 'sst - n' + #$00FC +
        'tzlich, wenn H2164 projektweit stummgeschaltet ist. Der Rumpf-Scan erkennt per `with` umgebundene Bezeichner und ignoriert Variablen, deren Namen einem vorhandenen Feld/einer vorhandenen Property entsprechen (das `with` w' +
        #$00FC + 'rde sie implizit umbinden). Inline-Variablen, die mit `var X: T := ...` eingef' +
        #$00FC +
        'hrt werden, werden genauso behandelt. Mit `// noinspection UnusedLocalVar` unterdr' +
        #$00FC +
        'cken, wenn die Variable absichtlich beibehalten wird (deklarative Dokumentation oder von einer API verlangte Record-Initialisierung).'
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Ungenutzter Methodenparameter';
      ShortDesc: 'Methodenparameter wird im Rumpf nie verwendet';
      FullDesc : 'Ein formaler Parameter ist deklariert, wird aber im Methodenrumpf nie gelesen. Der Parameter belastet die Aufrufstelle (jeder Aufrufer ' +
        #$00FC + 'bergibt einen Wert, der keine Wirkung hat) und verschleiert die tats' + #$00E4 +
        'chlichen Abh' + #$00E4 +
        'ngigkeiten der Methode. Refactoring: den Parameter entfernen oder die Aufrufstelle auf einen anderen Overload umstellen, der ihn nicht erwartet. Der Detektor ' +
        #$00FC + 'berspringt absichtlich von au' + #$00DF +
        'en festgelegte Signaturen: `override` (die Signatur der Basisklasse ist fest), Platzhalter-R' +
        #$00FC +
        'mpfe mit `; virtual; abstract`, Interface-Implementierungen (Signatur vom Interface vorgegeben), Event-Handler (`Sender: TObject` und der Rest des Event-Tupels) sowie Methoden, die als DFM-Event-Handler registriert sind. Je Methode mit `// noinspecti' +
        'on UnusedParameter` unterdr' + #$00FC +
        'cken, bei Callbacks mit fester Form (RTTI/Streaming).'
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Tautologischer boolescher Ausdruck';
      ShortDesc: 'Bin' + #$00E4 +
        'rer Operator mit identischer linker und rechter Seite: x = x, a and a, (p <> p)';
      FullDesc : 'Ein bin' + #$00E4 +
        'rer Operator hat auf beiden Seiten textuell denselben Operanden: `x = x`, `a and a`, `(p <> p)`. Der Ausdruck ergibt zur Compile-Zeit eine Konstante (True oder False) und deutet fast immer auf einen Tippfehler hin - gemeint war ein ' +
        #$00E4 +
        'hnlich benannter Bezeichner (`a = b`, `p1 <> p2`). Der Detektor erfasst: Gleichheit / Ungleichheit / Ordnung (`=`, `<>`, `<`, `>`, `<=`, `>=`) und boolesche Operatoren (`and`, `or`, `xor`). Arithmetische Operatoren (`+`, `-`, `*`) sind absichtlich au' +
        'sgenommen: `x + x` und `a * a` sind legitime Idiome. Die Normalisierung der Operanden wandelt in Kleinbuchstaben um und entfernt ' +
        #$00FC + 'berfl' + #$00FC + 'ssigen Leerraum, erh' + #$00E4 +
        'lt aber den Inhalt von String-Literalen, sodass `''foo'' = ''foo''` korrekt gemeldet wird. Der Detektor verlangt Bezeichner-Gleichheit ' +
        #$00FC +
        'ber den Operator hinweg - ein Funktionsaufruf mit Seiteneffekten (`Next = Next`) wird ebenfalls gemeldet, weil zwei Aufrufe den Fehler ohnehin erzeugen.'
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Master-Detail ohne MasterFields';
      ShortDesc: 'TDataSet hat MasterSource gesetzt, aber weder MasterFields noch IndexFieldNames';
      FullDesc : 'Die VCL bildet stillschweigend ein kartesisches Produkt statt des beabsichtigten Master-Detail-Joins - jede Elternzeile zieht zur Laufzeit jede Detailzeile. Abhilfe: MasterFields setzen (und IndexFieldNames bei IB/FB).'
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Formular mit vielen DB-Komponenten - DataModule abspalten';
      ShortDesc: 'Sammelhinweis: das Formular h' + #$00E4 + 'lt N oder mehr DB-Komponenten';
      FullDesc : 'Zusammenfassung mehrerer `DfmDbInUiForm`-Funde auf demselben Formular - sobald die Anzahl 3 erreicht, f' +
        #$00FC + 'gt SCA zus' + #$00E4 +
        'tzlich zu den Einzelfunden (sie bleiben bestehen) einen einzelnen Hinweis "TDataModule herausziehen" hinzu, um die architektonische L' +
        #$00F6 +
        'sung sichtbar zu machen, statt auf eine Komponente nach der anderen zu zeigen. Den DB-Zugriff in ein TDataModule zu verlagern, trennt die Datenanbindung sauber von der Oberfl' +
        #$00E4 + 'che: dieselbe TFDConnection und dieselben Queries k' + #$00F6 +
        'nnen von mehreren Formularen gemeinsam genutzt werden, die DB-Schicht ist testbar, ohne ein TForm zu instanziieren, und die Einrichtung von DesignForm gegen' +
        #$00FC +
        'ber RuntimeForm bleibt sauber. Die Schwelle ist 3 und derzeit fest einprogrammiert - bewusst niedrig gehalten, denn sobald 3 DB-Komponenten auf einem Formular zu sehen sind, ist das Muster bereits falsch.'
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE ohne WHERE';
      ShortDesc: 'SQL-Anweisung ' + #$00E4 + 'ndert jede Zeile - die WHERE-Klausel fehlt';
      FullDesc : '`UPDATE Users SET Active=0` ohne WHERE schaltet jede Zeile der Tabelle um. Dasselbe gilt f' +
        #$00FC +
        'r `DELETE FROM ...` und `TRUNCATE TABLE ...`. Eine Katastrophe in der Produktion, die nur darauf wartet, einzutreten.'
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format()-Gleitkommaformat ohne TFormatSettings';
      ShortDesc: '%.2f / %.3f ohne explizite TFormatSettings - die Falle Komma gegen Punkt als Dezimaltrenner';
      FullDesc : 'Auf einem DE-Windows liefert `Format(''%.2f'', [3.14])` ''3,14'', auf EN-US ''3.14''. F' +
        #$00FC + 'r maschinenlesbare Ausgabe (SQL, JSON, CSV) immer `TFormatSettings.Invariant` ' +
        #$00FC + 'bergeben.'
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'goto-Anweisung';
      ShortDesc: '`goto` schw' + #$00E4 + 'cht den strukturierten Kontrollfluss';
      FullDesc : '`goto` und Sprungmarken machen den Kontrollfluss unstrukturiert: Schleifen, Verschachtelung und try/finally werden schwer nachvollziehbar. SonarDelphi erfasst dasselbe als communitydelphi:GotoStatement. Moderner Delphi-Code rechtfertigt goto selten -' +
        ' selbst ein mehrstufiges break ist als herausgezogene Prozedur mit Exit sauberer.'
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulator im Quelltext';
      ShortDesc: 'Tabulatoren werden je Editor unterschiedlich dargestellt - Leerzeichen verwenden';
      FullDesc : 'Die Pascal-Codierkonvention setzt seit den 80er-Jahren auf Einr' + #$00FC +
        'ckung mit Leerzeichen. Tabulatoren werden je nach Editor mit 2/4/8 Spalten dargestellt, zerst' +
        #$00F6 +
        'ren nebeneinander dargestellte Diffs im Code-Review und bringen die Ausrichtung durcheinander. SonarDelphi erfasst dasselbe als communitydelphi:TabulationCharacter.'
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Quelltextzeile zu lang';
      ShortDesc: 'Zeile l' + #$00E4 + 'nger als 120 Zeichen - umbrechen oder einen Teilausdruck herausziehen';
      FullDesc : 'Zeilen ' + #$00FC + 'ber 120 Zeichen passen nicht in ein ' + #$00FC +
        'bliches Code-Review mit nebeneinander dargestellten Seiten (2*120+Rand) und laufen ' +
        #$00FC +
        'ber ein Drittel eines 16:9-Monitors hinaus. Die SonarDelphi-Vorgabe und die Sun/Java-Styleguides stimmen bei 120 ' +
        #$00FC + 'berein. Das Limit ist ' + #$00FC +
        'ber [Detectors] MaxLineLength konfigurierbar (Vorgabe 120).'
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Leerraum am Zeilenende';
      ShortDesc: 'Zeile endet mit Leerzeichen oder Tabulator - Hygiene f' + #$00FC + 'r Diffs';
      FullDesc : 'Ein Leerzeichen oder Tabulator am Zeilenende erzeugt Phantom-Diff-Zeilen, sobald ein Editor mit "trim trailing whitespace on save" die Datei anfasst. SonarDelphi erfasst dasselbe als communitydelphi:TrailingWhitespace.'
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Pascal-Schl' + #$00FC + 'sselwort nicht klein geschrieben';
      ShortDesc: 'Pascal-Schl' + #$00FC + 'sselw' + #$00F6 + 'rter (`begin`/`end`/`procedure`/...) geh' +
        #$00F6 + 'ren klein geschrieben';
      FullDesc : 'Der Object-Pascal-Styleguide (Embarcadero DocWiki, Marco Cantu, SonarDelphi) ist eindeutig: Schl' +
        #$00FC + 'sselw' + #$00F6 +
        'rter werden klein geschrieben. Varianten in gemischter Schreibweise wie `Begin`/`End`/`Procedure` sind ' +
        #$00DC + 'berbleibsel aus der Turbo-Pascal/Delphi-1-' + #$00C4 +
        'ra und erzeugen Uneinheitlichkeit in modernen Codebasen. SonarDelphi erfasst dasselbe als communitydelphi:LowercaseKeyword.'
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'NOSONAR-Unterdr' + #$00FC + 'ckungs-Marker';
      ShortDesc: '`// NOSONAR` sollte keine Funde unterdr' + #$00FC + 'cken - Verwendung pr' + #$00FC + 'fen';
      FullDesc : 'NOSONAR-Marker sind technische Schulden: jeder stellt einen Fund still, ohne das eigentliche Problem zu beheben. SCA meldet jedes NOSONAR, damit Reviewer die Unterdr' +
        #$00FC + 'ckungen im Code-Review pr' + #$00FC + 'fen k' + #$00F6 + 'nnen. SCA nutzt f' +
        #$00FC + 'r die native Unterdr' + #$00FC +
        'ckung einen eigenen Marker `// noinspection` - mit NOSONAR versehener Code aus SonarDelphi sollte migriert werden. Entspricht SonarDelphi communitydelphi:NoSonar.'
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Leere Argumentliste';
      ShortDesc: '`Foo()` sollte `Foo;` hei' + #$00DF + 'en - leere Klammern weglassen';
      FullDesc : 'Nach Delphi-Konvention werden parameterlose Aufrufe ohne `()` geschrieben. Die C-artige Form `Foo()` f' +
        #$00FC +
        'gt Rauschen hinzu, ohne etwas mitzuteilen, und passt nicht zum Rest der Sprache (Prozeduren, Properties und Funktionsreferenzen lassen die Klammern alle weg, wenn es keine Argumente gibt). Entspricht SonarDelphi communitydelphi:EmptyArgumentList.'
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Inline-Assembler-Block';
      ShortDesc: '`asm...end`-Block - besser Pascal und Compiler-Intrinsics';
      FullDesc : 'Inline-Assembler erzeugt eine Plattformbindung (Bytes nur f' + #$00FC +
        'r x86/x64, die einen ARM-Cross-Compile oder FreePascal-Ziele nicht ' + #$00FC +
        'berstehen), umgeht den Delphi-Optimierer (kein Inlining, keine Umordnung) und ist schwer zu debuggen. Die berechtigten Anwendungsf' +
        #$00E4 +
        'lle (CPUID-Erkennung, MMX/SSE-Intrinsics) sind durch RTL-Hilfsroutinen abgedeckt. Entspricht SonarDelphi communitydelphi:InlineAssembly.'
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Trailing-Komma in der Argument-Liste';
      ShortDesc: '`Foo(A, B,)` - das Komma weglassen oder das fehlende Argument erg' + #$00E4 + 'nzen';
      FullDesc : 'Trailing-Komma vor `)` in einer Argument-Liste. In einem normalen Aufruf weist Delphi es zur' +
        #$00FC + 'ck: das Komma f' + #$00FC +
        'gt ein leeres Argument hinzu (E2034 too many actual parameters). Nur ein sp' + #$00E4 +
        't gebundener Aufruf auf einem Variant oder dispinterface (OLE-Automatisierung) ' + #$00FC +
        'bersetzt es; dort ist das leere Argument ein ausgelassener optionaler Parameter. Dort hat es keinen semantischen Nutzen (anders als in Python/JS, wo es den Diff stabilisiert) und deutet auf ein vergessenes Argument hin. Entspricht SonarDelphi communi' +
        'tydelphi:TrailingCommaArgumentList.'
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Ganzzahlliteral ohne Ziffergruppierung';
      ShortDesc: 'Gro' + #$00DF + 'e Ganzzahlliterale sollten den Trenner `_` verwenden';
      FullDesc : 'Delphi 10.4+ unterst' + #$00FC +
        'tzt `_` als Zifferntrenner in numerischen Literalen. Konstanten wie Timeouts (1_800_000 ms = 30 min), Dateigr' +
        #$00F6 + #$00DF + 'en (1_048_576 = 1 MiB), Geldbetr' + #$00E4 + 'ge in Cent und ' + #$00C4 +
        'hnliches sind mit expliziter Gruppierung erheblich besser lesbar. Die Schwelle liegt bei 5 Ziffern (fest einprogrammiert; `[Detectors] DigitGroupingThreshold` ist geplant). Hex- und Gleitkommaliterale sind ausgenommen (andere Konvention). Entspricht ' +
        'SonarDelphi communitydelphi:DigitGrouping.'
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Auskommentierter Code';
      ShortDesc: 'Kommentar sieht wie Pascal-Code aus - l' + #$00F6 + 'schen oder begr' + #$00FC + 'nden';
      FullDesc : 'Heuristik: Kommentarinhalt mit 2+ Code-Merkmalen (abschlie' + #$00DF +
        'endes `;`, `:=`, Schl' + #$00FC + 'sselw' + #$00F6 +
        'rter `begin`/`end`/`procedure`/`function`/`if`/`then`/`for`/`while`) ist fast sicher auskommentierter Code. Solcher Code verrottet unbemerkt: niemand traut sich, ihn zu l' +
        #$00F6 +
        'schen, niemand aktualisiert ihn. Entweder entfernen oder durch ein TODO ersetzen, das die Absicht erkl' +
        #$00E4 +
        'rt. Eine `//`-Zeile wird nur gemeldet, wenn keine der beiden Nachbarzeilen ebenfalls ein `//`-Kommentar ist - ein mehrzeiliger `//`-Block gilt als Dokumentation mit Codebeispielen -, und ein nachgestellter Kommentar hinter Code wird ebenfalls nicht g' +
        'emeldet. Benachbarte gemeldete Zeilen (z. B. aufeinanderfolgende `{ ... }`-Kommentare) werden als EIN Fund gemeldet, der den Block umspannt (endLine markiert die Spanne); eine einzelne gemeldete Zeile beh' +
        #$00E4 + 'lt die Meldung je Zeile. Entspricht SonarDelphi communitydelphi:CommentedOutCode.'
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Schl' + #$00FC + 'sselwort auf Unit-Ebene nicht in Spalte 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` sollten in Spalte 1 beginnen';
      FullDesc : 'Nach Object-Pascal-Konvention stehen die strukturellen Abschnitts-Schl' + #$00FC + 'sselw' +
        #$00F6 + 'rter einer Unit b' + #$00FC + 'ndig links in Spalte 1. Einger' + #$00FC +
        'ckte Abschnitts-Schl' + #$00FC + 'sselw' + #$00F6 + 'rter verschleiern beim ' + #$00DC +
        'berfliegen die Struktur der Unit und k' + #$00F6 + 'nnen auf falsch gez' + #$00E4 +
        'hlte begin/end-Verschachtelung hindeuten. Entspricht SonarDelphi communitydelphi:UnitLevelKeywordIndentation.'
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssiger Boolean-Vergleich';
      ShortDesc: '`X = True` sollte `X` hei' + #$00DF + 'en (und `X <> False` entsprechend)';
      FullDesc : 'Einen Boolean mit True/False zu vergleichen ist umst' + #$00E4 +
        'ndlich und erzeugt subtile Fehler (bei WinAPI-BOOL mit Truthy != 1 ergibt `X = True` false). Der Ausdruck selbst ist bereits die Bedingung. Entspricht SonarDelphi communitydelphi:RedundantBoolean. Hinweis: Deklarationen `const X = True;` sind ausgeno' +
        'mmen (legitime Zuweisung, kein Vergleich).'
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'Leere Interface-Deklaration';
      ShortDesc: 'Interface ohne Methoden und Properties tr' + #$00E4 + 'gt keinen Vertrag';
      FullDesc : 'Ein Rumpf IFoo = interface end; ohne Methoden oder Properties ist entweder ein Refactoring-Rest oder ein verkapptes Marker-Interface. Marker-Interfaces werden in Delphi besser als Attributklassen modelliert. Entspricht SonarDelphi communitydelphi:Emp' +
        'tyInterface. Nicht gemeldet: ein Interface mit einem *benannten* Vorfahren au' + #$00DF +
        'er IInterface/IUnknown. Es erbt den Vertrag des Vorfahren und dient als Abfrageschl' +
        #$00FC +
        'ssel (Obj as IFileSystemFileSource), als Marker-Ableitung (IOTAFormWizard = interface(IOTARepositoryWizard)), als ObjC/JNI-Br' +
        #$00FC +
        'ckentyp oder als Automatisierungstyp aus *_TLB.pas - die vorgeschlagene Abhilfe per Attributklasse funktioniert f' +
        #$00FC + 'r keinen davon, denn Attribute sind Compile-Zeit-RTTI und lassen sich nicht ' +
        #$00FC +
        'ber QueryInterface abfragen. interface(IUnknown) wird weiterhin gemeldet: es ist semantisch identisch mit interface.'
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert ohne Meldung';
      ShortDesc: '`Assert(cond);` - eine `''warum''`-Meldung f' + #$00FC + 'r die Diagnose erg' + #$00E4 +
        'nzen';
      FullDesc : '`Assert(cond)` allein schl' + #$00E4 +
        'gt mit dem allgemeinen "Assertion failed at $address" fehl - kein Hinweis darauf, was eigentlich erwartet wurde. `Assert(cond, ''why'')` spart Stunden beim Debuggen. Entspricht SonarDelphi communitydelphi:AssertMessage.'
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'Explizite TObject-Ableitung';
      ShortDesc: '`class(TObject)` ist ' + #$00FC + 'berfl' + #$00FC + 'ssig - Klammern weglassen';
      FullDesc : 'Jede Klasse erbt implizit von TObject; `TFoo = class(TObject)` ist identisch mit `TFoo = class`. Ohne die explizite Basis fallen echte ' +
        #$00C4 +
        'nderungen der Vererbung in Diffs deutlicher auf. Entspricht SonarDelphi communitydelphi:ExplicitTObjectInheritance.'
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'Gruppierte Variablen-, Feld- oder Parameterdeklaration';
      ShortDesc: '`A, B: Type` in eine Deklaration je Zeile aufteilen';
      FullDesc : 'Gruppierte Deklarationen (`A, B, C: Integer;` f' + #$00FC +
        'r Variablen, Felder oder Parameter) verwirren Diffs (eine neue Variable ' + #$00E4 +
        'ndert eine bestehende Zeile), verhindern Kommentare je Variable und erschweren Refactorings mit Typ' +
        #$00E4 +
        'nderung. Jede Deklaration in einer eigenen Zeile ist sauberer. Fasst SonarDelphi communitydelphi:GroupedFieldDeclaration / :GroupedVariableDeclaration / :GroupedParameterDeclaration zu einer Regel zusammen (SCA kann sie sp' +
        #$00E4 + 'ter aufteilen).'
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Leerer begin..end-Block';
      ShortDesc: 'Leerer `begin..end` - l' + #$00F6 + 'schen oder die Anweisung erg' + #$00E4 + 'nzen';
      FullDesc : 'Ein leeres `begin..end` ist fast immer ein Refactoring-Rest oder ein nie gef' + #$00FC +
        'llter Platzhalter. Entweder l' + #$00F6 +
        'schen oder die fehlende Logik implementieren. Initialisierungsabschnitte `begin end.` auf oberster Unit-Ebene sind ausgenommen (das ist die leere Init-Form, kein Refactoring-Rest). Entspricht SonarDelphi communitydelphi:EmptyBlock.'
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Catch-all auf der Wurzelklasse Exception';
      ShortDesc: '`on E: Exception do` schluckt alles, auch AV und Speicherersch' + #$00F6 + 'pfung';
      FullDesc : 'Das Abfangen der Wurzelklasse `Exception` f' + #$00E4 +
        'ngt jeden Fehler ab, auch nicht behebbare (EAccessViolation, EOutOfMemory, EStackOverflow). Besser einen spezifischen Ausnahmetyp abfangen (EDatabaseError, EFOpenError, EConvertError, ...), damit fremde Fehler nicht verdeckt werden. Mit `// noinspect' +
        'ion` unterdr' + #$00FC +
        'cken, wenn das Catch-all beabsichtigt ist (z. B. an einer Logger-Grenze).'
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Aufeinanderfolgende const/type/var-Abschnitte';
      ShortDesc: 'Zwei `const`-, `type`- oder `var`-Bl' + #$00F6 + 'cke hintereinander geh' + #$00F6 +
        'ren zusammengefasst';
      FullDesc : '`const A = 1; const B = 2;` sollte `const A = 1; B = 2;` hei' + #$00DF +
        'en - ein Abschnitts-Schl' + #$00FC + 'sselwort kann alle deklarieren. Dasselbe gilt f' +
        #$00FC +
        'r `type` und `var`. Fasst SonarDelphi communitydelphi:ConsecutiveConstSection / :ConsecutiveTypeSection / :ConsecutiveVarSection zu einer Regel zusammen. Die Art des Abschnitts steht in der Meldung.'
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssiges Exit/Continue vor end';
      ShortDesc: '`Exit;` / `Continue;` direkt vor `end` ist wirkungslos';
      FullDesc : 'Ist Exit die letzte Anweisung einer Routine oder Continue die letzte Anweisung eines Schleifenrumpfs, verl' +
        #$00E4 + 'sst der Kontrollfluss den Block ohnehin - die Sprunganweisung ist tot. L' + #$00F6 +
        'schen, um die Absicht klarzustellen. Entspricht SonarDelphi communitydelphi:RedundantJump. Nicht gemeldet: (1) Exit, das aus einem Schleifenrumpf heraus erreicht wird - das ist ein vorzeitiger R' +
        #$00FC + 'cksprung, und wird es gel' + #$00F6 + 'scht, ' + #$00FC +
        'berschreibt die Schleife das Ergebnis, das sie gerade gefunden hat; eine bereits beendete Schleife auf derselben Ebene (while ... do Inc(Run); Exit;) z' +
        #$00E4 +
        'hlt nicht, diese Funde bleiben also bestehen. (2) Break an beliebiger Stelle - anders als Continue unterdr' +
        #$00FC +
        'ckt es die restlichen Iterationen, sodass das Befolgen des Hinweises Suchschleifen in vollst' +
        #$00E4 + 'ndige Durchl' + #$00E4 +
        'ufe und Schleifen while True in Endlosschleifen verwandelt. Break ist nur in repeat ... Break; until True ' +
        #$00FC + 'berfl' + #$00FC +
        'ssig, was im Referenzkorpus mit 12.000 Dateien nirgends vorkommt.'
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Mehrere Klassendeklarationen in einer Datei';
      ShortDesc: 'Eine Klasse je Unit erleichtert das Refactoring';
      FullDesc : 'Deklariert eine Unit zwei oder mehr ' + #$00F6 +
        'ffentliche Klassen, ist es schwerer als n' + #$00F6 +
        'tig, sie zu finden und zwischen Units zu verschieben. SonarDelphi communitydelphi:ClassPerFile empfiehlt dasselbe. Forward-Deklarationen (`TFoo = class;`) und Klassenreferenztypen (`TFooClass = class of TFoo`) sind ausgenommen.'
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Doppeltes Semikolon';
      ShortDesc: '`;;` - das ' + #$00FC + 'berz' + #$00E4 + 'hlige Semikolon weglassen';
      FullDesc : 'Ein doppeltes Semikolon (`;;`) bedeutet meist einen ' + #$00FC +
        'bersehenen Tippfehler oder einen versehentlich eingef' + #$00FC +
        'gten Rest. Compiler behandeln das zweite `;` als leere Anweisung, daher bricht nichts, aber es erzeugt Rauschen. Entspricht SonarDelphi communitydelphi:SuperfluousSemicolon.'
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Leerer finally-Block';
      ShortDesc: '`try ... finally end;` r' + #$00E4 + 'umt nichts auf - entweder f' + #$00FC +
        'llen oder das finally weglassen';
      FullDesc : 'Ein leerer `finally`-Block ist fast immer ein vergessenes Aufr' + #$00E4 +
        'umen. Gibt es wirklich nichts aufzur' + #$00E4 +
        'umen, die `try..finally`-Klammer entfernen. Entspricht SonarDelphi communitydelphi:EmptyFinallyBlock.'
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige Assigned- plus nil-Pr' + #$00FC + 'fung';
      ShortDesc: '`Assigned(X) and (X <> nil)` - die nil-Pr' + #$00FC + 'fung weglassen';
      FullDesc : '`Assigned(X)` ist f' + #$00FC +
        'r Zeiger und Klasseninstanzen semantisch identisch mit `X <> nil`. Beides zu kombinieren ist ' +
        #$00FC + 'berfl' + #$00FC + 'ssig - die zweite Pr' + #$00FC +
        'fung kann nie ein anderes Ergebnis liefern. Entspricht SonarDelphi communitydelphi:AssignedAndAssignedNil.'
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; sollte FreeAndNil(X) sein';
      ShortDesc: '`FreeAndNil(X)` statt `X.Free; X := nil;` verwenden';
      FullDesc : '`FreeAndNil(X)` ist das kanonische Delphi-Idiom: es erledigt beides atomar und vermeidet einen h' +
        #$00E4 + 'ngenden Zeiger, wenn `X.Free` eine Ausnahme ausl' + #$00F6 +
        'st (z. B. bei einem Fehler im Destruktor). Die manuelle zweizeilige Form erzeugt au' +
        #$00DF + 'erdem mehr Diff-Rauschen und wird bei sp' + #$00E4 +
        'teren Refactorings leichter auseinandergerissen. Entspricht SonarDelphi communitydelphi:FreeAndNil.'
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : 'out-Parameter vermeiden';
      ShortDesc: '`var` ist `out` vorzuziehen (out hat ' + #$00FC + 'berraschende Semantik)';
      FullDesc : '`out`-Parameter leeren gemanagte Typen (string/Interface/dynamische Arrays) beim Eintritt in die Methode - der Wert des Aufrufers wird verworfen, bevor die Methode l' +
        #$00E4 +
        'uft. Record- und einfache Typen bleiben uninitialisiert, daher ist das Lesen des eingehenden Werts undefiniertes Verhalten. Beides ist selten beabsichtigt. `var` ist die sicherere Vorgabe, sofern nicht die Semantik f' +
        #$00FC + 'r COM-Interop ben' + #$00F6 +
        'tigt wird. Entspricht SonarDelphi communitydelphi:AvoidOut.'
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Leerer Sichtbarkeitsabschnitt in der Klasse';
      ShortDesc: 'Abschnittskopf `public`/`private`/... ohne Member darunter';
      FullDesc : 'Eine Klasse mit einem Sichtbarkeits-Schl' + #$00FC +
        'sselwort, auf das unmittelbar ein weiteres Sichtbarkeits-Schl' + #$00FC +
        'sselwort (oder `end`) folgt, ist meist ein Refactoring-Rest - alle Member dieses Abschnitts wurden anderswohin verschoben. Den leeren Abschnittskopf l' +
        #$00F6 + 'schen. Entspricht SonarDelphi communitydelphi:EmptyVisibilitySection.'
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Alte Unit-Initialisierung begin..end.';
      ShortDesc: '`initialization..end.` statt des alten `begin..end.` verwenden';
      FullDesc : 'Units vor Delphi 2 kennzeichneten ihren Init-Block mit `begin..end.`. Seit Delphi 2 ist die idiomatische Form `initialization..end.`, die sich f' +
        #$00FC + 'r symmetrisches Aufr' + #$00E4 +
        'umen mit einem optionalen `finalization`-Block kombinieren l' + #$00E4 +
        'sst. Entspricht SonarDelphi communitydelphi:LegacyInitializationSection.'
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Public-Feld in der Klasse';
      ShortDesc: 'Ein public-Feld bricht die Kapselung - eine Property verwenden';
      FullDesc : 'Ein public-Feld legt den zugrunde liegenden Speicher offen; Aufrufer k' + #$00F6 +
        'nnen ihn ' + #$00E4 + 'ndern, ohne dass die Klasse es bemerkt. Eine Property l' + #$00E4 +
        'sst der Klasse die M' + #$00F6 + 'glichkeit, sp' + #$00E4 +
        'ter Validierung/Normalisierung zu erg' + #$00E4 +
        'nzen, ohne Aufrufer zu brechen. Entspricht SonarDelphi communitydelphi:PublicField.'
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Verschachtelter try-Block';
      ShortDesc: 'Verschachteltes `try..end` - das innere try in eine eigene Methode herausziehen';
      FullDesc : 'Verschachtelte try-Bl' + #$00F6 + 'cke machen den Kontrollfluss von Aufr' + #$00E4 +
        'umen / Fehlerbehandlung schwerer lesbar. Die meisten F' + #$00E4 + 'lle lassen sich aufl' +
        #$00F6 + 'sen, indem die Aufr' + #$00E4 +
        'umschritte umgeordnet oder der innere Block in eine eigene Methode herausgezogen wird. Entspricht SonarDelphi communitydelphi:NestedTry. Der Detektor nutzt eine Tiefen-Heuristik (z' +
        #$00E4 + 'hlt die Schl' + #$00FC + 'sselw' + #$00F6 +
        'rter `try` gegen `end`) und kann in stark verschachteltem begin/end-Code einige Fehlalarme erzeugen.'
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Gro' + #$00DF + 'e case-Anweisung';
      ShortDesc: '`case` mit 10 oder mehr Zweigen - Polymorphie oder eine Dispatch-Tabelle erw' + #$00E4 +
        'gen';
      FullDesc : 'Ein `case` mit vielen Zweigen verbirgt meist ein Polymorphie- oder Strategy-Muster. Der Code w' +
        #$00E4 + 're offener f' + #$00FC + 'r Erweiterung und geschlossener f' + #$00FC + 'r ' +
        #$00C4 + 'nderung (neues Verhalten = neue Klasse, kein neuer Zweig) und die Datei k' +
        #$00FC +
        'rzer, wenn jeder Zweig zu einer eigenen Klassenmethode oder einem `TDictionary<Key, TProc>`-Eintrag wird. Entspricht SonarDelphi communitydelphi:CaseStatementSize. Die Schwelle ist ' +
        #$00FC + 'ber `[Detectors] MaxCaseBranches` konfigurierbar, Vorgabe 10. Jedes `case` wird f' +
        #$00FC + 'r sich gemessen: nur Labels auf Blocktiefe 1 dieses `case` z' + #$00E4 +
        'hlen, sodass die Labels eines verschachtelten `case` das umgebende nicht mehr aufbl' +
        #$00E4 + 'hen. Ein verschachteltes Konstrukt kann daher mehr als einen Fund erzeugen - ein ' +
        #$00E4 + 'u' + #$00DF +
        'eres und ein inneres `case` werden getrennt gemeldet, sobald jedes f' + #$00FC + 'r sich ' +
        #$00FC + 'ber der Schwelle liegt.'
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit ohne Deklarationen';
      ShortDesc: 'Unit hat weder type, const, var noch procedure/function - l' + #$00F6 + 'schen oder f' +
        #$00FC + 'llen';
      FullDesc : 'Eine `.pas`-Datei mit Unit-Kopf, aber ohne Deklarationen ist toter Ballast. Entweder die Datei l' +
        #$00F6 + 'schen oder den Platzhalter f' + #$00FC +
        'llen. Entspricht SonarDelphi communitydelphi:EmptyFile.'
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Mehrere inherited-Aufrufe in einer Methode';
      ShortDesc: 'Zwei oder mehr `inherited;` in derselben Methode - die Seiteneffekte der Basis laufen doppelt';
      FullDesc : 'Jeder `inherited`-Aufruf f' + #$00FC +
        'hrt die Implementierung der Basisklasse aus. Zwei Aufrufe l' + #$00F6 +
        'sen Seiteneffekte (Ereignisbenachrichtigungen, Aktualisierungen des Referenzz' + #$00E4 +
        'hlers, Logzeilen) doppelt aus. Fast immer ein Copy-Paste-Fehler. Entspricht SonarDelphi communitydelphi:TwiceInheritedCalls.'
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige doppelte Klammern';
      ShortDesc: '`((Ident))` - die inneren Klammern weglassen';
      FullDesc : 'Doppelte Klammern um einen einzelnen Bezeichner, ein Literal oder einen einfachen Ausdruck bringen nichts - ein einzelnes Paar gen' +
        #$00FC +
        'gt (oft gar keines). Entspricht SonarDelphi communitydelphi:RedundantParentheses. Nur der Fall des einfachen Ausdrucks wird gemeldet; ein komplexes `((A + B))` kann weiterhin von inneren Klammern f' +
        #$00FC + 'r die Rangfolge profitieren und wird nicht gemeldet.'
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Wiederholter Sichtbarkeitsabschnitt';
      ShortDesc: 'Derselbe Abschnitt `public`/`private`/... kommt in einer Klasse zweimal vor';
      FullDesc : 'Zwei `private`-Abschnitte (oder `public`/`protected`/`published`) in derselben Klasse mit Membern dazwischen sollten zu einem zusammengefasst werden. Das hilft Reviewern, die Form der Klasse auf einen Blick zu erfassen. Entspricht SonarDelphi communi' +
        'tydelphi:ConsecutiveVisibilitySection. Hinweis: ein leerer Abschnittskopf, auf den ein weiterer Kopf folgt, ist die verwandte, aber eigenst' +
        #$00E4 + 'ndige Regel `EmptyVisibilitySection` (SCA087).'
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Konstruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Konstruktor fehlt `inherited Create` - die Basis bleibt uninitialisiert';
      FullDesc : 'Ein Konstruktor, der `inherited Create(...)` (oder `inherited;`) nicht aufruft, ' + #$00FC +
        'berspringt die Initialisierung der Basisklasse. Felder und Registrierungen der Basisklasse bleiben im Default-/nil-Zustand, was zu Folgeabst' +
        #$00FC + 'rzen f' + #$00FC +
        'hrt, wenn Methoden eine einsatzbereite Basisklasse erwarten. Entspricht SonarDelphi communitydelphi:ConstructorWithoutInherited.'
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Destruktor fehlt `inherited Destroy` - das Aufr' + #$00E4 + 'umen der Basis entf' +
        #$00E4 + 'llt (Leck-Risiko)';
      FullDesc : 'Ein Destruktor ohne `inherited Destroy` (oder `inherited;`) hindert die Basisklasse daran, ihre eigenen Felder freizugeben, Handler abzumelden und Referenzz' +
        #$00E4 +
        'hler zu aktualisieren. Fast immer ein Leck. Entspricht SonarDelphi communitydelphi:DestructorWithoutInherited.'
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige bedingte Zuweisung';
      ShortDesc: '`if Cond then X := True else X := False` sollte `X := Cond` hei' + #$00DF + 'en';
      FullDesc : 'Zwei Zweige, die derselben Variable True/False zuweisen, lassen sich auf eine einzige direkte Zuweisung reduzieren (oder `not Cond`, wenn die Polarit' +
        #$00E4 + 't umgekehrt ist). K' + #$00FC + 'rzer, schneller und n' + #$00E4 +
        'her am booleschen Ausdruck. Entspricht SonarDelphi communitydelphi:RedundantConditional.'
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'Unsymmetrisches begin/end in if/else';
      ShortDesc: 'Der then-Zweig nutzt `begin..end`, der else-Zweig ist eine einzelne Anweisung';
      FullDesc : 'Nutzt der then-Zweig `begin..end`, sollte der else-Zweig das ebenfalls tun (oder beide sollten darauf verzichten). Die gemischte Form (`end else DoStuff;`) l' +
        #$00E4 + 'sst einen sp' + #$00E4 +
        'teren Leser im Unklaren, ob weitere Anweisungen in den else-Zweig geh' + #$00F6 +
        'ren, aber vergessen wurden. `else if` (else-if-Kette) und `else begin` sind ausdr' + #$00FC +
        'cklich erlaubt. Entspricht SonarDelphi communitydelphi:IfElseBegin.'
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Zeigertyp-Alias ohne P-Pr' + #$00E4 + 'fix';
      ShortDesc: '`Foo = ^Bar` sollte `PBar = ^Bar` hei' + #$00DF + 'en (P-Pr' + #$00E4 + 'fix-Konvention)';
      FullDesc : 'Delphi-Konvention seit dem ersten Tag: ein Zeiger-Alias auf `TXxx` hei' + #$00DF +
        't `PXxx`. Das Pr' + #$00E4 +
        'fix `P` macht die Indirektion an der Aufrufstelle sichtbar. Entspricht SonarDelphi communitydelphi:PointerName. Ein Namens-Framework wird das Pr' +
        #$00E4 + 'fix sp' + #$00E4 + 'ter konfigurierbar machen.'
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Zweig ohne begin..end-Block';
      ShortDesc: '`then`/`else`/`do <Anweisung>` - besser ein ausdr' + #$00FC + 'ckliches `begin..end`';
      FullDesc : 'Ein Zweig mit einer einzelnen Anweisung ohne `begin..end` wird leicht falsch gelesen; wird sp' +
        #$00E4 + 'ter eine zweite Anweisung erg' + #$00E4 +
        'nzt, ohne neu zu blocken, ist das eine klassische Quelle f' + #$00FC +
        'r Fehler, bei denen Einr' + #$00FC +
        'ckung und Semantik auseinanderlaufen. Stilistisch umstrittene Regel (viele Delphi-Codebasen nutzen die kompakte Form bewusst) - lsHint, in Profilen leicht abzuschalten. `else if`-Ketten, `raise`/`exit`/`break`/`continue` und andere blocker' +
        #$00F6 + 'ffnende Anweisungen sind ausdr' + #$00FC +
        'cklich erlaubt. Entspricht SonarDelphi communitydelphi:BeginEndRequired.'
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Verschachtelte Routine in einer Methode';
      ShortDesc: 'Lokale verschachtelte Prozedur oder Funktion - auf Unit-Ebene herausziehen';
      FullDesc : 'Verschachtelte Routinen (eine `procedure`/`function`, die im lokalen Deklarationsteil einer anderen Routine deklariert ist) sind syntaktisch erlaubt, hemmen aber Tests und Wiederverwendung: die innere Routine l' +
        #$00E4 + 'sst sich weder per Unit-Test pr' + #$00FC +
        'fen noch an anderer Stelle wiederverwenden. Modernes Delphi bevorzugt anonyme Methoden (Lambdas) f' +
        #$00FC + 'r die seltenen F' + #$00E4 + 'lle, in denen die Verschachtelung tats' + #$00E4 +
        'chlich n' + #$00F6 +
        'tig war. Anonyme Methoden werden NICHT gemeldet (sie haben im AST keinen Namen). Entspricht SonarDelphi communitydelphi:NestedRoutines.'
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Klassenfeld ohne F-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Klassenfelder sollten der Konvention `F<Name>` folgen';
      FullDesc : 'Delphi-Konvention: Instanzfelder einer Klasse hei' + #$00DF +
        'en `FFoo`, damit der Leser sofort erkennt, dass sie sich auf ein Member der Klasse beziehen (im Gegensatz zu einer lokalen Variable oder einem Parameter). Das Pr' +
        #$00E4 +
        'fix `F` vermeidet Namenskollisionen mit public-Properties (Feld `FFoo` mit Property `Foo` ist das kanonische Paar). Gepr' +
        #$00FC +
        'ft werden nur `private`- und `protected`-Felddeklarationen - public-/published-Felder erfasst ohnehin `PublicField` (SCA089). Entspricht SonarDelphi communitydelphi:FieldName.'
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Klassen-/Record-Typ ohne T-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Klassen- und Record-Typaliase sollten mit `T` beginnen';
      FullDesc : 'Delphi-Konvention: Klassentypen `TXxx`, Records `TXxx` oder `RXxx`, Interfaces `IXxx`, Zeiger `PXxx` (SCA100), Ausnahmen `EXxx`. Dieser Detektor deckt nur die Teilmenge Klassen/Records ab. Forward-Deklarationen (`TFoo = class;`), `class of`-Referenze' +
        'n (`TFooClass = class of TFoo`) und generische Syntax werden ber' + #$00FC +
        'cksichtigt. Entspricht SonarDelphi communitydelphi:TypeName.'
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Interface-Typ ohne I-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Interface-Aliase sollten mit `I` beginnen (`IFoo = interface`)';
      FullDesc : 'Delphi-Konvention: Interfaces hei' + #$00DF + 'en `IXxx`, analog zu `TXxx` f' + #$00FC +
        'r Klassen und `PXxx` f' + #$00FC + 'r Zeiger. Das Pr' + #$00E4 +
        'fix `I` zeigt an jeder Aufrufstelle, ob ein Vertrag oder eine Implementierung vorliegt. Erfasst auch `dispinterface`. Entspricht SonarDelphi communitydelphi:InterfaceName.'
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'Methode nicht in PascalCase';
      ShortDesc: 'Methoden sollten mit einem Gro' + #$00DF + 'buchstaben beginnen (PascalCase)';
      FullDesc : 'Delphi-Konvention ist PascalCase (UpperCamel) f' + #$00FC +
        'r Routinen und Methoden: `DoSomething`, nicht `doSomething` oder `do_something`. Operator-Overloads und Bezeichner, die mit `_` beginnen, sind ausgenommen. Entspricht SonarDelphi communitydelphi:MethodName. AST-basiert: pr' +
        #$00FC +
        'ft `nkMethod.Name` (qualifiziertes `TFoo.bar` wird am Punkt getrennt). Dateiweite Ausnahmen: generierte Typbibliotheks-Importe (*_TLB.pas) und Units, die FPC-Klassen fremder Sprachen deklarieren (objcclass/objccategory/cppclass) - deren Methodennamen' +
        ' SIND die Selektoren/Symbole der fremden API; `external`-Routinen, `cdecl`-Typmethoden und FFI-Bindungstypen (JNI/ObjC-Importanker) sind je Methode ausgenommen.'
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Public-Member k' + #$00F6 + 'nnte strict private sein';
      ShortDesc: 'Public-Member wird NUR von Methoden der eigenen Klasse referenziert - `strict private` erreicht die st' +
        #$00E4 + 'rkste Kapselung';
      FullDesc : 'Analyse einer einzelnen Datei: Jeder sichtbare Aufrufer des `public`-Members ist selbst eine Methode DERSELBEN Klasse (keine Nachbarklasse, keine Prozedur auf oberster Ebene, keine Ableitung in dieser Unit). `strict private` (D2007+, Klassen-Scope, n' +
        'icht Unit-Scope) ist die engste korrekte Sichtbarkeit. Derselbe Einzeldatei-Vorbehalt wie bei CanBeUnitPrivate: Verwender in anderen Units sind unsichtbar, und der Compiler sichert die Korrektheit ' +
        #$00FC + 'ber E2361, falls die ' + #$00C4 + 'nderung etwas kaputt macht. ' + #$00DC +
        'bersprungen: published, virtual/abstract/override/dynamic, Klassenkonstruktoren/-destruktoren, RTTI-getriebene Basen (TForm/TFrame/TDataModule/TComponent), Hilfsklassen nur aus Klassenmethoden. F' +
        #$00FC + 'r beabsichtigte ' + #$00F6 +
        'ffentliche Schnittstellen je Zeile mit `// noinspection CanBeStrictPrivate` unterdr' +
        #$00FC + 'cken.'
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize aus dem Destruktor';
      ShortDesc: 'Synchronize() aus dem Destruktor Destroy gerufen - ein sich selbst freigebender Thread blockiert dort, bis der Hauptthread den Aufruf ausf' +
        #$00FC + 'hrt, und h' + #$00E4 + 'ngt, wenn er es nicht tut';
      FullDesc : 'TThread.Synchronize() in einem Destruktor-Rumpf ist fragil. L' + #$00E4 +
        'uft der Destruktor im Hauptthread, ruft Synchronize die Methode einfach direkt auf. L' +
        #$00E4 + 'uft er im Worker-Thread selbst - der ' + #$00FC +
        'bliche Fall bei FreeOnTerminate := True, wo sich der Thread nach Execute selbst freigibt -, blockiert Synchronize den Worker, bis der Hauptthread den Aufruf ausf' +
        #$00FC +
        'hrt. Bearbeitet der Hauptthread in diesem Moment keine Synchronize-Anfragen (etwa weil er mit WaitForSingleObject statt TThread.WaitFor auf den Thread wartet oder weil die Anwendung gerade beendet wird), warten beide Threads aufeinander und der Proze' +
        'ss h' + #$00E4 + 'ngt. Beim Beenden k' + #$00F6 + 'nnen die Objekte, die der Aufruf ber' +
        #$00FC +
        'hrt, zudem schon weg sein. Die Benachrichtigung in einen OnTerminate-Handler verlegen (er l' +
        #$00E4 +
        'uft im Hauptthread, bevor das Thread-Objekt freigegeben wird) oder ans Ende von Execute. AST-basiert: durchl' +
        #$00E4 +
        'uft jede nkMethod, deren Name auf ''.Destroy'' endet (oder deren TypeRef den Marker ''destructor'' tr' +
        #$00E4 + 'gt), und meldet nkCall auf ''Synchronize'' / ''<obj>.Synchronize''.'
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Sperre ohne Freigabe per try/finally genommen';
      ShortDesc: 'TCriticalSection, Monitor oder WinAPI-Sperre ohne umschlie' + #$00DF +
        'endes try..finally genommen - eine Ausnahme l' + #$00E4 + 'sst sie gesperrt';
      FullDesc : 'Eine Sperre anzufordern (TCriticalSection.Enter / .Acquire, TMonitor.Enter, TMultiReadExclusiveWriteSynchronizer.BeginWrite, WinAPI EnterCriticalSection), ohne unmittelbar ein try..finally mit dem passenden Leave / Release / EndWrite folgen zu lassen' +
        ', ist einer der h' + #$00E4 +
        'ufigsten Threading-Fehler in Delphi: Jede Ausnahme zwischen Anfordern und Freigeben l' +
        #$00E4 + 'sst die Sperre dauerhaft gehalten und blockiert jeden sp' + #$00E4 +
        'teren Aufrufer (Deadlock). Lexikalische Erkennung: findet die Anforderungsmuster und pr' +
        #$00FC + 'ft, ob die n' + #$00E4 + 'chste Anweisung nach dem `;` ein `try` ist. F' + #$00FC +
        'r absichtlich ungesch' + #$00FC +
        'tzte Abfolgen mit `// noinspection LockWithoutTryFinally` unterdr' + #$00FC +
        'cken (selten; bedeutet meist, dass der n' + #$00E4 +
        'chste Aufruf selbst nie eine Ausnahme ausl' + #$00F6 + 'st).'
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'String-Verkettung in der Schleife';
      ShortDesc: '`s := s + x` in for/while/repeat - quadratisch viele Neuallokationen';
      FullDesc : 'Jedes `s := s + x` in einem Schleifenrumpf allokiert einen NEUEN String der L' + #$00E4 +
        'nge length(s)+length(x) und kopiert beide Teile hinein. ' + #$00DC +
        'ber N Iterationen sind das O(N^2) Byte-Kopien und Heap-Druck. Zwei idiomatische Alternativen in Delphi: (1) in einen TStringBuilder schreiben und am Ende einmal ToString aufrufen, (2) die Teile in einer TStringList sammeln und .Text einmal lesen. Heu' +
        'ristik des Detektors: lexikalischer Abgleich auf das Muster LHS == erster RHS-Operand (ohne Beachtung der Gro' +
        #$00DF + '-/Kleinschreibung) in jedem for/while/repeat-Block. Fehlalarme sind m' + #$00F6 +
        'glich, wenn `s` absichtlich als Akkumulator ' + #$00FC +
        'ber kurze Schleifen mit kleinen Nutzdaten wiederverwendet wird; mit `// noinspection StringConcatInLoop` unterdr' +
        #$00FC + 'cken.'
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) in der Schleife gerufen';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` in einer Schleife - lineare Suche je Durchlauf';
      FullDesc : 'ParamByName durchl' + #$00E4 +
        'uft die TParam-Collection bei jedem Aufruf per String-Vergleich (linear in der Zahl der Parameter). In einem Hot-Path / einer Schleife wird so aus einem ParamByName je Query.Execute N je Execute. Die TParam-Referenz einmal au' +
        #$00DF +
        'erhalb der Schleife zwischenspeichern oder die per Integer indizierte Property Params[i] verwenden, wenn die Position des Parameters bekannt ist.'
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) in der Schleife gerufen';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` in einer Schleife - lineare Suche je Datensatz';
      FullDesc : 'FieldByName durchl' + #$00E4 +
        'uft die TFields-Collection bei jedem Aufruf per String-Vergleich. In einer Schleife ' +
        #$00FC +
        'ber ein DataSet wird so aus einem Lookup je Feld N Lookups je .Next, mitunter je Zeile mal N Felder = O(N*M). Die TField-Referenz einmal vor der Schleife zwischenspeichern und direkt lesen/schreiben. Derselbe L' +
        #$00F6 + 'sungsweg wie bei SCA111 (ParamByName) - nur eine andere Collection.'
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume ist veraltet';
      ShortDesc: '`MyThread.Resume` - `MyThread.Start` verwenden (seit Delphi 2010)';
      FullDesc : 'TThread.Resume ist seit Delphi 2010 zugunsten von TThread.Start veraltet (Suspendieren beim Erzeugen + Fortsetzen beim Starten wurden zu einem expliziten Start-Aufruf). Der Compiler gibt eine Deprecation-Warnung aus, die in gr' +
        #$00F6 + #$00DF + 'eren Codebasen aber leicht ' + #$00FC +
        'bersehen wird. Zwei Korrekturen: (a) .Start statt .Resume aufrufen, (b) mit CreateSuspended := False erzeugen und den Resume/Start-Schritt ganz weglassen. Der Detektor meldet Aufrufe `<ident>.Resume`. Ist der Typ des Empf' +
        #$00E4 +
        'ngers in derselben Datei sichtbar (`X: TFoo` oder `X := TFoo.Create`), muss er TThread sein, auf `Thread` enden oder in dieser Datei von TThread abgeleitet sein - andere Typen (Timer, Animationen, TProcess) werden ' +
        #$00FC + 'bersprungen. Ein nicht aufgel' + #$00F6 + 'ster Empf' + #$00E4 +
        'nger wird gemeldet, au' + #$00DF +
        'er bei einer Punktkette oder einer Inline-Variablen, deren Name oder Initialisierer ''thread'' nicht erw' +
        #$00E4 + 'hnt. Ist ein gemeldeter Empf' + #$00E4 +
        'nger kein TThread, je Zeile mit `// noinspection ThreadResumeDeprecated` unterdr' + #$00FC +
        'cken.'
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread per FreeAndNil freigegeben - Beendigung pr' + #$00FC + 'fen';
      ShortDesc: '`FreeAndNil(MyThread)` ohne nahes `Terminate` - ein Pr' + #$00FC +
        'fhinweis, kein bewiesener Defekt: `TThread.Destroy` beendet den Thread selbst; `Execute`, den Thread-Destruktor und `FreeOnTerminate` pr' +
        #$00FC + 'fen';
      FullDesc : 'Pr' + #$00FC +
        'fhinweis, kein bewiesener Defekt. `TThread.Destroy` beendet den Thread selbst: Es ruft `Terminate` auf, setzt einen suspendierten Thread fort und wartet, bis `Execute` zur' +
        #$00FC +
        'ckgekehrt ist; `FreeAndNil(MyThread)` allein ist daher sicher. An der gemeldeten Zeile drei Dinge pr' +
        #$00FC +
        'fen. Beachtet `Execute` `Terminated`? Falls nicht, wartet der Destruktor, bis `Execute` von selbst zur' +
        #$00FC +
        'ckkehrt. Gibt ein Destruktor der Thread-Klasse Felder, die `Execute` verwendet, erst nach `inherited` frei? Sein Rumpf l' +
        #$00E4 +
        'uft, bevor `TThread.Destroy` den Thread beendet. Ist `FreeOnTerminate` gesetzt? Ein solcher Thread gibt sich am Ende von `Execute` selbst frei und darf daher nicht zus' +
        #$00E4 + 'tzlich von au' + #$00DF + 'en freigegeben werden. Ein zus' + #$00E4 +
        'tzliches `WaitFor` bringt nichts: Es kehrt bei einem suspendiert erzeugten und nie gestarteten Thread nicht zur' +
        #$00FC +
        'ck. Heuristik: meldet `FreeAndNil(<id>)`, wenn `<id>` einen Thread-Typ hat (der deklarierte oder erzeugte Typ endet auf `Thread` oder ist in derselben Datei von TThread abgeleitet; l' +
        #$00F6 + 'st sich kein Typ auf, enth' + #$00E4 +
        'lt der Bezeichner `thread`) und die vorangehenden ~500 Zeichen (etwa 10 Zeilen) weder `<id>.Terminate` noch `<id>.WaitFor` enthalten. Kein Fund nach `TerminateThread(<id>`, unter einer positiven Bedingung `if <id>.Finished` oder wenn ein `Execute` de' +
        'r Thread-Klasse in derselben Unit `Terminated` referenziert. Die blanke Form `.Free` wird nicht gepr' +
        #$00FC + 'ft, und der Detektor l' + #$00E4 +
        'uft nur auf Dateien, die `TThread`, `.Synchronize`, `.Resume`, `.Queue`, `ParamByName` oder `FieldByName` erw' +
        #$00E4 + 'hnen. F' + #$00FC +
        'r Nicht-Thread-Klassen mit `// noinspection TThreadDestroyWithoutTerminate` unterdr' +
        #$00FC + 'cken.'
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'HTTP-URL im Klartext';
      ShortDesc: 'Literal `''http://...''` f' + #$00FC + 'r einen entfernten Endpunkt - anf' + #$00E4 +
        'llig f' + #$00FC + 'r Man-in-the-Middle';
      FullDesc : 'Ein String-Literal, das mit `http://` beginnt, ' + #$00FC + 'bertr' + #$00E4 + 'gt f' +
        #$00FC + 'r jeden Endpunkt au' + #$00DF + 'er localhost seine Nutzdaten unverschl' + #$00FC +
        'sselt. Zugangsdaten, Session-Token und personenbezogene Daten laufen im Klartext und k' +
        #$00F6 + 'nnen von jedem aktiven Akteur im Netz mitgelesen oder ver' + #$00E4 +
        'ndert werden. Die Korrektur kostet praktisch nichts: das Schema auf `https://` ' + #$00E4 +
        'ndern (fast jeder moderne Dienst unterst' + #$00FC +
        'tzt beides). Der Detektor liest den Host aus dem Literal (ohne Userinfo, Port und IPv6-Klammern) und bleibt still, wenn dieser Host kein erreichbarer Endpunkt sein kann: Loopback und lokale IPC (`localhost`, `127.x.x.x`, `[::1]`, `0.0.0.0`, `host.doc' +
        'ker.internal`, das Socket-Layout `http://unix:` von mORMot) sowie die f' + #$00FC +
        'r Dokumentation und Tests reservierten Bereiche (RFC 2606 `example.com/.net/.org`, `.example`, `.test`, `.invalid`; RFC 5737 `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`; RFC 3849 `2001:db8::/32`; und die Link-Local-Bereiche `169.254.0.0/16` u' +
        'nd `fe80::/10`, die keine Dokumentationsbereiche sind, in Quelltext-Literalen aber nur als Parser-Fixtures oder Diagnosebeispiele vorkommen - ein echter Einsatz gegen `fe80::` braucht einen Zonenindex, und `169.254.x` tritt nur auf, wenn DHCP fehlges' +
        'chlagen ist). Private LAN-Bereiche (RFC 1918) werden bewusst NICHT ' + #$00FC +
        'bersprungen - ein REST-Aufruf an `http://192.168.x.y` ist ein echter Klartext-Endpunkt. XML-Namespace-URIs (`xmlns=`, `schemas`, `w3.org`, ...) sind Identit' +
        #$00E4 + 'ten, keine Netzziele, und werden ebenfalls ' + #$00FC + 'bersprungen.'
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'TLS-Pr' + #$00FC + 'fung abgeschaltet';
      ShortDesc: 'Leeres `SecureProtocols`, `IgnoreCertificateErrors := True` oder `OnVerifyPeer := nil`';
      FullDesc : 'Drei Delphi-Muster schalten die TLS-Pr' + #$00FC +
        'fung stillschweigend ab: (a) `SecureProtocols := []` entfernt jedes Protokoll und erlaubt den R' +
        #$00FC + 'ckfall auf Klartext oder das schw' + #$00E4 + 'chste verf' + #$00FC +
        'gbare Protokoll, (b) `IgnoreCertificateErrors := True` akzeptiert jedes Zertifikat, auch abgelaufene und selbstsignierte, (c) `OnVerifyPeer := nil` schlie' +
        #$00DF + 't den Pr' + #$00FC + 'f-Callback kurz. Alle drei sind attraktiv f' + #$00FC +
        'r MITM-Angriffe. Ersetzen durch explizit nur moderne Protokolle (`[TLSv1_2, TLSv1_3]`), einen echten Trust Store oder einen OnVerifyPeer-Handler mit Fingerprint-Pinning. Der Detektor findet die drei Muster der Property-Zuweisung lexikalisch.'
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Public-Member ohne Doku-Kommentar';
      ShortDesc: 'Public-Methode oder -Property im `interface`-Abschnitt ohne Doku-Kommentar direkt dar' +
        #$00FC + 'ber';
      FullDesc : 'Ein Public-Member im `interface`-Abschnitt einer Unit geh' + #$00F6 +
        'rt zur dokumentierten API-Oberfl' + #$00E4 +
        'che, die andere Units verwenden. Fehlende Doku-Kommentare erschweren die Nutzung der Unit, ohne die Implementierung zu lesen. Der Detektor akzeptiert jede dieser Formen direkt ' +
        #$00FC +
        'ber der Deklaration: `///` XMLDoc, einen `{ ... }`-Block, einen `(* ... *)`-Block oder einen oder mehrere einzeilige `//`-Kommentare. ' +
        #$00DC +
        'bersprungen: Konstruktoren `Create` / Destruktoren `Destroy` (per Konvention selbsterkl' +
        #$00E4 +
        'rend), Member, die mit `_` beginnen (Private-Markierung in Public-Abschnitten), `published`-Member (DFM/RTTI-getrieben, Doku w' +
        #$00E4 + 're Rauschen). Unterdr' + #$00FC +
        'ckung: `// noinspection PublicMemberWithoutDoc` je Deklaration.'
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Exception-Klasse ohne `E`-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Eine `class(Exception)`-Ableitung sollte der RTL-Konvention `E<Name>` folgen';
      FullDesc : 'Die Delphi-RTL-Konvention ist eindeutig: Exception-Klassen beginnen mit `E` (EAbort, EConvertError, EAccessViolation). Eigene Exception-Klassen ohne das Pr' +
        #$00E4 +
        'fix brechen die Konvention und verschleiern die Art der Klasse an der Aufrufstelle (`raise MyError.Create(...)` vs. `raise EMyError.Create(...)`). Der Detektor findet jede Klasse, deren TypeRef von einer bekannten Exception-Klasse erbt (Exception, EA' +
        'bort, EAccessViolation, EExternal) und deren Name nicht mit `E<UpperCase>` beginnt.'
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Lokale Konstante nicht in UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` in einer Methode - f' + #$00FC +
        'r Zahlenkonstanten ist UPPER_SNAKE_CASE vorzuziehen';
      FullDesc : 'Lokale numerische/Integer-Konstanten in einem Methodenrumpf profitieren von UPPER_SNAKE_CASE (`MAX_RETRIES`, `BUFFER_SIZE`, `DEFAULT_TIMEOUT`) - der Leser sieht sofort, dass der Bezeichner eine Konstante und keine Variable ist, und die Konvention ent' +
        'spricht der von C / Java / Python, sodass Leser aus anderen Sprachen nicht stolpern. Der Detektor ' +
        #$00FC + 'berspringt: sehr kurze Namen (<=2 Zeichen, typischerweise Schleifenz' + #$00E4 +
        'hler oder Tempor' + #$00E4 +
        're), String-/Char-typisierte Konstanten (oft UI-Beschriftungen, bei denen PascalCase in Ordnung ist). F' +
        #$00FC +
        'r legitime lokale Konstanten in PascalCase mit `// noinspection LocalConstantName` unterdr' +
        #$00FC + 'cken.'
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Ausnahme erzeugt, aber nie ausgel' + #$00F6 + 'st';
      ShortDesc: '`EFoo.Create(''msg'');` legt ein Exception-Objekt an, ohne es zu `raise`n - der Fehlerpfad wird stillschweigend ' +
        #$00FC + 'bersprungen';
      FullDesc : 'Das Muster `EConvertError.Create(''bad input'');` ohne vorangehendes `raise` erzeugt eine Exception-Instanz, l' +
        #$00F6 + 'st sie nicht aus, und der aufrufende Code l' + #$00E4 + 'uft weiter, als w' +
        #$00E4 +
        're nichts geschehen. Das allokierte Objekt leckt (klassisches TObject) oder wird sofort eingesammelt (ARC), und der beabsichtigte Fehlerzweig ist verloren. Fast immer eine Copy-Paste-Regression aus `raise EConvertError.Create(...)`, bei der das Schl' +
        #$00FC + 'sselwort `raise` gel' + #$00F6 +
        'scht wurde. Heuristik des Detektors: jeder `nkCall` namens `<Ident>.Create(...)`, bei dem `<Ident>` `Exception` ist oder der Delphi-Konvention mit `E`-Pr' +
        #$00E4 + 'fix folgt (`E` + Gro' + #$00DF +
        'buchstabe, z. B. `EConvertError`, `EMyDomainError`). `raise X.Create(...)` wird vom Parser der raise-Anweisung als String ' +
        #$00FC + 'bernommen und erzeugt nie einen `nkCall`, daher sind tats' + #$00E4 +
        'chlich ausgel' + #$00F6 +
        'ste Ausnahmen keine Fehlalarme. Entspricht Sonar-Delphi `MissingRaiseCheck`.'
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'Funktion weist Result nie zu';
      ShortDesc: 'Der Funktionsrumpf endet, ohne `Result` (oder `<Funktionsname> := ...`) zu schreiben - der R' +
        #$00FC + 'ckgabewert ist undefiniert';
      FullDesc : 'Eine Funktion, die ihr `end;` ohne irgendein `Result := ...` oder Pascal-artiges `<FunctionName> := ...` erreicht, liefert den Register-/Stack-M' +
        #$00FC + 'll, der zuf' + #$00E4 + 'llig im Ergebnis-Slot steht. In Release-Builds erh' +
        #$00E4 + 'lt der Aufrufer daher den Wert des letzten Aufrufs gleicher Gr' + #$00F6 + #$00DF +
        'e - ein klassischer Heisenbug, der mit der Optimierungsstufe umschl' + #$00E4 +
        'gt. Der Detektor ist absichtlich konservativ: Er ' + #$00FC +
        'berspringt Funktionen, die ein `Exit` (k' + #$00F6 +
        'nnte `Exit(value)` sein) oder ein `raise` (die Funktion l' + #$00F6 + 'st wom' + #$00F6 +
        'glich immer aus) enthalten. Anmerkung: Der Parser erfasst das Argument von `Exit(value)` durchaus, dieses ' +
        #$00DC + 'berspringen ist also gr' + #$00F6 + 'ber als unbedingt n' + #$00F6 +
        'tig - eine Verengung w' + #$00FC + 'rde Funde hinzuf' + #$00FC +
        'gen und wartet deshalb auf einen gemessenen Korpuslauf. Prozeduren, abstract/forward/external-Deklarationen und reine DispatchID-Deklarationen werden ebenfalls ' +
        #$00FC +
        'bersprungen. Teilweise Abdeckung (Result nur in einem Zweig gesetzt) ist derzeit ein ' +
        #$00FC +
        'bersehener Fund, bis eine CFG-Analyse vorliegt. Entspricht Sonar-Delphi `RoutineResultAssignedCheck`.'
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Erneutes raise der gebundenen Ausnahme-Variablen';
      ShortDesc: '`on E: T do ... raise E;` verwirft den urspr' + #$00FC +
        'nglichen Stack-Trace - das blanke `raise;` erh' + #$00E4 + 'lt ihn';
      FullDesc : '`raise E` in einem Handler `on E: SomeException do ...` startet eine neue Ausnahme-Weitergabe, deren Ursprung die Stelle des erneuten Ausl' +
        #$00F6 + 'sens ist. Der urspr' + #$00FC +
        'ngliche Stack-Trace - der Weg von der Stelle, an der die Ausnahme zuerst ausgel' + #$00F6 +
        'st wurde, durch jede aufgerufene Routine bis zu diesem `except`-Block - ist verloren. Absturzberichte und Debugger-Ansichten zeigen dann auf den Handler, nicht auf die eigentliche Fehlerstelle, was die Triage drastisch erschwert. Gemeint war fast sic' +
        'her `raise;` (ohne Argument), das das *aktuelle* Exception-Objekt mit intaktem Stack-Trace weiterreicht. Der Detektor durchl' +
        #$00E4 +
        'uft jeden `nkOnHandler` mit nicht leerem gebundenem Variablennamen und meldet jedes `nkRaise` in diesem Teilbaum, dessen Argument genau diese Variable ist (ohne Beachtung der Gro' +
        #$00DF +
        '-/Kleinschreibung). `raise;` (ohne Argument) ist korrekt und wird nicht gemeldet; `raise EWrapper.Create(...)` wird ebenfalls akzeptiert (bewusstes Einpacken). Entspricht Sonar-Delphi `ReRaiseExceptionCheck`.'
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Typecast direkt vor Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - der Typecast beeinflusst nicht, welches Destroy l' + #$00E4 +
        'uft (Destroy ist virtuell)';
      FullDesc : '`TStringList(L).Free` oder `TObject(L).Destroy` zu schreiben ist ein Verwirrungs-Smell. `TObject.Free` ist ein nicht virtueller Wrapper um das *virtuelle* `Destroy`, daher erfolgt der virtuelle Dispatch ' +
        #$00FC + 'ber den Laufzeittyp von `L`, nicht ' + #$00FC +
        'ber den statischen Zieltyp des Typecasts. Ob `L.Free` oder `T(L).Free` geschrieben wird - es l' +
        #$00E4 + 'uft dieselbe Destruktorkette. Der Typecast ist daher entweder ' + #$00FC + 'berfl' +
        #$00FC + 'ssig (Typecast auf den eigenen Typ der Variablen) oder irref' + #$00FC +
        'hrend (Typecast auf eine fremde Klasse, der nahelegt, Destroy w' + #$00E4 +
        'hle ein anderes Override - das tut es nicht). Ist das Ziel des Typecasts falsch, kann sich der umgebende Code auf diese falsche Annahme st' +
        #$00FC +
        'tzen und bei Refactorings brechen. Der Detektor gleicht `nkCall.Name` mit den Mustern `<Ident>(<expr>).Free[()][;]` und `<Ident>(<expr>).Destroy[()][;]` ab, wobei `<Ident>` der Delphi-Namenskonvention f' +
        #$00FC + 'r Klassen/Interfaces folgt (`T` oder `I` plus Gro' + #$00DF +
        'buchstabe). Einfaches `L.Free` und qualifiziertes `Owner.Bar(x).Free` (vermutlich Free auf einem Funktionsergebnis) werden nicht gemeldet. Entspricht Sonar-Delphi `CastAndFreeCheck`.'
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Konstruktor auf einer Instanz statt der Klasse aufgerufen';
      ShortDesc: '`obj.Create` - ruft den Konstruktor als Methode auf einer bestehenden Instanz, ' + #$00FC +
        'berspringt die Allokation und initialisiert Felder ' + #$00FC + 'ber lebenden Daten neu';
      FullDesc : 'Delphi erlaubt es, einen Konstruktor auf einer Instanz aufzurufen, z. B. `obj.Create;`, das Ergebnis ist aber fast nie das Beabsichtigte. Als Klassenmethode aufgerufen (`TFoo.Create`), allokiert die Laufzeit zuerst ' +
        #$00FC +
        'ber `TObject.NewInstance` einen frischen Speicherblock, richtet den VMT-Zeiger ein und f' +
        #$00FC + 'hrt dann den Konstruktorrumpf aus. Auf einer bestehenden Instanz aufgerufen, entf' +
        #$00E4 + 'llt der Allokationspfad vollst' + #$00E4 + 'ndig - nur der Konstruktorrumpf l' +
        #$00E4 + 'uft und initialisiert Felder neu (`FList := TList.Create;` ' + #$00FC +
        'berschreibt das bisherige `FList`, ohne es freizugeben, Referenzen auf Managed Types werden zertrampelt, Vorgabewerte ' +
        #$00FC +
        'berschreiben, was der Aufrufer gesetzt hatte). Das Ergebnis ist bestenfalls ein Logikfehler, schlimmstenfalls Speicherkorruption. Heuristik des Detektors (kein Typ-Resolver verf' +
        #$00FC +
        'gbar): gleicht `nkCall.Name` mit `<Ident>.Create[(<args>)][;]` ab, wobei `<Ident>` mit einem Kleinbuchstaben beginnt (nach Delphi-Konvention klar eine Variable, da Typen das Pr' +
        #$00E4 + 'fix `T<Upper>` / `I<Upper>` tragen). ' + #$00DC +
        'bersprungen werden `Self`, `Result`, `Inherited`, Pfade mit mehreren Punkten (`A.B.Create` - mehrdeutig), Typecast-Formen (`T(x).Create`), Klassennamen und Empf' +
        #$00E4 + 'nger nach der Namenskonvention f' + #$00FC +
        'r Metaklassen (Bezeichner-Suffix `Class`, z. B. `itemClass: TFooClass`). Ein kleines bekanntes Fehlalarm-Risiko f' +
        #$00FC +
        'r anders benannte, `TClass`-typisierte Variablen mit Kleinbuchstaben wird in Kauf genommen (in der Praxis selten). Vorl' +
        #$00E4 + 'ufige Herabstufung des Schweregrads Fehler -> Warnung (2026-07-25): Ein Audit ' +
        #$00FC + 'ber den gesamten Korpus ma' + #$00DF +
        ' 100 % Fehlalarme auf der Stufe Fehler; bleibt Warnung, bis strukturelle Guards mit Typaufl' +
        #$00F6 + 'sung vorliegen. Entspricht Sonar-Delphi `InstanceInvokedConstructorCheck`.'
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Override, dessen Rumpf nur aus `inherited;` besteht';
      ShortDesc: 'Ein Override, das nur an die Basis weiterreicht, hat keinen Zweck - entfernen';
      FullDesc : 'Eine mit `override` deklarierte Methode, deren Implementierung nur den Vorfahren mit denselben Argumenten aufruft, f' +
        #$00FC +
        'gt dem Verhalten der Elternklasse nichts hinzu: Der virtuelle Dispatch erreicht den Vorfahren bereits, wenn die Ableitung nicht ' +
        #$00FC +
        'berschreibt. Das leere Override ist Rauschen, das Code-Reviews verlangsamt und bei jeder Signatur' +
        #$00E4 + 'nderung des Vorfahren erneut angefasst werden muss. Der Detektor durchl' + #$00E4 +
        'uft jede Methodenimplementierung `TClass.Name`, deren Rumpf aus genau einer Anweisung besteht - `inherited;` (Prozeduren, Konstruktoren, Destruktoren), `inherited Name;` (ohne Parameter), `inherited Name(p1, .., pn)` mit unver' +
        #$00E4 +
        'ndert und in Reihenfolge durchgereichten Parametern oder `Result := inherited [Name(..)]` in Funktionen - und liest die DEKLARATION in der Klasse derselben Unit (Implementierungsk' +
        #$00F6 +
        'pfe wiederholen `override` nie). Die Deklaration muss eindeutig sein (keine Overloads, keine {$IFDEF}-Zwillinge) und `override` und keine andere Direktive tragen (message, final, reintroduce, deprecated, Aufrufkonvention, ...), kein Attribut und kein' +
        'en Vorgabeparameter; zwischen Implementierungskopf und `end` darf keine Compiler-Direktive stehen. Klassenmethoden werden ' +
        #$00FC +
        'bersprungen. Sichtbarkeit: Ist die Methode des Vorfahren in derselben Unit deklariert und weniger sichtbar, erweitert das Override ihre Sichtbarkeit und wird nicht gemeldet. Liegt der Vorfahr au' +
        #$00DF + 'erhalb der Unit, werden private/protected Overrides und ' + #$00F6 +
        'ffentliche Overrides bekannter ' + #$00F6 +
        'ffentlicher Wurzelmethoden (Destroy, Create, AfterConstruction, BeforeDestruction, Assign, ToString, Equals, GetHashCode) mit hoher Konfidenz gemeldet, andere public/published Overrides mit niedriger Konfidenz (standardm' +
        #$00E4 + #$00DF +
        'ig ausgeblendet). Die Quelldatei muss lesbar sein. Entspricht Sonar-Delphi `InheritedMethodWithNoCodeCheck`.'
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Assigned() statt `= nil` / `<> nil` verwenden';
      ShortDesc: 'Pascal-Konvention: `Assigned(x)` und `not Assigned(x)` sind die kanonischen nil-Pr' +
        #$00FC + 'fungen';
      FullDesc : 'Der direkte Vergleich mit `nil` funktioniert f' + #$00FC +
        'r Objektreferenzen, versagt aber bei Methodenzeiger-Typen und Variants, f' + #$00FC +
        'r die die Standardbibliothek `Assigned` bevorzugt. Eine einheitliche Form in der gesamten Codebasis vermeidet Randfall-Fehler und verbessert die Lesbarkeit - der Leser muss nicht pr' +
        #$00FC + 'fen, welche Form der Typ der Variablen unterst' + #$00FC +
        'tzt. Der Detektor durchsucht `Name` und `TypeRef` jedes AST-Knotens (letzteres enth' +
        #$00E4 +
        'lt die Textform von `if`/`while`/`until`-Bedingungen und rechten Seiten von Zuweisungen) nach dem Muster `<op> nil`, wobei `<op>` `=` oder `<>` ist. String-Literale (`''nil''`) werden vor dem Abgleich entfernt, und `:= nil` (Zuweisung), `<= nil` / `>= ' +
        'nil` (seltene unsinnige Vergleiche) sind ausdr' + #$00FC +
        'cklich ausgenommen. Entspricht Sonar-Delphi `NilComparisonCheck`.'
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Basisklasse `Exception` statt einer eigenen Ableitung ausgel' + #$00F6 + 'st';
      ShortDesc: '`raise Exception.Create(''...'')` - die Basisklasse tr' + #$00E4 +
        'gt keine Semantik, Aufrufer k' + #$00F6 + 'nnen nicht gezielt filtern';
      FullDesc : 'Die RTL-Basisklasse `Exception` auszul' + #$00F6 +
        'sen entspricht `new Error(''something'')` in JavaScript: Es teilt dem Aufrufer mit, *dass* etwas schiefging, aber nicht *was*. Der aufrufende Code muss dann die breitestm' +
        #$00F6 + 'gliche Klasse fangen (`on E: Exception do ...`), die auch jeden unabh' + #$00E4 +
        'ngigen Laufzeitfehler f' + #$00E4 +
        'ngt und dazu neigt, Fehler zu verschlucken. Eine spezifische Ableitung ist vorzuziehen (z. B. `EArgumentOutOfRangeException`, `EFileNotFoundException`, ein dom' +
        #$00E4 + 'nenspezifisches `EMyDomainError`). Der Detektor durchl' + #$00E4 +
        'uft jeden `nkRaise`-Knoten und meldet ihn, wenn der ausgel' + #$00F6 +
        'ste Ausdruck mit `Exception.Create` beginnt (ohne Beachtung der Gro' + #$00DF +
        '-/Kleinschreibung) oder genau `Exception` ist (ohne Create-Aufruf). Blankes `raise;` (erneutes Ausl' +
        #$00F6 +
        'sen) und `raise E;` (Variable) werden nicht gemeldet. Entspricht Sonar-Delphi `RaisingRawExceptionCheck`.'
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Gebietsschema-abh' + #$00E4 + 'ngiger Formataufruf ohne TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` und Verwandte ohne TFormatSettings h' + #$00E4 +
        'ngen am System-Gebietsschema - je Rechner und Benutzer verschieden';
      FullDesc : 'Die gebietsschemaabh' + #$00E4 +
        'ngigen Konvertierungsfunktionen von Pascal (`StrToDate`, `StrToTime`, `StrToDateTime`, `DateToStr`, `TimeToStr`, `DateTimeToStr`, `StrToFloat`, `StrToCurr`, `FloatToStr`, `CurrToStr`, `FormatDateTime`, `FormatFloat`, `FormatCurr`) verwenden standardm' +
        #$00E4 + #$00DF +
        'ig den globalen Record `SysUtils.FormatSettings`, der aus den Regionaleinstellungen des Betriebssystems initialisiert wird. Derselbe Code verh' +
        #$00E4 +
        'lt sich daher auf einem Entwicklerrechner mit DE-Gebietsschema (`DateSeparator` = ''.'', `DecimalSeparator` = '','') anders als auf einem Produktionsserver mit EN-Gebietsschema (''/'' und ''.''). Daten, die ' +
        #$00FC + 'ber Dateien, APIs, Datenbanken oder CSV ausgetauscht werden, m' + #$00FC +
        'ssen immer ' + #$00FC +
        'ber explizite `TFormatSettings` laufen (typischerweise ein lokales `LFormatSettings := TFormatSettings.Invariant` f' +
        #$00FC + 'r maschinenlesbare Ausgabe oder ein Schnappschuss des Benutzer-Gebietsschemas f' +
        #$00FC + 'r die UI). Der Detektor durchl' + #$00E4 +
        'uft jeden `nkCall`, dessen Funktionsname einer bekannten gebietsschemaabh' + #$00E4 +
        'ngigen RTL-Routine entspricht, und meldet den Aufruf, wenn seine Argumentliste keinen Bezeichner erw' +
        #$00E4 + 'hnt, der `FormatSettings` oder `FmtSettings` enth' + #$00E4 +
        'lt (Teilstring, ohne Beachtung der Gro' + #$00DF +
        '-/Kleinschreibung) - die Settings-Variable also entsprechend benennen (`LFormatSettings`, `FFmtSettings`). `StrToInt` / `IntToStr` und die Boolean-Varianten sind ausdr' +
        #$00FC + 'cklich **nicht** gebietsschemaabh' + #$00E4 +
        'ngig und werden nicht gemeldet. Entspricht Sonar-Delphi `DateFormatSettingsCheck`.'
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'Typecast von string in einen 8-Bit-String-Typ ohne explizite Kodierung';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` verwirft stillschweigend alle Zeichen au' +
        #$00DF + 'erhalb der aktiven Codepage';
      FullDesc : 'Ein UnicodeString (oder jeder String-typisierte Ausdruck - der Delphi-string ist seit XE UnicodeString) per Typecast in eine der verlustbehafteten 8-Bit-String-Familien (AnsiString, RawByteString, ShortString) umzuwandeln, l' +
        #$00E4 + 'uft ' + #$00FC +
        'ber die implizite DefaultSystemCodePage-Konvertierung. Jeder Codepoint au' + #$00DF +
        'erhalb der aktiven Codepage wird stillschweigend durch ? ersetzt. Emoji, nichtlateinische Schriften und sogar einige westliche Buchstaben mit Akzent verschwinden, doch die Zuweisung kompiliert sauber und l' +
        #$00E4 + 'uft ohne Ausnahme - der Fehler zeigt sich daher erst, wenn die Daten ' + #$00FC +
        'ber einen Unicode-f' + #$00E4 + 'higen Verwender zur' + #$00FC +
        'cklaufen (eine andere DB, eine HTTP-API, ein Excel-Export). Stattdessen einen bewussten Kodierungs-Helfer verwenden (UTF8Encode, TEncoding.UTF8.GetBytes, WideStringToUTF8 ...). Der Detektor durchl' +
        #$00E4 + 'uft nkCall-Knoten, deren Name (ohne Beachtung der Gro' + #$00DF +
        '-/Kleinschreibung) mit AnsiString(, RawByteString( oder ShortString( beginnt, d. h. eine Anweisung oder Zuweisung, die mit dem Typecast beginnt; ein Typecast, der in einem anderen Aufruf oder mitten in einem Ausdruck steckt (`SaveToFile(AnsiString(u)' +
        ')`, `''x'' + AnsiString(u)`), wird nicht gesehen. UTF8String(...) wird bewusst NICHT gemeldet: UTF8String ist type AnsiString(CP_UTF8), daher erzeugt der Typecast genau denselben Code wie das empfohlene UTF8Encode und ist unabh' +
        #$00E4 +
        'ngig von der System-Codepage verlustfrei. Der einzige verbleibende verlustbehaftete Unterfall, UTF8String(<bereits 8-Bit>), ist ein akzeptierter ' +
        #$00FC +
        'bersehener Fund (null Vorkommen im Referenzkorpus). Leere String-Literal-Argumente (AnsiString('''')) werden nicht gemeldet. Typecasts nach string (= UnicodeString in modernem Delphi) werden ebenfalls nicht gemeldet. Akzeptiert wird der Fehlalarm, dass' +
        ' die Eingabe bereits derselbe 8-Bit-Typ sein k' + #$00F6 + 'nnte (' + #$00FC + 'berfl' +
        #$00FC + 'ssiger Typecast, als Smell trotzdem verd' + #$00E4 +
        'chtig). Entspricht Sonar-Delphi UnicodeToAnsiCastCheck. FPC/Lazarus-Dialekt: Diese Regel wird ' +
        #$00FC + 'bersprungen, wenn der Scan mit --dialect=fpc l' + #$00E4 +
        'uft - unter FPC IST der Standard-String-Typ 8-Bit (nach Lazarus-Konvention UTF-8), daher ist der Typecast dort keine verlustbehaftete Unicode-Verengung.'
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Typecast eines Char-Werts nach PChar - Codepoint wird zur Adresse';
      ShortDesc: '`PChar(''A'')` ist nicht `PChar("A")` - der Typecast deutet den 16-Bit-Codepoint als rohe Speicheradresse';
      FullDesc : 'Delphi kompiliert anstandslos `PChar(c)`, wenn `c` vom Typ `Char`, `WideChar` oder `AnsiChar` ist. Das Ergebnis ist **kein** nullterminierter 1-Zeichen-String - der Typecast deutet den 16-Bit-/8-Bit-Codepoint einfach als Zeiger. `PChar(''A'')` liefert ' +
        'also den Zeigerwert `$00000041`, der in den unteren Prozessspeicher zeigt; jede Dereferenzierung ist undefiniertes Verhalten und endet typischerweise in einer Access Violation, liest auf manchen Plattformen aber stattdessen veraltete Daten. Gemeint i' +
        'st fast immer das Muster `PChar(stringExpr)`, das einen Zeiger in den tats' + #$00E4 +
        'chlichen String-Puffer liefert. Der Detektor durchl' + #$00E4 +
        'uft `nkCall`-Knoten, deren Name mit `PChar(`, `PWideChar(` oder `PAnsiChar(` beginnt, und meldet den Aufruf, wenn das Argument erkennbar ein Char-Wert ist: ein in Anf' +
        #$00FC +
        'hrungszeichen gesetztes Literal aus einem Zeichen (`''A''`), ein Zeichen-Ordinal-Literal (`#65`, `#$41`) oder ein Aufruf `Chr(...)`. Bezeichner als Argumente werden nicht gemeldet, da der Detektor keinen Typ-Resolver hat, um zu bestimmen, ob die Variab' +
        'le ein `Char` oder ein `string` ist. Entspricht Sonar-Delphi `CharacterToCharacterPointerCastCheck`.'
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() wertet beide Zweige aus - keine Kurzschlussauswertung';
      ShortDesc: '`Math.IfThen(cond, A(), B())` und `StrUtils.IfThen` sind normale Funktionen - beide Arme laufen vor dem Aufruf';
      FullDesc : 'Sowohl `Math.IfThen` (Integer-/Double-Overload) als auch `StrUtils.IfThen` (String-Overload) sind normale Funktionen, keine Sprachkonstrukte. Pascal wertet jedes Argument *vor* dem Aufruf aus, die Funktion sieht also nur die fertigen Ergebniswerte - ' +
        'sie kann den nicht gew' + #$00E4 + 'hlten Zweig nicht ''' + #$00FC +
        'berspringen''. Enthalten die Arme Funktions- oder Methodenaufrufe mit Seiteneffekten (DB-Lesezugriff, Datei-IO, Zustands' +
        #$00E4 +
        'nderung) oder mit nennenswerten Performance-Kosten, laufen beide bedingungslos. Der eigentliche Grund, `IfThen(cond, A, B)` statt `if cond then x := A else x := B` zu schreiben, war meist die Annahme einer Kurzschlussauswertung - die es hier nicht gi' +
        'bt. Der Detektor durchl' + #$00E4 +
        'uft `nkCall`-Knoten, deren Name `IfThen(`, `Math.IfThen(` oder `StrUtils.IfThen(` entspricht (ohne Beachtung der Gro' +
        #$00DF + '-/Kleinschreibung). Nach dem Herausl' + #$00F6 + 'sen der ' + #$00E4 + 'u' +
        #$00DF +
        'eren Argumentliste entfernt er String-Literale (damit `''a(b)''` die Heuristik nicht ausl' +
        #$00F6 +
        'st) und sucht nach verschachtelten `(` - jeder verschachtelte Aufruf ist ein starkes Signal f' +
        #$00FC +
        'r einen Zweig mit Seiteneffekten. Aufrufe mit nur Literalen oder einfachen Variablen als Armen werden nicht gemeldet - ebenso wenig parameterlose Funktionsaufrufe ohne Klammern (`IfThen(b, FetchA, FetchB)`), weil sich ein Aufruf ohne Klammern nicht v' +
        'on einer Variablen unterscheiden l' + #$00E4 +
        'sst. Entspricht Sonar-Delphi `IfThenShortCircuitCheck`.'
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception f' + #$00E4 + 'ngt jeden Fehler';
      ShortDesc: '`on E: Exception do ...` f' + #$00E4 +
        'ngt die Basisklasse und damit jede Ableitung, auch System-Ausnahmen, die nicht stillgestellt werden d' +
        #$00FC + 'rfen (EOutOfMemory, EAccessViolation, EAbort)';
      FullDesc : '`Exception` selbst zu fangen - die Wurzel der Delphi-Ausnahmehierarchie - verschluckt stillschweigend Fehlerkategorien, auf die der aufrufende Code nicht vorbereitet ist: Speichermangel, Access Violations, die Ablaufsteuerungs-Ausnahme im Stil von `E' +
        'Abort` und alles andere, was nicht von einer dom' + #$00E4 +
        'nenspezifischen Basisklasse abgeleitet ist. Vorzuziehen ist eine pr' + #$00E4 +
        'zise Klausel `on E: ESpecific do` oder mehrere gestapelte Klauseln f' + #$00FC + 'r die F' +
        #$00E4 + 'lle, aus denen eine Erholung m' + #$00F6 +
        'glich ist. Wird wirklich ein Fallback gebraucht, der nach dem Protokollieren erneut ausl' +
        #$00F6 + 'st, `except Log(''''...''''); raise; end;` verwenden - das blanke `raise;` erh' +
        #$00E4 + 'lt den urspr' + #$00FC + 'nglichen Typ und Stack. Der Detektor durchl' + #$00E4 +
        'uft `nkOnHandler`-Knoten und meldet die, deren `TypeRef` gleich `Exception` ist (ohne Beachtung der Gro' +
        #$00DF + '-/Kleinschreibung). Entspricht Sonar-50-Regel #11 (`ExceptionTooGeneral`).'
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'Blankes raise au' + #$00DF + 'erhalb eines except/on-Handlers';
      ShortDesc: '`raise;` ohne Ausnahme-Ausdruck ist nur INNERHALB eines except-Handlers g' + #$00FC +
        'ltig (erneutes Ausl' + #$00F6 + 'sen) - ' + #$00FC +
        'berall sonst lehnen Delphi (E2145) und FPC es ab';
      FullDesc : 'Ein blankes `raise;` l' + #$00F6 +
        'st die gerade behandelte Ausnahme erneut aus und ist daher nur innerhalb von `except` / `on E: T do` g' +
        #$00FC + 'ltig. Delphi lehnt diese Form ' + #$00FC +
        'berall sonst mit dem Compilerfehler E2145 ''Re-raising an exception only allowed in exception handler'' ab, FPC mit `parser_e_no_reraise_possible` (''Re-raise isn''t possible there''). Der Detektor durchl' +
        #$00E4 + 'uft den Methoden-AST rekursiv und f' + #$00FC +
        'hrt dabei ein Flag `InHandler` mit. Das Flag wird gesetzt, wenn der Durchlauf in `nkExceptBlock` oder `nkOnHandler` absteigt. Ein `nkRaise`-Knoten mit `Name = ''raise''` (blanke Form), der angetroffen wird, w' +
        #$00E4 + 'hrend das Flag False ist, erzeugt einen Fund. Blankes `raise;` in `finally`-Bl' +
        #$00F6 + 'cken, die selbst au' + #$00DF +
        'erhalb eines except-Handlers liegen, wird ebenfalls gemeldet. Entspricht Sonar-50-Regel #15 (`RaiseWithoutClass`).'
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable nach Free / FreeAndNil verwendet';
      ShortDesc: 'Eine Variable nach `Free` oder `FreeAndNil` zu dereferenzieren liest einen h' + #$00E4 +
        'ngenden Zeiger und erzeugt eine Access Violation';
      FullDesc : 'Nach `obj.Free` oder `FreeAndNil(obj)` zeigt die Variable auf freigegebenen Speicher (oder ist NIL). Jeder sp' +
        #$00E4 + 'tere Member-Zugriff, Indexer oder Aufruf mit der Variablen als Empf' + #$00E4 +
        'nger ist undefiniertes Verhalten - typischerweise eine Access Violation, manchmal stille Korruption, wenn der Speicher wiederverwendet wurde. Der Detektor entfernt Strings + Kommentare aus der Datei, findet jedes Vorkommen von `FreeAndNil(<id>)` und ' +
        '`<id>.Free` und durchsucht dann den restlichen Methodenrumpf vorw' + #$00E4 +
        'rts nach demselben Bezeichner. Ein folgendes `<id>.<member>`, `<id>(<args>)` oder `<id>[<idx>]` erzeugt einen Fund. Neuzuweisungen `<id> := ...` oder Anf' +
        #$00E4 + 'nge eines var-Abschnitts `<id> :` beenden das Suchfenster. Blo' + #$00DF +
        'es Vorkommen ohne Zugriffsoperator wird absichtlich nicht gemeldet, um Fehlalarme bei Vergleichen wie `if x = oldL then` zu vermeiden. Entspricht Sonar-50-Regel #7. Einschr' +
        #$00E4 +
        'nkung: keine Kontrollflussanalyse; `if Cond then Free else Use` kann einen Fehlalarm erzeugen, da die Verwendung auf einem anderen Pfad liegt.'
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Konkrete Ableitung erbt eine abstrakte Methode ohne override';
      ShortDesc: 'Die Klasse leitet von einer Basis mit `abstract`-Methode ab, ' + #$00FC +
        'berschreibt sie aber nicht - der Aufruf auf der Instanz l' + #$00F6 +
        'st zur Laufzeit EAbstractError aus';
      FullDesc : 'Erbt eine Klasse eine `abstract`-Methode von ihrer Elternklasse und ' + #$00FC +
        'berschreibt sie nicht, kompiliert die Instanziierung der Klasse problemlos, aber jeder Aufruf der Methode l' +
        #$00F6 + 'st `EAbstractError` aus. Der Detektor durchl' + #$00E4 + 'uft `nkClass`-Knoten; f' +
        #$00FC +
        'r jede abgeleitete Klasse sucht er die direkte Elternklasse in derselben Unit, sammelt deren als `abstract` markierte Methoden und meldet jede abstrakte Methode, deren Name nicht unter den Methodennamen der abgeleiteten Klasse vorkommt. Einschr' +
        #$00E4 +
        'nkungen: nur innerhalb der Unit (Basen aus anderen Units wie `TForm`/`TStrings` werden nicht gesehen); nur die direkte Elternklasse (mehrstufige Ketten pr' +
        #$00FC + 'fen nur eine Stufe); Class Helper / Interfaces / Records werden ' + #$00FC +
        'bersprungen. Klassen, die selbst als `class abstract` markiert sind, d' + #$00FC +
        'rfen Methoden abstrakt lassen. Entspricht Sonar-50-Regel #10.'
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Konstruktor belegt Felder und l' + #$00F6 + 'st ohne try/except aus';
      ShortDesc: 'Der Konstruktor weist Felder per `<Klasse>.Create` zu und l' + #$00F6 + 'st sp' + #$00E4 +
        'ter ohne try/except aus - die Felder lecken, wenn der Destruktor sie nicht freigibt';
      FullDesc : 'L' + #$00F6 +
        'st ein Konstruktor eine Ausnahme aus, ruft Delphi automatisch den Destruktor auf der halb konstruierten Instanz auf. Felder, die der Konstruktor bereits allokiert hat, werden nur freigegeben, wenn dieser Destruktor sie freigibt - ohne Destruktor oder' +
        ' mit einem, der diese Felder nicht freigibt, lecken sie. Der Detektor durchl' + #$00E4 +
        'uft `nkMethod`-Knoten, deren `TypeRef` mit `constructor` beginnt (Klassenkonstruktoren werden ' +
        #$00FC + 'ber den Marker `;class` ' + #$00FC +
        'bersprungen), und verlangt dann (a) mindestens ein `nkAssign`, dessen LHS `F<Name>` / `Self.F<Name>` ist und dessen RHS einen Aufruf `.Create` enth' +
        #$00E4 +
        'lt, (b) mindestens ein `nkRaise` irgendwo im Rumpf und (c) kein `nkTryExcept` irgendwo im Rumpf. Der Detektor liest auch die Destruktoren der Klasse in derselben Unit: Geben sie jedes allokierte Feld frei (ein Aufruf `Free`, `FreeAndNil`, `Release` o' +
        'der `DisposeOf`, der das Feld nennt, oder `F<Name> := nil` f' + #$00FC +
        'r ein Interface-Feld), gibt es keinen Fund - es sei denn, ein Destruktor schreibt ohne `if` darauf in ein Member eines solchen Felds (er w' +
        #$00FC +
        'rde am nil-Feld scheitern, bevor der Rest freigegeben ist), oder ein Thread-Konstruktor l' +
        #$00F6 + 'st vor seinem benannten `inherited Create` aus. Freigabe ' + #$00FC +
        'ber eine Property, eine Hilfsmethode, eine Owner-Komponente oder einen Destruktor in einer anderen Unit wird nicht erkannt; solche Funde sind Fehlalarme. Einschr' +
        #$00E4 +
        'nkungen: keine Flussanalyse (raise VOR jeder Feldinitialisierung wird trotzdem gemeldet); ein teilweises try/except gilt als vollst' +
        #$00E4 + 'ndig sch' + #$00FC + 'tzend. Entspricht Sonar-50-Regel #12.'
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Int64-Ziel bekommt das Produkt zweier 32-Bit-Operanden';
      ShortDesc: '`<Int64-Var> := <a> * <b>` rechnet die Multiplikation in 32 Bit, bevor erweitert wird - ein ' +
        #$00DC + 'berlauf schneidet stillschweigend ab';
      FullDesc : 'Delphi wertet einen bin' + #$00E4 +
        'ren Ausdruck im Typ seiner Operanden aus, nicht im Typ des Zuweisungsziels. Werden zwei `Integer`-Operanden (32-Bit) multipliziert und wird das Ergebnis einem `Int64` zugewiesen, l' +
        #$00E4 + 'uft die Multiplikation in 32 Bit; ' + #$00FC + 'bersteigt das tats' + #$00E4 +
        'chliche Produkt `MaxInt`, wird der Wert stillschweigend abgeschnitten, bevor er erweitert wird. Die Korrektur besteht darin, mindestens einen Operanden per Typecast nach `Int64` umzuwandeln. Der Detektor entfernt Strings + Kommentare, durchsucht den ' +
        'bereinigten Text nach Deklarationen `<ident>: Int64|UInt64|QWord`, um eine Menge von 64-Bit-Variablen aufzubauen, und sucht dann nach Zuweisungen `<lhs> := <a> * <b>;`, bei denen die LHS eine 64-Bit-Variable ist, beide RHS-Operanden aber einfache Bez' +
        'eichner sind (kein Typecast, kein geklammerter Ausdruck), die selbst nicht 64-Bit sind. Numerische Literale auf einer der beiden Seiten unterdr' +
        #$00FC + 'cken den Fund (der Compiler kann oft sicher konstant falten). Einschr' + #$00E4 +
        'nkungen: keine Typinferenz f' + #$00FC +
        'r nicht lokale Operanden (Parameter, Felder); nur `*` wird gepr' + #$00FC +
        'ft, nicht `+`/`-`; komplexe Ausdr' + #$00FC +
        'cke wie `(a + b) * c` werden nicht erfasst. Entspricht Sonar-50-Regel #14.'
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'Klasse hat zu viele Methoden oder Felder';
      ShortDesc: 'Eine Klasse mit mehr als 20 Methoden oder mehr als 15 Instanzfeldern b' + #$00FC +
        'ndelt zu viele Zust' + #$00E4 + 'ndigkeiten - schwer zu testen, zu ' + #$00E4 +
        'ndern und zu pr' + #$00FC + 'fen';
      FullDesc : 'God-Klassen sind Klassen, die zu viel Verhalten und Zustand auf einmal besitzen: typische Beispiele sind UI-Composite-Roots, All-in-one-Manager-Singletons oder Dom' +
        #$00E4 + 'nenentit' + #$00E4 +
        'ten der ersten Generation, die mit der Anwendung gewachsen sind. Der Detektor durchl' +
        #$00E4 + 'uft `nkClass`-Knoten, z' + #$00E4 +
        'hlt die direkten `nkMethod`- und `nkField`-Kinder (einschlie' + #$00DF +
        'lich derer in `nkVisibilitySection`) und erzeugt einen Fund, wenn MethodCount > 20 ODER FieldCount > 15. Records, Interfaces, Class Helper, Forward-Deklarationen und als `class abstract` markierte Klassen (Vertr' +
        #$00E4 + 'ge mit Design-Absicht) werden ' + #$00FC +
        'bersprungen. Properties werden nicht gez' + #$00E4 + 'hlt - sie sind syntaktischer Zucker ' +
        #$00FC +
        'ber Getter/Setter-Paaren. Die Schwellen sind fest auf die Sonar-Standardwerte kodiert; God-Klassen ' +
        #$00FC +
        'berschreiten sie typischerweise um das 3-5-Fache, daher muss die Grenze nicht fein einstellbar sein. Entspricht Sonar-50-Regel #31.'
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free ohne anschlie' + #$00DF + 'endes nil-Setzen';
      ShortDesc: '`obj.Free;` ohne `obj := nil;` (oder ohne FreeAndNil) hinterl' + #$00E4 + 'sst einen h' +
        #$00E4 + 'ngenden Zeiger - jede weitere Verwendung ist ein Use-After-Free';
      FullDesc : 'Nach `obj.Free` zeigt die Variable weiterhin auf den freigegebenen Speicher. Jede weitere Dereferenzierung ist Use-After-Free, bestenfalls eine Access Violation, schlimmstenfalls stille Korruption. Der Detektor durchl' +
        #$00E4 +
        'uft `nkCall`-Knoten, deren Name `<ident>.Free` oder `<ident>.Destroy` entspricht, und durchsucht dann dieselbe Methode vorw' +
        #$00E4 +
        'rts nach einem folgenden `<ident> := nil` oder `FreeAndNil(<ident>)`. Fehlt beides, wird der Aufruf gemeldet - in einer Methode auch, wenn er der letzte Aufruf ist: Ein Feld ' +
        #$00FC + 'berlebt die Methode, und eine sp' + #$00E4 + 'tere `Assigned`-Pr' + #$00FC +
        'fung oder der Destruktor ber' + #$00FC +
        'hrt freigegebenen Speicher (in einem Konstruktor f' + #$00FC +
        'hrt Delphi bei jeder Ausnahme den Destruktor aus). Eine eigenst' + #$00E4 +
        'ndige Routine, die als letzten Aufruf eine globale Variable freigibt (Aufr' + #$00E4 +
        'umen am Programm- oder Skriptende), wird nicht gemeldet, au' + #$00DF +
        'er es folgt ein `raise`. Lokale Variablen, Inline-Konstanten und `const`-Parameter werden ' +
        #$00FC + 'bersprungen (sie verlassen den G' + #$00FC +
        'ltigkeitsbereich), ebenso Destruktoren, `BeforeDestruction`, `DoFree`, `FinalizeClass`, OnDestroy-Handler und eigenst' +
        #$00E4 +
        'ndige `Finalize*`-Routinen (mit ihnen endet die Instanz, die Klasse oder das Programm). `Self`/`Result`/`inherited` als Empf' +
        #$00E4 +
        'nger sind ausgenommen, da sie anderen Lebenszyklusmustern folgen. Entspricht Sonar-50-Regel #25.'
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'Methode hat zu viele Exit-Anweisungen';
      ShortDesc: 'Eine Methode mit mehr als 6 Exit-Aufrufen hat zu viele R' + #$00FC +
        'cksprungpfade - schwer zu lesen, schwer zu testen, leicht einen zu ' + #$00FC + 'bersehen';
      FullDesc : 'Mehrere fr' + #$00FC + 'he R' + #$00FC + 'ckspr' + #$00FC + 'nge sind f' + #$00FC +
        'r Guard-Clauses n' + #$00FC +
        'tzlich, ab einer kleinen Anzahl zersplittern sie den Kontrollfluss aber so stark, dass k' +
        #$00FC + 'nftige Maintainer Bedingungen ' + #$00FC + 'bersehen. Der Detektor z' + #$00E4 +
        'hlt die `nkExit`-Nachfahren jedes `nkMethod` und meldet eine Methode mit mehr als 6 davon: 6 Exit-Anweisungen bleiben still, 7 werden gemeldet. Die Schwelle ist im Detektor fest (`MAX_EXITS`). Exit-Anweisungen in verschachtelten Routinen und anonymen' +
        ' Methoden z' + #$00E4 +
        'hlen nicht. Refactoring-Optionen: Guards zu einem einzigen `if (... or ... or ...) then Exit;` zusammenfassen, von fr' +
        #$00FC + 'hen R' + #$00FC + 'ckspr' + #$00FC + 'ngen auf eine einzige R' + #$00FC +
        'ckgabevariable umstellen oder die innere Logik in einen Helfer extrahieren. Entspricht Sonar-50-Regel #34.'
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'Klassenimplementierung ' + #$00FC + 'berschreitet 500 Zeilen';
      ShortDesc: 'Eine Klasse, deren Deklaration und Implementierungsmethoden zusammen ' + #$00FC +
        'ber 500 Zeilen umfassen, hat zu viele Zust' + #$00E4 + 'ndigkeiten';
      FullDesc : 'Wie GodClass (SCA138), aber nach Zeilenspanne statt nach Methoden-/Feldanzahl gemessen. Erfasst Klassen, die nach Member-Anzahl klein wirken, aber riesige Implementierungsr' +
        #$00FC + 'mpfe haben - typisch f' + #$00FC + 'r Legacy-Logikklassen, die ' + #$00FC +
        'ber Jahre gewachsen sind. Der Detektor durchl' + #$00E4 + 'uft `nkClass`-Knoten; f' +
        #$00FC + 'r jede Klasse bestimmt er eine Spanne ' + #$00FC +
        'ber min(class-decl-line, first-method-with-prefix-line) .. max(class-decl-children-line, last-method-with-prefix-line). Schwelle 500 Zeilen. Records, Interfaces, Helper und Forward-Deklarationen werden ' +
        #$00FC + 'bersprungen. Entspricht Sonar-50-Regel #35.'
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'uses-Klausel ist nicht alphabetisch sortiert';
      ShortDesc: 'Eintr' + #$00E4 +
        'ge einer `uses`-Klausel stehen nicht alphabetisch - Merges werden unvorhersehbar und Reviews schwerer';
      FullDesc : 'Alphabetische Reihenfolge h' + #$00E4 +
        'lt Merge-Konflikte deterministisch und beseitigt eine ganze Klasse von Bikeshedding im Code-Review. Der Detektor durchl' +
        #$00E4 + 'uft `nkUses`-Knoten, sammelt die `nkUsesItem`-Kinder und vergleicht die tats' +
        #$00E4 + 'chliche Reihenfolge mit einer Sortierung ohne Beachtung der Gro' + #$00DF +
        '-/Kleinschreibung. Jede Abweichung erzeugt einen Fund auf der `uses`-Zeile. Klauseln mit nur einem Eintrag werden ' +
        #$00FC + 'bersprungen. Der Schweregrad ist Hinweis, weil viele Projekte die Eintr' + #$00E4 +
        'ge bewusst nach Schicht gruppieren (RTL / VCL / Drittanbieter / eigene) statt alphabetisch - Opt-in-Stil, keine harte Regel. Entspricht Sonar-50-Regel #47.'
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'Unit hat keinen erkl' + #$00E4 + 'renden Header-Kommentar';
      ShortDesc: 'Die Unit beginnt direkt mit `interface`, ohne erkl' + #$00E4 +
        'renden Kommentarblock zwischen `unit ...;` und `interface`';
      FullDesc : 'Ein kurzer Header-Kommentar zwischen der Deklaration `unit ...;` und dem Schl' + #$00FC +
        'sselwort `interface` sagt k' + #$00FC +
        'nftigen Maintainern, wozu die Unit dient - Zweck, Umfang, wichtige Invarianten, Zust' +
        #$00E4 +
        'ndigkeit. Der Detektor liest die ersten Zeilen der Datei, findet die Marker `unit` und `interface` und pr' +
        #$00FC +
        'ft, dass mindestens eine Kommentarzeile (`//`, `{...}` oder `(* ... *)`) dazwischen steht. Der Schweregrad ist Hinweis, weil viele Legacy-Units den Header ohne funktionale Folgen weglassen. Entspricht Sonar-50-Regel #48.'
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Gleichheits-/Ungleichheitsvergleich von Gleitkommazahlen';
      ShortDesc: '`a = b` oder `a <> b` zwischen Single/Double/Extended ist wegen der IEEE-754-Rundung unzuverl' +
        #$00E4 + 'ssig - SameValue oder Math.IsZero verwenden';
      FullDesc : 'IEEE-754-Gleitkommaarithmetik garantiert keine exakte Gleichheit, selbst bei Ergebnissen, die f' +
        #$00FC + 'r den Entwickler identisch aussehen (`0.1 + 0.2 = 0.3` ist False). Gleichheitspr' +
        #$00FC +
        'fungen auf Gleitkommazahlen sind eine klassische Quelle stiller Fehler - in Tests sehen sie gut aus, schlagen aber gelegentlich falsch aus. Der Detektor entfernt Strings und Kommentare und arbeitet dann in zwei Phasen: (1) sammelt lokale Variablendek' +
        'larationen vom Typ `Single`, `Double`, `Extended`, `Real` oder `Currency`; (2) sucht nach `<ident> = <expr>` oder `<ident> <> <expr>`, wobei mindestens eine Seite eine bekannte Gleitkommavariable referenziert. `:=`-Zuweisungen werden per Lookbehind a' +
        'usgeschlossen. Einschr' + #$00E4 + 'nkungen: keine Typinferenz f' + #$00FC +
        'r Funktionsergebnisse oder nicht lokale Parameter; komplexe Ausdr' + #$00FC +
        'cke wie `a + b = c + d` schlagen nur an, wenn mindestens ein Operand eine bekannte Gleitkommavariable ist. Entspricht Sonar-50-Regel #19. Korrektur: `System.Math.SameValue(a, b, Eps)` oder `IsZero(a - b)` verwenden.'
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise im Destruktor ohne try/except';
      ShortDesc: 'Ein ungesch' + #$00FC + 'tztes `raise` im Destruktor bricht die Aufr' + #$00E4 +
        'umkette ab - inherited Destroy und nachfolgende FreeAndNil-Aufrufe entfallen, der Zustand bleibt inkonsistent';
      FullDesc : 'Aufgabe eines Destruktors ist es, die Ressourcen einer Objektinstanz freizugeben und dann `inherited Destroy` aufzurufen, damit die Elternklasse ihren Teil freigibt. L' +
        #$00F6 + 'st der Destruktor eine Ausnahme aus, die kein umgebender Handler f' + #$00E4 +
        'ngt, wird die gesamte Aufr' + #$00E4 +
        'umkette abgewickelt: inherited Destroy wird nie aufgerufen, die Ressourcen der Elternklasse lecken, der Destruktor-Frame bleibt halb erledigt zur' +
        #$00FC +
        'ck, und der Aufrufer (typischerweise die RTL beim Stack-Unwinding) sieht eine Ausnahme in einem Kontext, in dem er sie meist verschluckt oder falsch eskaliert. Der Detektor durchl' +
        #$00E4 +
        'uft `nkMethod`-Knoten, deren `TypeRef` mit `destructor` beginnt (und die keine Klassendestruktoren sind, die eine andere Semantik haben), und besucht dann rekursiv den Rumpf mit einem Flag `InHandler`. Jedes `nkRaise`, das angetroffen wird, w' +
        #$00E4 + 'hrend das Flag False ist, wird gemeldet. Entspricht Sonar-50-Regel #23.'
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Boolean-Parameter als interner Verzweigungsschalter';
      ShortDesc: 'Ein Boolean-Parameter, dessen Wert zwischen zwei v' + #$00F6 +
        'llig verschiedenen Codepfaden w' + #$00E4 +
        'hlt, ist eine verdeckte Strategie - besser zwei Methoden mit sprechenden Namen';
      FullDesc : 'Wenn der Wert eines Boolean-Parameters die Funktion zwischen zwei unabh' + #$00E4 +
        'ngigen Verhaltensweisen umschaltet (`SendMsg(s, True)` vs. `SendMsg(s, False)`), ist die Aufrufstelle undurchsichtig: Der Leser muss entweder die API der Methode im Kopf haben oder nachschlagen, um zu wissen, was `True` bedeutet. Zwei Methoden mit sp' +
        'rechenden Namen (`SendErrorMessage` / `SendInfoMessage`) machen die Absicht an der Aufrufstelle ohne Kommentare deutlich. Der Detektor durchl' +
        #$00E4 +
        'uft `nkMethod`-Knoten, sucht unter den `nkParam`-Kindern nach Boolean (auch LongBool/WordBool/ByteBool) und meldet, wenn mindestens ein `nkIfStmt` im Rumpf den Parameter als Bedingung verwendet. Ausgenommen: Property-Setter (Methodennamen, die mit `S' +
        'et` beginnen), bekannte Parameternamen von VCL-Event-Handlern (`Handled`, `CanShow`). Reines Durchreichen (Bool nur weitergegeben, ohne interne Verzweigung) wird nicht gemeldet. Entspricht Sonar-50-Regel #33. Schweregrad Hinweis - dies ist ein Refact' +
        'oring-Vorschlag, kein Bug.'
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'Private Methode ohne Aufrufer in der Unit';
      ShortDesc: 'Eine private Methode, die von keiner anderen Methode derselben Unit referenziert wird, ist toter Code - l' +
        #$00F6 + 'schen oder anbinden';
      FullDesc : 'Private Methoden k' + #$00F6 +
        'nnen nur innerhalb derselben Unit (klassisches Delphi) oder Klasse (strict private) aufgerufen werden. Referenziert keine andere Methode sie, k' +
        #$00F6 + 'nnen sie ' + #$00FC +
        'berhaupt nicht aufgerufen werden - sie sind toter Code, oft der Rest eines unvollst' +
        #$00E4 + 'ndigen Refactorings. Der Detektor durchl' + #$00E4 +
        'uft `nkClass`-Knoten, findet `nkVisibilitySection`-Kinder mit dem Namen `private` oder `strict private`, sammelt deren `nkMethod`-Namen und durchsucht dann den (um Strings und Kommentare bereinigten) Dateiinhalt textuell nach Treffern an Wortgrenzen.' +
        ' Zwei Treffer je Methode werden toleriert (Deklarationszeile + Implementierungskopf); mehr deuten auf mindestens einen Aufruf hin. Weil diese Suche nur Aufrufe *' +
        #$00FC +
        'ber den Namen* sieht, wird jeder Dispatch-Mechanismus, der eine Methode erreicht, ohne sie zu nennen, vor dem Melden ausgefiltert - Message-Handler, Method-Resolution-Klauseln, Klassenkonstruktoren/-destruktoren, `override`s und Interface-Implementie' +
        'rungen. DFM-Event-Handler werden ' + #$00FC + 'ber die zugeh' + #$00F6 +
        'rige `.dfm` aufgel' + #$00F6 + 'st. Verbleibender blinder Fleck: Aufruf rein ' + #$00FC +
        'ber RTTI (`TypeInfo`, attributgesteuerte Registries) - dort `// noinspection UnusedPrivateMethod` verwenden. Entspricht Sonar-50-Regel #37.'
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'Instanzmethode greift nie auf Self zu - k' + #$00F6 + 'nnte Klassenmethode sein';
      ShortDesc: 'Eine Methode, die nur ihre Parameter nutzt (kein Self, keine Instanzfelder, keine virtuelle Kette), ist funktional eine Klassenmethode - als solche kennzeichnen';
      FullDesc : 'Ber' + #$00FC +
        'hrt eine Instanzmethode nie `Self`, ein Instanzfeld oder `inherited`, ist der implizite Parameter `Self` verschwendet - die Methode ist faktisch zustandslos. Sie als `class function ... static` zu deklarieren, spart die ' +
        #$00DC +
        'bergabe eines Zeigers, macht die zustandslose Absicht explizit und erlaubt Aufrufern, sie ohne Instanz aufzurufen (`TMath.Add(1, 2)` statt `MyMath.Add(1, 2)`). Der Detektor durchl' +
        #$00E4 + 'uft `nkMethod`-Knoten, die zu einer Klasse geh' + #$00F6 +
        'ren (qualifizierter Name wie `TFoo.Bar`), ' + #$00FC +
        'berspringt bereits vorhandene Klassenmethoden (`;class` in TypeRef), polymorphe (`;virtual`/`;override`/`;dynamic`/`;abstract`), Konstruktoren und Destruktoren und pr' +
        #$00FC +
        'ft dann rekursiv auf einen Bezeichner namens `self`, ein `inherited` oder eine Feldreferenz `F<UppercaseLetter>`. Nichts davon -> Fund. Einschr' +
        #$00E4 + 'nkungen: Impliziter Property-Zugriff ohne Pr' + #$00E4 +
        'fix `Self.` wird nicht als Instanzzugriff erkannt, daher k' + #$00F6 +
        'nnen Aufrufe wie `Bar := ...` f' + #$00FC +
        'r eine Property einen Fehlalarm erzeugen. Entspricht Sonar-50-Regel #50.'
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'Methode verdeckt eine virtuelle Basismethode ohne `override`';
      ShortDesc: 'Eine in der Ableitung mit demselben Namen wie eine virtuelle oder dynamische Basismethode neu deklarierte Methode ohne `override` bricht die Polymorphie - der Compiler meldet W1010';
      FullDesc : 'Ohne `override` behandelt der Compiler die Methode der Ableitung als neue Methode. Der polymorphe Dispatch ' +
        #$00FC +
        'ber die vtable der Elternklasse ruft weiterhin deren Implementierung auf - `Base := Derived; Base.DoWork` f' +
        #$00FC +
        'hrt `TBase.DoWork` aus, nicht `TDerived.DoWork`. Der Compiler warnt (W1010), doch viele Codebasen unterdr' +
        #$00FC + 'cken diesen Hinweis. Der Detektor durchl' + #$00E4 +
        'uft `nkClass`-Knoten, ermittelt deren direkte Elternklasse in derselben Unit, sammelt Elternmethoden mit `;virtual` oder `;dynamic` in `TypeRef` und pr' +
        #$00FC +
        'ft dann jede Methode der Ableitung, deren unqualifizierter Name einem polymorphen Elternnamen entspricht: fehlendes `;override` UND fehlendes `;reintroduce` -> Fund. Einschr' +
        #$00E4 +
        'nkungen: nur innerhalb der Unit (Elternklassen aus anderen Units wie `TForm`/`TStrings` werden nicht gesehen); nur die direkte Elternklasse (mehrstufige Ketten pr' +
        #$00FC + 'fen nur eine Stufe). Entspricht Sonar-50-Regel #21.'
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'Boolescher Vergleich ist immer wahr / immer falsch';
      ShortDesc: 'Vergleiche wie `Length(s) >= 0` sind Tautologien - das Ergebnis von Length ist nie negativ, die Bedingung also nie falsch';
      FullDesc : 'Tautologische boolesche Vergleiche deuten meist auf einen Tippfehler (`< 0` statt `= 0`, `>= 1` statt `> 0`) oder auf Copy-Paste-Reste aus einer fr' +
        #$00FC +
        'heren Version des Codes hin. Der Compiler warnt nicht, weil der Operandentyp den Wertebereich syntaktisch zul' +
        #$00E4 +
        'sst. Dieser enge Detektor entfernt Strings + Kommentare und gleicht dann zwei Muster lexikalisch ab: `Length(...) >= 0` / `Length(...) < 0` und das gespiegelte `0 <= Length(...)` / `0 > Length(...)`. Einschr' +
        #$00E4 +
        'nkungen: Cardinal/UInt-Variablen (`<UInt> >= 0` ist ebenfalls immer wahr) lassen sich ohne Typinferenz nicht erkennen; komplexe Ausdr' +
        #$00FC +
        'cke wie `Length(s) - 1 < 0` werden nicht erfasst. Entspricht Sonar-50-Regel #18 (enge Form).'
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'Funktion liefert immer dasselbe Literal';
      ShortDesc: 'Alle Pfade der Funktion weisen Result dasselbe Literal zu - die Verzweigung ' + #$00E4 +
        'ndert nichts am Verhalten, die Funktion durch eine Konstante ersetzen';
      FullDesc : 'Ist jede Zuweisung an `Result` (oder im klassischen Pascal-Stil an den Funktionsnamen) dasselbe Literal, liefert die Funktion dieses Literal unabh' +
        #$00E4 + 'ngig von den Eingaben. Die Bedingungsstruktur ist tot - entweder ein unvollst' +
        #$00E4 +
        'ndiges Refactoring (ein Zweig wurde nie angepasst), oder Zweige, die unterschiedliche Werte h' +
        #$00E4 + 'tten liefern sollen, tun es nicht. Der Detektor durchl' + #$00E4 +
        'uft `nkMethod`, deren `TypeRef` einen R' + #$00FC +
        'ckgabetyp deklariert, sammelt `nkAssign`-Knoten, deren LHS `result` oder dem unqualifizierten Funktionsnamen entspricht, extrahiert das RHS-Literal (Zahl, String-Literal, True/False/nil) und meldet, wenn mindestens zwei solcher Zuweisungen exakt dass' +
        'elbe Literal haben und keine Zuweisung ohne Literal existiert. Entspricht Sonar-50-Regel #43.'
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Benutzersichtbarer Text als Literal zugewiesen';
      ShortDesc: 'Zuweisungen an Caption/Hint/Text und Aufrufe von ShowMessage/MessageDlg mit Literaltext umgehen resourcestring und i18n - der Text ist nicht ' +
        #$00FC + 'bersetzbar';
      FullDesc : 'Hartkodierter benutzersichtbarer Text macht die Anwendung ohne Quelltext' + #$00E4 +
        'nderungen un' + #$00FC +
        'bersetzbar. Der Detektor durchsucht jede Quelltextzeile lexikalisch nach zwei engen Mustern: `<ident>.Caption|Hint|Text := ''<text>''` und `ShowMessage|MessageDlg(''<text>''`. Der erfasste Text wird nur gemeldet, wenn er (a) mindestens 2 Zeichen lang ist' +
        ', (b) mindestens einen Buchstaben enth' + #$00E4 + 'lt (schlie' + #$00DF +
        't einzelne Trennzeichen wie `''-''`, `''.''`, `'':''` und numerische Literale aus) und (c) nicht wie ein Ressourcenschl' +
        #$00FC + 'ssel aussieht (nur Gro' + #$00DF +
        'buchstaben + Unterstriche oder beginnt mit `$`). Zeilenkommentare (`//`) werden ' + #$00FC +
        'bersprungen. Einschr' + #$00E4 +
        'nkungen: Treffer auf Nicht-UI-Klassen mit einer Property Caption/Hint/Text (z. B. interne Helfer) k' +
        #$00F6 + 'nnen Fehlalarme sein - in diesem Fall den Zeilen-Unterdr' + #$00FC +
        'ckungs-Marker `// noinspection HardcodedString` verwenden. Entspricht Sonar-50-Regel #46 (enge Form, nur UI).'
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Lock/Unlock-Paar ohne try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter mit passender Freigabe in derselben Routine, aber ohne try/finally - der Ausnahmepfad l' +
        #$00E4 + 'sst die Sperre stehen und blockiert den n' + #$00E4 + 'chsten Aufrufer';
      FullDesc : 'Durchsucht jede Quelltextzeile lexikalisch (Kommentare + Strings entfernt) nach dem Anforderungs-Token `<ident>.Lock`, `Acquire`, `EnterCriticalSection` oder blankem `EnterCriticalSection(...)`. Ein Vorausschau-Fenster von h' +
        #$00F6 + 'chstens 200 Zeichen - abgeschnitten am Beginn der n' + #$00E4 +
        'chsten Routine - sucht dann nach dem passenden Freigabe-Token (`UnLock`, `LeaveCriticalSection`, `Release`); eine Freigabe, die zu einer benachbarten Methode geh' +
        #$00F6 +
        'rt (Lock/UnLock-Fassade, Begin/End-Paar, Scope-Guard aus Konstruktor/Destruktor), z' +
        #$00E4 + 'hlt nicht mehr. Sind BEIDE im Fenster vorhanden, steht aber kein Schl' + #$00FC +
        'sselwort `try` vor der Freigabe, wird das Paar gemeldet - eine Sperre anzufordern und dann vor der Freigabe eine Ausnahme auszul' +
        #$00F6 + 'sen, verursacht einen Deadlock f' + #$00FC + 'r jeden sp' + #$00E4 +
        'teren Wartenden. Auf mORMot abgestimmt: erfasst TSynLocker, TRWLock, TLightLock und das reine Windows-Paar EnterCriticalSection/LeaveCriticalSection. Muster, bei denen die Freigabe ganz fehlt, werden ' +
        #$00FC +
        'bersprungen (vermutlich ein Lock-Helfer im RAII-Stil mit der Freigabe in einem Destruktor).'
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar mit SizeOf eines Zeigertyps';
      ShortDesc: 'Move, FillChar, CopyMemory oder ZeroMemory mit SizeOf(PXxx), wobei PXxx ein Zeigertyp ist - kopiert nur 4 oder 8 Byte (die Zeigergr' +
        #$00F6 + #$00DF + 'e) statt des gemeinten Puffers';
      FullDesc : 'Lexikalische Suche nach `Move|FillChar|CopyMemory|ZeroMemory(...SizeOf(<Name>)...)`, wobei <Name> mit `P` gefolgt von einem Gro' +
        #$00DF + 'buchstaben beginnt (Delphi-Konvention mit P-Pr' + #$00E4 + 'fix f' + #$00FC +
        'r Zeigertypen: PByte, PInteger, PCardinal, PChar, PSomeRecord, ...). Unter 64 Bit liefert SizeOf(PXxx) unabh' +
        #$00E4 +
        'ngig vom Zieltyp 8; unter 32 Bit liefert es 4. Gemeint war fast immer SizeOf(Xxx) oder Length(Buf) - die verk' +
        #$00FC + 'rzte Kopie l' + #$00E4 + 'sst den Rest des Puffers stillschweigend unber' + #$00FC +
        'hrt (FillChar) oder kopiert die Quelle nur teilweise (Move). H' + #$00E4 +
        'ufige mORMot-Falle: SizeOf(PByte) statt einer expliziten Byte-Anzahl beim Kopieren in ein festes Array. Die Whitelist schlie' +
        #$00DF + 't SizeOf(TXxx) / SizeOf(Integer) / SizeOf(Variable) aus - nur P-Pr' + #$00E4 +
        'fix plus Gro' + #$00DF + 'buchstabe l' + #$00F6 + 'st aus.'
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'with-Anweisung mit mehreren Zielen';
      ShortDesc: '`with A, B do` (zwei oder mehr durch Komma getrennte Empf' + #$00E4 +
        'nger) macht die Member-Aufl' + #$00F6 + 'sung mehrdeutig - eine neue Methode an A oder B ' +
        #$00E4 + 'ndert stillschweigend die Bedeutung des Rumpfs';
      FullDesc : 'Regex-Treffer \bwith\s+<id>,\s*<id>\s*do\b ' + #$00FC +
        'ber die gesamte Datei (mehrzeilig / Kommentare entfernt), gefolgt von einem Klammerbilanz-Durchlauf ' +
        #$00FC +
        'ber den with-Kopf. Ein einzelnes Ziel ist bereits ein Code-Smell (abgedeckt durch fkWithStatement); zwei oder mehr machen den Rumpf zur Wartungsfalle: Eine neue Methode an A oder B kann stillschweigend ' +
        #$00FC + 'berdecken, was bisher an das jeweils andere ging. Der Compiler w' + #$00E4 +
        'hlt den n' + #$00E4 +
        'chstliegenden Treffer und warnt nie. Umbenennungen per IDE-Refactoring ' + #$00FC +
        'bergehen diese Referenzen, weil der Empf' + #$00E4 +
        'nger an der Aufrufstelle nicht genannt ist. Auf mORMot abgestimmt: erfasst bis zu 200 Zeichen je Zielname, um voll qualifizierte Namen wie Owner.SubObject.Component zu tolerieren. Korrektur: in getrennte with-Bl' +
        #$00F6 +
        'cke aufteilen oder - besser - with ganz weglassen und jedes Member explizit qualifizieren. Nicht gemeldet: ein einzelnes Ziel, dessen Kommas in einer Argument-, Index- oder Typargumentliste stehen. Nur ein Komma auf Klammertiefe 0 trennt Ziele; der B' +
        'ilanz-Durchlauf z' + #$00E4 + 'hlt runde und eckige Klammern und ' + #$00FC +
        'berspringt generische Typargumente (TDict<K,V>), und String-Literale werden vorher geleert. L' +
        #$00E4 +
        'sst sich der Kopf nicht entscheiden (kein do auf Tiefe 0 im Fenster, unausgeglichene Klammern), bleibt der Fund - der Filter darf nur entfernen, nie hinzuf' +
        #$00FC + 'gen.'
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem ohne try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem mit passendem FreeMem in derselben Routine, aber ohne umschlie' +
        #$00DF + 'endes try/finally - der Ausnahmepfad verliert den Puffer dauerhaft';
      FullDesc : 'Lexikalische Suche (Kommentare + Strings entfernt) nach `GetMem(...)`, `AllocMem(...)` oder `ReallocMem(...)`. Ein Vorausschau-Fenster von 400 Zeichen sucht nach dem passenden `FreeMem`. Sind beide im Fenster vorhanden, steht aber kein Schl' +
        #$00FC +
        'sselwort `try` vor dem FreeMem, wird das Paar gemeldet - jede Ausnahme zwischen Allokation und Freigabe l' +
        #$00E4 +
        'sst den rohen Heap-Puffer lecken. Auf mORMot abgestimmt: erfasst die ~20 GetMem-Vorkommen in mORMot core/, die hochperformante Pufferbearbeitung implementieren und bei denen jedes fehlende try/finally ein Leck in der Produktion ist. Muster, bei denen' +
        ' FreeMem ganz fehlt, werden ' + #$00FC + 'bersprungen (vermutlich Eigentums' + #$00FC +
        'bergabe an den Aufrufer oder ein eigener Allokator).'
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) in der Schleife';
      ShortDesc: 'Ein dynamisches Array in einer for/while/repeat-Schleife um eins (oder N) zu vergr' +
        #$00F6 + #$00DF + 'ern kostet quadratisch - einmal vor der Schleife vergr' + #$00F6 + #$00DF +
        'ern oder blockweise wachsen';
      FullDesc : 'Lexikalischer Scan nach einem beliebigen `for|while|repeat`-Schl' + #$00FC +
        'sselwort, dem innerhalb von 600 Zeichen `SetLength(<id>, Length(<id>) + ...)` folgt, wobei beide `<id>`-Namen identisch sind (das Array vergr' +
        #$00F6 + #$00DF +
        'ert sich selbst). Jede Neuzuteilung kopiert den vorhandenen Inhalt - n Iterationen kosten n*(n+1)/2 Elementkopien statt n. Bei 10_000 Elementen ist das ~5000x langsamer als ein einmaliges SetLength. H' +
        #$00E4 +
        'ufige mORMot-Performance-Falle, wenn Anwendercode Ergebnisse sammelt, ohne die endg' +
        #$00FC + 'ltige Gr' + #$00F6 + #$00DF + 'e zu kennen. Nur das erste Vergr' + #$00F6 + #$00DF +
        'ern je Schleife wird gemeldet, um Spam zu vermeiden. `SetLength(A, Length(B)+1)` (verschiedene Arrays) wird NICHT gemeldet - dieses Muster ist selten und meist beabsichtigt.'
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- Offset ohne Leerpr' + #$00FC + 'fung';
      ShortDesc: '`PChar(s) + n` und Verwandte ohne vorherige Leerpr' + #$00FC +
        'fung auf `s` - bei einem String k' + #$00FC +
        'rzer als n zeigt der Zeiger hinter den Terminator';
      FullDesc : 'Lexikalischer Scan nach `PChar|PAnsiChar|PWideChar(<id>) [+-] <offset>`. Ein R' + #$00FC +
        'ckw' + #$00E4 +
        'rtsfenster von 200 Zeichen sucht nach Schutzmustern: `<id> <> ''''`, `<id> = ''''`, `Length(<id>) ...` oder `Assigned(<id>)`. Wird kein Schutz gefunden, wird die Arithmetik gemeldet. F' +
        #$00FC +
        'r einen leeren String liefert `PChar(s)` einen Zeiger auf ein statisches #0-Zeichen (nicht nil), daher zeigt `PChar(s) + 5` f' +
        #$00FC + 'nf Zeichen hinter diesen Terminator; dasselbe passiert bei jedem String, der k' +
        #$00FC + 'rzer als der Offset ist. Lesen ' + #$00FC +
        'ber einen solchen Zeiger liefert Datenm' + #$00FC + 'll oder l' + #$00F6 +
        'st eine Access Violation aus. mORMot-Interna sch' + #$00FC +
        'tzen konsequent mit expliziten Leerpr' + #$00FC +
        'fungen; Anwendercode, der das PChar-Arithmetik-Idiom kopiert, l' + #$00E4 +
        'sst den Schutz oft weg. Einschr' + #$00E4 + 'nkungen: Das R' + #$00FC + 'ckw' + #$00E4 +
        'rtsfenster umfasst 200 Zeichen (weiter entfernte Pr' + #$00FC + 'fungen werden ' + #$00FC +
        'bersehen); Arithmetik ' + #$00FC +
        'ber `Inc(p, ...)` auf einer zuvor zugewiesenen PChar-Variablen wird NICHT erkannt (daf' +
        #$00FC + 'r w' + #$00E4 + 're eine Flussanalyse n' + #$00F6 + 'tig).'
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Typisierter Ausnahme-Handler mit leerem Rumpf';
      ShortDesc: '`on E: SomeException do ;` schluckt eine bestimmte Exception-Klasse stillschweigend - schlimmer als ein blankes `except end`, weil die Typangabe absichtsvoll aussieht';
      FullDesc : 'Lexikalischer Scan nach `on [E:] <ExceptionType> do (;|begin end)`. Die typisierte Form `on E:` erweckt den Eindruck einer durchdachten Behandlung - ein Leser nimmt an, dass sich der Entwickler mit genau dieser Ausnahme befasst hat. Ein leerer Rumpf ' +
        'bedeutet, dass der Fehler in Produktion unsichtbar ist: kein Log, keine R' + #$00FC +
        'ckmeldung in der Oberfl' + #$00E4 + 'che, keine Telemetrie. H' + #$00E4 +
        'ufiger Fund in mORMot-Reviews in Aufr' + #$00E4 +
        'umcode, in dem "das kann ignoriert werden" nicht dokumentiert ist. Die blanke Form `except end` erfasst bereits SCA-001 (EmptyExcept); diese Regel deckt die Variante mit typisiertem Handler ab.'
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'String-Typecast aus einem rohen Zeiger';
      ShortDesc: '`string(P)` und Verwandte aus einem P-pr' + #$00E4 +
        'fixierten Zeiger setzen einen Nullterminator voraus, den es nicht geben muss - ' + #$00DC +
        'berlesen des Heaps';
      FullDesc : 'Lexikalischer Scan nach `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)`, wobei `<id>` mit `P` gefolgt von einem weiteren Buchstaben beginnt (Delphi-P-Pr' +
        #$00E4 + 'fix-Konvention f' + #$00FC +
        'r Zeigertypen: PByte, PChar, PSomeRecord, ...). Der Abgleich ignoriert Gro' + #$00DF +
        '-/Kleinschreibung, daher trifft auch `pText`; ein Operand, der in derselben Datei mit einem String-Typ deklariert ist, wird ' +
        #$00FC +
        'bersprungen. Delphi behandelt den Typecast als nullterminiert und liest Speicher bis zum n' +
        #$00E4 + 'chsten #0 - bei einem Puffer ohne Terminator l' + #$00E4 + 'uft das ' + #$00FC +
        'ber die Grenze des Heap-Blocks hinaus und f' + #$00FC + 'hrt zu stillem ' + #$00DC +
        'berlesen und gelegentlicher AV. mORMot-Interna nutzen dieses Muster mit kontrollierter Nullterminierung; Anwendercode, der das Idiom kopiert, l' +
        #$00E4 +
        'sst die Terminator-Garantie oft weg. Stattdessen `SetString(s, PChar(Buf), Len)` mit expliziter L' +
        #$00E4 + 'nge verwenden. Fehlalarm-Filter: Nur Bezeichner, die mit P beginnen, l' + #$00F6 +
        'sen aus - `string(IntegerVar)` (Integer-zu-String) wird nicht gemeldet; ein doppelter Typecast wie `string(PChar(x))` ebenfalls nicht.'
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Zeigersubtraktion ' + #$00FC + 'ber einen 32-Bit-Typecast';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (auch Integer/LongWord/LongInt) schneidet unter Win64 die oberen 32 Bit ab - die Differenz ist zeitweise falsch';
      FullDesc : 'Lexikalischer Scan nach `(Cardinal|LongWord|Integer|LongInt)(<id>) - (Cardinal|...)(<id>)` - zwei 32-Bit-Typecasts, durch Minus verbunden. Unter Win64 ist ein Pointer 64 Bit breit, Cardinal/Integer/LongWord/LongInt dagegen 32 Bit, daher verwirft der ' +
        'Typecast die oberen vier Bytes der Adresse. Die resultierende Differenz ist falsch, sobald der Allokator hohe Adressen vergibt - der Code funktioniert unter Win32 und bricht unter Win64 zeitweise. H' +
        #$00E4 + 'ufiger Portierungsfehler aus Delphi-7-/Delphi-2007-Beispielen, die ' + #$00E4 +
        'lter als Win64 sind. Behebung: `NativeUInt(P1) - NativeUInt(P2)` oder `NativeInt(P1) - NativeInt(P2)` verwenden - Integer-Typen in Zeigerbreite, die der Zeigergr' +
        #$00F6 + #$00DF +
        'e der Plattform entsprechen (`PtrUInt`/`PtrInt` sind die Namen in FPC und mORMot; die Delphi-RTL deklariert sie nicht).'
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Schwacher oder veralteter Kryptoalgorithmus verwendet';
      ShortDesc: 'Algorithmusname (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') oder Wrapper-Klasse (THashMD5, TIdHashSHA1, ...) referenziert - anf' +
        #$00E4 + 'llig f' + #$00FC + 'r Kollisions- und Known-Plaintext-Angriffe';
      FullDesc : 'MD5 hat seit 2004 praktische Kollisionen (Wang et al.), SHA1 seit 2017 (SHAttered, Identical-Prefix; Chosen-Prefix seit 2020). DES hat 56 Bit und ist per Brute Force zu brechen, 3DES hat die Sweet32-CBC-Kollision (CVE-2016-2183). RC4 hat dokumentiert' +
        'e statistische Verzerrungen und ist durch RFC 7465 verboten. TLS 1.0 / 1.1 sind laut RFC 8996 veraltet (BEAST, POODLE, Lucky13). SSLv3 wurde durch POODLE erledigt (CVE-2014-3566). Der Detektor erkennt Algorithmusnamen mit Wortgrenzen in String-Litera' +
        'len/Bezeichnern UND eine Menge bekannter Wrapper-Klassennamen (Teilstring-Abgleich). Behebung: f' +
        #$00FC + 'r Hashing auf SHA-256/SHA-3 umsteigen, f' + #$00FC + 'r symmetrische Verschl' +
        #$00FC + 'sselung auf AES-GCM / AES-CCM, mindestens TLS 1.2 (1.3 bevorzugt).'
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'Shell-API mit String-Verkettung im Argument gerufen';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec mit `+` in den Argumenten - ist ein Operand beeinflussbar, wird daraus ein Command-Injection-Vektor';
      FullDesc : 'Den Befehlsstring per Verkettung aufzubauen (`PChar(''cmd /c '' + UserInput)`) erlaubt dem Angreifer, weitere Befehle anzuh' +
        #$00E4 + 'ngen, wenn die Eingabe nicht streng validiert wird. Dieser Detektor durchl' +
        #$00E4 +
        'uft den AST und meldet jeden nkCall, dessen Methodenname (ohne Qualifizierer) einer der bekannten Shell-Einstiegspunkte ist UND dessen Argumentliste einen `+`-Operator AUSSERHALB jedes String-Literals enth' +
        #$00E4 + 'lt. Da sich statisch nicht feststellen l' + #$00E4 + 'sst, ob ein Operand von au' +
        #$00DF +
        'en beeinflusst ist, wird der Fund mit Konfidenz = Low ausgegeben; er erscheint in der Oberfl' +
        #$00E4 + 'che nur, wenn die Mindest-Konfidenz auf ''low'' steht. Behebung: Argumente ' +
        #$00FC + 'ber das daf' + #$00FC + 'r vorgesehene Parameter-Array ' + #$00FC +
        'bergeben (CreateProcess) oder vor dem Verketten escapen/validieren; ShellExecuteEx mit einer strukturierten SHELLEXECUTEINFO bevorzugen.'
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine auf oberster Ebene wird nie gerufen';
      ShortDesc: 'Eine eigenst' + #$00E4 +
        'ndige Prozedur oder Funktion im implementation-Abschnitt wird nirgends in der Unit gerufen und ist nicht ' +
        #$00FC + 'ber den interface-Abschnitt exportiert - toter Code';
      FullDesc : 'Schlie' + #$00DF + 't die L' + #$00FC +
        'cke zwischen SCA147 (UnusedPrivateMethod - nur private Klassenmethoden) und der Familie der Sichtbarkeitspr' +
        #$00FC +
        'fungen SCA148+ (nur public Klassen-Member). Erkennt Routinen auf oberster Ebene (keine Klassenmethoden), deren Name nirgends in derselben Unit als Aufruf vorkommt, Selbstreferenzen ausgenommen (eine rekursive Routine, die nur sich selbst aufruft, wir' +
        'd trotzdem gemeldet - entspricht dem Verhalten von SonarDelphi UnusedRoutineCheck). Schutz vor Fehlalarmen: Konstruktoren und Destruktoren (nicht direkt als Prozedur aufrufbar), die Direktiven `override`/`virtual; abstract`/`message`/`dynamic` (Dispa' +
        'tch ' + #$00FC +
        'ber Klassengrenzen oder durch das System), die IDE-Bootstrap-Prozedur `Register`, das Enumerator-Trio (`MoveNext`/`GetEnumerator`/`Current` - implizit von `for-in` aufgerufen) sowie jede Routine, die im interface-Abschnitt der Unit vorw' +
        #$00E4 + 'rtsdeklariert ist (m' + #$00F6 +
        'glicher Nutzer in einer anderen Unit). Der Umfang ist eine einzelne Datei - Aufrufer von Routinen des interface-Abschnitts in anderen Units werden in diesem MVP nicht verfolgt, daher werden diese bewusst ' +
        #$00FC + 'bersprungen. Mit `// noinspection UnusedRoutine` unterdr' + #$00FC +
        'cken, wenn die Routine absichtlich erhalten bleibt (Aufruf ' + #$00FC +
        'ber RTTI, von Attributen genutzt, per Plugin geladen). Entspricht SonarDelphi UnusedRoutineCheck.'
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Ungenutzter noinspection-Marker';
      ShortDesc: 'Ein `// noinspection X` unterdr' + #$00FC +
        'ckt an seiner Zielzeile keinen Fund - entweder ist der Detektor besser geworden oder das Ziel war falsch';
      FullDesc : 'Der Unterdr' + #$00FC +
        'ckungsfilter (uSuppression) erfasst jeden Kommentar `// noinspection KindName` und die n' +
        #$00E4 + 'chste Codezeile, auf die er zielt. Nachdem alle Detektoren fertig sind, pr' +
        #$00FC + 'ft der Filter, welche Marker tats' + #$00E4 + 'chlich einen Fund unterdr' + #$00FC +
        'ckt haben. Marker, die nie gegriffen haben, werden als fkUnusedSuppression an der Marker-Zeile gemeldet - der Marker ist zu entfernen (die Weiterentwicklung des Detektors hat ihn ' +
        #$00FC + 'berfl' + #$00FC + 'ssig gemacht) oder es ist zu pr' + #$00FC +
        'fen, ob der Kind-Name des Ziels falsch war. Robust gegen ' + #$00FC +
        'bersehene Funde: Nur Marker mit einer eindeutigen Zielzeile, die kein Kommentar ist, werden ber' +
        #$00FC + 'cksichtigt (Marker am Dateiende oder in reinen Doc-Kommentarbl' + #$00F6 +
        'cken werden ignoriert). Profilabh' + #$00E4 +
        'ngig: Im default-Profil erscheint dieser Hinweis; Meldungen zur Unterdr' + #$00FC +
        'ckungs-Hygiene ohne Detektor-Rauschen liefert ein Lauf mit --profile selftest-quiet.'
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Uninitialisierte lokale Variable';
      ShortDesc: 'Lokale Variable wird vor ihrer ersten Zuweisung in Quelltext-Reihenfolge gelesen oder nie zugewiesen';
      FullDesc : 'Lokale Variablen nicht verwalteter Typen (Integer, Boolean, Pointer, record, Klasseninstanz) beginnen mit undefiniertem Inhalt. Sie vor einer Zuweisung zu lesen liefert Datenm' +
        #$00FC +
        'll oder eine Access Violation - ein klassischer Absturzfehler. Der Detektor durchl' +
        #$00E4 + 'uft die Anweisungen jeder Methode in Quelltext-Reihenfolge und verfolgt f' +
        #$00FC +
        'r jede lokale Variable den ersten Schreib- und den ersten Lesezugriff: Eine Variable, die gelesen, aber nie geschrieben wird, wird mit hoher Konfidenz gemeldet, ein Lesezugriff vor dem ersten Schreibzugriff in Quelltext-Reihenfolge mit mittlerer Konf' +
        'idenz. Die Pr' + #$00FC +
        'fung ist nicht pfadsensitiv - ein Schreibzugriff in einem Zweig z' + #$00E4 + 'hlt f' +
        #$00FC +
        'r jede Zeile darunter, daher wird `if Cond then L := TStringList.Create; L.Add(''x'');` nicht gemeldet. Bekannte Schreiber aus der RTL (Read, ReadLn, FillChar, Move, ZeroMemory, Initialize, New, GetMem) werden ' +
        #$00FC +
        'ber eine Allowlist erkannt; andere Aufrufe mit var-/out-Parametern werden pessimistisch als Lesezugriffe behandelt (' +
        #$00FC +
        'bersehene Funde, aber keine Fehlalarme). Die automatisch initialisierten verwalteten Typen von Pascal (string, dynamisches Array, interface) werden ' +
        #$00FC + 'bersprungen, sofern sie nicht per INI eingeschaltet sind. Methoden ' + #$00FC +
        'ber konfigurierbaren Obergrenzen (standardm' + #$00E4 + #$00DF +
        'ig 200 lokale Variablen / 5000 Anweisungen) werden nicht analysiert, um pathologische Worst-Case-Kosten zu vermeiden.'
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Random-Aufruf ohne vorheriges Randomize';
      ShortDesc: 'Random / RandomRange / RandomFrom ohne Randomize - Seed=0 liefert bei jedem Lauf dieselbe Folge';
      FullDesc : 'Die Delphi-Funktion Random verwendet einen internen Seed, der beim Programmstart 0 ist. Bis Randomize einmal aufgerufen wird (typischerweise zu Beginn der Programmausf' +
        #$00FC +
        'hrung), liefert Random bei jedem Programmstart dieselbe Wertefolge. Der Detektor durchl' +
        #$00E4 + 'uft den AST nach allen Aufrufen und ' + #$00FC +
        'berspringt die gesamte Unit, sobald irgendwo ein Randomize-Aufruf vorkommt. Andernfalls wird jeder Aufruf von Random / RandomRange / RandomFrom gemeldet. Hinweis: Randomize-Aufrufe in anderen Units (z. B. im initialization-Block einer per uses eingeb' +
        'undenen Unit) werden nicht erkannt; gegebenenfalls mit `// noinspection InsecureRandom` unterdr' +
        #$00FC + 'cken. F' + #$00FC +
        'r kryptografische Zwecke (Token-Erzeugung, Salts, Codes zum Zur' + #$00FC +
        'cksetzen von Passw' + #$00F6 + 'rtern) ist Random unabh' + #$00E4 +
        'ngig von Randomize ungeeignet - TBytes aus einem CSPRNG verwenden (z. B. CryptGenRandom unter Windows, /dev/urandom unter POSIX).'
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'case-Anweisung ohne else-Zweig';
      ShortDesc: 'Die case-Anweisung hat keinen else-Zweig - unbehandelte Werte fallen stillschweigend durch; ein else nach einem if im letzten Arm ist das else des case';
      FullDesc : 'Eine case-Anweisung ohne else-Zweig ignoriert stillschweigend alle Werte, die nicht ausdr' +
        #$00FC + 'cklich aufgef' + #$00FC +
        'hrt sind. Nimmt der case-Ausdruck einen dieser unbehandelten Werte an, passiert nichts und es wird kein Fehler ausgel' +
        #$00F6 + 'st, was Logikfehler verdecken kann (besonders, wenn sp' + #$00E4 +
        'ter neue Enum-Werte hinzukommen und die case-Anweisungen nicht angepasst werden). `else ;` f' +
        #$00FC + 'r ein beabsichtigtes Nichtstun erg' + #$00E4 +
        'nzen (das die Entscheidung dokumentiert) oder einen Standard-Handler, der eine Ausnahme ausl' +
        #$00F6 + 'st / protokolliert / per Assert pr' + #$00FC +
        'ft. Hinweis zum Vergleich mit einer ' + #$00E4 + 'lteren Version: Bis 2026-08 h' + #$00E4 +
        'ngte der Parser ein else, das auf ein if im letzten Arm folgte (`3: if C then Foo; else Bar;`), an dieses if statt an das case, sodass die Regel bei case-Anweisungen, die offensichtlich einen else-Zweig hatten, einen fehlenden else-Zweig meldete. Die' +
        'se Fehlalarme sind verschwunden - 148 davon im Referenzkorpus - und daran, was die Regel als Versto' +
        #$00DF + ' z' + #$00E4 + 'hlt, hat sich nichts ge' + #$00E4 + 'ndert.'
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'Assert-Argument enth' + #$00E4 + 'lt einen Aufruf mit Seiteneffekt';
      ShortDesc: 'Assert(SomeCall) - der Aufruf entf' + #$00E4 +
        'llt im Release-Build und sein Seiteneffekt geht stillschweigend verloren';
      FullDesc : 'Der Delphi-Compiler entfernt Assert-Aufrufe in Release-Builds vollst' + #$00E4 +
        'ndig (sofern DCC_Assertions nicht eingeschaltet ist). Enth' + #$00E4 + 'lt der gepr' +
        #$00FC + 'fte Ausdruck einen Funktionsaufruf mit Seiteneffekten (Allokation, Zustands' +
        #$00E4 + 'nderung, I/O, Z' + #$00E4 +
        'hlerinkrement), verschwindet auch der Seiteneffekt - das Verhalten im Release weicht vom Debug ab. Der Detektor meldet Assert-Aufrufe, deren Argument ein Funktionsaufruf-Muster enth' +
        #$00E4 +
        'lt, nach Ausschluss einer Whitelist bekannter reiner RTL-Helfer (Length, Assigned, SizeOf, IntToStr, ...). Den Aufruf aus dem Assert herausziehen und stattdessen das Ergebnis per Assert pr' +
        #$00FC + 'fen.'
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'string-Parameter ohne const';
      ShortDesc: 'string-Parameter ohne const deklariert - erzwingt bei jedem Aufruf eine Erh' + #$00F6 +
        'hung des Referenzz' + #$00E4 + 'hlers';
      FullDesc : 'Delphi erh' + #$00F6 + 'ht bei jedem Aufruf den Referenzz' + #$00E4 +
        'hler des Strings, wenn der Parameter ohne `const` deklariert ist. Mit `const` ' + #$00FC +
        'bergibt der Compiler eine reine Referenz und spart sich das Hoch- und Herunterz' + #$00E4 +
        'hlen des Referenzz' + #$00E4 + 'hlers. Der Compiler verbietet au' + #$00DF +
        'erdem Zuweisungen an einen `const`-Parameter, was den Vertrag, nichts zu ver' + #$00E4 +
        'ndern, explizit macht. F' + #$00FC + 'r String-Parameter, die nicht ver' + #$00E4 +
        'ndert werden (die ' + #$00FC + 'berw' + #$00E4 +
        'ltigende Mehrheit), `const` bevorzugen. Der Detektor meldet Parameter vom Typ `string`/`AnsiString`/`UnicodeString`/`WideString`/`RawByteString`/`ShortString` ohne `const`/`var`/`out`.'
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Compiler-Schalter OFF ohne passendes ON in derselben Datei';
      ShortDesc: '{$WARNINGS OFF} (oder HINTS/RANGECHECKS/...) ohne schlie' + #$00DF +
        'endes ON - wirkt in die folgenden Units hinein';
      FullDesc : 'Delphi-Direktiven f' + #$00FC +
        'r den Compiler-Zustand wie {$WARNINGS OFF}, {$HINTS OFF}, {$RANGECHECKS OFF}, {$BOOLEVAL OFF}, {$OVERFLOWCHECKS OFF} ' +
        #$00E4 + 'ndern den Compiler-Zustand f' + #$00FC +
        'r alles, was danach kompiliert wird. Steht dem OFF kein schlie' + #$00DF +
        'endes ON in derselben Datei gegen' + #$00FC +
        'ber, wirkt der Compiler-Schalter in alle nachfolgenden ' + #$00DC +
        'bersetzungseinheiten desselben Builds hinein und unterdr' + #$00FC +
        'ckt Warnungen/Hinweise/Pr' + #$00FC + 'fungen weit au' + #$00DF +
        'erhalb des beabsichtigten Bereichs. Der Detektor z' + #$00E4 +
        'hlt OFF und ON je Direktivenname in der Datei und meldet jede Direktive, bei der am Dateiende mehr OFF als ON stehen.'
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Boolean-Property ohne Is-/Has-/Can-/Should-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Der Name der Boolean-Property liest sich als Substantiv - besser ein Verb-Pr' + #$00E4 +
        'fix, das sich als Frage liest';
      FullDesc : 'Eine Boolean-Property, die wie ein Substantiv benannt ist, liest sich an der Aufrufstelle mehrdeutig (`if X.Active then` vs. `if X.IsActive then`). Ein verbartiges Pr' +
        #$00E4 +
        'fix (`Is`/`Has`/`Can`/`Should`/`Will`) bevorzugen, durch das sich die Aufrufstelle nat' +
        #$00FC +
        'rlich als Frage liest. Der Detektor meldet Boolean-Properties, deren Name nicht mit einem dieser Pr' +
        #$00E4 +
        'fixe beginnt, mit einer eingebauten Whitelist etablierter VCL-Konventionen (Enabled, Visible, Active, Checked, Modified, ReadOnly, Selected, Focused, Loaded, Modified, Dirty, ...).'
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant in einer leistungskritischen Methode (enth' + #$00E4 + 'lt Schleife)';
      ShortDesc: 'Variant-Variable in einer Methode mit Schleife - jede Variant-Operation zahlt den 10- bis 100-fachen COM-Dispatch-Aufwand';
      FullDesc : 'Variant-Operationen laufen ' + #$00FC +
        'ber den COM-VarType-Dispatcher (VarAdd, VarCmp, VarCast, ...), der bei jedem Lesen, Schreiben, Vergleichen und Umwandeln einen Umweg ' +
        #$00FC + 'ber das Typsystem hinzuf' + #$00FC + 'gt. In einer hei' + #$00DF +
        'en Schleife multipliziert sich dieser Aufwand mit der Zahl der Iterationen und kann die Laufzeit der Methode dominieren. Der Detektor meldet jede lokale Variable und jeden Parameter vom Typ Variant / OleVariant in Methoden, die mindestens eine for/wh' +
        'ile/repeat-Schleife enthalten. Akzeptierte Anwendungsf' + #$00E4 + 'lle (COM/OLE-Br' +
        #$00FC + 'cken, JSON-Variant-Adapter, Excel-Automatisierung) lassen sich ' + #$00FC +
        'ber den Unterdr' + #$00FC + 'ckungs-Marker `// noinspection VariantTypeMisuse` abdecken.'
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> mit T.Create gef' + #$00FC + 'llt - Elemente lecken beim Freigeben';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - die Liste besitzt ihre Elemente nicht, jede TFoo-Instanz leckt';
      FullDesc : 'TList<T> ist ein typisierter Container, der seine Elemente NICHT besitzt - das Freigeben der Liste gibt die enthaltenen Elemente nicht frei. Sind die Elemente mit .Create erzeugte Klasseninstanzen, lecken sie bei jedem Freigeben der Liste, sofern der' +
        ' Aufrufer nicht von Hand iteriert und jedes einzelne freigibt. Der richtige Container ist TObjectList<T> aus Generics.Collections, das standardm' +
        #$00E4 + #$00DF + 'ig OwnsObjects=True hat und seine Elemente beim Zerst' + #$00F6 +
        'ren freigibt. Der Detektor durchl' + #$00E4 +
        'uft jede Methode, sammelt alle Zuweisungen `TList<T>.Create` (wobei T ein Bezeichner ist, der nach einer Klasse aussieht) und sucht dann in derselben Methode nach Mustern `<varname>.Add(<T>.Create)`. Besitz ' +
        #$00FC +
        'ber Methodengrenzen hinweg (Add in einer anderen Methode als Create) wird nicht verfolgt.'
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'Anonyme Methode f' + #$00E4 + 'ngt die Schleifenvariable per Referenz';
      ShortDesc: 'Anonyme Methode in `for i := ... do` referenziert i - alle Closures sehen denselben Endwert';
      FullDesc : 'Delphi f' + #$00E4 +
        'ngt Variablen in anonymen Methoden per Referenz. Wird die anonyme Methode in einer for-Schleife erzeugt und referenziert sie die Schleifenvariable, teilen sich alle Closures dieselbe Referenz - wenn die Closures laufen, hat die Schleifenvariable ihre' +
        'n Endwert erreicht, und alle sehen diesen Endwert. Das klassische Symptom sind N parallele Threads, die in einer Schleife erzeugt werden und alle die letzte Iterationsnummer statt 0..N-1 protokollieren. Der Detektor durchl' +
        #$00E4 +
        'uft for-Anweisungen, ermittelt den Namen der Schleifenvariablen (klassisch `for i :=` oder inline `for var i :=`) und durchsucht nkCall-/nkAssign-Nachfahren nach der Kombination aus einem `procedure`-Schl' +
        #$00FC +
        'sselwort (Beginn einer anonymen Methode) und einer Referenz auf die Schleifenvariable. Behebung: Die Schleifenvariable unmittelbar vor dem Rumpf der anonymen Methode in eine lokale Variable kopieren.'
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'Methode mit hoher kognitiver Komplexit' + #$00E4 + 't (verschachtelter Kontrollfluss)';
      ShortDesc: 'Kognitive Komplexit' + #$00E4 + 't ' + #$00FC +
        'ber 15 (Sonar-Stil) - verschachtelten if/for/while/case ist gedanklich schwer zu folgen';
      FullDesc : 'Die zyklomatische Komplexit' + #$00E4 + 't (SCA022) z' + #$00E4 + 'hlt unabh' + #$00E4 +
        'ngige Pfade linear - zehn flache if-Anweisungen wiegen so viel wie ein dreifach verschachteltes if. Die kognitive Komplexit' +
        #$00E4 + 't, 2017 von Sonar eingef' + #$00FC +
        'hrt, vervielfacht die Kosten von Verschachtelung: Jedes Kontrollfluss-Konstrukt addiert 1 + Verschachtelungstiefe. Drei verschachtelte Schleifen ergeben damit 1+2+3=6 statt 3. Der Detektor durchl' +
        #$00E4 +
        'uft jede Methode mit einem expliziten Stack statt mit Rekursion (sodass tief verschachtelter Code den Aufrufstack nicht zum ' +
        #$00DC +
        'berlaufen bringen kann) und verfolgt die aktuelle Tiefe und die laufende Summe. Boolesche Operatoren (and/or/xor) in if-Bedingungen addieren jeweils +1. Schwelle: 15 (Sonar-Standard), konfigurierbar ' +
        #$00FC + 'ber INI [Detectors] CognitiveLimit.'
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Thread-Variable nach FreeOnTerminate := True verwendet';
      ShortDesc: 'Nach T.FreeOnTerminate := True riskiert jeder weitere T.-Zugriff eine Access Violation, wenn der Thread bereits beendet ist';
      FullDesc : 'TThread.FreeOnTerminate := True ' + #$00FC + 'bertr' + #$00E4 +
        'gt den Besitz der Thread-Instanz an diese selbst - der Thread gibt seinen eigenen Speicher in seinem Lebenszyklus Execute-dann-Destroy frei. Der Aufrufer MUSS alle Referenzen darauf sofort aufgeben (typischerweise, indem er die lokale Variable auf ni' +
        'l setzt), weil es keine Synchronisation zwischen der n' + #$00E4 +
        'chsten Anweisung des Aufrufers und der Selbstzerst' + #$00F6 +
        'rung des Threads gibt. Der Detektor durchl' + #$00E4 +
        'uft jede Methode, sammelt jede Zuweisung `<var>.FreeOnTerminate := True`, dann das erste `<var>.Start` oder `<var>.Resume` - ab diesem Moment l' +
        #$00E4 + 'uft der Thread und kann sich selbst freigeben - und meldet jeden sp' + #$00E4 +
        'teren Zugriff `<var>.<member>` (Aufruf ODER Zuweisung) in derselben Methode, ausgenommen die Lebenszyklus-Aufrufe Start, Resume und Execute. Ohne Start oder Resume in der Methode wird nichts gemeldet. Umfang je Methode: Referenzen ' +
        #$00FC +
        'ber Methodengrenzen hinweg (Thread in einem Feld, Zugriff in einer anderen Methode) werden nicht verfolgt.'
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'Datei-Open-API bekommt verkettete Benutzereingabe';
      ShortDesc: 'Datei-Open-Aufruf (TFileStream.Create, AssignFile, ...) mit einem Pfadausdruck, der Benutzereingaben (Edit.Text, Request.Params, ...) verkettet - Path-Traversal-Risiko';
      FullDesc : 'Klassische Path-Traversal-Schwachstelle: Vom Benutzer kontrollierte Eingabe flie' + #$00DF +
        't in eine Dateisystem-API. Ein Angreifer kann `../../../etc/passwd` oder ' + #$00C4 +
        'hnliches ' + #$00FC +
        'bergeben, um das vorgesehene Verzeichnis zu verlassen und beliebige Dateien zu lesen/zu schreiben. Der Detektor meldet Ausdr' +
        #$00FC +
        'cke, die sowohl ein Token einer Datei-Open-API (TFileStream.Create, TFile.OpenRead/WriteText, AssignFile, FileOpen, FileCreate) ALS AUCH ein Token einer Benutzereingabe-Quelle (.Text, .Lines.Text, .Caption, .Value, Request.Params, Sender.Text, ParamS' +
        'tr) UND einen `+`-Operator (String-Verkettung) enthalten. Der Detektor ist heuristisch - kein Taint-Tracking -, daher l' +
        #$00F6 + 'sen umh' + #$00FC +
        'llende Bereinigungsfunktionen (z. B. `Sanitize(edPath.Text)`) Fehlalarme aus; per Marker unterdr' +
        #$00FC + 'cken, wenn die Bereinigungsfunktion vertrauensw' + #$00FC + 'rdig ist.'
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'DUnitX-Attribut [Ignore] ohne Begr' + #$00FC + 'ndung';
      ShortDesc: '[Ignore] ohne Begr' + #$00FC + 'ndungs-String ' + #$00FC +
        'berspringt den Test stillschweigend - Nachricht erg' + #$00E4 +
        'nzen, warum er deaktiviert ist';
      FullDesc : 'DUnitX akzeptiert [Ignore] sowohl als Marker-Attribut als auch als [Ignore(''reason'')]. Die Marker-Form ' +
        #$00FC +
        'berspringt den Test, ohne sichtbar zu machen, WARUM er deaktiviert wurde - der Test veraltet dann ungepflegt und ger' +
        #$00E4 + 't oft in Vergessenheit. Immer einen Begr' + #$00FC + 'ndungs-String erg' + #$00E4 +
        'nzen, der auf ein Ticket / eine externe Abh' + #$00E4 + 'ngigkeit / eine bekannte Einschr' +
        #$00E4 + 'nkung verweist, damit die Deaktivierung eingeordnet werden kann.'
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Dasselbe Attribut zweimal am selben Member';
      ShortDesc: 'Zwei identische [X]-Attribute am selben Member - Copy-Paste-Rest ohne Wirkung';
      FullDesc : 'Das Attributmodell von Delphi akzeptiert wiederholte Attribute (manche, wie [TestCase], werden absichtlich mehrfach mit unterschiedlichen Argumenten angewendet). Duplikate mit IDENTISCHEN Argumenten sind es nicht ' +
        #$2014 +
        ' sie sind meist Copy-Paste-Reste aus einem Refactoring. Der Detektor vergleicht Paare (Attributname, Argumenttext) und meldet identische Vorkommen in derselben Attributgruppe (Zeilen max. 2 auseinander). Mehrfach angewendete Attribute mit unterschied' +
        'lichen Argumenten (verschiedene [TestCase(''A'',''1'')] / [TestCase(''B'',''2'')]) werden korrekt NICHT gemeldet.'
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'DUnitX-Attribut [Category] ohne Kategorienamen';
      ShortDesc: '[Category] ohne Argument ist in DUnitX ein Compile-Fehler - immer einen Kategorienamen ' +
        #$00FC + 'bergeben';
      FullDesc : 'Das DUnitX-Attribut [Category] verlangt ein String-Argument, mit dem Tests f' + #$00FC +
        'r die selektive Ausf' + #$00FC +
        'hrung gruppiert werden. Ohne das Argument meldet der Compiler einen Fehler wegen eines fehlenden Parameters. Immer einen expliziten Kategorienamen ' +
        #$00FC + 'bergeben (z. B. ''Slow'', ''CI-only'', ''Integration'').'
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : '[TestFixture]-Klasse ohne [Test]-Methode';
      ShortDesc: 'Klasse ist [TestFixture], enth' + #$00E4 +
        'lt aber keine [Test]-Methoden - Zombie-Fixture: sichtbar in TestInsight, wird aber nie ausgef' +
        #$00FC + 'hrt';
      FullDesc : 'DUnitX findet Testklassen, indem es nach [TestFixture]-Attributen sucht. Ein Fixture ohne [Test]-Methode erscheint im Testbaum, tr' +
        #$00E4 + 'gt aber null ausf' + #$00FC +
        'hrbare Tests bei - typischerweise ein Rest aus einem Refactoring (Tests gel' + #$00F6 +
        'scht, Fixture nicht). Der Detektor durchl' + #$00E4 +
        'uft den Dateitext mit einem einfachen Zustandsautomaten: Er betritt das Fixture-Fenster an der [TestFixture]-Zeile, achtet darin auf [Test] und verl' +
        #$00E4 + 'sst es beim n' + #$00E4 +
        'chsten `end;` auf oberster Ebene. Wurde kein [Test] gesehen, wird die [TestFixture]-Zeile gemeldet. Fixtures nur mit [SetupFixture] (zum Vorbereiten gemeinsamen Zustands f' +
        #$00FC +
        'r andere Fixtures) sind ein bekannter Fehlalarm-Fall - mit `// noinspection AttributeTestFixtureWithoutTests` unterdr' +
        #$00FC + 'cken.'
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut mit Leerzeile vor dem Ziel-Member';
      ShortDesc: 'Attributzeile gefolgt von einer Leerzeile - optisch losgel' + #$00F6 +
        'st, oft ein Refactoring-Rest';
      FullDesc : 'Der Delphi-Compiler h' + #$00E4 + 'ngt ein Attribut an das syntaktisch n' + #$00E4 +
        'chste Member, unabh' + #$00E4 +
        'ngig von dazwischenliegenden Leerzeilen. Optisch aber ist ein Attribut, das durch eine Leerzeile von seinem Member getrennt ist, leicht zu ' +
        #$00FC + 'bersehen - der Leser bemerkt wom' + #$00F6 + 'glich nicht, dass das Attribut f' +
        #$00FC + 'r das Member darunter gilt. Das ist auch ein h' + #$00E4 +
        'ufiges Symptom eines Refactorings, bei dem ein Member verschoben/gel' + #$00F6 +
        'scht, das Attribut aber zur' + #$00FC +
        'ckgelassen wurde. Der Detektor meldet Attributzeilen, deren n' + #$00E4 +
        'chste nicht leere Zeile mehr als eine Zeile entfernt ist.'
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Ungenutzte DFM-Komponente';
      ShortDesc: 'DFM-Komponente wird weder im Code noch in anderen Units noch im DFM referenziert - vermutlich ein Refactoring-Rest';
      FullDesc : 'Eine in der .dfm deklarierte Komponente hat keine Ereignisbindung, wird von keiner Property einer anderen Komponente referenziert (DataSource, Action, ActiveControl, ...), wird im eigenen Pascal-Code des Formulars nie verwendet und wird aus keiner an' +
        'deren Unit ' + #$00FC + 'ber die globale Formularvariable angesprochen. H' + #$00F6 +
        'chstwahrscheinlich ist sie ein Rest nach einem Refactoring, der zur Laufzeit trotzdem Speicher belegt. Da der Nutzungsnachweis namensbasiert ist (keine exakte Bindung), wird diese Regel mit niedriger Konfidenz ausgegeben und bleibt aus dem Profil mit' +
        ' Standard-Konfidenz heraus, bis sie an realem Code validiert ist. Persistente Feld-Komponenten (T*Field) sowie eingebettete Frames / geerbte Komponenten werden vorsichtshalber ' +
        #$00FC + 'bersprungen; ohne einen Repo-weiten, Unit-' + #$00FC +
        'bergreifenden Index bleibt der Detektor stumm.'
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'UTF-8-Quelldatei ohne BOM';
      ShortDesc: 'UTF-8-Datei ohne BOM mit Nicht-ASCII - der Compiler liest sie als ANSI (Mojibake)';
      FullDesc : 'Eine Quelldatei, die als UTF-8 ohne Byte-Order-Mark gespeichert ist und Nicht-ASCII-Zeichen enth' +
        #$00E4 +
        'lt, liest der Delphi-Compiler als ANSI (System-Codepage, GetACP) - das erzeugt zur Laufzeit Mojibake in String-Literalen, und das Ergebnis h' +
        #$00E4 +
        'ngt vom Rechner ab. Behebung: als UTF-8 mit BOM speichern oder das Projekt mit --codepage:65001 kompilieren. Nicht-ASCII in einem String-Literal oder Bezeichner wird mit mittlerer Konfidenz gemeldet (standardm' +
        #$00E4 + #$00DF +
        'ig sichtbar); eine Datei, deren Nicht-ASCII-Zeichen nur in Kommentaren stehen, wird mit niedriger Konfidenz gemeldet, weil der Compiler Kommentare verwirft. FPC/Lazarus-Dialekt: Diese Regel wird ' +
        #$00FC + 'bersprungen, wenn der Scan mit --dialect=fpc l' + #$00E4 +
        'uft - UTF-8 ohne BOM ist bei Lazarus die NORM (die Lazarus-IDE selbst speichert ohne BOM, und FPC liest standardm' +
        #$00E4 + #$00DF +
        'ig UTF-8), daher ist ein fehlendes BOM dort kein Mangel. Die Schwesterregeln (ung' + #$00FC +
        'ltiges UTF-8, ANSI-Quellen) bleiben aktiv.'
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'Ung' + #$00FC + 'ltige UTF-8-Folge in der Quelldatei';
      ShortDesc: 'Fehlerhaftes UTF-8 (' + #$00FC + 'berlang, Surrogat oder au' + #$00DF +
        'erhalb des Bereichs) unter einem UTF-8-BOM';
      FullDesc : 'Die Datei tr' + #$00E4 + 'gt ein UTF-8-BOM, enth' + #$00E4 +
        'lt aber Bytefolgen, die kein g' + #$00FC + 'ltiges UTF-8 nach RFC 3629 sind (' + #$00FC +
        'berlange Kodierungen, einzelne Surrogate oder Codepoints oberhalb von U+10FFFF). Der Delphi-Compiler ersetzt sie stillschweigend durch U+FFFD und verf' +
        #$00E4 + 'lscht so die betroffenen Zeichen. Die Datei als sauberes UTF-8 neu kodieren.'
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'NUL- oder Steuerbyte in der Quelldatei';
      ShortDesc: 'NUL oder unzul' + #$00E4 + 'ssiges Steuerbyte - Bin' + #$00E4 +
        'rdatei oder falsch erkannte Kodierung';
      FullDesc : 'Die Quelldatei enth' + #$00E4 + 'lt ein NUL-Byte oder ein unzul' + #$00E4 +
        'ssiges Steuerzeichen (unterhalb von U+0020, ausgenommen Tabulator / Zeilenvorschub / Wagenr' +
        #$00FC + 'cklauf / Seitenvorschub). Das bedeutet meist, dass die Datei bin' + #$00E4 +
        'r ist oder ihre Kodierung falsch erkannt wurde (zum Beispiel UTF-16 ohne BOM, bei dem jedes zweite Byte 0x00 ist). Die Datei pr' +
        #$00FC + 'fen und neu kodieren.'
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Bidirektionales Steuerzeichen (Trojan Source)';
      ShortDesc: 'Bidi-Override- oder Isolate-Steuerzeichen - der Quelltext liest sich anders, als er kompiliert';
      FullDesc : 'Die Datei enth' + #$00E4 + 'lt ein Unicode-Steuerzeichen f' + #$00FC + 'r bidirektionale ' +
        #$00DC +
        'berschreibung oder Isolierung (U+202A-202E, U+2066-2069, U+061C). Damit kann Quelltext einem menschlichen Reviewer anders angezeigt werden, als er kompiliert wird - der Trojan-Source-Angriff (CVE-2021-42574, CWE-1007). In Delphi-Quelltext gibt es daf' +
        #$00FC + 'r keine legitime Verwendung; das Steuerzeichen entfernen.'
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'ANSI-Quelldatei mit Nicht-ASCII-Inhalt';
      ShortDesc: '8-Bit-Quelltext (kein BOM, kein g' + #$00FC + 'ltiges UTF-8) - codepage-abh' + #$00E4 +
        'ngig und nicht portabel';
      FullDesc : 'Die Datei hat kein BOM, enth' + #$00E4 + 'lt Nicht-ASCII-Bytes und ist kein g' + #$00FC +
        'ltiges UTF-8 - sie ist also tats' + #$00E4 +
        'chlich 8-Bit-kodiert (ANSI). Der Delphi-Compiler liest sie in der System-Codepage (GetACP), wodurch die Nicht-ASCII-Zeichen von Rechner/Gebietsschema abh' +
        #$00E4 + 'ngen und nicht portabel sind. Die Datei als UTF-8 mit BOM speichern.'
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'UTF-16-Quelldatei';
      ShortDesc: 'UTF-16-Quelltext - kompiliert, aber ungew' + #$00F6 + 'hnlich und werkzeug-unfreundlich';
      FullDesc : 'Die Quelldatei ist UTF-16 (LE oder BE). Sie kompiliert, aber UTF-16-Quelltext ist ungew' +
        #$00F6 + 'hnlich und sorgt f' + #$00FC +
        'r Reibung mit Textwerkzeugen (git diff, grep, externe Hooks, Code-Review). Konvention ist UTF-8 mit BOM. Unter dem FPC-Dialekt (--dialect=fpc oder ein Lazarus-Projekt) wird der Fund stattdessen als FEHLER mit hoher Konfidenz gemeldet: Free Pascal leh' +
        'nt UTF-16-Quelltext ab, die Datei kompiliert ' + #$00FC + 'berhaupt nicht.'
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'UTF-32-/UCS-4-Quelldatei';
      ShortDesc: 'UTF-32-Quelltext - der Delphi-Compiler weist ihn mit dem fatalen Fehler F2438 zur' + #$00FC +
        'ck';
      FullDesc : 'Die Quelldatei ist UTF-32 / UCS-4 (erkannt an ihrem Byte-Order-Mark). Der Delphi-Compiler unterst' +
        #$00FC +
        'tzt diese Kodierung nicht und bricht mit dem fatalen Fehler F2438 ab ("UCS-4 text encoding not supported. Convert to UCS-2 or UTF-8"). Die Datei in UTF-8 (mit BOM) oder UTF-16 umwandeln.'
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Unsichtbares Zeichen ohne Breite im Quelltext';
      ShortDesc: 'Unsichtbares Unicode-Zeichen ohne Breite - Vektor f' + #$00FC +
        'r versteckten Text und Homoglyphen-Missbrauch';
      FullDesc : 'Die Datei enth' + #$00E4 +
        'lt ein unsichtbares Unicode-Zeichen oder eines ohne Breite (U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 Word Joiner oder ein U+FEFF ZWNBSP mitten in der Datei). Solche Zeichen sind in Quelltext fast nie legitim und k' +
        #$00F6 + 'nnen Bezeichner und Text verbergen oder ver' + #$00E4 +
        'ndern - Teil der Familie Trojan Source / unsichtbare Zeichen (CWE-1007). Hinweis: U+200D kann in String-Literalen mit Emoji legitim vorkommen.'
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Nicht-ASCII-Zeichen im Bezeichner';
      ShortDesc: 'Der Bezeichner enth' + #$00E4 +
        'lt einen Nicht-ASCII-Buchstaben - Risiko durch Homoglyphen und verwechselbare Zeichen';
      FullDesc : 'Ein Bezeichner (Variable, Typ, Routine, ...) enth' + #$00E4 +
        'lt ein Nicht-ASCII-Zeichen. Das ist der Homoglyphen- bzw. Confusable-Identifier-Vektor der Trojan-Source-Familie (CVE-2021-42694, CWE-1007): Ein Buchstabe wie das kyrillische U+043E sieht aus wie das lateinische ''o'', ist aber ein anderer Bezeichner, ' +
        'sodass zwei Bezeichner identisch aussehen und dennoch unterschiedlich gebunden werden k' +
        #$00F6 + 'nnen. Ein legitimer Unicode-Bezeichner ist ebenfalls m' + #$00F6 +
        'glich, daher vor einer ' + #$00C4 + 'nderung pr' + #$00FC +
        'fen; ASCII-Bezeichner bevorzugen, wegen der Portabilit' + #$00E4 +
        't und um Verwechslungen zu vermeiden.'
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Quelldatei geh' + #$00F6 + 'rt nicht zum Projekt';
      ShortDesc: 'Eine .pas-/.dfm-Datei liegt im Projektordner, ist aber nicht im Projekt (.dproj/.groupproj) referenziert - vermutlich verwaist';
      FullDesc : 'L' + #$00E4 +
        'uft nur bei Projekt- und Projektgruppen-Scans (--project / --project-group oder Auswahl einer .dproj/.groupproj ' +
        #$00FC +
        'ber den ''...''-Dialog), bei denen die genaue Dateiliste des Projekts (DCCReferences) bekannt ist. Der Detektor durchsucht das Verzeichnis der Projektdatei rekursiv nach .pas- und .dfm-Dateien und meldet jede, die das Projekt nicht referenziert. Eine .' +
        'dfm gilt als enthalten, wenn ihre zugeh' + #$00F6 +
        'rige .pas referenziert ist. Dateien, die per uses eingebunden SIND, werden stattdessen als SCA195 gemeldet (sie sind nicht tot). Typische Treffer: nach einem Refactoring zur' +
        #$00FC +
        'ckgebliebene Units, experimentelle Kopien oder Dateien, die aus dem Projekt, aber nicht von der Platte entfernt wurden. Einschr' +
        #$00E4 + 'nkung v1: Nur Dateien INNERHALB des Projektordner-Baums werden gepr' + #$00FC +
        'ft - Units, die von au' + #$00DF + 'erhalb ' + #$00FC +
        'ber relative DCCReferences mit ''..'' referenziert werden, und Units aus dem Suchpfad werden weder durchsucht noch gemeldet. Rekursive Verzeichnis-Scans und Einzeldatei-Scans f' +
        #$00FC + 'hren diese Pr' + #$00FC + 'fung nicht aus (kein Konzept der Projektzugeh' + #$00F6 +
        'rigkeit). Behebung: die Datei entfernen oder aus dem Projektordner verschieben (wird sie tats' +
        #$00E4 + 'chlich verwendet, verlangt SCA195 stattdessen, sie hinzuzuf' + #$00FC + 'gen).'
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit wird vom Projekt genutzt, ist aber nicht darin enthalten';
      ShortDesc: 'Eine .pas-Datei wird von Projekt-Units per uses gezogen (kompiliert ' + #$00FC +
        'ber den Suchpfad), steht aber nicht in der Projektdatei (.dproj/.groupproj) - ins Projekt aufnehmen';
      FullDesc : 'L' + #$00E4 +
        'uft nur bei Projekt- und Projektgruppen-Scans (--project / --project-group oder Auswahl einer .dproj/.groupproj ' +
        #$00FC +
        'ber den ''...''-Dialog). Abgespalten von SCA194 (das wirklich verwaiste Dateien meldet): Eine Datei, die per uses eingebunden WIRD - direkt oder transitiv ' +
        #$00FC + 'ber andere solche Units -, ist kein toter Code. Sie kompiliert ' + #$00FC +
        'ber den Suchpfad, bleibt aber f' + #$00FC +
        'r die Projektverwaltung unsichtbar: keine Projektnavigation in der IDE, leicht zu ' +
        #$00FC +
        'bersehen bei Reviews, Deployments und Versionsfixierung, und ein Umbenennen/Verschieben bricht den Build erst beim n' +
        #$00E4 + 'chsten vollst' + #$00E4 +
        'ndigen Kompilieren. Die Behebung besteht darin, die Datei ins Projekt aufzunehmen. Kommentare und String-Literale z' +
        #$00E4 +
        'hlen nie als uses-Referenz; verglichen wird der Dateiname ohne Erweiterung mit den (eventuell punktierten) Unit-Namen in uses-Klauseln.'
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Result eines verwalteten Typs wird gelesen, bevor es zugewiesen wurde';
      ShortDesc: 'Result eines verwalteten R' + #$00FC +
        'ckgabetyps wird vor der ersten Zuweisung gelesen - es ist ein Alias der Zielvariablen des Aufrufers und tr' +
        #$00E4 + 'gt deren ALTEN Wert. Zuerst initialisieren (nil / [] / '''')';
      FullDesc : 'Bei verwalteten R' + #$00FC + 'ckgabetypen ' + #$00FC +
        'bergibt der Compiler Result als versteckten var-Parameter, der ein Alias der Zielvariablen des Aufrufers ist, EINSCHLIESSLICH ihres bisherigen Inhalts (System.Rtti UseResultPointer; die RTL sch' +
        #$00FC +
        'tzt sich selbst dagegen, z. B. beginnt TStringBuilder.ToString mit Result := '''' ''to prevent copying of existing data''). Result wird beim Eintritt daher NICHT mit ''''/nil/leer initialisiert. Es vor der ersten Zuweisung zu lesen - Result := Result + [x]' +
        ', Result[i] := ... ohne vorheriges SetLength, Result.Add(...), Exit(Result + ...) - verarbeitet veraltete Daten des Aufrufers: Das klassische Symptom ist eine Sammelfunktion, deren zweiter Aufruf an die Ergebnisse des ersten anh' +
        #$00E4 + 'ngt. Der Compiler-Hinweis W1035 (R' + #$00FC +
        'ckgabewert undefiniert) bleibt genau bei diesen Typen STUMM, daher warnt hier sonst nichts. Die Erkennung erfolgt rein nach Quelltext-Reihenfolge (Variante 2, keine Pfadanalyse): Der erste Zugriff auf Result im Rumpf entscheidet; alles, was Result sc' +
        'hreibt oder schreiben kann (direkte Zuweisung, Exit(value), Result oder @Result als Aufrufargument wie SetLength(Result, n) oder TryGetValue(key, Result)), z' +
        #$00E4 +
        'hlt als Zuweisung und beendet die Suche. Funktionen mit einem Alias ''absolute Result'', Assembler-Routinen und Deklarationen ohne Rumpf werden ' +
        #$00FC + 'bersprungen; String-Literale, die das Wort ''result'' enthalten, z' + #$00E4 +
        'hlen nie. Bewusst pfadblind: Ein Schreibzugriff in einem Zweig, gefolgt von einem Lesezugriff nach dem Zweig, wird NICHT gemeldet (' +
        #$00FC +
        'bersehener Fund, kein Fehlalarm) - eine pfadsensitive Analyse ist als Folgeschritt geplant. Der Funktionsname als Result-Alias z' +
        #$00E4 + 'hlt NUR als Zuweisungsziel: Im Ausdruckskontext ist ein blo' + #$00DF +
        'er Funktionsname immer ein (rekursiver/parameterloser) AUFRUF - ''Result := Put;'' ruft den parameterlosen Overload auf und liest Result nie; ''Obj.Result'' ist ein fremdes Feld. IFDEF-Zwillingszuweisungen, eingebettete anonyme Methoden (deren Result zur' +
        ' anonymen Funktion geh' + #$00F6 + 'rt) und Puffer-F' + #$00FC +
        'll-Idiome wie ''Result[0] := Char(Api(@Result[1], N))'' werden als Schreib-, nicht als Lesezugriffe behandelt. Bei ShortString-Ergebnissen ist ''Result[0] := #len'' das Idiom zur Initialisierung des L' +
        #$00E4 + 'ngenbytes und z' + #$00E4 + 'hlt als erster Schreibzugriff. Wo diese Regel anschl' +
        #$00E4 + 'gt, bleibt SCA121 f' + #$00FC + 'r dieselbe Funktion stumm.'
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface ohne GUID deklariert';
      ShortDesc: 'Interface hat keine GUID - Supports() und QueryInterface() k' + #$00F6 +
        'nnen zur Laufzeit nicht danach fragen. Mit Strg+Umschalt+G eine erzeugen';
      FullDesc : 'Ein Interface ohne GUID existiert nur zur Compile-Zeit. Sowohl Supports(Obj, IFoo, X) als auch Obj.QueryInterface(IFoo, X) l' +
        #$00F6 + 'sen das Interface ' + #$00FC +
        'ber seine GUID auf, daher kompiliert keiner der beiden Aufrufe gegen ein Interface ohne GUID - und der Fehler zeigt sich an der Aufrufstelle, oft in einer anderen Unit und lange nachdem das Interface geschrieben wurde. Delphi erzeugt mit Strg+Umschal' +
        't+G eine neue GUID, w' + #$00E4 +
        'hrend der Cursor in der Interface-Deklaration steht. Die Erkennung ist lexikalisch: Auf die Deklaration `IFoo = interface` (optional mit Vorfahrenliste) folgt die optionale GUID in eckigen Klammern. Vorw' +
        #$00E4 + 'rtsdeklarationen (`IFoo = interface;`) werden ' + #$00FC +
        'bersprungen, weil sie ' + #$00FC + 'berhaupt keine GUID tragen d' + #$00FC +
        'rfen, und dispinterface-Typen liegen au' + #$00DF + 'erhalb dieser Regel.'
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Zwei Interfaces teilen sich dieselbe GUID';
      ShortDesc: 'Dieselbe GUID steht an mehr als einem Interface - Supports() liefert das zuerst registrierte, ohne Compilerfehler. Mit Strg+Umschalt+G eine neue erzeugen';
      FullDesc : 'Interface-GUIDs identifizieren das Interface zur Laufzeit und m' + #$00FC +
        'ssen im gesamten Programm eindeutig sein. Ein neues Interface durch Kopieren des vorigen zu deklarieren und dabei das Neuerzeugen der GUID zu vergessen, ergibt Code, der sauber kompiliert und sich stillschweigend falsch verh' +
        #$00E4 + 'lt: Supports(Obj, ISecond, X) gelingt und liefert das ERSTE Interface zur' +
        #$00FC +
        'ck, sodass Aufrufe auf den falschen Methoden landen oder ein Typecast zu funktionieren scheint, wo er es nicht sollte. Nichts in der Toolchain warnt davor. Die Pr' +
        #$00FC +
        'fung braucht den gesamten Scan, nicht eine Datei: Der Index wird aus derselben Dateiliste aufgebaut, die analysiert wird, daher folgt der Umfang der Auswahl - Verzeichnis, Projekt (.dproj) oder Projektgruppe (.groupproj). Die Meldung nennt die andere' +
        'n Deklarationen mit Datei und Zeile, weil das Finden des Zwillings die eigentliche Arbeit ist. Im Einzeldatei-Modus beschr' +
        #$00E4 +
        'nkt sich der Vergleich auf diese Datei - "eindeutig" ist keine Aussage, die eine einzelne Datei st' +
        #$00FC + 'tzen kann.'
    ),
    // SCA199
    (
      RuleID   : 'SCA199';
      Name     : 'ParamByName-Name passt nicht zu den SQL-Platzhaltern';
      ShortDesc: 'ParamByName(''x'') an einer Query, deren SQL kein :x hat (zur Laufzeit ''Parameter nicht gefunden''), oder ein :y im SQL, das die Routine nie zuweist, obwohl sie die anderen Parameter der Query setzt';
      FullDesc : 'Der Compiler sieht die Verbindung zwischen Query.SQL und Query.ParamByName nicht - beides sind Strings. Ein umbenannter Platzhalter, ein Tippfehler oder ein kopierter Block hinterl' +
        #$00E4 +
        'sst ein ParamByName, dessen Name nicht im SQL steht, und der Fehler zeigt sich erst, wenn die Anweisung ausgef' +
        #$00FC +
        'hrt wird: FireDAC, BDE, dbExpress, UniDAC, Zeos und ADO (Parameters.ParamByName) l' +
        #$00F6 + 'sen alle ''parameter not found'' aus. Die Gegenrichtung wird f' + #$00FC +
        'r Queries gemeldet, die die Routine selbst erzeugt: Das SQL hat :y, die Routine bindet andere Parameter dieser Query, aber nie y - die Ausf' +
        #$00FC +
        'hrung scheitert dann an einem ungebundenen Parameter (FireDAC: unbekannter Datentyp, Oracle: ORA-01008) oder bindet stillschweigend NULL. Die Pr' +
        #$00FC +
        'fung arbeitet je Routine und je Query-Variable, liest ab dem ersten ''begin'' der Routine und nur dann, wenn sie das SQL der Query vollst' +
        #$00E4 +
        'ndig aus Literalen in dieser Routine kennt: Die Query wird dort erzeugt (Q := TXxx.Create) oder ihr SQL wird vor dem ersten Add geleert oder zugewiesen, und jeder Beitrag ist ein String-Literal (sLineBreak und #13#10 eingeschlossen). Platzhalter sind' +
        ' :name au' + #$00DF +
        'erhalb von SQL-Strings und -Kommentaren - auch :@name (ADO, SQL Server), Namen mit $ oder # (Oracle) und :"Namen in Anf' +
        #$00FC +
        'hrungszeichen" -, und ein Name gilt als vorhanden, wenn er entweder zur Bezeichner-Lesart passt oder zur Lesart von Data.DB/ADODB ParseSQL, die bis zum n' +
        #$00E4 + 'chsten Leerzeichen, Komma, Semikolon oder zur schlie' + #$00DF +
        'enden Klammer reicht; f' + #$00FC + 'r die Richtung unbekannter Name z' + #$00E4 +
        'hlt auch ein Platzhalter in einem SQL-Kommentar als vorhanden, weil Data.DB, ADO und IBX ihn trotzdem anlegen. ''::''-Typecasts, '':='' (PL/SQL), positionales '':1'', '':new.''/'':old.'' in Trigger-R' +
        #$00FC + 'mpfen und ''?''-Parameter sind keine Namen. Namen werden ohne Beachtung der Gro' +
        #$00DF + '-/Kleinschreibung verglichen, wie es alle Bibliotheken tun. Als Binden z' + #$00E4 +
        'hlen die Zugriffe: ParamByName, Params.ParamByName, Parameters.ParamByName, FindParam, ParamValues[''a;b''] und f' +
        #$00FC +
        'r Direct Oracle Access SetVariable, DeclareVariable, SetComplexVariable, SetLongVariable.'
    ),
    // SCA200
    (
      RuleID   : 'SCA200';
      Name     : 'IP-Adresse als String-Literal';
      ShortDesc: 'Hartkodierte IPv4- oder IPv6-Adresse (privat, geteilt oder ' + #$00F6 +
        'ffentlich) in einem String-Literal - in die Konfiguration auslagern oder einen Hostnamen verwenden';
      FullDesc : 'Eine in den Quelltext geschriebene IP-Adresse bindet das Programm an ein Netz: Jeder Umzug auf einen anderen Server, in eine andere Umgebung (Entwicklung, Test, Produktion) oder zu einem anderen Kunden erfordert eine Code' +
        #$00E4 + 'nderung und einen neuen Build, und die Adresse verr' + #$00E4 +
        't jedem, der das Binary liest, die interne Topologie. Die Adresse aus der Konfiguration, der Kommandozeile oder der Umgebung lesen oder einen Hostnamen verwenden, den DNS je Umgebung aufl' +
        #$00F6 +
        'st. Die Regel liest nur String-Literale - nie Kommentare - und erkennt IPv4 in strikter Dotted-Decimal-Form (vier Oktette 0-255, keine f' +
        #$00FC + 'hrenden Nullen) und IPv6 in jeder Form nach RFC 4291, einschlie' + #$00DF +
        'lich Zone (%eth0), eckiger Klammern mit Port ([...]:443) und eingebetteter IPv4 (::ffff:10.1.2.3). Gemeldet werden private Adressen (RFC 1918, Unique Local fc00::/7), geteilte Adressen (100.64.0.0/10) und ' +
        #$00F6 +
        'ffentliche Adressen. Nicht gemeldet werden Loopback, unspezifizierte Adressen (0.0.0.0, ::), Broadcast, Netzmasken, Link-Local, die Dokumentationsbereiche (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32, 3fff::/20), IETF-Protokollbl' +
        #$00F6 +
        'cke, Benchmarking (198.18.0.0/15), Multicast und reservierte Bereiche. Test-Units (Benennung und Verzeichnisse test/spec) werden ' +
        #$00FC +
        'bersprungen. Eine Adresse in einer http://-URL wird auch von SCA115 gemeldet: Die beiden Regeln beschreiben verschiedene Probleme, Klartext-Transport und eine feste Adresse.'
    ),
    // SCA201
    (
      RuleID   : 'SCA201';
      Name     : 'IP-Adresse in einer versionierten Konfigurationsdatei';
      ShortDesc: 'IPv4- oder IPv6-Adresse (privat, geteilt oder ' + #$00F6 +
        'ffentlich) als Wert in einer .ini-Datei des Quellbaums';
      FullDesc : 'Eine Konfigurationsdatei im Quellbaum wird wie Code versioniert und ausgeliefert: Eine IP-Adresse darin bindet jeden Checkout und jede Installation an ein Netz, und der Umzug auf einen anderen Server oder in eine andere Umgebung erfordert wieder eine' +
        'n Commit. Umgebungsspezifische Adressen aus der Versionsverwaltung heraushalten (eine Datei je Rechner oder je Umgebung, die Umgebung, ein Deployment-Schritt) oder einen Hostnamen verwenden. Die Regel liest die .ini-Dateien des gescannten Baums - bei' +
        ' Ordner-Scans ' + #$00FC +
        'ber denselben Verzeichnisdurchlauf wie die Quellen, bei Projekt-Scans unterhalb der gemeinsamen Wurzel der Projekt-Units; nicht analyser.ini und nicht die Kopien in Plattform-Ausgabeordnern wie Win32 oder Win64 unterhalb der gescannten Wurzel. Zeilen' +
        ', die mit '';'' oder ''#'' beginnen, sind Kommentare, Abschnittsk' + #$00F6 +
        'pfe (auch mit nachgestelltem Kommentar) werden ' + #$00FC +
        'bersprungen, und der Wert ist alles nach dem ersten ''=''. Adressgrammatik, Klassen und Ausschl' +
        #$00FC + 'sse sind die von SCA200; zus' + #$00E4 + 'tzlich werden Schl' + #$00FC +
        'ssel, die Flie' + #$00DF +
        'text tragen (description, help, hint, comment, caption, text, example, note, title, summary), und Versionsschl' +
        #$00FC +
        'ssel nicht gemeldet. Eine Zeile wird mit einem ganzzeiligen Marker ''; noinspection HardcodedIpInConfig'' (oder ''#'') direkt dar' +
        #$00FC + 'ber unterdr' + #$00FC +
        'ckt, die ganze Datei mit ''; noinspection-file HardcodedIpInConfig''.'
    ),
    // SCA202
    (
      RuleID   : 'SCA202';
      Name     : 'not, and, or oder xor bindet vor dem Vergleich';
      ShortDesc: '''not Count > 0'' oder ''A = True or B = False'' - not/and/or/xor binden st' + #$00E4 +
        'rker als Vergleiche, der Ausdruck kompiliert, pr' + #$00FC + 'ft aber etwas anderes';
      FullDesc : 'In Pascal binden die Operatoren not, and, or und xor st' + #$00E4 +
        'rker als die Vergleiche (=, <>, <, >, <=, >=, in) - in Delphi wie in Free Pascal. Zwei Schreibweisen kompilieren daher ohne Meldung und pr' +
        #$00FC +
        'fen etwas anderes, als sie sich lesen. (1) ''not'' vor einem Vergleich: ''if not List.Count > 0'' ist ''(not List.Count) > 0''. Bei einem Integer ist not das bitweise Komplement, daher ist die Bedingung f' +
        #$00FC +
        'r jedes Count >= 0 falsch; ''not Key in [...]'' und ''not Result = mrOk'' scheitern auf dieselbe Weise. (2) Mit and/or/xor verkettete Vergleiche: ''if A = True or B = False'' ist ''(A = (True or B)) = False''. Das kompiliert nur, wenn die Operanden Boolean (' +
        'oder Variant) sind - bei Integern, Strings, Aufz' + #$00E4 +
        'hlungen oder Mengen meldet der Compiler bereits einen Typfehler. Den Vergleich in Klammern schreiben: ''not (List.Count > 0)'', ''(A = True) or (B = False)'' - oder den Vergleich mit True/False weglassen. Der Schweregrad ist Fehler, wenn der Typ belegt i' +
        'st (eine Zahl oder eine Menge von Zahlen rechts, Pos/Ord/Length/CompareText... oder .Count/.IndexOf als Operand, eine lokale Variable, ein Parameter oder ein Feld eines Integer-Typs, True/False in der Kette), andernfalls Warnung. Gelesen werden Bedin' +
        'gungen von if/while/until/case und rechte Seiten von :=; Kommentare, String-Literale (auch mehrzeilige Strings von Delphi 12) und asm-Bl' +
        #$00F6 + 'cke z' + #$00E4 + 'hlen nie als Code.'
    ),
    // SCA203
    (
      RuleID   : 'SCA203';
      Name     : 'for-Schleife l' + #$00E4 + 'uft einen Index ' + #$00FC + 'ber das Ende';
      ShortDesc: 'for-Schleife l' + #$00E4 +
        'uft bis Count, Length() oder High() + 1 und indiziert dieselbe Sammlung mit der Schleifenvariablen - der letzte Durchlauf liegt au' +
        #$00DF + 'erhalb';
      FullDesc : 'Ein klassischer Off-by-one-Fehler: ''for i := 0 to List.Count do'' mit List[i] im Rumpf liest List[List.Count], ein Element hinter dem Ende. Der Compiler akzeptiert das; zur Laufzeit l' +
        #$00F6 +
        'st es mit {$R+} ERangeError aus, bei TList und TStrings EArgumentOutOfRangeException oder EStringListError, und andernfalls liest oder schreibt es stillschweigend den Speicher hinter dem letzten Element. Gemeldet werden Schleifenk' +
        #$00F6 +
        'pfe, deren Obergrenze einen Index zu weit reicht - ''X.Count'' (ab 0, oder ab 1, wenn X eine nachgewiesene Liste ist), ''Length(A)'' ab 0, ''Low(A) to Length(A)'' bei einem dynamischen Array, ''High(A) + 1'' -, wenn der Rumpf dieselbe Sammlung (gleicher Name' +
        ' oder gleiche Kette) mit der unverschobenen Schleifenvariablen liest oder schreibt: X[i], X[i, j] und bei .Count auch X.Items[i], X.Strings[i] und X.Objects[i]. Strings sind 1-basiert und haben eigene Formen: ''0 to Length(S)'' mit S[i] ist an beiden E' +
        'nden falsch (S[0] vor dem ersten Zeichen), ''1 to Length(S) + 1'' hinter dem letzten; ''1 to Length(S)'' ist korrekt. Der Fund ist nur dann ein Fehler, wenn der Typ nachgewiesen ist: Die Sammlung ist ein in der Unit deklarierter Name (Parameter, lokale o' +
        'der Inline-Variable, Result, Feld der eigenen Klasse der Methode oder ihrer Vorfahren in der Unit, Unit-Variable), dessen Typ eine bekannte Liste (TList, TObjectList, TStrings, TStringList, TCollection, TMenuItem, FPC TFPList/TFPGList ...), ein Array' +
        ' oder ein String ist, und der Rumpf verl' + #$00E4 +
        'sst den Durchlauf weder vor dem Zugriff (break, exit, continue, raise, goto), noch vergr' +
        #$00F6 + #$00DF + 'ert er die Sammlung, noch enth' + #$00E4 +
        'lt er eine anonyme Methode. Andernfalls ist er eine Warnung. Behebung: Count - 1, High(A) (oder Length(A) - 1) und bei Strings 1 to Length(S).'
    ),
    // SCA204
    (
      RuleID   : 'SCA204';
      Name     : 'Ergebnis ' + #$00FC + 'ber den Funktionsnamen zugewiesen';
      ShortDesc: 'Funktionsergebnis durch Zuweisung an den Funktionsnamen gesetzt (''GetCount := ...'') - die alte Pascal-Form; Delphi schreibt Result';
      FullDesc : 'Innerhalb einer Funktion setzt ''GetCount := FItems.Count;'' das Ergebnis - die Form, die Pascal hatte, bevor es Result gab. Das funktioniert, aber derselbe Name bedeutet in einem Rumpf zwei verschiedene Dinge: links von '':='' ist er die Ergebnisvariabl' +
        'e, ' + #$00FC +
        'berall sonst ein rekursiver Aufruf der Funktion (siehe SCA205). ''Result :='' sagt, was gemeint ist, und kann nicht mit einem Aufruf verwechselt werden. Gemeldet wird eine Zuweisung an den blo' +
        #$00DF +
        'en Funktionsnamen am Anfang einer Anweisung (auch hinter einem case-Label) im eigenen Rumpf der Funktion. Nur dort, wo es Result gibt: in Delphi (nicht unter {$X-}) und in Free Pascal in den Modi delphi, delphiunicode und objfpc oder mit {$modeswitch' +
        ' result}; eine Datei ohne {$mode} gilt in einem Delphi-Scan als Delphi und unter --dialect=fpc als unbekannt. Stilregel (Hinweis): Profile strict und style, nicht default. reDelphix bietet die Ersetzung durch ''Result :='' an.'
    ),
    // SCA205
    (
      RuleID   : 'SCA205';
      Name     : 'Funktionsname im eigenen Rumpf gelesen ist ein rekursiver Aufruf';
      ShortDesc: '''Total := Total + X'' in der Funktion Total: rechts ist der Name ein rekursiver Aufruf, nicht das bisherige Ergebnis';
      FullDesc : 'In Delphi ist der Name einer Funktion in ihrem eigenen Rumpf nur links von '':='' die Ergebnisvariable. ' +
        #$00DC +
        'berall sonst - in einem Ausdruck, einer Bedingung, Exit(Name) - ruft er die Funktion erneut auf. ''Total := Total + X;'' addiert X daher nicht zum bisher aufgebauten Ergebnis: Es rekursiert, meist bis der Stack ' +
        #$00FC + 'berl' + #$00E4 +
        'uft. Die Modi objfpc und fpc von Free Pascal lesen dort stattdessen das Ergebnis, weshalb portierter Code dieses Muster zeigt. Gemeldet wird der blo' +
        #$00DF +
        'e Name (ohne Klammern, nicht hinter einem Punkt, nicht nach inherited oder @) in einem Ausdruck einer Funktion, die auch ihrem eigenen Namen zuweist - der Autor verwendet den Namen als Variable. Es ist ein Fehler, wenn die Funktion keine Parameter ha' +
        't und der Rumpf keine gewollte Rekursion zeigt (kein Name(), keine Aufrufanweisung ''Name;'', kein Self.Name, kein Name<T>) und der Name kein blo' +
        #$00DF +
        'es Aufrufargument ist; andernfalls eine Warnung (nur Default-Parameter, gewollte Rekursion daneben, blo' +
        #$00DF +
        'es Argument). Nur im Delphi-Modus: Delphi oder Free Pascal mit {$mode delphi} / {$mode delphiunicode}. Behebung: Result (oder Name(), wenn die Rekursion gewollt ist).'
    ),
    // SCA206
    (
      RuleID   : 'SCA206';
      Name     : 'Formatter-Marker zum Aus- und Einschalten falsch geschrieben oder ohne Partner';
      ShortDesc: 'Formatter-Marker `{(*}` / `{*)}` falsch geschrieben oder ohne Partner - GExperts, CnWizards und JCF formatieren den Bereich dann doch oder den Rest der Datei gar nicht mehr';
      FullDesc : 'Die Kommentare `{(*}` und `{*)}` schalten den Code-Formatter f' + #$00FC +
        'r den Bereich dazwischen aus und danach wieder ein. Sie stammen aus DelForExp und wirken im Formatter von GExperts, im Formatter von CnWizards und in JEDI Code Format (auch in Lazarus); der Formatter der Delphi-IDE (Strg+D, bis Delphi 12) kennt sie n' +
        'icht, und Delphi 13 liefert keinen Formatter mehr aus. Die Formatter erkennen nur genau diese vier Zeichen - `{ (*}` oder `{*) }` ist f' +
        #$00FC + 'r sie ein gew' + #$00F6 +
        'hnlicher Kommentar -, und die Bereiche schachteln nicht: ein Schalter, kein Z' + #$00E4 +
        'hler. Gemeldet werden: ein Marker mit Leerzeichen oder Tabs darin (er wird ignoriert, der Bereich wird formatiert); ein ' +
        #$00F6 + 'ffnendes `{(*}` ohne schlie' + #$00DF +
        'endes (danach wird nichts mehr formatiert); ein schlie' + #$00DF +
        'endes `{*)}` ohne offenen Bereich (es schlie' + #$00DF +
        't nichts); und ein zweites `{(*}` in einem offenen Bereich (das erste `{*)}` beendet ihn schon). Ein absichtlich bis zum Dateiende offener Bereich wird ebenfalls gemeldet - mit `// noinspection FormatterMarker` in der Zeile ' +
        #$00FC + 'ber dem `{(*}` unterdr' + #$00FC + 'cken. Der Compiler sieht beide Marker als gew' +
        #$00F6 + 'hnliche `{ }`-Kommentare, nichts davon ' + #$00E4 +
        'ndert das kompilierte Programm. Die Bilanz z' + #$00E4 +
        'hlt je Datei; `{$IFDEF}`-Zweige werden gelesen, wie sie dastehen, ohne sie auszuwerten.'
    )
  );

  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_FR : array[0..205] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objet cr' + #$00E9 + #$00E9 + ' sans lib' + #$00E9 + 'ration s' + #$00FB +
        're face aux exceptions';
      ShortDesc: 'Objet cr' + #$00E9 + #$00E9 + ' mais pas lib' + #$00E9 + 'r' + #$00E9 + ' de mani' + #$00E8 +
        're fiable (fuite m' + #$00E9 + 'moire possible)';
      FullDesc : 'Signale quatre variantes. (1) never-freed : l''objet n''est jamais lib' + #$00E9 + 'r' +
        #$00E9 +
        ' - avertissement. (2) freed-outside-finally : un Free existe mais se trouve hors du try/finally protecteur, si bien que toute exception ' +
        #$00E0 + ' l''int' + #$00E9 +
        'rieur du bloc provoque une fuite - avertissement. (3) return-value-not-freed : une fonction renvoie un objet fra' +
        #$00EE + 'chement cr' + #$00E9 + #$00E9 + ' et l''appelant ne le lib' + #$00E8 +
        're jamais - note. (4) proven-leak : jamais lib' + #$00E9 + 'r' + #$00E9 +
        ' ET il est prouv' + #$00E9 + ' que la variable ne sort jamais de la m' + #$00E9 +
        'thode (aucun argument d''appel, aucune cible d''affectation, aucun argument de constructeur suspect' +
        #$00E9 + ' d''' + #$00EA + 'tre un propri' + #$00E9 +
        'taire, aucun type interface) - la seule variante signal' + #$00E9 +
        'e comme erreur. La variante ' + #$00E0 + ' laquelle appartient un r' + #$00E9 +
        'sultat est indiqu' + #$00E9 +
        'e dans properties.variant de la sortie SARIF et dans l''astuce de correction affich' +
        #$00E9 + 'e par l''interface ; le texte du message lui-m' + #$00EA +
        'me ne contient que le nom de la variable.'
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Bloc except vide';
      ShortDesc: 'Un bloc except vide avale silencieusement toutes les exceptions';
      FullDesc : 'Un bloc except sans instruction intercepte toutes les exceptions, y compris les inattendues (EAccessViolation, EOutOfMemory). Les bugs deviennent invisibles. Au minimum, journaliser l''exception ou la relancer.'
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'Cha' + #$00EE + 'ne SQL construite par concat' + #$00E9 + 'nation';
      ShortDesc: 'Cha' + #$00EE + 'ne SQL concat' + #$00E9 + 'n' + #$00E9 + 'e avec ''+'' et un op' + #$00E9 +
        'rande non litt' + #$00E9 + 'ral (risque d''injection si cet op' + #$00E9 +
        'rande n''est pas fiable)';
      FullDesc : 'Construire du SQL via ''WHERE x='' + op' + #$00E9 +
        'rande permet une injection SQL lorsque cet op' + #$00E9 + 'rande n''est pas fiable. Le d' +
        #$00E9 + 'tecteur signale la CONCAT' + #$00C9 +
        'NATION - il ne suit pas l''origine de l''op' + #$00E9 + 'rande, un r' + #$00E9 +
        'sultat est donc une piste de revue, pas la preuve d''une vuln' + #$00E9 + 'rabilit' +
        #$00E9 + '. Les concat' + #$00E9 + 'nations de litt' + #$00E9 +
        'raux uniquement, les masques de format entiers et les fonctions d''assainissement connues sont d' +
        #$00E9 + 'j' + #$00E0 + ' exclus. Utiliser plut' + #$00F4 + 't des requ' + #$00EA +
        'tes param' + #$00E9 + 'tr' + #$00E9 + 'es (Params.ParamByName(...).Value := ...).'
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Identifiant / jeton d''API en dur';
      ShortDesc: 'Mot de passe, cl' + #$00E9 + ' d''API ou jeton sous forme de litt' + #$00E9 + 'ral de cha' +
        #$00EE + 'ne dans le code source';
      FullDesc : 'Les identifiants pr' + #$00E9 + 'sents dans le code source finissent dans le contr' +
        #$00F4 + 'le de version, les artefacts de build, les d' + #$00E9 +
        'compilateurs et les traces de pile. D' + #$00E9 +
        'placer les secrets vers des variables d''environnement, le magasin d''identifiants du syst' +
        #$00E8 + 'me d''exploitation ou une configuration chiffr' + #$00E9 + 'e.'
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format() : nombre de marqueurs incoh' + #$00E9 + 'rent';
      ShortDesc: 'Le nombre de marqueurs de Format() / FormatUtf8() ne correspond pas au nombre d''arguments';
      FullDesc : 'Des marqueurs incoh' + #$00E9 + 'rents provoquent une EConvertError ' + #$00E0 + ' l''ex' +
        #$00E9 + 'cution. Le d' + #$00E9 + 'tecteur g' + #$00E8 +
        're le Format de la RTL (%s/%d/...) et le style % nu de mORMot (FormatUtf8/FormatString).'
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Le fichier n''a pas pu ' + #$00EA + 'tre lu ou analys' + #$00E9;
      ShortDesc: 'Erreur d''analyse ou d''E/S - fichier source illisible ou syntaxiquement cass' + #$00E9;
      FullDesc : 'R' + #$00E9 + 'sultat particulier (pas un d' + #$00E9 +
        'faut de code) : le fichier n''a pas pu ' + #$00EA + 'tre charg' + #$00E9 +
        ' ou l''analyseur lexical/syntaxique a ' + #$00E9 + 'chou' + #$00E9 +
        '. Indique souvent des probl' + #$00E8 + 'mes d''encodage, des includes qui ne se r' +
        #$00E9 + 'solvent pas ou de v' + #$00E9 + 'ritables erreurs de syntaxe.'
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Unit' + #$00E9 + ' inutilis' + #$00E9 + 'e dans la clause uses';
      ShortDesc: 'Entr' + #$00E9 + 'e uses probablement inutilis' + #$00E9 +
        'e (aucun identificateur qui en provienne n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' +
        #$00E9 + ')';
      FullDesc : 'Heuristique : recherche n''importe quel identificateur de l''unit' + #$00E9 + ' utilis' +
        #$00E9 + 'e. Faux positifs possibles pour les unit' + #$00E9 +
        's qui se contentent d''enregistrer des classes / d''initialiser un ' + #$00E9 +
        'tat global via des sections initialization.'
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'D' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 + 'rencement nil possible';
      ShortDesc: 'Acc' + #$00E8 + 's ' + #$00E0 + ' une variable qui peut valoir nil ' + #$00E0 +
        ' cet endroit';
      FullDesc : 'Une variable locale est explicitement mise ' + #$00E0 + ' nil puis d' + #$00E9 + 'r' +
        #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + 'e (appel de m' + #$00E9 + 'thode ou acc' + #$00E8 +
        's ' + #$00E0 + ' une propri' + #$00E9 + 't' + #$00E9 + ') sans r' + #$00E9 +
        'affectation ni test de nil entre les deux. Provoque un plantage avec EAccessViolation ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution. Le d' + #$00E9 +
        'tecteur ne suit que les affectations explicites `obj := nil` ; une valeur renvoy' + #$00E9 +
        'e par une fonction qui peut renvoyer nil (p. ex. une m' + #$00E9 +
        'thode Find...) n''est pas suivie. Gardes reconnues : une r' + #$00E9 +
        'affectation, `Assigned(obj)` ou `obj <> nil` dans une condition if, un `if obj = nil then Exit` anticip' +
        #$00E9 +
        ', le passage de `obj` comme argument (affectation var/out possible) et les appels s' +
        #$00FB + 'rs vis-' + #$00E0 + '-vis de nil comme `obj.Free`.'
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objet cr' + #$00E9 + #$00E9 + ' sans try/finally protecteur';
      ShortDesc: 'Appel .Create sans try/finally englobant - risque de fuite en cas d''exception';
      FullDesc : 'Semblable ' + #$00E0 + ' MemoryLeak (SCA001) mais v' + #$00E9 + 'rifi' + #$00E9 +
        ' structurellement : une variable locale d''une classe suivie par le d' + #$00E9 +
        'tecteur de fuites (la liste [Detectors] LeakyClasses, p. ex. TStringList) est cr' + #$00E9 +
        #$00E9 + 'e avec .Create et lib' + #$00E9 + 'r' + #$00E9 +
        'e avec .Free ou FreeAndNil dans la m' + #$00EA + 'me m' + #$00E9 +
        'thode, mais aucun try/finally ne prot' + #$00E8 + 'ge le code interm' + #$00E9 +
        'diaire - une exception ' + #$00E0 +
        ' cet endroit saute le Free et l''objet fuit. Sans aucun Free, le d' + #$00E9 +
        'tecteur reste muet (ce cas rel' + #$00E8 + 've de SCA001). Ne sont pas signal' + #$00E9 +
        's non plus : un objet renvoy' + #$00E9 + ' comme r' + #$00E9 + 'sultat ou confi' + #$00E9 +
        ' ' + #$00E0 + ' un propri' + #$00E9 +
        'taire, et un intervalle entre Create et Free qui n''appelle que des membres de l''objet lui-m' +
        #$00EA + 'me (p. ex. List.Add sur une TStringList).'
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'Division par z' + #$00E9 + 'ro possible';
      ShortDesc: 'Division enti' + #$00E8 + 're (div / mod) par une variable pouvant valoir z' + #$00E9 +
        'ro';
      FullDesc : 'Le membre droit d''un div ou mod entier est un param' + #$00E8 +
        'tre ou une variable locale sans garde pr' + #$00E9 + 'alable contre z' + #$00E9 + 'ro ; ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution, cela l' + #$00E8 +
        've EDivByZero. Gardes reconnues : une condition if comme `Count <> 0`, `Count > 0` ou `Count >= 1` avant la division, `if Count = 0 then Exit` (ou raise), une variable de boucle for qui commence ' +
        #$00E0 + ' 1 ou plus, et un diviseur auquel ne sont jamais affect' + #$00E9 +
        'es que des valeurs non nulles. Un litt' + #$00E9 +
        'ral `div 0` / `mod 0` est toujours signal' + #$00E9 + '. L''op' + #$00E9 +
        'rateur flottant / n''est pas v' + #$00E9 + 'rifi' + #$00E9 + ' par cette r' + #$00E8 +
        'gle.'
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Le code apr' + #$00E8 + 's Exit/Raise est inatteignable';
      ShortDesc: 'L''instruction qui suit Exit, raise ou Halt est du code mort';
      FullDesc : 'Tout ce qui suit un terminateur inconditionnel (Exit, raise, Halt, Continue, Break) dans le m' +
        #$00EA + 'me bloc n''est jamais ex' + #$00E9 + 'cut' + #$00E9 + '. Il s''agit g' + #$00E9 +
        'n' + #$00E9 + 'ralement d''un reste de refactoring. Non signal' + #$00E9 +
        ' lorsque le terminateur lui-m' + #$00EA +
        'me se trouve dans une plage de compilation conditionnelle et que l''instruction suivante n''y est pas (`{$IFDEF DEBUG} raise ...; {$ENDIF}` suivi de `Exit;`) : sans le define, le terminateur n''existe pas et l''instruction suivante est le chemin actif. C' +
        'ette garde D' + #$00C9 + 'PEND DU DEFINE - pour un build qui pose toujours le define, le r' +
        #$00E9 + 'sultat masqu' + #$00E9 +
        ' serait factuellement correct. L''analyseur ne peut pas trancher sans les defines du projet et tranche en faveur de ' +
        #$00AB + ' atteignable ' + #$00BB + '.'
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'La m' + #$00E9 + 'thode d' + #$00E9 + 'passe le seuil de lignes';
      ShortDesc: 'Corps de m' + #$00E9 + 'thode plus long que le maximum configur' + #$00E9 + ' (par d' +
        #$00E9 + 'faut : plus de 50 lignes et plus de 30 instructions)';
      FullDesc : 'Les m' + #$00E9 + 'thodes longues sont corr' + #$00E9 + 'l' + #$00E9 + 'es ' + #$00E0 +
        ' une forte densit' + #$00E9 + ' de d' + #$00E9 +
        'fauts (Robert C. Martin, McConnell) : le lecteur garde le contexte en m' + #$00E9 +
        'moire de travail et, d' + #$00E8 + 's que la m' + #$00E9 + 'thode d' + #$00E9 + 'passe un ' +
        #$00E9 + 'cran, ce contexte d' + #$00E9 + 'borde. Les m' + #$00E9 + 'thodes longues r' +
        #$00E9 + 'sistent aussi aux tests unitaires - la pr' + #$00E9 +
        'paration des tests finit par dupliquer l''' + #$00E9 +
        'tat interne. Refactoring : extraire les blocs coh' + #$00E9 + 'rents dans des m' + #$00E9 +
        'thodes auxiliaires priv' + #$00E9 + 'es (ParseInput/Validate/Persist) ou d' + #$00E9 +
        'couper par responsabilit' + #$00E9 + ' (r' + #$00E9 + 'cup' + #$00E9 + 'ration des donn' +
        #$00E9 + 'es vs. transformation vs. ' + #$00E9 + 'mission). Une m' + #$00E9 +
        'thode n''est signal' + #$00E9 + 'e que lorsque les DEUX limites sont d' + #$00E9 + 'pass' +
        #$00E9 + 'es - par d' + #$00E9 +
        'faut plus de 50 lignes de corps et plus de 30 instructions, configurables via [Detectors] LongMethodMaxBodyLines et LongMethodMaxStatements - si bien qu''un code long mais plat, comme une initialisation de table, reste muet. Les lignes sont compt' +
        #$00E9 + 'es sur le corps de la m' + #$00E9 + 'thode ' + #$00E0 +
        ' partir de son `begin`, commentaires et lignes vides compris. La d' + #$00E9 +
        'tection des instructions compos' + #$00E9 + 'es ignore les m' + #$00E9 +
        'thodes anonymes imbriqu' + #$00E9 + 'es, de sorte qu''un corps de m' + #$00E9 +
        'thode qui ne contient qu''une closure n''est pas signal' + #$00E9 + ' ' + #$00E0 + ' tort.'
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Trop de param' + #$00E8 + 'tres';
      ShortDesc: 'La m' + #$00E9 + 'thode a plus de param' + #$00E8 + 'tres que le maximum configur' + #$00E9 +
        ' (5 par d' + #$00E9 + 'faut)';
      FullDesc : 'Un nombre ' + #$00E9 + 'lev' + #$00E9 + ' de param' + #$00E8 + 'tres est un indicateur pr' +
        #$00E9 + 'coce de violation du SRP : la routine jongle avec des responsabilit' + #$00E9 +
        's qui devraient ' + #$00EA + 'tre s' + #$00E9 + 'par' + #$00E9 +
        'es. Les longues listes entra' + #$00EE + 'nent aussi une confusion de position (le troisi' +
        #$00E8 + 'me Integer, c''est lequel d' + #$00E9 + 'j' + #$00E0 +
        ' ?) et obligent les appelants ' + #$00E0 + ' renseigner des valeurs par d' + #$00E9 +
        'faut qui ne s''appliquent pas forc' + #$00E9 + 'ment. Refactoring : regrouper les param' +
        #$00E8 + 'tres coh' + #$00E9 +
        'rents dans un record (TOrderInput), faire passer la configuration par un pattern builder (FluentQuery.Where(...).OrderBy(...)) ou d' +
        #$00E9 + 'couper la m' + #$00E9 +
        'thode par axe (SaveOrder + SaveOrderItems). Seuil via [Detectors] LongParamListMaxParams (5 par d' +
        #$00E9 + 'faut). Les param' + #$00E8 + 'tres out/var comptent comme les param' + #$00E8 +
        'tres par valeur ; le Self implicite des m' + #$00E9 + 'thodes de classe ne compte pas.'
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Litt' + #$00E9 + 'ral num' + #$00E9 + 'rique sans constante nomm' + #$00E9 + 'e';
      ShortDesc: 'Litt' + #$00E9 + 'ral num' + #$00E9 +
        'rique dans une expression - extraire vers une constante nomm' + #$00E9 + 'e';
      FullDesc : 'Les litt' + #$00E9 + 'raux num' + #$00E9 + 'riques int' + #$00E9 + 'gr' + #$00E9 +
        's directement dans la logique m' + #$00E9 +
        'tier ne portent aucun sens : `if RetryCount > 3` oblige chaque lecteur ' + #$00E0 +
        ' deviner ce que repr' + #$00E9 + 'sente 3 et chaque modification de maintenance ' + #$00E0 +
        ' retrouver chaque occurrence ' + #$00E0 + ' la main. Extraire une constante nomm' + #$00E9 +
        'e pour que la valeur ait un objectif document' + #$00E9 + ' et exactement une source de v' +
        #$00E9 + 'rit' + #$00E9 + '. Le d' + #$00E9 +
        'tecteur ignore les valeurs triviales (0, 1, 2, -1, tailles courantes en puissance de 2, indexation dans des collections connues pour ' +
        #$00EA +
        'tre minuscules) - voir [Detectors] MagicNumberTrivials pour la liste active. Les bornes de boucle par rapport ' +
        #$00E0 + ' `Length(arr)` et l''index de tableau 0 sont ' + #$00E9 + 'galement ignor' +
        #$00E9 +
        's. Utiliser la configuration globale pour ajouter des valeurs triviales propres au projet (p. ex. un PageSize fixe).'
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'Litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne r' + #$00E9 + 'p' + #$00E9 + 't' + #$00E9 +
        ' ' + #$00E0 + ' plusieurs endroits';
      ShortDesc: 'Le m' + #$00EA + 'me litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne appara' + #$00EE +
        't au moins 3 fois dans un fichier - extraire vers une constante';
      FullDesc : 'Les cha' + #$00EE + 'nes r' + #$00E9 + 'p' + #$00E9 + 't' + #$00E9 + 'es cr' + #$00E9 +
        'ent un risque de couplage au changement (une faute de frappe ' + #$00E0 +
        ' un endroit diverge silencieusement des autres). Les extraire dans une const, en particulier pour les messages destin' +
        #$00E9 + 's ' + #$00E0 + ' l''utilisateur. Le d' + #$00E9 + 'tecteur compte les litt' +
        #$00E9 + 'raux de cha' + #$00EE + 'ne d''au moins 4 caract' + #$00E8 +
        'res dans les affectations et les appels d''un fichier et signale un litt' + #$00E9 + 'ral ' +
        #$00E0 + ' partir de sa troisi' + #$00E8 + 'me occurrence ; les litt' + #$00E9 + 'raux situ' +
        #$00E9 + 's ailleurs (par exemple dans les instructions raise) ne sont pas compt' + #$00E9 +
        's, pas plus que ''true'', ''false'' et ''null''.'
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Chemin de fichier en litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne';
      ShortDesc: 'Chemin C:\, UNC ou Linux ' + #$00E9 + 'crit en dur dans le source';
      FullDesc : 'Les chemins ' + #$00E9 + 'crits en dur nuisent ' + #$00E0 + ' la portabilit' + #$00E9 +
        ' et au d' + #$00E9 +
        'ploiement CI. Utiliser des fichiers de configuration, des variables d''environnement ou des helpers de chemin adapt' +
        #$00E9 + 's ' + #$00E0 + ' la plateforme (TPath.Combine, etc.).'
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage en code de production';
      ShortDesc: 'Appel non qualifi' + #$00E9 + ' ' + #$00E0 +
        ' WriteLn, ShowMessage(Pos) ou OutputDebugString dans une unit' + #$00E9 + ' hors test';
      FullDesc : 'WriteLn / ShowMessage / OutputDebugString / OutputDebugStringA dans du code hors test est presque toujours un reste de d' +
        #$00E9 + 'bogage : ShowMessage en particulier bloque le thread d''interface et ne convient ' +
        #$00E0 + ' aucun chemin de code de production. Remplacer par un logger structur' + #$00E9 +
        ' (TLogger, mORMot TSynLog, log4d) afin que le point d''appel capture la s' + #$00E9 + 'v' +
        #$00E9 + 'rit' + #$00E9 + ', la cat' + #$00E9 +
        'gorie et l''emplacement dans le source, et que l''exploitation puisse r' + #$00E9 +
        'gler la verbosit' + #$00E9 + ' ' + #$00E0 + ' l''ex' + #$00E9 + 'cution. Le d' + #$00E9 +
        'tecteur ignore les unit' + #$00E9 + 's situ' + #$00E9 + 'es dans des segments de r' +
        #$00E9 + 'pertoire test/sample/demo (la d' + #$00E9 +
        'finition des chemins de fixtures valable pour tout le projet : `test`, `tests`, `unittest`, `unittests`, `samples`, `demos`, ancr' +
        #$00E9 + 's sous la racine de l''analyse) ainsi que les unit' + #$00E9 +
        's console/test-runner (`*Console*`, `*TestProject*` dans le nom de fichier de l''unit' +
        #$00E9 + ') - la sortie y est voulue, ce n''est pas un reste de d' + #$00E9 + 'bogage. Impl' +
        #$00E9 + 'ment' + #$00E9 + ' le 2026-09-05, apr' + #$00E8 +
        's que l''audit du 2026-09-04 a constat' + #$00E9 + ' que l''exclusion promise ' + #$00E0 +
        ' l''origine n''avait jamais ' + #$00E9 + 't' + #$00E9 +
        ' construite. Un marqueur `// noinspection DebugOutput` masque des lignes individuelles (p. ex. des banni' +
        #$00E8 + 'res CLI interactives).'
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'L''imbrication de blocs d' + #$00E9 + 'passe le seuil';
      ShortDesc: 'Profondeur d''imbrication if/for/while sup' + #$00E9 + 'rieure au maximum configur' +
        #$00E9 + ' (4 par d' + #$00E9 + 'faut) ; une cha' + #$00EE +
        'ne else-if compte pour UN seul niveau, comme un case';
      FullDesc : 'Une imbrication profonde nuit ' + #$00E0 + ' la lisibilit' + #$00E9 +
        ' et indique que la m' + #$00E9 +
        'thode en fait trop. Utiliser des clauses de garde (Exit anticip' + #$00E9 +
        ') ou extraire les blocs internes dans des m' + #$00E9 +
        'thodes auxiliaires. Un bloc est signal' + #$00E9 + ' lorsque sa profondeur d' + #$00E9 +
        'passe la limite - avec la valeur par d' + #$00E9 + 'faut 4, le cinqui' + #$00E8 +
        'me niveau d''imbrication est signal' + #$00E9 + '.'
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'Marqueur TODO/FIXME en commentaire';
      ShortDesc: 'Marqueur TODO, FIXME, HACK ou XXX ouvert - ' + #$00E0 + ' traiter avant la livraison';
      FullDesc : 'Les marqueurs de travail ouverts (TODO, FIXME, HACK, XXX) forment un suivi de t' + #$00E2 +
        'ches parall' + #$00E8 + 'le ' + #$00E0 + ' l''int' + #$00E9 + 'rieur du source. Ce sch' +
        #$00E9 + 'ma ' + #$00E9 + 'choue par accumulation : des marqueurs ajout' + #$00E9 + 's ' +
        #$00E0 + ' des ann' + #$00E9 + 'es d''intervalle ne sont jamais tri' + #$00E9 +
        's ensemble, l''auteur d''origine s''en va, et le lecteur suivant ne peut pas savoir si le TODO est encore pertinent ou s''il a ' +
        #$00E9 + 't' + #$00E9 + ' livr' + #$00E9 +
        ' en silence. SCA fait remonter chacun de ces marqueurs pour que les gates CI puissent imposer une branche de livraison sans TODO ou un tri au moment de la PR. Formes reconnues : commentaires `// TODO` et `{ TODO ... }`, le marqueur en tant que mot en' +
        'tier, avec suffixe d''ID jira facultatif (`// TODO PROJ-123: ...`). TODO, FIXME et HACK sont reconnus sans tenir compte de la casse, XXX uniquement en majuscules (un `xxx` en minuscules est presque toujours un espace r' +
        #$00E9 + 'serv' + #$00E9 + '). Les commentaires `(* ... *)` ne sont pas analys' + #$00E9 +
        's, et l''ensemble des marqueurs est fixe. Un marqueur qui doit rester peut ' + #$00EA +
        'tre masqu' + #$00E9 + ' avec `// noinspection TodoComment`.'
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Corps de m' + #$00E9 + 'thode vide';
      ShortDesc: 'Le corps de la m' + #$00E9 + 'thode ne contient aucune instruction';
      FullDesc : 'Une m' + #$00E9 + 'thode vide peut indiquer une impl' + #$00E9 + 'mentation oubli' + #$00E9 +
        'e, un TODO jamais trait' + #$00E9 +
        ' ou un stub d''interface. Rendre l''intention explicite (assert, exception ou commentaire). Non signal' +
        #$00E9 + ' : un corps vide qui porte d' + #$00E9 + 'j' + #$00E0 +
        ' un commentaire explicatif ({ do nothing }, // default implementation does nothing) - ce commentaire *est* l''une des trois corrections que demande la r' +
        #$00E8 +
        'gle. Ne comptent pas comme intention : les directives de compilation ({$REGION}, {$IFDEF}) et le code comment' +
        #$00E9 + ' (reconnu au point-virgule final). Cela n''affaiblit pas la r' + #$00E8 +
        'gle du projet selon laquelle les commentaires ne comptent jamais comme *utilisation* de code - la question ici est l''intention document' +
        #$00E9 + 'e, pas l''utilisation.'
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Bloc de code dupliqu' + #$00E9;
      ShortDesc: 'Plusieurs blocs de code identiques (' + #$00E0 +
        ' partir du nombre minimal de lignes configur' + #$00E9 + ')';
      FullDesc : 'D' + #$00E9 + 'tecte N+ lignes identiques cons' + #$00E9 +
        'cutives qui apparaissent deux fois ou plus dans le m' + #$00EA +
        'me fichier (minimum par d' + #$00E9 + 'faut : 8 lignes ; les copies situ' + #$00E9 +
        'es dans des fichiers diff' + #$00E9 + 'rents ne sont pas compar' + #$00E9 +
        'es). La violation de DRY cr' + #$00E9 +
        'e un couplage au changement : une correction sur une copie diverge silencieusement des autres, et les relecteurs ne voient pas facilement qu''une correction de comportement n''a trait' +
        #$00E9 + ' qu''un seul des N points d''appel. Refactoring : extraire dans une m' + #$00E9 +
        'thode auxiliaire ou une constante partag' + #$00E9 + 'e. Les lignes sont normalis' + #$00E9 +
        'es (espaces de d' + #$00E9 + 'but et de fin supprim' + #$00E9 +
        's, passage en minuscules, suites d''espaces r' + #$00E9 + 'duites) afin que des diff' +
        #$00E9 + 'rences cosm' + #$00E9 +
        'tiques ne masquent pas un vrai doublon. Les lignes triviales (vides, begin, end, else, try, finally, except, lignes ne contenant qu''un commentaire) ne comptent pas dans un bloc. Seuil via [Detectors] DuplicateBlockMinLines.'
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'La m' + #$00E9 + 'thode d' + #$00E9 + 'passe le seuil de complexit' + #$00E9 + ' de McCabe';
      ShortDesc: 'Complexit' + #$00E9 + ' cyclomatique sup' + #$00E9 + 'rieure au seuil configur' + #$00E9 +
        ' (10 par d' + #$00E9 + 'faut)';
      FullDesc : 'La complexit' + #$00E9 + ' de McCabe compte les points de d' + #$00E9 +
        'cision (1 de base + if + branche de case + for/while/repeat + gestionnaire on + and/or/xor). Une complexit' +
        #$00E9 + ' ' + #$00E9 + 'lev' + #$00E9 + 'e rend le code difficile ' + #$00E0 +
        ' tester et ' + #$00E0 + ' comprendre.'
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'R' + #$00E8 + 'gle personnalis' + #$00E9 + 'e';
      ShortDesc: 'Motif d' + #$00E9 + 'tect' + #$00E9 + ' par une r' + #$00E8 + 'gle charg' + #$00E9 +
        'e depuis analyser-rules.yml';
      FullDesc : 'Kind g' + #$00E9 + 'n' + #$00E9 + 'rique pour les r' + #$00E8 + 'gles regex / AST d' +
        #$00E9 + 'finies par l''utilisateur et charg' + #$00E9 + 'es ' + #$00E0 + ' l''ex' + #$00E9 +
        'cution depuis analyser-rules.yml. L''ID de r' + #$00E8 + 'gle sp' + #$00E9 +
        'cifique, le message et la s' + #$00E9 + 'v' + #$00E9 + 'rit' + #$00E9 +
        ' proviennent de l''entr' + #$00E9 + 'e YAML ; cette entr' + #$00E9 +
        'e du catalogue est un espace r' + #$00E9 + 'serv' + #$00E9 +
        ' afin que le dispatcher et l''exportateur SARIF disposent de m' + #$00E9 + 'tadonn' +
        #$00E9 + 'es stables.'
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Composant au nom par d' + #$00E9 + 'faut';
      ShortDesc: 'Le composant porte encore le nom par d' + #$00E9 +
        'faut de l''assistant (Button1, Edit3, Panel2 ...)';
      FullDesc : 'Les noms par d' + #$00E9 +
        'faut masquent l''intention et cassent la recherche des utilisations / les refactorings de renommage. Renommer les contr' +
        #$00F4 + 'les d''interface pour qu''ils expriment leur r' + #$00F4 +
        'le (btnSave, edUserName, pnlToolbar ...).'
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Texte d''interface en dur dans le DFM';
      ShortDesc: 'Caption, Hint ou Text sous forme de litt' + #$00E9 +
        'ral dans le DFM, sans passer par la couche i18n';
      FullDesc : 'Les cha' + #$00EE + 'nes destin' + #$00E9 + 'es ' + #$00E0 + ' l''utilisateur int' + #$00E9 +
        'gr' + #$00E9 + 'es dans un .dfm ne peuvent ' + #$00EA + 'tre ni localis' + #$00E9 +
        'es, ni test' + #$00E9 + 'es en A/B, ni conserv' + #$00E9 +
        'es dans un catalogue de traduction. Les affecter lors de la construction de la fiche ' +
        #$00E0 + ' partir d''une resourcestring ou d''un helper i18n. Non signal' + #$00E9 +
        's : les captions d''un seul caract' + #$00E8 +
        're dans des polices de symboles (Webdings/Wingdings/Marlett/Symbol - des ic' + #$00F4 +
        'nes, pas du texte), les valeurs DFM que l''unit' + #$00E9 + ' de la fiche remplace ' +
        #$00E0 + ' partir d''une resourcestring (espaces r' + #$00E9 + 'serv' + #$00E9 +
        's morts), et les fiches dont l''unit' + #$00E9 + ' utilise un traducteur DFM ' + #$00E0 +
        ' l''ex' + #$00E9 +
        'cution (gnugettext/dxgettext/JvGnugettext, TranslateComponent, Dev-Cpp MultiLangSupport, cnwizards CnLangMgr, uLocalization*) - l' +
        #$00E0 + ', le texte DFM EST la source des msgid de la couche i18n.'
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Identifiants de base de donn' + #$00E9 + 'es en dur dans le DFM';
      ShortDesc: 'Password en clair ou ConnectionString avec Pwd= sur un composant de base de donn' + #$00E9 +
        'es';
      FullDesc : 'Les identifiants de base de donn' + #$00E9 + 'es enregistr' + #$00E9 +
        's dans un .dfm fuient dans le contr' + #$00F4 +
        'le de version, les artefacts de build et n''importe quel d' + #$00E9 + 'compilateur. D' +
        #$00E9 +
        'placer les secrets vers des variables d''environnement, le magasin d''identifiants du syst' +
        #$00E8 + 'me d''exploitation ou une configuration chiffr' + #$00E9 + 'e, et les affecter ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution.'
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Liaison (DataSource, DataField) en double';
      ShortDesc: 'Deux contr' + #$00F4 + 'les ou plus lient le m' + #$00EA +
        'me couple DataSource / DataField';
      FullDesc : 'Lorsque l''utilisateur modifie un contr' + #$00F4 + 'le li' + #$00E9 + ', le second re' +
        #$00E7 + 'oit une mise ' + #$00E0 + ' jour parall' + #$00E8 + 'le depuis le dataset - ' +
        #$00E9 + 'crasements concurrents, difficiles ' + #$00E0 + ' d' + #$00E9 +
        'boguer. Lier chaque (DataSource, DataField) ' + #$00E0 + ' exactement un contr' + #$00F4 +
        'le.'
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'Le gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement DFM pointe vers une m' + #$00E9 +
        'thode absente';
      ShortDesc: 'OnClick / On... renvoie ' + #$00E0 + ' une m' + #$00E9 +
        'thode qui n''existe pas dans la classe de la fiche';
      FullDesc : 'Le streaming DFM plante au chargement de la fiche avec *"class TForm has no published method X"*. G' +
        #$00E9 + 'n' + #$00E9 + 'ralement caus' + #$00E9 +
        ' par un renommage manuel dans le .pas sans mise ' + #$00E0 + ' jour du .dfm.'
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement orphelin';
      ShortDesc: 'M' + #$00E9 + 'thode published de forme TNotifyEvent sans liaison DFM';
      FullDesc : 'La m' + #$00E9 + 'thode ressemble ' + #$00E0 + ' un gestionnaire d''' + #$00E9 + 'v' +
        #$00E9 + 'nement (Sender: TObject) mais aucun .dfm ne la r' + #$00E9 + 'f' + #$00E9 +
        'rence - les liaisons d''' + #$00E9 + 'l' + #$00E9 +
        'ments de collection (item ... OnAction = Foo, p. ex. les actions de WebModule ou les listes de commandes de plugin) comptent comme r' +
        #$00E9 + 'f' + #$00E9 + 'rences. Limites connues : les gestionnaires li' + #$00E9 +
        's uniquement dans un DFM anc' + #$00EA + 'tre hors de l''analyse, ou affect' + #$00E9 +
        's dans le code, sont tout de m' + #$00EA + 'me signal' + #$00E9 +
        's. Probablement un reste d''un contr' + #$00F4 + 'le supprim' + #$00E9 +
        ' - le supprimer ou le c' + #$00E2 + 'bler.'
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement li' + #$00E9 + ' mais vide';
      ShortDesc: 'L''' + #$00E9 + 'v' + #$00E9 + 'nement est li' + #$00E9 + ' dans le DFM, la m' + #$00E9 +
        'thode existe, le corps est vide';
      FullDesc : 'Un gestionnaire vide avec une liaison DFM active est presque toujours un stub oubli' +
        #$00E9 + ' apr' + #$00E8 +
        's son ajout par le concepteur de fiches. Supprimer la liaison ou impl' + #$00E9 +
        'menter le gestionnaire.'
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'Composant DFM sans champ published';
      ShortDesc: 'Le composant du DFM n''a pas de champ published correspondant dans la classe de la fiche - entr' +
        #$00E9 + 'e DFM p' + #$00E9 + 'rim' + #$00E9 + 'e (d' + #$00E9 + 'rive de sch' + #$00E9 +
        'ma)';
      FullDesc : 'Un composant DFM nomm' + #$00E9 + ' sans champ published correspondant est un ' + #$00E9 +
        'cart de sch' + #$00E9 + 'ma, pas une erreur d''ex' + #$00E9 + 'cution : le streamer r' +
        #$00E9 +
        'sout le champ via FieldAddress, obtient nil et ignore silencieusement l''affectation (pas d''EReadError). Le composant est tout de m' +
        #$00EA + 'me cr' + #$00E9 + #$00E9 + ' mais inaccessible depuis le code - une entr' + #$00E9 +
        'e DFM p' + #$00E9 + 'rim' + #$00E9 + 'e/morte qu''il vaut la peine de nettoyer.'
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Boucle DataSource / ma' + #$00EE + 'tre-d' + #$00E9 + 'tail circulaire';
      ShortDesc: 'Cycle dans les ar' + #$00EA + 'tes DataSource.DataSet / DataSet.MasterSource';
      FullDesc : 'Un cycle dans le graphe ma' + #$00EE + 'tre-d' + #$00E9 + 'tail provoque une r' + #$00E9 +
        'cursion infinie pendant BeforeOpen ou tout rafra' + #$00EE + 'chissement et fait d' +
        #$00E9 + 'border la pile du processus. Rompre le cycle en supprimant l''un des liens.'
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'Propri' + #$00E9 + 't' + #$00E9 + ' SQL construite depuis une saisie d''interface';
      ShortDesc: 'Query.SQL assembl' + #$00E9 + 'e ' + #$00E0 + ' partir des propri' + #$00E9 + 't' + #$00E9 +
        's Text ou Caption de contr' + #$00F4 + 'les de fiche';
      FullDesc : 'Une propri' + #$00E9 + 't' + #$00E9 + ' SQL de requ' + #$00EA + 'te de base de donn' +
        #$00E9 + 'es (TADOQuery / TFDQuery / TUniQuery / TZQuery / TKSQLQuery.SQL.Text) est assembl' +
        #$00E9 + 'e en concat' + #$00E9 + 'nant la propri' + #$00E9 + 't' + #$00E9 +
        ' Text / Caption / Hint / EditText / ItemText d''un contr' + #$00F4 +
        'le de saisie d''interface (TEdit, TComboBox, TMaskEdit, ...) - injection SQL classique via la fiche. Un utilisateur qui tape `'' OR ''''1''''=''''1'' --` dans le champ de recherche lit n''importe quelle ligne ; `''; DROP TABLE Users; --` est destructeur. Refact' +
        'oring : lier des param' + #$00E8 + 'tres nomm' + #$00E9 +
        's et les affecter via ParamByName, ne jamais concat' + #$00E9 + 'ner. Ce d' + #$00E9 +
        'tecteur est le pendant DFM/chemin d''interface de SCA003 (injection SQL lexicale) et de SCA058 (instruction SQL dangereuse).'
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Champ obligatoire sans liaison d''interface';
      ShortDesc: 'Un TField avec Required=True n''a aucun contr' + #$00F4 + 'le de saisie li' + #$00E9;
      FullDesc : 'Un champ obligatoire que l''utilisateur ne peut pas atteindre fait ' + #$00E9 +
        'chouer chaque insertion avec ''Field X must have a value''. Lier un contr' + #$00F4 +
        'le ou retirer le Required=True.'
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Champ obligatoire li' + #$00E9 + ' uniquement ' + #$00E0 + ' des contr' + #$00F4 +
        'les cach' + #$00E9 + 's';
      ShortDesc: 'Un TField avec Required=True n''est li' + #$00E9 + ' qu''' + #$00E0 + ' des contr' + #$00F4 +
        'les ayant Visible=False';
      FullDesc : 'Le contr' + #$00F4 +
        'le existe mais l''utilisateur ne peut ni le voir ni interagir avec lui - les insertions ' +
        #$00E9 + 'chouent ' + #$00E0 + ' chaque fois. Rendre visible au moins un contr' + #$00F4 +
        'le li' + #$00E9 + ' ou retirer le Required=True.'
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'Type de contr' + #$00F4 + 'le incompatible avec le TField';
      ShortDesc: 'La classe du contr' + #$00F4 + 'le de donn' + #$00E9 + 'es ne correspond pas ' + #$00E0 +
        ' TField.DataType (TDBEdit pour un TBooleanField)';
      FullDesc : 'L''utilisateur voit la valeur brute et peut corrompre le type. Choisir un contr' + #$00F4 +
        'le compatible avec le type du champ (TDBCheckBox pour les bool' + #$00E9 +
        'ens, TDBLookupComboBox pour les cl' + #$00E9 + 's ' + #$00E9 + 'trang' + #$00E8 + 'res).'
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'TabOrder en double entre fr' + #$00E8 + 'res';
      ShortDesc: 'Deux contr' + #$00F4 + 'les fr' + #$00E8 + 'res du m' + #$00EA + 'me parent partagent la m' +
        #$00EA + 'me valeur TabOrder';
      FullDesc : 'La s' + #$00E9 + 'rialisation VCL tol' + #$00E8 +
        're des TabOrder en double, mais la navigation par tabulation d' + #$00E9 +
        'pend alors de l''ordre de d' + #$00E9 + 'claration et devient impr' + #$00E9 +
        'visible pour l''utilisateur. Renum' + #$00E9 +
        'roter pour que TabOrder soit unique par parent.'
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Le composant utilise une classe interdite';
      ShortDesc: 'La classe du composant figure dans la liste ForbiddenClasses du projet';
      FullDesc : 'Application du guide de style pour les interdictions de classes propres au projet (TQuery, TLabel lorsqu''un TStyledLabel existe, ...). Le d' +
        #$00E9 + 'tecteur reste muet tant que le projet ne d' + #$00E9 +
        'finit pas `[Components] ForbiddenClasses=...` dans analyser.ini.'
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'Composant de base de donn' + #$00E9 + 'es sur une fiche d''interface';
      ShortDesc: 'TFDQuery / TFDConnection directement sur un TForm ou TFrame au lieu d''un DataModule';
      FullDesc : 'Une infrastructure de base de donn' + #$00E9 +
        'es sur une fiche d''interface couple la persistance ' + #$00E0 + ' la pr' + #$00E9 +
        'sentation - difficile ' + #$00E0 + ' r' + #$00E9 + 'utiliser, difficile ' + #$00E0 +
        ' tester. La d' + #$00E9 + 'placer dans un TDataModule et la r' + #$00E9 + 'f' + #$00E9 +
        'rencer depuis la fiche.'
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Acc' + #$00E8 + 's ' + #$00E0 + ' un champ d''une autre fiche';
      ShortDesc: 'Du code dans Form1 lit ou ' + #$00E9 + 'crit directement Form2.<champ_published>';
      FullDesc : 'Aller chercher un contr' + #$00F4 +
        'le enfant dans une autre fiche casse l''encapsulation - tout renommage dans Form2 casse silencieusement Form1. Exposer plut' +
        #$00F4 + 't une propri' + #$00E9 + 't' + #$00E9 + ' ou une m' + #$00E9 + 'thode sur Form2.'
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Contr' + #$00F4 + 'le de saisie directement sur le TForm';
      ShortDesc: 'Le contr' + #$00F4 + 'le de saisie est pos' + #$00E9 + ' sur la fiche au lieu d''' + #$00EA +
        'tre plac' + #$00E9 + ' dans un TPanel ou un TGroupBox';
      FullDesc : 'Une mise en page en couches (Form > Panel > Group > Controls) facilite nettement le redimensionnement, la mise ' +
        #$00E0 + ' l''' + #$00E9 + 'chelle DPI et l''application de th' + #$00E8 +
        'mes. Envelopper les contr' + #$00F4 +
        'les dans un conteneur de mise en page. Dialecte FPC/Lazarus : cette r' + #$00E8 +
        'gle est ignor' + #$00E9 + 'e lorsque l''analyse s''ex' + #$00E9 +
        'cute avec --dialect=fpc (ou un projet .lpi/.lpk/.lpg) - le mod' + #$00E8 +
        'le de couches VCL qu''elle v' + #$00E9 + 'rifie ne s''applique pas aux fiches LCL.'
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement li' + #$00E9 + ' ' + #$00E0 +
        ' trop d''' + #$00E9 + 'v' + #$00E9 + 'nements';
      ShortDesc: 'Une seule m' + #$00E9 + 'thode est li' + #$00E9 + 'e ' + #$00E0 + ' N ' + #$00E9 + 'v' +
        #$00E9 + 'nements de composants ou plus (N=5 par d' + #$00E9 + 'faut)';
      FullDesc : 'Indicateur de code spaghetti : un gestionnaire unique qui r' + #$00E9 +
        'partit de nombreux ' + #$00E9 + 'v' + #$00E9 +
        'nements sans rapport entre eux est difficile ' + #$00E0 + ' lire, difficile ' + #$00E0 +
        ' modifier et a presque toujours des probl' + #$00E8 + 'mes de coh' + #$00E9 +
        'sion. Le scinder par responsabilit' + #$00E9 + '. Signal' + #$00E9 + ' lorsqu''une m' +
        #$00E9 + 'thode est li' + #$00E9 + 'e ' + #$00E0 + ' 5 ' + #$00E9 + 'v' + #$00E9 +
        'nements de composants ou plus dans un DFM et que les liaisons sont h' + #$00E9 + 't' +
        #$00E9 + 'rog' + #$00E8 + 'nes - classes de composants diff' + #$00E9 + 'rentes ou ' +
        #$00E9 + 'v' + #$00E9 + 'nements diff' + #$00E9 + 'rents. Un gestionnaire partag' + #$00E9 +
        ' par des composants d''une m' + #$00EA + 'me classe sur le m' + #$00EA + 'me ' + #$00E9 +
        'v' + #$00E9 +
        'nement (douze boutons de couleur avec un seul OnClick) est un regroupement param' + #$00E9 +
        'tr' + #$00E9 + ' et n''est pas signal' + #$00E9 + '.'
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Le composant a Action et OnClick';
      ShortDesc: 'Action et OnClick sont tous deux d' + #$00E9 +
        'finis - le OnClick explicite l''emporte, le c' + #$00E2 + 'blage TAction est mort';
      FullDesc : 'Lorsque les deux sont d' + #$00E9 + 'finis, le gestionnaire OnClick EXPLICITE l''emporte ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution : TControl.Click appelle FOnClick d' + #$00E8 +
        's qu''il est affect' + #$00E9 +
        ' et ne pointe pas vers le OnExecute de l''action - ce n''est que dans le cas contraire que ActionLink.Execute s''ex' +
        #$00E9 + 'cute (m' + #$00EA + 'me logique dans TMenuItem.Click). Le double c' + #$00E2 +
        'blage est le signal d''alerte : l''un des deux chemins est mort. NON signal' + #$00E9 +
        ' lorsque le OnClick pointe exactement vers le gestionnaire OnExecute de l''action li' +
        #$00E9 + 'e trouv' + #$00E9 + 'e dans le m' + #$00EA + 'me DFM/LFM - les deux chemins ex' +
        #$00E9 + 'cutent alors la m' + #$00EA + 'me proc' + #$00E9 +
        'dure (l''IDE Lazarus enregistre cette combinaison comme artefact de sauvegarde dans chaque LFM).'
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Longue concat' + #$00E9 + 'nation - pr' + #$00E9 + 'f' + #$00E9 + 'rer Format()';
      ShortDesc: 'Concat' + #$00E9 + 'nation de cha' + #$00EE + 'ne en plusieurs segments - ' + #$00E0 +
        ' transformer en appel ' + #$00E0 + ' Format()';
      FullDesc : 'Les encha' + #$00EE + 'nements comme `''a'' + Var + ''b'' + IntToStr(N)` (trois concat' +
        #$00E9 + 'nations ou plus impliquant des segments non litt' + #$00E9 +
        'raux) sont plus difficiles ' + #$00E0 + ' parcourir et ' + #$00E0 +
        ' traduire que `Format(''a%sb%d'', [Var, N])` : chaque IntToStr / FloatToStr / FormatDateTime au milieu d''une cha' +
        #$00EE + 'ne est un endroit de plus o' + #$00F9 +
        ' une `resourcestring` ne peut pas capturer le mod' + #$00E8 + 'le du message. Le d' +
        #$00E9 + 'tecteur examine les affectations dont le membre droit comporte au moins trois op' +
        #$00E9 + 'rateurs `+` (quatre termes ou plus) avec au moins un terme non litt' + #$00E9 +
        'ral, de sorte que les cas triviaux (`''<'' + Name + ''>''`) restent muets ; une concat' +
        #$00E9 + 'nation pass' + #$00E9 + 'e directement comme argument d''appel n''est pas v' +
        #$00E9 + 'rifi' + #$00E9 + 'e. Il ignore les membres droits qui appellent d' + #$00E9 + 'j' +
        #$00E0 + ' Format, les affectations ' + #$00E0 + ' des propri' + #$00E9 + 't' + #$00E9 +
        's SQL (SCA003 les couvre) et les lignes sous un `// noinspection ConcatToFormat` actif. La forme signal' +
        #$00E9 + 'e peut ' + #$00EA +
        'tre voulue dans des boucles internes critiques pour les performances, o' + #$00F9 +
        ' les varargs de Format provoquent du boxing ; le marqueur de suppression est pr' + #$00E9 +
        'vu pour ce cas.'
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'Instruction with - pi' + #$00E8 + 'ge de masquage de port' + #$00E9 +
        'e contre lequel le compilateur n''avertit pas';
      FullDesc : 'Marco Cantu, delphi.org et Stack Overflow classent syst' + #$00E9 +
        'matiquement `with` parmi les principales sources de bugs en Delphi. Les identificateurs de la port' +
        #$00E9 + 'e externe sont masqu' + #$00E9 +
        's silencieusement par les membres de la cible du with. Utiliser plut' + #$00F4 +
        't un alias sous forme de variable locale.'
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto manquant';
      ShortDesc: 'for i := 10 to 1 do - le corps de boucle ne s''ex' + #$00E9 + 'cute jamais';
      FullDesc : '`for i := 10 to 1 do` est une faute de frappe downto-contre-to : en Pascal, une boucle `to` dont le d' +
        #$00E9 + 'but est > ' + #$00E0 + ' la fin it' + #$00E8 + 're z' + #$00E9 +
        'ro fois, si bien que le corps ne s''ex' + #$00E9 +
        'cute silencieusement jamais et que le bug se manifeste par des effets de bord manquants, sans avertissement du compilateur. Le d' +
        #$00E9 + 'tecteur compare des litt' + #$00E9 + 'raux entiers des deux c' + #$00F4 + 't' +
        #$00E9 + 's, signe moins initial facultatif compris (`for i := 5 to -1` est signal' + #$00E9 +
        ') ; les expressions et constantes comme `Length(L)-1` ou `High(A)` ne sont pas ' + #$00E9 +
        'valu' + #$00E9 + 'es. Les boucles ' + #$00E0 +
        ' bornes variables sont exclues - elles peuvent l' + #$00E9 +
        'gitimement ne rien faire selon les donn' + #$00E9 + 'es d''ex' + #$00E9 + 'cution. Pour it' +
        #$00E9 + 'rer en ordre d' + #$00E9 + 'croissant, ' + #$00E9 +
        'crire `downto` ; pour exprimer explicitement ' + #$00AB + ' peut-' + #$00EA + 'tre vide ' +
        #$00BB + ', prot' + #$00E9 + 'ger avec un `if From <= To`.'
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Auto-affectation - sans effet, ou faute de copier-coller';
      FullDesc : 'Signal' + #$00E9 + ' uniquement lorsqu''il est prouv' + #$00E9 +
        ' que la cible est un emplacement de stockage : une variable locale, un param' + #$00E8 +
        'tre, Result, une affectation au nom de la fonction, un champ d' + #$00E9 + 'clar' + #$00E9 +
        ' dans la m' + #$00EA + 'me unit' + #$00E9 +
        ' - ou un chemin de membre (Pt.Y, R^.iType) dont la racine est un tel emplacement et dont chaque segment est un simple champ de record, r' +
        #$00E9 + 'solu via les propres d' + #$00E9 + 'clarations de record de l''unit' + #$00E9 +
        ' plus une liste RTL s' + #$00E9 + 'lectionn' + #$00E9 +
        'e (champs de TPoint, TRect, ...). Les cibles de type propri' + #$00E9 + 't' + #$00E9 +
        ' restent muettes dans toutes les positions - ' + #$00E9 + 'crire dans une propri' + #$00E9 +
        't' + #$00E9 + ' ex' + #$00E9 + 'cute son setter, qui peut borner, r' + #$00E9 +
        'appliquer ou reformater la valeur (TopLine := TopLine borne par rapport ' + #$00E0 +
        ' la fen' + #$00EA + 'tre redimensionn' + #$00E9 + 'e ; TRectF.Height := TRectF.Height ' +
        #$00E9 + 'crit Bottom). Les chemins index' + #$00E9 +
        's (a[i]) et les noms qui ne peuvent pas ' + #$00EA + 'tre r' + #$00E9 + 'solus restent ' +
        #$00E9 + 'galement muets. Le compromis est d' + #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 +
        ' : les formes inconnues deviennent des faux n' + #$00E9 +
        'gatifs, jamais des faux positifs. Result := Result; pour faire taire un hint du compilateur est tout de m' +
        #$00EA + 'me signal' + #$00E9 + ' et peut ' + #$00EA + 'tre masqu' + #$00E9 +
        ' avec un commentaire // noinspection directement au-dessus de la ligne.'
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Appel virtuel dans le constructeur';
      ShortDesc: 'M' + #$00E9 + 'thode virtuelle appel' + #$00E9 + 'e depuis le constructeur - la classe d' +
        #$00E9 + 'riv' + #$00E9 + 'e voit un Self ' + #$00E0 + ' moiti' + #$00E9 + ' initialis' +
        #$00E9;
      FullDesc : 'C++ FAQ 23.5 / *Effective Java* item 17 sous forme Delphi : un appel virtuel dans un constructeur ex' +
        #$00E9 + 'cute la red' + #$00E9 + 'finition la plus d' + #$00E9 + 'riv' + #$00E9 +
        'e avant que les champs de la classe d' + #$00E9 + 'riv' + #$00E9 + 'e soient initialis' +
        #$00E9 + 's. Reporter le travail dans un hook non virtuel ex' + #$00E9 + 'cut' + #$00E9 +
        ' apr' + #$00E8 + 's la construction.'
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N sans garde';
      ShortDesc: '`Length(s) - K` ou `.Count - K` avec K >= 2 sans garde - index ou nombre n' + #$00E9 +
        'gatif quand l''entr' + #$00E9 + 'e est plus courte que K';
      FullDesc : '`Length` et `.Count` renvoient un Integer sign' + #$00E9 +
        ', donc `Length(s) - 4` sur une cha' + #$00EE + 'ne de moins de quatre caract' + #$00E8 +
        'res est simplement un nombre n' + #$00E9 + 'gatif - et ce nombre va g' + #$00E9 + 'n' +
        #$00E9 +
        'ralement tout droit dans un index, une position de Move ou un compteur : `s[Length(s) - 3]` lit avant le premier caract' +
        #$00E8 + 're (une erreur d''intervalle avec $R+, des donn' + #$00E9 +
        'es parasites ou une violation d''acc' + #$00E8 +
        's sans), `Move(s[Length(s) - 4], Buf, 4)` copie depuis l''ext' + #$00E9 + 'rieur de la cha' +
        #$00EE + 'ne. Le d' + #$00E9 + 'tecteur signale `Length(...)` et `.Count` suivis de `- K` o' +
        #$00F9 + ' K est un litt' + #$00E9 + 'ral entier valant 2 ou plus. `- 1` est ignor' + #$00E9 +
        ' : `for I := 0 to Length(s) - 1` s''ex' + #$00E9 + 'cute simplement z' + #$00E9 +
        'ro fois sur une cha' + #$00EE +
        'ne vide. Il s''agit d''une indication lexicale - une garde `if Length(s) >= K` qui pr' +
        #$00E9 + 'c' + #$00E8 + 'de n''est pas vue. Pr' + #$00E9 + 'f' + #$00E9 +
        'rer les helpers RTL qui g' + #$00E8 + 'rent les entr' + #$00E9 +
        'es courtes (ExtractFileExt, RightStr, EndsText) ou prot' + #$00E9 + 'ger l''acc' + #$00E8 +
        's.'
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre priv' + #$00E9 + ' ' + #$00E0 + ' l''unit' +
        #$00E9;
      ShortDesc: 'Ce membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + ' que dans l''unit' +
        #$00E9 + ' courante - le `private` classique de Delphi (port' + #$00E9 + 'e unit' + #$00E9 +
        ') suffit';
      FullDesc : 'Analyse d''un seul fichier : le membre `public` est r' + #$00E9 + 'f' + #$00E9 + 'renc' +
        #$00E9 + ' depuis un endroit de la m' + #$00EA + 'me unit' + #$00E9 +
        ' (autres classes, proc' + #$00E9 +
        'dures de premier niveau, ...), mais PAS exclusivement depuis la classe d' + #$00E9 +
        'clarante elle-m' + #$00EA +
        'me. Le restreindre au `private` classique de Delphi (dont la port' + #$00E9 +
        'e est l''unit' + #$00E9 + ', pas la classe) est s' + #$00FB + 'r : chaque appelant l' +
        #$00E9 + 'gal dans l''unit' + #$00E9 + ' continue de fonctionner. Ce d' + #$00E9 +
        'tecteur s''ex' + #$00E9 +
        'cute volontairement UNIQUEMENT sur un seul fichier - l''ancienne analyse inter-unit' +
        #$00E9 +
        's/inter-projets produisait trop de faux positifs (streaming RTTI/DFM, consommateurs .dpk/.dproj voisins, instanciations g' +
        #$00E9 + 'n' + #$00E9 +
        'riques, API de plugins). Ce conseil est une recommandation ; si une unit' + #$00E9 + ' ' +
        #$00E9 + 'trang' + #$00E8 + 're consomme le membre, le compilateur d' + #$00E9 +
        'tectera la visibilit' + #$00E9 + ' cass' + #$00E9 +
        'e avec E2361 une fois la modification appliqu' + #$00E9 +
        'e. Exclus : published, virtual/abstract/override/dynamic, constructeurs/destructeurs de classe, classes de base pilot' +
        #$00E9 + 'es par RTTI (TForm/TFrame/TDataModule/TComponent), classes utilitaires compos' +
        #$00E9 + 'es uniquement de m' + #$00E9 +
        'thodes de classe. Masquer ligne par ligne avec `// noinspection CanBeUnitPrivate` pour une surface publique voulue (API de biblioth' +
        #$00E8 + 'que, point d''entr' + #$00E9 + 'e de plugin).'
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre protected';
      ShortDesc: 'Membre public r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' uniquement depuis des classes d' + #$00E9 + 'riv' + #$00E9 + 'es, jamais de l''ext' +
        #$00E9 + 'rieur';
      FullDesc : 'Analyse d''un seul fichier : chaque appelant visible du membre public est lui-m' + #$00EA +
        'me une m' + #$00E9 + 'thode d''une classe d' + #$00E9 + 'riv' + #$00E9 + 'e de la classe d' +
        #$00E9 + 'clarante. `protected` est la visibilit' + #$00E9 +
        ' minimale qui satisfait tous les points d''appel actuels et signale l''intention de conception (' +
        #$00AB + ' ceci est un point d''extension, pas une partie de l''API destin' + #$00E9 +
        'e aux consommateurs ' + #$00BB + '). M' + #$00EA + 'me r' + #$00E9 + 'serve li' + #$00E9 +
        'e ' + #$00E0 +
        ' l''analyse d''un seul fichier que pour CanBeUnitPrivate / CanBeStrictPrivate : les consommateurs situ' +
        #$00E9 + 's dans d''autres unit' + #$00E9 + 's sont invisibles pour le d' + #$00E9 +
        'tecteur ; le compilateur v' + #$00E9 +
        'rifie le refactoring via E2361 s''il existe un appelant ' + #$00E9 +
        'tranger. Exclus : membres published / expos' + #$00E9 +
        's par RTTI, racines virtual/override qui font partie de la hi' + #$00E9 +
        'rarchie document' + #$00E9 + 'e. Restreindre en toute confiance au sein du projet d' +
        #$00E9 + 'clarant ; pour les API de biblioth' + #$00E8 + 'que livr' + #$00E9 + 'es, v' +
        #$00E9 + 'rifier d''abord manuellement les appelants externes.'
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Membre public inutilis' + #$00E9 + ' (API morte)';
      ShortDesc: 'Le membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' par aucune classe d' + #$00E9 + 'riv' + #$00E9 + 'e ni par aucun chemin inter-unit' +
        #$00E9 + 's';
      FullDesc : 'Aucune utilisation interne ET aucune utilisation externe trouv' + #$00E9 +
        'e - surface d''API morte. La supprimer ou la documenter comme export' + #$00E9 +
        'e volontairement (p. ex. pour la compatibilit' + #$00E9 + ' binaire).'
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Variable locale inutilis' + #$00E9 + 'e';
      ShortDesc: 'Variable locale d' + #$00E9 + 'clar' + #$00E9 + 'e mais jamais r' + #$00E9 + 'f' + #$00E9 +
        'renc' + #$00E9 + 'e dans le corps de la m' + #$00E9 + 'thode';
      FullDesc : 'Un `var X: T;` dans le corps d''une m' + #$00E9 + 'thode est d' + #$00E9 + 'clar' + #$00E9 +
        ' mais jamais lu ni ' + #$00E9 + 'crit dans ce m' + #$00EA +
        'me corps. Reprend le conseil H2164 du compilateur Delphi, mais ' + #$00E9 + 'mis comme r' +
        #$00E9 + 'sultat SCA afin de pouvoir ' + #$00EA + 'tre filtr' + #$00E9 + ', masqu' + #$00E9 +
        ', prioris' + #$00E9 + ' et suivi de la m' + #$00EA + 'me mani' + #$00E8 +
        're que les autres r' + #$00E8 + 'gles - utile lorsque H2164 est d' + #$00E9 + 'sactiv' +
        #$00E9 + ' pour tout le projet. L''analyse du corps reconna' + #$00EE +
        't les identificateurs reli' + #$00E9 +
        's par `with` et ignore les variables dont le nom correspond ' + #$00E0 + ' un champ ou ' +
        #$00E0 + ' une propri' + #$00E9 + 't' + #$00E9 +
        ' existants (le `with` les relierait implicitement). Les variables inline introduites par `var X: T := ...` sont trait' +
        #$00E9 + 'es de la m' + #$00EA + 'me fa' + #$00E7 +
        'on. Masquer avec `// noinspection UnusedLocalVar` lorsque la variable est conserv' + #$00E9 +
        'e volontairement (documentation d' + #$00E9 + 'clarative, ou initialisation de record exig' +
        #$00E9 + 'e par une API).'
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Param' + #$00E8 + 'tre de m' + #$00E9 + 'thode inutilis' + #$00E9;
      ShortDesc: 'Le param' + #$00E8 + 'tre de la m' + #$00E9 + 'thode n''est jamais utilis' + #$00E9 +
        ' dans le corps';
      FullDesc : 'Un param' + #$00E8 + 'tre formel est d' + #$00E9 + 'clar' + #$00E9 +
        ' mais jamais lu dans le corps de la m' + #$00E9 + 'thode. Le param' + #$00E8 +
        'tre encombre le site d''appel (chaque appelant passe une valeur sans effet) et occulte les v' +
        #$00E9 + 'ritables d' + #$00E9 + 'pendances de la m' + #$00E9 +
        'thode. Refactoring : supprimer le param' + #$00E8 +
        'tre, ou faire passer le site d''appel par une autre surcharge qui ne le prend pas. Le d' +
        #$00E9 + 'tecteur ignore volontairement les signatures impos' + #$00E9 + 'es de l''ext' +
        #$00E9 + 'rieur : `override` (la signature du parent est fix' + #$00E9 +
        'e), les corps de remplacement `; virtual; abstract`, les impl' + #$00E9 +
        'mentations d''interface (signature dict' + #$00E9 +
        'e par l''interface), les gestionnaires d''' + #$00E9 + 'v' + #$00E9 +
        'nement (`Sender: TObject` et le reste du tuple d''' + #$00E9 + 'v' + #$00E9 +
        'nement) et les m' + #$00E9 + 'thodes enregistr' + #$00E9 + 'es comme gestionnaires d''' +
        #$00E9 + 'v' + #$00E9 + 'nement DFM. Masquer par m' + #$00E9 +
        'thode avec `// noinspection UnusedParameter` pour les callbacks ' + #$00E0 +
        ' forme stable (RTTI/streaming).'
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Expression bool' + #$00E9 + 'enne tautologique';
      ShortDesc: 'Op' + #$00E9 +
        'rateur binaire avec membres gauche et droit identiques : x = x, a and a, (p <> p)';
      FullDesc : 'Un op' + #$00E9 + 'rateur binaire a le m' + #$00EA + 'me op' + #$00E9 +
        'rande textuel des deux c' + #$00F4 + 't' + #$00E9 +
        's : `x = x`, `a and a`, `(p <> p)`. L''expression s''' + #$00E9 + 'value ' + #$00E0 +
        ' une constante (True ou False) ' + #$00E0 +
        ' la compilation et indique presque toujours une faute de frappe - l''op' + #$00E9 +
        'rande devait ' + #$00EA + 'tre un identificateur au nom proche (`a = b`, `p1 <> p2`). Le d' +
        #$00E9 + 'tecteur suit : ' + #$00E9 + 'galit' + #$00E9 + ' / in' + #$00E9 + 'galit' + #$00E9 +
        ' / ordre (`=`, `<>`, `<`, `>`, `<=`, `>=`) et op' + #$00E9 + 'rateurs bool' + #$00E9 +
        'ens (`and`, `or`, `xor`). Les op' + #$00E9 + 'rateurs arithm' + #$00E9 +
        'tiques (`+`, `-`, `*`) sont volontairement exclus : `x + x` et `a * a` sont des idiomes l' +
        #$00E9 + 'gitimes. La normalisation des op' + #$00E9 +
        'randes passe en minuscules et supprime les espaces superflus, mais conserve le contenu des litt' +
        #$00E9 + 'raux de cha' + #$00EE +
        'ne, de sorte que `''foo'' = ''foo''` est correctement signal' + #$00E9 + '. Le d' + #$00E9 +
        'tecteur exige l''' + #$00E9 + 'galit' + #$00E9 +
        ' des identificateurs de part et d''autre de l''op' + #$00E9 +
        'rateur - un appel de fonction avec effets de bord (`Next = Next`) est aussi signal' +
        #$00E9 + ', car deux appels produisent le bug dans tous les cas.'
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Ma' + #$00EE + 'tre-d' + #$00E9 + 'tail sans MasterFields';
      ShortDesc: 'Le TDataSet a MasterSource mais ni MasterFields ni IndexFieldNames';
      FullDesc : 'La VCL effectue silencieusement un produit cart' + #$00E9 +
        'sien au lieu de la jointure ma' + #$00EE + 'tre-d' + #$00E9 + 'tail pr' + #$00E9 +
        'vue - chaque ligne parente ram' + #$00E8 + 'ne toutes les lignes de d' + #$00E9 + 'tail ' +
        #$00E0 + ' l''ex' + #$00E9 +
        'cution. Corriger en renseignant MasterFields (et IndexFieldNames pour IB/FB).'
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Fiche charg' + #$00E9 + 'e de composants de donn' + #$00E9 + 'es - extraire un DataModule';
      ShortDesc: 'Indication agr' + #$00E9 + 'g' + #$00E9 + 'e : la fiche porte N composants de base de donn' +
        #$00E9 + 'es ou plus';
      FullDesc : 'Agr' + #$00E9 + 'gat de plusieurs r' + #$00E9 + 'sultats `DfmDbInUiForm` sur la m' + #$00EA +
        'me fiche - d' + #$00E8 + 's que leur nombre atteint 3, SCA ajoute une unique indication ' +
        #$00AB + ' extraire un TDataModule ' + #$00BB + ' en plus des r' + #$00E9 +
        'sultats individuels (qui restent), afin de mettre en avant la correction architecturale au lieu de pointer un composant apr' +
        #$00E8 + 's l''autre. D' + #$00E9 + 'placer l''acc' + #$00E8 + 's aux donn' + #$00E9 +
        'es dans un TDataModule s' + #$00E9 + 'pare proprement la plomberie de donn' + #$00E9 +
        'es de l''interface : la m' + #$00EA + 'me TFDConnection et les m' + #$00EA + 'mes requ' +
        #$00EA + 'tes peuvent ' + #$00EA + 'tre partag' + #$00E9 +
        'es par plusieurs fiches, la couche base de donn' + #$00E9 +
        'es est testable sans instancier de TForm, et la configuration DesignForm vs RuntimeForm reste propre. Le seuil est de 3 et actuellement cod' +
        #$00E9 + ' en dur - maintenu bas, car d' + #$00E8 + 's que 3 composants de base de donn' +
        #$00E9 + 'es apparaissent sur une fiche, le sch' + #$00E9 + 'ma est d' + #$00E9 + 'j' +
        #$00E0 + ' mauvais.'
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE sans WHERE';
      ShortDesc: 'L''instruction SQL modifie toutes les lignes - clause WHERE manquante';
      FullDesc : '`UPDATE Users SET Active=0` sans WHERE bascule toutes les lignes de la table. De m' +
        #$00EA +
        'me pour `DELETE FROM ...` et `TRUNCATE TABLE ...`. Une catastrophe en production qui ne demande qu''' +
        #$00E0 + ' arriver.'
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format flottant dans Format() sans TFormatSettings';
      ShortDesc: '%.2f / %.3f sans TFormatSettings explicite - le pi' + #$00E8 + 'ge du s' + #$00E9 +
        'parateur d' + #$00E9 + 'cimal virgule ou point';
      FullDesc : 'Sur un Windows DE, `Format(''%.2f'', [3.14])` donne ' + #$00AB + ' 3,14 ' + #$00BB +
        ' ; sous EN-US, il donne ' + #$00AB + ' 3.14 ' + #$00BB +
        '. Pour une sortie lisible par machine (SQL, JSON, CSV), toujours passer `TFormatSettings.Invariant`.'
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'Instruction goto';
      ShortDesc: '`goto` affaiblit le flot de contr' + #$00F4 + 'le structur' + #$00E9;
      FullDesc : '`goto` et les ' + #$00E9 + 'tiquettes rendent le flot de contr' + #$00F4 +
        'le non structur' + #$00E9 +
        ' : les boucles, l''imbrication et try/finally deviennent difficiles ' + #$00E0 +
        ' suivre. SonarDelphi suit la m' + #$00EA +
        'me chose sous communitydelphi:GotoStatement. Le code Delphi moderne justifie rarement goto - m' +
        #$00EA + 'me un break sur plusieurs niveaux est plus propre sous forme de proc' + #$00E9 +
        'dure extraite avec Exit.'
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulation dans le source';
      ShortDesc: 'Les tabulations s''affichent diff' + #$00E9 + 'remment selon l''' + #$00E9 +
        'diteur - utiliser des espaces';
      FullDesc : 'La convention de codage Pascal est l''indentation par espaces depuis les ann' + #$00E9 +
        'es 80. Les tabulations s''affichent sur 2/4/8 colonnes selon l''' + #$00E9 +
        'diteur, cassent les diffs c' + #$00F4 + 'te ' + #$00E0 + ' c' + #$00F4 +
        'te des revues de code et perturbent l''alignement. SonarDelphi suit la m' + #$00EA +
        'me chose sous communitydelphi:TabulationCharacter.'
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Ligne de source trop longue';
      ShortDesc: 'La ligne d' + #$00E9 + 'passe 120 caract' + #$00E8 +
        'res - couper ou extraire une sous-expression';
      FullDesc : 'Les lignes de plus de 120 caract' + #$00E8 + 'res ne tiennent pas dans une revue de code c' +
        #$00F4 + 'te ' + #$00E0 + ' c' + #$00F4 + 'te standard (2*120+marge) et d' + #$00E9 +
        'bordent d''un tiers d''' + #$00E9 + 'cran 16:9. La valeur par d' + #$00E9 +
        'faut de SonarDelphi et les guides de style Sun/Java s''accordent sur 120. La limite est configurable via [Detectors] MaxLineLength (120 par d' +
        #$00E9 + 'faut).'
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Espaces en fin de ligne';
      ShortDesc: 'La ligne se termine par une espace ou une tabulation - hygi' + #$00E8 + 'ne pour les diffs';
      FullDesc : 'Une espace ou une tabulation en fin de ligne cr' + #$00E9 + 'e des lignes de diff fant' +
        #$00F4 + 'mes d' + #$00E8 + 's qu''un ' + #$00E9 + 'diteur avec ' + #$00AB +
        ' trim trailing whitespace on save ' + #$00BB + ' touche le fichier. SonarDelphi suit la m' +
        #$00EA + 'me chose sous communitydelphi:TrailingWhitespace.'
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Mot-cl' + #$00E9 + ' Pascal pas en minuscules';
      ShortDesc: 'Les mots-cl' + #$00E9 + 's Pascal (`begin`/`end`/`procedure`/...) doivent ' + #$00EA +
        'tre en minuscules';
      FullDesc : 'Le guide de style Object Pascal (Embarcadero DocWiki, Marco Cantu, SonarDelphi) est sans ambigu' +
        #$00EF + 't' + #$00E9 + ' : les mots-cl' + #$00E9 + 's s''' + #$00E9 +
        'crivent en minuscules. Les variantes ' + #$00E0 +
        ' casse mixte comme `Begin`/`End`/`Procedure` sont des restes de l''' + #$00E9 +
        'poque Turbo-Pascal/Delphi-1 et cr' + #$00E9 + 'ent des incoh' + #$00E9 +
        'rences dans les bases de code modernes. SonarDelphi suit la m' + #$00EA +
        'me chose sous communitydelphi:LowercaseKeyword.'
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'Marqueur de suppression NOSONAR';
      ShortDesc: '`// NOSONAR` ne devrait pas faire taire des r' + #$00E9 + 'sultats - v' + #$00E9 +
        'rifier l''usage';
      FullDesc : 'Les marqueurs NOSONAR sont de la dette technique : chacun fait taire un r' + #$00E9 +
        'sultat sans corriger le probl' + #$00E8 +
        'me sous-jacent. SCA signale chaque NOSONAR afin que les relecteurs puissent contr' + #$00F4 +
        'ler les masquages pendant la revue de code. SCA utilise son propre marqueur `// noinspection` pour le masquage natif - le code d' +
        #$00E9 + 'cor' + #$00E9 + ' de NOSONAR provenant de SonarDelphi devrait ' + #$00EA +
        'tre migr' + #$00E9 + '. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:NoSonar.'
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Liste d''arguments vide';
      ShortDesc: '`Foo()` devrait s''' + #$00E9 + 'crire `Foo;` - supprimer les parenth' + #$00E8 +
        'ses vides';
      FullDesc : 'La convention Delphi est d''' + #$00E9 + 'crire les appels sans param' + #$00E8 +
        'tre sans `()`. La forme `Foo()` de style C ajoute du bruit sans rien communiquer et est incoh' +
        #$00E9 + 'rente avec le reste du langage (proc' + #$00E9 + 'dures, propri' + #$00E9 + 't' +
        #$00E9 + 's, r' + #$00E9 + 'f' + #$00E9 + 'rences de fonction omettent toutes les parenth' +
        #$00E8 + 'ses en l''absence d''arguments). Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:EmptyArgumentList.'
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Bloc assembleur en ligne';
      ShortDesc: 'Bloc `asm...end` - pr' + #$00E9 + 'f' + #$00E9 + 'rer Pascal et les intrins' + #$00E8 +
        'ques du compilateur';
      FullDesc : 'L''assembleur en ligne cr' + #$00E9 + 'e une d' + #$00E9 + 'pendance ' + #$00E0 +
        ' la plate-forme (octets propres ' + #$00E0 + ' x86/x64 qui ne survivent pas ' + #$00E0 +
        ' une compilation crois' + #$00E9 +
        'e ARM ni aux cibles FreePascal), contourne l''optimiseur Delphi (pas d''inlining ni de r' +
        #$00E9 + 'organisation) et est difficile ' + #$00E0 + ' d' + #$00E9 +
        'boguer. Les cas d''usage l' + #$00E9 + 'gitimes (d' + #$00E9 + 'tection CPUID, intrins' +
        #$00E8 + 'ques MMX/SSE) sont couverts par des helpers de la RTL. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:InlineAssembly.'
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Virgule finale dans la liste d''arguments';
      ShortDesc: '`Foo(A, B,)` - supprimer la virgule ou ajouter l''argument manquant';
      FullDesc : 'Virgule finale avant `)` dans une liste d''arguments. Dans un appel normal, Delphi la rejette : la virgule ajoute un argument vide (E2034 trop de param' +
        #$00E8 + 'tres r' + #$00E9 + 'els). Seul un appel ' + #$00E0 +
        ' liaison tardive sur un Variant ou une dispinterface (automation OLE) la compile ; l''argument vide y est un param' +
        #$00E8 + 'tre optionnel omis. Elle n''y apporte aucun b' + #$00E9 + 'n' + #$00E9 + 'fice s' +
        #$00E9 + 'mantique (contrairement ' + #$00E0 + ' Python/JS, o' + #$00F9 +
        ' elle stabilise le diff) et sugg' + #$00E8 + 're un argument oubli' + #$00E9 +
        '. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:TrailingCommaArgumentList.'
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Litt' + #$00E9 + 'ral entier sans s' + #$00E9 + 'parateur de milliers';
      ShortDesc: 'Les grands litt' + #$00E9 + 'raux entiers devraient utiliser le s' + #$00E9 +
        'parateur `_`';
      FullDesc : 'Delphi 10.4+ accepte `_` comme s' + #$00E9 + 'parateur de chiffres dans les litt' + #$00E9 +
        'raux num' + #$00E9 + 'riques. Les constantes comme les d' + #$00E9 +
        'lais (1_800_000 ms = 30 min), les tailles de fichier (1_048_576 = 1 MiB), les montants en centimes et autres sont nettement plus lisibles avec un groupement explicite. Le seuil est de 5 chiffres (cod' +
        #$00E9 + ' en dur ; `[Detectors] DigitGroupingThreshold` est pr' + #$00E9 + 'vu). Les litt' +
        #$00E9 + 'raux hexad' + #$00E9 +
        'cimaux et flottants sont exclus (autre convention). Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:DigitGrouping.'
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Code en commentaire';
      ShortDesc: 'Le commentaire ressemble ' + #$00E0 + ' du code Pascal - supprimer ou justifier';
      FullDesc : 'Heuristique : un contenu de commentaire avec 2 marqueurs de style code ou plus (`;` final, `:=`, mots-cl' +
        #$00E9 +
        's `begin`/`end`/`procedure`/`function`/`if`/`then`/`for`/`while`) est presque certainement du code mis en commentaire. Ce code pourrit en silence : personne n''ose le supprimer, personne ne le met ' +
        #$00E0 +
        ' jour. Soit le supprimer, soit le remplacer par un TODO qui explique l''intention. Une ligne `//` n''est signal' +
        #$00E9 +
        'e que si aucune des lignes voisines n''est elle aussi un commentaire `//` - un bloc `//` de plusieurs lignes est trait' +
        #$00E9 +
        ' comme de la documentation avec des exemples de code - et un commentaire en fin de ligne apr' +
        #$00E8 + 's du code n''est pas signal' + #$00E9 + ' non plus. Les lignes signal' + #$00E9 +
        'es adjacentes (p. ex. des commentaires `{ ... }` cons' + #$00E9 + 'cutifs) sont signal' +
        #$00E9 + 'es comme UN SEUL r' + #$00E9 + 'sultat couvrant le bloc (endLine marque l''' +
        #$00E9 + 'tendue) ; une ligne signal' + #$00E9 + 'e isol' + #$00E9 +
        'e conserve le message par ligne. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:CommentedOutCode.'
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Mot-cl' + #$00E9 + ' de section d''unit' + #$00E9 + ' qui n''est pas en colonne 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` doivent commencer en colonne 1';
      FullDesc : 'La convention Object Pascal veut que les mots-cl' + #$00E9 +
        's de section structurels d''une unit' + #$00E9 + ' soient align' + #$00E9 + 's ' + #$00E0 +
        ' gauche en colonne 1. Des mots-cl' + #$00E9 + 's de section indent' + #$00E9 +
        's brouillent la structure de l''unit' + #$00E9 + ' ' + #$00E0 +
        ' la lecture rapide et peuvent indiquer une imbrication begin/end mal compt' + #$00E9 +
        'e. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:UnitLevelKeywordIndentation.'
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : 'Comparaison bool' + #$00E9 + 'enne redondante';
      ShortDesc: '`X = True` devrait s''' + #$00E9 + 'crire `X` (et `X <> False` de m' + #$00EA + 'me)';
      FullDesc : 'Comparer un Boolean ' + #$00E0 + ' True/False est verbeux et cr' + #$00E9 +
        'e des bugs subtils (BOOL de la WinAPI : avec une valeur vraie != 1, `X = True` s''' +
        #$00E9 + 'value ' + #$00E0 + ' false). L''expression elle-m' + #$00EA + 'me est d' + #$00E9 +
        'j' + #$00E0 + ' la condition. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:RedundantBoolean. Remarque : les d' + #$00E9 +
        'clarations `const X = True;` sont exclues (affectation l' + #$00E9 +
        'gitime, pas une comparaison).'
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'D' + #$00E9 + 'claration d''interface vide';
      ShortDesc: 'Une interface sans m' + #$00E9 + 'thode ni propri' + #$00E9 + 't' + #$00E9 +
        ' ne porte aucun contrat';
      FullDesc : 'Un corps IFoo = interface end; sans aucune m' + #$00E9 + 'thode ni propri' + #$00E9 + 't' +
        #$00E9 + ' est soit un reste de refactoring, soit une interface marqueur d' + #$00E9 +
        'guis' + #$00E9 + 'e. En Delphi, les interfaces marqueurs se mod' + #$00E9 +
        'lisent mieux sous forme de classes d''attribut. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:EmptyInterface. Non signal' + #$00E9 +
        ' : une interface ayant un anc' + #$00EA + 'tre *nomm' + #$00E9 +
        '* autre que IInterface/IUnknown. Elle h' + #$00E9 + 'rite du contrat de l''anc' + #$00EA +
        'tre et sert de cl' + #$00E9 + ' de requ' + #$00EA +
        'te (Obj as IFileSystemFileSource), de d' + #$00E9 +
        'rivation marqueur (IOTAFormWizard = interface(IOTARepositoryWizard)), de type passerelle ObjC/JNI ou de type d''automation *_TLB.pas - la correction propos' +
        #$00E9 +
        'e par classe d''attribut ne fonctionne pour aucun d''eux, car les attributs sont de la RTTI de compilation et ne peuvent pas ' +
        #$00EA + 'tre interrog' + #$00E9 +
        's via QueryInterface. interface(IUnknown) est toujours signal' + #$00E9 + 'e : elle est s' +
        #$00E9 + 'mantiquement identique ' + #$00E0 + ' interface.'
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert sans message';
      ShortDesc: '`Assert(cond);` - ajouter un message `''pourquoi''` pour le diagnostic';
      FullDesc : '`Assert(cond)` seul ' + #$00E9 + 'choue avec le message g' + #$00E9 + 'n' + #$00E9 +
        'rique ' + #$00AB + ' Assertion failed at $address ' + #$00BB +
        ' - aucune indication sur ce qui ' + #$00E9 + 'tait r' + #$00E9 +
        'ellement attendu. `Assert(cond, ''why'')` ' + #$00E9 + 'pargne des heures de d' + #$00E9 +
        'bogage. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:AssertMessage.'
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'H' + #$00E9 + 'ritage explicite de TObject';
      ShortDesc: '`class(TObject)` est redondant - supprimer les parenth' + #$00E8 + 'ses';
      FullDesc : 'Toute classe h' + #$00E9 +
        'rite implicitement de TObject ; `TFoo = class(TObject)` est identique ' + #$00E0 +
        ' `TFoo = class`. Supprimer la base explicite fait ressortir les vrais changements d''h' +
        #$00E9 + 'ritage dans les diffs. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:ExplicitTObjectInheritance.'
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'D' + #$00E9 + 'claration group' + #$00E9 + 'e de variables, champs ou param' + #$00E8 +
        'tres';
      ShortDesc: 'S' + #$00E9 + 'parer `A, B: Type` en une d' + #$00E9 + 'claration par ligne';
      FullDesc : 'Les d' + #$00E9 + 'clarations group' + #$00E9 +
        'es (`A, B, C: Integer;` pour des variables, des champs ou des param' + #$00E8 +
        'tres) brouillent les diffs (une nouvelle variable modifie une ligne existante), emp' +
        #$00EA +
        'chent les commentaires par variable et compliquent les refactorings de changement de type. Une d' +
        #$00E9 + 'claration par ligne est plus propre. R' + #$00E9 +
        'unit SonarDelphi communitydelphi:GroupedFieldDeclaration / :GroupedVariableDeclaration / :GroupedParameterDeclaration en une seule r' +
        #$00E8 + 'gle (SCA pourra les s' + #$00E9 + 'parer plus tard).'
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Bloc begin..end vide';
      ShortDesc: '`begin..end` vide - le supprimer ou ' + #$00E9 + 'crire l''instruction';
      FullDesc : 'Un `begin..end` vide est presque toujours un reste de refactoring ou un emplacement r' +
        #$00E9 + 'serv' + #$00E9 + ' jamais compl' + #$00E9 + 't' + #$00E9 +
        '. Soit le supprimer, soit impl' + #$00E9 +
        'menter la logique manquante. Les sections d''initialisation `begin end.` au niveau de l''unit' +
        #$00E9 +
        ' sont exclues (c''est la forme d''initialisation vide, pas un reste de refactoring). Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:EmptyBlock.'
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Capture g' + #$00E9 + 'n' + #$00E9 + 'rale sur la classe racine Exception';
      ShortDesc: '`on E: Exception do` avale tout, y compris les violations d''acc' + #$00E8 + 's et l''' +
        #$00E9 + 'puisement m' + #$00E9 + 'moire';
      FullDesc : 'Capturer la classe racine `Exception` capture toutes les erreurs, y compris les erreurs irr' +
        #$00E9 + 'cup' + #$00E9 + 'rables (EAccessViolation, EOutOfMemory, EStackOverflow). Pr' +
        #$00E9 + 'f' + #$00E9 + 'rer un type d''exception sp' + #$00E9 +
        'cifique (EDatabaseError, EFOpenError, EConvertError, ...) afin que des ' + #$00E9 +
        'checs sans rapport ne soient pas occult' + #$00E9 +
        's. Masquer avec `// noinspection` si la capture g' + #$00E9 + 'n' + #$00E9 +
        'rale est voulue (p. ex. fronti' + #$00E8 + 're de journalisation).'
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Sections const/type/var cons' + #$00E9 + 'cutives';
      ShortDesc: 'Deux blocs `const`, `type` ou `var` qui se suivent devraient ' + #$00EA + 'tre fusionn' +
        #$00E9 + 's';
      FullDesc : '`const A = 1; const B = 2;` devrait s''' + #$00E9 +
        'crire `const A = 1; B = 2;` - un seul mot-cl' + #$00E9 + ' de section peut toutes les d' +
        #$00E9 + 'clarer. De m' + #$00EA + 'me pour `type` et `var`. R' + #$00E9 +
        'unit SonarDelphi communitydelphi:ConsecutiveConstSection / :ConsecutiveTypeSection / :ConsecutiveVarSection en une seule r' +
        #$00E8 + 'gle. Le type de section figure dans le message.'
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : 'Exit/Continue redondant avant end';
      ShortDesc: '`Exit;` / `Continue;` juste avant `end` est sans effet';
      FullDesc : 'Si Exit est la derni' + #$00E8 + 're instruction d''une routine, ou Continue la derni' +
        #$00E8 + 're instruction du corps d''une boucle, le flot de contr' + #$00F4 + 'le quitte d' +
        #$00E9 + 'j' + #$00E0 +
        ' le bloc - l''instruction de saut est du code mort. La supprimer pour clarifier l''intention. Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:RedundantJump. Non signal' + #$00E9 +
        ' : (1) un Exit atteint depuis l''int' + #$00E9 +
        'rieur du corps d''une boucle - c''est un retour anticip' + #$00E9 +
        ', et le supprimer laisse la boucle ' + #$00E9 + 'craser le r' + #$00E9 +
        'sultat qu''elle vient de trouver ; une boucle d' + #$00E9 + 'j' + #$00E0 + ' termin' +
        #$00E9 + 'e au m' + #$00EA + 'me niveau (while ... do Inc(Run); Exit;) ne compte pas, ces r' +
        #$00E9 + 'sultats restent donc. (2) Break, quelle que soit sa position - contrairement ' +
        #$00E0 + ' Continue, il supprime les it' + #$00E9 +
        'rations restantes ; suivre l''indication transforme donc les boucles de recherche en parcours complets et les boucles while True en boucles infinies. Break n''est redondant que dans repeat ... Break; until True, qui n''appara' +
        #$00EE + 't nulle part dans le corpus de r' + #$00E9 + 'f' + #$00E9 +
        'rence de 12 000 fichiers.'
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Plusieurs d' + #$00E9 + 'clarations de classe dans un fichier';
      ShortDesc: 'Une classe par unit' + #$00E9 + ' facilite le refactoring';
      FullDesc : 'Lorsqu''une unit' + #$00E9 + ' d' + #$00E9 +
        'clare deux classes publiques ou plus, les retrouver et les d' + #$00E9 +
        'placer entre unit' + #$00E9 + 's est plus difficile que n' + #$00E9 +
        'cessaire. SonarDelphi communitydelphi:ClassPerFile sugg' + #$00E8 + 're la m' + #$00EA +
        'me chose. Les d' + #$00E9 + 'clarations anticip' + #$00E9 +
        'es (`TFoo = class;`) et les types r' + #$00E9 + 'f' + #$00E9 +
        'rence de classe (`TFooClass = class of TFoo`) sont exclus.'
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Point-virgule double';
      ShortDesc: '`;;` - supprimer le point-virgule superflu';
      FullDesc : 'Un double point-virgule (`;;`) signale g' + #$00E9 + 'n' + #$00E9 +
        'ralement une faute de frappe oubli' + #$00E9 + 'e ou un reste de copier-coller ' + #$00E9 +
        'gar' + #$00E9 +
        '. Les compilateurs traitent le second `;` comme une instruction vide ; cela ne casse donc rien, mais ajoute du bruit. Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:SuperfluousSemicolon.'
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Bloc finally vide';
      ShortDesc: '`try ... finally end;` ne lib' + #$00E8 + 're rien - compl' + #$00E9 +
        'ter ou supprimer le finally';
      FullDesc : 'Un bloc `finally` vide est presque toujours un nettoyage oubli' + #$00E9 +
        '. S''il n''y a vraiment rien ' + #$00E0 +
        ' nettoyer, supprimer l''enveloppe `try..finally`. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:EmptyFinallyBlock.'
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : 'Test Assigned + nil redondant';
      ShortDesc: '`Assigned(X) and (X <> nil)` - supprimer le test nil';
      FullDesc : 'Pour les pointeurs et les instances de classe, `Assigned(X)` est s' + #$00E9 +
        'mantiquement identique ' + #$00E0 +
        ' `X <> nil`. Combiner les deux est redondant - le second test ne peut jamais donner un r' +
        #$00E9 + 'sultat diff' + #$00E9 + 'rent. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:AssignedAndAssignedNil.'
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; devrait ' + #$00EA + 'tre FreeAndNil(X)';
      ShortDesc: 'Utiliser `FreeAndNil(X)` au lieu de `X.Free; X := nil;`';
      FullDesc : '`FreeAndNil(X)` est l''idiome Delphi canonique : il fait les deux de mani' + #$00E8 +
        're atomique et ' + #$00E9 + 'vite un pointeur pendant si `X.Free` l' + #$00E8 +
        've une exception (p. ex. ' + #$00E9 +
        'chec du destructeur). La forme manuelle sur deux lignes produit aussi plus de bruit dans les diffs et se laisse plus facilement s' +
        #$00E9 + 'parer lors de refactorings ult' + #$00E9 + 'rieurs. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:FreeAndNil.'
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : #$00C9 + 'viter le modificateur out';
      ShortDesc: 'Pr' + #$00E9 + 'f' + #$00E9 + 'rer `var` ' + #$00E0 + ' `out` (out a une s' + #$00E9 +
        'mantique surprenante)';
      FullDesc : 'Les param' + #$00E8 + 'tres `out` vident les types manag' + #$00E9 +
        's (string/Interface/tableaux dynamiques) ' + #$00E0 + ' l''entr' + #$00E9 + 'e de la m' +
        #$00E9 + 'thode - la valeur de l''appelant est abandonn' + #$00E9 + 'e avant l''ex' + #$00E9 +
        'cution de la m' + #$00E9 + 'thode. Les types record/simples restent non initialis' + #$00E9 +
        's, si bien que lire la valeur entrante est un comportement ind' + #$00E9 +
        'fini. Ces deux effets sont rarement voulus. `var` est le choix par d' + #$00E9 +
        'faut le plus s' + #$00FB + 'r, sauf si la s' + #$00E9 + 'mantique d''interop' + #$00E9 +
        'rabilit' + #$00E9 + ' COM est n' + #$00E9 + 'cessaire. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:AvoidOut.'
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Section de visibilit' + #$00E9 + ' vide dans la classe';
      ShortDesc: 'En-t' + #$00EA + 'te de section `public`/`private`/... sans aucun membre';
      FullDesc : 'Une classe dont un mot-cl' + #$00E9 + ' de visibilit' + #$00E9 + ' est imm' + #$00E9 +
        'diatement suivi d''un autre mot-cl' + #$00E9 + ' de visibilit' + #$00E9 +
        ' (ou de `end`) est g' + #$00E9 + 'n' + #$00E9 +
        'ralement un reste de refactoring - tous les membres de cette section ont ' + #$00E9 + 't' +
        #$00E9 + ' d' + #$00E9 + 'plac' + #$00E9 + 's ailleurs. Supprimer l''en-t' + #$00EA +
        'te vide. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:EmptyVisibilitySection.'
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Initialisation d''unit' + #$00E9 + ' ' + #$00E0 + ' l''ancienne begin..end.';
      ShortDesc: 'Utiliser `initialization..end.` plut' + #$00F4 + 't que l''ancien `begin..end.`';
      FullDesc : 'Avant Delphi 2, les unit' + #$00E9 +
        's marquaient leur bloc d''initialisation avec `begin..end.`. Depuis Delphi 2, la forme idiomatique est `initialization..end.`, qui peut ' +
        #$00EA + 'tre associ' + #$00E9 + 'e ' + #$00E0 +
        ' un bloc `finalization` facultatif pour un nettoyage sym' + #$00E9 + 'trique. Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:LegacyInitializationSection.'
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Champ public dans la classe';
      ShortDesc: 'Un champ public rompt l''encapsulation - utiliser une propri' + #$00E9 + 't' + #$00E9;
      FullDesc : 'Un champ public expose le stockage sous-jacent ; les appelants peuvent le modifier sans que la classe s''en aper' +
        #$00E7 + 'oive. Une propri' + #$00E9 + 't' + #$00E9 + ' laisse ' + #$00E0 +
        ' la classe la possibilit' + #$00E9 +
        ' d''ajouter plus tard une validation/normalisation sans casser les appelants. Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:PublicField.'
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Bloc try imbriqu' + #$00E9;
      ShortDesc: '`try..end` imbriqu' + #$00E9 + ' - extraire le try interne dans une m' + #$00E9 + 'thode';
      FullDesc : 'Imbriquer des blocs try rend le flot de contr' + #$00F4 +
        'le du nettoyage / de la reprise sur erreur plus difficile ' + #$00E0 +
        ' lire. La plupart des cas se d' + #$00E9 + 'm' + #$00EA + 'lent soit en r' + #$00E9 +
        'ordonnant les nettoyages, soit en extrayant le bloc interne dans sa propre m' + #$00E9 +
        'thode. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:NestedTry. Le d' + #$00E9 +
        'tecteur utilise une heuristique de profondeur (comptage des mots-cl' + #$00E9 +
        's `try` vs `end`) et peut produire quelques faux positifs dans du code begin/end fortement imbriqu' +
        #$00E9 + '.'
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Instruction case volumineuse';
      ShortDesc: '`case` avec 10 branches ou plus - envisager le polymorphisme ou une table de dispatch';
      FullDesc : 'Un `case` avec de nombreuses branches cache g' + #$00E9 + 'n' + #$00E9 +
        'ralement un polymorphisme ou un pattern strat' + #$00E9 +
        'gie. Le code serait plus ouvert/ferm' + #$00E9 +
        ' (nouveau comportement = nouvelle classe, pas nouvelle branche) et le fichier plus court si chaque branche devenait sa propre m' +
        #$00E9 + 'thode de classe ou une entr' + #$00E9 + 'e `TDictionary<Key, TProc>`. Correspond ' +
        #$00E0 +
        ' SonarDelphi communitydelphi:CaseStatementSize. Le seuil est configurable via `[Detectors] MaxCaseBranches` et vaut 10 par d' +
        #$00E9 + 'faut. Chaque `case` est mesur' + #$00E9 + ' s' + #$00E9 + 'par' + #$00E9 +
        'ment : seules les ' + #$00E9 + 'tiquettes ' + #$00E0 +
        ' la profondeur de bloc 1 de ce `case` comptent, de sorte que les ' + #$00E9 +
        'tiquettes d''un `case` imbriqu' + #$00E9 +
        ' ne gonflent plus celui qui l''englobe. Une construction imbriqu' + #$00E9 +
        'e peut donc produire plus d''un r' + #$00E9 +
        'sultat - un `case` externe et un interne sont signal' + #$00E9 + 's s' + #$00E9 + 'par' +
        #$00E9 + 'ment d' + #$00E8 + 's que chacun d' + #$00E9 + 'passe le seuil ' + #$00E0 +
        ' lui seul.'
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit' + #$00E9 + ' sans aucune d' + #$00E9 + 'claration';
      ShortDesc: 'L''unit' + #$00E9 +
        ' n''a ni type, ni const, ni var, ni procedure/function - supprimer ou compl' + #$00E9 +
        'ter';
      FullDesc : 'Un fichier `.pas` avec un en-t' + #$00EA + 'te d''unit' + #$00E9 + ' mais sans aucune d' +
        #$00E9 + 'claration est un poids mort. Soit supprimer le fichier, soit compl' + #$00E9 +
        'ter l''emplacement r' + #$00E9 + 'serv' + #$00E9 + '. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:EmptyFile.'
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Plusieurs appels inherited dans une m' + #$00E9 + 'thode';
      ShortDesc: 'Deux `inherited;` ou plus dans la m' + #$00EA + 'me m' + #$00E9 +
        'thode - les effets de bord du parent s''ex' + #$00E9 + 'cutent deux fois';
      FullDesc : 'Chaque invocation de `inherited` ex' + #$00E9 + 'cute l''impl' + #$00E9 +
        'mentation du parent. Deux appels d' + #$00E9 +
        'clenchent les effets de bord (notifications d''' + #$00E9 + 'v' + #$00E9 + 'nement, mises ' +
        #$00E0 + ' jour du compteur de r' + #$00E9 + 'f' + #$00E9 +
        'rences, lignes de journal) deux fois. Presque toujours un bug de copier-coller. Correspond ' +
        #$00E0 + ' SonarDelphi communitydelphi:TwiceInheritedCalls.'
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : 'Doubles parenth' + #$00E8 + 'ses redondantes';
      ShortDesc: '`((Ident))` - supprimer les parenth' + #$00E8 + 'ses int' + #$00E9 + 'rieures';
      FullDesc : 'Des doubles parenth' + #$00E8 + 'ses autour d''un identificateur, d''un litt' + #$00E9 +
        'ral ou d''une expression simple n''apportent rien - une seule paire suffit (souvent aucune). Correspond ' +
        #$00E0 +
        ' SonarDelphi communitydelphi:RedundantParentheses. Seul le cas de l''expression simple est signal' +
        #$00E9 + ' ; un `((A + B))` complexe peut encore tirer profit des parenth' + #$00E8 +
        'ses internes pour la priorit' + #$00E9 + ' et n''est pas signal' + #$00E9 + '.'
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Section de visibilit' + #$00E9 + ' r' + #$00E9 + 'p' + #$00E9 + 't' + #$00E9 + 'e';
      ShortDesc: 'La m' + #$00EA + 'me section `public`/`private`/... appara' + #$00EE +
        't deux fois dans une classe';
      FullDesc : 'Deux sections `private` (ou `public`/`protected`/`published`) dans la m' + #$00EA +
        'me classe, avec des membres entre elles, devraient ' + #$00EA + 'tre fusionn' + #$00E9 +
        'es en une seule. Cela aide les relecteurs ' + #$00E0 + ' saisir d''un coup d''' + #$0153 +
        'il la forme de la classe. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:ConsecutiveVisibilitySection. Remarque : un en-t' + #$00EA +
        'te vide suivi d''un autre en-t' + #$00EA + 'te rel' + #$00E8 + 've de la r' + #$00E8 +
        'gle voisine mais distincte `EmptyVisibilitySection` (SCA087).'
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Constructeur sans appel ' + #$00E0 + ' inherited';
      ShortDesc: 'Il manque `inherited Create` au constructeur - le parent reste non initialis' + #$00E9;
      FullDesc : 'Un constructeur qui n''appelle pas `inherited Create(...)` (ni `inherited;`) saute l''initialisation de la classe parente. Les champs et enregistrements du parent restent ' +
        #$00E0 + ' l''' + #$00E9 + 'tat par d' + #$00E9 + 'faut/nil, ce qui entra' + #$00EE +
        'ne des plantages en aval lorsque des m' + #$00E9 + 'thodes s''attendent ' + #$00E0 +
        ' ce que le parent soit pr' + #$00EA + 't. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:ConstructorWithoutInherited.'
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destructeur sans appel ' + #$00E0 + ' inherited';
      ShortDesc: 'Il manque `inherited Destroy` au destructeur - le nettoyage du parent est saut' + #$00E9 +
        ' (risque de fuite)';
      FullDesc : 'Un destructeur sans `inherited Destroy` (ni `inherited;`) emp' + #$00EA +
        'che la classe parente de lib' + #$00E9 + 'rer ses propres champs, de d' + #$00E9 +
        'sinscrire des gestionnaires et de mettre ' + #$00E0 + ' jour les compteurs de r' + #$00E9 +
        'f' + #$00E9 + 'rences. Presque toujours une fuite. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:DestructorWithoutInherited.'
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : 'Affectation conditionnelle redondante';
      ShortDesc: '`if Cond then X := True else X := False` devrait s''' + #$00E9 + 'crire `X := Cond`';
      FullDesc : 'Deux branches qui affectent True/False ' + #$00E0 + ' la m' + #$00EA +
        'me variable peuvent se r' + #$00E9 + 'duire ' + #$00E0 +
        ' une seule affectation directe (ou `not Cond` si la polarit' + #$00E9 + ' est invers' +
        #$00E9 + 'e). Plus court, plus rapide, et plus directement fid' + #$00E8 + 'le ' + #$00E0 +
        ' l''expression bool' + #$00E9 + 'enne. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:RedundantConditional.'
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'begin/end asym' + #$00E9 + 'trique dans if/else';
      ShortDesc: 'La branche then utilise `begin..end` mais la branche else est une instruction unique';
      FullDesc : 'Lorsque la branche then utilise `begin..end`, la branche else devrait faire de m' + #$00EA +
        'me (ou les deux devraient s''en passer). La forme mixte (`end else DoStuff;`) laisse un futur lecteur incertain : d''autres instructions appartenaient-elles ' +
        #$00E0 + ' la branche else et ont-elles ' + #$00E9 + 't' + #$00E9 + ' oubli' + #$00E9 +
        'es ? `else if` (cha' + #$00EE + 'ne else-if) et `else begin` sont explicitement autoris' +
        #$00E9 + 's. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:IfElseBegin.'
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Alias de type pointeur sans pr' + #$00E9 + 'fixe P';
      ShortDesc: '`Foo = ^Bar` devrait s''' + #$00E9 + 'crire `PBar = ^Bar` (convention du pr' + #$00E9 +
        'fixe P)';
      FullDesc : 'Convention Delphi depuis le premier jour : un alias de pointeur sur `TXxx` se nomme `PXxx`. Le pr' +
        #$00E9 + 'fixe `P` rend l''indirection visible au site d''appel. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:PointerName. Le framework de nommage rendra plus tard le pr' +
        #$00E9 + 'fixe configurable.'
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Branche sans bloc begin..end';
      ShortDesc: '`then`/`else`/`do <instruction>` - pr' + #$00E9 + 'f' + #$00E9 +
        'rer un `begin..end` explicite';
      FullDesc : 'Une branche ' + #$00E0 + ' instruction unique sans `begin..end` est facile ' + #$00E0 +
        ' mal lire ; ajouter plus tard une deuxi' + #$00E8 + 'me instruction sans recr' + #$00E9 +
        'er de bloc est une source classique de bugs o' + #$00F9 + ' l''indentation contredit la s' +
        #$00E9 + 'mantique. R' + #$00E8 + 'gle de style d' + #$00E9 +
        'battue (de nombreuses bases de code Delphi utilisent d' + #$00E9 + 'lib' + #$00E9 + 'r' +
        #$00E9 + 'ment la forme compacte) - lsHint, facile ' + #$00E0 + ' d' + #$00E9 +
        'sactiver dans les profils. La cha' + #$00EE +
        'ne `else if`, `raise`/`exit`/`break`/`continue` et les autres instructions ouvrant un bloc sont explicitement autoris' +
        #$00E9 + 'es. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:BeginEndRequired.'
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Routine imbriqu' + #$00E9 + 'e dans une m' + #$00E9 + 'thode';
      ShortDesc: 'Proc' + #$00E9 + 'dure ou fonction locale imbriqu' + #$00E9 + 'e - ' + #$00E0 +
        ' extraire au niveau de l''unit' + #$00E9;
      FullDesc : 'Les routines imbriqu' + #$00E9 + 'es (une `procedure`/`function` d' + #$00E9 + 'clar' +
        #$00E9 + 'e dans la section de d' + #$00E9 +
        'clarations locales d''une autre routine) sont syntaxiquement autoris' + #$00E9 +
        'es mais nuisent aux tests et ' + #$00E0 + ' la r' + #$00E9 +
        'utilisation : la routine interne ne peut ' + #$00EA + 'tre ni test' + #$00E9 +
        'e unitairement ni r' + #$00E9 + 'utilis' + #$00E9 + 'e ailleurs. Le Delphi moderne pr' +
        #$00E9 + 'f' + #$00E8 + 're les m' + #$00E9 +
        'thodes anonymes (lambdas) pour les rares cas o' + #$00F9 + ' l''imbrication ' + #$00E9 +
        'tait r' + #$00E9 + 'ellement n' + #$00E9 + 'cessaire. Les m' + #$00E9 +
        'thodes anonymes ne sont PAS signal' + #$00E9 +
        'es (elles n''ont pas de nom dans l''AST). Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:NestedRoutines.'
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Champ de classe sans pr' + #$00E9 + 'fixe F';
      ShortDesc: 'Les champs de classe doivent suivre la convention `F<Nom>`';
      FullDesc : 'Convention Delphi : les champs d''instance de classe se nomment `FFoo`, afin que le lecteur sache imm' +
        #$00E9 +
        'diatement qu''il s''agit d''un membre de la classe (et non d''une variable locale ou d''un param' +
        #$00E8 + 'tre). Le pr' + #$00E9 + 'fixe `F` ' + #$00E9 +
        'vite les conflits de noms avec les propri' + #$00E9 + 't' + #$00E9 +
        's publiques (le champ `FFoo` avec la propri' + #$00E9 + 't' + #$00E9 +
        ' `Foo` forme la paire canonique). Seules les d' + #$00E9 +
        'clarations de champs `private` et `protected` sont v' + #$00E9 + 'rifi' + #$00E9 +
        'es - les champs public/published sont de toute fa' + #$00E7 +
        'on couverts par `PublicField` (SCA089). Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:FieldName.'
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Type classe ou record sans pr' + #$00E9 + 'fixe T';
      ShortDesc: 'Les alias de type classe et record doivent commencer par `T`';
      FullDesc : 'Convention Delphi : types classe `TXxx`, records `TXxx` ou `RXxx`, interfaces `IXxx`, pointeurs `PXxx` (SCA100), exceptions `EXxx`. Ce d' +
        #$00E9 + 'tecteur ne couvre que le sous-ensemble classe/record. Les d' + #$00E9 +
        'clarations anticip' + #$00E9 + 'es (`TFoo = class;`), les r' + #$00E9 + 'f' + #$00E9 +
        'rences `class of` (`TFooClass = class of TFoo`) et la syntaxe g' + #$00E9 + 'n' + #$00E9 +
        'rique sont prises en charge. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:TypeName.'
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Type interface sans pr' + #$00E9 + 'fixe I';
      ShortDesc: 'Les alias d''interface doivent commencer par `I` (`IFoo = interface`)';
      FullDesc : 'Convention Delphi : les interfaces s''appellent `IXxx`, ' + #$00E0 +
        ' l''image de `TXxx` pour les classes et `PXxx` pour les pointeurs. Le pr' + #$00E9 +
        'fixe `I` distingue le contrat de l''impl' + #$00E9 + 'mentation ' + #$00E0 +
        ' chaque site d''appel. Couvre aussi `dispinterface`. Correspond ' + #$00E0 +
        ' SonarDelphi communitydelphi:InterfaceName.'
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'M' + #$00E9 + 'thode pas en PascalCase';
      ShortDesc: 'Les m' + #$00E9 + 'thodes doivent commencer par une majuscule (PascalCase)';
      FullDesc : 'La convention Delphi est le PascalCase (UpperCamel) pour les routines et les m' + #$00E9 +
        'thodes : `DoSomething`, pas `doSomething` ni `do_something`. Les surcharges d''op' + #$00E9 +
        'rateurs et les identificateurs commen' + #$00E7 + 'ant par `_` sont exempt' + #$00E9 +
        's. Correspond ' + #$00E0 + ' SonarDelphi communitydelphi:MethodName. Bas' + #$00E9 +
        ' sur l''AST : v' + #$00E9 + 'rifie `nkMethod.Name` (un nom qualifi' + #$00E9 +
        ' `TFoo.bar` est coup' + #$00E9 +
        ' au point). Exemptions pour tout le fichier : imports de biblioth' + #$00E8 +
        'ques de types g' + #$00E9 + 'n' + #$00E9 + 'r' + #$00E9 + 's (*_TLB.pas) et unit' + #$00E9 +
        's d' + #$00E9 + 'clarant des classes FPC en langage ' + #$00E9 +
        'tranger (objcclass/objccategory/cppclass) - leurs noms de m' + #$00E9 + 'thodes SONT les s' +
        #$00E9 + 'lecteurs/symboles de l''API ' + #$00E9 + 'trang' + #$00E8 +
        're ; les routines `external`, les m' + #$00E9 +
        'thodes de type `cdecl` et les types de liaison FFI (ancres d''import JNI/ObjC) sont exempt' +
        #$00E9 + 's m' + #$00E9 + 'thode par m' + #$00E9 + 'thode.'
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre strict private';
      ShortDesc: 'Le membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + ' QUE par des m' +
        #$00E9 +
        'thodes de sa propre classe - `strict private` atteint l''encapsulation la plus forte';
      FullDesc : 'Analyse d''un seul fichier : chaque appelant visible du membre `public` est lui-m' + #$00EA +
        'me une m' + #$00E9 + 'thode de la M' + #$00CA + 'ME classe (aucune classe s' + #$0153 +
        'ur, aucune proc' + #$00E9 + 'dure de niveau sup' + #$00E9 +
        'rieur, aucune sous-classe dans cette unit' + #$00E9 + '). `strict private` (D2007+, port' +
        #$00E9 + 'e de classe, pas d''unit' + #$00E9 + ') est la visibilit' + #$00E9 +
        ' correcte la plus restrictive. M' + #$00EA + 'me r' + #$00E9 + 'serve li' + #$00E9 + 'e ' +
        #$00E0 +
        ' l''analyse d''un seul fichier que pour CanBeUnitPrivate : les consommateurs d''autres unit' +
        #$00E9 +
        's sont invisibles et le compilateur garantit la correction via E2361 si le changement casse quelque chose. Exclusions : published, virtual/abstract/override/dynamic, constructeurs/destructeurs de classe, bases pilot' +
        #$00E9 + 'es par RTTI (TForm/TFrame/TDataModule/TComponent), classes utilitaires compos' +
        #$00E9 + 'es uniquement de m' + #$00E9 +
        'thodes de classe. Masquer ligne par ligne avec `// noinspection CanBeStrictPrivate` pour une surface publique intentionnelle.'
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize depuis le destructeur';
      ShortDesc: 'Synchronize() appel' + #$00E9 + ' depuis le destructeur Destroy - un thread qui se lib' +
        #$00E8 + 're lui-m' + #$00EA + 'me y reste bloqu' + #$00E9 + ' jusqu''' + #$00E0 +
        ' ce que le thread principal ex' + #$00E9 + 'cute l''appel, et se fige s''il ne le fait pas';
      FullDesc : 'TThread.Synchronize() dans le corps d''un destructeur est fragile. Quand le destructeur s''ex' +
        #$00E9 + 'cute dans le thread principal, Synchronize appelle simplement la m' + #$00E9 +
        'thode directement. Quand il s''ex' + #$00E9 + 'cute dans le thread de travail lui-m' +
        #$00EA + 'me - le cas habituel avec FreeOnTerminate := True, o' + #$00F9 +
        ' le thread se lib' + #$00E8 + 're lui-m' + #$00EA + 'me apr' + #$00E8 +
        's Execute - Synchronize bloque le thread de travail jusqu''' + #$00E0 +
        ' ce que le thread principal traite l''appel. Si le thread principal ne traite pas les demandes de synchronisation ' +
        #$00E0 + ' ce moment-l' + #$00E0 +
        ' (par exemple parce qu''il attend le thread avec WaitForSingleObject au lieu de TThread.WaitFor, ou parce que l''application est en cours de fermeture), les deux threads s''attendent mutuellement et le processus se fige. Pendant la fermeture, les objets' +
        ' que l''appel touche peuvent aussi avoir d' + #$00E9 + 'j' + #$00E0 + ' disparu. D' +
        #$00E9 + 'placer la notification dans un gestionnaire OnTerminate (il s''ex' + #$00E9 +
        'cute dans le thread principal avant la lib' + #$00E9 + 'ration de l''objet thread) ou ' +
        #$00E0 + ' la fin de Execute. Bas' + #$00E9 +
        ' sur l''AST : parcourt chaque nkMethod dont le nom se termine par ''.Destroy'' (ou dont le TypeRef porte le marqueur ''destructor'') et signale les nkCall vers ''Synchronize'' / ''<obj>.Synchronize''.'
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Verrou pris sans lib' + #$00E9 + 'ration par try/finally';
      ShortDesc: 'TCriticalSection, Monitor ou verrou WinAPI pris sans try..finally englobant - une exception laisse le verrou pos' +
        #$00E9;
      FullDesc : 'Prendre un verrou (TCriticalSection.Enter / .Acquire, TMonitor.Enter, TMultiReadExclusiveWriteSynchronizer.BeginWrite, EnterCriticalSection de WinAPI) sans le faire suivre imm' +
        #$00E9 +
        'diatement d''un try..finally contenant le Leave / Release / EndWrite correspondant est l''un des bugs de threading Delphi les plus courants : toute exception entre la prise et la lib' +
        #$00E9 + 'ration laisse le verrou pos' + #$00E9 + ' d' + #$00E9 +
        'finitivement, ce qui provoque un interblocage pour chaque appelant suivant. D' + #$00E9 +
        'tection lexicale : reconna' + #$00EE + 't les motifs de prise et v' + #$00E9 +
        'rifie si l''instruction qui suit le `;` est `try`. Masquer avec `// noinspection LockWithoutTryFinally` pour les s' +
        #$00E9 + 'quences volontairement non prot' + #$00E9 + 'g' + #$00E9 + 'es (rare ; signifie g' +
        #$00E9 + 'n' + #$00E9 + 'ralement que l''appel suivant ne l' + #$00E8 + 'vera de toute fa' +
        #$00E7 + 'on jamais d''exception).'
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'Concat' + #$00E9 + 'nation de cha' + #$00EE + 'ne dans une boucle';
      ShortDesc: '`s := s + x` dans for/while/repeat - r' + #$00E9 + 'allocations quadratiques';
      FullDesc : 'Chaque `s := s + x` dans le corps d''une boucle alloue une NOUVELLE cha' + #$00EE +
        'ne de longueur length(s)+length(x) et y copie les deux morceaux. Sur N it' + #$00E9 +
        'rations, cela fait O(N^2) copies d''octets et une pression sur le tas. Deux alternatives idiomatiques en Delphi : (1) construire dans un TStringBuilder et appeler ToString une seule fois ' +
        #$00E0 +
        ' la fin, (2) collecter les morceaux dans une TStringList et lire .Text une seule fois. Heuristique du d' +
        #$00E9 + 'tecteur : correspondance lexicale sur le motif LHS == premier op' + #$00E9 +
        'rande RHS (insensible ' + #$00E0 +
        ' la casse) dans tout bloc for/while/repeat. Faux positifs possibles si `s` est volontairement r' +
        #$00E9 + 'utilis' + #$00E9 + ' comme accumulateur dans de courtes boucles ' + #$00E0 + ' tr' +
        #$00E8 + 's petites charges ; masquer avec `// noinspection StringConcatInLoop`.'
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) appel' + #$00E9 + ' dans une boucle';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` dans une boucle - recherche lin' + #$00E9 + 'aire ' +
        #$00E0 + ' chaque it' + #$00E9 + 'ration';
      FullDesc : 'ParamByName parcourt la collection TParam par comparaison de cha' + #$00EE + 'nes ' +
        #$00E0 + ' chaque appel (lin' + #$00E9 + 'aire en nombre de param' + #$00E8 +
        'tres). Dans un chemin critique / une boucle, un ParamByName par Query.Execute devient N par Execute. Mettre en cache la r' +
        #$00E9 + 'f' + #$00E9 + 'rence TParam une fois hors de la boucle, ou utiliser la propri' +
        #$00E9 + 't' + #$00E9 + ' index' + #$00E9 + 'e par entier Params[i] si la position du param' +
        #$00E8 + 'tre est connue.'
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) appel' + #$00E9 + ' dans une boucle';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` dans une boucle - recherche lin' + #$00E9 + 'aire ' +
        #$00E0 + ' chaque enregistrement';
      FullDesc : 'FieldByName parcourt la collection TFields par comparaison de cha' + #$00EE + 'nes ' +
        #$00E0 + ' chaque appel. Dans une boucle d''it' + #$00E9 +
        'ration sur un DataSet, une recherche par champ devient N recherches par .Next, parfois par enregistrement fois N champs = O(N*M). Mettre en cache la r' +
        #$00E9 + 'f' + #$00E9 + 'rence TField une fois avant la boucle et la lire/' + #$00E9 +
        'crire directement. M' + #$00EA +
        'me correction que SCA111 (ParamByName) - seule la collection diff' + #$00E8 + 're.'
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume est obsol' + #$00E8 + 'te';
      ShortDesc: '`MyThread.Resume` - utiliser `MyThread.Start` (depuis Delphi 2010)';
      FullDesc : 'TThread.Resume est obsol' + #$00E8 +
        'te depuis Delphi 2010 au profit de TThread.Start (suspension ' + #$00E0 + ' la cr' + #$00E9 +
        'ation + reprise au d' + #$00E9 +
        'marrage sont devenues un seul appel Start explicite). Le compilateur ' + #$00E9 +
        'met un avertissement d''obsolescence, mais il passe facilement inaper' + #$00E7 +
        'u dans les grandes bases de code. Deux corrections : (a) appeler .Start au lieu de .Resume, (b) construire avec CreateSuspended := False et omettre enti' +
        #$00E8 + 'rement l''' + #$00E9 + 'tape Resume/Start. Le d' + #$00E9 +
        'tecteur signale les appels `<ident>.Resume`. Quand le type du receveur est visible dans le m' +
        #$00EA + 'me fichier (`X: TFoo` ou `X := TFoo.Create`), il doit ' + #$00EA +
        'tre TThread, se terminer par `Thread` ou d' + #$00E9 +
        'river de TThread dans ce fichier - les autres types (timers, animations, TProcess) sont ignor' +
        #$00E9 + 's. Un receveur non r' + #$00E9 + 'solu est signal' + #$00E9 +
        ', sauf pour une cha' + #$00EE + 'ne point' + #$00E9 +
        'e ou une variable inline dont le nom ou l''initialiseur ne mentionne pas ''thread''. Si un receveur signal' +
        #$00E9 +
        ' n''est pas un TThread, masquer ligne par ligne avec `// noinspection ThreadResumeDeprecated`.'
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread lib' + #$00E9 + 'r' + #$00E9 + ' par FreeAndNil - v' + #$00E9 + 'rifier l''arr' +
        #$00EA + 't';
      ShortDesc: '`FreeAndNil(MyThread)` sans `Terminate` ' + #$00E0 + ' proximit' + #$00E9 +
        ' - une indication ' + #$00E0 + ' v' + #$00E9 + 'rifier, pas un d' + #$00E9 + 'faut prouv' +
        #$00E9 + ' : `TThread.Destroy` arr' + #$00EA + 'te lui-m' + #$00EA + 'me le thread ; v' +
        #$00E9 + 'rifier `Execute`, le destructeur du thread et `FreeOnTerminate`';
      FullDesc : 'Indication ' + #$00E0 + ' v' + #$00E9 + 'rifier, pas un d' + #$00E9 + 'faut prouv' + #$00E9 +
        '. `TThread.Destroy` arr' + #$00EA + 'te lui-m' + #$00EA +
        'me le thread : il appelle `Terminate`, reprend un thread suspendu et attend que `Execute` soit termin' +
        #$00E9 + ', donc `FreeAndNil(MyThread)` seul est s' + #$00FB + 'r. V' + #$00E9 +
        'rifier trois choses ' + #$00E0 + ' la ligne signal' + #$00E9 +
        'e. `Execute` respecte-t-il `Terminated` ? Sinon, le destructeur attend que `Execute` se termine de lui-m' +
        #$00EA + 'me. Un destructeur de la classe du thread lib' + #$00E8 +
        're-t-il des champs qu''`Execute` utilise seulement apr' + #$00E8 +
        's `inherited` ? Son corps s''ex' + #$00E9 + 'cute avant que `TThread.Destroy` arr' + #$00EA +
        'te le thread. `FreeOnTerminate` est-il positionn' + #$00E9 + ' ? Un tel thread se lib' +
        #$00E8 + 're lui-m' + #$00EA + 'me ' + #$00E0 + ' la fin d''`Execute`, il ne doit donc pas ' +
        #$00EA + 'tre lib' + #$00E9 + 'r' + #$00E9 + ' aussi de l''ext' + #$00E9 +
        'rieur. Un `WaitFor` suppl' + #$00E9 +
        'mentaire n''apporte rien : il ne revient pas pour un thread cr' + #$00E9 + #$00E9 +
        ' suspendu et jamais d' + #$00E9 + 'marr' + #$00E9 +
        '. Heuristique : signale `FreeAndNil(<id>)` quand `<id>` a un type thread (le type d' +
        #$00E9 + 'clar' + #$00E9 + ' ou construit se termine par `Thread` ou d' + #$00E9 +
        'rive de TThread dans le m' + #$00EA + 'me fichier ; si aucun type n''est r' + #$00E9 +
        'solu, l''identificateur contient `thread`) et que les ~500 caract' + #$00E8 + 'res pr' +
        #$00E9 + 'c' + #$00E9 +
        'dents (environ 10 lignes) ne contiennent ni `<id>.Terminate` ni `<id>.WaitFor`. Aucun r' +
        #$00E9 + 'sultat apr' + #$00E8 +
        's `TerminateThread(<id>`, sous une garde positive `if <id>.Finished`, ou quand un `Execute` de la classe du thread dans la m' +
        #$00EA + 'me unit' + #$00E9 + ' r' + #$00E9 + 'f' + #$00E9 +
        'rence `Terminated`. La forme simple `.Free` n''est pas v' + #$00E9 + 'rifi' + #$00E9 +
        'e, et le d' + #$00E9 + 'tecteur ne s''ex' + #$00E9 +
        'cute que sur les fichiers qui mentionnent `TThread`, `.Synchronize`, `.Resume`, `.Queue`, `ParamByName` ou `FieldByName`. Masquer avec `// noinspection TThreadDestroyWithoutTerminate` pour les classes qui ne sont pas des threads.'
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'URL HTTP en clair';
      ShortDesc: 'Litt' + #$00E9 + 'ral `''http://...''` pour un point d''acc' + #$00E8 + 's distant - vuln' +
        #$00E9 + 'rable ' + #$00E0 + ' l''interception';
      FullDesc : 'Un litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne commen' + #$00E7 +
        'ant par `http://` pour tout point d''acc' + #$00E8 +
        's autre que localhost transmet sa charge utile sans chiffrement. Identifiants de connexion, jetons de session et donn' +
        #$00E9 + 'es personnelles circulent en clair et peuvent ' + #$00EA + 'tre intercept' +
        #$00E9 + 's ou modifi' + #$00E9 + 's par tout acteur r' + #$00E9 +
        'seau actif. La correction ne co' + #$00FB + 'te pratiquement rien : passer le sch' + #$00E9 +
        'ma ' + #$00E0 +
        ' `https://` (presque tous les services modernes prennent en charge les deux). Le d' +
        #$00E9 + 'tecteur extrait l''h' + #$00F4 + 'te du litt' + #$00E9 +
        'ral (userinfo, port et crochets IPv6 retir' + #$00E9 + 's) et reste muet quand cet h' +
        #$00F4 + 'te ne peut pas ' + #$00EA + 'tre un point d''acc' + #$00E8 +
        's joignable : bouclage et IPC locale (`localhost`, `127.x.x.x`, `[::1]`, `0.0.0.0`, `host.docker.internal`, la forme de socket `http://unix:` de mORMot) ainsi que les plages r' +
        #$00E9 + 'serv' + #$00E9 + 'es ' + #$00E0 +
        ' la documentation et aux tests (RFC 2606 `example.com/.net/.org`, `.example`, `.test`, `.invalid` ; RFC 5737 `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` ; RFC 3849 `2001:db8::/32` ; et les plages lien-local `169.254.0.0/16` et `fe80::/10`, qu' +
        'i ne sont pas des plages de documentation mais n''apparaissent dans les litt' + #$00E9 +
        'raux du code source que comme fixtures de parseur ou exemples de diagnostic - un vrai d' +
        #$00E9 + 'ploiement sur `fe80::` exige un index de zone, et `169.254.x` n''appara' + #$00EE +
        't que lorsque DHCP a ' + #$00E9 + 'chou' + #$00E9 + '). Les plages LAN priv' + #$00E9 +
        'es (RFC 1918) ne sont d' + #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + 'ment PAS ignor' +
        #$00E9 + 'es - un appel REST `http://192.168.x.y` est un vrai point d''acc' + #$00E8 +
        's en clair. Les URI d''espaces de noms XML (`xmlns=`, `schemas`, `w3.org`, ...) sont des identit' +
        #$00E9 + 's, pas des cibles r' + #$00E9 + 'seau, et sont ' + #$00E9 + 'galement ignor' +
        #$00E9 + 'es.'
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'V' + #$00E9 + 'rification TLS d' + #$00E9 + 'sactiv' + #$00E9 + 'e';
      ShortDesc: '`SecureProtocols` vide, `IgnoreCertificateErrors := True` ou `OnVerifyPeer := nil`';
      FullDesc : 'Trois motifs Delphi d' + #$00E9 +
        'sactivent silencieusement la validation TLS : (a) `SecureProtocols := []` retire tous les protocoles, ce qui permet un repli vers le texte en clair ou le protocole le plus faible disponible, (b) `IgnoreCertificateErrors := True` accepte n''importe que' +
        'l certificat, y compris expir' + #$00E9 + ' ou auto-sign' + #$00E9 +
        ', (c) `OnVerifyPeer := nil` court-circuite le callback de v' + #$00E9 +
        'rification. Tous trois sont des cibles de choix pour une attaque MITM. Remplacer par des protocoles explicitement modernes uniquement (`[TLSv1_2, TLSv1_3]`), un vrai magasin de confiance, ou un gestionnaire OnVerifyPeer qui ' +
        #$00E9 + 'pingle l''empreinte. Le d' + #$00E9 + 'tecteur reconna' + #$00EE +
        't lexicalement les trois motifs d''affectation de propri' + #$00E9 + 't' + #$00E9 + '.'
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Membre public sans commentaire de documentation';
      ShortDesc: 'M' + #$00E9 + 'thode ou propri' + #$00E9 + 't' + #$00E9 +
        ' publique dans la section `interface` sans commentaire de documentation juste au-dessus';
      FullDesc : 'Un membre public dans la section `interface` d''une unit' + #$00E9 +
        ' fait partie de la surface d''API document' + #$00E9 + 'e que consomment les autres unit' +
        #$00E9 + 's. Sans commentaires de documentation, l''unit' + #$00E9 + ' est plus difficile ' +
        #$00E0 + ' utiliser sans lire l''impl' + #$00E9 + 'mentation. Le d' + #$00E9 +
        'tecteur accepte au choix : un XMLDoc `///`, un bloc `{ ... }`, un bloc `(* ... *)`, ou un ou plusieurs commentaires `//` d''une ligne directement au-dessus de la d' +
        #$00E9 +
        'claration. Exclusions : constructeurs `Create` / destructeurs `Destroy` (explicites par convention), membres commen' +
        #$00E7 + 'ant par `_` (marqueur de priv' + #$00E9 +
        ' dans les sections publiques), membres `published` (pilot' + #$00E9 +
        's par DFM/RTTI, la doc serait du bruit). Masquage : `// noinspection PublicMemberWithoutDoc` par d' +
        #$00E9 + 'claration.'
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Classe d''exception sans pr' + #$00E9 + 'fixe `E`';
      ShortDesc: 'Un descendant de `class(Exception)` doit suivre la convention `E<Nom>` de la RTL Delphi';
      FullDesc : 'La convention de la RTL Delphi est sans ambigu' + #$00EF + 't' + #$00E9 +
        ' : les classes d''exception commencent par `E` (EAbort, EConvertError, EAccessViolation). Les classes d''exception d' +
        #$00E9 + 'finies par l''utilisateur qui omettent le pr' + #$00E9 +
        'fixe rompent la convention et obscurcissent la nature de la classe au site d''appel (`raise MyError.Create(...)` vs `raise EMyError.Create(...)`). Le d' +
        #$00E9 + 'tecteur reconna' + #$00EE + 't toute classe dont le TypeRef h' + #$00E9 +
        'rite d''une classe Exception connue (Exception, EAbort, EAccessViolation, EExternal) et dont le nom ne commence pas par `E<UpperCase>`.'
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Constante locale pas en UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` dans une m' + #$00E9 + 'thode - pr' + #$00E9 + 'f' + #$00E9 +
        'rer UPPER_SNAKE_CASE pour les constantes num' + #$00E9 + 'riques';
      FullDesc : 'Les constantes locales num' + #$00E9 + 'riques/enti' + #$00E8 +
        'res dans le corps d''une m' + #$00E9 + 'thode gagnent ' + #$00E0 + ' ' + #$00EA +
        'tre en UPPER_SNAKE_CASE (`MAX_RETRIES`, `BUFFER_SIZE`, `DEFAULT_TIMEOUT`) - le lecteur voit imm' +
        #$00E9 +
        'diatement que l''identificateur est une constante et non une variable, et la convention rejoint celle de C / Java / Python, si bien que les lecteurs venant d''autres langages ne tr' +
        #$00E9 + 'buchent pas. Exclusions du d' + #$00E9 + 'tecteur : noms tr' + #$00E8 +
        's courts (<=2 caract' + #$00E8 + 'res, en g' + #$00E9 + 'n' + #$00E9 +
        'ral compteurs de boucle ou temporaires), constantes de type cha' + #$00EE + 'ne/caract' +
        #$00E8 + 're (souvent des libell' + #$00E9 +
        's d''interface pour lesquels le PascalCase convient). Masquer avec `// noinspection LocalConstantName` pour les constantes locales l' +
        #$00E9 + 'gitimement en PascalCase.'
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception construite mais jamais lev' + #$00E9 + 'e';
      ShortDesc: '`EFoo.Create(''msg'');` alloue un objet exception sans `raise` - le chemin d''erreur est saut' +
        #$00E9 + ' silencieusement';
      FullDesc : 'Le motif `EConvertError.Create(''bad input'');` sans `raise` devant construit une instance d''exception, ne la l' +
        #$00E8 + 've pas, et le code appelant continue comme si de rien n''' + #$00E9 +
        'tait. L''objet allou' + #$00E9 + ' fuit (TObject classique) ou est imm' + #$00E9 +
        'diatement collect' + #$00E9 + ' (ARC), et la branche d''erreur pr' + #$00E9 + 'vue dispara' +
        #$00EE + 't. Il s''agit presque toujours d''une r' + #$00E9 + 'gression de copier-coller ' +
        #$00E0 + ' partir de `raise EConvertError.Create(...)` o' + #$00F9 + ' le mot-cl' + #$00E9 +
        ' `raise` a ' + #$00E9 + 't' + #$00E9 + ' supprim' + #$00E9 + '. Heuristique du d' + #$00E9 +
        'tecteur : tout `nkCall` nomm' + #$00E9 + ' `<Ident>.Create(...)` o' + #$00F9 +
        ' `<Ident>` est `Exception` ou suit la convention Delphi du pr' + #$00E9 +
        'fixe `E` (`E` + lettre majuscule, p. ex. `EConvertError`, `EMyDomainError`). `raise X.Create(...)` est consomm' +
        #$00E9 + ' comme cha' + #$00EE +
        'ne par le parseur de l''instruction raise et ne produit jamais de `nkCall`, si bien que les exceptions r' +
        #$00E9 + 'ellement lev' + #$00E9 + 'es ne sont pas des faux positifs. Correspond ' + #$00E0 +
        ' `MissingRaiseCheck` de Sonar-Delphi.'
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'La fonction n''affecte jamais Result';
      ShortDesc: 'Le corps de la fonction se termine sans ' + #$00E9 +
        'crire `Result` (ni `<NomFonction> := ...`) - la valeur de retour est ind' + #$00E9 +
        'finie';
      FullDesc : 'Une fonction qui atteint son `end;` sans aucun `Result := ...` ni `<FunctionName> := ...` ' +
        #$00E0 + ' la mani' + #$00E8 + 're Pascal renvoie les r' + #$00E9 +
        'sidus de registre/pile qui occupent par hasard l''emplacement du r' + #$00E9 +
        'sultat. Dans les builds Release, l''appelant re' + #$00E7 +
        'oit donc la valeur du dernier appel de m' + #$00EA +
        'me taille - un Heisenbug classique qui change selon le niveau d''optimisation. Le d' +
        #$00E9 +
        'tecteur est volontairement prudent : il ignore les fonctions qui contiennent un `Exit` quelconque (peut ' +
        #$00EA + 'tre `Exit(value)`) ou un `raise` (la fonction l' + #$00E8 + 've peut-' + #$00EA +
        'tre syst' + #$00E9 +
        'matiquement). Remarque : le parseur enregistre bien l''argument de `Exit(value)`, cette exclusion est donc plus grossi' +
        #$00E8 + 're que strictement n' + #$00E9 + 'cessaire - la resserrer ajouterait des r' +
        #$00E9 + 'sultats et attend donc une analyse mesur' + #$00E9 + 'e du corpus. Les proc' +
        #$00E9 + 'dures, les d' + #$00E9 + 'clarations abstract/forward/external et les d' + #$00E9 +
        'clarations uniquement DispatchID sont aussi ignor' + #$00E9 +
        'es. Une couverture partielle (Result affect' + #$00E9 +
        ' dans une seule branche) est actuellement un faux n' + #$00E9 +
        'gatif en attendant l''analyse CFG. Correspond ' + #$00E0 +
        ' `RoutineResultAssignedCheck` de Sonar-Delphi.'
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Relance de la variable d''exception li' + #$00E9 + 'e';
      ShortDesc: '`on E: T do ... raise E;` perd la pile d''appels d''origine - le `raise;` nu la conserve';
      FullDesc : '`raise E` dans un gestionnaire `on E: SomeException do ...` d' + #$00E9 +
        'marre une nouvelle propagation d''exception enracin' + #$00E9 +
        'e au site de la relance. La pile d''appels d''origine - le chemin depuis l''endroit o' +
        #$00F9 + ' l''exception a ' + #$00E9 + 't' + #$00E9 + ' lev' + #$00E9 + 'e la premi' +
        #$00E8 + 're fois, ' + #$00E0 + ' travers chaque routine appel' + #$00E9 + 'e, jusqu''' +
        #$00E0 + ' ce bloc `except` - est perdue. Les rapports de plantage et les vues du d' +
        #$00E9 + 'bogueur pointent alors vers le gestionnaire, et non vers l''emplacement r' +
        #$00E9 + 'el de la faute, ce qui rend le tri consid' + #$00E9 +
        'rablement plus difficile. L''intention du d' + #$00E9 + 'veloppeur ' + #$00E9 +
        'tait presque certainement `raise;` (sans argument), qui continue de propager l''objet exception *courant* avec sa trace intacte. Le d' +
        #$00E9 + 'tecteur parcourt chaque `nkOnHandler` ayant un nom de variable li' + #$00E9 +
        'e non vide et signale chaque `nkRaise` de ce sous-arbre dont l''argument est exactement cette variable (insensible ' +
        #$00E0 + ' la casse). `raise;` (sans argument) est correct et n''est pas signal' + #$00E9 +
        ' ; `raise EWrapper.Create(...)` est ' + #$00E9 + 'galement accept' + #$00E9 +
        ' (encapsulation d' + #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + 'e). Correspond ' + #$00E0 +
        ' `ReRaiseExceptionCheck` de Sonar-Delphi.'
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Transtypage juste avant Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - le transtypage ne change pas quel Destroy s''ex' + #$00E9 +
        'cute (Destroy est virtuel)';
      FullDesc : #$00C9 +
        'crire `TStringList(L).Free` ou `TObject(L).Destroy` est un signe de confusion. `TObject.Free` est une enveloppe non virtuelle autour du `Destroy` *virtuel* : la r' +
        #$00E9 + 'partition virtuelle passe donc par le type d''ex' + #$00E9 +
        'cution de `L`, pas par le type statique du transtypage. Que l''on ' + #$00E9 +
        'crive `L.Free` ou `T(L).Free`, la m' + #$00EA + 'me cha' + #$00EE +
        'ne de destructeurs s''ex' + #$00E9 +
        'cute. Le transtypage est donc soit redondant (transtypage vers le propre type de la variable), soit trompeur (transtypage vers une classe sans rapport qui sugg' +
        #$00E8 + 're que Destroy choisira une autre red' + #$00E9 +
        'finition - ce ne sera pas le cas). Si la cible du transtypage est fausse, le reste du code environnant peut reposer sur cette hypoth' +
        #$00E8 + 'se erron' + #$00E9 + 'e et casser lors d''une refactorisation. Le d' + #$00E9 +
        'tecteur compare `nkCall.Name` aux motifs `<Ident>(<expr>).Free[()][;]` et `<Ident>(<expr>).Destroy[()][;]` o' +
        #$00F9 +
        ' `<Ident>` suit la convention de nommage Delphi des classes/interfaces (`T` ou `I` plus une lettre majuscule). Un simple `L.Free` et un `Owner.Bar(x).Free` qualifi' +
        #$00E9 + ' (vraisemblablement un Free sur un r' + #$00E9 +
        'sultat de fonction) ne sont pas signal' + #$00E9 + 's. Correspond ' + #$00E0 +
        ' `CastAndFreeCheck` de Sonar-Delphi.'
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Constructeur appel' + #$00E9 + ' sur une instance au lieu de la classe';
      ShortDesc: '`obj.Create` - appelle le constructeur comme m' + #$00E9 +
        'thode sur une instance existante, saute l''allocation et r' + #$00E9 +
        'initialise les champs par-dessus des donn' + #$00E9 + 'es vivantes';
      FullDesc : 'Delphi permet d''appeler un constructeur sur une instance, p. ex. `obj.Create;`, mais le r' +
        #$00E9 + 'sultat n''est presque jamais celui voulu. Appel' + #$00E9 + ' comme m' + #$00E9 +
        'thode de classe (`TFoo.Create`), le runtime alloue d''abord un nouveau bloc m' + #$00E9 +
        'moire via `TObject.NewInstance`, initialise le pointeur de VMT, puis ex' + #$00E9 +
        'cute le corps du constructeur. Appel' + #$00E9 +
        ' sur une instance existante, le chemin d''allocation est enti' + #$00E8 + 'rement saut' +
        #$00E9 + ' - seul le corps du constructeur s''ex' + #$00E9 + 'cute, ce qui r' + #$00E9 +
        'initialise les champs (`FList := TList.Create;` ' + #$00E9 + 'crase le `FList` pr' + #$00E9 +
        'c' + #$00E9 + 'dent sans le lib' + #$00E9 + 'rer, les r' + #$00E9 + 'f' + #$00E9 +
        'rences de types manag' + #$00E9 + 's sont ' + #$00E9 + 'cras' + #$00E9 +
        'es, les valeurs par d' + #$00E9 + 'faut effacent ce que l''appelant avait positionn' +
        #$00E9 + '). Le r' + #$00E9 +
        'sultat est au mieux un bug de logique, au pire une corruption m' + #$00E9 +
        'moire. Heuristique du d' + #$00E9 + 'tecteur (aucun r' + #$00E9 +
        'solveur de types disponible) : compare `nkCall.Name` ' + #$00E0 +
        ' `<Ident>.Create[(<args>)][;]` o' + #$00F9 +
        ' `<Ident>` commence par une lettre minuscule (clairement une variable selon la convention Delphi, puisque les types utilisent le pr' +
        #$00E9 + 'fixe `T<Upper>` / `I<Upper>`). Ignore `Self`, `Result`, `Inherited`, les chemins ' +
        #$00E0 +
        ' plusieurs points (`A.B.Create` - ambigu), les formes de transtypage (`T(x).Create`), les noms de classes et les receveurs qui suivent la convention de nommage des m' +
        #$00E9 +
        'taclasses (suffixe d''identificateur `Class`, p. ex. `itemClass: TFooClass`). Accepte un faible risque connu de faux positif pour les variables en minuscules de type `TClass` nomm' +
        #$00E9 + 'es autrement (rare en pratique). R' + #$00E9 + 'trogradation provisoire de la s' +
        #$00E9 + 'v' + #$00E9 + 'rit' + #$00E9 +
        ' Erreur -> Avertissement (2026-07-25) : un audit sur le corpus complet a mesur' + #$00E9 +
        ' 100 % de faux positifs au niveau Erreur ; reste Avertissement jusqu''' + #$00E0 +
        ' l''arriv' + #$00E9 + 'e de gardes structurelles de r' + #$00E9 +
        'solution de types. Correspond ' + #$00E0 +
        ' `InstanceInvokedConstructorCheck` de Sonar-Delphi.'
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Red' + #$00E9 + 'finition dont le corps se r' + #$00E9 + 'duit ' + #$00E0 + ' `inherited;`';
      ShortDesc: 'Une red' + #$00E9 + 'finition qui ne fait que transmettre au parent ne sert ' + #$00E0 +
        ' rien - la supprimer';
      FullDesc : 'Une m' + #$00E9 + 'thode d' + #$00E9 + 'clar' + #$00E9 + 'e avec `override` dont l''impl' +
        #$00E9 + 'mentation ne fait qu''appeler l''anc' + #$00EA + 'tre avec les m' + #$00EA +
        'mes arguments n''ajoute rien au comportement de la classe parente : la r' + #$00E9 +
        'partition virtuelle atteint d' + #$00E9 + 'j' + #$00E0 + ' l''anc' + #$00EA +
        'tre quand la sous-classe ne red' + #$00E9 + 'finit pas la m' + #$00E9 + 'thode. La red' +
        #$00E9 + 'finition vide est du bruit qui ralentit les revues de code et doit ' + #$00EA +
        'tre revue chaque fois que la signature de l''anc' + #$00EA + 'tre change. Le d' + #$00E9 +
        'tecteur parcourt chaque impl' + #$00E9 + 'mentation de m' + #$00E9 +
        'thode `TClass.Name` dont le corps est exactement une instruction - `inherited;` (proc' +
        #$00E9 + 'dures, constructeurs, destructeurs), `inherited Name;` (sans param' + #$00E8 +
        'tres), `inherited Name(p1, .., pn)` avec les param' + #$00E8 + 'tres transmis inchang' +
        #$00E9 +
        's et dans l''ordre, ou `Result := inherited [Name(..)]` dans les fonctions - et lit la D' +
        #$00C9 + 'CLARATION dans la classe de la m' + #$00EA + 'me unit' + #$00E9 + ' (les en-t' +
        #$00EA + 'tes d''impl' + #$00E9 + 'mentation ne r' + #$00E9 + 'p' + #$00E8 +
        'tent jamais `override`). La d' + #$00E9 + 'claration doit ' + #$00EA +
        'tre unique (pas de surcharges, pas de jumeaux {$IFDEF}) et porter `override` sans autre directive (message, final, reintroduce, deprecated, convention d''appel, ...), sans attribut ni param' +
        #$00E8 + 'tre par d' + #$00E9 +
        'faut ; aucune directive de compilation ne doit se trouver entre l''en-t' + #$00EA +
        'te d''impl' + #$00E9 + 'mentation et `end`. Les m' + #$00E9 + 'thodes de classe sont ignor' +
        #$00E9 + 'es. Visibilit' + #$00E9 + ' : quand la m' + #$00E9 + 'thode de l''anc' + #$00EA +
        'tre est d' + #$00E9 + 'clar' + #$00E9 + 'e dans la m' + #$00EA + 'me unit' + #$00E9 +
        ' avec une visibilit' + #$00E9 + ' moindre, la red' + #$00E9 + 'finition ' + #$00E9 +
        'largit sa visibilit' + #$00E9 + ' et n''est pas signal' + #$00E9 + 'e. Quand l''anc' +
        #$00EA + 'tre se trouve hors de l''unit' + #$00E9 + ', les red' + #$00E9 +
        'finitions private/protected et les red' + #$00E9 + 'finitions public de m' + #$00E9 +
        'thodes racines publiques bien connues (Destroy, Create, AfterConstruction, BeforeDestruction, Assign, ToString, Equals, GetHashCode) sont signal' +
        #$00E9 + 'es avec une confiance ' + #$00E9 + 'lev' + #$00E9 + 'e, les autres red' + #$00E9 +
        'finitions public/published avec une confiance faible (masqu' + #$00E9 + 'es par d' + #$00E9 +
        'faut). Le fichier source doit ' + #$00EA + 'tre lisible. Correspond ' + #$00E0 +
        ' `InheritedMethodWithNoCodeCheck` de Sonar-Delphi.'
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Utiliser Assigned() plut' + #$00F4 + 't que `= nil` / `<> nil`';
      ShortDesc: 'Convention Pascal : `Assigned(x)` et `not Assigned(x)` sont les tests nil canoniques';
      FullDesc : 'La comparaison directe avec `nil` fonctionne pour les r' + #$00E9 + 'f' + #$00E9 +
        'rences d''objet mais ' + #$00E9 + 'choue pour les types pointeur de m' + #$00E9 +
        'thode et les Variants, pour lesquels la biblioth' + #$00E8 + 'que standard pr' + #$00E9 +
        'f' + #$00E8 + 're `Assigned`. S''en tenir ' + #$00E0 +
        ' une seule forme dans toute la base de code ' + #$00E9 +
        'vite des bugs de cas limites et am' + #$00E9 + 'liore la lisibilit' + #$00E9 +
        ' - le lecteur n''a pas besoin de v' + #$00E9 +
        'rifier quelle forme le type de la variable prend en charge. Le d' + #$00E9 +
        'tecteur examine le `Name` et le `TypeRef` de chaque n' + #$0153 +
        'ud de l''AST (ce dernier contient la forme textuelle des conditions `if`/`while`/`until` et des parties droites d''affectation) ' +
        #$00E0 + ' la recherche du motif `<op> nil` o' + #$00F9 +
        ' `<op>` vaut `=` ou `<>`. Les litt' + #$00E9 + 'raux de cha' + #$00EE +
        'ne (`''nil''`) sont retir' + #$00E9 +
        's avant la correspondance, et `:= nil` (affectation), `<= nil` / `>= nil` (comparaisons rares et absurdes) sont explicitement exclus. Correspond ' +
        #$00E0 + ' `NilComparisonCheck` de Sonar-Delphi.'
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Lev' + #$00E9 + 'e de la classe de base `Exception` au lieu d''une sous-classe';
      ShortDesc: '`raise Exception.Create(''...'')` - la classe de base ne porte aucune information s' +
        #$00E9 + 'mantique, les appelants ne peuvent pas filtrer s' + #$00E9 + 'lectivement';
      FullDesc : 'Lever la classe de base `Exception` de la RTL ' + #$00E9 + 'quivaut ' + #$00E0 +
        ' lancer `new Error(''something'')` en JavaScript : cela indique ' + #$00E0 +
        ' l''appelant *qu''*une erreur s''est produite, mais pas *laquelle*. Le code appelant est alors contraint d''attraper la classe la plus large possible (`on E: Exception do ...`), qui attrape aussi toutes les erreurs d''ex' +
        #$00E9 + 'cution sans rapport et tend ' + #$00E0 + ' avaler des bugs. Pr' + #$00E9 + 'f' +
        #$00E9 + 'rer une sous-classe sp' + #$00E9 +
        'cifique (p. ex. `EArgumentOutOfRangeException`, `EFileNotFoundException`, une `EMyDomainError` propre au domaine). Le d' +
        #$00E9 + 'tecteur parcourt chaque n' + #$0153 +
        'ud `nkRaise` et le signale quand l''expression lev' + #$00E9 +
        'e commence par `Exception.Create` (insensible ' + #$00E0 +
        ' la casse) ou est exactement `Exception` (sans appel ' + #$00E0 +
        ' Create). Le `raise;` nu (relance) et `raise E;` (variable) ne sont pas signal' + #$00E9 +
        's. Correspond ' + #$00E0 + ' `RaisingRawExceptionCheck` de Sonar-Delphi.'
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Appel de formatage d' + #$00E9 + 'pendant de la locale sans TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` et consorts sans TFormatSettings d' + #$00E9 +
        'pendent de la locale syst' + #$00E8 + 'me - le r' + #$00E9 +
        'sultat change d''une machine ou d''un utilisateur ' + #$00E0 + ' l''autre';
      FullDesc : 'Les fonctions de conversion de Pascal sensibles ' + #$00E0 +
        ' la locale (`StrToDate`, `StrToTime`, `StrToDateTime`, `DateToStr`, `TimeToStr`, `DateTimeToStr`, `StrToFloat`, `StrToCurr`, `FloatToStr`, `CurrToStr`, `FormatDateTime`, `FormatFloat`, `FormatCurr`) utilisent par d' +
        #$00E9 + 'faut l''enregistrement global `SysUtils.FormatSettings`, initialis' + #$00E9 + ' ' +
        #$00E0 + ' partir des param' + #$00E8 + 'tres r' + #$00E9 + 'gionaux du syst' + #$00E8 +
        'me d''exploitation. Le m' + #$00EA + 'me code se comporte donc diff' + #$00E9 +
        'remment sur la machine d''un d' + #$00E9 +
        'veloppeur en locale DE (`DateSeparator` = ''.'', `DecimalSeparator` = '','') et sur un serveur de production en locale EN (''/'' et ''.''). Les donn' +
        #$00E9 + 'es ' + #$00E9 + 'chang' + #$00E9 +
        'es via des fichiers, des API, des bases de donn' + #$00E9 +
        'es ou du CSV doivent toujours passer par un `TFormatSettings` explicite (typiquement un `LFormatSettings := TFormatSettings.Invariant` local pour une sortie lisible par machine, ou un instantan' +
        #$00E9 + ' de la locale de l''utilisateur pour l''interface). Le d' + #$00E9 +
        'tecteur parcourt chaque `nkCall` dont le nom de fonction correspond ' + #$00E0 +
        ' une routine RTL connue d' + #$00E9 +
        'pendant de la locale et signale l''appel quand sa liste d''arguments ne mentionne aucun identificateur contenant `FormatSettings` ou `FmtSettings` (sous-cha' +
        #$00EE + 'ne, insensible ' + #$00E0 + ' la casse) - nommer donc la variable de param' +
        #$00E8 + 'tres en cons' + #$00E9 +
        'quence (`LFormatSettings`, `FFmtSettings`). `StrToInt` / `IntToStr` et les variantes bool' +
        #$00E9 + 'ennes ne d' + #$00E9 +
        'pendent explicitement **pas** de la locale et ne sont pas signal' + #$00E9 +
        'es. Correspond ' + #$00E0 + ' `DateFormatSettingsCheck` de Sonar-Delphi.'
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'Transtypage de cha' + #$00EE + 'ne vers un type 8 bits sans encodage explicite';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` supprime silencieusement les caract' +
        #$00E8 + 'res hors de la page de codes active';
      FullDesc : 'Transtyper une UnicodeString (ou toute expression de type string - la string Delphi est UnicodeString depuis XE) vers l''une des familles de cha' +
        #$00EE +
        'nes 8 bits avec perte (AnsiString, RawByteString, ShortString) passe par la conversion implicite DefaultSystemCodePage. Chaque point de code hors de la page de codes active est remplac' +
        #$00E9 + ' silencieusement par ?. Les emoji, les ' + #$00E9 + 'critures non latines et m' +
        #$00EA + 'me certaines lettres accentu' + #$00E9 +
        'es occidentales disparaissent, mais l''affectation compile proprement et s''ex' + #$00E9 +
        'cute sans exception - le bug n''appara' + #$00EE + 't donc que lorsque les donn' + #$00E9 +
        'es reviennent par un consommateur compatible Unicode (une autre base de donn' + #$00E9 +
        'es, une API HTTP, un export Excel). Utiliser plut' + #$00F4 +
        't une fonction d''encodage d' + #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 +
        'e (UTF8Encode, TEncoding.UTF8.GetBytes, WideStringToUTF8 ...). Le d' + #$00E9 +
        'tecteur parcourt les n' + #$0153 + 'uds nkCall dont le nom commence (insensible ' + #$00E0 +
        ' la casse) par AnsiString(, RawByteString( ou ShortString(, c.-' + #$00E0 +
        '-d. une instruction ou une affectation qui commence par le transtypage ; un transtypage imbriqu' +
        #$00E9 +
        ' dans un autre appel ou au milieu d''une expression (`SaveToFile(AnsiString(u))`, `''x'' + AnsiString(u)`) n''est pas vu. UTF8String(...) n''est d' +
        #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + 'ment PAS signal' + #$00E9 +
        ' : UTF8String est type AnsiString(CP_UTF8), le transtypage produit donc exactement le m' +
        #$00EA + 'me code que l''UTF8Encode recommand' + #$00E9 +
        ' et est sans perte quelle que soit la page de codes du syst' + #$00E8 +
        'me. Le seul sous-cas restant avec perte, UTF8String(<already 8-bit>), est un faux n' +
        #$00E9 + 'gatif accept' + #$00E9 + ' (z' + #$00E9 + 'ro occurrence dans le corpus de r' +
        #$00E9 + 'f' + #$00E9 + 'rence). Les arguments litt' + #$00E9 + 'raux de cha' + #$00EE +
        'ne vides (AnsiString('''')) ne sont pas signal' + #$00E9 +
        's. Les transtypages vers string (= UnicodeString dans le Delphi moderne) ne sont pas non plus signal' +
        #$00E9 + 's. Accepte le faux positif o' + #$00F9 + ' l''entr' + #$00E9 + 'e serait d' +
        #$00E9 + 'j' + #$00E0 + ' du m' + #$00EA +
        'me type 8 bits (transtypage redondant, toujours suspect en tant que code smell). Correspond ' +
        #$00E0 + ' UnicodeToAnsiCastCheck de Sonar-Delphi. Dialecte FPC/Lazarus : cette r' + #$00E8 +
        'gle est ignor' + #$00E9 + 'e quand l''analyse s''ex' + #$00E9 +
        'cute avec --dialect=fpc - sous FPC, le type string par d' + #$00E9 +
        'faut EST 8 bits (UTF-8 par convention Lazarus), le transtypage n''y est donc pas un r' +
        #$00E9 + 'tr' + #$00E9 + 'cissement Unicode avec perte.'
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Transtypage d''un Char en PChar : le point de code devient une adresse';
      ShortDesc: '`PChar(''A'')` n''est pas `PChar("A")` - le transtypage traite le point de code 16 bits comme une adresse m' +
        #$00E9 + 'moire brute';
      FullDesc : 'Delphi compile sans broncher `PChar(c)` o' + #$00F9 +
        ' `c` est de type `Char`, `WideChar` ou `AnsiChar`. Le r' + #$00E9 +
        'sultat n''est **pas** une cha' + #$00EE + 'ne d''un caract' + #$00E8 + 're termin' + #$00E9 +
        'e par un nul - le transtypage r' + #$00E9 + 'interpr' + #$00E8 +
        'te simplement le point de code 16 bits/8 bits comme un pointeur. Ainsi `PChar(''A'')` renvoie la valeur de pointeur `$00000041`, qui pointe dans la m' +
        #$00E9 + 'moire basse du processus ; tout d' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 +
        'rencement est un comportement ind' + #$00E9 + 'fini et se termine g' + #$00E9 + 'n' +
        #$00E9 + 'ralement par une violation d''acc' + #$00E8 +
        's, mais sur certaines plateformes lit plut' + #$00F4 + 't des donn' + #$00E9 + 'es p' +
        #$00E9 + 'rim' + #$00E9 +
        'es. Le motif voulu est presque toujours `PChar(stringExpr)`, qui renvoie un pointeur dans le tampon r' +
        #$00E9 + 'el de la cha' + #$00EE + 'ne. Le d' + #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkCall` dont le nom commence par `PChar(`, `PWideChar(` ou `PAnsiChar(` et signale l''appel quand l''argument est reconnaissable comme une valeur Char : un litt' +
        #$00E9 + 'ral entre apostrophes d''un seul caract' + #$00E8 + 're (`''A''`), un litt' +
        #$00E9 + 'ral ordinal de caract' + #$00E8 +
        're (`#65`, `#$41`), ou un appel `Chr(...)`. Les arguments identificateurs ne sont pas signal' +
        #$00E9 + 's, car le d' + #$00E9 + 'tecteur n''a pas de r' + #$00E9 +
        'solveur de types pour d' + #$00E9 +
        'terminer si la variable est un `Char` ou une `string`. Correspond ' + #$00E0 +
        ' `CharacterToCharacterPointerCastCheck` de Sonar-Delphi.'
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() ' + #$00E9 + 'value les deux branches - pas de court-circuit';
      ShortDesc: '`Math.IfThen(cond, A(), B())` et `StrUtils.IfThen` sont des fonctions ordinaires - les deux bras s''ex' +
        #$00E9 + 'cutent avant l''appel';
      FullDesc : '`Math.IfThen` (surcharge Integer/Double) comme `StrUtils.IfThen` (surcharge string) sont des fonctions ordinaires, pas des constructions du langage. Pascal ' +
        #$00E9 +
        'value chaque argument *avant* l''appel, la fonction ne voit donc que les valeurs finales - elle ne peut pas ' +
        #$00AB + ' sauter ' + #$00BB + ' la branche non s' + #$00E9 + 'lectionn' + #$00E9 + 'e. D' +
        #$00E8 + 's que les bras contiennent des appels de fonction ou de m' + #$00E9 +
        'thode avec des effets de bord (lecture en base, E/S fichier, modification d''' + #$00E9 +
        'tat) ou d''un co' + #$00FB + 't non n' + #$00E9 + 'gligeable, les deux s''ex' + #$00E9 +
        'cutent inconditionnellement. Tout l''int' + #$00E9 + 'r' + #$00EA + 't d''' + #$00E9 +
        'crire `IfThen(cond, A, B)` au lieu de `if cond then x := A else x := B` reposait g' +
        #$00E9 + 'n' + #$00E9 + 'ralement sur l''hypoth' + #$00E8 + 'se d''une s' + #$00E9 +
        'mantique de court-circuit - qui n''existe pas ici. Le d' + #$00E9 +
        'tecteur parcourt les n' + #$0153 + 'uds `nkCall` dont le nom correspond ' + #$00E0 +
        ' `IfThen(`, `Math.IfThen(` ou `StrUtils.IfThen(` (insensible ' + #$00E0 + ' la casse). Apr' +
        #$00E8 + 's extraction de la liste d''arguments externe, il retire les litt' + #$00E9 +
        'raux de cha' + #$00EE +
        'ne (pour que `''a(b)''` ne trompe pas l''heuristique) et cherche des `(` imbriqu' + #$00E9 +
        'es - tout appel imbriqu' + #$00E9 + ' est un signal fort d''une branche ' + #$00E0 +
        ' effets de bord. Les appels n''ayant que des litt' + #$00E9 +
        'raux ou de simples variables comme bras ne sont pas signal' + #$00E9 +
        's - pas plus que les appels de fonctions sans param' + #$00E8 + 'tre ' + #$00E9 +
        'crits sans parenth' + #$00E8 + 'ses (`IfThen(b, FetchA, FetchB)`), car sans parenth' +
        #$00E8 + 'ses un appel ne peut pas ' + #$00EA + 'tre distingu' + #$00E9 +
        ' d''une variable. Correspond ' + #$00E0 + ' `IfThenShortCircuitCheck` de Sonar-Delphi.'
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception attrape toutes les erreurs';
      ShortDesc: '`on E: Exception do ...` attrape la classe de base et donc tous ses descendants, y compris les exceptions syst' +
        #$00E8 + 'me qui ne doivent pas ' + #$00EA + 'tre ' + #$00E9 + 'touff' + #$00E9 +
        'es (EOutOfMemory, EAccessViolation, EAbort)';
      FullDesc : 'Attraper `Exception` elle-m' + #$00EA + 'me - la racine de la hi' + #$00E9 +
        'rarchie des exceptions Delphi - avale silencieusement des cat' + #$00E9 +
        'gories d''erreurs que le code appelant n''est pas pr' + #$00EA + 't ' + #$00E0 +
        ' traiter : manque de m' + #$00E9 + 'moire, violations d''acc' + #$00E8 +
        's, l''exception de contr' + #$00F4 + 'le de flux de type `EAbort`, et tout ce qui ne d' +
        #$00E9 + 'rive pas d''une classe de base propre au domaine. Pr' + #$00E9 + 'f' + #$00E9 +
        'rer une clause pr' + #$00E9 + 'cise `on E: ESpecific do`, ou plusieurs clauses empil' +
        #$00E9 + 'es pour les cas dont on peut se r' + #$00E9 +
        'tablir. Si un repli qui relance apr' + #$00E8 + 's journalisation est vraiment n' + #$00E9 +
        'cessaire, utiliser `except Log(''''...''''); raise; end;` - le `raise;` nu conserve le type et la pile d''origine. Le d' +
        #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkOnHandler` et signale ceux dont le `TypeRef` vaut `Exception` (insensible ' + #$00E0 +
        ' la casse). Correspond ' + #$00E0 + ' la r' + #$00E8 +
        'gle Sonar-50 #11 (`ExceptionTooGeneral`).'
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'raise nu hors d''un gestionnaire except/on';
      ShortDesc: '`raise;` sans expression d''exception n''est valide qu''' + #$00E0 + ' l''int' + #$00E9 +
        'rieur d''un gestionnaire except (pour relancer l''exception) - ailleurs, Delphi (E2145) et FPC le refusent';
      FullDesc : 'Un `raise;` nu relance l''exception en cours de traitement ; il n''est donc valide qu''' +
        #$00E0 + ' l''int' + #$00E9 +
        'rieur de `except` / `on E: T do`. Delphi refuse cette forme partout ailleurs avec l''erreur de compilation E2145 ''Re-raising an exception only allowed in exception handler'', FPC avec `parser_e_no_reraise_possible` (''Re-raise isn''t possible there''). Le' +
        ' d' + #$00E9 + 'tecteur parcourt r' + #$00E9 + 'cursivement l''AST de la m' + #$00E9 +
        'thode en suivant un indicateur `InHandler`. L''indicateur est positionn' + #$00E9 +
        ' quand le parcours descend dans `nkExceptBlock` ou `nkOnHandler`. Un n' + #$0153 +
        'ud `nkRaise` avec `Name = ''raise''` (forme nue) rencontr' + #$00E9 +
        ' alors que l''indicateur vaut False produit un r' + #$00E9 +
        'sultat. Un `raise;` nu dans un bloc `finally` lui-m' + #$00EA + 'me situ' + #$00E9 +
        ' hors d''un gestionnaire except est ' + #$00E9 + 'galement signal' + #$00E9 +
        '. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #15 (`RaiseWithoutClass`).'
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable utilis' + #$00E9 + 'e apr' + #$00E8 + 's Free / FreeAndNil';
      ShortDesc: 'D' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 + 'rencer une variable apr' + #$00E8 +
        's `Free` ou `FreeAndNil` lit un pointeur pendant et provoque une violation d''acc' + #$00E8 +
        's';
      FullDesc : 'Apr' + #$00E8 + 's `obj.Free` ou `FreeAndNil(obj)`, la variable pointe vers de la m' +
        #$00E9 + 'moire lib' + #$00E9 + 'r' + #$00E9 + 'e (ou vaut NIL). Tout acc' + #$00E8 +
        's ult' + #$00E9 + 'rieur ' + #$00E0 + ' un membre, ' + #$00E0 +
        ' un indexeur ou tout appel utilisant la variable comme receveur est un comportement ind' +
        #$00E9 + 'fini - typiquement une violation d''acc' + #$00E8 +
        's, parfois une corruption silencieuse si la m' + #$00E9 + 'moire a ' + #$00E9 + 't' +
        #$00E9 + ' r' + #$00E9 + 'utilis' + #$00E9 + 'e. Le d' + #$00E9 + 'tecteur retire cha' +
        #$00EE +
        'nes + commentaires du fichier, trouve chaque occurrence de `FreeAndNil(<id>)` et `<id>.Free`, puis parcourt vers l''avant le reste du corps de la m' +
        #$00E9 + 'thode ' + #$00E0 + ' la recherche du m' + #$00EA +
        'me identificateur. Un `<id>.<member>`, `<id>(<args>)` ou `<id>[<idx>]` ult' + #$00E9 +
        'rieur produit un r' + #$00E9 + 'sultat. Les r' + #$00E9 +
        'affectations `<id> := ...` ou les d' + #$00E9 +
        'buts de section var `<id> :` terminent la fen' + #$00EA +
        'tre d''analyse. Les apparitions nues sans accesseur ne sont volontairement pas signal' +
        #$00E9 + 'es, pour ' + #$00E9 +
        'viter les faux positifs sur des comparaisons comme `if x = oldL then`. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #7. Limite : pas d''analyse de flot de contr' +
        #$00F4 +
        'le ; `if Cond then Free else Use` peut produire un faux positif, car l''utilisation se trouve sur un autre chemin.'
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Classe concr' + #$00E8 + 'te h' + #$00E9 + 'ritant d''une m' + #$00E9 +
        'thode abstraite sans override';
      ShortDesc: 'La classe d' + #$00E9 + 'rive d''une base ayant une m' + #$00E9 +
        'thode `abstract` mais ne la red' + #$00E9 + 'finit pas - l''appel sur l''instance l' +
        #$00E8 + 've EAbstractError ' + #$00E0 + ' l''ex' + #$00E9 + 'cution';
      FullDesc : 'Quand une classe h' + #$00E9 + 'rite d''une m' + #$00E9 +
        'thode `abstract` de son parent et ne la red' + #$00E9 +
        'finit pas, l''instanciation de la classe compile sans probl' + #$00E8 +
        'me, mais tout appel de la m' + #$00E9 + 'thode l' + #$00E8 + 've `EAbstractError`. Le d' +
        #$00E9 + 'tecteur parcourt les n' + #$0153 + 'uds `nkClass` ; pour chaque classe d' + #$00E9 +
        'riv' + #$00E9 + 'e, il cherche le parent direct dans la m' + #$00EA + 'me unit' + #$00E9 +
        ', collecte les m' + #$00E9 + 'thodes du parent marqu' + #$00E9 +
        'es `abstract` et signale chaque m' + #$00E9 +
        'thode abstraite dont le nom ne figure pas parmi les noms de m' + #$00E9 +
        'thodes de la classe d' + #$00E9 + 'riv' + #$00E9 +
        'e. Limites : uniquement au sein de l''unit' + #$00E9 + ' (les bases d''autres unit' +
        #$00E9 +
        's comme `TForm`/`TStrings` ne sont pas vues) ; uniquement le parent direct (les cha' +
        #$00EE + 'nes ' + #$00E0 + ' plusieurs niveaux ne v' + #$00E9 +
        'rifient qu''un seul niveau) ; les class helpers / interfaces / records sont ignor' + #$00E9 +
        's. Les classes elles-m' + #$00EA + 'mes marqu' + #$00E9 +
        'es `class abstract` peuvent laisser des m' + #$00E9 + 'thodes abstraites. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #10.'
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Constructeur qui alloue des champs et l' + #$00E8 + 've sans try/except';
      ShortDesc: 'Le constructeur affecte des champs par `<Classe>.Create` puis l' + #$00E8 +
        've sans try/except - les champs fuient si le destructeur ne les lib' + #$00E8 + 're pas';
      FullDesc : 'Quand un constructeur l' + #$00E8 +
        've une exception, Delphi appelle automatiquement le destructeur sur l''instance ' + #$00E0 +
        ' moiti' + #$00E9 + ' construite. Les champs que le constructeur a d' + #$00E9 + 'j' +
        #$00E0 + ' allou' + #$00E9 + 's ne sont lib' + #$00E9 + 'r' + #$00E9 +
        's que si ce destructeur les lib' + #$00E8 +
        're - sans destructeur, ou avec un destructeur qui ne lib' + #$00E8 +
        're pas ces champs, ils fuient. Le d' + #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkMethod` dont le `TypeRef` commence par `constructor` (en ignorant les constructeurs de classe via le marqueur `;class`), puis exige (a) au moins un `nkAssign` dont la partie gauche est `F<Name>` / `Self.F<Name>` et dont la partie droite contie' +
        'nt un appel `.Create`, (b) au moins un `nkRaise` quelque part dans le corps, et (c) aucun `nkTryExcept` dans le corps. Le d' +
        #$00E9 + 'tecteur lit aussi les destructeurs de la classe dans la m' + #$00EA + 'me unit' +
        #$00E9 + ' : quand ils lib' + #$00E8 + 'rent chaque champ allou' + #$00E9 +
        ' (un appel `Free`, `FreeAndNil`, `Release` ou `DisposeOf` qui nomme le champ, ou `F<Name> := nil` pour un champ interface), il n''y a pas de r' +
        #$00E9 + 'sultat - sauf si un destructeur ' + #$00E9 +
        'crit dans un membre d''un tel champ sans `if` sur celui-ci (il ' + #$00E9 +
        'chouerait sur le champ nil avant que le reste soit lib' + #$00E9 + 'r' + #$00E9 +
        '), ou si un constructeur de thread l' + #$00E8 + 've avant son `inherited Create` nomm' +
        #$00E9 + '. La lib' + #$00E9 + 'ration via une propri' + #$00E9 + 't' + #$00E9 + ', une m' +
        #$00E9 + 'thode auxiliaire, un composant propri' + #$00E9 +
        'taire ou un destructeur d''une autre unit' + #$00E9 + ' n''est pas reconnue ; de tels r' +
        #$00E9 +
        'sultats sont des faux positifs. Limites : pas d''analyse de flot (un raise AVANT toute initialisation de champ est quand m' +
        #$00EA + 'me signal' + #$00E9 + ') ; un try/except partiel est consid' + #$00E9 + 'r' +
        #$00E9 + ' comme enti' + #$00E8 + 'rement protecteur. Correspond ' + #$00E0 + ' la r' +
        #$00E8 + 'gle Sonar-50 #12.'
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Cible Int64 recevant le produit de deux op' + #$00E9 + 'randes 32 bits';
      ShortDesc: '`<var-Int64> := <a> * <b>` ' + #$00E9 + 'value la multiplication en 32 bits avant l''' +
        #$00E9 + 'largissement - un d' + #$00E9 + 'passement tronque silencieusement';
      FullDesc : 'Delphi ' + #$00E9 + 'value une expression binaire dans le type de ses op' + #$00E9 +
        'randes, pas dans celui de la cible de l''affectation. Quand deux op' + #$00E9 +
        'randes `Integer` (32 bits) sont multipli' + #$00E9 + 's et que le r' + #$00E9 +
        'sultat est affect' + #$00E9 + ' ' + #$00E0 +
        ' un `Int64`, la multiplication s''effectue en 32 bits ; si le produit r' + #$00E9 + 'el d' +
        #$00E9 + 'passe `MaxInt`, la valeur est tronqu' + #$00E9 + 'e silencieusement avant d''' +
        #$00EA + 'tre ' + #$00E9 + 'largie. La correction consiste ' + #$00E0 +
        ' transtyper au moins un op' + #$00E9 + 'rande en `Int64`. Le d' + #$00E9 +
        'tecteur retire cha' + #$00EE + 'nes + commentaires, analyse le texte nettoy' + #$00E9 + ' ' +
        #$00E0 + ' la recherche de d' + #$00E9 +
        'clarations `<ident>: Int64|UInt64|QWord` pour constituer un ensemble de variables 64 bits, puis cherche les affectations `<lhs> := <a> * <b>;` o' +
        #$00F9 + ' la partie gauche est une variable 64 bits mais o' + #$00F9 + ' les deux op' +
        #$00E9 +
        'randes de droite sont de simples identificateurs (sans transtypage, sans expression entre parenth' +
        #$00E8 + 'ses) qui ne sont pas eux-m' + #$00EA + 'mes 64 bits. Un litt' + #$00E9 + 'ral num' +
        #$00E9 + 'rique d''un c' + #$00F4 + 't' + #$00E9 + ' ou de l''autre emp' + #$00EA +
        'che le r' + #$00E9 + 'sultat (le compilateur peut souvent ' + #$00E9 +
        'valuer la constante sans risque). Limites : pas d''inf' + #$00E9 +
        'rence de type pour les op' + #$00E9 + 'randes non locaux (param' + #$00E8 +
        'tres, champs) ; seul `*` est v' + #$00E9 + 'rifi' + #$00E9 +
        ', pas `+`/`-` ; les expressions complexes comme `(a + b) * c` ne sont pas reconnues. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #14.'
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'La classe a trop de m' + #$00E9 + 'thodes ou de champs';
      ShortDesc: 'Une classe de plus de 20 m' + #$00E9 +
        'thodes ou de plus de 15 champs d''instance concentre trop de responsabilit' + #$00E9 +
        's - difficile ' + #$00E0 + ' tester, ' + #$00E0 + ' faire ' + #$00E9 + 'voluer et ' +
        #$00E0 + ' relire';
      FullDesc : 'Les god classes sont des classes qui poss' + #$00E8 + 'dent trop de comportement et d''' +
        #$00E9 + 'tat ' + #$00E0 +
        ' la fois : exemples typiques, les racines composites d''interface utilisateur, les singletons gestionnaires tout-en-un ou les entit' +
        #$00E9 + 's m' + #$00E9 + 'tier de premi' + #$00E8 + 're g' + #$00E9 + 'n' + #$00E9 +
        'ration qui ont grandi avec l''application. Le d' + #$00E9 + 'tecteur parcourt les n' +
        #$0153 +
        'uds `nkClass`, compte les enfants directs `nkMethod` et `nkField` (y compris ceux ' +
        #$00E0 + ' l''int' + #$00E9 + 'rieur de `nkVisibilitySection`) et ' + #$00E9 + 'met un r' +
        #$00E9 +
        'sultat quand MethodCount > 20 OU FieldCount > 15. Les records, interfaces, class helpers, d' +
        #$00E9 + 'clarations forward et classes marqu' + #$00E9 +
        'es `class abstract` (contrats d''intention de conception) sont ignor' + #$00E9 +
        's. Les propri' + #$00E9 + 't' + #$00E9 + 's ne sont pas compt' + #$00E9 +
        'es - ce sont du sucre syntaxique au-dessus de paires getter/setter. Les seuils sont cod' +
        #$00E9 + 's en dur aux valeurs par d' + #$00E9 + 'faut de Sonar ; les god classes les d' +
        #$00E9 + 'passent g' + #$00E9 + 'n' + #$00E9 + 'ralement de 3 ' + #$00E0 +
        ' 5 fois, la limite n''a donc pas besoin d''' + #$00EA + 'tre finement r' + #$00E9 +
        'glable. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #31.'
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free sans mise ' + #$00E0 + ' nil ensuite';
      ShortDesc: '`obj.Free;` sans `obj := nil;` (ni FreeAndNil) laisse un pointeur pendant - toute utilisation ult' +
        #$00E9 + 'rieure est un Use-After-Free';
      FullDesc : 'Apr' + #$00E8 + 's `obj.Free`, la variable pointe toujours vers la m' + #$00E9 +
        'moire lib' + #$00E9 + 'r' + #$00E9 + 'e. Tout d' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 +
        'rencement ult' + #$00E9 + 'rieur est un Use-After-Free, au mieux une violation d''acc' +
        #$00E8 + 's, au pire une corruption silencieuse. Le d' + #$00E9 + 'tecteur parcourt les n' +
        #$0153 + 'uds `nkCall` dont le nom correspond ' + #$00E0 +
        ' `<ident>.Free` ou `<ident>.Destroy`, puis parcourt vers l''avant la m' + #$00EA + 'me m' +
        #$00E9 + 'thode ' + #$00E0 +
        ' la recherche d''un `<ident> := nil` ou `FreeAndNil(<ident>)` ult' + #$00E9 +
        'rieur. Si aucun des deux n''existe, l''appel est signal' + #$00E9 + ' - dans une m' +
        #$00E9 + 'thode aussi lorsqu''il s''agit du dernier appel : un champ survit ' + #$00E0 +
        ' la m' + #$00E9 + 'thode, et un contr' + #$00F4 + 'le `Assigned` ult' + #$00E9 +
        'rieur ou le destructeur touche de la m' + #$00E9 + 'moire lib' + #$00E9 + 'r' + #$00E9 +
        'e (dans un constructeur, Delphi ex' + #$00E9 + 'cute le destructeur ' + #$00E0 +
        ' chaque exception). Une routine autonome qui lib' + #$00E8 +
        're une variable globale en dernier appel (nettoyage en fin de programme ou de script) n''est pas signal' +
        #$00E9 +
        'e, sauf si un `raise` suit. Les variables locales, les constantes inline et les param' +
        #$00E8 + 'tres `const` sont ignor' + #$00E9 + 's (ils sortent de port' + #$00E9 + 'e), de m' +
        #$00EA +
        'me que les destructeurs, `BeforeDestruction`, `DoFree`, `FinalizeClass`, les gestionnaires OnDestroy et les routines autonomes `Finalize*` (l''instance, la classe ou le programme se termine avec eux). `Self`/`Result`/`inherited` comme receveurs sont e' +
        'xclus, car ils suivent d''autres mod' + #$00E8 + 'les de cycle de vie. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #25.'
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'La m' + #$00E9 + 'thode a trop d''instructions Exit';
      ShortDesc: 'Une m' + #$00E9 + 'thode avec plus de 6 appels ' + #$00E0 +
        ' Exit a trop de chemins de sortie - difficile ' + #$00E0 + ' lire, difficile ' + #$00E0 +
        ' tester, facile d''en oublier un';
      FullDesc : 'Plusieurs retours anticip' + #$00E9 +
        's sont utiles pour les clauses de garde, mais au-del' + #$00E0 +
        ' d''un petit nombre ils fragmentent tant le flot de contr' + #$00F4 +
        'le que les futurs mainteneurs manquent des conditions. Le d' + #$00E9 +
        'tecteur compte les descendants `nkExit` de chaque `nkMethod` et signale une m' + #$00E9 +
        'thode qui en a plus de 6 : 6 instructions Exit restent silencieuses, 7 sont signal' +
        #$00E9 + 'es. Le seuil est fix' + #$00E9 + ' dans le d' + #$00E9 +
        'tecteur (`MAX_EXITS`). Les instructions Exit des routines imbriqu' + #$00E9 + 'es et des m' +
        #$00E9 +
        'thodes anonymes ne comptent pas. Options de refactorisation : regrouper les gardes en un seul `if (... or ... or ...) then Exit;`, passer des retours anticip' +
        #$00E9 + 's ' + #$00E0 +
        ' une variable de retour unique, ou extraire la logique interne dans une m' + #$00E9 +
        'thode auxiliaire. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #34.'
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'L''impl' + #$00E9 + 'mentation de la classe d' + #$00E9 + 'passe 500 lignes';
      ShortDesc: 'Une classe dont la d' + #$00E9 + 'claration et les m' + #$00E9 + 'thodes d''impl' + #$00E9 +
        'mentation totalisent plus de 500 lignes a trop de responsabilit' + #$00E9 + 's';
      FullDesc : 'Comme GodClass (SCA138), mais mesur' + #$00E9 + ' en ' + #$00E9 + 'tendue de lignes plut' +
        #$00F4 + 't qu''en nombre de m' + #$00E9 + 'thodes/champs. Rep' + #$00E8 +
        're les classes qui paraissent petites d''apr' + #$00E8 +
        's le nombre de membres mais ont d''' + #$00E9 + 'normes corps d''impl' + #$00E9 +
        'mentation - typique des classes de logique h' + #$00E9 + 'rit' + #$00E9 +
        'es qui ont grandi pendant des ann' + #$00E9 + 'es. Le d' + #$00E9 +
        'tecteur parcourt les n' + #$0153 + 'uds `nkClass` ; pour chaque classe, il d' + #$00E9 +
        'termine une ' + #$00E9 +
        'tendue via min(class-decl-line, first-method-with-prefix-line) .. max(class-decl-children-line, last-method-with-prefix-line). Seuil 500 lignes. Les records, interfaces, helpers et d' +
        #$00E9 + 'clarations forward sont ignor' + #$00E9 + 's. Correspond ' + #$00E0 + ' la r' +
        #$00E8 + 'gle Sonar-50 #35.'
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'La clause uses n''est pas dans l''ordre alphab' + #$00E9 + 'tique';
      ShortDesc: 'Les entr' + #$00E9 + 'es d''une clause `uses` ne sont pas dans l''ordre alphab' + #$00E9 +
        'tique - les fusions deviennent non d' + #$00E9 +
        'terministes et la relecture plus difficile';
      FullDesc : 'L''ordre alphab' + #$00E9 + 'tique rend les conflits de fusion d' + #$00E9 +
        'terministes et ' + #$00E9 + 'limine toute une cat' + #$00E9 + 'gorie de d' + #$00E9 +
        'bats st' + #$00E9 + 'riles en revue de code. Le d' + #$00E9 + 'tecteur parcourt les n' +
        #$0153 + 'uds `nkUses`, collecte les enfants `nkUsesItem` et compare l''ordre r' + #$00E9 +
        'el ' + #$00E0 + ' un tri insensible ' + #$00E0 + ' la casse. Toute diff' + #$00E9 +
        'rence produit un r' + #$00E9 + 'sultat sur la ligne `uses`. Les clauses ' + #$00E0 +
        ' une seule entr' + #$00E9 + 'e sont ignor' + #$00E9 + 'es. La s' + #$00E9 + 'v' + #$00E9 +
        'rit' + #$00E9 + ' est Conseil, car de nombreux projets regroupent d' + #$00E9 + 'lib' +
        #$00E9 + 'r' + #$00E9 + 'ment les entr' + #$00E9 +
        'es par couche (RTL / VCL / tiers / propre) plut' + #$00F4 + 't qu''alphab' + #$00E9 +
        'tiquement - un style ' + #$00E0 + ' activer volontairement, pas une r' + #$00E8 +
        'gle stricte. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #47.'
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'L''unit' + #$00E9 + ' n''a pas de commentaire d''en-t' + #$00EA + 'te descriptif';
      ShortDesc: 'L''unit' + #$00E9 +
        ' commence directement par `interface`, sans bloc de commentaire explicatif entre `unit ...;` et `interface`';
      FullDesc : 'Un court commentaire d''en-t' + #$00EA + 'te entre la d' + #$00E9 +
        'claration `unit ...;` et le mot-cl' + #$00E9 +
        ' `interface` indique aux futurs mainteneurs ' + #$00E0 + ' quoi sert l''unit' + #$00E9 +
        ' - objectif, p' + #$00E9 + 'rim' + #$00E8 +
        'tre, invariants importants, appartenance. Le d' + #$00E9 + 'tecteur lit les premi' + #$00E8 +
        'res lignes du fichier, trouve les marqueurs `unit` et `interface` et v' + #$00E9 +
        'rifie qu''au moins une ligne de commentaire (`//`, `{...}` ou `(* ... *)`) se trouve entre eux. La s' +
        #$00E9 + 'v' + #$00E9 + 'rit' + #$00E9 + ' est Conseil, car de nombreuses unit' + #$00E9 +
        's h' + #$00E9 + 'rit' + #$00E9 + 'es omettent l''en-t' + #$00EA + 'te sans cons' + #$00E9 +
        'quence fonctionnelle. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #48.'
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Comparaison d''' + #$00E9 + 'galit' + #$00E9 + ' ou d''in' + #$00E9 + 'galit' + #$00E9 +
        ' entre flottants';
      ShortDesc: '`a = b` ou `a <> b` entre Single/Double/Extended n''est pas fiable ' + #$00E0 +
        ' cause de l''arrondi IEEE-754 - utiliser SameValue ou Math.IsZero';
      FullDesc : 'L''arithm' + #$00E9 + 'tique flottante IEEE-754 ne garantit pas l''' + #$00E9 + 'galit' +
        #$00E9 + ' exacte, m' + #$00EA + 'me pour des r' + #$00E9 +
        'sultats qui semblent identiques au d' + #$00E9 +
        'veloppeur (`0.1 + 0.2 = 0.3` vaut False). Les tests d''' + #$00E9 + 'galit' + #$00E9 +
        ' sur des flottants sont une source classique de bugs silencieux - ils semblent corrects dans les tests mais se d' +
        #$00E9 + 'clenchent parfois ' + #$00E0 + ' tort. Le d' + #$00E9 + 'tecteur retire cha' +
        #$00EE + 'nes et commentaires, puis proc' + #$00E8 +
        'de en deux phases : (1) collecte les d' + #$00E9 +
        'clarations de variables locales dont le type est `Single`, `Double`, `Extended`, `Real` ou `Currency` ; (2) recherche `<ident> = <expr>` ou `<ident> <> <expr>` o' +
        #$00F9 + ' au moins un c' + #$00F4 + 't' + #$00E9 + ' r' + #$00E9 + 'f' + #$00E9 +
        'rence une variable flottante connue. Les affectations `:=` sont exclues par un lookbehind. Limites : pas d''inf' +
        #$00E9 + 'rence de type pour les retours de fonction ni les param' + #$00E8 +
        'tres non locaux ; les expressions complexes comme `a + b = c + d` ne se d' + #$00E9 +
        'clenchent que si au moins un op' + #$00E9 +
        'rande est une variable flottante connue. Correspond ' + #$00E0 + ' la r' + #$00E8 +
        'gle Sonar-50 #19. Correction : utiliser `System.Math.SameValue(a, b, Eps)` ou `IsZero(a - b)`.'
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise dans un destructeur sans try/except';
      ShortDesc: 'Un `raise` non prot' + #$00E9 + 'g' + #$00E9 + ' dans un destructeur interrompt la cha' +
        #$00EE + 'ne de nettoyage - inherited Destroy et les FreeAndNil suivants sont saut' + #$00E9 +
        's, l''' + #$00E9 + 'tat reste incoh' + #$00E9 + 'rent';
      FullDesc : 'Le r' + #$00F4 + 'le d''un destructeur est de lib' + #$00E9 +
        'rer les ressources d''une instance d''objet, puis d''appeler `inherited Destroy` pour que le parent lib' +
        #$00E8 + 're sa part. Si le destructeur l' + #$00E8 +
        've une exception qu''aucun gestionnaire englobant n''attrape, toute la cha' + #$00EE +
        'ne de nettoyage est d' + #$00E9 + 'roul' + #$00E9 +
        'e : inherited Destroy n''est jamais appel' + #$00E9 +
        ', les ressources du parent fuient, le cadre du destructeur reste ' + #$00E0 + ' moiti' +
        #$00E9 + ' ex' + #$00E9 + 'cut' + #$00E9 +
        ' et l''appelant (typiquement la RTL pendant le d' + #$00E9 +
        'roulement de la pile) voit une exception dans un contexte o' + #$00F9 + ' il l''avale g' +
        #$00E9 + 'n' + #$00E9 + 'ralement ou la remonte de fa' + #$00E7 + 'on incorrecte. Le d' +
        #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkMethod` dont le `TypeRef` commence par `destructor` (et qui ne sont pas un destructeur de classe, dont la s' +
        #$00E9 + 'mantique diff' + #$00E8 + 're), puis visite r' + #$00E9 +
        'cursivement le corps avec un indicateur `InHandler`. Chaque `nkRaise` rencontr' + #$00E9 +
        ' alors que l''indicateur vaut False est signal' + #$00E9 + '. Correspond ' + #$00E0 +
        ' la r' + #$00E8 + 'gle Sonar-50 #23.'
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Param' + #$00E8 + 'tre bool' + #$00E9 + 'en servant d''aiguillage interne';
      ShortDesc: 'Un param' + #$00E8 + 'tre bool' + #$00E9 +
        'en dont la valeur choisit entre deux chemins de code compl' + #$00E8 + 'tement diff' +
        #$00E9 + 'rents est une strat' + #$00E9 + 'gie d' + #$00E9 + 'guis' + #$00E9 + 'e - pr' +
        #$00E9 + 'f' + #$00E9 + 'rer deux m' + #$00E9 + 'thodes aux noms parlants';
      FullDesc : 'Quand la valeur d''un param' + #$00E8 + 'tre bool' + #$00E9 +
        'en fait basculer la fonction entre deux comportements sans rapport (`SendMsg(s, True)` vs `SendMsg(s, False)`), le site d''appel est opaque : le lecteur doit soit se souvenir de l''API de la m' +
        #$00E9 + 'thode, soit la consulter pour savoir ce que signifie `True`. Deux m' + #$00E9 +
        'thodes aux noms parlants (`SendErrorMessage` / `SendInfoMessage`) rendent l''intention ' +
        #$00E9 + 'vidente au site d''appel sans commentaires. Le d' + #$00E9 +
        'tecteur parcourt les n' + #$0153 +
        'uds `nkMethod`, examine les enfants `nkParam` de type Boolean (ainsi que LongBool/WordBool/ByteBool) et signale d' +
        #$00E8 + 's qu''au moins un `nkIfStmt` du corps utilise le param' + #$00E8 +
        'tre comme condition. Exclus : setters de propri' + #$00E9 + 't' + #$00E9 + ' (noms de m' +
        #$00E9 + 'thode commen' + #$00E7 + 'ant par `Set`), noms de param' + #$00E8 +
        'tres bien connus de gestionnaires d''' + #$00E9 + 'v' + #$00E9 +
        'nements VCL (`Handled`, `CanShow`). Le simple relais (bool' + #$00E9 +
        'en seulement transmis, sans branchement interne) n''est pas signal' + #$00E9 +
        '. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #33. S' + #$00E9 + 'v' + #$00E9 +
        'rit' + #$00E9 +
        ' Conseil - il s''agit d''une suggestion de refactorisation, pas d''un bug.'
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'M' + #$00E9 + 'thode priv' + #$00E9 + 'e sans appelant dans l''unit' + #$00E9;
      ShortDesc: 'Une m' + #$00E9 + 'thode priv' + #$00E9 + 'e que nulle autre m' + #$00E9 + 'thode de la m' +
        #$00EA + 'me unit' + #$00E9 + ' ne r' + #$00E9 + 'f' + #$00E9 +
        'rence est du code mort - la supprimer ou la brancher';
      FullDesc : 'Les m' + #$00E9 + 'thodes priv' + #$00E9 + 'es ne peuvent ' + #$00EA + 'tre appel' + #$00E9 +
        'es que depuis la m' + #$00EA + 'me unit' + #$00E9 + ' (Delphi classique) ou la m' + #$00EA +
        'me classe (strict private). Si aucune autre m' + #$00E9 + 'thode ne les r' + #$00E9 + 'f' +
        #$00E9 + 'rence, elles ne peuvent pas ' + #$00EA + 'tre appel' + #$00E9 +
        'es du tout - c''est du code mort, souvent le reste d''une refactorisation inachev' + #$00E9 +
        'e. Le d' + #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkClass`, trouve les enfants `nkVisibilitySection` nomm' + #$00E9 +
        's `private` ou `strict private`, collecte leurs noms de `nkMethod`, puis recherche textuellement dans le corps du fichier (d' +
        #$00E9 + 'barrass' + #$00E9 + ' des cha' + #$00EE +
        'nes et commentaires) des correspondances en limite de mot. Deux correspondances par m' +
        #$00E9 + 'thode sont tol' + #$00E9 + 'r' + #$00E9 + 'es (ligne de d' + #$00E9 +
        'claration + en-t' + #$00EA + 'te d''impl' + #$00E9 +
        'mentation) ; davantage indique au moins un appel. Comme cette recherche ne voit que les appels *par nom*, tout m' +
        #$00E9 + 'canisme de r' + #$00E9 + 'partition qui atteint une m' + #$00E9 +
        'thode sans la nommer est ' + #$00E9 + 'cart' + #$00E9 +
        ' avant le signalement - gestionnaires de messages, clauses de r' + #$00E9 + 'solution de m' +
        #$00E9 + 'thode, constructeurs/destructeurs de classe, `override` et impl' + #$00E9 +
        'mentations d''interface. Les gestionnaires d''' + #$00E9 + 'v' + #$00E9 +
        'nements DFM sont r' + #$00E9 + 'solus via le `.dfm` appari' + #$00E9 +
        '. Angle mort restant : l''invocation uniquement via RTTI (`TypeInfo`, registres pilot' +
        #$00E9 + 's par attributs) - y utiliser `// noinspection UnusedPrivateMethod`. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #37.'
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'M' + #$00E9 + 'thode d''instance n''acc' + #$00E9 + 'dant jamais ' + #$00E0 +
        ' Self - pourrait ' + #$00EA + 'tre de classe';
      ShortDesc: 'Une m' + #$00E9 + 'thode qui n''utilise que ses param' + #$00E8 +
        'tres (ni Self, ni champs d''instance, ni cha' + #$00EE +
        'ne virtuelle) est fonctionnellement une m' + #$00E9 + 'thode de classe - la d' + #$00E9 +
        'clarer comme telle';
      FullDesc : 'Quand une m' + #$00E9 +
        'thode d''instance ne touche jamais `Self`, un champ d''instance ou `inherited`, le param' +
        #$00E8 + 'tre implicite `Self` est gaspill' + #$00E9 + ' - la m' + #$00E9 +
        'thode est en fait sans ' + #$00E9 + 'tat. La d' + #$00E9 +
        'clarer `class function ... static` ' + #$00E9 +
        'conomise le passage d''un pointeur, rend explicite l''intention sans ' + #$00E9 +
        'tat et permet aux appelants de l''invoquer sans instance (`TMath.Add(1, 2)` au lieu de `MyMath.Add(1, 2)`). Le d' +
        #$00E9 + 'tecteur parcourt les n' + #$0153 + 'uds `nkMethod` qui appartiennent ' + #$00E0 +
        ' une classe (nom qualifi' + #$00E9 + ' comme `TFoo.Bar`), ignore les m' + #$00E9 +
        'thodes d' + #$00E9 + 'j' + #$00E0 +
        ' de classe (`;class` dans le TypeRef), les polymorphes (`;virtual`/`;override`/`;dynamic`/`;abstract`), les constructeurs et destructeurs, puis recherche r' +
        #$00E9 + 'cursivement tout identificateur nomm' + #$00E9 +
        ' `self`, tout `inherited` ou toute r' + #$00E9 + 'f' + #$00E9 +
        'rence de champ `F<UppercaseLetter>`. Rien de tout cela -> r' + #$00E9 +
        'sultat. Limites : l''acc' + #$00E8 + 's implicite ' + #$00E0 + ' une propri' + #$00E9 + 't' +
        #$00E9 + ' sans pr' + #$00E9 + 'fixe `Self.` n''est pas d' + #$00E9 + 'tect' + #$00E9 +
        ' comme acc' + #$00E8 + 's ' + #$00E0 +
        ' l''instance, de sorte que des appels comme `Bar := ...` pour une propri' + #$00E9 + 't' +
        #$00E9 + ' peuvent produire un faux positif. Correspond ' + #$00E0 + ' la r' + #$00E8 +
        'gle Sonar-50 #50.'
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'La m' + #$00E9 + 'thode masque une m' + #$00E9 + 'thode virtuelle parente sans `override`';
      ShortDesc: 'Une m' + #$00E9 + 'thode red' + #$00E9 + 'clar' + #$00E9 + 'e dans une classe d' + #$00E9 +
        'riv' + #$00E9 + 'e avec le m' + #$00EA + 'me nom qu''une m' + #$00E9 +
        'thode parente virtuelle ou dynamique, mais sans `override`, casse le polymorphisme - le compilateur ' +
        #$00E9 + 'met W1010';
      FullDesc : 'Sans `override`, le compilateur traite la m' + #$00E9 +
        'thode de la sous-classe comme une nouvelle m' + #$00E9 + 'thode. La r' + #$00E9 +
        'partition polymorphe via la vtable du parent appelle toujours l''impl' + #$00E9 +
        'mentation du parent - `Base := Derived; Base.DoWork` ex' + #$00E9 +
        'cute `TBase.DoWork`, pas `TDerived.DoWork`. Le compilateur avertit (W1010), mais de nombreuses bases de code d' +
        #$00E9 + 'sactivent cette indication. Le d' + #$00E9 + 'tecteur parcourt les n' + #$0153 +
        'uds `nkClass`, identifie leur parent direct dans la m' + #$00EA + 'me unit' + #$00E9 +
        ', collecte les m' + #$00E9 +
        'thodes du parent ayant `;virtual` ou `;dynamic` dans le `TypeRef`, puis v' + #$00E9 +
        'rifie chaque m' + #$00E9 + 'thode de la sous-classe dont le nom non qualifi' + #$00E9 +
        ' correspond ' + #$00E0 +
        ' un nom polymorphe du parent : `;override` absent ET `;reintroduce` absent -> r' + #$00E9 +
        'sultat. Limites : uniquement au sein de l''unit' + #$00E9 + ' (les parents d''autres unit' +
        #$00E9 +
        's comme `TForm`/`TStrings` ne sont pas vus) ; uniquement le parent direct (les cha' +
        #$00EE + 'nes ' + #$00E0 + ' plusieurs niveaux ne v' + #$00E9 +
        'rifient qu''un seul niveau). Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #21.'
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'La comparaison bool' + #$00E9 + 'enne est toujours vraie / toujours fausse';
      ShortDesc: 'Des comparaisons comme `Length(s) >= 0` sont des tautologies - le r' + #$00E9 +
        'sultat de Length n''est jamais n' + #$00E9 + 'gatif, la condition ne peut donc jamais ' +
        #$00EA + 'tre fausse';
      FullDesc : 'Les comparaisons bool' + #$00E9 + 'ennes tautologiques indiquent g' + #$00E9 + 'n' + #$00E9 +
        'ralement une faute de frappe (`< 0` au lieu de `= 0`, `>= 1` au lieu de `> 0`) ou un reste de copier-coller d''une version ant' +
        #$00E9 + 'rieure du code. Le compilateur n''avertit pas, car le type de l''op' + #$00E9 +
        'rande autorise syntaxiquement la plage de valeurs. Ce d' + #$00E9 + 'tecteur ' + #$00E9 +
        'troit retire cha' + #$00EE + 'nes + commentaires, puis reconna' + #$00EE +
        't lexicalement deux motifs : `Length(...) >= 0` / `Length(...) < 0` et leurs miroirs `0 <= Length(...)` / `0 > Length(...)`. Limites : les variables Cardinal/UInt (`<UInt> >= 0` est ' +
        #$00E9 + 'galement toujours vrai) ne peuvent pas ' + #$00EA + 'tre d' + #$00E9 + 'tect' +
        #$00E9 + 'es sans inf' + #$00E9 +
        'rence de type ; les expressions complexes comme `Length(s) - 1 < 0` ne sont pas reconnues. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #18 (forme ' + #$00E9 + 'troite).'
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'La fonction renvoie toujours le m' + #$00EA + 'me litt' + #$00E9 + 'ral';
      ShortDesc: 'Tous les chemins de la fonction affectent le m' + #$00EA + 'me litt' + #$00E9 + 'ral ' +
        #$00E0 +
        ' Result - la logique conditionnelle ne change rien au comportement, remplacer la fonction par une constante';
      FullDesc : 'Quand chaque affectation ' + #$00E0 +
        ' `Result` (ou au nom de la fonction dans le style Pascal classique) est le m' + #$00EA +
        'me litt' + #$00E9 + 'ral, la fonction renvoie ce litt' + #$00E9 +
        'ral quelles que soient les entr' + #$00E9 +
        'es. La structure conditionnelle est morte - soit une refactorisation inachev' + #$00E9 +
        'e (une branche n''a jamais ' + #$00E9 + 't' + #$00E9 + ' mise ' + #$00E0 +
        ' jour), soit des branches qui auraient d' + #$00FB + ' produire des valeurs diff' + #$00E9 +
        'rentes ne le font pas. Le d' + #$00E9 +
        'tecteur parcourt les `nkMethod` dont le `TypeRef` d' + #$00E9 +
        'clare un type de retour, collecte les n' + #$0153 +
        'uds `nkAssign` dont la partie gauche vaut `result` ou le nom non qualifi' + #$00E9 +
        ' de la fonction, extrait le litt' + #$00E9 + 'ral de droite (nombre, litt' + #$00E9 +
        'ral de cha' + #$00EE +
        'ne, True/False/nil) et signale quand au moins deux de ces affectations partagent exactement le m' +
        #$00EA + 'me litt' + #$00E9 + 'ral et qu''aucune affectation non litt' + #$00E9 +
        'rale n''existe. Correspond ' + #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #43.'
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Texte visible par l''utilisateur affect' + #$00E9 + ' en litt' + #$00E9 + 'ral';
      ShortDesc: 'Les affectations ' + #$00E0 + ' Caption/Hint/Text et les appels ' + #$00E0 +
        ' ShowMessage/MessageDlg avec du texte litt' + #$00E9 +
        'ral contournent resourcestring et i18n - la cha' + #$00EE + 'ne n''est pas traduisible';
      FullDesc : 'Un texte visible par l''utilisateur cod' + #$00E9 +
        ' en dur rend l''application intraduisible sans modifier le code source. Le d' + #$00E9 +
        'tecteur analyse lexicalement chaque ligne source ' + #$00E0 +
        ' la recherche de deux motifs ' + #$00E9 +
        'troits : `<ident>.Caption|Hint|Text := ''<text>''` et `ShowMessage|MessageDlg(''<text>''`. Le texte captur' +
        #$00E9 + ' n''est signal' + #$00E9 + ' que s''il (a) fait au moins 2 caract' + #$00E8 +
        'res, (b) contient au moins une lettre (ce qui ' + #$00E9 + 'carte les s' + #$00E9 +
        'parateurs d''un caract' + #$00E8 + 're comme `''-''`, `''.''`, `'':''` et les litt' +
        #$00E9 + 'raux num' + #$00E9 + 'riques), et (c) ne ressemble pas ' + #$00E0 + ' une cl' +
        #$00E9 + ' de ressource (uniquement majuscules + soulign' + #$00E9 +
        's, ou commence par `$`). Les commentaires de ligne (`//`) sont ignor' + #$00E9 +
        's. Limites : les correspondances sur des classes non graphiques ayant une propri' + #$00E9 +
        't' + #$00E9 +
        ' Caption/Hint/Text (p. ex. des auxiliaires internes) peuvent produire des faux positifs - dans ce cas, utiliser le marqueur de suppression de ligne `// noinspection HardcodedString`. Correspond ' +
        #$00E0 + ' la r' + #$00E8 + 'gle Sonar-50 #46 (forme ' + #$00E9 + 'troite, UI uniquement).'
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Paire Lock/Unlock sans try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter avec sa lib' + #$00E9 + 'ration dans la m' +
        #$00EA + 'me routine mais sans try/finally - le chemin d''exception laisse le verrou pos' +
        #$00E9 + ' et bloque l''appelant suivant';
      FullDesc : 'Analyse lexicalement chaque ligne source (commentaires + cha' + #$00EE + 'nes retir' +
        #$00E9 + 's) ' + #$00E0 +
        ' la recherche du jeton de prise `<ident>.Lock`, `Acquire`, `EnterCriticalSection` ou d''un `EnterCriticalSection(...)` nu. Une fen' +
        #$00EA + 'tre d''anticipation d''au plus 200 caract' + #$00E8 + 'res - tronqu' + #$00E9 +
        'e au d' + #$00E9 + 'but de la routine suivante - cherche ensuite le jeton de lib' + #$00E9 +
        'ration correspondant (`UnLock`, `LeaveCriticalSection`, `Release`) ; une lib' + #$00E9 +
        'ration qui appartient ' + #$00E0 + ' une m' + #$00E9 + 'thode voisine (fa' + #$00E7 +
        'ade Lock/UnLock, paire Begin/End, garde de port' + #$00E9 +
        'e constructeur/destructeur) ne compte plus. Quand les DEUX sont pr' + #$00E9 +
        'sents dans la fen' + #$00EA + 'tre mais qu''aucun mot-cl' + #$00E9 + ' `try` ne pr' +
        #$00E9 + 'c' + #$00E8 + 'de la lib' + #$00E9 + 'ration, la paire est signal' + #$00E9 +
        'e - prendre un verrou puis lever une exception avant la lib' + #$00E9 +
        'ration provoque un interblocage pour chaque attente ult' + #$00E9 + 'rieure. Ajust' +
        #$00E9 + ' pour mORMot : reconna' + #$00EE +
        't TSynLocker, TRWLock, TLightLock et la paire Windows nue EnterCriticalSection/LeaveCriticalSection. Les motifs o' +
        #$00F9 + ' la lib' + #$00E9 + 'ration manque enti' + #$00E8 + 'rement sont ignor' + #$00E9 +
        's (probablement un style RAII avec un assistant de verrou dont la lib' + #$00E9 +
        'ration se trouve dans un destructeur).'
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar avec SizeOf d''un type pointeur';
      ShortDesc: 'Move, FillChar, CopyMemory ou ZeroMemory appel' + #$00E9 + ' avec SizeOf(PXxx) o' + #$00F9 +
        ' PXxx est un type pointeur - ne copie que 4 ou 8 octets (la taille du pointeur) au lieu du tampon vis' +
        #$00E9;
      FullDesc : 'Analyse lexicale ' + #$00E0 +
        ' la recherche de `Move|FillChar|CopyMemory|ZeroMemory(...SizeOf(<Name>)...)` o' + #$00F9 +
        ' <Name> commence par `P` suivi d''une majuscule (convention Delphi du pr' + #$00E9 +
        'fixe P pour les types pointeur : PByte, PInteger, PCardinal, PChar, PSomeRecord, ...). En 64 bits, SizeOf(PXxx) renvoie 8 quel que soit le type point' +
        #$00E9 +
        ' ; en 32 bits, il renvoie 4. L''auteur voulait presque toujours SizeOf(Xxx) ou Length(Buf) - la copie tronqu' +
        #$00E9 +
        'e laisse silencieusement le reste du tampon intact (FillChar) ou ne copie que partiellement la source (Move). Pi' +
        #$00E8 +
        'ge courant dans mORMot : SizeOf(PByte) au lieu d''un nombre d''octets explicite lors d''une copie dans un tableau fixe. La liste blanche exclut SizeOf(TXxx) / SizeOf(Integer) / SizeOf(Variable) - seul le pr' +
        #$00E9 + 'fixe P suivi d''une majuscule d' + #$00E9 + 'clenche.'
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'Instruction with sur plusieurs cibles';
      ShortDesc: '`with A, B do` (deux receveurs ou plus s' + #$00E9 + 'par' + #$00E9 +
        's par des virgules) rend la r' + #$00E9 + 'solution des membres ambigu' + #$00EB +
        ' - ajouter une m' + #$00E9 + 'thode ' + #$00E0 + ' A ou ' + #$00E0 +
        ' B change silencieusement le sens du corps';
      FullDesc : 'Correspondance regex \bwith\s+<id>,\s*<id>\s*do\b sur tout le fichier (multiligne / commentaires retir' +
        #$00E9 + 's), suivie d''une passe d''' + #$00E9 + 'quilibrage des parenth' + #$00E8 +
        'ses sur la t' + #$00EA + 'te du with. Une seule cible est d' + #$00E9 + 'j' + #$00E0 +
        ' un code smell (couvert par fkWithStatement) ; deux ou plus transforment le corps en pi' +
        #$00E8 + 'ge de maintenance : une nouvelle m' + #$00E9 + 'thode ajout' + #$00E9 + 'e ' +
        #$00E0 + ' A ou ' + #$00E0 + ' B peut silencieusement supplanter ce qui ' + #$00E9 +
        'tait auparavant r' + #$00E9 +
        'solu vers l''autre. Le compilateur choisit la correspondance la plus proche et n''avertit jamais. Les renommages via la refactorisation de l''IDE omettent ces r' +
        #$00E9 + 'f' + #$00E9 + 'rences, car le receveur n''est pas nomm' + #$00E9 +
        ' au site d''appel. Ajust' + #$00E9 + ' pour mORMot : accepte jusqu''' + #$00E0 +
        ' 200 caract' + #$00E8 + 'res par nom de cible pour tol' + #$00E9 + 'rer des noms enti' +
        #$00E8 + 'rement qualifi' + #$00E9 + 's comme Owner.SubObject.Component. Correction : s' +
        #$00E9 + 'parer en blocs with distincts ou - mieux - abandonner with enti' + #$00E8 +
        'rement et qualifier explicitement chaque membre. Non signal' + #$00E9 +
        ' : une cible unique dont les virgules se trouvent dans une liste d''arguments, d''indices ou d''arguments de type. Seule une virgule ' +
        #$00E0 + ' la profondeur de parenth' + #$00E8 + 'ses 0 s' + #$00E9 +
        'pare des cibles ; la passe d''' + #$00E9 + 'quilibrage compte les parenth' + #$00E8 +
        'ses et les crochets et ignore les arguments de type g' + #$00E9 + 'n' + #$00E9 +
        'riques (TDict<K,V>), et les litt' + #$00E9 + 'raux de cha' + #$00EE + 'ne sont vid' +
        #$00E9 + 's au pr' + #$00E9 + 'alable. Si la t' + #$00EA + 'te ne peut pas ' + #$00EA +
        'tre tranch' + #$00E9 + 'e (aucun do ' + #$00E0 + ' la profondeur 0 dans la fen' + #$00EA +
        'tre, parenth' + #$00E8 + 'ses d' + #$00E9 + 's' + #$00E9 + 'quilibr' + #$00E9 + 'es), le r' +
        #$00E9 + 'sultat est conserv' + #$00E9 + ' - le filtre ne peut que retirer, jamais ajouter.'
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem sans try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem suivi du FreeMem correspondant dans la m' + #$00EA +
        'me routine mais sans try/finally englobant - le chemin d''exception perd le tampon d' +
        #$00E9 + 'finitivement';
      FullDesc : 'Analyse lexicale (commentaires + cha' + #$00EE + 'nes retir' + #$00E9 + 's) ' + #$00E0 +
        ' la recherche de `GetMem(...)`, `AllocMem(...)` ou `ReallocMem(...)`. Une fen' + #$00EA +
        'tre d''anticipation de 400 caract' + #$00E8 +
        'res cherche le `FreeMem` correspondant. Quand les deux sont pr' + #$00E9 +
        'sents dans la fen' + #$00EA + 'tre mais qu''aucun mot-cl' + #$00E9 + ' `try` ne pr' +
        #$00E9 + 'c' + #$00E8 + 'de le FreeMem, la paire est signal' + #$00E9 +
        'e - toute exception entre l''allocation et la lib' + #$00E9 +
        'ration fait fuir le tampon brut du tas. Ajust' + #$00E9 + ' pour mORMot : reconna' + #$00EE +
        't les ~20 occurrences de GetMem dans core/ de mORMot qui impl' + #$00E9 +
        'mentent une manipulation de tampons haute performance, o' + #$00F9 +
        ' chaque try/finally manquant est une fuite en production. Les motifs o' + #$00F9 +
        ' FreeMem manque enti' + #$00E8 + 'rement sont ignor' + #$00E9 +
        's (probablement transfert de propri' + #$00E9 + 't' + #$00E9 +
        ' vers l''appelant, ou allocateur personnalis' + #$00E9 + ').'
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) dans une boucle';
      ShortDesc: 'Agrandir un tableau dynamique d''un ' + #$00E9 + 'l' + #$00E9 +
        'ment (ou de N) dans une boucle for/while/repeat co' + #$00FB +
        'te quadratiquement - agrandir une fois avant la boucle ou proc' + #$00E9 + 'der par blocs';
      FullDesc : 'Analyse lexicale de tout mot-cl' + #$00E9 + ' `for|while|repeat` suivi, ' + #$00E0 +
        ' moins de 600 caract' + #$00E8 + 'res, de `SetLength(<id>, Length(<id>) + ...)` o' + #$00F9 +
        ' les deux noms `<id>` sont identiques (le tableau s''agrandit lui-m' + #$00EA +
        'me). Chaque r' + #$00E9 + 'allocation copie le contenu existant - n it' + #$00E9 +
        'rations co' + #$00FB + 'tent n*(n+1)/2 copies d''' + #$00E9 + 'l' + #$00E9 +
        'ments au lieu de n. ' + #$00C0 + ' 10_000 ' + #$00E9 + 'l' + #$00E9 +
        'ments, c''est ~5000 fois plus lent qu''un SetLength unique. Pi' + #$00E8 +
        'ge de performance courant avec mORMot quand le code utilisateur accumule des r' + #$00E9 +
        'sultats sans conna' + #$00EE +
        'tre la taille finale. Seul le premier agrandissement par boucle est signal' + #$00E9 +
        ', pour ' + #$00E9 + 'viter le spam. `SetLength(A, Length(B)+1)` (tableaux diff' + #$00E9 +
        'rents) n''est PAS signal' + #$00E9 + ' - ce motif est rare et g' + #$00E9 + 'n' + #$00E9 +
        'ralement d' + #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + '.'
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- d' + #$00E9 + 'calage sans test de cha' + #$00EE + 'ne vide';
      ShortDesc: '`PChar(s) + n` et variantes sans test pr' + #$00E9 + 'alable de `s` vide - pour une cha' +
        #$00EE + 'ne plus courte que n, le pointeur pointe au-del' + #$00E0 + ' du terminateur';
      FullDesc : 'Analyse lexicale de `PChar|PAnsiChar|PWideChar(<id>) [+-] <offset>`. Une fen' + #$00EA +
        'tre de 200 caract' + #$00E8 + 'res en arri' + #$00E8 +
        're recherche des motifs de garde : `<id> <> ''''`, `<id> = ''''`, `Length(<id>) ...` ou `Assigned(<id>)`. Si aucune garde n''est trouv' +
        #$00E9 + 'e, l''arithm' + #$00E9 + 'tique est signal' + #$00E9 + 'e. Pour une cha' + #$00EE +
        'ne vide, `PChar(s)` renvoie un pointeur vers un caract' + #$00E8 +
        're #0 statique (pas nil), donc `PChar(s) + 5` pointe cinq caract' + #$00E8 + 'res au-del' +
        #$00E0 + ' de ce terminateur ; il en va de m' + #$00EA + 'me pour toute cha' + #$00EE +
        'ne plus courte que le d' + #$00E9 + 'calage. Lire via un tel pointeur renvoie des donn' +
        #$00E9 + 'es parasites ou provoque une violation d''acc' + #$00E8 +
        's. Le code interne de mORMot prot' + #$00E8 + 'ge syst' + #$00E9 +
        'matiquement par des tests explicites de cha' + #$00EE +
        'ne vide ; le code utilisateur qui copie l''idiome d''arithm' + #$00E9 +
        'tique PChar omet souvent la garde. Limites : la fen' + #$00EA + 'tre arri' + #$00E8 +
        're est de 200 caract' + #$00E8 + 'res (les tests plus ' + #$00E9 + 'loign' + #$00E9 +
        's ne sont pas vus) ; l''arithm' + #$00E9 +
        'tique via `Inc(p, ...)` sur une variable PChar affect' + #$00E9 +
        'e auparavant n''est PAS d' + #$00E9 + 'tect' + #$00E9 +
        'e (il faudrait une analyse de flux).'
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Gestionnaire d''exception typ' + #$00E9 + 'e au corps vide';
      ShortDesc: '`on E: SomeException do ;` avale silencieusement une classe d''exception pr' + #$00E9 +
        'cise - pire qu''un `except end` nu, car l''annotation typ' + #$00E9 + 'e a l''air d' +
        #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + 'e';
      FullDesc : 'Analyse lexicale de `on [E:] <ExceptionType> do (;|begin end)`. La forme typ' + #$00E9 +
        'e `on E:` donne l''impression d''un traitement r' + #$00E9 + 'fl' + #$00E9 +
        'chi - le lecteur suppose que le d' + #$00E9 + 'veloppeur a pens' + #$00E9 + ' ' + #$00E0 +
        ' cette exception pr' + #$00E9 + 'cise. Un corps vide rend l''' + #$00E9 +
        'chec invisible en production : pas de journal, pas de retour dans l''interface, pas de t' +
        #$00E9 + 'l' + #$00E9 + 'm' + #$00E9 + 'trie. Constat fr' + #$00E9 +
        'quent des revues mORMot dans du code de nettoyage o' + #$00F9 + ' ' + #$00AB +
        ' cela peut ' + #$00EA + 'tre ignor' + #$00E9 + ' ' + #$00BB + ' n''est pas document' +
        #$00E9 + '. La forme nue `except end` est d' + #$00E9 + 'j' + #$00E0 +
        ' couverte par SCA-001 (EmptyExcept) ; cette r' + #$00E8 +
        'gle couvre la variante au gestionnaire typ' + #$00E9 + '.'
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'Transtypage en cha' + #$00EE + 'ne depuis un pointeur brut';
      ShortDesc: '`string(P)` et variantes depuis un pointeur pr' + #$00E9 + 'fix' + #$00E9 +
        ' par P supposent un terminateur nul qui peut ne pas exister - lecture au-del' + #$00E0 +
        ' du tas';
      FullDesc : 'Analyse lexicale de `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)` o' +
        #$00F9 + ' `<id>` commence par `P` suivi d''une autre lettre (convention Delphi du pr' +
        #$00E9 +
        'fixe P pour les types pointeur : PByte, PChar, PSomeRecord, ...). La correspondance ignore la casse, donc `pText` correspond aussi ; un op' +
        #$00E9 + 'rande d' + #$00E9 + 'clar' + #$00E9 + ' avec un type cha' + #$00EE +
        'ne dans le m' + #$00EA + 'me fichier est ignor' + #$00E9 +
        '. Delphi traite le transtypage comme termin' + #$00E9 + ' par un nul et lit la m' + #$00E9 +
        'moire jusqu''au prochain #0 - sur un tampon sans terminateur, la lecture d' + #$00E9 +
        'passe la limite du bloc de tas, ce qui provoque une lecture hors limites silencieuse et parfois une AV. Le code interne de mORMot utilise ce motif avec une terminaison nulle ma' +
        #$00EE + 'tris' + #$00E9 +
        'e ; le code utilisateur qui copie l''idiome omet souvent la garantie du terminateur. Utiliser plut' +
        #$00F4 +
        't `SetString(s, PChar(Buf), Len)` avec une longueur explicite. Filtre anti-faux positifs : seuls les identificateurs commen' +
        #$00E7 + 'ant par P d' + #$00E9 +
        'clenchent - `string(IntegerVar)` (Integer vers String) n''est pas signal' + #$00E9 +
        ' ; un double transtypage comme `string(PChar(x))` ne l''est pas non plus.'
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Soustraction de pointeurs via un transtypage 32 bits';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (ou Integer/LongWord/LongInt) tronque les 32 bits de poids fort d''un pointeur 64 bits sous Win64 - la diff' +
        #$00E9 + 'rence est parfois fausse';
      FullDesc : 'Analyse lexicale de `(Cardinal|LongWord|Integer|LongInt)(<id>) - (Cardinal|...)(<id>)` - deux transtypages 32 bits reli' +
        #$00E9 +
        's par un moins. Sous Win64, un Pointer fait 64 bits alors que Cardinal/Integer/LongWord/LongInt font 32 bits, donc le transtypage perd les quatre octets de poids fort de l''adresse. La diff' +
        #$00E9 + 'rence obtenue est fausse d' + #$00E8 +
        's que l''allocateur fournit des adresses hautes - le code fonctionne sous Win32 et ' +
        #$00E9 +
        'choue par intermittence sous Win64. Bug de portage courant issu d''exemples Delphi-7 / Delphi-2007 ant' +
        #$00E9 + 'rieurs ' + #$00E0 +
        ' Win64. Correction : utiliser `NativeUInt(P1) - NativeUInt(P2)` ou `NativeInt(P1) - NativeInt(P2)` - des types entiers de la largeur d''un pointeur, adapt' +
        #$00E9 + 's ' + #$00E0 +
        ' la taille de pointeur de la plateforme (`PtrUInt`/`PtrInt` sont les noms FPC et mORMot ; la RTL Delphi ne les d' +
        #$00E9 + 'clare pas).'
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Utilisation d''un algorithme cryptographique faible ou obsol' + #$00E8 + 'te';
      ShortDesc: 'Nom d''algorithme (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') ou classe d''encapsulation (THashMD5, TIdHashSHA1, ...) r' +
        #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + 'e - vuln' + #$00E9 +
        'rable aux collisions et aux attaques ' + #$00E0 + ' texte clair connu';
      FullDesc : 'MD5 pr' + #$00E9 +
        'sente des collisions praticables depuis 2004 (Wang et al.), SHA1 depuis 2017 (SHAttered, pr' +
        #$00E9 + 'fixe identique ; pr' + #$00E9 +
        'fixe choisi depuis 2020). DES utilise 56 bits et peut ' + #$00EA + 'tre cass' + #$00E9 +
        ' par force brute, 3DES subit la collision CBC Sweet32 (CVE-2016-2183). RC4 pr' + #$00E9 +
        'sente des biais statistiques document' + #$00E9 +
        's et est interdit par la RFC 7465. TLS 1.0 / 1.1 sont d' + #$00E9 + 'clar' + #$00E9 +
        's obsol' + #$00E8 + 'tes par la RFC 8996 (BEAST, POODLE, Lucky13). SSLv3 a ' + #$00E9 + 't' +
        #$00E9 + ' rendu caduc par POODLE (CVE-2014-3566). Le d' + #$00E9 + 'tecteur reconna' +
        #$00EE + 't les noms d''algorithmes, d' + #$00E9 + 'limit' + #$00E9 +
        's comme mots, dans les litt' + #$00E9 + 'raux de cha' + #$00EE +
        'ne et les identificateurs, ET un ensemble de noms de classes d''encapsulation connues (correspondance de sous-cha' +
        #$00EE + 'ne). Correction : passer ' + #$00E0 + ' SHA-256/SHA-3 pour le hachage, ' + #$00E0 +
        ' AES-GCM / AES-CCM pour le chiffrement sym' + #$00E9 + 'trique, et ' + #$00E0 +
        ' TLS 1.2 au minimum (1.3 de pr' + #$00E9 + 'f' + #$00E9 + 'rence).'
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'API shell appel' + #$00E9 + 'e avec concat' + #$00E9 + 'nation dans les arguments';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec avec `+` dans les arguments - si un op' + #$00E9 +
        'rande est contr' + #$00F4 + 'lable, cela devient un vecteur d''injection de commande';
      FullDesc : 'Construire la cha' + #$00EE + 'ne de commande par concat' + #$00E9 +
        'nation (`PChar(''cmd /c '' + UserInput)`) permet ' + #$00E0 +
        ' un attaquant d''ajouter des commandes suppl' + #$00E9 + 'mentaires lorsque l''entr' +
        #$00E9 + 'e n''est pas strictement valid' + #$00E9 + 'e. Ce d' + #$00E9 +
        'tecteur parcourt l''AST et signale tout nkCall dont le nom de m' + #$00E9 +
        'thode (sans qualificateur) est l''un des points d''entr' + #$00E9 +
        'e shell connus ET dont la liste d''arguments contient un op' + #$00E9 +
        'rateur `+` EN DEHORS de tout litt' + #$00E9 + 'ral de cha' + #$00EE +
        'ne. Comme il est impossible de dire statiquement si un op' + #$00E9 + 'rande est contamin' +
        #$00E9 + ', le r' + #$00E9 + 'sultat est ' + #$00E9 +
        'mis avec Confidence = Low ; il n''appara' + #$00EE +
        't dans l''interface que si le seuil de confiance minimale est r' + #$00E9 + 'gl' + #$00E9 +
        ' sur ''low''. Correction : passer les arguments via le tableau de param' + #$00E8 +
        'tres d' + #$00E9 + 'di' + #$00E9 + ' (CreateProcess) ou les ' + #$00E9 +
        'chapper/valider avant la concat' + #$00E9 + 'nation, pr' + #$00E9 + 'f' + #$00E9 +
        'rer ShellExecuteEx avec une structure SHELLEXECUTEINFO.'
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine de premier niveau jamais appel' + #$00E9 + 'e';
      ShortDesc: 'Une proc' + #$00E9 + 'dure ou fonction autonome de la section implementation n''est appel' +
        #$00E9 + 'e nulle part dans l''unit' + #$00E9 + ' et n''est pas export' + #$00E9 +
        'e par la section interface - code mort';
      FullDesc : 'Comble le vide entre SCA147 (UnusedPrivateMethod - seulement les m' + #$00E9 +
        'thodes priv' + #$00E9 + 'es de classe) et la famille de contr' + #$00F4 +
        'les de visibilit' + #$00E9 + ' SCA148+ (seulement les membres publics de classe). D' +
        #$00E9 + 'tecte les routines de premier niveau (hors classe) dont le nom n''appara' + #$00EE +
        't nulle part comme appel dans la m' + #$00EA + 'me unit' + #$00E9 + ', auto-r' + #$00E9 +
        'f' + #$00E9 + 'rences exclues (une routine r' + #$00E9 +
        'cursive qui ne fait que s''appeler elle-m' + #$00EA + 'me est tout de m' + #$00EA +
        'me signal' + #$00E9 +
        'e - comme le UnusedRoutineCheck de SonarDelphi). Gardes anti-faux positifs : constructeurs et destructeurs (non appelables directement comme proc' +
        #$00E9 +
        'dure), les directives `override`/`virtual; abstract`/`message`/`dynamic` (dispatch inter-classes ou syst' +
        #$00E8 + 'me), la proc' + #$00E9 + 'dure d''amor' + #$00E7 +
        'age IDE `Register`, le trio de l''' + #$00E9 + 'num' + #$00E9 +
        'rateur (`MoveNext`/`GetEnumerator`/`Current` - invoqu' + #$00E9 +
        's implicitement par `for-in`) et toute routine d' + #$00E9 + 'clar' + #$00E9 +
        'e par anticipation dans la section interface de l''unit' + #$00E9 +
        ' (consommateur potentiel dans une autre unit' + #$00E9 + '). La port' + #$00E9 +
        'e est un seul fichier - les appelants d''autres unit' + #$00E9 +
        's des routines de la section interface ne sont pas suivis dans ce MVP, ces routines sont donc volontairement ignor' +
        #$00E9 + 'es. Masquer avec `// noinspection UnusedRoutine` quand la routine est conserv' +
        #$00E9 + 'e volontairement (invocation via RTTI, consomm' + #$00E9 +
        'e par un attribut, charg' + #$00E9 +
        'e par un plugin). Correspond au UnusedRoutineCheck de SonarDelphi.'
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Marqueur noinspection inutilis' + #$00E9;
      ShortDesc: 'Un `// noinspection X` ne masque aucun r' + #$00E9 +
        'sultat sur sa ligne cible - soit le d' + #$00E9 + 'tecteur s''est am' + #$00E9 + 'lior' +
        #$00E9 + ', soit la cible ' + #$00E9 + 'tait mauvaise';
      FullDesc : 'Le filtre de suppression (uSuppression) enregistre chaque commentaire `// noinspection KindName` et la ligne de code suivante qu''il vise. Une fois tous les d' +
        #$00E9 + 'tecteurs termin' + #$00E9 + 's, le filtre v' + #$00E9 +
        'rifie quels marqueurs ont effectivement masqu' + #$00E9 + ' un r' + #$00E9 +
        'sultat. Les marqueurs qui n''ont jamais agi sont signal' + #$00E9 +
        's comme fkUnusedSuppression sur la ligne du marqueur - l''utilisateur doit supprimer le marqueur (l''' +
        #$00E9 + 'volution du d' + #$00E9 + 'tecteur l''a rendu obsol' + #$00E8 + 'te) ou v' +
        #$00E9 + 'rifier si le nom de type vis' + #$00E9 + ' ' + #$00E9 + 'tait erron' + #$00E9 +
        '. R' + #$00E9 + 'sistant aux faux n' + #$00E9 +
        'gatifs : seuls les marqueurs ayant une ligne cible claire hors commentaire sont pris en compte (les marqueurs en fin de fichier ou dans des blocs de commentaires de documentation purs sont ignor' +
        #$00E9 + 's). Tient compte du profil : dans le profil default, ce conseil appara' + #$00EE +
        't ; qui veut des rapports d''hygi' + #$00E8 + 'ne des suppressions sans le bruit des d' +
        #$00E9 + 'tecteurs peut lancer l''analyse avec --profile selftest-quiet.'
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Variable locale non initialis' + #$00E9 + 'e';
      ShortDesc: 'Variable locale lue avant sa premi' + #$00E8 +
        're affectation dans l''ordre du source, ou jamais affect' + #$00E9 + 'e';
      FullDesc : 'Les variables locales de types non manag' + #$00E9 +
        's (Integer, Boolean, Pointer, record, instance de classe) d' + #$00E9 +
        'marrent avec un contenu ind' + #$00E9 +
        'fini. Les lire avant affectation donne des valeurs parasites ou une violation d''acc' +
        #$00E8 + 's - un bug de plantage classique. Le d' + #$00E9 +
        'tecteur parcourt les instructions de chaque m' + #$00E9 +
        'thode dans l''ordre du source et suit la premi' + #$00E8 + 're ' + #$00E9 +
        'criture et la premi' + #$00E8 +
        're lecture de chaque variable locale : une variable lue mais jamais ' + #$00E9 +
        'crite est signal' + #$00E9 + 'e avec une confiance ' + #$00E9 + 'lev' + #$00E9 +
        'e, une lecture qui pr' + #$00E9 + 'c' + #$00E8 + 'de la premi' + #$00E8 + 're ' + #$00E9 +
        'criture dans l''ordre du source avec une confiance moyenne. Le contr' + #$00F4 +
        'le n''est pas sensible aux chemins - une ' + #$00E9 +
        'criture dans une branche compte pour toutes les lignes situ' + #$00E9 +
        'es en dessous, donc `if Cond then L := TStringList.Create; L.Add(''x'');` n''est pas signal' +
        #$00E9 + '. Les ' + #$00E9 +
        'crivains connus de la RTL (Read, ReadLn, FillChar, Move, ZeroMemory, Initialize, New, GetMem) sont reconnus via une liste blanche ; les autres appels avec param' +
        #$00E8 + 'tres var/out sont trait' + #$00E9 + 's de fa' + #$00E7 +
        'on pessimiste comme des lectures (faux n' + #$00E9 +
        'gatifs, mais pas de faux positifs). Les types manag' + #$00E9 + 's initialis' + #$00E9 +
        's automatiquement par Pascal (string, tableau dynamique, interface) sont ignor' + #$00E9 +
        's, sauf activation via l''INI. Les m' + #$00E9 + 'thodes qui d' + #$00E9 +
        'passent des plafonds configurables (200 variables locales / 5000 instructions, par d' +
        #$00E9 + 'faut) sont exclues de l''analyse pour ' + #$00E9 + 'viter un co' + #$00FB +
        't pathologique dans le pire cas.'
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Appel ' + #$00E0 + ' Random sans Randomize pr' + #$00E9 + 'alable';
      ShortDesc: 'Random / RandomRange / RandomFrom sans Randomize - un germe ' + #$00E0 + ' 0 produit la m' +
        #$00EA + 'me suite ' + #$00E0 + ' chaque ex' + #$00E9 + 'cution';
      FullDesc : 'La fonction Random de Delphi utilise un germe interne qui vaut 0 au d' + #$00E9 +
        'marrage du programme. Tant que Randomize n''a pas ' + #$00E9 + 't' + #$00E9 + ' appel' +
        #$00E9 + ' une fois (g' + #$00E9 + 'n' + #$00E9 + 'ralement au d' + #$00E9 + 'but de l''ex' +
        #$00E9 + 'cution du programme), Random renvoie la m' + #$00EA + 'me suite de valeurs ' +
        #$00E0 + ' chaque lancement du programme. Le d' + #$00E9 + 'tecteur parcourt l''AST ' +
        #$00E0 + ' la recherche de tous les appels et ignore l''unit' + #$00E9 + ' enti' + #$00E8 +
        're si un appel ' + #$00E0 + ' Randomize s''y trouve n''importe o' + #$00F9 +
        '. Sinon, chaque appel ' + #$00E0 + ' Random / RandomRange / RandomFrom est signal' + #$00E9 +
        '. Remarque : les appels ' + #$00E0 + ' Randomize dans d''autres unit' + #$00E9 +
        's (p. ex. dans le bloc initialization d''une unit' + #$00E9 + ' utilis' + #$00E9 +
        'e) ne sont pas d' + #$00E9 + 'tect' + #$00E9 +
        's ; masquer avec `// noinspection InsecureRandom` le cas ' + #$00E9 + 'ch' + #$00E9 +
        'ant. Pour les usages cryptographiques (g' + #$00E9 + 'n' + #$00E9 +
        'ration de jetons, sels, codes de r' + #$00E9 +
        'initialisation de mot de passe), Random ne convient pas, avec ou sans Randomize - utiliser des TBytes issus d''un CSPRNG (p. ex. CryptGenRandom sous Windows, /dev/urandom sous POSIX).'
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'Instruction case sans branche else';
      ShortDesc: 'L''instruction case n''a pas de branche else - les valeurs non trait' + #$00E9 +
        'es passent silencieusement ; un else suivant un if dans le dernier bras est le else du case';
      FullDesc : 'Une instruction case sans branche else ignore silencieusement toutes les valeurs qui ne sont pas list' +
        #$00E9 +
        'es explicitement. Quand l''expression du case prend l''une de ces valeurs non trait' +
        #$00E9 + 'es, aucune action n''a lieu et aucune erreur n''est lev' + #$00E9 +
        'e, ce qui peut masquer des bugs de logique (surtout quand de nouvelles valeurs d''' +
        #$00E9 + 'num' + #$00E9 + 'ration sont ajout' + #$00E9 +
        'es plus tard sans que les instructions case soient mises ' + #$00E0 +
        ' jour). Ajouter `else ;` pour un no-op voulu (qui documente la d' + #$00E9 +
        'cision) ou un traitement par d' + #$00E9 + 'faut qui l' + #$00E8 +
        've une exception / journalise / fait une assertion. Remarque pour la comparaison avec une version ant' +
        #$00E9 +
        'rieure : jusqu''en 2026-08, le parseur rattachait un else suivant un if dans le dernier bras (`3: if C then Foo; else Bar;`) ' +
        #$00E0 + ' ce if plut' + #$00F4 + 't qu''au case, si bien que la r' + #$00E8 +
        'gle signalait une branche else manquante sur des instructions case qui en avaient manifestement une. Ces faux positifs ont disparu - 148 sur le corpus de r' +
        #$00E9 + 'f' + #$00E9 + 'rence - et rien n''a chang' + #$00E9 + ' dans ce que la r' + #$00E8 +
        'gle compte comme violation.'
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'L''argument d''Assert contient un appel ' + #$00E0 + ' effet de bord';
      ShortDesc: 'Assert(SomeCall) - l''appel dispara' + #$00EE +
        't en build Release et son effet de bord est perdu silencieusement';
      FullDesc : 'Le compilateur Delphi supprime enti' + #$00E8 + 'rement les appels ' + #$00E0 +
        ' Assert des builds Release (sauf si DCC_Assertions est activ' + #$00E9 +
        '). Si l''expression v' + #$00E9 + 'rifi' + #$00E9 + 'e contient un appel de fonction ' +
        #$00E0 + ' effet de bord (allocation, modification d''' + #$00E9 + 'tat, E/S, incr' + #$00E9 +
        'mentation de compteur), l''effet de bord dispara' + #$00EE +
        't aussi - le comportement en Release diverge de celui en Debug. Le d' + #$00E9 +
        'tecteur signale les appels ' + #$00E0 +
        ' Assert dont l''argument contient un motif d''appel de fonction, apr' + #$00E8 +
        's exclusion d''une liste blanche de fonctions RTL connues comme pures (Length, Assigned, SizeOf, IntToStr, ...). Sortir l''appel de l''Assert et v' +
        #$00E9 + 'rifier plut' + #$00F4 + 't son r' + #$00E9 + 'sultat.'
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'Param' + #$00E8 + 'tre string sans const';
      ShortDesc: 'Param' + #$00E8 + 'tre string d' + #$00E9 + 'clar' + #$00E9 +
        ' sans const - provoque une incr' + #$00E9 + 'mentation du compteur de r' + #$00E9 + 'f' +
        #$00E9 + 'rences ' + #$00E0 + ' chaque appel';
      FullDesc : 'Delphi incr' + #$00E9 + 'mente le compteur de r' + #$00E9 + 'f' + #$00E9 +
        'rences de la cha' + #$00EE + 'ne ' + #$00E0 + ' chaque appel quand le param' + #$00E8 +
        'tre est d' + #$00E9 + 'clar' + #$00E9 +
        ' sans `const`. Avec `const`, le compilateur passe une r' + #$00E9 + 'f' + #$00E9 +
        'rence pure et ' + #$00E9 + 'vite l''aller-retour du compteur de r' + #$00E9 + 'f' + #$00E9 +
        'rences. Le compilateur interdit aussi l''affectation ' + #$00E0 + ' un param' + #$00E8 +
        'tre `const`, ce qui rend explicite le contrat de non-modification. Pour les param' + #$00E8 +
        'tres string non modifi' + #$00E9 + 's (l''' + #$00E9 + 'crasante majorit' + #$00E9 +
        '), pr' + #$00E9 + 'f' + #$00E9 + 'rer `const`. Le d' + #$00E9 + 'tecteur signale les param' +
        #$00E8 +
        'tres dont le type est `string`/`AnsiString`/`UnicodeString`/`WideString`/`RawByteString`/`ShortString` sans `const`/`var`/`out`.'
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Aiguillage de compilation OFF sans ON correspondant dans le fichier';
      ShortDesc: '{$WARNINGS OFF} (ou HINTS/RANGECHECKS/...) sans ON de fermeture - d' + #$00E9 +
        'borde sur les unit' + #$00E9 + 's suivantes';
      FullDesc : 'Les directives d''' + #$00E9 +
        'tat du compilateur Delphi comme {$WARNINGS OFF}, {$HINTS OFF}, {$RANGECHECKS OFF}, {$BOOLEVAL OFF}, {$OVERFLOWCHECKS OFF} modifient l''' +
        #$00E9 + 'tat du compilateur pour tout ce qui est compil' + #$00E9 + ' apr' + #$00E8 +
        's elles. Si le OFF n''est pas suivi d''un ON de fermeture dans le m' + #$00EA +
        'me fichier, l''aiguillage d' + #$00E9 + 'borde sur toutes les unit' + #$00E9 +
        's de compilation suivantes du m' + #$00EA +
        'me build et supprime avertissements/conseils/contr' + #$00F4 + 'les bien au-del' + #$00E0 +
        ' de la port' + #$00E9 + 'e voulue. Le d' + #$00E9 +
        'tecteur compte les OFF et les ON par nom de directive dans le fichier et signale toute directive dont les OFF sont plus nombreux que les ON en fin de fichier.'
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Propri' + #$00E9 + 't' + #$00E9 + ' bool' + #$00E9 + 'enne sans pr' + #$00E9 +
        'fixe Is / Has / Can / Should';
      ShortDesc: 'Le nom de la propri' + #$00E9 + 't' + #$00E9 + ' bool' + #$00E9 +
        'enne se lit comme un substantif - pr' + #$00E9 + 'f' + #$00E9 + 'rer un pr' + #$00E9 +
        'fixe verbal qui se lit comme une question';
      FullDesc : 'Une propri' + #$00E9 + 't' + #$00E9 + ' bool' + #$00E9 + 'enne nomm' + #$00E9 +
        'e comme un substantif se lit de fa' + #$00E7 + 'on ambigu' + #$00EB +
        ' aux points d''appel (`if X.Active then` contre `if X.IsActive then`). Pr' + #$00E9 + 'f' +
        #$00E9 + 'rer un pr' + #$00E9 +
        'fixe verbal (`Is`/`Has`/`Can`/`Should`/`Will`) qui fait lire naturellement le point d''appel comme une question. Le d' +
        #$00E9 + 'tecteur signale les propri' + #$00E9 + 't' + #$00E9 + 's bool' + #$00E9 +
        'ennes dont le nom ne commence pas par l''un de ces pr' + #$00E9 +
        'fixes, avec une liste blanche int' + #$00E9 + 'gr' + #$00E9 + 'e de conventions VCL ' +
        #$00E9 +
        'tablies (Enabled, Visible, Active, Checked, Modified, ReadOnly, Selected, Focused, Loaded, Modified, Dirty, ...).'
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant dans une m' + #$00E9 + 'thode sensible aux performances (avec boucle)';
      ShortDesc: 'Variable Variant dans une m' + #$00E9 + 'thode contenant une boucle - chaque op' + #$00E9 +
        'ration Variant paie un surco' + #$00FB + 't de dispatch COM de 10 ' + #$00E0 + ' 100 fois';
      FullDesc : 'Les op' + #$00E9 + 'rations sur Variant passent par le r' + #$00E9 +
        'partiteur COM VarType (VarAdd, VarCmp, VarCast, ...), ce qui ajoute un aller-retour par le syst' +
        #$00E8 + 'me de types ' + #$00E0 + ' chaque lecture, ' + #$00E9 +
        'criture, comparaison et conversion. Dans une boucle critique, ce co' + #$00FB +
        't est multipli' + #$00E9 + ' par le nombre d''it' + #$00E9 +
        'rations et peut dominer le temps d''ex' + #$00E9 + 'cution de la m' + #$00E9 +
        'thode. Le d' + #$00E9 + 'tecteur signale chaque variable locale et chaque param' + #$00E8 +
        'tre Variant / OleVariant dans les m' + #$00E9 +
        'thodes qui contiennent au moins une boucle for/while/repeat. Les cas d''usage accept' +
        #$00E9 +
        's (ponts COM/OLE, adaptateurs JSON-Variant, automatisation Excel) se traitent via le marqueur de suppression `// noinspection VariantTypeMisuse`.'
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> rempli de T.Create - les ' + #$00E9 + 'l' + #$00E9 + 'ments fuient ' + #$00E0 +
        ' la lib' + #$00E9 + 'ration';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - la liste ne poss' + #$00E8 + 'de pas ses ' +
        #$00E9 + 'l' + #$00E9 + 'ments, chaque instance TFoo fuit';
      FullDesc : 'TList<T> est un conteneur typ' + #$00E9 + ' qui ne poss' + #$00E8 + 'de PAS ses ' + #$00E9 +
        'l' + #$00E9 + 'ments - lib' + #$00E9 + 'rer la liste ne lib' + #$00E8 + 're pas les ' +
        #$00E9 + 'l' + #$00E9 + 'ments qu''elle contient. Quand les ' + #$00E9 + 'l' + #$00E9 +
        'ments sont des instances de classe allou' + #$00E9 + 'es avec .Create, ils fuient ' +
        #$00E0 + ' chaque lib' + #$00E9 + 'ration de la liste, sauf si l''appelant parcourt et lib' +
        #$00E8 +
        're manuellement chacun d''eux. Le bon conteneur est TObjectList<T> de Generics.Collections, qui a OwnsObjects=True par d' +
        #$00E9 + 'faut et lib' + #$00E8 + 're ses ' + #$00E9 + 'l' + #$00E9 + 'ments ' + #$00E0 +
        ' sa destruction. Le d' + #$00E9 + 'tecteur parcourt chaque m' + #$00E9 +
        'thode, collecte toutes les affectations `TList<T>.Create` (o' + #$00F9 +
        ' T est un identificateur qui ressemble ' + #$00E0 +
        ' une classe), puis recherche des motifs `<varname>.Add(<T>.Create)` dans la m' + #$00EA +
        'me m' + #$00E9 + 'thode. La possession entre m' + #$00E9 + 'thodes (Add dans une autre m' +
        #$00E9 + 'thode que Create) n''est pas suivie.'
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'M' + #$00E9 + 'thode anonyme capturant la variable de boucle par r' + #$00E9 + 'f' + #$00E9 +
        'rence';
      ShortDesc: 'Une m' + #$00E9 + 'thode anonyme dans `for i := ... do` r' + #$00E9 + 'f' + #$00E9 +
        'rence i - toutes les closures voient la m' + #$00EA + 'me valeur finale';
      FullDesc : 'Delphi capture les variables par r' + #$00E9 + 'f' + #$00E9 + 'rence dans les m' + #$00E9 +
        'thodes anonymes. Quand la m' + #$00E9 + 'thode anonyme est cr' + #$00E9 + #$00E9 +
        'e dans une boucle for et r' + #$00E9 + 'f' + #$00E9 +
        'rence la variable de boucle, toutes les closures partagent la m' + #$00EA + 'me r' + #$00E9 +
        'f' + #$00E9 + 'rence - au moment o' + #$00F9 + ' les closures s''ex' + #$00E9 +
        'cutent, la variable de boucle a atteint sa valeur terminale et toutes observent cette valeur finale. Le sympt' +
        #$00F4 + 'me classique : N threads parall' + #$00E8 + 'les cr' + #$00E9 + #$00E9 +
        's dans une boucle journalisent tous le num' + #$00E9 + 'ro de la derni' + #$00E8 + 're it' +
        #$00E9 + 'ration au lieu de 0..N-1. Le d' + #$00E9 +
        'tecteur parcourt les instructions for, extrait le nom de la variable de boucle (`for i :=` classique ou `for var i :=` inline) et examine les descendants nkCall / nkAssign ' +
        #$00E0 + ' la recherche de la combinaison d''un mot-cl' + #$00E9 + ' `procedure` (d' +
        #$00E9 + 'but de m' + #$00E9 + 'thode anonyme) et d''une r' + #$00E9 + 'f' + #$00E9 +
        'rence ' + #$00E0 +
        ' la variable de boucle. Correction : copier la variable de boucle dans une variable locale juste avant le corps de la m' +
        #$00E9 + 'thode anonyme.'
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'M' + #$00E9 + 'thode ' + #$00E0 + ' forte complexit' + #$00E9 + ' cognitive (flot de contr' +
        #$00F4 + 'le imbriqu' + #$00E9 + ')';
      ShortDesc: 'La complexit' + #$00E9 + ' cognitive (style Sonar) d' + #$00E9 +
        'passe 15 - les if/for/while/case imbriqu' + #$00E9 + 's sont difficiles ' + #$00E0 +
        ' suivre mentalement';
      FullDesc : 'La complexit' + #$00E9 + ' cyclomatique (SCA022) compte les chemins ind' + #$00E9 +
        'pendants de fa' + #$00E7 + 'on lin' + #$00E9 + 'aire - dix instructions if ' + #$00E0 +
        ' plat p' + #$00E8 + 'sent autant qu''un if imbriqu' + #$00E9 +
        ' sur trois niveaux. La complexit' + #$00E9 +
        ' cognitive, introduite par Sonar en 2017, multiplie le co' + #$00FB +
        't de l''imbrication : chaque construction de flux de contr' + #$00F4 +
        'le ajoute 1 + profondeur d''imbrication. Trois boucles imbriqu' + #$00E9 +
        'es valent donc 1+2+3=6 au lieu de 3. Le d' + #$00E9 + 'tecteur parcourt chaque m' + #$00E9 +
        'thode avec une pile explicite plut' + #$00F4 + 't que par r' + #$00E9 +
        'cursion (ainsi, un code profond' + #$00E9 + 'ment imbriqu' + #$00E9 +
        ' ne peut pas faire d' + #$00E9 +
        'border la pile d''appels), en suivant la profondeur courante et la somme cumul' + #$00E9 +
        'e. Les op' + #$00E9 + 'rateurs bool' + #$00E9 +
        'ens (and/or/xor) dans les conditions if ajoutent +1 chacun. Seuil : 15 (valeur par d' +
        #$00E9 + 'faut de Sonar), configurable via l''INI [Detectors] CognitiveLimit.'
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Variable de thread utilis' + #$00E9 + 'e apr' + #$00E8 + 's FreeOnTerminate := True';
      ShortDesc: 'Apr' + #$00E8 + 's T.FreeOnTerminate := True, tout acc' + #$00E8 + 's ult' + #$00E9 +
        'rieur ' + #$00E0 + ' T.Field/T.Method risque une violation d''acc' + #$00E8 +
        's si le thread s''est d' + #$00E9 + 'j' + #$00E0 + ' auto-d' + #$00E9 + 'truit';
      FullDesc : 'TThread.FreeOnTerminate := True transf' + #$00E8 +
        're la possession de l''instance de thread au thread lui-m' + #$00EA + 'me - le thread lib' +
        #$00E8 + 're sa propre m' + #$00E9 +
        'moire dans son cycle de vie Execute-puis-Destroy. L''appelant DOIT abandonner imm' + #$00E9 +
        'diatement toutes ses r' + #$00E9 + 'f' + #$00E9 + 'rences au thread (en g' + #$00E9 + 'n' +
        #$00E9 + 'ral en mettant la variable locale ' + #$00E0 +
        ' nil), car il n''existe aucune synchronisation entre l''instruction suivante de l''appelant et l''autodestruction du thread. Le d' +
        #$00E9 + 'tecteur parcourt chaque m' + #$00E9 +
        'thode, collecte chaque affectation `<var>.FreeOnTerminate := True`, puis le premier `<var>.Start` ou `<var>.Resume` - ' +
        #$00E0 + ' partir de ce moment, le thread tourne et peut se lib' + #$00E9 + 'rer lui-m' +
        #$00EA + 'me - et signale chaque acc' + #$00E8 + 's `<var>.<member>` ult' + #$00E9 +
        'rieur (appel OU affectation) dans la m' + #$00EA + 'me m' + #$00E9 + 'thode, ' + #$00E0 +
        ' l''exception des appels de cycle de vie Start, Resume et Execute. Sans Start ni Resume dans la m' +
        #$00E9 + 'thode, rien n''est signal' + #$00E9 + '. Port' + #$00E9 + 'e par m' + #$00E9 +
        'thode : les r' + #$00E9 + 'f' + #$00E9 + 'rences entre m' + #$00E9 + 'thodes (thread d' +
        #$00E9 + 'tenu dans un champ et utilis' + #$00E9 + ' dans une autre m' + #$00E9 +
        'thode) ne sont pas suivies.'
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'API d''ouverture de fichier recevant une saisie utilisateur concat' + #$00E9 + 'n' + #$00E9 +
        'e';
      ShortDesc: 'Ouverture de fichier (TFileStream.Create, AssignFile, ...) avec un chemin construit ' +
        #$00E0 +
        ' partir d''une saisie utilisateur (Edit.Text, Request.Params, ...) - risque de path traversal';
      FullDesc : 'Vuln' + #$00E9 + 'rabilit' + #$00E9 + ' classique de path traversal : une saisie contr' +
        #$00F4 + 'l' + #$00E9 + 'e par l''utilisateur aboutit dans une API du syst' + #$00E8 +
        'me de fichiers. Un attaquant peut soumettre `../../../etc/passwd` ou ' + #$00E9 +
        'quivalent pour sortir du r' + #$00E9 + 'pertoire pr' + #$00E9 + 'vu et lire/' + #$00E9 +
        'crire des fichiers arbitraires. Le d' + #$00E9 +
        'tecteur signale les expressions qui contiennent ' + #$00E0 +
        ' la fois un jeton d''API d''ouverture de fichier (TFileStream.Create, TFile.OpenRead/WriteText, AssignFile, FileOpen, FileCreate) ET un jeton de source de saisie utilisateur (.Text, .Lines.Text, .Caption, .Value, Request.Params, Sender.Text, ParamStr) ' +
        'ET un op' + #$00E9 + 'rateur `+` (concat' + #$00E9 + 'nation de cha' + #$00EE +
        'nes). Le d' + #$00E9 +
        'tecteur est heuristique - pas de suivi de contamination - donc des fonctions d''assainissement enveloppantes (p. ex. `Sanitize(edPath.Text)`) d' +
        #$00E9 +
        'clenchent des faux positifs ; masquer via un marqueur si la fonction d''assainissement est fiable.'
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'Attribut DUnitX [Ignore] sans argument de justification';
      ShortDesc: '[Ignore] sans argument de type cha' + #$00EE +
        'ne ignore le test silencieusement - ajouter un message expliquant pourquoi il est d' +
        #$00E9 + 'sactiv' + #$00E9;
      FullDesc : 'DUnitX accepte [Ignore] ' + #$00E0 +
        ' la fois comme attribut marqueur et sous la forme [Ignore(''reason'')]. La forme marqueur ignore le test sans indiquer POURQUOI il a ' +
        #$00E9 + 't' + #$00E9 + ' d' + #$00E9 + 'sactiv' + #$00E9 + ' - le test d' + #$00E9 +
        'rive alors sans maintenance, souvent oubli' + #$00E9 + '. Toujours ajouter une cha' +
        #$00EE + 'ne de justification qui renvoie ' + #$00E0 + ' un ticket / une d' + #$00E9 +
        'pendance externe / une limitation connue, afin que la d' + #$00E9 + 'sactivation puisse ' +
        #$00EA + 'tre tri' + #$00E9 + 'e.'
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Le m' + #$00EA + 'me attribut appliqu' + #$00E9 + ' deux fois au m' + #$00EA + 'me membre';
      ShortDesc: 'Deux attributs [X] identiques sur le m' + #$00EA +
        'me membre - reste de copier-coller, sans effet';
      FullDesc : 'Le mod' + #$00E8 + 'le d''attributs de Delphi accepte les attributs r' + #$00E9 + 'p' +
        #$00E9 + 't' + #$00E9 + 's (certains, comme [TestCase], sont volontairement appliqu' +
        #$00E9 + 's plusieurs fois avec des arguments diff' + #$00E9 +
        'rents). Les doublons avec des arguments IDENTIQUES ne le sont pas ' + #$2014 + ' ce sont g' +
        #$00E9 + 'n' + #$00E9 + 'ralement des restes de copier-coller issus d''un refactoring. Le d' +
        #$00E9 +
        'tecteur compare les paires (nom d''attribut, texte des arguments) et signale les occurrences identiques dans le m' +
        #$00EA + 'me groupe d''attributs (lignes distantes de 2 au maximum). Les attributs appliqu' +
        #$00E9 + 's plusieurs fois avec des arguments diff' + #$00E9 +
        'rents ([TestCase(''A'',''1'')] / [TestCase(''B'',''2'')] diff' + #$00E9 +
        'rents) ne sont, ' + #$00E0 + ' juste titre, PAS signal' + #$00E9 + 's.'
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'Attribut DUnitX [Category] sans nom de cat' + #$00E9 + 'gorie';
      ShortDesc: '[Category] sans argument est une erreur de compilation dans DUnitX - toujours passer un nom de cat' +
        #$00E9 + 'gorie';
      FullDesc : 'L''attribut [Category] de DUnitX exige un argument cha' + #$00EE + 'ne qui sert ' + #$00E0 +
        ' regrouper les tests pour une ex' + #$00E9 + 'cution s' + #$00E9 +
        'lective. Sans cet argument, le compilateur l' + #$00E8 + 've une erreur de param' + #$00E8 +
        'tre manquant. Toujours passer un nom de cat' + #$00E9 +
        'gorie explicite (p. ex. ''Slow'', ''CI-only'', ''Integration'').'
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : 'Classe [TestFixture] sans aucune m' + #$00E9 + 'thode [Test]';
      ShortDesc: 'La classe est marqu' + #$00E9 + 'e [TestFixture] mais ne contient aucune m' + #$00E9 +
        'thode [Test] - fixture zombie, visible dans TestInsight mais qui n''ex' + #$00E9 +
        'cute rien';
      FullDesc : 'DUnitX d' + #$00E9 +
        'couvre les classes de test en recherchant les attributs [TestFixture]. Une fixture sans aucune m' +
        #$00E9 + 'thode [Test] appara' + #$00EE +
        't dans l''arbre des tests mais n''apporte aucun test ex' + #$00E9 +
        'cutable - typiquement un reste de refactoring (tests supprim' + #$00E9 +
        's, fixture conserv' + #$00E9 + 'e). Le d' + #$00E9 +
        'tecteur parcourt le texte du fichier avec une simple machine ' + #$00E0 + ' ' + #$00E9 +
        'tats : il entre dans la fen' + #$00EA +
        'tre de fixture sur la ligne [TestFixture], guette un [Test] ' + #$00E0 + ' l''int' + #$00E9 +
        'rieur et en sort au prochain `end;` de premier niveau. Si aucun [Test] n''a ' + #$00E9 +
        't' + #$00E9 + ' vu, la ligne [TestFixture] est signal' + #$00E9 +
        'e. Les fixtures ne contenant que [SetupFixture] (servant ' + #$00E0 + ' pr' + #$00E9 +
        'parer un ' + #$00E9 + 'tat partag' + #$00E9 +
        ' pour d''autres fixtures) sont un cas connu de faux positif - masquer avec `// noinspection AttributeTestFixtureWithoutTests`.'
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut suivi d''une ligne vide avant le membre cible';
      ShortDesc: 'Ligne d''attribut suivie d''une ligne vide - visuellement d' + #$00E9 + 'tach' + #$00E9 +
        'e, souvent un reste de refactoring';
      FullDesc : 'Le compilateur Delphi rattache un attribut au membre syntaxiquement suivant, quelles que soient les lignes vides intercal' +
        #$00E9 + 'es. Visuellement en revanche, un attribut s' + #$00E9 + 'par' + #$00E9 +
        ' de son membre par une ligne vide passe facilement inaper' + #$00E7 +
        'u - le lecteur peut ne pas se rendre compte que l''attribut s''applique au membre en dessous. C''est aussi un sympt' +
        #$00F4 + 'me fr' + #$00E9 + 'quent d''un refactoring o' + #$00F9 + ' un membre a ' + #$00E9 +
        't' + #$00E9 + ' d' + #$00E9 + 'plac' + #$00E9 + '/supprim' + #$00E9 +
        ' mais l''attribut est rest' + #$00E9 + '. Le d' + #$00E9 +
        'tecteur signale les lignes d''attribut dont la ligne non vide suivante se trouve ' + #$00E0 +
        ' plus d''une ligne de distance.'
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Composant DFM inutilis' + #$00E9;
      ShortDesc: 'Le composant DFM n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' ni dans le code, ni dans d''autres unit' + #$00E9 + 's, ni dans le DFM lui-m' + #$00EA +
        'me - probablement un reste de refactoring';
      FullDesc : 'Un composant d' + #$00E9 + 'clar' + #$00E9 + ' dans le .dfm n''a aucune liaison d''' +
        #$00E9 + 'v' + #$00E9 + 'nement, n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' par les propri' + #$00E9 + 't' + #$00E9 +
        's d''aucun autre composant (DataSource, Action, ActiveControl, ...), n''est jamais utilis' +
        #$00E9 + ' dans le code Pascal de la fiche elle-m' + #$00EA + 'me et n''est acc' + #$00E9 +
        'd' + #$00E9 + ' depuis aucune autre unit' + #$00E9 +
        ' via la variable globale de la fiche. Il s''agit tr' + #$00E8 +
        's probablement d''un reste de refactoring qui est toujours allou' + #$00E9 + ' ' + #$00E0 +
        ' l''ex' + #$00E9 +
        'cution. Comme la preuve d''utilisation repose sur les noms (pas de liaison exacte), cette r' +
        #$00E8 + 'gle est ' + #$00E9 +
        'mise avec une confiance faible et reste hors du profil de confiance par d' + #$00E9 +
        'faut jusqu''' + #$00E0 + ' sa validation sur du code r' + #$00E9 +
        'el. Les composants de champ persistants (T*Field) ainsi que les frames incorpor' + #$00E9 +
        'es / composants h' + #$00E9 + 'rit' + #$00E9 + 's sont ignor' + #$00E9 +
        's par prudence ; le d' + #$00E9 + 'tecteur reste muet sans index inter-unit' + #$00E9 +
        's ' + #$00E0 + ' l''' + #$00E9 + 'chelle du d' + #$00E9 + 'p' + #$00F4 + 't.'
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'Fichier source UTF-8 sans BOM';
      ShortDesc: 'Fichier UTF-8 sans BOM contenant du non-ASCII - le compilateur le lit comme de l''ANSI (mojibake)';
      FullDesc : 'Un fichier source enregistr' + #$00E9 +
        ' en UTF-8 sans marque d''ordre des octets et contenant des caract' + #$00E8 +
        'res non-ASCII est lu par le compilateur Delphi comme de l''ANSI (page de codes syst' +
        #$00E8 + 'me, GetACP) - ce qui produit du mojibake dans les litt' + #$00E9 + 'raux de cha' +
        #$00EE + 'ne ' + #$00E0 + ' l''ex' + #$00E9 + 'cution, et le r' + #$00E9 + 'sultat d' +
        #$00E9 +
        'pend de la machine. Correction : enregistrer en UTF-8 avec BOM, ou compiler le projet avec --codepage:65001. Un caract' +
        #$00E8 + 're non-ASCII dans un litt' + #$00E9 + 'ral de cha' + #$00EE +
        'ne ou un identificateur est signal' + #$00E9 + ' avec une confiance moyenne (visible par d' +
        #$00E9 + 'faut) ; un fichier dont les caract' + #$00E8 +
        'res non-ASCII se trouvent uniquement dans des commentaires est signal' + #$00E9 +
        ' avec une confiance faible, car le compilateur ignore les commentaires. Dialecte FPC/Lazarus : cette r' +
        #$00E8 + 'gle est ignor' + #$00E9 + 'e quand l''analyse s''ex' + #$00E9 +
        'cute avec --dialect=fpc - l''UTF-8 sans BOM est la NORME de Lazarus (l''IDE Lazarus lui-m' +
        #$00EA + 'me enregistre sans BOM, et FPC lit l''UTF-8 par d' + #$00E9 +
        'faut), donc un BOM manquant n''y est pas un d' + #$00E9 + 'faut. Les r' + #$00E8 + 'gles s' +
        #$0153 + 'urs (UTF-8 invalide, sources ANSI) restent actives.'
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'S' + #$00E9 + 'quence UTF-8 invalide dans le fichier source';
      ShortDesc: 'UTF-8 mal form' + #$00E9 + ' (surlong, substitut ou hors plage) sous un BOM UTF-8';
      FullDesc : 'Le fichier porte un BOM UTF-8 mais contient des s' + #$00E9 +
        'quences d''octets qui ne sont pas de l''UTF-8 valide au sens de la RFC 3629 (encodages surlongs, substituts isol' +
        #$00E9 + 's ou points de code au-del' + #$00E0 +
        ' de U+10FFFF). Le compilateur Delphi les remplace silencieusement par U+FFFD, ce qui corrompt les caract' +
        #$00E8 + 'res concern' + #$00E9 + 's. R' + #$00E9 + 'encoder le fichier en UTF-8 propre.'
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'Octet NUL ou de contr' + #$00F4 + 'le dans le fichier source';
      ShortDesc: 'NUL ou octet de contr' + #$00F4 + 'le interdit - fichier binaire ou encodage mal d' +
        #$00E9 + 'tect' + #$00E9;
      FullDesc : 'Le fichier source contient un octet NUL ou un caract' + #$00E8 + 're de contr' + #$00F4 +
        'le interdit (en dessous de U+0020, hors tabulation / saut de ligne / retour chariot / saut de page). Cela signifie g' +
        #$00E9 + 'n' + #$00E9 + 'ralement que le fichier est binaire ou que son encodage a ' +
        #$00E9 + 't' + #$00E9 + ' mal d' + #$00E9 + 'tect' + #$00E9 +
        ' (par exemple de l''UTF-16 sans BOM, o' + #$00F9 +
        ' un octet sur deux vaut 0x00). Examiner le fichier et le r' + #$00E9 + 'encoder.'
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Caract' + #$00E8 + 're de contr' + #$00F4 + 'le bidirectionnel (Trojan Source)';
      ShortDesc: 'Caract' + #$00E8 + 're de contr' + #$00F4 +
        'le bidi override ou isolate - le source se lit autrement qu''il ne compile';
      FullDesc : 'Le fichier contient un caract' + #$00E8 + 're de contr' + #$00F4 +
        'le Unicode bidirectionnel de type override ou isolate (U+202A-202E, U+2066-2069, U+061C). Ces caract' +
        #$00E8 +
        'res peuvent faire s''afficher le code source pour un relecteur humain autrement qu''il n''est compil' +
        #$00E9 + ' - l''attaque Trojan Source (CVE-2021-42574, CWE-1007). Ils n''ont aucun usage l' +
        #$00E9 + 'gitime dans du source Delphi ; supprimer le caract' + #$00E8 + 're de contr' +
        #$00F4 + 'le.'
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'Fichier source ANSI avec du contenu non-ASCII';
      ShortDesc: 'Source 8 bits (sans BOM, pas de l''UTF-8 valide) - d' + #$00E9 +
        'pendant de la page de codes, non portable';
      FullDesc : 'Le fichier n''a pas de BOM, contient des octets non-ASCII et n''est pas de l''UTF-8 valide - il est donc r' +
        #$00E9 + 'ellement encod' + #$00E9 +
        ' sur 8 bits (ANSI). Le compilateur Delphi le lit dans la page de codes syst' + #$00E8 +
        'me (GetACP), ce qui rend les caract' + #$00E8 + 'res non-ASCII d' + #$00E9 +
        'pendants de la machine/des param' + #$00E8 + 'tres r' + #$00E9 +
        'gionaux et non portables. Enregistrer le fichier en UTF-8 avec BOM.'
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'Fichier source UTF-16';
      ShortDesc: 'Source UTF-16 - compile, mais inhabituel et peu commode pour les outils texte';
      FullDesc : 'Le fichier source est en UTF-16 (LE ou BE). Il compile, mais un source UTF-16 est inhabituel et pose des difficult' +
        #$00E9 +
        's aux outils texte (git diff, grep, hooks externes, revue de code). La convention est l''UTF-8 avec BOM. Sous le dialecte FPC (--dialect=fpc ou un projet Lazarus), le r' +
        #$00E9 + 'sultat est signal' + #$00E9 + ' ' + #$00E0 +
        ' la place comme ERREUR avec une confiance ' + #$00E9 + 'lev' + #$00E9 +
        'e : Free Pascal rejette les sources UTF-16, le fichier ne compile pas du tout.'
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'Fichier source UTF-32 / UCS-4';
      ShortDesc: 'Source UTF-32 - le compilateur Delphi le rejette avec l''erreur fatale F2438';
      FullDesc : 'Le fichier source est en UTF-32 / UCS-4 (d' + #$00E9 + 'tect' + #$00E9 +
        ' via sa marque d''ordre des octets). Le compilateur Delphi ne prend pas en charge cet encodage et s''interrompt avec l''erreur fatale F2438 (' +
        #$00AB + ' UCS-4 text encoding not supported. Convert to UCS-2 or UTF-8 ' + #$00BB +
        '). Convertir le fichier en UTF-8 (avec BOM) ou en UTF-16.'
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Caract' + #$00E8 + 're invisible ou de largeur nulle dans le source';
      ShortDesc: 'Caract' + #$00E8 + 're Unicode invisible ou de largeur nulle - vecteur de texte cach' +
        #$00E9 + ' et d''abus par homoglyphes';
      FullDesc : 'Le fichier contient un caract' + #$00E8 +
        're Unicode invisible ou de largeur nulle (U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 word-joiner, ou un U+FEFF ZWNBSP en milieu de fichier). De tels caract' +
        #$00E8 + 'res ne sont presque jamais l' + #$00E9 +
        'gitimes dans du source et peuvent masquer ou alt' + #$00E9 +
        'rer des identificateurs et du texte - ils font partie de la famille Trojan Source / caract' +
        #$00E8 + 'res invisibles (CWE-1007). Remarque : U+200D peut appara' + #$00EE + 'tre l' +
        #$00E9 + 'gitimement dans des litt' + #$00E9 + 'raux de cha' + #$00EE +
        'ne contenant des emoji.'
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Caract' + #$00E8 + 're non-ASCII dans un identificateur';
      ShortDesc: 'L''identificateur contient une lettre non-ASCII - risque d''homoglyphes et de caract' +
        #$00E8 + 'res confondables';
      FullDesc : 'Un identificateur (variable, type, routine, ...) contient un caract' + #$00E8 +
        're non-ASCII. C''est le vecteur des homoglyphes / identificateurs confondables de la famille Trojan Source (CVE-2021-42694, CWE-1007) : une lettre comme le cyrillique U+043E ressemble au ''o'' latin mais forme un identificateur diff' +
        #$00E9 + 'rent, si bien que deux identificateurs peuvent sembler identiques et pourtant d' +
        #$00E9 + 'signer des choses diff' + #$00E9 + 'rentes. Un identificateur Unicode l' + #$00E9 +
        'gitime est aussi possible, donc examiner avant de modifier ; pr' + #$00E9 + 'f' + #$00E9 +
        'rer des identificateurs ASCII pour la portabilit' + #$00E9 + ' et pour ' + #$00E9 +
        'viter la confusion.'
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Fichier source hors du projet';
      ShortDesc: 'Un fichier .pas/.dfm se trouve dans le dossier du projet mais n''est pas r' + #$00E9 + 'f' +
        #$00E9 + 'renc' + #$00E9 +
        ' par le projet (.dproj/.groupproj) - probablement un fichier source orphelin';
      FullDesc : 'S''ex' + #$00E9 +
        'cute uniquement pour les analyses de projet et de groupe de projets (--project / --project-group, ou choix d''un .dproj/.groupproj via le dialogue ''...''), o' +
        #$00F9 + ' la liste exacte des fichiers du projet (DCCReferences) est connue. Le d' + #$00E9 +
        'tecteur parcourt r' + #$00E9 + 'cursivement le r' + #$00E9 + 'pertoire du fichier projet ' +
        #$00E0 +
        ' la recherche de fichiers .pas et .dfm et signale chacun de ceux que le projet ne r' +
        #$00E9 + 'f' + #$00E9 + 'rence pas. Un .dfm compte comme inclus quand son .pas associ' +
        #$00E9 + ' est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + '. Les fichiers qui SONT tir' +
        #$00E9 + 's via uses sont signal' + #$00E9 + 's comme SCA195 ' + #$00E0 +
        ' la place (ils ne sont pas morts). Cas typiques : unit' + #$00E9 + 's laiss' + #$00E9 +
        'es apr' + #$00E8 + 's un refactoring, copies exp' + #$00E9 +
        'rimentales, ou fichiers retir' + #$00E9 +
        's du projet mais pas du disque. Limite v1 : seuls les fichiers DANS l''arborescence du dossier du projet sont contr' +
        #$00F4 + 'l' + #$00E9 + 's - les unit' + #$00E9 + 's r' + #$00E9 + 'f' + #$00E9 + 'renc' +
        #$00E9 + 'es depuis l''ext' + #$00E9 +
        'rieur via des DCCReferences relatives en ''..'' et les unit' + #$00E9 +
        's du chemin de recherche ne sont ni parcourues ni signal' + #$00E9 + 'es. Les analyses r' +
        #$00E9 + 'cursives de r' + #$00E9 + 'pertoire et les analyses d''un seul fichier n''ex' +
        #$00E9 + 'cutent pas ce contr' + #$00F4 +
        'le (pas de notion d''appartenance au projet). Correction : supprimer le fichier, ou le sortir du dossier du projet (s''il est r' +
        #$00E9 + 'ellement utilis' + #$00E9 + ', SCA195 indique au contraire de l''ajouter).'
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit' + #$00E9 + ' utilis' + #$00E9 + 'e par le projet mais non incluse dedans';
      ShortDesc: 'Un fichier .pas est tir' + #$00E9 + ' par les unit' + #$00E9 +
        's du projet via uses (il compile gr' + #$00E2 +
        'ce au chemin de recherche) mais n''est pas list' + #$00E9 +
        ' dans le fichier projet (.dproj/.groupproj) - l''ajouter au projet';
      FullDesc : 'S''ex' + #$00E9 +
        'cute uniquement pour les analyses de projet et de groupe de projets (--project / --project-group, ou choix d''un .dproj/.groupproj via le dialogue ''...''). S' +
        #$00E9 + 'par' + #$00E9 + 'e de SCA194 (qui signale les fichiers r' + #$00E9 +
        'ellement orphelins) : un fichier qui EST tir' + #$00E9 +
        ' via uses - directement ou transitivement par d''autres unit' + #$00E9 +
        's de ce type - n''est pas du code mort. Il compile gr' + #$00E2 +
        'ce au chemin de recherche, mais reste invisible pour la gestion de projet : pas de navigation de projet dans l''IDE, facile ' +
        #$00E0 + ' manquer lors des revues, des d' + #$00E9 +
        'ploiements et du verrouillage de versions, et un renommage/d' + #$00E9 +
        'placement ne casse le build qu''' + #$00E0 + ' la prochaine compilation compl' + #$00E8 +
        'te. La correction consiste ' + #$00E0 +
        ' ajouter le fichier au projet. Les commentaires et les litt' + #$00E9 + 'raux de cha' +
        #$00EE + 'ne ne comptent jamais comme r' + #$00E9 + 'f' + #$00E9 +
        'rence uses ; la correspondance compare le nom de fichier sans extension aux noms d''unit' +
        #$00E9 + 's (' + #$00E9 + 'ventuellement point' + #$00E9 + 's) des clauses uses.'
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Le Result d''un type manag' + #$00E9 + ' est lu avant d''avoir ' + #$00E9 + 't' + #$00E9 +
        ' affect' + #$00E9;
      ShortDesc: 'Le Result d''un type de retour manag' + #$00E9 + ' est lu avant la premi' + #$00E8 +
        're affectation - il est un alias de la variable cible de l''appelant et porte son ANCIENNE valeur. L''initialiser d''abord (nil / [] / '''')';
      FullDesc : 'Pour les types de retour manag' + #$00E9 + 's, le compilateur passe Result comme param' +
        #$00E8 + 'tre var cach' + #$00E9 +
        ', alias de la variable cible de l''appelant, Y COMPRIS son contenu pr' + #$00E9 + 'c' +
        #$00E9 + 'dent (System.Rtti UseResultPointer ; la RTL elle-m' + #$00EA + 'me s''en prot' +
        #$00E8 +
        'ge, p. ex. TStringBuilder.ToString commence par Result := '''' ''to prevent copying of existing data''). Result n''est donc PAS initialis' +
        #$00E9 + ' ' + #$00E0 + ' ''''/nil/vide ' + #$00E0 + ' l''entr' + #$00E9 +
        'e. Le lire avant la premi' + #$00E8 +
        're affectation - Result := Result + [x], Result[i] := ... sans SetLength pr' + #$00E9 +
        'alable, Result.Add(...), Exit(Result + ...) - traite des donn' + #$00E9 + 'es p' + #$00E9 +
        'rim' + #$00E9 + 'es de l''appelant : le sympt' + #$00F4 +
        'me classique est une fonction collectrice dont le second appel ajoute aux r' + #$00E9 +
        'sultats du premier. Le conseil du compilateur W1035 (valeur de retour ind' + #$00E9 +
        'finie) reste MUET pr' + #$00E9 + 'cis' + #$00E9 +
        'ment pour ces types, donc rien d''autre n''avertit ici. La d' + #$00E9 +
        'tection suit purement l''ordre du source (variante 2, sans analyse de chemins) : le premier acc' +
        #$00E8 + 's ' + #$00E0 + ' Result dans le corps d' + #$00E9 + 'cide ; tout ce qui ' + #$00E9 +
        'crit ou peut ' + #$00E9 +
        'crire Result (affectation directe, Exit(value), Result ou @Result pass' + #$00E9 +
        ' comme argument d''appel, comme SetLength(Result, n) ou TryGetValue(key, Result)) compte comme affectation et termine l''examen. Les fonctions avec un alias ''absolute Result'', les routines assembleur et les d' +
        #$00E9 + 'clarations sans corps sont ignor' + #$00E9 + 'es ; les litt' + #$00E9 +
        'raux de cha' + #$00EE +
        'ne contenant le mot ''result'' ne comptent jamais. Aveugle aux chemins par conception : une ' +
        #$00E9 + 'criture dans une branche suivie d''une lecture apr' + #$00E8 +
        's la branche n''est PAS signal' + #$00E9 + 'e (faux n' + #$00E9 +
        'gatif, pas faux positif) - une analyse sensible aux chemins est une suite pr' + #$00E9 +
        'vue. L''alias de r' + #$00E9 +
        'sultat par le nom de la fonction compte UNIQUEMENT comme cible d''affectation : dans un contexte d''expression, un nom de fonction nu est toujours un APPEL (r' +
        #$00E9 + 'cursif/sans param' + #$00E8 +
        'tre) - ''Result := Put;'' invoque la surcharge sans param' + #$00E8 +
        'tre et ne lit jamais Result ; ''Obj.Result'' est un champ ' + #$00E9 +
        'tranger. Les affectations jumelles sous IFDEF, les m' + #$00E9 + 'thodes anonymes incorpor' +
        #$00E9 + 'es (dont le Result appartient ' + #$00E0 +
        ' la fonction anonyme) et les idiomes de remplissage de tampon ''Result[0] := Char(Api(@Result[1], N))'' sont trait' +
        #$00E9 + 's comme des ' + #$00E9 + 'critures, pas comme des lectures. Pour les r' + #$00E9 +
        'sultats ShortString, ''Result[0] := #len'' est l''idiome d''initialisation de l''octet de longueur et compte comme premi' +
        #$00E8 + 're ' + #$00E9 + 'criture. L' + #$00E0 + ' o' + #$00F9 + ' cette r' + #$00E8 +
        'gle se d' + #$00E9 + 'clenche, SCA121 reste muette pour la m' + #$00EA + 'me fonction.'
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface d' + #$00E9 + 'clar' + #$00E9 + 'e sans GUID';
      ShortDesc: 'L''interface n''a pas de GUID - Supports() et QueryInterface() ne peuvent pas la demander ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution. En g' + #$00E9 + 'n' + #$00E9 +
        'rer un avec Ctrl+Maj+G';
      FullDesc : 'Une interface sans GUID n''existe qu''' + #$00E0 +
        ' la compilation. Supports(Obj, IFoo, X) comme Obj.QueryInterface(IFoo, X) r' + #$00E9 +
        'solvent l''interface via son GUID, donc aucun des deux ne compile avec une interface sans GUID - et l''erreur appara' +
        #$00EE + 't au point d''appel, souvent dans une autre unit' + #$00E9 + ' et longtemps apr' +
        #$00E8 + 's l''' + #$00E9 + 'criture de l''interface. Delphi g' + #$00E9 + 'n' + #$00E8 +
        're un nouveau GUID avec Ctrl+Maj+G lorsque le curseur se trouve dans la d' + #$00E9 +
        'claration de l''interface. La d' + #$00E9 + 'tection est lexicale : la d' + #$00E9 +
        'claration `IFoo = interface` (' + #$00E9 + 'ventuellement avec une liste d''anc' + #$00EA +
        'tres) est suivie du GUID optionnel entre crochets. Les d' + #$00E9 + 'clarations anticip' +
        #$00E9 + 'es (`IFoo = interface;`) sont ignor' + #$00E9 +
        'es parce qu''elles peuvent ne porter aucun GUID, et les types dispinterface sont hors du champ de cette r' +
        #$00E8 + 'gle.'
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Deux interfaces partagent le m' + #$00EA + 'me GUID';
      ShortDesc: 'Le m' + #$00EA +
        'me GUID figure sur plusieurs interfaces - Supports() renvoie celle enregistr' + #$00E9 +
        'e en premier, sans erreur de compilation. En g' + #$00E9 + 'n' + #$00E9 +
        'rer un nouveau avec Ctrl+Maj+G';
      FullDesc : 'Les GUID d''interface identifient l''interface ' + #$00E0 + ' l''ex' + #$00E9 +
        'cution et doivent ' + #$00EA + 'tre uniques dans tout le programme. D' + #$00E9 +
        'clarer une nouvelle interface en copiant la pr' + #$00E9 + 'c' + #$00E9 +
        'dente et en oubliant de r' + #$00E9 + 'g' + #$00E9 + 'n' + #$00E9 +
        'rer le GUID produit du code qui compile proprement et se comporte mal en silence : Supports(Obj, ISecond, X) r' +
        #$00E9 + 'ussit et renvoie la PREMI' + #$00C8 +
        'RE interface, si bien que les appels atterrissent sur les mauvaises m' + #$00E9 +
        'thodes ou qu''un transtypage semble fonctionner l' + #$00E0 + ' o' + #$00F9 +
        ' il ne le devrait pas. Rien dans la cha' + #$00EE + 'ne d''outils n''avertit ' + #$00E0 +
        ' ce sujet. Le contr' + #$00F4 +
        'le a besoin de toute l''analyse, pas d''un seul fichier : l''index est construit ' + #$00E0 +
        ' partir de la m' + #$00EA + 'me liste de fichiers que celle qui est analys' + #$00E9 +
        'e, donc la port' + #$00E9 + 'e suit la s' + #$00E9 + 'lection - r' + #$00E9 +
        'pertoire, projet (.dproj) ou groupe de projets (.groupproj). Le message nomme les autres d' +
        #$00E9 +
        'clarations avec fichier et ligne, car trouver le jumeau est le vrai travail. En mode fichier unique, la comparaison se limite ' +
        #$00E0 + ' ce fichier - ' + #$00AB + ' unique ' + #$00BB +
        ' n''est pas une affirmation qu''un seul fichier peut ' + #$00E9 + 'tayer.'
    ),
    // SCA199
    (
      RuleID   : 'SCA199';
      Name     : 'Le nom pass' + #$00E9 + ' ' + #$00E0 + ' ParamByName ne correspond pas aux param' + #$00E8 +
        'tres du SQL';
      ShortDesc: 'ParamByName(''x'') sur une requ' + #$00EA + 'te dont le SQL n''a pas de :x (erreur ' +
        #$00AB + ' param' + #$00E8 + 'tre introuvable ' + #$00BB + ' ' + #$00E0 + ' l''ex' + #$00E9 +
        'cution), ou un :y dans le SQL que la routine n''affecte jamais alors qu''elle renseigne les autres param' +
        #$00E8 + 'tres de la requ' + #$00EA + 'te';
      FullDesc : 'Le compilateur ne voit pas le lien entre Query.SQL et Query.ParamByName - ce sont deux cha' +
        #$00EE + 'nes. Un param' + #$00E8 + 'tre renomm' + #$00E9 +
        ', une faute de frappe ou un bloc copi' + #$00E9 +
        ' laisse un ParamByName dont le nom ne figure pas dans le SQL, et l''erreur n''appara' +
        #$00EE + 't qu''' + #$00E0 + ' l''ex' + #$00E9 +
        'cution de l''instruction : FireDAC, BDE, dbExpress, UniDAC, Zeos et ADO (Parameters.ParamByName) l' +
        #$00E8 + 'vent tous ' + #$00AB + ' param' + #$00E8 + 'tre introuvable ' + #$00BB +
        '. Le sens inverse est signal' + #$00E9 + ' pour les requ' + #$00EA +
        'tes que la routine cr' + #$00E9 + 'e elle-m' + #$00EA +
        'me : le SQL contient :y, la routine lie d''autres param' + #$00E8 + 'tres de cette requ' +
        #$00EA + 'te mais jamais y - l''ex' + #$00E9 + 'cution ' + #$00E9 +
        'choue alors avec un param' + #$00E8 + 'tre non li' + #$00E9 + ' (FireDAC : type de donn' +
        #$00E9 + 'es inconnu, Oracle : ORA-01008) ou lie silencieusement NULL. Le contr' + #$00F4 +
        'le op' + #$00E8 + 're par routine et par variable de requ' + #$00EA + 'te, en lisant ' +
        #$00E0 + ' partir du premier ''begin'' de la routine, et seulement lorsqu''il conna' +
        #$00EE + 't enti' + #$00E8 + 'rement le SQL de la requ' + #$00EA + 'te ' + #$00E0 +
        ' partir de litt' + #$00E9 + 'raux de cette routine : la requ' + #$00EA + 'te y est cr' +
        #$00E9 + #$00E9 + 'e (Q := TXxx.Create) ou son SQL est vid' + #$00E9 + ' ou affect' + #$00E9 +
        ' avant le premier Add, et chaque contribution est un litt' + #$00E9 + 'ral de cha' + #$00EE +
        'ne (sLineBreak et #13#10 compris). Les param' + #$00E8 + 'tres sont les :name hors des cha' +
        #$00EE +
        'nes et des commentaires SQL - aussi :@name (ADO, SQL Server), les noms avec $ ou # (Oracle) et :"noms entre guillemets" - et un nom compte comme pr' +
        #$00E9 + 'sent s''il correspond soit ' + #$00E0 + ' la lecture comme identificateur, soit ' +
        #$00E0 + ' la lecture de ParseSQL de Data.DB/ADODB, qui va jusqu''' + #$00E0 +
        ' l''espace, la virgule, le point-virgule ou la parenth' + #$00E8 +
        'se fermante suivants ; pour le sens du nom inconnu, un param' + #$00E8 +
        'tre dans un commentaire SQL compte aussi comme pr' + #$00E9 +
        'sent, car Data.DB, ADO et IBX le cr' + #$00E9 + 'ent quand m' + #$00EA +
        'me. Les transtypages ''::'', '':='' (PL/SQL), le positionnel '':1'', '':new.''/'':old.'' dans les corps de triggers et les param' +
        #$00E8 +
        'tres ''?'' ne sont pas des noms. Les noms se comparent sans tenir compte de la casse, comme le font toutes les biblioth' +
        #$00E8 + 'ques. Acc' + #$00E8 +
        's qui comptent comme liaison : ParamByName, Params.ParamByName, Parameters.ParamByName, FindParam, ParamValues[''a;b''], et pour Direct Oracle Access SetVariable, DeclareVariable, SetComplexVariable, SetLongVariable.'
    ),
    // SCA200
    (
      RuleID   : 'SCA200';
      Name     : 'Adresse IP en litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne';
      ShortDesc: 'Adresse IPv4 ou IPv6 cod' + #$00E9 + 'e en dur (priv' + #$00E9 + 'e, partag' + #$00E9 +
        'e ou publique) dans un litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne - la d' + #$00E9 +
        'placer dans la configuration ou utiliser un nom d''h' + #$00F4 + 'te';
      FullDesc : 'Une adresse IP ' + #$00E9 + 'crite dans le source lie le programme ' + #$00E0 + ' un r' +
        #$00E9 + 'seau : chaque passage ' + #$00E0 + ' un autre serveur, ' + #$00E0 +
        ' un autre environnement (d' + #$00E9 + 'veloppement, test, production) ou ' + #$00E0 +
        ' un autre client exige une modification du code et un nouveau build, et l''adresse r' +
        #$00E9 + 'v' + #$00E8 + 'le la topologie interne ' + #$00E0 +
        ' quiconque lit le binaire. Lire l''adresse depuis la configuration, la ligne de commande ou l''environnement, ou utiliser un nom d''h' +
        #$00F4 + 'te que le DNS r' + #$00E9 + 'sout selon l''environnement. La r' + #$00E8 +
        'gle ne lit que les litt' + #$00E9 + 'raux de cha' + #$00EE +
        'ne - jamais les commentaires - et reconna' + #$00EE + 't l''IPv4 sous forme d' + #$00E9 +
        'cimale point' + #$00E9 + 'e stricte (quatre octets 0-255, sans z' + #$00E9 + 'ros de t' +
        #$00EA +
        'te) et l''IPv6 sous toutes les formes de la RFC 4291, y compris une zone (%eth0), des crochets avec un port ([...]:443) et une IPv4 incorpor' +
        #$00E9 + 'e (::ffff:10.1.2.3). Sont signal' + #$00E9 + 'es les adresses priv' + #$00E9 +
        'es (RFC 1918, unique local fc00::/7), les adresses partag' + #$00E9 +
        'es (100.64.0.0/10) et les adresses publiques. Ne sont pas signal' + #$00E9 +
        's : loopback, adresse non sp' + #$00E9 + 'cifi' + #$00E9 +
        'e (0.0.0.0, ::), broadcast, masques de r' + #$00E9 +
        'seau, link-local, les plages de documentation (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32, 3fff::/20), les blocs de protocole de l''IETF, le benchmarking (198.18.0.0/15), le multicast et l''espace r' +
        #$00E9 + 'serv' + #$00E9 + '. Les unit' + #$00E9 + 's de test (nommage et r' + #$00E9 +
        'pertoires test/spec) sont ignor' + #$00E9 +
        'es. Une adresse dans une URL http:// est aussi signal' + #$00E9 +
        'e par SCA115 : les deux r' + #$00E8 + 'gles d' + #$00E9 + 'crivent des probl' + #$00E8 +
        'mes diff' + #$00E9 + 'rents, le transport en clair et une adresse fixe.'
    ),
    // SCA201
    (
      RuleID   : 'SCA201';
      Name     : 'Adresse IP dans un fichier de configuration versionn' + #$00E9;
      ShortDesc: 'Adresse IPv4 ou IPv6 (priv' + #$00E9 + 'e, partag' + #$00E9 +
        'e ou publique) comme valeur dans un fichier .ini de l''arborescence des sources';
      FullDesc : 'Un fichier de configuration dans l''arborescence des sources est versionn' + #$00E9 +
        ' et livr' + #$00E9 +
        ' comme du code : une adresse IP qu''il contient fige chaque checkout et chaque installation sur un r' +
        #$00E9 + 'seau, et passer ' + #$00E0 +
        ' un autre serveur ou environnement exige de nouveau un commit. Garder les adresses propres ' +
        #$00E0 + ' un environnement hors du contr' + #$00F4 +
        'le de version (un fichier par machine ou par environnement, l''environnement, une ' +
        #$00E9 + 'tape de d' + #$00E9 + 'ploiement) ou utiliser un nom d''h' + #$00F4 + 'te. La r' +
        #$00E8 + 'gle lit les fichiers .ini de l''arborescence analys' + #$00E9 +
        'e - dans les analyses de dossier, avec le m' + #$00EA + 'me parcours de r' + #$00E9 +
        'pertoires que pour les sources, dans les analyses de projet, sous la racine commune des unit' +
        #$00E9 +
        's du projet ; ni analyser.ini ni les copies dans les dossiers de sortie de plateforme comme Win32 ou Win64 sous la racine analys' +
        #$00E9 + 'e. Les lignes commen' + #$00E7 +
        'ant par '';'' ou ''#'' sont des commentaires, les en-t' + #$00EA + 'tes de section (m' +
        #$00EA + 'me suivis d''un commentaire) sont ignor' + #$00E9 +
        's, et la valeur est tout ce qui suit le premier ''=''. La grammaire des adresses, les classes et les exclusions sont celles de SCA200 ; en outre, les cl' +
        #$00E9 +
        's qui portent de la prose (description, help, hint, comment, caption, text, example, note, title, summary) et les cl' +
        #$00E9 + 's de version ne sont pas signal' + #$00E9 +
        'es. Masquer une ligne avec un marqueur occupant toute la ligne ''; noinspection HardcodedIpInConfig'' (ou ''#'') juste au-dessus, ou tout le fichier avec ''; noinspection-file HardcodedIpInConfig''.'
    ),
    // SCA202
    (
      RuleID   : 'SCA202';
      Name     : 'not, and, or ou xor s''applique avant la comparaison';
      ShortDesc: '''not Count > 0'' ou ''A = True or B = False'' - not/and/or/xor sont prioritaires sur les comparaisons, l''expression compile mais teste autre chose';
      FullDesc : 'En Pascal, les op' + #$00E9 +
        'rateurs not, and, or et xor sont prioritaires sur les comparaisons (=, <>, <, >, <=, >=, in) - c''est pareil en Delphi et en Free Pascal. Deux ' +
        #$00E9 +
        'critures compilent donc sans message et testent autre chose que ce qu''elles semblent dire. (1) ''not'' devant une comparaison : ''if not List.Count > 0'' est ''(not List.Count) > 0''. Pour un entier, not est le compl' +
        #$00E9 + 'ment bit ' + #$00E0 +
        ' bit, donc la condition est fausse pour tout Count >= 0 ; ''not Key in [...]'' et ''not Result = mrOk'' ' +
        #$00E9 + 'chouent de la m' + #$00EA + 'me fa' + #$00E7 + 'on. (2) Comparaisons encha' +
        #$00EE + 'n' + #$00E9 +
        'es par and/or/xor : ''if A = True or B = False'' est ''(A = (True or B)) = False''. Cela ne compile que si les op' +
        #$00E9 + 'randes sont Boolean (ou Variant) - avec des entiers, des cha' + #$00EE +
        'nes, des ' + #$00E9 + 'num' + #$00E9 + 'rations ou des ensembles, le compilateur signale d' +
        #$00E9 + 'j' + #$00E0 + ' une erreur de type. Mettre la comparaison entre parenth' + #$00E8 +
        'ses : ''not (List.Count > 0)'', ''(A = True) or (B = False)'' - ou supprimer la comparaison avec True/False. La s' +
        #$00E9 + 'v' + #$00E9 + 'rit' + #$00E9 + ' est Erreur quand le type est ' + #$00E9 +
        'tabli (un nombre ou un ensemble de nombres ' + #$00E0 +
        ' droite, Pos/Ord/Length/CompareText... ou .Count/.IndexOf comme op' + #$00E9 +
        'rande, une variable locale, un param' + #$00E8 +
        'tre ou un champ de type entier, True/False dans la cha' + #$00EE +
        'ne) et Avertissement sinon. Sont lus les conditions de if/while/until/case et les membres droits de := ; les commentaires, les litt' +
        #$00E9 + 'raux de cha' + #$00EE + 'ne (y compris les cha' + #$00EE +
        'nes multilignes de Delphi 12) et les blocs asm ne comptent jamais comme du code.'
    ),
    // SCA203
    (
      RuleID   : 'SCA203';
      Name     : 'La boucle for d' + #$00E9 + 'passe le dernier indice';
      ShortDesc: 'La boucle for va jusqu''' + #$00E0 + ' Count, Length() ou High() + 1 et indexe la m' +
        #$00EA + 'me collection avec la variable de boucle - le dernier passage est hors limites';
      FullDesc : 'Un off-by-one classique : ''for i := 0 to List.Count do'' avec List[i] dans le corps lit List[List.Count], un ' +
        #$00E9 + 'l' + #$00E9 + 'ment au-del' + #$00E0 + ' de la fin. Le compilateur l''accepte ; ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution, cela l' + #$00E8 +
        've ERangeError avec {$R+}, EArgumentOutOfRangeException ou EStringListError pour TList et TStrings, et sinon lit ou ' +
        #$00E9 + 'crit silencieusement la m' + #$00E9 + 'moire situ' + #$00E9 + 'e apr' + #$00E8 +
        's le dernier ' + #$00E9 + 'l' + #$00E9 + 'ment. Sont signal' + #$00E9 + 'es les t' + #$00EA +
        'tes de boucle dont la borne sup' + #$00E9 +
        'rieure va un indice trop loin - ''X.Count'' (depuis 0, ou depuis 1 quand X est une liste prouv' +
        #$00E9 +
        'e), ''Length(A)'' depuis 0, ''Low(A) to Length(A)'' pour un tableau dynamique, ''High(A) + 1'' - quand le corps lit ou ' +
        #$00E9 + 'crit la m' + #$00EA + 'me collection (m' + #$00EA + 'me nom ou m' + #$00EA +
        'me cha' + #$00EE + 'ne d''acc' + #$00E8 + 's) avec la variable de boucle non d' + #$00E9 +
        'cal' + #$00E9 +
        'e : X[i], X[i, j], et pour .Count aussi X.Items[i], X.Strings[i] et X.Objects[i]. Les cha' +
        #$00EE + 'nes commencent ' + #$00E0 +
        ' 1 et ont leurs propres formes : ''0 to Length(S)'' avec S[i] est faux aux deux bouts (S[0] avant le premier caract' +
        #$00E8 + 're), ''1 to Length(S) + 1'' au-del' + #$00E0 +
        ' du dernier ; ''1 to Length(S)'' est correct. Le r' + #$00E9 +
        'sultat n''est une erreur que si le type est prouv' + #$00E9 +
        ' : la collection est un nom d' + #$00E9 + 'clar' + #$00E9 + ' dans l''unit' + #$00E9 +
        ' (param' + #$00E8 +
        'tre, variable locale ou inline, Result, champ de la propre classe de la m' + #$00E9 +
        'thode ou de ses anc' + #$00EA + 'tres dans l''unit' + #$00E9 + ', variable d''unit' +
        #$00E9 +
        ') dont le type est une liste connue (TList, TObjectList, TStrings, TStringList, TCollection, TMenuItem, FPC TFPList/TFPGList ...), un tableau ou une cha' +
        #$00EE + 'ne, et le corps ne quitte pas le passage avant l''acc' + #$00E8 +
        's (break, exit, continue, raise, goto), ne fait pas grandir la collection et ne contient pas de m' +
        #$00E9 +
        'thode anonyme. Sinon, c''est un avertissement. Correction : Count - 1, High(A) (ou Length(A) - 1) et, pour les cha' +
        #$00EE + 'nes, 1 to Length(S).'
    ),
    // SCA204
    (
      RuleID   : 'SCA204';
      Name     : 'R' + #$00E9 + 'sultat affect' + #$00E9 + ' via le nom de la fonction';
      ShortDesc: 'R' + #$00E9 + 'sultat de la fonction d' + #$00E9 + 'fini par affectation ' + #$00E0 +
        ' son nom (''GetCount := ...'') - l''ancienne forme Pascal ; Delphi ' + #$00E9 +
        'crit Result';
      FullDesc : 'Dans une fonction, ''GetCount := FItems.Count;'' d' + #$00E9 + 'finit le r' + #$00E9 +
        'sultat - la forme qu''avait Pascal avant l''existence de Result. Cela fonctionne, mais le m' +
        #$00EA + 'me nom signifie alors deux choses diff' + #$00E9 + 'rentes dans un m' + #$00EA +
        'me corps : ' + #$00E0 + ' gauche de '':='', c''est la variable de r' + #$00E9 +
        'sultat, partout ailleurs, c''est un appel r' + #$00E9 +
        'cursif de la fonction (voir SCA205). ''Result :='' dit ce qui est voulu et ne peut pas ' +
        #$00EA + 'tre confondu avec un appel. Est signal' + #$00E9 +
        'e une affectation au nom nu de la fonction en d' + #$00E9 +
        'but d''instruction (y compris derri' + #$00E8 + 're une ' + #$00E9 +
        'tiquette de case) dans le propre corps de la fonction. Uniquement l' + #$00E0 + ' o' +
        #$00F9 +
        ' Result existe : en Delphi (pas sous {$X-}), et en Free Pascal dans les modes delphi, delphiunicode et objfpc ou avec {$modeswitch result} ; un fichier sans {$mode} compte comme Delphi dans une analyse Delphi et comme inconnu sous --dialect=fpc. R' +
        #$00E8 +
        'gle de style (conseil) : profils strict et style, pas default. reDelphix propose le remplacement par ''Result :=''.'
    ),
    // SCA205
    (
      RuleID   : 'SCA205';
      Name     : 'Le nom de la fonction lu dans son propre corps est un appel r' + #$00E9 + 'cursif';
      ShortDesc: '''Total := Total + X'' dans la fonction Total : ' + #$00E0 +
        ' droite, le nom est un appel r' + #$00E9 + 'cursif, pas le r' + #$00E9 + 'sultat courant';
      FullDesc : 'En Delphi, le nom d''une fonction dans son propre corps n''est la variable de r' + #$00E9 +
        'sultat qu''' + #$00E0 +
        ' gauche de '':=''. Partout ailleurs - dans une expression, une condition, Exit(Name) - il appelle de nouveau la fonction. ''Total := Total + X;'' n''ajoute donc pas X au r' +
        #$00E9 + 'sultat construit jusque-l' + #$00E0 + ' : il provoque une r' + #$00E9 +
        'cursion, en g' + #$00E9 + 'n' + #$00E9 + 'ral jusqu''au d' + #$00E9 +
        'bordement de pile. Les modes objfpc et fpc de Free Pascal y lisent au contraire le r' +
        #$00E9 + 'sultat, d''o' + #$00F9 + ' ce motif dans le code port' + #$00E9 + '. Est signal' +
        #$00E9 + ' le nom nu (sans parenth' + #$00E8 + 'ses, pas derri' + #$00E8 +
        're un point, pas apr' + #$00E8 +
        's inherited ou @) dans une expression d''une fonction qui affecte aussi son propre nom - l''auteur utilise le nom comme une variable. C''est une erreur quand la fonction n''a pas de param' +
        #$00E8 + 'tres, que le corps ne montre aucune r' + #$00E9 + 'cursion d' + #$00E9 + 'lib' +
        #$00E9 + 'r' + #$00E9 +
        'e (pas de Name(), pas d''instruction d''appel ''Name;'', pas de Self.Name, pas de Name<T>) et que le nom n''est pas un argument d''appel nu ; sinon un avertissement (uniquement des param' +
        #$00E8 + 'tres par d' + #$00E9 + 'faut, r' + #$00E9 + 'cursion d' + #$00E9 + 'lib' + #$00E9 +
        'r' + #$00E9 + 'e ' + #$00E0 + ' c' + #$00F4 + 't' + #$00E9 +
        ', argument nu). Uniquement en mode Delphi : Delphi, ou Free Pascal avec {$mode delphi} / {$mode delphiunicode}. Correction : Result (ou Name() quand la r' +
        #$00E9 + 'cursion est voulue).'
    ),
    // SCA206
    (
      RuleID   : 'SCA206';
      Name     : 'Marqueur de d' + #$00E9 + 'sactivation du formateur mal ' + #$00E9 +
        'crit ou sans partenaire';
      ShortDesc: 'Marqueur de formateur `{(*}` / `{*)}` mal ' + #$00E9 +
        'crit ou sans partenaire - GExperts, CnWizards et JCF formatent alors quand m' + #$00EA +
        'me la zone ou plus du tout le reste du fichier';
      FullDesc : 'Les commentaires `{(*}` et `{*)}` d' + #$00E9 +
        'sactivent le formateur de code pour la zone qui les s' + #$00E9 + 'pare, puis le r' +
        #$00E9 +
        'activent. Ils viennent de DelForExp et sont reconnus par le formateur de GExperts, celui de CnWizards et JEDI Code Format (aussi dans Lazarus) ; le formateur de l''IDE Delphi (Ctrl+D, jusqu''' +
        #$00E0 + ' Delphi 12) les ignore, et Delphi 13 n''est plus livr' + #$00E9 +
        ' avec un formateur. Les formateurs n''acceptent que ces quatre caract' + #$00E8 +
        'res exacts - `{ (*}` ou `{*) }` est pour eux un commentaire ordinaire - et les zones ne s''imbriquent pas : un interrupteur, pas un compteur. Sont signal' +
        #$00E9 + 's : un marqueur contenant des espaces ou des tabulations (il est ignor' + #$00E9 +
        ', la zone est format' + #$00E9 + 'e) ; un `{(*}` ouvrant jamais referm' + #$00E9 +
        ' (plus rien n''est format' + #$00E9 +
        ' ensuite) ; un `{*)}` fermant sans zone ouverte (il ne ferme rien) ; et un second `{(*}` dans une zone ouverte (le premier `{*)}` la termine d' +
        #$00E9 + 'j' + #$00E0 + '). Une zone laiss' + #$00E9 + 'e ouverte volontairement jusqu''' +
        #$00E0 + ' la fin du fichier est signal' + #$00E9 +
        'e aussi - la masquer avec `// noinspection FormatterMarker` sur la ligne au-dessus du `{(*}`. Le compilateur voit les deux marqueurs comme de simples commentaires `{ }` ; rien de tout cela ne modifie le programme compil' +
        #$00E9 +
        '. Le bilan se fait par fichier ; les branches `{$IFDEF}` sont lues telles quelles, sans ' +
        #$00EA + 'tre ' + #$00E9 + 'valu' + #$00E9 + 'es.'
    )
  );

