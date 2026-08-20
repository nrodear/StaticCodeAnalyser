# Configuration reference (`analyser.ini`)

🇩🇪 [Deutsche Fassung](configuration_de.md) · 🇫🇷 [Version française](configuration_fr.md)

Every key the tool reads from `analyser.ini`, in one place. The file lives in

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

next to `ignore.txt`. It is created on first use; an older `repo.ini` is
migrated automatically. All keys are optional - a missing key means the
default below.

The same file is read by the standalone EXE, the IDE plugin and the CLI.
Where the three deliberately differ, the key name says so (`IdeProfile`,
`IdeMinSeverity`). CLI switches win over the file for the run they are
given in.

> SonarQube settings are **not** in this file - see
> [sonar-config.md](sonar-config.md).


## `[Rules]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Profile` | String | _(empty)_ | Rule profile for CLI and standalone runs. Empty = all rules. |
| `MinSeverity` | String | `hint` | Lowest severity that is reported: `error`, `warning`, `hint`. |
| `MinConfidence` | String | `medium` | Confidence floor: `low` disables the filter, `medium` is the shipped default. |
| `IdeProfile` | String | `ide-fast` | Profile the IDE plugin uses. Mirrored into `Profile` per run - it does not overwrite it. |
| `IdeMinSeverity` | String | `hint` | Severity floor for the IDE plugin, mirrored the same way. |
| `EnableDetectorReviewFilter` | Bool | `False` | Opt-in filter that hides rules still under review. |

## `[Detectors]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `LeakyClasses` | String | _(empty)_ | Extra classes SCA001 treats as leak-capable, comma-separated. |
| `ExcludeLeakyClasses` | String | _(empty)_ | Classes removed from that list again. |
| `OwnershipSinks` | String | _(empty)_ | Routines that take ownership of a passed object. Empty by default - see DETECTORS. |
| `AutoDiscoverClasses` | Bool | `False` | Discover leak-capable classes during the scan and log them. |
| `CustomRulesFile` | String | _(empty)_ | YAML file with custom rules. |
| `FormatFunctions` | String | _(empty)_ | Additional `Format`-like functions for the placeholder check (SCA005). |
| `MagicNumberTrivials` | String | _(empty)_ | Numbers SCA014 accepts without a named constant. |
| `IncludeTests` | Bool | `False` | Scan test directories too. Off by default - fixtures produce noise. |
| `UsesCheck` | Bool | `False` | Enable the expensive unused-uses detector. |
| `MaxFileMB` | Integer | `5` | Files above this size are skipped. |
| `LongMethodMaxBodyLines` | Integer | `50` | SCA012 threshold: body lines. |
| `LongMethodMaxStatements` | Integer | `30` | SCA012 threshold: statements. |
| `LongParamListMaxParams` | Integer | `5` | SCA013 threshold: parameters. |
| `DeepNestingMaxDepth` | Integer | `4` | SCA018 threshold: nesting depth. |
| `CyclomaticMax` | Integer | `10` | SCA022 threshold: McCabe complexity. |
| `CognitiveLimit` | Integer | `15` | SCA176 threshold: cognitive complexity (nesting weighs heavier than in McCabe). |
| `MaxCaseBranches` | Integer | `10` | SCA091 threshold: case branches. |
| `MaxLineLength` | Integer | `120` | Threshold for the line-length rule. |
| `DuplicateBlockMinLines` | Integer | `8` | Minimum block length before duplication is reported. |

## `[Components]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `ForbiddenClasses` | String | _(empty)_ | Component classes that must not appear in any DFM; every use is reported as SCA038. Comma-separated, case-insensitive. Empty keeps the rule silent. |

## `[Baseline]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `File` | String | _(empty)_ | Baseline JSON. Relative paths resolve against the scan root; empty = `.sca` default location. |
| `OnlyNew` | Bool | `False` | Show only findings that are not in the baseline. |
| `PathInFingerprint` | Bool | `False` | Include the relative path in the fingerprint - distinguishes same-named files in different folders. |

## `[Score]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `GradeBMax` | Integer | `50` | Upper score bound for grade B. |
| `GradeCMax` | Integer | `200` | Upper score bound for grade C. |
| `GradeDMax` | Integer | `500` | Upper score bound for grade D; above it the grade is E. |

## `[UI]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Language` | String | `en` | UI language: `de`, `en`, `fr`. Empty = system locale. |
| `Theme` | String | `system` | Standalone theme: `system` (follow Windows), `light`, `dark`. |
| `Element.<Name>` | Bool | `True` | **Kill switch per UI element of the IDE plugin.** `0` disables exactly that element without uninstalling - for when one of them disturbs the IDE. Takes effect after an IDE restart; skipped elements are reported via debug output (prefix `SCA-UI`). Valid names: `SharedUiHooks`, `DockForm`, `LineHighlighter`, `AnnotationOverlay`, `WatchMode`, `WarmUpCaches`, `ViewMenuItem`, `EditorContextMenu`, `OptionsPageSCA`, `OptionsPageSonar`, `FindingsProperties`, `AboutBox`, `ToolsMenuItem`. `PackageWizard` is deliberately not switchable - it carries the teardown of all the others. The standalone EXE ignores these keys. |
| `ClipboardOnClick` | Integer | `1` | What a row click copies: `1` nothing, `2` Jira mini issue, `3` Markdown prompt. |
| `EditorColorScheme` | String | `default` | Colour scheme of the editor marker stripe and overlay title bar. |
| `OverlayPosition` | String | `sameline` | Where the hover overlay anchors relative to the finding line. |
| `OverlayShowOnHover` | Bool | `False` | Show the overlay on hover instead of on click. |
| `OverlayTextOnly` | Bool | `False` | Replace the overlay window with a transparent one-line hint. |

## `[Silent]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `Enabled` | Bool | `True` | Background analysis of the file being edited (IDE plugin). |

## `[Repo]`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `BaseBranch` | String | _(empty)_ | Base branch for Branch-Changes. Empty = auto-detect. |
| `IncludeWorkingTree` | Bool | `True` | Include uncommitted changes in the diff. |

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
| `ExternalEditorArgs` | String | `-g "%file%:%line%"` | Arguments. Placeholders: `%file%`, `%line%`, `%col%`, `%dir%`, `%%`. The default matches Visual Studio Code. |
| `DfmTarget` | String | `ide` | What a `.dfm` finding opens when no external editor is set: `ide` or `viewer` (built-in text viewer, which can jump to the line). |

## `[Sonar]`

Connection settings for the check (`--sonar-test`, "Test Connection" in the
IDE) and for `--sonar-init`. **None of these influence the analysis or any
detector.** Full walkthrough in [sonar-config.md](sonar-config.md).

**This section has the lowest priority of the four sources.** A CLI flag, an
environment variable (`SONAR_HOST_URL`, `SONAR_TOKEN`, `SONAR_PROJECT_KEY`,
`SONAR_ORGANIZATION`, `SONAR_BRANCH`) and - for the project key,
organisation and branch - a `sonar-project.properties` in the scanned
repository all win over it. `--sonar-test` prints which source supplied
each value.

**The token is not here.** It sits encrypted in `[SonarTokens]`, written by
the options page or `--sonar-token`. On Windows it is protected per user and
machine, so a copied `analyser.ini` is useless elsewhere - and a
hand-written token will not decrypt. Use `SONAR_TOKEN` when it should not
touch the disk at all.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `HostUrl` | String | _(empty)_ | Base URL of the server. The check sends the token here as a bearer header, so a wrong host receives the secret - which is why a `sonar.host.url` found in the scanned repository is deliberately ignored. |
| `ProjectKey` | String | _(empty)_ | The project the check looks up. |
| `Organization` | String | _(empty)_ | SonarCloud tenant key. Without it SonarCloud answers 400 and the check reports "project not found" although the project exists. |
| `Branch` | String | _(empty)_ | Branch name for the lookup and for `--sonar-init`. |
| `Insecure` | Bool | `0` | `1` skips TLS certificate validation for the check. It weakens exactly the transport that carries the token. |
| `TokenRef` | String | _(empty)_ | Name of the entry in `[SonarTokens]` holding the encrypted token - lets one INI carry several. |

## Written automatically - do not edit

These sections are maintained by the application. Editing them by hand has
no lasting effect; the next window close overwrites them.

| Section | Keys | Written by |
|---|---|---|
| `[Window]` | `Left`, `Top`, `Width`, `Height`, `Maximized` | standalone EXE, on close |
| `[FindingsPropertiesPanel]` | `Left`, `Top`, `Width`, `Height` | IDE plugin, on close |

## `[PathOverrides]`

Free-form section: each key is a path fragment, each value the severity that
findings below that path get. Use it to downgrade vendored or generated
code without excluding it.

```ini
[PathOverrides]
third_party=hint
generated\=off
```

---

_Keys collected by scanning **every** INI reader in the tree
(`uRepoSettings`, `uAppTheme`, `uEditorCommand`, `uCognitiveComplexity`,
`uUiElementRegistry`, …). The first version of this page listed only two of
them and missed 22 keys. If you add a key, add it here - there is no
generator for this page yet._
