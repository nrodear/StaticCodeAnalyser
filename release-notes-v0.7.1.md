## v0.7.1 — Pre-Release

Patch-Release ueber v0.7.0 mit Schwerpunkt auf Code-Metriken (neuer
Detector), responsive Docked-Mode-UI fuer das IDE-Plugin, AI-Prompt-
Verbesserungen und durchgaengiger DPI-Skalierung.

### Highlights

- **Cyclomatic Complexity (McCabe) Detector** (NEU, Phase 1 der Code-
  Metriken-Roadmap) — `TCyclomaticComplexityDetector` misst pro
  Methode die McCabe-Komplexitaet: 1 Base + `if` + `case`-Arm +
  `for`/`while`/`repeat` + `on`-Handler + `and`/`or`/`xor` BinaryOps.
  `else` zaehlt nicht (binary branch). Default-Schwelle: 10
  (Sonar/Checkstyle/PMD-Standard) via `[Detectors] CyclomaticMax`.
  Findings als `fkCyclomaticComplexity` mit Refactor-Hint in
  `uFixHint` (Before/After-Beispiel mit `CanProcess`/`ProcessOrder`-
  Methoden-Split).
- **Docked-Mode UI** (NEU, IDE-Plugin) — der Plugin-Frame erkennt
  schmale Container (< 700 px ClientWidth, typisch fuer gedockte
  IDE-Tool-Panels) und reduziert sich auf das Wesentliche:
  - Stats-Tiles schrumpfen auf 4 essenzielle (Errors / Warnings /
    Hints / Code Quality)
  - Action-Buttons (Start / Current / Branch-Changes) wandern ins
    **Hamburger-Menu** (☰)
  - Settings / Ignore-Liste werden ebenfalls per Hamburger erreichbar
  - Filter-Combo-Labels verschwinden (Combos selbsterklaerend)
  - SearchEdit-MinWidth schrumpft von 120 auf 60 px im Docked
  - Sub-Panel-Container (Severity-/Type-Combo) passen ihre Width an
    Label-Visibility an
  - **Floated**: alles wie gewohnt - voller Funktionsumfang sichtbar
- **AI-Prompt-Rewrite** (`uClaudePrompt`) — Role-Priming am Anfang
  ("senior Delphi developer reviewing static-analysis output"),
  strukturierte Antwort-Vorgabe (Cause / Fix / Verify), Vorher/Nachher
  als "Reference pattern (NOT the user's code)" markiert, Source-
  Marker `>>> ` deutlich auffaelliger, False-Positive-Pfad mit
  `// noinspection`-Vorschlag. Komplett ueber `_(...)` lokalisiert -
  DE-User bekommt DE-Prompt -> DE AI-Antwort.
- **DPI-Scaling** durchgehend in der IDE-Plugin-UI - alle hardcoded
  Pixel-Widths/Heights laufen jetzt durch `ScaleW(...)` (Frame) bzw.
  `ScaleByPPI(...)` (Stats-Tiles). Plugin sieht auf 200%-DPI nicht
  mehr halb so gross aus. Auch der Docked-Threshold 700 wird skaliert.

### IDE-Plugin

- **Cyclomatic-Stats-Tile** zwischen "Duplicates" und "Code Quality"
  (Magenta-Branch-Glyph, ICON_SMELL-Farbton). Zaehlt
  `fkCyclomaticComplexity`-Findings.
- **Klickbare Stats-Tiles** - Hover zeigt Multi-Line-Tooltip mit
  Erklaerung, Klick filtert das Grid auf die jeweilige Severity bzw.
  Type-Bucket. Code-Quality-Tile resetet alle Filter.
- **Filter-Combo** bekommt "Cyclomatic Complexity"-Eintrag.
- **`TResponsiveVisibilityController`** (in `uIDEStatsTiles`) -
  generischer Layout-Controller, hookt Parent.OnResize chained ohne
  bestehende Handler zu zerstoeren, AInverse-Flag fuer "show-only-
  when-narrow"-Controls (Hamburger).
- **`TAnalyserFrame.Resize`-Override** (statt nur OnResize-Event) -
  garantiert Responsive-Trigger auch bei Float->Dock-Transitions, wo
  die IDE-Dock-Logik den OnResize-Event manchmal verschluckt.
- **Magic-Numbers konsolidiert** in `BTN_W_*`/`LBL_W_*`/`CMB_W_*`/
  `STATS_*`/`TB_*`-Konstanten. 14 verstreute Pixel-Werte vorher,
  jetzt benannte Const-Sektion.
- **`BuildHamburgerMenu`** als eigene Methode extrahiert (war ~25
  Inline-Zeilen).

### Engine

- **Cyclomatic-Detector-Implementation** liest `nkIfStmt.TypeRef`
  fuer Boolean-Op-Counts (Parser baut keine Expression-AST, nur
  Cond-Text auf if-Knoten). `while`/`repeat`/`case`-Conditions liegen
  gar nicht vor - akzeptabler Trade-off vs. Parser-Erweiterung.

### Tests

- **`uTestAnalyserChecks` (7500 LOC) zerlegt** in 16 Per-Detector-
  Test-Units: `uTestFindingHelper` (shared `TFindingHelper`), plus
  je eine Unit pro Detector-Themengruppe (`uTestLeakDetector`,
  `uTestSQLInjection`, `uTestHardcodedSecret`, ...). DUnitX
  `initialization`-Block geloescht; Runner nutzt RTTI
  (`UseRTTI := True`) und findet `[TestFixture]`-Klassen automatisch
  sobald die Unit referenziert ist.
- **`TTestCyclomaticComplexity`** mit 10 neuen Tests in
  `uTestCodeMetrics` (Trivial, SingleIf, ElseDoesNotCount,
  BooleanAndOr, ManyIfs, CaseArms, ForWhileRepeat, OnHandler,
  TryFinallyNotCounted, TwoMethodsOneOver).

### i18n

- **~40 neue Dict-Eintraege** in `uLocalization`: Tile-Hints
  (Multi-Line, EN-source -> DE-dict), Hamburger-Menu-Items,
  Cyclomatic-Tile-Caption + FilterCombo-Eintrag, AI-Prompt-Headings
  + Strukturierte-Antwort-Bestandteile, Watch-Status, Cyclomatic-
  FixHint.
- **uIDEWatchMode** Status-Strings durch `Format(_(...), [...])`
  ersetzt - vorher hardcoded English ohne `_(...)`-Wrap.
- **Stale Dict-Eintraege** gefixt: `Settings: ... next click of
  Branch-Changes` -> `... the next analysis run` (Source hatte ich
  geaendert, Dict zeigte alte Variante). Spelling-Drift fix:
  `Analyzing:` (US) -> `Analysing:` (BR), matched jetzt den
  existierenden Dict-Key.

### Configuration

- **`[Detectors] CyclomaticMax=10`** (NEU, Default 10) - INI-Doc-
  Block ergaenzt mit Erklaerung was zaehlt.

### Bekannte Einschraenkungen

- **Single-File-Live-Watch ohne Re-Entrancy-Guard** - unveraendert
  zu v0.7.0. Bei langsamen Workers + aktivem Tippen kann der Backlog
  wachsen. Phase 2 (TODO.md _Single-File-Live-Watch_).
- **Docked-Mode UI** ist Phase 1 der Roadmap - weitere Phasen in
  `TODO.md` (Layout-Architektur via TFlowPanel, Two-Mode-UI, Polish).

### Upgrade von v0.7.0

- **`[Detectors] CyclomaticMax=10`** ist neu im Default-INI-Template,
  aber bestehende `analyser.ini` ohne diesen Eintrag bekommt einfach
  den Default. Kein Migrationspfad noetig.
- **IDE-Plugin Layout** veraendert sich beim Resize/Dock - Floated-
  Mode visuell wie v0.7.0, Docked-Mode neu (Hamburger + reduzierte
  Toolbar). Keine User-Aktion noetig.
- **Bestehende Suppressions, `ignore.txt`-Eintraege, Custom-LeakyClasses,
  Severity-Konfiguration** bleiben unveraendert gueltig.
- **HTML-Exporte** unveraendert.
