<#
.SYNOPSIS
  Push an SCA Sonar Generic Issue Format JSON to SonarQube via sonar-scanner.

.DESCRIPTION
  Reads connection settings (HostUrl / ProjectKey / DPAPI-encrypted token)
  from %APPDATA%\StaticCodeAnalyser\analyser.ini (sections [Sonar] +
  [SonarTokens]), decrypts the token in-memory via DPAPI, and runs
  sonar-scanner with the right -D parameters. Token is never written to
  disk or shell history.

.PARAMETER ProjectPath
  Directory containing the JSON to upload. Default: the StaticCodeAnalyser
  repo root (mirrors sonar-scan.ps1 self-scan default).

.PARAMETER JsonPath
  Path to the Sonar Generic Issue Format JSON. Default:
  <ProjectPath>\sca-findings.json.

.PARAMETER ScannerPath
  Full path to sonar-scanner.bat. Default: looks for 'sonar-scanner' in
  PATH; if missing, falls back to D:\git-demos\sonar-scanner-8.0.1\bin\
  sonar-scanner.bat (the user's known install).

.PARAMETER Exclusions
  Comma-separated exclusion patterns. Default covers Delphi build output
  + node_modules + .sonar/ + DUnitX vendor.

.PARAMETER DisableDelphi
  Adds scanner flags that prevent the SonarDelphi plugin (or its community
  fork 'communitydelphi') from processing .dproj/.dpk files during the
  push. Useful when the plugin chokes on .dproj entries in foreign repos
  that reference unavailable Delphi targets. SCA's external issues are
  unaffected - they reference .pas files by path and stay visible.

.PARAMETER DryRun
  Print the sonar-scanner command that would be invoked, without running
  it. Useful for verifying token/host/project before pushing.

.EXAMPLE
  .\sonar-upload.ps1

.EXAMPLE
  .\sonar-upload.ps1 -ProjectPath D:\myrepo -JsonPath D:\myrepo\sca.json

.EXAMPLE
  .\sonar-upload.ps1 -DryRun
#>
[CmdletBinding()]
param(
  # Default = analyser repo root (..\..\ from scripts/). Override for own projects.
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\'),
  [string]$JsonPath    = $null,
  [string]$ScannerPath = $null,
  [string]$Exclusions  = '**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**,**/.sonar/**,**/node_modules/**,**/DUnitX-*/**',
  [switch]$DisableDelphi,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not $JsonPath) {
  $JsonPath = Join-Path $ProjectPath 'sca-findings.json'
}
if (-not (Test-Path $JsonPath)) {
  throw "Findings JSON not found: $JsonPath -- run sonar-scan.ps1 first."
}

# Locate sonar-scanner: PATH first, then the user's known install.
if (-not $ScannerPath) {
  $cmd = Get-Command sonar-scanner -ErrorAction SilentlyContinue
  if ($cmd) {
    $ScannerPath = $cmd.Source
  } elseif (Test-Path 'D:\git-demos\sonar-scanner-8.0.1\bin\sonar-scanner.bat') {
    $ScannerPath = 'D:\git-demos\sonar-scanner-8.0.1\bin\sonar-scanner.bat'
    Write-Host "sonar-scanner not in PATH - using fallback: $ScannerPath" -ForegroundColor DarkGray
  } else {
    throw "sonar-scanner not found in PATH and no fallback - install per sonarHowto.md section 0.1."
  }
}

# Load Sonar settings from analyser.ini
$iniPath = Join-Path $env:APPDATA 'StaticCodeAnalyser\analyser.ini'
if (-not (Test-Path $iniPath)) {
  throw "analyser.ini not found at $iniPath -- run 'analyser.exe --sonar-host <url> --sonar-project <key> --sonar-token <tok>' once to populate it."
}
$ini = Get-Content $iniPath -Raw -Encoding UTF8

function Match-IniValue([string]$key) {
  $m = [regex]::Match($ini, "(?m)^$key=(.+)$")
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value.Trim()
}

$hostUrl    = Match-IniValue 'HostUrl'
$projectKey = Match-IniValue 'ProjectKey'
$tokenRef   = Match-IniValue 'TokenRef'
if (-not $tokenRef) { $tokenRef = 'ide-default' }
$tokenHex   = Match-IniValue $tokenRef

if (-not $hostUrl)    { throw "analyser.ini [Sonar] HostUrl missing." }
if (-not $projectKey) { throw "analyser.ini [Sonar] ProjectKey missing." }
if (-not $tokenHex)   { throw "analyser.ini [SonarTokens] $tokenRef missing." }

# DPAPI-decrypt the token (Current-User scope -- only the same Windows user
# on the same machine can read it).
Add-Type -AssemblyName System.Security
$bytes = [byte[]]::new($tokenHex.Length / 2)
for ($i = 0; $i -lt $tokenHex.Length; $i += 2) {
  $bytes[$i / 2] = [Convert]::ToByte($tokenHex.Substring($i, 2), 16)
}
try {
  $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $bytes, $null, 'CurrentUser')
  $token = [System.Text.Encoding]::UTF8.GetString($plain)
} catch {
  throw "DPAPI decrypt failed - the encrypted blob was created by a different Windows user or on a different machine. Re-run analyser.exe --sonar-token <tok> to re-encrypt."
}

# Make JsonPath relative to ProjectPath so sonar-scanner picks it up
# regardless of absolute drive paths.
$relJson = ''
try {
  $relJson = (Resolve-Path $JsonPath -Relative -RelativeBasePath $ProjectPath).TrimStart('.\').TrimStart('.','/')
} catch {
  # PowerShell 5.1 lacks -RelativeBasePath -> fall back to manual prefix-strip
  $absJson = (Resolve-Path $JsonPath).Path
  $absProj = (Resolve-Path $ProjectPath).Path
  if ($absJson.StartsWith($absProj, [StringComparison]::OrdinalIgnoreCase)) {
    $relJson = $absJson.Substring($absProj.Length).TrimStart('\','/').Replace('\','/')
  } else {
    $relJson = $absJson  # absolut, sonar-scanner kommt damit klar
  }
}

$scannerArgs = @(
  "-Dsonar.host.url=$hostUrl"
  "-Dsonar.projectKey=$projectKey"
  "-Dsonar.projectName=$projectKey"
  "-Dsonar.sources=."
  "-Dsonar.sourceEncoding=UTF-8"
  "-Dsonar.exclusions=$Exclusions"
  "-Dsonar.externalIssuesReportPaths=$relJson"
)

if ($DisableDelphi) {
  # Beide Plugin-Varianten (IntegraDev = key 'delphi', alter Community-Fork
  # = key 'communitydelphi') gleichzeitig stilllegen. Leere file.suffixes
  # bewirkt: kein File matched mehr die Delphi-Language - der Sensor
  # bekommt 0 Input und exit'd ohne Stack-Trace.
  # Zusaetzlich .dproj/.dpk/.dpr aus dem Scope nehmen, weil's die sind
  # die das Plugin parsed (und an denen es bei externen Repos crashed).
  $scannerArgs += @(
    "-Dsonar.delphi.file.suffixes="
    "-Dsonar.communitydelphi.file.suffixes="
    "-Dsonar.lang.patterns.delphi="
    "-Dsonar.lang.patterns.communitydelphi="
    "-Dsonar.exclusions=$Exclusions,**/*.dproj,**/*.dpk,**/*.dpr,**/*.dpkw"
  )
  # Den ersten Exclusions-Eintrag entfernen (er kommt durch das zweite
  # Hinzufuegen oben jetzt doppelt rein - der spaetere ueberschreibt).
  $scannerArgs = $scannerArgs | Where-Object {
    $_ -ne "-Dsonar.exclusions=$Exclusions"
  } | Select-Object -Unique
}

Write-Host "Scanner:  $ScannerPath" -ForegroundColor DarkGray
Write-Host "Host:     $hostUrl"     -ForegroundColor DarkGray
Write-Host "Project:  $projectKey"  -ForegroundColor DarkGray
Write-Host "JSON:     $relJson (relative to $ProjectPath)" -ForegroundColor DarkGray
Write-Host "Token:    ($($token.Length) chars from $tokenRef)" -ForegroundColor DarkGray

if ($DryRun) {
  Write-Host ''
  Write-Host 'DRY RUN - command that would run:' -ForegroundColor Yellow
  Write-Host "  cd $ProjectPath"
  Write-Host "  `$env:SONAR_TOKEN = '***'"
  Write-Host "  $ScannerPath $($scannerArgs -join ' ')"
  exit 0
}

Write-Host ''
$env:SONAR_TOKEN = $token
$rc = 0
Push-Location $ProjectPath
try {
  & $ScannerPath @scannerArgs
  $rc = $LASTEXITCODE
} finally {
  Pop-Location
  Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
}

if ($rc -ne 0) {
  Write-Error "sonar-scanner failed with exit code $rc."
  exit $rc
}
Write-Host ''
Write-Host "Upload complete. Dashboard: $hostUrl/dashboard?id=$projectKey" -ForegroundColor Green
exit 0
