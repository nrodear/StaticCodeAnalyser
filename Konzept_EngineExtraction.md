# Konzept: Engine in eigenes Projekt extrahieren (UI bleibt)

Status: **Konzept**, noch nicht umgesetzt
Stand: 2026-06-01

Minimal-invasiver Schnitt: **nur** den headless Analyse-Kern in ein
eigenständiges `SCA.Engine`-Projekt herausziehen. UI-Welt (Standalone-Form
+ IDE-Plugin) bleibt strukturell wo sie ist und konsumiert die Engine
weiter als Source oder als BPL. **Kein** SharedUI-Refactor, **kein**
Tests-Split, **kein** Bootstrap-Umbau.

Vorlage / breitere Variante: [Konzept_ProjektAufteilung.md](Konzept_ProjektAufteilung.md).
Dieses Dokument schneidet daraus die kleinste sinnvolle Phase 1 heraus.

---

## 1. Ziel

- Engine-Code lebt in **`SCA.Engine/`** als separates Delphi-Projekt
  (`SCA.Engine.dpk` + `SCA.Engine.dproj`).
- Engine-DPK kompiliert ohne `Vcl.*` / `Forms.*` / `Controls.*` —
  Verstoß = Build-Fehler, nicht Konvention.
- Standalone-EXE und IDE-Plugin konsumieren die Engine weiter wie heute
  (Source-Pfade oder Runtime-Package — Entscheidung in §6).
- **Keine** Verhaltensänderung im Standalone-EXE oder IDE-Plugin.
- Tests-Projekt bleibt zunächst unverändert.

## 2. Ist-Zustand (Stand 2026-06-01)

```
StaticCodeAnalyserForm/sources/
├── Common/          12 Files   ← gemischt: 11 Engine, 1 UI (uIDEColors.pas)
├── Parsing/          7 Files   ← reine Engine
├── Detectors/      158 Files   ← reine Engine
├── Infrastructure/  23 Files   ← reine Engine
├── Output/           5 Files   ← reine Engine
├── Console/          1 File    ← uConsoleRunner.pas (Standalone-spezifisch, BLEIBT)
└── UI/             ~25 Files   ← UI (BLEIBT)

SCA.Engine/                    ← Folder existiert, leere Hülle
├── SCA.Engine.dpk             ← nur `requires rtl;`
├── SCA.Engine.dproj
└── (kein Source-Folder)
```

Engine-Kandidaten: **205 .pas-Dateien** (`Common` + `Parsing` + `Detectors`
+ `Infrastructure` + `Output`) minus `uIDEColors.pas`.

## 3. Soll-Zustand nach Engine-Extraction

```
SCA.Engine/                          ← Eigenes Projekt, Runtime-Package
├── SCA.Engine.dpk
├── SCA.Engine.dproj
└── sources/
    ├── Common/         11 Files    ← ohne uIDEColors.pas
    ├── Parsing/         7 Files
    ├── Detectors/     158 Files
    ├── Infrastructure/ 23 Files
    └── Output/          5 Files

StaticCodeAnalyserForm/sources/      ← UI-Hülle bleibt, Engine-Folder leer
├── Common/                          ← nur noch uIDEColors.pas (UI-Theme)
├── Console/uConsoleRunner.pas       ← bleibt (Standalone-CLI)
└── UI/                              ← unverändert

StaticCodeAnalyserIDE/               ← unverändert
└── uIDE*.pas

StaticCodeAnalyserForm/tests/        ← unverändert
└── uTest*.pas
```

## 4. Abhängigkeits-Regel (hart, per Compile)

| Engine-Unit darf requiren | Engine-Unit darf NICHT requiren |
|---|---|
| `System.*`, `Winapi.*` (nur Win-API, kein UI) | `Vcl.*` |
| `System.Generics.*`, `System.RegularExpressions`, … | `Forms.*` |
| `System.IOUtils`, `System.Classes` | `Controls.*` |
| `System.JSON`, `System.Net.*` (für SonarPull/Push) | `Graphics.*` (außer für SARIF-Snippet-Renderer — prüfen) |
| Andere Engine-Units | UI-/Theme-/Localization-Units |

**Build-Check**: Engine-BPL muss ohne `vclX0.bpl`/`vclimg.bpl` als
runtime-Package linken. Wenn das nicht geht → Verstoß lokalisieren.

## 5. UI-Verseuchungs-Audit

**Vor** dem Verschieben einmal `grep -r "Vcl\.\|Forms\.\|Controls\.\|Graphics\."`
über alle Engine-Kandidaten. Bekannte Verdachtsfälle aus dem Konzept-
Vorgänger:

| Datei | Verdacht | Aktion |
|---|---|---|
| `Common/uIDEColors.pas` | Theme-Farben | **BLEIBT in StaticCodeAnalyserForm/sources/Common/** (UI) |
| `Infrastructure/uPathOverrides.pas` | evtl. Dialog-Aufrufe | grep, falls UI → splitten oder Engine-Teil rein |
| `Infrastructure/uIgnoreList.pas` | evtl. UI-Dialog | grep, falls UI → splitten |
| `Output/uExportHtml.pas` | rein HTML-Generierung | sollte UI-frei sein, verifizieren |
| `Output/uFixHint.pas` | benutzt `_()`-Localization | hier KEIN UI-Form, aber `uLocalization` — UI-frei? prüfen |

Konkret: das Audit-Kommando vorab laufen lassen:

```powershell
Get-ChildItem -Recurse -Path StaticCodeAnalyserForm\sources\Common,StaticCodeAnalyserForm\sources\Parsing,StaticCodeAnalyserForm\sources\Detectors,StaticCodeAnalyserForm\sources\Infrastructure,StaticCodeAnalyserForm\sources\Output -Filter *.pas |
  Select-String -Pattern 'Vcl\.|Forms\.|Controls\.|Graphics\.' |
  Group-Object Path | Select Count, Name
```

Treffer pro Datei. Jeder Treffer ist VOR der Migration zu klären.

## 6. Linking-Strategie für Standalone + IDE

Zwei Optionen, beide funktionieren — pro-Konsument entscheiden:

### Variante A — Source-Pfade biegen (empfohlen, no-deployment-change)

Standalone-`.dproj` und IDE-`.dproj` bekommen `<DCC_UnitSearchPath>` mit
neuem Pfad `..\SCA.Engine\sources\Common;..\SCA.Engine\sources\Parsing;…`.
Engine-Source wird in jeden Konsumenten **statisch kompiliert**, dieselbe
Source dreimal.

**Pro**:
- Keine BPL-Deployment-Aufwand (heutige `StaticCodeAnalyser.d12.exe`
  bleibt single-File)
- Kein Risiko bei BPL-Versions-Mismatch
- Tests-Projekt funktioniert weiter ohne Änderung

**Contra**:
- Engine-Refactor kompiliert weiterhin alle 3 Konsumenten neu
- Compile-Time-Reduktion gleich Null

### Variante B — Runtime-Package (Engine-BPL als shared dependency)

Standalone-EXE und IDE-BPL setzen `Build with runtime packages = True` und
listen `SCA.Engine` in den Runtime-Packages. Engine-BPL wird neben der EXE
ausgeliefert.

**Pro**:
- Engine kompiliert einmal, IDE+Standalone linken nur dagegen
- Echte Build-Zeit-Reduktion
- Architektur-Grenze ist hart durchgesetzt (BPL kann nicht uses-cyclen)

**Contra**:
- Deployment: `SCA.Engine.bpl` + ggf. `rtl{Version}.bpl` neben der EXE
- IDE-Plugin und Standalone müssen mit derselben Engine-BPL-Version
  bauen (Versions-Konflikt-Risiko)
- DCU-Cache-Fallstricke (siehe Konzept_ProjektAufteilung.md §9.4):
  Source-Edit ohne Engine-Rebuild = stale EXE

**Empfehlung**: Variante A für den ersten Wurf. Variante B kann als
Folge-Refactor kommen wenn der Deployment-Aufwand klar ist.

## 7. Migrationsplan (1 Tag, in 6 Schritten)

### Schritt 1 — UI-Verseuchungs-Audit (15 min)

`grep`-Lauf aus §5 ausführen. Treffer dokumentieren. Wenn signifikant:
zuerst aufräumen (kann eigene Mini-Phase sein).

### Schritt 2 — `SCA.Engine/sources/` anlegen (5 min)

```powershell
mkdir SCA.Engine\sources
```

### Schritt 3 — Files mit `git mv` verschieben (15 min)

History-erhaltend. Pro Folder ein einzelner `git mv`:

```powershell
git mv StaticCodeAnalyserForm\sources\Common         SCA.Engine\sources\Common
git mv StaticCodeAnalyserForm\sources\Parsing        SCA.Engine\sources\Parsing
git mv StaticCodeAnalyserForm\sources\Detectors      SCA.Engine\sources\Detectors
git mv StaticCodeAnalyserForm\sources\Infrastructure SCA.Engine\sources\Infrastructure
git mv StaticCodeAnalyserForm\sources\Output         SCA.Engine\sources\Output
```

Anschließend **`uIDEColors.pas` zurückholen** (UI, bleibt in Form-Projekt):

```powershell
mkdir StaticCodeAnalyserForm\sources\Common
git mv SCA.Engine\sources\Common\uIDEColors.pas StaticCodeAnalyserForm\sources\Common\uIDEColors.pas
```

### Schritt 4 — `SCA.Engine.dpk` Contains-Liste füllen (30 min)

Heute leer (`requires rtl;`). Alle 204 Engine-Units explizit auflisten.
**Generator-Skript** dafür schreiben (einmaliger Aufwand, langfristig
wiederverwendbar):

```powershell
# tools\regen-engine-dpk.ps1
$files = Get-ChildItem -Recurse SCA.Engine\sources -Filter u*.pas |
         Sort-Object Name |
         ForEach-Object { "  $($_.BaseName) in '$($_.FullName.Substring((Get-Location).Path.Length+1))'," }
$lines = $files -join "`r`n"
$dpk = @"
package SCA.Engine;

requires rtl;

contains
$($lines.TrimEnd(','))
;

end.
"@
$dpk | Set-Content SCA.Engine\SCA.Engine.dpk -Encoding UTF8
```

Skript einchecken, in PRE-COMMIT-Hook oder CI als "validate dpk in sync
with source folder" laufen lassen.

### Schritt 5 — Konsument-`.dproj` Source-Pfade umbiegen (Variante A) (20 min)

In `StaticCodeAnalyser.d12.dproj` (Standalone) und
`StaticCodeAnalyser.IDE.d12.dproj` (IDE) jeweils:

- `<DCC_UnitSearchPath>` erweitern um:
  `..\SCA.Engine\sources\Common;..\SCA.Engine\sources\Parsing;..\SCA.Engine\sources\Detectors;..\SCA.Engine\sources\Infrastructure;..\SCA.Engine\sources\Output;…`
- Bestehende Pfad-Einträge auf die alten Folder entfernen
- `<DCCReference Include="…">` für Engine-Units AUSBLENDEN (sie werden
  über UnitSearchPath gefunden) — optional, sauberer ist explizit listen

Selbe Pfad-Anpassung im Test-Project `tests\TestProject.dproj`.

### Schritt 6 — Smoke-Test (30 min)

- IDE-Build Standalone → EXE startet, Analyse auf Beispielprojekt grün
- IDE-Build Tests → DUnit-Runner alle Tests grün
- IDE-Build IDE-Plugin → BPL lädt, Dock-Frame öffnet, Analyse läuft
- CLI-Test: `StaticCodeAnalyser.d12.exe --version` zeigt 0.9.7
- Self-Test: `StaticCodeAnalyser.d12.exe --path . --full --profile strict
  --report-sarif sca.sarif --quiet` → identische Findings-Anzahl
  wie vor der Migration (Regression-Check)

## 8. Was NICHT Teil dieses Konzepts ist

Bewusste Abgrenzungen — gehört in den breiteren Aufteilung-Vorgänger
oder spätere Phasen:

- **SharedUI-Extraction**: Theme/Palette/Tiles/Grid-Renderer bleiben in
  `StaticCodeAnalyserForm/sources/UI/`. IDE-Plugin liest sie weiter via
  Source-Pfad.
- **Tests-Projekt-Trennung**: `StaticCodeAnalyserForm/tests/` bleibt wo
  es ist. Pfad-Anpassung in `TestProject.dproj` reicht.
- **Runtime-Packages-Umstellung**: Engine wird gebaut als BPL (für
  IDE-Plugin notwendig sowieso), aber Standalone-EXE bleibt monolithisch
  statisch verlinkt (Variante A).
- **Singleton-Entkopplung** (`gAstFileCache`/`gSymbolRefIndex`): bleibt
  globaler State. Bei BPL-Verteilung kommt das später dazu.
- **`finalization`-Cleanup für Regex-Caches** (Round 9+11+13): wandert
  mit den Detector-Units, kein extra Schritt nötig.
- **CI-Pipeline-Anpassung**: SonarScanner scannt heute `**/*.pas` egal
  wo sie liegen — keine Anpassung nötig.

## 9. Risiken (minimal-Variante)

| Risiko | Wahrscheinlichkeit | Gegenmaßnahme |
|---|---|---|
| `git mv` mit 200+ Files macht History unleserlich | niedrig | Pro Folder einen Commit, Reviewer-friendly Diff |
| `uses`-Cycle wird erst bei BPL-Build sichtbar | mittel | Vor Schritt 6 einmaliger Audit-Build der BPL allein |
| Konsument-`.dproj` vergisst einen Pfad | mittel | Smoke-Test fängt; Wenn nur Standalone bricht, lokales Repro schnell |
| `uIDEColors.pas` wird versehentlich von Engine-Unit gezogen | niedrig | Nach Move einmaliger `grep -r 'uIDEColors' SCA.Engine\sources\` (sollte 0 Treffer geben) |
| `DCC_UnitSearchPath` Reihenfolge — alte Folder geistern noch | niedrig | Alte Source-Folder leer lassen, NICHT löschen (führt zu nichts) |
| DUnit-Tests finden ihre Detector-Units nicht mehr | mittel | Schritt 5 deckt das mit ab |

## 10. Erfolgs-Kriterien

- [ ] `SCA.Engine\sources\` enthält 204 .pas-Dateien (alle ehemals
  `StaticCodeAnalyserForm/sources/{Common\Parsing\Detectors\Infrastructure\Output}`
  minus `uIDEColors.pas`)
- [ ] `SCA.Engine.dpk` listet alle 204 Units im `contains`-Block
- [ ] `SCA.Engine.bpl` baut grün ohne `Vcl.*`/`Forms.*`-Referenz
  (Build-Output verifizieren)
- [ ] `StaticCodeAnalyser.d12.exe` baut grün, `--version` → 0.9.7,
  Selftest produziert identische Findings-Anzahl wie pre-Migration
- [ ] `StaticCodeAnalyser.IDE.d12.bpl` baut grün, Dock-Frame öffnet im IDE
- [ ] `TestProject.exe` baut grün, alle ~1700 DUnit-Tests laufen durch
- [ ] `tools\regen-engine-dpk.ps1` existiert, läuft idempotent
- [ ] Diff in `git log --stat` zeigt fast nur Renames, minimal echte
  Edits (nur die 3 dproj-Dateien + die dpk)

## 11. Aufwand

| Phase | Zeit |
|---|---|
| Schritt 1 (UI-Audit) | 15 min |
| Schritt 2 (Folder) | 5 min |
| Schritt 3 (git mv) | 15 min |
| Schritt 4 (DPK + Generator-Skript) | 30 min |
| Schritt 5 (3 dproj-Dateien anpassen) | 20 min |
| Schritt 6 (Smoke-Test) | 30 min |
| Buffer für UI-Verseuchungs-Cleanup | 60 min |
| **Total** | **~3h** (1 Arbeitssitzung) |

Falls Schritt 1 mehr als 10 UI-Treffer in Engine-Code findet: separate
Aufräum-Phase davor, +1-2h.

## 12. Folgemöglichkeiten

Nach dieser Engine-Extraction ist die Vorarbeit für die größere
4-Projekte-Aufteilung (siehe [Konzept_ProjektAufteilung.md](Konzept_ProjektAufteilung.md))
geleistet. Nächste sinnvolle Schritte (separate Konzepte/Tickets):

1. **SharedUI** aus `StaticCodeAnalyserForm/sources/UI/` extrahieren
   (Theme/Palette/Tiles, ~10 Units)
2. **Tests-Projekt** verselbständigen mit BPL-Linking
3. **Runtime-Packages für Standalone** (Variante B aus §6)
4. **Singleton-Entkopplung** der globalen Indizes via Context-Record

Jeder davon ist ein eigener Tag Aufwand, alle voneinander unabhängig.
