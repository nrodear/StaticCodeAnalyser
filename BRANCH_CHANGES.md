# Static Code Analysis Tool for Delphi

Sonar-inspired static code analyser for Delphi / Object Pascal. Catches
memory leaks, code smells, security gaps and maintainability issues.

🇬🇧 English page · 🇩🇪 [Deutsche Version](BRANCH_CHANGES_de.md)

The repository ships two components:

| Component | Purpose | Path |
|-----------|---------|------|
| **Standalone EXE** | Stand-alone tool for scanning directories on disk | `StaticCodeAnalyserForm/` |
| **IDE plugin** | Dockable tool window inside the Delphi IDE | `StaticCodeAnalyserIDE/` |

---

## Features at a glance

- **21 active detectors** drawn from the Sonar rule catalogue — see [`DETECTORS.md`](DETECTORS.md)
- **Sonar-style stat tiles** above the grid: Errors / Warnings / Hints / Bugs / Code duplications / Code Quality score
- **Severity filter** + **type filter** (Bug, Code Smell, Vulnerability, Security Hotspot, Code Duplication)
- **Help panel on the right** with paired "before/after" code examples per finding
- **Claude AI prompt generator** — clicking a row copies a ready-made Markdown block to the clipboard
- **VCS branch mode** — analyses only the files changed in the branch (see below)
- **Suppression** through `// SCA: ignore` comments
- **Export** as CSV / JSON / Jira / HTML
- **Theme aware** — follows the active Delphi IDE theme (Light / Dark / Mountain Mist / Carbon)
- **Recent paths** persisted across sessions
- **Ignore list** at `%APPDATA%\StaticCodeAnalyser\ignore.txt`

---

## Components in detail

### 1. Standalone EXE — `analyser.d12.dpr`

A self-contained program built from `analyser.d12.dproj`. It offers:

- Recursive folder scan
- Single-file analysis
- CSV export
- Direct navigation to a finding line (opens the IDE and jumps to the line)

Build:

```
Open analyser.d12.dproj in Delphi 12  →  Project  →  Build
```

### 2. IDE plugin — `StaticCodeAnalyserIDE.dpk`

Designtime package providing the dockable tool window. Launched via
**Tools / Static Code Analysis Tool for Delphi** or **View / Static Code
Analysis Tool for Delphi**.

Functions on top of the standalone:

- **Current file** — analyses the source file currently open in the IDE
- **Branch-Changes** — analyses only files changed in the branch
- **Direct navigation** through IDE editor services (no WinAPI hack)
- Stat tile row with live counters
- Help panel with before/after snippets

Install:

```
Open StaticCodeAnalyserIDE.dproj  →  Project  →  Install
```

---

## Detectors

The full list with status (✅ implemented · 🟡 partial · 🔲 open) lives
in [`DETECTORS.md`](DETECTORS.md).

Current state: **18 complete + 1 partial + 3 bonus detectors = 21 active detectors**.

Highlights by severity:

| Severity | Examples |
|----------|----------|
| 🔴 **Blocker** | MemoryLeak, EmptyExcept, NilDeref, SQLInjection, HardcodedSecret |
| 🟠 **Critical** | DivByZero, MissingFinally, FormatMismatch, FieldLeak |
| 🟡 **Major** | LongMethod, LongParamList, DeepNesting, MagicNumber, DuplicateString |
| 🔵 **Minor** | UnusedUses, TodoComment, EmptyMethod, DeadCode |
| 🎁 **Bonus** | HardcodedPath, DebugOutput, DuplicateString |

---

## Branch-Changes mode

Skip the full project scan and analyse only the files that were touched
in the current branch — drastically faster (seconds instead of minutes),
ideal as a pre-commit gate.

### Quick start

1. Click the **`Branch-Changes`** button in the IDE plugin
2. The analyser walks up from `Project path` looking for `.git` or `.svn`
3. It fetches the list of changed `.pas` files
4. The detectors run only on those files; findings show up in the grid

### What gets included

**Git repositories** combine two sources:

```
git diff --name-only --diff-filter=ACMR <base>...HEAD   # committed branch diff
git status --porcelain                                  # uncommitted + untracked
```

`<base>` is auto-detected: `origin/HEAD` → `main` → `master`. Status
codes `A` / `C` / `M` / `R` are included; `D` (deleted) is skipped. For
renames only the destination path is analysed.

**SVN repositories** look at the working copy only:

```
svn status
```

Status codes `M` / `A` / `R` / `?` are included; `D` / `!` / `I` / `C`
are skipped.

### Requirements

The CLI tool must be reachable. Search order:

| VCS | Search order |
|-----|--------------|
| **Git** | `PATH` → `C:\Program Files\Git\bin\git.exe` → `C:\Program Files (x86)\Git\bin\git.exe` → `C:\Program Files\TortoiseGit\bin\git.exe` → `TortoiseGit\mingw64\bin\git.exe` |
| **SVN** | `PATH` → `C:\Program Files\TortoiseSVN\bin\svn.exe` → `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe` → `C:\Program Files\Subversion\bin\svn.exe` |

Recommended setups:

- **Git for Windows** ([git-scm.com](https://git-scm.com/download/win))
- **TortoiseSVN** with the *"command line client tools"* option enabled
  — without it `svn.exe` is not installed

### Tortoise compatibility

| Setup | Works? |
|-------|--------|
| **Git for Windows** alone, or together with TortoiseGit | ✅ via `PATH` |
| **TortoiseGit alone** without Git for Windows | ❌ TortoiseGit ships no own `git.exe`; a separate Git install is required |
| **TortoiseSVN with** "command line client tools" | ✅ found automatically in the TortoiseSVN bin directory |
| **TortoiseSVN without** "command line client tools" | ❌ clear error message — re-run the installer with the option enabled |

### Performance

| Mode | Typical time |
|------|--------------|
| Full directory scan | 60–90 s |
| Branch-Changes (5–30 .pas files) | 200 ms – 3 s |

---

## Theme handling

The IDE plugin tracks the active Delphi IDE theme through:

- **`StyleServices.GetSystemColor`** in custom drawing (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace` / `clWindow` / `clBtnText`** as property values (auto-themed)
- **`IOTAIDEThemingServices.ApplyTheme`** when the frame is hosted
- **`INTAIDEThemingServicesNotifier`** for live theme changes
- **`CM_STYLECHANGED`** plus a **`SetParent` override** as additional triggers

Architecture units:

| Unit | Content |
|------|---------|
| [`uAnalyserPalette.pas`](StaticCodeAnalyserForm/sources/uAnalyserPalette.pas) | Central colour constants (severity backgrounds, accents, icon colours) |
| [`uAnalyserTypes.pas`](StaticCodeAnalyserForm/sources/uAnalyserTypes.pas) | `TFindingSeverity` enum + conversions |
| [`uAnalyserTheme.pas`](StaticCodeAnalyserForm/sources/uAnalyserTheme.pas) | `SeverityBg`, `SeverityAccent`, `BlendColor` |

**Known limitation**: in floating mode the plugin window does not pick
up runtime IDE theme changes reliably. Workaround: dock the plugin, or
close and re-open the window after switching themes.

---

## Settings — `analyser.ini`

Click the **`Repo...`** button to open:

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

The file is created with default content on first launch. Changes are
re-loaded automatically on the next click of **`Branch-Changes`**.

```ini
[Repo]
; Comparison branch for "git diff <base>...HEAD".
; Empty = auto-detect (origin/HEAD -> main -> master).
; Examples: develop, release/2024.1, origin/main
BaseBranch=

; Include uncommitted working-tree changes?
; 1 = yes (default - typical for a pre-commit check)
; 0 = committed changes only
IncludeWorkingTree=1

[Paths]
; Full paths if git/svn are not on PATH and not at the standard
; Tortoise locations. Otherwise leave empty.
GitExe=
SvnExe=
```

### Common adjustments

| Scenario | Setting |
|----------|---------|
| Team uses `develop` as the default branch | `BaseBranch=develop` |
| Code-review committed changes only | `IncludeWorkingTree=0` |
| TortoiseGit at a custom path | `GitExe=D:\Tools\Git\bin\git.exe` |
| TortoiseSVN without CLI tools on PATH | `SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe` |

---

## Suppression

Suppress findings on a single line:

```pascal
x := 1 / y;  // SCA: ignore (DivByZero — y is validated upstream)
```

Skip whole files via `%APPDATA%\StaticCodeAnalyser\ignore.txt` — one
file (or path glob) per line.

---

## Troubleshooting

### "no Git/SVN repository in or above ..."

The analyser walks up from **`Project path`** looking for `.git` /
`.svn`. Make sure the path lives inside a repository and you didn't
accidentally pick a sub-path outside the repo root.

### "no base branch (main/master) found — working tree only"

Your repository has no default branch under the usual names. Set
`BaseBranch=` explicitly in `analyser.ini` (e.g. `develop`).

### Findings you expected aren't there

- **File extension**: only `.pas` files are analysed. `.dpr` / `.dpk`
  are not yet covered (extension is straightforward).
- **Submodules**: `git status` does not capture submodule-internal
  changes — scan the submodule folder separately.
- **Test filter**: tests are excluded by default. Tick the **`Include
  tests`** checkbox to include them.
- **Ignore list**: check `%APPDATA%\StaticCodeAnalyser\ignore.txt`.

### Paths with non-ASCII characters

The analyser uses the default code page when converting stdout. Paths
with special characters can suffer encoding glitches (the converted
path no longer exists). Workaround in `.gitconfig`:

```
[core]
    quotepath = false
```

This makes `git status --porcelain` emit UTF-8 instead of escaped
sequences.

---

## Build / install

| Target | Step |
|--------|------|
| Standalone EXE | Open `analyser.d12.dproj` → Project → Build |
| IDE plugin | Open `StaticCodeAnalyserIDE.dproj` → Project → Install |

Platform: **Win32** — designtime packages currently only run in the
32-bit IDE variant.

---

## Repository layout

```
StaticCodeAnalyser/
├── StaticCodeAnalyserForm/         # Standalone EXE + detector code
│   ├── sources/                    # Detectors, parser, theme helpers
│   ├── resources/                  # Pascal test files used by detector tests
│   ├── tests/                      # Unit tests
│   └── analyser.d12.dproj          # Standalone project
├── StaticCodeAnalyserIDE/          # IDE plugin (dockable)
│   ├── uIDEExpert.pas              # Tools menu wizard
│   ├── uIDEAnalyserForm.pas        # Frame + dockable form wrapper
│   └── StaticCodeAnalyserIDE.dpk   # Designtime package
├── docs/                           # Mockups, sketches, screenshots
└── DETECTORS.md                    # Full detector catalogue with status
```
