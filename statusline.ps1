<#
.SYNOPSIS
    Claude Code statusline HUD for Windows / PowerShell 5.1+.

.DESCRIPTION
    Reads Claude Code telemetry JSON from stdin, enriches it with git status,
    effort level from the settings file cascade, and Anthropic OAuth API usage
    metrics, then writes a 6-line ANSI RGB true-colour HUD to stdout via a
    single [Console]::Write() call.

.INPUTS
    JSON string piped from Claude Code via stdin.

.OUTPUTS
    Six lines of ANSI RGB text written to stdout.

.NOTES
    Dependencies : PowerShell 5.1+, git (optional), internet access (optional).
    Cache files  : %TEMP%\claude_*.json  (TTLs defined by $*_TTL constants).
#>
# Force UTF-8 output — both for console rendering and pipe encoding (PS 5.1 pipe default is ASCII)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding             = [System.Text.Encoding]::UTF8

$CRED_FILE    = "$env:USERPROFILE\.claude\.credentials.json"
$USAGE_CACHE       = "$env:TEMP\claude_usage_cache.json"
$USAGE_ERROR_CACHE = "$env:TEMP\claude_usage_error.json"
$GIT_CACHE         = "$env:TEMP\claude_git_cache.json"
$EFFORT_CACHE      = "$env:TEMP\claude_effort_cache.json"
$USAGE_TTL    = 120   # seconds — Anthropic API call
$GIT_TTL      = 8     # seconds — git branch + status
$EFFORT_TTL   = 30    # seconds — settings file read
$ERROR_TTL    = 30    # seconds — API error backoff (4d)
$API_TIMEOUT  = 3     # seconds — HTTP API call timeout

# Locale → currency table: @{ Symbol; DecSep; SymBefore; SymSpace; Decimals }
$euro = [char]0x20AC
$script:CurrencyTable = @{
    'it_IT' = @{ Symbol=$euro; DecSep=','; SymBefore=$false; SymSpace=$true;  Decimals=2 }
    'de_DE' = @{ Symbol=$euro; DecSep=','; SymBefore=$false; SymSpace=$true;  Decimals=2 }
    'fr_FR' = @{ Symbol=$euro; DecSep=','; SymBefore=$false; SymSpace=$true;  Decimals=2 }
    'es_ES' = @{ Symbol=$euro; DecSep=','; SymBefore=$false; SymSpace=$true;  Decimals=2 }
    'pt_PT' = @{ Symbol=$euro; DecSep=','; SymBefore=$false; SymSpace=$true;  Decimals=2 }
    'en_US' = @{ Symbol='$';   DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'en_AU' = @{ Symbol='$';   DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'en_CA' = @{ Symbol='$';   DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'en_GB' = @{ Symbol=([char]0x00A3); DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'ja_JP' = @{ Symbol=([char]0x00A5); DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=0 }
    'zh_CN' = @{ Symbol=([char]0x00A5); DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'zh_TW' = @{ Symbol=([char]0x00A5); DecSep='.'; SymBefore=$true;  SymSpace=$false; Decimals=2 }
    'fr_CH' = @{ Symbol='CHF'; DecSep='.'; SymBefore=$true;  SymSpace=$true;  Decimals=2 }
    'de_CH' = @{ Symbol='CHF'; DecSep='.'; SymBefore=$true;  SymSpace=$true;  Decimals=2 }
    'it_CH' = @{ Symbol='CHF'; DecSep='.'; SymBefore=$true;  SymSpace=$true;  Decimals=2 }
    'pt_BR' = @{ Symbol='R$';  DecSep=','; SymBefore=$true;  SymSpace=$false; Decimals=2 }
}
$_locale = $PSCulture.Replace('-', '_')
$script:CurrFmt = if ($script:CurrencyTable.ContainsKey($_locale)) {
    $script:CurrencyTable[$_locale]
} else {
    $script:CurrencyTable['en_US']
}

# PS DayOfWeek: 0=Sun,1=Mon,...,6=Sat — Days array indexed [0..6]
$script:DateTable = @{
    'it_IT' = @{ Days=@('DOM','LUN','MAR','MER','GIO','VEN','SAB'); Order='DMY'; Sep='/'; H24=$true  }
    'it_CH' = @{ Days=@('DOM','LUN','MAR','MER','GIO','VEN','SAB'); Order='DMY'; Sep='/'; H24=$true  }
    'de_DE' = @{ Days=@('SO', 'MO', 'DI', 'MI', 'DO', 'FR', 'SA' ); Order='DMY'; Sep='.'; H24=$true  }
    'de_CH' = @{ Days=@('SO', 'MO', 'DI', 'MI', 'DO', 'FR', 'SA' ); Order='DMY'; Sep='.'; H24=$true  }
    'fr_FR' = @{ Days=@('DIM','LUN','MAR','MER','JEU','VEN','SAM'); Order='DMY'; Sep='/'; H24=$true  }
    'fr_CH' = @{ Days=@('DIM','LUN','MAR','MER','JEU','VEN','SAM'); Order='DMY'; Sep='/'; H24=$true  }
    'es_ES' = @{ Days=@('DOM','LUN','MAR','MIE','JUE','VIE','SAB'); Order='DMY'; Sep='/'; H24=$true  }
    'pt_PT' = @{ Days=@('DOM','SEG','TER','QUA','QUI','SEX','SAB'); Order='DMY'; Sep='/'; H24=$true  }
    'pt_BR' = @{ Days=@('DOM','SEG','TER','QUA','QUI','SEX','SAB'); Order='DMY'; Sep='/'; H24=$true  }
    'en_US' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='MDY'; Sep='/'; H24=$false }
    'en_AU' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='MDY'; Sep='/'; H24=$false }
    'en_CA' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='MDY'; Sep='/'; H24=$false }
    'en_GB' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='DMY'; Sep='/'; H24=$true  }
    'ja_JP' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='MDY'; Sep='/'; H24=$true  }
    'zh_CN' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='DMY'; Sep='/'; H24=$true  }
    'zh_TW' = @{ Days=@('SUN','MON','TUE','WED','THU','FRI','SAT'); Order='DMY'; Sep='/'; H24=$true  }
}
$script:DateFmt = if ($script:DateTable.ContainsKey($_locale)) {
    $script:DateTable[$_locale]
} else {
    $script:DateTable['en_US']
}

$script:I18N = @{
    'it' = @{ Effort='Effort';   NA='N/D'; Error='ERRORE STATUSBAR';      RemPre='mancano '; RemPost='' }
    'en' = @{ Effort='Effort';   NA='N/A'; Error='STATUS ERROR';          RemPre='';          RemPost=' left' }
    'de' = @{ Effort='Aufwand';  NA='N/A'; Error='STATUSLEISTE FEHLER';   RemPre='noch ';     RemPost='' }
    'fr' = @{ Effort='Effort';   NA='N/V'; Error='ERREUR STATUSBAR';      RemPre='reste ';    RemPost='' }
    'es' = @{ Effort='Esfuerzo'; NA='N/V'; Error='ERROR STATUSBAR';       RemPre='faltan ';   RemPost='' }
    'pt' = @{ Effort='Esforco';  NA='N/D'; Error='ERRO STATUSBAR';        RemPre='faltam ';   RemPost='' }
    'ja' = @{ Effort='Effort';   NA='N/A'; Error='STATUS ERROR';          RemPre='';          RemPost=' left' }
    'zh' = @{ Effort='Effort';   NA='N/A'; Error='STATUS ERROR';          RemPre='';          RemPost=' left' }
}
$_lang2 = if ($_locale.Length -ge 2) { $_locale.Substring(0,2).ToLower() } else { 'en' }
$script:I18nFmt = if ($script:I18N.ContainsKey($_lang2)) { $script:I18N[$_lang2] } else { $script:I18N['en'] }

<#
.SYNOPSIS
    Converts a cent amount to a locale-formatted currency string.

.PARAMETER cents
    Amount in cents (integer or double). Pass $null to get the localised N/A string.

.OUTPUTS
    System.String — formatted currency (e.g. "1,23 €" or "$1.23") or the
    localised N/A value when $cents is $null.
#>
function Format-Currency($cents) {
    if ($null -eq $cents) { return $script:I18nFmt.NA }
    $fmt   = $script:CurrFmt
    $value = [double]$cents / 100
    $numStr = if ($fmt.Decimals -eq 0) {
        [string][int][Math]::Round($value)
    } else {
        ("{0:F$($fmt.Decimals)}" -f $value).Replace('.', $fmt.DecSep)
    }
    $sp = if ($fmt.SymSpace) { ' ' } else { '' }
    if ($fmt.SymBefore) { "$($fmt.Symbol)$sp$numStr" }
    else                { "$numStr$sp$($fmt.Symbol)" }
}

try {
    $now = Get-Date

    # 1. Read JSON input from Claude Code
    $inputRaw = $Input | Out-String
    if ([string]::IsNullOrWhiteSpace($inputRaw)) { $inputRaw = '{}' }
    $json = $inputRaw | ConvertFrom-Json

    # 2. Fetch Usage Data (Anthropic API) — 120s cache
    $usageData  = $null
    $needsUpdate = $true
    if (Test-Path $USAGE_CACHE) {
        if ($now -lt (Get-Item $USAGE_CACHE).LastWriteTime.AddSeconds($USAGE_TTL)) {
            $usageData   = (Get-Content $USAGE_CACHE -Raw) | ConvertFrom-Json
            $needsUpdate = $false
        }
    }
    # 4d: skip API if a fresh error is cached (prevents hammering with expired token)
    if ($needsUpdate -and (Test-Path $USAGE_ERROR_CACHE)) {
        if ($now -lt (Get-Item $USAGE_ERROR_CACHE).LastWriteTime.AddSeconds($ERROR_TTL)) {
            $needsUpdate = $false
        }
    }
    if ($needsUpdate -and (Test-Path $CRED_FILE)) {
        try {
            if ((Get-Item $CRED_FILE).Length -le 65536) {
                $token = ((Get-Content $CRED_FILE -Raw) | ConvertFrom-Json).claudeAiOauth.accessToken
            }
            if ($token -match '[\r\n\x00]') { $token = $null }
            if ($token) {
                $headers   = @{ "Authorization" = "Bearer $token"; "anthropic-beta" = "oauth-2025-04-20" }
                $usageData = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -Method Get -TimeoutSec $API_TIMEOUT
                if ($null -ne $usageData.five_hour -and $null -ne $usageData.seven_day) {
                    [System.IO.File]::WriteAllText($USAGE_CACHE,
                    ($usageData | ConvertTo-Json -Depth 10 -Compress),
                    (New-Object System.Text.UTF8Encoding($false)))
                    Remove-Item $USAGE_ERROR_CACHE -ErrorAction SilentlyContinue
                }
            }
        } catch {
            $errCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            $errTs   = [long]($now.ToUniversalTime() - [DateTime]'1970-01-01T00:00:00Z').TotalSeconds
            $errObj  = [PSCustomObject]@{ error = "HTTP $errCode $($_.Exception.GetType().Name)"; timestamp = $errTs }
            [System.IO.File]::WriteAllText($USAGE_ERROR_CACHE, ($errObj | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
            if (Test-Path $USAGE_CACHE) { $usageData = (Get-Content $USAGE_CACHE -Raw) | ConvertFrom-Json }
        }
    }

    # Cache state after fetch: 'fresh' | 'stale' | 'missing' (TASK-4b)
    $cacheState = 'missing'
    $cacheAge   = [double]::PositiveInfinity
    if (Test-Path $USAGE_CACHE) {
        $cacheAge   = ($now - (Get-Item $USAGE_CACHE).LastWriteTime).TotalSeconds
        $cacheState = if ($cacheAge -lt $USAGE_TTL) { 'fresh' } else { 'stale' }
    }

    # --- DATE FORMATTING FUNCTION (locale-aware) ---
    <#
    .SYNOPSIS
        Converts an ISO 8601 date string to a localised display string.

    .PARAMETER rawDate
        ISO 8601 date string (e.g. "2025-06-15T14:30:00Z"). Empty or $null
        returns the localised N/A string.

    .OUTPUTS
        System.String — localised date/time (e.g. "SAB 15/06 H: 14:30") or N/A.
    #>
    function Get-FmtDate($rawDate) {
        if (!$rawDate) { return $script:I18nFmt.NA }
        try {
            $d   = [DateTime]::Parse($rawDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
            $fmt = $script:DateFmt
            $day = $fmt.Days[[int]$d.DayOfWeek]
            $dd  = $d.ToString('dd'); $mm = $d.ToString('MM')
            $dateStr = if ($fmt.Order -eq 'MDY') { "$mm$($fmt.Sep)$dd" } else { "$dd$($fmt.Sep)$mm" }
            $timeStr = if ($fmt.H24) { $d.ToString('HH:mm') } else { $d.ToString('hh:mm tt') }
            return "$day $dateStr H: $timeStr"
        } catch { return $script:I18nFmt.NA }
    }

    function Get-Remaining($rawDate) {
        if (!$rawDate) { return '' }
        try {
            $d     = [DateTime]::Parse($rawDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $delta = [int]($d - [DateTime]::Now).TotalSeconds
            if ($delta -le 0) { return '' }
            $h = [int][Math]::Floor($delta / 3600)
            $m = [int][Math]::Floor(($delta % 3600) / 60)
            $pre  = $script:I18nFmt.RemPre
            $post = $script:I18nFmt.RemPost
            return " [$pre$($h.ToString('D2')):$($m.ToString('D2'))$post]"
        } catch { return '' }
    }

    # API data mapping
    $u5h = 0; $uWk = 0; $r5h = $script:I18nFmt.NA; $rWk = $script:I18nFmt.NA
    $extraUsage = $null; $monthLimit = $null; $usedCredits = $null; $monthUtil = $script:I18nFmt.NA
    if ($usageData) {
        $u5h         = if ($usageData.five_hour.utilization)            { [int]([double]$usageData.five_hour.utilization) }           else { 0 }
        $uWk         = if ($usageData.seven_day.utilization)            { [int]([double]$usageData.seven_day.utilization) }           else { 0 }
        $r5h         = Get-FmtDate $usageData.five_hour.resets_at
        $rWk         = Get-FmtDate $usageData.seven_day.resets_at
        $extraUsage  = $usageData.extra_usage.is_enabled
        $monthLimit  = if ($null -ne $usageData.extra_usage.monthly_limit) { [double]$usageData.extra_usage.monthly_limit } else { $null }
        $usedCredits = if ($null -ne $usageData.extra_usage.used_credits)  { [double]$usageData.extra_usage.used_credits }  else { $null }
        $monthUtil   = if ($null -ne $usageData.extra_usage.utilization)   { "{0:F1}%" -f [double]$usageData.extra_usage.utilization } else { "N/A" }
    }

    # 3. Extract Claude Code data
    $model  = if ($json.model.display_name)          { $json.model.display_name }          else { "Claude" }
    $path   = if ($json.workspace.current_dir)        { $json.workspace.current_dir }        else { "." }
    $dir    = Split-Path $path -Leaf
    $pct    = if ($json.context_window.used_percentage)    { [int]$json.context_window.used_percentage }    else { 0 }
    $ctxMax = if ($json.context_window.context_window_size){ [int]$json.context_window.context_window_size }else { 200000 }
    $ctxMaxFmt = if ($ctxMax -ge 1000000) { "{0:F0}M" -f ($ctxMax/1000000) } elseif ($ctxMax -ge 1000) { "{0:F0}K" -f ($ctxMax/1000) } else { "$ctxMax" }

    $tokIn     = if ($json.context_window.total_input_tokens)  { [long]$json.context_window.total_input_tokens }  else { 0 }
    $tokOut    = if ($json.context_window.total_output_tokens) { [long]$json.context_window.total_output_tokens } else { 0 }
    $tokCached = if ($json.context_window.current_usage.cache_read_input_tokens) { [long]$json.context_window.current_usage.cache_read_input_tokens } else { 0 }
    $tokTotal  = $tokIn + $tokOut + $tokCached

    <#
    .SYNOPSIS
        Formats a token count: values >= 1000 become "X.XK", smaller values are
        returned as plain integers.

    .PARAMETER n
        Token count (integer or long).

    .OUTPUTS
        System.String — e.g. "5.0K" or "800".
    #>
    function Format-Tokens($n) { if ($n -ge 1000) { "{0:F1}K" -f ($n/1000) } else { "$n" } }

    # 3a. Effort — 30s cache (reads settings files only when cache is expired)
    $effortRaw = $null
    if (Test-Path $EFFORT_CACHE) {
        $ec = (Get-Content $EFFORT_CACHE -Raw) | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($ec -and $ec.expires) {
            try { if ($now -lt [DateTime]::Parse($ec.expires, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)) { $effortRaw = $ec.effort } } catch {}
        }
    }
    if (-not $effortRaw) {
        foreach ($sp in @(
            (Join-Path $path ".claude\settings.local.json"),
            (Join-Path $path ".claude\settings.json"),
            "$env:USERPROFILE\.claude\settings.local.json",
            "$env:USERPROFILE\.claude\settings.json"
        )) {
            if ((Test-Path $sp) -and (Get-Item $sp).Length -le 262144) {
                $s = (Get-Content $sp -Raw -ErrorAction SilentlyContinue) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($s.effortLevel) { $effortRaw = $s.effortLevel; break }
            }
        }
        if (-not $effortRaw) { $effortRaw = "normal" }
        $effortObj = [PSCustomObject]@{
            effort  = $effortRaw
            expires = $now.AddSeconds($EFFORT_TTL).ToString("o")
        }
        if ($effortObj.effort) {
            [System.IO.File]::WriteAllText($EFFORT_CACHE,
                ($effortObj | ConvertTo-Json -Compress),
                (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    $effortMap = @{ low="Low"; medium="Medium"; high="High"; max="Max" }
    $effort = if ($effortMap.ContainsKey($effortRaw)) { $effortMap[$effortRaw] } else { "Not Set" }

    # 4. Colors and Icons
    $e = [char]27
    $cReset  = "$e[0m"
    $cCyan   = "$e[36m"
    $cGreen  = "$e[32m"
    $cYellow = "$e[33m"
    $cRed    = "$e[31m"
    $cGray   = "$e[90m"
    $cWhite  = "$e[37m"
    $cBranch = "$e[38;2;186;230;253m"
    $cOrange = "$e[38;2;255;165;0m"
    $icoFolder  = [string]([char]0xD83D + [char]0xDCC1)   # 📁
    $icoLeaf    = [string]([char]0xD83C + [char]0xDF3F)   # 🌿
    $charBucket = [string][char]0x26C1                     # ⛁
    $script:GradientStops = @(
        @(74,  222, 128),   # 0%   — green
        @(250, 204, 21),    # 33%  — yellow
        @(251, 146, 60),    # 66%  — orange
        @(239, 68,  68)     # 100% — red
    )
    $script:cDimGray = "$e[38;2;60;60;60m"
    $script:Sep100    = "$cGray" + ([string][char]0x2500 * 107) + "$cReset"

    <#
    .SYNOPSIS
        Builds an ANSI RGB gradient bar of ⛁ characters.

    .DESCRIPTION
        Renders $totalWidth ⛁ (U+26C1) characters coloured along a four-stop
        gradient: Green(74,222,128) → Yellow(250,204,21) → Orange(251,146,60)
        → Red(239,68,68). Unfilled buckets are shown in dim gray (60,60,60).
        Uses a pre-allocated StringBuilder to avoid O(n²) string concatenation.

    .PARAMETER percent
        Fill percentage (0–100). Values outside this range are clamped.

    .PARAMETER totalWidth
        Total number of ⛁ characters to render. Defaults to 48.

    .OUTPUTS
        System.String — ANSI-escaped bar ready to embed in a console line.
    #>
    function Get-GradientBar($percent, $totalWidth = 48) {
        $filled   = [math]::Min($totalWidth, [math]::Max(0, [math]::Round($percent / 100 * $totalWidth)))
        $r0=$script:GradientStops[0][0]; $g0=$script:GradientStops[0][1]; $b0=$script:GradientStops[0][2]
        $r1=$script:GradientStops[1][0]; $g1=$script:GradientStops[1][1]; $b1=$script:GradientStops[1][2]
        $r2=$script:GradientStops[2][0]; $g2=$script:GradientStops[2][1]; $b2=$script:GradientStops[2][2]
        $r3=$script:GradientStops[3][0]; $g3=$script:GradientStops[3][1]; $b3=$script:GradientStops[3][2]
        $sb = [System.Text.StringBuilder]::new($totalWidth * 26)
        for ($i = 1; $i -le $totalWidth; $i++) {
            $pos = if ($totalWidth -gt 1) { ($i-1) / ($totalWidth-1) } else { 0 }
            if ($i -le $filled) {
                if ($pos -le 0.33) {
                    $t = $pos / 0.33
                    $r = [int]($r0 + $t*($r1-$r0)); $g = [int]($g0 + $t*($g1-$g0)); $b = [int]($b0 + $t*($b1-$b0))
                } elseif ($pos -le 0.66) {
                    $t = ($pos-0.33) / 0.33
                    $r = [int]($r1 + $t*($r2-$r1)); $g = [int]($g1 + $t*($g2-$g1)); $b = [int]($b1 + $t*($b2-$b1))
                } else {
                    $t = ($pos-0.66) / 0.34
                    $r = [int]($r2 + $t*($r3-$r2)); $g = [int]($g2 + $t*($g3-$g2)); $b = [int]($b2 + $t*($b3-$b2))
                }
                [void]$sb.Append("$e[38;2;${r};${g};${b}m${charBucket}${cReset}")
            } else {
                [void]$sb.Append("$script:cDimGray${charBucket}${cReset}")
            }
        }
        return $sb.ToString()
    }

    <#
    .SYNOPSIS
        Returns the ANSI RGB escape sequence for a percentage along the gradient.

    .PARAMETER percent
        Percentage value (0–100). Clamped to [0, 100].

    .OUTPUTS
        System.String — ANSI escape sequence (e.g. "$e[38;2;74;222;128m").
    #>
    function Get-PctColor($percent) {
        $pos = [math]::Min(1.0, [math]::Max(0.0, $percent / 100))
        $r0=$script:GradientStops[0][0]; $g0=$script:GradientStops[0][1]; $b0=$script:GradientStops[0][2]
        $r1=$script:GradientStops[1][0]; $g1=$script:GradientStops[1][1]; $b1=$script:GradientStops[1][2]
        $r2=$script:GradientStops[2][0]; $g2=$script:GradientStops[2][1]; $b2=$script:GradientStops[2][2]
        $r3=$script:GradientStops[3][0]; $g3=$script:GradientStops[3][1]; $b3=$script:GradientStops[3][2]
        if ($pos -le 0.33) {
            $t=$pos/0.33
            $r=[int]($r0+$t*($r1-$r0)); $g=[int]($g0+$t*($g1-$g0)); $b=[int]($b0+$t*($b1-$b0))
        } elseif ($pos -le 0.66) {
            $t=($pos-0.33)/0.33
            $r=[int]($r1+$t*($r2-$r1)); $g=[int]($g1+$t*($g2-$g1)); $b=[int]($b1+$t*($b2-$b1))
        } else {
            $t=($pos-0.66)/0.34
            $r=[int]($r2+$t*($r3-$r2)); $g=[int]($g2+$t*($g3-$g2)); $b=[int]($b2+$t*($b3-$b2))
        }
        return "$e[38;2;${r};${g};${b}m"
    }

    # 6. Git Branch + Status — 8s cache, invalidated on path or HEAD change (4e)
    $branch = ""; $staged = 0; $modified = 0
    if (Test-Path $path -PathType Container) {
        $headRef = ''
        try { $headRef = (Get-Content (Join-Path $path '.git\HEAD') -Raw -ErrorAction Stop).Trim() } catch {}
        $branch = $null
        if (Test-Path $GIT_CACHE) {
            $gc = (Get-Content $GIT_CACHE -Raw) | ConvertFrom-Json -ErrorAction SilentlyContinue
            $gcValid = $false
            if ($gc -and $gc.expires) { try { $gcValid = $now -lt [DateTime]::Parse($gc.expires, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {} }
            if ($gc -and $gc.path -eq $path -and $gc.head_ref -eq $headRef -and $gcValid) {
                $branch   = $gc.branch
                $staged   = [int]$gc.staged
                $modified = [int]$gc.modified
            }
        }
        if ($null -eq $branch) {
            $branch = ""; $staged = 0; $modified = 0
            try {
                $br = git -C $path branch --show-current 2>$null
                if ($br) {
                    $branch = $br
                    foreach ($line in (git -C $path status --porcelain 2>$null)) {
                        if ($line.Length -ge 2) {
                            if ($line[0] -ne ' ' -and $line[0] -ne '?') { $staged++ }
                            if ($line[1] -ne ' ' -and $line[1] -ne '?') { $modified++ }
                        }
                    }
                }
            } catch {}
            $gitObj = [PSCustomObject]@{
                branch   = $branch
                staged   = $staged
                modified = $modified
                path     = $path
                head_ref = $headRef
                expires  = $now.AddSeconds($GIT_TTL).ToString("o")
            }
            if ($null -ne $gitObj.branch -and $null -ne $gitObj.path) {
                [System.IO.File]::WriteAllText($GIT_CACHE,
                    ($gitObj | ConvertTo-Json -Compress),
                    (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    $branchStr = ""
    if ($branch) {
        $gitSuffix = ""
        if ($staged   -gt 0) { $gitSuffix += " ${cGreen}+$staged${cReset}" }
        if ($modified -gt 0) { $gitSuffix += " ${cYellow}~$modified${cReset}" }
        $branchStr = " " + $icoLeaf + " " + $cBranch + "Branch" + $cReset + ": " + $branch + $gitSuffix
    }

    # Stale-while-revalidate visual indicators (TASK-4b)
    $staleFlag = if ($cacheState -eq 'stale' -and $cacheAge -gt ($USAGE_TTL * 2)) { "$([char]0x26A0) " } else { '' }
    $uvc       = if ($cacheState -eq 'missing') { $cGray  } else { '' }
    $ucr       = if ($cacheState -eq 'missing') { $cReset } else { '' }
    $pc5hDisp  = if ($cacheState -eq 'missing') { $cGray  } else { Get-PctColor $u5h }
    $pcWkDisp  = if ($cacheState -eq 'missing') { $cGray  } else { Get-PctColor $uWk }

    # --- FINAL OUTPUT ---
    $sep100 = $script:Sep100

    # Pre-compute gradient bars
    $ctxBar = Get-GradientBar $pct 92
    $u5hBar = Get-GradientBar $u5h 49
    $uWkBar = Get-GradientBar $uWk 49

    # Pre-compute extra usage values
    $usedFmt    = Format-Currency $usedCredits
    $monthFmt   = Format-Currency $monthLimit
    $balanceVal = if (($null -ne $monthLimit) -and ($null -ne $usedCredits)) { $monthLimit - $usedCredits } else { $null }
    $balanceFmt = Format-Currency $balanceVal
    $extraColor = if ($extraUsage -eq $true) { $cGreen } else { $cOrange }
    $extraLabel = if ($extraUsage -eq $true) { "True" } else { "False" }

    # Single write — StringBuilder pre-allocated to ~4 KB
    $sb = [System.Text.StringBuilder]::new(4096)
    # Line 1: ENV: Model (ctx) | Effort: X | 📁 dir | 🌿 Branch: main +S~M
    [void]$sb.AppendLine("${cWhite}ENV:$cReset$cCyan $model$cReset $cGray(${ctxMaxFmt} token)$cReset | ${cWhite}$($script:I18nFmt.Effort):$cReset $effort | $icoFolder ${cWhite}$dir$cReset |$branchStr")
    [void]$sb.AppendLine($sep100)
    # Line 2: Session tokens — IN | OUT | Cached | Total
    [void]$sb.AppendLine("${cWhite}CONTEXT_WINDOW$cReset | ${cWhite}IN:$cReset $(Format-Tokens $tokIn) | ${cWhite}OUT:$cReset $(Format-Tokens $tokOut) | ${cWhite}Cached:$cReset $(Format-Tokens $tokCached) | ${cWhite}Total:$cReset $(Format-Tokens $tokTotal)")
    [void]$sb.AppendLine($sep100)
    # Line CONTEXT: label(9) + bar(92) + " XXX%" (5) = 106
    [void]$sb.AppendLine("${cWhite}CONTEXT:$cReset $ctxBar $(Get-PctColor $pct)$("{0,3}%" -f $pct)$cReset")
    [void]$sb.AppendLine($sep100)
    # Line USAGE 5H: label(10) + bar(49) + " XXX% | RST: DDD dd/MM H: HH:mm [remaining]"
    [void]$sb.AppendLine("${cWhite}USAGE 5H:$cReset $u5hBar $pc5hDisp$staleFlag$("{0,3}%" -f $u5h)$cReset | ${cYellow}RST:$cReset $uvc$r5h$ucr$(Get-Remaining $usageData.five_hour.resets_at)")
    [void]$sb.AppendLine($sep100)
    # Line USAGE WK: label(10) + bar(49) + " XXX% | RST: DDD dd/MM H: HH:mm [remaining]"
    [void]$sb.AppendLine("${cWhite}USAGE WK:$cReset $uWkBar $pcWkDisp$staleFlag$("{0,3}%" -f $uWk)$cReset | ${cYellow}RST:$cReset $uvc$rWk$ucr$(Get-Remaining $usageData.seven_day.resets_at)")
    [void]$sb.AppendLine($sep100)
    # Line EXTRA USAGE: status | USED | MONTH | UTIL | BALANCE
    [void]$sb.AppendLine("${cWhite}XTRA USG:$cReset $extraColor$extraLabel$cReset | ${cWhite}USED:$cReset $uvc$usedFmt$ucr | ${cWhite}MONTH:$cReset $uvc$monthFmt$ucr | ${cWhite}UTIL:$cReset $uvc$monthUtil$ucr | ${cWhite}BALANCE:$cReset $uvc$balanceFmt$ucr")
    [void]$sb.AppendLine($sep100)
    [Console]::Write($sb.ToString())

} catch {
    Write-Host ("$($script:I18nFmt.Error): execution failed")
}
