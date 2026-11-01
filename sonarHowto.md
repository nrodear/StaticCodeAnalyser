# Sonar quick guide

🇩🇪 [Deutsche Version](sonarHowto_de.md) · 🇫🇷 [Version française](sonarHowto_fr.md)

SCA writes its findings to a file and sends nothing. `sonar-scanner` carries that file to the server. Server, scanner, tokens and quality gates are covered by the [official Sonar documentation](#official-documentation).

## 1. Write the report

Run this in the project folder:

```powershell
analyser.exe --path . --sonar-export sca.json --profile default
```

The GUI and the IDE write the same format with *Export > Sonar: write Generic Issue report (all findings)...*: always the whole analysis, whatever the grid shows. *Sonar: write selected as external issue* writes one file per selected finding to `.sonar\external\`; set `sonar.externalIssuesReportPaths=.sonar/external/` for those.

## 2. Configure the scanner

`sonar-project.properties` in the same folder:

```properties
sonar.projectKey=my-delphi-project
sonar.sources=.
sonar.externalIssuesReportPaths=sca.json
```

SARIF works too: write it with `--report-sarif sca.sarif` and set `sonar.sarifReportPaths=sca.sarif`. Use only one of the two; Sonar does not deduplicate them.

## 3. Run the scanner

```powershell
$env:SONAR_HOST_URL = "https://sonar.example.com"
$env:SONAR_TOKEN = "<your token>"
sonar-scanner
```

`ANALYSIS SUCCESSFUL` does not prove the import. Look for `Imported N issues in M files` in the scanner log, and for `External issues ignored for N unknown files`.

## Mistakes worth avoiding

- **One Sonar project per Git repository.** A scan from a parent folder pulls in every subproject, and files of embedded repositories have no blame data: each of their issues counts as new code (`Missing blame information for N files`).
- **Report and scanner in the same folder.** Paths in the report are relative to the project folder (`--base-dir`, default `--path`), and Sonar resolves them against the folder of `sonar-project.properties`. Otherwise it drops them as unknown files.
- **Dropped files.** Findings in files that match `sonar.exclusions`, in gitignored files and in a subfolder with its own `.git` that the parent repository does not track as a submodule are lost, even though SCA analysed them.
- **Same rule set.** The IDE uses `[Rules] IdeProfile`, and `--profile default` hides test fixtures (`--show-test-fixtures` keeps them). An unknown profile name gives no error, the run scans with other rules.
- **Stay on one way.** GUI and CLI write different rule metadata. Switching changes severities and ratings in Sonar although the code did not change.
- **Exit code in a pipeline.** Findings end a run with exit 1 to 3. So that the scanner step still runs, add `--fail-on none`; tool errors stay exit 99.
- **SonarDelphi.** If the plugin stops the scanner with `Path to Delphi standardlibrary is invalid`, set `sonar.delphi.installationPath` and `sonar.delphi.compilerVersion`.

## Severity and impact

- **Sonar knows a severity per rule, not per finding.** The impact of a rule follows the strongest finding of the run: if evidence capped all of them, the rule carries the capped severity (Warning: at most MEDIUM). One finding at full severity keeps the catalog impacts. The impact can therefore change from run to run, the issues stay. `[Rules] EvidenceTiering=0` keeps the catalog impacts.
- **Findings you downgraded with `[PathOverrides]` are left out,** because they would arrive at full severity. `--sonar-keep-downgraded` exports them (CLI only). Decide once: findings that leave the report count as fixed, findings that enter it as new.
- **BLOCKER needs SonarQube 10.8 or later.** SCA026 always carries it, SCA004 with a proven finding. On 10.3 to 10.7 such a report is invalid.

## Official documentation

- [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/): installation, token, server URL
- [Generic issue import format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [Quality gates](https://docs.sonarsource.com/sonarqube-server/latest/quality-standards-administration/managing-quality-gates/introduction-to-quality-gates/)
