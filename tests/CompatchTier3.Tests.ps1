BeforeAll {
    $script:CompatchRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Describe 'Compatch Tier 3 Validation' {
    Context 'Encoding Checks' {
        It 'Ensures all .txt files under common and events have no UTF-8 BOM [ENC-001]' {
            $checkDirs = @(
                (Join-Path $script:CompatchRoot 'common'),
                (Join-Path $script:CompatchRoot 'events')
            )
            $txtFiles = @(Get-ChildItem -Path $checkDirs -Filter '*.txt' -Recurse -File -ErrorAction SilentlyContinue)
            foreach ($file in $txtFiles) {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                $hasBom | Should -BeFalse -Because "File $($file.FullName) must not have UTF-8 BOM"
            }
        }

        It 'Ensures all .yml files in localisation have UTF-8 BOM [LOC-001]' {
            $locDir = Join-Path $script:CompatchRoot 'localisation'
            if (Test-Path $locDir) {
                $ymlFiles = @(Get-ChildItem -Path $locDir -Filter '*.yml' -Recurse -File -ErrorAction SilentlyContinue)
                foreach ($file in $ymlFiles) {
                    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                    $hasBom | Should -BeTrue -Because "Localisation file $($file.FullName) must have UTF-8 BOM"
                }
            }
        }
    }

    Context 'Focus Tree Syntax & Structure' {
        It 'Validates balanced braces on all compatch focus trees' {
            $focusDir = Join-Path $script:CompatchRoot 'common\national_focus'
            if (Test-Path $focusDir) {
                $focusFiles = @(Get-ChildItem -Path $focusDir -Filter '*.txt' -Recurse -File -ErrorAction SilentlyContinue)
                foreach ($file in $focusFiles) {
                    $content = [System.IO.File]::ReadAllText($file.FullName)
                    $openBraces = ($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                    $closeBraces = ($content.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                    $openBraces | Should -Be $closeBraces -Because "Braces in $($file.Name) must be balanced"
                }
            }
        }
    }

    Context 'On-Actions and Decisions Integrity' {
        It 'Validates balanced braces on all on_actions and decisions' {
            $scriptDirs = @(
                (Join-Path $script:CompatchRoot 'common\on_actions'),
                (Join-Path $script:CompatchRoot 'common\decisions')
            )
            foreach ($dir in $scriptDirs) {
                if (Test-Path $dir) {
                    $files = @(Get-ChildItem -Path $dir -Filter '*.txt' -Recurse -File -ErrorAction SilentlyContinue)
                    foreach ($file in $files) {
                        $content = [System.IO.File]::ReadAllText($file.FullName)
                        $openBraces = ($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                        $closeBraces = ($content.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                        $openBraces | Should -Be $closeBraces -Because "Braces in $($file.Name) must be balanced"
                    }
                }
            }
        }
    }

    Context 'Non-fascist Germany Gate' {
        It 'Defines the shared Germany gate trigger as fascism or neutrality' {
            $triggerText = [System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot 'common\scripted_triggers\rkplus_rt56_scripted_triggers.txt'))
            $triggerText | Should -Match 'rkplus_ger_can_run_rks\s*=\s*\{'
            $triggerText | Should -Match 'has_government = fascism'
            $triggerText | Should -Match 'has_government = neutrality'
        }

        It 'Leaves no bare fascism government check in the release decisions, colonial decisions or German AI files' {
            $gatedFiles = @(
                'common\decisions\reichskommissariat.txt',
                'common\decisions\rkplus_rt56_colonial_decisions.txt',
                'common\ai_strategy\GER_rkplus_ai_strategy.txt',
                'common\ai_strategy_plans\GER_rkplus_historical_plan.txt'
            )
            foreach ($relativePath in $gatedFiles) {
                $content = [System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot $relativePath))
                $content | Should -Not -Match 'has_government = fascism' -Because "$relativePath must use rkplus_ger_can_run_rks"
                $content | Should -Match 'rkplus_ger_can_run_rks = yes'
            }
        }

        It 'Uses the shared gate in the Reichskommissariats placeholder category and keeps the vanilla categories' {
            $content = [System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot 'common\decisions\categories\GER_decision_categories.txt'))
            $blockMatch = [regex]::Match($content, '(?s)^GER_reichskommissariats = \{.*?\r?\n\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $blockMatch.Success | Should -BeTrue
            $blockMatch.Value | Should -Match 'rkplus_ger_can_run_rks = yes'
            $blockMatch.Value | Should -Not -Match 'has_government = fascism'
            $content | Should -Match 'GER_case_anton_category'
        }

        It 'Sets the startup flag and aligns puppet ideology for neutrality Germany in on_weekly_GER' {
            $content = [System.IO.File]::ReadAllText((Join-Path $script:CompatchRoot 'common\on_actions\rkplus_rt56_on_actions.txt'))
            $content | Should -Match 'rkplus_rt56_neutral_unlock_handled'
            $content | Should -Match 'set_country_flag = GER_rksplus_startup_event_enable'
            $content | Should -Match 'has_autonomy_state = autonomy_reichskommissariat'
            $content | Should -Match 'set_politics = \{ ruling_party = neutrality \}'
        }
    }
}
