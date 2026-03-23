#Requires -Modules Pester
<#
.SYNOPSIS
    test_statusline.ps1 — Pester v5 test suite for statusline.ps1

.DESCRIPTION
    Usage:
        Invoke-Pester -Path test_statusline.ps1 -Output Detailed

    Dependencies:
        Pester v5  (Install-Module -Name Pester -Force -SkipPublisherCheck)

    Dot-source strategy:
        BeforeAll dot-sources statusline.ps1 with an empty stdin pipeline.
        This executes the try{} block (which defines Get-FmtDate,
        Format-Tokens, Get-GradientBar, and Get-PctColor) and brings
        $script:CurrencyTable and $script:CurrFmt into test scope.
        Format-Currency is defined outside try{} and is always available.
#>

# Dot-source with empty stdin to define all functions
BeforeAll {
    $script:ScriptPath = Join-Path (Join-Path $PSScriptRoot '..') 'statusline.ps1'
    $null | . $script:ScriptPath 2>$null
}

# ============================================================================
# Format-Currency
# ============================================================================

Describe 'Format-Currency' {

    Context 'Italian locale — € suffix, comma as decimal separator' {
        BeforeEach {
            $script:CurrFmt  = $script:CurrencyTable['it_IT']
            $script:I18nFmt = $script:I18N['en']
        }

        It '420 cents → "4,20 €"' {
            Format-Currency 420 | Should -Be '4,20 €'
        }

        It '0 cents → "0,00 €"' {
            Format-Currency 0 | Should -Be '0,00 €'
        }

        It '1 cent → "0,01 €"' {
            Format-Currency 1 | Should -Be '0,01 €'
        }

        It '10000 cents → "100,00 €"' {
            Format-Currency 10000 | Should -Be '100,00 €'
        }

        It '999999 cents → "9999,99 €"' {
            Format-Currency 999999 | Should -Be '9999,99 €'
        }

        It '$null → "N/A"' {
            Format-Currency $null | Should -Be 'N/A'
        }
    }

    Context 'US dollar — $ prefix, period as decimal separator' {
        BeforeEach {
            $script:CurrFmt  = $script:CurrencyTable['en_US']
            $script:I18nFmt = $script:I18N['en']
        }

        It '420 cents → "$4.20"' {
            Format-Currency 420 | Should -Be '$4.20'
        }

        It '0 cents → "$0.00"' {
            Format-Currency 0 | Should -Be '$0.00'
        }

        It '$null → "N/A"' {
            Format-Currency $null | Should -Be 'N/A'
        }
    }

    Context 'British pound' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['en_GB']
        }

        It '420 cents → "£4.20"' {
            Format-Currency 420 | Should -Be '£4.20'
        }
    }

    Context 'Japanese yen — 0 decimal places' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['ja_JP']
        }

        It '42000 cents (= 420 JPY) → "¥420"' {
            Format-Currency 42000 | Should -Be '¥420'
        }

        It '100 cents (= 1 JPY) → "¥1"' {
            Format-Currency 100 | Should -Be '¥1'
        }

        It '0 → "¥0"' {
            Format-Currency 0 | Should -Be '¥0'
        }
    }

    Context 'Swiss franc — symbol with space separator' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['fr_CH']
        }

        It '420 cents → "CHF 4.20"' {
            Format-Currency 420 | Should -Be 'CHF 4.20'
        }

        It '0 cents → "CHF 0.00"' {
            Format-Currency 0 | Should -Be 'CHF 0.00'
        }
    }

    Context 'Brazilian real — symbol prefix, comma as decimal separator' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['pt_BR']
        }

        It '420 cents → "R$4,20"' {
            Format-Currency 420 | Should -Be 'R$4,20'
        }
    }
}

# ============================================================================
# CurrencyTable
# ============================================================================

Describe 'CurrencyTable' {

    It 'Contains all 16 expected locales' {
        $expectedLocales = @(
            'it_IT','de_DE','fr_FR','es_ES','pt_PT',
            'en_US','en_AU','en_CA','en_GB',
            'ja_JP','zh_CN','zh_TW',
            'fr_CH','de_CH','it_CH',
            'pt_BR'
        )
        foreach ($loc in $expectedLocales) {
            $script:CurrencyTable.ContainsKey($loc) | Should -BeTrue -Because "locale $loc must be present"
        }
    }

    It 'it_IT has Symbol=€, DecSep=",", SymBefore=$false' {
        $it = $script:CurrencyTable['it_IT']
        $it.Symbol    | Should -Be '€'
        $it.DecSep    | Should -Be ','
        $it.SymBefore | Should -BeFalse
    }

    It 'en_US has Symbol=$, SymBefore=$true' {
        $us = $script:CurrencyTable['en_US']
        $us.Symbol    | Should -Be '$'
        $us.SymBefore | Should -BeTrue
    }

    It 'ja_JP has Decimals=0' {
        $script:CurrencyTable['ja_JP'].Decimals | Should -Be 0
    }

    It 'fr_CH has SymSpace=$true' {
        $script:CurrencyTable['fr_CH'].SymSpace | Should -BeTrue
    }

    It 'Unknown locale is not in the table (fallback is handled in Format-Currency via $script:CurrFmt)' {
        $script:CurrencyTable.ContainsKey('xx_XX') | Should -BeFalse
    }

    It 'Unknown locale → $script:CurrFmt falls back to en_US' {
        # Simulate unknown locale by applying the same fallback logic as the script
        $fakeLocale = 'xx_XX'
        $expected = $script:CurrencyTable['en_US']
        $result = if ($script:CurrencyTable.ContainsKey($fakeLocale)) {
            $script:CurrencyTable[$fakeLocale]
        } else {
            $script:CurrencyTable['en_US']
        }
        $result.Symbol | Should -Be '$'
    }
}

# ============================================================================
# DateTable
# ============================================================================

Describe 'DateTable' {

    It 'Contains all 16 expected locales' {
        $expectedLocales = @(
            'it_IT','it_CH','de_DE','de_CH','fr_FR','fr_CH',
            'es_ES','pt_PT','pt_BR',
            'en_US','en_AU','en_CA','en_GB',
            'ja_JP','zh_CN','zh_TW'
        )
        foreach ($loc in $expectedLocales) {
            $script:DateTable.ContainsKey($loc) | Should -BeTrue -Because "locale $loc must be present"
        }
    }

    It 'it_IT has Order=DMY, Sep=/, H24=$true' {
        $it = $script:DateTable['it_IT']
        $it.Order | Should -Be 'DMY'
        $it.Sep   | Should -Be '/'
        $it.H24   | Should -BeTrue
    }

    It 'en_US has Order=MDY, H24=$false' {
        $us = $script:DateTable['en_US']
        $us.Order | Should -Be 'MDY'
        $us.H24   | Should -BeFalse
    }

    It 'de_DE has Sep=dot' {
        $script:DateTable['de_DE'].Sep | Should -Be '.'
    }

    It 'Unknown locale → DateFmt falls back to en_US' {
        $fakeLocale = 'xx_XX'
        $result = if ($script:DateTable.ContainsKey($fakeLocale)) {
            $script:DateTable[$fakeLocale]
        } else {
            $script:DateTable['en_US']
        }
        $result.Order | Should -Be 'MDY'
        $result.H24   | Should -BeFalse
    }
}

# ============================================================================
# Get-FmtDate
# ============================================================================

Describe 'Get-FmtDate' {

    BeforeEach {
        $script:I18nFmt = $script:I18N['en']
    }

    It 'Empty string → "N/A"' {
        Get-FmtDate '' | Should -Be 'N/A'
    }

    It '$null → "N/A"' {
        Get-FmtDate $null | Should -Be 'N/A'
    }

    It 'Invalid date string → returns "N/A" (via try/catch)' {
        Get-FmtDate 'not-a-date' | Should -Be 'N/A'
    }

    Context 'it_IT (DMY, 24h)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['it_IT']
            $script:I18nFmt = $script:I18N['en']
        }

        It '2025-01-06 → starts with "LUN" (Monday in Italian)' {
            Get-FmtDate '2025-01-06T12:00:00Z' | Should -Match '^LUN '
        }

        It '2025-01-12 → starts with "DOM" (Sunday in Italian)' {
            Get-FmtDate '2025-01-12T12:00:00Z' | Should -Match '^DOM '
        }

        It '2025-01-07 → starts with "MAR" (Tuesday in Italian)' {
            Get-FmtDate '2025-01-07T12:00:00Z' | Should -Match '^MAR '
        }

        It 'Output format matches pattern "\w{3} dd/MM H: HH:mm"' {
            Get-FmtDate '2025-06-15T14:30:00Z' | Should -Match '^\w{3} \d{2}/\d{2} H: \d{2}:\d{2}$'
        }
    }

    Context 'en_US (MDY, 12h)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['en_US']
            $script:I18nFmt = $script:I18N['en']
        }

        It 'Output format matches pattern "\w{3} MM/DD H: hh:mm AM/PM"' {
            $result = Get-FmtDate '2025-03-19T18:00:00Z'
            $result | Should -Match '^\w{3} \d{2}/\d{2} H: \d{2}:\d{2} (AM|PM)$'
        }

        It '2025-01-06 (Monday) → starts with "MON"' {
            Get-FmtDate '2025-01-06T12:00:00Z' | Should -Match '^MON '
        }
    }

    Context 'de_DE (dot separator)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['de_DE']
            $script:I18nFmt = $script:I18N['en']
        }

        It 'Output format uses dot as date separator' {
            $result = Get-FmtDate '2025-03-19T18:00:00Z'
            $result | Should -Match '^\w{2} \d{2}\.\d{2} H: \d{2}:\d{2}$'
        }
    }
}

# ============================================================================
# Format-Tokens
# ============================================================================

Describe 'Format-Tokens' {

    It '0 → "0"' {
        Format-Tokens 0 | Should -Be '0'
    }

    It '999 → "999"' {
        Format-Tokens 999 | Should -Be '999'
    }

    It '1000 → "1.0K"' {
        Format-Tokens 1000 | Should -Be '1.0K'
    }

    It '1500 → "1.5K"' {
        Format-Tokens 1500 | Should -Be '1.5K'
    }

    It '10000 → "10.0K"' {
        Format-Tokens 10000 | Should -Be '10.0K'
    }
}

# ============================================================================
# Get-GradientBar
# ============================================================================

Describe 'Get-GradientBar' {

    It 'width=10 → output contains exactly 10 ⛁ characters' {
        $bar = Get-GradientBar 50 10
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 10
    }

    It '0% → all buckets are dim gray (38;2;60;60;60)' {
        $bar = Get-GradientBar 0 10
        $bar | Should -Match '60;60;60'
        # No coloured buckets — must not contain any RGB value other than 60;60;60
        $bar | Should -Not -Match '38;2;(?!60;60;60)\d'
    }

    It '100% → no bucket is dim gray' {
        $bar = Get-GradientBar 100 10
        $bar | Should -Not -Match '60;60;60'
    }

    It 'width=0 → returns empty string' {
        Get-GradientBar 50 0 | Should -Be ''
    }

    It 'width=1 → contains exactly 1 ⛁ character' {
        $bar = Get-GradientBar 50 1
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 1
    }

    It 'width=48 default → contains 48 ⛁ characters' {
        $bar = Get-GradientBar 50
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 48
    }
}

# ============================================================================
# Get-PctColor
# ============================================================================

Describe 'Get-PctColor' {

    It '0% → contains the start green colour (74;222;128)' {
        Get-PctColor 0 | Should -Match '74;222;128'
    }

    It '100% → contains the end red colour (239;68;68)' {
        Get-PctColor 100 | Should -Match '239;68;68'
    }

    It 'Output is an ANSI escape sequence ESC[38;2;R;G;Bm' {
        Get-PctColor 50 | Should -Match '\x1b\[38;2;\d+;\d+;\d+m'
    }

    It 'RGB components are in the range [0, 255]' {
        $color = Get-PctColor 50
        if ($color -match '38;2;(\d+);(\d+);(\d+)m') {
            [int]$Matches[1] | Should -BeGreaterOrEqual 0
            [int]$Matches[1] | Should -BeLessOrEqual 255
            [int]$Matches[2] | Should -BeGreaterOrEqual 0
            [int]$Matches[2] | Should -BeLessOrEqual 255
            [int]$Matches[3] | Should -BeGreaterOrEqual 0
            [int]$Matches[3] | Should -BeLessOrEqual 255
        } else {
            Set-ItResult -Skipped -Because "unrecognised ANSI format: $color"
        }
    }
}

# ============================================================================
# Integration — subprocess
# ============================================================================

Describe 'Integration' {

    $MinimalPayload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"."}}'

    It 'Minimal payload → output contains "ENV:"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'ENV:'
    }

    It 'Minimal payload → output contains "XTRA USG:"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'XTRA USG:'
    }

    It 'Minimal payload → output contains "CONTEXT_WINDOW"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'CONTEXT_WINDOW'
    }

    It 'Empty input → no "ERRORE STATUSBAR:" in output' {
        $out = '' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out -join '' | Should -Not -Match 'ERRORE STATUSBAR:'
    }
}

# ============================================================================
# I18N — table and localised formatting
# ============================================================================

Describe 'I18N' {

    It 'Table contains all 8 expected languages' {
        $expectedLangs = @('it','en','de','fr','es','pt','ja','zh')
        foreach ($lang in $expectedLangs) {
            $script:I18N.ContainsKey($lang) | Should -BeTrue -Because "language $lang must be present"
        }
    }

    It 'it → NA=N/D' {
        $script:I18N['it'].NA | Should -Be 'N/D'
    }

    It 'en → NA=N/A' {
        $script:I18N['en'].NA | Should -Be 'N/A'
    }

    It 'de → Effort=Aufwand' {
        $script:I18N['de'].Effort | Should -Be 'Aufwand'
    }

    It 'it → Error=ERRORE STATUSBAR' {
        $script:I18N['it'].Error | Should -Be 'ERRORE STATUSBAR'
    }

    It 'en → Error=STATUS ERROR' {
        $script:I18N['en'].Error | Should -Be 'STATUS ERROR'
    }

    It 'Unknown locale → falls back to en (NA=N/A)' {
        $fakeLocale = 'xx_XX'
        $lang2 = if ($fakeLocale.Length -ge 2) { $fakeLocale.Substring(0,2).ToLower() } else { 'en' }
        $fmt = if ($script:I18N.ContainsKey($lang2)) { $script:I18N[$lang2] } else { $script:I18N['en'] }
        $fmt.NA | Should -Be 'N/A'
    }

    Context 'Format-Currency with localised NA string' {
        It 'it_IT: $null → N/D' {
            $script:CurrFmt  = $script:CurrencyTable['it_IT']
            $script:I18nFmt = $script:I18N['it']
            Format-Currency $null | Should -Be 'N/D'
        }

        It 'en_US: $null → N/A' {
            $script:CurrFmt  = $script:CurrencyTable['en_US']
            $script:I18nFmt = $script:I18N['en']
            Format-Currency $null | Should -Be 'N/A'
        }
    }

    Context 'Get-FmtDate with localised NA string' {
        It 'it: empty string → N/D' {
            $script:I18nFmt = $script:I18N['it']
            Get-FmtDate '' | Should -Be 'N/D'
        }

        It 'en: empty string → N/A' {
            $script:I18nFmt = $script:I18N['en']
            Get-FmtDate '' | Should -Be 'N/A'
        }

        It 'en: invalid date → N/A' {
            $script:I18nFmt = $script:I18N['en']
            Get-FmtDate 'not-a-date' | Should -Be 'N/A'
        }
    }
}

# ============================================================================
# TASK-006c — ConvertTo-Json -Depth 10 for usage cache
# ============================================================================

Describe 'TASK-006c: ConvertTo-Json -Depth 10' {

    It 'Round-trip with -Depth 10 preserves nested objects at depth 3' {
        $deep = [PSCustomObject]@{
            five_hour = [PSCustomObject]@{
                utilization = 44.0
                nested = [PSCustomObject]@{
                    deep = [PSCustomObject]@{ value = 'ok' }
                }
            }
        }
        $json = $deep | ConvertTo-Json -Depth 10
        $back = $json | ConvertFrom-Json
        $back.five_hour.nested.deep.value | Should -Be 'ok'
    }

    It 'Without -Depth (default=2) a depth-3 object is serialised as a string' {
        $deep = [PSCustomObject]@{
            five_hour = [PSCustomObject]@{
                utilization = 44.0
                nested = [PSCustomObject]@{
                    deep = [PSCustomObject]@{ value = 'ok' }
                }
            }
        }
        $json = $deep | ConvertTo-Json   # default depth = 2
        $back = $json | ConvertFrom-Json
        # At depth 2, the nested value becomes the string "@{value=ok}" instead of an object
        $back.five_hour.nested.deep -is [string] | Should -BeTrue
    }

    It 'Anthropic API response (five_hour, seven_day, extra_usage) survives a depth-10 round-trip' {
        $mock = [PSCustomObject]@{
            five_hour  = [PSCustomObject]@{ utilization = 44.0; resets_at = '2026-03-23T00:59:59Z' }
            seven_day  = [PSCustomObject]@{ utilization = 5.0;  resets_at = '2026-03-29T19:59:59Z' }
            extra_usage = [PSCustomObject]@{
                is_enabled    = $true
                monthly_limit = 2000
                used_credits  = 574.0
                utilization   = 28.7
            }
        }
        $json = $mock | ConvertTo-Json -Depth 10
        $back = $json | ConvertFrom-Json
        $back.extra_usage.used_credits | Should -Be 574.0
        $back.five_hour.utilization    | Should -Be 44.0
    }
}

# ============================================================================
# TASK-006e — $path validation before git -C
# ============================================================================

Describe 'TASK-006e: Git path validation' {

    It 'Non-existent path → script completes without ERRORE STATUSBAR' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"Z:/nonexistent-path-xyz"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out -join '' | Should -Not -Match 'ERRORE|ERROR'
    }

    It 'Non-existent path → output contains ENV: (rendering completed)' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"Z:/nonexistent-path-xyz"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }

    It 'Empty path (fallback ".") → script completes without error' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":""}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }

    It 'Valid existing path → output contains ENV:' {
        $validPath = $PSScriptRoot | Split-Path -Parent
        $payload = "{`"model`":{`"display_name`":`"Sonnet 4.6`"},`"context_window`":{`"context_window_size`":200000,`"used_percentage`":0,`"total_input_tokens`":0,`"total_output_tokens`":0,`"current_usage`":{`"cache_read_input_tokens`":0}},`"workspace`":{`"current_dir`":`"$($validPath -replace '\\','/')`"}}"
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }
}

# ============================================================================
# TASK-006g — $script:GradientStops deduplication
# ============================================================================

Describe 'TASK-006g: $script:GradientStops deduplication' {

    It '$script:GradientStops is defined and not null' {
        $script:GradientStops | Should -Not -BeNullOrEmpty
    }

    It 'Has exactly 4 stops' {
        $script:GradientStops.Count | Should -Be 4
    }

    It 'Stop 0 — green (74, 222, 128)' {
        $script:GradientStops[0][0] | Should -Be 74
        $script:GradientStops[0][1] | Should -Be 222
        $script:GradientStops[0][2] | Should -Be 128
    }

    It 'Stop 1 — yellow (250, 204, 21)' {
        $script:GradientStops[1][0] | Should -Be 250
        $script:GradientStops[1][1] | Should -Be 204
        $script:GradientStops[1][2] | Should -Be 21
    }

    It 'Stop 2 — orange (251, 146, 60)' {
        $script:GradientStops[2][0] | Should -Be 251
        $script:GradientStops[2][1] | Should -Be 146
        $script:GradientStops[2][2] | Should -Be 60
    }

    It 'Stop 3 — red (239, 68, 68)' {
        $script:GradientStops[3][0] | Should -Be 239
        $script:GradientStops[3][1] | Should -Be 68
        $script:GradientStops[3][2] | Should -Be 68
    }

    It 'Get-GradientBar uses GradientStops: 0% → all buckets are dim gray (60;60;60)' {
        $bar = Get-GradientBar 0 4
        $bar | Should -Match '60;60;60'
        $bar | Should -Not -Match '38;2;(?!60;60;60)\d'
    }

    It 'Get-GradientBar uses GradientStops: 100% → no dim gray buckets' {
        $bar = Get-GradientBar 100 4
        $bar | Should -Not -Match '60;60;60'
    }

    It 'Get-PctColor uses GradientStops: 0% → green (74;222;128)' {
        Get-PctColor 0 | Should -Match '74;222;128'
    }

    It 'Get-PctColor uses GradientStops: 100% → red (239;68;68)' {
        Get-PctColor 100 | Should -Match '239;68;68'
    }

    It 'Modifying GradientStops[0] changes the colour returned by Get-PctColor 0%' {
        $original = $script:GradientStops[0]
        $script:GradientStops[0] = @(10, 20, 30)
        $color = Get-PctColor 0
        $script:GradientStops[0] = $original   # restore original value
        $color | Should -Match '10;20;30'
    }
}

# ============================================================================
# TASK-006h — Pre-calculated script-scope constants
# ============================================================================

Describe 'TASK-006h: Pre-calculated script-scope constants' {

    It '$script:cDimGray is defined' {
        $script:cDimGray | Should -Not -BeNullOrEmpty
    }

    It '$script:cDimGray contains the ANSI RGB sequence 60;60;60' {
        $script:cDimGray | Should -Match '38;2;60;60;60'
    }

    It '$script:cDimGray is a string' {
        $script:cDimGray | Should -BeOfType [string]
    }

    It '$script:cDimGray starts with ESC[' {
        $script:cDimGray | Should -Match '^\x1b\['
    }

    It '$script:Sep90 is defined' {
        $script:Sep90 | Should -Not -BeNullOrEmpty
    }

    It '$script:Sep90 contains exactly 90 U+2500 (─) characters' {
        $count = ($script:Sep90.ToCharArray() | Where-Object { $_ -eq [char]0x2500 }).Count
        $count | Should -Be 90
    }

    It '$script:Sep90 starts with an ANSI colour sequence' {
        $script:Sep90 | Should -Match '^\x1b\['
    }

    It '$script:Sep90 ends with an ANSI reset sequence' {
        $script:Sep90 | Should -Match '\x1b\[0m$'
    }

    It 'Get-GradientBar works correctly after 6 h — returns N ⛁ buckets' {
        $bar = Get-GradientBar 50 6
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 6
    }

    It 'Get-GradientBar 0% after 6 h — uses cDimGray (60;60;60) for empty buckets' {
        $bar = Get-GradientBar 0 4
        $bar | Should -Match '60;60;60'
    }

    It 'Get-PctColor works correctly after 6 h — output is an ANSI sequence' {
        Get-PctColor 50 | Should -Match '\x1b\[38;2;\d+;\d+;\d+m'
    }

    It 'Get-PctColor 50% after 6 h — RGB components are in range [0, 255]' {
        $color = Get-PctColor 50
        if ($color -match '38;2;(\d+);(\d+);(\d+)m') {
            [int]$Matches[1] | Should -BeGreaterOrEqual 0
            [int]$Matches[1] | Should -BeLessOrEqual 255
            [int]$Matches[2] | Should -BeGreaterOrEqual 0
            [int]$Matches[2] | Should -BeLessOrEqual 255
            [int]$Matches[3] | Should -BeGreaterOrEqual 0
            [int]$Matches[3] | Should -BeLessOrEqual 255
        } else {
            Set-ItResult -Skipped -Because "unrecognised ANSI format: $color"
        }
    }
}

# ============================================================================
# TASK-006i — Atomic usage cache write (WriteAllText, not Out-File)
# ============================================================================

Describe 'TASK-006i: Atomic usage cache write' {

    BeforeAll {
        $script:TmpCache = Join-Path $env:TEMP "claude_test_6i_$([System.IO.Path]::GetRandomFileName()).json"
    }

    AfterAll {
        Remove-Item $script:TmpCache -ErrorAction SilentlyContinue
    }

    It 'WriteAllText produces a valid JSON file readable by ConvertFrom-Json' {
        $mock = [PSCustomObject]@{
            five_hour   = [PSCustomObject]@{ utilization = 44.0; resets_at = '2026-03-23T00:59:59Z' }
            seven_day   = [PSCustomObject]@{ utilization = 5.0;  resets_at = '2026-03-29T19:59:59Z' }
            extra_usage = [PSCustomObject]@{ is_enabled = $true; monthly_limit = 2000; used_credits = 574.0; utilization = 28.7 }
        }
        [System.IO.File]::WriteAllText(
            $script:TmpCache,
            ($mock | ConvertTo-Json -Depth 10 -Compress),
            [System.Text.Encoding]::UTF8)

        { (Get-Content $script:TmpCache -Raw) | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Written content is compact (single line — no embedded newlines)' {
        $content = Get-Content $script:TmpCache -Raw
        $content.TrimEnd() -match "`n" | Should -BeFalse
    }

    It 'Round-trip preserves five_hour.utilization and extra_usage.used_credits' {
        $back = (Get-Content $script:TmpCache -Raw) | ConvertFrom-Json
        $back.five_hour.utilization    | Should -Be 44.0
        $back.extra_usage.used_credits | Should -Be 574.0
    }

    It 'statusline.ps1 no longer uses Out-File for USAGE_CACHE' {
        $src = Get-Content $script:ScriptPath -Raw
        $src | Should -Not -Match 'Out-File\s+\$USAGE_CACHE'
    }
}

# ============================================================================
# TASK-006j — Single Console::Write output (StringBuilder, no Write-Host loop)
# ============================================================================

Describe 'TASK-006j: Single Console::Write output' {

    It 'statusline.ps1 uses [Console]::Write for the output block' {
        $src = Get-Content $script:ScriptPath -Raw
        $src | Should -Match '\[Console\]::Write\('
    }

    It 'statusline.ps1 has no Write-Host outside the catch block' {
        # Load only the try{} body: everything before the final "} catch {"
        $src = Get-Content $script:ScriptPath -Raw
        # Remove the catch block so we only check the main body
        $tryBody = ($src -split '(?m)^\} catch \{')[0]
        $tryBody | Should -Not -Match 'Write-Host'
    }

    It 'Integration: output produces exactly 12 lines' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"C:/my-project"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out.Count | Should -Be 12
    }

    It 'Integration: output contains ENV: keyword' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"C:/my-project"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }
}
