# Release 0.9.8 — Phase 1 Quick-Wins, Phase 4, Hardening v3/v4 & FP-Reduction

🇩🇪 [Deutsche Version](RELEASE_NOTES_de.md)

Full release notes: [docs/releases/v0.9.8.md](docs/releases/v0.9.8.md)
([deutsch](docs/releases/v0.9.8_de.md)).

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
