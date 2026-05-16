# Sonar-Push-Scripts

🇬🇧 [English version](README.md)

Zwei PowerShell-Helfer um die Standalone-EXE + `sonar-scanner`. Scan und
Upload getrennt zu halten erlaubt einen Upload-Retry ohne Re-Scan,
ermöglicht den Scan offline (CI) und macht es einfach, das JSON zwischen
den Schritten zu inspizieren.

**Getestet mit**: SonarQube Community Build 26.5+ (Sonar 10+, MQR-Modus).
SCA-Findings werden als External Issues über das Generic Issue Format
importiert und stehen neben den built-in Findings des Default-Quality-
Profile **Sonar Way** — kein Konflikt, kein Override. Funktioniert sowohl
mit SonarQube Server als auch SonarCloud.

| Script | Was es macht |
|---|---|
| [`sonar-scan.ps1`](sonar-scan.ps1)     | Ruft `analyser.exe --sonar-export` und produziert `sca-findings.json`. Deployt beim ersten Lauf den Rule-Catalog nach `%APPDATA%`, decodiert den Exit-Code in ein menschenlesbares Verdict, validiert dass die Output-Datei wirklich entstand. |
| [`sonar-upload.ps1`](sonar-upload.ps1) | Entschlüsselt das DPAPI-Token aus `analyser.ini`, liest Host/Project aus `[Sonar]`, ruft `sonar-scanner` mit den richtigen `-D`-Flags. Unterstützt `-DryRun` und `-DisableDelphi`. |

---

## Voraussetzungen (einmalig)

1. **Release-EXE bauen** —
   `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` in Delphi 12
   öffnen, auf `Win32/Release` umstellen, **Build**.
2. **sonar-scanner installieren** — siehe
   [`../../sonarHowto_de.md`](../../sonarHowto_de.md) Abschnitt 0.1 oder
   Direkt-Download von
   <https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/>.
   `sonar-scanner.bat` entweder in `PATH` oder unter
   `D:\git-demos\sonar-scanner-8.0.1\bin\` ablegen (beide Pfade werden
   automatisch erkannt).
3. **`analyser.ini` initial befüllen** mit den Sonar-Zugangsdaten
   (einmalig; verschlüsselt den Token via DPAPI):
   ```powershell
   $exe = "..\Win32\Release\StaticCodeAnalyser.d12.exe"
   & $exe --sonar-host    "http://sonar.company.com:9000" `
          --sonar-project "my-delphi-project" `
          --sonar-token   "squ_xxxxxxxxxx" `
          --sonar-test
   ```
   Das schreibt `%APPDATA%\StaticCodeAnalyser\analyser.ini` mit Section
   `[Sonar]` und `[SonarTokens]` (Token DPAPI-verschlüsselt — nur derselbe
   Windows-User auf demselben Rechner kann ihn entschlüsseln).

---

## Typischer Ablauf

```powershell
cd D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\scripts

# Scan + Upload. Default-ProjectPath = das Analyser-Repo selbst (Self-Scan).
.\sonar-scan.ps1
.\sonar-upload.ps1

# Real-World-Beispiel: alles unter D:\git-demos scannen und pushen.
.\sonar-scan.ps1   -ProjectPath D:\git-demos\
.\sonar-upload.ps1 -ProjectPath D:\git-demos\ -DisableDelphi

# Single-File- oder Branch-Mode-Scans
.\sonar-scan.ps1 -ProjectPath D:\myrepo -Branch -Quiet

# Scanner-Kommando vor dem Push prüfen
.\sonar-upload.ps1 -ProjectPath D:\myrepo -DryRun
```

`Get-Help .\sonar-scan.ps1 -Detailed` / `Get-Help .\sonar-upload.ps1
-Detailed` zeigt die vollständige Parameter-Doku pro Script.

---

## PowerShell Execution Policy

Falls beim Aufruf:

```
.\sonar-scan.ps1 ist nicht digital signiert. Sie können dieses Skript
im aktuellen System nicht ausführen.   ( UnauthorizedAccess )
```

Deine Execution-Policy steht auf `AllSigned` (oder `Restricted`). Drei
Wege, von minimal-invasiv bis dauerhaft:

| Modus | Befehl | Wirkung |
|---|---|---|
| **Einmalig** | `powershell -ExecutionPolicy Bypass -File .\sonar-scan.ps1 ...` | Keine State-Änderung. Ideal für Ad-hoc-Runs und CI-Maschinen ohne Schreibrechte. |
| **Pro Session** | `Set-ExecutionPolicy -Scope Process Bypass` und dann normal aufrufen | Hält bis das Shell-Fenster zu ist. |
| **Dauerhaft für deinen User** | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` | Lokal-unsignierte Scripts laufen; downloaded Scripts brauchen Signatur. Windows-Server-Default. **Empfohlen.** |

Die Scripts dürfen **nicht** per PowerShell-ISE-Save-Dialog mit
"Save as UTF-8" überschrieben werden wenn du auf `AllSigned` stehst —
das fügt ein BOM hinzu und würde eine spätere Signatur invalidieren.

---

## Catalog-Deployment (woher die Rule-Metadaten kommen)

`sonar-scan.ps1` ruft `analyser.exe --sonar-export`, das wiederum
`rules/sca-rules.json` braucht um pro Rule die Felder
`cleanCodeAttribute` und `impacts` zu befüllen. Die EXE walked bis zu
8 Ebenen hoch von ihrem eigenen Verzeichnis aus und sucht nach
`rules\sca-rules.json`; bei keinem Treffer läuft der Export trotzdem,
aber **ohne** die MQR-Felder — Sonar 10+ lehnt die JSON dann ab mit
`either type, impacts or both should be provided`.

`sonar-scan.ps1` deployt den Catalog automatisch beim ersten Lauf:

```
%APPDATA%\StaticCodeAnalyser\rules\sca-rules.json
```

Das ist der **Priority-4-Lookup** für die Standalone-EXE (das `rules\`-
Verzeichnis in APPDATA wird unabhängig vom EXE-Start-Pfad gefunden).
Nach einem Catalog-Edit das Scan-Script erneut laufen lassen um die
Copy zu sync. Manuelles Deploy:

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item ..\..\rules\sca-rules.json "$dst\sca-rules.json" -Force
```

---

## `-DisableDelphi` — wenn der Sonar-Server ein Delphi-Plugin hat

Wenn auf dem Sonar-Server das **SonarDelphi**-Plugin (IntegraDev,
Key [`delphi`](https://github.com/integrated-application-development/sonar-delphi))
oder dessen alter Community-Fork (`communitydelphi`) installiert ist,
kann der Upload mit `EXECUTION FAILURE` und hunderten `WARN`-Zeilen
abbrechen:

```
WARN  Invalid DCC_UnitSearchPath directory: ..\..\..\src\core
WARN  File specified by DCCReference does not exist: ...
WARN  Could not resolve imported file: C:\Embarcadero\Studio\23.0\Bin\CodeGear.Delphi.Targets
INFO  Conditional defines: [..., VER350, ...]
INFO  EXECUTION FAILURE
```

Das Delphi-Plugin parst jede `.dproj` / `.dpk` im Scope und scheitert
bei Projekten die Targets / Dependencies referenzieren, die auf der
Analyse-Maschine nicht vorhanden sind (typisch für Fremd-Repos in
einem geteilten Workspace).

`-DisableDelphi` setzt fünf Flags, sodass der Delphi-Sensor null Input
bekommt und sauber beendet:

```text
-Dsonar.delphi.file.suffixes=
-Dsonar.communitydelphi.file.suffixes=
-Dsonar.lang.patterns.delphi=
-Dsonar.lang.patterns.communitydelphi=
-Dsonar.exclusions=...,**/*.dproj,**/*.dpk,**/*.dpr,**/*.dpkw
```

SCA's External-Issues bleiben davon unberührt — sie referenzieren
`.pas`-Files per Pfad, diese Pfade existieren weiter im Scan. Nur das
**Language-Mapping** wird leergesetzt, sodass der Delphi-Sensor nichts
zu verarbeiten findet.

Langzeit-Alternativen:
- Plugin in Sonar Web-UI deinstallieren →
  `Administration → Marketplace → Installed → uninstall`
- Scan-Scope auf ein einziges Delphi-Repo eingrenzen, dessen `.dproj`-
  Files gültige Pfade haben (dann ist `-DisableDelphi` nicht nötig)

---

## Stream-Capture fürs Debugging

Wenn der Scanner mit `EXECUTION FAILURE` aussteigt aber keine
`ERROR`-Zeile im Log steht, ist die echte Java-Exception auf **stderr**
gelandet — und PowerShells `>` fängt das nicht standardmäßig auf.
`*>&1` plus `Tee-Object` für vollständigen Trace:

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
powershell -ExecutionPolicy Bypass -File .\sonar-upload.ps1 `
  -ProjectPath D:\git-demos\ -DisableDelphi *>&1 |
  Tee-Object -FilePath ".\sonar-upload-$ts.log"
```

`*>&1` mergt Error / Warning / Verbose / Output in einen einzigen
Stream, den `Tee-Object` ins File schreibt. Die `.log`-Files sind in
`.gitignore` damit sie keine Commits verschmutzen.

---

## Troubleshooting

| Symptom | Ursache | Fix |
|---|---|---|
| `... ist nicht digital signiert` | ExecutionPolicy = AllSigned/Restricted | Siehe Abschnitt *Execution Policy* oben |
| `analyser.exe not found` | Win32/Release nicht gebaut | `.dproj` bauen; Script fällt mit Warnung auf Debug-EXE zurück |
| `analyser.ini not found at ...` | Sonar-Credentials nie initial seeded | Einmalig `--sonar-test` aus *Voraussetzungen* Schritt 3 |
| `DPAPI decrypt failed` | INI von anderem Windows-User / anderer Maschine | `analyser.exe --sonar-token <tok>` einmal auf dieser Maschine erneut |
| `Findings JSON not found` | `sonar-scan.ps1` noch nicht gelaufen, oder `-ProjectPath` differiert | `sonar-scan.ps1` mit gleichem `-ProjectPath`, oder `-JsonPath` mitgeben |
| `Failed to parse report: either type, impacts or both should be provided` | Stale EXE ohne Catalog → Fallback-Metadaten | Release-EXE neu bauen; Catalog manuell nach APPDATA kopieren |
| `[FAIL] DNS resolution` | Sonar-Host nicht erreichbar | URL prüfen, Host pingen, VPN falls remote |
| `[FAIL] Token validation: 401` | Token widerrufen oder abgelaufen | Neuen Token in Sonar Web-UI erzeugen, INI neu seeden |
| `[FAIL] Project access: 403` | Projekt fehlt / keine Browse-Permission | Projekt in Sonar anlegen oder Browse-Recht erteilen |
| `EXECUTION FAILURE` nach 500+ `WARN`-Zeilen zu `DCCReference` / `DCC_UnitSearchPath` | Delphi-Plugin verschluckt sich an Fremd-`.dproj`-Files | `-DisableDelphi` ergänzen (siehe oben) |
| Issues fehlen in Sonar nach erfolgreichem Push | Files exkludiert oder `--base-dir` falsch → Pfade zeigen außerhalb `sonar.sources` | `--base-dir` gleich `--path` setzen; `sonar.exclusions` prüfen |

---

## Warum Scan und Upload trennen?

- **CI-Pipelines** lassen den Scan oft in einem Job laufen und den
  Upload in einem späteren Job, der den Sonar-Token im Environment hat.
- **Re-Uploads** nach transienten Netzwerkfehlern sollen nicht ein
  unverändertes Tree neu scannen.
- **Manuelle Inspection** des JSON (jq, Diff gegen den vorigen Run,
  zusätzliche Metadaten reinpatchen) ist einfacher wenn das Artifact
  zwischen den zwei Schritten existiert.

---

## Siehe auch

- [`../../sonarHowto.md`](../../sonarHowto.md) (English) /
  [`../../sonarHowto_de.md`](../../sonarHowto_de.md) — vollständige
  Schritt-für-Schritt-Anleitung inkl. sonar-scanner-Install und
  INI-Struktur.
- [`../../docs/sonar-config.md`](../../docs/sonar-config.md) —
  Konfigurations-Resolver-Reihenfolge (CLI > Env > Properties > INI).
- [`../../docs/sonar-setup.md`](../../docs/sonar-setup.md) —
  größerer Sonar-Guide inklusive IDE-Plugin-Workflow.
- [Sonar Generic Issue Format Spezifikation](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [SonarDelphi (IntegraDev-Fork)](https://github.com/integrated-application-development/sonar-delphi)
