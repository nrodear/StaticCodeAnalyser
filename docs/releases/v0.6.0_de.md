## v0.6.0 — Pre-Release

Zweite oeffentliche Version des **Static Code Analysis Tool for Delphi**.
Schwerpunkt: tiefere IDE-Integration (Editor-Highlight, Watch-Mode), durchgaengige
INI-Konfiguration und strukturelle Aufraeumarbeiten.

### Highlights

- **Editor-Line-Highlight** beim Klick auf einen Befund — 3 px roter Stripe
  links neben der Zeile im IDE-Editor (via `INTAEditViewNotifier`,
  DelphiLint-Pattern). Lazy-Attach beim ersten Klick, sauberes
  `RemoveNotifier` beim Plugin-Unload.
- **Watch-Mode** (Live-Analyse beim Speichern) — `Strg+S` triggert die
  Re-Analyse genau der gespeicherten Datei in einem Background-Thread,
  300 ms Debounce, Generation-Counter dropped spaete Worker-Ergebnisse.
  Aktivierung via `[Detectors] WatchMode=1`; bei „Aktuelle Datei" auto-an.
- **Auto-Discovery von Custom-Klassen** — `AutoDiscoverClasses=1` scannt
  das Projekt-AST nach Klassen die `Free` brauchen und teilt sie in
  _instantiable_ und _static-only_ Kandidaten. Ergebnis in
  `LeakyClassesDiscover.log` zum manuellen Pflegen der `LeakyClasses=`.
- **Konfigurierbare Detektor-Schwellwerte** — `LongMethodMaxBodyLines`,
  `LongMethodMaxStatements`, `LongParamListMaxParams`, `DeepNestingMaxDepth`,
  `DuplicateBlockMinLines`, `MaxFileMB`, `MagicNumberTrivials` direkt in
  `analyser.ini`, kein Recompile mehr noetig.

### Configuration

- **`repo.ini` → `analyser.ini`** mit Auto-Migration. Eine zentrale
  INI-Datei fuer VCS, Detektor-Schwellwerte, Custom-Klassen und UI-Sprache.
  Wird beim ersten Start mit selbsterklaerenden Kommentaren angelegt.
- **`UsesCheck` / `IncludeTests` von der Toolbar in die INI verschoben** —
  Toolbar entlastet, gleiches Pattern wie `AutoDiscoverClasses` und
  `WatchMode`.
- **`LeakyClasses` / `ExcludeLeakyClasses`** in `[Detectors]` —
  projektspezifische Klassen ohne Code-Aenderung tracken bzw. aus den
  Defaults herausnehmen.

### IDE-Plugin

- **Watch-Mode-Implementierung** in `uIDEWatchMode.pas`: pro offener
  `.pas` ein `IOTAModuleNotifier`, alle drei Interface-Versionen
  (`IOTAModuleNotifier`/`80`/`90`) explizit gelistet — vermeidet einen
  AV in `coreide290.bpl` bei dem Delphi 12 auf der 90-Variante
  QueryInterface't.
- **Line-Highlighter** in `uIDELineHighlighter.pas`: Manager trackt pro
  Attach `(Notifier, Index, View)` und ruft im Destructor sauber
  `RemoveNotifier` — kein AV mehr beim Plugin-Unload waehrend
  Editor-Repaint.
- **Toolbar-Button-Rename**: „Repo…" -> „Settings…" / „Einstellungen…",
  oeffnet jetzt `analyser.ini` direkt.
- **Tooltip im Grid** (nur Datei-Spalte, 100 ms Delay statt
  IDE-Default 500 ms).
- **Severity/Type Filter-Combos** in eigene Container-Panels gepackt —
  loest das Mischverhalten zwischen Graphic- und Window-Control beim
  `alLeft`-Layout.

### Engine

- **Re-Strukturierung** der `sources/`-Hierarchie in
  `Common/`, `Parsing/`, `Detectors/`, `Infrastructure/`, `Output/`, `UI/`.
- **`TDetectorUtils`-Wortgrenzen-Helper** — gemeinsam genutzt von fuenf
  Detektoren, ersetzt mehrere ad-hoc-Implementierungen.
- **Iterativer AST-Traversal** durchgehend — kein Stack-Overflow mehr bei
  tief verschachteltem Code.
- **JSON / HTML Encoding RFC-konform** mit Surrogate-Handling.
- **Suppression abdeckt jetzt alle 21 Finding-Kinds** (vorher Luecken).
- **UTF-8-BOM-Export** ueber `TExporter.SaveUtf8WithBom`-Helper —
  notwendig fuer deutsches Excel; der Default-Singleton in Delphi 12
  hat `FUseBOM=False`.
- **FixHint-Texte komplett auf Englisch** und mit alternativen Loesungen
  erweitert (Description / Vorher / Nachher) — passt zu Code-Reviews,
  Jira-Tickets und Claude-AI-Prompts in der Praxis.
- **Konsolidierter `uClaudePrompt`-Helper** — kein 1:1-Doppelcode mehr
  zwischen Standalone und Plugin.
- **DE-Lokalisierung der UI** (eingebautes Dictionary in
  `uLocalization`); Default ist Englisch, umstellbar via INI.

### Robustheit

- **UI-Race-Schutz**: globaler `GLiveAnalyserFrame`-Sentinel verhindert
  AV bei Frame-Destruction waehrend Worker-Callback.
- **`FilterCombo` Edge-Cases**: `Items.Count = 0` + `idx >= Count`
  Pre-Checks plus Re-Entry-Schutz beim ItemIndex-Reset.
- **Watchdog 200k-Token pro Datei** — pathologischer Input wird in
  unter einer Sekunde abgebrochen.
- **GuardAdvance** in jeder aeusseren Parser-Schleife — keine
  Endlos-Loops mehr bei malformiertem Input.

### Requirements

- Windows 10/11
- (Plugin) RAD Studio 12 Athens
- (Standalone) keine — kompiliert als single EXE

### Bekannte Einschraenkungen

- Keine Binaries in diesem Release — nur Source. Plugin (BPL) und
  Standalone (EXE) selbst bauen.
- Floating-Point-Division (`/`) wird vom DivByZero-Detektor nicht
  geprueft.
- WatchMode haengt Notifier nur beim Aktivieren an — Module die
  _danach_ neu geoeffnet werden, triggern keine Live-Analyse, bis ein
  neuer Run startet.
- Plugin-Unload waehrend ein Watch-Worker laeuft kann in seltenen
  Faellen einen AV ausloesen (Synchronize in freed Memory). Workaround:
  WatchMode in INI ausschalten bevor das Plugin entfernt wird.

### Upgrade von v0.5.0

- `repo.ini` wird beim ersten Start automatisch nach `analyser.ini`
  migriert.
- Toolbar-Checkboxen `with uses check` / `Include tests` sind weg —
  Werte stehen jetzt unter `[Detectors] UsesCheck=` und `IncludeTests=`.
- Bestehende Suppressions, ignore.txt-Eintraege und
  Severity-Konfiguration bleiben unveraendert.
