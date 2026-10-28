[CmdletBinding()]
param(
    [Parameter()]
    [string]$ModRoot,

    [Parameter()]
    [switch]$Detail,

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not $ModRoot) {
    $ModRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..')).Path
}
Import-Module (Join-Path $PSScriptRoot 'RkPlusStateReferences.psm1') -Force

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$sourceRoot = Join-Path $ModRoot (Get-RkPlusSourceFolderName)
$stateMap = Read-RkPlusStateMap -Path (Join-Path $PSScriptRoot 'RkPlusRt56StateMap.json')

$pending = [System.Collections.Generic.List[object]]::new()
$stopLines = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in (Get-RkPlusStateFileTargets -ModRoot $ModRoot)) {
    $sourcePath = Join-Path $sourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw ("Source {0} is missing: copy the frozen Reichskommissariats Plus file to {1} first." -f $relativePath, $sourcePath)
    }
    $sourceText = [System.IO.File]::ReadAllText($sourcePath, $strictUtf8)
    if ($sourceText.Length -gt 0 -and $sourceText[0] -eq [char]0xFEFF) {
        $sourceText = $sourceText.Substring(1)
    }
    $conversion = Convert-RkPlusStateText -Text $sourceText -StateMap $stateMap
    foreach ($stop in $conversion.Stops) {
        $stopLines.Add(("{0}:{1}: {2}" -f $relativePath, (Get-RkPlusLineNumber -Text $sourceText -Index $stop.Index), $stop.Reason))
    }
    foreach ($unread in $conversion.Unclassified) {
        Write-Warning ("{0}:{1}: '{2} = {3}' may name a state and is not converted" -f $relativePath, (Get-RkPlusLineNumber -Text $sourceText -Index $unread.Index), $unread.Key, $unread.Id)
    }
    if ($Detail) {
        foreach ($note in $conversion.OnePiece) {
            Write-Host ("{0}:{1}: the block of state {2} runs once, in {3} of {4}" -f $relativePath, (Get-RkPlusLineNumber -Text $sourceText -Index $note.Index), $note.StateId, $note.Chosen, ($note.Targets -join ', '))
        }
    }
    $newLine = if ($sourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $outputPath = Join-Path $ModRoot $relativePath
    $outputText = (Get-RkPlusGeneratedMarker -RelativePath $relativePath) + $newLine + $conversion.Text
    $currentText = if (Test-Path -LiteralPath $outputPath) { [System.IO.File]::ReadAllText($outputPath, $utf8WithoutBom) } else { $null }
    $pending.Add([pscustomobject]@{
        RelativePath = $relativePath
        Path         = $outputPath
        Text         = $outputText
        Changed      = ($currentText -cne $outputText)
        Count        = $conversion.ChangedReferenceCount
        OnePiece     = $conversion.OnePiece.Count
    })
}

if ($stopLines.Count -gt 0) {
    foreach ($line in $stopLines) {
        Write-Host $line
    }
    throw ("{0} reference(s) have no conversion rule; nothing was written." -f $stopLines.Count)
}

foreach ($item in $pending) {
    $status = if (-not $item.Changed) { 'up to date' } elseif ($WhatIf) { 'would write' } else { 'wrote' }
    if ($item.Changed -and -not $WhatIf) {
        $folder = Split-Path -Parent $item.Path
        if (-not (Test-Path -LiteralPath $folder)) {
            [void](New-Item -ItemType Directory -Path $folder)
        }
        [System.IO.File]::WriteAllText($item.Path, $item.Text, $utf8WithoutBom)
    }
    Write-Host ("{0,-11} {1}: {2} reference(s) converted, {3} block(s) kept in one piece" -f $status, $item.RelativePath, $item.Count, $item.OnePiece)
}
