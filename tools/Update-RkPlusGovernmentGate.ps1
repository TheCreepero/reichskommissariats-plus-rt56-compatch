[CmdletBinding()]
param(
    [Parameter()]
    [string]$ModRoot,

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not $ModRoot) {
    $ModRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..')).Path
}

$fascismGate = 'has_government = fascism'
$sharedGate = 'rkplus_ger_can_run_rks = yes'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

$wholeFileTargets = @(
    'common\decisions\reichskommissariat.txt',
    'common\decisions\rkplus_rt56_colonial_decisions.txt',
    'common\ai_strategy\GER_rkplus_ai_strategy.txt',
    'common\ai_strategy_plans\GER_rkplus_historical_plan.txt'
)

$blockTargets = @(
    @{ Path = 'common\decisions\categories\GER_decision_categories.txt'; BlockName = 'GER_reichskommissariats' }
)

function Write-IfChanged {
    param(
        [string]$Path,
        [string]$OriginalText,
        [string]$UpdatedText,
        [int]$ReplacementCount
    )

    if ($ReplacementCount -eq 0) {
        Write-Host ("unchanged {0}" -f $Path)
        return
    }
    if (-not $WhatIf) {
        [System.IO.File]::WriteAllText($Path, $UpdatedText, $utf8WithoutBom)
    }
    Write-Host ("{0} replacement(s) in {1}" -f $ReplacementCount, $Path)
}

foreach ($relativePath in $wholeFileTargets) {
    $path = Join-Path $ModRoot $relativePath
    $originalText = [System.IO.File]::ReadAllText($path, $utf8WithoutBom)
    $replacementCount = ([regex]::Matches($originalText, [regex]::Escape($fascismGate))).Count
    $updatedText = $originalText.Replace($fascismGate, $sharedGate)
    Write-IfChanged -Path $path -OriginalText $originalText -UpdatedText $updatedText -ReplacementCount $replacementCount
}

foreach ($target in $blockTargets) {
    $path = Join-Path $ModRoot $target.Path
    $originalText = [System.IO.File]::ReadAllText($path, $utf8WithoutBom)
    $blockPattern = '(?s)(^' + [regex]::Escape($target.BlockName) + ' = \{.*?\r?\n\})'
    $blockMatch = [regex]::Match($originalText, $blockPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $blockMatch.Success) {
        throw ("Block {0} not found in {1}" -f $target.BlockName, $path)
    }
    $replacementCount = ([regex]::Matches($blockMatch.Value, [regex]::Escape($fascismGate))).Count
    $updatedBlock = $blockMatch.Value.Replace($fascismGate, $sharedGate)
    $updatedText = $originalText.Remove($blockMatch.Index, $blockMatch.Length).Insert($blockMatch.Index, $updatedBlock)
    Write-IfChanged -Path $path -OriginalText $originalText -UpdatedText $updatedText -ReplacementCount $replacementCount
}
