# Changelog

All notable changes to this project are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.10.0] - 2026-05-11

The "DFM scanner" release: detector count grows from 21 to **41
total** (21 Pascal + 20 DFM), plus full IDE-side support for working
on DFM findings as text in the Code Editor.

### Added

- **DFM scanner with 20 dedicated detectors** across six clusters
  (Dead-Wiring, Data-Access, Security, Master-Detail, UI/UX,
  Localization). Each comes with a before/after fix hint and DUnitX
  tests. See [DETECTORS.md](DETECTORS.md).
- **DFM parsing infrastructure**: own DFM lexer, DFM parser, and
  component graph (`uDfmLexer`, `uDfmParser`, `uDfmComponentGraph`).
- **DFM analysis pipeline**: runner, FormBinder (couples Pascal AST
  to DFM graph), repo-wide form index (`TDfmRepoIndex`), and
  DB-field helper for SQL-from-property detection.
- **Cross-unit form index** so detectors can answer questions like
  "is this published event referenced anywhere in the repo?" and
  "which form owns this datasource?".
- **`.dfm`-aware VCS diff**: when `.dfm` is touched in the branch,
  the companion `.pas` is queued for analysis automatically (and
  vice versa).
- **HTML report**: file dropdown groups `.pas` and `.dfm` with the
  same basename under one heading; severity badges filter both
  views consistently.
- **IDE plugin — DFM finding opens DFM as text** in the Code Editor
  via the Close-and-Reopen pattern (DFMCheck/GExperts-style). When
  the companion `.pas` is modified, falls back to opening the
  `.pas` and showing a status-bar hint that Alt+F12 toggles to the
  DFM source. New return enum `TOpenFileMode`
  (`ofmRegular` / `ofmDfmAsText` / `ofmDfmFallbackPas`) so the
  status bar can describe what happened.
- **Standalone EXE — modal DFM text viewer** on double-click: opens
  the form file as text with the finding line highlighted and the
  caret pre-positioned (EM_LINEINDEX).
- **Smarter double-click on DFM findings** in the standalone grid:
  routes `.dfm` to the modal viewer, `.pas` via ShellExecute as
  before.
- **Stat-tile readability bump**: tile fonts grow +1pt (Icon, Count
  11→12; Caption 6→7).
- **Demo resources** for trying the DFM scanner:
  - `uOrderForm.pas` + `.dfm`: `TADOQuery` + `TFields` + `TDBEdit`s
    with intentional smells.
  - `uCustomerForm.pas` + `.dfm`: `TFDQuery` → `TDataSetProvider`
    → `TClientDataSet` → `TDataSource` chain.

### Changed

- `uIDEEditorIntegration.OpenFileAtLine` now returns
  `TOpenFileMode`; callers can describe the result in the status
  bar. Old `Boolean` return is gone — bump the version of any
  third-party caller (unlikely outside this repo).
- `SafeCloseModule` uses `CloseModule(True)` (save-if-dirty)
  unconditionally — the Modified flag is unreliable in Delphi 12
  directly after `OpenFile` and blocked the Close-and-Reopen trick.
- README + README-de tagline rewritten to highlight the **41
  detectors total** + DFM scanner feature surface; added a
  "Related projects and alternatives" section and a "Keywords"
  block for discoverability.

### Fixed

- `TEditSource Refcount = 2` error during IDE destroy after
  rapid DFM→PAS click sequences. Cause: implicit interface
  references kept the source alive past IDE-internal destroy
  ordering. Fix: explicit `:= nil` on the `IOTAModule` reference
  in `SafeCloseModule`.
- DFM-finding line off-by-one in the standalone modal viewer.
- `TDictionary<string, Cardinal>` var-parameter type mismatch in
  `uExportHtml` (inline-var was inferred as `Integer`).

---

## [0.9.0] - 2026-03-15

### Added

- **SARIF report** (`--report-sarif`) for GitHub Code Scanning,
  GitLab CI, Azure DevOps, and other SARIF-aware CI/CD systems.
  Findings show up as inline annotations in PR diffs.
- **Custom-rule engine** with YAML profiles (`analyser-rules.yml`)
  loadable per project. Profiles in `examples/` for common
  starting points.
- **Rule Catalog** — all detectors expose machine-readable
  metadata (id, severity, category, fix hint).

---

## [0.8.0] - 2026-02-04

### Added

- **Headless CLI mode**: `analyser.d12.exe --path X --full|--branch
  --report-sarif Y` runs the same engine as the IDE plugin without
  RAD Studio, for use in CI pipelines and pre-commit hooks.
- **Exit-code mapping**: 0 clean / 1 hints / 2 warnings /
  3 errors — drop-in for hook scripts.

---

## [0.7.1] - 2026-01-20

### Added

- **IDE hover-hint overlay** on finding lines.
- **Hover-overlay description** as multiline wrap text.

### Fixed

- IDE plugin: first docking now reliably switches into compact
  layout.
- Three detectors received false-positive reduction work.

### Changed

- Central three-tier responsive layout for the IDE plugin.
- FormatMismatch fixes.

---

## [0.7.0] - 2025-12-XX

### Added

- **Docked-mode UI**: two breakpoints (700/400) with sub-panel
  width shrinking; Hamburger menu absorbs all actions; SearchEdit
  shrinks in docked mode.
- **DPI scaling** + extracted layout constants.

---

## [0.6.x and earlier]

Initial release stream — Sonar-style classification, 21 Pascal
detectors, Git+SVN branch-changes mode, dxgettext localisation,
HTML/CSV/JSON export, Claude AI prompt copy, theme-aware rendering.
See `git log` for granular history before the changelog was
introduced.

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
