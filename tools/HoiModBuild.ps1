function Write-Step { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info { param([string]$msg) Write-Host "  [INFO] $msg" -ForegroundColor Gray }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

function Get-ModDefaultContentDirs {
    return @('common', 'events', 'gfx', 'history', 'interface', 'localisation', 'map', 'music', 'portraits', 'sound', 'tutorial')
}

function Get-ModDefaultModDir {
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Paradox Interactive\Hearts of Iron IV\mod')
}

function Get-ModUtf8NoBom {
    return [System.Text.UTF8Encoding]::new($false)
}

function Get-ModSettingValue {
    param(
        $Settings,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue
    )

    if ($null -ne $Settings -and $Settings.PSObject.Properties[$Name] -and $null -ne $Settings.$Name -and "$($Settings.$Name)" -ne '') {
        return $Settings.$Name
    }
    return $DefaultValue
}

function Get-ModPackageSettings {
    param($Settings)

    $packageSettings = [ordered]@{}
    if ($null -ne $Settings -and $Settings.PSObject.Properties['packages'] -and $null -ne $Settings.packages) {
        foreach ($packageProperty in $Settings.packages.PSObject.Properties) {
            $packageSettings[$packageProperty.Name] = $packageProperty.Value
        }
    }
    return $packageSettings
}

function Get-ModBuildConfig {
    param(
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [string]$ModDir,
        [string]$PackageName
    )

    $repoPath = (Get-Item -LiteralPath $RepoDir).FullName.TrimEnd('\')
    $repoFolderName = Split-Path -Leaf $repoPath
    $settingsPath = Join-Path $repoPath 'tools\HoiModBuild.json'
    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    $packageSettings = Get-ModPackageSettings -Settings $settings
    $packageNames = @($packageSettings.Keys)
    $packageSetting = $null
    $contentRoot = $repoPath
    $contentPrefix = ''
    $modFolderName = [string](Get-ModSettingValue -Settings $settings -Name 'modFolderName' -DefaultValue $repoFolderName)
    $zipArchiveName = [string](Get-ModSettingValue -Settings $settings -Name 'zipArchiveName' -DefaultValue ($repoFolderName + '.zip'))
    if ($PackageName) {
        if ($packageNames.Count -eq 0) {
            throw "tools\HoiModBuild.json defines no packages, so -Pack '$PackageName' names nothing"
        }
        if (-not $packageSettings.Contains($PackageName)) {
            throw "tools\HoiModBuild.json defines no package '$PackageName'; its packages are: $($packageNames -join ', ')"
        }
        $packageSetting = $packageSettings[$PackageName]
        $packageRoot = [string](Get-ModSettingValue -Settings $packageSetting -Name 'root' -DefaultValue '')
        if (-not $packageRoot -or [System.IO.Path]::IsPathRooted($packageRoot)) {
            throw "tools\HoiModBuild.json: package '$PackageName' needs a root relative to the repository"
        }
        $contentRoot = [System.IO.Path]::GetFullPath((Join-Path $repoPath $packageRoot)).TrimEnd('\')
        if (-not $contentRoot.StartsWith($repoPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "tools\HoiModBuild.json: the root '$packageRoot' of package '$PackageName' lies outside the repository"
        }
        $contentPrefix = $contentRoot.Substring($repoPath.Length + 1).Replace('\', '/') + '/'
        $modFolderName = [string](Get-ModSettingValue -Settings $packageSetting -Name 'modFolderName' -DefaultValue ($repoFolderName + '_' + $PackageName))
        $zipArchiveName = [string](Get-ModSettingValue -Settings $packageSetting -Name 'zipArchiveName' -DefaultValue ($modFolderName + '.zip'))
    }

    $packageLayout = [string](Get-ModSettingValue -Settings $packageSetting -Name 'packageLayout' -DefaultValue (Get-ModSettingValue -Settings $settings -Name 'packageLayout' -DefaultValue 'Flat'))
    if (@('Flat', 'ModFolder') -notcontains $packageLayout) {
        throw "tools\HoiModBuild.json: packageLayout must be 'Flat' or 'ModFolder', not '$packageLayout'"
    }
    if (-not $ModDir) {
        $ModDir = Get-ModDefaultModDir
    }

    return [PSCustomObject]@{
        RepoDir           = $repoPath
        ContentRoot       = $contentRoot
        ContentPrefix     = $contentPrefix
        PackageName       = [string]$PackageName
        PackageNames      = $packageNames
        DescriptorPath    = Join-Path $contentRoot 'descriptor.mod'
        ModFolderName     = $modFolderName
        ZipArchiveName    = $zipArchiveName
        PackageLayout     = $packageLayout
        ContentDirs       = @(Get-ModSettingValue -Settings $packageSetting -Name 'contentDirs' -DefaultValue (Get-ModSettingValue -Settings $settings -Name 'contentDirs' -DefaultValue (Get-ModDefaultContentDirs)))
        ContentFiles      = @('descriptor.mod', 'thumbnail.png')
        DefaultChangeNote = [string](Get-ModSettingValue -Settings $packageSetting -Name 'defaultChangeNote' -DefaultValue (Get-ModSettingValue -Settings $settings -Name 'defaultChangeNote' -DefaultValue ''))
        ModDir            = $ModDir
        ArtifactsDir      = Join-Path $repoPath 'artifacts'
        GuidelinesPath    = Join-Path $contentRoot 'WORKSHOP_DESCRIPTION_GUIDELINES.md'
    }
}

function Get-ModSelectedConfigs {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$Pack
    )

    if ($Pack) {
        return @(Get-ModBuildConfig -RepoDir $Config.RepoDir -ModDir $Config.ModDir -PackageName $Pack)
    }
    if ($Config.PackageName -or @($Config.PackageNames).Count -eq 0) {
        return @($Config)
    }
    $packageConfigs = @($Config.PackageNames | ForEach-Object { Get-ModBuildConfig -RepoDir $Config.RepoDir -ModDir $Config.ModDir -PackageName $_ })
    foreach ($uniqueProperty in @('ModFolderName', 'ZipArchiveName', 'ContentRoot')) {
        $sharedValues = @($packageConfigs | Group-Object -Property $uniqueProperty | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        if ($sharedValues.Count -gt 0) {
            throw "tools\HoiModBuild.json: packages share a $uniqueProperty ($($sharedValues -join ', ')); each package needs its own"
        }
    }
    return $packageConfigs
}

function Select-ModBuildParameters {
    param([Parameter(Mandatory = $true)]$BoundParameters)

    $lifecycleParameterNames = @('Deploy', 'DevLink', 'Package', 'PublishSteam', 'InstallSteamCmd', 'ValidateOnly', 'Test', 'Validate', 'NoValidate', 'Clean', 'ZipOutput', 'SteamUser', 'ChangeNote', 'SteamCmdPath', 'DryRun', 'UpdateDescription', 'Pack')
    $selectedParameters = @{}
    foreach ($parameterName in $lifecycleParameterNames) {
        if ($BoundParameters.ContainsKey($parameterName)) {
            $selectedParameters[$parameterName] = $BoundParameters[$parameterName]
        }
    }
    return $selectedParameters
}

function Get-ModManagerRoot {
    $relativeCandidates = @(
        (Join-Path $PSScriptRoot '..\..\..\..'),
        (Join-Path $PSScriptRoot '..\..')
    )
    foreach ($relativeCandidate in $relativeCandidates) {
        $candidateRoot = [System.IO.Path]::GetFullPath($relativeCandidate).TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $candidateRoot 'Config\mods_registry.json')) {
            return $candidateRoot
        }
    }
    $pointerPaths = @(
        (Join-Path $HOME '.claude\skills\hoi4-modding-knowledge\manager-root.txt'),
        (Join-Path $HOME '.gemini\config\skills\hoi4-modding-knowledge\manager-root.txt')
    )
    foreach ($pointerPath in $pointerPaths) {
        if (-not (Test-Path -LiteralPath $pointerPath)) {
            continue
        }
        $managerRoot = [System.IO.File]::ReadAllText($pointerPath).Trim()
        if ($managerRoot -and (Test-Path -LiteralPath (Join-Path $managerRoot 'Config\mods_registry.json'))) {
            return $managerRoot
        }
    }
    return $null
}

function Get-ModMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Descriptor file not found: $Path"
    }

    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $metadata = @{
        Raw              = $raw
        Version          = $null
        SupportedVersion = $null
        Name             = $null
        RemoteFileId     = $null
        Tags             = @()
    }

    $fieldNames = @{ Version = 'version'; SupportedVersion = 'supported_version'; Name = 'name'; RemoteFileId = 'remote_file_id' }
    foreach ($metadataKey in @($fieldNames.Keys)) {
        $fieldMatch = [regex]::Match($raw, '(?m)^\s*' + $fieldNames[$metadataKey] + '\s*=\s*"([^"]*)"')
        if ($fieldMatch.Success -and $fieldMatch.Groups[1].Value) {
            $metadata[$metadataKey] = $fieldMatch.Groups[1].Value
        }
    }
    $tagsMatch = [regex]::Match($raw, '(?s)(?m)^\s*tags\s*=\s*\{(.*?)\}')
    if ($tagsMatch.Success) {
        $metadata.Tags = @([regex]::Matches($tagsMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    }

    return $metadata
}

function New-LauncherModContent {
    param(
        [Parameter(Mandatory = $true)][string]$DescriptorPath,
        [Parameter(Mandatory = $true)][string]$TargetModPath
    )

    $rawLines = [System.IO.File]::ReadAllLines($DescriptorPath, [System.Text.Encoding]::UTF8)
    $normalizedPath = ($TargetModPath -replace '\\', '/')

    $lines = [System.Collections.Generic.List[string]]::new()
    $insertedPath = $false

    foreach ($line in $rawLines) {
        if ($line -match '^\s*path\s*=') {
            continue
        }
        if (-not $insertedPath -and ($line -match '^\s*remote_file_id\s*=')) {
            $lines.Add('path="' + $normalizedPath + '"')
            $insertedPath = $true
        }
        $lines.Add($line)
    }

    if (-not $insertedPath) {
        $lines.Add('path="' + $normalizedPath + '"')
    }

    return ($lines -join "`r`n")
}

function Get-ModLauncherTarget {
    param([Parameter(Mandatory = $true)][string]$LauncherFilePath)

    if (-not (Test-Path -LiteralPath $LauncherFilePath)) {
        return $null
    }
    $launcherText = [System.IO.File]::ReadAllText($LauncherFilePath, [System.Text.Encoding]::UTF8)
    $pathMatch = [regex]::Match($launcherText, '(?m)^\s*path\s*=\s*"([^"]+)"')
    if (-not $pathMatch.Success) {
        return $null
    }
    return ($pathMatch.Groups[1].Value -replace '/', '\').TrimEnd('\')
}

function Test-ModFileHasBom {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fileStream = [System.IO.File]::OpenRead($Path)
    try {
        $leadingBytes = New-Object byte[] 3
        $readCount = $fileStream.Read($leadingBytes, 0, 3)
        return ($readCount -eq 3 -and $leadingBytes[0] -eq 0xEF -and $leadingBytes[1] -eq 0xBB -and $leadingBytes[2] -eq 0xBF)
    } finally {
        $fileStream.Dispose()
    }
}

function Get-ModContentFiles {
    param([Parameter(Mandatory = $true)]$Config)

    $relativePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($contentDir in $Config.ContentDirs) {
        $sourceDir = Join-Path $Config.ContentRoot $contentDir
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
            continue
        }
        $sourceRoot = (Get-Item -LiteralPath $sourceDir).FullName.TrimEnd('\')
        foreach ($contentFile in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)) {
            if ($contentFile.Name -eq '.gitkeep') {
                continue
            }
            $relativePaths.Add($contentDir + '/' + $contentFile.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/'))
        }
    }
    foreach ($contentFileName in $Config.ContentFiles) {
        if (Test-Path -LiteralPath (Join-Path $Config.ContentRoot $contentFileName) -PathType Leaf) {
            $relativePaths.Add($contentFileName)
        }
    }
    return @($relativePaths | Sort-Object)
}

function Get-ClausewitzLineNumber {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][int]$Index
    )

    return ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count + 1
}

function Get-ClausewitzSyntaxProblems {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $problems = [System.Collections.Generic.List[string]]::new()
    $openBraceIndexes = [System.Collections.Generic.Stack[int]]::new()
    $tokenPattern = '"(?:\\"|\\(?!")|[^"\\])*"|#[^\n]*|[{}]|"'
    foreach ($token in [regex]::Matches($Text, $tokenPattern)) {
        $tokenText = $token.Value
        if ($tokenText -eq '{') {
            $openBraceIndexes.Push($token.Index)
        } elseif ($tokenText -eq '}') {
            if ($openBraceIndexes.Count -eq 0) {
                $problems.Add(('line {0}: closing brace without an opening one' -f (Get-ClausewitzLineNumber -Text $Text -Index $token.Index)))
            } else {
                [void]$openBraceIndexes.Pop()
            }
        } elseif ($tokenText -eq '"') {
            $problems.Add(('line {0}: quote that is never closed' -f (Get-ClausewitzLineNumber -Text $Text -Index $token.Index)))
        }
    }
    foreach ($openBraceIndex in $openBraceIndexes) {
        $problems.Add(('line {0}: opening brace that is never closed' -f (Get-ClausewitzLineNumber -Text $Text -Index $openBraceIndex)))
    }
    return , $problems
}

function Test-ModGitRepository {
    param([Parameter(Mandatory = $true)]$Config)

    return ((Test-Path -LiteralPath (Join-Path $Config.RepoDir '.git')) -and [bool](Get-Command -Name 'git' -ErrorAction SilentlyContinue))
}

function Invoke-ModGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $gitOutput = @(& git -C $RepoDir @Arguments 2>$null)
        $gitExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $global:LASTEXITCODE = 0
    if ($gitExitCode -ne 0) {
        return @()
    }
    return $gitOutput
}

function Get-ModIgnoredRequiredFiles {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not (Test-ModGitRepository -Config $Config)) {
        return @()
    }
    $ignoredPaths = @(Invoke-ModGit -RepoDir $Config.RepoDir -Arguments (@('check-ignore', '--') + @($Config.ContentFiles | ForEach-Object { $Config.ContentPrefix + $_ })))
    return @($ignoredPaths | Where-Object { $_ })
}

function Get-ModUncommittedContentFiles {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not (Test-ModGitRepository -Config $Config)) {
        return @()
    }
    $contentPaths = @(@($Config.ContentDirs) + @($Config.ContentFiles) | Where-Object { Test-Path -LiteralPath (Join-Path $Config.ContentRoot $_) } | ForEach-Object { $Config.ContentPrefix + $_ })
    if ($contentPaths.Count -eq 0) {
        return @()
    }
    $statusLines = @(Invoke-ModGit -RepoDir $Config.RepoDir -Arguments (@('status', '--porcelain', '--untracked-files=all', '--') + $contentPaths))
    return @($statusLines | Where-Object { $_ -and $_.Length -gt 3 } | ForEach-Object { $_.Substring(3).Trim('"') })
}

function Invoke-ModValidation {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [switch]$SkipParser
    )

    $packageLabel = if ($Config.PackageName) { " of pack '$($Config.PackageName)'" } else { '' }
    Write-Step "Validating the descriptor, the thumbnail and the files that ship$packageLabel..."
    $problemCount = 0

    if (-not (Test-Path -LiteralPath $Config.DescriptorPath)) {
        Write-Err 'descriptor.mod is missing'
        $problemCount++
    } else {
        $metadata = Get-ModMetadata -Path $Config.DescriptorPath
        if (-not $metadata.Name) {
            Write-Err "descriptor.mod: missing 'name'"
            $problemCount++
        }
        if (-not $metadata.SupportedVersion) {
            Write-Err "descriptor.mod: missing 'supported_version'"
            $problemCount++
        }
        if ($metadata.Name -and $metadata.SupportedVersion) {
            Write-Ok "descriptor.mod: '$($metadata.Name)' for game version $($metadata.SupportedVersion)"
        }
    }

    $thumbnailPath = Join-Path $Config.ContentRoot 'thumbnail.png'
    if (-not (Test-Path -LiteralPath $thumbnailPath)) {
        Write-Err 'thumbnail.png is missing'
        $problemCount++
    } elseif ((Get-Item -LiteralPath $thumbnailPath).Length -gt 1MB) {
        Write-Warn 'thumbnail.png is larger than 1 MB, the Steam Workshop limit for a preview image: the upload will fail'
    }

    foreach ($ignoredPath in @(Get-ModIgnoredRequiredFiles -Config $Config)) {
        Write-Err "$ignoredPath is ignored by .gitignore, so it is never committed and CI does not have it: add the line !$ignoredPath after *.mod"
        $problemCount++
    }

    $contentFiles = @(Get-ModContentFiles -Config $Config)
    $scriptFiles = @($contentFiles | Where-Object { $_ -match '\.(txt|gui|gfx)$' })
    $localisationFiles = @($contentFiles | Where-Object { $_ -match '\.yml$' })

    foreach ($relativePath in $scriptFiles) {
        $fullPath = Join-Path $Config.ContentRoot $relativePath
        if (Test-ModFileHasBom -Path $fullPath) {
            Write-Err "${relativePath}: starts with a UTF-8 BOM; script, .gui and .gfx files are written without one"
            $problemCount++
        }
        $fileText = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
        foreach ($syntaxProblem in (Get-ClausewitzSyntaxProblems -Text $fileText)) {
            Write-Err "${relativePath}: $syntaxProblem"
            $problemCount++
        }
    }

    foreach ($relativePath in $localisationFiles) {
        if (-not (Test-ModFileHasBom -Path (Join-Path $Config.ContentRoot $relativePath))) {
            Write-Err "${relativePath}: localisation files need a UTF-8 BOM"
            $problemCount++
        }
    }

    if (-not $SkipParser -and $problemCount -eq 0 -and $scriptFiles.Count -gt 0) {
        $managerRoot = Get-ModManagerRoot
        $parserScript = if ($managerRoot) { Join-Path $managerRoot 'Scripts\Vanilla\Test-HoiParser.ps1' } else { $null }
        if ($parserScript -and (Test-Path -LiteralPath $parserScript)) {
            $parserPaths = @($scriptFiles | ForEach-Object { Join-Path $Config.ContentRoot $_ })
            $parseResult = & $parserScript -Path $parserPaths -PassThru
            foreach ($diagnostic in @($parseResult.Diagnostics)) {
                $displayPath = ([string]$diagnostic.File).Replace($Config.RepoDir + '\', '').Replace('\', '/')
                Write-Err ('{0}:{1}: {2}' -f $displayPath, $diagnostic.Line, $diagnostic.Message)
                $problemCount++
            }
        }
    }

    if ($problemCount -eq 0) {
        Write-Ok "$($scriptFiles.Count) script file(s) and $($localisationFiles.Count) localisation file(s) passed the encoding and structure checks"
    }
    return ($problemCount -eq 0)
}

function Copy-ModContent {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    $destinationRoot = (Get-Item -LiteralPath $Destination).FullName.TrimEnd('\')

    $keptNames = [System.Collections.Generic.List[string]]::new()
    foreach ($contentDir in $Config.ContentDirs) {
        $sourceDir = Join-Path $Config.ContentRoot $contentDir
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
            continue
        }
        $keptNames.Add($contentDir)
        & robocopy.exe $sourceDir (Join-Path $destinationRoot $contentDir) /MIR /XF .gitkeep /R:1 /W:1 /NDL /NP /NFL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed for '$contentDir' with exit code $LASTEXITCODE"
        }
    }
    foreach ($contentFileName in $Config.ContentFiles) {
        $sourceFile = Join-Path $Config.ContentRoot $contentFileName
        if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
            $keptNames.Add($contentFileName)
            Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $destinationRoot $contentFileName) -Force
        }
    }
    foreach ($existingItem in @(Get-ChildItem -LiteralPath $destinationRoot -Force)) {
        if ($keptNames -notcontains $existingItem.Name) {
            Remove-Item -LiteralPath $existingItem.FullName -Recurse -Force
        }
    }
    $global:LASTEXITCODE = 0
}

function Test-ModStage {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$StageDir
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $stageRoot = (Get-Item -LiteralPath $StageDir).FullName.TrimEnd('\')
    $developmentExtensions = @('.md', '.ps1', '.psm1', '.psd1', '.py', '.pyc', '.bat', '.cmd', '.sh', '.zip', '.7z', '.vdf', '.bak', '.tmp', '.orig', '.log')

    foreach ($requiredFile in $Config.ContentFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $stageRoot $requiredFile))) {
            $problems.Add("${requiredFile}: missing")
        }
    }

    foreach ($stagedFile in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Force)) {
        $relativePath = $stagedFile.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
        if ($relativePath.IndexOf('/') -lt 0) {
            if ($Config.ContentFiles -notcontains $relativePath) {
                $problems.Add("${relativePath}: not a mod file")
            }
            continue
        }
        $topFolder = $relativePath.Substring(0, $relativePath.IndexOf('/'))
        if ($Config.ContentDirs -notcontains $topFolder) {
            $problems.Add("${relativePath}: outside the content folders ($($Config.ContentDirs -join ', '))")
            continue
        }
        $extension = $stagedFile.Extension.ToLowerInvariant()
        if ($stagedFile.Name -eq '.gitkeep') {
            $problems.Add("${relativePath}: placeholder file")
        } elseif ($developmentExtensions -contains $extension) {
            $problems.Add("${relativePath}: development file")
        } elseif ($extension -eq '.mod') {
            $problems.Add("${relativePath}: launcher file")
        } elseif (@('.txt', '.gui', '.gfx') -contains $extension -and (Test-ModFileHasBom -Path $stagedFile.FullName)) {
            $problems.Add("${relativePath}: starts with a UTF-8 BOM")
        } elseif ($extension -eq '.yml' -and -not (Test-ModFileHasBom -Path $stagedFile.FullName)) {
            $problems.Add("${relativePath}: localisation file without a UTF-8 BOM")
        }
    }
    return , $problems
}

function Write-ModStageProblems {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Problems)

    foreach ($stageProblem in $Problems) {
        Write-Err "Staged content: $stageProblem"
    }
    if (@($Problems).Count -gt 0) {
        Write-Err "The staged content holds $(@($Problems).Count) file(s) that must not ship. Nothing was packaged or uploaded."
    }
}

function Write-ModUncommittedWarning {
    param([Parameter(Mandatory = $true)]$Config)

    $uncommittedFiles = @(Get-ModUncommittedContentFiles -Config $Config)
    if ($uncommittedFiles.Count -eq 0) {
        return
    }
    Write-Warn "$($uncommittedFiles.Count) content file(s) differ from the last commit; they are included as they are on disk:"
    foreach ($uncommittedFile in @($uncommittedFiles | Select-Object -First 10)) {
        Write-Warn "  $uncommittedFile"
    }
    if ($uncommittedFiles.Count -gt 10) {
        Write-Warn "  ... and $($uncommittedFiles.Count - 10) more"
    }
}

function New-ModTempDirectory {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ($Prefix + '_' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    return (Get-Item -LiteralPath $tempPath).FullName.TrimEnd('\')
}

function New-ModZipArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$ZipPath
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceRoot = (Get-Item -LiteralPath $SourceDir).FullName.TrimEnd('\')
    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($sourceFile in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force | Sort-Object FullName)) {
            $entryName = $sourceFile.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourceFile.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $archive.Dispose()
    }
}

function ConvertTo-VdfString {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-ModWorkshopVdf {
    param(
        [Parameter(Mandatory = $true)][string]$ContentDir,
        [Parameter(Mandatory = $true)][string]$PreviewPath,
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowEmptyString()][string]$PublishedFileId,
        [AllowEmptyString()][string]$ChangeNote,
        [AllowEmptyString()][string]$Description
    )

    $vdfFields = [System.Collections.Generic.List[string[]]]::new()
    $vdfFields.Add([string[]]@('appid', '394360'))
    $vdfFields.Add([string[]]@('publishedfileid', $(if ($PublishedFileId) { $PublishedFileId } else { '0' })))
    $vdfFields.Add([string[]]@('contentfolder', ($ContentDir -replace '\\', '/')))
    $vdfFields.Add([string[]]@('previewfile', ($PreviewPath -replace '\\', '/')))
    if (-not $PublishedFileId) {
        $vdfFields.Add([string[]]@('visibility', '2'))
    }
    $vdfFields.Add([string[]]@('title', $Title))
    if ($Description) {
        $vdfFields.Add([string[]]@('description', ($Description -replace "`r`n", "`n")))
    }
    $vdfFields.Add([string[]]@('changenote', [string]$ChangeNote))

    $vdfLines = [System.Collections.Generic.List[string]]::new()
    $vdfLines.Add('"workshopitem"')
    $vdfLines.Add('{')
    foreach ($vdfField in $vdfFields) {
        $vdfLines.Add(('    {0} {1}' -f (ConvertTo-VdfString -Value $vdfField[0]), (ConvertTo-VdfString -Value $vdfField[1])))
    }
    $vdfLines.Add('}')
    return ($vdfLines -join "`r`n")
}

function Get-ModVdfPublishedFileId {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $idMatch = [regex]::Match([System.IO.File]::ReadAllText($Path), '"publishedfileid"\s+"(\d+)"')
    if ($idMatch.Success -and $idMatch.Groups[1].Value -ne '0') {
        return $idMatch.Groups[1].Value
    }
    return $null
}

function Get-ModWorkshopDescription {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not (Test-Path -LiteralPath $Config.GuidelinesPath)) {
        return $null
    }
    $guidelinesText = [System.IO.File]::ReadAllText($Config.GuidelinesPath, [System.Text.Encoding]::UTF8)
    $bbcodeMatch = [regex]::Match($guidelinesText, '(?ms)```bbcode\s*\r?\n(.*?)\r?\n```')
    if ($bbcodeMatch.Success) {
        return $bbcodeMatch.Groups[1].Value
    }
    return $null
}

function Set-ModDescriptorRemoteFileId {
    param(
        [Parameter(Mandatory = $true)][string]$DescriptorPath,
        [Parameter(Mandatory = $true)][string]$RemoteFileId
    )

    $descriptorText = [System.IO.File]::ReadAllText($DescriptorPath, [System.Text.Encoding]::UTF8)
    if ($descriptorText -match '(?m)^\s*remote_file_id\s*=') {
        $descriptorText = [regex]::Replace($descriptorText, '(?m)^(\s*remote_file_id\s*=\s*)"[^"]*"', ('${1}"' + $RemoteFileId + '"'))
    } else {
        $lineBreak = if ($descriptorText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $descriptorText = $descriptorText.TrimEnd("`r", "`n") + $lineBreak + 'remote_file_id="' + $RemoteFileId + '"' + $lineBreak
    }
    [System.IO.File]::WriteAllText($DescriptorPath, $descriptorText, (Get-ModUtf8NoBom))
}

function Set-ModRegistryWorkshopId {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemoteFileId
    )

    $managerRoot = Get-ModManagerRoot
    if (-not $managerRoot) {
        return $false
    }
    $registryPath = Join-Path $managerRoot 'Config\mods_registry.json'
    $parsedRegistry = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $registryEntries = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($registryItem in $parsedRegistry) {
        if ($registryItem.PSObject.Properties['value']) {
            foreach ($wrappedItem in $registryItem.value) {
                $registryEntries.Add($wrappedItem)
            }
        } else {
            $registryEntries.Add($registryItem)
        }
    }
    $entryUpdated = $false
    foreach ($registryEntry in $registryEntries) {
        $entryPath = ([string]$registryEntry.localPath).TrimEnd('\')
        if (-not [System.IO.Path]::IsPathRooted($entryPath)) {
            $entryPath = [System.IO.Path]::GetFullPath((Join-Path $managerRoot $entryPath)).TrimEnd('\')
        }
        if ($entryPath -ieq ([string]$Config.RepoDir).TrimEnd('\')) {
            $registryEntry.steamWorkshopId = $RemoteFileId
            $entryUpdated = $true
        }
    }
    if ($entryUpdated) {
        [System.IO.File]::WriteAllText($registryPath, ((ConvertTo-Json -InputObject @($registryEntries) -Depth 5) + "`r`n"), (Get-ModUtf8NoBom))
    }
    return $entryUpdated
}

function Find-SteamCmd {
    param([string]$CustomPath)

    if ($CustomPath -and (Test-Path -LiteralPath $CustomPath)) {
        return $CustomPath
    }
    $steamCmdCommand = Get-Command -Name 'steamcmd' -ErrorAction SilentlyContinue
    if ($steamCmdCommand) {
        return $steamCmdCommand.Source
    }
    $candidatePaths = @(
        'C:\steamcmd\steamcmd.exe',
        'C:\Program Files (x86)\SteamCMD\steamcmd.exe',
        'C:\Program Files (x86)\Steam\steamcmd.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\steamcmd\steamcmd.exe'),
        (Join-Path $env:USERPROFILE 'steamcmd\steamcmd.exe')
    )
    foreach ($candidatePath in $candidatePaths) {
        if ($candidatePath -and (Test-Path -LiteralPath $candidatePath)) {
            return $candidatePath
        }
    }
    return $null
}

function Install-SteamCmd {
    $installDir = 'C:\steamcmd'
    Write-Step "Installing SteamCMD to $installDir..."
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    $zipPath = Join-Path $installDir 'steamcmd.zip'
    Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile $zipPath -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $installDir)
    Remove-Item -LiteralPath $zipPath -Force
    $steamCmdPath = Join-Path $installDir 'steamcmd.exe'
    Write-Ok "SteamCMD installed at $steamCmdPath"
    return $steamCmdPath
}

function Resolve-ModSteamUser {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$SteamUser,
        [switch]$DryRun
    )

    if ($SteamUser) {
        return $SteamUser
    }
    if ($env:STEAM_USERNAME) {
        return $env:STEAM_USERNAME
    }
    $steamUserFile = Join-Path $Config.RepoDir '.steam_username'
    if (Test-Path -LiteralPath $steamUserFile) {
        $savedUser = ([string][System.IO.File]::ReadAllText($steamUserFile)).Trim()
        if ($savedUser) {
            return $savedUser
        }
    }
    if ($DryRun) {
        return '<steam_username>'
    }
    $enteredUser = ([string](Read-Host 'Enter your Steam account username')).Trim()
    if ($enteredUser) {
        [System.IO.File]::WriteAllText($steamUserFile, $enteredUser, (Get-ModUtf8NoBom))
        Write-Info "Saved the Steam username to $steamUserFile"
    }
    return $enteredUser
}

function Resolve-ModChangeNote {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ChangeNote
    )

    if ($ChangeNote) {
        return $ChangeNote
    }
    if (Test-ModGitRepository -Config $Config) {
        $logArguments = @('log', '-1', '--pretty=%s')
        if ($Config.ContentPrefix) {
            $logArguments += @('--', $Config.ContentPrefix)
        }
        $lastSubject = @(Invoke-ModGit -RepoDir $Config.RepoDir -Arguments $logArguments)
        if ($lastSubject.Count -gt 0 -and $lastSubject[0]) {
            Write-Info "No -ChangeNote: using the last commit subject"
            return [string]$lastSubject[0]
        }
    }
    return $Config.DefaultChangeNote
}

function Invoke-ModClean {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ZipOutput
    )

    Write-Step 'Removing the deployed copy, the launcher file and the release archive...'
    $removablePaths = @(
        (Join-Path $Config.ModDir $Config.ModFolderName),
        (Join-Path $Config.ModDir ($Config.ModFolderName + '.mod')),
        (Join-Path $Config.ArtifactsDir $Config.ZipArchiveName),
        (Join-Path $Config.RepoDir $Config.ZipArchiveName),
        (Join-Path $Config.RepoDir ($Config.ModFolderName + '.mod'))
    )
    if ($ZipOutput) {
        $removablePaths += $ZipOutput
    }
    foreach ($removablePath in $removablePaths) {
        if (Test-Path -LiteralPath $removablePath) {
            Remove-Item -LiteralPath $removablePath -Recurse -Force
            Write-Ok "Removed $removablePath"
        }
    }
    return 0
}

function Invoke-ModDevLink {
    param([Parameter(Mandatory = $true)]$Config)

    Write-Step 'Pointing the launcher at this repository (DevLink)...'
    if (-not (Test-Path -LiteralPath $Config.ModDir)) {
        New-Item -ItemType Directory -Path $Config.ModDir -Force | Out-Null
    }
    $deployedFolder = Join-Path $Config.ModDir $Config.ModFolderName
    if (Test-Path -LiteralPath $deployedFolder) {
        Write-Warn "An old deployed copy exists at $deployedFolder. The launcher no longer loads it; delete the folder when you do not need it."
    }
    $launcherContent = New-LauncherModContent -DescriptorPath $Config.DescriptorPath -TargetModPath $Config.ContentRoot
    $launcherFile = Join-Path $Config.ModDir ($Config.ModFolderName + '.mod')
    [System.IO.File]::WriteAllText($launcherFile, $launcherContent, (Get-ModUtf8NoBom))
    [System.IO.File]::WriteAllText((Join-Path $Config.RepoDir ($Config.ModFolderName + '.mod')), $launcherContent, (Get-ModUtf8NoBom))
    Write-Ok "Launcher file: $launcherFile"
    Write-Ok "Loads: $($Config.ContentRoot)"
    Write-Info 'The game reads the files at start: restart it to see a change.'
    return 0
}

function Invoke-ModDeploy {
    param([Parameter(Mandatory = $true)]$Config)

    Write-Step 'Deploying a copy to the launcher mod folder...'
    if (-not (Test-Path -LiteralPath $Config.ModDir)) {
        New-Item -ItemType Directory -Path $Config.ModDir -Force | Out-Null
    }
    $launcherFile = Join-Path $Config.ModDir ($Config.ModFolderName + '.mod')
    $targetFolder = Join-Path $Config.ModDir $Config.ModFolderName
    $currentTarget = Get-ModLauncherTarget -LauncherFilePath $launcherFile
    if ($currentTarget -and $currentTarget -ieq $Config.ContentRoot) {
        Write-Warn "This replaces the active DevLink: the game will load the copy in $targetFolder, not this repository, until build.ps1 -DevLink runs again."
    }

    Copy-ModContent -Config $Config -Destination $targetFolder
    $launcherContent = New-LauncherModContent -DescriptorPath $Config.DescriptorPath -TargetModPath $targetFolder
    [System.IO.File]::WriteAllText($launcherFile, $launcherContent, (Get-ModUtf8NoBom))

    $deployedCount = @(Get-ChildItem -LiteralPath $targetFolder -Recurse -File -Force).Count
    Write-Ok "Deployed $deployedCount file(s) to $targetFolder"
    Write-Ok "Launcher file: $launcherFile"
    return 0
}

function Invoke-ModPackage {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ZipOutput
    )

    Write-Step 'Packaging the release archive...'
    if (-not (Test-Path -LiteralPath $Config.ArtifactsDir)) {
        New-Item -ItemType Directory -Path $Config.ArtifactsDir -Force | Out-Null
    }
    $zipTarget = Join-Path $Config.ArtifactsDir $Config.ZipArchiveName
    if ($ZipOutput) {
        $zipTarget = if ([System.IO.Path]::IsPathRooted($ZipOutput)) { $ZipOutput } else { Join-Path $Config.ArtifactsDir $ZipOutput }
    }
    Write-ModUncommittedWarning -Config $Config

    $stageRoot = New-ModTempDirectory -Prefix 'hoi4_package'
    try {
        $contentDir = $stageRoot
        if ($Config.PackageLayout -eq 'ModFolder') {
            $contentDir = Join-Path $stageRoot $Config.ModFolderName
        }
        Copy-ModContent -Config $Config -Destination $contentDir
        $stageProblems = Test-ModStage -Config $Config -StageDir $contentDir
        if ($stageProblems.Count -gt 0) {
            Write-ModStageProblems -Problems $stageProblems
            return 1
        }
        if ($Config.PackageLayout -eq 'ModFolder') {
            $launcherContent = New-LauncherModContent -DescriptorPath $Config.DescriptorPath -TargetModPath ('mod/' + $Config.ModFolderName)
            [System.IO.File]::WriteAllText((Join-Path $stageRoot ($Config.ModFolderName + '.mod')), $launcherContent, (Get-ModUtf8NoBom))
        }
        New-ModZipArchive -SourceDir $stageRoot -ZipPath $zipTarget
        $packagedCount = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Force).Count
        $archiveSize = [Math]::Round((Get-Item -LiteralPath $zipTarget).Length / 1KB, 1)
        Write-Ok "Package created: $zipTarget ($packagedCount file(s), $archiveSize KB)"
    } finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
    return 0
}

function Invoke-ModPublish {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$SteamUser,
        [string]$ChangeNote,
        [string]$SteamCmdPath,
        [switch]$DryRun,
        [switch]$UpdateDescription
    )

    Write-Step 'Preparing the Steam Workshop upload...'
    $metadata = Get-ModMetadata -Path $Config.DescriptorPath
    $remoteFileId = $metadata.RemoteFileId
    if (-not $remoteFileId) {
        Write-Warn 'descriptor.mod has no remote_file_id: the upload creates a new Workshop item, hidden until you change its visibility on the Workshop page.'
    }
    $thumbnailPath = Join-Path $Config.ContentRoot 'thumbnail.png'
    if ((Test-Path -LiteralPath $thumbnailPath) -and (Get-Item -LiteralPath $thumbnailPath).Length -gt 1MB) {
        Write-Err 'thumbnail.png is larger than 1 MB, the Steam Workshop limit for a preview image.'
        return 1
    }
    Write-ModUncommittedWarning -Config $Config

    $steamCmd = Find-SteamCmd -CustomPath $SteamCmdPath
    if (-not $steamCmd) {
        if (-not $DryRun) {
            Write-Err 'SteamCMD was not found. Run build.ps1 -InstallSteamCmd, or pass -SteamCmdPath.'
            return 1
        }
        $steamCmd = 'steamcmd.exe'
    }
    $resolvedUser = Resolve-ModSteamUser -Config $Config -SteamUser $SteamUser -DryRun:$DryRun
    if (-not $resolvedUser) {
        Write-Err 'A Steam username is needed to upload.'
        return 1
    }
    $resolvedNote = Resolve-ModChangeNote -Config $Config -ChangeNote $ChangeNote
    $description = $null
    if ($UpdateDescription) {
        $description = Get-ModWorkshopDescription -Config $Config
        if (-not $description) {
            Write-Err 'No ```bbcode block in WORKSHOP_DESCRIPTION_GUIDELINES.md to use as the Workshop description.'
            return 1
        }
        Write-Info "The Workshop description is replaced with the bbcode block of WORKSHOP_DESCRIPTION_GUIDELINES.md ($($description.Length) characters)."
    }

    $staleStageCutoff = (Get-Date).AddHours(-1)
    foreach ($staleStage in @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'hoi4_workshop_*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $staleStageCutoff })) {
        Remove-Item -LiteralPath $staleStage.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    $stageRoot = New-ModTempDirectory -Prefix 'hoi4_workshop'
    $keepStage = $false
    try {
        $contentDir = Join-Path $stageRoot 'content'
        Copy-ModContent -Config $Config -Destination $contentDir
        $stageProblems = Test-ModStage -Config $Config -StageDir $contentDir
        if ($stageProblems.Count -gt 0) {
            Write-ModStageProblems -Problems $stageProblems
            return 1
        }

        $vdfPath = Join-Path $stageRoot 'workshop_build.vdf'
        $vdfContent = New-ModWorkshopVdf -ContentDir $contentDir -PreviewPath (Join-Path $contentDir 'thumbnail.png') -Title $metadata.Name -PublishedFileId $remoteFileId -ChangeNote $resolvedNote -Description $description
        [System.IO.File]::WriteAllText($vdfPath, $vdfContent, (Get-ModUtf8NoBom))
        Write-Info "Staged content at: $contentDir"
        Write-Info "VDF: $vdfPath"

        if ($DryRun) {
            $keepStage = $true
            Write-Step '[DryRun] Workshop VDF:'
            Write-Host $vdfContent -ForegroundColor Yellow
            Write-Step '[DryRun] Files that would be uploaded:'
            foreach ($stagedFile in @(Get-ChildItem -LiteralPath $contentDir -Recurse -File -Force | Sort-Object FullName)) {
                Write-Host ('  ' + $stagedFile.FullName.Substring($contentDir.Length + 1).Replace('\', '/')) -ForegroundColor Gray
            }
            Write-Step '[DryRun] Command:'
            Write-Host ('& "' + $steamCmd + '" +login ' + $resolvedUser + ' +workshop_build_item "' + $vdfPath + '" +quit') -ForegroundColor Cyan
            Write-Ok 'Dry run: nothing was uploaded. The stage is kept for inspection.'
            return 0
        }

        Write-Step 'Running SteamCMD...'
        Write-Info 'SteamCMD may ask for your password or a Steam Guard code.'
        $steamCmdArguments = '+login ' + $resolvedUser + ' +workshop_build_item "' + $vdfPath + '" +quit'
        $steamCmdProcess = Start-Process -FilePath $steamCmd -ArgumentList $steamCmdArguments -NoNewWindow -Wait -PassThru
        $steamCmdExitCode = $steamCmdProcess.ExitCode
        if ($steamCmdExitCode -ne 0) {
            Write-Err "SteamCMD exited with code $steamCmdExitCode"
            return $steamCmdExitCode
        }

        $publishedId = $remoteFileId
        if (-not $remoteFileId) {
            $publishedId = Get-ModVdfPublishedFileId -Path $vdfPath
            if ($publishedId) {
                Set-ModDescriptorRemoteFileId -DescriptorPath $Config.DescriptorPath -RemoteFileId $publishedId
                Write-Ok "New Workshop item $publishedId written to descriptor.mod as remote_file_id"
                if (-not $Config.PackageName -and (Set-ModRegistryWorkshopId -Config $Config -RemoteFileId $publishedId)) {
                    Write-Ok 'steamWorkshopId updated in the Modding Manager registry'
                }
            } else {
                Write-Warn 'SteamCMD did not write the new item id into the VDF: add remote_file_id to descriptor.mod from the Workshop page.'
            }
        }
        Write-Ok 'Steam Workshop upload finished.'
        if ($publishedId) {
            Write-Info "https://steamcommunity.com/sharedfiles/filedetails/?id=$publishedId"
        }
        return 0
    } finally {
        if (-not $keepStage -and (Test-Path -LiteralPath $stageRoot)) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
}

function Invoke-ModTests {
    param([Parameter(Mandatory = $true)]$Config)

    $testRunner = Join-Path $Config.RepoDir 'tests\Run-Tests.ps1'
    if (-not (Test-Path -LiteralPath $testRunner)) {
        Write-Err "Test runner not found: $testRunner"
        return 1
    }
    & $testRunner | Out-Host
    return $LASTEXITCODE
}

function Invoke-ModFullValidation {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [scriptblock]$ExtraValidation,
        [object[]]$PackageConfigs
    )

    if (-not $PackageConfigs) {
        $PackageConfigs = @($Config)
    }
    $engineChecksPassed = $true
    foreach ($packageConfig in $PackageConfigs) {
        if (-not (Invoke-ModValidation -Config $packageConfig)) {
            $engineChecksPassed = $false
        }
    }
    $extraChecksPassed = $true
    if ($ExtraValidation) {
        $extraResults = @(& $ExtraValidation)
        $extraChecksPassed = ($extraResults.Count -gt 0 -and [bool]$extraResults[-1])
    }
    return ($engineChecksPassed -and $extraChecksPassed)
}

function Invoke-ModBuildAction {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [scriptblock]$ExtraValidation,
        [switch]$Deploy,
        [switch]$DevLink,
        [switch]$Package,
        [switch]$PublishSteam,
        [switch]$InstallSteamCmd,
        [switch]$ValidateOnly,
        [switch]$Test,
        [switch]$Validate,
        [switch]$NoValidate,
        [switch]$Clean,
        [string]$ZipOutput,
        [string]$SteamUser,
        [string]$ChangeNote,
        [string]$SteamCmdPath,
        [switch]$DryRun,
        [switch]$UpdateDescription,
        [string]$Pack
    )

    if ($InstallSteamCmd) {
        Install-SteamCmd | Out-Null
        return 0
    }
    try {
        $selectedConfigs = @(Get-ModSelectedConfigs -Config $Config -Pack $Pack)
    } catch {
        Write-Err $_.Exception.Message
        return 1
    }
    if ($ValidateOnly) {
        if (Invoke-ModFullValidation -Config $Config -ExtraValidation $ExtraValidation -PackageConfigs $selectedConfigs) {
            Write-Host "`nValidation succeeded." -ForegroundColor Green
            return 0
        }
        Write-Host "`nValidation failed!" -ForegroundColor Red
        return 1
    }
    if ($Test) {
        return (Invoke-ModTests -Config $Config)
    }
    if ($PublishSteam -and $selectedConfigs.Count -gt 1) {
        Write-Err "An upload is one Workshop item: pass -Pack with one of the packages ($($Config.PackageNames -join ', '))."
        return 1
    }
    if ($ZipOutput -and $selectedConfigs.Count -gt 1) {
        Write-Err '-ZipOutput names one archive: pass -Pack to package one of the packages.'
        return 1
    }
    $shouldValidate = $Validate -or (-not $NoValidate -and -not $Clean)
    if ($shouldValidate -and -not (Invoke-ModFullValidation -Config $Config -ExtraValidation $ExtraValidation -PackageConfigs $selectedConfigs)) {
        Write-Err 'Validation failed. Nothing was deployed, packaged or uploaded.'
        return 1
    }
    $worstExitCode = 0
    foreach ($selectedConfig in $selectedConfigs) {
        if ($selectedConfig.PackageName) {
            Write-Step "Package '$($selectedConfig.PackageName)' ($($selectedConfig.ContentPrefix.TrimEnd('/')))"
        }
        $actionOutput = if ($Clean) {
            Invoke-ModClean -Config $selectedConfig -ZipOutput $ZipOutput
        } elseif ($DevLink) {
            Invoke-ModDevLink -Config $selectedConfig
        } elseif ($Package) {
            Invoke-ModPackage -Config $selectedConfig -ZipOutput $ZipOutput
        } elseif ($PublishSteam) {
            Invoke-ModPublish -Config $selectedConfig -SteamUser $SteamUser -ChangeNote $ChangeNote -SteamCmdPath $SteamCmdPath -DryRun:$DryRun -UpdateDescription:$UpdateDescription
        } else {
            Invoke-ModDeploy -Config $selectedConfig
        }
        $actionExitCode = [int](@($actionOutput)[-1])
        if ($actionExitCode -ne 0 -and $worstExitCode -eq 0) {
            $worstExitCode = $actionExitCode
        }
    }
    return $worstExitCode
}

function Invoke-ModBuild {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [scriptblock]$ExtraValidation,
        [switch]$Deploy,
        [switch]$DevLink,
        [switch]$Package,
        [switch]$PublishSteam,
        [switch]$InstallSteamCmd,
        [switch]$ValidateOnly,
        [switch]$Test,
        [switch]$Validate,
        [switch]$NoValidate,
        [switch]$Clean,
        [string]$ZipOutput,
        [string]$SteamUser,
        [string]$ChangeNote,
        [string]$SteamCmdPath,
        [switch]$DryRun,
        [switch]$UpdateDescription,
        [string]$Pack
    )

    $buildStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $actionParameters = @{}
    foreach ($boundName in @($PSBoundParameters.Keys)) {
        $actionParameters[$boundName] = $PSBoundParameters[$boundName]
    }
    $exitCode = [int](@(Invoke-ModBuildAction @actionParameters)[-1])
    $buildStopwatch.Stop()
    Write-Info ('Finished in {0}s' -f $buildStopwatch.Elapsed.TotalSeconds.ToString('0.00'))
    return $exitCode
}
