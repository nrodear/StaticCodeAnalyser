# Confidence-Audit pro Detektor (Phase-1 A.1)

**Stand:** 2026-06-02 · **Konzept:** [Konzept_ScannerQualitaet.md](../Konzept_ScannerQualitaet.md) §A.1

## Modell

Jedes Finding hat zwei orthogonale Dimensionen:

| Dimension      | Sagt aus                                          | Werte                        |
|----------------|---------------------------------------------------|------------------------------|
| `Severity`     | Wie schlimm WENN der Befund echt ist              | `error` / `warning` / `hint` |
| `Confidence`   | Wie sicher der Detektor ist, dass es KEIN FP ist  | `low` / `medium` / `high`    |

Post-Filter `uConfidenceFilter` verwirft Findings unter
`FindingMinConfidence` (Default **medium**). User kann via
`--min-confidence high` strenger filtern.

## Default-Werte (`KindDefaultConfidence` in `uSCAConsts.pas`)

Alles was nicht in den Listen unten steht ist **`fcHigh`** (sicherer Default).
Detektoren-Override via `F.Confidence := xxx` nach `SetKind` bleibt moeglich
(siehe `uCommandInjection` als fcLow-Override).

### `fcMedium` (Pattern-Match / Metrik / Style)

Pattern-Match-basiert (rein lexikalisch oder regex, ohne Datenfluss):

| Kind                       | Begruendung                                          |
|----------------------------|------------------------------------------------------|
| `fkHardcodedSecret`        | Pattern-Match auf Variable-Namen, kein Wert-Check    |
| `fkHardcodedPath`          | `C:\`/`/etc/`-Pattern, viele OK-Faelle (Tests)       |
| `fkHardcodedString`        | Lokalisierbarkeit kontextabhaengig                   |
| `fkTodoComment`            | rein lexikalisch, Triage-Hint                        |
| `fkCommentedOutCode`       | Heuristik; Round 13 fixt Block-Faelle, FPs bleiben   |
| `fkDuplicateString`        | Token-Match, viele triviale Hits                     |
| `fkDuplicateBlock`         | LOC-Toleranz, FP bei boilerplate                     |
| `fkMagicNumber`            | viele konventionell-OK-Faelle (`0`,`1`,`-1`,`100`)   |
| `fkDebugOutput`            | `WriteLn` legitim bei CLI-Tools                      |

Metric-basiert (Schwellwert-Heuristik, abhaengig vom Coding-Stil):

- `fkLongMethod`, `fkLongParamList`, `fkLargeClass`, `fkGodClass`,
  `fkDeepNesting`, `fkCyclomaticComplexity`, `fkCaseStatementSize`

Style-/Refactor-Praeferenzen (kein Bug, oft kontroverses Style-Thema):

- `fkBooleanParam`, `fkMultipleExit`, `fkCanBeClassMethod`,
  `fkCanBeUnitPrivate`, `fkCanBeProtected`, `fkCanBeStrictPrivate`,
  `fkPublicMemberWithoutDoc`, `fkConstantReturn`, `fkUnusedParameter`,
  `fkUnusedPublicMember`, `fkUnusedPrivateMethod`

> Note: die `Unused*`-Detektoren bleiben fcMedium solange der Symbol-
> Referenz-Index ueber Units hinweg nicht reaktiviert ist
> (Konzept A.3) - sonst hohes FP-Risiko bei Cross-Unit-Konsumenten
> (RTTI/DFM/Plugin-APIs).

Schema-Heuristik (DFM ohne vollen Schema-Index):

- `fkDfmDefaultName`, `fkDfmHardcodedCaption`, `fkDfmFieldTypeMismatch`,
  `fkDfmTabOrderConflict`, `fkDfmForbiddenClass`, `fkDfmLayerViolation`,
  `fkDfmGodHandler`, `fkDfmDbInUiForm`

Security-Heuristik ohne Datenfluss:

- `fkSQLInjection` (ohne Taint-Tracking)
- `fkInsecureCryptoAlgorithm` (Pattern-Match auf Algo-Namen)

### `fcLow` (Detektor-Override)

Detektoren die explizit fcLow setzen (nicht ueber KIND_META):

- `fkCommandInjection` -> `uCommandInjection.pas` setzt `:= fcLow` nach SetKind,
  weil rein lexikalische Heuristik ohne Taint-Tracking sehr FP-anfaellig

### `fcHigh` (alle anderen)

Struktureller Bug-Match mit klarer Logik. Beispiele:

- `fkMemoryLeak`, `fkUseAfterFree`, `fkNilDeref`, `fkFreeWithoutNil`
- `fkVirtualCallInCtor`, `fkSynchronizeInDestructor`
- `fkReversedForRange`, `fkFormatMismatch`, `fkTautologicalBoolExpr`
- `fkUnusedRoutine`, `fkUnusedSuppression`, `fkRedundantJump`
- alle DFM-Bug-Klassen (`fkDfmDeadEvent`, `fkDfmCircularDataSource`,
  `fkDfmMasterDetailUnlinked`, `fkDfmSqlFromUserInput`, ...)

## Tooling

- Setzen: zentral in [`uSCAConsts.KindDefaultConfidence`](../StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas)
- Anwenden: `TLeakFinding.SetKind` ruft `KindDefaultConfidence` mit auf
- Override: Detektor setzt `F.Confidence := xxx` nach `SetKind`
- Filtern: `uConfidenceFilter.ApplyToFindings(Findings, MinConfidence)`
- CLI-Flag: `--min-confidence low|medium|high` (Default: medium)

## Wartung

Wenn ein Detektor strukturell verbessert wird (z.B. Taint-Tracking dazu)
und damit das FP-Risiko sinkt, **diesen Audit-Eintrag pruefen** und ggf.
Confidence anheben.

Wenn ein neuer Detektor hinzukommt und heuristisch ist: hier eintragen
**und** im `KindDefaultConfidence`-case ergaenzen.
