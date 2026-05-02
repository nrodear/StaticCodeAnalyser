# Branch-Changes analysieren

Statt das ganze Projekt zu scannen, kannst du nur die Dateien analysieren
lassen, die im aktuellen Branch geaendert wurden. Das ist drastisch
schneller (Sekunden statt Minuten) und ideal als Pre-Commit-Check.

## Schnellstart

1. Im IDE-Plugin (oder in der Standalone-Form falls erweitert) auf den Button
   **`Branch-Changes`** klicken
2. Der Analyser sucht ausgehend vom aktuellen `Projektpfad` nach oben
   nach einem `.git` oder `.svn` Verzeichnis
3. Holt die Liste der geaenderten `.pas`-Dateien
4. Analysiert nur diese und zeigt die Befunde im Grid

## Was der Button findet

### Git-Repositories

Vereinigt **zwei** Quellen:

1. **Branch-Diff (committed)** — Aenderungen seit dem Verzweigen vom
   Default-Branch:
   ```
   git diff --name-only --diff-filter=ACMR <base>...HEAD
   ```
   `<base>` wird automatisch ermittelt:
   - `git symbolic-ref --short refs/remotes/origin/HEAD` (typisch `origin/main`)
   - Fallback: `main`
   - Letzter Fallback: `master`
   - Falls keiner existiert: nur Working Tree

2. **Working Tree (uncommitted + untracked)**:
   ```
   git status --porcelain
   ```

Aktionen die einbezogen werden: `A` (added), `C` (copied), `M` (modified),
`R` (renamed). Dateien mit Status `D` (deleted) werden uebersprungen, weil
sie nicht mehr existieren. Bei Renames wird nur der **Ziel-Pfad** analysiert.

### SVN-Repositories

`svn` hat kein Branch-Diff-Konzept wie Git (Branches sind Repository-Kopien),
daher wird **nur die Working Copy** analysiert:

```
svn status
```

Status-Codes die einbezogen werden: `M` (modified), `A` (added),
`R` (replaced), `?` (unversioned/neu). Uebersprungen werden:
`D` (deleted), `!` (missing), `I` (ignored), `C` (conflict).

## Voraussetzungen

Das jeweilige CLI-Tool muss aufrufbar sein. Der Analyser sucht
in dieser Reihenfolge:

| VCS | Suchreihenfolge |
|-----|-----------------|
| **Git** | `PATH` → `C:\Program Files\Git\bin\git.exe` → `C:\Program Files (x86)\Git\bin\git.exe` → `C:\Program Files\TortoiseGit\bin\git.exe` → `TortoiseGit\mingw64\bin\git.exe` |
| **SVN** | `PATH` → `C:\Program Files\TortoiseSVN\bin\svn.exe` → `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe` → `C:\Program Files\Subversion\bin\svn.exe` |

### Empfohlene Installationen

- **Git**: [Git for Windows](https://git-scm.com/download/win) — installiert
  `git.exe` im PATH (Standard)
- **SVN**:
  - Beim **TortoiseSVN-Installer** die Option *"command line client tools"*
    ankreuzen — sonst wird nur das GUI-Tool installiert, ohne `svn.exe`
  - Alternativ: [Apache Subversion CLI](https://subversion.apache.org/packages.html)

## Tortoise-Kompatibilitaet

| Setup | Funktioniert? |
|-------|---------------|
| **Git for Windows** allein oder mit TortoiseGit | ✅ ja, via `PATH` |
| **TortoiseGit allein** ohne Git for Windows | ❌ TortoiseGit liefert kein eigenes `git.exe`, eine separate Git-Installation ist Pflicht |
| **TortoiseSVN MIT** "command line client tools" Option | ✅ ja, der Analyser findet `svn.exe` automatisch im TortoiseSVN-Bin-Pfad |
| **TortoiseSVN OHNE** "command line client tools" | ❌ klare Fehlermeldung — Installer mit Option nachholen |

## Performance

Bei einem typischen Feature-Branch:

- Verzeichnis-Scan entfaellt komplett
- 5-30 geaenderte `.pas`-Dateien × ~30-100 ms = **~200 ms bis ~3 s** total
- Statt 60-90 s fuer vollstaendigen Repo-Scan

## Beispielausgabe (Statusbar)

| Situation | Statusbar-Text |
|-----------|---------------|
| 5 geaenderte Dateien im Git-Branch | `Git: Branch vs origin/main: 5 Datei(en) - Analyse laeuft...` |
| Working Copy mit 2 Aenderungen (SVN) | `SVN: Working Copy: 2 Datei(en) - Analyse laeuft...` |
| Nichts geaendert | `Git: Branch vs origin/main - keine geaenderten .pas-Dateien` |
| `git`/`svn` nicht installiert | `git nicht gefunden. Installiere Git for Windows ...` |

## Settings (repo.ini)

Per Klick auf den Button **`Repo...`** oeffnest du die Settings-Datei:

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
| Team arbeitet mit `develop` als Default-Branch | `BaseBranch=develop` |
| Nur Code-Review committeter Aenderungen | `IncludeWorkingTree=0` |
| TortoiseGit im Custom-Pfad | `GitExe=D:\Tools\Git\bin\git.exe` |
| TortoiseSVN ohne CLI-Tools im PATH | `SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe` |

## Troubleshooting

### "kein Git-/SVN-Repository in oder oberhalb von ..."

Der Analyser sucht ausgehend vom **`Projektpfad`** im Form-Feld nach oben.
Stelle sicher dass:
- Der Pfad innerhalb eines Repos liegt
- Du nicht versehentlich einen Sub-Pfad ohne `.git`/`.svn` ausserhalb
  des Repo-Roots gewaehlt hast

### "kein Base-Branch (main/master) gefunden - nur Working Tree"

Dein Repo hat keinen Default-Branch unter dem ueblichen Namen. Der
Analyser faellt automatisch auf nur Working-Tree-Aenderungen zurueck.
Falls du regelmaessig vs einen anderen Branch (z.B. `develop`)
analysieren willst, koennte das spaeter konfigurierbar gemacht werden.

### Befunde fehlen die du erwartest

- Hat die Datei wirklich `.pas`-Endung? `.dpr`/`.dpk` werden aktuell **nicht**
  durch den Branch-Filter erfasst (kann erweitert werden)
- Wurde die Datei nur in einem Untermodul geaendert? Submodule-Aenderungen
  werden via `git status` nicht erfasst — dort musst du in den Submodul-Ordner
  wechseln und neu scannen
- Gilt der Test-Filter? Tests werden standardmaessig ausgeschlossen.
  Aktiviere die Checkbox **`Tests einschliessen`** wenn du Test-Dateien
  mitanalysieren willst

### Pfade mit Umlauten / Sonderzeichen

Der Analyser nutzt Default-Codepage zur stdout-Konvertierung. Bei Pfaden
mit Sonderzeichen kann es zu kleinen Encoding-Glitches kommen (Datei
wird dann nicht gefunden weil der konvertierte Pfad nicht existiert).
Workaround: in `.gitconfig` setzen:
```
[core]
    quotepath = false
```
Dann liefert `git status --porcelain` UTF-8 statt escaped Sequenzen.
