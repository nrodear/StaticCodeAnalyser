# Release 0.9.8 — Phase 1 Quick-Wins, Phase 4, Hardening v3/v4 & FP-Reduktion

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.8_de.md](docs/releases/v0.9.8_de.md)
([english](docs/releases/v0.9.8.md)).

## Update 2026-06-08 / 2026-06-09 — Hardening v3/v4 + FP-Reduktion

- **DFM Resource-Wrapper-Format (`$FF $0A $00`) unterstuetzt** — die 83
  GExperts-DFMs sprangen von 0 auf 1.084 Findings. JVCL-DFM-Coverage
  hat sich etwa verdoppelt.
- **AST `Destroy` Reentrancy-Bug** behoben — `EInvalidPointer` /
  SARIF SCA006 bei `gAstFileCache.Evict` nach dem ersten File im Scan
  beseitigt.
- **`uFixHint` Memoize-Cache** — fixt Win32-`EOutOfMemory` im IDE-
  Plugin-Pfad `HighlightAllFindingsInFile` bei grossen Scans
  (≥100k Findings).
- **scan.log Phase-Tracking + Skip-Log** — jeder `Analyseabbruch:`
  zeigt jetzt die letzte erfolgreiche Phase + das aktuelle File;
  ignorierte / ausgeschlossene Files erscheinen mit Grund, statt
  stillschweigend zu verschwinden.
- **FP-Reduktion-Sprint** — Self-Scan-FPs in `SCA017 DebugOutput`,
  `SCA070 CommentedOutCode`, `SCA019 TodoComment` und `SCA005
  FormatMismatch` um ~80% reduziert (67 → 12 ueber die drei
  Style-Detektoren). Nebenbei-Fix: `FreeAndNil(Self.Field)` mit
  `Self.`-Qualifier wird jetzt als Freigabe erkannt.
- **Konfiguration** — `[Detectors] MaxLineLength` und `MaxCaseBranches`
  hinzugefuegt.

## Frueherer Stand im 0.9.8-Zyklus

13 Commits seit v0.9.7. Phase 1 aus
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) ist komplett
(6/6 Quick-Wins); Phase 4 hat mit dem A.3-Minimal-Schritt fuer den
Cross-Unit-Sichtbarkeits-Check begonnen. Ein Multi-Persona-Review
(Architektur + Security + Performance) hat den Code zusaetzlich
gehaertet.

## Highlights

- **`--time-detectors` Markdown-Report** — kumulierte Wall-Time +
  Call-Count pro Detektor.
- **Test-Fixture-Auto-Detection** — Findings aus `uTest*.pas` /
  `*Sample.pas` / `*Demo.pas` / test/samples/demos/resources-Ordnern
  werden in den Profilen `default` und `selftest-quiet` ausgefiltert.
  Repo-Root-anchored gegen Silent-Drop-Angriffe.
- **SCA165 `UnusedSuppression`** — `// noinspection X`-Marker die nie
  ein Finding unterdrueckt haben, werden selbst geflaggt.
- **Golden-Corpus-FP-Regression-Suite** — 5 historische FP-Reproducer,
  PowerShell-Runner, CI-tauglicher Exit-Code.
- **SARIF + Baseline `contextHash/v1`** — SHA256 ueber ein whitespace-
  normalisiertes +/-3-Zeilen-Snippet. Baselines ueberstehen kleine
  Refactors. Backward-Compat mit alten Baselines.
- **Confidence-Audit (35 Kinds → `fcMedium`)** — heuristische /
  metrik-basierte / Style- / DFM-Schema- / no-data-flow-Security-Kinds
  getaggt. Per-Kind-Begruendungen in
  [`docs/ConfidenceAudit.md`](docs/ConfidenceAudit.md).
- **A.3-Minimal: SCA052 Cross-Unit reaktiviert** — `gSymbolRefIndex`
  wird jetzt fuer `fkUnusedPublicMember` konsultiert. Spot-Check zeigt
  44 % der Cross-Unit-Methoden korrekt erkannt; 56 % als Follow-Up im
  `Konzept_ScannerQualitaet.md §A.3+` dokumentiert.

## Security-Hardening (Multi-Persona-Review)

- **`// noinspection All`** schliesst Security-Critical-Kinds aus
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). Single-Marker-
  Backdoor-Bypass ausgehebelt.
- **`ParseMarkerLine`** nutzt `TDetectorUtils.ScanCodeLine` — String-/
  Block-Comment-Context-aware. Marker in String-Literalen werden nicht
  mehr als aktiv geparst.
- **Baseline-JSON** gehaertet mit `MAX_BASELINE_ENTRIES = 1_000_000`
  und `MAX_FINGERPRINT_LEN = 256` gegen OOM-Angriffe.

## Performance

- **`gFileTextCache` lebt durch die Post-Scan-Phase** — Suppression,
  ContextHash und SARIF/Baseline-Output nutzen den warmen Cache statt
  jede Datei neu zu lesen. Spart ~191k redundante `LoadFromFile`
  + UTF-8-Validierungen pro Real-World-Scan.
- **`TFileTextCache` ist mtime-aware** — stale Entries invalidieren
  sich selbst.
- **`uVisibilityCheck`** cacht `AllUnitMethods` + memoiziert
  `DescendantsOf` pro Unit statt pro Public-Member.

## Migration

Keine Breaking-Changes. Bestehende Baselines funktionieren wie bisher
(matched via Legacy-Fingerprint); neue Baselines tragen zusaetzlich
`contextHash`. Detector-Autoren mit `F.Confidence := xxx` NACH
`SetKind` sollten auf den neuen `SetKind(K, AConfidence)`-Overload
migrieren — das alte Pattern bleibt kompatibel.

## Commit-Log

```
1e7e193  fix(cache):       mtime-aware Cache-Invalidation
2b723f7  fix(build):       IsTestFixturePath Impl-Signatur
120894a  fix(review):      9 Review-Findings (Sec + Perf + API)
e18323d  refactor:         Clean-Code-Fixes (DRY, SRP, Naming)
3054630  fix(visibility):  A.3 OwnUnit-Pfad + Konzept-Roadmap
0ab0bf4  feat(visibility): A.3-Minimal — gSymbolRefIndex fuer SCA052
a8c7c35  feat(confidence): A.1 Audit — ~35 Kinds als fcMedium
91ae2ec  feat(baseline):   C.2 SARIF contextHash + Baseline-Match
7b957a8  test(corpus):     C.1 Golden-Corpus + Runner
c0234d7  feat(suppression):C.3 Unused-Suppression-Tracking (SCA165)
57a0b06  feat(filter):     A.2 Test-Fixture-Auto-Detection
1b5a145  fix(perf):        gDetectorTimings in INTERFACE-Section
79b4f56  feat(cli):        --time-detectors Flag
```
