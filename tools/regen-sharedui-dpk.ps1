# Regeneriert NUR die contains-Klausel von SCA.SharedUI\SCA.SharedUI.dpk
# aus SCA.SharedUI\sources\**\*.pas.
#
# NEUFASSUNG 2026-09-05: die alte Fassung schrieb die GANZE Datei aus
# einem Standardkopf neu und zerstoerte dabei den handgepflegten
# {$RUNONLY}-Block samt der requires-Begruendungen (deshalb stand sie
# seit 2026-08-16 als DEFEKT in den Notizen; Projektdateien wurden von
# Hand gepflegt). Jetzt wird die Datei byte-erhaltend gelesen (Latin-1-
# Roundtrip, verlustfrei je Byte) und ausschliesslich der Text zwischen
# "contains" und dem naechsten ";" ersetzt - Kopf, requires, Kommentare
# und Zeilenenden bleiben unangetastet. Idempotent: ohne Datei-Drift ist
# der git-Diff nach einem Lauf LEER.

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$dpkPath    = 'SCA.SharedUI\SCA.SharedUI.dpk'
$sourcesDir = 'SCA.SharedUI\sources'
$prefix     = '^SCA\.SharedUI\\'

if (-not (Test-Path $sourcesDir)) { Write-Error "Sources-Verzeichnis nicht gefunden: $sourcesDir" }
if (-not (Test-Path $dpkPath))    { Write-Error ".dpk nicht gefunden: $dpkPath" }

$unitLines = Get-ChildItem -Recurse -Path $sourcesDir -Filter *.pas |
    Sort-Object FullName |
    ForEach-Object {
        $relPath = $_.FullName.Substring((Get-Location).Path.Length + 1) -replace $prefix, ''
        "  $($_.BaseName) in '$relPath'"
    }
if (-not $unitLines) { Write-Error "Keine .pas-Dateien unter $sourcesDir" }

# Latin-1 ist eine 1:1-Byte-Abbildung - der Rest der Datei bleibt exakt.
$enc = [System.Text.Encoding]::GetEncoding(28591)
$raw = $enc.GetString([System.IO.File]::ReadAllBytes($dpkPath))

$m = [regex]::Match($raw, '(?m)^contains\s*?\r?\n')
if (-not $m.Success) { Write-Error "Keine contains-Klausel in $dpkPath - nichts ersetzt." }
$start = $m.Index + $m.Length
$semi  = $raw.IndexOf(';', $start)
if ($semi -lt 0) { Write-Error "contains-Klausel ohne ';' in $dpkPath - nichts ersetzt." }

$neu = $raw.Substring(0, $start) + (($unitLines -join ",`r`n")) + $raw.Substring($semi)
[System.IO.File]::WriteAllBytes($dpkPath, $enc.GetBytes($neu))
Write-Host "contains-Klausel von $dpkPath erneuert: $($unitLines.Count) Units (Rest der Datei unveraendert)."
