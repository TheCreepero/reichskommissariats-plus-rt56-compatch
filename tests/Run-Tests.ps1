[CmdletBinding()]
param(
    [string]$Suite = 'All',

    [switch]$CI,
    [string]$OutputFile,
    [switch]$InstallPrereqs
)

$ErrorActionPreference = 'Stop'

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

Import-Module $pesterModule -Force

$testDir = $PSScriptRoot
$testFiles = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -File | Sort-Object Name | ForEach-Object { $_.FullName })
if ($Suite -ne 'All') {
    $testFiles = @($testFiles | Where-Object { (Split-Path -Leaf $_) -eq "$Suite.Tests.ps1" })
}
if ($testFiles.Count -eq 0) {
    $availableSuites = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name -replace '\.Tests\.ps1$', '' })
    Write-Host "No test file matches suite '$Suite'. Suites: All, $($availableSuites -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  Mod Test Suite Runner (Pester $($pesterModule.Version))" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Suite:       $Suite" -ForegroundColor Gray
Write-Host "Test Files:  $(($testFiles | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Gray
Write-Host "CI Mode:     $($CI.IsPresent)`n" -ForegroundColor Gray

$config = [PesterConfiguration]::Default
$config.Run.Path = $testFiles
$config.Run.PassThru = $true
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

$failedTotal = $result.FailedCount + $result.FailedBlocksCount + $result.FailedContainersCount
$summary = "  Summary: $($result.PassedCount) Passed, $($result.FailedCount) Failed, $($result.SkippedCount) Skipped"
if ($result.FailedContainersCount -gt 0) { $summary += ", $($result.FailedContainersCount) test file(s) failed to run" }
if ($result.FailedBlocksCount -gt 0) { $summary += ", $($result.FailedBlocksCount) block(s) failed in setup or teardown" }

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
