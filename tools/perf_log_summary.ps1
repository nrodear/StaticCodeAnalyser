#requires -Version 5.1
<#
.SYNOPSIS
    Wertet eine SCA-Analyselauf-Log-Datei aus und produziert eine
    Markdown-Zusammenfassung der Top-Hotspots (Parser + Detektoren).

.DESCRIPTION
    Der SCA loggt pro analysierter Datei:
      [<idx>/<total>] <file> (<size> KB)
        Parse: <ms> ms [(langsam!)]
        Detektor <name>: <ms> ms [(langsam!)]

    Dieses Skript saugt die Zeilen ein und produziert:
      - Top-20 langsamste Dateien (gesamt Parse-Zeit)
      - Per-Detector Aggregat: Anzahl Calls + Summe ms + Average + Max
      - Liste aller "langsam!"-markierten Events

.PARAMETER LogFile
    Pfad zur SCA-Log-Datei. Default: sca.log im aktuellen Verzeichnis.

.PARAMETER OutputFile
    Optional: Markdown-Output in Datei statt STDOUT.

.EXAMPLE
    PS> .\tools\perf_log_summary.ps1 -LogFile sca.log
    PS> .\tools\perf_log_summary.ps1 -LogFile sca.log -OutputFile perf.md
#>

param(
    [string] $LogFile = 'sca.log',
    [string] $OutputFile = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LogFile)) {
    Write-Error "Log-File nicht gefunden: $LogFile"
    exit 1
}

$content = Get-Content -Path $LogFile -Raw -Encoding UTF8
$lines = $content -split "`r?`n"

# Parse-Events sammeln
$fileEntries = New-Object System.Collections.Generic.List[object]
$detectorEntries = New-Object System.Collections.Generic.List[object]
$slowEvents = New-Object System.Collections.Generic.List[object]

$currentFile = $null
$currentSize = 0

foreach ($line in $lines) {
    # Header: '[3/47] D:\foo\bar.pas (12 KB)'
    if ($line -match '^\[\d+/\d+\]\s+(.+?)\s+\((\d+)\s+KB\)') {
        $currentFile = $Matches[1]
        $currentSize = [int] $Matches[2]
        continue
    }
    # Parse-Zeit: '  Parse: 142 ms [(langsam!)]'
    if ($line -match '^\s+Parse:\s+(\d+)\s+ms') {
        $ms = [int] $Matches[1]
        $isSlow = $line -match 'langsam'
        $fileEntries.Add([pscustomobject]@{
            File   = $currentFile
            SizeKB = $currentSize
            ParseMs = $ms
            Slow   = $isSlow
        })
        if ($isSlow) {
            $slowEvents.Add([pscustomobject]@{
                Type = 'Parse'
                Name = $currentFile
                Ms   = $ms
            })
        }
        continue
    }
    # Detektor-Zeit: '  Detektor LeakDetector: 320 ms (langsam!)'
    if ($line -match '^\s+Detektor\s+(\S+):\s+(\d+)\s+ms') {
        $name = $Matches[1]
        $ms = [int] $Matches[2]
        $isSlow = $line -match 'langsam'
        $detectorEntries.Add([pscustomobject]@{
            File = $currentFile
            Detector = $name
            Ms       = $ms
            Slow     = $isSlow
        })
        if ($isSlow) {
            $slowEvents.Add([pscustomobject]@{
                Type = 'Detector'
                Name = "$name @ $currentFile"
                Ms   = $ms
            })
        }
        continue
    }
}

# Helper-Function fuer Output
$sb = New-Object System.Text.StringBuilder
function Out([string] $s) {
    $sb.AppendLine($s) | Out-Null
}

Out '# SCA Performance-Log Summary'
Out ''
Out ("Quelle: ``{0}`` ({1} Zeilen, {2:N0} Bytes)" -f $LogFile, $lines.Count, ((Get-Item $LogFile).Length))
Out ("Files analysiert: {0}, Detector-Events: {1}, Slow-Events: {2}" -f `
    $fileEntries.Count, $detectorEntries.Count, $slowEvents.Count)
Out ''

# Top-20 langsamste Dateien
Out '## Top-20 langsamste Parse-Operationen'
Out ''
Out '| File | Size (KB) | Parse (ms) |'
Out '|---|---:|---:|'
$top = $fileEntries | Sort-Object -Property ParseMs -Descending | Select-Object -First 20
foreach ($e in $top) {
    Out ("| {0} | {1} | {2} |" -f $e.File, $e.SizeKB, $e.ParseMs)
}
Out ''

# Aggregat: Total parse time + average
if ($fileEntries.Count -gt 0) {
    $totalParseMs = ($fileEntries | Measure-Object -Property ParseMs -Sum).Sum
    $avgParseMs = ($fileEntries | Measure-Object -Property ParseMs -Average).Average
    $maxParseMs = ($fileEntries | Measure-Object -Property ParseMs -Maximum).Maximum
    Out ("**Parse total**: {0:N0} ms | Avg: {1:N1} ms/File | Max: {2:N0} ms" -f `
        $totalParseMs, $avgParseMs, $maxParseMs)
    Out ''
}

# Per-Detector Aggregat
Out '## Per-Detector Aggregat'
Out ''
Out '| Detector | Calls | Sum (ms) | Avg (ms) | Max (ms) | Slow |'
Out '|---|---:|---:|---:|---:|---:|'
$grouped = $detectorEntries | Group-Object -Property Detector
$detRows = foreach ($g in $grouped) {
    $sum = ($g.Group | Measure-Object -Property Ms -Sum).Sum
    $avg = ($g.Group | Measure-Object -Property Ms -Average).Average
    $max = ($g.Group | Measure-Object -Property Ms -Maximum).Maximum
    $slowCount = ($g.Group | Where-Object Slow).Count
    [pscustomobject]@{
        Detector = $g.Name
        Calls    = $g.Count
        SumMs    = $sum
        AvgMs    = $avg
        MaxMs    = $max
        SlowCount = $slowCount
    }
}
$detRows = $detRows | Sort-Object -Property SumMs -Descending
foreach ($r in $detRows) {
    Out ("| {0} | {1} | {2:N0} | {3:N1} | {4:N0} | {5} |" -f `
        $r.Detector, $r.Calls, $r.SumMs, $r.AvgMs, $r.MaxMs, $r.SlowCount)
}
Out ''

# Slow-Events
if ($slowEvents.Count -gt 0) {
    Out '## Slow-Events (> 500 ms)'
    Out ''
    Out '| Type | Name | Ms |'
    Out '|---|---|---:|'
    foreach ($s in ($slowEvents | Sort-Object -Property Ms -Descending)) {
        Out ("| {0} | {1} | {2} |" -f $s.Type, $s.Name, $s.Ms)
    }
}

$markdown = $sb.ToString()
if ($OutputFile -ne '') {
    Set-Content -Path $OutputFile -Value $markdown -Encoding UTF8
    Write-Host "Geschrieben: $OutputFile"
} else {
    Write-Output $markdown
}
