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

.PARAMETER Branch
  If set, scan only VCS-changed files (--branch mode). Default: full scan.

.PARAMETER Quiet
  Pass --quiet to the analyser (suppress per-finding stdout).

.EXAMPLE
  .\sonar-scan.ps1
  # Scans the parent of the repo, writes sca-findings.json next to it.

.EXAMPLE
  .\sonar-scan.ps1 -ProjectPath D:\myrepo -OutputPath D:\myrepo\sca-findings.json -Quiet

.EXAMPLE
  .\sonar-scan.ps1 -Branch
  # Branch-mode: only files changed against the base branch.
#>
[CmdletBinding()]
param(
  # Default = analyser repo root (..\..\ from scripts/). Override for own projects.
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\'),
  [string]$OutputPath  = $null,
  [switch]$Branch,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Locate the analyser EXE - prefer Release, fall back to Debug with a warning.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$release  = Join-Path $repoRoot 'StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe'
$debug    = Join-Path $repoRoot 'StaticCodeAnalyserForm\Win32\Debug\StaticCodeAnalyser.d12.exe'

if (Test-Path $release) {
  $exe = $release
} elseif (Test-Path $debug) {
  $exe = $debug
  Write-Warning "Release EXE missing - falling back to Debug. Build Win32\Release for production scans."
} else {
  throw "analyser.exe not found. Build StaticCodeAnalyserForm\StaticCodeAnalyser.d12.dproj first."
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

# Compose flags
$flags = @(
  '--path',       $ProjectPath
  '--base-dir',   $ProjectPath
  '--sonar-export', $OutputPath
)
if ($Branch) { $flags += '--branch' } else { $flags += '--full' }
if ($Quiet)  { $flags += '--quiet' }

Write-Host "Analyser: $exe" -ForegroundColor DarkGray
Write-Host "Scope:    $ProjectPath ($(if ($Branch) {'branch'} else {'full'}))" -ForegroundColor DarkGray
Write-Host "Output:   $OutputPath" -ForegroundColor DarkGray
Write-Host ''

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $exe @flags
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

if (Test-Path $OutputPath) {
  $sz = (Get-Item $OutputPath).Length
  Write-Host ("Wrote: $OutputPath  ({0:N0} bytes)" -f $sz) -ForegroundColor Green
} else {
  Write-Error "Output file missing after scan: $OutputPath"
  exit 1
}

exit 0
