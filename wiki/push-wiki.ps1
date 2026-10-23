param(
    [string]$CommitMessage = "Update wiki from source",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WikiSource = Join-Path $RepoRoot "wiki"
$WikiClone = Join-Path ([System.IO.Path]::GetTempPath()) "reichskommissariats-plus-rt56-compatch_wiki_push"

Write-Host "=== Reichskommissariats Plus - RT56 Compatch Wiki Push Script ===" -ForegroundColor Cyan
Write-Host "Source : $WikiSource"
Write-Host "Temp   : $WikiClone"
if ($DryRun) { Write-Host "[DRY RUN - no changes will be pushed]" -ForegroundColor Yellow }

$remoteUrl = git -C $RepoRoot config --get remote.origin.url
if (-not $remoteUrl) {
    Write-Error "Git remote origin URL not found. Ensure the repository has an origin remote configured."
    exit 1
}

$wikiRemote = $remoteUrl -replace '\.git$', '.wiki.git'
if ($wikiRemote -notmatch '\.wiki\.git$') {
    $wikiRemote += ".wiki.git"
}

if (Test-Path -LiteralPath $WikiClone) {
    Write-Host "Updating existing wiki clone..." -ForegroundColor Yellow
    git -C $WikiClone fetch origin
    git -C $WikiClone reset --hard origin/master 2>$null
    if ($LASTEXITCODE -ne 0) {
        git -C $WikiClone reset --hard origin/main 2>$null
    }
} else {
    Write-Host "Cloning wiki repository..." -ForegroundColor Yellow
    git clone $wikiRemote $WikiClone
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone wiki. Ensure the wiki tab is initialized on GitHub."
        exit 1
    }
}

$mdFiles = Get-ChildItem -Path $WikiSource -Filter "*.md"
foreach ($f in $mdFiles) {
    $dest = Join-Path $WikiClone $f.Name
    if (-not $DryRun) {
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
}

$status = git -C $WikiClone status --porcelain
if (-not $status) {
    Write-Host "Nothing to commit - wiki is already up to date." -ForegroundColor Green
    exit 0
}

if (-not $DryRun) {
    git -C $WikiClone add -A
    git -C $WikiClone commit -m $CommitMessage
    git -C $WikiClone push origin HEAD
    Write-Host "Wiki pushed successfully!" -ForegroundColor Green
} else {
    Write-Host "[DRY RUN] Completed without pushing." -ForegroundColor Yellow
}