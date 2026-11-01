# Sonar-Kurzanleitung

🇬🇧 [English version](sonarHowto.md) · 🇫🇷 [Version française](sonarHowto_fr.md)

SCA schreibt seine Funde in eine Datei und sendet nichts. `sonar-scanner` trägt diese Datei zum Server. Server, Scanner, Token und Quality Gates beschreibt die [offizielle Sonar-Dokumentation](#offizielle-dokumentation).

## 1. Bericht schreiben

Im Projektordner ausführen:

```powershell
analyser.exe --path . --sonar-export sca.json --profile default
```

GUI und IDE schreiben dasselbe Format mit *Export > Sonar: write Generic Issue report (all findings)...*: immer die ganze Analyse, egal was das Grid zeigt. *Sonar: write selected as external issue* schreibt je markiertem Fund eine Datei nach `.sonar\external\`; dafür `sonar.externalIssuesReportPaths=.sonar/external/` setzen.

## 2. Scanner einrichten

`sonar-project.properties` im selben Ordner:

```properties
sonar.projectKey=my-delphi-project
sonar.sources=.
sonar.externalIssuesReportPaths=sca.json
```

SARIF geht auch: mit `--report-sarif sca.sarif` schreiben und `sonar.sarifReportPaths=sca.sarif` setzen. Nur eines von beiden nutzen, Sonar dedupliziert sie nicht.

## 3. Scanner starten

```powershell
$env:SONAR_HOST_URL = "https://sonar.example.com"
$env:SONAR_TOKEN = "<dein Token>"
sonar-scanner
```

`ANALYSIS SUCCESSFUL` beweist den Import nicht. Maßgeblich sind im Scanner-Log `Imported N issues in M files` und `External issues ignored for N unknown files`.

## Fehler, die sich vermeiden lassen

- **Ein Sonar-Projekt je Git-Repository.** Ein Scan aus dem Elternordner zieht alle Unterprojekte mit, und Dateien eingebetteter Repositories haben keine Blame-Daten: Jedes ihrer Issues zählt als neuer Code (`Missing blame information for N files`).
- **Bericht und Scanner im selben Ordner.** Die Pfade im Bericht sind relativ zum Projektverzeichnis (`--base-dir`, Vorgabe `--path`), und Sonar löst sie gegen den Ordner der `sonar-project.properties` auf. Sonst verwirft es sie als unbekannte Dateien.
- **Verworfene Dateien.** Funde in Dateien, die `sonar.exclusions` treffen, in gitignorierten Dateien und in einem Unterordner mit eigenem `.git`, den das Eltern-Repository nicht als Submodul führt, gehen verloren, auch wenn SCA sie analysiert hat.
- **Gleicher Regelsatz.** Die IDE nimmt `[Rules] IdeProfile`, und `--profile default` blendet Test-Fixtures aus (`--show-test-fixtures` behält sie). Ein unbekannter Profilname ergibt keinen Fehler, der Lauf scannt mit anderen Regeln.
- **Bei einem Weg bleiben.** GUI und CLI schreiben unterschiedliche Regel-Metadaten. Ein Wechsel ändert in Sonar Severities und Ratings, obwohl sich der Code nicht geändert hat.
- **Exit-Code in der Pipeline.** Funde beenden einen Lauf mit Exit 1 bis 3. Damit der Scanner-Schritt trotzdem läuft, `--fail-on none` ergänzen; Werkzeugfehler bleiben Exit 99.
- **SonarDelphi.** Bricht das Plugin den Scanner mit `Path to Delphi standardlibrary is invalid` ab, `sonar.delphi.installationPath` und `sonar.delphi.compilerVersion` setzen.

## Severity und Impact

- **Sonar kennt die Severity je Regel, nicht je Fund.** Der Impact einer Regel folgt dem stärksten Fund des Laufs: Hat die Evidenz-Politik alle gedeckelt, trägt die Regel die gedeckelte Schwere (Warning: höchstens MEDIUM). Ein Fund mit voller Schwere hält die Katalog-Impacts. Der Impact kann also von Lauf zu Lauf wechseln, die Issues bleiben. `[Rules] EvidenceTiering=0` behält die Katalog-Impacts.
- **Funde, die du per `[PathOverrides]` herabgestuft hast, fehlen im Bericht,** denn sie kämen in voller Schwere an. `--sonar-keep-downgraded` exportiert sie (nur CLI). Einmal entscheiden: Was den Bericht verlässt, zählt als behoben, was hinzukommt, als neu.
- **BLOCKER braucht SonarQube 10.8 oder neuer.** SCA026 trägt ihn immer, SCA004 bei einem belegten Fund. Auf 10.3 bis 10.7 ist ein solcher Bericht ungültig.

## Offizielle Dokumentation

- [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/): Installation, Token, Server-URL
- [Generic Issue Import Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [Quality Gates](https://docs.sonarsource.com/sonarqube-server/latest/quality-standards-administration/managing-quality-gates/introduction-to-quality-gates/)
