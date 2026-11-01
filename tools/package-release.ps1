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
#   .\tools\package-release.ps1 -Version 0.9.19 -DryRun          (nur Vorbedingungen)
#
# Danach:
#   gh release create v<Version> --title ... --notes-file ... <OutDir>\*.zip <OutDir>\*.exe

param(
  [Parameter(Mandatory=$true)]
  [string]$Version,

  [string]$OutDir = 'release-artifacts',

  [int]$StackMB = 32,

  [switch]$SkipSource,

  # Laesst den Inno-Setup-Schritt und damit die Paketsatz-Vorbedingungen
  # aus (z.B. solange der Paketsatz auf dieser Maschine nicht gebaut ist).
  # Default ist STRIKT: fehlende Voraussetzungen brechen ab statt still ein
  # Release ohne Installer zu erzeugen - gleiche Philosophie wie die
  # Versions-/Stack-Wachposten.
  [switch]$SkipInstaller,

  # GetIt ist fuer das Paketsatz-Release ausgesetzt (E7): Laufzeit-BPLs
  # brauchen einen Ladeweg, den die Manifest-Actions nicht ausdruecken
  # koennen. Daher Default AN. -SkipGetIt:$false erzeugt die Artefakte
  # aus dem Monolithen und braucht dessen gebaute BPL; das ist kein
  # Releaseweg, sondern ein Rest bis zum Loeschen des Monolithen.
  [switch]$SkipGetIt = $true,

  # Prueft nur die Vorbedingungen (Gates + 12 BPLs) und endet danach. Legt
  # nichts an und raeumt nichts. Die EXEs prueft erst der echte Lauf.
  [switch]$DryRun
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

function Get-PeMachine([string]$Path) {
  # COFF-Feld Machine, 4 Byte hinter der PE-Signatur. 0 = keine PE-Datei.
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 0x40) { return 0 }
  $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
  if (($peOff -lt 0) -or (($peOff + 6) -gt $bytes.Length)) { return 0 }
  if ([BitConverter]::ToUInt32($bytes, $peOff) -ne 0x4550) { return 0 }
  return [BitConverter]::ToUInt16($bytes, $peOff + 4)
}

function Invoke-Gate([string]$Script, [string[]]$GateArgs) {
  # Mit ErrorActionPreference=Stop koennte eine stderr-Zeile des Gates das
  # Skript ohne Meldung beenden; hier entscheidet allein der Exit-Code.
  $alt = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & python (Join-Path $PSScriptRoot $Script) @GateArgs | Out-Host
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $alt
  }
}

# ---- Paketsatz: 4 Pakete x 3 Schienen = 12 BPLs -----------------------------
# Laufzeitpakete tragen den Compiler-Suffix (LIBSUFFIX AUTO), die beiden
# Design-Pakete nicht. Win32 und Win64 unter D13 heissen gleich und liegen
# nur in verschiedenen Ordnern; die PE-Machine ist die einzige Stelle, an
# der eine Verwechslung vor der Auslieferung auffaellt. Define ist der Name,
# unter dem ISCC den Quellordner bekommt.
$studio = Join-Path $env:PUBLIC 'Documents\Embarcadero\Studio'
$schienen = @(
  @{ Name = 'D12 Win32'; Define = 'SCABplSourceDir';       Suffix = '290'
     Dir  = (Join-Path $studio '23.0\Bpl');       Machine = 0x014C },
  @{ Name = 'D13 Win32'; Define = 'SCABplSourceDirD13';    Suffix = '370'
     Dir  = (Join-Path $studio '37.0\Bpl');       Machine = 0x014C },
  @{ Name = 'D13 Win64'; Define = 'SCABplSourceDirD13X64'; Suffix = '370'
     Dir  = (Join-Path $studio '37.0\Bpl\Win64'); Machine = 0x8664 }
)
$pakete = @(
  @{ Name = 'SCA.Engine';                 Laufzeit = $true  },
  @{ Name = 'SCA.SharedUI';               Laufzeit = $true  },
  @{ Name = 'StaticCodeAnalyser.IDE.d12'; Laufzeit = $false },
  @{ Name = 'reDelphix.d12';              Laufzeit = $false }
)

# ---- Vorbedingungen ---------------------------------------------------------
# Stehen VOR allem anderen: ein Abbruch hier hat noch nichts angelegt,
# geraeumt oder gepatcht. Es wird alles geprueft und erst dann abgebrochen -
# so nennt ein Lauf alle Befunde, nicht nur den ersten.
$befunde = New-Object System.Collections.Generic.List[string]
if ((-not $SkipInstaller) -or $DryRun) {
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'python nicht gefunden - die Gates sind Vorbedingung des Releases.'
  }

  # Quelltext-Vertraege des Satzes, gegen genau diese Version.
  if ((Invoke-Gate 'package_set_gate.py' @('--version', $Version)) -ne 0) {
    $befunde.Add('package_set_gate.py ist rot (Ausgabe oben).')
  }
  # DCP aelter als seine Quelle: die BPL zeigt dann den alten Stand, auch
  # wenn ihre Version stimmt.
  if ((Invoke-Gate 'stale_artifacts_check.py' @('--release')) -ne 0) {
    $befunde.Add('stale_artifacts_check.py --release ist rot (Ausgabe oben).')
  }

  $verRegex = '^' + [regex]::Escape($Version) + '(\.|$)'
  ''
  '{0,-10} {1,-32} {2,-20} {3,-5} {4}' -f 'Schiene', 'BPL', 'Version', 'PE', 'Zustand'
  foreach ($s in $schienen) {
    foreach ($p in $pakete) {
      $datei = if ($p.Laufzeit) { "$($p.Name)$($s.Suffix).bpl" } else { "$($p.Name).bpl" }
      $f = Join-Path $s.Dir $datei
      $was = "$($s.Name) ${datei}"

      if (-not (Test-Path $f)) {
        '{0,-10} {1,-32} {2,-20} {3,-5} {4}' -f $s.Name, $datei, '-', '-', 'FEHLT'
        $befunde.Add("$was fehlt: $f")
        continue
      }

      # Die BPL traegt die Version zweimal, als String und als Zahlen
      # (VS_FIXEDFILEINFO). Beide muessen stimmen; verglichen wird das
      # Gebaute, nicht die dproj.
      $vi = (Get-Item $f).VersionInfo
      $text = if ($vi.FileVersion) { $vi.FileVersion } else { '(leer)' }
      $zahl = '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart,
                                   $vi.FileBuildPart, $vi.FilePrivatePart
      $alsText = if ($text -eq $zahl) { $text } else { "$text/$zahl" }
      $zustand = @()
      if (($text -notmatch $verRegex) -or ($zahl -notmatch $verRegex)) {
        $zustand += 'VERSION'
        $befunde.Add("$was hat VERSIONINFO $alsText, erwartet $Version.0.")
      }

      $machine = Get-PeMachine $f
      $alsMachine = '{0:X4}' -f [int]$machine
      if ($machine -ne $s.Machine) {
        $zustand += 'BITBREITE'
        $befunde.Add(('{0} hat PE-Machine {1}, erwartet {2:X4}.' -f `
          $was, $alsMachine, [int]$s.Machine))
      }

      $meldung = if ($zustand.Count) { $zustand -join ' + ' } else { 'ok' }
      '{0,-10} {1,-32} {2,-20} {3,-5} {4}' -f $s.Name, $datei, $alsText, $alsMachine, $meldung
    }
  }
  ''
}

# Nur -SkipGetIt:$false. Der Paketsatz kennt keinen GetIt-Ladeweg, daher der
# Monolith; siehe den Parameter oben.
$bpl = Join-Path $studio '23.0\Bpl\StaticCodeAnalyser.Plugin.d12.bpl'
if (-not $SkipGetIt) {
  if (-not (Test-Path $bpl)) {
    $befunde.Add("Monolith-BPL fuer GetIt fehlt: $bpl")
  } elseif ((Get-Item $bpl).VersionInfo.FileVersion -notmatch ('^' + [regex]::Escape($Version))) {
    $befunde.Add("Monolith-BPL fuer GetIt hat nicht die Version ${Version}: $bpl")
  }
}

if ($befunde.Count -gt 0) {
  throw ("Release abgebrochen, {0} Befund(e):`n  - {1}`n" -f $befunde.Count,
         ($befunde -join "`n  - ")) +
        ('Paketsatz in der IDE bauen (Release), je Schiene in dieser Reihenfolge: ' +
         'SCA.Engine, SCA.SharedUI, StaticCodeAnalyser.IDE.d12, reDelphix.d12. ' +
         'Schienen: D12 Win32, D13 Win32, D13 Win64. ' +
         'Ohne Installer: -SkipInstaller. Es wurde nichts angelegt oder veraendert.')
}

if ($DryRun) {
  "Trockenlauf gruen: Gates und 12 BPLs passen zu $Version. Nichts angelegt oder veraendert."
  return
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
  #    neben der EXE faellt TRuleCatalog auf den einkompilierten Stand
  #    zurueck: der Sonar-Export bleibt gueltig, traegt aber grobe
  #    Attribute und Impacts statt der Katalogwerte. Der Katalog speist
  #    ausserdem tool.driver.version im SARIF und die FixHints.
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
# Die Notes laufen mit -Version mit: fest eingetragen lag bis v0.9.18 noch
# v0.9.17 im Archiv. Dazu alles, worauf README und RELEASE_NOTES im Archiv
# verweisen, soweit es einzelne Doku-Dateien sind. Nicht dabei: der Ordner
# i18n und die Quelle uSCAConsts.pas (kein Doku-Inhalt) sowie die Seiten je
# Regel hinter docs/rules/index.md.
$docItems = @(
  'README.md', 'README_de.md', 'README_fr.md',
  'EXPORTS.md', 'EXPORTS_de.md', 'EXPORTS_fr.md',
  'sonarHowto.md', 'sonarHowto_de.md', 'sonarHowto_fr.md',
  'DETECTORS.md', 'DETECTORS_de.md', 'DETECTORS_fr.md',
  'BRANCH_CHANGES.md', 'BRANCH_CHANGES_de.md', 'BRANCH_CHANGES_fr.md',
  'RELEASE_NOTES.md', 'RELEASE_NOTES_de.md', 'RELEASE_NOTES_fr.md',
  'HowTo_Build.md', 'HowTo_Build_de.md', 'HowTo_Build_fr.md',
  'CHANGELOG.md',
  'docs/sonar-coverage.md',
  'docs/rules.md', 'docs/rules/index.md', 'docs/index.md',
  'docs/configuration.md', 'docs/configuration_de.md', 'docs/configuration_fr.md',
  'docs/profiles.md', 'docs/profiles_de.md', 'docs/profiles_fr.md',
  'docs/OptionsSca.gif', 'docs/PlugInDockedSca.gif', 'docs/PlugInSca.gif',
  'docs/sca-demo.gif',
  'LICENSE',
  'reDelphix/QUICKFIXES.md', 'reDelphix/README.md',
  "docs/releases/v$Version.md", "docs/releases/v${Version}_de.md",
  'docs/releases/v0.9.18.md', 'docs/releases/v0.9.18_de.md',
  'docs/releases/v0.9.17.md', 'docs/releases/v0.9.17_de.md',
  'docs/releases/v0.9.16.md', 'docs/releases/v0.9.16_de.md',
  'docs/releases/v0.9.14.md', 'docs/releases/v0.9.14_de.md',
  'docs/releases/v0.9.13.md', 'docs/releases/v0.9.13_de.md',
  'docs/releases/v0.9.12.md', 'docs/releases/v0.9.12_de.md',
  'docs/releases/v0.9.11.md', 'docs/releases/v0.9.11_de.md',
  'docs/releases/v0.9.10.md', 'docs/releases/v0.9.10_de.md',
  'docs/releases/v0.9.9.md', 'docs/releases/v0.9.9_de.md'
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
foreach ($sentinel in @('EXPORTS.md', 'sonarHowto.md',
                        'examples/ci/github-actions-sca.yml')) {
  if ($names -notcontains $sentinel) {
    throw "docs-scripts: $sentinel fehlt im Archiv. Abbruch."
  }
}
"{0,-6} {1} Doku-Dateien + examples ({2} Eintraege)  ->  {3}" -f `
  'docs', $docItems.Count, $names.Count, (Split-Path $docZip -Leaf)

# ---- IDE-Plugin-Installer (Inno Setup, Paketsatz) ---------------------------
# Das Setup verteilt die vier BPLs je Schiene per-user - Details in
# installer\README_Installer.md. Die Quellordner kommen von hier, damit
# Pruefung und Verpackung garantiert dieselben Dateien meinen.
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
  $isccArgs = @('/DSCAVersion=' + $Version + '.0')
  foreach ($s in $schienen) { $isccArgs += ('/D' + $s.Define + '=' + $s.Dir) }
  $isccArgs += ('/O' + $OutDir)
  $isccArgs += $iss
  & $iscc @isccArgs | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ISCC fehlgeschlagen (Exit $LASTEXITCODE)." }

  $setupExe = Join-Path $OutDir "StaticCodeAnalyserSetup-$Version.0.exe"
  if (-not (Test-Path $setupExe)) {
    throw "Setup-EXE fehlt nach ISCC: $setupExe. Abbruch."
  }
  "{0,-6} Paketsatz v{1} (12 BPLs)  ->  {2}" -f `
    'setup', $Version, (Split-Path $setupExe -Leaf)
}

# ---- GetIt-Artefakte (P3.3/3.4, 2026-08-15) --------------------------------
# AUSGESETZT (E7), Default -SkipGetIt; siehe Parameter oben.
# Erzeugt (a) das Payload-ZIP fuer den GetIt-Paketmanager (Monolith-BPL +
# LICENSE + Logo im WURZELVERZEICHNIS - exakt das Layout, das die
# InstallIDEPackage-Action im Manifest referenziert) und (b) zwei
# finalisierte Manifeste aus der Vorlage getit\StaticCodeAnalyser-D12.getit.json:
#   *.getit.json       - Url = GitHub-Release-Asset (fuer Einreichung/Nutzer)
#   *.local.getit.json - Url = lokaler ZIP-Pfad (fuer "Load Local Package"-
#                        Tests VOR dem Release-Upload)
# WICHTIG: "Modified" steuert die GetIt-Update-Erkennung (nicht "Version") -
# es wird hier auf die Paketier-Zeit gesetzt.
if ($SkipGetIt) {
  "{0,-6} ausgesetzt (E7), keine Artefakte" -f 'getit'
} else {
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
