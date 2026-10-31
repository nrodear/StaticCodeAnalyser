<#
.SYNOPSIS
  Push an SCA Sonar Generic Issue Format JSON to SonarQube via sonar-scanner.

.DESCRIPTION
  Reads connection settings from the environment (SONAR_HOST_URL,
  SONAR_PROJECT_KEY, SONAR_TOKEN). Whatever is not set there comes from
  %APPDATA%\StaticCodeAnalyser\analyser.ini (sections [Sonar] +
  [SonarTokens]); a stored token is decrypted in-memory via DPAPI. Checks
  that the paths in the report exist under ProjectPath and warns about files
  the scanner will drop anyway, then runs sonar-scanner with the right -D
  parameters. Token is never written to disk or shell history.

.PARAMETER ProjectPath
  The folder the analysis ran on: the paths in the report are relative to
  it. The script aborts if no report path exists below it and warns if only
  some do. It also warns, per reason, about report files that match the
  exclusions, sit in an embedded git repo (own .git, no gitlink in the parent
  index) or are gitignored in their repo; none of these stops the upload, and
  the git part is skipped with a note if git or a repo is missing. Default:
  the StaticCodeAnalyser repo root (mirrors sonar-scan.ps1 self-scan default).

.PARAMETER JsonPath
  Path to the Sonar Generic Issue Format JSON. Default:
  <ProjectPath>\sca-findings.json.

.PARAMETER ScannerPath
  Full path to sonar-scanner.bat. Default: 'sonar-scanner' from PATH, then
  %SONAR_SCANNER_HOME%\bin\sonar-scanner.bat, then a local fallback path.

.PARAMETER Exclusions
  Comma-separated exclusion patterns. Default covers Delphi build output
  + node_modules + .sonar/ + DUnitX vendor.

.PARAMETER DisableDelphi
  Adds scanner flags that prevent the SonarDelphi plugin (or its community
  fork 'communitydelphi') from processing .dproj/.dpk files during the
  push. Useful when the plugin chokes on .dproj entries in foreign repos
  that reference unavailable Delphi targets. Also the way out of 'Path to
  Delphi standardlibrary is invalid' when the plugin should not run at all.
  SCA's external issues are unaffected - they reference .pas files by path
  and stay visible.

.PARAMETER DryRun
  Print the sonar-scanner command that would be invoked, without running
  it. Useful for verifying token/host/project before pushing.

.EXAMPLE
  .\sonar-upload.ps1

.EXAMPLE
  .\sonar-upload.ps1 -ProjectPath D:\myrepo -JsonPath D:\myrepo\sca.json

.EXAMPLE
  .\sonar-upload.ps1 -DryRun
#>
[CmdletBinding()]
param(
  # Default = analyser repo root, resolved below. Override for own projects.
  [string]$ProjectPath = $null,
  [string]$JsonPath    = $null,
  [string]$ScannerPath = $null,
  [string]$Exclusions  = '**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**,**/.sonar/**,**/node_modules/**,**/DUnitX-*/**',
  [switch]$DisableDelphi,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Nicht im param-Block: dort ist $PSScriptRoot unter Windows PowerShell 5.1
# mit `powershell -File` leer, und das Skript bricht vor der ersten Zeile ab.
if (-not $ProjectPath) {
  $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
}

if (-not $JsonPath) {
  $JsonPath = Join-Path $ProjectPath 'sca-findings.json'
}
if (-not (Test-Path $JsonPath)) {
  throw "Findings JSON not found: $JsonPath -- run sonar-scan.ps1 first."
}

# Locate sonar-scanner: PATH first, then the user's known install.
if (-not $ScannerPath) {
  $cmd = Get-Command sonar-scanner -ErrorAction SilentlyContinue
  $fromEnv = if ($env:SONAR_SCANNER_HOME) {
    Join-Path $env:SONAR_SCANNER_HOME 'bin\sonar-scanner.bat'
  } else { $null }
  if ($cmd) {
    $ScannerPath = $cmd.Source
  } elseif ($fromEnv -and (Test-Path $fromEnv)) {
    $ScannerPath = $fromEnv
    Write-Host "sonar-scanner from SONAR_SCANNER_HOME: $ScannerPath" -ForegroundColor DarkGray
  } elseif (Test-Path 'D:\git-demos\sonar-scanner-8.0.1\bin\sonar-scanner.bat') {
    $ScannerPath = 'D:\git-demos\sonar-scanner-8.0.1\bin\sonar-scanner.bat'
    Write-Host "sonar-scanner not in PATH - using fallback: $ScannerPath" -ForegroundColor DarkGray
  } else {
    throw "sonar-scanner not found. Put it in PATH, set SONAR_SCANNER_HOME, or pass -ScannerPath. Install instructions: sonarHowto.md section 0.1."
  }
}

# Load Sonar settings: environment first, same order as the tool itself
# (docs/sonar-setup.md, "Konfigurations-Quellen"). analyser.ini only fills
# what the environment leaves open.
$hostUrl     = $env:SONAR_HOST_URL
$projectKey  = $env:SONAR_PROJECT_KEY
$token       = $env:SONAR_TOKEN
$tokenSource = 'env SONAR_TOKEN'

if (-not $hostUrl -or -not $projectKey -or -not $token) {
  $iniPath = Join-Path $env:APPDATA 'StaticCodeAnalyser\analyser.ini'
  if (-not (Test-Path $iniPath)) {
    # KEIN CLI-Schalter schreibt diese Datei - StoreToken hat genau einen
    # produktiven Aufrufer, und der sitzt im IDE-Plugin. Die frueher hier
    # stehende Anweisung ("run analyser.exe --sonar-host ... once to populate
    # it") war Fiktion; wer ihr folgte, bekam nie eine INI.
    throw @"
analyser.ini not found at $iniPath

The standalone EXE only READS this file, it never writes a token to it.
Create it one of two ways:
  * IDE plugin: Tools > Options > Third Party > Sonar Integration, fill in
    host / project / token, Save. That is the only place in the product
    that DPAPI-encrypts a token.
  * By hand: see sonarHowto.md, section 1 "Option C" - it has a ready
    PowerShell snippet that writes both sections.
For CI, skip the INI entirely and set SONAR_HOST_URL, SONAR_PROJECT_KEY
and SONAR_TOKEN in the environment.
"@
  }
  $ini = Get-Content $iniPath -Raw -Encoding UTF8

  function Match-IniValue([string]$key) {
    $m = [regex]::Match($ini, "(?m)^$key=(.+)$")
    if (-not $m.Success) { return '' }
    return $m.Groups[1].Value.Trim()
  }

  if (-not $hostUrl)    { $hostUrl    = Match-IniValue 'HostUrl' }
  if (-not $projectKey) { $projectKey = Match-IniValue 'ProjectKey' }
  if (-not $hostUrl)    { throw "Sonar host missing: set SONAR_HOST_URL or analyser.ini [Sonar] HostUrl." }
  if (-not $projectKey) { throw "Sonar project missing: set SONAR_PROJECT_KEY or analyser.ini [Sonar] ProjectKey." }

  if (-not $token) {
    $tokenRef = Match-IniValue 'TokenRef'
    if (-not $tokenRef) { $tokenRef = 'ide-default' }
    $tokenHex = Match-IniValue $tokenRef
    if (-not $tokenHex) { throw "Sonar token missing: set SONAR_TOKEN or analyser.ini [SonarTokens] $tokenRef." }
    $tokenSource = $tokenRef

    # Zwei Formate koennen in [SonarTokens] stehen:
    #   * DPAPI-Hex        - von Windows geschrieben, Current-User-Scope
    #   * 'PT:' + Base64   - der Nicht-Windows-Fallback, UNVERSCHLUESSELT.
    #     Er wird auf jeder Plattform gelesen, also auch hier.
    # Vor 2026-08-08 lief ein PT:-Eintrag in die Hex-Schleife und warf dort
    # eine rohe FormatException ("PT" ist kein Hex) - ausserhalb des try, also
    # ohne jede Erklaerung.
    Add-Type -AssemblyName System.Security

    if ($tokenHex.StartsWith('PT:', [StringComparison]::OrdinalIgnoreCase)) {
      Write-Warning ("The token in analyser.ini is stored as PLAINTEXT (PT: = Base64, not encrypted). " +
                     "Anyone who can read the file has it. Re-save it via the IDE plugin on Windows to DPAPI-encrypt it.")
      try {
        $token = [System.Text.Encoding]::UTF8.GetString(
                   [Convert]::FromBase64String($tokenHex.Substring(3)))
      } catch {
        throw "The PT: entry in analyser.ini is not valid Base64 - the file looks damaged."
      }
    } else {
      if ($tokenHex.Length % 2 -ne 0 -or $tokenHex -notmatch '^[0-9A-Fa-f]+$') {
        throw "The [SonarTokens] entry '$tokenRef' is neither DPAPI hex nor a PT: value. Re-save the token via the IDE plugin."
      }
      $bytes = [byte[]]::new($tokenHex.Length / 2)
      for ($i = 0; $i -lt $tokenHex.Length; $i += 2) {
        $bytes[$i / 2] = [Convert]::ToByte($tokenHex.Substring($i, 2), 16)
      }
      try {
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                  $bytes, $null, 'CurrentUser')
        $token = [System.Text.Encoding]::UTF8.GetString($plain)
      } catch {
        throw "DPAPI decrypt failed - the blob was created by a different Windows user or on a different machine. Re-save the token via the IDE plugin (Tools > Options > Third Party > Sonar Integration)."
      }
    }
  }
}

# Make JsonPath relative to ProjectPath so sonar-scanner picks it up
# regardless of absolute drive paths.
$relJson = ''
try {
  $relJson = (Resolve-Path $JsonPath -Relative -RelativeBasePath $ProjectPath).TrimStart('.\').TrimStart('.','/')
} catch {
  # PowerShell 5.1 lacks -RelativeBasePath -> fall back to manual prefix-strip
  $absJson = (Resolve-Path $JsonPath).Path
  $absProj = (Resolve-Path $ProjectPath).Path
  if ($absJson.StartsWith($absProj, [StringComparison]::OrdinalIgnoreCase)) {
    $relJson = $absJson.Substring($absProj.Length).TrimStart('\','/').Replace('\','/')
  } else {
    $relJson = $absJson  # absolut, sonar-scanner kommt damit klar
  }
}

# Die EINE Liste, die der Scanner bekommt: die Vorpruefung unten liest dieselbe.
# Mit -DisableDelphi kommen .dproj/.dpk/.dpr dazu, weil's die sind, die das
# Plugin parsed (und an denen es bei externen Repos crashed).
$effectiveExclusions = $Exclusions
if ($DisableDelphi) {
  $effectiveExclusions = "$Exclusions,**/*.dproj,**/*.dpk,**/*.dpr,**/*.dpkw"
}

$scannerArgs = @(
  "-Dsonar.host.url=$hostUrl"
  "-Dsonar.projectKey=$projectKey"
  "-Dsonar.projectName=$projectKey"
  "-Dsonar.sources=."
  "-Dsonar.sourceEncoding=UTF-8"
  "-Dsonar.exclusions=$effectiveExclusions"
  "-Dsonar.externalIssuesReportPaths=$relJson"
)

if ($DisableDelphi) {
  # Beide Plugin-Varianten (IntegraDev = key 'delphi', alter Community-Fork
  # = key 'communitydelphi') gleichzeitig stilllegen. Leere file.suffixes
  # bewirkt: kein File matched mehr die Delphi-Language - der Sensor
  # bekommt 0 Input und exit'd ohne Stack-Trace.
  $scannerArgs += @(
    "-Dsonar.delphi.file.suffixes="
    "-Dsonar.communitydelphi.file.suffixes="
    "-Dsonar.lang.patterns.delphi="
    "-Dsonar.lang.patterns.communitydelphi="
  )
}

Write-Host "Scanner:  $ScannerPath" -ForegroundColor DarkGray
Write-Host "Host:     $hostUrl"     -ForegroundColor DarkGray
Write-Host "Project:  $projectKey"  -ForegroundColor DarkGray
Write-Host "JSON:     $relJson (relative to $ProjectPath)" -ForegroundColor DarkGray
Write-Host "Token:    ($($token.Length) chars from $tokenSource)" -ForegroundColor DarkGray

# Sonar-Muster -> Regex: **/ = beliebig viele Ordner, * und ? bleiben innerhalb
# eines Ordners. Gross-/Kleinschreibung zaehlt, wie beim Scanner.
function ConvertTo-SonarPathRegex([string]$pattern) {
  $p  = $pattern.Trim().Replace('\', '/')
  $rx = New-Object System.Text.StringBuilder
  [void]$rx.Append('^')
  $i = 0
  while ($i -lt $p.Length) {
    if ([string]::CompareOrdinal($p, $i, '**/', 0, 3) -eq 0) {
      [void]$rx.Append('(?:.*/)?'); $i += 3
    } elseif ([string]::CompareOrdinal($p, $i, '**', 0, 2) -eq 0) {
      [void]$rx.Append('.*'); $i += 2
    } elseif ($p[$i] -eq '*') {
      [void]$rx.Append('[^/]*'); $i++
    } elseif ($p[$i] -eq '?') {
      [void]$rx.Append('[^/]'); $i++
    } else {
      [void]$rx.Append([regex]::Escape([string]$p[$i])); $i++
    }
  }
  [void]$rx.Append('$')
  return New-Object System.Text.RegularExpressions.Regex($rx.ToString())
}

# Git ueber Process statt `& git`, aus zwei Gruenden: stdin muss binaer sein
# (NUL-getrennt, UTF-8; als Text wird unter Windows aus \n ein \r\n, und
# check-ignore prueft dann Pfade mit angehaengtem \r), und mit
# ErrorActionPreference=Stop wird unter Windows PowerShell 5.1 jede
# stderr-Zeile von git zum Abbruch.
function Invoke-Git([string]$gitExe, [string]$workDir, [string]$gitArgs, [byte[]]$stdin = $null) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $gitExe
  $psi.Arguments = "-C `"$($workDir.Replace('\', '/'))`" $gitArgs"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  try {
    # stdout/stderr parallel leeren: bei vollem Puffer blockiert git, waehrend
    # wir noch in stdin schreiben.
    $outBuffer = New-Object System.IO.MemoryStream
    $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outBuffer)
    $errTask = $proc.StandardError.ReadToEndAsync()
    if ($stdin) { $proc.StandardInput.BaseStream.Write($stdin, 0, $stdin.Length) }
    $proc.StandardInput.Close()
    $outTask.Wait()
    $proc.WaitForExit()
    return @{
      ExitCode = $proc.ExitCode
      Output   = [System.Text.Encoding]::UTF8.GetString($outBuffer.ToArray())
      Error    = $errTask.Result.Trim()
    }
  } finally {
    $proc.Dispose()
  }
}

# Sonar verwirft Findings zu Dateien, die es unter dem Scan-Ordner nicht
# findet, und der Scanner meldet trotzdem Erfolg. Ein falscher ProjectPath
# ergab so ein leeres Projekt mit "Upload complete" - also vorher pruefen.
$report = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reportFiles = @($report.issues | ForEach-Object { $_.primaryLocation.filePath } | Sort-Object -Unique)
if ($reportFiles.Count -gt 0) {
  $missingFiles = @($reportFiles | Where-Object {
    -not (Test-Path -LiteralPath ([IO.Path]::Combine($ProjectPath, $_)) -PathType Leaf)
  })
  $foundCount = $reportFiles.Count - $missingFiles.Count
  Write-Host "Report:   $($reportFiles.Count) files, $foundCount found under ProjectPath" -ForegroundColor DarkGray
  if ($foundCount -eq 0) {
    throw @"
None of the $($reportFiles.Count) files in the report exist under ProjectPath.
  ProjectPath: $ProjectPath
  Example:     $($reportFiles[0])
ProjectPath must be the folder the analysis ran on: the paths in the report
are relative to it. Sonar would import 0 issues.
"@
  }
  if ($missingFiles.Count -gt 0) {
    $examples = ($missingFiles | Select-Object -First 3) -join ', '
    Write-Warning "$($missingFiles.Count) of $($reportFiles.Count) report files not found under ProjectPath, their findings will be dropped. Examples: $examples"
  }

  # "found" heisst noch nicht "importiert": der Scanner verwirft auch Dateien,
  # die sonar.exclusions treffen oder die Git vor ihm verbirgt, und nennt davon
  # nur fuenf Beispiele. Jede Datei zaehlt genau einmal, in der Reihenfolge des
  # Scanners: erst die Muster, dann SCM.
  $missingSet = New-Object 'System.Collections.Generic.HashSet[string]' (
    [string[]]$missingFiles, [StringComparer]::OrdinalIgnoreCase)
  $findingsPerFile = @{}
  foreach ($issue in $report.issues) {
    $findingsPerFile[$issue.primaryLocation.filePath] += 1
  }
  function Measure-Findings([string[]]$files) {
    $sum = 0
    foreach ($f in $files) { $sum += $findingsPerFile[$f] }
    return $sum
  }

  $excludedFiles = New-Object System.Collections.Generic.List[string]
  $embeddedFiles = New-Object System.Collections.Generic.List[string]
  $ignoredFiles  = New-Object System.Collections.Generic.List[string]
  $scmFiles      = New-Object System.Collections.Generic.List[string]
  $embeddedRepos = @{}

  $exclusionRegexes = @($effectiveExclusions -split ',' | Where-Object { $_.Trim() } |
    ForEach-Object { ConvertTo-SonarPathRegex $_ })
  foreach ($file in $reportFiles) {
    if ($missingSet.Contains($file)) { continue }
    $hit = $false
    foreach ($rx in $exclusionRegexes) {
      if ($rx.IsMatch($file.Replace('\', '/'))) { $hit = $true; break }
    }
    if ($hit) { $excludedFiles.Add($file) } else { $scmFiles.Add($file) }
  }

  # Fehlt git oder ist ProjectPath kein Repo, wendet auch der Scanner keine
  # SCM-Regeln an. Scheitert die Pruefung, bleibt es bei einem Hinweis: die
  # Vorpruefung darf den Upload nie verhindern.
  $scmSkipped = $null
  $gitCmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $gitCmd) {
    $scmSkipped = 'git not found'
  } else {
    try {
      $inside = Invoke-Git $gitCmd.Source $ProjectPath 'rev-parse --is-inside-work-tree'
      if ($inside.ExitCode -ne 0 -or $inside.Output.Trim() -ne 'true') {
        $scmSkipped = 'ProjectPath is not a git repository'
      }
    } catch {
      $scmSkipped = "git failed: $($_.Exception.Message)"
    }
  }

  if ($scmSkipped) {
    Write-Host "Report:   SCM check skipped: $scmSkipped" -ForegroundColor DarkGray
  } else {
    try {
      $git = $gitCmd.Source
      # Alle Pfade relativ zu ProjectPath mit /, '' = das Repo von ProjectPath.
      # Je Ordner genau eine .git-Pruefung, je Repo genau ein git-Aufruf.
      $repoOfDir = @{}
      function Get-OwningRepo([string]$dir) {
        if (-not $dir) { return '' }
        if ($repoOfDir.ContainsKey($dir)) { return $repoOfDir[$dir] }
        $owner = $dir
        if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($ProjectPath, $dir, '.git')))) {
          $slash = $dir.LastIndexOf('/')
          $owner = if ($slash -gt 0) { Get-OwningRepo $dir.Substring(0, $slash) } else { '' }
        }
        $repoOfDir[$dir] = $owner
        return $owner
      }

      $gitlinksOfRepo = @{}
      function Test-Gitlink([string]$repo, [string]$path) {
        if (-not $gitlinksOfRepo.ContainsKey($repo)) {
          $links = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
          $index = Invoke-Git $git ([IO.Path]::Combine($ProjectPath, $repo)) 'ls-files -s -z'
          foreach ($entry in $index.Output.Split([char]0)) {
            if ($entry.StartsWith('160000 ')) { [void]$links.Add($entry.Substring($entry.IndexOf("`t") + 1)) }
          }
          $gitlinksOfRepo[$repo] = $links
        }
        return $gitlinksOfRepo[$repo].Contains($path)
      }

      # Sichtbar ist ein verschachteltes Repo nur als Gitlink im Index seines
      # Eltern-Repos, und nur wenn das Eltern-Repo selbst sichtbar ist.
      $visibleRepo = @{ '' = $true }
      function Test-RepoVisible([string]$repo) {
        if ($visibleRepo.ContainsKey($repo)) { return $visibleRepo[$repo] }
        $slash = $repo.LastIndexOf('/')
        $parent = if ($slash -gt 0) { Get-OwningRepo $repo.Substring(0, $slash) } else { '' }
        $inParent = if ($parent) { $repo.Substring($parent.Length + 1) } else { $repo }
        $visible = (Test-RepoVisible $parent) -and (Test-Gitlink $parent $inParent)
        $visibleRepo[$repo] = $visible
        return $visible
      }

      $filesOfRepo = @{}
      foreach ($file in $scmFiles) {
        $norm = $file.Replace('\', '/')
        $slash = $norm.LastIndexOf('/')
        $repo = if ($slash -gt 0) { Get-OwningRepo $norm.Substring(0, $slash) } else { '' }
        if (Test-RepoVisible $repo) {
          if (-not $filesOfRepo.ContainsKey($repo)) { $filesOfRepo[$repo] = @{} }
          $inRepo = if ($repo) { $norm.Substring($repo.Length + 1) } else { $norm }
          $filesOfRepo[$repo][$inRepo] = $file
        } else {
          $embeddedFiles.Add($file)
          $embeddedRepos[$repo] += 1
        }
      }

      # check-ignore im zustaendigen Repo: aus dem Eltern-Repo heraus gaelte fuer
      # Dateien hinter einem Gitlink dessen eigene .gitignore nicht.
      foreach ($repo in @($filesOfRepo.Keys)) {
        $paths = @($filesOfRepo[$repo].Keys)
        $stdin = [System.Text.Encoding]::UTF8.GetBytes(($paths -join "`0") + "`0")
        $check = Invoke-Git $git ([IO.Path]::Combine($ProjectPath, $repo)) 'check-ignore -z --stdin' $stdin
        if ($check.ExitCode -gt 1) { throw "git check-ignore in '$repo': $($check.Error)" }
        foreach ($path in $check.Output.Split([char]0)) {
          if ($path) { $ignoredFiles.Add($filesOfRepo[$repo][$path]) }
        }
      }
    } catch {
      $scmSkipped = "git failed: $($_.Exception.Message)"
      Write-Host "Report:   SCM check incomplete: $scmSkipped" -ForegroundColor DarkGray
    }
  }

  $droppedCount = $excludedFiles.Count + $embeddedFiles.Count + $ignoredFiles.Count
  $droppedLabel = if ($scmSkipped) { "$droppedCount+" } else { "$droppedCount" }
  Write-Host "Report:   $droppedLabel of $foundCount found files will be dropped by the scanner" -ForegroundColor DarkGray
  if ($excludedFiles.Count -gt 0) {
    $examples = ($excludedFiles | Select-Object -First 3) -join ', '
    Write-Warning "$($excludedFiles.Count) report files ($(Measure-Findings $excludedFiles) findings) match sonar.exclusions, their findings will be dropped. Examples: $examples"
  }
  if ($embeddedFiles.Count -gt 0) {
    $repoList = ($embeddedRepos.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 5 |
      ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', '
    Write-Warning "$($embeddedFiles.Count) report files ($(Measure-Findings $embeddedFiles) findings) are in embedded git repos the scanner does not see (own .git, no gitlink in the parent index), their findings will be dropped: $repoList"
  }
  if ($ignoredFiles.Count -gt 0) {
    $examples = ($ignoredFiles | Select-Object -First 3) -join ', '
    Write-Warning "$($ignoredFiles.Count) report files ($(Measure-Findings $ignoredFiles) findings) are gitignored in their repo, their findings will be dropped. Examples: $examples"
  }
}

if ($DryRun) {
  Write-Host ''
  Write-Host 'DRY RUN - command that would run:' -ForegroundColor Yellow
  Write-Host "  cd $ProjectPath"
  Write-Host "  `$env:SONAR_TOKEN = '***'"
  Write-Host "  $ScannerPath $($scannerArgs -join ' ')"
  exit 0
}

Write-Host ''
$previousToken = $env:SONAR_TOKEN
$env:SONAR_TOKEN = $token
$rc = 0
Push-Location $ProjectPath
try {
  & $ScannerPath @scannerArgs
  $rc = $LASTEXITCODE
} finally {
  Pop-Location
  if ($previousToken) {
    $env:SONAR_TOKEN = $previousToken
  } else {
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
  }
}

if ($rc -ne 0) {
  Write-Error "sonar-scanner failed with exit code $rc."
  exit $rc
}
Write-Host ''
Write-Host "Upload complete. Dashboard: $hostUrl/dashboard?id=$projectKey" -ForegroundColor Green
exit 0
