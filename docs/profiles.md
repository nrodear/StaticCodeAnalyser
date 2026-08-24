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

The standalone app can also show you what is *inside* a profile:
**burger menu -> Rule-set profiles...** lists every rule of the selected
profile with its ID, kind token, severity, type and detector unit.

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

There is one route today, and one caveat worth knowing before you start:

1. Open `rules/sca-rules.json` next to the executable.
2. Add an entry to the `profiles` block.
3. Restart the app. The name appears in the profile combo and in the
   profile window.

**The caveat:** `rules/sca-rules.json` ships with the product and is
overwritten on every update. Keep your profile in a copy outside it. A
second route - own profiles in a file of their own, next to
`analyser.ini` and safe from updates - is planned as the second stage of
the profile window. Built-in profiles will stay read-only.

If the catalogue file cannot be read at all, the engine falls back to a
list compiled into the binary. That fallback carries the built-in
profiles only, so a custom profile disappears until the file is readable
again.

## Not the same thing: `examples/profile-*.yml`

`examples/profile-security.yml` and its siblings are **custom rule files**
(`[Detectors] CustomRulesFile=`). They add regex-based rules of your own.
They share the word "profile" with this page and nothing else: a scan
profile selects among existing detectors, a custom rule file adds new
ones.
