# Static Code Analysis Tool for Delphi

A static code analyser for Delphi 12, packaged as an IDE expert with a
dockable tool window. It catches memory leaks, code smells, security
risks, and UI smells right inside the IDE — and produces an AI-ready
fix prompt at the click of a row.

🇩🇪 [Deutsche Version](README_de.md)

![Static Code Analysis Tool for Delphi inside the Delphi IDE dock](docs/APP.png)

---

## What this plugin does

In one sentence: **Sonar-style analysis for Delphi projects, with no
Sonar setup required, running inside the IDE, with a Claude AI hand-off.**

| Capability | Details |
|------------|---------|
| 🐛 **Bug detection** | 21 detectors run against every `.pas` file (MemoryLeak, NilDeref, DivByZero, FormatMismatch, …) |
| 🔐 **Security checks** | SQLInjection (score-based), HardcodedSecret, HardcodedPath |
| 🧹 **Code smells** | LongMethod, MagicNumber, EmptyExcept, MissingFinally, DeadCode, DuplicateString/Block |
| ⚡ **Incremental analysis** | "Branch-Changes" button: only the files modified in the Git/SVN branch — 200 ms instead of 60 s |
| 🤖 **Claude AI prompt** | Click a finding → a complete Markdown block with code context + before/after is copied to the clipboard |
| 📊 **Sonar-style dashboard** | Stat tiles above the grid: Errors / Warnings / Hints / Bugs / Vulnerabilities / Code Quality score |
| 🎯 **Filter & sort** | Severity dropdown, type dropdown, live search box, clickable column headers |
| 📤 **Export** | CSV, JSON, self-contained HTML report, Jira wiki markup, plain-text clipboard with before/after |
| 🔇 **Suppression** | `// noinspection MemoryLeak` per line, plus `ignore.txt` for whole files |
| 🌓 **Theme aware** | Follows the active IDE theme automatically (Light / Dark / Mountain Mist / Carbon) |
| 💡 **Before/after help** | Every detector has a paired "wrong way / right way" code example in the help panel |

---

## Main features

### 1. Static code analysis (21 detectors, Sonar taxonomy)

Catches **bugs** (MemoryLeak, NilDeref, DivByZero, FormatMismatch),
**vulnerabilities** (SQLInjection, HardcodedSecret), **security hotspots**
(HardcodedPath), **code smells** (LongMethod, MagicNumber, DeadCode,
EmptyExcept, MissingFinally, …), and **code duplication** (DuplicateString,
DuplicateBlock). Every finding ships with a before/after fix in the help
panel.

### 2. Incremental VCS-aware analysis (Git + SVN)

Skip the full project scan. **One click on `Branch-Changes`** is enough:
the analyser asks `git diff` (or `svn status`) for the `.pas` files
touched in your branch and runs the detectors only on those.
**~200 ms instead of 60 s** for a typical feature branch — cheap enough
to use as a pre-commit gate. Configuration lives in `repo.ini`. Full
details in [BRANCH_CHANGES.md](BRANCH_CHANGES.md).

### 3. AI hand-off (Claude prompt with one click)

Click a finding row in the grid and the clipboard is filled with a
**ready-made Markdown prompt**: finding metadata, code context (±5
lines, with a marker on the offending line), and the before/after fix.
Paste it into Claude with **Ctrl+V** — the AI now has everything it
needs to suggest a concrete patch.

---

## Quick start

1. **Build and install** the plugin: open `StaticCodeAnalyserIDE\StaticCodeAnalyserIDE.dpk`,
   run **Build**, then **Install** (right-click the package in Project
   Manager → **Install**, or use **Component → Install Packages** from
   the menu and pick the package). Without the install step the plugin
   compiles but never appears in the IDE menu.
2. In Delphi: **View → Static Code Analysis Tool for Delphi** — the
   dockable window shows up.
3. Pick a project path → click **Start analysis**.

For incremental scans of branch-changed files only, see
[BRANCH_CHANGES.md](BRANCH_CHANGES.md).

---

## What is detected (21 detectors)

Findings fall into one of **five Sonar categories**:

| Category | Detector | Severity |
|----------|----------|----------|
| **Bug** | `MemoryLeak` (LeakDetector + FieldLeak) | Error / Warning |
| | `NilDeref` (nil dereference) | Error |
| | `DivByZero` (division by zero) | Error / Warning |
| | `FormatMismatch` (format vs argument count) | Error |
| **Vulnerability** | `SQLInjection` (score-based) | Error |
| | `HardcodedSecret` (API keys, passwords) | Error |
| **Security Hotspot** | `HardcodedPath` (`C:\…`, `/etc/…`) | Warning |
| **Code Smell** | `EmptyExcept` (silent swallow) | Warning |
| | `MissingFinally` (Free outside finally) | Warning |
| | `DeadCode` (unreachable after exit/raise) | Warning |
| | `UnusedUses` (optional, default off) | Hint |
| | `LongMethod`, `LongParamList` | Hint |
| | `MagicNumber` (in if conditions) | Hint |
| | `DebugOutput` (`OutputDebugString` etc.) | Warning |
| | `DeepNesting` | Warning |
| | `TodoComment` (TODO/FIXME/HACK) | Hint |
| | `EmptyMethod` | Hint |
| **Code Duplication** | `DuplicateString` (same literal, ≥3 occurrences) | Hint |
| | `DuplicateBlock` (≥8 identical lines) | Hint |
| **Read error** | `FileReadError` (parser hang or oversized file) | Error |

Every detector comes with a **before/after code example** in the help
panel. Clicking a finding copies a **Markdown block ready for Claude AI**
to the clipboard.

Full status of all 50 Sonar rules: see [DETECTORS.md](DETECTORS.md).

---

## Usage

### Buttons (left to right)

| Button | Function |
|--------|----------|
| **Folder picker** (`...`) | Choose the project folder |
| **Repo...** | Open `repo.ini` — VCS settings (see [BRANCH_CHANGES.md](BRANCH_CHANGES.md)) |
| **Ignore...** | Open `ignore.txt` — file/folder exclusion list |
| **Start analysis** | Recursive folder scan |
| **Current file** | Just the `.pas` file currently open in the editor |
| **Branch-Changes** | Only files changed in Git/SVN (see [BRANCH_CHANGES.md](BRANCH_CHANGES.md)) |
| **Cancel** | Aborts a running analysis |

### Checkboxes

| Checkbox | Effect |
|----------|--------|
| `with uses check` | Enables the `UnusedUses` detector (off by default; can produce false positives) |
| `Include tests` | Includes `uTest*.pas`, `*_Tests.pas`, `TestProject.dpr`, and `/tests/` directories (off by default) |

### Stat cards

Two card rows above the grid show how findings are distributed:

- **By severity**: Errors / Warnings / Hints / Security risks / Read errors
- **By type**: Code Smell / Bug / Vulnerability / Security Hotspot / Code Duplication / Read errors

Both rows are guaranteed to add up to the same total.

### Filter

- **Severity / type dropdowns**: narrow the grid down to a single category.
- **Search box** (`Filter file / method / finding`): live filter across
  every column.

### Grid interaction

| Action | Effect |
|--------|--------|
| **Click a row** | Finding is copied to the clipboard as a Markdown prompt for Claude AI |
| **Double-click** | Open the file in the IDE and jump to the finding line |
| **Hover** | Tooltip with the full file path |
| **Click a column header** | Sort by that column |
| **3 px stripe on the left edge** | Severity accent (red / orange / green / blue) |

### Export

| Button | Format | Content |
|--------|--------|---------|
| **JSON** | `.json` | All findings as an array |
| **CSV** | `.csv` | Excel-friendly (semicolon-separated) |
| **HTML report** | `.html` | Self-contained report with sort, filter, code snippets, before/after |
| **Jira** | Clipboard | Wiki markup ready to paste into a Jira ticket (filtered to one file) |
| **Clipboard** | Clipboard | Plain text with before/after (filtered to one file) |

---

## Theme integration

The plugin tracks the active Delphi IDE theme through several
mechanisms:

- **`StyleServices.GetSystemColor`** in custom drawing (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace` / `clWindow` / `clBtnText`** as property values (auto-themed via VCL Styles)
- **`IOTAIDEThemingServices.ApplyTheme`** when the frame is hosted
- **`INTAIDEThemingServicesNotifier`** for live theme changes
- **`CM_STYLECHANGED`** plus a **`SetParent` override** as additional triggers

Severity background colors are blended at paint time from the themed
`clWindow` base mixed with a saturated accent color, so the same code
works in any theme without separate light/dark tables.

**Known limitation**: in floating mode the plugin window does not pick
up runtime IDE theme changes reliably — `INTACustomDockableForm` exposes
no official hook for re-applying the theme on the wrapper form.
Workaround: dock the plugin, or close and re-open the window after
switching themes.

---

## Configuration files

All under `%APPDATA%\StaticCodeAnalyser\`:

| File | Content |
|------|---------|
| `ignore.txt` | File and directory patterns to skip during analysis |
| `repo.ini` | VCS settings (BaseBranch, git/svn paths) — see [BRANCH_CHANGES.md](BRANCH_CHANGES.md) |
| `recent.ini` | Recently used project paths |
| `StaticCodeAnalyser_scan.log` | Diagnostic log: which file took how long |

---

## Suppression

Silence individual findings inline:

```pascal
// noinspection MemoryLeak
list := TStringList.Create;

// noinspection NilDeref, DivByZero
DoSomethingRisky;

// noinspection All
// suppress every check on the next line
```

Recognised category names: `MemoryLeak`, `EmptyExcept`, `SQLInjection`,
`HardcodedSecret`, `FormatMismatch`, `UnusedUses`, `NilDeref`,
`MissingFinally`, `DivByZero`, `DeadCode`, `LongMethod`, `LongParamList`,
`MagicNumber`, `DuplicateString`, `HardcodedPath`, `DebugOutput`,
`DeepNesting`, `All`.

---

## Ownership transfer (no MemoryLeak warning)

These patterns are recognised as ownership hand-off and don't trigger a
MemoryLeak finding:

| Pattern | Meaning |
|---------|---------|
| `Result := varName` | Function returns ownership to its caller |
| `inherited Create(varName, …)` | Parent constructor takes ownership |
| `TAnyClass.Create(varName, …)` | Another constructor takes ownership |
| `Container.Add(varName)` | TObjectList (etc.) takes ownership |
| `Container.Add(key, varName)` | TObjectDictionary takes ownership |
| `Container.AddObject(text, varName)` | TStringList with objects |
| `Container.Insert(i, varName)` | TList.Insert |
| `Container.Push(varName)` | TStack.Push |
| `Container.Enqueue(varName)` | TQueue.Enqueue |

---

## Architecture

```
StaticCodeAnalyserIDE/                 IDE expert package (.dpk)
  uIDEExpert.pas                       Wizard registration (IOTAMenuWizard)
  uIDEAnalyserForm.pas                 Dockable window (TFrame)
                                       Filters, stats, export, Branch-Changes,
                                       Claude prompt generator, theme notifier

StaticCodeAnalyserForm/sources/        Analysis engine (shared by standalone + IDE plugin)
  uAnalyserPalette.pas                 Central colour constants (severity, accents, icons)
  uAnalyserTypes.pas                   TFindingSeverity enum + conversions
  uAnalyserTheme.pas                   SeverityBg, SeverityAccent, BlendColor

  uLexer.pas, uParser2.pas             Tokeniser + recursive-descent parser,
                                       watchdog (200k-token limit) and
                                       forward-progress guarantees
  uAstNode.pas                         AST with FindAll / FindFirst lookup
  uStaticAnalyzer2.pas                 Orchestrates the 21 detectors per file
  uStaticFiles.pas                     Recursive file scan with tick callback,
                                       cancel support, symlink protection
  uIgnoreList.pas                      ignore.txt + test filter
  uVcsChanges.pas                      Git/SVN diff via CreateProcess + pipe
  uRepoSettings.pas                    repo.ini (BaseBranch, exe paths)
  uSuppression.pas                     // noinspection markers
  uExport.pas                          JSON / CSV / HTML / Jira / clipboard
  uFixHint.pas                         Before/after example per finding type
  uClaudePrompt.pas                    Markdown prompt generator

  uLeakDetector2.pas                   MemoryLeak (AST-based)
  uFieldLeak.pas                       Class-field leak (Create / Destroy)
  uCodeSmells2.pas                     EmptyExcept
  uSQLInjection.pas, uSQLInjectionScore.pas
  uHardcodedSecret.pas, uHardcodedPath.pas
  uFormatMismatch.pas, uUnusedUses.pas
  uNilDeref.pas, uMissingFinally.pas
  uDivByZero.pas, uDeadCode.pas
  uLongMethod.pas, uLongParamList.pas
  uMagicNumbers.pas, uDuplicateString.pas
  uDuplicateBlock.pas
  uDebugOutput.pas, uDeepNesting.pas
  uTodoComment.pas, uEmptyMethod.pas
```

### Data flow

```
File → Lexer → Parser2 → AST (TAstNode)
                            │
                            ├── 21 detectors run in parallel (try/except per detector)
                            │       each emits TLeakFinding
                            │
                            └── TSuppression strips noinspection markers
                                        │
                                        └── TObjectList<TLeakFinding>
                                                │
                                                └── PopulateFindings →
                                                    Stat cards + grid + export
```

---

## Performance

For a typical 1 000-unit repository:

| Phase | Per file | 1 000 files |
|-------|----------|-------------|
| Folder scan | — | 1–3 s |
| Lexer | ~5–15 ms | ~10 s |
| Parser2 | ~10–50 ms | ~30 s |
| 21 detectors | ~5–30 ms | ~20 s |
| Suppression sweep | — | <1 s |
| **Total** | **~30–100 ms** | **~60–90 s** |

For incremental re-scans, **use Branch-Changes instead of a full scan**
— typically 200 ms to 3 s. See [BRANCH_CHANGES.md](BRANCH_CHANGES.md).

### Robustness

- **Watchdog**: 200k-token limit per file — pathological inputs are
  aborted in under a second instead of hanging.
- **GuardAdvance**: forward-progress guarantee in every outer parser loop.
- **MAX_FILE_BYTES = 5 MB**: oversized files are reported immediately as
  `FileError`.
- **MAX_DEPTH = 32**: protection against symlink loops.
- **Cancel any time**: `EAbort` propagates cleanly through every layer.
- **Per-detector try/except**: a crashing detector never blocks the
  other twenty.

---

## Test projects

```
StaticCodeAnalyserForm/tests/
  TestProject.dpr                      DUnitX console runner
  uTestAnalyserChecks.pas              ~290 tests in 26 fixtures
                                       (one fixture per detector)
  uTestTAstNode.pas                    AST helper tests
  uTestPerformance.pas                 Throughput benchmarks
                                       (tokens/ms, lines/ms)
```

Tests run on DUnitX. In console mode the test project emits an NUnit
XML report — ready to wire into CI.

---

## Requirements

- Delphi 12 (Athens)
- DUnitX (only for the test suite, not for the plugin itself)
- Optional: Git for Windows or TortoiseSVN **with** CLI tools for the
  Branch-Changes feature

---

## Component overview

| Component | Path | Purpose |
|-----------|------|---------|
| **Standalone EXE** | `StaticCodeAnalyserForm/analyser.d12.dproj` | Folder/file scan outside the IDE |
| **IDE plugin** | `StaticCodeAnalyserIDE/StaticCodeAnalyserIDE.dpk` | Main feature — dockable tool window with the full feature set |

Both share the analysis engine in `StaticCodeAnalyserForm/sources/`.

---

## Documentation

The repository contains three Markdown documents per language. They
complement each other, so each one stands on its own:

| File | Content | When to consult |
|------|---------|-----------------|
| [README.md](README.md) | **Overview** — what the plugin does, how to use it, architecture, performance, suppression, theme integration | Default starting point for everything except the two specialised topics below |
| [DETECTORS.md](DETECTORS.md) | **Canonical detector list** — all 50 Sonar rules plus 3 bonus detectors with status (✅ implemented / 🟡 partial / 🔲 open), description and the responsible unit | When you want to know which rule is implemented, what exactly it checks, or which detector is up next |
| [BRANCH_CHANGES.md](BRANCH_CHANGES.md) | **VCS / Branch-Changes feature** — how the `Branch-Changes` button works, Git/SVN setup, Tortoise compatibility, `repo.ini` configuration, troubleshooting for repo detection | When the Branch-Changes button isn't doing what you expect, or you want to fine-tune the VCS setup |

Convention: `README.md` is broad; the other two are deep and focused on
one aspect. Whenever a section in the README grows too large, it gets
moved into its own dedicated file (which is exactly what happened with
the Branch-Changes content).

🇩🇪 German versions: [README_de.md](README_de.md), [DETECTORS_de.md](DETECTORS_de.md), [BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md)

---

## Support

If the plugin saves you time, a coffee is appreciated:

[![Donate via PayPal](https://img.shields.io/badge/PayPal-Donate-blue?logo=paypal&style=flat-square)](https://paypal.me/nrodear)

Direct link: <https://paypal.me/nrodear>
