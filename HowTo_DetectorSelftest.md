# HowTo: Detector Self-Test (Dogfooding)

Den StaticCodeAnalyser auf seinen eigenen Quelltext loslassen, um neue
False-Positive-Klassen zu finden und Detektor-Qualitaet messbar zu halten.

## Warum

Jedes Mal wenn ein Detektor erweitert wird, ist der Analyser selbst die
beste Testumgebung:

- ~1700 Pascal-Files, viele Sprach-Idiome, Multi-Line-Method-Header,
  Markdown-Code-Spans in Doc-Comments, Quickfix-Templates mit
  Pascal-Code im String-Literal etc.
- Real-Welt-Mix aus Detektoren, Tests, Parser, GUI-Code (TForm/TFrame),
  IDE-Plugin (ToolsAPI), CLI-Runner.
- Findings sind sofort triage-fbar - der Code-Owner sind WIR.

Ein Self-Test-Run hat in der Praxis schon Bugs in 14 Detektoren plus
einen Parser-Bug zutage gefoerdert (siehe Commit-History
`fix(detectors): self-test FP-Fixes`).

## Voraussetzungen

- Aktueller Release/Win64-Build:
  `Output\Win64 Release\StaticCodeAnalyser.d12.exe`
  (Build via IDE, da Delphi-Community-Edition kein msbuild-CLI hat.)
- `rules\sca-rules.json` aktuell (auto-loaded via dproj-Deployment).

## Run

```powershell
"Output\Win64 Release\StaticCodeAnalyser.d12.exe" `
  --path "D:\git-demos\delphi\StaticCodeAnalyser" `
  --full `
  --profile selftest-quiet `
  --report-html sca-selftest.html `
  --report-sarif sca-selftest.sarif `
  --quiet
```

Laufzeit auf einem Mid-Range-Desktop: ~3 Sekunden fuer das ganze Projekt.

## Profile `selftest-quiet`

Default-Profil meldet alles inklusive Style-Regeln. Beim Self-Test
ueberwiegt Style-Noise (Line-Length, begin..end-Required, Uses-
Sort) die echten Bugs - deshalb dieses dedizierte Profil das die
folgenden reinen Style-Detektoren ausblendet:

| Kind | Begruendung fuer Ausblendung |
|---|---|
| `BeginEndRequired` | Hint, projekt-stilabhaengig, ~700 Hits |
| `TooLongLine` | Mechanisches Format, im IDE-Linter abgedeckt |
| `UnsortedUses` | Style, oft bewusst gruppiert |
| `ConsecutiveSection` | Style, mehrere `var`-Bloecke oft absichtlich |
| `ClassPerFile` | Style, Helper-Klassen sind oft im selben File ok |
| `EmptyVisibilitySection` | Cosmetisch, harmlos |
| `ConcatToFormat` | Refactor-Hint, nicht jeder Concat ist falsch |
| `NestedTry` | Refactor-Hint, manche nested-Trys sind sinnvoll |
| `GroupedDeclaration` | Style, Diff-Hygiene-Argument schwach |
| `NilComparison` | Convention, `=nil` vs `not Assigned(x)` |
| `CommentedOutCode` | Hit-Rate vs Signal niedrig nach Round-3-Fix |

Wenn du eine dieser Regeln aktivieren willst: ein eigenes Profile
in `rules\sca-rules.json` mit Negation-Syntax (s. unten).

## Output triagieren

### HTML (`sca-selftest.html`)

Self-contained Code-Review-Report mit Filter (Severity/Type/Search),
Sort und Snippet-Toggle. Im Browser oeffnen, beginnen mit `Error`-
Findings (klein, hoechstes Signal).

### SARIF (`sca-selftest.sarif`)

Maschinen-lesbar fuer eigene Triage-Skripte:

```powershell
$s = Get-Content sca-selftest.sarif -Raw | ConvertFrom-Json
"Total: $($s.runs[0].results.Count)"
$s.runs[0].results | Group-Object level | ForEach-Object { "  $($_.Name): $($_.Count)" }

# Top noisy rules
$s.runs[0].results | Group-Object ruleId | Sort-Object Count -Descending |
  Select-Object -First 12 | ForEach-Object { "  {0,4}  {1}" -f $_.Count, $_.Name }
```

### Triage-Workflow

1. **Errors zuerst** - meist klein (10-50) und hochgradig
   actionable.
2. **Pro Finding entscheiden**: TP (echter Bug) oder FP
   (Detektor-Schwaeche).
3. **Bei FP**: zugehoerigen Detektor in
   `StaticCodeAnalyserForm\sources\Detectors\` aufrufen, Guard
   ergaenzen, Unit-Test im `tests\uTestXxx.pas` erweitern, Commit
   mit Begruendung warum die Heuristik diese Klasse ausschliesst.
4. **Bei TP**: Bug fixen.
5. **Build + Re-Scan**. Diff der Counts vor/nach Fix zeigt den
   konkreten Erfolg.

## Profile-Negation-Syntax

Seit Commit `43fd0e6` unterstuetzt der Profile-Loader Negation:

```json
"my-profile": [
  "*",                       /* alle Detektoren */
  "!Kind1",                  /* AUSSER Kind1 */
  "-Kind2"                   /* '-' ist Alias fuer '!' */
]
```

Token-Reihenfolge zaehlt (links nach rechts):
- `["*", "!Foo"]`  → alle ausser Foo
- `["!Foo", "*"]`  → alle (das `*` setzt nach dem Exclude wieder
  alles dazu, inklusive Foo)
- `["Foo", "Bar"]` → nur Foo und Bar (additiv ohne `*`)

Kind-Namen sind die `kind`-Werte aus `rules\sca-rules.json`
(z.B. `BeginEndRequired`, `MemoryLeak`, `FormatMismatch`).

## Historische FP-Reduktion via Self-Test

Vier Triage-Runden, alle in main:

| Commit | Detektor-Fix(es) | FP-Klasse |
|---|---|---|
| `0d752f3` | uHardcodedSecret, uRestHttpSecurity, uSqlDangerousStatement, uConsoleRunner | Meta-Felder, Self-Match in Fix-Templates, neuer `--report-html` |
| `4b7f5cc` | uFieldName, uRedundantJump, uUnusedRoutine, uFormatMismatch, uUseAfterFree | published-Default-Visibility, inner-block-end, routine-end-via-AST |
| `68de1d3` | uPublicField, uGroupedDeclaration, uCommentedOutCode, uCanBeClassMethod, **uParser2** | multi-line method-header, paren-depth, backtick-strip, event-handler, for-loop AST |
| `484e407` | uLeakDetector2 | Release/Dispose/Return/Recycle-Pattern |
| `43fd0e6` | uExceptionTooGeneral + Profile-Negation | Top-Level-Handler |

Total: **12 200 → 7 119 Findings** (-42%), davon **37 → 16 Errors**
(-57%). Alle eliminierten Findings waren strukturelle FPs, keine
echten Bugs - alle Tests in DUnit weiterhin gruen ausser einem
explizit umgestellten (`ParameterGrouped_Reported` → `_NotReported`).

## Wann re-runnen

- Nach jedem neuen Detektor: Self-Test laeuft schon mit, Round-Out
  triage von >5 FPs in der eigenen neuen Regel.
- Vor jedem Release-Tag: Vergleich Counts gegen vorigen Release als
  Quality-Gate.
- Bei Bug-Reports "Detector flaggt Y faelschlich": pruefen ob Y im
  Self-Test auch gefunden wird (oft ja - dann ist die Reproduktion
  da, und der Self-Test ist gleichzeitig Regression-Test fuer den
  Fix).

## Verwandte Dokumente

- `HowTo_AddDetector.md` - neuen Detektor anlegen
- `Todo_FalsePositiveReduction.md` - laufende FP-Backlog-Liste
- `Konzept_SCA164_UnusedRoutine.md` - Beispiel-Detektor-Design
