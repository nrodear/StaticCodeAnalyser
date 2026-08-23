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
#   .\tools\package-release.ps1 -Version 0.9.10 -SkipInstaller   (ohne Setup-EXE)
#
# Danach:
#   gh release create v<Version> --title ... --notes-file ... <OutDir>\*.zip <OutDir>\*.exe

param(
  [Parameter(Mandatory=$true)]
  [string]$Version,

  [string]$OutDir = 'release-artifacts',

  [int]$StackMB = 32,

  [switch]$SkipSource,

  # Laesst den Inno-Setup-Schritt aus (z.B. solange die Monolith-BPL auf
  # dieser Maschine nicht gebaut ist). Default ist STRIKT: fehlende
  # Voraussetzungen brechen ab statt still ein Release ohne Installer zu
  # erzeugen - gleiche Philosophie wie die Versions-/Stack-Wachposten.
  [switch]$SkipInstaller,

  # Laesst die GetIt-Artefakte aus (plugin-getit.zip + finalisierte
  # .getit.json). Braucht wie der Installer die gebaute Monolith-BPL.
  [switch]$SkipGetIt
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

# Alt-Zips ALLER Versionen raeumen (Review 2026-08-04). Die Einzel-Loeschung
# unten trifft nur den exakt gleichen, versionsbehafteten Namen - Zips
# frueherer Laeufe ueberlebten jeden Durchgang. Der dokumentierte
# Folgeschritt "gh release create ... <OutDir>\*.zip" haette sie dann als
# Assets an das NEUE Release gehaengt: exakt die Fehlerklasse (falsches
# Artefakt ausgeliefert), gegen die dieses Skript gebaut wurde.
Get-ChildItem -Path $OutDir -Filter 'StaticCodeAnalyser-v*.zip' -ErrorAction SilentlyContinue |
  Remove-Item -Force
Get-ChildItem -Path $OutDir -Filter 'StaticCodeAnalyserSetup-*.exe' -ErrorAction SilentlyContinue |
  Remove-Item -Force
Get-ChildItem -Path $OutDir -Filter 'StaticCodeAnalyser-D12*.getit.json' -ErrorAction SilentlyContinue |
  Remove-Item -Force

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

  # 1b. AUCH die Windows-VERSIONINFO pruefen (Datei-Eigenschaften im
  #     Explorer). Sie kommt aus den VerInfo_*-Feldern der dproj, nicht
  #     aus SCA_VERSION - v0.9.16 ging beinahe mit --version=0.9.16,
  #     aber FileVersion=0.9.14.0 raus, weil der Versions-Bump die dproj
  #     nie mitzog. Zwei Quellen, zwei Pruefungen.
  $fileVer = (Get-Item $exe).VersionInfo.FileVersion
  if ($fileVer -notmatch ('^' + [regex]::Escape($Version))) {
    throw ("$($p.Name): VERSIONINFO ist '$fileVer', erwartet $Version.*. " +
           'VerInfo_Release/VerInfo_Keys in der dproj nachziehen + neu bauen.')
  }

  # 2. Patchen (idempotent).
  & (Join-Path $PSScriptRoot 'patch-stack-size.ps1') $exe -SizeMB $StackMB | Out-Null

  # 3. NACHPRUEFEN statt vertrauen - das ist der Punkt des Skripts.
  $mb = Get-StackReserveMB $exe
  if ($mb -ne $StackMB) {
    throw "$($p.Name): Stack-Reserve ist $mb MB, erwartet $StackMB MB. Abbruch."
  }

  # 4. Der Regelkatalog MUSS mit ins Archiv. Ohne rules\sca-rules.json
  #    neben der EXE faellt TRuleCatalog auf den einkompilierten Notbehelf
  #    zurueck - und der Sonar-Export wird dann von SonarQube komplett
  #    verworfen (2026-08-08 am v0.9.14-ZIP nachgewiesen: Lauf gruen,
  #    Datei geschrieben, Dashboard leer). Der Katalog speist ausserdem
  #    tool.driver.version im SARIF und die FixHints.
  $rules = Join-Path $repo 'rules\sca-rules.json'
  if (-not (Test-Path $rules)) { throw "Regelkatalog fehlt: $rules" }

  $zip = Join-Path $OutDir "StaticCodeAnalyser-v$Version-$($p.Name).zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }

  # Archiv von Hand aufbauen statt per Compress-Archive: Windows
  # PowerShell 5.1 schreibt BACKSLASHES in die Eintragsnamen
  # ("rules\sca-rules.json"). Die ZIP-Spezifikation verlangt Forward
  # Slashes; mit Backslash entsteht unter Linux/macOS eine DATEI dieses
  # Namens statt eines Ordners, und die EXE findet ihren Katalog nicht.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
  try {
    $lvl = [System.IO.Compression.CompressionLevel]::Optimal
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $za, $exe, (Split-Path $exe -Leaf), $lvl)
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $za, $rules, 'rules/sca-rules.json', $lvl)
    # Sprach-Overlays (2026-08-19): ohne sie faellt die lokalisierte
    # Regelanzeige beim Kunden auf die einkompilierte Tabelle zurueck -
    # funktioniert, aber lose Dateien sind der Update-Weg ohne Rebuild.
    foreach ($lang in @('de', 'fr')) {
      $ov = Join-Path (Split-Path $rules -Parent) "sca-rules.$lang.json"
      if (-not (Test-Path $ov)) { throw "Overlay fehlt: $ov. Abbruch." }
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $za, $ov, "rules/sca-rules.$lang.json", $lvl)
    }
  } finally {
    $za.Dispose()
  }

  # 5. Gegenprobe am fertigen Archiv - Namen exakt, nicht "irgendwie drin".
  $za = [System.IO.Compression.ZipFile]::OpenRead($zip)
  try { $names = @($za.Entries | ForEach-Object { $_.FullName }) }
  finally { $za.Dispose() }
  foreach ($muss in @('rules/sca-rules.json', 'rules/sca-rules.de.json',
                      'rules/sca-rules.fr.json')) {
    if ($names -notcontains $muss) {
      throw "$($p.Name): $muss fehlt im Archiv (gefunden: $($names -join ', ')). Abbruch."
    }
  }
  "{0,-6} {1} v{2}  Stack {3} MB  + rules  ->  {4}" -f `
    $p.Name, (Split-Path $exe -Leaf), $Version, $mb, (Split-Path $zip -Leaf)
}

# ---- Doku + Skripte fuer EXE-Anwender --------------------------------------
# Nutzerwunsch v0.9.15: ein eigenes Archiv mit allem, was man NEBEN der
# nackten EXE braucht, um die dokumentierten Ablaeufe einzurichten -
# Baseline, Sonar, CI-Gate, eigene Regeln - ohne dafuer das Source-Zip zu
# durchwuehlen. NUR oeffentliche Doku: die internen Doku_/Todo_/Konzept_-
# Dateien sind gitignoriert und gehoeren hier bewusst nicht hinein.
# Alle drei Sprachfassungen: das Projekt pflegt de/en/fr durchgehend,
# das Doku-Archiv lieferte bisher aber nur de/en aus. Dazu HowTo_Build -
# wer die Packages selbst bauen will, braucht genau diese Anleitung, und
# das Setup verweist im Wizard darauf.
$docItems = @(
  'README.md', 'README_de.md', 'README_fr.md',
  'EXPORTS.md', 'EXPORTS_de.md', 'EXPORTS_fr.md',
  'sonarHowto.md', 'sonarHowto_de.md', 'sonarHowto_fr.md',
  'DETECTORS.md', 'DETECTORS_de.md', 'DETECTORS_fr.md',
  'BRANCH_CHANGES.md', 'BRANCH_CHANGES_de.md', 'BRANCH_CHANGES_fr.md',
  'RELEASE_NOTES.md', 'RELEASE_NOTES_de.md', 'RELEASE_NOTES_fr.md',
  'HowTo_Build.md', 'HowTo_Build_de.md', 'HowTo_Build_fr.md',
  'CHANGELOG.md',
  'docs/sonar-setup.md', 'docs/sonar-config.md', 'docs/sonar-coverage.md',
  'docs/rules.md',
  'docs/releases/v0.9.17.md', 'docs/releases/v0.9.17_de.md'
)
foreach ($d in $docItems) {
  if (-not (Test-Path (Join-Path $repo $d))) { throw "Doku fehlt: $d" }
}
# examples\ komplett: Analyse-Profile, Custom-Rules-Vorlage und die
# CI-Skripte (GitHub-Actions-Workflow mit SARIF-Upload + Baseline-Gate,
# pre-commit-Hook, PR-Kommentar-Bot, MSBuild-Target).
$exampleRoot = Join-Path $repo 'examples'
if (-not (Test-Path $exampleRoot)) { throw "examples\ fehlt" }

$docZip = Join-Path $OutDir "StaticCodeAnalyser-v$Version-docs-scripts.zip"
if (Test-Path $docZip) { Remove-Item $docZip -Force }
$za = [System.IO.Compression.ZipFile]::Open($docZip, 'Create')
try {
  $lvl = [System.IO.Compression.CompressionLevel]::Optimal
  foreach ($d in $docItems) {
    # Eintragsname = Repo-relativer Pfad mit FORWARD Slashes (gleiche
    # Begruendung wie beim EXE-Zip: Backslash-Eintraege entpacken unter
    # Linux/macOS als eine seltsam benannte Datei).
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $za, (Join-Path $repo $d), ($d -replace '\\', '/'), $lvl)
  }
  Get-ChildItem $exampleRoot -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($repo.Length + 1) -replace '\\', '/'
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $za, $_.FullName, $rel, $lvl)
  }
} finally {
  $za.Dispose()
}

# Gegenprobe am fertigen Archiv - je ein Wachposten pro Inhaltsklasse.
$za = [System.IO.Compression.ZipFile]::OpenRead($docZip)
try { $names = @($za.Entries | ForEach-Object { $_.FullName }) }
finally { $za.Dispose() }
foreach ($sentinel in @('EXPORTS.md', 'docs/sonar-setup.md',
                        'examples/ci/github-actions-sca.yml')) {
  if ($names -notcontains $sentinel) {
    throw "docs-scripts: $sentinel fehlt im Archiv. Abbruch."
  }
}
"{0,-6} {1} Doku-Dateien + examples ({2} Eintraege)  ->  {3}" -f `
  'docs', $docItems.Count, $names.Count, (Split-Path $docZip -Leaf)

# ---- Gemeinsame Voraussetzung Installer + GetIt: die Monolith-BPL ----------
# Wachposten wie bei den EXEs: BPL-VERSIONINFO muss zur Release-Version
# passen (faengt "vergessen zu bauen" ab).
$bpl = 'C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\StaticCodeAnalyser.Plugin.d12.bpl'
if ((-not $SkipInstaller) -or (-not $SkipGetIt)) {
  if (-not (Test-Path $bpl)) {
    throw ("Monolith-BPL fehlt: $bpl - StaticCodeAnalyser.Plugin.d12.dproj " +
           'in der IDE bauen (Release/Win32) oder -SkipInstaller -SkipGetIt verwenden.')
  }
  $bplVer = (Get-Item $bpl).VersionInfo.FileVersion
  if ($bplVer -notmatch ('^' + [regex]::Escape($Version))) {
    throw ("Plugin-BPL VERSIONINFO ist '$bplVer', erwartet $Version.*. " +
           'VerInfo der Plugin-dproj nachziehen + neu bauen.')
  }

  # Seit 2026-08-23 packt das Setup auch die Delphi-13-Schiene (BDS 37.0),
  # Win32 und Win64 getrennt - die 64-bit-IDE laedt NIE eine 32-bit-BPL.
  # Ohne diese Pruefung braeche erst ISCC ab, und zwar mit einer Meldung
  # ueber einen fehlenden Quellpfad statt ueber ein nicht gebautes Projekt.
  $bpl37 = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl'
  $bplD13 = [ordered]@{
    'D13 Win32' = Join-Path $bpl37 'StaticCodeAnalyser.Plugin.d12.bpl'
    'D13 Win64' = Join-Path $bpl37 'Win64\StaticCodeAnalyser.Plugin.d12.bpl'
  }
  foreach ($k in $bplD13.Keys) {
    $f = $bplD13[$k]
    if (-not (Test-Path $f)) {
      throw ("Monolith-BPL fuer $k fehlt: $f - " +
             'StaticCodeAnalyser.Plugin.d12.dproj in Delphi 13 bauen ' +
             '(Release, Win32 UND Win64).')
    }
    $v = (Get-Item $f).VersionInfo.FileVersion
    if ($v -notmatch ('^' + [regex]::Escape($Version))) {
      throw ("Plugin-BPL $k hat VERSIONINFO '$v', erwartet $Version.*.")
    }
  }
}

# ---- IDE-Plugin-Installer (Inno Setup, Monolith-BPL) -----------------------
# Installer P2 (2026-08-14): das Setup registriert die Monolith-BPL per-user
# in der D12-IDE (HKCU Known Packages) - Details in installer\README_Installer.md.
if (-not $SkipInstaller) {
  $isccCmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($isccCmd) {
    $iscc = $isccCmd.Source
  } else {
    $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
    if (-not (Test-Path $iscc)) {
      throw ('ISCC.exe nicht gefunden (PATH + Standardpfad). ' +
             'Inno Setup 6 installieren oder -SkipInstaller verwenden.')
    }
  }

  $iss = Join-Path $repo 'installer\StaticCodeAnalyserSetup.iss'
  & $iscc ('/DSCAVersion=' + $Version + '.0') ('/O' + $OutDir) $iss | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ISCC fehlgeschlagen (Exit $LASTEXITCODE)." }

  $setupExe = Join-Path $OutDir "StaticCodeAnalyserSetup-$Version.0.exe"
  if (-not (Test-Path $setupExe)) {
    throw "Setup-EXE fehlt nach ISCC: $setupExe. Abbruch."
  }
  "{0,-6} Plugin-BPL v{1}  ->  {2}" -f `
    'setup', $bplVer, (Split-Path $setupExe -Leaf)
}

# ---- GetIt-Artefakte (P3.3/3.4, 2026-08-15) --------------------------------
# Erzeugt (a) das Payload-ZIP fuer den GetIt-Paketmanager (Monolith-BPL +
# LICENSE + Logo im WURZELVERZEICHNIS - exakt das Layout, das die
# InstallIDEPackage-Action im Manifest referenziert) und (b) zwei
# finalisierte Manifeste aus der Vorlage getit\StaticCodeAnalyser-D12.getit.json:
#   *.getit.json       - Url = GitHub-Release-Asset (fuer Einreichung/Nutzer)
#   *.local.getit.json - Url = lokaler ZIP-Pfad (fuer "Load Local Package"-
#                        Tests VOR dem Release-Upload)
# WICHTIG: "Modified" steuert die GetIt-Update-Erkennung (nicht "Version") -
# es wird hier auf die Paketier-Zeit gesetzt.
if (-not $SkipGetIt) {
  $getitTpl = Join-Path $repo 'getit\StaticCodeAnalyser-D12.getit.json'
  $license  = Join-Path $repo 'LICENSE'
  $logo     = Join-Path $repo 'getit\sca_logo_128.png'
  foreach ($f in @($getitTpl, $license, $logo)) {
    if (-not (Test-Path $f)) { throw "GetIt-Zutat fehlt: $f" }
  }

  $getitZip = Join-Path $OutDir "StaticCodeAnalyser-v$Version-plugin-getit.zip"
  if (Test-Path $getitZip) { Remove-Item $getitZip -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [System.IO.Compression.ZipFile]::Open($getitZip, 'Create')
  try {
    $lvl = [System.IO.Compression.CompressionLevel]::Optimal
    foreach ($pair in @(
      @{ Src = $bpl;     Name = 'StaticCodeAnalyser.Plugin.d12.bpl' },
      @{ Src = $license; Name = 'LICENSE' },
      @{ Src = $logo;    Name = 'sca_logo_128.png' })) {
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $za, $pair.Src, $pair.Name, $lvl)
    }
  } finally {
    $za.Dispose()
  }

  # Gegenprobe am fertigen Archiv.
  $za = [System.IO.Compression.ZipFile]::OpenRead($getitZip)
  try { $names = @($za.Entries | ForEach-Object { $_.FullName }) }
  finally { $za.Dispose() }
  foreach ($sentinel in @('StaticCodeAnalyser.Plugin.d12.bpl', 'LICENSE',
                          'sca_logo_128.png')) {
    if ($names -notcontains $sentinel) {
      throw "getit-zip: $sentinel fehlt im Archiv. Abbruch."
    }
  }

  # Manifeste aus der Vorlage: Version/Modified/Url ersetzen. Die Vorlage
  # gehoert uns - gezielte Zeilen-Regexe sind hier robust genug, und die
  # ConvertFrom-Json-Gegenprobe unten faengt jeden Formfehler.
  $tpl = Get-Content $getitTpl -Raw -Encoding UTF8
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $releaseUrl = "https://github.com/nrodear/StaticCodeAnalyser/releases/download/v$Version/StaticCodeAnalyser-v$Version-plugin-getit.zip"
  $tpl = $tpl -replace '("Version"\s*:\s*)"[^"]*"',  ('$1"' + $Version + '"')
  $tpl = $tpl -replace '("Modified"\s*:\s*)"[^"]*"', ('$1"' + $now + '"')

  $jsonRelease = Join-Path $OutDir 'StaticCodeAnalyser-D12.getit.json'
  $jsonLocal   = Join-Path $OutDir 'StaticCodeAnalyser-D12.local.getit.json'
  # GetIt-Konvention (offizielles Abbrevia-Sample): Schraegstriche in URLs
  # werden als \/ escaped.
  $relText = $tpl -replace '("Url"\s*:\s*)"[^"]*"', ('$1"' + ($releaseUrl -replace '/', '\/') + '"')
  # JSON-Escaping: je Backslash im Windows-Pfad genau EIN \\ im JSON-Text.
  # (Replacement-Strings von -replace behandeln Backslashes literal -
  # '\\\\' haette hier vier erzeugt, der erste Lauf bewies es.)
  $locText = $tpl -replace '("Url"\s*:\s*)"[^"]*"', ('$1"' + ($getitZip -replace '\\', '\\') + '"')
  [System.IO.File]::WriteAllText($jsonRelease, $relText,
    (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText($jsonLocal, $locText,
    (New-Object System.Text.UTF8Encoding($false)))

  # Gegenprobe: beide Manifeste muessen parsen und die ersetzten Werte
  # tragen; die LOKALE Url muss nach dem JSON-Roundtrip als Datei
  # existieren (faengt Escaping-Fehler wie doppelte Backslashes).
  foreach ($j in @($jsonRelease, $jsonLocal)) {
    $parsed = Get-Content $j -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($parsed.Version -ne $Version) { throw "getit-json: Version nicht ersetzt in $j" }
    if ($parsed.Modified -ne $now)    { throw "getit-json: Modified nicht ersetzt in $j" }
    if (-not $parsed.Url)             { throw "getit-json: Url leer in $j" }
  }
  $locParsed = Get-Content $jsonLocal -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($locParsed.Url -ne $getitZip) {
    throw "getit-json: lokale Url '$($locParsed.Url)' != '$getitZip' (Escaping?)"
  }

  # License/Image im Manifest sind DATEIEN NEBEN DER JSON (wie im
  # offiziellen Sample) - GetIt laedt sie beim Oeffnen des Pakets.
  # (a) Fuer den Lokaltest direkt aus $OutDir: beide daneben legen.
  # (b) Fuer fremde Maschinen: Manifest-Bundle-ZIP (JSON + LICENSE +
  #     Logo) - eine nackte JSON bricht sonst mit "EULA kann nicht
  #     geladen werden" ab (2026-08-15 auf dem Zweit-PC bewiesen).
  Copy-Item $license (Join-Path $OutDir 'LICENSE') -Force
  Copy-Item $logo    (Join-Path $OutDir 'sca_logo_128.png') -Force

  $bundleZip = Join-Path $OutDir "StaticCodeAnalyser-v$Version-getit-manifest.zip"
  if (Test-Path $bundleZip) { Remove-Item $bundleZip -Force }
  $za = [System.IO.Compression.ZipFile]::Open($bundleZip, 'Create')
  try {
    $lvl = [System.IO.Compression.CompressionLevel]::Optimal
    foreach ($pair in @(
      @{ Src = $jsonRelease; Name = 'StaticCodeAnalyser-D12.getit.json' },
      @{ Src = $license;     Name = 'LICENSE' },
      @{ Src = $logo;        Name = 'sca_logo_128.png' })) {
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $za, $pair.Src, $pair.Name, $lvl)
    }
  } finally {
    $za.Dispose()
  }
  $za = [System.IO.Compression.ZipFile]::OpenRead($bundleZip)
  try { $names = @($za.Entries | ForEach-Object { $_.FullName }) }
  finally { $za.Dispose() }
  foreach ($sentinel in @('StaticCodeAnalyser-D12.getit.json', 'LICENSE',
                          'sca_logo_128.png')) {
    if ($names -notcontains $sentinel) {
      throw "getit-manifest-zip: $sentinel fehlt im Archiv. Abbruch."
    }
  }

  "{0,-6} BPL + LICENSE + Logo  ->  {1} (+ 2 Manifeste + Manifest-Bundle)" -f `
    'getit', (Split-Path $getitZip -Leaf)
}

if (-not $SkipSource) {
  # Aus dem TAG, nicht aus dem Arbeitsbaum: so landet nichts Ungetaggtes
  # im Archiv, und gitignorierte interne Dokumente bleiben ohnehin draussen.
  $tag = "v$Version"
  # KEIN 2>$null auf dem nativen Kommando: PS 5.1 wickelt umgeleitete
  # stderr-Zeilen in ErrorRecords, und mit ErrorActionPreference=Stop
  # terminierte das Skript dann VOR dem throw mit einem rohen
  # NativeCommandError - der Guard darunter war toter Code und seine
  # Meldung erschien nie. --verify --quiet unterdrueckt gits stderr selbst;
  # entschieden wird ueber den Exit-Code.
  git -C $repo rev-parse --verify --quiet "$tag^{commit}" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Tag $tag existiert nicht - erst taggen." }
  $src = Join-Path $OutDir "StaticCodeAnalyser-v$Version-source.zip"
  if (Test-Path $src) { Remove-Item $src -Force }
  git -C $repo archive --format=zip --prefix="StaticCodeAnalyser-$Version/" -o $src $tag
  "{0,-6} aus Tag {1}  ->  {2}" -f 'source', $tag, (Split-Path $src -Leaf)
}

""
"Artefakte in: $OutDir"
