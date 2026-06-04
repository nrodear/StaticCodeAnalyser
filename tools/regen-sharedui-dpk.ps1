# Regeneriert SCA.SharedUI\SCA.SharedUI.dpk aus dem aktuellen Stand von
# SCA.SharedUI\sources\**\*.pas. Idempotent (analog regen-engine-dpk.ps1).

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$sourcesDir = 'SCA.SharedUI\sources'
if (-not (Test-Path $sourcesDir)) {
    Write-Error "Sources-Verzeichnis nicht gefunden: $sourcesDir"
    exit 1
}

$files = Get-ChildItem -Recurse -Path $sourcesDir -Filter *.pas |
    Sort-Object FullName |
    ForEach-Object {
        $unitName = $_.BaseName
        $relPath  = $_.FullName.Substring((Get-Location).Path.Length + 1)
        $relPath  = $relPath -replace '^SCA\.SharedUI\\', ''
        "  $unitName in '$relPath',"
    }

if ($files.Count -eq 0) {
    Write-Error "Keine .pas-Files in $sourcesDir gefunden"
    exit 1
}

$last = $files[-1].TrimEnd(',')
$filesArr = @($files[0..($files.Count-2)]) + @($last)
$containsBlock = $filesArr -join "`r`n"

$dpkContent = @"
package SCA.SharedUI;

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
  rtl,
  vcl,
  vclwinx,
  designide,
  SCA.Engine;

contains
$containsBlock
;

end.
"@

$out = 'SCA.SharedUI\SCA.SharedUI.dpk'
$dpkContent | Out-File -FilePath $out -Encoding utf8 -NoNewline
Write-Host "Regenerated $out with $($files.Count) units."
