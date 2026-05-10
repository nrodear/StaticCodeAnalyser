## v0.7.0 — Pre-Release

Dritte oeffentliche Version des **Static Code Analysis Tool for Delphi**.
Schwerpunkt: grosser Frame-Refactor im IDE-Plugin (God-Class entkoppelt),
neuer **Single-File-Live-Watch** (loest WatchMode + AutoScanOnEdit ab),
ueberarbeiteter `FormatMismatch`-Detektor und ein eigenstaendiger HTML-Export.

### Highlights

- **Single-File-Live-Watch** (NEU, loest WatchMode + AutoScanOnEdit ab) —
  Klick auf **Aktuelle Datei** aktiviert einen Live-Watch auf genau
  diese Datei: jeder Save (300 ms debounced) UND jeder Edit (1000 ms
  debounced) re-scant die Datei im Hintergrund. Tab-Wechsel auf eine
  andere Datei aendert nichts; erneuter Klick haengt den Watch um.
  Bulk-Pfade (**Analyse starten**, **Branch-Changes**) deaktivieren
  den Watch explizit. Kein INI-Flag mehr.
  > ⚠️ **RISIKO Endlosschleife.** Heute kein Re-Entrancy-Guard fuer
  > ueberlappende Worker-Spawns. Vor breitem Einsatz erst
  > Re-Entrancy-Guard + Hard-Cap einbauen — siehe `TODO.md` und der
  > Warning-Block oben in `uIDEWatchMode.pas`.
- **`FormatMismatch`-Detektor ueberarbeitet** — `Format(...)` /
  `FormatUtf8(...)` werden jetzt auch ueber **Konstanten** /
  **Resourcestrings** als ersten Parameter aufgeloest (vorher nur
  Inline-Literale). Anzahl Specifier vs. Argumente wird sauber
  abgeglichen, mit Sonderfaellen fuer `%n`, `%%` und Index-Specifier.
- **Frame-Refactor (`TAnalyserFrame` God-Class entkoppelt)** —
  ehemals ~2000 Zeilen Frame, jetzt verteilt auf:
  `uIDEAnalyseRunner`, `uIDEAnalyseProgress`, `uIDEEditorIntegration`,
  `uIDEExportMenu`, `uIDEHelpPanel`, `uIDEStatusBar`,
  `uIDEThemeIntegration`, `uIDEStatsTiles`, `uIDEGridTooltip`,
  `uIDELifecycle`. Frame haelt nur noch UI-Komposition + Click-
  Delegation, keine Business-Logik mehr.
- **HTML-Export** in eigene Unit `uExportHtml` ausgelagert (vorher
  730+ Zeilen in `uExport`). Neuer Look mit Sonar-Style Tile-Reihe,
  Severity-Filter und filebasierter Detail-Liste.
- **`uIDEStatsTiles`** — Sonar-Style Befund-Kacheln (Total, Critical,
  Warning, Hint je Detector-Group) als horizontale Reihe oberhalb des
  Befund-Grids.

### Removed

- **INI-Flags `[Detectors] WatchMode` und `AutoScanOnEdit`** — beide
  ersatzlos entfernt. Live-Watch ist jetzt implizit an "Aktuelle Datei"
  gekoppelt (siehe Highlights). Bestehende INI-Dateien muessen nicht
  angepasst werden — die Flags werden ignoriert.
- **Legacy `uLeakDetector` / `uStaticAnalyzer` / `uParser`** geloescht
  (vor v0.6.0 schon durch `uLeakDetector2` / `uStaticAnalyzer2` /
  `uParser2` abgeloest, jetzt final raus).

### Configuration

- **`AutoScanOnEdit`** war kurzzeitig in v0.7-rc1 vorhanden — wieder
  raus, durch Single-File-Live-Watch ersetzt.
- **Kein neues INI-Schema** in v0.7 — alle alten Keys aus v0.6 bleiben
  gueltig.

### IDE-Plugin

- **Frame-Decomposition** (siehe oben) — jeder neue Helper-Modul
  haelt seinen Zustand in einer eigenen Klasse statt als Frame-Field.
- **Progressbar Marquee-Mode** waehrend Branch-Changes-Diff-Phase
  (Git/SVN-Aufrufe haben keinen sinnvollen Fortschritt).
- **Watch-Modul-Notifier** — `TFindingModuleNotifier` listet jetzt
  alle drei `IOTAModuleNotifier`/`80`/`90` Versionen explizit; Save
  in Delphi 12 schiesst sonst AV in `coreide290.bpl`.
- **Recent-Paths-MRU** in `uRecentPaths` — letzte 10 Projekt-Pfade
  im "Project Path"-Combo.
- **uIDELineHighlighter** Robustheits-Fixes — sauberer
  `RemoveNotifier` auch wenn Editor schon geschlossen ist.

### Engine

- **`FormatMismatch` Const-Resolution** — Map aus `(UnitName, ConstName)
  -> Wert` wird beim ersten Aufruf einer Methode lazy aufgebaut, dann
  bei jedem `Format(...)`/`FormatUtf8(...)` konsultiert. Erkennt
  `Format(MY_CONST_FMT, [...])` korrekt.
- **`DivByZero`** — bessere Erkennung von Variablen-Divisor mit
  Validierung weiter oben in der Methode (`if x = 0 then Exit`-Pattern
  reduziert false-positives).
- **`SQLInjection`** — neue `Safe-Cast`-Erkennung
  (`IntToStr(...) + ' OR 1=1'` zaehlt nicht als Injection-Risk).
- **`uLeakDetector2`** — diverse FP-Reduktionen + neuer
  `FieldLeak`-Pfad fuer `class.field := TX.Create` ohne Owner.
- **`HardcodedSecret`** — gepflegte Filter-Liste fuer false-positives
  (`secretary`, `tokenize`, `passport`, ...).
- **`TodoComment`** — Block-Kommentar-Aware Scanner (kein `// TODO`
  mehr in `'foo // bar'`-String-Literalen).
- **Suppression-Helper konsolidiert** — `noinspection`-Marker werden
  in einer Pass ueber den Tokenstream extrahiert statt pro Detektor.
- **`uParser2`** Iterations-Hardening — weitere `GuardAdvance`-
  Stellen, `try-finally`-Block-Adoption ueber neuen
  `AdoptChildrenFrom`-Helper (kein O(n^2) mehr beim Hochziehen).

### Tests

- **TestProject** erweitert auf ~270+ Cases (`uTestAnalyserChecks`).
- **`uTestSrcBuilder`** Helper fuer kompakte Test-Source-Konstruktion.
- **`TestParseX509`** als Reproducer fuer Mormot-X509-Parser-Crash
  (bereits gefixt, Test bleibt als Regression).

### UI / UX

- **DE-Lokalisierungs-Erweiterungen** in `uLocalization`.
- **Themed Findings-Grid** — VCL-Style-aware (Light/Dark/Mountain Mist).
- **Help-Panel** (`uIDEHelpPanel`) — Inline-Doku + FixHints im
  IDE-Plugin, ohne den Frame zu verlassen.
- **Status-Bar 3-Panel** — Befunde-Count / Datei-Progress / Mode
  in dedizierter `uIDEStatusBar`-Komponente.

### Robustheit

- **Re-Entrancy-Schutz** in `uIDEAnalyseRunner` — kein Doppel-Start
  durch versehentliches Doppel-Klicken auf Analyse-Button.
- **Path-Normalisierung** im Watch-Manager — `/` vs `\` und
  Case-Differenzen werden in `NormalizePath` abgefangen, sonst
  matchen `IOTAModule`-Pfade nicht gegen `EditView.Buffer`-Pfade.
- **Locale-sicherer `.pas`-Filter** — `EndsText` statt
  `ToLower.EndsWith` (Turkish-I-Problem).
- **Worker-Generation-Counter** auch beim Switch zwischen
  Watched-Files inkrementiert — alter Worker-Output landet nicht
  mehr im neuen Watch-Kontext.

### Requirements

- Windows 10/11
- (Plugin) RAD Studio 12 Athens — fuer den Frame-Refactor +
  ToolsAPI-Notifier-Patterns
- (Standalone) keine — kompiliert als single EXE

### Bekannte Einschraenkungen

- Keine Binaries in diesem Release — nur Source. Plugin (BPL) und
  Standalone (EXE) selbst bauen.
- **Single-File-Live-Watch ohne Re-Entrancy-Guard** (siehe Highlights /
  README). Bei langsamen Workers + aktivem Tippen kann der Backlog
  wachsen. Workaround: einfach nicht permanent angeschaltet lassen,
  bei Performance-Problemen einen Bulk-Pfad starten -> Watch wird
  deaktiviert.
- Floating-Point-Division (`/`) wird vom DivByZero-Detektor nicht
  geprueft.
- Plugin-Unload waehrend ein Watch-Worker laeuft: weiterhin in
  seltenen Faellen AV moeglich (Synchronize in freed Memory).
  Workaround: vor dem Plugin-Entfernen einen Bulk-Run starten,
  damit der Watch deaktiviert ist.

### Upgrade von v0.6.0

- **`[Detectors] WatchMode` und `AutoScanOnEdit` in `analyser.ini`
  werden ignoriert.** Eintraege koennen drinbleiben oder geloescht
  werden — keine Auswirkung. Live-Watch ist nur noch via
  **Aktuelle Datei**-Klick aktiv.
- **Frame-Refactor ist UI-transparent** — alle Buttons, Menus,
  Shortcuts und Befund-Filter funktionieren wie in v0.6.
- **Bestehende Suppressions, `ignore.txt`-Eintraege, Custom-LeakyClasses
  und Severity-Konfiguration** bleiben unveraendert gueltig.
- **HTML-Exporte aus v0.6** sind nicht binaer-kompatibel — neuer Look
  + neue Tile-Reihe. Kein Migrationspfad noetig, einfach neu exportieren.
