# Branding-Assets

Single source of truth fuer App-Icon und IDE-Plugin-Bitmap. Folgt der
**canonical Embarcadero**-Konvention — siehe
[Application_Icon docwiki](https://docwiki.embarcadero.com/RADStudio/Athens/en/Application_Icon)
und [OTAPI-Docs Kapitel 9](https://github.com/Embarcadero/OTAPI-Docs).

## Dateien

| Datei | Zweck |
|---|---|
| `sca.png` | Quell-Image (297×242). Wird **nicht direkt** im Build verwendet, sondern als Source fuer die generierten `.ico` und `.bmp` (siehe "Regenerieren" unten). |
| `sca.ico` | Multi-Resolution-Icon (16/32/48/256 jeweils PNG-komprimiert in der ICO-Huelle). Wird als `MAINICON`-Resource in die Standalone-EXE einkompiliert (Delphi's eigene Toolchain, kein BRCC32). |
| `sca_small.ico` | Reduziertes ICO (NUR 16/32/48, kein 256er) fuer das IDE-Plugin-Window-Caption. **MUSS BMP-encoded sein** (klassisches ICO-Format von 1995), nicht PNG-compressed wie `sca.ico`. BRCC32 versteht das moderne PNG-in-ICO-Format nicht und kippt sonst mit `Allocate failed`. |
| `sca_24.bmp` | 24×24 Windows-BMP (24-bit, kein Alpha — BRCC32-tauglich) fuer das IDE-Plugin (Splash + About-Box, IOTA-API verlangt BMP via LoadBitmap). |
| `sca_branding.rc` | `SCA_APP_BMP BITMAP "sca_24.bmp"` + `SCA_APP_ICO ICON "sca_small.ico"`. Beide gehen ueber BRCC32. |

## Standalone-EXE — canonical MAINICON-Pfad

| Stelle | Inhalt |
|---|---|
| `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` | `<Icon_MainIcon>..\branding\sca.ico</Icon_MainIcon>` |
| Auto-Mechanismus | Delphi packt das ICO als `MAINICON`-Resource in die auto-generierte `StaticCodeAnalyser.d12.res`. `{$R *.res}` im `.dpr` linkt das automatisch ein. |
| Runtime | `Application.Icon` wird beim Start automatisch aus `MAINICON` gefuellt. Windows nutzt es fuer **Shell/Explorer-Icon, Taskbar (vor und waehrend Run), Window-Caption, Alt-Tab**. |

Kein `{$R}` fuer Branding noetig, kein `uBrandingImage`-Helper, kein
Runtime-PNG-Decoder. Nur die dproj-Zeile.

## IDE-Plugin — LoadBitmap-Pattern

| Stelle | Inhalt |
|---|---|
| `StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dproj` | `<RcCompile Include="..\branding\sca_branding.rc"/>` triggert BRCC32 → `sca_branding.res` neben der dpk |
| `StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk` | `{$R 'sca_branding.res'}` linkt die Resource in die BPL |
| `uIDEExpert.pas` | `LoadBitmap(HInstance, 'SCA_APP_BMP')` liefert das `HBITMAP` direkt — kein TBitmap-Wrapper, kein PngImage |
| IOTA-Pfad | `SplashScreenServices.AddPluginBitmap(.., HBmp, ..)` (waehrend IDE-Boot) und `IOTAAboutBoxServices.AddPluginInfo(.., HBmp, ..)` (Help → About → Plugins) |

## Regenerieren (wenn `sca.png` sich aendert)

Ein einmaliges PowerShell-Snippet erzeugt beide Derivat-Assets aus dem PNG.
Schreibe folgendes in eine `_regen.ps1` neben den Assets, run, wieder loeschen:

```powershell
Add-Type -AssemblyName System.Drawing
$png = [System.Drawing.Image]::FromFile("$PSScriptRoot\sca.png")
# 24x24 BMP fuer IDE-Plugin. WICHTIG: Format24bppRgb (nicht Default 32bppArgb)
# - BRCC32 stammt aus der 16-bit-Era und lehnt 32-bit-DIB mit
# 'Invalid bitmap format' ab. Kein Alpha-Channel -> weisser Hintergrund.
$fmt = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
$b = New-Object System.Drawing.Bitmap 24, 24, $fmt
$g = [System.Drawing.Graphics]::FromImage($b)
$g.InterpolationMode = 'HighQualityBicubic'
$g.Clear([System.Drawing.Color]::White)
$g.DrawImage($png, 0, 0, 24, 24)
$b.Save("$PSScriptRoot\sca_24.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
$g.Dispose(); $b.Dispose()
# Multi-res ICO (16/32/48/256) - jede Groesse PNG-komprimiert.
# Zweite Variante 'sca_small.ico' OHNE 256 fuer das IDE-Plugin - BRCC32
# (16-bit-Erbe) kippt mit 'Allocate failed' beim 256x256-Sub-Icon.
foreach ($outName in @('sca.ico', 'sca_small.ico')) {
$sizes = if ($outName -eq 'sca_small.ico') { @(16, 32, 48) } else { @(16, 32, 48, 256) }
$pngBytes = @{}
foreach ($s in $sizes) {
  $b = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($png, 0, 0, $s, $s)
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngBytes[$s] = $ms.ToArray()
  $g.Dispose(); $b.Dispose(); $ms.Dispose()
}
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $out
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
foreach ($s in $sizes) {
  $bSize = if ($s -eq 256) { [byte]0 } else { [byte]$s }
  $bw.Write($bSize); $bw.Write($bSize); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([UInt16]1); $bw.Write([UInt16]32)
  $bw.Write([UInt32]$pngBytes[$s].Length); $bw.Write([UInt32]$offset)
  $offset += $pngBytes[$s].Length
}
foreach ($s in $sizes) { $bw.Write($pngBytes[$s]) }
$bw.Flush()
[System.IO.File]::WriteAllBytes("$PSScriptRoot\$outName", $out.ToArray())
$out.Dispose()
}
$png.Dispose()
```

## Was vor diesem Umbau probiert wurde (und nicht klappte)

Ein paar Iterationen lang hatten wir versucht, `sca.png` direkt als
`RCDATA`-Resource einzubetten und zur Laufzeit via `TPngImage` +
`Application.Icon.Assign(TPngImage)` zu setzen, plus IOTA-Bitmap via
`TBitmap.Canvas.Draw(0, 0, Png)`. Mehrere Stolpersteine zugleich:

1. `<RcCompile>` allein bindet die `.res` nicht — `{$R '...res'}` ist Pflicht
2. `{$R '...rc'}` triggert den 16-bit-Legacy-BRC
3. `Application.Icon.Assign(TPngImage)` ist in Delphi 12 nicht verlaesslich
4. BRCC32 erzeugt die `.res` neben der `.dpr/.dpk`, nicht neben der `.rc`
5. Die IDE schmiess beim Dproj-Save manchmal manuell hinzugefuegte
   `<RcCompile>`-Elemente weg

Der canonical Weg (MAINICON via dproj + BITMAP via LoadBitmap) umgeht alle
diese Punkte.
