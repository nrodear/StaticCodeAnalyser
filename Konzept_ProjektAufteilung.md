# Konzept: Aufteilung in eigenständige Projekte

Status: **Konzept**, noch nicht umgesetzt
Stand: 2026-06-01 (Update Session 13)

## 1. Ist-Zustand

Heute leben **alle Quelldateien** unter `StaticCodeAnalyserForm/sources/` als
loser Source-Baum. Drei Konsumenten ziehen die selben `.pas`-Dateien per
`DCC_UnitSearchPath` direkt ein und kompilieren sie jeweils neu:

| Konsument | Pfad | Typ |
|---|---|---|
| Standalone-EXE (+ CLI) | `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` | `Application` |
| IDE-Plugin | `StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dproj` | `Package (BPL)` |
| Tests | `StaticCodeAnalyserForm/tests/TestProject.dproj` | `Application (DUnit)` |

Engine-Folder `SCA.Engine/` existiert bereits leer (nur `SCA.Engine.dpk`
mit `requires rtl;`). Source ist heute organisiert nach Schicht:

```
StaticCodeAnalyserForm/sources/
├── Common/          ─ Konstanten, Utilities (RuleCatalog, RecentPaths, ...)
├── Parsing/         ─ Lexer, Parser, AST, DFM-Reader
├── Detectors/       ─ 150+ Regel-Units (uXxx.pas pro Regel)
├── Infrastructure/  ─ StaticAnalyzer, Sonar-Push/-Pull, VCS, Ignore, Baseline
├── Output/          ─ SARIF, Sonar-Generic, Claude-Prompt, Fix-Hint, HTML
├── Console/         ─ uConsoleRunner.pas (CLI)
└── UI/              ─ MainForm, Theme, Palette, Tiles, Grid, Help, Localization
```

### Probleme der Monolith-Struktur

- **Engine-Code zieht UI-Units** versehentlich mit (über `uses`-Querverweise),
  weil alle Pfade im selben Suchpfad liegen — keine harte Grenze.
- **Test-Build** muss alle Detector-Units doppelt kompilieren, weil sie aus
  Source statt aus Package gezogen werden — lange Build-Zeiten.
- **IDE-Plugin** zieht **alle** Detector-Units obwohl es eigentlich nur die
  Engine-API braucht — größere BPL als nötig.
- **Refactoring im Engine-Kern** kompiliert sofort alle 3 Konsumenten neu
  statt nur die Engine-BPL.

## 2. Soll-Architektur — 4 Projekte

```
┌─────────────────────────────────────────────────────────────┐
│  SCA.IDE.bpl  (Design-Time-Package, IDE-Plugin)            │
│  - uIDE*.pas, uIDEAnalyserForm, Expert, Theme-Hooks         │
│  ───── requires ─────►  SCA.SharedUI.bpl  ──┐               │
│  ───── requires ─────►  SCA.Engine.bpl        │              │
└──────────────────────────────────────────────┼──────────────┘
                                               │
┌──────────────────────────────────────────────┼──────────────┐
│  SCA.Standalone.exe (Form-UI + CLI-Mode)    │              │
│  - uMainForm, uConsoleRunner, .dpr-Bootstrap │              │
│  ───── uses (statisch gelinkt) ─────►       │              │
│  oder runtime-Package ─────►  SCA.SharedUI.bpl ─┤           │
│  ───── runtime-Package ─────►  SCA.Engine.bpl   │           │
└──────────────────────────────────────────────┼─┼────────────┘
                                               ▼ ▼
┌─────────────────────────────────────────────────────────────┐
│  SCA.SharedUI.bpl  (Runtime-Package, UI-Bausteine)         │
│  - Theme/Palette/Colors, Tiles, Help-Panel,                 │
│    Grid-Renderer, Localization, Export-Menu                 │
│  ───── requires ─────►  SCA.Engine.bpl                       │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  SCA.Engine.bpl  (Runtime-Package, HEADLESS)                 │
│  - Common, Parsing, Detectors, Infrastructure, Output       │
│  - KEINE Vcl.*-Abhängigkeiten                               │
└────────────────────────▲────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│  SCA.Tests.exe (DUnit/DUnitX)                               │
│  - uTest*.pas pro Detector                                  │
│  ───── runtime-Package ─────►  SCA.Engine.bpl                │
└─────────────────────────────────────────────────────────────┘
```

**4 Projekte** (wie vom User gewünscht) plus **1 optionales 5.** (SharedUI).
Falls SharedUI kein eigenes Projekt sein soll, wandert es entweder in
Standalone-EXE und die IDE-BPL zieht die Source-Pfade (heutiges Verhalten,
nur sauber dokumentiert).

### Abhängigkeits-Regeln (hart, per Compile-Check)

| Von → Nach | SCA.Engine | SharedUI | Standalone | IDE | Tests |
|---|---|---|---|---|---|
| **SCA.Engine** | — | ✗ | ✗ | ✗ | ✗ |
| **SharedUI** | ✓ | — | ✗ | ✗ | ✗ |
| **Standalone** | ✓ | ✓ | — | ✗ | ✗ |
| **IDE** | ✓ | ✓ | ✗ | — | ✗ |
| **Tests** | ✓ | ✗ | ✗ | ✗ | — |

Engine darf nichts requiren ausser RTL. SharedUI darf VCL + Engine.
Standalone und IDE dürfen alles ausser einander. Tests dürfen nur Engine.

## 3. Modul-zu-Projekt-Mapping

### → SCA.Engine (`SCA.Engine/`)

Alle aktuell unter `StaticCodeAnalyserForm/sources/{Common,Parsing,Detectors,Infrastructure,Output}/`.

Sub-Foldering im Engine-Projekt:
```
SCA.Engine/
├── SCA.Engine.dpk
├── SCA.Engine.dproj
└── sources/
    ├── Common/           ─ uSCAConsts, uRuleCatalog, uMethodd12, ...
    ├── Parsing/          ─ uLexer, uParser2, uAstNode, uDfmLexer, ...
    ├── Detectors/        ─ 150 uXxx.pas
    ├── Infrastructure/   ─ uStaticAnalyzer2, uSonarPull/-Push, uVcsChanges,
    │                      uBaseline, uIgnoreList, uRepoSettings, ...
    └── Output/           ─ uExportSARIF, uExportSonarGeneric,
                            uClaudePrompt, uFixHint
```

Zwei Engine-Units **mit Theme-Abhängigkeit** müssen verschoben werden bevor
sie in die Engine können:
- `uIDEColors.pas` — gehört in SharedUI, nicht Engine
- `uAnalyserPalette/-Theme.pas` — gehört in SharedUI

### → SharedUI (optional, `SCA.SharedUI/`)

```
SCA.SharedUI/
├── SCA.SharedUI.dpk
├── SCA.SharedUI.dproj
└── sources/
    ├── uIDEColors.pas              ─ Themed-Color-Constants
    ├── uAnalyserPalette.pas        ─ Severity-Akzentfarben
    ├── uAnalyserTheme.pas          ─ Theme-Subscription
    ├── uIDEStatsTiles.pas          ─ Tile-Builder + Responsive-Controller
    ├── uIDEHelpPanel.pas           ─ Findings-Hint-Panel
    ├── uFindingGridRenderer.pas    ─ StringGrid-DrawCell
    ├── uFindingFilter.pas          ─ Filter-Predikat
    ├── uExportMenu.pas             ─ Export-Dropdown
    ├── uLocalization.pas           ─ Translation-Map
    └── uAnalyserTypes.pas          ─ Shared-UI-Records (TFindingDisplay etc.)
```

### → SCA.Standalone (`StaticCodeAnalyserForm/`)

Nur die EXE-spezifischen Teile bleiben:
```
StaticCodeAnalyserForm/
├── StaticCodeAnalyser.d12.dproj    (Application, EXE)
├── StaticCodeAnalyser.d12.dpr
└── sources/
    ├── uMainForm.pas / .dfm        ─ Standalone-Form
    ├── uConsoleRunner.pas          ─ CLI-Mode (-cli Flag)
    ├── MainController.pas          ─ aktuell leer, kann weg
    └── resources/                  ─ DPI-Manifest, App-Icon
```

CLI-Mode bleibt im selben EXE — Bootstrap unterscheidet via
`ParamCount > 0` ob Form oder ConsoleRunner gestartet wird (heutige Logik
beibehalten).

### → SCA.IDE (`StaticCodeAnalyserIDE/`)

Bleibt im Wesentlichen wo es ist, aber **ohne** die Source-Pfade auf
`StaticCodeAnalyserForm/sources/`:
```
StaticCodeAnalyserIDE/
├── StaticCodeAnalyser.IDE.d12.dproj  (Package, Design-Time)
├── StaticCodeAnalyser.IDE.d12.dpk
└── uIDE*.pas                          ─ alle IDE-spezifischen Units
```

DPK requires: `SCA.Engine`, `SCA.SharedUI`, `designide`, `vclide`.

### → SCA.Tests (`StaticCodeAnalyserTests/`)

```
StaticCodeAnalyserTests/
├── SCA.Tests.dproj                 (Application, DUnitX)
├── SCA.Tests.dpr
└── uTest*.pas                       ─ pro Detector eine Test-Unit
```

Tests requiren `SCA.Engine`-BPL → kein doppeltes Kompilieren der Detectors,
schnellere Test-Runs.

## 4. Heisse Eisen

### 4.1 Wo läuft die Analysis?

Heute: `Infrastructure/uStaticAnalyzer2.pas` (Engine) **+** `uIDEAnalyseRunner.pas`
(IDE-Wrapper mit Progress-Callbacks). Engine soll Callback-basierte API
liefern, IDE-Wrapper bleibt in IDE-Projekt.

### 4.2 Welche Units sind UI-frei genug für Engine?

Audit-Schritt vor Verschieben: per `grep -r "Vcl\.\|Forms\.\|Controls\." StaticCodeAnalyserForm/sources/{Common,Parsing,Detectors,Infrastructure,Output}/`.
Treffer müssen entweder umgezogen oder gereinigt werden.

Bekannte Kandidaten die heute Engine-Folder sind aber UI-Code enthalten:
- `Infrastructure/uPathOverrides.pas` — könnte TStringList-Dialog ziehen
- `Infrastructure/uIgnoreList.pas` — falls UI-Dialog drin → splitten
- `Output/uExportHtml.pas` — generiert HTML, sollte UI-frei sein, prüfen

### 4.3 Wie laden CLI und IDE-Plugin die Detectoren?

Heute: alle Detector-Units sind in der `uses`-Klausel der jeweiligen
EXE/BPL — sie registrieren sich in `initialization` beim `RuleCatalog`.
Bei Auslagerung in `SCA.Engine.bpl`:
- Standalone-EXE läuft mit **runtime-Packages** → BPL wird vom OS geladen,
  alle Detector-`initialization`s feuern → RuleCatalog vollständig.
- IDE-Plugin: gleiches Schema, aber BPL bereits geladen durch IDE.

Konsequenz: Standalone-EXE muss von **statischem Linking** auf
**Runtime-Packages** umgestellt werden (`{$WEAKPACKAGEUNIT}` ggf., aber
primär `Project > Options > Packages > Runtime Packages > [x] Build with
runtime packages`). Das ist eine bewusste Architektur-Entscheidung:
- Pro: einmal kompilierte Engine, alle 3 Konsumenten laden dieselbe BPL
- Contra: Deployment braucht jetzt `SCA.Engine.bpl` neben der EXE

Alternative für die Standalone-EXE: **statisches Linking gegen Source**
(wie heute, nur Source-Pfade auf den neuen `SCA.Engine/sources/`-Folder
umbiegen). Build-Zeit höher, Deployment simpler.

### 4.4 Ressourcen (.po, .dfm, .res)

- `i18n/*.po` — bleibt im Repo-Root, von SharedUI/uLocalization geladen
- `uMainForm.dfm` — bleibt bei Standalone
- `uIDEAnalyserForm.dfm` — bleibt bei IDE-Plugin (ist Frame, nicht Form)
- `*.res` — pro Projekt eigenes (Icon, Version-Info)

### 4.5 Output-Folder

Heute: alle 3 Projekte schreiben nach `Output/` (zentral). Bei 4-Projekt-
Setup pro Projekt eigenen `Output/`-Folder (in `.gitignore` schon abgedeckt).
Die BPLs sollten in einen **gemeinsamen** Folder wandern damit die IDE
zur Run-Time alles findet — Konvention: `$(BDSCOMMONDIR)\Bpl` oder
`Output/Bpl/`.

## 5. Migrationsplan

### Phase 1 — Engine-Extraction (1-2 Tage)
1. UI-Audit der heutigen Engine-Folder (`grep Vcl.\* ...`), Treffer fixen
2. `Common/Parsing/Detectors/Infrastructure/Output` von `StaticCodeAnalyserForm/sources/`
   nach `SCA.Engine/sources/` verschieben (per `git mv`, History bleibt)
3. `SCA.Engine.dpk` Contains-Liste füllen (alle Units explizit listen)
4. `SCA.Engine.bpl` baut, kein Konsument
5. Tests-Project umstellen: Detectors aus BPL statt Source

### Phase 2 — SharedUI extrahieren (optional, 0.5 Tag)
1. `SCA.SharedUI`-Projekt anlegen, `uIDEColors/Palette/Theme/StatsTiles/...`
   verschieben
2. Standalone-EXE und IDE-BPL beide auf das neue Package requiren

### Phase 3 — Standalone umstellen (0.5 Tag)
1. Source-Pfade in `StaticCodeAnalyser.d12.dproj` entfernen, Engine-BPL als
   runtime-Package requiren (oder Source-Pfade auf `SCA.Engine/sources/` biegen)
2. CLI-Build verifizieren (Smoke-Test gegen Beispiel-Projekt)

### Phase 4 — IDE-Plugin entrümpeln (0.5 Tag)
1. `DCC_UnitSearchPath` in `StaticCodeAnalyser.IDE.d12.dproj` entfernen
2. DPK auf `requires SCA.Engine, SCA.SharedUI` umstellen
3. Plugin-Build in IDE testen (BPL laden, Dock-Frame öffnen, Analyse laufen)

### Phase 5 — Tests-Project (0.5 Tag)
1. `StaticCodeAnalyserTests/` als eigenes Projekt
2. `requires SCA.Engine` statt Source-Pfade
3. CI-Pipeline anpassen (heute scannt SonarScanner über alles, künftig 4 Projekte)

## 6. Risiken

- **Circular Dependencies**: heute oft `Detectors → Common → Detectors`
  über uses-Cycles. Beim Strict-Package-Split fallen die auf — vorher
  einmal `grep`-basiertes Cycle-Audit.
- **Initialization-Order**: BPL-Laden ist nicht deterministisch zwischen
  unabhängigen Packages. Detector-Registrierung in `initialization` muss
  ohne Reihenfolge-Annahmen funktionieren (heutiger Code tut das schon).
- **VCL-Style-Hooks**: SharedUI und IDE laden beide Style-Hooks. Doppelte
  Subscription möglich — wir haben dafür bereits Dedupe-Logik (cb3d109).
- **Runtime-Packages-Deployment**: Standalone-EXE braucht BPLs zur Side-by-
  Side-Auslieferung. Falls das nicht akzeptabel ist, Engine-Source-Pfade-
  Lösung bevorzugen (kein echtes Package-Linking).

## 7. Offene Entscheidungen

| Frage | Optionen | Empfehlung |
|---|---|---|
| SharedUI als 5. Projekt? | A) eigenes BPL · B) Source-Folder den beide UI-Projekte includen | A — sauberer, aber bedeutet 5 Projekte |
| Standalone gegen Engine-BPL oder Source linken? | A) Runtime-Package · B) Source-Pfade | B — keine BPL-Deployment-Komplexität |
| Tests auch IDE-Plugin testen? | A) nur Engine · B) auch IDE-Smoke | A — IDE-Tests brauchen lebendige IDE-Instanz, separates CI-Setup |
| `SCA.Engine.dpk` als runtime oder dual? | A) runtime · B) runtime+design | A — kein Designtime-Verhalten in Engine |

## 8. Erfolgs-Kriterien

- [ ] `SCA.Engine.bpl` kompiliert ohne `Vcl.`/`Forms.`/`Controls.`-Refs
- [ ] `SCA.Standalone.exe` startet Form + erkennt `-cli` für Console-Mode
- [ ] `SCA.IDE.bpl` lädt in IDE, Dock-Frame öffnet, Analyse-Run grün
- [ ] `SCA.Tests.exe` läuft, alle Detector-Tests grün, < 50% Build-Zeit
  gegenüber heute
- [ ] Engine-Refactor (z.B. neuer Detector) kompiliert nur Engine-BPL + Tests,
  nicht zwingend Standalone/IDE

---

## 9. Update Session 13 (2026-06-01)

Seit dem ersten Konzept (2026-05-25) sind ~30 Detector-Fixes + Architektur-
Erweiterungen dazugekommen. Für die Engine-Extraction sind besonders relevant:

### 9.1 Neue Engine-API-Felder die mitziehen müssen

| Komponente | Datei(en) | Zielprojekt | Bemerkung |
|---|---|---|---|
| Profile-Negation-Syntax | `uRuleCatalog.pas` | Engine | `["*","!Kind"]` jetzt unterstützt — Engine-internes Parsing, kein UI |
| `selftest-quiet` Bundled-Profile | `rules/sca-rules.json` | Engine | 11 Style-Detektoren ausgeblendet |
| `--report-html` CLI-Flag | `uConsoleRunner.pas` | Standalone (CLI-Mode) | TExporterHtml ist Engine-Output |
| `TExporterHtml.Run` | `Output/uExportHtml.pas` | Engine | War schon UI-frei, jetzt offiziell CLI-konsumiert |
| 4 neue `fm`-Filter | `uFindingFilter.pas` | SharedUI | CommandInjection/Insecure/UnusedRoutine/NoSonarMarker |

### 9.2 Module-Regex-Cache-Pattern (Round 9+11+13)

12 Detektoren tragen jetzt module-private `Cached_X: TRegEx` + Lazy-Init via
`EnsureRegexCacheBuilt`. Lifecycle-Konsequenz für Package-Build:

- Module-Var lebt für die GESAMTE BPL-Laufzeit (~Prozess-Lebenszeit im IDE)
- TRegEx hält interne PCRE2-Pattern → ~paar KB pro Pattern × 25 Patterns
  ≈ ~50KB Steady-State-Memory im Engine-BPL
- **Cleanup im finalization** wäre sauber, aber heute nicht gemacht
  (Process-Exit räumt's). Bei Engine-Unload (selten) leakt's.

→ **Empfehlung**: vor BPL-Migration ein einheitliches
`finalization FreeAndNil(CachedRe...)` pro Detektor ergänzen. Pattern:

```pascal
finalization
  // Lazy-allokiert in EnsureRegexCacheBuilt - bei Process-Exit aufrauemen.
  CachedReInit := False;  // TRegEx ist Record, kein explizites Free noetig
```

(TRegEx ist record-based, kein .Free nötig — Reset des Init-Flags reicht.)

### 9.3 Self-Test als Engine-Quality-Gate

`HowTo_DetectorSelftest.md` beschreibt den Dogfooding-Workflow. Bei der
Aufteilung sollte:

- Self-Test als CI-Job auf der `SCA.Engine.bpl` (kein UI nötig)
- `selftest-quiet` Profile als baseline
- Counts pro Detektor in einer Trend-Datei → Regression-Alarm wenn ein
  Detektor plötzlich 10× mehr Findings produziert
- Vorlage: `Todo_FalsePositiveReduction.md` Section D dokumentiert
  pro-Detektor verifizierte Reduktionen — wird zur Regression-Baseline

### 9.4 DCU-Cache-Fallstricke (gelernt aus SCA078-Sache)

Beim aktuellen Source-Pfad-Setup wurde meine `uExceptionTooGeneral.pas`-
Änderung im DCU-Cache nicht aufgefrischt obwohl die mtime stimmte. Symptom:
Source-Edit hat keinen Effekt im EXE-Verhalten trotz "Build All".

Bei Package-Migration verschärft sich das:
- Konsumenten linken gegen die **Output-BPL**, nicht gegen die Source
- DCU vom Engine-Build ist nicht zwingend der DCU vom Standalone-Build
- Mehrere DCU-Versionen können in `$(BDSCOMMONDIR)` koexistieren

→ **Migration-Risiko**: jeder Refactor braucht *expliziten* Clean-Build der
Engine-BPL bevor Konsumenten ihn sehen. CI-Script muss `del *.dcu *.bpl`
einbauen.

### 9.5 156 statt 150 Detektoren

Audit Stand 2026-06-01: 156 Detector-Units, davon
- ~14 Multi-Kind-Container (CodeSmells2/ConcurrencyExt/PerfHotspots/...)
- ~20 DFM-Detektoren via `TDfmAnalysisRunner`-Adapter (separater Pfad)
- 3 Helper/Non-Emitter (CustomClassDiscovery, CustomRuleDetector, LeakDetector2-Engine)

Engine-DPK Contains-Liste muss alle 156 explizit auflisten (kein
Source-Pfad-Magic). Wartungs-Aufwand: bei jedem neuen Detektor 2 Edits
(DPK contains + DPR uses).

→ **Vorschlag**: Code-Generator-Script `tools/regen-engine-dpk.ps1` das
die Contains-Liste aus `ls Detectors/u*.pas | sort` ableitet. Vorbild:
das bereits vorhandene `tools/perf_log_summary.ps1`.

### 9.6 gAstFileCache + gSymbolRefIndex als Engine-Singletons

Beide globalen Indizes (`Infrastructure/uAstFileCache.pas`,
`uSymbolReferenceIndex.pas`) sind heute Modul-Level-Variablen die in
`uStaticAnalyzer2.ParseLeaks` allokiert + freigegeben werden. Bei
Package-Migration:

- Singleton-Variable lebt im BPL-Adressraum, **shared zwischen allen
  Konsumenten** des gleichen Prozesses (IDE-Plugin + ... was sonst noch?)
- Zwei parallele Analyse-Läufe (z.B. Background-Watch + manueller Re-Scan)
  würden sich den Cache stehlen
- Heute funktioniert das, weil der Process die EXE/IDE ist und nur EIN
  Scan parallel läuft

→ **Empfehlung**: vor BPL-Migration die Singleton-Variablen durch
**Thread-Local-Storage** oder durch einen **expliziten Context-Parameter**
ersetzen. Letzteres ist sauberer:
```pascal
TStaticAnalyzer2.AnalyzeLeaksRecursive(Path, ARequest: TAnalyzeRequest)
```
wo ARequest die Caches kapselt.

### 9.7 Aktualisierte Migrationsplan-Phase

**Phase 0** (NEU, vor allem anderen, 1 Tag):
- Engine-Cleanup: TRegEx-Cache-`finalization` pro Detektor (Round 9/11/13-Files)
- Singleton-Entkopplung: `gAstFileCache`/`gSymbolRefIndex` in Context-Record
- `tools/regen-engine-dpk.ps1` schreiben
- Self-Test-Baseline einfrieren (`sca-baseline-engine.json` für künftiges
  Regression-Diff)

Damit ist Engine-Code "Package-ready" bevor die eigentliche Verschiebung
beginnt.
