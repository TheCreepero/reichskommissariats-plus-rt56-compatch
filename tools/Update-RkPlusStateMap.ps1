[CmdletBinding()]
param(
    [Parameter()]
    [string]$ModRoot,

    [Parameter()]
    [string]$ManagerRoot,

    [Parameter()]
    [string]$MapMod,

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not $ModRoot) {
    $ModRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
Import-Module (Join-Path $PSScriptRoot 'RkPlusStateReferences.psm1') -Force

if (-not $ManagerRoot) {
    $ManagerRoot = Resolve-RkPlusManagerRoot -ModRoot $ModRoot
}
if (-not $ManagerRoot) {
    throw 'The Hearts of Iron IV Modding Manager was not found; pass -ManagerRoot.'
}
if (-not $MapMod) {
    $MapMod = Get-RkPlusMapModName
}

$mapPath = Join-Path $PSScriptRoot 'RkPlusRt56StateMap.json'
$overridesPath = Join-Path $PSScriptRoot 'RkPlusRt56StateMapOverrides.json'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

$overrides = @{}
if (Test-Path -LiteralPath $overridesPath) {
    $overrideEntries = ([System.IO.File]::ReadAllText($overridesPath) | ConvertFrom-Json).overrides
    if ($overrideEntries -and $overrideEntries.PSObject.Properties['value'] -and -not ($overrideEntries -is [array])) {
        $overrideEntries = $overrideEntries.value
    }
    foreach ($entry in @($overrideEntries | Where-Object { $_ })) {
        $overrides[[int]$entry.id] = $entry
    }
}

$vanillaStates = Get-RkPlusStateTable -ManagerRoot $ManagerRoot
$mapStates = Get-RkPlusStateTable -ManagerRoot $ManagerRoot -Mod $MapMod
$mapOwnerOfProvince = Get-RkPlusProvinceOwners -StateTable $mapStates
$translation = Get-RkPlusProvinceTranslation -ManagerRoot $ManagerRoot -MapMod $MapMod
$footprints = Get-RkPlusVanillaFootprints -VanillaStates $vanillaStates -MapStates $mapStates -Translation $translation
Write-Host ("province ids that name another place on the map: {0} vanilla, {1} map; without a land province nearby: {2} vanilla, {3} map" -f $translation.MovedForward, $translation.MovedReverse, $translation.UnmatchedForward, $translation.UnmatchedReverse)

$victoryPointStateOf = @{}
foreach ($vanillaState in $vanillaStates.Values) {
    $topVictoryPoint = @($vanillaState.VictoryPoints.GetEnumerator() | Sort-Object { - $_.Value }, { $_.Key } | Select-Object -First 1)
    if ($topVictoryPoint.Count) {
        $victoryPointProvince = $translation.Forward[[int]$topVictoryPoint[0].Key]
        if ($null -ne $victoryPointProvince -and $mapOwnerOfProvince.ContainsKey($victoryPointProvince)) {
            $victoryPointStateOf[$vanillaState.Id] = $mapOwnerOfProvince[$victoryPointProvince]
        }
    }
}
$holdersOf = @{}
foreach ($vanillaId in $footprints.Keys) {
    foreach ($province in $footprints[$vanillaId]) {
        if ($mapOwnerOfProvince.ContainsKey($province)) {
            $mapId = $mapOwnerOfProvince[$province]
            if (-not $holdersOf.ContainsKey($mapId)) {
                $holdersOf[$mapId] = @{}
            }
            $holdersOf[$mapId][$vanillaId] = 1 + [int]$holdersOf[$mapId][$vanillaId]
        }
    }
}
$majorityVanillaStateOf = @{}
$claimedBy = @{}
foreach ($mapId in $holdersOf.Keys) {
    $holders = $holdersOf[$mapId]
    $size = $mapStates[$mapId].Provinces.Count
    $majority = @($holders.Keys | Where-Object { $holders[$_] / $size -ge 0.5 })
    if ($majority.Count) {
        $majorityVanillaStateOf[$mapId] = $majority[0]
        continue
    }
    $largest = ($holders.Values | Measure-Object -Maximum).Maximum
    $tied = @($holders.Keys | Where-Object { $holders[$_] -eq $largest } | Sort-Object)
    $withCity = @($tied | Where-Object { $victoryPointStateOf[$_] -eq $mapId })
    $claimedBy[$mapId] = if ($withCity.Count) { $withCity[0] } else { $tied[0] }
}

$lines = [System.Collections.Generic.List[string]]::new()
$kindCounts = @{}
foreach ($vanillaId in @($vanillaStates.Keys | Sort-Object)) {
    $vanillaState = $vanillaStates[$vanillaId]
    $footprint = $footprints[$vanillaId]
    $provinceCountByMapState = @{}
    foreach ($province in $footprint) {
        if ($mapOwnerOfProvince.ContainsKey($province)) {
            $mapId = $mapOwnerOfProvince[$province]
            $provinceCountByMapState[$mapId] = 1 + [int]$provinceCountByMapState[$mapId]
        }
    }
    $overrideReason = $null
    $victoryPointState = $null
    if ($overrides.ContainsKey($vanillaId)) {
        $targets = ConvertTo-RkPlusIntArray $overrides[$vanillaId].targets
        $overrideReason = [string]$overrides[$vanillaId].reason
        $kind = 'override'
    } else {
        if ($provinceCountByMapState.Count -eq 0) {
            throw "Vanilla state $vanillaId $($vanillaState.Name) has no land on the $MapMod map; add it to $overridesPath."
        }
        $mostlyThisState = @($provinceCountByMapState.Keys | Where-Object { $provinceCountByMapState[$_] / $mapStates[$_].Provinces.Count -ge 0.5 -or $claimedBy[$_] -eq $vanillaId } | Sort-Object)
        $victoryPointState = $victoryPointStateOf[$vanillaId]
        $largestShare = [int](@($provinceCountByMapState.GetEnumerator() | Sort-Object { - $_.Value }, { $_.Key } | Select-Object -First 1)[0].Key)
        if ($mostlyThisState.Count -eq 0) {
            $anchor = if ($null -ne $victoryPointState) { $victoryPointState } else { $largestShare }
            $targets = @($anchor)
            $kind = 'merged'
        } else {
            $anchor = if ($mostlyThisState -contains $victoryPointState) { $victoryPointState } else { [int](@($mostlyThisState | Sort-Object { - $provinceCountByMapState[$_] }, { $_ } | Select-Object -First 1)[0]) }
            $targets = @(@($anchor) + @($mostlyThisState | Where-Object { $_ -ne $anchor }))
            $kind = if ($targets.Count -gt 1) {
                'split'
            } elseif ($anchor -ne $vanillaId) {
                'renumbered'
            } elseif ($mapStates[$anchor].Provinces.Count -eq $footprint.Count -and $provinceCountByMapState[$anchor] -eq $footprint.Count) {
                'same'
            } else {
                'reshaped'
            }
        }
    }

    $covered = 0
    foreach ($province in $footprint) {
        if ($mapOwnerOfProvince.ContainsKey($province) -and $targets -contains $mapOwnerOfProvince[$province]) {
            $covered++
        }
    }
    $kindCounts[$kind] = 1 + [int]$kindCounts[$kind]

    $entry = [ordered]@{
        id       = $vanillaId
        name     = $vanillaState.Name
        kind     = $kind
        targets  = $targets
        names    = @($targets | ForEach-Object { $mapStates[$_].Name })
        coverage = if ($footprint.Count) { [Math]::Round($covered / $footprint.Count, 2) } else { 1 }
        drift    = $footprint.Count - $covered
    }
    $capital = $targets[0]
    if ($null -ne $victoryPointState -and $victoryPointState -ne $capital -and (-not $majorityVanillaStateOf.ContainsKey($victoryPointState) -or $majorityVanillaStateOf[$victoryPointState] -eq $vanillaId)) {
        $capital = $victoryPointState
    }
    if ($capital -ne $targets[0]) {
        $entry['capital'] = $capital
        $entry['capitalName'] = $mapStates[$capital].Name
    }
    if ($targets.Count -gt 1) {
        $entry['provinces'] = @($targets | ForEach-Object { , @($mapStates[$_].Provinces | Sort-Object) })
    }
    if ($overrideReason) {
        $entry['reason'] = $overrideReason
    }
    $lines.Add((ConvertTo-Json -InputObject $entry -Compress -Depth 4))
}

$movedProvinces = [ordered]@{}
foreach ($province in @($translation.Forward.Keys | Sort-Object)) {
    $mapProvince = $translation.Forward[$province]
    if ($null -ne $mapProvince -and $mapProvince -ne $province) {
        $movedProvinces["$province"] = $mapProvince
    }
}

$header = [ordered]@{
    vanillaStates = $vanillaStates.Count
    mapMod        = $MapMod
    mapStates     = $mapStates.Count
    rule          = 'a province is the same on both maps when its centroid moved at most 8 px, otherwise it is the nearest land centroid on the other map; the targets are the map states with at least half of their provinces from the vanilla state, and each map state that no vanilla state holds half of goes to the vanilla state with the largest part of it (on a tie, the one whose largest victory point lies there); the one holding its largest victory point comes first; when there is none, the map state holding that victory point; capital is the map state holding that victory point for single-valued references (capital, set_capital) when no other vanilla state holds half of it; overrides come from RkPlusRt56StateMapOverrides.json'
}
$document = '{' + "`n" + '"source": ' + (ConvertTo-Json -InputObject $header -Compress) + ",`n" + '"movedProvinces": ' + (ConvertTo-Json -InputObject $movedProvinces -Compress) + ",`n" + '"states": [' + "`n" + ($lines -join ",`n") + "`n]`n}`n"

foreach ($kindName in @($kindCounts.Keys | Sort-Object)) {
    Write-Host ("{0,-11} {1}" -f $kindName, $kindCounts[$kindName])
}
Write-Host ("{0} province id(s) translated" -f $movedProvinces.Count)
if ($WhatIf) {
    Write-Host ("would write {0} state(s) to {1}" -f $lines.Count, $mapPath)
    return
}
[System.IO.File]::WriteAllText($mapPath, $document, $utf8WithoutBom)
Write-Host ("wrote {0} state(s) to {1}" -f $lines.Count, $mapPath)
