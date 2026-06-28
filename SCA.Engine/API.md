# SCA.Engine — Engine & API

*🇬🇧 English — 🇩🇪 [Deutsch](API_de.md)*

Static code analysis for Delphi/Object Pascal as a reusable runtime package.
This document describes the **engine** (architecture, pipeline) and the **public
API** (`uEngineApi`) through which a consumer runs the complete analysis without
knowing the internal units.

> Runnable minimal example: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl;` — no VCL/FMX dependency)
- **Version:** 0.9.8 (`uSCAConsts.SCA_VERSION`)
- **Scope:** ~174 detectors (rule IDs `SCA001`–`SCA183`)

---

## 1. Architecture

The engine is a pure analysis library with no UI. Data flow of a scan:

```
  .pas / .dfm
      │
      ▼
  Lexer (uLexer)  ──►  Parser (uParser2)  ──►  AST (uAstNode)
                                                   │
                              ┌────────────────────┤
                              ▼                    ▼
                       AST detectors        Line/token detectors
                       (~174 rules, one uXxx.pas each)
                              │
                              ▼
                     TLeakFinding list
                              │
   ┌──────────────────────────┼───────────────────────────────┐
   ▼                          ▼                                 ▼
 Suppression            Confidence filter                  Baseline
 (uSuppression:         (uConfidenceFilter:                (uBaseline:
  // noinspection)       MinConfidence)                     known findings)
   └──────────────────────────┼───────────────────────────────┘
                              ▼
                         TScanResult
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
             SARIF          Sonar          HTML
        (uExportSARIF) (uExportSonar…) (uExportHtml)
```

Cross-cutting infrastructure:

- **`uAnalyzeContext`** — holds the per-scan caches (AST cache, symbol reference
  index, DFM repo index). Passed through the detectors; no per-scan global state.
- **`uStaticFiles`** — recursive file collection with default exclusions
  (`__history`, `__recovery`, `.git`, `.svn`, `node_modules`) + ignore/test
  filter (`uIgnoreList`).
- **`uRuleCatalog`** — rule metadata (ID, title, severity, type) + profiles.
- **`uRepoSettings`** — `analyser.ini` configuration (thresholds, profiles, path
  overrides, custom rules).

---

## 2. Quick start

A recursive scan in one line:

```pascal
uses uEngineApi;

var Res: TScanResult;
begin
  Res := ScanRecursive('C:\myproject');   // all detectors, default limits
  try
    WriteLn('Findings: ', Res.FindingCount,
            '  (errors ', Res.ErrorCount,
            ', warnings ', Res.WarningCount,
            ', hints ', Res.HintCount, ')');
  finally
    Res.Free;   // also frees the findings list
  end;
end;
```

A complete, runnable example is the **`SCA.CLI.Demo`** project.

---

## 3. The API: `uEngineApi`

The facade consists of a request record, a result object, a session class and
two convenience functions.

### 3.1 Entry points

| Call | Purpose |
|------|---------|
| `ScanRecursive(APath, AProfile=''): TScanResult` | Recursive directory scan (one-liner). |
| `AnalyzeSource(ASource, AProfile=''): TScanResult` | In-memory scan of a source-code string (editor lint/embedding). |
| `TAnalysisSession.Create.Run(Req): TScanResult` | Full access via `TScanRequest` (all options). |

### 3.2 `TScanRequest`

Fill via `TScanRequest.Init` with sensible defaults (`ssRecursive`, all
detectors, loosest thresholds), then override selectively.

| Field | Type | Meaning |
|-------|------|---------|
| `Scope` | `TScanScope` | Scan kind (see 3.5). Default `ssRecursive`. |
| `Path` | `string` | Root (recursive) / file (single) / base dir (list). |
| `Files` | `TArray<string>` | Explicit file list for `ssFileList`. |
| `Source` | `string` | In-memory source for `ssSource`. |
| `VcsRange` | `string` | `ssVcsChanged`: `''`=auto, else `shaA..shaB`. |
| `Profile` | `string` | `''`=all detectors, else profile name (see 3.6). |
| `MinSeverity` | `TLeakSeverity` | Findings below this threshold are discarded. |
| `MinConfidence` | `TFindingConfidence` | FP threshold (default `fcMedium`). |
| `MaxFileBytes` | `Integer` | `<=0` → engine default (5 MB). |
| `UsesCheck` | `Boolean` | Run the expensive unused-uses detector. |
| `AutoDiscover` | `Boolean` | Discover custom classes during the scan. |
| `IfdefDefines` | `TArray<string>` | `{$IFDEF}`-aware parsing with these defines. |
| `CustomRulesPath` | `string` | YAML with custom rules (`''`=none). |
| `BaselinePath` | `string` | Filter findings against a baseline JSON (`''`=off). |
| `WriteBaselinePath` | `string` | Write current findings as a new baseline. |
| `ApplyRepoIni` | `Boolean` | Load + fully apply `analyser.ini` (like the CLI). |
| `MinSeverityName` | `string` | INI mode: override `'error'`/`'warning'`/`'hint'`. |
| `ConfigRoot` | `string` | INI mode: root for INI/rules resolution. |
| `SkipConfig` | `Boolean` | `true`: apply no config (consumer has set state itself). |
| `SingleFileProjectRoot` | `string` | `ssSingleFile`: project root for the cross-unit index. |
| `IgnoreList` | `TIgnoreList` | `ssRecursive`: ignore/test filter (`nil`=none). |
| `Progress` | `TProc<Integer,Integer>` | `(current,total)`; `EAbort` inside aborts. |

### 3.3 `TScanResult`

Owns the findings list; release with `.Free` (also frees the findings, except
after `ReleaseFindings`).

```pascal
TScanResult = class
  function FindingCount: Integer;     // total
  function ErrorCount:   Integer;     // severity lsError
  function WarningCount: Integer;     // severity lsWarning
  function HintCount:    Integer;     // severity lsHint
  property Findings: TObjectList<TLeakFinding>;   // detail access
  property BaseDir:  string;                       // scan root

  function ReleaseFindings: TObjectList<TLeakFinding>;  // give up ownership

  procedure WriteSarif(const AFileName: string;
                       const AToolName: string = SCA_DEFAULT_TOOLNAME);
  procedure WriteSonar(const AFileName: string);
  procedure WriteHtml (const AFileName: string);
end;
```

### 3.4 Configuration modes

`TAnalysisSession.Run` decides where the detector configuration comes from based
on the request:

1. **Direct (default):** only the request's fields (`Profile`, `MinSeverity`,
   `MinConfidence`, `MaxFileBytes`, `IfdefDefines`, `CustomRulesPath`). No
   `analyser.ini`. → this is what `ScanRecursive`/`AnalyzeSource` do.
2. **`ApplyRepoIni := True`:** loads `analyser.ini` (from `ConfigRoot`/`Path`) and
   applies it fully — 8 thresholds, path overrides, magic/format lists, INI
   profile + INI custom rules. This is how the CLI runs.
3. **`SkipConfig := True`:** `Run` applies **no** config — the consumer has
   already set the global detector/threshold state itself (this is what the IDE
   plugin and the Form do via their own preparation). `Run` then only does
   scope → scan → baseline.

### 3.5 Scopes (`TScanScope`)

| Value | Description |
|-------|-------------|
| `ssRecursive` | Directory recursively (default). Uses `Path` + optional `IgnoreList`. |
| `ssSingleFile` | A single `.pas` file (`Path`); with `SingleFileProjectRoot` a project-wide symbol index. |
| `ssFileList` | Explicit file list (`Files`); `Path` = optional base dir. |
| `ssVcsChanged` | Only VCS-changed files (`Path`=repo, `VcsRange` optional). |
| `ssSource` | In-memory source (`Source`); `Path`=optional logical name. |

### 3.6 Profiles

A profile is a whitelist of finding kinds. `''` (empty) = **all** detectors.
Built-in profiles (`uRuleCatalog`):

| Profile | Content |
|---------|---------|
| `default` / `strict` | All rules. |
| `ide-fast` | Fast subset for live analysis (bugs + vulnerabilities + critical DFM). |
| `security` | Vulnerabilities/secrets only (SQLInjection, HardcodedSecret, …). |
| `bugs-only` | Real bugs only (leaks, NilDeref, DivByZero, FormatMismatch, …). |
| `code-quality` | Code smells (LongMethod, MagicNumber, Cyclomatic, duplicates, …). |
| `dfm-only` | DFM/form rules only. |

### 3.7 Data model: `TLeakFinding` (`uMethodd12`)

Each finding:

| Member | Type / return | Meaning |
|--------|---------------|---------|
| `FileName` | `string` | Source file. |
| `MethodName` | `string` | Method/routine (if known). |
| `LineNumber` / `LineInt` | `string` / `Integer` | Line (string field + integer helper). |
| `MissingVar` / `Message` | `string` | Detail message (`Message` = alias). |
| `Severity` | `TLeakSeverity` | `lsError` / `lsWarning` / `lsHint`. |
| `Kind` | `TFindingKind` | Concrete rule kind (`fkXxx`). |
| `Confidence` | `TFindingConfidence` | `fcLow` / `fcMedium` / `fcHigh`. |
| `RuleID` | `string` | Custom rule ID (else empty). |
| `FindingType` | `TFindingType` | Category (see below). |
| `SeverityText` / `TypeText` | `string` | Readable labels. |
| `ResolvedRuleId` | `string` | `SCAxxx` (RuleID if set, else catalog lookup). |

Enums (`uSCAConsts`):

```pascal
TLeakSeverity     = (lsError, lsWarning, lsHint);
TFindingConfidence= (fcLow, fcMedium, fcHigh);
TFindingType      = (ftBug, ftCodeSmell, ftVulnerability,
                     ftSecurityHotspot, ftCodeDuplication, ftFileError);
```

---

## 4. Lifecycle / threading

- The engine is **not thread-safe** (shared global config/cache state). One scan
  at a time per process.
- The **recursive scan** is safe for short-lived single-scan processes
  (CLI/demo). In resident hosts (IDE) prefer the single-file/source path.
- `TScanResult` owns the findings; `Free` releases them. With `ReleaseFindings`
  ownership passes to the caller.

---

## 5. Referencing the package (consumer setup)

A third-party consumer needs **only the package**, no engine source:

- `.dproj`: `UsePackages=true` and `DCC_UsePackage` contains `SCA.Engine;rtl`.
- **No** engine source directory in `DCC_UnitSearchPath`.
- At runtime `SCA.Engine.bpl` must be findable (global BPL directory or next to
  the `.exe`).
- `uses uEngineApi;` (+ `uMethodd12`, `uSCAConsts` for detail access) — all from
  the package.

Complete example incl. `.dpr`/`.dproj`: **`SCA.CLI.Demo`**.

---

## 6. Examples

**Profile + SARIF export:**

```pascal
var Res := ScanRecursive('C:\src', 'security');
try
  Res.WriteSarif('report.sarif');
finally
  Res.Free;
end;
```

**Full request (INI mode, baseline, progress):**

```pascal
var Req := TScanRequest.Init;
Req.Path          := 'C:\src';
Req.ApplyRepoIni  := True;            // apply analyser.ini fully
Req.BaselinePath  := 'baseline.json'; // hide known findings
Req.Progress      := procedure(C, T: Integer)
                     begin Write(#13, C, '/', T); end;

var Ses := TAnalysisSession.Create;
try
  var Res := Ses.Run(Req);
  try
    Res.WriteSonar('sonar.json');
  finally
    Res.Free;
  end;
finally
  Ses.Free;
end;
```

**In-memory (editor lint):**

```pascal
var Res := AnalyzeSource(EditorBuffer.Text);
try
  for var F in Res.Findings do
    WriteLn(F.LineInt, ': [', F.ResolvedRuleId, '] ', F.Message);
finally
  Res.Free;
end;
```

---

## 7. Exit-code convention (CLI/tools)

Standalone tools typically use: `0` = clean, `3` = findings present, `1`/`2` =
error (exception / invalid path). See `SCA.CLI.Demo`.
