# SCA.CLI.Demo

*🇬🇧 English — 🇩🇪 [Deutsch](README_de.md) — Full engine/API reference: [../SCA.Engine/API.md](../SCA.Engine/API.md)*

Minimal example consumer of the **SCA engine API** (`uEngineApi`).

It demonstrates that the complete static analysis is usable through the public
facade **without knowing the engine's source code**: this project references the
runtime package **`SCA.Engine`** exclusively (`DCC_UsePackage`) — there is **no**
engine source directory on the search path.

The program scans a directory recursively and prints only a **metrics summary**.

## The API it uses

| API | Purpose |
|-----|---------|
| `ScanRecursive(path, profile): TScanResult` | One-line recursive scan. |
| `TScanResult.FindingCount / ErrorCount / WarningCount / HintCount` | Severity metrics. |
| `TScanResult.Findings` (`TObjectList<TLeakFinding>`) | Detail access. |
| `TLeakFinding.FindingType` / `.FileName` | Category breakdown + file count. |

That's the whole surface — a clean proof that the facade alone is enough. For
more control (profiles, MinSeverity, baseline, ignore list, SARIF/Sonar/HTML
export) there is `TScanRequest.Init` + `TAnalysisSession.Run` and
`TScanResult.WriteSarif/WriteSonar/WriteHtml` — see
[../SCA.Engine/API.md](../SCA.Engine/API.md).

## Building (RAD Studio / Delphi 12)

Order matters — the package must exist before the demo:

1. Build `SCA.Engine.dproj` for the target platform (produces `SCA.Engine.dcp` +
   `SCA.Engine.bpl` in the global DCP/BPL directory).
2. Open and build `SCA.CLI.Demo.dproj` (console EXE, Win32 or Win64).

Easiest: put both projects in one project group. The package linkage is via
`DCC_UsePackage SCA.Engine` (no source paths).

> At runtime `SCA.Engine.bpl` must be findable (the global BPL directory is on
> the path with RAD Studio installed; for standalone deployment ship the `.bpl`
> next to the `.exe`).

## Usage

```
SCA.CLI.Demo.exe [<path>] [<profile>]
```

| Argument | Meaning |
|----------|---------|
| `<path>`    | Root directory (default: current directory) |
| `<profile>` | optional. `''` = all detectors (default). Known: `default`, `strict`, `ide-fast`, `security`, `bugs-only`, `code-quality`, `dfm-only` |

Exit code (like the CLI): `0` = clean, `3` = findings present, `1`/`2` = error.

## Example output

```
========================================================
 SCA CLI Demo - Kennwert-Statistik
========================================================
  Pfad         : D:\myproject
  Profil       : (alle Detektoren)
  Dauer        : 1082 ms
  Dateien      : 174 (mit Funden)
--------------------------------------------------------
  Funde gesamt : 714

  Nach Schweregrad:
    Fehler  (Error)  : 0
    Warnung (Warning): 206
    Hinweis (Hint)   : 508

  Nach Kategorie:
    Bug              : 2
    Code Smell       : 705
    Vulnerability    : 0
    Security Hotspot : 0
    Duplication      : 7
    File Error       : 0
========================================================
```

*(The program output itself is German; the metric meanings are: Pfad=path,
Dauer=duration, Dateien=files with findings, Funde gesamt=total findings,
Nach Schweregrad=by severity [Fehler=error, Warnung=warning, Hinweis=hint],
Nach Kategorie=by category.)*
