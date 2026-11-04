# Configuration reference (`analyser.ini`)

🇩🇪 [Deutsche Fassung](configuration_de.md) · 🇫🇷 [Version française](configuration_fr.md)

Every key the tool reads from `analyser.ini`, in one place. The file lives in

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

next to `ignore.txt`. It is created on first use; an older `repo.ini` is
migrated automatically. All keys are optional - a missing key means the
default below.

**Bool keys take `1` (on) or `0` (off).** `True`, `False` or `yes` are
not read as numbers: the key then keeps its default without a message.

The same file is read by the standalone EXE, the IDE plugin and the CLI.
Some keys are named for one consumer (`IdeProfile`, `IdeMinSeverity`);
others are not read by all three, and their row says so (`IncludeTests`,
`UsesCheck`, `OnlyNew`, `[Baseline] File`, `[Scan] Dialect`). CLI
switches win over the file for the run they are given in.

> SCA keeps no SonarQube settings: server, token and project key belong to
> `sonar-scanner`, see [sonarHowto.md](../sonarHowto.md). `[Sonar]` and
> `[SonarTokens]` sections from older versions are ignored and can be
> deleted.

> reDelphix, the code actions of the IDE plugin, keeps its own settings in
> `redelphix.ini` next to this file and creates it with a commented
> template on first use. With its default `[UI] Language=auto` the
> reDelphix texts follow `Language` below - see
> [reDelphix/README.md](../reDelphix/README.md#sprache-und-redelphixini).


## `[Scan]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Dialect` | String | _(empty)_ | Source dialect when no `--dialect` switch is given: `delphi` or `fpc` (Lazarus/Free Pascal: collects `*.pp`/`*.lpr`, pairs `.lfm`, FPC/LCL defines, skips the Delphi-only rules SCA041/SCA129/SCA185). Empty = delphi. `auto` is understood by the CLI only: from the scan root upwards, the first folder with `*.dpr`/`*.dproj` or `*.lpi`/`*.lpk` decides, Delphi wins a tie; the standalone EXE treats `auto` as delphi. The CLI switch and an `.lpi`/`.lpk`/`.lpg` project scan always win; the GUI toggles this key via right-click on the status bar. |

## `[Rules]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Profile` | String | _(empty)_ | Rule profile for CLI and standalone runs. Empty = `default` (197 rules); the template writes `Profile=default`. |
| `MinSeverity` | String | `hint` | Lowest severity that is reported: `error`, `warning`, `hint`. |
| `MinConfidence` | String | `medium` | Confidence floor: `low` disables the filter, `medium` is the shipped default. |
| `EvidenceTiering` | Bool | `1` | Evidence policy "error = proven": finding severity is capped by the detector's confidence in that specific finding (high → `error` allowed, medium → `warning` at most, low → `hint` at most). Set `0` to restore the pre-0.9.18 behaviour, e.g. for CI gates that count on the old error totals. |
| `IdeProfile` | String | `ide-fast` | Profile the IDE plugin uses. Mirrored into `Profile` per run - it does not overwrite it. |
| `IdeMinSeverity` | String | `hint` | Severity floor for the IDE plugin, mirrored the same way. |
| `EnableDetectorReviewFilter` | Bool | `0` | Internal review aid: adds the entry "Detector Review (1 per detector, random)" to the severity combo. Only in builds compiled with `DEBUG`; release builds ignore the key. |

## `[Detectors]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `LeakyClasses` | String | _(empty)_ | Extra classes SCA001 treats as leak-capable, comma-separated. |
| `ExcludeLeakyClasses` | String | _(empty)_ | Classes removed from that list again. |
| `OwnershipSinks` | String | _(empty)_ | Routines that take ownership of a passed object (bare routine names, comma-separated). Empty by default - see DETECTORS. Corpus-verified candidates for framework code (S4 audit 2026-09-23): `AddItem` (mORMot `TPdfDictionary`/`TPdfArray` own their items), `Add` on Alcinoe `TALXMLNodeList` / doublecmd `TDirectoryHotlist` / fpjson objects. CAUTION: names act globally - a listed name suppresses SCA001 for EVERY routine of that name, which is why the default stays empty. |
| `AutoDiscoverClasses` | Bool | `0` | Discover leak-capable classes during the scan and log them. |
| `CustomRulesFile` | String | _(empty)_ | YAML file with custom rules. |
| `FormatFunctions` | String | `Format,FormatUtf8,FormatString` | `Format`-like functions for the placeholder check (SCA005), comma-separated. A value **replaces** this list: name the three defaults too if you want to keep them. |
| `MagicNumberTrivials` | String | `0,1,2,-1,10,100` | Numbers SCA014 accepts without a named constant, comma-separated. A value **replaces** this list. |
| `IncludeTests` | Bool | `0` | Scan test directories too. Off by default - fixtures produce noise. Standalone EXE and IDE plugin only; the CLI uses `--hide-test-fixtures` / `--show-test-fixtures`. |
| `UsesCheck` | Bool | `0` | Enable the expensive unused-uses detector (SCA007). In the CLI the `strict` profile (`--profile strict` or `Profile=strict`) enables it regardless of this key; the standalone EXE and the IDE plugin read only this key. |
| `MaxFileMB` | Integer | `5` | Files above this size are skipped. |
| `LongMethodMaxBodyLines` | Integer | `50` | SCA012 threshold: body lines. |
| `LongMethodMaxStatements` | Integer | `30` | SCA012 threshold: statements. |
| `LongParamListMaxParams` | Integer | `5` | SCA013 threshold: parameters. |
| `DeepNestingMaxDepth` | Integer | `4` | SCA018 threshold: nesting depth. |
| `CyclomaticMax` | Integer | `10` | SCA022 threshold: McCabe complexity. |
| `CognitiveLimit` | Integer | `15` | SCA176 threshold: cognitive complexity (nesting weighs heavier than in McCabe). |
| `MaxCaseBranches` | Integer | `10` | SCA091 threshold: case branches. |
| `MaxLineLength` | Integer | `120` | Threshold for the line-length rule (SCA062). The rule reports at confidence low, so it only shows with `[Rules] MinConfidence=low`. |
| `DuplicateBlockMinLines` | Integer | `8` | Minimum block length before duplication is reported. |

## `[Components]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `ForbiddenClasses` | String | _(empty)_ | Component classes that must not appear in any DFM; every use is reported as SCA038. Comma-separated, case-insensitive. Empty keeps the rule silent. |

## `[Baseline]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `File` | String | _(empty)_ | Baseline JSON. A relative path resolves against the directory of the project or group, otherwise against the scan root; the CLI falls back to the working directory if the file exists only there, and says so. Empty = `.sca` default location. The CLI reads this key only with `--baseline-scan y`. |
| `OnlyNew` | Bool | `0` | Show only findings that are not in the baseline. Standalone EXE and IDE plugin only; the CLI uses `--baseline` / `--baseline-scan`. |
| `PathInFingerprint` | Bool | `0` | Include the relative path in the fingerprint - distinguishes same-named files in different folders. |

**A baseline counts.** The file holds one entry per finding, and each
entry covers at most one finding: two entries with the same fingerprint
cover two findings, a third one is new. Entries match in three passes,
each entry used once: fingerprint and context hash, then the context hash
alone, then the fingerprint alone. So where a file has more findings of
one kind than the baseline has entries, the extra ones are reported as
new.

**Findings outside a routine** have an empty method, and the method is
part of the fingerprint. A baseline written before v0.9.19 still matches
them through its context hash as long as the lines around them are
unchanged; a baseline without context hashes shows them once as new.

### Which thresholds you can re-tune without invalidating a baseline

The fingerprint hashes the finding's message, and most threshold rules
print the configured limit into that message. Turning such a knob then
changes the *fingerprint* of every finding of that rule without changing a
single finding. Five of the nine `[Detectors]` threshold keys above are
exempt from that, four are not - the table says which, and the paragraph
after it says what the "No" actually costs you, which is less than it
sounds.

| Key | Rule | Re-tuning keeps the fingerprint? |
|---|---|---|
| `[Detectors] LongMethodMaxBodyLines` | SCA012 | **Yes** |
| `[Detectors] LongMethodMaxStatements` | SCA012 | **Yes** |
| `[Detectors] DeepNestingMaxDepth` | SCA018 | **Yes** |
| `[Detectors] CyclomaticMax` | SCA022 | **Yes** |
| `[Detectors] CognitiveLimit` | SCA176 | **Yes** |
| `[Detectors] LongParamListMaxParams` | SCA013 | No - but see below, the context hash usually still matches |
| `[Detectors] MaxCaseBranches` | SCA091 | No - but see below, the context hash usually still matches |
| `[Detectors] MaxLineLength` | SCA062 | No - but see below, the context hash usually still matches |
| `[Detectors] DuplicateBlockMinLines` | SCA021 | No - but see below, the context hash usually still matches |

**What the "No" rows do and do not mean.** They are about the
fingerprint, and the fingerprint is only one of two match sources. Every
entry a baseline of v0.9.8 or later carries also has a *context hash*
over the source lines around the finding, and re-tuning a threshold
changes only the wording of the message - not the finding's line, not the
code around it. So in the normal case those findings keep matching and
you see nothing. They surface once as new when the context hash cannot
help: on a baseline older than v0.9.8 (those carry no context hash), when
the code within three lines of the finding changed as well, or when the
baseline was written with the other `PathInFingerprint` setting (then
nothing matches at all and the run says so). In those cases re-write the
baseline (`--write-baseline`, or "Write baseline" in the GUI and the
plugin) - noting that a re-write accepts *all* current findings, not only
the previously accepted ones. Do **not** re-write pre-emptively just
because you turned one of those four knobs.

That also makes the "Yes" rows the stronger promise, not the weaker one:
they hold even when the context hash does *not* match, because for those
five keys no number from the message goes into the fingerprint at all.
Changing `CyclomaticMax` changes which findings are *reported*, never
which of them your baseline already *accepts*.

The one case the exempt five cannot tell apart: for SCA012, SCA018,
SCA022 and SCA176, two same-named methods in one file - overloads, or the
same name in two classes of one unit - share one fingerprint. Each keeps
its own baseline entry, so the count stays right; the entries just cannot
say which method is which. On the 783,105-finding reference corpus that affects **183 to 185 of 37,990
findings (0.49 %) with `PathInFingerprint=1`**, and **about 1,450 (3.8 %)
in the default mode**, where the file token is the bare file name and
same-named files in different folders share it (the corpus has four
copies of some JVCL units and six of one CEF4Delphi unit). Both numbers
are per repository. The spread of the first one comes from the method-name
heuristic used to count it, see CHANGELOG.

The other four rules were left out on purpose, not forgotten. Dropping
the numbers from *their* messages would merge findings that nothing else
tells apart - measured on the same corpus and in the same path mode,
SCA013 would lose 455 of 10,099 identities (4.5 %, nine times the rate of
the exempt five, because overloads differ in exactly the parameter count
that would be dropped) and SCA091 621 of 1,944 (31.9 %, because that rule
records no method name and its message is otherwise identical
everywhere). In the default mode the SCA013 gap closes to 4.4 % against
3.8 % - there the case rests on the structural reason rather than on the
rate.

## `[Score]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `GradeBMax` | Integer | `50` | Upper score bound for grade B. |
| `GradeCMax` | Integer | `200` | Upper score bound for grade C. |
| `GradeDMax` | Integer | `500` | Upper score bound for grade D; above it the grade is E. |

## `[UI]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Language` | String | `en` | UI language: `de`, `en`, `fr`. Empty or unknown = English. reDelphix follows this key unless its own `redelphix.ini` says otherwise (see above). |
| `Theme` | String | `system` | Standalone theme: `system` (follow Windows), `light`, `dark`. |
| `Element.<Name>` | Bool | `1` | **Kill switch per UI element of the IDE plugin.** `0` disables exactly that element without uninstalling - for when one of them disturbs the IDE. Takes effect after an IDE restart; skipped elements are reported via debug output (prefix `SCA-UI`). Valid names: `SharedUiHooks`, `DockForm`, `LineHighlighter`, `EditorBulb` (light bulb with the finding actions at the caret line; it receives its editor events from `LineHighlighter`, so `LineHighlighter=0` silences it too), `AnnotationOverlay`, `WatchMode`, `WarmUpCaches`, `ViewMenuItem`, `EditorContextMenu`, `EditorContextActions` (code actions without a finding in the editor context menu, flat section below the finding actions with the disabled header "Code actions"; finding actions stay; without `EditorContextMenu` it has no effect), `OptionsPageSCA`, `FindingsProperties`, `AboutBox`, `ToolsMenuItem`. `PackageWizard` is deliberately not switchable - it carries the teardown of all the others. The standalone EXE ignores these keys. |
| `ClipboardOnClick` | Integer | `1` | What a row click copies: `1` nothing, `2` Jira mini issue, `3` Markdown prompt. |
| `EditorColorScheme` | String | `default` | Colour scheme of the editor marker stripe and overlay title bar. |
| `OverlayPosition` | String | `below` | Where the hover overlay anchors relative to the finding line. `below` (default) starts one line below it, at the start of the line; `sameline` overlays the finding line itself. |
| `OverlayShowOnHover` | Bool | `0` | Show the overlay on hover instead of on click. |
| `OverlayTextOnly` | Bool | `0` | Replace the overlay window with a transparent one-line hint. |

## `[Silent]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Enabled` | Bool | `1` | Shows the entry "Analyse current file (silent)" in the editor right-click menu of the IDE plugin: it analyses the file being edited and marks the findings in the editor without opening the dock window. `0` hides the entry. Also on the options page of the plugin. |

## `[Repo]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `BaseBranch` | String | _(empty)_ | Base branch for Branch-Changes. Empty = auto-detect. |
| `IncludeWorkingTree` | Bool | `1` | Include uncommitted changes in the diff. |

## `[Paths]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `GitExe` | String | _(empty)_ | Path to `git.exe`. Empty = search `PATH`. |
| `SvnExe` | String | _(empty)_ | Path to `svn.exe`. Empty = search `PATH`. |


## `[Editor]` — how a finding opens (standalone EXE only)

The IDE plugin jumps to the location through the ToolsAPI and ignores this
section.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `ExternalEditor` | String | _(empty)_ | Full path to an editor. If set, it opens **every** file type - including `.dfm` - and the Delphi IDE is no longer used. |
| `ExternalEditorArgs` | String | `-g "%file%:%line%"` | Arguments. Placeholders: `%file%`, `%line%`, `%col%`, `%dir%`, `%%`. The default matches Visual Studio Code. The Lazarus IDE accepts a file name only - use `%file%` there; it cannot jump to the line. |
| `DfmTarget` | String | `ide` | What a `.dfm` finding opens when no external editor is set: `ide` or `viewer` (built-in text viewer, which can jump to the line). |

## Written automatically - do not edit

These sections are maintained by the application. Editing them by hand has
no lasting effect; the next window close overwrites them.

| Section | Keys | Written by |
|---|---|---|
| `[Window]` | `Left`, `Top`, `Width`, `Height`, `Maximized` | standalone EXE, on close |
| `[FindingsPropertiesPanel]` | `Left`, `Top`, `Width`, `Height` | IDE plugin, on close |

## `[PathOverrides]`

Drops or re-grades findings by path, so vendored, generated or test code
stays in the scan without weakening the profile. The section is read only
from `analyser.ini` in `%APPDATA%\StaticCodeAnalyser\` (standalone EXE, IDE
plugin and CLI alike); there is no per-repository copy.

Each line is `<glob> = <action>`:

- **Glob:** matched against the finding's **full, absolute** file path,
  case-insensitive, `\` and `/` are interchangeable, `*` and `**` both match
  across folders. Start the pattern with `**\` - a relative pattern such as
  `third_party\**` never matches.
- **Action:** `drop:*` (drop every finding), `drop:KindA,KindB` (drop only
  these kinds), `severity:hint:<kinds>`, `severity:warn:<kinds>`,
  `severity:error:<kinds>` (`<kinds>` = `*` or a comma list). Kinds are the
  rule names also used by `// noinspection`, e.g. `MagicNumber`.
- The first matching line wins. A line with any other value (for example
  `third_party=hint`) is ignored without a message.

```ini
[PathOverrides]
**\third_party\** = severity:hint:*
**\generated\**   = drop:*
**\legacy\**      = drop:MagicNumber,BeginEndRequired
```

Read errors (`FileReadError`) are never dropped. Downgraded findings are left
out of the Sonar export unless you pass `--sonar-keep-downgraded`.

---

_Keys collected by scanning **every** INI reader in the tree
(`uRepoSettings`, `uAppTheme`, `uEditorCommand`, `uCognitiveComplexity`,
`uUiElementRegistry`, …). The first version of this page listed only two of
them and missed 22 keys. If you add a key, add it here - there is no
generator for this page yet._
