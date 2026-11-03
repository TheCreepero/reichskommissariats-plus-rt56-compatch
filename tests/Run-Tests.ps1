[CmdletBinding()]
param(
    [string]$Suite = 'All',

    [switch]$Changed,
    [switch]$ListOnly,
    [switch]$CI,
    [string]$OutputFile,
    [switch]$InstallPrereqs,
    [int]$ThrottleLimit = 0,
    [switch]$EngineTests,

    [string]$ChildTestFile,
    [string]$ChildResultPath,
    [string]$ChildPesterPath,
    [string]$ChildExcludeTags = ''
)

$ErrorActionPreference = 'Stop'

if ($ChildTestFile) {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    Import-Module $ChildPesterPath -Force
    $childConfiguration = [PesterConfiguration]::Default
    $childConfiguration.Run.Path = @($ChildTestFile)
    $childConfiguration.Run.PassThru = $true
    $childConfiguration.Output.Verbosity = 'Normal'
    $childExcludedTags = @($ChildExcludeTags -split ',' | Where-Object { $_ })
    if ($childExcludedTags.Count -gt 0) {
        $childConfiguration.Filter.ExcludeTag = $childExcludedTags
    }
    $childResult = Invoke-Pester -Configuration $childConfiguration
    $childCounts = [ordered]@{
        PassedCount           = $childResult.PassedCount
        FailedCount           = $childResult.FailedCount
        SkippedCount          = $childResult.SkippedCount
        FailedBlocksCount     = $childResult.FailedBlocksCount
        FailedContainersCount = $childResult.FailedContainersCount
    }
    [System.IO.File]::WriteAllText($ChildResultPath, ($childCounts | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    exit 0
}

function Test-SuiteGlobMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Glob
    )

    $normalizedGlob = $Glob.Replace('\', '/')
    $matchTarget = $Path
    if (-not $normalizedGlob.Contains('/')) {
        $matchTarget = ($Path -split '/')[-1]
    }
    $globPattern = [regex]::Escape($normalizedGlob).Replace('\*\*/', '(.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]')
    return [regex]::IsMatch($matchTarget, '^' + $globPattern + '$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-ChangedRepoPaths {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $statusOutput = @(& git -C $RepoRoot status --porcelain=v1 -z -uall)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed in $RepoRoot; -Changed needs the repository to be a git work tree"
    }
    $statusEntries = @(($statusOutput -join "`n") -split "`0" | Where-Object { $_ -ne '' })
    $changedPaths = [System.Collections.Generic.List[string]]::new()
    $entryIndex = 0
    while ($entryIndex -lt $statusEntries.Count) {
        $statusEntry = $statusEntries[$entryIndex]
        $changedPaths.Add($statusEntry.Substring(3))
        $entryIndex += $(if ('R', 'C' -contains [string]$statusEntry[0]) { 2 } else { 1 })
    }
    return @($changedPaths)
}

function Get-AddedSuiteGlobMap {
    return [ordered]@{
        BuildEngine  = @('build.ps1', 'tools/HoiModBuild.ps1', 'tools/HoiModBuild.json', 'tests/Run-Tests.ps1')
        Descriptor   = @('descriptor.mod', 'thumbnail.png')
        ImageSources = @('tools/HoiImageSources.ps1', 'tests/fixtures/image-sources/**')
        Knowledge    = @('*.md', '*.ps1', '*.py', 'docs/**', 'wiki/**', '.claude/**', '.agents/**')
    }
}

function Get-SuiteGlobMap {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $suiteGlobMap = [ordered]@{
        none = @('.github/**')
    }
    $settingsPath = Join-Path $RepoRoot 'tools\HoiModBuild.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return $suiteGlobMap
    }
    $settings = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['testSuites'] -or $null -eq $settings.testSuites) {
        return $suiteGlobMap
    }
    foreach ($suiteProperty in $settings.testSuites.PSObject.Properties) {
        $existingGlobs = @()
        if ($suiteGlobMap.Contains($suiteProperty.Name)) {
            $existingGlobs = @($suiteGlobMap[$suiteProperty.Name])
        }
        $suiteGlobMap[$suiteProperty.Name] = @($existingGlobs + @($suiteProperty.Value | ForEach-Object { [string]$_ }))
    }
    return $suiteGlobMap
}

function Get-ChangedSuiteSelection {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$AvailableSuites
    )

    $changedPaths = @(Get-ChangedRepoPaths -RepoRoot $RepoRoot)
    $suiteGlobMap = Get-SuiteGlobMap -RepoRoot $RepoRoot
    $addedSuiteGlobMap = Get-AddedSuiteGlobMap
    $selectedSuites = [System.Collections.Generic.List[string]]::new()
    $runAllPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($changedPath in $changedPaths) {
        $pathIsMapped = $false
        $testFileMatch = [regex]::Match($changedPath, '^tests/([^/]+)\.Tests\.ps1$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($testFileMatch.Success) {
            $pathIsMapped = $true
            $selectedSuites.Add($testFileMatch.Groups[1].Value)
        }
        foreach ($suiteName in $suiteGlobMap.Keys) {
            if (-not @($suiteGlobMap[$suiteName] | Where-Object { Test-SuiteGlobMatch -Path $changedPath -Glob $_ })) {
                continue
            }
            if ($suiteName -eq 'all') {
                $runAllPaths.Add($changedPath)
            } elseif ($suiteName -ne 'none') {
                $selectedSuites.Add($suiteName)
            }
            $pathIsMapped = $true
        }
        foreach ($suiteName in $addedSuiteGlobMap.Keys) {
            if (@($addedSuiteGlobMap[$suiteName] | Where-Object { Test-SuiteGlobMatch -Path $changedPath -Glob $_ })) {
                $selectedSuites.Add($suiteName)
            }
        }
        if (-not $pathIsMapped) {
            $runAllPaths.Add($changedPath)
        }
    }
    $suiteNames = @($AvailableSuites | Where-Object { $selectedSuites -contains $_ })
    if ($runAllPaths.Count -gt 0) {
        $suiteNames = @($AvailableSuites)
    }
    return [PSCustomObject]@{
        ChangedPaths = $changedPaths
        RunAllPaths  = @($runAllPaths)
        SuiteNames   = $suiteNames
    }
}

function Read-SharedTextLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ($true) {
        try {
            $sharedStream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $streamReader = [System.IO.StreamReader]::new($sharedStream, [System.Text.Encoding]::UTF8)
                return @($streamReader.ReadToEnd() -split "`r?`n" | Where-Object { $_ -ne '' })
            } finally {
                $sharedStream.Dispose()
            }
        } catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -gt $deadline) {
                throw
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Invoke-ParallelTestFiles {
    param(
        [Parameter(Mandatory = $true)][string[]]$TestFiles,
        [Parameter(Mandatory = $true)][int]$Throttle,
        [Parameter(Mandatory = $true)][string]$PesterPath,
        [AllowEmptyCollection()][string[]]$ExcludeTags = @()
    )

    $powerShellExecutable = if (Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $workFolder = Join-Path ([System.IO.Path]::GetTempPath()) ('hoi_tests_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workFolder -Force | Out-Null
    $totals = [ordered]@{ PassedCount = 0; FailedCount = 0; SkippedCount = 0; FailedBlocksCount = 0; FailedContainersCount = 0 }
    $pendingFiles = [System.Collections.Generic.Queue[string]]::new()
    foreach ($testFile in @($TestFiles | Sort-Object -Property { (Get-Item -LiteralPath $_).Length } -Descending)) {
        $pendingFiles.Enqueue($testFile)
    }
    $runningChildren = [System.Collections.Generic.List[PSObject]]::new()
    $boilerplatePattern = '^(Running tests from \d+ files\.|Tests completed in |Tests Passed: \d+)'
    try {
        while ($pendingFiles.Count -gt 0 -or $runningChildren.Count -gt 0) {
            while ($pendingFiles.Count -gt 0 -and $runningChildren.Count -lt $Throttle) {
                $testFile = $pendingFiles.Dequeue()
                $childStem = Join-Path $workFolder ([guid]::NewGuid().ToString('N'))
                $childArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ChildTestFile', "`"$testFile`"", '-ChildResultPath', "`"$childStem.json`"", '-ChildPesterPath', "`"$PesterPath`"")
                if ($ExcludeTags.Count -gt 0) {
                    $childArguments += @('-ChildExcludeTags', ($ExcludeTags -join ','))
                }
                $childProcess = Start-Process -FilePath $powerShellExecutable -ArgumentList $childArguments -RedirectStandardOutput "$childStem.out" -RedirectStandardError "$childStem.err" -NoNewWindow -PassThru
                $null = $childProcess.Handle
                $runningChildren.Add([PSCustomObject]@{ Process = $childProcess; TestFile = $testFile; Stem = $childStem })
            }
            foreach ($finishedChild in @($runningChildren | Where-Object { $_.Process.HasExited })) {
                $null = $runningChildren.Remove($finishedChild)
                foreach ($outputLine in @(Read-SharedTextLines -Path "$($finishedChild.Stem).out")) {
                    if ($outputLine -notmatch $boilerplatePattern) {
                        Write-Host $outputLine
                    }
                }
                if (-not (Test-Path -LiteralPath "$($finishedChild.Stem).json")) {
                    $totals.FailedContainersCount++
                    Write-Host "[-] $($finishedChild.TestFile): the test process ended with exit code $($finishedChild.Process.ExitCode) and no result" -ForegroundColor Red
                    $errorLines = @(Read-SharedTextLines -Path "$($finishedChild.Stem).err" | Where-Object { $_.Trim() })
                    foreach ($errorLine in @($errorLines | Select-Object -Last 20)) {
                        Write-Host "    $errorLine" -ForegroundColor Red
                    }
                    continue
                }
                $childCounts = [System.IO.File]::ReadAllText("$($finishedChild.Stem).json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                foreach ($countName in @($totals.Keys)) {
                    $totals[$countName] += [int]$childCounts.$countName
                }
            }
            Start-Sleep -Milliseconds 100
        }
    } finally {
        foreach ($runningChild in $runningChildren) {
            if (-not $runningChild.Process.HasExited) {
                & taskkill.exe /PID $runningChild.Process.Id /T /F 2>&1 | Out-Null
            }
        }
        Remove-Item -LiteralPath $workFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    return [PSCustomObject]$totals
}

$testDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $testDir
$availableSuites = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -File | Sort-Object Name | ForEach-Object { $_.Name -replace '\.Tests\.ps1$', '' })

if ($Changed -and $PSBoundParameters.ContainsKey('Suite')) {
    Write-Host "-Changed picks the suites itself; pass either -Changed or -Suite, not both." -ForegroundColor Red
    exit 1
}

$selectionLabel = 'all suites'
$selectedSuites = @($availableSuites)
if ($Changed) {
    $selection = Get-ChangedSuiteSelection -RepoRoot $repoRoot -AvailableSuites $availableSuites
    Write-Host "Changed files: $($selection.ChangedPaths.Count)" -ForegroundColor Gray
    if ($selection.RunAllPaths.Count -gt 0) {
        Write-Host "Outside the testSuites map of tools\HoiModBuild.json (or mapped to all): $($selection.RunAllPaths -join ', '); running all suites" -ForegroundColor Yellow
    }
    $selectedSuites = @($selection.SuiteNames)
    $selectionLabel = 'changed: ' + $(if ($selection.RunAllPaths.Count -gt 0) { 'all suites' } elseif ($selectedSuites.Count -gt 0) { $selectedSuites -join ', ' } else { 'none' })
    if ($selectedSuites.Count -eq 0) {
        Write-Host "No changed file needs a test suite." -ForegroundColor Green
        exit 0
    }
} elseif ($Suite -ne 'All') {
    $selectedSuites = @($availableSuites | Where-Object { $_ -eq $Suite })
    $selectionLabel = "suite: $Suite"
    if ($selectedSuites.Count -eq 0) {
        Write-Host "No test file matches suite '$Suite'. Suites: All, $($availableSuites -join ', ')" -ForegroundColor Red
        exit 1
    }
}

if ($ListOnly) {
    foreach ($selectedSuite in $selectedSuites) {
        Write-Host "Suite: $selectedSuite"
    }
    exit 0
}

$pesterModule = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pesterModule) {
    if ($InstallPrereqs -or $env:CI) {
        Write-Host "Pester 5+ not detected. Installing Pester to CurrentUser scope..." -ForegroundColor Yellow
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        Install-Module -Name Pester -MinimumVersion 5.3.0 -Scope CurrentUser -Force -SkipPublisherCheck | Out-Null
        $pesterModule = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1
    } else {
        Write-Host "Pester 5.0+ is required to run the tests. Run with -InstallPrereqs to install it." -ForegroundColor Red
        exit 1
    }
}

$testFiles = @($selectedSuites | ForEach-Object { Join-Path $testDir "$_.Tests.ps1" })
$parallelThrottle = if ($ThrottleLimit -gt 0) { $ThrottleLimit } else { [Math]::Max(1, [int][Math]::Floor([Environment]::ProcessorCount / 2)) }
$runInParallel = (-not $CI) -and $parallelThrottle -gt 1 -and $testFiles.Count -gt 1
$excludedTags = @(if (-not $CI -and -not $EngineTests) { 'Engine' })

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  Mod Test Suite Runner (Pester $($pesterModule.Version))" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Selection:   $selectionLabel" -ForegroundColor Gray
Write-Host "Test Files:  $(($testFiles | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Gray
Write-Host "Processes:   $(if ($runInParallel) { [Math]::Min($parallelThrottle, $testFiles.Count) } else { 1 })" -ForegroundColor Gray
Write-Host "Engine:      $(if ($excludedTags -contains 'Engine') { 'tests tagged Engine left out (the Manager runs them; -EngineTests or -CI runs them here)' } else { 'tests tagged Engine included' })" -ForegroundColor Gray
Write-Host "CI Mode:     $($CI.IsPresent)`n" -ForegroundColor Gray

if ($runInParallel) {
    $result = Invoke-ParallelTestFiles -TestFiles $testFiles -Throttle $parallelThrottle -PesterPath $pesterModule.Path -ExcludeTags $excludedTags
} else {
    Import-Module $pesterModule -Force
    $config = [PesterConfiguration]::Default
    $config.Run.Path = $testFiles
    $config.Run.PassThru = $true
    if ($excludedTags.Count -gt 0) {
        $config.Filter.ExcludeTag = $excludedTags
    }
    $config.Output.Verbosity = if ($CI) { 'Detailed' } else { 'Normal' }

    if ($CI) {
        if (-not $OutputFile) {
            $OutputFile = Join-Path $testDir "test-results.xml"
        }
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = $OutputFile
    }

    $result = Invoke-Pester -Configuration $config
}

$failedTotal = $result.FailedCount + $result.FailedBlocksCount + $result.FailedContainersCount
$summary = "  Summary: $($result.PassedCount) Passed, $($result.FailedCount) Failed, $($result.SkippedCount) Skipped"
if ($result.FailedContainersCount -gt 0) { $summary += ", $($result.FailedContainersCount) test file(s) failed to run" }
if ($result.FailedBlocksCount -gt 0) { $summary += ", $($result.FailedBlocksCount) block(s) failed in setup or teardown" }
$summary += " ($selectionLabel)"

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host $summary -ForegroundColor $(if ($failedTotal -gt 0) { "Red" } else { "Green" })
Write-Host "-------------------------------------------------------" -ForegroundColor Cyan

if ($CI -and (Test-Path $OutputFile)) {
    Write-Host "NUnit Test Results saved to: $OutputFile" -ForegroundColor Green
}

if ($failedTotal -gt 0) {
    exit 1
}
exit 0
