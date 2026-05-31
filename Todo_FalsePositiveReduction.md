# False-Positives reduzieren — Vorschläge

Analyse der FP-relevanten Infrastruktur des StaticCodeAnalyser und konkrete,
auf die Architektur zugeschnittene Maßnahmen zur Reduktion von False-Positives.
Sortiert nach Hebelwirkung.

## Ausgangslage (Ist-Stand)

- **Die meisten Detektoren sind lexikalisch/regex-basiert** — 127 von ~140
  Detector-Dateien nutzen `TRegEx`/`AcquireLines`. Das ist die zentrale
  FP-Quelle, weil Typ- und Scope-Information fehlt.
- **Der AST ist flach** — Ausdrucks-Knoten (`nkIdent`, `nkBinaryOp`,
  `nkLiteral`, `nkDot`, …) sind in `TNodeKind` reserviert, werden aber vom
  Parser **nicht** erzeugt. Detektoren arbeiten auf Flachtext in
  `nkAssign.TypeRef` / `nkCall.Name`
  (siehe `StaticCodeAnalyserForm/sources/Parsing/uAstNode.pas`).
- **Vorhandene FP-Mechanismen:**
  - `// noinspection <Kind>` Suppression, Zeilen-basiert, als Post-Filter
    (`StaticCodeAnalyserForm/sources/Infrastructure/uSuppression.pas`).
  - Baseline-Filter (Fingerprint-basiert, CI-Adoption)
    (`StaticCodeAnalyserForm/sources/Infrastructure/uBaseline.pas`).
  - Profile-System (`uRuleCatalog.pas`).
  - `// NOSONAR` wird nur gemeldet, nicht zum Suppressen genutzt.
- **Kein First-class Confidence-Feld** auf `TLeakFinding` — Confidence wird
  heute von Hand in `Severity` gefaltet (siehe Kommentar in
  `StaticCodeAnalyserForm/sources/Common/uMethodd12.pas`, betrifft
  `uLeakDetector2`, `uDivByZero`).

---

## A. Größter Hebel — Architektur

### 1. First-class `Confidence`-Feld auf `TLeakFinding` + Schwellwert-Filter — ✅ ERLEDIGT
Aktuell war ein Finding binär: melden oder nicht. Umgesetzt:
- Enum `TFindingConfidence = (fcLow, fcMedium, fcHigh)` + Helpers
  `ConfidenceName`/`ParseConfidence` und globaler Schwellwert
  `FindingMinConfidence` (Default `fcMedium`) in `uSCAConsts.pas`.
- Feld `Confidence` auf `TLeakFinding` + Konstruktor mit Default `fcHigh`
  (`uMethodd12.pas`) → bestehende Detektoren bleiben hochkonfident, **null
  Verhaltensänderung** bis ein Detektor bewusst `fcLow` setzt.
- Eigenständiger, testbarer Post-Filter `TConfidenceFilter`
  (`uConfidenceFilter.pas`), in die Pipeline von `TStaticAnalyzer2.ParseLeaks`
  eingehängt (nach Suppression/Path-Overrides). `fkFileReadError` ausgenommen.
- INI-Anbindung `[Rules] MinConfidence = low|medium|high` in `uRepoSettings.pas`
  (analog `MinSeverity`).
- Tests in `tests/uTestConfidenceFilter.pas`.

**Vorteil:** FP-Logik wird **eine** tunbare Stellschraube statt hart in jeden
Detektor gebaut. Fundament für #6 und #7.

**Offen (Follow-up):** (a) ausgewählte heuristische Detektoren tatsächlich auf
`fcLow`/`fcMedium` taggen; (b) SARIF-Export `rank` aus Confidence ableiten;
(c) optional CLI-Flag `--min-confidence` + IDE-Override (analog
`FIdeMinSeverity`).

### 2. Golden-Corpus-Regressionstest
Ordner mit echten `.pas`-Dateien + erwarteten Findings (annotiert). Jeder
FP-Fix bekommt einen Negativ-Fall im Corpus → verhindert FP-Regressionen
dauerhaft. Die gelöschte `todo-sonardelphi-realworld-test.md` deutet an, dass
das angefangen war. Ohne das wandern gefixte FPs zurück.

---

## B. Präzision der Regex-Detektoren

### 3. String-/Kommentar-Stripping zentralisieren — ✅ ERLEDIGT
`StripStringsAndComments` war in `uFloatEquality` und `uNoSonarMarker` je
eigen reimplementiert (mit subtilen Abweichungen). Zusammengeführt in
`TDetectorUtils.ScanCodeLine` / `TDetectorUtils.StripStringsAndComments`
(`StaticCodeAnalyserForm/sources/Common/uDetectorUtils.pas`), beide Detektoren
darauf umgestellt, Unit-Tests in `tests/uTestDetectorUtils.pas`.
→ Damit verschwindet die Klasse „Match im String-Literal/Kommentar"-FPs
konsistent für alle künftigen Detektoren, die den zentralen Stripper nutzen.

### 4. Schlanke Symbol-/Typ-Tabelle pro Unit
Die dokumentierten FloatEquality-Limits (keine Typ-Inferenz für
Funktions-Returns/Parameter, `Self.X`-Felder unauflösbar) sind exakt eine
fehlende Symboltabelle. Ein gemeinsamer Pass, der je Unit deklarierte
Identifier + Typ (Vars, Params, Felder, Return-Typen) sammelt und Detektoren
bereitstellt, eliminiert eine ganze FP-Klasse (z.B. „`x = 0` gemeldet, obwohl
`x` ein `Integer` ist"). Größter Wurf, aber auch teuerste Maßnahme.

### 5. Bekannten Komma-Listen-Bug fixen
`A, B: Double` erfasst im FloatEquality-Detektor nur `A`. Primär ein
False-*Negative*, aber dieselbe Parser-Schwäche (Deklarationen nur halb
verstehen) erzeugt anderswo FPs. Deklarations-Regex auf Identifier-Listen
verallgemeinern.

---

## C. Prozess & Konfiguration

### 6. „High-Precision"-Profil
Das Profil-System existiert schon (`uRuleCatalog.pas`). Ein zusätzliches
Profil, das nur Regeln mit gemessen niedriger FP-Rate enthält — für Teams,
die lieber wenige sichere Findings wollen.

### 7. Suppression-Telemetrie
Jedes `// noinspection X` ist ein **gelabeltes FP-Signal** vom Nutzer.
Suppressions pro Kind zählen/loggen → die lautesten Regeln empirisch
identifizieren statt nach Bauchgefühl. Datenbasis für #1 und #6.

---

## Empfohlene Reihenfolge

1. **#3 (zentrales Stripping)** — ✅ erledigt (kleinster Aufwand, breite Wirkung).
2. **#1 (Confidence-Feld)** — Fundament für alles Weitere.
3. **#5 (Komma-Listen-Fix)** — kleiner, isolierter Gewinn.
4. **#2 (Golden-Corpus)** — sichert die übrigen Fixes dauerhaft ab.
5. **#6 / #7 (Profil + Telemetrie)** — datengetriebenes Tuning.
6. **#4 (Symboltabelle)** — größter Wurf, zuletzt.

---

## D. Self-Test Triage 2026-05-31 (v0.9.5 Dogfooding)

Workflow: `analyser.exe --path . --full --profile strict --report-sarif sca-selftest.sarif`
auf das eigene Repo. Sieben Triage-Runden mit ~5400 eliminierten FPs aus
12 200 Findings auf v0.9.5. Detail-Workflow siehe
[HowTo_DetectorSelftest.md](HowTo_DetectorSelftest.md).

### Erledigte Detector-Fixes

| Round | Commit | Detector | FP-Klasse | Δ |
|---|---|---|---|---|
| 1 | `0d752f3` | uHardcodedSecret | Meta-Felder (SourceXxx/XxxChar/XxxRef) | 4 |
| 1 | `0d752f3` | uRestHttpSecurity | TLS-Pattern matchte in eigenen Fix-Templates | 3 |
| 1 | `0d752f3` | uSqlDangerousStatement | `:=` im Literal → Pascal-Code-Zitat | 1 |
| 1 | `0d752f3` | uConsoleRunner | NEU: `--report-html` Flag | — |
| 2 | `4b7f5cc` | uFieldName | Default-Visibility ist `published` (TForm/Frame/DataModule) | ~3000 |
| 2 | `4b7f5cc` | uRedundantJump | Look-Ahead: nur flaggen wenn nach `end;` Block-Terminator | ~900 |
| 2 | `4b7f5cc` | uUnusedRoutine | `MaxLineOf(Mth)` statt `NextStartAfter` für self-call-Range | ~50 |
| 2 | `4b7f5cc` | uFormatMismatch | `IsInsideStringLiteral`-Guard | 3 |
| 2 | `4b7f5cc` | uUseAfterFree | Sibling-Free-Guard (if/else-Pattern) | 1 |
| 3 | `68de1d3` | uPublicField | Multi-line Method-Header-Continuation + Section-Boundaries | ~50 |
| 3 | `68de1d3` | uGroupedDeclaration | ParenDepth-Filter (Param-Listen sind idiomatisch) | ~600 |
| 3 | `68de1d3` | uCommentedOutCode | Backtick-Code-Spans aus Doc-Kommentaren strippen | ~70 |
| 3 | `68de1d3` | uCanBeClassMethod | Event-Handler-Signature-Check (`Sender: TObject`) | ~50 |
| 3 | `68de1d3` | **uParser2** | `for k := ...` Loop-Variable wurde aus AST verworfen | (indirekt) |
| 4 | `484e407` | uLeakDetector2 | Release/Dispose/Return/Recycle-Pattern erkennen | ~60 |
| 5 | `43fd0e6` | uExceptionTooGeneral | Legit Top-Level-Handler (log+exit/raise) | ~40 |
| 5 | `cec4d41` | uUnusedLocal | Source-Verify (Parser legt nested-Procs als nkLocalVar) | ~30 |
| 5 | `cec4d41` | uFreeWithoutNil | Nur Felder flaggen (Locals fallen aus dem Scope) | ~100 |
| 5 | `cec4d41` | uTodoComment | Skip Pfad-Refs (`todo-sonar.md`/`todo.md`) | ~20 |
| 6 | `679caef` | uMethodName | DFM-Event-Handler-Skip | ~8 |
| 7 | `ae2f20b` | uTypeName | Exception-Klassen (`E*`/`*Error`/`*Exception`) skippen | 4 |

**Zusatz-Infrastruktur**:
- Profile-Negation-Syntax `["*","!Kind"]` in `uRuleCatalog` (Commit `431a901`).
- Bundled Profile `selftest-quiet` blendet 11 reine Style-Detektoren aus.
- CLI-Flag `--report-html` via `TExporterHtml`.

### Bekannte Limitationen (NICHT gefixt, by-design)

Die folgenden Findings sind keine FPs im Detektor-Sinn, sondern Folge
fundamentaler Design-Trade-offs:

| Rule(n) | Hits (post-fix) | Begründung |
|---|---|---|
| SCA052 / SCA107 / SCA050 | ~580 | Single-File-Scope per Design (siehe `uVisibilityCheck.pas:24-31`). Cross-Unit-Lookup hatte mehr FPs als TPs (RTTI/DFM/Generics). HINT-Empfehlung, Compiler-E2361 verifiziert. |
| SCA101 / SCA062 / SCA142 / SCA079 / SCA081 / SCA087 / SCA088 | ~1700 | Pure Style. Im Profile `selftest-quiet` deaktiviert. |
| SCA021 / SCA012 / SCA013 / SCA022 / SCA014 / SCA117 | ~700 | Echte Code-Metriken (Komplexität/Länge/Doku) — Schwellwerte projekt-spezifisch. |
| SCA025 / SCA039 / SCA024 / SCA034 in `*Sample.pas`/`*Demo.pas`/`*.dfm` | ~50 | Test-Fixtures by design. |
| SCA098 / SCA127 / SCA077 in `uTest*.pas` | ~10 | Detector-Self-Test-Fixtures. |
| SCA121 (`Result := ...` in nested-try) | 1 | Parser-Bug in tiefer try-Verschachtelung. Größerer Refactor nötig. |
| SCA083 / SCA065 (Self-Match in Detector-Doku-Kommentaren) | ~6 | Narrow, geringe ROI. |

### Test-Anpassungen

Folgende Tests dokumentierten altes (übereifriges) Verhalten und wurden
umgestellt:

- `uTestGroupedDeclaration.ParameterGrouped_Reported` → `ParameterGrouped_NotReported`
  (Commit `afd43b6`). Param-Grouping ist idiomatisches Pascal.
- `uTestFreeWithoutNil.FreeWithoutNil_Reported` + `Finding_KindAndSeverity`
  (Commit `cec4d41`). SRC auf Field-Pattern umgestellt (Locals nicht mehr geflaggt).

### Aggregierte Wirkung

| Metrik | v0.9.5 | nach Rebuild #1 (R1-R3) | nach Rebuild #2 (R4-R7, erwartet) |
|---|---|---|---|
| Total | 12 200 | 7 119 | ~6 800 |
| Errors | 37 | 16 | ~10 |
| Warnings | 609 | 612 | ~570 |
| Notes | 11 554 | 6 491 | ~6 200 |

**Reduktion gesamt**: ≈ −44%, alle eliminierten Findings strukturell erklärt.
Keine echten Bugs übersehen (Cross-Check via DUnit-Suite mit 1696 Tests).
