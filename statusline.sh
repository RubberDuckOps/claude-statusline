#!/usr/bin/env bash
# statusline.sh — HUD for Claude Code (Linux/macOS/WSL)
# Bash port of statusline.ps1
# Dependencies: jq, curl, git, awk, date, stat
set -uo pipefail

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------
readonly USAGE_TTL=120    # seconds — Anthropic API call
readonly GIT_TTL=8        # seconds — git branch + status
readonly EFFORT_TTL=30    # seconds — settings file read
readonly ERROR_TTL=30     # seconds — API error backoff (4d)
readonly API_TIMEOUT=3    # seconds — HTTP API call timeout
readonly STDIN_MAX_BYTES=1048576  # 1 MB — sanity cap on stdin payload
readonly CRED_MAX_BYTES=65536     # 64 KB — credentials file is never legitimately large
readonly API_RESPONSE_MAX_BYTES=1048576  # 1 MB — sanity cap on API response
readonly SETTINGS_MAX_BYTES=262144       # 256 KB — settings files are never legitimately large

readonly CACHE_DIR="${TMPDIR:-/tmp}"
readonly USAGE_CACHE="${CACHE_DIR}/claude_usage_cache.json"
readonly USAGE_ERROR_CACHE="${CACHE_DIR}/claude_usage_error.json"
readonly GIT_CACHE="${CACHE_DIR}/claude_git_cache.json"
readonly EFFORT_CACHE="${CACHE_DIR}/claude_effort_cache.json"

# OAuth credentials file (with fallback path)
CRED_FILE="$HOME/.claude/.credentials.json"
[[ -f "$CRED_FILE" ]] || CRED_FILE="$HOME/.config/claude/.credentials.json"
readonly CRED_FILE

# ---------------------------------------------------------------------------
# GNU vs BSD detection (done once)
# ---------------------------------------------------------------------------
if date --version 2>/dev/null | grep -q GNU; then
    readonly DATE_IS_GNU=1
else
    readonly DATE_IS_GNU=0
fi

if stat --version 2>/dev/null | grep -q GNU; then
    readonly STAT_IS_GNU=1
else
    readonly STAT_IS_GNU=0
fi

# ---------------------------------------------------------------------------
# LOCALE AND CURRENCY DETECTION
# ---------------------------------------------------------------------------
_raw_locale="${LC_MONETARY:-${LC_ALL:-${LANG:-}}}"
_raw_locale="${_raw_locale%%.*}"
_raw_locale="${_raw_locale//-/_}"
_SYS_LOCALE="${_raw_locale:-}"

# ---------------------------------------------------------------------------
# _init_currency
# Initialises locale-specific currency formatting globals from _SYS_LOCALE.
#
# Reads _SYS_LOCALE and sets the CURR_* globals used by fmt_currency.
# Falls back to US dollar formatting for unrecognised locales.
#
# Globals set (all readonly after this call):
#   CURR_SYMBOL    — currency symbol (e.g. "€", "$")
#   CURR_DEC_SEP   — decimal separator ("," or ".")
#   CURR_SYM_BEFORE — "1" if symbol precedes amount, "0" if it follows
#   CURR_SYM_SPACE  — "1" if a space separates symbol from amount
#   CURR_DECIMALS  — number of decimal places (0 or 2)
# ---------------------------------------------------------------------------
_init_currency() {
    local sym dec sym_before sym_space dec_places
    case "$_SYS_LOCALE" in
        it_IT|de_DE|fr_FR|es_ES|pt_PT) sym=$'\u20ac'; dec=','; sym_before=0; sym_space=1; dec_places=2 ;;
        en_US|en_AU|en_CA)             sym='$';       dec='.'; sym_before=1; sym_space=0; dec_places=2 ;;
        en_GB)                         sym=$'\u00a3'; dec='.'; sym_before=1; sym_space=0; dec_places=2 ;;
        ja_JP)                         sym=$'\u00a5'; dec='.'; sym_before=1; sym_space=0; dec_places=0 ;;
        zh_CN|zh_TW)                   sym=$'\u00a5'; dec='.'; sym_before=1; sym_space=0; dec_places=2 ;;
        fr_CH|de_CH|it_CH)             sym='CHF'; dec='.'; sym_before=1; sym_space=1; dec_places=2 ;;
        pt_BR)                         sym='R$';  dec=','; sym_before=1; sym_space=0; dec_places=2 ;;
        *)                             sym='$';   dec='.'; sym_before=1; sym_space=0; dec_places=2 ;;
    esac
    readonly CURR_SYMBOL="$sym"
    readonly CURR_DEC_SEP="$dec"
    readonly CURR_SYM_BEFORE="$sym_before"
    readonly CURR_SYM_SPACE="$sym_space"
    readonly CURR_DECIMALS="$dec_places"
}
_init_currency

# ---------------------------------------------------------------------------
# _init_date_fmt
# Initialises locale-specific date/time formatting globals from _SYS_LOCALE.
#
# Globals set (all readonly after this call):
#   DATE_DAY_NAMES — indexed array of abbreviated weekday names (index 1=Mon…7=Sun)
#   DATE_ORDER     — "DMY" or "MDY" field order for date display
#   DATE_SEP       — date field separator ("/" or ".")
#   DATE_H24       — 1 for 24-hour clock, 0 for 12-hour AM/PM
# ---------------------------------------------------------------------------
_init_date_fmt() {
    local order sep h24
    local -a days_arr
    case "$_SYS_LOCALE" in
        it_IT|it_CH)         days_arr=("" "LUN" "MAR" "MER" "GIO" "VEN" "SAB" "DOM"); order="DMY"; sep="/"; h24=1 ;;
        de_DE|de_CH)         days_arr=("" "MO"  "DI"  "MI"  "DO"  "FR"  "SA"  "SO" ); order="DMY"; sep="."; h24=1 ;;
        fr_FR|fr_CH)         days_arr=("" "LUN" "MAR" "MER" "JEU" "VEN" "SAM" "DIM"); order="DMY"; sep="/"; h24=1 ;;
        es_ES)               days_arr=("" "LUN" "MAR" "MIE" "JUE" "VIE" "SAB" "DOM"); order="DMY"; sep="/"; h24=1 ;;
        pt_PT|pt_BR)         days_arr=("" "SEG" "TER" "QUA" "QUI" "SEX" "SAB" "DOM"); order="DMY"; sep="/"; h24=1 ;;
        en_US|en_AU|en_CA)   days_arr=("" "MON" "TUE" "WED" "THU" "FRI" "SAT" "SUN"); order="MDY"; sep="/"; h24=0 ;;
        en_GB)               days_arr=("" "MON" "TUE" "WED" "THU" "FRI" "SAT" "SUN"); order="DMY"; sep="/"; h24=1 ;;
        ja_JP)               days_arr=("" "MON" "TUE" "WED" "THU" "FRI" "SAT" "SUN"); order="MDY"; sep="/"; h24=1 ;;
        zh_CN|zh_TW)         days_arr=("" "MON" "TUE" "WED" "THU" "FRI" "SAT" "SUN"); order="DMY"; sep="/"; h24=1 ;;
        *)                   days_arr=("" "MON" "TUE" "WED" "THU" "FRI" "SAT" "SUN"); order="MDY"; sep="/"; h24=0 ;;
    esac
    DATE_DAY_NAMES=("${days_arr[@]}")
    readonly DATE_ORDER="$order" DATE_SEP="$sep" DATE_H24="$h24"
}
_init_date_fmt

# ---------------------------------------------------------------------------
# _init_i18n
# Initialises localised UI strings from _SYS_LOCALE.
#
# Globals set (all readonly after this call):
#   I18N_EFFORT — translated label for "Effort" (e.g. "Aufwand" in de_DE)
#   I18N_NA     — localised not-available string (e.g. "N/D" in it_IT)
#   I18N_ERROR  — error prefix shown in the statusline on failure
# ---------------------------------------------------------------------------
_init_i18n() {
    local lang2="${_SYS_LOCALE:0:2}"
    case "$lang2" in
        it) I18N_EFFORT="Effort";   I18N_NA="N/D"; I18N_ERROR="ERRORE STATUSBAR";      I18N_REM_PRE="mancano "; I18N_REM_POST="" ;;
        de) I18N_EFFORT="Aufwand";  I18N_NA="N/A"; I18N_ERROR="STATUSLEISTE FEHLER";   I18N_REM_PRE="noch ";     I18N_REM_POST="" ;;
        fr) I18N_EFFORT="Effort";   I18N_NA="N/V"; I18N_ERROR="ERREUR STATUSBAR";      I18N_REM_PRE="reste ";    I18N_REM_POST="" ;;
        es) I18N_EFFORT="Esfuerzo"; I18N_NA="N/V"; I18N_ERROR="ERROR STATUSBAR";       I18N_REM_PRE="faltan ";   I18N_REM_POST="" ;;
        pt) I18N_EFFORT="Esforco";  I18N_NA="N/D"; I18N_ERROR="ERRO STATUSBAR";        I18N_REM_PRE="faltam ";   I18N_REM_POST="" ;;
        *)  I18N_EFFORT="Effort";   I18N_NA="N/A"; I18N_ERROR="STATUS ERROR";          I18N_REM_PRE="";          I18N_REM_POST=" left" ;;
    esac
    readonly I18N_EFFORT I18N_NA I18N_ERROR I18N_REM_PRE I18N_REM_POST
}
_init_i18n

# ---------------------------------------------------------------------------
# ANSI COLOR CONSTANTS (computed once at load time)
# ---------------------------------------------------------------------------
readonly _ESC=$'\033'
readonly cReset="${_ESC}[0m"
readonly cCyan="${_ESC}[36m"
readonly cGreen="${_ESC}[32m"
readonly cYellow="${_ESC}[33m"
readonly cGray="${_ESC}[90m"
readonly cWhite="${_ESC}[37m"
readonly cBranch="${_ESC}[38;2;186;230;253m"
readonly cOrange="${_ESC}[38;2;255;165;0m"
readonly icoFolder=$'\U1F4C1'   # 📁
readonly icoLeaf=$'\U1F33F'     # 🌿
readonly _SEP90="${cGray}$(printf '%.0s─' {1..90})${cReset}"

# Gradient color stops (shared by get_gradient_bar and get_pct_color)
readonly _GRAD_R0=74  _GRAD_G0=222 _GRAD_B0=128   # green
readonly _GRAD_R1=250 _GRAD_G1=204 _GRAD_B1=21    # yellow
readonly _GRAD_R2=251 _GRAD_G2=146 _GRAD_B2=60    # orange
readonly _GRAD_R3=239 _GRAD_G3=68  _GRAD_B3=68    # red

# ---------------------------------------------------------------------------
# ERROR HANDLING
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# _cleanup
# EXIT trap handler: removes the in-flight temp file if the script is
# interrupted mid-write, preventing a partial cache file from being left on
# disk.
#
# Globals:
#   _TMP_FILE — path of the mktemp file currently being written (may be empty)
# ---------------------------------------------------------------------------
_cleanup() {
    [[ -n "${_TMP_FILE:-}" ]] && rm -f "$_TMP_FILE"
}
trap '_cleanup' EXIT

# ---------------------------------------------------------------------------
# is_cache_valid FILE TTL
# Returns 0 (true) if the file exists and is newer than TTL seconds
# ---------------------------------------------------------------------------
is_cache_valid() {
    local file="$1" ttl="$2"
    [[ -f "$file" ]] || return 1
    local mtime now
    if (( STAT_IS_GNU )); then
        mtime=$(stat -c %Y "$file" 2>/dev/null) || return 1
    else
        mtime=$(stat -f %m "$file" 2>/dev/null) || return 1
    fi
    now=$(date +%s)
    (( now - mtime < ttl ))
}

# ---------------------------------------------------------------------------
# atomic_write TARGET CONTENT
# Atomic file write (mktemp → mv), 0600 permissions guaranteed by mktemp
# ---------------------------------------------------------------------------
atomic_write() {
    local target="$1" content="$2"
    _TMP_FILE=$(mktemp "${CACHE_DIR}/claude_tmp_XXXXXX")
    printf '%s' "$content" > "$_TMP_FILE" && mv -f "$_TMP_FILE" "$target"
    _TMP_FILE=""
}

# ---------------------------------------------------------------------------
# fmt_date RAW_DATE
# Converts an ISO8601 date to the localised format "DDD dd/MM H: HH:mm"
# ---------------------------------------------------------------------------
fmt_date() {
    local raw="$1"
    [[ -z "$raw" ]] && echo "$I18N_NA" && return
    local epoch
    local time_fmt
    if (( DATE_H24 )); then time_fmt="%H:%M"; else time_fmt="%I:%M %p"; fi
    local dow dd mm time_str parts
    if (( DATE_IS_GNU )); then
        epoch=$(date -d "$raw" +%s 2>/dev/null) || { echo "$I18N_NA"; return; }
        parts=$(date -d "@$epoch" "+%u %d %m $time_fmt" 2>/dev/null) \
            || { echo "$I18N_NA"; return; }
    else
        local raw_clean="${raw%Z}"
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$raw" +%s 2>/dev/null) \
            || epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$raw_clean" +%s 2>/dev/null) \
            || { echo "$I18N_NA"; return; }
        parts=$(date -r "$epoch" "+%u %d %m $time_fmt" 2>/dev/null) \
            || { echo "$I18N_NA"; return; }
    fi
    # read -r: last var (time_str) captures remainder including spaces (e.g. "02:30 PM")
    read -r dow dd mm time_str <<< "$parts"
    local date_str
    if [[ "$DATE_ORDER" == "MDY" ]]; then date_str="${mm}${DATE_SEP}${dd}"
    else                                  date_str="${dd}${DATE_SEP}${mm}"; fi
    echo "${DATE_DAY_NAMES[$dow]} $date_str H: $time_str"
}

# ---------------------------------------------------------------------------
# fmt_remaining RAW_DATE
# Returns " [pre HH:MM post]" (time left until reset), or "" if elapsed/missing.
# ---------------------------------------------------------------------------
fmt_remaining() {
    local raw="$1"
    [[ -z "$raw" ]] && return
    local now_epoch target_epoch delta
    if (( DATE_IS_GNU )); then
        target_epoch=$(date -d "$raw" +%s 2>/dev/null) || return
    else
        local raw_clean="${raw%Z}"
        target_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$raw" +%s 2>/dev/null) \
            || target_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$raw_clean" +%s 2>/dev/null) \
            || return
    fi
    now_epoch=$(date +%s)
    delta=$(( target_epoch - now_epoch ))
    (( delta <= 0 )) && return
    local h=$(( delta / 3600 ))
    local m=$(( (delta % 3600) / 60 ))
    printf ' [%s%02d:%02d%s]' "$I18N_REM_PRE" "$h" "$m" "$I18N_REM_POST"
}

# ---------------------------------------------------------------------------
# fmt_tokens N
# Formats a token count: ">= 1000" → "X.XK", otherwise integer
# ---------------------------------------------------------------------------
fmt_tokens() {
    local n="$1"
    awk -v n="$n" 'BEGIN {
        if (n >= 1000) printf "%.1fK\n", n/1000
        else            printf "%d\n",   n
    }'
}

# ---------------------------------------------------------------------------
# fmt_currency CENTS
# Converts cents to locale-formatted currency string
# ---------------------------------------------------------------------------
fmt_currency() {
    local cents="$1"
    [[ "$cents" == "null" || -z "$cents" ]] && echo "$I18N_NA" && return
    awk -v c="$cents" -v sym="$CURR_SYMBOL" -v dec="$CURR_DEC_SEP" \
        -v sym_before="$CURR_SYM_BEFORE" -v sym_space="$CURR_SYM_SPACE" \
        -v decimals="$CURR_DECIMALS" \
    'BEGIN {
        v = c / 100
        fmt = "%." decimals "f"
        s = sprintf(fmt, v)
        gsub(/\./, dec, s)
        sp = (sym_space == "1") ? " " : ""
        if (sym_before == "1") printf "%s%s%s\n", sym, sp, s
        else                   printf "%s%s%s\n", s, sp, sym
    }'
}

# ---------------------------------------------------------------------------
# get_gradient_bar PERCENT TOTAL_WIDTH
# Prints an RGB gradient bar of TOTAL_WIDTH ⛁ characters
# Gradient: Green(74,222,128)→Yellow(250,204,21)→Orange(251,146,60)→Red(239,68,68)
# ---------------------------------------------------------------------------
get_gradient_bar() {
    local percent="$1" total_width="${2:-48}"
    awk -v pct="$percent" -v tw="$total_width" \
        -v r0="$_GRAD_R0" -v g0="$_GRAD_G0" -v b0="$_GRAD_B0" \
        -v r1="$_GRAD_R1" -v g1="$_GRAD_G1" -v b1="$_GRAD_B1" \
        -v r2="$_GRAD_R2" -v g2="$_GRAD_G2" -v b2="$_GRAD_B2" \
        -v r3="$_GRAD_R3" -v g3="$_GRAD_G3" -v b3="$_GRAD_B3" \
    'BEGIN {
        filled = int(pct / 100 * tw + 0.5)
        if (filled > tw) filled = tw
        if (filled < 0)  filled = 0

        ESC = "\033"
        DIM = ESC "[38;2;60;60;60m"
        RST = ESC "[0m"
        BKT = "\342\233\201"   # U+26C1 ⛁ in UTF-8 octal

        for (i = 1; i <= tw; i++) {
            pos = (tw > 1) ? (i-1)/(tw-1) : 0

            if (i <= filled) {
                if (pos <= 0.33) {
                    t = pos / 0.33
                    r = int(r0 + t*(r1-r0))
                    g = int(g0 + t*(g1-g0))
                    b = int(b0 + t*(b1-b0))
                } else if (pos <= 0.66) {
                    t = (pos-0.33) / 0.33
                    r = int(r1 + t*(r2-r1))
                    g = int(g1 + t*(g2-g1))
                    b = int(b1 + t*(b2-b1))
                } else {
                    t = (pos-0.66) / 0.34
                    r = int(r2 + t*(r3-r2))
                    g = int(g2 + t*(g3-g2))
                    b = int(b2 + t*(b3-b2))
                }
                printf "%s[38;2;%d;%d;%dm%s%s", ESC, r, g, b, BKT, RST
            } else {
                printf "%s%s%s", DIM, BKT, RST
            }
        }
        printf "\n"
    }'
}

# ---------------------------------------------------------------------------
# get_pct_color PERCENT
# Prints the ANSI RGB color code corresponding to the percentage
# ---------------------------------------------------------------------------
get_pct_color() {
    local percent="$1"
    awk -v pct="$percent" \
        -v r0="$_GRAD_R0" -v g0="$_GRAD_G0" -v b0="$_GRAD_B0" \
        -v r1="$_GRAD_R1" -v g1="$_GRAD_G1" -v b1="$_GRAD_B1" \
        -v r2="$_GRAD_R2" -v g2="$_GRAD_G2" -v b2="$_GRAD_B2" \
        -v r3="$_GRAD_R3" -v g3="$_GRAD_G3" -v b3="$_GRAD_B3" \
    'BEGIN {
        ESC = "\033"
        pos = pct / 100
        if (pos < 0) pos = 0
        if (pos > 1) pos = 1

        if (pos <= 0.33) {
            t = pos / 0.33
            r = int(r0 + t*(r1-r0)); g = int(g0 + t*(g1-g0)); b = int(b0 + t*(b1-b0))
        } else if (pos <= 0.66) {
            t = (pos-0.33) / 0.33
            r = int(r1 + t*(r2-r1)); g = int(g1 + t*(g2-g1)); b = int(b1 + t*(b2-b1))
        } else {
            t = (pos-0.66) / 0.34
            r = int(r2 + t*(r3-r2)); g = int(g2 + t*(g3-g2)); b = int(b2 + t*(b3-b2))
        }
        printf "%s[38;2;%d;%d;%dm", ESC, r, g, b
    }'
}

# ---------------------------------------------------------------------------
# fetch_usage
# Loads usage data from the Anthropic API (with USAGE_CACHE caching)
# ---------------------------------------------------------------------------
fetch_usage() {
    if is_cache_valid "$USAGE_CACHE" "$USAGE_TTL"; then
        return 0
    fi

    # 4d: skip API if a fresh error is cached (prevents hammering with expired token)
    if is_cache_valid "$USAGE_ERROR_CACHE" "$ERROR_TTL"; then
        return 1
    fi

    [[ -f "$CRED_FILE" ]] || return 1

    local cred_size
    cred_size=$(stat -c %s "$CRED_FILE" 2>/dev/null || stat -f %z "$CRED_FILE" 2>/dev/null)
    [[ "${cred_size:-0}" -gt "$CRED_MAX_BYTES" ]] && return 1

    local token
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null)
    [[ -z "$token" ]] && return 1
    [[ "$token" =~ [^[:print:]] ]] && return 1  # reject control characters (header injection)

    local response
    response=$(curl -sf --max-time "$API_TIMEOUT" \
        --max-filesize "$API_RESPONSE_MAX_BYTES" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || {
        atomic_write "$USAGE_ERROR_CACHE" \
            "$(jq -n --arg e 'curl_failed' --argjson t "$(date +%s)" '{"error":$e,"timestamp":$t}')"
        return 1
    }

    # Validate structure before writing: must contain expected fields
    if printf '%s' "$response" | jq -e '.five_hour and .seven_day' >/dev/null 2>&1; then
        atomic_write "$USAGE_CACHE" "$response"
        rm -f "$USAGE_ERROR_CACHE"
    else
        atomic_write "$USAGE_ERROR_CACHE" \
            "$(jq -n --arg e 'invalid_response' --argjson t "$(date +%s)" '{"error":$e,"timestamp":$t}')"
    fi
}

# ---------------------------------------------------------------------------
# read_effort_cascade WORKSPACE_PATH
# Reads effortLevel from settings files with EFFORT_CACHE caching
# ---------------------------------------------------------------------------
read_effort_cascade() {
    local workspace_path="$1"

    if is_cache_valid "$EFFORT_CACHE" "$EFFORT_TTL"; then
        jq -r '.effort // "normal"' "$EFFORT_CACHE" 2>/dev/null && return
    fi

    local effort=""
    local settings_files=(
        "${workspace_path}/.claude/settings.local.json"
        "${workspace_path}/.claude/settings.json"
        "$HOME/.claude/settings.local.json"
        "$HOME/.claude/settings.json"
    )

    local sp
    for sp in "${settings_files[@]}"; do
        if [[ -f "$sp" ]]; then
            local sp_size
            sp_size=$(stat -c %s "$sp" 2>/dev/null || stat -f %z "$sp" 2>/dev/null)
            [[ "${sp_size:-0}" -gt "$SETTINGS_MAX_BYTES" ]] && continue
            local val
            val=$(jq -r '.effortLevel // empty' "$sp" 2>/dev/null)
            if [[ -n "$val" ]]; then
                effort="$val"
                break
            fi
        fi
    done

    [[ -z "$effort" ]] && effort="normal"

    local cache_content
    cache_content=$(jq -n --arg e "$effort" '{"effort": $e}')
    if [[ -n "$effort" ]]; then
        atomic_write "$EFFORT_CACHE" "$cache_content"
    fi

    echo "$effort"
}

# ---------------------------------------------------------------------------
# read_git_status WORKSPACE_PATH
# Reads branch + staged/modified with GIT_CACHE caching
# Prints to stdout: "BRANCH\nSTAGED\nMODIFIED"
# ---------------------------------------------------------------------------
read_git_status() {
    local workspace_path="$1"

    # 4e: reads .git/HEAD without git subprocesses (simple file read)
    local head_ref=""
    [[ -f "${workspace_path}/.git/HEAD" ]] && \
        IFS= read -r head_ref < "${workspace_path}/.git/HEAD" 2>/dev/null || true

    if is_cache_valid "$GIT_CACHE" "$GIT_TTL"; then
        local cached_path cached_head_ref cached_branch cached_staged cached_modified
        { read -r cached_path; read -r cached_head_ref;
          read -r cached_branch; read -r cached_staged; read -r cached_modified; } \
            < <(jq -r '(.path // ""), (.head_ref // ""), (.branch // ""),
                        (.staged // 0 | tostring), (.modified // 0 | tostring)' \
                "$GIT_CACHE" 2>/dev/null)
        if [[ "$cached_path" == "$workspace_path" && "$cached_head_ref" == "$head_ref" ]]; then
            printf '%s\n%s\n%s\n' "$cached_branch" "$cached_staged" "$cached_modified"
            return
        fi
    fi

    local branch="" staged=0 modified=0

    if [[ -d "$workspace_path" ]]; then
        branch=$(git -C "$workspace_path" branch --show-current 2>/dev/null) || branch=""

        if [[ -n "$branch" ]]; then
            while IFS= read -r line; do
                [[ ${#line} -lt 2 ]] && continue
                local xy="${line:0:1}" y="${line:1:1}"
                [[ "$xy" != " " && "$xy" != "?" ]] && (( staged++ ))
                [[ "$y"  != " " && "$y"  != "?" ]] && (( modified++ ))
            done < <(git -C "$workspace_path" status --porcelain 2>/dev/null)
        fi
    fi

    local cache_content
    cache_content=$(jq -n \
        --arg branch   "$branch" \
        --argjson staged   "$staged" \
        --argjson modified "$modified" \
        --arg path     "$workspace_path" \
        --arg head_ref "$head_ref" \
        '{"branch": $branch, "staged": $staged, "modified": $modified, "path": $path, "head_ref": $head_ref}')
    if printf '%s' "$cache_content" | jq -e '.branch != null and .path != null' >/dev/null 2>&1; then
        atomic_write "$GIT_CACHE" "$cache_content"
    fi

    printf '%s\n%s\n%s\n' "$branch" "$staged" "$modified"
}

# ---------------------------------------------------------------------------
# main
# Entry point: reads Claude Code telemetry JSON from stdin, enriches it with
# git status, effort level from the settings cascade, and Anthropic OAuth API
# usage metrics, then prints the 6-line ANSI RGB HUD to stdout.
#
# Data flow:
#   stdin (JSON, ≤1 MB) → jq parse → git/effort/usage enrichment → 6-line output
#
# Arguments:  none (all input via stdin)
# Outputs:    6 lines of ANSI RGB text written to stdout
# Returns:    0 on success; non-zero propagated via "|| printf error" wrapper
# ---------------------------------------------------------------------------
main() {
    # -----------------------------------------------------------------------
    # 1. Read JSON from stdin
    # -----------------------------------------------------------------------
    local input_raw
    input_raw=$(head -c "$STDIN_MAX_BYTES")
    [[ -z "${input_raw// }" ]] && input_raw='{}'

    # Extract all fields in a single jq call
    local model workspace_path pct ctx_max tok_in tok_out tok_cached
    {
        read -r model
        read -r workspace_path
        read -r pct
        read -r ctx_max
        read -r tok_in
        read -r tok_out
        read -r tok_cached
    } < <(printf '%s' "$input_raw" | jq -r '
        (.model.display_name // "Claude"),
        (.workspace.current_dir // "."),
        ((.context_window.used_percentage // 0) | floor | tostring),
        ((.context_window.context_window_size // 200000) | tostring),
        ((.context_window.total_input_tokens // 0) | tostring),
        ((.context_window.total_output_tokens // 0) | tostring),
        ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring)
    ')

    # Format ctx_max
    local ctx_max_fmt
    ctx_max_fmt=$(awk -v n="$ctx_max" 'BEGIN {
        if (n >= 1000000) printf "%.0fM\n", n/1000000
        else if (n >= 1000) printf "%.0fK\n", n/1000
        else printf "%d\n", n
    }')

    local tok_total=$(( tok_in + tok_out + tok_cached ))

    local tok_in_fmt tok_out_fmt tok_cached_fmt tok_total_fmt
    { read -r tok_in_fmt; read -r tok_out_fmt;
      read -r tok_cached_fmt; read -r tok_total_fmt; } \
        < <(awk -v a="$tok_in" -v b="$tok_out" -v c="$tok_cached" -v d="$tok_total" \
            'function f(n) { return (n>=1000) ? sprintf("%.1fK", n/1000) : int(n) }
             BEGIN { print f(a); print f(b); print f(c); print f(d) }')

    # -----------------------------------------------------------------------
    # 2. Effort (cache 30s)
    # -----------------------------------------------------------------------
    local effort_raw effort
    effort_raw=$(read_effort_cascade "$workspace_path")

    case "$effort_raw" in
        low)    effort="Low"    ;;
        medium) effort="Medium" ;;
        high)   effort="High"   ;;
        max)    effort="Max"    ;;
        *)      effort="Not Set" ;;
    esac

    # -----------------------------------------------------------------------
    # 3. Usage API Anthropic (cache 120s)
    # -----------------------------------------------------------------------
    fetch_usage || true   # fails silently

    # Cache state after fetch: 'fresh' | 'stale' | 'missing' (TASK-4b)
    local cache_state="missing" cache_age=999999
    if [[ -f "$USAGE_CACHE" ]]; then
        local _cmtime _cnow
        if (( STAT_IS_GNU )); then
            _cmtime=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null) || _cmtime=0
        else
            _cmtime=$(stat -f %m "$USAGE_CACHE" 2>/dev/null) || _cmtime=0
        fi
        _cnow=$(date +%s)
        cache_age=$(( _cnow - _cmtime ))
        if (( cache_age < USAGE_TTL )); then
            cache_state="fresh"
        else
            cache_state="stale"
        fi
    fi

    local u5h=0 uwk=0 r5h="$I18N_NA" rwk="$I18N_NA"
    local extra_usage="" month_limit="null" used_credits="null" month_util="$I18N_NA"

    if [[ -f "$USAGE_CACHE" ]]; then
        local raw_5h_util raw_wk_util raw_5h_reset raw_wk_reset
        local raw_extra raw_month_limit raw_used_credits raw_month_util
        {
            read -r raw_5h_util
            read -r raw_wk_util
            read -r raw_5h_reset
            read -r raw_wk_reset
            read -r raw_extra
            read -r raw_month_limit
            read -r raw_used_credits
            read -r raw_month_util
        } < <(jq -r '
            ((.five_hour.utilization  // 0) | floor | tostring),
            ((.seven_day.utilization  // 0) | floor | tostring),
            (.five_hour.resets_at  // ""),
            (.seven_day.resets_at  // ""),
            (.extra_usage.is_enabled // ""),
            (.extra_usage.monthly_limit // "null"),
            (.extra_usage.used_credits  // "null"),
            ((.extra_usage.utilization  // null) | if . == null then "N/A" else (. * 10 | round / 10 | tostring) + "%" end)
        ' "$USAGE_CACHE" 2>/dev/null)

        u5h="${raw_5h_util:-0}"
        uwk="${raw_wk_util:-0}"
        r5h=$(fmt_date "$raw_5h_reset")
        rwk=$(fmt_date "$raw_wk_reset")
        extra_usage="$raw_extra"
        month_limit="$raw_month_limit"
        used_credits="$raw_used_credits"
        month_util="${raw_month_util:-$I18N_NA}"
    fi

    # -----------------------------------------------------------------------
    # 4. Git branch + status (cache 8s)
    # -----------------------------------------------------------------------
    local branch="" staged=0 modified=0 branch_str=""
    local dir
    dir=$(basename "$workspace_path")

    {
        read -r branch
        read -r staged
        read -r modified
    } < <(read_git_status "$workspace_path")

    # -----------------------------------------------------------------------
    # 6. Git branch string
    # -----------------------------------------------------------------------
    if [[ -n "$branch" ]]; then
        local git_suffix=""
        (( staged   > 0 )) && git_suffix+=" ${cGreen}+${staged}${cReset}"
        (( modified > 0 )) && git_suffix+=" ${cYellow}~${modified}${cReset}"
        branch_str=" ${icoLeaf} ${cBranch}Branch${cReset}: ${branch}${git_suffix}"
    fi

    # -----------------------------------------------------------------------
    # 8. Gradient bars and percentage colors
    # -----------------------------------------------------------------------
    local ctx_bar u5h_bar uwk_bar
    ctx_bar=$(get_gradient_bar "$pct" 76)
    u5h_bar=$(get_gradient_bar "$u5h" 49)
    uwk_bar=$(get_gradient_bar "$uwk" 49)

    local ctx_pct_color u5h_pct_color uwk_pct_color
    ctx_pct_color=$(get_pct_color "$pct")
    u5h_pct_color=$(get_pct_color "$u5h")
    uwk_pct_color=$(get_pct_color "$uwk")

    # -----------------------------------------------------------------------
    # Stale-while-revalidate visual indicators (TASK-4b)
    # -----------------------------------------------------------------------
    local stale_flag="" uvc="" ucr=""
    local u5h_pct_disp="${u5h_pct_color}" uwk_pct_disp="${uwk_pct_color}"
    if [[ "$cache_state" == "stale" ]] && (( cache_age > USAGE_TTL * 2 )); then
        stale_flag=$'\u26a0 '
    fi
    if [[ "$cache_state" == "missing" ]]; then
        uvc="${cGray}"
        ucr="${cReset}"
        u5h_pct_disp="${cGray}"
        uwk_pct_disp="${cGray}"
    fi

    # -----------------------------------------------------------------------
    # 9. EXTRA USAGE line — currency calculation
    # -----------------------------------------------------------------------
    local used_fmt month_fmt balance_fmt
    used_fmt=$(fmt_currency "$used_credits")
    month_fmt=$(fmt_currency "$month_limit")

    # Calculate balance only if both values are valid numbers
    if [[ "$used_credits" != "null" && "$month_limit" != "null" && \
          -n "$used_credits" && -n "$month_limit" ]]; then
        local bal_cents=$(( month_limit - used_credits ))
        balance_fmt=$(fmt_currency "$bal_cents")
    else
        balance_fmt="$I18N_NA"
    fi

    local extra_color extra_label
    if [[ "$extra_usage" == "true" ]]; then
        extra_color="$cGreen"
        extra_label="True"
    else
        extra_color="$cOrange"
        extra_label="False"
    fi

    # -----------------------------------------------------------------------
    # 10. FINAL OUTPUT — 6 lines + separators (single printf)
    # -----------------------------------------------------------------------
    local line1 line2 line3 line4 line5 line6
    line1="${cWhite}ENV:${cReset}${cCyan} ${model}${cReset} ${cGray}(${ctx_max_fmt} token)${cReset} | ${cWhite}${I18N_EFFORT}:${cReset} ${effort} | ${icoFolder} ${cWhite}${dir}${cReset} |${branch_str}"
    line2="${cWhite}CONTEXT_WINDOW${cReset} | ${cWhite}IN:${cReset} ${tok_in_fmt} | ${cWhite}OUT:${cReset} ${tok_out_fmt} | ${cWhite}Cached:${cReset} ${tok_cached_fmt} | ${cWhite}Total:${cReset} ${tok_total_fmt}"
    line3="${cWhite}CONTEXT:${cReset} ${ctx_bar} ${ctx_pct_color}$(printf '%3d%%' "$pct")${cReset}"
    line4="${cWhite}USAGE 5H:${cReset} ${u5h_bar} ${u5h_pct_disp}${stale_flag}$(printf '%3d%%' "$u5h")${cReset} | ${cYellow}RST:${cReset} ${uvc}${r5h}${ucr}$(fmt_remaining "$raw_5h_reset")"
    line5="${cWhite}USAGE WK:${cReset} ${uwk_bar} ${uwk_pct_disp}${stale_flag}$(printf '%3d%%' "$uwk")${cReset} | ${cYellow}RST:${cReset} ${uvc}${rwk}${ucr}$(fmt_remaining "$raw_wk_reset")"
    line6="${cWhite}XTRA USG:${cReset} ${extra_color}${extra_label}${cReset} | ${cWhite}USED:${cReset} ${uvc}${used_fmt}${ucr} | ${cWhite}MONTH:${cReset} ${uvc}${month_fmt}${ucr} | ${cWhite}UTIL:${cReset} ${uvc}${month_util}${ucr} | ${cWhite}BALANCE:${cReset} ${uvc}${balance_fmt}${ucr}"
    local out
    out="${line1}"$'\n'"${_SEP90}"$'\n'"${line2}"$'\n'"${_SEP90}"$'\n'"${line3}"$'\n'"${_SEP90}"$'\n'"${line4}"$'\n'"${_SEP90}"$'\n'"${line5}"$'\n'"${_SEP90}"$'\n'"${line6}"$'\n'"${_SEP90}"
    printf '%s\n' "$out"
}

main "$@" 2>/dev/null || printf '%s: execution failed\n' "$I18N_ERROR"
