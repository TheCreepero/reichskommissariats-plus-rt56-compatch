BeforeDiscovery {
    $discoveryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $discoveryRoot 'tools\RkPlusStateReferences.psm1') -Force
    $auditSkipReason = $null
    $discoveryManagerRoot = Resolve-RkPlusManagerRoot -ModRoot $discoveryRoot
    if (-not $discoveryManagerRoot) {
        $auditSkipReason = 'the Hearts of Iron IV Modding Manager is not installed'
    } else {
        try {
            if (-not (Resolve-RkPlusFrozenRoot -ManagerRoot $discoveryManagerRoot)) {
                $auditSkipReason = 'Reichskommissariats Plus is not installed'
            } elseif (-not @(& (Join-Path $discoveryManagerRoot 'Scripts\Vanilla\Get-HoiMod.ps1') -Name (Get-RkPlusMapModName) -PassThru).Count) {
                $auditSkipReason = "$(Get-RkPlusMapModName) is not installed"
            }
        } catch {
            $auditSkipReason = "the game or its mods cannot be read: $($_.Exception.Message)"
        }
    }
    $script:CanAudit = -not $auditSkipReason
    if ($auditSkipReason) {
        Write-Host "The land audit is skipped: $auditSkipReason."
    }
}

BeforeAll {
    $script:CompatchRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:CompatchRoot 'tools\RkPlusStateReferences.psm1') -Force
    $script:SourceRoot = Join-Path $script:CompatchRoot (Get-RkPlusSourceFolderName)
    $script:Targets = Get-RkPlusStateFileTargets -ModRoot $script:CompatchRoot
    $script:StateMap = Read-RkPlusStateMap -Path (Join-Path $script:CompatchRoot 'tools\RkPlusRt56StateMap.json')
    $script:OnceOnlyEffects = 'create_unit|add_building_construction|add_resource|add_extra_state_shared_building_slots|set_victory_points|add_victory_points|remove_building|set_province_name'
    $script:Generated = @{}
    foreach ($relativePath in $script:Targets) {
        $sourceText = [System.IO.File]::ReadAllText((Join-Path $script:SourceRoot $relativePath))
        $newLine = if ($sourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $script:Generated[$relativePath] = [pscustomobject]@{
            Source   = $sourceText
            Expected = (Get-RkPlusGeneratedMarker -RelativePath $relativePath) + $newLine + (Convert-RkPlusStateText -Text $sourceText -StateMap $script:StateMap).Text
            Actual   = [System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot $relativePath))
        }
    }
}

Describe 'Road to 56 state ids in the RK+ copies' {
    It 'Ships every target exactly as tools/Update-RkPlusStateIds.ps1 generates it from rkplus-source' {
        foreach ($relativePath in $script:Targets) {
            ($script:Generated[$relativePath].Actual -ceq $script:Generated[$relativePath].Expected) | Should -BeTrue -Because "$relativePath must be regenerated from rkplus-source, not edited"
        }
    }

    It 'Ships a country history file only where rkplus-source has one' {
        $sources = @(Get-ChildItem -LiteralPath (Join-Path $script:SourceRoot 'history\countries') -Filter '*.txt' -File | ForEach-Object Name | Sort-Object)
        $shipped = @(Get-ChildItem -LiteralPath (Join-Path $script:CompatchRoot 'history\countries') -Filter '*.txt' -File | ForEach-Object Name | Sort-Object)
        ($shipped -join '|') | Should -Be ($sources -join '|')
    }

    It 'Runs every effect that adds units, buildings, resources or victory points as often as the source does' {
        foreach ($relativePath in $script:Targets) {
            $sourceCount = ([regex]::Matches($script:Generated[$relativePath].Source, "(?m)^[^#\r\n]*\b($script:OnceOnlyEffects)\s*=")).Count
            $shippedCount = ([regex]::Matches($script:Generated[$relativePath].Actual, "(?m)^[^#\r\n]*\b($script:OnceOnlyEffects)\s*=")).Count
            $shippedCount | Should -Be $sourceCount -Because "$relativePath must not repeat a one-time effect for each piece of a split state"
        }
    }

    It 'Names only states that exist on the Road to 56 map and leaves no number that may be a state unread' {
        $maxStateId = $script:StateMap.MapStateCount
        $maxStateId | Should -BeGreaterThan (Get-RkPlusVanillaStateCount)
        foreach ($relativePath in $script:Targets) {
            $parsed = Get-RkPlusStateReferences -Text $script:Generated[$relativePath].Actual -MaxStateId $maxStateId
            @($parsed.References | Where-Object { $_.Id -lt 1 -or $_.Id -gt $maxStateId } | ForEach-Object Id) | Should -BeNullOrEmpty -Because "$relativePath names states the map does not have"
            @($parsed.Unclassified | ForEach-Object { "$($_.Key) = $($_.Id)" }) | Should -BeNullOrEmpty -Because "$relativePath has a key the converter does not read"
        }
    }

    It 'Maps every vanilla state to at least one Road to 56 state' {
        foreach ($vanillaId in 1..(Get-RkPlusVanillaStateCount)) {
            $script:StateMap.Targets.ContainsKey($vanillaId) | Should -BeTrue -Because "vanilla state $vanillaId needs an entry"
            $script:StateMap.Targets[$vanillaId].Count | Should -BeGreaterThan 0
            @($script:StateMap.Targets[$vanillaId] | Where-Object { $_ -lt 1 -or $_ -gt $script:StateMap.MapStateCount }) | Should -BeNullOrEmpty
        }
    }

    It 'Gives every hand-kept override a reason' {
        $overrides = ([System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot 'tools\RkPlusRt56StateMapOverrides.json')) | ConvertFrom-Json).overrides
        foreach ($override in @($overrides | Where-Object { $_ })) {
            [string]$override.reason | Should -Not -BeNullOrEmpty -Because "override of state $($override.id) needs a reason"
        }
    }

    It 'Asks Reichskommissariat Norwegen for the ten Norwegian states of the Road to 56 map' {
        $relativePath = 'common\decisions\reichskommissariat.txt'
        $parsed = Get-RkPlusStateReferences -Text $script:Generated[$relativePath].Actual
        foreach ($section in 'available', 'highlight_states', 'complete_effect') {
            $stateIds = @($parsed.References | Where-Object {
                    $location = Get-RkPlusDefinitionKey -Frame $_.Parent -RelativePath $relativePath
                    $location.Definition -eq 'GER_reichskommissariat_norway' -and $location.Section -eq $section
                } | ForEach-Object Id | Sort-Object -Unique)
            ($stateIds -join ',') | Should -Be '110,142,143,144,967,1031,1032,1033,1034,1035' -Because "the $section of Norwegen must name Road to 56's Norway"
        }
    }
}

Describe 'Land audit against the frozen RK+ on the Road to 56 map' {
    It 'Finds no decision, event, focus, capital or province id that names the wrong land' -Skip:(-not $script:CanAudit) {
        $rows = & (Join-Path $script:CompatchRoot 'tools\Test-RkPlusStateReferences.ps1') -ModRoot $script:CompatchRoot -PassThru
        $wrong = @($rows | Where-Object Verdict -eq 'WRONG' | ForEach-Object { "$($_.File) $($_.Definition) / $($_.Section): $(@($_.Foreign) + @($_.Missing) + @($_.Provinces) -join '; ')" })
        $wrong | Should -BeNullOrEmpty -Because 'tools/Test-RkPlusStateReferences.ps1 lists what is wrong'
        $rows.Count | Should -BeGreaterThan 1000
    }
}
