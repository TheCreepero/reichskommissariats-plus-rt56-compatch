BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:AuditScript = $null
    $treeCandidate = Join-Path $PSScriptRoot '..\..\..\Scripts\Knowledge\Test-HoiKnowledge.ps1'
    if (Test-Path -LiteralPath $treeCandidate) {
        $script:AuditScript = [System.IO.Path]::GetFullPath($treeCandidate)
    }
    $pointerPaths = @(
        (Join-Path $HOME '.claude\skills\hoi4-modding-knowledge\manager-root.txt'),
        (Join-Path $HOME '.gemini\config\skills\hoi4-modding-knowledge\manager-root.txt')
    )
    foreach ($pointerPath in $pointerPaths) {
        if ($script:AuditScript -or -not (Test-Path -LiteralPath $pointerPath)) {
            continue
        }
        $managerRoot = [System.IO.File]::ReadAllText($pointerPath).Trim()
        $candidateScript = Join-Path $managerRoot 'Scripts\Knowledge\Test-HoiKnowledge.ps1'
        if (Test-Path -LiteralPath $candidateScript) {
            $script:AuditScript = $candidateScript
        }
    }
}

Describe 'Central knowledge register' {
    It 'AGENTS.md sends agents to the central register' {
        $ruleText = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'AGENTS.md'), [System.Text.Encoding]::UTF8)
        $ruleText | Should -Match '(?m)^##\s+(\d+\.\s+)?Engine Knowledge\s*$'
        $ruleText | Should -Match 'hoi4-modding-knowledge'
    }

    It 'CLAUDE.md and GEMINI.md point to AGENTS.md' {
        $claudePath = Join-Path $script:RepoRoot 'CLAUDE.md'
        $geminiPath = Join-Path $script:RepoRoot 'GEMINI.md'
        Test-Path -LiteralPath $claudePath | Should -BeTrue
        Test-Path -LiteralPath $geminiPath | Should -BeTrue
        [System.IO.File]::ReadAllText($claudePath, [System.Text.Encoding]::UTF8) | Should -Match '(?m)^@AGENTS\.md\s*$'
        [System.IO.File]::ReadAllText($geminiPath, [System.Text.Encoding]::UTF8) | Should -Match '(?m)^@AGENTS\.md\s*$'
    }

    It 'has no blocking finding in the knowledge audit' {
        if (-not $script:AuditScript) {
            Set-ItResult -Skipped -Because 'the Modding Manager is not installed on this machine'
            return
        }
        $blockingFindings = @(& $script:AuditScript -Repo $script:RepoRoot -PassThru | Where-Object { $_.Blocking })
        $findingLines = @($blockingFindings | ForEach-Object { '{0}:{1} {2}' -f $_.File, $_.Line, $_.Message })
        $findingLines | Should -BeNullOrEmpty -Because 'engine facts live in the central register (hoi4-modding-knowledge skill); a stale wiki region is regenerated with Export-HoiKnowledge.ps1'
    }
}
