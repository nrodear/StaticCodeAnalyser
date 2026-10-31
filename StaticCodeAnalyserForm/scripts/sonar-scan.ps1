<#
.SYNOPSIS
  Run the StaticCodeAnalyser standalone EXE and write a Sonar Generic Issue
  Format report.

.DESCRIPTION
  Calls the Release build of analyser.exe with the right flags to produce
  a sonar-ready JSON. No upload - run sonar-upload.ps1 after this.

.PARAMETER ProjectPath
  Directory to analyze. Default: the StaticCodeAnalyser repo root (self-
  scan). Override to scan a different codebase.

.PARAMETER OutputPath
  Where the Sonar Generic Issue Format JSON lands. Default:
  <ProjectPath>\sca-findings.json. The companion sonar-upload.ps1 looks at
  the same default - if you change one, change the other.

.PARAMETER RuleProfile
  Rule profile for the report (--profile). Default: [Rules] IdeProfile from
  analyser.ini, so the report has the rule set of the IDE. Without that entry
  the analyser decides ([Rules] Profile, else 'default'). The script aborts on
  a name it cannot find: the analyser itself would accept it and silently scan
  with a different rule set.

.PARAMETER HideTestFixtures
  Leave out findings in test fixtures. Default: they stay in the report, as in
  the IDE (--show-test-fixtures).

.PARAMETER Branch
  If set, scan only VCS-changed files (--branch mode). Default: full scan.

.PARAMETER Quiet
  Pass --quiet to the analyser (suppress per-finding stdout).

.EXAMPLE
  .\sonar-scan.ps1
  # Scans the repo, writes sca-findings.json into it.

.EXAMPLE
  .\sonar-scan.ps1 -ProjectPath D:\myrepo -OutputPath D:\myrepo\sca-findings.json -Quiet

.EXAMPLE
  .\sonar-scan.ps1 -RuleProfile security -HideTestFixtures

.EXAMPLE
  .\sonar-scan.ps1 -Branch
  # Branch-mode: only files changed against the base branch.
#>
[CmdletBinding()]
param(
  # Default = analyser repo root, resolved below. Override for own projects.
  [string]$ProjectPath = $null,
  [string]$OutputPath  = $null,
  [string]$RuleProfile = $null,
  [switch]$HideTestFixtures,
  [switch]$Branch,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Nicht im param-Block: dort ist $PSScriptRoot unter Windows PowerShell 5.1
# mit `powershell -File` leer, und das Skript bricht vor der ersten Zeile ab.
if (-not $ProjectPath) {
  $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
}

# Locate the analyser EXE. Win64 Release first: the project builds to
# ..\Output\<Platform> <Config>\ (DCC_ExeOutput), and a full-repo SARIF from
# the 32-bit build truncates at 2 GB - so 64-bit is the one to prefer.
#
# Until 2026-08-08 this looked under StaticCodeAnalyserForm\Win32\Release\,
# a path that does not exist in this repo: the script could never find the
# EXE and always threw "analyser.exe not found".
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$candidates = @(
  @{ Path = 'Output\Win64 Release'; Warn = $null }
  @{ Path = 'Output\Win32 Release'; Warn = 'Using the 32-bit build. Fine for normal repos; a full scan of a very large tree can truncate its report at 2 GB.' }
  @{ Path = 'Output\Win64 Debug';   Warn = 'Release EXE missing - falling back to Debug. Build Release for production scans.' }
  @{ Path = 'Output\Win32 Debug';   Warn = 'Release EXE missing - falling back to 32-bit Debug. Build Win64 Release for production scans.' }
)

$exe = $null
foreach ($c in $candidates) {
  $p = Join-Path $repoRoot (Join-Path $c.Path 'StaticCodeAnalyser.d12.exe')
  if (Test-Path $p) {
    $exe = $p
    if ($c.Warn) { Write-Warning $c.Warn }
    break
  }
}
if (-not $exe) {
  throw "analyser.exe not found under $repoRoot\Output\. Build StaticCodeAnalyserForm\StaticCodeAnalyser.d12.dproj first."
}

if (-not (Test-Path $ProjectPath)) {
  throw "ProjectPath does not exist: $ProjectPath"
}

if (-not $OutputPath) {
  $OutputPath = Join-Path $ProjectPath 'sca-findings.json'
}

# Make sure the catalog is reachable. If %APPDATA%\StaticCodeAnalyser\rules\
# is empty, deploy it from the repo - otherwise the EXE falls back to bare
# metadata and Sonar rejects the JSON later (see sonarHowto.md "Catalog
# persistent ablegen").
$catUser  = Join-Path $env:APPDATA 'StaticCodeAnalyser\rules\sca-rules.json'
$catRepo  = Join-Path $repoRoot 'rules\sca-rules.json'
if (-not (Test-Path $catUser)) {
  New-Item -ItemType Directory -Force (Split-Path $catUser) | Out-Null
  Copy-Item $catRepo $catUser -Force
  Write-Host "Catalog deployed to: $catUser" -ForegroundColor DarkGray
}

# Regelsatz: Vorgabe ist das Profil der IDE, damit ein Report nicht vom Weg
# abhaengt, auf dem er entstand. Die EXE lehnt einen unbekannten Namen nicht ab,
# sondern scannt ohne Fehler mit anderen Regeln - also hier pruefen.
$configDir = Join-Path $env:APPDATA 'StaticCodeAnalyser'
if (-not $RuleProfile) {
  $iniPath = Join-Path $configDir 'analyser.ini'
  if (Test-Path $iniPath) {
    $m = [regex]::Match((Get-Content $iniPath -Raw -Encoding UTF8), '(?m)^IdeProfile=(.*)$')
    if ($m.Success) { $RuleProfile = $m.Groups[1].Value.Trim() }
  }
}
if ($RuleProfile) {
  $knownProfiles = @()
  foreach ($file in @($catRepo, $catUser, (Join-Path $configDir 'profiles.json'))) {
    if (Test-Path $file) {
      $json = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($json.profiles) { $knownProfiles += $json.profiles.PSObject.Properties.Name }
    }
  }
  if ($knownProfiles -notcontains $RuleProfile) {
    throw "Rule profile '$RuleProfile' not found. Known: $(($knownProfiles | Sort-Object -Unique) -join ', '). Pass -RuleProfile, or fix [Rules] IdeProfile in analyser.ini."
  }
}

# Compose flags
$flags = @(
  '--path',       $ProjectPath
  '--base-dir',   $ProjectPath
  '--sonar-export', $OutputPath
)
if ($Branch) { $flags += '--branch' } else { $flags += '--full' }
if ($Quiet)  { $flags += '--quiet' }
if ($RuleProfile) { $flags += @('--profile', $RuleProfile) }
if (-not $HideTestFixtures) { $flags += '--show-test-fixtures' }

Write-Host "Analyser: $exe" -ForegroundColor DarkGray
Write-Host "Scope:    $ProjectPath ($(if ($Branch) {'branch'} else {'full'}))" -ForegroundColor DarkGray
Write-Host "Rules:    $(if ($RuleProfile) { $RuleProfile } else { '(analyser default)' }), test fixtures $(if ($HideTestFixtures) { 'hidden' } else { 'shown' })" -ForegroundColor DarkGray
Write-Host "Output:   $OutputPath" -ForegroundColor DarkGray
Write-Host ''

$sw = [System.Diagnostics.Stopwatch]::StartNew()
# Ausgabe mitschneiden UND anzeigen: die Summary-Zeile ist die einzige
# Stelle, an der Lesefehler noch auftauchen (s. u.).
& $exe @flags | Tee-Object -Variable scanOut
$rc = $LASTEXITCODE
$sw.Stop()

# Exit-code interpretation per uConsoleRunner:
#   0 = clean, 1 = hints only, 2 = warnings, 3 = errors, 4 = read-errors,
#   99 = tool error (bad args / missing path / write error)
$verdict = switch ($rc) {
  0  { 'clean' }
  1  { 'hints only' }
  2  { 'warnings present' }
  3  { 'errors present' }
  4  { 'read errors (parser/IO)' }
  99 { 'tool error' }
  default { "unexpected exit code $rc" }
}

Write-Host ''
Write-Host ("Scan finished in {0:N1}s -- $verdict" -f $sw.Elapsed.TotalSeconds)

if ($rc -ge 99) {
  Write-Error "analyser.exe reported a tool error - JSON may be incomplete."
  exit $rc
}

# Lesefehler sichtbar machen. Seit 2026-08-08 exportiert der Sonar-Writer
# Lauf-Diagnosen NICHT mehr - eine unlesbare Datei taucht im Dashboard also
# gar nicht auf, und der Exit-Code verraet sie nur, wenn der Lauf sonst
# nichts gefunden hat (die Stufen Error > Warning > Hint gewinnen gegen 4).
# Die Summary-Zeile ist damit die einzige verbleibende Quelle.
$summary = $scanOut | Where-Object { $_ -match '^Summary:' } | Select-Object -Last 1
if ($summary -match '(\d+)\s+Read Error') {
  $readErrors = [int]$Matches[1]
  if ($readErrors -gt 0) {
    Write-Warning ("$readErrors file(s) could not be read - the report covers LESS than the tree. " +
                   "They are not in the Sonar JSON by design; see the console line above for which ones.")
  }
}

if (Test-Path $OutputPath) {
  $sz = (Get-Item $OutputPath).Length
  Write-Host ("Wrote: $OutputPath  ({0:N0} bytes)" -f $sz) -ForegroundColor Green
} else {
  Write-Error "Output file missing after scan: $OutputPath"
  exit 1
}

exit 0
