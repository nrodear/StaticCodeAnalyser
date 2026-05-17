#!/usr/bin/env pwsh
# Git pre-commit hook: runs Static Code Analyser on the .pas/.dfm files
# changed in the working tree, fails the commit on Warnings or Errors.
#
# Install:
#   1. Copy this file to .git\hooks\pre-commit  (no extension!)
#   2. On Windows: ensure pwsh.exe is in PATH (PowerShell 7+) - or
#      adapt the shebang to powershell.exe (5.1).
#   3. Make sure analyser.d12.exe is reachable - adjust $SCA_EXE below.
#
# Usage:
#   git commit       (hook runs automatically)
#   git commit --no-verify    (bypass hook - emergency only)
#
# Exit-Code-Mapping:
#   0 -> commit proceeds
#   non-0 -> commit aborted (analyser reported findings)

$ErrorActionPreference = 'Stop'
$SCA_EXE   = Join-Path $PSScriptRoot '..\..\tools\sca\analyser.d12.exe'
$BASELINE  = Join-Path $PSScriptRoot '..\..\sca.baseline.json'
$REPO_ROOT = (git rev-parse --show-toplevel).Trim()

if (-not (Test-Path $SCA_EXE)) {
    Write-Host "[sca-hook] analyser.d12.exe not found at $SCA_EXE - skipping."
    exit 0
}

# Snapshot for SARIF (optional, helpful for `git stash` debugging)
$SarifOut = Join-Path $env:TEMP "sca-precommit-$(Get-Date -Format 'yyyyMMdd-HHmmss').sarif"

# --branch picks up .pas/.dfm files that differ from main (working-tree-aware)
# --fail-on=warning: hints are reported but the commit goes through; warnings
#                    and errors abort the commit so they get fixed BEFORE
#                    they enter history.
$BaselineArg = @()
if (Test-Path $BASELINE) {
    $BaselineArg = @('--baseline', $BASELINE)
}

& $SCA_EXE `
    --path $REPO_ROOT `
    --branch `
    --quiet `
    --fail-on=warning `
    --report-sarif $SarifOut `
    @BaselineArg

$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0) {
    Write-Host ""
    Write-Host "[sca-hook] Static Code Analyser blocked the commit (exit $ExitCode)." -ForegroundColor Red
    Write-Host "[sca-hook] See SARIF report: $SarifOut" -ForegroundColor Yellow
    Write-Host "[sca-hook] To bypass (emergency): git commit --no-verify" -ForegroundColor DarkGray
}

exit $ExitCode
