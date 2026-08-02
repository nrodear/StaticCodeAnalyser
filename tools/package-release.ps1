# Release-Artefakte bauen: patchen -> pruefen -> zippen.
#
# WARUM ES DIESES SKRIPT GIBT: am 2026-08-02 ist v0.9.10 mit UNGEPATCHTEN
# Exen rausgegangen. Die Exen wurden direkt aus Output\ gezippt, und der
# Stack-Patch wird bei JEDEM Build zurueckgesetzt - er stand nirgends im
# Ablauf, nur im Gedaechtnis. v0.9.8 und v0.9.9 waren gepatcht, v0.9.10
# nicht; aufgefallen ist es erst beim Nachfragen.
#
# Der Patch ist nicht kosmetisch: die Detektoren laufen rekursiv durch den
# AST, und tief verschachtelter Real-World-Code sprengt den 1-MB-Default.
# Ein Stack-Overflow wird dabei als DATEI-LESEFEHLER verbucht - der Lauf
# sieht vollstaendig aus und liefert still zu wenige Funde.
#
# Deshalb prueft dieses Skript NACH dem Patchen noch einmal den PE-Header
# und bricht ab, wenn die Reserve nicht stimmt. Ein Zip entsteht nur aus
# einer verifizierten Exe.
#
# Usage:
#   .\tools\package-release.ps1 -Version 0.9.10
#   .\tools\package-release.ps1 -Version 0.9.10 -OutDir C:\temp\rel
#   .\tools\package-release.ps1 -Version 0.9.10 -SkipSource
#
# Danach:
#   gh release create v<Version> --title ... --notes-file ... <OutDir>\*.zip

param(
  [Parameter(Mandatory=$true)]
  [string]$Version,

  [string]$OutDir = 'release-artifacts',

  [int]$StackMB = 32,

  [switch]$SkipSource
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

function Get-StackReserveMB([string]$Path) {
  # SizeOfStackReserve liegt in PE32 und PE32+ am Optional-Header-Offset
  # +0x48; nur die Breite unterscheidet sich. Siehe patch-stack-size.ps1.
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
  $magic = [BitConverter]::ToUInt16($bytes, $peOff + 24)
  $off   = $peOff + 24 + 0x48
  if ($magic -eq 0x20B) {
    return [BitConverter]::ToUInt64($bytes, $off) / 1MB
  } elseif ($magic -eq 0x10B) {
    return [BitConverter]::ToUInt32($bytes, $off) / 1MB
  } else {
    throw "Keine PE-Datei: $Path (magic=0x$($magic.ToString('X')))"
  }
}

$outPath = Join-Path $repo $OutDir
if (-not [System.IO.Path]::IsPathRooted($OutDir)) { $OutDir = $outPath }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

$platforms = @(
  @{ Name = 'Win64'; Exe = 'Output\Win64 Release\StaticCodeAnalyser.d12.exe' },
  @{ Name = 'Win32'; Exe = 'Output\Win32 Release\StaticCodeAnalyser.d12.exe' }
)

foreach ($p in $platforms) {
  $exe = Join-Path $repo $p.Exe
  if (-not (Test-Path $exe)) { throw "Exe fehlt: $exe - erst bauen." }

  # 1. Meldet die Exe ueberhaupt die Version, die verpackt werden soll?
  #    Faengt den Fall "vergessen zu bauen" ab, der sonst still eine alte
  #    Exe unter neuer Nummer ausliefert.
  $reported = (& $exe --version 2>&1 | Select-Object -First 1)
  if ($reported -notmatch [regex]::Escape($Version)) {
    throw "$($p.Name): Exe meldet '$reported', erwartet wurde $Version. Nicht gebaut?"
  }

  # 2. Patchen (idempotent).
  & (Join-Path $PSScriptRoot 'patch-stack-size.ps1') $exe -SizeMB $StackMB | Out-Null

  # 3. NACHPRUEFEN statt vertrauen - das ist der Punkt des Skripts.
  $mb = Get-StackReserveMB $exe
  if ($mb -ne $StackMB) {
    throw "$($p.Name): Stack-Reserve ist $mb MB, erwartet $StackMB MB. Abbruch."
  }

  $zip = Join-Path $OutDir "StaticCodeAnalyser-v$Version-$($p.Name).zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path $exe -DestinationPath $zip -CompressionLevel Optimal
  "{0,-6} {1} v{2}  Stack {3} MB  ->  {4}" -f `
    $p.Name, (Split-Path $exe -Leaf), $Version, $mb, (Split-Path $zip -Leaf)
}

if (-not $SkipSource) {
  # Aus dem TAG, nicht aus dem Arbeitsbaum: so landet nichts Ungetaggtes
  # im Archiv, und gitignorierte interne Dokumente bleiben ohnehin draussen.
  $tag = "v$Version"
  $null = git -C $repo rev-parse $tag 2>$null
  if (-not $?) { throw "Tag $tag existiert nicht - erst taggen." }
  $src = Join-Path $OutDir "StaticCodeAnalyser-v$Version-source.zip"
  if (Test-Path $src) { Remove-Item $src -Force }
  git -C $repo archive --format=zip --prefix="StaticCodeAnalyser-$Version/" -o $src $tag
  "{0,-6} aus Tag {1}  ->  {2}" -f 'source', $tag, (Split-Path $src -Leaf)
}

""
"Artefakte in: $OutDir"
