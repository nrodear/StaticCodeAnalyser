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
| `sca_16.bmp` | 16×16 Windows-BMP (24-bit, kein Alpha, weisser Hintergrund) fuer das Menue-Icon des IDE-Plugins (`INTAServices.AddImages`). |
| `sca_branding.rc` | `SCA_APP_BMP BITMAP "sca_24.bmp"` + `SCA_APP_BMP16 BITMAP "sca_16.bmp"` + `SCA_APP_ICO ICON "sca_small.ico"`. Alle drei gehen ueber BRCC32. |

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

Ein einmaliges PowerShell-Snippet erzeugt alle vier Derivat-Assets aus dem
PNG (`sca_24.bmp`, `sca_16.bmp`, `sca.ico`, `sca_small.ico`; aus dem
heutigen `sca.png` byte-gleich zu den eingecheckten Dateien).
Schreibe folgendes in eine `_regen.ps1` neben den Assets, run, wieder loeschen:

```powershell
Add-Type -AssemblyName System.Drawing
$png = [System.Drawing.Image]::FromFile("$PSScriptRoot\sca.png")
# 24x24 und 16x16 BMP fuer das IDE-Plugin (SCA_APP_BMP, SCA_APP_BMP16).
# WICHTIG: Format24bppRgb (nicht Default 32bppArgb) - BRCC32 stammt aus
# der 16-bit-Era und lehnt 32-bit-DIB mit 'Invalid bitmap format' ab.
# Kein Alpha-Channel -> weisser Hintergrund.
$fmt = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
foreach ($s in @(24, 16)) {
  $b = New-Object System.Drawing.Bitmap $s, $s, $fmt
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($png, 0, 0, $s, $s)
  $b.Save("$PSScriptRoot\sca_$s.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
  $g.Dispose(); $b.Dispose()
}
# Ein Sub-Icon als 32-bit-ARGB-Bitmap der Kantenlaenge $s.
function New-IconBitmap([int]$s) {
  $b = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($png, 0, 0, $s, $s)
  $g.Dispose()
  $b
}
# ICO-Huelle: Kopf, Verzeichnis, dann die Bilddaten je Groesse.
function Write-Ico([string]$name, [int[]]$sizes, [hashtable]$data) {
  $out = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter $out
  $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  foreach ($s in $sizes) {
    $bSize = if ($s -eq 256) { [byte]0 } else { [byte]$s }
    $bw.Write($bSize); $bw.Write($bSize); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$data[$s].Length); $bw.Write([UInt32]$offset)
    $offset += $data[$s].Length
  }
  foreach ($s in $sizes) { $bw.Write($data[$s]) }
  $bw.Flush()
  [System.IO.File]::WriteAllBytes("$PSScriptRoot\$name", $out.ToArray())
  $out.Dispose()
}
# sca.ico (16/32/48/256) fuer die EXE: jede Groesse PNG-komprimiert.
$pngData = @{}
foreach ($s in @(16, 32, 48, 256)) {
  $b = New-IconBitmap $s
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngData[$s] = $ms.ToArray()
  $b.Dispose(); $ms.Dispose()
}
Write-Ico 'sca.ico' @(16, 32, 48, 256) $pngData
# sca_small.ico (16/32/48, kein 256er) fuer das IDE-Plugin, BMP-encoded:
# BITMAPINFOHEADER, 32 bit, Zeilen von unten nach oben, doppelte Hoehe,
# leere AND-Maske. BRCC32 versteht PNG im ICO nicht.
$dibData = @{}
foreach ($s in @(16, 32, 48)) {
  $b = New-IconBitmap $s
  $rect = New-Object System.Drawing.Rectangle 0, 0, $s, $s
  $bd = $b.LockBits($rect, 'ReadOnly', $b.PixelFormat)
  $px = New-Object byte[] ($s * $s * 4)
  [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $px, 0, $px.Length)
  $b.UnlockBits($bd); $b.Dispose()
  $maskRow = [int][Math]::Ceiling($s / 32) * 4
  $ms = New-Object System.IO.MemoryStream
  $w = New-Object System.IO.BinaryWriter $ms
  $w.Write([UInt32]40); $w.Write([Int32]$s); $w.Write([Int32](2 * $s))
  $w.Write([UInt16]1); $w.Write([UInt16]32)
  foreach ($i in 1..6) { $w.Write([UInt32]0) }
  for ($y = $s - 1; $y -ge 0; $y--) { $w.Write($px, $y * $s * 4, $s * 4) }
  $w.Write((New-Object byte[] ($maskRow * $s)))
  $w.Flush()
  $dibData[$s] = $ms.ToArray()
  $ms.Dispose()
}
Write-Ico 'sca_small.ico' @(16, 32, 48) $dibData
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
