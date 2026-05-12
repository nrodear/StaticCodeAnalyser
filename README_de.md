# Static Code Analysis Tool for Delphi

[![Spendier mir einen Kaffee](https://img.shields.io/badge/%E2%98%95_Spendier_mir_einen_Kaffee-paypal.me%2Fnrodear-0070BA?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/nrodear)

[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-green.svg?style=flat)](LICENSE)
[![PayPal](https://img.shields.io/badge/PayPal-paypal.me%2Fnrodear-0070BA?style=flat&logo=paypal&logoColor=white)](https://paypal.me/nrodear)

> Wenn dir das Plugin bei deiner Delphi-Arbeit Zeit spart, freue ich mich über einen Kaffee. 🙏

---

**Statisches Code-Analyse-Tool** und **Linter** für **Delphi 12 / RAD Studio (Athens)** —
als **IDE-Plugin** mit dockbarem Tool-Fenster plus **eigenständige Windows-Anwendung**.
AST-basierte Analyse mit **insgesamt 41 Detektoren**: 21 Pascal-Checks für
Speicherlecks, SQL-Injection, Code-Smells, Sicherheitslücken und Code-Duplikate,
**plus ein dedizierter DFM-Scanner mit 20 Checks** auf Basis eines eigenen DFM-Lexers
+ Parsers + Komponentengraph, verheiratet mit dem Pascal-AST — tote Event-Handler,
Klartext-DB-Credentials in Form-Dateien, zirkuläre Master-Detail-Verkettung,
Required-Felder ohne UI-Bindung, SQL aus `TEdit.Text`, Cross-Form-Kopplung und mehr.
Sonar-Style-Klassifikation mit Quality Score. Repo-weiter Form-Index für Cross-Unit-
Analyse. VCS-Diff-Modus behandelt `.dfm`-Änderungen als Trigger für die zugehörige
`.pas`. HTML-Report mit gruppiertem `.pas`+`.dfm`-Filter. IDE-Plugin öffnet
DFM-Befunde direkt als Text im Code-Editor. Ein Klick auf einen Befund kopiert
einen AI-fertigen Markdown-Fix-Prompt in die Zwischenablage. Open Source,
MIT-lizenziert.

🇬🇧 [English version](README.md)

![Static Code Analysis Tool for Delphi im Delphi-IDE-Dock](docs/APP.png)

---

## Was dieses Plugin kann

In einem Satz: **Sonar-Funktionalität für Delphi-Projekte ohne Sonar-Setup,
direkt in der IDE, mit Claude-AI-Anbindung.**

| Fähigkeit | Wie genutzt |
|-----------|-------------|
| 🐛 **Bugs finden** | 21 Pascal-Detektoren laufen über jede `.pas`-Datei (MemoryLeak, NilDeref, DivByZero, FormatMismatch, …) plus 20 DFM-Detektoren über jede `.dfm` (tote Event-Handler, Klartext-DB-Credentials, zirkuläre Master-Detail-Verkettung, …) — **insgesamt 41** |
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

### 1. Statische Code-Analyse (insgesamt 41 Detektoren — 21 Pascal + 20 DFM, Sonar-Taxonomie)

**Pascal-AST-Checks (21)**: **Bugs** (MemoryLeak, NilDeref, DivByZero,
FormatMismatch), **Vulnerabilities** (SQLInjection, HardcodedSecret),
**Security Hotspots** (HardcodedPath), **Code Smells** (LongMethod,
MagicNumber, DeadCode, EmptyExcept, MissingFinally, …) und **Code
Duplication** (DuplicateString, DuplicateBlock).

**DFM-Checks (20)** auf Basis eines eigenen Form-Datei-Lexers +
Parsers + Komponentengraph, gekoppelt mit dem Pascal-AST via FormBinder:
tote Event-Handler, Klartext-DB-Credentials in Form-Dateien, zirkuläre
Master-Detail-Verkettung, Required-Felder ohne UI-Bindung, SQL aus
`TEdit.Text`, Cross-Form-Kopplung, doppelte Steuer-Hotkeys, nicht
übersetzte Caption-Strings und mehr. Repo-weiter Form-Index für
Cross-Unit-Analyse.

Jeder Befund kommt mit einer Vorher/Nachher-Lösung im Hilfe-Panel.

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

## Was wird erkannt (41 Detektoren — 21 Pascal + 20 DFM)

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

Die **20 DFM-spezifischen Detektoren** (DFM-DeadEventHandler,
DFM-HardcodedDBCredentials, DFM-CircularMasterDetail,
DFM-MissingRequiredFieldBinding, DFM-SQLFromTEditText …) und ihre
Fix-Hints: siehe [DETECTORS_de.md](DETECTORS_de.md).

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
- **Profile-Combo**: schaltet das aktive Rule-Set live um. Mitgeliefert:
  `ide-fast` (Plugin-Default — nur Bugs + Vulns), `default` (alle
  Detektoren), `strict` (alle + `UnusedUses`), `security` (Vulns +
  Hotspots), `bugs-only`, `code-quality`, `dfm-only`. Profile leben in
  `rules/sca-rules.json` unter `profiles` und die Combo wird daraus
  gefüllt — eigene Profile dort eintragen, erscheinen automatisch.
  Auswahl wird in `[Rules] IdeProfile` persistiert und greift beim
  nächsten Analyse-Lauf.
- **Such-Edit** (`Datei / Methode / Befund filtern`): live-Filter über alle Spalten

### Grid-Interaktion

| Aktion | Wirkung |
|--------|---------|
| **Klick auf Zeile** | Befund als Markdown-Prompt in Zwischenablage (für Claude AI) **und** — wenn die Datei in der IDE offen ist — wird ein 3-px-roter Streifen am linken Rand der zugehörigen Zeile im Editor gezeichnet |
| **Doppelklick** | Datei in IDE öffnen, zur Befund-Zeile springen, Zeilen-Marker setzen |
| **Hover (Datei-Spalte)** | Tooltip mit vollem Datei-Pfad (100 ms Delay) |
| **Klick auf Spalten-Header** | Sortierung |
| **3-px-Indikatorleiste links** der Grid-Zeile | Severity-Akzent (rot/orange/grün/blau) |

Das **Hilfe-Panel** rechts mit den Vorher/Nachher-Code-Blöcken wird nur
im **Floating-Modus** angezeigt — wenn das IDE-Plugin-Fenster in eine
Side-Bar oder einen Tab gedockt ist, blendet sich das Panel aus und
das Grid bekommt die volle Breite (kommt innerhalb von ~250 ms nach
dem Loslösen wieder zurück).

### Export

| Button | Format | Inhalt |
|--------|--------|--------|
| **JSON** | `.json` | Alle Befunde als Array |
| **CSV** | `.csv` | Excel-tauglich (Semikolon-getrennt) |
| **HTML-Report** | `.html` | Self-contained Report mit Sortierung, Filter, Code-Snippets, Vorher/Nachher. Klick auf eine Severity-Kachel filtert — und blendet zusätzlich Dateien im Dropdown aus, die keine Befunde dieser Severity haben (mit dem Datei-Filter UND-verknüpft) |
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

## Verwendung unter Git und SVN

Der Analyser erkennt das VCS-System **automatisch** anhand des Projekt-
Verzeichnisses (sucht nach `.git/` oder `.svn/`-Marker). Custom-Rules
und alle Detektor-Konfigurationen sind **VCS-agnostisch** — derselbe
Workflow funktioniert mit beiden Systemen.

### Auto-Detection

| Marker im Projekt-Pfad | Erkannt als | Genutzte CLI |
|---|---|---|
| `.git/` (oder Eltern-Pfad enthält `.git/`) | Git | `git diff` + `git status` |
| `.svn/` | SVN | `svn status` + `svn diff` |
| keiner | None | `--branch` deaktiviert, `--full` funktioniert |

Ausführbare CLI wird automatisch gesucht in: `PATH`, dann typische
Installations-Pfade (TortoiseGit, TortoiseSVN, Git for Windows, ...).
Override via `analyser.ini` möglich (siehe unten).

### Verwendung mit Git

**Plugin/GUI**: Projekt-Pfad auf den Git-Working-Tree zeigen, dann
**Branch-Changes**-Button. Der Analyser ermittelt:
- Geänderte `.pas`-Dateien zwischen `BaseBranch` und `HEAD` (committed)
- Plus uncommitted Working-Tree-Modifikationen (wenn `IncludeWorkingTree=1`)

**CLI**:
```powershell
analyser.d12.exe --path D:\meinGitRepo --branch --report-sarif sca.sarif
```

**`analyser.ini`-Settings für Git**:
```ini
[Repo]
BaseBranch=develop          ; leer = auto: origin/HEAD -> main -> master
IncludeWorkingTree=1        ; 1 = uncommitted Aenderungen mit, 0 = nur committed

[Paths]
GitExe=C:\custom\git\bin\git.exe   ; leer = auto-Detection
```

### Verwendung mit SVN

**Plugin/GUI**: identisch zu Git — Working-Copy-Pfad wählen, **Branch-
Changes**-Button. Da SVN kein "echtes" Branch-Konzept im Working-Copy
hat, liefert der Branch-Mode hier:
- Alle uncommitted Änderungen (`svn status`-Output: M/A/R/D/?)
- Auf Wunsch erweitert um committed Differenzen seit BASE-Revision

Ideal als **Pre-Commit-Hook**: prüft genau das, was beim nächsten
`svn commit` ginge.

**CLI**:
```powershell
analyser.d12.exe --path D:\meinSvnWC --branch --report-sarif sca.sarif
```

**`analyser.ini`-Settings für SVN**:
```ini
[Repo]
BaseBranch=trunk            ; SVN: typisch trunk (informativ, da kein echter Diff)
IncludeWorkingTree=1        ; uncommitted Aenderungen mit

[Paths]
SvnExe=C:\custom\svn\bin\svn.exe   ; leer = auto: PATH + TortoiseSVN
```

**Auto-Detection-Pfade für SVN**:
1. `svn.exe` im PATH
2. `C:\Program Files\TortoiseSVN\bin\svn.exe`
3. `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe`
4. `C:\Program Files\Subversion\bin\svn.exe`

### Custom-Rules unter beiden VCS

Die [Custom-Rule-Engine](examples/README.md) (YAML-Profile) ist
unabhängig vom VCS — sie liest nur Dateien. Empfohlener Workflow für
**beide** VCS-Systeme:

1. `analyser-rules.yml` (oder eines der Profile aus `examples/`) ins
   **Projekt-Wurzelverzeichnis** legen — Git/SVN versionieren die Datei mit
2. In `analyser.ini` referenzieren:
   ```ini
   [Detectors]
   CustomRulesFile=analyser-rules.yml   ; relativ zum Projekt-Root
   ```
3. Plugin/GUI lädt automatisch beim nächsten Analyse-Lauf

So pflegt jedes Projekt **sein eigenes Ruleset im Repo** — Team-shared,
versioniert, in Code-Reviews mitchangbar.

### CI/CD-Integration

**GitHub Actions** (Git): siehe Vorlage [`.github/workflows/sca.yml`](.github/workflows/sca.yml).
SARIF-Upload erscheint als Inline-Annotations im PR.

**GitLab CI / Jenkins / TeamCity / Azure DevOps**: identisches Muster —
Tool im Pipeline-Image bereitstellen, `analyser.exe --path . --branch
--report-sarif sca.sarif` aufrufen, Artefakt anhängen oder weiterver-
arbeiten (SARIF-Plugins für die meisten CI-Systeme verfügbar).

**SVN-Pre-Commit-Hook** (Server-side, Linux):
```bash
#!/bin/sh
# /path/to/svn-repo/hooks/pre-commit
REPOS="$1"
TXN="$2"

# Tool-Pfad und Working-Copy-Mirror anpassen
ANALYSER=/opt/sca/analyser.d12.exe
WC=/tmp/sca-precommit-$TXN

svn export "$REPOS" "$WC" -r "$TXN" --quiet
"$ANALYSER" --path "$WC" --full --quiet
EXIT=$?
rm -rf "$WC"
exit $EXIT
```

Exit-Code-Mapping (siehe [Headless CLI](#headless-cli-mode)):
- 0 = clean → commit erlaubt
- 1 = nur Hints → commit erlaubt
- 2 = Warnings → commit erlaubt (oder blockieren via Hook-Logik)
- 3 = Errors → **commit blockiert**

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
| `CyclomaticMax` | 10 | McCabe-Komplexität `> N` pro Methode (zählt `if`, `case`-Arm, `for`/`while`/`repeat`, `on`-Handler, `and`/`or`/`xor`) |
| `DuplicateBlockMinLines` | 8 | minimale normalisierte Zeilen-Anzahl für Duplikat-Erkennung |
| `MaxFileMB` | 5 | größere Dateien werden übersprungen (OOM-Schutz bei generiertem Code) |
| `MagicNumberTrivials` | `0,1,2,-1,10,100` | Zahlen die NICHT als Magic-Number gemeldet werden |
| `UsesCheck` | 0 | `UnusedUses`-Detektor (default off — produziert ggf. false positives) |
| `IncludeTests` | 0 | `uTest*.pas`, `*_Tests.pas`, `TestProject*.dpr`, `/tests/`-Ordner mit-analysieren |
| `AutoDiscoverClasses` | 0 | Projekt-AST nach Custom-Klassen scannen die `Free` brauchen, automatisch zu `LeakyClasses` ergänzen |
| `LeakyClasses` | _(leer)_ | kommagetrennt — zusätzliche Klassen die getrackt werden sollen |
| `ExcludeLeakyClasses` | _(leer)_ | kommagetrennt — Klassen die NICHT getrackt werden sollen, auch wenn sie in den Defaults stehen |

### Live-Watch (nur IDE-Plugin) — ⚠️ RISKY

Klick auf **Aktuelle Datei** im IDE-Plugin aktiviert einen Single-File-Live-Watch
auf genau diese Datei: bei jedem Save (300 ms debounced) und Edit (1000 ms
debounced) laeuft die Analyse fuer DIESE Datei automatisch im Hintergrund-Thread.
Tab-Wechsel auf eine andere Datei aendert nichts; erneuter Klick auf
**Aktuelle Datei** haengt den Watch um. Bulk-Pfade (**Analyse starten**,
**Branch-Changes**) deaktivieren den Watch explizit. Es gibt kein INI-Flag dafuer.

> ⚠️ **Risiko Endlosschleife.** Es existiert heute **kein Re-Entrancy-Guard**
> fuer ueberlappende Worker-Spawns. Wenn der Worker laenger als der Edit-
> Debounce (1000 ms) braucht und der User waehrenddessen weiter tippt, wachst
> der Worker-Backlog statt zu schrumpfen. Zusaetzlich kann (Delphi-version-
> abhaengig) ein Editor-Repaint nach Findings-Update wieder als `Modified`
> interpretiert werden — Edit-/Save-Pfad koennen sich dann gegenseitig
> nachtriggern. Heute geschuetzt nur durch den Generation-Counter (verwirft
> _spaete_ Ergebnisse, verhindert aber keinen ueberlappenden Spawn). Vor
> breitem Einsatz unbedingt erst Re-Entrancy-Guard + Hard-Cap einbauen
> (`TODO.md` -> _Single-File-Live-Watch_).

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

Erkannte Kategorien (eine pro registriertem Detektor — Single source of
truth ist `KIND_META` in `uSCAConsts.pas`):

`MemoryLeak`, `EmptyExcept`, `SQLInjection`, `HardcodedSecret`,
`FormatMismatch`, `FileReadError`, `UnusedUses`, `NilDeref`,
`MissingFinally`, `DivByZero`, `DeadCode`, `LongMethod`, `LongParamList`,
`MagicNumber`, `DuplicateString`, `HardcodedPath`, `DebugOutput`,
`DeepNesting`, `TodoComment`, `EmptyMethod`, `DuplicateBlock`, `All`.

---

## Ownership-Transfer (kein MemoryLeak-Befund)

Folgende Muster werden als Ownership-Übergabe erkannt:

| Muster | Bedeutung |
|--------|-----------|
| `Result := varName` | Funktion gibt Ownership an Aufrufer ab |
| `varName.Parent := winControl` | VCL: TWinControl gibt seine `Controls[]` frei |
| `varName := X.Add(...)` | Borrowed-Return — Item lebt in der `OwnsObjects`-Liste |
| `varName := X.AddChild(...)` | AST-/DOM-Tree: Child gehört dem Parent |
| `varName := X.AddNode(...)` | TTreeView etc. |
| `varName := X.AppendChild(...)` | XML-DOM / IXMLNode |
| `FField := varName` | Var-zu-Feld: Ownership verlässt Method-Scope |
| `FField := varName as ISomething` | Interface-Refcount hält das Objekt am Leben |
| `inherited Create(varName, …)` | Elternkonstruktor übernimmt |
| `TAnyClass.Create(varName, …)` | Anderer Konstruktor übernimmt |
| `Container.Add(varName)` | TObjectList o.ä. übernimmt |
| `Container.Add(key, varName)` | TObjectDictionary übernimmt |
| `Container.AddObject(text, varName)` | TStringList mit Objekten |
| `Container.Insert(i, varName)` | TList.Insert |
| `Container.Push(varName)` | TStack.Push |
| `Container.Enqueue(varName)` | TQueue.Enqueue |

Für **Klassen-Felder** kennt der FieldLeak-Detektor zusätzlich das
Standard-TComponent-Owner-Pattern als kein-Leak:

| Muster | Bedeutung |
|--------|-----------|
| `FField := X.Create(Self)` | TComponent-Owner: `inherited Destroy` ruft `DestroyComponents` |
| `FField := X.Create(AOwner)` | Owner aus Konstruktor-Parameter weitergereicht |
| `FField := X.Create(Owner)` | Owner aus existierendem Feld/Property |

---

## Architektur

```
StaticCodeAnalyserIDE/                 IDE-Expert Paket (.dpk)
  uIDEExpert.pas                       Wizard-Registrierung (IOTAMenuWizard)
  uIDEAnalyserForm.pas                 Dockbares Fenster (TFrame) - Hauptshell:
                                       Filter, Stats-Grid, Sort, Export,
                                       Claude-Prompt-Copy, Lifecycle-Sentinel
  uIDELineHighlighter.pas              3 px roter Streifen im IDE-Editor-
                                       Gutter auf der Befund-Zeile
  uIDEMessages.pas                     Hand-off in den IDE-Messages-Tab
  uIDEWatchMode.pas                    Single-File-Live-Watch (Aktuelle Datei)
                                       Save 300 ms / Edit 1000 ms debounced
                                       ⚠️ kein Re-Entrancy-Guard - s. README
  uIDEStatsTiles.pas                   Sonar-Style Tile-Reihe Builder
  uIDEHelpPanel.pas                    Rechtes Help-Panel mit Vorher/Nachher,
                                       auto-hide im Docked-Modus
  uIDEExportMenu.pas                   Export-Dropdown (JSON/CSV/HTML/Jira)
  uIDEEditorIntegration.pas            ToolsAPI-Wrapper: aktuelle .pas-Datei,
                                       Project-Dir, OpenFileAtLine
  uIDEStatusBar.pas                    Drei-Panel-Statusleiste
                                       (Findings / Progress / Mode)
  uIDEThemeIntegration.pas             IDE-Theme-Notifier + ApplyTheme-Refresh
  uIDEAnalyseProgress.pas              Busy-State-Controller
                                       (Begin/EndRun, Cancel-Flag)

StaticCodeAnalyserForm/sources/        Analyse-Engine (shared zwischen Standalone + IDE-Plugin)
  Common/
    uSCAConsts.pas                     TFindingKind + KIND_META Single source
                                       of truth (Sonar-Kategorie-Mapping)
    uMethodd12.pas                     TLeakFinding-Record + Helpers
    uRecentPaths.pas                   recent.ini-Verwaltung
    uRegExMatches.pas                  Geteilte RegEx-Helpers
    uDetectorUtils.pas                 IsIdentChar, IsWholeWord-Helpers
    uCollectValues.pas                 AST-Literal-Wert-Sammlung

  UI/
    uAnalyserPalette.pas               Zentrale Farb-Konstanten
    uAnalyserTypes.pas                 TFindingSeverity-Enum + Konversion
    uAnalyserTheme.pas                 SeverityBg, SeverityAccent, BlendColor
    uFindingGridRenderer.pas           StringGrid-OnDrawCell-Logik
    uFindingFilter.pas                 Severity/Type/Search-Filter-Pipeline
    uLocalization.pas                  dxgettext-Wrapper (_('…')-Makro)

  Parsing/
    uLexer.pas                         Tokenizer, Watchdog (200k Token)
    uParser2.pas                       Recursive-Descent-Parser mit
                                       Forward-Progress-Garantie
    uAstNode.pas                       AST mit FindAll/FindFirst-Suche

  Infrastructure/
    uStaticAnalyzer2.pas               Orchestriert 21 Pascal-Detektoren pro Datei
    uStaticFiles.pas                   Rekursiver Datei-Scan, Tick-Callback,
                                       Cancel-Support, Symlink-Schutz
    uIgnoreList.pas                    ignore.txt + Test-Filter
    uVcsChanges.pas                    Git/SVN-Diff via CreateProcess+Pipe
    uRepoSettings.pas                  analyser.ini (BaseBranch etc.)
    uSuppression.pas                   // noinspection-Marker
    uExport.pas                        JSON / CSV / Jira / Clipboard
    uExportHtml.pas                    Self-contained HTML-Report

  Output/
    uClaudePrompt.pas                  AI-Markdown-Prompt-Generator
    uFixHint.pas                       Vorher/Nachher pro Befund-Typ

  Detectors/
    uLeakDetector2.pas                 MemoryLeak (Local-Var, AST-basiert)
    uFieldLeak.pas                     Class-Field-Leak (Create/Destroy)
    uCodeSmells2.pas                   EmptyExcept
    uSQLInjection.pas                  + uSQLInjectionScore.pas (Scoring)
    uHardcodedSecret.pas, uHardcodedPath.pas
    uFormatMismatch.pas, uUnusedUses.pas
    uNilDeref.pas, uMissingFinally.pas
    uDivByZero.pas, uDeadCode.pas
    uLongMethod.pas, uLongParamList.pas
    uMagicNumbers.pas, uDuplicateString.pas
    uDuplicateBlock.pas
    uDebugOutput.pas, uDeepNesting.pas
    uTodoComment.pas, uEmptyMethod.pas
    uCustomClassDiscovery.pas          AutoDiscoverClasses-Helper
                                       (kein Detektor - speist LeakyClasses)
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
| 21 Pascal-Detektoren | ~5-30 ms | ~20 s |
| DFM-Parser + 20 DFM-Detektoren (pro `.dfm`) | ~5-20 ms | ~5-10 s |
| Suppression-Sweep | — | <1 s |
| **Gesamt** | **~30-100 ms** | **~60-90 s** |

**Für inkrementelle Re-Scans nur Branch-Änderungen** statt Voll-Scan
benutzen — typisch 200 ms bis 3 s. Siehe [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md).

### Robustheit

- **Watchdog**: 200k Token-Limit pro Datei → pathologische Inputs werden
  nach <1 s abgebrochen (statt zu hängen)
- **GuardAdvance**: Forward-Progress-Garantie in allen Outer-Parser-Loops
- **Real-world Delphi-Syntax-Abdeckung**: der Parser handhabt
  `interface`-Typdeklarationen, Generics (`TFoo<T>`, `function Get<T>: T;`),
  `packed record` / `packed class`, lokale `label`-Sektionen,
  `record helper for X` / `class helper for X` und IFDEF-konditionale
  Method-Header, ohne dabei Methodenrümpfe zu verlieren — wichtig für
  real-world Codebases (mORMot2 usw.).
- **`MaxFileMB` (default 5 MB)**: größere Files sofort als `FileError`
  gemeldet. Konfigurierbar in `analyser.ini`.
- **MAX_DEPTH = 32**: Symlink-Endlosschleifen-Schutz
- **Cancel jederzeit**: EAbort propagiert sauber durch alle Schichten
- **Pro-Detektor try/except**: ein abstürzender Detektor blockiert
  nicht die anderen 40

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

- Delphi 12 (Athens)
- DUnitX (nur fuer die Testsuite, nicht fuer das Plugin selbst)
- Optional: Git for Windows oder TortoiseSVN **mit** CLI-Tools fuer das
  Branch-Changes-Feature

### Build-Ziele

| Ziel | Win32 | Win64 |
|------|-------|-------|
| **IDE-Plugin** (`StaticCodeAnalyserIDE.dpk`) | ✅ Pflicht | ❌ — muss 32-Bit bleiben, weil die RAD-Studio-12-IDE selbst 32-Bit ist und Plugins die Bitness erben |
| **Standalone-EXE / CLI** (`analyser.d12.dproj`) | ✅ | ✅ |
| **Test-Suite** (`TestProject.dproj`) | ✅ | _Plattform bei Bedarf hinzufuegen_ |

Die Standalone-EXE kompiliert sauber sowohl fuer `Win32` als auch
`Win64` — beide Ziele laufen durch dieselbe Detektor-Engine und
liefern dieselben SARIF-/JSON-/CSV-/HTML-Reports. `Win64` waehlst du,
wenn du einen groesseren Heap brauchst (relevant nur bei
Multi-GB-Scans).

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

## Verwandte Projekte & Alternativen

Wer dieses Projekt evaluiert, schaut häufig parallel auf:

- **SonarQube / SonarLint** — breite Sprach-Abdeckung, aber
  **Delphi / Object Pascal wird nicht out-of-the-box unterstützt**.
  Dieses Projekt ist der naheliegendste "Sonar-Feel" für Delphi, ohne
  selbst ein Sonar-Plugin schreiben zu müssen. Gleiche fünf Kategorien
  (Bug / Vulnerability / Security Hotspot / Code Smell / Code
  Duplication), gleiche Quality-Score-Idee, SARIF-Export für GitHub
  Code Scanning.
- **FixInsight** (CodeHealer) — kommerziell, IDE-integriert. Dieses
  Projekt ist eine **freie, Open-Source-FixInsight-Alternative** mit
  vergleichbarer Pascal-Detektor-Abdeckung plus dediziertem DFM-Scanner,
  den FixInsight nicht mitliefert.
- **Pascal Analyzer (PAL)** — kommerziell. Überlappendes Detektor-Set,
  aber keine DFM-aware Checks, kein Claude-AI-Hand-off, kein SARIF.
- **DFMCheck / GExperts DFM-Check** — Single-Purpose-DFM-Linter. Die
  20 DFM-Detektoren in diesem Projekt sind eine Obermenge
  (graph-basierte Cross-Form-Analyse, Repo-weiter Form-Index,
  Pascal-AST-Kopplung).
- **DCC32-Hints/Warnings** — eingebaute Compiler-Diagnostik. Nützlich
  aber begrenzt auf syntaktische und trivial-semantische Checks; keine
  Taxonomie, keine AST-Queries, keine Security-Kategorie.

## Schlagwörter

Delphi statische Code-Analyse, Object Pascal Linter, RAD-Studio-Plugin,
Delphi 12 Athens, Delphi-IDE-Plugin, ToolsAPI, DFM-Analyzer,
Formular-Datei-Linter, Pascal AST, SonarQube-Alternative für Delphi,
FixInsight-Alternative, Pascal-Analyzer-Alternative, Delphi
Speicherleck-Detektor, SQL-Injection-Detektor für Delphi, Hardcoded-
Secret-Scanner, Delphi Code-Smell, Delphi Code-Duplication, McCabe-
Komplexität Delphi, SARIF Delphi, Branch-Changes inkrementeller Scan,
Git-Diff Delphi, SVN-Diff Delphi, Claude-AI-Prompt, Delphi-Code-Review-
Automation, TADOQuery-Security, TFDQuery-Security, TClientDataSet-
Provider-Chain, TDataSetProvider-Audit, Master-Detail-Zirkel-Erkennung,
tote Event-Handler erkennen, untranslated Caption Detektor, dxgettext-
Audit, TEdit.Text-SQL-Injection, hardcoded DB-Credentials in DFM,
Pascal Lint CI/CD, GitHub-Actions Delphi SARIF, Pre-Commit-Hook Delphi.

---

## Lizenz

Dieses Projekt steht unter der **MIT-Lizenz** — vollständiger Text in
[LICENSE](LICENSE).

```
Copyright (c) 2026 Nicolas Gerlach
```

Kurz zusammengefasst:

- ✅ Frei nutzbar, kopierbar, modifizierbar, mergen, weiterverteilen und sublizenzieren
- ✅ Auch für kommerzielle Nutzung freigegeben
- ✅ Keine Gewährleistung — Software wird „as is" bereitgestellt
- ℹ️ Copyright-Vermerk und Lizenztext müssen in Kopien oder wesentlichen
  Teilen der Software erhalten bleiben

---

## Unterstützen

Spenden-Link steht oben am Anfang der README — danke!
