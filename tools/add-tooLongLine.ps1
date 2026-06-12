# Adds 'TooLongLine' to every '// noinspection-file ...' marker so the
# marker line itself (often > 80 chars due to many kinds) doesn't trigger
# SCA062. Idempotent: skips if TooLongLine already present.

Get-ChildItem -Path 'SCA.Engine','SCA.SharedUI','StaticCodeAnalyserForm','StaticCodeAnalyserIDE' -Filter '*.pas' -Recurse | ForEach-Object {
    $path = $_.FullName
    if ($path -match '__history') { return }

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
        [System.IO.File]::WriteAllText($path, ($lines -join "`r`n") + "`r`n")
    }
}
