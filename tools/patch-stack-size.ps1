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

# PE32+ Optional Header layout: SizeOfStackReserve at +0x48
# (PE32 (32-bit) waere +0x48 mit 4-Byte-Wert, hier 8-Byte-uint64).
# Magic-Wort am +0x18 = 0x20B fuer PE32+, 0x10B fuer PE32.
$magic = [BitConverter]::ToUInt16($bytes, $peOff + 24)
if ($magic -ne 0x20B) {
  Write-Warning "Not a PE32+ binary (magic=0x$($magic.ToString('X')))."
  exit 1
}

$stkResOff = $peOff + 24 + 0x48
$oldStack  = [BitConverter]::ToUInt64($bytes, $stkResOff)
$newStack  = [uint64]($SizeMB * 1MB)

if ($oldStack -eq $newStack) {
  Write-Host "Stack already $SizeMB MB - nothing to do." -ForegroundColor Green
  exit 0
}

# Endian-write uint64
$stkBytes = [BitConverter]::GetBytes([uint64]$newStack)
for ($i = 0; $i -lt 8; $i++) { $bytes[$stkResOff + $i] = $stkBytes[$i] }
[System.IO.File]::WriteAllBytes($ExePath, $bytes)

Write-Host "Patched $ExePath" -ForegroundColor Green
Write-Host "  SizeOfStackReserve: $($oldStack / 1MB) MB -> $($newStack / 1MB) MB"
