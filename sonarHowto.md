# Sonar HowTo (Standalone EXE)

🇩🇪 [Deutsche Version](sonarHowto_de.md)

Step-by-step guide for pushing SCA findings into a SonarQube instance using
the **standalone EXE only**. No IDE plugin required.

> **Not covered**: setting up the SonarQube server itself (Docker / creating
> a project / generating tokens in the web UI). Prerequisites: a running
> server, a user account with a token, and a project with Browse permission.
> If you don't have those yet, see [docs/sonar-setup.md](docs/sonar-setup.md)
> ("Troubleshooting" section) and the official SonarQube documentation.

---

## 0. Prerequisites — one-time setup

### 0.1 Install sonar-scanner

Official source: https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/

Direct downloads (Windows x64):
https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/

**PowerShell quick-install**:

```powershell
# Adjust version as needed
$ver = "6.2.1.4610"
Invoke-WebRequest `
  "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$ver-windows-x64.zip" `
  -OutFile "$env:TEMP\sonar-scanner.zip"
Expand-Archive "$env:TEMP\sonar-scanner.zip" -DestinationPath C:\Tools -Force
Rename-Item "C:\Tools\sonar-scanner-$ver-windows-x64" "C:\Tools\sonar-scanner"

# Add to user PATH (persistent)
[Environment]::SetEnvironmentVariable("PATH",
  "$env:PATH;C:\Tools\sonar-scanner\bin", "User")
```

**Open a new PowerShell window** so the PATH change takes effect, then verify:

```powershell
sonar-scanner --version
```

Should print something like `INFO: SonarScanner CLI 6.2.1.4610`. Since
version 5 the scanner ships a bundled JRE — no separate Java install needed.

### 0.2 Build the standalone EXE

Open `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` in Delphi 12,
switch to `Win32 / Release`, **Build**.

Result: `StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe`.

### 0.3 Deploy the catalog persistently (recommended)

`rules\sca-rules.json` is the data source for the per-rule
`cleanCodeAttribute` and `impacts` fields (Sonar MQR mode). By default the
EXE looks for the catalog relative to its own location. If you plan to run
scans from arbitrary working directories later on, drop a user copy so the
EXE always finds it:

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "D:\git-demos\delphi\StaticCodeAnalyser\rules\sca-rules.json" `
          "$dst\sca-rules.json" -Force
```

After catalog updates in the repo: re-copy. (See
[docs/sonar-config.md](docs/sonar-config.md) for the full lookup order.)

---

## 1. Sonar configuration for the standalone EXE

You have three ways to give the EXE the connection details — pick one,
don't mix:

### Option A — CLI flags per run

```powershell
analyser.exe --sonar-test `
  --sonar-host http://sonar.company.com:9000 `
  --sonar-token squ_xxxxxxxxxx `
  --sonar-project my-delphi-project
```

Fast for tests / CI pipelines. Caveat: the token ends up in shell history.

### Option B — Environment variables

```powershell
$env:SONAR_HOST_URL    = "http://sonar.company.com:9000"
$env:SONAR_TOKEN       = "squ_xxxxxxxxxx"
$env:SONAR_PROJECT_KEY = "my-delphi-project"

analyser.exe --sonar-test
```

Recommended for CI (secret stores supply the variables).

### Option C — analyser.ini with DPAPI-encrypted token

Persistent per local Windows user, token **DPAPI-encrypted**:

```powershell
analyser.exe --sonar-host    http://sonar.company.com:9000 `
             --sonar-project my-delphi-project `
             --sonar-token   squ_xxxxxxxxxx `
             --sonar-test
```

On first call — if the file doesn't exist yet — the EXE creates
`%APPDATA%\StaticCodeAnalyser\analyser.ini` with the `[Sonar]` section plus
the encrypted token under `[SonarTokens]`. Subsequent runs need no flags:

```powershell
analyser.exe --sonar-test
```

The token can **only** be decrypted by the same Windows user on the same
machine.

---

## 2. Test the connection

```powershell
analyser.exe --sonar-test
```

Expected output (all four stages green):

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

On failure: the `[FAIL]` line states the cause (DNS, server status, token,
or project permission).

---

## 3. Generate the findings

### 3.1 (Optional) Create sonar-project.properties

```powershell
cd D:\path\to\your\repo
analyser.exe --sonar-init
```

Writes a template into `sonar-project.properties` — edit:

```properties
sonar.projectKey=my-delphi-project
sonar.projectName=My Delphi Project
sonar.sources=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**
sonar.externalIssuesReportPaths=sca-findings.json
```

This file is committed to VCS (the token does **not** belong in it — it
comes at runtime via env var or DPAPI INI).

Alternative: pass every value via `-D` on each call (see step 4 below). Then
no `sonar-project.properties` is needed.

### 3.2 Analyze + export

```powershell
analyser.exe `
  --path D:\path\to\your\repo `
  --full `
  --base-dir D:\path\to\your\repo `
  --sonar-export D:\path\to\your\repo\sca-findings.json
```

Key points:
- `--full` = recursive scan (branch mode would be `--branch` — only
  VCS-changed files)
- `--base-dir` ensures the file paths in the JSON are **relative** to the
  repo root, not absolute. Otherwise Sonar can't link findings to source
  files
- `--sonar-export <file>` writes the Sonar Generic Issue Format JSON
- Optional: `--quiet` suppresses the per-finding stdout (only the summary
  at the end)

Final line of output:
```
Sonar Generic report written: D:\path\to\your\repo\sca-findings.json
Findings: 529 (Errors: 18, Warnings: 30, Hints: 481)
```

---

## 4. Push with sonar-scanner

### Variant 1 — with `sonar-project.properties`

```powershell
$env:SONAR_TOKEN = "squ_xxxxxxxxxx"
cd D:\path\to\your\repo
sonar-scanner
```

The scanner reads `sonar-project.properties` automatically.

### Variant 2 — all parameters inline

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

Successful output ends with:
```
INFO  ANALYSIS SUCCESSFUL, you can find the results at:
      http://sonar.company.com:9000/dashboard?id=my-delphi-project
INFO  EXECUTION SUCCESS
INFO  Total time: 22.081s
```

First run is slower (Sonar downloads language plugins). Subsequent runs
~10–30 s depending on file count.

---

## 5. All-in-one script (example)

Save as `push-to-sonar.ps1` in the repo root and run it as a task or
manually:

```powershell
# push-to-sonar.ps1
$ErrorActionPreference = "Stop"

$exe = "D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe"
$repo = $PSScriptRoot
$json = Join-Path $repo "sca-findings.json"

# Load DPAPI-encrypted token from analyser.ini
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
  # 1. Analyze + export
  & $exe --path $repo --full --base-dir $repo --sonar-export $json --quiet
  if ($LASTEXITCODE -ge 99) { throw "SCA failed (exit $LASTEXITCODE)" }

  # 2. Push
  Push-Location $repo
  try {
    & sonar-scanner   # reads sonar-project.properties
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

| Symptom | Cause | Fix |
|---|---|---|
| `[FAIL] DNS resolution` | Host unreachable, URL typo | Check URL, ping host |
| `[FAIL] HTTP /api/system/status: 503` | Server still booting | Wait ~60 s, retry |
| `[FAIL] Token validation: 401` | Token invalid / expired | Generate a new token in Sonar |
| `[FAIL] Project access: not found` | Project doesn't exist | Create in Sonar (Web UI) |
| `[FAIL] Project access: 403` (project exists) | Missing Browse permission | Project Permissions → grant Browse |
| `Failed to parse report: either type, impacts or both should be provided` | Stale standalone EXE without catalog | Rebuild EXE (0.2), deploy catalog to APPDATA (0.3) |
| Issues missing in Sonar | Wrong `--base-dir` → absolute paths | Set `--base-dir` equal to `--path` |
| `sonar-scanner` not found | PATH not active | Open a new shell window |
| Files appear "Empty" in Sonar | `sonar.exclusions` too broad | Review `sonar.exclusions` in properties |

---

## References

- [docs/sonar-setup.md](docs/sonar-setup.md) — full setup guide (incl. IDE plugin and CI examples)
- [docs/sonar-config.md](docs/sonar-config.md) — resolver order (CLI > Env > Properties > INI)
- [Sonar Scanner documentation](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/)
- [Sonar Generic Issue Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
