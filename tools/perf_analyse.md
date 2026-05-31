# SCA Performance-Analyse

Strukturelle Untersuchung wo der SCA-Analyselauf seine Zeit verbringt,
plus konkrete Optimierungs-Vorschläge mit Aufwand-/Impact-Schätzung.

Quelle: Code-Review von [uStaticAnalyzer2.pas](../StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas) +
[uParser2.pas](../StaticCodeAnalyserForm/sources/Parsing/uParser2.pas) +
allen Detektor-Units.

---

## 1. Pipeline-Reihenfolge pro Analyselauf

```
AnalyzeLeaksRecursive(Path)
│
├── Pre-Pass 1: gDfmRepoIndex.Build(FileList)
│   └── für jede .pas: TParser2.ParseFile  ← #1 Parse-Durchlauf
│
├── Pre-Pass 2: gSymbolRefIndex.Build(FileList)
│   └── für jede .pas: TParser2.ParseFile  ← #2 Parse-Durchlauf
│
├── Main-Loop: für jede .pas
│   ├── TParser2.ParseFile                 ← #3 Parse-Durchlauf
│   ├── TCustomClassDiscovery.DiscoverInUnit
│   ├── RunAllDetectors  (~25 AST-Detektoren, jeder mit 1-10 FindAll-Calls)
│   ├── 7× File-Scan-Detektoren            ← #4-10 File-Reads
│   │   (uTodoComment, uWithStatement, uReversedForRange,
│   │    uLengthUnderflow, uTautologicalExpr, uDuplicateBlock,
│   │    uCustomRuleDetector)
│   └── DfmAnalysisRunner.AnalyzePasFile
│       ├── für jede companion .dfm: TDfmParser.ParseSource
│       └── für jede companion .dfm: TParser2.ParseFile ← #11 Parse
│
└── Post-Filter: TSuppression.ApplyToFindings
    └── pro Befund: 1 LoadFromFile der zugehörigen .pas  ← #12+ File-Read
```

**Per-File-Multiplier**: bei vollständigem Scan wird jede .pas typischerweise
**3-5 mal geparst** und zusätzlich **7+ mal als Text gelesen**.

---

## 2. Hot-Spots — gemessen anhand FindAll-Anzahl

Stand jetzt im Code:

| Detector | FindAll-Calls | Approx. AST-Walks/File |
|---|---:|---:|
| uLeakDetector2 | 10 | 10 |
| uUnusedParameter | 6 | 6 |
| uDivByZero | 6 | 6 |
| uVisibilityCheck | 5 | 5 |
| uFormatMismatch | 5 | 5 |
| uFieldLeak | 5 | 5 |
| uVirtualCallInCtor | 4 | 4 |
| uNilDeref | 4 | 4 |
| uCustomClassDiscovery | 4 | 4 |
| Andere | 2-3 | 2-3 |

**Summe ~100 FindAll-Calls pro .pas-Datei** → 100 vollständige AST-Tree-Walks
pro File. Jeder Walk alloziert eine neue `TList<TAstNode>` (Heap-Pressure).
Bei 1000 Files = 100 000 Tree-Walks + 100 000 Listen-Allokationen.

---

## 3. Bottleneck-Inventur (sortiert nach erwartetem Impact)

### 🅐 Doppel-Parse durch Pre-Indizes (HOCH)
**Symptom**: Bei `AnalyzeLeaksRecursive` werden `gDfmRepoIndex` und
`gSymbolRefIndex` jeweils per `Build(FileList)` über alle Dateien geparst.
Das sind **2× zusätzliche volle Parser-Durchläufe** vor der eigentlichen
Analyse.

**Files**:
- [uDfmRepoIndex.pas:116-118](../StaticCodeAnalyserForm/sources/Infrastructure/uDfmRepoIndex.pas#L116-L118)
- [uSymbolReferenceIndex.pas:200-203](../StaticCodeAnalyserForm/sources/Infrastructure/uSymbolReferenceIndex.pas#L200-L203)

**Fix-Idee**: Zentraler AST-Cache `TAstFileCache` der pro Pfad einmal parst und
das Root-Node hält. Pre-Indizes + Main-Loop greifen auf denselben Cache zu.
Sparpotential: **2/3 der Parser-Zeit weg**, also bei Parser-dominiertem Scan
~50% Gesamtspeed-up.

**Aufwand**: 2-3 Stunden. Neue Unit `Infrastructure/uAstFileCache.pas` +
3 Call-Sites umstellen. Risiko: Memory-Footprint steigt (ASTs bleiben länger
im Heap), aber typisch <50 MB für 1000-File-Projekte.

### 🅑 File-Scan-Detektoren lesen jede Datei einzeln (MITTEL)
**Symptom**: 7 Detektoren rufen jeweils `Lines.LoadFromFile(FileName, ...)`
auf, dann iterieren sie über die Lines. Pro .pas-Datei sind das **7× Disk-IO
+ 7× TStringList-Allokation + 7× Encoding-Erkennung**.

**Files**:
- uTodoComment, uWithStatement, uReversedForRange, uLengthUnderflow,
  uTautologicalExpr, uDuplicateBlock, uCustomRuleDetector

**Fix-Idee**: `TLineCache` pro File - einmal lesen + dekodieren, allen
File-Scan-Detektoren via Closure/Parameter durchreichen. Existierendes
Pattern: `TFindingHelper.FindingsOfFile` (Tests) macht das schon, aber die
Production-Pipeline nicht.

**Aufwand**: 3-4 Stunden. Signatur-Änderung an allen 7 Detektoren (statt
`AnalyzeUnit(Root, FileName, Results)` → `(Root, FileName, Lines, Results)`).
Sparpotential bei 1000-File-Scan: 6 von 7 File-IO-Ops gespart →
~25-40% File-IO-Zeit weg (Festplatten-abhängig stärker auf HDD,
weniger auf SSD).

### 🅒 FindAll alloziert immer eine neue Liste (MITTEL)
**Symptom**: `MethodNode.FindAll(nkAssign)` und `MethodNode.FindAll(nkCall)`
werden in mehreren Detektoren je Method gerufen. Pro Call neue
`TList<TAstNode>.Create`. Bei 5000 Methoden × 5 Detektoren × 2 FindAll =
50 000 Allokationen.

**Fix-Idee A** (klein, ~30 Min): Eine ge-cachte Variante `FindAllInto(Kind,
Reuse: TList<TAstNode>)` die in eine vom Caller bereitgestellte Liste
schreibt + clearen. Hot-Loops reusen eine einzige Liste über alle Methoden.

**Fix-Idee B** (groß, halber Tag): Pro Methode einen einmaligen Visitor-
Pass der ALLE benötigten NodeKinds in ein Dictionary
`<NodeKind, TList<TAstNode>>` sammelt. Alle Detektoren bedienen sich
aus diesem Cache → 1 Walk statt N.

**Aufwand**: A ist 30 Min, B ist ein halber Tag mit Risiko (Detector-API-
Änderung). A bringt ~20% bei AST-walk-dominiertem Scan.

### 🅓 DfmAnalysisRunner re-parst die .pas (NIEDRIG-MITTEL)
**Symptom**: `TDfmAnalysisRunner.AnalyzePasFile` ruft `TParser2.ParseFile`
auf der .pas nochmal — obwohl der Main-Loop sie gerade frisch geparst hat.

**File**: [uDfmAnalysisRunner.pas:140](../StaticCodeAnalyserForm/sources/Infrastructure/uDfmAnalysisRunner.pas#L140)

**Fix-Idee**: AnalyzePasFile zusätzliche Signatur mit `UnitNode: TAstNode`
parameter, die der Main-Loop durchreicht. Bei .pas ohne companion .dfm
fällt der Re-Parse sowieso aus (early-return). Aber wenn .dfm existiert,
spart die Übergabe einen vollen Parse-Run.

**Aufwand**: 1-2 Stunden. Sparpotential abhängig von DFM-Anteil (mORMot:
fast keine DFM → kaum Impact; klassisches VCL-Projekt → 30-50% der Files
haben .dfm, also gut messbar).

### 🅔 Suppression-Pass öffnet Files für jedes Finding (NIEDRIG)
**Symptom**: `TSuppression.ApplyToFindings` iteriert pro Befund + öffnet
die Quelldatei jeweils mit `LoadFromFile`. Bei vielen Findings auf einer
Datei wird sie mehrfach gelesen.

**File**: [uSuppression.pas](../StaticCodeAnalyserForm/sources/Infrastructure/uSuppression.pas)

**Fix-Idee**: Findings nach FileName gruppieren, pro Gruppe die Datei
genau einmal lesen + Suppression-Map bauen.

**Aufwand**: 1 Stunde. Sparpotential nur relevant für Projekte mit
hundert+ Findings.

---

## 4. Was ist schon gut

- **`CollectAll` iterativ** (uAstNode.pas:184) — kein Stack-Overflow-Risiko
- **Pro-File-Watchdog** im Parser — kein Endlos-Loop bei kaputtem Source
- **Per-Detector Stopwatch + Logging** schon vorhanden — Performance-Bugs
  werden im `.log` mit "(langsam!)" markiert wenn > 500 ms
- **`DetectorMaxFileBytes`** schützt vor Pathologien
- **AST-basierte Detektoren** sind durchweg O(Nodes), nicht O(Nodes²) —
  kein quadratisches Verhalten gefunden

---

## 5. Quick-Win-Ranking

| # | Item | Aufwand | Impact | Risiko |
|---|---|---|---|---|
| 1 | 🅐 AST-Cache für Pre-Indizes | 2-3 h | Hoch (~50%) | Niedrig (additiv) |
| 2 | 🅑 File-Read-Cache für File-Scan | 3-4 h | Mittel (~25%) | Niedrig (Signatur-Add) |
| 3 | 🅒A FindAllInto-Variante | 30 min | Niedrig-Mittel | Sehr niedrig |
| 4 | 🅓 UnitNode an DfmRunner durchreichen | 1-2 h | Niedrig (VCL: Mittel) | Niedrig |
| 5 | 🅔 Suppression File-Read-Cache | 1 h | Niedrig | Sehr niedrig |

**Empfehlung**: 🅐 + 🅑 zuerst — zusammen ~5 h Aufwand, ~60-70% Speed-up
auf typischen Projekt-Scans. Rest ist Inkrement-Politur.

---

## 6. Wie man real misst (nach IDE-Build)

### Variante A — Bestehende `.log`-Datei auswerten

Der CLI-Lauf produziert eine `.log`-Datei mit per-File Parse-Time und
"langsam!"-Markern. Dafür gibt's jetzt `tools/perf_log_summary.ps1`:

```powershell
.\sca-bin\analyser.d12.exe --path <project> --report-html report.html
powershell -ExecutionPolicy Bypass -File tools\perf_log_summary.ps1 -LogFile sca.log
```

Output: Markdown-Tabelle mit Top-20-langsamsten Dateien + per-Detector-
Aggregaten.

### Variante B — Sampling-Profiler

Für tieferes Profiling: [Sampling Profiler](https://www.delphitools.info/samplingprofiler/)
an die `analyser.d12.exe` hängen während eines Scans auf ein
großes Test-Repo.

### Variante C — uTestPerformance baseline

Der bestehende [uTestPerformance.pas](../StaticCodeAnalyserForm/tests/uTestPerformance.pas)
fixiert Soft-Limits für synthetische Workloads (50/500 Methoden,
DeepNesting). Bei Regressionen schlagen die Tests an.

---

## 7. Trade-offs der implementierten Optimierungen

### 🅐 AST-File-Cache — Memory-Peak-Regression in Pre-Index-Phase

`gAstFileCache` wird in `ParseLeaks` **vor** den beiden Pre-Indizes
(`gDfmRepoIndex.Build` + `gSymbolRefIndex.Build`) angelegt. Beide
Pre-Index-Phasen parsen alle Files und befüllen den Cache. Erst der
Main-Loop räumt File-für-File via `Evict` auf.

**Konsequenz**: Direkt vor Main-Loop-Start liegen **alle N AST-Trees
gleichzeitig im Heap**. Vorher hat jede `ScanUnit`-Iteration ihr AST
lokal geparst und sofort freigegeben → konstanter Peak von 1× AST.

**Größenordnung**:

| Projekt-Größe | Avg. AST-Size | Peak (vorher) | Peak (nachher) |
|---|---|---|---|
| 100 Files | ~50 KB | <1 MB | ~5 MB |
| 1 000 Files | ~50 KB | <1 MB | ~50 MB |
| 5 000 Files | ~50 KB | <1 MB | ~250 MB |
| 10 000 Files | ~50 KB | <1 MB | ~500 MB |

Bis ~2000 Files ist das auf Standard-Entwickler-Hardware (8-16 GB RAM)
unkritisch. Für sehr große Repos (>5000 .pas) sollte man den Memory-
Verbrauch beobachten — bei Bedarf eine selektive Eviction-Strategie
ergänzen (z.B. nach `gSymbolRefIndex.Build` alle Files entfernen, die
nicht im Main-Loop-Input vorkommen, oder LRU mit Cap).

**Aktueller Stand**: bewusst akzeptiert, weil ASTs bei typischen Größen
unter 50 MB Peak bleiben und der Parse-Zeit-Gewinn (3× → 1×) dominant ist.

### 🅑 File-Text-Cache — uncritical

`gFileTextCache.Clear` wird nach jeder Main-Loop-Iteration aufgerufen,
also liegt nur die Text-Repräsentation des **aktuell** verarbeiteten
Files im Cache (1× ~30 KB). Kein Memory-Concern.

### 🅕 Regex-Cache pro Detektor — Round 9 (commit 81749a0)

22 Detektoren rufen `TRegEx.Create` in `AnalyzeUnit` auf - für KONSTANTE
Patterns. Im Self-Test mit 409 Files = ~8000 Regex-Compilations pro Scan
ohne semantischen Grund. Round-9 hat die 4 hot-path Detektoren auf
Module-Level-Lazy-Cache umgestellt:

| Detektor | Patterns | Hot? |
|---|---:|---|
| uRestHttpSecurity | 4 | jeder File |
| uPerfHotspots | 3 | jeder File |
| uLockWithoutTryFinally | 1 | jeder File |
| uUseAfterFree | 2 | besonders teuer: ReEndOfMethod war PRO Free-Match neu kompiliert |

**Pattern**: `var Cached_X : TRegEx; CachedReInit: Boolean = False;` plus
ein `EnsureRegexCacheBuilt`-Helper. Init beim ersten AnalyzeUnit, dann
für alle weiteren Files wiederverwendet.

**Restliche 18 Detektoren**: bleiben TRegEx.Create-pro-File. Wenn der
Self-Test sie als hot zeigt, gleiche Migration nach selbem Pattern.

### 🅖 StripFileComments-Konsolidierung — OFFEN

10 Detektoren haben lokale `StripFileComments`-Funktionen (~70 Zeilen
pro Kopie = 700 Zeilen Duplikat). ABER: spot-check zeigt mindestens
zwei Varianten unter gleichem Namen:

- **uRestHttpSecurity / uPerfHotspots / ...**: behält String-Inhalte
- **uLockWithoutTryFinally / uEmptyBlock / ...**: ersetzt String-Inhalte
  durch Blanks (analog zu `TDetectorUtils.StripStringsAndComments`)

Naive Zentralisierung würde Detektor-Semantik subtil ändern (FPs / FNs
in Pattern-Matches). Vor Konsolidierung: pro Detektor verifizieren
welche Variante er braucht, dann auf `TDetectorUtils.StripFileCommentsOnly`
(neu) oder `TDetectorUtils.StripStringsAndComments` (vorhanden) migrieren.

Schätzung: 1-2 h pro Detektor inkl. Test-Verifikation = 10-20 h gesamt.
Trade-off: -700 Zeilen Code, kein Perf-Impact (StripFileComments läuft
einmal pro File, schon im File-Read-Cache amortisiert).
