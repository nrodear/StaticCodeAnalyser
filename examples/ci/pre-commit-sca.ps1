# Git pre-commit hook: runs Static Code Analyser on the .pas/.dfm files
# changed in the working tree, fails the commit on Warnings or Errors.
#
# Install (details: examples/ci/README.md, "pre-commit-sca.ps1"):
#   1. Copy this file to .git\hooks\pre-commit-sca.ps1 - KEEP the .ps1
#      extension. Do not copy it as .git\hooks\pre-commit: Git for Windows
#      starts hooks through sh, and PowerShell does not run a file without
#      the .ps1 extension - the hook body never runs and every commit
#      goes through.
#   2. Create .git\hooks\pre-commit as a two-line sh wrapper (LF line
#      endings) that calls this script with -File and hands its exit code
#      to Git:
#        #!/bin/sh
#        exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/pre-commit-sca.ps1"
#   3. Make sure StaticCodeAnalyser.d12.exe is reachable - adjust $SCA_EXE
#      below. If it is missing, the hook prints a note and lets the
#      commit through.
#
# Usage:
#   git commit       (hook runs automatically)
#   git commit --no-verify    (bypass hook - emergency only)
#
# Exit-Code-Mapping:
#   0 -> commit proceeds
#   non-0 -> commit aborted (analyser reported findings)

$ErrorActionPreference = 'Stop'
$SCA_EXE   = Join-Path $PSScriptRoot '..\..\tools\sca\StaticCodeAnalyser.d12.exe'
$BASELINE  = Join-Path $PSScriptRoot '..\..\sca.baseline.json'
$REPO_ROOT = (git rev-parse --show-toplevel).Trim()

if (-not (Test-Path $SCA_EXE)) {
    Write-Host "[sca-hook] StaticCodeAnalyser.d12.exe not found at $SCA_EXE - skipping."
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

# "| Out-Host" is required: StaticCodeAnalyser.d12.exe is a GUI-subsystem
# program that also serves the CLI. PowerShell does not wait for such a
# program unless its output is piped - $LASTEXITCODE would then still hold
# the 0 of "git rev-parse" above, and every commit would go through.
& $SCA_EXE `
    --path $REPO_ROOT `
    --branch `
    --quiet `
    --fail-on=warning `
    --report-sarif $SarifOut `
    @BaselineArg | Out-Host

$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0) {
    Write-Host ""
    Write-Host "[sca-hook] Static Code Analyser blocked the commit (exit $ExitCode)." -ForegroundColor Red
    Write-Host "[sca-hook] See SARIF report: $SarifOut" -ForegroundColor Yellow
    Write-Host "[sca-hook] To bypass (emergency): git commit --no-verify" -ForegroundColor DarkGray
}

exit $ExitCode
