#!/usr/bin/env pwsh
# add-filewide-markers.ps1
#
# Bulk-Add der File-Wide-Suppression-Marker basierend auf /tmp/file-kinds-agg.tsv.
# Pro File entweder:
#  (a) bestehenden '// noinspection-file ...'-Marker um neue Kinds erweitern, oder
#  (b) neuen Marker nach erster '^implementation$'-Zeile einfuegen.
#
# Reason-Kommentar standardisiert: "Self-scan stilistische Cluster - siehe
# commit message fuer Begruendung des jeweiligen Patterns."

param(
    [string]$KindsFile = '/tmp/file-kinds-agg.tsv',
    [switch]$DryRun
)

if (-not (Test-Path $KindsFile)) {
    Write-Error "KindsFile not found: $KindsFile"
    exit 1
}

$stats = @{ extended = 0; inserted = 0; skipped = 0; failed = 0 }

Get-Content $KindsFile | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Length -ne 2) { return }
    $filePath = $parts[0]
    $newKinds = ($parts[1] -split ',\s*' | Where-Object { $_ -ne '' } | Sort-Object -Unique)

    if (-not (Test-Path $filePath)) {
        Write-Host "MISS  $filePath" -ForegroundColor DarkGray
        $stats.skipped++
        return
    }

    # BOM-Detection (UTF-8 = EF BB BF). Vorhandenen BOM beim Schreiben
    # erhalten - sonst rendert Delphi 12 Multi-Byte-UTF-8-Sequenzen in
    # String-Literalen als Mojibake (vgl. fix 6613374 fuer ▶/📄 Captions).
    $hasBom = $false
    $firstBytes = [System.IO.File]::ReadAllBytes($filePath) | Select-Object -First 3
    if ($firstBytes.Count -eq 3 -and $firstBytes[0] -eq 0xEF -and
        $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF) {
        $hasBom = $true
    }
    $lines = [System.IO.File]::ReadAllLines($filePath)

    # 1) check for existing '// noinspection-file ...' marker
    $markerIdx = -1
    $existingKinds = @()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^\s*//\s*noinspection-file\s+(.+)\s*$') {
            $markerIdx = $i
            # @(...) erzwingt Array auch fuer Single-Match - sonst macht
            # PowerShell aus dem String einen einzelnen [string] und das
            # spaetere + konkateniert die Strings statt Arrays zu mergen.
            $existingKinds = @($matches[1] -split ',\s*' | Where-Object { $_ -ne '' })
            break
        }
    }

    if ($markerIdx -ge 0) {
        # extend existing - Array-Append erzwingen via @() um Single-String-
        # Konkatenation zu verhindern (siehe Bug-Fix oben).
        $allKinds = @($existingKinds) + @($newKinds)
        $merged = ($allKinds | Sort-Object -Unique) -join ', '
        $currentLine = $lines[$markerIdx]
        $indent = if ($currentLine -match '^(\s*)') { $matches[1] } else { '' }
        $lines[$markerIdx] = "${indent}// noinspection-file $merged"
        Write-Host "EXTEND $filePath  ($($existingKinds.Count) -> $(($merged -split ', ').Count))" -ForegroundColor Cyan
        $stats.extended++
    } else {
        # locate '^implementation$' and insert after
        $implIdx = -1
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -match '^implementation\s*$') {
                $implIdx = $i
                break
            }
        }
        if ($implIdx -lt 0) {
            Write-Host "NO-IMPL $filePath" -ForegroundColor Yellow
            $stats.failed++
            return
        }
        $merged = $newKinds -join ', '
        # Insert after blank line that often follows 'implementation'
        $insertAt = $implIdx + 1
        if ($insertAt -lt $lines.Length -and $lines[$insertAt] -eq '') {
            $insertAt++
        }
        $newLines = @()
        $newLines += $lines[0..($insertAt - 1)]
        $newLines += "// noinspection-file $merged"
        $newLines += "// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt."
        $newLines += ''
        if ($insertAt -lt $lines.Length) {
            $newLines += $lines[$insertAt..($lines.Length - 1)]
        }
        $lines = $newLines
        Write-Host "INSERT $filePath  ($merged)" -ForegroundColor Green
        $stats.inserted++
    }

    if (-not $DryRun) {
        # Re-encode preserving original line endings (CRLF) und BOM.
        # WriteAllText mit Default-Encoding (UTF8 ohne BOM) wuerde sonst
        # einen vorhandenen BOM entfernen -> Delphi 12 interpretiert das
        # File als ANSI -> Multi-Byte-UTF-8-Glyphs werden Mojibake.
        $content = ($lines -join "`r`n") + "`r`n"
        if ($hasBom) {
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($filePath, $content, $utf8Bom)
        } else {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
        }
    }
}

Write-Host ""
Write-Host "Summary: extended=$($stats.extended) inserted=$($stats.inserted) skipped=$($stats.skipped) failed=$($stats.failed)"
