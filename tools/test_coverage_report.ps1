#requires -Version 5.1
<#
.SYNOPSIS
    Test-Coverage-Estimation pro SCA-Detektor (Markdown-Tabelle).

.DESCRIPTION
    Statt Line-Coverage (das braeuchte delphi-code-coverage mit .map-Files)
    verwenden wir Test-Category-Coverage als Heuristik: pro Detektor wird
    geprueft, welche der 7 Standard-Kategorien durch Tests abgedeckt sind:

       +20%  Positive case          (Detector triggert auf erwartetem Pattern)
       +20%  Negative case          (false-positive guard)
       +15%  Severity/Kind asserted (KindAndSeverity-Test)
       +15%  Finding-Inhalt         (MissingVar/LineNumber asserted)
       +10%  Multi-Hit              (mehrere Findings in selber Methode)
       +10%  Suppression            (// noinspection)
       +10%  Edge / Boundary / Regression

    Auf 100% gekappt. Quelle: SCA-Test-Best-Practices-Recherche
    (PMD, Roslyn, ESLint, SonarQube).

.EXAMPLE
    PS> .\tools\test_coverage_report.ps1
    PS> .\tools\test_coverage_report.ps1 > coverage.md
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$DetectorDir = Join-Path $RepoRoot 'StaticCodeAnalyserForm\sources\Detectors'
$TestDir     = Join-Path $RepoRoot 'StaticCodeAnalyserForm\tests'

# Mapping: Detector-Unit -> emittierte FindingKinds.
# Mehrere Detektoren koennen denselben Kind teilen (z.B. uLeakDetector2 +
# uFieldLeak teilen fkMemoryLeak); dann werden ihre Tests zusammengezaehlt.
$DetectorKinds = [ordered]@{
    'uLeakDetector2'         = @('fkMemoryLeak')
    'uFieldLeak'             = @('fkMemoryLeak')
    'uCodeSmells2'           = @('fkEmptyExcept')
    'uSQLInjection'          = @('fkSQLInjection')
    'uSQLInjectionScore'     = @()
    'uHardcodedSecret'       = @('fkHardcodedSecret')
    'uFormatMismatch'        = @('fkFormatMismatch')
    'uConcatToFormat'        = @('fkConcatToFormat')
    'uUnusedUses'            = @('fkUnusedUses')
    'uNilDeref'              = @('fkNilDeref')
    'uMissingFinally'        = @('fkMissingFinally')
    'uDivByZero'             = @('fkDivByZero')
    'uDeadCode'              = @('fkDeadCode')
    'uLongMethod'            = @('fkLongMethod')
    'uLongParamList'         = @('fkLongParamList')
    'uMagicNumbers'          = @('fkMagicNumber')
    'uDuplicateString'       = @('fkDuplicateString')
    'uDuplicateBlock'        = @('fkDuplicateBlock')
    'uHardcodedPath'         = @('fkHardcodedPath')
    'uDebugOutput'           = @('fkDebugOutput')
    'uDeepNesting'           = @('fkDeepNesting')
    'uCyclomaticComplexity'  = @('fkCyclomaticComplexity')
    'uTodoComment'           = @('fkTodoComment')
    'uEmptyMethod'           = @('fkEmptyMethod')
    'uCustomRuleDetector'    = @('fkCustomRule')
    'uCustomClassDiscovery'  = @()
    'uWithStatement'         = @('fkWithStatement')
    'uReversedForRange'      = @('fkReversedForRange')
    'uSelfAssignment'        = @('fkSelfAssignment')
    'uVirtualCallInCtor'     = @('fkVirtualCallInCtor')
    'uLengthUnderflow'       = @('fkLengthUnderflow')
    'uVisibilityCheck'       = @('fkCanBeUnitPrivate','fkCanBeStrictPrivate','fkCanBeProtected','fkUnusedPublicMember')
    'uUnusedLocal'           = @('fkUnusedLocalVar')
    'uUnusedParameter'       = @('fkUnusedParameter')
    'uTautologicalExpr'      = @('fkTautologicalBoolExpr')
    'uDfmDefaultName'        = @('fkDfmDefaultName')
    'uDfmHardcodedCaption'   = @('fkDfmHardcodedCaption')
    'uDfmHardcodedDbCreds'   = @('fkDfmHardcodedDbCreds')
    'uDfmDuplicateBinding'   = @('fkDfmDuplicateBinding')
    'uDfmDeadEvent'          = @('fkDfmDeadEvent')
    'uDfmOrphanHandler'      = @('fkDfmOrphanHandler')
    'uDfmEmptyBoundEvent'    = @('fkDfmEmptyBoundEvent')
    'uDfmSchemaMismatch'     = @('fkDfmSchemaMismatch')
    'uDfmCircularDataSource' = @('fkDfmCircularDataSource')
    'uDfmSqlFromUserInput'   = @('fkDfmSqlFromUserInput')
    'uDfmRequiredField'      = @('fkDfmRequiredFieldUnbound','fkDfmRequiredFieldNotVisible')
    'uDfmFieldTypeMismatch'  = @('fkDfmFieldTypeMismatch')
    'uDfmTabOrderConflict'   = @('fkDfmTabOrderConflict')
    'uDfmForbiddenClass'     = @('fkDfmForbiddenClass')
    'uDfmDbInUiForm'         = @('fkDfmDbInUiForm')
    'uDfmCrossFormCoupling'  = @('fkDfmCrossFormCoupling')
    'uDfmLayerViolation'     = @('fkDfmLayerViolation')
    'uDfmGodHandler'         = @('fkDfmGodHandler')
    'uDfmActionMismatch'     = @('fkDfmActionMismatch')
    'uDfmMasterDetailUnlinked' = @('fkDfmMasterDetailUnlinked')
    'uDfmDataModuleSplitHint'  = @('fkDfmDataModuleSplitHint')
    'uSqlDangerousStatement'   = @('fkSqlDangerousStatement')
}

$Weights = [ordered]@{
    positive        = 20
    negative        = 20
    severity        = 15
    finding_content = 15
    multi_hit       = 10
    suppression     = 10
    edge            = 10
}

function Get-TestBodies {
    param([string] $Content)
    # Findet pro 'procedure TXxx.Method;' den Body bis zur naechsten
    # 'procedure'-Zeile. Liefert Hashtable: TestName -> Body-Text.
    $result = @{}
    $lines  = $Content -split "`r?`n"
    $proc   = $null
    $sb     = New-Object System.Text.StringBuilder
    foreach ($line in $lines) {
        if ($line -match '^procedure\s+T[A-Za-z0-9_]+\.([A-Za-z0-9_]+);\s*$') {
            if ($null -ne $proc) {
                $result[$proc] = $sb.ToString()
            }
            $proc = $Matches[1]
            $sb = New-Object System.Text.StringBuilder
        }
        if ($null -ne $proc) {
            [void]$sb.AppendLine($line)
        }
    }
    if ($null -ne $proc) {
        $result[$proc] = $sb.ToString()
    }
    return $result
}

function Get-Categories {
    param([string] $TestName, [string] $Body)
    $cats = New-Object System.Collections.Generic.HashSet[string]
    if ($TestName -match '(NoFinding|NoFalsePositive|NotDetected|NotReported|Silent|NoCrash|Suppressed|Skipped|Excluded|Ignored|NotMatched|NotIndexed|NotInPrimary)') {
        [void]$cats.Add('negative')
    }
    # 'Reports?' matched sowohl 'Reported' (Past Tense, our convention) als
    # auch 'Reports' (Present Tense, alternative convention im aelteren Code,
    # z.B. 'Path_X_ReportsWarning', 'Cyclomatic_Y_ReportsHint'). Plus
    # terminale Severity-Suffixe ('_ReportsHint', '_ReportsWarning',
    # '_ReportsError') als zusaetzliche Trigger.
    if (($TestName -match '(Reports?|Detected|Discovered|Triggered|Instantiable|CanBe(Unit|Strict)?Private|CanBeProtected|Score\d|Easy|Hard|Trivial|Medium|VeryHard|StaticOnly|Found|Indexed|MentionsQuickFix|StillReported|FromIndex|HitDetectionStillWorks|_ReportsHint|_ReportsWarning|_ReportsError)') -and -not $cats.Contains('negative')) {
        [void]$cats.Add('positive')
    }
    if ($TestName -match '(KindAndSeverity|Finding_Kind|_Severity)') {
        [void]$cats.Add('severity')
    }
    if (($Body -match 'Severity') -and ($Body -match 'Assert\.AreEqual\(ls')) {
        [void]$cats.Add('severity')
    }
    if ($TestName -match '(MissingVar|LineNumber|_Mentions|Line_)') {
        [void]$cats.Add('finding_content')
    }
    if (($Body -match 'MissingVar') -and ($Body -match 'Assert\.Contains')) {
        [void]$cats.Add('finding_content')
    }
    if ($TestName -match '(Multi|All(Reported|Found)|Several|MultipleHits)') {
        [void]$cats.Add('multi_hit')
    }
    if (($TestName -match 'Suppression|Noinspection') -or ($Body -match '// noinspection')) {
        [void]$cats.Add('suppression')
    }
    if ($TestName -match '(Boundary|Threshold|Exactly|Empty|Regression|DeepNest|Pathological|UnicodeOrEmpty|GracefulNoCrash|NestedComponent|CaseInsensitive|CaseSensitive|Edge|Defensive|Whitespace|InString|InComment|FromEqualsTo|NoMatch|NilFileList|EmptyFileList|NonExistent|WordBoundary|InlineVar)') {
        [void]$cats.Add('edge')
    }
    return $cats
}

# 1. Alle Test-Dateien einlesen
$testBodiesPerFile = @{}
Get-ChildItem -Path $TestDir -Filter 'uTest*.pas' | ForEach-Object {
    try {
        $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8
    } catch {
        $content = Get-Content -Path $_.FullName -Raw
    }
    $testBodiesPerFile[$_.Name] = Get-TestBodies -Content $content
}

# 2. Pro Detektor Tests sammeln + Kategorien aggregieren
$rows = New-Object System.Collections.Generic.List[object]
foreach ($detector in $DetectorKinds.Keys) {
    $pasPath = Join-Path $DetectorDir "$detector.pas"
    if (-not (Test-Path $pasPath)) { continue }
    $loc = (Get-Content -Path $pasPath).Count
    $kinds = @($DetectorKinds[$detector])
    $cls   = 'T' + $detector.Substring(1)
    # Pattern: Wortgrenze um jeden Kind + Class. Dem Detector dediziertes
    # Test-File (uTest<Name>.pas) wird IMMER mitgezaehlt, auch wenn die
    # einzelne Test-Methode weder Kind noch Class-Name nennt - das deckt
    # Helper-Detektoren ab (uCustomClassDiscovery -> RunDiscover, etc.).
    $detectorStem      = $detector.Substring(1)
    $dedicatedTestFile = "uTest$detectorStem.pas"
    $allTerms = @($kinds) + @($cls)
    $pattern = '\b(' + (($allTerms | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

    $matchedTests = New-Object System.Collections.Generic.List[hashtable]
    $aggCats = New-Object System.Collections.Generic.HashSet[string]

    foreach ($file in $testBodiesPerFile.Keys) {
        $isDedicated = ($file -eq $dedicatedTestFile)
        foreach ($testName in $testBodiesPerFile[$file].Keys) {
            $body = $testBodiesPerFile[$file][$testName]
            if ($isDedicated -or ($body -match $pattern)) {
                $matchedTests.Add(@{ File = $file; Name = $testName; Body = $body })
                $catSet = Get-Categories -TestName $testName -Body $body
                foreach ($c in $catSet) { [void]$aggCats.Add($c) }
            }
        }
    }

    $score = 0
    foreach ($c in $aggCats) {
        if ($Weights.Contains($c)) { $score += $Weights[$c] }
    }
    if ($score -gt 100) { $score = 100 }

    $rows.Add([pscustomobject]@{
        Detector = $detector
        LOC      = $loc
        Tests    = $matchedTests.Count
        Cats     = $aggCats
        Score    = $score
    })
}

# 3. Markdown rausschreiben (sortiert nach Score asc, damit Schwachpunkte oben)
$rows = $rows | Sort-Object -Property Score, Detector

Write-Output "# SCA-Detector Test-Coverage (Test-Category-Heuristik)"
Write-Output ""
Write-Output "Heuristik: 7 Test-Kategorien (Positive 20% / Negative 20% / Severity 15% / Finding-Inhalt 15% / Multi-Hit 10% / Suppression 10% / Edge 10%)."
Write-Output "Nicht zu verwechseln mit Line-Coverage. Siehe Header des Skripts."
Write-Output ""
Write-Output "| Detector | LOC | Tests | Pos | Neg | Sev | FC | MH | Sup | Edge | Coverage |"
Write-Output "|---|---:|---:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---:|"
$catOrder = @('positive','negative','severity','finding_content','multi_hit','suppression','edge')
foreach ($r in $rows) {
    $cells = foreach ($c in $catOrder) {
        if ($r.Cats.Contains($c)) { 'X' } else { '.' }
    }
    $filled = [int]([math]::Floor($r.Score / 10))
    $bar = ('#' * $filled) + ('-' * (10 - $filled))
    Write-Output ("| {0} | {1} | {2} | {3} | ``{4}`` {5}% |" -f `
        $r.Detector, $r.LOC, $r.Tests, ($cells -join ' | '), $bar, $r.Score)
}

# Summary
$avg = 0
if ($rows.Count -gt 0) {
    $avg = ($rows | Measure-Object -Property Score -Average).Average
}
$weak = $rows | Where-Object { $_.Score -lt 60 }
Write-Output ""
Write-Output ("**Durchschnitt**: {0:N1}% across {1} Detektoren" -f $avg, $rows.Count)
if ($weak) {
    Write-Output ("**Unter 60%**: {0} ({1})" -f $weak.Count, (($weak | ForEach-Object { $_.Detector }) -join ', '))
} else {
    Write-Output "**Alle Detektoren >= 60%** [OK]"
}
