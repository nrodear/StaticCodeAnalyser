# SCA.CLI.Demo

*🇬🇧 English — 🇩🇪 [Deutsch](README_de.md) — 🇫🇷 [Français](README_fr.md) — Full engine/API reference: [../SCA.Engine/API.md](../SCA.Engine/API.md)*

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
| `IsKnownProfile(profile): Boolean` | Detects a mistyped profile name. |
| `KnownProfileNames: TArray<string>` | The known profiles, sorted, for the error message. |
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
   `SCA.Engine290.bpl` in the global DCP/BPL directory).
2. Open and build `SCA.CLI.Demo.dproj` (console EXE, Win32 or Win64).

Easiest: put both projects in one project group. The package linkage is via
`DCC_UsePackage SCA.Engine` (no source paths).

> At runtime `SCA.Engine290.bpl` and the Delphi runtime packages it requires
> (`rtl290.bpl`, `xmlrtl290.bpl`) must be findable (the global BPL directory is
> on the path with RAD Studio installed; for standalone deployment ship all
> three `.bpl` next to the `.exe`).

## Usage

```
SCA.CLI.Demo.exe [<path>] [<profile>]
```

| Argument | Meaning |
|----------|---------|
| `<path>`    | Root directory (default: current directory) |
| `<profile>` | optional. `''` = all detectors (default); SCA007 never, the demo does not set `UsesCheck`. Known: `default`, `strict`, `ide-fast`, `security`, `bugs-only`, `code-quality`, `style`, `dfm-only`, `selftest-quiet`. An unknown name is an error, as in the CLI: the demo lists the known profiles on stderr, does not scan and exits `2`. |

Exit code: the demo's own, simplified convention, **not** the CLI contract.

| Code | Demo |
|------|------|
| `0` | no findings |
| `3` | at least one finding of any severity; file errors count too (an empty folder yields "no .pas files" and so `3`) |
| `2` | call error: path not found or unknown profile |
| `1` | exception |

The CLI grades by severity instead (`1` hints only, `2` warnings, `3`
errors, `4` read errors, `99` tool error, which includes an unknown
profile) and `--fail-on` shifts that; see
`StaticCodeAnalyser.d12.exe --help`. Do not build a CI gate on the demo's
codes: its `2` means "call error", not "warnings".

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
