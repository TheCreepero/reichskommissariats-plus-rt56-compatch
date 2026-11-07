[CmdletBinding()]
param(
    [string]$CommitMessage = 'Update wiki from source',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Invoke-WikiGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $previousErrorAction = $ErrorActionPreference
    $previousEncoding = $null
    $ErrorActionPreference = 'Continue'
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    } catch {
        $previousEncoding = $null
    }
    try {
        $gitArguments = if ($WorkingDirectory) { @('-C', $WorkingDirectory) + $Arguments } else { $Arguments }
        $rawLines = @(& git @gitArguments 2>&1)
        $gitExitCode = $LASTEXITCODE
    } finally {
        if ($previousEncoding) {
            try { [Console]::OutputEncoding = $previousEncoding } catch { $null = $_ }
        }
        $ErrorActionPreference = $previousErrorAction
    }
    $global:LASTEXITCODE = 0
    $outputLines = @($rawLines | ForEach-Object { ([string]$_).TrimEnd() } | Where-Object { $_ -ne '' -and $_ -ne 'System.Management.Automation.RemoteException' })
    return [PSCustomObject]@{
        ExitCode = $gitExitCode
        Output   = $outputLines
        Text     = ($outputLines -join "`n")
    }
}

function Assert-WikiGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $gitResult = Invoke-WikiGit -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    if ($gitResult.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $($gitResult.ExitCode):`n$($gitResult.Text)"
    }
    return $gitResult
}

function Get-WikiModName {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $descriptorPath = Join-Path $RepoRoot 'descriptor.mod'
    if (Test-Path -LiteralPath $descriptorPath) {
        $nameMatch = [regex]::Match([System.IO.File]::ReadAllText($descriptorPath), '(?m)^\s*name\s*=\s*"([^"]*)"')
        if ($nameMatch.Success) {
            return $nameMatch.Groups[1].Value
        }
    }
    return (Split-Path -Leaf $RepoRoot)
}

function Get-WikiRemoteUrl {
    param([Parameter(Mandatory = $true)][string]$RemoteUrl)

    $baseUrl = $RemoteUrl.Trim() -replace '\.git$', ''
    return ($baseUrl + '.wiki.git')
}

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $wikiSource = Join-Path $repoRoot 'wiki'
    $repoName = Split-Path -Leaf $repoRoot
    $wikiClone = Join-Path ([System.IO.Path]::GetTempPath()) ($repoName + '_wiki_push')

    Write-Host "=== $(Get-WikiModName -RepoRoot $repoRoot) Wiki Push Script ===" -ForegroundColor Cyan
    Write-Host "Source : $wikiSource"
    Write-Host "Temp   : $wikiClone"
    if ($DryRun) {
        Write-Host '[DRY RUN - no changes will be pushed]' -ForegroundColor Yellow
    }

    $originResult = Invoke-WikiGit -Arguments @('config', '--get', 'remote.origin.url') -WorkingDirectory $repoRoot
    if ($originResult.ExitCode -ne 0 -or -not $originResult.Text) {
        throw 'Git remote origin URL not found. Ensure the repository has an origin remote configured.'
    }
    $wikiRemote = Get-WikiRemoteUrl -RemoteUrl $originResult.Text

    if (Test-Path -LiteralPath (Join-Path $wikiClone '.git')) {
        Write-Host 'Updating existing wiki clone...' -ForegroundColor Yellow
        Assert-WikiGit -Arguments @('remote', 'set-url', 'origin', $wikiRemote) -WorkingDirectory $wikiClone | Out-Null
        Assert-WikiGit -Arguments @('fetch', 'origin') -WorkingDirectory $wikiClone | Out-Null
        $remoteHeadResult = Invoke-WikiGit -Arguments @('symbolic-ref', '--short', 'refs/remotes/origin/HEAD') -WorkingDirectory $wikiClone
        $wikiBranch = if ($remoteHeadResult.ExitCode -eq 0 -and $remoteHeadResult.Text) { $remoteHeadResult.Text.Trim() } else { $null }
        if (-not $wikiBranch) {
            $currentBranchResult = Assert-WikiGit -Arguments @('symbolic-ref', '--short', 'HEAD') -WorkingDirectory $wikiClone
            $wikiBranch = 'origin/' + $currentBranchResult.Text.Trim()
        }
        Assert-WikiGit -Arguments @('reset', '--hard', $wikiBranch) -WorkingDirectory $wikiClone | Out-Null
    } else {
        if (Test-Path -LiteralPath $wikiClone) {
            Remove-Item -LiteralPath $wikiClone -Recurse -Force
        }
        Write-Host 'Cloning wiki repository...' -ForegroundColor Yellow
        $cloneResult = Invoke-WikiGit -Arguments @('clone', $wikiRemote, $wikiClone)
        if ($cloneResult.ExitCode -ne 0) {
            if ($cloneResult.Text -match 'not found|does not exist|does not appear to be a git repository') {
                throw "The wiki does not exist yet: save a first page in the repository's Wiki tab on GitHub, then run this script again.`nWiki URL: $wikiRemote`n$($cloneResult.Text)"
            }
            throw "git clone $wikiRemote failed with exit code $($cloneResult.ExitCode):`n$($cloneResult.Text)"
        }
    }

    $markdownFiles = @(Get-ChildItem -LiteralPath $wikiSource -Filter '*.md' -File)
    if ($markdownFiles.Count -eq 0) {
        throw "No wiki pages found in $wikiSource."
    }
    foreach ($markdownFile in $markdownFiles) {
        Copy-Item -LiteralPath $markdownFile.FullName -Destination (Join-Path $wikiClone $markdownFile.Name) -Force
    }

    $statusResult = Assert-WikiGit -Arguments @('status', '--porcelain') -WorkingDirectory $wikiClone
    if (-not $statusResult.Text) {
        Write-Host 'Nothing to commit - wiki is already up to date.' -ForegroundColor Green
        exit 0
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] $(@($statusResult.Output).Count) changed page(s), completed without pushing:" -ForegroundColor Yellow
        $statusResult.Output | ForEach-Object { Write-Host "  $_" }
        exit 0
    }

    Assert-WikiGit -Arguments @('add', '-A') -WorkingDirectory $wikiClone | Out-Null
    Assert-WikiGit -Arguments @('commit', '-m', $CommitMessage) -WorkingDirectory $wikiClone | Out-Null
    Assert-WikiGit -Arguments @('push', 'origin', 'HEAD') -WorkingDirectory $wikiClone | Out-Null
    Write-Host 'Wiki pushed successfully!' -ForegroundColor Green
    exit 0
} catch {
    Write-Host "Wiki push failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
