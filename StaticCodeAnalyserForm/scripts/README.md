# Sonar push scripts

🇩🇪 [Deutsche Version](README_de.md)

Two PowerShell helpers around the standalone EXE + `sonar-scanner`.
Splitting scan from upload lets you re-run the upload without re-scanning,
keeps the scan offline-able for CI, and makes it easy to inspect the JSON
between the two steps.

**Tested with**: SonarQube Community Build 26.5+ (Sonar 10+, MQR mode).
SCA findings import as external issues via Generic Issue Format and sit
alongside Sonar's default **Sonar Way** quality profile — no conflict, no
override. Works with both SonarQube Server and SonarCloud.

| Script | What it does |
|---|---|
| [`sonar-scan.ps1`](sonar-scan.ps1)     | Runs `analyser.exe --sonar-export` and produces `sca-findings.json`. Auto-deploys the rule catalog to `%APPDATA%` on first run, decodes the exit code into a human-readable verdict, validates the output file. |
| [`sonar-upload.ps1`](sonar-upload.ps1) | Decrypts the DPAPI token from `analyser.ini`, reads host/project from `[Sonar]`, runs `sonar-scanner` with the right `-D` flags. Supports `-DryRun` and `-DisableDelphi`. |

---

## Prerequisites (one-time)

1. **Build the Release EXE** — open
   `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` in Delphi 12,
   switch to `Win32/Release`, **Build**.
2. **Install sonar-scanner** — see
   [`../../sonarHowto.md`](../../sonarHowto.md) section 0.1, or
   download directly from
   <https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/>.
   Put `sonar-scanner.bat` either in `PATH` **or** at
   `D:\git-demos\sonar-scanner-8.0.1\bin\` (the scripts auto-detect both).
3. **Seed `analyser.ini`** with the Sonar credentials (one-time, encrypts
   the token via DPAPI):
   ```powershell
   $exe = "..\Win32\Release\StaticCodeAnalyser.d12.exe"
   & $exe --sonar-host    "http://sonar.company.com:9000" `
          --sonar-project "my-delphi-project" `
          --sonar-token   "squ_xxxxxxxxxx" `
          --sonar-test
   ```
   That populates `%APPDATA%\StaticCodeAnalyser\analyser.ini` with section
   `[Sonar]` plus `[SonarTokens]` (token DPAPI-encrypted, only the same
   Windows user on the same machine can read it).

---

## Typical workflow

```powershell
cd D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\scripts

# Scan + upload. Default ProjectPath = the analyser repo itself (self-scan).
.\sonar-scan.ps1
.\sonar-upload.ps1

# Real-world example: scan everything under D:\git-demos and push.
.\sonar-scan.ps1   -ProjectPath D:\git-demos\
.\sonar-upload.ps1 -ProjectPath D:\git-demos\ -DisableDelphi

# Single-file or branch-only scans
.\sonar-scan.ps1 -ProjectPath D:\myrepo -Branch -Quiet

# Verify the scanner command before pushing
.\sonar-upload.ps1 -ProjectPath D:\myrepo -DryRun
```

`Get-Help .\sonar-scan.ps1 -Detailed` / `Get-Help .\sonar-upload.ps1
-Detailed` shows the full per-parameter documentation.

---

## PowerShell Execution Policy

If you see this when running the scripts:

```
.\sonar-scan.ps1 ist nicht digital signiert. Sie können dieses Skript
im aktuellen System nicht ausführen.   ( UnauthorizedAccess )
```

Your execution policy is `AllSigned` (or `Restricted`). Three options,
from least intrusive to most permanent:

| Mode | Command | Effect |
|---|---|---|
| **One-shot** | `powershell -ExecutionPolicy Bypass -File .\sonar-scan.ps1 ...` | No state change. Best for ad-hoc runs and the no-permission CI machine. |
| **Per session** | `Set-ExecutionPolicy -Scope Process Bypass` then run normally | Lasts until you close the shell. |
| **Permanent for your user** | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` | Local unsigned scripts run; downloaded scripts still need a signature. The Windows-Server default. **Recommended.** |

The scripts must **not** be edited via the PowerShell ISE save dialog
with "Save as UTF-8" if you set policy to `AllSigned` — that adds a BOM
which would invalidate a hypothetical signature later.

---

## Catalog deployment (where the rule metadata comes from)

`sonar-scan.ps1` calls
`analyser.exe --sonar-export`, which needs `rules/sca-rules.json` to
populate the `cleanCodeAttribute` + `impacts` fields per rule. The EXE
walks up to 8 directory levels from its own location looking for
`rules\sca-rules.json`; if it doesn't find it the export still works but
ships **without** the MQR fields — Sonar 10+ then rejects the JSON with
`either type, impacts or both should be provided`.

`sonar-scan.ps1` deploys the catalog automatically on first run:

```
%APPDATA%\StaticCodeAnalyser\rules\sca-rules.json
```

That's the **priority-4 lookup** for the standalone EXE (`rules\` in
APPDATA is found regardless of where the EXE is run from). Re-run the
scan script after a catalog edit to sync the copy. Manual deploy:

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item ..\..\rules\sca-rules.json "$dst\sca-rules.json" -Force
```

---

## `-DisableDelphi` — when the Sonar server has a Delphi plugin installed

If the Sonar server has the **SonarDelphi** plugin (IntegraDev,
[`delphi`](https://github.com/integrated-application-development/sonar-delphi)
key) or the older community fork (`communitydelphi`), the upload may
crash on `EXECUTION FAILURE` with hundreds of `WARN` lines like:

```
WARN  Invalid DCC_UnitSearchPath directory: ..\..\..\src\core
WARN  File specified by DCCReference does not exist: ...
WARN  Could not resolve imported file: C:\Embarcadero\Studio\23.0\Bin\CodeGear.Delphi.Targets
INFO  Conditional defines: [..., VER350, ...]
INFO  EXECUTION FAILURE
```

The Delphi plugin parses every `.dproj` / `.dpk` in scope and fails
when the project references targets / dependencies that aren't on the
analysis machine (typical for foreign repos in a shared workspace).

`-DisableDelphi` sets five flags so the Delphi sensor receives no input
and exits cleanly:

```text
-Dsonar.delphi.file.suffixes=
-Dsonar.communitydelphi.file.suffixes=
-Dsonar.lang.patterns.delphi=
-Dsonar.lang.patterns.communitydelphi=
-Dsonar.exclusions=...,**/*.dproj,**/*.dpk,**/*.dpr,**/*.dpkw
```

SCA's external issues are unaffected — they reference `.pas` files by
path, and those paths stay in the scan. Only the **language mapping** is
emptied, so the Delphi sensor finds nothing to process.

Long-term alternatives:
- Uninstall the Delphi plugin in Sonar Web-UI →
  `Administration → Marketplace → Installed → uninstall`
- Narrow the scan scope to a single Delphi repo whose `.dproj` files
  have valid paths (then `-DisableDelphi` is not needed)

---

## Stream capture for debugging

When the scanner fails silently with `EXECUTION FAILURE` and no `ERROR`
line in the log, the actual Java exception went to **stderr** which
PowerShell's `>` doesn't capture by default. Use `*>&1` plus
`Tee-Object` for a complete trace:

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
powershell -ExecutionPolicy Bypass -File .\sonar-upload.ps1 `
  -ProjectPath D:\git-demos\ -DisableDelphi *>&1 |
  Tee-Object -FilePath ".\sonar-upload-$ts.log"
```

`*>&1` merges Error/Warning/Verbose/Output into a single stream that
`Tee-Object` can write to the file. The `.log` files are in
`.gitignore` so they don't pollute commits.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `... ist nicht digital signiert` | ExecutionPolicy = AllSigned/Restricted | See *Execution Policy* section above |
| `analyser.exe not found` | Win32/Release wasn't built | Build the `.dproj` first; script falls back to Debug with a warning |
| `analyser.ini not found at ...` | Sonar credentials never seeded | Run the one-time `--sonar-test` from *Prerequisites* (step 3) |
| `DPAPI decrypt failed` | INI created by a different Windows user / on a different machine | Re-run `analyser.exe --sonar-token <tok>` once on this machine |
| `Findings JSON not found` | `sonar-scan.ps1` not run yet, or `-ProjectPath` mismatch | Run `sonar-scan.ps1` with the same `-ProjectPath`, or pass `-JsonPath` |
| `Failed to parse report: either type, impacts or both should be provided` | Stale EXE without catalog → fallback rule metadata | Rebuild Release EXE; manually copy catalog to APPDATA |
| `[FAIL] DNS resolution` | Sonar host unreachable | Check URL, ping host, VPN if remote |
| `[FAIL] Token validation: 401` | Token revoked or expired | Generate a new token in Sonar Web-UI, re-seed analyser.ini |
| `[FAIL] Project access: 403` | Project missing / no Browse permission | Create project in Sonar or grant Browse to your user |
| `EXECUTION FAILURE` after 500+ `WARN` lines about `DCCReference` / `DCC_UnitSearchPath` | Delphi plugin chokes on foreign `.dproj` files | Add `-DisableDelphi` flag (see section above) |
| `Issues missing from Sonar` after successful push | Files were excluded or `--base-dir` wrong → paths point outside `sonar.sources` | Set `--base-dir` equal to `--path`; review `sonar.exclusions` |

---

## Why split scan from upload?

- **CI pipelines** often run the scan in one job and the upload in a
  later job that has the Sonar token in its environment.
- **Re-uploads** after transient network failures shouldn't re-scan an
  unchanged tree.
- **Manual inspection** of the JSON (jq, diff against a previous run,
  patching in extra metadata) is easier when the artifact lives between
  two steps.

---

## See also

- [`../../sonarHowto.md`](../../sonarHowto.md) (English) /
  [`../../sonarHowto_de.md`](../../sonarHowto_de.md) — full step-by-step
  including sonar-scanner install and INI structure.
- [`../../docs/sonar-config.md`](../../docs/sonar-config.md) —
  configuration resolver order (CLI > Env > properties > INI).
- [`../../docs/sonar-setup.md`](../../docs/sonar-setup.md) — broader
  Sonar guide including the IDE-plugin workflow.
- [Sonar Generic Issue Format spec](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [SonarDelphi (IntegraDev fork)](https://github.com/integrated-application-development/sonar-delphi)
