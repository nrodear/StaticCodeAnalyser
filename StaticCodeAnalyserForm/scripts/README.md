# Sonar push scripts

Two PowerShell helpers around the standalone EXE + sonar-scanner. Splitting
scan from upload lets you re-run the upload without re-scanning, and lets
the scan run in CI without ever touching the network.

| Script | What it does |
|---|---|
| [`sonar-scan.ps1`](sonar-scan.ps1)   | Runs `analyser.exe --sonar-export` and produces `sca-findings.json`. Auto-deploys the rule catalog to `%APPDATA%` on first run. |
| [`sonar-upload.ps1`](sonar-upload.ps1) | Reads host/project from `analyser.ini`, decrypts the DPAPI token, calls `sonar-scanner` with the right `-D` flags. |

## Typical workflow

```powershell
# One-time prerequisites (see ../../../sonarHowto.md sections 0 + 1):
#   1. Build the Release EXE
#   2. Install sonar-scanner and put it in PATH
#   3. Run `analyser.exe --sonar-host ... --sonar-project ... --sonar-token ...`
#      once to populate analyser.ini with the DPAPI-encrypted token.

cd D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\scripts

# Scan + upload. Default scope is the parent of the analyser repo.
.\sonar-scan.ps1
.\sonar-upload.ps1

# Or with explicit paths:
.\sonar-scan.ps1   -ProjectPath D:\myrepo -Quiet
.\sonar-upload.ps1 -ProjectPath D:\myrepo

# Dry run (prints scanner command, never connects):
.\sonar-upload.ps1 -DryRun
```

## Parameter reference

Run `Get-Help .\sonar-scan.ps1 -Detailed` or `Get-Help .\sonar-upload.ps1
-Detailed` for the full PowerShell-style help.

## Why split scan from upload?

- CI pipelines often run the scan in one job and the upload in a later
  job that has the Sonar token in its environment.
- Re-uploading after a transient network failure shouldn't re-scan an
  unchanged tree.
- Trying out the JSON manually (jq, diff against the previous run, etc.)
  is easier when the artifact lives between two steps.

## See also

- [`../../sonarHowto.md`](../../sonarHowto.md) (English) /
  [`../../sonarHowto_de.md`](../../sonarHowto_de.md) — full step-by-step
  including sonar-scanner install and INI structure.
- [`../../docs/sonar-config.md`](../../docs/sonar-config.md) — config
  resolver order (CLI > Env > properties > INI).
