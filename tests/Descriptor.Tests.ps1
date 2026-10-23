BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $script:DescriptorPath = Join-Path $script:RepoRoot "descriptor.mod"
    $script:ThumbnailPath = Join-Path $script:RepoRoot "thumbnail.png"
}

Describe "descriptor.mod Invariants" {
    It "descriptor.mod exists" {
        Test-Path $script:DescriptorPath | Should -Be $true
    }

    It "descriptor.mod is saved without UTF-8 BOM" {
        $bytes = [System.IO.File]::ReadAllBytes($script:DescriptorPath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -Be $false
    }

    It "descriptor.mod has valid name matching mod configuration" {
        $content = [System.IO.File]::ReadAllText($script:DescriptorPath, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'name\s*=\s*"([^"]+)"'
    }

    It "descriptor.mod has supported_version matching semver pattern" {
        $content = [System.IO.File]::ReadAllText($script:DescriptorPath, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'supported_version\s*=\s*"\d+\.\d+(\.\*|\.\d+)?"'
    }

    It "descriptor.mod specifies picture attribute and thumbnail file exists" {
        $content = [System.IO.File]::ReadAllText($script:DescriptorPath, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'picture\s*=\s*"thumbnail\.png"'
        Test-Path $script:ThumbnailPath | Should -Be $true
    }
}