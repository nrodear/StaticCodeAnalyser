# Scan profiles

A **profile** is a named set of rules. It answers one question: *which of
the 196 detectors run in this scan?* Everything else - severity floor,
suppressions, baseline - filters afterwards. The profile decides what is
looked for in the first place.

## The nine built-in profiles

| Profile | Rules | What it is for |
|---|---|---|
| `strict` | 196 | Everything. The completeness promise hangs on this one. |
| `default` | 189 | Everything except the seven pure-convention rules of `style`. Those seven account for roughly half of all findings on a large code base - which is why they are not in the default. |
| `selftest-quiet` | 185 | `default` minus a few formatting rules. Used when this repository scans itself. |
| `code-quality` | 26 | Maintainability: dead code, long methods, complexity, unused uses. |
| `ide-fast` | 20 | Small enough to run on every file you open in the IDE. Bugs and security, no style. |
| `dfm-only` | 20 | The form-file checks alone. |
| `bugs-only` | 15 | Defects only - no smells, no conventions. |
| `security` | 7 | Vulnerabilities and hotspots only. |
| `style` | 7 | The pure-convention rules that `default` leaves out. |

Counts are as shipped in 0.9.17, measured against the catalogue.

## Choosing a profile

| Where | How |
|---|---|
| Standalone app | Profile combo in the filter row |
| IDE plugin | Profile combo; `[Rules] IdeProfile` sets the plugin default (`ide-fast`) |
| CLI | `--profile <name>` |
| `analyser.ini` | `[Rules] Profile=<name>` |

Both surfaces can also show you what is *inside* a profile:
**burger menu -> Rule-set profiles...**, in the standalone app and in the
IDE plugin alike, lists every rule of the selected profile with its ID,
kind token, severity and type. It is the same window - it lives in
`SCA.SharedUI`, so the two cannot drift apart.

## Where profiles are defined

In `rules/sca-rules.json`, in the `profiles` block:

```json
"profiles": {
  "security": ["SQLInjection", "HardcodedSecret", "CommandInjection"],
  "default":  ["*", "!PublicMemberWithoutDoc", "!NilComparison"]
}
```

Each entry is a list of tokens, applied **left to right**:

| Token | Effect |
|---|---|
| `*` | all 196 kinds |
| `Kind` | add this kind |
| `!Kind` or `-Kind` | remove this kind |

Order matters. `["*", "!LongMethod"]` is everything but one rule;
`["!LongMethod", "*"]` is everything, because the `*` runs last.

## The token is the kind name, not the SCA ID

A profile lists **kind names** (`MemoryLeak`), never rule IDs (`SCA001`).
The kind name of every rule sits in the **Kind (profile token)** column of
the profile window, and in [`DETECTORS.md`](../DETECTORS.md).

An unknown token is **ignored without a word** - no error, no warning. A
typo therefore does nothing at all, silently. After editing a profile,
open the profile window and check that the rule count is what you meant.

## Writing your own profile

Built-in profiles cannot be changed - they come from the shipped
catalogue and are overwritten on every update. Your own profile therefore
lives in a file of its own, and the way to make one is to copy:

1. **Burger menu -> Rule-set profiles...** (standalone app or IDE
   plugin - either will do)
2. Select the profile that comes closest, press **Copy...** and give it a
   name (letters, digits, `-`, `_`, `.`).
3. Shape it with **Add rules...** and **Remove rules**, then **Save**.

Your profile is stored in `profiles.json` next to `analyser.ini`, in
`%APPDATA%\StaticCodeAnalyser\`. No update touches that file.

The **engine** reads it, not just the app: a profile you build here also
works with `--profile <name>` on the command line and shows up in the IDE
plugin's profile combo.

A name already used by a built-in profile is refused. Otherwise the same
name would mean different things on different machines, and comparing two
SARIF runs would be worthless.

### Editing that file by hand

`profiles.json` uses the same token syntax as the catalogue:

```json
{
  "version": 1,
  "profiles": {
    "my-team": ["MemoryLeak", "SQLInjection", "NilDeref"]
  }
}
```

The window writes the kind list out in full instead of using `*` with
exceptions, so what the list shows is what stands in the file. If the
file cannot be parsed, the engine keeps the built-in profiles and says
nothing - your own are simply gone until it reads again.

**The file is read once per program start.** A profile you add or edit
by hand therefore does not show up on its own. Press **Reload** in the
profile window and it is read again - no restart of the application or
of the IDE. Profiles you create *in* the window are active immediately;
Reload is only for edits made outside it.

## Not the same thing: `examples/profile-*.yml`

`examples/profile-security.yml` and its siblings are **custom rule files**
(`[Detectors] CustomRulesFile=`). They add regex-based rules of your own.
They share the word "profile" with this page and nothing else: a scan
profile selects among existing detectors, a custom rule file adds new
ones.
