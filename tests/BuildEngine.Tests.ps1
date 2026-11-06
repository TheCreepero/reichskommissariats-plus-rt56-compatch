BeforeAll {
    $engineCandidatePaths = @((Join-Path $PSScriptRoot '..\tools\HoiModBuild.ps1'), (Join-Path $PSScriptRoot 'HoiModBuild.ps1'))
    $script:EnginePath = @($engineCandidatePaths | Where-Object { Test-Path -LiteralPath $_ })[0]
    . $script:EnginePath

    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $script:BuildScriptPath = Join-Path $script:RepoRoot 'build.ps1'
    $script:IsModRepo = (Test-Path -LiteralPath $script:BuildScriptPath) -and ((Test-Path -LiteralPath (Join-Path $script:RepoRoot 'descriptor.mod')) -or @((Get-ModBuildConfig -RepoDir $script:RepoRoot).PackageNames).Count -gt 0)
    $script:PowerShellExe = (Get-Process -Id $PID).Path
    $script:TempRoots = [System.Collections.Generic.List[string]]::new()

    function New-TestDirectory {
        $testDirectory = New-ModTempDirectory -Prefix 'hoi4_engine_test'
        $script:TempRoots.Add($testDirectory)
        return $testDirectory
    }

    function Write-TestFile {
        param(
            [string]$Root,
            [string]$RelativePath,
            [string]$Text = 'x',
            [switch]$Bom
        )

        $fullPath = Join-Path $Root $RelativePath
        $parentPath = Split-Path -Parent $fullPath
        if (-not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($fullPath, $Text, [System.Text.UTF8Encoding]::new([bool]$Bom))
    }

    function New-FixtureRepo {
        $fixtureRoot = New-TestDirectory
        Write-TestFile -Root $fixtureRoot -RelativePath 'descriptor.mod' -Text ("version=`"1.0`"`r`nname=`"Fixture Mod`"`r`nsupported_version=`"1.19.*`"`r`n")
        [System.IO.File]::WriteAllBytes((Join-Path $fixtureRoot 'thumbnail.png'), [byte[]](137, 80, 78, 71))
        Write-TestFile -Root $fixtureRoot -RelativePath 'common\units\names\fixture_names.txt' -Text "FIX = {`r`n    name = `"Squadron #1`"`r`n}`r`n"
        Write-TestFile -Root $fixtureRoot -RelativePath 'common\.gitkeep' -Text ''
        Write-TestFile -Root $fixtureRoot -RelativePath 'localisation\english\fixture_l_english.yml' -Text "l_english:`r`n FIXTURE_KEY:0 `"Text`"`r`n" -Bom
        Write-TestFile -Root $fixtureRoot -RelativePath 'README.md' -Text '# Fixture'
        Write-TestFile -Root $fixtureRoot -RelativePath 'AGENTS.md' -Text '# Rules'
        Write-TestFile -Root $fixtureRoot -RelativePath 'CLAUDE.md' -Text '@AGENTS.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'GEMINI.md' -Text '@AGENTS.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'fixture.mod' -Text 'path="C:/dev/fixture"'
        Write-TestFile -Root $fixtureRoot -RelativePath 'docs\notes.md' -Text 'notes'
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\helper.ps1' -Text 'Write-Host 1'
        Write-TestFile -Root $fixtureRoot -RelativePath 'assets\source.psd' -Text 'raw'
        Write-TestFile -Root $fixtureRoot -RelativePath '.claude\skills\fixture\SKILL.md' -Text 'skill'
        return $fixtureRoot
    }

    function Get-FixtureContentList {
        return @('common/units/names/fixture_names.txt', 'descriptor.mod', 'localisation/english/fixture_l_english.yml', 'thumbnail.png' | Sort-Object)
    }

    function New-FixturePackRepo {
        $fixtureRoot = New-TestDirectory
        foreach ($packName in @('alpha', 'beta')) {
            $packRoot = 'packs\' + $packName
            Write-TestFile -Root $fixtureRoot -RelativePath "$packRoot\descriptor.mod" -Text ("version=`"1.0`"`r`nname=`"Fixture Pack: $packName`"`r`nsupported_version=`"1.19.*`"`r`n")
            [System.IO.File]::WriteAllBytes((Join-Path $fixtureRoot "$packRoot\thumbnail.png"), [byte[]](137, 80, 78, 71))
            Write-TestFile -Root $fixtureRoot -RelativePath "$packRoot\events\${packName}_events.txt" -Text "add_namespace = $packName`r`n"
            Write-TestFile -Root $fixtureRoot -RelativePath "$packRoot\localisation\english\${packName}_l_english.yml" -Text "l_english:`r`n ${packName}_key:0 `"Text`"`r`n" -Bom
            Write-TestFile -Root $fixtureRoot -RelativePath "$packRoot\WORKSHOP_DESCRIPTION_GUIDELINES.md" -Text "# $packName`r`n`r`n``````bbcode`r`n[h1]$packName[/h1]`r`n```````r`n"
        }
        Write-TestFile -Root $fixtureRoot -RelativePath 'source\alpha\events.json' -Text '{}'
        Write-TestFile -Root $fixtureRoot -RelativePath 'events\decoy_events.txt' -Text "add_namespace = decoy`r`n"
        Write-TestFile -Root $fixtureRoot -RelativePath 'common\decoy\decoy.txt' -Text "decoy = { }`r`n"
        Write-TestFile -Root $fixtureRoot -RelativePath 'README.md' -Text '# Fixture packs'
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "defaultChangeNote": "Fixture update", "packages": { "alpha": { "root": "packs/alpha", "modFolderName": "fixture_alpha" }, "beta": { "root": "packs/beta", "modFolderName": "fixture_beta", "zipArchiveName": "beta_release.zip" } } }'
        return $fixtureRoot
    }

    function Get-FixturePackContentList {
        param([string]$PackName)

        return @("events/${PackName}_events.txt", 'descriptor.mod', "localisation/english/${PackName}_l_english.yml", 'thumbnail.png' | Sort-Object)
    }

    function Get-RelativeFileList {
        param([string]$Root)

        $listRoot = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
        return @(Get-ChildItem -LiteralPath $listRoot -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($listRoot.Length + 1).Replace('\', '/') } | Sort-Object)
    }

    function Get-NestedFolderList {
        param([string]$Root)

        return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory | Where-Object { $_.Name -eq $_.Parent.Name } | ForEach-Object { $_.FullName })
    }

    function Get-ZipEntryList {
        param([string]$ZipPath)

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            return @($archive.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName } | Sort-Object)
        } finally {
            $archive.Dispose()
        }
    }

    function Get-ScaffoldNormalizedText {
        param([string]$Path)

        return ((@([System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
    }
}

AfterAll {
    foreach ($tempRoot in $script:TempRoots) {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

Describe 'Descriptor helpers' -Tag 'Engine' {
    It 'reads the descriptor fields, also when supported_version comes before version' {
        $fixtureRoot = New-TestDirectory
        Write-TestFile -Root $fixtureRoot -RelativePath 'descriptor.mod' -Text ("supported_version=`"1.19.*`"`r`nversion=`"2.3`"`r`ntags={`r`n`t`"Historical`"`r`n`t`"Military`"`r`n}`r`nname=`"Some Mod`"`r`nremote_file_id=`"1234567890`"`r`n")
        $metadata = Get-ModMetadata -Path (Join-Path $fixtureRoot 'descriptor.mod')
        $metadata.Version | Should -Be '2.3'
        $metadata.SupportedVersion | Should -Be '1.19.*'
        $metadata.Name | Should -Be 'Some Mod'
        $metadata.RemoteFileId | Should -Be '1234567890'
        $metadata.Tags | Should -Be @('Historical', 'Military')
    }

    It 'writes the launcher path with forward slashes, before remote_file_id, replacing an old path' {
        $fixtureRoot = New-TestDirectory
        Write-TestFile -Root $fixtureRoot -RelativePath 'descriptor.mod' -Text ("name=`"Some Mod`"`r`npath=`"old`"`r`nremote_file_id=`"42`"`r`n")
        $launcherText = New-LauncherModContent -DescriptorPath (Join-Path $fixtureRoot 'descriptor.mod') -TargetModPath 'C:\Games\Hearts of Iron IV\mod\some_mod'
        $launcherLines = @($launcherText -split "`r`n")
        $launcherLines | Should -Be @('name="Some Mod"', 'path="C:/Games/Hearts of Iron IV/mod/some_mod"', 'remote_file_id="42"')
    }

    It 'adds remote_file_id to a descriptor without one, and replaces an existing one' {
        $fixtureRoot = New-TestDirectory
        $descriptorPath = Join-Path $fixtureRoot 'descriptor.mod'
        Write-TestFile -Root $fixtureRoot -RelativePath 'descriptor.mod' -Text ("name=`"Some Mod`"`r`nsupported_version=`"1.19.*`"`r`n")
        Set-ModDescriptorRemoteFileId -DescriptorPath $descriptorPath -RemoteFileId '111'
        (Get-ModMetadata -Path $descriptorPath).RemoteFileId | Should -Be '111'
        Set-ModDescriptorRemoteFileId -DescriptorPath $descriptorPath -RemoteFileId '222'
        $descriptorText = [System.IO.File]::ReadAllText($descriptorPath)
        $descriptorText | Should -Match 'remote_file_id="222"'
        ([regex]::Matches($descriptorText, 'remote_file_id')).Count | Should -Be 1
    }

    It 'leaves the cross-link marker lines out of the description and keeps the text between them' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        $descriptionLines = @('Intro line.', '<!-- cross-links:begin -->', '[b]More from the author[/b]', '[list]', '[*]One', '[/list]', '<!-- cross-links:end -->', '[h1]Info[/h1]', 'Last line <!-- cross-links:end --> stays.')
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text ("# Guidelines`r`n`r`n``````bbcode`r`n" + ($descriptionLines -join "`r`n") + "`r`n```````r`n")
        $description = Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })
        $description | Should -Be ((@('Intro line.', '[b]More from the author[/b]', '[list]', '[*]One', '[/list]', '[h1]Info[/h1]', 'Last line <!-- cross-links:end --> stays.')) -join "`r`n")
    }

    It 'leaves the region marker lines out of the description and keeps the text between them' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        $descriptionLines = @('<!-- region:image:hero -->', '[img]https://i.imgur.com/a.png[/img]', '<!-- /region -->', 'Intro line.', '<!-- region:info:rt56,ironman -->', '- Works with Road to 56.', '<!-- /region -->', 'Text <!-- region:inline --> stays.')
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text ("# Guidelines`r`n`r`n``````bbcode`r`n" + ($descriptionLines -join "`r`n") + "`r`n```````r`n")
        $description = Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })
        $description | Should -Be ((@('[img]https://i.imgur.com/a.png[/img]', 'Intro line.', '- Works with Road to 56.', 'Text <!-- region:inline --> stays.')) -join "`r`n")
    }

    It 'leaves an empty region and a region at the very end out' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "``````bbcode`r`nText`r`n<!-- region:image:strip-info -->`r`n<!-- /region -->`r`n<!-- region:image:button-wiki -->`r`n[img]x[/img]`r`n<!-- /region -->`r`n```````r`n"
        (Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })) | Should -Be "Text`r`n[img]x[/img]"
    }

    It 'keeps a marker that ends a line of text, and only drops a marker that stands alone on its line' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "``````bbcode`r`nLine one <!-- /region -->`r`nLine two <!-- region:x -->`r`n<!-- region:y -->`r`nLine three <!-- /region -->`r`n```````r`n"
        (Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })) | Should -Be "Line one <!-- /region -->`r`nLine two <!-- region:x -->`r`nLine three <!-- /region -->"
    }

    It 'leaves an empty or an unclosed region at the very end out without a stray line break' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "``````bbcode`r`nA`r`n<!-- region:image:x -->`r`n<!-- /region -->`r`n```````r`n"
        (Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })) | Should -Be 'A'
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "``````bbcode`r`nA`r`n<!-- region:image:x -->`r`n```````r`n"
        (Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })) | Should -Be 'A'
    }

    It 'leaves a marker line at the very end of the description out as well' {
        $fixtureRoot = New-TestDirectory
        $guidelinesPath = Join-Path $fixtureRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
        Write-TestFile -Root $fixtureRoot -RelativePath 'WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "``````bbcode`r`nText`r`n<!-- cross-links:begin -->`r`nBlock`r`n<!-- cross-links:end -->`r`n```````r`n"
        (Get-ModWorkshopDescription -Config ([PSCustomObject]@{ GuidelinesPath = $guidelinesPath })) | Should -Be "Text`r`nBlock"
    }
}

Describe 'Parameters of build.ps1' -Tag 'Engine' {
    It 'passes only the lifecycle parameters of a script on to the engine' {
        function Invoke-BuildScriptProbe {
            param([switch]$Package, [string]$ZipOutput, [string]$Audit)
            Select-ModBuildParameters -BoundParameters $PSBoundParameters
        }
        $selectedParameters = Invoke-BuildScriptProbe -Package -ZipOutput 'out.zip' -Audit 'GER'
        @($selectedParameters.Keys | Sort-Object) | Should -Be @('Package', 'ZipOutput')
        $selectedParameters['ZipOutput'] | Should -Be 'out.zip'
    }
}

Describe 'Structure check of script files' -Tag 'Engine' {
    It 'accepts balanced braces, a # inside a quoted name and an escaped quote' {
        $problems = Get-ClausewitzSyntaxProblems -Text "FIX = {`n    name = `"Squadron #1`"`n    desc = `"say \`"hi\`"`"`n    # a comment with { and `"`n}`n"
        $problems.Count | Should -Be 0
    }

    It 'reports an opening brace that is never closed, with its line' {
        $problems = Get-ClausewitzSyntaxProblems -Text "a = {`n    b = {`n    }`n"
        @($problems) | Should -Be @('line 1: opening brace that is never closed')
    }

    It 'reports a closing brace without an opening one, with its line' {
        $problems = Get-ClausewitzSyntaxProblems -Text "a = {`n}`n}`n"
        @($problems) | Should -Be @('line 3: closing brace without an opening one')
    }

    It 'reports a quote that is never closed' {
        $problems = Get-ClausewitzSyntaxProblems -Text "a = { name = `"open }`n"
        @($problems | Where-Object { $_ -match 'quote that is never closed' }).Count | Should -Be 1
    }
}

Describe 'Content selection and staging' -Tag 'Engine' {
    It 'selects only the content folders and the descriptor and thumbnail' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        @(Get-ModContentFiles -Config $config) | Should -Be (Get-FixtureContentList)
    }

    It 'copies into an existing folder without nesting, and removes what does not belong' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $destination = Join-Path (New-TestDirectory) 'deployed'
        Copy-ModContent -Config $config -Destination $destination
        Write-TestFile -Root $destination -RelativePath 'common\stale_file.txt' -Text 'old'
        Write-TestFile -Root $destination -RelativePath 'README.md' -Text 'old'
        Copy-ModContent -Config $config -Destination $destination
        Get-NestedFolderList -Root $destination | Should -BeNullOrEmpty
        Get-RelativeFileList -Root $destination | Should -Be (Get-FixtureContentList)
    }

    It 'accepts a clean stage' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $stage = Join-Path (New-TestDirectory) 'stage'
        Copy-ModContent -Config $config -Destination $stage
        (Test-ModStage -Config $config -StageDir $stage).Count | Should -Be 0
    }

    It 'flags development files, placeholders, stray files and wrong encodings in a stage' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $stage = New-TestDirectory
        Write-TestFile -Root $stage -RelativePath 'descriptor.mod' -Text 'name="x"'
        Write-TestFile -Root $stage -RelativePath 'common\notes.md' -Text 'notes'
        Write-TestFile -Root $stage -RelativePath 'common\.gitkeep' -Text ''
        Write-TestFile -Root $stage -RelativePath 'common\bom.txt' -Text 'a = b' -Bom
        Write-TestFile -Root $stage -RelativePath 'localisation\english\no_bom_l_english.yml' -Text 'l_english:'
        Write-TestFile -Root $stage -RelativePath 'wiki\Home.md' -Text 'wiki'
        Write-TestFile -Root $stage -RelativePath 'README.md' -Text 'readme'
        Write-TestFile -Root $stage -RelativePath 'fixture.mod' -Text 'path="x"'
        $problems = Test-ModStage -Config $config -StageDir $stage
        $problems | Should -Contain 'thumbnail.png: missing'
        $problems | Should -Contain 'common/notes.md: development file'
        $problems | Should -Contain 'common/.gitkeep: placeholder file'
        $problems | Should -Contain 'common/bom.txt: starts with a UTF-8 BOM'
        $problems | Should -Contain 'localisation/english/no_bom_l_english.yml: localisation file without a UTF-8 BOM'
        $problems | Should -Contain 'README.md: not a mod file'
        $problems | Should -Contain 'fixture.mod: not a mod file'
        @($problems | Where-Object { $_ -like 'wiki/Home.md: outside the content folders*' }).Count | Should -Be 1
    }
}

Describe 'Validation' -Tag 'Engine' {
    It 'passes for a clean mod' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        Invoke-ModValidation -Config $config -SkipParser | Should -BeTrue
    }

    It 'fails for an unclosed brace, a BOM in a script file and a localisation file without a BOM' {
        foreach ($brokenCase in @(
                @{ Path = 'common\broken.txt'; Text = "a = {`n"; Bom = $false },
                @{ Path = 'interface\window.gui'; Text = "guiTypes = { }`n"; Bom = $true },
                @{ Path = 'localisation\english\x_l_english.yml'; Text = "l_english:`n"; Bom = $false }
            )) {
            $fixtureRoot = New-FixtureRepo
            Write-TestFile -Root $fixtureRoot -RelativePath $brokenCase.Path -Text $brokenCase.Text -Bom:$brokenCase.Bom
            $config = Get-ModBuildConfig -RepoDir $fixtureRoot
            Invoke-ModValidation -Config $config -SkipParser | Should -BeFalse -Because "$($brokenCase.Path) is broken"
        }
    }

    It 'fails when .gitignore hides descriptor.mod, and passes once it is excepted' {
        if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not installed'
            return
        }
        $fixtureRoot = New-FixtureRepo
        Invoke-ModGit -RepoDir $fixtureRoot -Arguments @('init', '-q') | Out-Null
        Write-TestFile -Root $fixtureRoot -RelativePath '.gitignore' -Text "*.mod`n"
        $ErrorActionPreference = 'Stop'
        Invoke-ModValidation -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) -SkipParser | Should -BeFalse
        Write-TestFile -Root $fixtureRoot -RelativePath '.gitignore' -Text "*.mod`n!descriptor.mod`n"
        Invoke-ModValidation -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) -SkipParser | Should -BeTrue
    }

    It 'fails when the descriptor or the thumbnail is missing' {
        $fixtureRoot = New-FixtureRepo
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'thumbnail.png')
        Invoke-ModValidation -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) -SkipParser | Should -BeFalse
    }
}

Describe 'Lifecycle actions' -Tag 'Engine' {
    It 'packages only the content, with forward slashes, in the flat layout' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $zipPath = Join-Path (New-TestDirectory) 'package.zip'
        Invoke-ModPackage -Config $config -ZipOutput $zipPath | Should -Be 0
        Get-ZipEntryList -ZipPath $zipPath | Should -Be (Get-FixtureContentList)
    }

    It 'packages a mod folder and a launcher file in the ModFolder layout' {
        $fixtureRoot = New-FixtureRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "modFolderName": "fixture_mod", "packageLayout": "ModFolder" }'
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot
        $zipPath = Join-Path (New-TestDirectory) 'package.zip'
        Invoke-ModPackage -Config $config -ZipOutput $zipPath | Should -Be 0
        $expectedEntries = @(@(Get-FixtureContentList | ForEach-Object { 'fixture_mod/' + $_ }) + @('fixture_mod.mod') | Sort-Object)
        Get-ZipEntryList -ZipPath $zipPath | Should -Be $expectedEntries
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($contentEntry in @(Get-FixtureContentList)) {
                $entryStream = $archive.GetEntry('fixture_mod/' + $contentEntry).Open()
                $entryBytes = [System.IO.MemoryStream]::new()
                try { $entryStream.CopyTo($entryBytes) } finally { $entryStream.Dispose() }
                [System.Convert]::ToBase64String($entryBytes.ToArray()) | Should -Be ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $fixtureRoot $contentEntry.Replace('/', '\'))))) -Because $contentEntry
            }
            $launcherStream = $archive.GetEntry('fixture_mod.mod').Open()
            $launcherReader = [System.IO.StreamReader]::new($launcherStream)
            try { $launcherReader.ReadToEnd() | Should -Match 'path="mod/fixture_mod"' } finally { $launcherReader.Dispose() }
        } finally {
            $archive.Dispose()
        }
    }

    It 'refuses to package a development file inside a content folder' {
        $fixtureRoot = New-FixtureRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'common\units\README.md' -Text 'notes'
        $zipPath = Join-Path (New-TestDirectory) 'package.zip'
        Invoke-ModPackage -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) -ZipOutput $zipPath | Should -Be 1
        Test-Path -LiteralPath $zipPath | Should -BeFalse
    }

    It 'deploys twice without nesting and points the launcher file at the copy' {
        $modDir = New-TestDirectory
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo) -ModDir $modDir
        Invoke-ModDeploy -Config $config | Should -Be 0
        Invoke-ModDeploy -Config $config | Should -Be 0
        $deployedFolder = Join-Path $modDir $config.ModFolderName
        Get-NestedFolderList -Root $deployedFolder | Should -BeNullOrEmpty
        Get-RelativeFileList -Root $deployedFolder | Should -Be (Get-FixtureContentList)
        Get-ModLauncherTarget -LauncherFilePath (Join-Path $modDir ($config.ModFolderName + '.mod')) | Should -Be $deployedFolder
    }

    It 'points the launcher file at the repository with DevLink, and Clean removes it' {
        $modDir = New-TestDirectory
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo) -ModDir $modDir
        $launcherFile = Join-Path $modDir ($config.ModFolderName + '.mod')
        Invoke-ModDevLink -Config $config | Should -Be 0
        Get-ModLauncherTarget -LauncherFilePath $launcherFile | Should -Be $config.RepoDir
        Invoke-ModClean -Config $config | Should -Be 0
        Test-Path -LiteralPath $launcherFile | Should -BeFalse
    }

    It 'stages a dry-run upload of the content only, as a new hidden item' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 0
        $stagedLine = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' })[0]
        $contentDir = ($stagedLine -replace '^.*Staged content at:\s*', '').Trim()
        $script:TempRoots.Add((Split-Path -Parent $contentDir))
        Get-RelativeFileList -Root $contentDir | Should -Be (Get-FixtureContentList)
        $listedLines = @((@($publishOutput | ForEach-Object { "$_" }) -join "`n") -split "`r?`n")
        foreach ($contentFile in @(Get-FixtureContentList)) {
            @($listedLines | Where-Object { $_ -eq "  $contentFile" }).Count | Should -Be 1 -Because "the dry run lists $contentFile once"
        }
        $vdfText = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $contentDir) 'workshop_build.vdf'))
        $vdfText | Should -Match '"publishedfileid" "0"'
        $vdfText | Should -Match '"visibility" "2"'
    }

    It 'stages a dry-run upload in a git repository that has no commits yet' {
        if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not installed'
            return
        }
        $fixtureRoot = New-FixtureRepo
        Invoke-ModGit -RepoDir $fixtureRoot -Arguments @('init', '-q') | Out-Null
        $ErrorActionPreference = 'Stop'
        $publishOutput = @(Invoke-ModPublish -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) -DryRun -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 0
        $stagedLine = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' })[0]
        $script:TempRoots.Add((Split-Path -Parent (($stagedLine -replace '^.*Staged content at:\s*', '').Trim())))
    }
}

Describe 'Packages' -Tag 'Engine' {
    It 'keeps a repository without packages at its root, and refuses -Pack there' {
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        $config.ContentRoot | Should -Be $config.RepoDir
        $config.ContentPrefix | Should -Be ''
        @($config.PackageNames).Count | Should -Be 0
        @(Get-ModSelectedConfigs -Config $config).Count | Should -Be 1
        { Get-ModSelectedConfigs -Config $config -Pack 'alpha' } | Should -Throw '*defines no packages*'
    }

    It 'gives each package its own root, descriptor, folder, archive and inherited settings' {
        $fixtureRoot = New-FixturePackRepo
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot
        @($config.PackageNames) | Should -Be @('alpha', 'beta')
        $alphaConfig = Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha'
        $alphaConfig.RepoDir | Should -Be $config.RepoDir
        $alphaConfig.ContentRoot | Should -Be (Join-Path $config.RepoDir 'packs\alpha')
        $alphaConfig.ContentPrefix | Should -Be 'packs/alpha/'
        $alphaConfig.DescriptorPath | Should -Be (Join-Path $config.RepoDir 'packs\alpha\descriptor.mod')
        $alphaConfig.GuidelinesPath | Should -Be (Join-Path $config.RepoDir 'packs\alpha\WORKSHOP_DESCRIPTION_GUIDELINES.md')
        $alphaConfig.ModFolderName | Should -Be 'fixture_alpha'
        $alphaConfig.ZipArchiveName | Should -Be 'fixture_alpha.zip'
        $alphaConfig.DefaultChangeNote | Should -Be 'Fixture update'
        (Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'beta').ZipArchiveName | Should -Be 'beta_release.zip'
    }

    It 'refuses an unknown package and a root outside the repository' {
        $fixtureRoot = New-FixturePackRepo
        { Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'gamma' } | Should -Throw '*its packages are: alpha, beta*'
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "packages": { "alpha": { "root": "../elsewhere" } } }'
        { Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha' } | Should -Throw '*outside the repository*'
    }

    It 'selects and validates only the files of each package' {
        $fixtureRoot = New-FixturePackRepo
        $packConfigs = @(Get-ModSelectedConfigs -Config (Get-ModBuildConfig -RepoDir $fixtureRoot))
        @($packConfigs | ForEach-Object { $_.PackageName }) | Should -Be @('alpha', 'beta')
        foreach ($packConfig in $packConfigs) {
            @(Get-ModContentFiles -Config $packConfig) | Should -Be (Get-FixturePackContentList -PackName $packConfig.PackageName)
            Invoke-ModValidation -Config $packConfig -SkipParser | Should -BeTrue
        }
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'packs\beta\thumbnail.png')
        Invoke-ModValidation -Config (Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'beta') -SkipParser | Should -BeFalse
        Invoke-ModValidation -Config (Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha') -SkipParser | Should -BeTrue
    }

    It 'packages every package into its own archive when no package is named' {
        $fixtureRoot = New-FixturePackRepo
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot
        Invoke-ModBuildAction -Config $config -Package -NoValidate | Select-Object -Last 1 | Should -Be 0
        Get-ZipEntryList -ZipPath (Join-Path $fixtureRoot 'artifacts\fixture_alpha.zip') | Should -Be (Get-FixturePackContentList -PackName 'alpha')
        Get-ZipEntryList -ZipPath (Join-Path $fixtureRoot 'artifacts\beta_release.zip') | Should -Be (Get-FixturePackContentList -PackName 'beta')
    }

    It 'refuses an upload or one archive name without a package, and an unknown package' {
        $config = Get-ModBuildConfig -RepoDir (New-FixturePackRepo)
        Invoke-ModBuildAction -Config $config -PublishSteam -DryRun -NoValidate -SteamUser 'tester' | Select-Object -Last 1 | Should -Be 1
        Invoke-ModBuildAction -Config $config -Package -NoValidate -ZipOutput 'one.zip' | Select-Object -Last 1 | Should -Be 1
        Invoke-ModBuildAction -Config $config -Package -NoValidate -Pack 'gamma' | Select-Object -Last 1 | Should -Be 1
    }

    It 'finds a mod that the Manager registry marks with publish false, by absolute or relative path, and no other' {
        $managerRoot = New-TestDirectory
        $localRepo = Join-Path $managerRoot 'mods\local-mod'
        $publishedRepo = Join-Path $managerRoot 'mods\published-mod'
        $unlistedRepo = Join-Path $managerRoot 'mods\unlisted-mod'
        foreach ($repoPath in @($localRepo, $publishedRepo, $unlistedRepo)) {
            Write-TestFile -Root $repoPath -RelativePath 'descriptor.mod' -Text "name=`"Fixture`"`r`n"
        }
        $registryText = ConvertTo-Json -InputObject @(
            [ordered]@{ modName = 'Local'; localPath = 'mods\local-mod'; publish = $false },
            [ordered]@{ modName = 'Published'; localPath = $publishedRepo; publish = $true },
            [ordered]@{ modName = 'Plain'; localPath = 'mods\plain-mod' }
        )
        Write-TestFile -Root $managerRoot -RelativePath 'Config\mods_registry.json' -Text $registryText
        Test-ModRegisteredLocalOnly -Config (Get-ModBuildConfig -RepoDir $localRepo) -ManagerRoot $managerRoot | Should -BeTrue
        Test-ModRegisteredLocalOnly -Config (Get-ModBuildConfig -RepoDir $publishedRepo) -ManagerRoot $managerRoot | Should -BeFalse
        Test-ModRegisteredLocalOnly -Config (Get-ModBuildConfig -RepoDir $unlistedRepo) -ManagerRoot $managerRoot | Should -BeFalse
    }

    It 'does not treat a mod as local only when no Manager root is found' {
        $repo = New-FixtureRepo
        Test-ModRegisteredLocalOnly -Config (Get-ModBuildConfig -RepoDir $repo) -ManagerRoot '' | Should -BeFalse
    }

    It 'refuses to upload a mod that is registered as local only' {
        Mock Test-ModRegisteredLocalOnly { $true }
        $config = Get-ModBuildConfig -RepoDir (New-FixtureRepo)
        Invoke-ModPublish -Config $config -DryRun -SteamUser 'tester' | Select-Object -Last 1 | Should -Be 1
        Should -Invoke Test-ModRegisteredLocalOnly -Times 1 -Exactly
    }

    It 'deploys and DevLinks one package from its own root' {
        $modDir = New-TestDirectory
        $fixtureRoot = New-FixturePackRepo
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot -ModDir $modDir
        Invoke-ModBuildAction -Config $config -Deploy -NoValidate -Pack 'beta' | Select-Object -Last 1 | Should -Be 0
        Get-RelativeFileList -Root (Join-Path $modDir 'fixture_beta') | Should -Be (Get-FixturePackContentList -PackName 'beta')
        Test-Path -LiteralPath (Join-Path $modDir 'fixture_alpha.mod') | Should -BeFalse
        Invoke-ModBuildAction -Config $config -DevLink -NoValidate -Pack 'alpha' | Select-Object -Last 1 | Should -Be 0
        Get-ModLauncherTarget -LauncherFilePath (Join-Path $modDir 'fixture_alpha.mod') | Should -Be (Join-Path $config.RepoDir 'packs\alpha')
    }

    It 'stages a dry-run upload of one package with its own title, preview and description' {
        $config = Get-ModBuildConfig -RepoDir (New-FixturePackRepo) -PackageName 'alpha'
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -UpdateDescription -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 0
        $stagedLine = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' })[0]
        $contentDir = ($stagedLine -replace '^.*Staged content at:\s*', '').Trim()
        $script:TempRoots.Add((Split-Path -Parent $contentDir))
        Get-RelativeFileList -Root $contentDir | Should -Be (Get-FixturePackContentList -PackName 'alpha')
        $vdfText = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $contentDir) 'workshop_build.vdf'))
        $vdfText | Should -Match ([regex]::Escape('"title" "Fixture Pack: alpha"'))
        $vdfText | Should -Match ([regex]::Escape('"description" "[h1]alpha[/h1]"'))
        $vdfText | Should -Match ([regex]::Escape('"previewfile" "' + ($contentDir -replace '\\', '/') + '/thumbnail.png"'))
    }

    It 'uploads the double quotes of a description and a change note as typographic quotes' {
        $fixtureRoot = New-FixturePackRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'packs\alpha\WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "# alpha`r`n`r`n``````bbcode`r`nInspired by the old `"Third Reich Events`" mod.`r`n[i]`"Duque de Caxias`"[/i] and `"[b]Suomi[/b]`"`r`n```````r`n"
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha'
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -UpdateDescription -SteamUser 'tester' -ChangeNote 'The "Winter War" event' 6>&1)
        [int]$publishOutput[-1] | Should -Be 0
        $stagedLine = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' })[0]
        $contentDir = ($stagedLine -replace '^.*Staged content at:\s*', '').Trim()
        $script:TempRoots.Add((Split-Path -Parent $contentDir))
        $vdfText = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $contentDir) 'workshop_build.vdf'))
        $openQuote = [string][char]0x201C
        $closeQuote = [string][char]0x201D
        $vdfText | Should -Match ([regex]::Escape('"description" "Inspired by the old ' + $openQuote + 'Third Reich Events' + $closeQuote + " mod.`n[i]" + $openQuote + 'Duque de Caxias' + $closeQuote + '[/i] and ' + $openQuote + '[b]Suomi[/b]' + $closeQuote + '"'))
        $vdfText | Should -Match ([regex]::Escape('"changenote" "The ' + $openQuote + 'Winter War' + $closeQuote + ' event"'))
        $vdfText | Should -Not -Match ([regex]::Escape('\"'))
    }

    It 'refuses an upload with a double quote inside a BBCode tag and names the line' {
        $fixtureRoot = New-FixturePackRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'packs\alpha\WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text "# alpha`r`n`r`n``````bbcode`r`n[h1]alpha[/h1]`r`nSee [url=`"https://example.com`"]the wiki[/url].`r`n```````r`n"
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha'
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -UpdateDescription -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 1
        $errorLines = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match '\[ERROR\]' })
        $errorLines.Count | Should -Be 1
        $errorLines[0] | Should -BeLike '*Line: See `[url="https://example.com"`]the wiki`[/url`].'
    }

    It 'measures a description in UTF-8 bytes as uploaded: LF line ends and typographic quotes' {
        (Get-ModWorkshopDescriptionSize -Description "ab`r`ncd").Bytes | Should -Be 5
        (Get-ModWorkshopDescriptionSize -Description 'Mannerheim "Suomi"').Bytes | Should -Be (18 + 4)
        (Get-ModWorkshopDescriptionSize -Description ([string][char]0x00E4)).Bytes | Should -Be 2
    }

    It 'refuses to upload a description over 8,000 bytes and warns above 7,500' {
        $fixtureRoot = New-FixturePackRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'packs\alpha\WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text ("# alpha`r`n`r`n``````bbcode`r`n" + ([string][char]0x00E4 * 4001) + "`r`n```````r`n")
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha'
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -UpdateDescription -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 1
        @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match '\[ERROR\].*8002 bytes.*over 8000' }).Count | Should -Be 1
        @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' }).Count | Should -Be 0

        Write-TestFile -Root $fixtureRoot -RelativePath 'packs\alpha\WORKSHOP_DESCRIPTION_GUIDELINES.md' -Text ("# alpha`r`n`r`n``````bbcode`r`n" + ('a' * 7600) + "`r`n```````r`n")
        $publishOutput = @(Invoke-ModPublish -Config $config -DryRun -UpdateDescription -SteamUser 'tester' 6>&1)
        [int]$publishOutput[-1] | Should -Be 0
        $stagedLine = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'Staged content at:' })[0]
        $script:TempRoots.Add((Split-Path -Parent (($stagedLine -replace '^.*Staged content at:\s*', '').Trim())))
        @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_ -match '\[WARN\].*7600 bytes.*budget of 7500' }).Count | Should -Be 1
    }

    It 'passes -Pack on to the engine' {
        function Invoke-PackProbe {
            param([switch]$Deploy, [string]$Pack, [string]$Generate)
            Select-ModBuildParameters -BoundParameters $PSBoundParameters
        }
        $selectedParameters = Invoke-PackProbe -Deploy -Pack 'alpha' -Generate 'x'
        @($selectedParameters.Keys | Sort-Object) | Should -Be @('Deploy', 'Pack')
        $selectedParameters['Pack'] | Should -Be 'alpha'
    }

    It 'fails validation when any package is broken, and passes for the sound one alone' {
        $fixtureRoot = New-FixturePackRepo
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'packs\beta\thumbnail.png')
        $config = Get-ModBuildConfig -RepoDir $fixtureRoot
        Invoke-ModBuildAction -Config $config -ValidateOnly | Select-Object -Last 1 | Should -Be 1
        Invoke-ModBuildAction -Config $config -ValidateOnly -Pack 'alpha' | Select-Object -Last 1 | Should -Be 0
    }

    It 'cleans one package and leaves the other deployed' {
        $modDir = New-TestDirectory
        $config = Get-ModBuildConfig -RepoDir (New-FixturePackRepo) -ModDir $modDir
        Invoke-ModBuildAction -Config $config -Deploy -NoValidate | Select-Object -Last 1 | Should -Be 0
        Invoke-ModBuildAction -Config $config -Clean -Pack 'alpha' | Select-Object -Last 1 | Should -Be 0
        Test-Path -LiteralPath (Join-Path $modDir 'fixture_alpha') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $modDir 'fixture_alpha.mod') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $modDir 'fixture_beta.mod') | Should -BeTrue
        Get-RelativeFileList -Root (Join-Path $modDir 'fixture_beta') | Should -Be (Get-FixturePackContentList -PackName 'beta')
    }

    It 'reports ignored and uncommitted files under the package root only' {
        if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not installed'
            return
        }
        $fixtureRoot = New-FixturePackRepo
        Invoke-ModGit -RepoDir $fixtureRoot -Arguments @('init', '-q') | Out-Null
        Write-TestFile -Root $fixtureRoot -RelativePath '.gitignore' -Text "*.mod`n"
        $ErrorActionPreference = 'Stop'
        $alphaConfig = Get-ModBuildConfig -RepoDir $fixtureRoot -PackageName 'alpha'
        @(Get-ModIgnoredRequiredFiles -Config $alphaConfig) | Should -Be @('packs/alpha/descriptor.mod')
        $uncommittedFiles = @(Get-ModUncommittedContentFiles -Config $alphaConfig)
        $uncommittedFiles.Count | Should -BeGreaterThan 0
        @($uncommittedFiles | Where-Object { $_ -notlike 'packs/alpha/*' }) | Should -BeNullOrEmpty
    }

    It 'refuses packages that share a mod folder name' {
        $fixtureRoot = New-FixturePackRepo
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "packages": { "alpha": { "root": "packs/alpha", "modFolderName": "same" }, "beta": { "root": "packs/beta", "modFolderName": "same" } } }'
        { Get-ModSelectedConfigs -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) } | Should -Throw '*share a ModFolderName*'
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "packages": { "alpha": { "root": "packs/alpha", "zipArchiveName": "same.zip" }, "beta": { "root": "packs/beta", "zipArchiveName": "same.zip" } } }'
        { Get-ModSelectedConfigs -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) } | Should -Throw '*share a ZipArchiveName*'
        Write-TestFile -Root $fixtureRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "packages": { "alpha": { "root": "packs/alpha" }, "beta": { "root": "packs/alpha" } } }'
        { Get-ModSelectedConfigs -Config (Get-ModBuildConfig -RepoDir $fixtureRoot) } | Should -Throw '*share a ContentRoot*'
    }
}

Describe 'Workshop VDF' -Tag 'Engine' {
    It 'escapes quotes and backslashes and keeps the visibility of an existing item' {
        $vdfText = New-ModWorkshopVdf -ContentDir 'C:\stage\content' -PreviewPath 'C:\stage\content\thumbnail.png' -Title 'My "Mod"' -PublishedFileId '123' -ChangeNote 'Fix C:\path and "quotes"'
        $vdfText | Should -Match ([regex]::Escape('"title" "My \"Mod\""'))
        $vdfText | Should -Match ([regex]::Escape('"changenote" "Fix C:\\path and ' + [char]0x201C + 'quotes' + [char]0x201D + '"'))
        $vdfText | Should -Match ([regex]::Escape('"contentfolder" "C:/stage/content"'))
        $vdfText | Should -Not -Match 'visibility'
    }

    It 'reads the item id SteamCMD writes back into the VDF' {
        $vdfPath = Join-Path (New-TestDirectory) 'workshop_build.vdf'
        [System.IO.File]::WriteAllText($vdfPath, "`"workshopitem`"`r`n{`r`n    `"publishedfileid`" `"3456789012`"`r`n}")
        Get-ModVdfPublishedFileId -Path $vdfPath | Should -Be '3456789012'
    }
}

Describe 'Test runner selection by changed files' -Tag 'Engine' {
    BeforeAll {
        $script:RunnerText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Run-Tests.ps1'))

        function New-RunnerRepo {
            $runnerRoot = New-TestDirectory
            foreach ($suiteName in @('Alpha', 'Beta', 'Knowledge')) {
                Write-TestFile -Root $runnerRoot -RelativePath "tests\$suiteName.Tests.ps1" -Text "Describe '$suiteName' { It 'passes' { 1 | Should -Be 1 } }"
            }
            Write-TestFile -Root $runnerRoot -RelativePath 'tests\Run-Tests.ps1' -Text $script:RunnerText
            Write-TestFile -Root $runnerRoot -RelativePath 'tools\HoiModBuild.json' -Text '{ "testSuites": { "Alpha": ["Common/Alpha/**"], "Beta": ["common/beta/*.txt", "gfx folder/**/*.dds"], "Knowledge": ["*.md"], "none": ["artwork/**"], "all": ["tools/shared.ps1"] } }'
            foreach ($trackedFile in @('common\alpha\a.txt', 'common\beta\b.txt', 'README.md', 'other\c.txt', 'tools\shared.ps1')) {
                Write-TestFile -Root $runnerRoot -RelativePath $trackedFile
            }
            & git -C $runnerRoot -c core.autocrlf=false init -q | Out-Null
            & git -C $runnerRoot -c core.autocrlf=false add -A | Out-Null
            & git -C $runnerRoot -c core.autocrlf=false -c user.name=Tester -c user.email=tester@example.com commit -q -m fixture | Out-Null
            return $runnerRoot
        }

        function Invoke-Runner {
            param(
                [Parameter(Mandatory = $true)][string]$Root,
                [string[]]$RunnerArguments = @('-Changed', '-ListOnly')
            )

            $runnerOutput = @(& $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Run-Tests.ps1') @RunnerArguments | ForEach-Object { "$_" })
            return [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = $runnerOutput
                Suites   = @($runnerOutput | Where-Object { $_ -match '^Suite: ' } | ForEach-Object { $_.Substring(7) })
            }
        }
    }

    It 'selects only the suite mapped to a changed file, whatever the case of the glob' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'common\alpha\a.txt' -Text 'changed'
        $runnerResult = Invoke-Runner -Root $runnerRoot
        $runnerResult.ExitCode | Should -Be 0
        $runnerResult.Suites | Should -Be @('Alpha')
    }

    It 'selects a changed test file as its own suite, with Knowledge for the citations in a script' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'tests\Beta.Tests.ps1' -Text "Describe 'Beta' { It 'still passes' { 2 | Should -Be 2 } }"
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Beta', 'Knowledge')
    }

    It 'selects every suite for an untracked file outside the map and names the file' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'other\new.txt'
        $runnerResult = Invoke-Runner -Root $runnerRoot
        $runnerResult.Suites | Should -Be @('Alpha', 'Beta', 'Knowledge')
        ($runnerResult.Output -join "`n") | Should -Match ([regex]::Escape('other/new.txt'))
    }

    It 'selects every suite for a script outside the map, although the built-in Knowledge entry reads it too' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'tools\new.ps1'
        $runnerResult = Invoke-Runner -Root $runnerRoot
        $runnerResult.Suites | Should -Be @('Alpha', 'Beta', 'Knowledge')
        ($runnerResult.Output -join "`n") | Should -Match ([regex]::Escape('tools/new.ps1'))
    }

    It 'keeps a single star within one folder' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'common\beta\sub\b.txt'
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Alpha', 'Beta', 'Knowledge')
    }

    It 'selects every suite for a file mapped to all' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'tools\shared.ps1' -Text 'changed'
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Alpha', 'Beta', 'Knowledge')
    }

    It 'selects no suite in a clean tree and exits 0' {
        $runnerResult = Invoke-Runner -Root (New-RunnerRepo)
        $runnerResult.ExitCode | Should -Be 0
        $runnerResult.Suites | Should -BeNullOrEmpty
        ($runnerResult.Output -join "`n") | Should -Match 'No changed file needs a test suite'
    }

    It 'skips a file mapped to none and selects Knowledge for a markdown file the map gives it' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'artwork\source.psd'
        Write-TestFile -Root $runnerRoot -RelativePath 'README.md' -Text 'changed'
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Knowledge')
    }

    It 'maps a renamed file by its new path' {
        $runnerRoot = New-RunnerRepo
        & git -C $runnerRoot mv common/beta/b.txt common/alpha/b.txt | Out-Null
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Alpha')
    }

    It 'matches untracked files in a new folder with a space, at the top of a double star and below it' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'gfx folder\icon.dds'
        Write-TestFile -Root $runnerRoot -RelativePath 'gfx folder\sub\deep\icon.dds'
        (Invoke-Runner -Root $runnerRoot).Suites | Should -Be @('Beta')
    }

    It 'refuses -Changed together with -Suite' {
        (Invoke-Runner -Root (New-RunnerRepo) -RunnerArguments @('-Changed', '-Suite', 'Alpha')).ExitCode | Should -Be 1
    }

    It 'runs only the selected suite and names the selection in the summary line' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'common\alpha\a.txt' -Text 'changed'
        $runnerResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-Changed')
        $runnerResult.ExitCode | Should -Be 0
        @($runnerResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('1 Passed, 0 Failed, 0 Skipped (changed: Alpha)'))
    }

    It 'runs the test files in parallel processes and adds up their results, a failing and a broken file included' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'tests\Failing.Tests.ps1' -Text "Describe 'Failing' { It 'fails' { 1 | Should -Be 2 }; It 'is skipped' -Skip { } }"
        Write-TestFile -Root $runnerRoot -RelativePath 'tests\Broken.Tests.ps1' -Text "throw 'broken at discovery'"
        Write-TestFile -Root $runnerRoot -RelativePath 'tests\Exiting.Tests.ps1' -Text "[Environment]::Exit(3)"
        $runnerResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-ThrottleLimit', '3')
        $runnerResult.ExitCode | Should -Be 1
        ($runnerResult.Output -join "`n") | Should -Match 'Processes:\s+3'
        ($runnerResult.Output -join "`n") | Should -Match 'Expected 2, but got 1'
        ($runnerResult.Output -join "`n") | Should -Match 'Exiting\.Tests\.ps1: the test process ended with exit code 3 and no result'
        @($runnerResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('3 Passed, 1 Failed, 1 Skipped, 2 test file(s) failed to run (all suites)'))
    }

    It 'leaves out the tests tagged Engine, which the Manager runs, in parallel and in one process, unless -EngineTests asks for them' {
        $runnerRoot = New-RunnerRepo
        Write-TestFile -Root $runnerRoot -RelativePath 'tests\Alpha.Tests.ps1' -Text "Describe 'Engine' -Tag 'Engine' { It 'tests the engine' { 1 | Should -Be 1 } }; Describe 'This repository' { It 'tests the mod' { 1 | Should -Be 1 } }"
        $parallelResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-ThrottleLimit', '3')
        ($parallelResult.Output -join "`n") | Should -Match 'Processes:\s+3'
        ($parallelResult.Output -join "`n") | Should -Match 'tests tagged Engine left out'
        @($parallelResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('3 Passed, 0 Failed, 0 Skipped (all suites)'))
        $parallelEngineResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-ThrottleLimit', '3', '-EngineTests')
        @($parallelEngineResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('4 Passed, 0 Failed, 0 Skipped (all suites)'))
        $serialResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-Suite', 'Alpha')
        @($serialResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('1 Passed, 0 Failed, 0 Skipped (suite: Alpha)'))
        $serialEngineResult = Invoke-Runner -Root $runnerRoot -RunnerArguments @('-Suite', 'Alpha', '-EngineTests')
        @($serialEngineResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('2 Passed, 0 Failed, 0 Skipped (suite: Alpha)'))
    }

    It 'runs the test files one after another in one process with -ThrottleLimit 1' {
        $runnerResult = Invoke-Runner -Root (New-RunnerRepo) -RunnerArguments @('-ThrottleLimit', '1')
        $runnerResult.ExitCode | Should -Be 0
        ($runnerResult.Output -join "`n") | Should -Match 'Processes:\s+1'
        @($runnerResult.Output | Where-Object { $_ -match 'Summary:' })[-1] | Should -Match ([regex]::Escape('3 Passed, 0 Failed, 0 Skipped (all suites)'))
    }
}

Describe 'This repository' {
    BeforeAll {
        if ($script:IsModRepo) {
            $script:RepoConfigs = @(Get-ModSelectedConfigs -Config (Get-ModBuildConfig -RepoDir $script:RepoRoot))
        }

        function Get-PackArguments {
            param($RepoConfig)

            if ($RepoConfig.PackageName) {
                return @('-Pack', $RepoConfig.PackageName)
            }
            return @()
        }
    }

    It 'build.ps1 loads the shared engine from tools\HoiModBuild.ps1' {
        if (-not $script:IsModRepo) {
            Set-ItResult -Skipped -Because 'this file runs from the Modding Manager, not from a mod repository'
            return
        }
        [System.IO.File]::ReadAllText($script:BuildScriptPath) | Should -Match ([regex]::Escape('tools\HoiModBuild.ps1'))
    }

    It 'carries the current shared build files of the Modding Manager' {
        $managerRoot = Get-ModManagerRoot
        if (-not $script:IsModRepo -or -not $managerRoot) {
            Set-ItResult -Skipped -Because 'the Modding Manager is not installed on this machine, or this is not a mod repository'
            return
        }
        $scaffoldPairs = @(
            @{ Source = 'Scripts\Build\HoiModBuild.ps1'; Target = 'tools\HoiModBuild.ps1' },
            @{ Source = 'Scripts\Build\HoiModBuild.Tests.ps1'; Target = 'tests\BuildEngine.Tests.ps1' },
            @{ Source = 'Scripts\Build\Run-Tests.ps1'; Target = 'tests\Run-Tests.ps1' },
            @{ Source = 'Scripts\Build\ci.yml'; Target = '.github\workflows\ci.yml' }
        )
        foreach ($groupName in @(Get-ModSharedToolGroups -RepoPath $script:RepoRoot)) {
            foreach ($sharedFile in @(Get-ModSharedToolFiles -ManagerRoot $managerRoot -GroupName $groupName)) {
                $scaffoldPairs += @{ Source = $sharedFile.Source.Substring($managerRoot.TrimEnd('\').Length + 1); Target = $sharedFile.Target }
            }
        }
        $staleTargets = foreach ($scaffoldPair in $scaffoldPairs) {
            $targetPath = Join-Path $script:RepoRoot $scaffoldPair.Target
            if (-not (Test-Path -LiteralPath $targetPath) -or (Get-ScaffoldNormalizedText -Path $targetPath) -cne (Get-ScaffoldNormalizedText -Path (Join-Path $managerRoot $scaffoldPair.Source))) {
                $scaffoldPair.Target
            }
        }
        @($staleTargets) | Should -BeNullOrEmpty -Because 'the Manager copies them with Scripts\Sync-ModScaffold.ps1'
    }

    It 'names only existing suites in the testSuites map of tools\HoiModBuild.json' {
        $settingsPath = Join-Path $script:RepoRoot 'tools\HoiModBuild.json'
        if (-not $script:IsModRepo -or -not (Test-Path -LiteralPath $settingsPath)) {
            Set-ItResult -Skipped -Because 'this file runs from the Modding Manager, or the mod has no tools\HoiModBuild.json'
            return
        }
        $settings = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not $settings.PSObject.Properties['testSuites']) {
            Set-ItResult -Skipped -Because 'the mod has no testSuites map'
            return
        }
        $unknownSuites = @($settings.testSuites.PSObject.Properties.Name | Where-Object { @('all', 'none') -notcontains $_ -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "$_.Tests.ps1")) })
        $unknownSuites | Should -BeNullOrEmpty -Because 'a misspelt suite name selects nothing while its files still count as mapped'
    }

    It 'packages exactly the content folders and the descriptor and thumbnail' {
        if (-not $script:IsModRepo) {
            Set-ItResult -Skipped -Because 'this file runs from the Modding Manager, not from a mod repository'
            return
        }
        foreach ($repoConfig in $script:RepoConfigs) {
            $repoContent = @(Get-ModContentFiles -Config $repoConfig)
            $zipPath = Join-Path (New-TestDirectory) 'package.zip'
            $packArguments = @(Get-PackArguments -RepoConfig $repoConfig)
            & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -Package -NoValidate -ZipOutput $zipPath @packArguments | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "package '$($repoConfig.PackageName)'"
            $expectedEntries = $repoContent
            if ($repoConfig.PackageLayout -eq 'ModFolder') {
                $expectedEntries = @(@($repoContent | ForEach-Object { $repoConfig.ModFolderName + '/' + $_ }) + @($repoConfig.ModFolderName + '.mod') | Sort-Object)
            }
            Get-ZipEntryList -ZipPath $zipPath | Should -Be $expectedEntries
        }
    }

    It 'deploys twice into the same mod folder without nesting' {
        if (-not $script:IsModRepo) {
            Set-ItResult -Skipped -Because 'this file runs from the Modding Manager, not from a mod repository'
            return
        }
        foreach ($repoConfig in $script:RepoConfigs) {
            $modDir = New-TestDirectory
            $packArguments = @(Get-PackArguments -RepoConfig $repoConfig)
            foreach ($deployRun in 1..2) {
                & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -Deploy -NoValidate -ModDir $modDir @packArguments | Out-Null
                $LASTEXITCODE | Should -Be 0 -Because "package '$($repoConfig.PackageName)'"
            }
            $deployedFolder = Join-Path $modDir $repoConfig.ModFolderName
            Get-NestedFolderList -Root $deployedFolder | Should -BeNullOrEmpty
            Get-RelativeFileList -Root $deployedFolder | Should -Be @(Get-ModContentFiles -Config $repoConfig)
        }
    }

    It 'stages a dry-run Workshop upload of the content only' {
        if (-not $script:IsModRepo) {
            Set-ItResult -Skipped -Because 'this file runs from the Modding Manager, not from a mod repository'
            return
        }
        foreach ($repoConfig in $script:RepoConfigs) {
            if (Test-ModRegisteredLocalOnly -Config $repoConfig) {
                continue
            }
            $packArguments = @(Get-PackArguments -RepoConfig $repoConfig)
            $dryRunOutput = @(& $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -PublishSteam -DryRun -NoValidate -SteamUser 'tester' @packArguments 2>&1 | ForEach-Object { "$_" })
            $LASTEXITCODE | Should -Be 0 -Because "package '$($repoConfig.PackageName)'"
            $stagedLine = @($dryRunOutput | Where-Object { $_ -match 'Staged content at:' })[0]
            $stagedLine | Should -Not -BeNullOrEmpty
            $contentDir = ($stagedLine -replace '^.*Staged content at:\s*', '').Trim()
            $script:TempRoots.Add((Split-Path -Parent $contentDir))
            Get-NestedFolderList -Root $contentDir | Should -BeNullOrEmpty
            Get-RelativeFileList -Root $contentDir | Should -Be @(Get-ModContentFiles -Config $repoConfig)
        }
    }
}
