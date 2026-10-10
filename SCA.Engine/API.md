# SCA.Engine — Engine & API

*🇬🇧 English — 🇩🇪 [Deutsch](API_de.md) — 🇫🇷 [Français](API_fr.md)*

Static code analysis for Delphi/Object Pascal as a reusable runtime package.
This document describes the **engine** (architecture, pipeline) and the **public
API** (`uEngineApi`) through which a consumer runs the complete analysis without
knowing the internal units.

> Runnable minimal example: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl;` — no VCL/FMX dependency)
- **Version:** 0.9.14 (`uSCAConsts.SCA_VERSION`)
- **Scope:** ~196 detectors (rule IDs `SCA001`–`SCA196`)

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
                       (~178 rules, one uXxx.pas each)
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

### 3.8 Source places: `TSourcePlaces` (`uSourcePlaces`)

Describes places in a source file **on request** — for consumers that want to rewrite code (e.g. the "Source Refactor" module reDelphix). It only reads: no scan runs, no finding, field or export is touched, and no detector uses it. One instance per file.

`uEngineApi` re-exports the class and record types: `TSourcePlaces`, `TNodeRef`, `TSourceLineRange`, `TUsesSection`, `TNodeKind`, `TNodeKinds`, `TRefactorInfo`, `TRefactorSpan`. It does **not** re-export constants and enum values: the roles (`ROLE_*`), value types (`rv*`, `TRefactorValueType`) and flags (`rf*`, `TRefactorFlags`) need `uses uRefactorInfo`, the contract version `SOURCE_PLACES_VERSION` needs `uses uSourcePlaces`. Both units are in the package.

```pascal
Places := TSourcePlaces.Create;
try
  try
    Opened := Places.Open(FileName);    // False: file not readable
  except
    on E: Exception do
    begin
      Log(E.Message);                   // parser error, incl. the watchdog
      Opened := False;                  // nothing is open (IsOpen = False)
    end;
  end;
  if Opened then
  begin
    Nodes := Places.NodesAt(Line, [TNodeKind.nkAssign]);   // finding line -> AST nodes
    if Length(Nodes) = 1 then
    begin
      Info := Places.ChainOf(Nodes[0].Line, Nodes[0].Col, Nodes[0].Name);
      try
        if Assigned(Info) and Info.FixSafe then
          ...                                              // build the rewrite
      finally
        Info.Free;
      end;
    end;
  end;
finally
  Places.Free;
end;
```

| Member | Returns | Meaning |
|--------|---------|---------|
| `Open(FileName)` / `Close` | `Boolean` | Reads the file itself (no scan cache, no engine lock) and parses exactly the decoded text. `False` if unreadable. A parser error (incl. the parser watchdog) **raises**; the service is closed afterwards (`IsOpen = False`). Any previously opened text is discarded first. |
| `OpenSource(FileName, Source)` | `Boolean` | Like `Open`, but on a text the host passes in (IDE: the editor buffer with unsaved changes). `FileName` is only the name; the file is not read. `False` for an empty text; a parser error raises as with `Open`. |
| `SetIfdefDefines(Defines)` | | Lexer view of the next `Open`/`OpenSource`. The service always parses in its own view, never in the process-wide view a running scan sets from `TScanRequest.IfdefDefines`. `nil` or empty (default) = both branches of every `{$IFDEF}`; otherwise one branch with exactly these defines — a consumer that knows the view of the run (`TScanRequest.IfdefDefines`) then gets nodes and types from the same view as the findings. Exception: for a `dlFpc` run with a non-empty define list (also forced for `.lpi`/`.lpk`/`.lpg` projects) the scan adds `FPC` and `LCL` (`TAnalysisSession.ApplyIfdefView`), the service does not — the caller adds the two itself to get the view of the findings. The values are copied and stay set across `Close`. Limits of the both-branch view: `DeclaredTypeOf` returns the type of one of the branches (the last for parameters and locals, the first for fields and globals), and `NodesAt` may return nodes of both branches. Defines from include files are not evaluated. |
| `IsOpen` / `FileName` / `LineCount` | `Boolean` / `string` / `Integer` | State of the opened text. |
| `StatementAt(Line, Col)` | `TRefactorInfo` | The statement starting there: span with columns, flags, insert point, hash. `nil` if its end cannot be determined, also when a Delphi 12 multi-line string (`'''`) is in it. |
| `ChainOf(Line, Col, ExpectedTarget = '', ExpectedPlus = ANY_PLUS_COUNT)` | `TRefactorInfo` | Assignment with a `+` chain: target, literals, operands, `FixSafe`. Two cross-checks, each returning `nil` on a mismatch: the target against `ExpectedTarget` (use `TNodeRef.Name`; `''` = no check), and the number of top-level `+` against `ExpectedPlus`, counted independently by the consumer (e.g. from `TNodeRef.TypeRef`, the way SCA044 counts). Any negative value (`TSourcePlaces.ANY_PLUS_COUNT`) means no check. |
| `CallOf(Line, Col, ExpectedHead)` | `TRefactorInfo` | Call statement: head plus the chain of a single argument, otherwise one `argument` part per argument. `ExpectedHead` is the head before the first `(` (`''` = no check). |
| `NodesAt(Line, Kinds)` | `TArray<TNodeRef>` | AST nodes of the given kinds that start on that line, sorted by column. Two hits mean the line is ambiguous. |
| `UsesEntries(Section)` | `TArray<TRefactorSpan>` | Every unit name of the `uses` clauses with its span (`Resolved` = the name as written). `usAny` (default) also covers the clause of a program or library. |
| `IdentifiersIn(Span)` | `TArray<TRefactorSpan>` | Identifiers inside a span as `ident` parts; keywords are not filtered. Strings and comments are excluded — also when the span starts inside one, because the file is read up to the span. Limitation: a Delphi 12 multi-line string (`'''`) before the span is not recognised. |
| `CodeViewOf` / `TextOf` / `HashOf` | | Column-true code view, raw text and SHA-256 of a span, all on the text of the last `Open`/`OpenSource`. In the code view strings are `~` fill (`TRefactorInfoBuilder.VIEW_FILL`), while comments and compiler directives, delimiters included, are blanks. `HashOf` does not see a later change: to detect one, open the current text again and compare `HashOf(Info.Span)` with `Info.SpanHash`, or compare `TextOf(Span)` with the target buffer right before writing (reDelphix does the latter). |
| `ConditionalRanges` | `TArray<TSourceLineRange>` | `{$IFDEF}` ranges of the file. |
| `SectionLine(Section)` | `Integer` | Line of the `interface` / `implementation` keyword; `0` if the section is missing (program, library) and for `usAny`. |
| `LineText(Line)` | `string` | Text of one line of the opened text; `''` outside. |
| `SpanHasComment(Span)` | `Boolean` | `True` if the span contains a comment or a compiler directive — for a consumer that replaces only part of a statement (`rfHasComment` covers the whole statement). |
| `DeclaredTypeOf(Line, Name)` | `string` | Declared type (bare, lower case) of an identifier: parameter or local of the enclosing routine, else field or unit global; `''` if unknown. `string[N]` resolves to `'shortstring'`, not `'string'` (the detectors' type resolver keeps `'string'`). `Line` is the **anchor line** of a statement (the line of an AST node), not a continuation line. Knows no `with` blocks: it returns the declaration found even where the compiler binds the name to a member of the `with` expression. |
| `InWithBlock(Line)` | `Boolean` | `True` if the line lies in the body of a `with` statement (line-granular, from the `with` line to the last node line of its statement). Ask this before proving anything from `DeclaredTypeOf`. |
| `CollectNodesAt` / `CollectUsesEntries` / `CollectIdentifiers` | | Class functions: the same on a tree, line list or code view the caller already holds — for tests and consumers with their own AST. |

**`TNodeRef`** copies the node fields a consumer needs: `Kind`, `Line`, `Col`, `Name` (target or head as the parser joined it) and `TypeRef` (right-hand side or type reference, flattened). The tree itself belongs to the service and lives only until the next `Open`/`Close`.

**What `ChainOf` and `CallOf` prove.** An operand that is a bare identifier gets its declared type (`rvString`/`rvNonString`, `Resolved` = type name), and `FixSafe` is derived again. Unknown stays unknown: `rvUnknown` and `FixSafe = False` are the normal case. There is no `rvString` proof inside a `with` block (`InWithBlock`; `Resolved` still names the declaration found), and none for a known RTL call or a `.ToString` term whose name a function of the unit itself declares with a non-string result — that function shadows the RTL routine (e.g. a unit-local `function Trim(..): Variant`). Calls qualified with `SysUtils.`/`StrUtils.` keep their proof. A function declared in a nested routine is not seen (the parser drops nested routines).

Coordinates are 1-based; `EndCol` points **behind** the last character. Every primitive except `Open`/`OpenSource` is total (`nil`, empty, `0` or `False` instead of an exception, also when nothing is open). `SOURCE_PLACES_VERSION` (= 1) is the contract version — a **compile-time** constant: a consumer checks it with `{$IF SOURCE_PLACES_VERSION <> 1}{$MESSAGE ERROR '...'}{$IFEND}` (reDelphix does this in `uRdxRecipeRunner`) and then no longer builds against a changed contract. It cannot detect a BPL swapped at runtime; the package binding (DCP/`requires`) does that. The version rises with a change to the signature of an existing primitive, to roles, to coordinates, or to a `FixSafe`/`ValueType`/`Resolved` derivation that newly reports something as proven; it stays for new primitives, new parameters with a default value and derivations that only get stricter.

Per rule, `rules/sca-rules.json` may carry `anchor` (what the findings anchor on: `statement`, `assign`, `call`, `assign-or-call`; `uses-item` is reserved) and `fixMode` (`none` / `assisted` / `auto`); read them via `TRuleCatalog` (`TRuleMeta.Anchor`, `TRuleMeta.FixMode`). A missing or unknown value falls back to the compiled-in catalog; a rule is switched off with `"fixMode": "none"`.

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
- At runtime `SCA.Engine290.bpl` must be findable (global BPL directory or next to
  the `.exe`).
- `uses uEngineApi;` (+ `uMethodd12`, `uSCAConsts` for detail access;
  `uRefactorInfo`, `uSourcePlaces` for the constants of the source-places
  service, see 3.8) — all from the package.

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
