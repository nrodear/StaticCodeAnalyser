# Sonar-HowTo (Standalone-EXE)

Schritt-für-Schritt-Anleitung um SCA-Findings per **Standalone-EXE** in eine
SonarQube-Instanz zu pushen. Kein IDE-Plugin nötig.

> **Nicht abgedeckt**: das Aufsetzen des SonarQube-Servers selbst (Docker /
> Project anlegen / User+Token in der Web-UI). Voraussetzung: du hast einen
> laufenden Server, einen User mit Token und ein Project mit Browse-
> Permission. Falls noch nicht: siehe [docs/sonar-setup.md](docs/sonar-setup.md)
> Abschnitt "Troubleshooting" und die offizielle SonarQube-Doku.

---

## 0. Voraussetzungen — einmalig

### 0.1 Sonar-Scanner installieren

Offizielle Quelle: https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/

Direkter Download (Windows x64):
https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/

**Quick-Install via PowerShell**:

```powershell
# Aktuelle Version ggf. anpassen
$ver = "6.2.1.4610"
Invoke-WebRequest `
  "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$ver-windows-x64.zip" `
  -OutFile "$env:TEMP\sonar-scanner.zip"
Expand-Archive "$env:TEMP\sonar-scanner.zip" -DestinationPath C:\Tools -Force
Rename-Item "C:\Tools\sonar-scanner-$ver-windows-x64" "C:\Tools\sonar-scanner"

# PATH erweitern (dauerhaft fuer den User)
[Environment]::SetEnvironmentVariable("PATH",
  "$env:PATH;C:\Tools\sonar-scanner\bin", "User")
```

**Neues PowerShell-Fenster öffnen** damit der PATH greift, dann verifizieren:

```powershell
sonar-scanner --version
```

Sollte etwas wie `INFO: SonarScanner CLI 6.2.1.4610` ausgeben. Seit Version 5
bringt der Scanner ein **eigenes JRE** mit — du brauchst kein extra Java zu
installieren.

### 0.2 Standalone-EXE bauen

`StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` in Delphi 12 öffnen,
auf `Win32 / Release` umstellen, **Build**.

Ergebnis: `StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe`.

### 0.3 Catalog persistent ablegen (empfohlen)

`rules\sca-rules.json` ist die Datenquelle für `cleanCodeAttribute` und
`impacts` pro Rule (Sonar MQR-Mode). Standardmäßig sucht der EXE den Catalog
relativ zum eigenen Verzeichnis. Wenn du den Scan später aus beliebigen
Working-Directories startest, leg eine User-Copy an — dort findet die EXE
ihn immer:

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "D:\git-demos\delphi\StaticCodeAnalyser\rules\sca-rules.json" `
          "$dst\sca-rules.json" -Force
```

Bei Catalog-Updates im Repo: Copy nachziehen. (Siehe
[docs/sonar-config.md](docs/sonar-config.md) für die volle Lookup-Reihenfolge.)

---

## 1. Sonar-Konfiguration für die Standalone-EXE

Du hast drei Wege, der EXE die Verbindungsdaten zu geben — wähle einen,
nicht mischen:

### Variante A — CLI-Flags pro Lauf

```powershell
analyser.exe --sonar-test `
  --sonar-host http://sonar.company.com:9000 `
  --sonar-token squ_xxxxxxxxxx `
  --sonar-project my-delphi-project
```

Schnell für Tests / CI-Pipelines. Vorsicht: Token landet in der Shell-
History.

### Variante B — Environment-Variablen

```powershell
$env:SONAR_HOST_URL    = "http://sonar.company.com:9000"
$env:SONAR_TOKEN       = "squ_xxxxxxxxxx"
$env:SONAR_PROJECT_KEY = "my-delphi-project"

analyser.exe --sonar-test
```

Empfohlen für CI (Secret-Stores liefern die Variablen).

### Variante C — analyser.ini mit DPAPI-Token

Persistent für den lokalen User, Token **DPAPI-verschlüsselt**:

```powershell
analyser.exe --sonar-host    http://sonar.company.com:9000 `
             --sonar-project my-delphi-project `
             --sonar-token   squ_xxxxxxxxxx `
             --sonar-test
```

Beim ersten Aufruf legt der EXE — falls noch nicht vorhanden —
`%APPDATA%\StaticCodeAnalyser\analyser.ini` an mit Section `[Sonar]` plus
verschlüsseltem Token in `[SonarTokens]`. Nächster Lauf braucht keine
Flags mehr:

```powershell
analyser.exe --sonar-test
```

Token kann **nur** vom selben Windows-User auf demselben Rechner
entschlüsselt werden.

---

## 2. Verbindung testen

```powershell
analyser.exe --sonar-test
```

Erwarteter Output (alle vier Stufen grün):

```
Sonar config:
  host    = http://sonar.company.com:9000   (CLI --sonar-host)
  project = my-delphi-project               (analyser.ini)
  token   = (42 chars from CLI --sonar-token)

[OK]   DNS resolution: sonar.company.com -> 10.0.0.42
[OK]   HTTP /api/system/status: UP
[OK]   Token validation: valid
[OK]   Project access: my-delphi-project (visible)
Sonar connection healthy.
```

Bei Fehlern: die `[FAIL]`-Zeile beschreibt die Ursache (DNS, Server-Status,
Token, oder Project-Permission).

---

## 3. Findings erzeugen

### 3.1 (Optional) sonar-project.properties anlegen

```powershell
cd D:\path\to\your\repo
analyser.exe --sonar-init
```

Schreibt eine Vorlage in `sonar-project.properties` — anpassen:

```properties
sonar.projectKey=my-delphi-project
sonar.projectName=My Delphi Project
sonar.sources=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**
sonar.externalIssuesReportPaths=sca-findings.json
```

Die Datei landet ins VCS (Token gehört nicht rein — der kommt zur Laufzeit
via Env-Var oder DPAPI-INI).

Alternative: nimm jeden Aufruf alle Werte per `-D` mit (siehe Schritt 4
unten). Dann brauchst du keine `sonar-project.properties`.

### 3.2 Analyse + Export

```powershell
analyser.exe `
  --path D:\path\to\your\repo `
  --full `
  --base-dir D:\path\to\your\repo `
  --sonar-export D:\path\to\your\repo\sca-findings.json
```

Wichtig:
- `--full` = rekursiver Scan (Branch-Mode wäre `--branch` — nur VCS-Diff)
- `--base-dir` = damit die Dateipfade im JSON **relativ** zum Repo-Root sind,
  nicht absolut. Sonst findet Sonar die Files nicht zum Anzeigen
- `--sonar-export <file>` schreibt das Sonar-Generic-Issue-Format-JSON
- Optional dazu: `--quiet` unterdrückt Per-Finding-Output (nur Summary am
  Ende)

Output am Ende:
```
Sonar Generic report written: D:\path\to\your\repo\sca-findings.json
Findings: 529 (Errors: 18, Warnings: 30, Hints: 481)
```

---

## 4. Push mit sonar-scanner

### Variante 1 — mit `sonar-project.properties`

```powershell
$env:SONAR_TOKEN = "squ_xxxxxxxxxx"
cd D:\path\to\your\repo
sonar-scanner
```

Scanner liest `sonar-project.properties` automatisch.

### Variante 2 — alle Parameter inline

```powershell
$env:SONAR_TOKEN = "squ_xxxxxxxxxx"
cd D:\path\to\your\repo

sonar-scanner `
  "-Dsonar.host.url=http://sonar.company.com:9000" `
  "-Dsonar.projectKey=my-delphi-project" `
  "-Dsonar.projectName=My Delphi Project" `
  "-Dsonar.sources=." `
  "-Dsonar.sourceEncoding=UTF-8" `
  "-Dsonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**" `
  "-Dsonar.externalIssuesReportPaths=sca-findings.json"
```

Erwarteter Output endet mit:
```
INFO  ANALYSIS SUCCESSFUL, you can find the results at:
      http://sonar.company.com:9000/dashboard?id=my-delphi-project
INFO  EXECUTION SUCCESS
INFO  Total time: 22.081s
```

Erster Lauf dauert länger (Sonar lädt Sprach-Plugins nach). Folge-Läufe
~10–30 s je nach Anzahl Files.

---

## 5. All-in-one Skript (Beispiel)

Speichere als `push-to-sonar.ps1` im Repo-Root und ruf es per Aufgabe oder
manuell auf:

```powershell
# push-to-sonar.ps1
$ErrorActionPreference = "Stop"

$exe = "D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe"
$repo = $PSScriptRoot
$json = Join-Path $repo "sca-findings.json"

# DPAPI-Token aus analyser.ini laden
Add-Type -AssemblyName System.Security
$ini = Get-Content "$env:APPDATA\StaticCodeAnalyser\analyser.ini" -Raw -Encoding UTF8
$tokenHex = ([regex]::Match($ini, '(?m)^ide-default=(.+)$')).Groups[1].Value.Trim()
$bytes = [byte[]]::new($tokenHex.Length / 2)
for ($i = 0; $i -lt $tokenHex.Length; $i += 2) {
  $bytes[$i / 2] = [Convert]::ToByte($tokenHex.Substring($i, 2), 16)
}
$env:SONAR_TOKEN = [System.Text.Encoding]::UTF8.GetString(
  [System.Security.Cryptography.ProtectedData]::Unprotect(
    $bytes, $null, "CurrentUser"))

try {
  # 1. Analyse + Export
  & $exe --path $repo --full --base-dir $repo --sonar-export $json --quiet
  if ($LASTEXITCODE -ge 99) { throw "SCA failed (exit $LASTEXITCODE)" }

  # 2. Push
  Push-Location $repo
  try {
    & sonar-scanner   # liest sonar-project.properties
    if ($LASTEXITCODE -ne 0) { throw "sonar-scanner failed (exit $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
} finally {
  Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
}
```

---

## Troubleshooting

| Symptom | Ursache | Fix |
|---|---|---|
| `[FAIL] DNS resolution` | Host nicht erreichbar, Tippfehler in URL | URL prüfen, ping Host |
| `[FAIL] HTTP /api/system/status: 503` | Server bootet noch | ~60 s warten, retry |
| `[FAIL] Token validation: 401` | Token ungültig / abgelaufen | Neuen Token im Sonar erzeugen |
| `[FAIL] Project access: not found` | Project existiert nicht | In Sonar anlegen (Web-UI) |
| `[FAIL] Project access: 403` (Project exists) | Browse-Permission fehlt | Project Permissions → User Browse-Recht geben |
| `Failed to parse report: either type, impacts or both should be provided` | Stale Standalone-EXE ohne Catalog | EXE neu bauen (siehe 0.2), Catalog in APPDATA (0.3) |
| Issues in Sonar fehlen | `--base-dir` falsch → absolute Pfade | `--base-dir` == `--path` setzen |
| sonar-scanner nicht gefunden | PATH nicht aktiv | Neues Shell-Fenster |
| Sonar zeigt Files als "Empty" | `sonar.exclusions` greift zu breit | Exclusions in `sonar-project.properties` prüfen |

---

## Referenzen

- [docs/sonar-setup.md](docs/sonar-setup.md) — vollständiger Setup-Guide (inkl. IDE-Plugin und CI-Beispiele)
- [docs/sonar-config.md](docs/sonar-config.md) — Resolver-Pfade (CLI > Env > Properties > INI)
- [Sonar-Scanner-Dokumentation](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/)
- [Sonar Generic Issue Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
