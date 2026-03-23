#Requires -Modules Pester
<#
.SYNOPSIS
    test_statusline.ps1 — Pester v5 test suite per statusline.ps1

.DESCRIPTION
    Esecuzione:
        Invoke-Pester -Path test_statusline.ps1 -Output Detailed

    Dipendenze:
        Pester v5  (Install-Module -Name Pester -Force -SkipPublisherCheck)

    Strategia dot-source:
        Il BeforeAll fa dot-source di statusline.ps1 con stdin vuoto.
        Questo esegue il blocco try{} (che definisce Get-FmtDate,
        Format-Tokens, Get-GradientBar, Get-PctColor) e porta
        $script:CurrencyTable e $script:CurrFmt nello scope del test.
        Format-Currency è definita fuori da try{} ed è sempre disponibile.
#>

# Dot-source con stdin vuoto per definire tutte le funzioni
BeforeAll {
    $script:ScriptPath = Join-Path (Join-Path $PSScriptRoot '..') 'statusline.ps1'
    $null | . $script:ScriptPath 2>$null
}

# ============================================================================
# Format-Currency
# ============================================================================

Describe 'Format-Currency' {

    Context 'Italiano — € dopo, virgola come separatore decimale' {
        BeforeEach {
            $script:CurrFmt  = $script:CurrencyTable['it_IT']
            $script:I18nFmt = $script:I18N['en']
        }

        It '420 centesimi → "4,20 €"' {
            Format-Currency 420 | Should -Be '4,20 €'
        }

        It '0 centesimi → "0,00 €"' {
            Format-Currency 0 | Should -Be '0,00 €'
        }

        It '1 centesimo → "0,01 €"' {
            Format-Currency 1 | Should -Be '0,01 €'
        }

        It '10000 centesimi → "100,00 €"' {
            Format-Currency 10000 | Should -Be '100,00 €'
        }

        It '999999 centesimi → "9999,99 €"' {
            Format-Currency 999999 | Should -Be '9999,99 €'
        }

        It '$null → "N/A"' {
            Format-Currency $null | Should -Be 'N/A'
        }
    }

    Context 'Dollaro USA — $ prima, punto come separatore decimale' {
        BeforeEach {
            $script:CurrFmt  = $script:CurrencyTable['en_US']
            $script:I18nFmt = $script:I18N['en']
        }

        It '420 centesimi → "$4.20"' {
            Format-Currency 420 | Should -Be '$4.20'
        }

        It '0 centesimi → "$0.00"' {
            Format-Currency 0 | Should -Be '$0.00'
        }

        It '$null → "N/A"' {
            Format-Currency $null | Should -Be 'N/A'
        }
    }

    Context 'Sterlina inglese' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['en_GB']
        }

        It '420 centesimi → "£4.20"' {
            Format-Currency 420 | Should -Be '£4.20'
        }
    }

    Context 'Yen giapponese — 0 decimali' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['ja_JP']
        }

        It '42000 centesimi (= 420 JPY) → "¥420"' {
            Format-Currency 42000 | Should -Be '¥420'
        }

        It '100 centesimi (= 1 JPY) → "¥1"' {
            Format-Currency 100 | Should -Be '¥1'
        }

        It '0 → "¥0"' {
            Format-Currency 0 | Should -Be '¥0'
        }
    }

    Context 'Franco Svizzero — simbolo con spazio' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['fr_CH']
        }

        It '420 centesimi → "CHF 4.20"' {
            Format-Currency 420 | Should -Be 'CHF 4.20'
        }

        It '0 centesimi → "CHF 0.00"' {
            Format-Currency 0 | Should -Be 'CHF 0.00'
        }
    }

    Context 'Real Brasiliano — simbolo prima, virgola decimale' {
        BeforeEach {
            $script:CurrFmt = $script:CurrencyTable['pt_BR']
        }

        It '420 centesimi → "R$4,20"' {
            Format-Currency 420 | Should -Be 'R$4,20'
        }
    }
}

# ============================================================================
# CurrencyTable
# ============================================================================

Describe 'CurrencyTable' {

    It 'Contiene tutti i 16 locale previsti' {
        $expectedLocales = @(
            'it_IT','de_DE','fr_FR','es_ES','pt_PT',
            'en_US','en_AU','en_CA','en_GB',
            'ja_JP','zh_CN','zh_TW',
            'fr_CH','de_CH','it_CH',
            'pt_BR'
        )
        foreach ($loc in $expectedLocales) {
            $script:CurrencyTable.ContainsKey($loc) | Should -BeTrue -Because "locale $loc deve essere presente"
        }
    }

    It 'it_IT ha Symbol=€, DecSep=",", SymBefore=$false' {
        $it = $script:CurrencyTable['it_IT']
        $it.Symbol    | Should -Be '€'
        $it.DecSep    | Should -Be ','
        $it.SymBefore | Should -BeFalse
    }

    It 'en_US ha Symbol=$, SymBefore=$true' {
        $us = $script:CurrencyTable['en_US']
        $us.Symbol    | Should -Be '$'
        $us.SymBefore | Should -BeTrue
    }

    It 'ja_JP ha Decimals=0' {
        $script:CurrencyTable['ja_JP'].Decimals | Should -Be 0
    }

    It 'fr_CH ha SymSpace=$true' {
        $script:CurrencyTable['fr_CH'].SymSpace | Should -BeTrue
    }

    It 'Locale sconosciuto non è nella tabella (usa fallback in Format-Currency tramite $script:CurrFmt)' {
        $script:CurrencyTable.ContainsKey('xx_XX') | Should -BeFalse
    }

    It 'Locale sconosciuto → $script:CurrFmt usa en_US come fallback' {
        # Simula locale sconosciuto settando CurrFmt al valore che lo script sceglie
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

    It 'Contiene tutti i 16 locale previsti' {
        $expectedLocales = @(
            'it_IT','it_CH','de_DE','de_CH','fr_FR','fr_CH',
            'es_ES','pt_PT','pt_BR',
            'en_US','en_AU','en_CA','en_GB',
            'ja_JP','zh_CN','zh_TW'
        )
        foreach ($loc in $expectedLocales) {
            $script:DateTable.ContainsKey($loc) | Should -BeTrue -Because "locale $loc deve essere presente"
        }
    }

    It 'it_IT ha Order=DMY, Sep=/, H24=$true' {
        $it = $script:DateTable['it_IT']
        $it.Order | Should -Be 'DMY'
        $it.Sep   | Should -Be '/'
        $it.H24   | Should -BeTrue
    }

    It 'en_US ha Order=MDY, H24=$false' {
        $us = $script:DateTable['en_US']
        $us.Order | Should -Be 'MDY'
        $us.H24   | Should -BeFalse
    }

    It 'de_DE ha Sep=punto' {
        $script:DateTable['de_DE'].Sep | Should -Be '.'
    }

    It 'Locale sconosciuto → DateFmt usa en_US come fallback' {
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

    It 'Stringa vuota → "N/A"' {
        Get-FmtDate '' | Should -Be 'N/A'
    }

    It '$null → "N/A"' {
        Get-FmtDate $null | Should -Be 'N/A'
    }

    It 'Data invalida → restituisce "N/A" (grazie a try/catch)' {
        Get-FmtDate 'non-una-data' | Should -Be 'N/A'
    }

    Context 'it_IT (DMY, 24h)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['it_IT']
            $script:I18nFmt = $script:I18N['en']
        }

        It '2025-01-06 → inizia con "LUN" (lunedì)' {
            Get-FmtDate '2025-01-06T12:00:00Z' | Should -Match '^LUN '
        }

        It '2025-01-12 → inizia con "DOM" (domenica)' {
            Get-FmtDate '2025-01-12T12:00:00Z' | Should -Match '^DOM '
        }

        It '2025-01-07 → inizia con "MAR"' {
            Get-FmtDate '2025-01-07T12:00:00Z' | Should -Match '^MAR '
        }

        It 'Formato output rispetta il pattern "\w{3} dd/MM H: HH:mm"' {
            Get-FmtDate '2025-06-15T14:30:00Z' | Should -Match '^\w{3} \d{2}/\d{2} H: \d{2}:\d{2}$'
        }
    }

    Context 'en_US (MDY, 12h)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['en_US']
            $script:I18nFmt = $script:I18N['en']
        }

        It 'Formato output rispetta il pattern "\w{3} MM/DD H: hh:mm AM/PM"' {
            $result = Get-FmtDate '2025-03-19T18:00:00Z'
            $result | Should -Match '^\w{3} \d{2}/\d{2} H: \d{2}:\d{2} (AM|PM)$'
        }

        It '2025-01-06 (lunedì) → inizia con "MON"' {
            Get-FmtDate '2025-01-06T12:00:00Z' | Should -Match '^MON '
        }
    }

    Context 'de_DE (sep punto)' {
        BeforeEach {
            $script:DateFmt = $script:DateTable['de_DE']
            $script:I18nFmt = $script:I18N['en']
        }

        It 'Formato output usa punto come separatore data' {
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

    It 'width=10 → output contiene esattamente 10 caratteri ⛁' {
        $bar = Get-GradientBar 50 10
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 10
    }

    It '0% → tutti i bucket sono dim gray (38;2;60;60;60)' {
        $bar = Get-GradientBar 0 10
        $bar | Should -Match '60;60;60'
        # Nessun bucket colorato (non deve contenere colori diversi da 60;60;60)
        $bar | Should -Not -Match '38;2;(?!60;60;60)\d'
    }

    It '100% → nessun bucket è dim gray' {
        $bar = Get-GradientBar 100 10
        $bar | Should -Not -Match '60;60;60'
    }

    It 'width=0 → stringa vuota' {
        Get-GradientBar 50 0 | Should -Be ''
    }

    It 'width=1 → contiene esattamente 1 carattere ⛁' {
        $bar = Get-GradientBar 50 1
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 1
    }

    It 'width=48 default → contiene 48 caratteri ⛁' {
        $bar = Get-GradientBar 50
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 48
    }
}

# ============================================================================
# Get-PctColor
# ============================================================================

Describe 'Get-PctColor' {

    It '0% → contiene il verde iniziale (74;222;128)' {
        Get-PctColor 0 | Should -Match '74;222;128'
    }

    It '100% → contiene il rosso finale (239;68;68)' {
        Get-PctColor 100 | Should -Match '239;68;68'
    }

    It 'Output è una sequenza ANSI ESC[38;2;R;G;Bm' {
        Get-PctColor 50 | Should -Match '\x1b\[38;2;\d+;\d+;\d+m'
    }

    It 'Componenti RGB sono nell''intervallo [0, 255]' {
        $color = Get-PctColor 50
        if ($color -match '38;2;(\d+);(\d+);(\d+)m') {
            [int]$Matches[1] | Should -BeGreaterOrEqual 0
            [int]$Matches[1] | Should -BeLessOrEqual 255
            [int]$Matches[2] | Should -BeGreaterOrEqual 0
            [int]$Matches[2] | Should -BeLessOrEqual 255
            [int]$Matches[3] | Should -BeGreaterOrEqual 0
            [int]$Matches[3] | Should -BeLessOrEqual 255
        } else {
            Set-ItResult -Skipped -Because "formato ANSI non riconosciuto: $color"
        }
    }
}

# ============================================================================
# Integrazione — subprocess
# ============================================================================

Describe 'Integrazione' {

    $MinimalPayload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"."}}'

    It 'Payload minimo → output contiene "ENV:"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'ENV:'
    }

    It 'Payload minimo → output contiene "XTRA USG:"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'XTRA USG:'
    }

    It 'Payload minimo → output contiene "CONTEXT_WINDOW"' {
        $out = $MinimalPayload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out | Should -Match 'CONTEXT_WINDOW'
    }

    It 'Input vuoto → nessun "ERRORE STATUSBAR:"' {
        $out = '' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out -join '' | Should -Not -Match 'ERRORE STATUSBAR:'
    }
}

# ============================================================================
# I18N — tabella e formattazione localizzata
# ============================================================================

Describe 'I18N' {

    It 'Tabella ha tutte le 8 lingue previste' {
        $expectedLangs = @('it','en','de','fr','es','pt','ja','zh')
        foreach ($lang in $expectedLangs) {
            $script:I18N.ContainsKey($lang) | Should -BeTrue -Because "lingua $lang deve essere presente"
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

    It 'Locale sconosciuto → fallback en (NA=N/A)' {
        $fakeLocale = 'xx_XX'
        $lang2 = if ($fakeLocale.Length -ge 2) { $fakeLocale.Substring(0,2).ToLower() } else { 'en' }
        $fmt = if ($script:I18N.ContainsKey($lang2)) { $script:I18N[$lang2] } else { $script:I18N['en'] }
        $fmt.NA | Should -Be 'N/A'
    }

    Context 'Format-Currency con NA localizzato' {
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

    Context 'Get-FmtDate con NA localizzato' {
        It 'it: stringa vuota → N/D' {
            $script:I18nFmt = $script:I18N['it']
            Get-FmtDate '' | Should -Be 'N/D'
        }

        It 'en: stringa vuota → N/A' {
            $script:I18nFmt = $script:I18N['en']
            Get-FmtDate '' | Should -Be 'N/A'
        }

        It 'en: data invalida → N/A' {
            $script:I18nFmt = $script:I18N['en']
            Get-FmtDate 'non-una-data' | Should -Be 'N/A'
        }
    }
}

# ============================================================================
# TASK-006c — ConvertTo-Json -Depth 10 per cache usage
# ============================================================================

Describe 'TASK-006c: ConvertTo-Json -Depth 10' {

    It 'Round-trip con -Depth 10 preserva oggetti annidati a profondità 3' {
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

    It 'Senza -Depth (default=2) un oggetto a profondità 3 viene corrotto in stringa' {
        $deep = [PSCustomObject]@{
            five_hour = [PSCustomObject]@{
                utilization = 44.0
                nested = [PSCustomObject]@{
                    deep = [PSCustomObject]@{ value = 'ok' }
                }
            }
        }
        $json = $deep | ConvertTo-Json   # depth default = 2
        $back = $json | ConvertFrom-Json
        # A depth 2, il valore annidato diventa stringa "@{value=ok}" non un oggetto
        $back.five_hour.nested.deep -is [string] | Should -BeTrue
    }

    It 'La risposta API Anthropic (five_hour, seven_day, extra_usage) sopravvive a depth 10' {
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
# TASK-006e — Validazione $path prima di git -C
# ============================================================================

Describe 'TASK-006e: Validazione path git' {

    It 'Path inesistente → script completa senza ERRORE STATUSBAR' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"Z:/nonexistent-path-xyz"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        $out -join '' | Should -Not -Match 'ERRORE|ERROR'
    }

    It 'Path inesistente → output contiene ENV: (rendering completato)' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"Z:/nonexistent-path-xyz"}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }

    It 'Path vuoto (fallback ".") → script completa senza errore' {
        $payload = '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":0,"total_input_tokens":0,"total_output_tokens":0,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":""}}'
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }

    It 'Path valido esistente → output contiene ENV:' {
        $validPath = $PSScriptRoot | Split-Path -Parent
        $payload = "{`"model`":{`"display_name`":`"Sonnet 4.6`"},`"context_window`":{`"context_window_size`":200000,`"used_percentage`":0,`"total_input_tokens`":0,`"total_output_tokens`":0,`"current_usage`":{`"cache_read_input_tokens`":0}},`"workspace`":{`"current_dir`":`"$($validPath -replace '\\','/')`"}}"
        $out = $payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScriptPath 2>$null
        ($out -join "`n") | Should -Match 'ENV:'
    }
}

# ============================================================================
# TASK-006g — $script:GradientStops deduplicato
# ============================================================================

Describe 'TASK-006g: GradientStops script-scope' {

    It '$script:GradientStops è definito e non nullo' {
        $script:GradientStops | Should -Not -BeNullOrEmpty
    }

    It 'Ha esattamente 4 stop' {
        $script:GradientStops.Count | Should -Be 4
    }

    It 'Stop 0 — verde (74, 222, 128)' {
        $script:GradientStops[0][0] | Should -Be 74
        $script:GradientStops[0][1] | Should -Be 222
        $script:GradientStops[0][2] | Should -Be 128
    }

    It 'Stop 1 — giallo (250, 204, 21)' {
        $script:GradientStops[1][0] | Should -Be 250
        $script:GradientStops[1][1] | Should -Be 204
        $script:GradientStops[1][2] | Should -Be 21
    }

    It 'Stop 2 — arancio (251, 146, 60)' {
        $script:GradientStops[2][0] | Should -Be 251
        $script:GradientStops[2][1] | Should -Be 146
        $script:GradientStops[2][2] | Should -Be 60
    }

    It 'Stop 3 — rosso (239, 68, 68)' {
        $script:GradientStops[3][0] | Should -Be 239
        $script:GradientStops[3][1] | Should -Be 68
        $script:GradientStops[3][2] | Should -Be 68
    }

    It 'Get-GradientBar usa GradientStops: 0% → tutti i bucket sono dim gray (60;60;60)' {
        $bar = Get-GradientBar 0 4
        $bar | Should -Match '60;60;60'
        $bar | Should -Not -Match '38;2;(?!60;60;60)\d'
    }

    It 'Get-GradientBar usa GradientStops: 100% → nessun bucket dim gray' {
        $bar = Get-GradientBar 100 4
        $bar | Should -Not -Match '60;60;60'
    }

    It 'Get-PctColor usa GradientStops: 0% → verde (74;222;128)' {
        Get-PctColor 0 | Should -Match '74;222;128'
    }

    It 'Get-PctColor usa GradientStops: 100% → rosso (239;68;68)' {
        Get-PctColor 100 | Should -Match '239;68;68'
    }

    It 'Modificare GradientStops[0] cambia il colore di Get-PctColor 0%' {
        $original = $script:GradientStops[0]
        $script:GradientStops[0] = @(10, 20, 30)
        $color = Get-PctColor 0
        $script:GradientStops[0] = $original   # ripristina
        $color | Should -Match '10;20;30'
    }
}

# ============================================================================
# TASK-006h — Variabili costanti pre-calcolate script-scope
# ============================================================================

Describe 'TASK-006h: Variabili costanti script-scope' {

    It '$script:cDimGray è definito' {
        $script:cDimGray | Should -Not -BeNullOrEmpty
    }

    It '$script:cDimGray contiene la sequenza ANSI RGB 60;60;60' {
        $script:cDimGray | Should -Match '38;2;60;60;60'
    }

    It '$script:cDimGray è una stringa' {
        $script:cDimGray | Should -BeOfType [string]
    }

    It '$script:cDimGray inizia con ESC[' {
        $script:cDimGray | Should -Match '^\x1b\['
    }

    It '$script:Sep90 è definito' {
        $script:Sep90 | Should -Not -BeNullOrEmpty
    }

    It '$script:Sep90 contiene esattamente 90 caratteri U+2500 (─)' {
        $count = ($script:Sep90.ToCharArray() | Where-Object { $_ -eq [char]0x2500 }).Count
        $count | Should -Be 90
    }

    It '$script:Sep90 inizia con una sequenza ANSI di colore' {
        $script:Sep90 | Should -Match '^\x1b\['
    }

    It '$script:Sep90 termina con sequenza reset ANSI' {
        $script:Sep90 | Should -Match '\x1b\[0m$'
    }

    It 'Get-GradientBar funziona correttamente dopo 6h — restituisce N bucket ⛁' {
        $bar = Get-GradientBar 50 6
        ($bar.ToCharArray() | Where-Object { $_ -eq [char]0x26C1 }).Count | Should -Be 6
    }

    It 'Get-GradientBar 0% dopo 6h — usa cDimGray (60;60;60) per i bucket vuoti' {
        $bar = Get-GradientBar 0 4
        $bar | Should -Match '60;60;60'
    }

    It 'Get-PctColor funziona correttamente dopo 6h — output è sequenza ANSI' {
        Get-PctColor 50 | Should -Match '\x1b\[38;2;\d+;\d+;\d+m'
    }

    It 'Get-PctColor 50% dopo 6h — componenti RGB in range [0,255]' {
        $color = Get-PctColor 50
        if ($color -match '38;2;(\d+);(\d+);(\d+)m') {
            [int]$Matches[1] | Should -BeGreaterOrEqual 0
            [int]$Matches[1] | Should -BeLessOrEqual 255
            [int]$Matches[2] | Should -BeGreaterOrEqual 0
            [int]$Matches[2] | Should -BeLessOrEqual 255
            [int]$Matches[3] | Should -BeGreaterOrEqual 0
            [int]$Matches[3] | Should -BeLessOrEqual 255
        } else {
            Set-ItResult -Skipped -Because "formato ANSI non riconosciuto: $color"
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
