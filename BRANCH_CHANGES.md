# Static Code Analyser

Sonar-inspirierter statischer Code-Analyser fuer Delphi/Object-Pascal-Code.
Findet Memory-Leaks, Code-Smells, Sicherheitsluecken und Wartbarkeits-Probleme.

Das Repository enthaelt zwei Komponenten:

| Komponente | Zweck | Pfad |
|------------|-------|------|
| **Standalone-EXE** | Stand-alone-Tool zum Analysieren von Verzeichnissen | `StaticCodeAnalyserForm/` |
| **IDE-Plugin** | Dockbares Tool-Fenster in der Delphi-IDE | `StaticCodeAnalyserIDE/` |

---

## Features auf einen Blick

- **21 implementierte Detektoren** aus dem Sonar-Pruefkatalog (siehe [`DETECTORS.md`](DETECTORS.md))
- **Sonar-Style Stat-Tiles** ueber dem Grid: Fehler / Warnungen / Hinweise / Bugs / Code-Duplikate / Code-Quality-Score
- **Severity-Filter** + **Typ-Filter** (Bug, Code Smell, Vulnerability, Security Hotspot, Code Duplication)
- **Help-Panel rechts** mit "Vorher/Nachher"-Code-Beispielen je Befund
- **Claude-AI-Prompt-Generator** — Klick auf eine Zeile legt einen kompletten Markdown-Block in die Zwischenablage
- **VCS-Branch-Mode** — analysiert nur in der Branch geaenderte Dateien (siehe unten)
- **Suppression** ueber `// SCA: ignore` Kommentare
- **Export** als CSV / JSON / Jira / HTML
- **Theme-Aware** — folgt dem aktiven Delphi-IDE-Theme (Light/Dark/Mountain Mist/Carbon)
- **Recent-Pfade** persistiert pro Session
- **Ignore-Liste** unter `%APPDATA%\StaticCodeAnalyser\ignore.txt`

---

## Komponenten im Detail

### 1. Standalone-EXE — `analyser.d12.dpr`

Eigenstaendiges Programm, kompiliert via `analyser.d12.dproj`. Bietet:
- Verzeichnis-Scan
- Einzeldatei-Analyse
- CSV-Export
- Direkt-Navigation zur Befundzeile (oeffnet IDE und springt zur Zeile)

Bauen:
```
Open analyser.d12.dproj in Delphi 12 -> Project -> Build
```

### 2. IDE-Plugin — `StaticCodeAnalyserIDE.dpk`

Designtime-Paket mit dockbarem Tool-Fenster. Wird ueber das Menue
**Tools / Static Code Analyser** oder **Ansicht / Static Code Analyser**
aufgerufen.

Zusaetzliche Funktionen gegenueber Standalone:
- **Aktuelle Datei** — analysiert die aktive Source-Datei in der IDE
- **Branch-Changes** — analysiert nur die im Branch geaenderten Dateien
- **Direkt-Navigation** ueber IDE-Editor-Services (kein WinAPI-Hack)
- Statistik-Tile-Reihe mit Echtzeitzahlen
- Help-Panel mit Vorher/Nachher-Snippets

Installieren:
```
Open StaticCodeAnalyserIDE.dproj -> Project -> Install
```

---

## Detektoren

Vollstaendige Liste mit Status (✅ implementiert / 🟡 teilweise / 🔲 offen)
in [`DETECTORS.md`](DETECTORS.md).

Aktueller Stand: **18 vollstaendig + 1 teilweise + 3 Bonus-Detektoren = 21 Detektoren**.

Schwerpunkte:

| Severity | Beispiele |
|----------|-----------|
| 🔴 **Blocker** | MemoryLeak, EmptyExcept, NilDeref, SQLInjection, HardcodedSecret |
| 🟠 **Critical** | DivByZero, MissingFinally, FormatMismatch, FieldLeak |
| 🟡 **Major** | LongMethod, LongParamList, DeepNesting, MagicNumber, DuplicateString |
| 🔵 **Minor** | UnusedUses, TodoComment, EmptyMethod, DeadCode |
| 🎁 **Bonus** | HardcodedPath, DebugOutput, DuplicateString |

---

## Branch-Changes-Modus

Statt das ganze Projekt zu scannen, kannst du nur die Dateien analysieren
lassen, die im aktuellen Branch geaendert wurden — drastisch schneller
(Sekunden statt Minuten), ideal als Pre-Commit-Check.

### Schnellstart

1. Im IDE-Plugin auf den Button **`Branch-Changes`** klicken
2. Der Analyser sucht ausgehend vom `Projektpfad` nach oben nach `.git` oder `.svn`
3. Holt die Liste der geaenderten `.pas`-Dateien
4. Analysiert nur diese und zeigt die Befunde im Grid

### Was gefunden wird

**Git-Repositories** vereinen zwei Quellen:

```
git diff --name-only --diff-filter=ACMR <base>...HEAD   # committed Branch-Diff
git status --porcelain                                  # uncommitted + untracked
```

`<base>` wird automatisch ermittelt: `origin/HEAD` → `main` → `master`.
Aktionen `A`/`C`/`M`/`R` werden einbezogen, `D` (deleted) uebersprungen.

**SVN-Repositories** analysieren nur die Working Copy:

```
svn status
```

Status `M`/`A`/`R`/`?` werden einbezogen, `D`/`!`/`I`/`C` uebersprungen.

### Voraussetzungen

CLI-Tool muss aufrufbar sein. Suchreihenfolge:

| VCS | Suchreihenfolge |
|-----|-----------------|
| **Git** | `PATH` → `C:\Program Files\Git\bin\git.exe` → `C:\Program Files (x86)\Git\bin\git.exe` → `C:\Program Files\TortoiseGit\bin\git.exe` → `TortoiseGit\mingw64\bin\git.exe` |
| **SVN** | `PATH` → `C:\Program Files\TortoiseSVN\bin\svn.exe` → `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe` → `C:\Program Files\Subversion\bin\svn.exe` |

Empfohlen:
- **Git for Windows** ([git-scm.com](https://git-scm.com/download/win))
- **TortoiseSVN** mit aktivierter Option *"command line client tools"* — sonst fehlt `svn.exe`

### Tortoise-Kompatibilitaet

| Setup | Funktioniert? |
|-------|---------------|
| **Git for Windows** allein oder mit TortoiseGit | ✅ ja, via `PATH` |
| **TortoiseGit allein** ohne Git for Windows | ❌ TortoiseGit liefert kein eigenes `git.exe` |
| **TortoiseSVN MIT** "command line client tools" | ✅ ja, automatisch im TortoiseSVN-Bin-Pfad gefunden |
| **TortoiseSVN OHNE** "command line client tools" | ❌ klare Fehlermeldung — Installer mit Option nachholen |

### Performance

| Mode | Zeit (typisches Projekt) |
|------|--------------------------|
| Vollstaendiger Verzeichnis-Scan | 60–90 s |
| Branch-Changes (5–30 .pas-Dateien) | 200 ms – 3 s |

---

## Theme-Handling

Das IDE-Plugin folgt dem aktiven Delphi-IDE-Theme via:

- **`StyleServices.GetSystemColor`** in Custom-Drawing (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace`/`clWindow`/`clBtnText`** als Property-Werte (auto-themed)
- **`IOTAIDEThemingServices.ApplyTheme`** beim Frame-Hosting
- **`INTAIDEThemingServicesNotifier`** fuer Live-Theme-Wechsel
- **`CM_STYLECHANGED`** + **`SetParent`-Override** als zusaetzliche Trigger

Architektur-Module:

| Unit | Inhalt |
|------|--------|
| [`uAnalyserPalette.pas`](StaticCodeAnalyserForm/sources/uAnalyserPalette.pas) | Zentrale Farb-Konstanten (Severity-Hintergruende, Akzente, Icon-Farben) |
| [`uAnalyserTypes.pas`](StaticCodeAnalyserForm/sources/uAnalyserTypes.pas) | `TFindingSeverity`-Enum + Konversion |
| [`uAnalyserTheme.pas`](StaticCodeAnalyserForm/sources/uAnalyserTheme.pas) | `SeverityBg`, `SeverityAccent`, `BlendColor` |

**Bekannte Limitation**: Im Floating-Modus uebernimmt das Plugin-Fenster
IDE-Theme-Wechsel zur Laufzeit nicht zuverlaessig. Workaround: Plugin im
Dock-Modus betreiben oder Fenster nach Theme-Wechsel schliessen + erneut
oeffnen.

---

## Settings — `repo.ini`

Per Klick auf den Button **`Repo...`** oeffnet sich:

```
%APPDATA%\StaticCodeAnalyser\repo.ini
```

Die Datei wird beim ersten Aufruf mit Default-Inhalt angelegt. Aenderungen
werden beim naechsten Klick auf **`Branch-Changes`** automatisch neu geladen.

```ini
[Repo]
; Vergleichs-Branch fuer "git diff <base>...HEAD".
; Leer = Auto-Detect (origin/HEAD -> main -> master).
; Beispiele: develop, release/2024.1, origin/main
BaseBranch=

; Uncommitted Working-Tree-Aenderungen einbeziehen?
; 1 = ja (Default - typisch fuer Pre-Commit-Check)
; 0 = nur committed Aenderungen
IncludeWorkingTree=1

[Paths]
; Vollstaendige Pfade falls git/svn nicht im PATH und nicht im
; Standard-Tortoise-Pfad liegen. Sonst leer lassen.
GitExe=
SvnExe=
```

### Typische Anpassungen

| Szenario | Setting |
|----------|---------|
| Team mit `develop` als Default-Branch | `BaseBranch=develop` |
| Nur Code-Review committeter Aenderungen | `IncludeWorkingTree=0` |
| TortoiseGit im Custom-Pfad | `GitExe=D:\Tools\Git\bin\git.exe` |
| TortoiseSVN ohne CLI-Tools im PATH | `SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe` |

---

## Suppression

Befunde lassen sich pro Zeile unterdruecken:

```pascal
x := 1 / y;  // SCA: ignore (DivByZero geprueft - y kommt aus Validation)
```

Auch ganze Dateien koennen ueber `%APPDATA%\StaticCodeAnalyser\ignore.txt`
ausgeschlossen werden — eine Datei (oder ein Pfad-Glob) pro Zeile.

---

## Troubleshooting

### "kein Git-/SVN-Repository in oder oberhalb von ..."

Der Analyser sucht ausgehend vom **`Projektpfad`** nach oben. Stelle sicher
dass der Pfad innerhalb eines Repos liegt und du nicht versehentlich einen
Sub-Pfad ausserhalb des Repo-Roots gewaehlt hast.

### "kein Base-Branch (main/master) gefunden - nur Working Tree"

Dein Repo hat keinen Default-Branch unter dem ueblichen Namen. Setze in
`repo.ini` den `BaseBranch=` Eintrag explizit (z. B. `develop`).

### Befunde fehlen die du erwartest

- **Datei-Endung**: nur `.pas`-Dateien werden analysiert. `.dpr`/`.dpk`
  werden noch nicht erfasst (Erweiterung moeglich)
- **Submodule**: `git status` erfasst Submodul-interne Aenderungen nicht
  — separat im Submodul-Ordner scannen
- **Test-Filter**: Tests werden standardmaessig ausgeschlossen. Aktiviere
  Checkbox **`Tests einschliessen`** wenn gewuenscht
- **Ignore-Liste**: pruefe `%APPDATA%\StaticCodeAnalyser\ignore.txt`

### Pfade mit Umlauten / Sonderzeichen

Der Analyser nutzt Default-Codepage zur stdout-Konvertierung. Bei Pfaden
mit Sonderzeichen kann es zu Encoding-Glitches kommen. Workaround in
`.gitconfig`:

```
[core]
    quotepath = false
```

Liefert UTF-8 statt escaped Sequenzen.

---

## Bauen / Installieren

| Ziel | Schritt |
|------|---------|
| Standalone-EXE | `analyser.d12.dproj` oeffnen → Project → Build |
| IDE-Plugin | `StaticCodeAnalyserIDE.dproj` oeffnen → Project → Install |

Plattform: **Win32** (Designtime-Pakete laufen aktuell nur in 32-Bit-IDE-Variante).

---

## Repository-Struktur

```
StaticCodeAnalyser/
├── StaticCodeAnalyserForm/         # Standalone-EXE + Detector-Code
│   ├── sources/                    # Detektoren, Parser, Theme-Helper
│   ├── resources/                  # Test-Pascal-Dateien fuer Detector-Test
│   ├── tests/                      # Unit-Tests
│   └── analyser.d12.dproj          # Standalone-Projekt
├── StaticCodeAnalyserIDE/          # IDE-Plugin (dockable)
│   ├── uIDEExpert.pas              # Tools-Menue-Wizard
│   ├── uIDEAnalyserForm.pas        # Frame + Dockable-Form-Wrapper
│   └── StaticCodeAnalyserIDE.dpk   # Designtime-Paket
├── docs/                           # Mockups, Skizzen
└── DETECTORS.md                    # Vollstaendiger Detektor-Katalog mit Status
```
