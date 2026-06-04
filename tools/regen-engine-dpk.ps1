# Regeneriert SCA.Engine\SCA.Engine.dpk aus dem aktuellen Stand von
# SCA.Engine\sources\**\*.pas. Idempotent.
#
# Aufruf: tools\regen-engine-dpk.ps1
#
# Hintergrund: das contains-Block muss synchron mit den Source-Files
# bleiben, sonst bricht der BPL-Build. Statt manuelles Tracking schreibt
# dieses Skript den Block neu - eingecheckt in git, manuelles Editieren
# nur am Header (Compiler-Direktiven) noetig.

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$sourcesDir = 'SCA.Engine\sources'
if (-not (Test-Path $sourcesDir)) {
    Write-Error "Sources-Verzeichnis nicht gefunden: $sourcesDir"
    exit 1
}

$files = Get-ChildItem -Recurse -Path $sourcesDir -Filter *.pas |
    Sort-Object FullName |
    ForEach-Object {
        $unitName = $_.BaseName
        $relPath  = $_.FullName.Substring((Get-Location).Path.Length + 1)
        # SCA.Engine\sources\... -> sources\... (relativ zum dpk-Speicherort)
        $relPath  = $relPath -replace '^SCA\.Engine\\', ''
        "  $unitName in '$relPath',"
    }

if ($files.Count -eq 0) {
    Write-Error "Keine .pas-Files in $sourcesDir gefunden"
    exit 1
}

# Letzten Eintrag: Komma weg
$last = $files[-1].TrimEnd(',')
$filesArr = @($files[0..($files.Count-2)]) + @($last)
$containsBlock = $filesArr -join "`r`n"

$dpkContent = @"
package SCA.Engine;

{`$R *.res}
{`$IFDEF IMPLICITBUILDING This IFDEF should not be used by users}
{`$ALIGN 8}
{`$ASSERTIONS ON}
{`$BOOLEVAL OFF}
{`$DEBUGINFO OFF}
{`$EXTENDEDSYNTAX ON}
{`$IMPORTEDDATA ON}
{`$IOCHECKS ON}
{`$LOCALSYMBOLS ON}
{`$LONGSTRINGS ON}
{`$OPENSTRINGS ON}
{`$OPTIMIZATION OFF}
{`$OVERFLOWCHECKS ON}
{`$RANGECHECKS ON}
{`$REFERENCEINFO ON}
{`$SAFEDIVIDE OFF}
{`$STACKFRAMES ON}
{`$TYPEDADDRESS OFF}
{`$VARSTRINGCHECKS ON}
{`$WRITEABLECONST OFF}
{`$MINENUMSIZE 1}
{`$IMAGEBASE `$400000}
{`$DEFINE DEBUG}
{`$ENDIF IMPLICITBUILDING}
{`$IMPLICITBUILD ON}

requires
  rtl;

contains
$containsBlock
;

end.
"@

$out = 'SCA.Engine\SCA.Engine.dpk'
$dpkContent | Out-File -FilePath $out -Encoding utf8 -NoNewline
Write-Host "Regenerated $out with $($files.Count) units."
