# Patch PE32+/PE Stack-Reserve auf 32 MB.
#
# Background: Delphi 12 ignoriert $MAXSTACKSIZE-Direktive in DPR und
# <DCC_MaxStackSize> in DPROJ (verifiziert via PE-Header-Inspection).
# Detektoren walken rekursiv durchs AST und sprengen den Default-Stack
# (1 MB) bei tief verschachteltem Real-World-Code (z.B. JvId3v2.pas).
#
# Diese Script patcht die Stack-Reserve direkt im PE-Header nach Build.
# Idempotent; Backup wird NICHT angelegt (Re-Build ueberschreibt EXE).
#
# Usage:
#   .\tools\patch-stack-size.ps1 'Output\Win64 Release\StaticCodeAnalyser.d12.exe'
#   .\tools\patch-stack-size.ps1 'Output\Win64 Release\StaticCodeAnalyser.d12.exe' -SizeMB 64

param(
  [Parameter(Mandatory=$true)]
  [string]$ExePath,

  [int]$SizeMB = 32
)

if (-not (Test-Path $ExePath)) {
  Write-Error "EXE not found: $ExePath"
  exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($ExePath)
$peOff = [BitConverter]::ToInt32($bytes, 0x3C)

# SizeOfStackReserve liegt in BEIDEN Formaten am Optional-Header-Offset +0x48;
# nur die Breite unterscheidet sich (PE32: DWORD, PE32+: QWORD). Die Felder
# davor gleichen sich aus: PE32 hat ein 4-Byte-ImageBase plus BaseOfData,
# PE32+ ein 8-Byte-ImageBase ohne BaseOfData.
# Magic-Wort am +0x18 = 0x20B fuer PE32+, 0x10B fuer PE32.
#
# Win32 wurde 2026-07-27 nachgeruestet: der Nutzer baut mal Win32, mal Win64,
# und ohne Patch verhungert der Scan auf tief verschachtelten Quellen. Ein
# Stack-Overflow wird dabei als Datei-Lesefehler verbucht - der Lauf sieht
# vollstaendig aus und liefert still zu wenige Funde. Genau die Sorte Fehler,
# die einen A/B-Vergleich unbemerkt wertlos macht.
$magic = [BitConverter]::ToUInt16($bytes, $peOff + 24)
switch ($magic) {
  0x20B   { $width = 8 }   # PE32+ (x64)
  0x10B   { $width = 4 }   # PE32  (x86)
  default {
    Write-Warning "Not a PE binary (magic=0x$($magic.ToString('X')))."
    exit 1
  }
}

$stkResOff = $peOff + 24 + 0x48
if ($width -eq 8) {
  $oldStack = [BitConverter]::ToUInt64($bytes, $stkResOff)
} else {
  $oldStack = [uint64][BitConverter]::ToUInt32($bytes, $stkResOff)
}
$newStack = [uint64]($SizeMB * 1MB)

if ($oldStack -eq $newStack) {
  Write-Host "Stack already $SizeMB MB - nothing to do." -ForegroundColor Green
  exit 0
}

if ($width -eq 4 -and $newStack -gt [uint32]::MaxValue) {
  Write-Error "SizeMB $SizeMB passt nicht in ein PE32-DWORD."
  exit 1
}

$stkBytes = if ($width -eq 8) { [BitConverter]::GetBytes([uint64]$newStack) }
            else              { [BitConverter]::GetBytes([uint32]$newStack) }
for ($i = 0; $i -lt $width; $i++) { $bytes[$stkResOff + $i] = $stkBytes[$i] }
[System.IO.File]::WriteAllBytes($ExePath, $bytes)

$arch = if ($width -eq 8) { 'PE32+' } else { 'PE32' }
Write-Host "Patched $ExePath ($arch)" -ForegroundColor Green
Write-Host "  SizeOfStackReserve: $($oldStack / 1MB) MB -> $($newStack / 1MB) MB"
