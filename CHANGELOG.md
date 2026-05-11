# Changelog

All notable changes to this project are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
