# SCA.Engine — Engine & API

*🇬🇧 English — 🇩🇪 [Deutsch](API_de.md) — 🇫🇷 [Français](API_fr.md)*

Static code analysis for Delphi/Object Pascal as a reusable runtime package.
This document describes the **engine** (architecture, pipeline) and the **public
API** (`uEngineApi`) through which a consumer runs the complete analysis without
knowing the internal units.

> Runnable minimal example: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl, xmlrtl;` — `xmlrtl` reads `.dproj`/`.groupproj` for the project scopes; no VCL/FMX dependency)
- **Version:** 0.9.18 (`uSCAConsts.SCA_VERSION`)
- **Scope:** 205 rules (rule IDs `SCA001`–`SCA205`, `rules/sca-rules.json`)

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

The facade consists of a request record, a result object, a session class, a
test-fixture filter and two convenience functions.

### 3.1 Entry points

| Call | Purpose |
|------|---------|
| `ScanRecursive(APath, AProfile=''): TScanResult` | Recursive directory scan (one-liner). |
| `AnalyzeSource(ASource, AProfile=''): TScanResult` | In-memory scan of a source-code string (editor lint/embedding). |
| `TAnalysisSession.Create.Run(Req): TScanResult` | Full access via `TScanRequest` (all options). |

### 3.2 `TScanRequest`

Fill via `TScanRequest.Init` with sensible defaults (`ssRecursive`, all
detectors, loosest thresholds, one-branch `{$IFDEF}` view with
`TScanRequest.DefaultIfdefDefines`, include defines on, `dlDelphi`, serial),
then override selectively.

| Field | Type | Meaning |
|-------|------|---------|
| `Scope` | `TScanScope` | Scan kind (see 3.5). Default `ssRecursive`. |
| `Path` | `string` | Root (recursive) / file (single) / base dir (list) / `.dproj`, `.lpi`, `.lpk` (project) / `.groupproj`, `.lpg` (project group). |
| `Files` | `TArray<string>` | Explicit file list for `ssFileList`. |
| `Source` | `string` | In-memory source for `ssSource`. |
| `VcsRange` | `string` | `ssVcsChanged`: `''`=auto, else `shaA..shaB`. |
| `Profile` | `string` | `''`=all detectors, else profile name (see 3.6). |
| `MinSeverity` | `TLeakSeverity` | Findings below this threshold are discarded. |
| `MinConfidence` | `TFindingConfidence` | FP threshold (default `fcMedium`). |
| `MaxFileBytes` | `Integer` | `<=0` → engine default (5 MB). |
| `UsesCheck` | `Boolean` | Run the expensive unused-uses detector. |
| `AutoDiscover` | `Boolean` | Discover custom classes during the scan. |
| `IfdefDefines` | `TArray<string>` | `{$IFDEF}`-aware parsing with these defines: one branch, as a compiler sees it. `Init` sets `DefaultIfdefDefines` (`MSWINDOWS`, `WIN64`, `UNICODE`, `CONDITIONALEXPRESSIONS`); `nil`/empty = both branches of every `{$IFDEF}`. Scan view: applied by `Run` even with `SkipConfig`. |
| `IncludeDefines` | `Boolean` | Read `{$I}` include files for their `{$DEFINE}` effect. `Init` sets `True`; `False` = include-blind (CLI `--no-include-defines`). Scan view like `IfdefDefines`. |
| `Dialect` | `TSourceDialect` | `dlDelphi` (`Init`) or `dlFpc` (`uSCAConsts`): `dlFpc` also collects `*.pp` in directory walks and, with a non-empty `IfdefDefines`, adds `FPC` and `LCL`. Forced to `dlFpc` for `.lpi`/`.lpk`/`.lpg` project scopes. Scan view like `IfdefDefines`. |
| `CustomRulesPath` | `string` | YAML with custom rules (`''`=none). |
| `BaselinePath` | `string` | Filter findings against a baseline JSON (`''`=off). |
| `WriteBaselinePath` | `string` | Write current findings as a new baseline. |
| `ApplyRepoIni` | `Boolean` | Load + fully apply `analyser.ini` (like the CLI). |
| `MinSeverityName` | `string` | INI mode: override `'error'`/`'warning'`/`'hint'`. |
| `ConfigRoot` | `string` | INI mode: root for INI/rules resolution. |
| `SkipConfig` | `Boolean` | `true`: apply no config (consumer has set state itself). |
| `IndexRoot` | `string` | `ssProject`/`ssProjectGroup`/`ssFileList`: directory over which the cross-unit indexes (symbol references, types, DFM) are built while the analysis stays on the list. `''` = common root of the resolved list (project scopes) or the list itself (`ssFileList`). |
| `SingleFileProjectRoot` | `string` | `ssSingleFile`: project root for the cross-unit index. |
| `IgnoreList` | `TIgnoreList` | `ssRecursive`, `ssProject`, `ssProjectGroup`: ignore/test filter (`nil`=none). |
| `Parallel` | `Boolean` | Per-file parallel scan (opt-in, `Init`: `False`; CLI `--parallel`). Falls back to serial when a mode that is not parallel-safe is active (auto-discovery, custom rules, detector timing); the result order equals the serial run. Not applied with `SkipConfig`. |
| `ParallelWorkers` | `Integer` | Worker count with `Parallel`; `0` = `TThread.ProcessorCount`. |
| `Progress` | `TProc<Integer,Integer>` | `(current,total)`; `EAbort` inside aborts. In parallel mode the callback is delivered during the merge phase, on the caller's thread. |

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
   scope → scan → baseline. The scan view (`IfdefDefines`, `IncludeDefines`,
   `Dialect`) is applied in every mode.

### 3.5 Scopes (`TScanScope`)

| Value | Description |
|-------|-------------|
| `ssRecursive` | Directory recursively (default). Uses `Path` + optional `IgnoreList`. |
| `ssSingleFile` | A single `.pas` file (`Path`); with `SingleFileProjectRoot` a project-wide symbol index. |
| `ssFileList` | Explicit file list (`Files`); `Path` = optional base dir. |
| `ssVcsChanged` | Only VCS-changed files (`Path`=repo, `VcsRange` optional). |
| `ssSource` | In-memory source (`Source`); `Path`=optional logical name. |
| `ssProject` | Files of a project (`Path` = `.dproj`: its `DCCReference` list; `.lpi`/`.lpk`: the Lazarus counterpart); also reports files in the project folder that the project does not list (SCA194/SCA195). |
| `ssProjectGroup` | Union of the project lists of a group (`Path` = `.groupproj` or `.lpg`). |

An unresolvable project file yields a result with a single `fkFileReadError`
finding instead of an exception.

### 3.6 Profiles

A profile is a whitelist of finding kinds. `''` (empty) = **all** detectors.
Built-in profiles (`uRuleCatalog`):

| Profile | Content |
|---------|---------|
| `default` | All rules except the style rules of `style`. |
| `strict` | All rules. |
| `ide-fast` | Fast subset for live analysis (bugs + vulnerabilities + critical DFM). |
| `security` | Vulnerabilities/secrets only (SQLInjection, HardcodedSecret, …). |
| `bugs-only` | Real bugs only (leaks, NilDeref, DivByZero, FormatMismatch, …). |
| `code-quality` | Code smells (LongMethod, MagicNumber, Cyclomatic, duplicates, …). |
| `dfm-only` | DFM/form rules only. |
| `style` | Style rules only (PublicMemberWithoutDoc, BeginEndRequired, WithStatement, …). |
| `selftest-quiet` | All rules except a few layout rules — for scanning the analyser itself. |

### 3.7 Data model: `TLeakFinding` (`uMethodd12`)

Each finding:

| Member | Type / return | Meaning |
|--------|---------------|---------|
| `FileName` | `string` | Source file. |
| `MethodName` | `string` | Method/routine (if known). |
| `LineNumber` / `LineInt` | `string` / `Integer` | Line (string field + integer helper). |
| `EndLine` / `SpanEnd` / `IsMultiLine` / `SpanLineCount` | `Integer` / `Integer` / `Boolean` / `Integer` | Last line of the finding's range. `EndLine = 0` (default) = single line; read `SpanEnd` (clamped, never below the start line) instead of the raw field. A range changes only how much a finding marks, never the number of findings. |
| `MissingVar` / `Message` | `string` | Detail message (`Message` = alias). |
| `Severity` | `TLeakSeverity` | `lsError` / `lsWarning` / `lsHint` — as it stands after the post-filters (evidence tiering, `[PathOverrides]`). |
| `OriginalSeverity` | `TLeakSeverity` | The severity the **detector** assigned. Post-filters change `Severity` only via `OverrideSeverity`, which keeps the first original; `SavedDetectorSeverity`/`SeverityWasOverridden` are its storage — do not read them directly. |
| `Kind` | `TFindingKind` | Concrete rule kind (`fkXxx`). |
| `Confidence` | `TFindingConfidence` | `fcLow` / `fcMedium` / `fcHigh`. |
| `RuleID` | `string` | Custom rule ID (else empty). |
| `RelatedLines` | `string` | Further lines of the same thing — today only SCA015/SCA021 (the partner places of a duplicate group): comma-separated 1-based line numbers, ascending, without the anchor line; empty for every other rule. |
| `StructureChain` | `string` | Nesting chain to the finding, outside in, joined with `CHAIN_SEP` (`' → '`), e.g. `if → for → while`; today only SCA018 (DeepNesting), otherwise empty. |
| `LeakVariant` / `MemoryLeakVariant` | `string` | SCA001 (MemoryLeak) variant: `never-freed`, `freed-outside-finally`, `return-value-not-freed`, `proven-leak`. `LeakVariant` is the field the detector sets (empty = not set); `MemoryLeakVariant` returns it or derives it from `OriginalSeverity` and the message; `''` for every other kind. |
| `FindingType` | `TFindingType` | Category (see below). |
| `SeverityText` / `TypeText` | `string` | Readable labels. |
| `ResolvedRuleId` | `string` | `SCAxxx` (RuleID if set, else catalog lookup). |

`RelatedLines`, `StructureChain` and `LeakVariant` are deliberately not part of
the message, so they are in neither the SARIF nor the baseline fingerprint.
Producers create findings with `TLeakFinding.New(...)`/`NewAtPos(...)` or
`Create` + `SetKind(Kind[, Confidence])` (severity from the catalog default).

Enums (`uSCAConsts`):

```pascal
TLeakSeverity     = (lsError, lsWarning, lsHint);
TFindingConfidence= (fcLow, fcMedium, fcHigh);
TFindingType      = (ftBug, ftCodeSmell, ftVulnerability,
                     ftSecurityHotspot, ftCodeDuplication, ftFileError);
```

Copying a finding: `procedure CopyFrom(ASource: TLeakFinding)` takes over **all** fields of `ASource` (not nil); `function Clone: TLeakFinding` returns a new finding with all fields of `Self`, owned by the caller - always a plain `TLeakFinding`, also for a subclass. Do not copy findings field by field. A new field in `TLeakFinding` is added to `CopyFrom`, then `FINDING_FIELD_COUNT` in `uTestFindingCopy` is raised; that test enumerates the fields by RTTI and fails on a field `CopyFrom` misses.

### 3.8 Source places: `TSourcePlaces` (`uSourcePlaces`)

Describes places in a source file **on request** — for consumers that want to rewrite code (e.g. the "Source Refactor" module reDelphix). It only reads: no scan runs, no finding, field or export is touched, and no detector uses it. One instance per file.

`uEngineApi` re-exports the types `TSourcePlaces`, `TNodeRef`, `TSourceLineRange`, `TUsesSection`, `TNodeKind`, `TNodeKinds`, `TRefactorInfo`, `TRefactorSpan`; values of the aliased enums work qualified through the alias (`TNodeKind.nkAssign`, `TUsesSection.usImplementation`). It does **not** re-export the constants and the other enums: the roles (`ROLE_*`), value types (`rv*`, `TRefactorValueType`) and flags (`rf*`, `TRefactorFlags`) need `uses uRefactorInfo`, the contract version `SOURCE_PLACES_VERSION` needs `uses uSourcePlaces`. Both units are in the package.

```pascal
Places := TSourcePlaces.Create;
try
  try
    Opened := Places.Open(FileName);    // False: file not readable
  except
    on EStackExhausted do raise;        // uCrashDiag: never swallow - no guard page after an overflow
    on EAbort do raise;                 // a silent abort belongs to the host
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
| `Open(FileName)` / `Close` | `Boolean` | Reads the file itself (no scan cache, no engine lock) and parses exactly the decoded text. `False` if unreadable. A parser error (incl. the parser watchdog) **raises**; catch it without swallowing `EStackExhausted` (`uCrashDiag`) or `EAbort`; the service is closed afterwards (`IsOpen = False`). Any previously opened text is discarded first. |
| `OpenSource(FileName, Source)` | `Boolean` | Like `Open`, but on a text the host passes in (IDE: the editor buffer with unsaved changes). `FileName` is only the name; the file is not read. `False` for an empty text; a parser error raises as with `Open`. |
| `SetIfdefDefines(Defines)` | | Lexer view of the next `Open`/`OpenSource`. The service always parses in its own view, never in the process-wide view a running scan sets from `TScanRequest.IfdefDefines`. `nil` or empty (default) = both branches of every `{$IFDEF}`; otherwise one branch with exactly these defines — a consumer that knows the view of the run (`TScanRequest.IfdefDefines`) then gets nodes and types from the same view as the findings. Exception: for a `dlFpc` run with a non-empty define list (also forced for `.lpi`/`.lpk`/`.lpg` projects) the scan adds `FPC` and `LCL` (`TAnalysisSession.ApplyIfdefView`), the service does not — the caller adds the two itself to get the view of the findings. The values are copied and stay set across `Close`. Limits of the both-branch view: `DeclaredTypeOf` returns `''` for a name the branches declare with different types, and `NodesAt` may return nodes of both branches. Defines from include files are not evaluated. |
| `IsOpen` / `FileName` / `LineCount` | `Boolean` / `string` / `Integer` | State of the opened text. |
| `StatementAt(Line, Col)` | `TRefactorInfo` | The statement starting there: span with columns, flags, insert point, hash. `nil` if its end cannot be determined, also when a Delphi 12 multi-line string (`'''`) is in it. |
| `ChainOf(Line, Col, ExpectedTarget = '', ExpectedPlus = ANY_PLUS_COUNT)` | `TRefactorInfo` | Assignment with a `+` chain: target, literals, operands, `FixSafe`. Two cross-checks, each returning `nil` on a mismatch: the target against `ExpectedTarget` (use `TNodeRef.Name`; `''` = no check), and the number of top-level `+` against `ExpectedPlus`, counted independently by the consumer (e.g. from `TNodeRef.TypeRef`, the way SCA044 counts). Any negative value (`TSourcePlaces.ANY_PLUS_COUNT`) means no check. |
| `CallOf(Line, Col, ExpectedHead)` | `TRefactorInfo` | Call statement: head plus the chain of a single argument, otherwise one `argument` part per argument. `ExpectedHead` is the head before the first `(` (`''` = no check). |
| `NodesAt(Line, Kinds)` | `TArray<TNodeRef>` | AST nodes of the given kinds that start on that line, sorted by column. Two hits mean the line is ambiguous. |
| `UsesEntries(Section)` | `TArray<TRefactorSpan>` | Every unit name of the `uses` clauses with its span (`Resolved` = the name as written). `usAny` (default) also covers the clause of a program or library. |
| `IdentifiersIn(Span)` | `TArray<TRefactorSpan>` | Identifiers inside a span as `ident` parts; keywords are not filtered. Strings and comments are excluded — also when the span starts inside one, because the file is read up to the span. Limitation: a Delphi 12 multi-line string (`'''`) before the span is not recognised. |
| `CodeViewOf` / `TextOf` / `HashOf` | | Column-true code view, raw text and SHA-256 of a span, all on the text of the last `Open`/`OpenSource`. In the code view strings are `~` fill (`TRefactorInfoBuilder.VIEW_FILL`), while comments and compiler directives, delimiters included, are blanks. `HashOf` does not see a later change: to detect one, open the current text again and compare `HashOf(Info.Span)` with `Info.SpanHash`, or compare `TextOf(Span)` with the target buffer right before writing (reDelphix does the latter). |
| `ConditionalRanges` | `TArray<TSourceLineRange>` | Conditional ranges of the file, in source order: one range per branch (`{$IFDEF}`..`{$ELSE}`, `{$ELSE}`..`{$ENDIF}`), for every conditional directive (`$IF`, `$IFDEF`, `$IFNDEF`, `$IFOPT`). |
| `SectionLine(Section)` | `Integer` | Line of the `interface` / `implementation` keyword; `0` if the section is missing (program, library) and for `usAny`. |
| `LineText(Line)` | `string` | Text of one line of the opened text; `''` outside. |
| `SpanHasComment(Span)` | `Boolean` | `True` if the span contains a comment or a compiler directive — for a consumer that replaces only part of a statement (`rfHasComment` covers the whole statement). |
| `DeclaredTypeOf(Line, Name)` | `string` | Declared type (bare, lower case) of an identifier, as a **proof**: parameter, local variable or local typed constant of the enclosing routine, else field of the class named in the method name (`TFoo.Bar`) and of its ancestors in this unit, else unit global; `''` if unknown or not proven - an ancestor from outside the unit (it may hide any name), a class or record helper, a method of a nested type, a property or method of that name, different types for the same name (`{$IFDEF}` branches), a line inside a nested routine. Known limit: an untyped class constant (`const Max = 10;` in a class body) has no node, so a unit global of the same name counts as proven. The detectors' type resolver keeps its coarser fallback. `string[N]` resolves to `'shortstring'`, not `'string'` (the detectors' type resolver keeps `'string'`). `Line` is the **anchor line** of a statement (the line of an AST node), not a continuation line. Knows no `with` blocks: it returns the declaration found even where the compiler binds the name to a member of the `with` expression. |
| `InWithBlock(Line)` | `Boolean` | `True` if the line lies in the body of a `with` statement (line-granular, from the `with` line to the last node line of its statement). Ask this before proving anything from `DeclaredTypeOf`. |
| `CollectNodesAt` / `CollectUsesEntries` / `CollectIdentifiers` | | Class functions: the same on a tree, line list or code view the caller already holds — for tests and consumers with their own AST. |

**`TNodeRef`** copies the node fields a consumer needs: `Kind`, `Line`, `Col`, `Name` (target or head as the parser joined it) and `TypeRef` (right-hand side or type reference, flattened). The tree itself belongs to the service and lives only until the next `Open`/`Close`.

**What `ChainOf` and `CallOf` prove.** An operand that is a bare identifier gets its declared type (`rvString`/`rvNonString`, `Resolved` = type name), and `FixSafe` is derived again. A `Char`, `WideChar`, `AnsiChar`, `ShortString` or `PAnsiChar` operand stays `rvString` (Format takes it for `%s`), but not lossless - a `#0` ends the text, an `AnsiChar` from `#$80` passes as its ordinal - so it never makes `FixSafe`. Unknown stays unknown: `rvUnknown` and `FixSafe = False` are the normal case. There is no `rvString` proof inside a `with` block (`InWithBlock`; `Resolved` still names the declaration found), and none for a known RTL call or a `.ToString` term whose name a function of the unit itself declares with a non-string result — that function shadows the RTL routine (e.g. a unit-local `function Trim(..): Variant`). Calls qualified with `SysUtils.`/`StrUtils.` keep their proof. A function declared in a nested routine is not seen (the parser drops nested routines).

Coordinates are 1-based; `EndCol` points **behind** the last character. Every primitive except `Open`/`OpenSource` is total (`nil`, empty, `0` or `False` instead of an exception, also when nothing is open). `SOURCE_PLACES_VERSION` (= 1) is the contract version — a **compile-time** constant: a consumer checks it with `{$IF SOURCE_PLACES_VERSION <> 1}{$MESSAGE ERROR '...'}{$IFEND}` (reDelphix does this in `uRdxRecipeRunner`, `uRdxPlacesRunner` and `uRdxFixRunner`) and then no longer builds against a changed contract. It cannot detect a BPL swapped at runtime; the package binding (DCP/`requires`) does that. The version rises with a change to the signature of an existing primitive, to roles, to coordinates, or to a `FixSafe`/`ValueType`/`Resolved` derivation that newly reports something as proven; it stays for new primitives, new parameters with a default value and derivations that only get stricter.

Per rule, `rules/sca-rules.json` may carry `anchor` (what the findings anchor on: `statement`, `assign`, `call`, `assign-or-call`; `uses-item` is reserved) and `fixMode` (`none` / `assisted` / `auto`); read them via `TRuleCatalog` (`TRuleMeta.Anchor`, `TRuleMeta.FixMode`). A missing or unknown value falls back to the compiled-in catalog; a rule is switched off with `"fixMode": "none"` - then a module offers no rewriting help on its signal at all. `assisted` = template or preview only, never written; `auto` = may write. Without a value the statement recipes (Format()/SQL) offer nothing, and line-based helpers of a module decide for themselves. `editorHelp` (boolean) says whether an IDE module offers a quick fix (a code action for its findings) for the rule (reDelphix: light bulb, Ctrl+Alt+F); reports read it for the HTML "QF" badge and the "Quick-Wins" filter (`TRuleMeta.EditorHelp`, a missing value falls back to the compiled-in catalog). `editorHelps` lists those quick fixes, one item per menu entry (`id`, `effect`: `same`/`changes`/`depends`/`template`, `slug`) - `TRuleMeta.EditorHelps`, empty unless `EditorHelp`; the SARIF export writes it per finding as `properties.editorHelp` (`EditorHelpTokens`: `id:effect:slug`) only when asked to (`TSarifOptions.EditorHelp`, CLI `--sarif-editor-help`; off by default), and `tools/gen-quickfix-doc.py --check` keeps it identical to the reDelphix fix table. The HTML report (`TExporterHtml.Run`, `TScanResult.WriteHtml`) shows the list once per rule in the rule report and a reference to it in the details of each finding while `THtmlReportOptions.EditorHelp` is True - the default; CLI `--html-no-editor-help` sets it to False.

### 3.9 Session class methods: engine lock and caches

| Call | Purpose |
|------|---------|
| `TAnalysisSession.AcquireEngineLock` / `ReleaseEngineLock` | Process-wide engine lock for consumers that change the global detector state themselves (e.g. before a `SkipConfig` run). Recursive: a holder that then calls `Run` re-enters it. Never hold it across `Synchronize`/`ProcessMessages`. |
| `TAnalysisSession.TryAcquireEngineLock: Boolean` | Non-blocking probe for UI-thread callers that skip instead of freezing while a scan runs. `True` = lock held; the caller **must** call `ReleaseEngineLock`. |
| `TAnalysisSession.ReleaseTransientCaches` | Frees the transient engine caches (today: the process-wide file-text cache). Call it at the consumer's last point (after display, reports or export). Too early only costs a warm start, never correctness; do not call it during a running scan. |

### 3.10 Test fixtures: `TFixtureFilter`

The engine owns the rule for hiding findings in test-fixture paths; `Run` does
**not** apply it — a consumer decides (today only the CLI does).

| Call | Purpose |
|------|---------|
| `TFixtureFilter.AutoHidesFixtures(AProfile): Boolean` | Whether a profile hides fixture findings by default: `default` and `selftest-quiet` yes, `strict` and every other profile no. |
| `TFixtureFilter.Apply(AFindings, ABaseDir, ADroppedFiles = nil): Integer` | Removes fixture findings from the list and returns their count. `ABaseDir` (the scan root) anchors the path patterns; `fkFileReadError` always stays; `ADroppedFiles` optionally collects the affected file names. |

---

## 4. Lifecycle / threading

- The engine is **not thread-safe** (shared global config/cache state). One scan
  at a time per process; `Run` takes the engine lock (see 3.9). `Parallel`
  parallelises the files *within* one scan.
- The **recursive scan** is safe for short-lived single-scan processes
  (CLI/demo). In resident hosts (IDE) prefer the single-file/source path.
- `TScanResult` owns the findings; `Free` releases them. With `ReleaseFindings`
  ownership passes to the caller.

---

## 5. Referencing the package (consumer setup)

A third-party consumer needs **only the package**, no engine source:

- `.dproj`: `UsePackages=true` and `DCC_UsePackage` contains `SCA.Engine;rtl`.
- **No** engine source directory in `DCC_UnitSearchPath`.
- At runtime `SCA.Engine290.bpl` (Delphi 12; `{$LIBSUFFIX AUTO}`) and the
  Delphi runtime packages it requires (`rtl`, `xmlrtl`) must be findable
  (global BPL directory or next to the `.exe`).
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
