# Static Code Analysis Tool for Delphi

**Statisches Code-Analyse-Tool** und **Linter** für **Delphi 12 / RAD Studio (Athens)** —
als **IDE-Plugin** mit dockbarem Tool-Fenster plus **eigenständige Windows-Anwendung**.
AST-basierte Analyse mit **21 Detektoren** für Speicherlecks, SQL-Injection,
Code-Smells, Sicherheitslücken und Code-Duplikate. Sonar-Style-Klassifikation mit
Quality Score. Ein Klick auf einen Befund kopiert einen AI-fertigen Markdown-Fix-Prompt
in die Zwischenablage. Open Source, MIT-lizenziert.

🇬🇧 [English version](README.md)

![Static Code Analysis Tool for Delphi im Delphi-IDE-Dock](docs/APP.png)

---

## Was dieses Plugin kann

In einem Satz: **Sonar-Funktionalität für Delphi-Projekte ohne Sonar-Setup,
direkt in der IDE, mit Claude-AI-Anbindung.**

| Fähigkeit | Wie genutzt |
|-----------|-------------|
| 🐛 **Bugs finden** | 21 Detektoren laufen über jede `.pas`-Datei (MemoryLeak, NilDeref, DivByZero, FormatMismatch, …) |
| 🔐 **Sicherheitslücken** | SQLInjection (Score-basiert), HardcodedSecret, HardcodedPath |
| 🧹 **Code-Smells** | LongMethod, MagicNumber, EmptyExcept, MissingFinally, DeadCode, DuplicateString/Block |
| ⚡ **Inkrementell analysieren** | „Branch-Changes"-Button: nur die im Git-/SVN-Branch geänderten Dateien — 200 ms statt 60 s |
| 🤖 **Claude-AI-Prompt** | Klick auf Befund → vollständiger Markdown-Block mit Code-Kontext + Vorher/Nachher in der Zwischenablage |
| 📊 **Sonar-Style-Dashboard** | Stat-Tiles über dem Grid: Fehler / Warnungen / Hinweise / Bugs / Vulnerabilities / Codequalität-Score |
| 🎯 **Filtern & Sortieren** | Severity-Combo, Type-Combo, Live-Such-Edit, klickbare Spalten-Header |
| 📤 **Exportieren** | CSV, JSON, HTML-Report, Jira-Wiki-Markup, Clipboard mit Vorher/Nachher |
| 🔇 **Suppression** | `// noinspection MemoryLeak` pro Zeile + `ignore.txt` für ganze Dateien |
| 🌓 **Theme-aware** | Folgt automatisch dem aktiven IDE-Theme (Light/Dark/Mountain Mist/Carbon) |
| 💡 **Vorher/Nachher-Hilfe** | Pro Detektor ein Code-Beispiel "wie es falsch aussieht" + "wie es richtig aussieht" im Help-Panel |

---

## Hauptfeatures

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
Konfigurierbar via `analyser.ini`. Details: [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md).

### 3. AI-Integration (Claude-Prompt per Klick)

Klick auf eine Befund-Zeile im Grid → ein **vollständiger Markdown-Prompt**
landet in der Zwischenablage: Befund-Metadaten, Code-Kontext (±5 Zeilen
mit Marker auf der Befund-Zeile), Vorher/Nachher-Lösung. **Strg+V im
Claude-Chat** — und Claude bekommt genug Kontext um den Fix konkret
vorzuschlagen.

---

## Quick-Start

1. Plugin bauen **und installieren**: `StaticCodeAnalyserIDE\StaticCodeAnalyserIDE.dpk`
   öffnen → **Build** → anschließend **Install** (Rechtsklick auf das Paket
   im Project Manager → **Install**, oder Menü **Component → Install Packages**
   → Paket auswählen). Ohne den Install-Schritt bleibt das Plugin nur
   kompiliert, taucht aber nicht im Menü der IDE auf.
2. In Delphi: **Ansicht → Static Code Analysis Tool for Delphi** → dockbares Fenster erscheint
3. Projektpfad wählen → **Analyse starten**

Für inkrementelle Analyse nur der im Branch geänderten Dateien siehe
[BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md).

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
| | `DuplicateBlock` (≥ `DuplicateBlockMinLines`, default 8 Zeilen identischer Code) | Hinweis |
| **Lesefehler** | `FileReadError` (Parser hängt / Datei zu groß) | Fehler |

Pro Detektor gibt es ein **Vorher/Nachher-Code-Beispiel** im Hilfe-Panel.
Per Klick auf einen Befund landet ein **Markdown-Block für Claude AI** in
der Zwischenablage.

Vollständiger Status der 50-Sonar-Pruefregeln: siehe [DETECTORS_de.md](DETECTORS_de.md).

---

## Bedienung

### Buttons (von links nach rechts)

| Button | Funktion |
|--------|----------|
| **Verzeichnis-Auswahl** (`...`) | Projektordner wählen |
| **Einstellungen...** | `analyser.ini` öffnen — VCS-Settings, Custom-LeakyClasses (siehe [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md)) |
| **Ignore...** | `ignore.txt` öffnen — Datei-/Verzeichnis-Filter |
| **Analyse starten** | Rekursiver Verzeichnis-Scan |
| **Aktuelle Datei** | Nur die im Editor offene `.pas` |
| **Branch-Changes** | Nur via Git/SVN geänderte Dateien (siehe [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md)) |
| **Abbrechen** | Bricht laufende Analyse ab |

### Detektor-Konfiguration

In der Toolbar gibt es keine Toggle-Checkboxen mehr — alles optionale
Detektor-Verhalten wird über `analyser.ini` konfiguriert (siehe
_Konfigurations-Dateien_ unten). Datei via **Einstellungen…**-Button
öffnen, anpassen, speichern, **Analyse starten** klicken. Settings
werden bei jedem Lauf neu geladen, kein IDE-Neustart nötig.

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
| **Klick auf Zeile** | Befund als Markdown-Prompt in Zwischenablage (für Claude AI) **und** — wenn die Datei in der IDE offen ist — wird ein 3-px-roter Streifen am linken Rand der zugehörigen Zeile im Editor gezeichnet |
| **Doppelklick** | Datei in IDE öffnen, zur Befund-Zeile springen, Zeilen-Marker setzen |
| **Hover (Datei-Spalte)** | Tooltip mit vollem Datei-Pfad (100 ms Delay) |
| **Klick auf Spalten-Header** | Sortierung |
| **3-px-Indikatorleiste links** der Grid-Zeile | Severity-Akzent (rot/orange/grün/blau) |

### Export

| Button | Format | Inhalt |
|--------|--------|--------|
| **JSON** | `.json` | Alle Befunde als Array |
| **CSV** | `.csv` | Excel-tauglich (Semikolon-getrennt) |
| **HTML-Report** | `.html` | Self-contained Report mit Sortierung, Filter, Code-Snippets, Vorher/Nachher |
| **Jira** | Clipboard | Wiki-Markup für Jira-Tickets (gefiltert auf Datei) |
| **Clipboard** | Clipboard | Plain-Text mit Vorher/Nachher (gefiltert auf Datei) |

---

## Sprache / Lokalisierung

Die UI-Quellsprache ist **Englisch**. UI-Strings sind mit dem `_('…')`-
Makro aus `uLocalization.pas` gewrappt, das bei aktivem dxgettext
(GNU gettext für Delphi) zur Übersetzung weiterleitet.

### Sprache umschalten

| Zustand | Effekt |
|---------|--------|
| **Default (kein dxgettext)** | UI zeigt die Quellstrings direkt — Englisch |
| **dxgettext aktiv, kein `SetLanguage` aufgerufen** | UI folgt System-Locale via `gnugettext.UseLanguageFromSysLocale` |
| **`uLocalization.SetLanguage('de')`** | UI wechselt auf Deutsch via `i18n/de.po` |
| **`uLocalization.SetLanguage('fr')`** | UI wechselt auf Französisch via `i18n/fr.po` |
| **`uLocalization.SetLanguage('en')`** | UI auf Englisch erzwingen |

Sprache beim Start setzen — in `TAnalyserDockableForm.FrameCreated`
(IDE-Plugin) oder im Standalone-`TForm2.FormCreate` aufrufen:

```pascal
uses uLocalization;

SetLanguage('de');   // 'de' / 'en' / 'fr' / '' (= System-Default)
```

### Wo die Übersetzungen liegen

| Pfad | Zweck |
|------|-------|
| `i18n/template.pot` | Quell-Template (Englisch) |
| `i18n/de.po` | Deutsche Übersetzung |
| `i18n/fr.po` | Französische Übersetzung |
| `i18n/en.po` | Englischer Identity-Baseline |
| `locale/<lang>/LC_MESSAGES/default.mo` | Compiled Binary, zur Laufzeit geladen |

Die `.po`-Dateien sind Klartext und Git-freundlich; mit
[poEdit](https://poedit.net/) oder einem normalen Editor bearbeiten.

### dxgettext aktivieren (einmalig)

Ohne installiertes dxgettext ist der Wrapper Passthrough — jeder `_()`-
Aufruf gibt den Quellstring unverändert zurück. Die UI bleibt Englisch,
egal mit welchem Argument `SetLanguage` gerufen wird.

Um echte Übersetzungen zu bekommen:

1. <https://github.com/sjrd/dxgettext> klonen
2. Den `dxgettext/Source/`-Ordner zu `DCC_UnitSearchPath` von IDE-Plugin
   und Standalone-EXE hinzufügen
3. `{$DEFINE USE_GETTEXT}` in der `.dpk` setzen (oder via **Project
   Options → Conditional Defines**)
4. Jede `.po` zu `.mo` kompilieren:
   ```
   msgfmt i18n/de.po -o locale/de/LC_MESSAGES/default.mo
   msgfmt i18n/fr.po -o locale/fr/LC_MESSAGES/default.mo
   ```
5. Den `locale/`-Ordner neben die BPL/EXE legen

Komplette Schritt-für-Schritt-Anleitung: [I18N.md](I18N.md).

---

## Theme-Integration

Das Plugin folgt automatisch dem aktiven Delphi-IDE-Theme:

- **`StyleServices.GetSystemColor`** in Custom-Drawing (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace`/`clWindow`/`clBtnText`** als Property-Werte (auto-themed via VCL Style)
- **`IOTAIDEThemingServices.ApplyTheme`** beim Frame-Hosting
- **`INTAIDEThemingServicesNotifier`** für Live-Theme-Wechsel
- **`CM_STYLECHANGED`** + **`SetParent`-Override** als zusätzliche Trigger

Severity-Hintergrundfarben werden zur Paint-Zeit aus der themed
`clWindow`-Basis + saturierten Akzentfarben gemischt — funktioniert in
jedem Theme ohne separate Light-/Dark-Tabellen.

**Bekannte Limitation**: Im Floating-Modus übernimmt das Plugin-Fenster
IDE-Theme-Wechsel zur Laufzeit nicht zuverlässig (kein offizieller Hook
in `INTACustomDockableForm` für Live-Reapply der Wrapper-Form). Workaround:
Plugin im Dock-Modus betreiben oder Fenster nach Theme-Wechsel schließen
und erneut öffnen.

---

## Konfigurations-Dateien

Alle in `%APPDATA%\StaticCodeAnalyser\`:

| Datei | Inhalt |
|-------|--------|
| `analyser.ini` | Alle Settings — VCS (BaseBranch, git/svn-Pfade), Detektor-Toggles (`UsesCheck`, `IncludeTests`, `AutoDiscoverClasses`), Custom-`LeakyClasses` / `ExcludeLeakyClasses`, Detektor-Schwellwerte, UI-Sprache. Wird beim ersten Start mit selbst-dokumentierten Kommentaren neben jeder Option angelegt |
| `ignore.txt` | Datei-/Verzeichnis-Patterns die NICHT analysiert werden |
| `recent.ini` | Zuletzt verwendete Projektpfade |
| `LeakyClassesDiscover.log` | Output von `AutoDiscoverClasses=1` — gefundene Klassen aufgeteilt in _instantiable_ (haben ctor/dtor oder `Create()`-Aufruf) und _static-only candidates_. Relevante manuell in `LeakyClasses=` von `analyser.ini` übernehmen |
| `StaticCodeAnalyser_scan.log` | Diagnose-Log: welche Datei wie lange gebraucht hat |

### Detektor-Schwellwerte (alle optional, in `[Detectors]`)

| Key | Default | Wirkung |
|-----|---------|---------|
| `LongMethodMaxBodyLines` | 50 | `LongMethod` greift wenn Body-Zeilen UND Statement-Anzahl beide über den Schwellen liegen |
| `LongMethodMaxStatements` | 30 | (sekundäre Schwelle für `LongMethod`) |
| `LongParamListMaxParams` | 5 | `> N` Parameter → Refactoring-Hinweis |
| `DeepNestingMaxDepth` | 4 | `> N` verschachtelte Kontroll-Strukturen |
| `DuplicateBlockMinLines` | 8 | minimale normalisierte Zeilen-Anzahl für Duplikat-Erkennung |
| `MaxFileMB` | 5 | größere Dateien werden übersprungen (OOM-Schutz bei generiertem Code) |
| `MagicNumberTrivials` | `0,1,2,-1,10,100` | Zahlen die NICHT als Magic-Number gemeldet werden |
| `UsesCheck` | 0 | `UnusedUses`-Detektor (default off — produziert ggf. false positives) |
| `IncludeTests` | 0 | `uTest*.pas`, `*_Tests.pas`, `TestProject*.dpr`, `/tests/`-Ordner mit-analysieren |
| `WatchMode` | 0 | **nur IDE-Plugin** — Live-Analyse beim Speichern. Pro offener `.pas`-Datei haengt das Plugin einen `IOTAModuleNotifier`; nach jedem `Strg+S` wird die Datei im Hintergrund-Thread re-analysiert und das Grid aktualisiert sich innerhalb ~50–100 ms. 300 ms Debounce glaettet Save-on-Build-Stuerme. **Wird automatisch aktiviert** (egal was diese INI-Option sagt) wenn Du auf **Aktuelle Datei** klickst — das ist der natural fit fuer Live-Editing |
| `AutoDiscoverClasses` | 0 | Projekt-AST nach Custom-Klassen scannen die `Free` brauchen, automatisch zu `LeakyClasses` ergänzen |
| `LeakyClasses` | _(leer)_ | kommagetrennt — zusätzliche Klassen die getrackt werden sollen |
| `ExcludeLeakyClasses` | _(leer)_ | kommagetrennt — Klassen die NICHT getrackt werden sollen, auch wenn sie in den Defaults stehen |

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
                                       Claude-Prompt-Generator, Theme-Notifier

StaticCodeAnalyserForm/sources/        Analyse-Engine (shared zwischen Standalone + IDE-Plugin)
  uAnalyserPalette.pas                 Zentrale Farb-Konstanten (Severity, Akzente, Icons)
  uAnalyserTypes.pas                   TFindingSeverity-Enum + Konversion
  uAnalyserTheme.pas                   SeverityBg, SeverityAccent, BlendColor

  uLexer.pas, uParser2.pas             Tokenizer + Recursive-Descent-Parser
                                       mit Watchdog (200k Token-Limit) und
                                       Forward-Progress-Garantien
  uAstNode.pas                         AST mit FindAll/FindFirst-Suche
  uStaticAnalyzer2.pas                 Orchestriert 21 Detektoren pro Datei
  uStaticFiles.pas                     Rekursiver Datei-Scan mit Tick-Callback,
                                       Cancel-Support, Symlink-Schutz
  uIgnoreList.pas                      ignore.txt + Test-Filter
  uVcsChanges.pas                      Git/SVN-Diff via CreateProcess+Pipe
  uRepoSettings.pas                    analyser.ini (BaseBranch etc.)
  uSuppression.pas                     // noinspection-Marker
  uExport.pas                          JSON/CSV/HTML/Jira/Clipboard
  uFixHint.pas                         Vorher/Nachher pro Befund-Typ
  uClaudePrompt.pas                    Markdown-Prompt-Generator

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
benutzen — typisch 200 ms bis 3 s. Siehe [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md).

### Robustheit

- **Watchdog**: 200k Token-Limit pro Datei → pathologische Inputs werden
  nach <1 s abgebrochen (statt zu hängen)
- **GuardAdvance**: Forward-Progress-Garantie in allen Outer-Parser-Loops
- **`MaxFileMB` (default 5 MB)**: größere Files sofort als `FileError`
  gemeldet. Konfigurierbar in `analyser.ini`.
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

---

## Komponenten-Übersicht

| Komponente | Pfad | Zweck |
|------------|------|-------|
| **Standalone-EXE** | `StaticCodeAnalyserForm/analyser.d12.dproj` | Verzeichnis-/Datei-Scan außerhalb der IDE |
| **IDE-Plugin** | `StaticCodeAnalyserIDE/StaticCodeAnalyserIDE.dpk` | Hauptfeature: dockbares Tool-Fenster mit allen Funktionen |

Beide nutzen die gemeinsame Analyse-Engine in `StaticCodeAnalyserForm/sources/`.

---

## Dokumentation

Das Repository enthält drei Markdown-Dokumente. Sie ergänzen sich
inhaltlich, sodass jedes für sich gelesen werden kann:

| Datei | Inhalt | Wann nachschlagen |
|-------|--------|-------------------|
| [README_de.md](README_de.md) | **Übersichts-Doku** — was das Plugin kann, wie es bedient wird, Architektur, Performance, Suppression, Theme-Integration | Erste Anlaufstelle für alle Themen außer den zwei Spezial-Bereichen unten |
| [DETECTORS_de.md](DETECTORS_de.md) | **Kanonische Detektor-Liste** — alle 50 Sonar-Prüfregeln plus 3 Bonus-Detektoren mit Status (✅ implementiert / 🟡 teilweise / 🔲 offen), Beschreibung und zuständiger Unit | Wenn du wissen willst welche Regel implementiert ist, was sie genau prüft, oder welcher Detektor als nächstes drankommt |
| [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md) | **VCS-/Branch-Changes-Feature** — wie der `Branch-Changes`-Button funktioniert, Git/SVN-Setup, Tortoise-Kompatibilität, `analyser.ini`-Konfiguration, Troubleshooting für Repo-Erkennung | Wenn der Branch-Changes-Button nicht macht was er soll, oder du das VCS-Setup feinjustieren willst |

Konvention: `README_de.md` ist breit, die anderen zwei sind tief und auf
einen Aspekt fokussiert. Wenn du eine bestehende Section in `README_de.md`
zu groß findest, wird sie typischerweise in eine eigene Spezial-Datei
ausgelagert (so wie es mit dem Branch-Changes-Teil passiert ist).

---

## Unterstützen

Wenn dir das Plugin Zeit spart, freue ich mich über einen Kaffee:

[![Donate via PayPal](https://img.shields.io/badge/PayPal-Donate-blue?logo=paypal&style=flat-square)](https://paypal.me/nrodear)

Direktlink: <https://paypal.me/nrodear>
