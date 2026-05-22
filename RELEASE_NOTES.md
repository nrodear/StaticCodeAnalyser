# Release 0.9.2 — 2026-05-22

🇩🇪 [Deutsche Version](RELEASE_NOTES_de.md)

> v0.9.1 was already published earlier (2026-05-16, "SonarQube integration").
> The work in this release tag bumps to **0.9.2** so the previous tag stays
> intact in the history.

## Highlights

- **9 new mORMot-cluster detectors** (SCA153-161): UnpairedLock,
  MoveSizeOfPointer, WithMultipleTargets, GetMemWithoutFreeMem,
  SetLengthAppendInLoop, PointerArithmeticOnString, EmptyOnHandler,
  StringFromPointer, PointerSubtraction.
- **Standalone GUI** finally has a progress bar + Cancel button +
  MAX_SCAN_FILES scan-runaway protection (was IDE-only before).
- **IDE-plugin** keyboard shortcuts are configurable (cnpack-style:
  press the key combo, store in INI). Master toggle to disable all
  shortcuts at once. Settings dialog now scrollable.
- **Detector count: 161 kinds** (Sonar-style finding categories),
  delivered by ~130 pipeline classes — some classes emit multiple
  kinds (e.g. `uVisibilityCheck` → 4, `uDfmAnalysisRunner` → 22 DFM).
- **Translation completeness: 161 / 161** finding-hint descriptions
  covered in both DE translation stores (GDeMap runtime fallback
  + i18n/de.po dxgettext path), all 82 combo-labels translated.

## What's new

### Detectors

**SCA138-152** — Sonar-50 expansion to cover the remaining
Maintainability + Code-Smell slots:

| ID | Name | Type |
|---|---|---|
| 138 | GodClass | Code Smell |
| 139 | FreeWithoutNil | Bug |
| 140 | MultipleExit | Code Smell |
| 141 | LargeClass | Code Smell |
| 142 | UnsortedUses | Code Smell |
| 143 | MissingUnitHeader | Code Smell |
| 144 | FloatEquality | Bug |
| 145 | ExceptInDestructor | Bug |
| 146 | BooleanParam | Code Smell |
| 147 | UnusedPrivateMethod | Code Smell |
| 148 | CanBeClassMethod | Code Smell |
| 149 | MissingOverride | Bug |
| 150 | BoolAlwaysTrue | Bug |
| 151 | ConstantReturn | Code Smell |
| 152 | HardcodedString | Code Smell |

**SCA153-161** — mORMot-cluster: patterns recurring in large
low-level Delphi codebases (threading primitives, raw heap
allocation, dynamic-array growth, byte-level buffer ops, PChar
arithmetic, multi-target `with` blocks, typed exception handlers,
string casts from raw pointers, Win64 pointer subtraction).

| ID | Name | Type | Severity |
|---|---|---|---|
| 153 | UnpairedLock | Bug | Warning |
| 154 | MoveSizeOfPointer | Bug | Warning |
| 155 | WithMultipleTargets | Code Smell | Hint |
| 156 | GetMemWithoutFreeMem | Bug | Warning |
| 157 | SetLengthAppendInLoop | Code Smell | Warning |
| 158 | PointerArithmeticOnString | Bug | Warning |
| 159 | EmptyOnHandler | Bug | Warning |
| 160 | StringFromPointer | Bug | Warning |
| 161 | PointerSubtraction | Bug | Warning |

### UI / UX

- **Standalone progress feedback**: `TProgressBar` (Marquee during
  the directory scan, Position-bar with %-readout during the file
  phase) + a `Cancel` button + `MAX_SCAN_FILES=20000` guard. Wired
  into all three analysis entry points: full-folder scan, branch-
  changes-only scan, single-file analysis.
- **IDE-plugin configurable shortcuts**: Tools → Options → Static
  Code Analyser → Hotkeys section. Click into the edit field, press
  the desired key combo (e.g. `Ctrl+Alt+A` for silent analysis,
  `Ctrl+Alt+↑/↓` for finding navigation). Stored in `analyser.ini`,
  master "Enable all keyboard shortcuts" toggle gates all of them.
- **Settings dialog as TScrollBox**: groups (Silent → Rule-Set →
  Detectors → Hotkeys) stack vertically with auto-scroll, no more
  per-group height-engineering.
- **Use-cases section in README** (EN+DE): 19-row capability matrix
  showing what each deployment mode (IDE plugin / Standalone GUI /
  CLI) supports, plus 4 role profiles.

### Build / Infra

- **Central output directory**: `..\Output\Test\<Platform> <Config>`
  in all three .dproj — no more per-project Win32/Win64 build
  artefacts polluting the source tree. Added to `.gitignore`.
- **`paths.optset.xml` shared search path** for the IDE plugin —
  one Form-sources directory per line with explanatory comments.
- **TestInsight CI**: GitHub Actions workflow runs the full DUnitX
  test suite on push (Win32 + Win64).

### Tests

- **uTestSuppressionCompleteness**: three-test fixture that
  guarantees every one of the 161 detector kinds is reachable via
  the `// noinspection <Name>` suppression marker.
- 36 new DUnitX fixtures for the new SCA138-161 detectors
  (~5 tests each: positive cases + negative cases + Kind/Severity
  round-trip).

### Translations

- **161 / 161** hint descriptions present in both
  `uLocalization.pas:GDeMap` (runtime fallback) and `i18n/de.po`
  (dxgettext path).
- **82 / 82** UI combo-labels translated.
- `Todo_TexteTranslate.md` (new): per-detector translation
  checklist with audit shell snippets.

## Bug fixes

### IDE-plugin progress bar

- **Scan→File-phase transition** no longer waits for the 100ms
  throttle. First File-Phase callback always forces the
  `pbstMarquee → pbstNormal` style switch.
- **RunCurrent** (single-file analysis) now toggles `pbstMarquee`
  for the duration. Previously the bar stayed idle.

### Detectors (round 1)

Eight SCA138-152 detectors had AST-shape assumptions that didn't
match the actual parser output:

- **uBooleanParam**: `IfStmt` condition is flat text in
  `IfNode.TypeRef`, not in children. Added word-boundary scan.
- **uCanBeClassMethod**: method body lives in an `nkBlock` wrapper
  child, not direct children. Added `nkBlock` to body check, plus
  cross-decl lookup so interface-only `;virtual` markers are seen.
- **uConstantReturn**: `IsFunctionMethod` was looking for `:` in
  TypeRef; parser uses `'function:Integer'` format. `ExtractRhs`
  was reading children; RHS lives in `nkAssign.TypeRef`.
- **uFloatEquality**: rejected `Ratio = 0.5` because `0.5` has a
  dot — was meant to filter qualified names. Now also accepts
  numeric literals (first char is a digit).
- **uLargeClass**: measured span between method *headers* only;
  600-line method bodies were invisible. Added `DeepMaxLine`
  recursive descendant scan.
- **uExceptInDestructor**: raises in the try-body of `try/except`
  were flagged even though the `except` catches them. Added
  `nkTryExcept` special case.
- **uFreeWithoutNil**: identity check `S = FreeCall` between an
  `nkAssign` and an `nkCall` could never match. Switched to
  Line-number comparison.
- **uGodClass**: `;abstract` marker was being looked for on
  `nkClass.TypeRef`, but the parser only stores class-level
  modifiers there for inheritance lists. Detect "framework class"
  by checking all methods have `;abstract` in their TypeRef instead.

### Build

- **Forward-declaration** for `IsShortcutsMasterEnabled` in
  `uIDEAnalyserForm.pas` — was called ~1700 lines before its
  definition, caused E2003 in the IDE build.
- **dpk + dproj sync** for 15 implicit-import warnings (W1033):
  detector units must be listed in the package `contains` clause.
- **Hint cleanup**: removed unused locals in uAbstractNotImpl
  (`Other`), uUnusedPrivateMethod (`Sections`, `Mthods`), dropped
  dead `Found` write in uFreeWithoutNil.

## Breaking changes

None. All existing rule names, KIND_META entries, and suppression
markers remain stable.

## Compatibility

- **Delphi 12 Athens** (RAD Studio 23) - target
- **Sonar**: External-Issues JSON format unchanged
- **SARIF**: 2.1.0 output unchanged
- **`analyser.ini` schema**: backward compatible; new keys for
  shortcut config and master-toggle (default = enabled)

## Files added in this release

- `Todo_TexteTranslate.md` — generic translation checklist
- `paths.optset.xml` — IDE-plugin shared search path
- `RELEASE_NOTES.md` / `RELEASE_NOTES_de.md` — this file
- 9 new `uXxx.pas` detector units (SCA153-161)
- 9 new `uTestXxx.pas` test fixtures
- `uTestSuppressionCompleteness.pas` — completeness guard

## Acknowledgements

Detectors SCA153-161 came out of an audit of the
[mORMot2](https://github.com/synopse/mORMot2) source tree —
patterns that recur in large low-level Delphi codebases were
extracted into reusable lexical detectors.
