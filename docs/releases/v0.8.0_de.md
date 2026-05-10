## v0.8.0 — Headless CLI + Rule Catalog + SARIF

Major-Feature-Release: das Tool laeuft jetzt headless als CI/CD-Bestand-
teil. Drei zusammenhaengende Bausteine: **Console-Mode**, **Detector-Rule-
Catalog** als Single Source of Truth, und **SARIF v2.1.0 Export** fuer
GitHub Code-Scanning.

### Highlights

- **Headless CLI-Mode** — `analyser.d12.exe` ist jetzt console-aware
  (`{$APPTYPE CONSOLE}`) und akzeptiert Switches:
  ```
  analyser.exe --path D:\repo --full --report-sarif sca.sarif
  analyser.exe --path D:\repo --branch --quiet
  analyser.exe --file MeineUnit.pas
  analyser.exe --help / --version
  ```
  Ohne Switch-Argumente startet weiterhin die VCL-GUI. Exit-Code-
  Konvention klassisch fuer SCA-Tools:
  ```
   0 = clean
   1 = hints only
   2 = warnings present
   3 = errors present
   4 = read errors (parser/IO)
  99 = tool error (bad args, missing path, ...)
  ```

- **Rule Catalog** (`rules/sca-rules.json`) — Single Source of Truth fuer
  alle 22 Detektor-Regeln (`SCA001`-`SCA022`). Pro Rule: stable ID,
  Name, Short/FullDescription, Default-Severity, Type, Tags, CWE,
  OWASP-Refs, ConfigKey, Detector-Unit, Bad/Good-Examples. Loader
  `uRuleCatalog` mit Lookup-by-Kind und Lookup-by-ID. JSON-Schema
  (`rules/sca-rules.schema.json`) fuer Editor-Autocomplete +
  CI-Validation.

- **SARIF v2.1.0 Export** (`--report-sarif <file>`) — der OASIS-Standard
  fuer Static-Analysis-Output. Wird nativ von **GitHub Code-Scanning**,
  **Azure DevOps**, **Visual Studio Code** (mit SARIF-Extension) und
  **SonarCloud** verarbeitet. Findings erscheinen direkt im PR als
  Inline-Annotations, GitHub Security-Tab trackt die Historie pro Branch.
  - Vollstaendige `tool.driver.rules[]` aus dem Rule-Catalog (jeder
    Finding hat Rule-ID + helpUri auf [`docs/rules.md`](docs/rules.md))
  - `partialFingerprints.primaryLocationLineHash` (SHA256 ueber Rule-
    ID + Path + Line + Message) fuer Cross-Commit-Dedup in GitHub
  - Repo-relative Pfade mit Forward-Slashes (SARIF-/GitHub-Konvention)
  - `properties.tags` enthaelt Catalog-Tags + CWE + OWASP fuer Filter

### CI-Integration

- **GitHub-Actions-Workflow** (`.github/workflows/sca.yml`) als Vorlage:
  - Job `sca`: full project scan auf push + PR, SARIF-Upload via
    `github/codeql-action/upload-sarif@v3`
  - Job `sca-pr-changes`: nur Branch-diff (`--branch`), fail-on-error
    fuer PRs

- **Distribution-Pattern**: das Workflow zieht ein Release-Asset
  (`analyser-windows.zip`) mit `analyser.d12.exe` + `rules/`-Ordner.
  Pro Release einmal hochladen via:
  ```powershell
  Compress-Archive -Path bin\analyser.d12.exe,rules -DestinationPath dist\analyser-windows.zip
  gh release upload v0.8.0 dist\analyser-windows.zip
  ```

### Engine

- **`uConsoleRunner`** (`Console/uConsoleRunner.pas`, NEU) - Args-Parser
  mit `--key=value` und `--key value`-Syntax, Run-Dispatcher (Branch/
  SingleFile/Full), Exit-Code-Mapping, stderr-Logging. Komplett testbar
  ueber `ParseArgs(Args: array of string)`-API ohne Process-IO.

- **`uRuleCatalog`** (`Common/uRuleCatalog.pas`, NEU) - Lazy JSON-Loader
  mit File-Lookup-Reihenfolge (ExeDir/rules/, ../rules/, .../rules/),
  Fallback-Mode wenn Catalog-JSON fehlt (Minimal-Metadaten aus
  `KIND_META`-Enum), Lookup-Methoden + ForEach-Iterator.

- **`uExportSARIF`** (`Output/uExportSARIF.pas`, NEU) - SARIF-Writer
  via `System.JSON`, keine externe Dep. `WriteFile`-API + `ToJsonString`-
  API (fuer Tests). `partialFingerprints` ueber `THashSHA2.GetHashString`.

- **DPR-Dispatch** (`analyser.d12.dpr`) - prueft per `IsCliMode` ob
  irgendein Param mit `-` oder `/` anfaengt. Wenn ja: `Halt(uConsoleRunner
  .RunFromCmdLine)` ohne VCL-Form. Sonst: `Application.Run` wie bisher.
  Doppel-`Application.CreateForm`-Bug aus v0.7.x mit gefixt.

### Tests

- **`TTestRuleCatalog`** mit 6 Tests in `uTestRuleCatalog`:
  EveryFindingKindHasRule (jeder TFindingKind muss Catalog-Entry haben),
  RuleIDsFollowConvention (`SCA\d{3}`), RuleIDsAreUnique, KindNameMatches-
  Catalog, ToolInfoIsPopulated, GetRuleByIDRoundtrip.

- **`TTestExportSARIF`** mit 10 Tests in `uTestExportSARIF`:
  SchemaUriPresent, VersionIs210, ToolDriverHasNameAndVersion, Rules-
  ArrayContainsAllKinds, ResultHasRuleIdAndLevel, ResultLocationHas-
  FileAndLine, RelativePathsAreUsedWhenBaseDirSet, FingerprintHashIs-
  Stable, SeverityMapsCorrectly, EmptyFindingsListProducesEmptyResults.

### Docs

- **`docs/rules.md`** - konsolidiertes Markdown-Verzeichnis aller 22
  Regeln mit Anker-Links pro Rule-ID. Wird von SARIF-`helpUri` referen-
  ziert (`docs/rules.md#sca001`), GitHub zeigt das beim "More info"-
  Klick im PR.

- **`tools/gen-rules-docs.py`** (Python 3.7+) - generiert per-rule
  Markdown-Pages (`docs/rules/SCA001.md`...) aus dem Catalog-JSON. CLI
  hat `--check`-Mode fuer CI (Fail wenn Docs out of sync). Aktuell
  optional - der einzelne `docs/rules.md` deckt SARIF-helpUri auch ab.

### Bekannte Einschraenkungen

- **Per-rule HTML-Dokumentation** wird noch nicht ausgeliefert - SARIF
  `helpUri` zeigt auf Anker in der konsolidierten `docs/rules.md`
  statt auf eigene Pages. Mit Python verfuegbar generiert
  `tools/gen-rules-docs.py` separate Files pro Rule.

- **Quality-Gate-Flags** (`--max-errors N --max-warnings N`) noch
  nicht implementiert - Pipeline-Fail erfolgt heute nur ueber den
  generischen Exit-Code (3 = errors). Fuer Threshold-basierte Fails
  bis dahin in `.github/workflows/sca.yml` per `if`-Step pruefen.

- **Custom-Rule-Engine** (YAML) ist als Roadmap-Item fuer **v0.9.0**
  geplant - YAML-Parser, `TCustomRuleDetector`, `--custom-rules`-Flag.
  Heute koennen User nur die hardcoded Detektoren nutzen.

### Upgrade von v0.7.2

- **Keine Source-Aenderungen** im User-Code noetig. Alle Neuerungen
  sind additiv.
- **Neue ZIP-Distribution**: das `rules/`-Verzeichnis muss neben
  `analyser.d12.exe` liegen. Bei Standalone-Installation einfach mit-
  kopieren. Im IDE-Plugin spielt der Catalog noch keine Rolle (Plugin
  nutzt weiterhin direkt `KIND_META` aus `uSCAConsts`).
- **GUI-Mode unveraendert** - alle bisherigen Workflows funktionieren
  weiter.
- **CLI ist neu** - kann ab sofort in CI verwendet werden, siehe
  Beispiel-Workflow `.github/workflows/sca.yml`.
- **Bestehende Suppressions, `ignore.txt`, Custom-LeakyClasses,
  Severity-Konfiguration** bleiben unveraendert gueltig.
- **HTML-/CSV-/JSON-Exporte** unveraendert (noch nicht via CLI
  exposed - kommt in v0.8.x).
