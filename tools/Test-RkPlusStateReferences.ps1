[CmdletBinding()]
param(
    [Parameter()]
    [string]$ModRoot,

    [Parameter()]
    [string]$ManagerRoot,

    [Parameter()]
    [string]$RkPlusRoot,

    [Parameter()]
    [string]$MapMod,

    [Parameter()]
    [switch]$Detail,

    [Parameter()]
    [switch]$PassThru
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
if (-not $RkPlusRoot) {
    $RkPlusRoot = Resolve-RkPlusFrozenRoot -ManagerRoot $ManagerRoot
}
if (-not $RkPlusRoot) {
    throw 'Reichskommissariats Plus was not found; pass -RkPlusRoot.'
}
if (-not $MapMod) {
    $MapMod = Get-RkPlusMapModName
}

$exclusions = Get-RkPlusAuditExclusions
$vanillaStateCount = Get-RkPlusVanillaStateCount
$vanillaStates = Get-RkPlusStateTable -ManagerRoot $ManagerRoot
$mapStates = Get-RkPlusStateTable -ManagerRoot $ManagerRoot -Mod $MapMod
$vanillaOwnerOfProvince = Get-RkPlusProvinceOwners -StateTable $vanillaStates
$mapOwnerOfProvince = Get-RkPlusProvinceOwners -StateTable $mapStates
$translation = Get-RkPlusProvinceTranslation -ManagerRoot $ManagerRoot -MapMod $MapMod
$footprints = Get-RkPlusVanillaFootprints -VanillaStates $vanillaStates -MapStates $mapStates -Translation $translation
$overridesPath = Join-Path $PSScriptRoot 'RkPlusRt56StateMapOverrides.json'
if (Test-Path -LiteralPath $overridesPath) {
    $overrideEntries = ([System.IO.File]::ReadAllText($overridesPath) | ConvertFrom-Json).overrides
    if ($overrideEntries -and $overrideEntries.PSObject.Properties['value'] -and -not ($overrideEntries -is [array])) {
        $overrideEntries = $overrideEntries.value
    }
    foreach ($override in @($overrideEntries | Where-Object { $_ })) {
        foreach ($targetId in (ConvertTo-RkPlusIntArray $override.targets)) {
            foreach ($province in $mapStates[$targetId].Provinces) {
                [void]$footprints[[int]$override.id].Add($province)
            }
        }
    }
}

$partsByVanillaState = @{}
$holdersByMapState = @{}
foreach ($vanillaId in $footprints.Keys) {
    $parts = @{}
    foreach ($province in $footprints[$vanillaId]) {
        if ($mapOwnerOfProvince.ContainsKey($province)) {
            $mapId = $mapOwnerOfProvince[$province]
            $parts[$mapId] = 1 + [int]$parts[$mapId]
            if (-not $holdersByMapState.ContainsKey($mapId)) {
                $holdersByMapState[$mapId] = @{}
            }
            $holdersByMapState[$mapId][$vanillaId] = 1 + [int]$holdersByMapState[$mapId][$vanillaId]
        }
    }
    $partsByVanillaState[$vanillaId] = $parts
}

function Test-ClosestState {
    param([int]$MapId, [System.Collections.Generic.HashSet[int]]$OriginalStateIds)

    foreach ($vanillaId in $OriginalStateIds) {
        if ($vanillaId -gt $vanillaStateCount -or -not $partsByVanillaState.ContainsKey($vanillaId)) {
            continue
        }
        $parts = $partsByVanillaState[$vanillaId]
        $hasOwnState = @($parts.Keys | Where-Object { $parts[$_] / $mapStates[$_].Provinces.Count -ge 0.5 }).Count -gt 0
        if (-not $hasOwnState -and $parts.ContainsKey($MapId) -and $parts[$MapId] -eq ($parts.Values | Measure-Object -Maximum).Maximum) {
            return $true
        }
        $holders = $holdersByMapState[$MapId]
        if ($holders -and $holders.ContainsKey($vanillaId) -and $holders[$vanillaId] -eq ($holders.Values | Measure-Object -Maximum).Maximum) {
            return $true
        }
    }
    return $false
}

function Get-IntentProvinces {
    param([int]$StateId)

    if ($StateId -le $vanillaStateCount -and $footprints.ContainsKey($StateId)) {
        return $footprints[$StateId]
    }
    if ($StateId -gt $vanillaStateCount -and $mapStates.ContainsKey($StateId)) {
        return $mapStates[$StateId].Provinces
    }
    return @()
}

function Get-StateLabel {
    param([int]$StateId, [switch]$Intended)

    if ($Intended -and $StateId -le $vanillaStateCount -and $vanillaStates.ContainsKey($StateId)) {
        return "$StateId $($vanillaStates[$StateId].Name)"
    }
    if ($mapStates.ContainsKey($StateId)) {
        return "$StateId $($mapStates[$StateId].Name) ($($mapStates[$StateId].Owner))"
    }
    return "$StateId (no such state)"
}

function Get-ScopeState {
    param($Frame, [System.Collections.Generic.HashSet[object]]$ScopeFrames)

    $walker = $Frame
    while ($walker -and $walker.Depth -ge 0) {
        if ($ScopeFrames.Contains($walker)) {
            return [int]$walker.Key
        }
        $walker = $walker.Parent
    }
    return $null
}

function Get-Section {
    param([hashtable]$Sections, $Location)

    $sectionKey = "$($Location.Definition)|$($Location.Section)"
    if (-not $Sections.ContainsKey($sectionKey)) {
        $Sections[$sectionKey] = [pscustomobject]@{
            Definition        = $Location.Definition
            Section           = $Location.Section
            Original          = [System.Collections.Generic.HashSet[int]]::new()
            Current           = [System.Collections.Generic.HashSet[int]]::new()
            SingleOriginal    = [System.Collections.Generic.HashSet[int]]::new()
            SingleCurrent     = [System.Collections.Generic.HashSet[int]]::new()
            OriginalProvinces = [System.Collections.Generic.List[object]]::new()
            CurrentProvinces  = [System.Collections.Generic.List[object]]::new()
        }
    }
    $Sections[$sectionKey]
}

function Add-SectionReferences {
    param([hashtable]$Sections, [string]$Text, [string]$RelativePath, [string]$Side)

    $parsed = Get-RkPlusStateReferences -Text $Text -MaxStateId $mapStates.Count
    $scopeFrames = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($reference in $parsed.References) {
        if ($reference.Kind -eq 'Scope') {
            [void]$scopeFrames.Add($reference.Frame)
        }
    }
    foreach ($reference in $parsed.References) {
        $section = Get-Section -Sections $Sections -Location (Get-RkPlusDefinitionKey -Frame $reference.Parent -RelativePath $RelativePath -FallbackSection $reference.Key)
        $runsOnce = (Test-RkPlusSingleValuedReference -Reference $reference) -or ($reference.Kind -eq 'Scope' -and -not (Test-RkPlusRepeatableBody -Text $Text -Frame $reference.Frame))
        $setName = if ($runsOnce) { "Single$Side" } else { $Side }
        [void]$section.$setName.Add($reference.Id)
    }
    foreach ($province in $parsed.Provinces) {
        $section = Get-Section -Sections $Sections -Location (Get-RkPlusDefinitionKey -Frame $province.Parent -RelativePath $RelativePath -FallbackSection $province.Key)
        $section."$($Side)Provinces".Add([pscustomobject]@{ Id = $province.Id; Scope = (Get-ScopeState -Frame $province.Parent -ScopeFrames $scopeFrames) })
    }
    $parsed.Unclassified
}

function New-ProvinceSet {
    param([System.Collections.Generic.HashSet[int]]$StateIds)

    $provinces = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($stateId in $StateIds) {
        foreach ($province in (Get-IntentProvinces -StateId $stateId)) {
            [void]$provinces.Add($province)
        }
    }
    , $provinces
}

function Measure-Section {
    param($Section)

    $foreign = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    $wrongProvinces = [System.Collections.Generic.List[string]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()

    $intent = New-ProvinceSet -StateIds $Section.Original
    $named = [System.Collections.Generic.HashSet[int]]::new()
    $covered = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($stateId in $Section.Current) {
        if (-not $mapStates.ContainsKey($stateId)) {
            $foreign.Add((Get-StateLabel -StateId $stateId))
            continue
        }
        [void]$named.Add($stateId)
        $inside = 0
        foreach ($province in $mapStates[$stateId].Provinces) {
            if ($intent.Contains($province)) {
                $inside++
                [void]$covered.Add($province)
            }
        }
        if ($inside / $mapStates[$stateId].Provinces.Count -lt 0.5) {
            $label = "$(Get-StateLabel -StateId $stateId), $inside of $($mapStates[$stateId].Provinces.Count) province(s) intended"
            if ($inside -gt 0 -and (Test-ClosestState -MapId $stateId -OriginalStateIds $Section.Original)) {
                $notes.Add("names mostly other land, the closest the map has: $label")
            } else {
                $foreign.Add($label)
            }
        }
    }
    $insideByUnnamedState = @{}
    foreach ($province in $intent) {
        if ($mapOwnerOfProvince.ContainsKey($province)) {
            $stateId = $mapOwnerOfProvince[$province]
            if (-not $named.Contains($stateId)) {
                $insideByUnnamedState[$stateId] = 1 + [int]$insideByUnnamedState[$stateId]
            }
        }
    }
    foreach ($stateId in @($insideByUnnamedState.Keys | Sort-Object)) {
        $inside = $insideByUnnamedState[$stateId]
        if ($inside / $mapStates[$stateId].Provinces.Count -ge 0.5) {
            $missing.Add((Get-StateLabel -StateId $stateId))
        } else {
            $notes.Add("leaves $inside province(s) in $(Get-StateLabel -StateId $stateId)")
        }
    }

    $singleIntent = New-ProvinceSet -StateIds $Section.SingleOriginal
    foreach ($stateId in $Section.SingleCurrent) {
        if (-not $mapStates.ContainsKey($stateId) -or -not @($mapStates[$stateId].Provinces | Where-Object { $singleIntent.Contains($_) }).Count) {
            $foreign.Add("$(Get-StateLabel -StateId $stateId) instead of $(@($Section.SingleOriginal | ForEach-Object { Get-StateLabel -StateId $_ -Intended }) -join ', ')")
        }
    }

    $expectedProvinces = @($Section.OriginalProvinces | ForEach-Object { if ($null -ne $translation.Forward[$_.Id]) { $translation.Forward[$_.Id] } else { $_.Id } } | Sort-Object -Unique)
    $currentProvinces = @($Section.CurrentProvinces | ForEach-Object Id | Sort-Object -Unique)
    if (($expectedProvinces -join ',') -ne ($currentProvinces -join ',')) {
        $wrongProvinces.Add("province ids $($currentProvinces -join ',') where the map has $($expectedProvinces -join ',')")
    }
    foreach ($province in $Section.CurrentProvinces) {
        if ($null -eq $province.Scope -or $mapOwnerOfProvince[$province.Id] -eq $province.Scope) {
            continue
        }
        $wasInside = @($Section.OriginalProvinces | Where-Object { $translation.Forward[$_.Id] -eq $province.Id -and $null -ne $_.Scope -and $vanillaOwnerOfProvince[$_.Id] -eq $_.Scope }).Count
        $message = "province $($province.Id) lies in $(Get-StateLabel -StateId $mapOwnerOfProvince[$province.Id]), not in its scope $(Get-StateLabel -StateId $province.Scope)"
        if ($wasInside) {
            $wrongProvinces.Add($message)
        } else {
            $notes.Add("$message, as on the game's map")
        }
    }

    $coverage = if ($intent.Count -gt 0) { $covered.Count / $intent.Count } else { 1.0 }
    $hasOriginal = $Section.Original.Count -gt 0 -or $Section.SingleOriginal.Count -gt 0 -or $Section.OriginalProvinces.Count -gt 0
    $verdict = if (-not $hasOriginal) {
        'NEW'
    } elseif ($foreign.Count -gt 0 -or $missing.Count -gt 0 -or $wrongProvinces.Count -gt 0) {
        'WRONG'
    } elseif ($notes.Count -gt 0) {
        'NOTE'
    } else {
        'OK'
    }
    [pscustomobject]@{
        Verdict   = $verdict
        Coverage  = [Math]::Round($coverage, 3)
        Foreign   = $foreign.ToArray()
        Missing   = $missing.ToArray()
        Provinces = $wrongProvinces.ToArray()
        Notes     = $notes.ToArray()
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$unclassifiedRows = [System.Collections.Generic.List[object]]::new()
$auditedFileCount = 0

foreach ($folder in (Get-RkPlusAuditedFolders)) {
    $rkPlusFolder = Join-Path $RkPlusRoot $folder
    if (-not (Test-Path -LiteralPath $rkPlusFolder)) {
        continue
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $rkPlusFolder -Filter '*.txt' -File -Recurse | Sort-Object FullName)) {
        $relativePath = $file.FullName.Substring($RkPlusRoot.TrimEnd('\').Length + 1)
        if ($exclusions.ContainsKey($relativePath)) {
            Write-Verbose ("skipped {0}: {1}" -f $relativePath, $exclusions[$relativePath])
            continue
        }
        $originalText = [System.IO.File]::ReadAllText($file.FullName)
        $compatchPath = Join-Path $ModRoot $relativePath
        $loadedFrom = if (Test-Path -LiteralPath $compatchPath) { 'compatch' } else { 'RK+' }
        $currentText = if ($loadedFrom -eq 'compatch') { [System.IO.File]::ReadAllText($compatchPath) } else { $originalText }

        $sections = @{}
        [void](Add-SectionReferences -Sections $sections -Text $originalText -RelativePath $relativePath -Side 'Original')
        if ($sections.Count -eq 0) {
            continue
        }
        $auditedFileCount++
        foreach ($row in @(Add-SectionReferences -Sections $sections -Text $currentText -RelativePath $relativePath -Side 'Current')) {
            $unclassifiedRows.Add([pscustomobject]@{ File = $relativePath; Key = $row.Key; Id = $row.Id; Parent = $row.Parent })
        }

        foreach ($section in $sections.Values) {
            $measure = Measure-Section -Section $section
            $results.Add([pscustomobject]@{
                File       = $relativePath
                LoadedFrom = $loadedFrom
                Definition = $section.Definition
                Section    = $section.Section
                Verdict    = $measure.Verdict
                Coverage   = $measure.Coverage
                Foreign    = $measure.Foreign
                Missing    = $measure.Missing
                Provinces  = $measure.Provinces
                Notes      = $measure.Notes
            })
        }
    }
}

if ($PassThru) {
    return $results.ToArray()
}

$wrongRows = @($results | Where-Object Verdict -eq 'WRONG')
$noteRows = @($results | Where-Object Verdict -eq 'NOTE')
foreach ($row in $wrongRows) {
    Write-Host ("WRONG  {0} [{1}]  {2} / {3}: {4:P0} of the intended land" -f $row.File, $row.LoadedFrom, $row.Definition, $row.Section, $row.Coverage)
    if ($row.Foreign.Count) {
        Write-Host ("         names land that is mostly not its own: {0}" -f ($row.Foreign -join '; '))
    }
    if ($row.Missing.Count) {
        Write-Host ("         leaves out states that are mostly its land: {0}" -f ($row.Missing -join '; '))
    }
    foreach ($line in $row.Provinces) {
        Write-Host ("         {0}" -f $line)
    }
}
if ($Detail) {
    foreach ($row in $noteRows) {
        Write-Host ("NOTE   {0}  {1} / {2}: {3:P0}; {4}" -f $row.File, $row.Definition, $row.Section, $row.Coverage, ($row.Notes -join '; '))
    }
    foreach ($group in @($unclassifiedRows | Group-Object File, Key)) {
        Write-Host ("UNREAD {0}: {1} number(s) that may be state ids" -f $group.Name, $group.Count)
    }
}
Write-Host ("Audited {0} RK+ file(s), {1} section(s) on the {2} map: {3} WRONG, {4} NOTE, {5} OK, {6} NEW; {7} unread number(s) under keys naming a state." -f $auditedFileCount, $results.Count, $MapMod, $wrongRows.Count, $noteRows.Count, @($results | Where-Object Verdict -eq 'OK').Count, @($results | Where-Object Verdict -eq 'NEW').Count, $unclassifiedRows.Count)
if ($wrongRows.Count -gt 0) {
    exit 1
}
exit 0
