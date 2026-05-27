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
