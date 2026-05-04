# TODO

Offene Aufgaben für **Static Code Analysis Tool for Delphi**.
Sortiert nach Priorität: 🔴 Bug / 🟡 Robustheit / 🟢 Wartbarkeit / 🚀 CI-Mode / 💡 Feature / 🧪 Tests / 📋 Akzeptiert / 📝 Erledigt-History.

---

## 🔴 Bugs / Korrektheit

- [ ] **`LoadRecentPaths` ohne `try…except` gegen korrupte INI**
  Korrupte INI-Datei lässt das Plugin beim Init crashen.
  Datei: `uIDEAnalyserForm.pas` — `LoadRecentPaths`-Methode.
  Lösung: `TIniFile.Create + ReadString` umschließen, bei Fehler leere
  Liste zurückgeben.

- [ ] **`uTodoComment.FindMarkerInComment` matcht in String-Literalen**
  `var todoList := 'TODO-Item'` triggert den TodoComment-Detektor
  fälschlich. Marker-Detection muss zwischen Code und String-Literalen
  unterscheiden.
  Datei: `Detectors/uTodoComment.pas:48-75`

- [ ] **`uMainForm.NavigateDelphiToLine(0)` bei invalidem Input**
  `Sleep(800) + SendInput` läuft auch mit `LineNo=0` durch — flackernder
  Cursor + Goto-Dialog im Hintergrund.
  Lösung: Pre-Check `if LineNo > 0 then …` direkt am Methodenanfang.
  Datei: `UI/uMainForm.pas`

---

## 🟡 Robustheit

- [ ] **`uParser2` Skip-Loops ohne GuardAdvance**
  Z. 749, 893 — analog zur Z. 736-Korrektur. Schutz vor Endlos-Loop bei
  malformiertem Input.
  Datei: `Parsing/uParser2.pas`

- [ ] **`ParseTryStmt` O(n²) `Children.Delete(0)`**
  Bei sehr großen Try-Bodies (>1000 Statements) messbar langsam.
  Lösung: `Move`-API oder Liste komplett tauschen.
  Datei: `Parsing/uParser2.pas:1071`

- [ ] **`uHardcodedSecret.IsSecretName` Coverage erweitern**
  Aktuelle Tests prüfen Defaults (`secretary` als false-positive bereits
  abgedeckt). Fehlend: `tokenize`, `passport`, `keyboard` (alle sollten
  KEIN Match sein).

- [ ] **WatchMode dynamic module attach**
  `RescanOpenModules` läuft nur in `PrepareAnalysis`. Module die der User
  NACH Watch-Aktivierung neu öffnet bekommen keinen `IOTAModuleNotifier`,
  ihre Saves triggern keine Live-Analyse.
  Lösung: `INTAEditServicesNotifier` registrieren, in
  `EditorViewActivated` per `TryAttach` ergänzen.
  Datei: `StaticCodeAnalyserIDE/uIDEWatchMode.pas`

- [ ] **WatchMode echtes Cancel-Token**
  Heute droppen wir nur _späte_ Worker-Ergebnisse via Generation-Counter.
  Bei einer wirklich langen Datei (5+ Sekunden) läuft der Worker zu Ende,
  obwohl der User schon weiter editiert hat — Verschwendung.
  Lösung: Cancel-Flag im Worker, periodisch von Detektoren via Callback
  abgefragt (analog zum Manual-Cancel in `AnalyseLeaksRecursive`).

---

## 🟢 Wartbarkeit / Refactoring

- [ ] **`uIDEAnalyserForm.pas` aufteilen (~2570 Zeilen)**
  Drei klar extrahierbare Bereiche:
  - `uIDEStatsTiles.pas` — `BuildStatsTiles`/`MakeTile`/`TTilePanel` (~200 Z.)
  - `uIDEFindingGrid.pas` — Grid-Drawing + Filter-Logik (~600 Z.)
  - `uIDERecentPaths.pas` — Load/Save (~80 Z., gemeinsam mit uMainForm)
  Reduktion auf <1500 Zeilen.

- [ ] **`uMainForm` Code-Duplikation mit IDE-Plugin**
  - `LoadRecentPaths`/`SaveRecentPath` → in `Common/uRecentPaths.pas`
  - `ResultGridDrawCell` → in `UI/uFindingGridRenderer.pas`

- [ ] **Severity-Tiles im Standalone-`Form2`**
  IDE-Plugin hat die 8-Tile-Reihe (Errors / Warnings / Hints / Bugs /
  Security / Duplicates / Code-Quality), Standalone nicht. Feature-
  Parität herstellen — entweder portieren oder den IDE-Code als Helper
  extrahieren und beidseitig nutzen.

- [ ] **Leere Stub-Dateien entfernen**
  - `StaticCodeAnalyserForm/sources/MainController.pas` (7 Zeilen, leer)
  - `StaticCodeAnalyserForm/sources/Unit1.pas` (deklariert sich als
    `uParser2`, ist aber leer — Konflikt mit dem echten `uParser2.pas`
    in `Parsing/`)
  Beide ersatzlos löschen + Build-Pakete prüfen.

- [ ] **`uParser.pas` (Legacy) prüfen**
  184 Zeilen, möglicherweise ungenutzt. Falls nur für Tests gebraucht:
  kennzeichnen oder entfernen.

- [ ] **Encoding-Konvention für `.pas`-Files**
  Inkonsistent: einige Files UTF-8 ohne BOM mit rohen Umlauten, andere
  mit `#$xx`-Codepoints. Konvention festlegen + einmal-Sweep.

- [ ] **Detektor-Messages noch teilweise deutsch (Phase-2 i18n)**
  Bewusst übersprungen weil situativ — UI-Hauptpfad ist bereits englisch:
  - `Output/uFixHint.pas` — Vorher/Nachher-Snippets mit deutschen
    Inline-Kommentaren (~30 Snippet-Strings)
  - `Infrastructure/uStaticFiles.pas` — 5 Error-Messages
  - `Infrastructure/uVcsChanges.pas` — Branch-Changes-Status-Messages
  - `Detectors/uSQLInjectionScore.pas` — Reason / Suggestion-Strings

- [ ] **Severity je Detektor user-konfigurierbar**
  Heute hardcodiert (`F.Severity := lsWarning`). User möchte vielleicht
  `LongMethod` als `lsHint` einstufen oder `MagicNumber` aufwerten.
  Geplant: `[SeverityOverrides]`-Sektion in `analyser.ini` mit
  `LongMethod=hint` etc. + Read-In in `TRepoSettings`.

---

## 🚀 Console-Mode / CI-Integration

Großer separater Block — nichts von dem hier ist trivial, aber alles
hängt zusammen (CLI-Mode ist die Voraussetzung für CI-Integration).

- [ ] **Headless-CLI-Mode für `analyser.d12.exe`**
  Aktuell GUI-only. Für CI-Pipelines: nicht-interaktiver Modus mit
  Exit-Code, Report-Output und Branch-Mode.

  Geplante Aufrufe:
  ```
  analyser.exe --path D:\repo --branch              # Branch-Diff (Git/SVN)
  analyser.exe --path D:\repo --full                # rekursiv
  analyser.exe --file MeineUnit.pas                 # Einzeldatei
  analyser.exe --path . --branch --report sca.json  # Report-Output
  ```

  Eigenschaften:
  - **Exit-Code-Konvention**: 0 = clean, 1 = Hints, 2 = Warnings, 3 =
    Errors, 4 = Read-Errors, 99 = Tool-Fehler. `--exit-on error|warn|hint`
    konfigurierbar.
  - **Quality-Gate-Flag**: `--max-errors 0 --max-warnings 5` →
    Pipeline-Fail wenn überschritten.
  - **VCS-Auto-Detect**: nutzt bestehenden `uVcsChanges`-Code für
    `--branch`. Setting für `--base-branch develop` durchreichbar.
  - **Stdout / `--quiet`**: tabellarische Befund-Liste auf stdout,
    `--quiet` unterdrückt alles außer Exit-Code.
  - **Locale**: `--lang en` / `--lang de` für Report-Sprache.
  - Datei: neue `Console/uConsoleRunner.pas` + Anpassung in
    `analyser.d12.dpr` (Args parsen, keine Form wenn CLI-Modus aktiv).

- [ ] **Report-Formate für CI-Tools**
  Mehrere Standard-Formate, je ein Output-Switch:
  - `--report-junit sca.xml` — JUnit-XML, GitLab-CI / GitHub Actions /
    Jenkins kompatibel
  - `--report-sarif sca.sarif` — [SARIF v2](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning),
    GitHub Code-Scanning-fähig (Findings im PR sichtbar)
  - `--report-sonar sca-sonar.json` — SonarQube Generic Issues
  - `--report-checkstyle sca-checkstyle.xml` — breitester Tool-Support
    (BitBucket, Phabricator, GitLab)
  - `--report-codeclimate sca-cc.json` — GitLab Code-Quality Widget
  - `--report-html sca.html` — bestehender Report aus `uExport`,
    self-contained, fürs Build-Artefakt

  Datei: `Output/uReportFormats.pas` (neu), nutzt vorhandene
  Finding-Liste, getrennt von der UI-orientierten `uExport.pas`.

- [ ] **GitHub-Action / GitLab-CI Beispielworkflows**
  `.github/workflows/sca.yml` und `examples/.gitlab-ci.yml` —
  copy-paste-fertig, nutzt CLI + SARIF/JUnit-Output.

- [ ] **Pre-Commit-Hook-Script**
  `examples/pre-commit-sca.sh` (bash) und `pre-commit-sca.ps1`
  (PowerShell). Rufen `analyser.exe --branch --max-errors 0`. User
  kopiert ins `.git/hooks/pre-commit`.

- [ ] **Quality-Gate via `analyser.ini`**
  Zusätzlich zum CLI-Flag eine `[QualityGate]`-Sektion:
  ```ini
  [QualityGate]
  MaxErrors=0
  MaxWarnings=10
  MaxHints=50
  FailOn=error,warning
  ```
  Wird genutzt wenn keine CLI-Flags angegeben sind. Konsistente Defaults
  zwischen lokalem CLI-Run und Pipeline.

- [ ] **Baseline-File**
  Bei großen bestehenden Projekten will man neue Findings catchen, alte
  ignorieren.
  - `analyser.exe --baseline sca.baseline` — liest die Liste der
    bekannten Findings (Hash je File+Line+Rule), markiert sie als
    „pre-existing", failt nur bei NEUEN.
  - `analyser.exe --update-baseline sca.baseline` — re-generiert die
    Datei nach manuellem Code-Review der bestehenden Findings.

---

## 💡 Features / Erweiterungen

- [ ] **Multi-View-Support für Highlight**
  Aktuell wird nur die TopView aktiv repainted — bei Split-View wird
  der zweite Pane erst beim nächsten Auto-Paint aktualisiert.
  Lösung: über alle EditWindows iterieren und `View.Paint` rufen.
  Datei: `StaticCodeAnalyserIDE/uIDELineHighlighter.pas`

- [ ] **„Ignore this finding"-Button im Grid-Context-Menü**
  Rechtsklick auf eine Befund-Zeile → „Suppress in code" (fügt
  `// noinspection <Kind>` über die Zeile ein) oder „Add to ignore.txt"
  (Datei-Glob in der Ignore-Datei). Heute muss der User händisch in
  `ignore.txt` editieren oder Suppression-Kommentare schreiben.

- [ ] **Bulk-Suppress (Multi-Select im Grid)**
  Mehrere Zeilen in der Ergebnisliste markieren → eine Action
  („Suppress all in code" / „Add files to ignore.txt"). Setzt
  `goRowSelect` auf Multi-Select voraus.

- [ ] **Compare-Scans (Regression-Detection)**
  Zwei Scan-Reports laden (oder einer aus Baseline) und Diff anzeigen:
  - **Neu**: Findings die im aktuellen Scan dazugekommen sind
  - **Behoben**: Findings die vorher da waren, jetzt weg
  - **Unverändert**: identisches Set
  Nützlich für Code-Reviews und PR-Kommentare.

- [ ] **Fix-It-Aktionen (auto-correct) für Trivialfälle**
  Bestimmte Detektor-Findings sind mechanisch fixbar:
  - `MissingFinally`: try/finally-Block einfügen
  - `EmptyMethod`: `inherited;`-Stub einfügen oder Methode entfernen
  - `TodoComment` ohne Issue-Nummer: Marker-Erweiterung anbieten
  Über `IOTAEditWriter` direkt im Quellcode patchen. Behutsam — nur mit
  User-Bestätigung pro Fix.

- [ ] **„Go to next / previous error"-Navigation**
  Tastenkürzel (z. B. F8 / Shift+F8 wie Compiler-Errors), springt durch
  die Findings-Liste in der aktuellen Datei. Heute muss man im Grid
  klicken um zu navigieren.

- [ ] **Mercurial-(`hg`-)Support in `uVcsChanges`**
  Heute nur Git und SVN. Mercurial-Repos via `hg status -nmar` +
  `hg diff --stat -r main` analog zu SVN. Auto-Detect über `.hg`-Ordner.
  Niedrige Priorität — Mercurial-Anteil im Delphi-Umfeld klein, aber
  technisch trivial.

---

## 🧪 Tests

- [ ] **Unit-Tests für `TDetectorUtils`**
  Edge-Cases:
  - `FindWholeWordLower('', 'haystack')` → 0
  - `FindWholeWordLower('a', 'a')` → 1
  - `FindWholeWordLower('foo', '_foo_')` → kein Match (Underscore)
  - `IsIdentChar` mit Sonderzeichen, Numerals
  Neue Datei: `tests/uTestDetectorUtils.pas`

- [ ] **Plattformunabhängige Tests**
  Hardcodierte Windows-Pfade brechen auf Linux/macOS-CI:
  - `uTestAnalyserChecks.pas:3204` (`'D:\does\not\exist\nirvana.pas'`)
  - `uTestAnalyserChecks.pas:3226` (`'D:\nirgendwo\unbekannt'`)
  Lösung: `TPath.Combine(TPath.GetTempPath, 'sca_nirvana_' + Guid)`

- [ ] **Performance-Tests mit Soft-Schwellen**
  `uTestPerformance.pas:183, 222, 269, 314` haben harte Timeouts
  (`< 10000ms`) → flaky auf langsamen CI-Maschinen.
  Lösung: nur Warnung loggen oder Timeout aus Umgebungsvariable.

- [ ] **Schwache Asserts ersetzen**
  Pattern `Assert.IsTrue(F.Count > 0)` ohne Inhaltsprüfung — sollte
  `Assert.AreEqual(1, CountOfKind(F, fkXxx))` sein. ~30+ Stellen in
  `uTestAnalyserChecks.pas`.

- [ ] **Test-Daten-Factory**
  ~280 inline `const SRC = 'procedure …'#13#10` Strings. Eine
  `TTestSourceBuilder.Procedure(Body).Class(Name).Build`-API würde
  tausende Test-Zeilen sparen.

- [ ] **Coverage-Lücken abdecken**
  - `TodoComment` (10 Tests) — ausbaubar
  - `DuplicateBlock` (10 Tests)
  - `FieldLeak` — kaum Tests
  - Encoding-Edge-Cases (UTF-8-BOM, UTF-16, Windows-1252) gar nicht

- [ ] **Suppression-Tests für `// noinspection All`-Variante**
  Sicherstellen dass alle 21 Kinds vom `All`-Branch erfasst werden.

- [ ] **Tests für `uVcsChanges` (Git/SVN-Integration)**
  Aktuell ungetestet — wird nur durch manuelles Klicken auf
  „Branch-Changes" verifiziert. Mit einem Temp-Repo-Helper:
  - Git: `git init`, Datei anlegen, committen, ändern → erwarten dass
    geänderte Datei erkannt wird
  - SVN: nur `svn status`-Mock (echtes svn-Setup zu komplex für CI)
  - VCS-CLI fehlt: erwarten klare Fehlermeldung, nicht AV
  Datei: neue `tests/uTestVcsChanges.pas`

- [ ] **Tests für `uExport` (CSV / JSON / HTML / Jira)**
  Roundtrip: Liste → Export → wieder einlesen (CSV/JSON) bzw. HTML/
  Jira-Output gegen Snapshot. Encoding-Edge-Cases (Sonderzeichen,
  lange Pfade, leere Liste). **0 Tests heute.** UTF-8-BOM-Verifikation
  ist nach jüngstem Fix wichtig.

- [ ] **Tests für `uClaudePrompt`**
  Snapshot-Test des erzeugten Markdown-Blocks: Header, Code-Snippet
  ±5 Zeilen, Marker auf richtiger Zeile, Vorher/Nachher. Edge-Cases:
  Befund auf Zeile 1 (kein „vor"), letzte Zeile (kein „nach"), Datei
  mit nur 3 Zeilen.

- [ ] **Tests für `uLocalization`**
  - `_('Errors')` mit `SetLanguage('de')` → `'Fehler'`
  - Format: `_('%d findings', [5])` → korrekte Übersetzung + Substitution
  - Unbekannter Key: Passthrough = Source-String
  - Sprachwechsel mehrfach hintereinander (de → fr → en) ohne Leak

- [ ] **Apostroph-Escape in Tests verifizieren**
  Nach `HtmlEscape`-Update werden Apostrophe immer als `&#39;` escaped.
  Falls Tests rohen Output-Vergleich machen → anpassen.

---

## 📋 Bekannt-aber-akzeptiert (kein Fix geplant)

- **Compiler-Errors verschwinden im Messages-Pane bei Scan-Start**
  Tradeoff für `ClearAllMessages` aus früherer Variante. IDE-Messages-
  Spiegelung ist heute komplett deaktiviert (siehe Erledigt-History) —
  TODO obsolet falls Spiegelung später re-aktiviert wird.

- **WatchMode + Plugin-Unload ohne explizites Worker-Cancel**
  Wenn User „Components → Remove Package" während ein Watch-Worker
  läuft, kann die Synchronize-Callback in freed Memory landen → AV.
  Sehr selten, akzeptiert. Workaround für User: WatchMode in INI
  ausschalten bevor Plugin entfernt wird.

- **`uClaudePrompt` schluckt Encoding-Fehler beim Snippet-Lesen**
  Bewusst — Snippet ist ein „best effort"-Feature, nicht
  analyse-kritisch.

- **Floating-Mode-Theme nicht live aktualisiert**
  `INTACustomDockableForm` exposes keinen offiziellen Hook für
  Theme-Reapply auf der Wrapper-Form. Workaround: Plugin docken oder
  schließen+öffnen nach Theme-Wechsel.

---

## 📝 Erledigt (für die History)

Siehe `git log` für Details. Haupt-Themen chronologisch:

**Strukturell**
- ✅ Re-Strukturierung in `Common/Parsing/Detectors/Infrastructure/Output/UI`
- ✅ `repo.ini` → `analyser.ini` mit Auto-Migration
- ✅ Konsolidierter `uClaudePrompt`-Helper (kein Doppelcode)
- ✅ FixHint-Wrapper in IDE-Plugin (delegiert an Resolver)

**Konfiguration über INI**
- ✅ Custom-LeakyClasses + ExcludeLeakyClasses in `[Detectors]`
- ✅ `UsesCheck` / `IncludeTests` Checkboxen → INI-Settings
  (Toolbar entlastet, Pattern wie `AutoDiscoverClasses`)
- ✅ Konfigurierbare Detektor-Schwellwerte: `LongMethodMaxBodyLines`,
  `LongMethodMaxStatements`, `LongParamListMaxParams`,
  `DeepNestingMaxDepth`, `DuplicateBlockMinLines`, `MaxFileMB`,
  `MagicNumberTrivials`. Gespiegelt in `uSCAConsts`-Globals via
  `TRepoSettings.ApplyDetectorThresholds`
- ✅ Auto-Discovery von Custom-Klassen — `AutoDiscoverClasses=1` scannt
  Projekt-AST nach Klassen die `Free` brauchen, splittet in
  _instantiable_ vs. _static-only_, schreibt nach
  `LeakyClassesDiscover.log`

**Detektor-Pipeline**
- ✅ Wortgrenzen-Helper `TDetectorUtils` für 5 Detektoren
- ✅ Iterativer AST-Traversal (kein Stack-Overflow mehr)
- ✅ JSON/HTML Encoding RFC-konform mit Surrogate-Handling
- ✅ Suppression abdeckt alle 21 Finding-Kinds
- ✅ uExport UTF-8 mit BOM — `TExporter.SaveUtf8WithBom`-Helper mit
  `TUTF8Encoding.Create(True)`. Default-Singleton hat in Delphi 12
  `FUseBOM=False` — notwendig für deutsches Excel

**IDE-Plugin Integration**
- ✅ DE-Lokalisierung (eingebautes Dictionary in `uLocalization`)
- ✅ Messages-Pane statt Custom-Line-Highlights — später wieder
  deaktiviert (User-Feedback: kein Export aus Scan)
- ✅ UI-Race-Schutz: globaler `GLiveAnalyserFrame`-Sentinel verhindert
  AV bei Frame-Destruction während Worker-Callback
- ✅ Button „Repo..." → „Settings..." / „Einstellungen..." umbenannt
- ✅ FilterCombo Edge-Cases: `Items.Count = 0` + `idx >= Count`
  Pre-Checks + Re-Entry-Schutz beim ItemIndex-Reset
- ✅ Tooltip im Grid — nur Datei-Spalte, 100 ms Delay (statt IDE-Default
  500 ms), keine Tooltips auf Method/Line/Type/Severity
- ✅ Severity / Type Filter-Combos in eigenen Container-Panels —
  `TLabel`+`TComboBox` mit losem `alLeft` verschoben sich gegeneinander
  (Graphic- vs. Window-Control), Container-Pattern serialisiert sauber

**Editor-Integration (ToolsAPI)**
- ✅ Editor-Line-Highlight bei Click auf Befund — via
  `INTAEditViewNotifier.PaintLine` (DelphiLint-Pattern),
  `TNotifierObject`-Basisklasse, 3 px roter Stripe links neben der
  Zeile. Lazy-Attach beim ersten Klick (kein Plugin-Install-Risiko)
- ✅ `View.RemoveNotifier` beim Plugin-Unload — Manager trackt pro
  Attach `(TFindingViewNotifier, Index, IOTAEditView)`, ruft
  `RemoveNotifier` im Destructor mit `try/except` + Buffer-null-Check

**Watch-Mode (Live-Analyse beim Speichern)**
- ✅ Watch-Mode komplett implementiert in `uIDEWatchMode.pas`:
  - Pro offener `.pas`-Datei einen `IOTAModuleNotifier`
  - `AfterSave` triggert nach 300 ms Debounce einen
    `TWatchAnalyzer`-Background-Thread
  - `Synchronize` zurück an Frame, der via `OnWatchFindings` nur die
    Findings für diese eine Datei in `FAllFindings` ersetzt
  - Generation-Counter dropped späte Worker-Ergebnisse wenn manuelle
    Analyse zwischenzeitlich läuft
  - Aktivierung via INI `[Detectors] WatchMode=1` (Pattern wie
    `UsesCheck` / `IncludeTests`)
- ✅ WatchMode auto-aktiv bei „Aktuelle Datei" — Klick auf den Button
  forciert WatchMode unabhängig von der INI-Einstellung; Live-Edit-
  Update ist da der natural fit. Bulk-Pfade (Full-Project,
  Branch-Changes) folgen weiterhin dem INI-Wert
- ✅ `IOTAModuleNotifier` Delphi-12-kompatibel — alle drei
  Interface-Versionen explizit gelistet (`IOTAModuleNotifier`,
  `IOTAModuleNotifier80`, `IOTAModuleNotifier90`) + zusätzlich
  `IInterface` und `IOTANotifier`. Vorher AV in `coreide290.bpl` weil
  IDE-Kern auf 90 QueryInterface't und beim nil-Result NULL-Pointer
  dereferenziert
