#requires -Version 5
<#
.SYNOPSIS
    Golden-Corpus-Regression-Test: scannt tests/golden-corpus/ und prueft
    dass keine als must_not_flag deklarierten Rules feuern.

.DESCRIPTION
    Phase-1-Quick-Win C.1 aus Konzept_ScannerQualitaet. Jeder Round-1-13
    Detector-Fix hinterlegt einen kleinen Pascal-Snippet in
    tests/golden-corpus/fp-reproducers/ + Eintrag in expected.json mit
    Liste der Rule-IDs die NICHT feuern duerfen.

    Skript:
      1. Findet die EXE (Output/Win64 Release/StaticCodeAnalyser.d12.exe)
      2. Scant das Korpus-Verzeichnis mit --profile strict
      3. Parst SARIF, gruppiert nach File
      4. Pro File: prueft expected.json must_not_flag-Liste
      5. Exit 0 = alle Regression-Tests gruen, Exit 1 = mind. 1 Verstoss

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\check-golden-corpus.ps1
#>

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ExePath  = '',
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($ExePath)) {
    $ExePath = Join-Path $RepoRoot 'Output\Win64 Release\StaticCodeAnalyser.d12.exe'
}
if (-not (Test-Path $ExePath)) {
    Write-Error "EXE nicht gefunden: $ExePath - im IDE bauen oder via -ExePath angeben."
    exit 2
}

$CorpusDir = Join-Path $RepoRoot 'tests\golden-corpus\fp-reproducers'
$ExpectedFile = Join-Path $CorpusDir 'expected.json'
if (-not (Test-Path $ExpectedFile)) {
    Write-Error "Erwartungs-Datei nicht gefunden: $ExpectedFile"
    exit 2
}

$Expected = Get-Content $ExpectedFile -Raw | ConvertFrom-Json
$SarifOut = Join-Path $env:TEMP 'sca-golden-corpus.sarif'

Write-Host "Scanning golden corpus: $CorpusDir"
& $ExePath --path $CorpusDir --full --profile strict --report-sarif $SarifOut --quiet | Out-Null

if (-not (Test-Path $SarifOut)) {
    Write-Error "SARIF-Output wurde nicht erzeugt: $SarifOut"
    exit 2
}

$Sarif = Get-Content $SarifOut -Raw | ConvertFrom-Json
$Findings = $Sarif.runs[0].results

# Findings pro Datei gruppieren (Basename)
$ByFile = @{}
foreach ($r in $Findings) {
    $uri = $r.locations[0].physicalLocation.artifactLocation.uri
    $base = [System.IO.Path]::GetFileName($uri)
    if (-not $ByFile.ContainsKey($base)) {
        $ByFile[$base] = @()
    }
    $ByFile[$base] += $r
}

$Violations = 0
$Checked    = 0

foreach ($prop in $Expected.files.PSObject.Properties) {
    $fileName = $prop.Name
    $rules    = $prop.Value
    $Checked++

    $found = $ByFile[$fileName]
    if (-not $found) { $found = @() }

    # MUST-NOT-FLAG-Liste durchgehen
    foreach ($mustNot in $rules.must_not_flag) {
        $offenders = $found | Where-Object { $_.ruleId -eq $mustNot }
        if ($offenders) {
            Write-Host "[FAIL] $fileName flagged $mustNot ($($offenders.Count)x) - regression!" -ForegroundColor Red
            foreach ($o in $offenders) {
                Write-Host "       Line $($o.locations[0].physicalLocation.region.startLine): $($o.message.text)"
            }
            $Violations++
        } elseif ($Verbose) {
            Write-Host "[OK]   $fileName - $mustNot nicht geflaggt" -ForegroundColor Green
        }
    }

    # EXPECTED-FINDINGS-Liste: TODO falls positive Tests dazukommen
    # (heute alle Reproducer = negativ-Tests, expected_findings ist leer)
}

Write-Host ""
if ($Violations -eq 0) {
    Write-Host "[PASS] Golden corpus check: $Checked files clean (no regressions)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] Golden corpus check: $Violations violation(s) across $Checked files" -ForegroundColor Red
    exit 1
}
