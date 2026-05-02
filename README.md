# StaticCodeAnalyser

Statischer Code-Analyser für Delphi 12 als IDE-Expert (dockbares Tool-Fenster).
Erkennt Speicherlecks, Code-Smells und Sicherheitsrisiken in `.pas`-Dateien
direkt in der IDE.

---

## Drei Hauptfeatures

### 1. Statische Code-Analyse (21 Detektoren, Sonar-Taxonomie)

Findet **Bugs** (MemoryLeak, NilDeref, DivByZero, FormatMismatch),
**Vulnerabilities** (SQLInjection, HardcodedSecret), **Security Hotspots**
(HardcodedPath), **Code Smells** (LongMethod, MagicNumber, DeadCode,
EmptyExcept, MissingFinally, …) und **Code Duplication** (DuplicateString,
DuplicateBlock). Jeder Befund kommt mit einer Vorher/Nachher-Lösung im
Hilfe-Panel.

### 2. Inkrementelle VCS-basierte Analyse (Git + SVN)

Statt das ganze Projekt zu scannen genügt **ein Klick auf `Branch-Changes`**:
der Analyser holt sich via `git diff` bzw. `svn status` die im Branch
geänderten `.pas`-Dateien und analysiert nur diese. **~200 ms statt 60 s**
bei einem typischen Feature-Branch — ideal als Pre-Commit-Check.
Konfigurierbar via `repo.ini`. Details: [readme_repo.md](readme_repo.md).

### 3. AI-Integration (Claude-Prompt per Klick)

Klick auf eine Befund-Zeile im Grid → ein **vollständiger Markdown-Prompt**
landet in der Zwischenablage: Befund-Metadaten, Code-Kontext (±5 Zeilen
mit Marker auf der Befund-Zeile), Vorher/Nachher-Lösung. **Strg+V im
Claude-Chat** — und Claude bekommt genug Kontext um den Fix konkret
vorzuschlagen.

---

## Quick-Start

1. Plugin bauen: `StaticCodeAnalyserIDE\StaticCodeAnalyserIDE.dpk` öffnen → **Build**
2. In Delphi: **Ansicht → Static Code Analyser** → dockbares Fenster erscheint
3. Projektpfad wählen → **Analyse starten**

Für inkrementelle Analyse nur der im Branch geänderten Dateien siehe
[readme_repo.md](readme_repo.md).

---

## Was wird erkannt (21 Detektoren)

Alle Befunde landen in einer der **5 Sonar-Kategorien**:

| Kategorie | Detektor | Schweregrad |
|-----------|----------|-------------|
| **Bug** | `MemoryLeak` (LeakDetector + FieldLeak) | Fehler / Warnung |
| | `NilDeref` (Nil-Dereferenzierung) | Fehler |
| | `DivByZero` (Division durch Null) | Fehler / Warnung |
| | `FormatMismatch` (Format/Argumente) | Fehler |
| **Vulnerability** | `SQLInjection` (Score-basiert) | Fehler |
| | `HardcodedSecret` (API-Keys, Passwörter) | Fehler |
| **Security Hotspot** | `HardcodedPath` (`C:\…`, `/etc/…`) | Warnung |
| **Code Smell** | `EmptyExcept` (silent swallow) | Warnung |
| | `MissingFinally` (Free außerhalb finally) | Warnung |
| | `DeadCode` (unerreichbar nach exit/raise) | Warnung |
| | `UnusedUses` (optional, default off) | Hinweis |
| | `LongMethod`, `LongParamList` | Hinweis |
| | `MagicNumber` (in if-Bedingungen) | Hinweis |
| | `DebugOutput` (`OutputDebugString` etc.) | Warnung |
| | `DeepNesting` | Warnung |
| | `TodoComment` (TODO/FIXME/HACK) | Hinweis |
| | `EmptyMethod` | Hinweis |
| **Code Duplication** | `DuplicateString` (≥3 mal gleicher Literal) | Hinweis |
| | `DuplicateBlock` (≥8 Zeilen identischer Code) | Hinweis |
| **Lesefehler** | `FileReadError` (Parser hängt / Datei zu groß) | Fehler |

Pro Detektor gibt es eine **Vorher/Nachher-Code-Beispiel** im Hilfe-Panel.
Per Klick auf einen Befund landet ein **Markdown-Block für Claude AI** in
der Zwischenablage.

---

## Bedienung

### Buttons (von links nach rechts)

| Button | Funktion |
|--------|----------|
| **Verzeichnis-Auswahl** (`...`) | Projektordner wählen |
| **Repo...** | `repo.ini` öffnen — VCS-Settings (siehe [readme_repo.md](readme_repo.md)) |
| **Ignore...** | `ignore.txt` öffnen — Datei-/Verzeichnis-Filter |
| **Analyse starten** | Rekursiver Verzeichnis-Scan |
| **Aktuelle Datei** | Nur die im Editor offene `.pas` |
| **Branch-Changes** | Nur via Git/SVN geänderte Dateien (siehe [readme_repo.md](readme_repo.md)) |
| **Abbrechen** | Bricht laufende Analyse ab (sichtbar während Analyse) |

### Checkboxen

| Checkbox | Wirkung |
|----------|---------|
| `mit uses check` | Aktiviert `UnusedUses`-Detektor (false-positives möglich, default off) |
| `Tests einschliessen` | Schließt `uTest*.pas`, `*_Tests.pas`, `TestProject.dpr`, `/tests/`-Verzeichnisse mit ein (default off) |

### Stat-Cards

Zwei Cards oben zeigen die Verteilung der Befunde:

- **Probleme nach Schweregrad**: Fehler / Warnungen / Hinweise / Sicherheitsrisiken / Lesefehler
- **Probleme nach Typ**: Code Smell / Bug / Vulnerability / Security Hotspot / Code Duplication / Lesefehler

Beide Totals stimmen mathematisch überein.

### Filter

- **Severity-/Type-Combo**: filtert das Grid auf eine Kategorie
- **Such-Edit** (`Datei / Methode / Befund filtern`): live-Filter über alle Spalten

### Grid-Interaktion

| Aktion | Wirkung |
|--------|---------|
| **Klick auf Zeile** | Befund als Markdown-Prompt in Zwischenablage (für Claude AI) |
| **Doppelklick** | Datei in IDE öffnen + zur Befund-Zeile springen |
| **Hover** | Tooltip mit vollem Datei-Pfad |
| **Klick auf Spalten-Header** | Sortierung |

### Export

| Button | Format | Inhalt |
|--------|--------|--------|
| **JSON** | `.json` | Alle Befunde als Array |
| **CSV** | `.csv` | Excel-tauglich (Semikolon-getrennt) |
| **HTML-Report** | `.html` | Self-contained Report mit Sortierung, Filter, Code-Snippets, Vorher/Nachher |
| **Jira** | Clipboard | Wiki-Markup für Jira-Tickets (gefiltert auf Datei) |
| **Clipboard** | Clipboard | Plain-Text mit Vorher/Nachher (gefiltert auf Datei) |

---

## Konfigurations-Dateien

Alle in `%APPDATA%\StaticCodeAnalyser\`:

| Datei | Inhalt |
|-------|--------|
| `ignore.txt` | Datei-/Verzeichnis-Patterns die NICHT analysiert werden |
| `repo.ini` | VCS-Settings (BaseBranch, git/svn-Pfade) — siehe [readme_repo.md](readme_repo.md) |
| `recent.ini` | Zuletzt verwendete Projektpfade |
| `StaticCodeAnalyser_scan.log` | Diagnose-Log: welche Datei wie lange gebraucht hat |

---

## Suppression

Einzelne Befunde im Code unterdrücken:

```pascal
// noinspection MemoryLeak
list := TStringList.Create;

// noinspection NilDeref, DivByZero
DoSomethingRisky;

// noinspection All
// alle Pruefungen fuer die naechste Zeile
```

Erkannte Kategorien: `MemoryLeak`, `EmptyExcept`, `SQLInjection`,
`HardcodedSecret`, `FormatMismatch`, `UnusedUses`, `NilDeref`,
`MissingFinally`, `DivByZero`, `DeadCode`, `LongMethod`, `LongParamList`,
`MagicNumber`, `DuplicateString`, `HardcodedPath`, `DebugOutput`,
`DeepNesting`, `All`.

---

## Ownership-Transfer (kein MemoryLeak-Befund)

Folgende Muster werden als Ownership-Übergabe erkannt:

| Muster | Beispiel |
|--------|----------|
| `Result := varName` | Funktion gibt Ownership ab |
| `inherited Create(varName, …)` | Elternkonstruktor übernimmt |
| `TAnyClass.Create(varName, …)` | Anderer Konstruktor übernimmt |
| `Container.Add(varName)` | TObjectList o.ä. übernimmt |
| `Container.Add(key, varName)` | TObjectDictionary übernimmt |
| `Container.AddObject(text, varName)` | TStringList mit Objekten |
| `Container.Insert(i, varName)` | TList.Insert |
| `Container.Push(varName)` | TStack.Push |
| `Container.Enqueue(varName)` | TQueue.Enqueue |

---

## Architektur

```
StaticCodeAnalyserIDE/                 IDE-Expert Paket (.dpk)
  uIDEExpert.pas                       Wizard-Registrierung (IOTAMenuWizard)
  uIDEAnalyserForm.pas                 Dockbares Fenster (TFrame)
                                       Filter, Stats, Export, Branch-Changes,
                                       Claude-Prompt-Generator

StaticCodeAnalyserForm/sources/        Analyse-Engine (shared)
  uLexer.pas, uParser2.pas             Tokenizer + Recursive-Descent-Parser
                                       mit Watchdog (200k Token-Limit) und
                                       Forward-Progress-Garantien
  uAstNode.pas                         AST mit FindAll/FindFirst-Suche
  uStaticAnalyzer2.pas                 Orchestriert 21 Detektoren pro Datei
  uStaticFiles.pas                     Rekursiver Datei-Scan mit Tick-Callback,
                                       Cancel-Support, Symlink-Schutz
  uIgnoreList.pas                      ignore.txt + Test-Filter
  uVcsChanges.pas                      Git/SVN-Diff via CreateProcess+Pipe
  uRepoSettings.pas                    repo.ini (BaseBranch etc.)
  uSuppression.pas                     // noinspection-Marker
  uExport.pas                          JSON/CSV/HTML/Jira/Clipboard
  uFixHint.pas                         Vorher/Nachher pro Befund-Typ

  uLeakDetector2.pas                   MemoryLeak (AST-basiert)
  uFieldLeak.pas                       Class-Field-Leak (Create/Destroy)
  uCodeSmells2.pas                     EmptyExcept
  uSQLInjection.pas, uSQLInjectionScore.pas
  uHardcodedSecret.pas, uHardcodedPath.pas
  uFormatMismatch.pas, uUnusedUses.pas
  uNilDeref.pas, uMissingFinally.pas
  uDivByZero.pas, uDeadCode.pas
  uLongMethod.pas, uLongParamList.pas
  uMagicNumbers.pas, uDuplicateString.pas
  uDuplicateBlock.pas
  uDebugOutput.pas, uDeepNesting.pas
  uTodoComment.pas, uEmptyMethod.pas
```

### Datenfluss

```
Datei → Lexer → Parser2 → AST (TAstNode)
                              │
                              ├── 21 Detektoren parallel (try-except pro Detector)
                              │       jeder produziert TLeakFinding
                              │
                              └── TSuppression filtert noinspection-Markierungen
                                          │
                                          └── TObjectList<TLeakFinding>
                                                  │
                                                  └── PopulateFindings →
                                                      Stats-Cards + Grid + Export
```

---

## Performance

Bei einem typischen 1000-Unit-Repo:

| Phase | Pro File | 1000 Files |
|-------|----------|------------|
| Verzeichnis-Scan | — | 1-3 s |
| Lexer | ~5-15 ms | ~10 s |
| Parser2 | ~10-50 ms | ~30 s |
| 21 Detektoren | ~5-30 ms | ~20 s |
| Suppression-Sweep | — | <1 s |
| **Gesamt** | **~30-100 ms** | **~60-90 s** |

**Für inkrementelle Re-Scans nur Branch-Änderungen** statt Voll-Scan
benutzen — typisch 200 ms bis 3 s. Siehe [readme_repo.md](readme_repo.md).

### Robustheit

- **Watchdog**: 200k Token-Limit pro Datei → pathologische Inputs werden
  nach <1 s abgebrochen (statt zu hängen)
- **GuardAdvance**: Forward-Progress-Garantie in allen Outer-Parser-Loops
- **MAX_FILE_BYTES = 5 MB**: größere Files sofort als FileError gemeldet
- **MAX_DEPTH = 32**: Symlink-Endlosschleifen-Schutz
- **Cancel jederzeit**: EAbort propagiert sauber durch alle Schichten
- **Pro-Detektor try/except**: ein crashing Detektor blockiert nicht die
  anderen 20

---

## Test-Projekte

```
StaticCodeAnalyserForm/tests/
  TestProject.dpr                      DUnitX-Konsolen-Runner
  uTestAnalyserChecks.pas              ~290 Tests in 26 Fixtures
                                       (1 Fixture pro Detektor)
  uTestTAstNode.pas                    AST-Helper-Tests
  uTestPerformance.pas                 Throughput-Benchmarks
                                       (Tokens/ms, Lines/ms)
```

Tests laufen mit DUnitX. Im Console-Modus erzeugt das Testprojekt einen
NUnit-XML-Report — CI-tauglich.

---

## Voraussetzungen

- Delphi 12 (Alexandria)
- DUnitX (für Tests, nicht für Plugin)
- Optional: Git for Windows oder TortoiseSVN MIT CLI-Tools für Branch-Changes
