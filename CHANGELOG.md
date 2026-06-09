# Changelog

All notable changes to this project are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] - Hardening v3 + v4, FP-Reduction Sprint (since v0.9.7)

### 2026-06-09 — FP-Reduction + Diagnostics Pass

**Detector False-Positive reduction** on self-scan (67 → 12 FPs, −82%):
- **SCA017 DebugOutput** — String-literal contents (`'WriteLn(...)'` in UI-hint
  templates) no longer flagged as real debug calls. New `IsInsideStringLiteral`
  helper counts bare apostrophes before the match position.
- **SCA070 CommentedOutCode** — Inline-doc comments after code and doc-block
  starts (look-ahead on next line) skipped. Reduced from 45 to 9 FPs (−80%).
- **SCA019 TodoComment** — Detector-source mentions like `'TODO'` in quotes,
  `TODO / FIXME / HACK / XXX` slash-lists and `(TODO)` in parens skipped.
  Reduced from 13 to 3 FPs (−77%); remaining 3 are real backlog markers.
- **SCA005 FormatMismatch** — empty-resolved const identifiers
  (`Format(IDENT, [arg])` where IDENT resolves to empty) no longer reported
  as `0 placeholders, 1 arguments`.

**Bug fixes:**
- **FieldLeak detector** — `FreeAndNil(Self.Field)` with `Self.`-qualifier
  was not recognised as freeing, producing false leak reports in code that
  consistently uses Self-qualified field access.
- **TEMP DIAG audit-block** in `uUseAfterFree.pas` (73-line CFG-dump that
  wrote `sca-cfg-debug.log`) removed — leftover from hardening sprint.

**Diagnostics:**
- **scan.log Phase-Tracking** — outer handler in `ParseLeaks` now records
  the last successful phase + current file before any uncaught exception
  is re-raised. Replaces "Analyseabbruch: ..." mystery findings with a clear
  trail (`=== ABBRUCH: EXClass: msg / letzte Phase: X / aktuelles File: Y`).
- **scan.log skip-log** — files/directories skipped by ignore-list,
  default-exclude (`__history`/`Win32`) or symlink detection now appear in
  `StaticCodeAnalyser_scan.log` with a clear reason. Previously a black box.

**Configuration:**
- `[Detectors] MaxLineLength=N` (default 120) for `uTooLongLine`.
- `[Detectors] MaxCaseBranches=N` (default 10) for `uCaseStatementSize`.

### 2026-06-08 — DFM Resource-Wrapper Support + Stack-Hardening v3/v4

**Critical:**
- **DFM Resource-Wrapper format `$FF $0A $00`** is now supported. GExperts
  and JVCL ship binary DFMs in the `$FF $0A $00 [ResName] [pad] TPF0 ...`
  wrapper layout — previously these were silently misinterpreted as text
  and produced 0 DFM-findings. GExperts: 0 → 1.084 DFM-findings;
  JVCL DFM-findings doubled on real-world scans.
- **AST `Destroy` reentrancy double-free** (Hardening v4 follow-up): the
  iterative `TAstNode.Destroy` collected descendants into `AllDesc` and
  freed them, but each `Cur.Free` re-entered the same destructor and
  re-freed nodes via its own DFS. Manifested as `EInvalidPointer` in
  `gAstFileCache.Evict` after the first file in a scan.

**Performance:**
- **`uFixHint` Memoize-Cache** keyed by `(Kind, Severity)` — the IDE plugin's
  `HighlightAllFindingsInFile` called `FixHint()` per finding, allocating
  ~3 KB of UI-hint strings each. On a 165k-finding scan that crossed the
  Win32 user-space limit and produced `EOutOfMemory`. Cache has ≤166 unique
  slots; downstream `Entries[]`-arrays share ref-counted strings.

**Detector UI Hints:**
- Added `fkUninitVar` and `fkUnusedSuppression` to `uFixHint` (Before/After
  code snippets). 165/165 kinds now have UI-hint coverage.



13 commits since v0.9.7 (released 2026-06-01). Phase 1 of
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) is complete
(6/6 quick-wins); Phase 4 has begun with the A.3-Minimal cross-unit
visibility check. A subsequent multi-persona review hardened the code
on Security, Performance, and API dimensions.

Full release notes: [docs/releases/v0.9.8.md](docs/releases/v0.9.8.md)
([deutsch](docs/releases/v0.9.8_de.md)).

### Added

- **`--time-detectors` CLI flag** — emits a Markdown table with per-detector
  cumulative wall-time and call count after a scan. Drives data-based
  optimisation choices.
- **Test-fixture auto-detection** (`uDetectorUtils.IsTestFixturePath`) —
  filters findings from `uTest*.pas` / `*Sample.pas` / `*Demo.pas`,
  test/samples/demos/resources directories and known fixture files. Auto-on
  for `default` and `selftest-quiet` profiles, off for `strict`. Manual
  overrides via `--hide-test-fixtures` / `--show-test-fixtures`.
- **SCA165 `UnusedSuppression`** — emits a hint when a `// noinspection X`
  marker did not suppress any finding (detector improved → marker obsolete).
- **SCA166 `UninitVar` (MVP)** — local variable read before being
  assigned. Conservative single-method-scope detector
  ([`uUninitVar.pas`](StaticCodeAnalyserForm/sources/Detectors/uUninitVar.pas))
  with three-class call model (READ_ALLOWLIST: `WriteLn`/`Length`/…,
  WRITE_ALLOWLIST: `ReadLn`/`FillChar`/…, UNKNOWN-calls: pessimistic-
  write). Method-boundary scan + `_`-prefix + managed-type skip + hard
  caps against pathological methods. Full path-sensitivity (if-else
  sibling-write, CFG, symbol table) deferred to Phase 2-4 per
  [`Konzept_SCA166_UninitVar.md`](Konzept_SCA166_UninitVar.md).
  Closes the long-standing DETECTORS.md slot #16 (UninitVar) with a
  conservative MVP; slot stays `🟡 partial` until full flow analysis.
- **Golden-corpus regression tests** in `tests/golden-corpus/fp-reproducers/`
  — 5 historical FP reproducer `.pas` files (one per Round-1..13 fix) plus
  `expected.json` and `tools/check-golden-corpus.ps1` PowerShell runner.
- **SARIF `partialFingerprints.contextHash/v1`** — SHA256 over a
  whitespace-normalised ±3-line snippet around the finding. Stable against
  re-indent, line drift and method renames (when method header lies outside
  the radius). Survives baseline diffs that the legacy fingerprint would
  miss.
- **Baseline matches via `contextHash` OR legacy fingerprint** — old
  baselines remain valid; new ones survive small refactors.
- **`KindDefaultConfidence` in `uSCAConsts`** — ~35 heuristic /
  metric-based / DFM-schema kinds tagged as `fcMedium`. `TLeakFinding.SetKind`
  applies the default automatically. `--min-confidence high` now blends
  out heuristic findings without losing structural-bug coverage.
  Audit table: [docs/ConfidenceAudit.md](docs/ConfidenceAudit.md).
- **`TLeakFinding.SetKind(K, AConfidence)`** overload — explicit
  Confidence-passing instead of the order-fragile post-`SetKind` overwrite.
  `uCommandInjection` migrated.
- **A.3-Minimal: `gSymbolRefIndex` reactivated** for `fkUnusedPublicMember`
  (SCA052) — cross-unit caller lookup, no more dead-public-API false
  positives for symbols actually called via `obj.Method(args)`. Audit shows
  44% of known cross-unit methods now correctly recognised; remaining 56%
  documented as A.3+ follow-up (nkRef + class-function-call index limits).

### Changed

- **`gFileTextCache` lives through the post-scan phase** — Suppression,
  ContextHash and SARIF/baseline output reuse the warm cache instead of
  re-reading every file. Eliminates ~191k redundant `LoadFromFile` +
  UTF-8 validations per real-world scan.
- **`TFileTextCache` is now mtime-aware** — stale cache entries are
  invalidated on next `GetLines` if the file's `FileAge` no longer matches.
- **`uSuppression.BuildMap` / `BuildMarkers` use `AcquireLines`** — second
  call for the same file is a cache hit instead of a duplicate read.
- **`uSuppression.ApplyToFindings` split** into three methods
  (`ApplyToFindings` orchestrator + `RemoveSuppressedFindings` +
  `EmitUnusedSuppressionFindings`).
- **`uVisibilityCheck`** caches `AllUnitMethods` (`FindAll(nkMethod)`)
  and memoises `DescendantsOf(ClassLow)` once per `AnalyzeUnit` — previously
  re-walked the tree per public member, costing up to `O(members × methods)`.
- **`uFindingFingerprint.Normalize`** extracted inner whitespace-collapse
  into `CollapseWhitespace(Line, Sb)` and reuses a single TStringBuilder
  per call instead of allocating per snippet line.
- **`TryLoadLinesWithFallback` in `uFileTextCache`** — single source of
  truth for the 3-step encoding fallback (default → UTF-8 → Unicode).
  Removed duplicate in `uSuppression`.

### Security

- **`// noinspection All` excludes security-critical kinds**
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). These must be
  named explicitly. Prevents a single `All` marker from hiding a backdoor.
- **`ParseMarkerLine` routes through `TDetectorUtils.ScanCodeLine`** —
  string-/block-comment-context-aware. A marker inside a string literal
  (`Log('// noinspection All // ' + Payload);`) is no longer treated as
  active. Scan state is carried per file across lines.
- **`IsTestFixturePath` repo-root-anchored** — optional `BaseDir` parameter
  matches path components only inside the scan root. Stops external paths
  like `D:\projects\company-tests\src\auth.pas` from being silently filtered.
- **Baseline JSON hardened** with `MAX_BASELINE_ENTRIES = 1_000_000`
  and `MAX_FINGERPRINT_LEN = 256`. Mitigates OOM attacks via tampered
  baseline files. Warning to `ErrOutput` on truncation.

### Fixed

- **`gDetectorTimings` moved to INTERFACE section** of `uStaticAnalyzer2`
  — was unit-private so `uConsoleRunner` could not see it; `--time-detectors`
  built but never wrote the report.
- **Latent memory leak in `gAstFileCache` + `gFileTextCache`** on repeated
  scans (IDE plugin re-runs) — caches are now freed before re-create.
- **`uVisibilityCheck` `OwnUnit` path mismatch** — `ExtractFileName`
  compared "name.pas" against full-path entries in `gSymbolRefIndex`, so
  self-references were always counted as external. Now passes full path.
- **`Baseline.Apply` skips `ContextHash` computation** when the loaded
  baseline contains no `contextHash` entries (legacy file). Saves
  ~191k SHA256 + file-read operations on legacy baselines.

### Documentation

- New: [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) —
  4-axis quality roadmap (Precision / Recall / Tooling / Architecture)
  with 4 prioritised phases.
- New: [`docs/ConfidenceAudit.md`](docs/ConfidenceAudit.md) — per-kind
  default-confidence table with justifications.
- New: [`tests/golden-corpus/README.md`](tests/golden-corpus/README.md) —
  FP-regression-test workflow + how to add new reproducers.
- Updated: A.3 entry in `Konzept_ScannerQualitaet.md` marks the minimal
  step done and documents the 3 index limitations (nkRef, class-function-
  call, bare-call) as A.3+ follow-up.

---

## [0.9.3] - 2026-05-27

Polish release. No new detectors (count stays at 161). Focus on
IDE-plugin theme reliability in docked-mode, file encoding correctness,
and annotation-overlay usability.

Full release notes: [docs/releases/v0.9.3.md](docs/releases/v0.9.3.md)
([deutsch](docs/releases/v0.9.3_de.md)).

### Added

- IDE-plugin splash-screen entry + About-Box registration via standard
  ToolsAPI splash/about services.
- Visible 1 px per-tile border in the Sonar stats row, theme-aware via
  `ActiveStyleServices.GetSystemColor(clBtnShadow)`.
- `Konzept_DockedThemeRefresh.md` documenting the docked-mode theme
  diagnostic trail and the combined fix.
- `Konzept_ProjektAufteilung.md` outlining the planned project split
  (Engine / SharedUI / Standalone+CLI / IDE-Plugin / Tests).
- Regression test `StringEqualityWithFloatVarNameElsewhere_NotReported`
  for the FloatEquality string-compare false-positive.

### Changed

- **IDE-plugin theme apply pipeline** rewritten as a per-Descendant
  5-step walker (`ApplyTheme` → preserve `StyleElements - [seClient]`
  → resolve `Color`/`Font.Color` to concrete RGB → bind `StyleName` to
  the IDE style → `Invalidate` / grid `Repaint`). Fixes docked-mode
  theme refresh on tiles, toolbar panels, help-panel caption, memos.
- **`uIDETheme.TIDEThemeImpl.ApplyRecursive`** split into four named
  helpers: `ApplyStyleHookPreserveSeClient`, `ResolveDescendantColors`,
  `BindToIdeStyle`, `TriggerRepaint`.
- **`uFileTextCache.LoadFileSmart`** does three-stage encoding
  detection (BOM-sniff → strict-UTF-8 validation → Windows-1252
  fallback). Replaces the lenient `LoadFromFile(file, TEncoding.UTF8)`
  pattern that silently substituted invalid bytes.
- **Multi-finding annotation overlay** keeps each finding's
  description in an indented bullet list (was title-only summary).
  Fix-hint still suppressed for multi-mark.
- **`IDE_SEPARATOR`** color changed from `cl3DDkShadow` to
  `clBtnShadow` — visible in Dark themes (the old value collapsed
  onto `clBtnFace`).
- **`STATS_PANEL_HEIGHT`** 51 → 53 (Sonar stats row 2 px taller).
- **`FTileScore`** caption shortened from "Code Quality" to "Quality"
  (tile label + tooltip title; status-bar score line keeps the long
  form).
- **IDE-plugin toolbar** reduced from 4 rows to 3 (Path /
  Filter+Search / Stats); less-used actions moved into a hamburger
  menu.
- **`EngineSCA/`** folder renamed to `SCA.Engine/`.

### Fixed

- **Docked-mode IDE-theme refresh** affected only the grid; tiles,
  toolbar, help-panel caption and memos stayed in the previous theme.
- **`uFileTextCache`** silently produced mojibake on ANSI files with
  German umlauts in the unit header (`TEncoding.UTF8` decoded invalid
  bytes to U+FFFD instead of falling back to Windows-1252).
- **FloatEquality detector** reported `aValue = ''` (string compare)
  as a float-equality bug when another function in the same file had
  `aValue: Double` as a parameter. Stripped string content now uses
  `~` as marker so the regex can't bridge across an empty literal.
- **Theme-switch second-pass bug** — concrete RGB values were written
  back after first apply, so the next theme switch had no
  `clSystemColor` bit to resolve. Per-control original-color cache
  (`FOrigColors`) preserves the original identifier.

### Performance

- **~80× faster IDE theme switch** via cold/warm Apply split
  (per-Descendant `ApplyTheme` only on first apply; subsequent switches
  reuse registered style hooks). Full switch dropped from ~2 s of
  broadcast repaints to under ~25 ms.

---

## [0.9.2] - 2026-05-22

mORMot-cluster + Sonar-50 expansion + standalone progress +
i18n completeness. Detector count grows from 59 to **161 kinds**
(across ~130 detector classes — `uVisibilityCheck` emits 4 kinds,
`uDfmAnalysisRunner` emits 22).

Full release notes: [docs/releases/v0.9.2.md](docs/releases/v0.9.2.md)
([deutsch](docs/releases/v0.9.2_de.md)).

### Added

- **9 mORMot-cluster detectors** (SCA153-161): UnpairedLock,
  MoveSizeOfPointer, WithMultipleTargets, GetMemWithoutFreeMem,
  SetLengthAppendInLoop, PointerArithmeticOnString, EmptyOnHandler,
  StringFromPointer, PointerSubtraction.
- **SCA138-152 Sonar-50 expansion** filling Maintainability +
  Code-Smell slots: GodClass, FreeWithoutNil, MultipleExit,
  LargeClass, UnsortedUses, MissingUnitHeader, FloatEquality,
  ExceptInDestructor, BooleanParam, UnusedPrivateMethod,
  CanBeClassMethod, MissingOverride, BoolAlwaysTrue, ConstantReturn,
  HardcodedString.
- **Standalone GUI**: progress bar, Cancel button, MAX_SCAN_FILES
  scan-runaway protection (was IDE-only).
- **IDE-plugin keyboard shortcuts** are user-configurable (cnpack-
  style: press key combo, store in INI). Master toggle to disable all
  shortcuts. Settings dialog scrollable.

### Changed

- **Translation completeness: 161 / 161** finding-hint descriptions
  covered in both DE translation stores (GDeMap + i18n/de.po), all 82
  combo-labels translated.

---

## [0.9.1] - 2026-05-16

SonarQube-Integration release. Production-ready external-issues push
to SonarQube / SonarCloud, plus a major rule-catalog expansion and a
severity single-source refactor. Detector count grows from 41 to **59**
(21 Pascal + 20 DFM + 18 newer Pascal / visibility / SQL / format
detectors).

Full release notes: [docs/releases/v0.9.1.md](docs/releases/v0.9.1.md)
([deutsch](docs/releases/v0.9.1_de.md)).

### Added

#### SonarQube integration (Phase 0 + A + B + C + D per `todo-sonar.md`)

- **`uSonarConfig`** — 4-source config resolver (CLI > Env >
  `sonar-project.properties` > User-INI), DPAPI-encrypted token storage
  on Windows (plaintext+Base64 fallback on non-Windows for CI), each
  field tracks its source for diagnostics.
- **Health-check** — `--sonar-test` runs DNS → `/api/system/status` →
  token validation → project access in stages, renders an ASCII
  checklist. 403 disambiguation via `/api/components/show` distinguishes
  "project not found" from "no Browse permission".
- **Generic Issue Format export** — new unit `uExportSonarGeneric`,
  CLI flag `--sonar-export <file>`. Emits MQR fields
  (`cleanCodeAttribute` + `impacts`) per rule from the catalog; falls
  back to legacy `type` when the catalog isn't loaded so Sonar always
  accepts the JSON.
- **Project-template** — `--sonar-init` writes a `sonar-project.properties`
  template into the project root (or `.sample` if one exists).
- **IDE plugin Tools > Options > "Sonar Integration"** page
  ([uIDESonarOptions](StaticCodeAnalyserIDE/uIDESonarOptions.pas)) —
  Host / Project / Token / Branch / Insecure-TLS toggle, "Test
  Connection" button runs the same multi-stage check as the CLI,
  "Detect from project" reads `sonar-project.properties` of the active
  IDE project, token storage via DPAPI.
- **Send-to-Sonar context menus** in the findings list — bulk export
  (all findings, mirrors `--sonar-export`) plus per-issue export to
  `<repo>\.sonar\external\<severity>-<file>-L<line>-<hash>.json` for
  `sonar.externalIssuesReportPaths` pickup.
- **Pull-mode engine** `uSonarPull` — `GET /api/issues/search`, 5-min
  LRU cache, dedup-matcher for SCA-kind ↔ Sonar-rule name overlap.
  (UI binding into the findings grid deferred to a later release.)
- **PowerShell push helpers** under
  [StaticCodeAnalyserForm/scripts/](StaticCodeAnalyserForm/scripts/):
  `sonar-scan.ps1` (analysis + JSON), `sonar-upload.ps1` (DPAPI-decrypt
  + scanner) with `-DryRun` and `-DisableDelphi` switches for the
  SonarDelphi/communitydelphi sensor-crash case.

#### Rule-Catalog: 22 → 59 rules

- 37 new rule entries documented in [rules/sca-rules.json](rules/sca-rules.json)
  with full metadata (Name, ShortDescription, FullDescription, examples,
  tags, CWE, OWASP, configKey, detectorUnit). All 20 DFM detectors plus
  18 newer Pascal/visibility/SQL/format detectors: `ConcatToFormat`,
  `WithStatement`, `ReversedForRange`, `SelfAssignment`,
  `VirtualCallInCtor`, `LengthUnderflow`, `CanBePrivate`,
  `CanBeProtected`, `UnusedPublicMember`, `UnusedLocalVar`,
  `UnusedParameter`, `TautologicalBoolExpr`, `DfmMasterDetailUnlinked`,
  `DfmDataModuleSplitHint`, `SqlDangerousStatement`, `FormatLocaleHint`,
  `CustomRule`.
- **MQR mapping** per rule — `cleanCodeAttribute` (14-value taxonomy)
  + `impacts` (`softwareQuality` × `severity`) populated for all 59
  rules. Schema [rules/sca-rules.schema.json](rules/sca-rules.schema.json)
  extended; catalog version bumped 1.1 → 1.3.
- **Regenerated [docs/rules.md](docs/rules.md)** with the full 59-rule
  table and per-rule sections.

#### Detector quality

- `--sonar-export` plus `--sonar-test` plus `--sonar-init` plus seven
  per-flag overrides (`--sonar-host`, `--sonar-token`,
  `--sonar-project`, `--sonar-branch`, `--sonar-insecure`,
  `--sonar-config`).
- New drift tests `JsonSeverityMatchesKindMeta`,
  `EveryFindingKindHasRichMetadata`, `EveryFindingKindHasMqrMapping`
  in `uTestRuleCatalog` plus the full `uTestSonarConfig` and
  `uTestExportSonarGeneric` test fixtures.

### Changed

- **Severity is now single-source via `TLeakFinding.SetKind(K)`**
  ([uMethodd12](StaticCodeAnalyserForm/sources/Common/uMethodd12.pas)) —
  the new method sets Kind + pulls Severity from `KIND_META`. 58
  detector emit sites refactored from the two-line
  `F.Severity := lsXxx; F.Kind := fkXxx;` pattern; three detectors
  with context-dependent severity (`uLeakDetector2`, `uDivByZero`,
  `uCustomRuleDetector`) keep their manual assignment.
  `TFindingKindMeta.DefaultSeverity` is the new SOT in `KIND_META`.
- **Catalog lookup** ([uRuleCatalog.FindJsonFile](StaticCodeAnalyserForm/sources/Common/uRuleCatalog.pas))
  walks up to **8 directory levels** from the EXE/BPL dir (was 3) —
  fixes catalog-not-found from deep test runners and arbitrary scan
  working directories.
- **INI handling** — `TIniFile` → `TMemIniFile` in `uSonarConfig` and
  `uIDESonarOptions` so UTF-8-BOM files (Notepad default) parse
  correctly. `StoreToken` calls `Ini.UpdateFile` to persist.

### Fixed

- **Severity-drift** — `fkNilDeref` was emitting `lsError`, catalog
  said Warning → now Warning. `fkUnusedUses` was emitting `lsWarning`,
  catalog said Hint → now Hint. No existing test asserted the wrong
  values; SARIF export was already using the catalog values.
- **IDE plugin theme adoption** — Tools>Options frames now call
  `IOTAIDEThemingServices.ApplyTheme` in `FrameCreated` so they
  respect the active IDE theme (was falling back to VCL-default white).
  Shared one-shot helper `ApplyIDETheme` in
  [uIDEThemeIntegration](StaticCodeAnalyserIDE/uIDEThemeIntegration.pas).
- **IDE plugin Options page i18n** — `GetArea` returns empty string
  (was `'Third Party'`) so the page lands under the localized
  "Fremdhersteller" / "Third Party" node instead of creating a second
  English-named root.
- **Options-page layout** — Frame total height fits the 520-px IDE
  pane (Connectivity-Memo no longer clipped at the bottom), labels
  use `AutoSize=False` to stay DPI-stable, DPAPI help label uses 8pt
  in a non-clipped 40-px box, memo background `clWindow` not `clBtnFace`.
- **Build** — `.dpr` contains-list updated with the new Sonar units
  (Standalone EXE refused to compile without it), `.dfm` resource
  added for `TSonarOptionsFrame` (VCL streaming needs it even for
  programmatically built frames), operator-precedence fix in
  `Pos(...)>0`-or-chains.
- **Health-check** — DNS-only stage no longer hangs, 403 case shows
  whether the project is missing or the token lacks Browse.

### Docs

- New: [sonarHowto.md](sonarHowto.md) + [sonarHowto_de.md](sonarHowto_de.md)
  (standalone-only walkthrough), [docs/sonar-setup.md](docs/sonar-setup.md)
  (full guide), [docs/sonar-config.md](docs/sonar-config.md) (resolver
  reference), [StaticCodeAnalyserForm/scripts/README.md](StaticCodeAnalyserForm/scripts/README.md)
  + `README_de.md` (scripts reference with troubleshooting table).
- All Sonar-relevant READMEs gained a "Tested with: SonarQube Community
  Build 26.5+, sits alongside Sonar Way" compatibility block.

---

## [0.9.0] - 2026-05-14

Workflow-focused release: Silent-Mode (single-file analysis from the
editor right-click + `Ctrl+Alt+A` hotkey), Rule-Set Profiles
(`ide-fast`/`default`/`strict`/`security`/`bugs-only`/`code-quality`/
`dfm-only`), Tools>Options page in the IDE, multi-file marker
storage, IDE-overlay polish, 10 new Pascal detectors with i18n, and
UI parity between Standalone form and IDE plugin.

Full release notes: [docs/releases/v0.9.0.md](docs/releases/v0.9.0.md)
([deutsch](docs/releases/v0.9.0_de.md)).

This entry retroactively documents the `v0.9.0` tag (created
2026-05-14) which was not landed in the changelog at release time.

---

## [0.8.0] - 2026-05-12

Big tagged release bundling four years of structural work: **DFM
scanner with 20 form-file detectors**, **headless CLI mode**,
**rule catalog**, **SARIF v2.1.0 export**, **IDE plugin polish**,
and **Win64 readiness** for the standalone EXE.

Detector count grows from 21 to **41 total** (21 Pascal + 20 DFM).

### Added

#### DFM scanner

- **20 DFM detectors** across six clusters (Dead-Wiring, Data-Access,
  Security, Layering, UI/UX, Naming). Each comes with a before/after
  fix hint and DUnitX tests. See [DETECTORS.md](DETECTORS.md).
- **DFM parsing infrastructure**: own lexer (`uDfmLexer`), parser
  (`uDfmParser`), component graph (`uComponentGraph`), plus
  binary-DFM reader (`uDfmBinaryReader`) for TPF0-prefixed files
  that used to be silently skipped.
- **Typed property accessors** on `TPropValue` + `TComponentNode`
  (`GetBoolean / GetInteger / GetString / GetIdent /
  SetPropertyContains`), default-aware to mirror VCL serialisation
  semantics.
- **FormBinder** (`uFormBinder`) couples DFM graph to Pascal AST.
  `BindWithParents` walks the class inheritance chain so detectors
  see inherited members.
- **Repo-wide form index** (`TDfmRepoIndex`) for cross-unit lookups:
  "which class lives in which `.pas`", "which form owns this
  datasource".
- **Frame resolver** (`uDfmFrameResolver`) loads a frame's
  components on demand for cross-frame analyses.
- **`.dfm`-aware VCS diff**: branch changes on a `.dfm` queue the
  companion `.pas` for analysis (and vice versa).
- **HTML report** groups `.pas` + `.dfm` with the same basename
  under one dropdown entry.
- **IDE plugin — DFM finding opens DFM as text** in the Code
  Editor via the Close-and-Reopen pattern (DFMCheck/GExperts-
  style). When the companion `.pas` is modified, falls back to
  opening the `.pas` with a status-bar hint that Alt+F12 toggles
  to the DFM source. Return enum `TOpenFileMode`
  (`ofmRegular` / `ofmDfmAsText` / `ofmDfmFallbackPas`) drives the
  status text.
- **Standalone EXE — modal DFM text viewer** on double-click.
- **Smarter double-click on DFM findings** in the standalone grid.
- **WatchMode** now triggers re-analysis on `.dfm` saves and edits
  (companion-aware: `.dfm`-as-text changes are mapped to the
  watched `.pas`).
- **Demo resources** under `resources/`:
  - `uOrderForm.{pas,dfm}`: `TADOQuery` + `TFields` + `TDBEdit`
    chain with intentional smells.
  - `uCustomerForm.{pas,dfm}`: `TFDQuery` → `TDataSetProvider` →
    `TClientDataSet` → `TDataSource`.

#### Headless CLI + Rule Catalog + SARIF

- **Headless CLI mode** (`{$APPTYPE CONSOLE}` dispatch) —
  `analyser.d12.exe --path X --full|--branch|--file Y
  --report-sarif sca.sarif` runs the same engine as the IDE plugin
  without RAD Studio. Exit-code mapping
  (0 clean / 1 hints / 2 warnings / 3 errors / 4 read errors /
  99 tool error) drops into CI pipelines and pre-commit hooks.
- **Rule catalog** (`rules/sca-rules.json`) — single source of
  truth for all 22 Pascal-AST detector rules (`SCA001`–`SCA022`)
  with stable IDs, severity, type, tags, CWE, OWASP refs, fix
  examples. Loader `uRuleCatalog` + JSON schema for editor
  autocomplete and CI validation.
- **SARIF v2.1.0 export** — natively consumed by GitHub Code
  Scanning, Azure DevOps, VS Code, SonarCloud. Findings appear as
  PR inline annotations; `partialFingerprints` deduplicate across
  commits.
- **GitHub Actions workflow template** in
  `.github/workflows/sca.yml` — `sca` (full project on push/PR,
  SARIF upload) + `sca-pr-changes` (branch diff, fail-on-error
  for PRs).
- **`docs/rules.md`** consolidated Markdown rule reference,
  referenced by SARIF `helpUri`.

#### IDE plugin polish

- **Three-tier responsive layout** for the docked window
  (Narrow/Medium/Full breakpoints at 500/700 px).
- **Hamburger menu** absorbs all toolbar actions in narrow mode.
- **Single-file live watch** (📄 Current file) — Save 300 ms /
  Edit 1000 ms debounced background re-analysis.
- **Hover-hint overlay** for finding lines, multi-line wrap.
- **Sonar-style stat tiles** above the grid.
- **Theme tracking** via `IOTAIDEThemingServices` +
  `INTAIDEThemingServicesNotifier` notifier.

#### Other

- **Standalone EXE compiles cleanly for Win64** —
  `analyser.d12.dproj` lists `Win32 + Win64` in its `<Platforms>`
  block. No code changes required for a 64-bit build.

### Changed

- `uIDEEditorIntegration.OpenFileAtLine` returns `TOpenFileMode`
  instead of `Boolean`. Third-party callers (unlikely outside this
  repo) need to update.
- `SafeCloseModule` uses `CloseModule(True)` (save-if-dirty)
  unconditionally — the `Modified` flag is unreliable in Delphi 12
  immediately after `OpenFile` and was blocking Close-and-Reopen.
- README + README-de rewritten to highlight 41 detectors + DFM
  scanner; added "Related projects and alternatives" and SEO
  "Keywords" / "Schlagwörter" sections.
- Toolbar buttons (`☰` hamburger, `...` browse) now sit flush
  against the right panel edge (removed 6 px right padding).

### Fixed

- `TEditSource Refcount = 2` error during IDE destroy after rapid
  DFM↔PAS click sequences. Cause: implicit interface references
  kept the source alive past IDE-internal destroy ordering. Fix:
  explicit `:= nil` on the `IOTAModule` reference in
  `SafeCloseModule`.
- DFM-finding line off-by-one in the standalone modal viewer.
- `TDictionary<string, Cardinal>` var-parameter type mismatch in
  `uExportHtml` (inline-var was inferred as `Integer`).
- `Classes.ObjectBinaryToText` qualifier dropped — `System.Classes`
  doesn't expose a `Classes`-only alias on Delphi 12; unqualified
  call resolves correctly through the `uses` chain.
- **Win64 readiness**: `uDfmTextViewer.StartPos` is now `LRESULT`
  with an explicit `Integer(...)` cast at the `SelStart` assignment
  site — eliminates `W1057 implicit truncation` warning on Win64
  builds.

---

## [0.7.2] - 2026-02-15

### Added

- Hover-overlay description as multi-line wrap text.

### Changed

- IDE plugin docked layout: hamburger menu fully absorbs all
  actions in narrow mode.

---

## [0.7.1] - 2026-01-20

### Added

- IDE hover-hint overlay on finding lines.

### Fixed

- IDE plugin: first docking reliably switches into compact layout.
- Three detectors received false-positive reduction work.

### Changed

- Central three-tier responsive layout for the IDE plugin.
- FormatMismatch fixes.

---

## [0.7.0] - 2025-12-15

### Added

- Docked-mode UI: two breakpoints (700/400) with sub-panel width
  shrinking; hamburger menu; SearchEdit shrinks in docked mode.
- DPI scaling + extracted layout constants.

---

## [0.6.x and earlier]

Initial release stream — Sonar-style classification, 21 Pascal
detectors, Git+SVN branch-changes mode, dxgettext localisation,
HTML/CSV/JSON export, Claude AI prompt copy, theme-aware
rendering. See `git log` for granular history before the changelog
was introduced.

---

## Conventions

- **MAJOR.MINOR.PATCH** follows SemVer for the public API of the
  IDE plugin (BPL exports) and the standalone CLI (flags + exit
  codes). Detector additions are **MINOR** bumps; behaviour or
  signature changes that break either are **MAJOR**.
- The pre-1.0 line is still allowed to break public surface in
  MINOR bumps when the change is necessary — every such case is
  called out under **Changed** with a migration note.
- Each entry is grouped under **Added / Changed / Fixed / Removed
  / Deprecated / Security** so a reader can scan one section.
- Dates are absolute (`YYYY-MM-DD`) so relative phrasing like
  "last week" doesn't drift.
