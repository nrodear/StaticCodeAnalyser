# Adds 'TooLongLine' to every '// noinspection-file ...' marker so the
# marker line itself (often > 80 chars due to many kinds) doesn't trigger
# SCA062. Idempotent: skips if TooLongLine already present.

Get-ChildItem -Path 'SCA.Engine','SCA.SharedUI','StaticCodeAnalyserForm','StaticCodeAnalyserIDE' -Filter '*.pas' -Recurse | ForEach-Object {
    $path = $_.FullName
    if ($path -match '__history') { return }

    # BOM-Detection (UTF-8) - muss beim Schreiben erhalten bleiben
    # sonst rendert Delphi 12 Multi-Byte-UTF-8 in String-Literalen als
    # Mojibake (fix 6613374 / iter 8 wiederherstellung).
    $hasBom = $false
    $firstBytes = [System.IO.File]::ReadAllBytes($path) | Select-Object -First 3
    if ($firstBytes.Count -eq 3 -and $firstBytes[0] -eq 0xEF -and
        $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF) {
        $hasBom = $true
    }
    $lines = [System.IO.File]::ReadAllLines($path)
    $changed = $false

    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^(\s*//\s*noinspection-file\s+)(.+?)\s*$') {
            $prefix = $matches[1]
            $kinds = @($matches[2] -split ',\s*' | Where-Object { $_ -ne '' })
            if ($kinds -notcontains 'TooLongLine') {
                $kinds = @($kinds) + 'TooLongLine'
                $merged = ($kinds | Sort-Object -Unique) -join ', '
                $lines[$i] = "$prefix$merged"
                $changed = $true
                Write-Host "PATCH $path"
                break
            }
        }
    }

    if ($changed) {
        $content = ($lines -join "`r`n") + "`r`n"
        $enc = New-Object System.Text.UTF8Encoding($hasBom)
        [System.IO.File]::WriteAllText($path, $content, $enc)
    }
}
