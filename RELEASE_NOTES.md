# Release 0.9.11 — Repairs

🇩🇪 [Deutsche Version](RELEASE_NOTES_de.md)

Full release notes: [docs/releases/v0.9.11.md](docs/releases/v0.9.11.md)
([deutsch](docs/releases/v0.9.11_de.md)).

A fix release, one day after 0.9.10. No new rules, no new features.
Everything here is a false positive proven on the reference corpus, a
regression that crept in with 0.9.10, or a version number that had quietly
stopped being true.

- **Scrolling in the IDE plugin is quick again.** Three causes: the gutter
  bracket added in 0.9.10 asks for *every* line where the code area leaves
  early for unmarked ones; continuation lines are marks now, so a block over
  21 lines turns one marked line into twenty-one; and every scroll event
  forced a full repaint on top of the one the editor already performs — now
  coalesced through a 90 ms settle timer.
- **Every cell of the findings grid was painted twice** — the renderer draws
  everything itself, but `DefaultDrawing` was never switched off.
- **`SCA028` no longer reports two kinds of non-finding**: an event
  explicitly cleared with `nil`, and a handler that only *seems* missing
  because the ancestor class name exists in two units (skia4delphi carries
  `TfrmBase` in both its VCL and its FMX sample tree).
- **`SCA054` asks the source before claiming a parameter is never read.** The
  AST text it counted against is a lossy approximation — an index expression
  on an assignment's left side and arguments behind an `as` cast never appear
  in it.
- **`SCA099 IfElseBegin` joins the `style` profile**, where the other six
  convention rules already were.
- **The IDE plugin no longer announces itself as v0.9.8.**

---

# Previously — Release 0.9.10 — One finding per block, a quieter default

🇩🇪 [Deutsche Version](RELEASE_NOTES_de.md)

Full release notes: [docs/releases/v0.9.10.md](docs/releases/v0.9.10.md)
([deutsch](docs/releases/v0.9.10_de.md)).

A small release, tagged the same day as 0.9.9. **No rule gained or lost a
finding** — the reference corpus stays at exactly **560,964** across all
**141** rules that fire, checked rule by rule rather than on the total. What
changed is *how* findings are reported.

- **`SCA021` names the real line range** (`lines 513-533, 8 matched
  lines`). The message is part of the SARIF fingerprint, so every `SCA021`
  finding looks new against an existing baseline — **re-write your
  baseline**. That is also why this is a new version and not a re-publish
  of 0.9.9.
- **The `default` profile is quieter.** Six pure-convention rules — 45.4 %
  of all findings on the corpus, all of them correct — moved to a new
  `style` profile. `strict` still means everything.
- **The IDE draws the range bracket in the gutter**, and it is visible now:
  the cap grew rightwards from a right-aligned two-pixel bar, so it landed
  on top of itself and seven pixels outside the gutter.
- **A suppression marker inside a finding's range counts**, both as a match
  and as consumed — the migration step 0.9.9 asked for is gone.
- **`--parallel` says when it declined** instead of quietly going serial.
- **Two published numbers in the 0.9.9 notes were wrong** and are corrected:
  the error tier is **2,134**, not 2,172, and the rule roster grew **166 →
  195**, not 183 → 195.

---

# Previously — Release 0.9.9 — Fewer false positives, two project-scope rules

🇩🇪 [Deutsche Version](RELEASE_NOTES_de.md)

Full release notes: [docs/releases/v0.9.9.md](docs/releases/v0.9.9.md)
([deutsch](docs/releases/v0.9.9_de.md)).

This cycle the tool learned to report **less**. On the 12,800-file
reference corpus the finding count fell from **645,622 to 560,964 —
84,658 fewer (−13.1 %)**, with no true positive knowingly lost. The rule
roster grew from 166 to **195 rules**.

- **−84,658 findings**, in seven separately measured and gated increments.
- **`SCA194` / `SCA195`** — files that are not part of the project, and
  units the project compiles without listing. Both need a project-wide
  view, so they run only in a project or project-group scan.
- **Rule pages now state what a rule deliberately does *not* report.**
- **`SCA080` no longer flags `Break`** — following that hint turned search
  loops into full scans and `while True` loops into infinite ones.
- **The CLI states its active rule set on every run**, including where the
  profile came from. It used to stay silent when the profile came from
  `analyser.ini`, and an unexpected `ide-fast` there looks exactly like a
  broken build.

There is **no version 0.9.4** — it was skipped. v0.9.5 through v0.9.7 had
shipped without release notes; the CHANGELOG now covers them.

---

# Previously — Release 0.9.8

## 2026-06-08 / 2026-06-09 update — Hardening v3/v4 + FP-Reduction

- **DFM Resource-Wrapper format (`$FF $0A $00`) supported** — GExperts'
  83 DFMs went from 0 to 1.084 findings. JVCL DFM-coverage roughly doubled.
- **AST `Destroy` reentrancy bug** fixed — `EInvalidPointer`/SARIF SCA006
  on `gAstFileCache.Evict` after first file in a scan eliminated.
- **`uFixHint` Memoize-Cache** — fixes Win32 `EOutOfMemory` in the IDE
  plugin's `HighlightAllFindingsInFile` on large scans (≥100k findings).
- **scan.log Phase-Tracking + skip-log** — every `Analyseabbruch:`
  finding now reveals the last successful phase + current file; ignored /
  excluded files appear with a reason instead of disappearing silently.
- **FP-Reduction Sprint** — self-scan FPs in `SCA017 DebugOutput`,
  `SCA070 CommentedOutCode`, `SCA019 TodoComment` and `SCA005
  FormatMismatch` reduced by ~80% (67 → 12 across the three style
  detectors). Side-fix: `FreeAndNil(Self.Field)` with `Self.`-qualifier
  is now recognised as freeing.
- **Configuration** — `[Detectors] MaxLineLength` and `MaxCaseBranches`
  added.

## Earlier in 0.9.8 cycle

13 commits since v0.9.7. Phase 1 of
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) is complete
(6/6 quick-wins); Phase 4 has begun with the A.3-Minimal cross-unit
visibility check. A multi-persona review (Architecture + Security +
Performance) hardened the code along the way.

## Highlights

- **`--time-detectors` Markdown report** — per-detector cumulative
  wall-time + call count.
- **Test-fixture auto-detection** — findings from `uTest*.pas` /
  `*Sample.pas` / `*Demo.pas` / test/samples/demos/resources directories
  are filtered out in `default` and `selftest-quiet` profiles. Repo-root-
  anchored against silent-drop attacks.
- **SCA165 `UnusedSuppression`** — `// noinspection X` markers that
  never suppressed a finding are themselves flagged.
- **Golden-corpus FP-regression suite** — 5 historical FP reproducers,
  PowerShell runner, CI-ready exit code.
- **SARIF + Baseline `contextHash/v1`** — SHA256 over a whitespace-
  normalised ±3-line snippet. Baselines survive small refactors.
  Backward-compatible with legacy baselines.
- **Confidence audit (35 kinds → `fcMedium`)** — heuristic / metric /
  style / DFM-schema / no-data-flow-security kinds tagged. Per-kind
  justifications in [`docs/ConfidenceAudit.md`](docs/ConfidenceAudit.md).
- **A.3-Minimal: SCA052 cross-unit reactivated** — `gSymbolRefIndex`
  is now consulted for `fkUnusedPublicMember`. Spot-check shows 44 %
  of cross-unit methods correctly recognised; 56 % follow-up scope
  documented in `Konzept_ScannerQualitaet.md §A.3+`.

## Security hardening (multi-persona review)

- **`// noinspection All`** excludes security-critical kinds
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). Single-marker
  backdoor bypass mitigated.
- **`ParseMarkerLine`** uses `TDetectorUtils.ScanCodeLine` — string-/
  block-comment-context-aware. Markers inside string literals no longer
  treated as active.
- **Baseline JSON** hardened with `MAX_BASELINE_ENTRIES = 1_000_000`
  and `MAX_FINGERPRINT_LEN = 256` against OOM attacks.

## Performance

- **`gFileTextCache` lives through the post-scan phase** — Suppression,
  ContextHash and SARIF/baseline output reuse the warm cache instead
  of re-reading every file. Eliminates ~191k redundant `LoadFromFile`
  + UTF-8 validations per real-world scan.
- **`TFileTextCache` is mtime-aware** — stale entries auto-invalidate.
- **`uVisibilityCheck`** caches `AllUnitMethods` + memoises
  `DescendantsOf` per unit instead of per-public-member.

## Migration

No breaking changes. Existing baselines work as-is (matched via legacy
fingerprint); new baselines additionally carry `contextHash`. Detector
authors with `F.Confidence := xxx` after `SetKind` should migrate to
the new `SetKind(K, AConfidence)` overload — the old pattern still
works.

## Commit log

```
1e7e193  fix(cache):       mtime-aware cache-invalidation
2b723f7  fix(build):       IsTestFixturePath impl signature
120894a  fix(review):      9 review findings (Sec + Perf + API)
e18323d  refactor:         Clean-code fixes (DRY, SRP, naming)
3054630  fix(visibility):  A.3 OwnUnit path + roadmap update
0ab0bf4  feat(visibility): A.3-Minimal — gSymbolRefIndex for SCA052
a8c7c35  feat(confidence): A.1 audit — ~35 kinds as fcMedium
91ae2ec  feat(baseline):   C.2 SARIF contextHash + baseline match
7b957a8  test(corpus):     C.1 Golden-corpus + runner
c0234d7  feat(suppression):C.3 Unused-suppression tracking (SCA165)
57a0b06  feat(filter):     A.2 Test-fixture auto-detection
1b5a145  fix(perf):        gDetectorTimings in interface section
79b4f56  feat(cli):        --time-detectors flag
```
