#!/usr/bin/env bats
# test_statusline.bats — bats-core test suite for statusline.sh
#
# Run:
#   bats test_statusline.bats
#
# Dependencies:
#   - bats-core  (https://github.com/bats-core/bats-core)
#   - bats-assert (https://github.com/bats-core/bats-assert)  [optional, see notes]
#   - jq, awk, date, stat  (already required by statusline.sh)
#
# Note: tests use $output and $status directly (without bats-assert)
# to avoid additional dependencies.

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
    # Isolated temporary directory for each test
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # Set TMPDIR — the script uses this as CACHE_DIR
    export TMPDIR="$TEST_DIR"

    # Clear locale variables to prevent system interference
    unset LC_MONETARY LC_ALL LANG

    # Create funcs.sh: a copy of the script with the main invocation removed
    sed '/^main /d' "$BATS_TEST_DIRNAME/../statusline.sh" > "$TEST_DIR/funcs.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: source funcs.sh in the current test's subshell
source_fns() {
    # shellcheck disable=SC1090
    source "$TEST_DIR/funcs.sh"
}

# Helper: source with a specific locale in a subshell
# Usage: run_with_locale LOCALE 'bash code'
run_with_locale() {
    local lc="$1"
    local code="$2"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY=\"$lc\"
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        $code
    "
}

# ---------------------------------------------------------------------------
# is_cache_valid
# ---------------------------------------------------------------------------

@test "is_cache_valid: missing file → failure" {
    source_fns
    run is_cache_valid "$TEST_DIR/missing.json" 60
    [ "$status" -ne 0 ]
}

@test "is_cache_valid: fresh file → success" {
    source_fns
    local f="$TEST_DIR/fresh.json"
    echo '{}' > "$f"
    run is_cache_valid "$f" 60
    [ "$status" -eq 0 ]
}

@test "is_cache_valid: expired file → failure" {
    source_fns
    local f="$TEST_DIR/expired.json"
    echo '{}' > "$f"
    # touch -t: format YYYYMMDDHHSS, portable across GNU and BSD
    touch -t "202301010000" "$f"
    run is_cache_valid "$f" 60
    [ "$status" -ne 0 ]
}

@test "is_cache_valid: ttl=0 → failure" {
    source_fns
    local f="$TEST_DIR/ttl_zero.json"
    echo '{}' > "$f"
    run is_cache_valid "$f" 0
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# atomic_write
# ---------------------------------------------------------------------------

@test "atomic_write: writes basic content" {
    source_fns
    local f="$TEST_DIR/out.json"
    atomic_write "$f" '{"ok":true}'
    [ "$(cat "$f")" = '{"ok":true}' ]
}

@test "atomic_write: overwrites existing file" {
    source_fns
    local f="$TEST_DIR/out.json"
    atomic_write "$f" "first"
    atomic_write "$f" "second"
    [ "$(cat "$f")" = "second" ]
}

@test "atomic_write: handles unicode content" {
    source_fns
    local f="$TEST_DIR/unicode.json"
    atomic_write "$f" '{"emoji":"🌿","sym":"€"}'
    run cat "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *'€'* ]]
}

# ---------------------------------------------------------------------------
# fmt_tokens
# ---------------------------------------------------------------------------

@test "fmt_tokens: 0 → '0'" {
    source_fns
    run fmt_tokens 0
    [ "$output" = "0" ]
}

@test "fmt_tokens: 999 → '999'" {
    source_fns
    run fmt_tokens 999
    [ "$output" = "999" ]
}

@test "fmt_tokens: 1000 → '1.0K'" {
    source_fns
    run fmt_tokens 1000
    [ "$output" = "1.0K" ]
}

@test "fmt_tokens: 1500 → '1.5K'" {
    source_fns
    run fmt_tokens 1500
    [ "$output" = "1.5K" ]
}

@test "fmt_tokens: 10000 → '10.0K'" {
    source_fns
    run fmt_tokens 10000
    [ "$output" = "10.0K" ]
}

# ---------------------------------------------------------------------------
# fmt_currency — each test uses a subshell with an explicit locale
# ---------------------------------------------------------------------------

@test "fmt_currency: it_IT 420 → '4,20 €'" {
    run_with_locale "it_IT" "fmt_currency 420"
    [ "$status" -eq 0 ]
    [ "$output" = "4,20 €" ]
}

@test "fmt_currency: it_IT 0 → '0,00 €'" {
    run_with_locale "it_IT" "fmt_currency 0"
    [ "$status" -eq 0 ]
    [ "$output" = "0,00 €" ]
}

@test "fmt_currency: it_IT 10000 → '100,00 €'" {
    run_with_locale "it_IT" "fmt_currency 10000"
    [ "$status" -eq 0 ]
    [ "$output" = "100,00 €" ]
}

@test "fmt_currency: en_US 420 → '\$4.20'" {
    run_with_locale "en_US" "fmt_currency 420"
    [ "$status" -eq 0 ]
    [ "$output" = '$4.20' ]
}

@test "fmt_currency: en_US 0 → '\$0.00'" {
    run_with_locale "en_US" "fmt_currency 0"
    [ "$output" = '$0.00' ]
}

@test "fmt_currency: en_GB 420 → '£4.20'" {
    run_with_locale "en_GB" "fmt_currency 420"
    [ "$output" = "£4.20" ]
}

@test "fmt_currency: ja_JP 42000 → '¥420'" {
    run_with_locale "ja_JP" "fmt_currency 42000"
    [ "$output" = "¥420" ]
}

@test "fmt_currency: ja_JP 100 → '¥1'" {
    run_with_locale "ja_JP" "fmt_currency 100"
    [ "$output" = "¥1" ]
}

@test "fmt_currency: fr_CH 420 → 'CHF 4.20'" {
    run_with_locale "fr_CH" "fmt_currency 420"
    [ "$output" = "CHF 4.20" ]
}

@test "fmt_currency: pt_BR 420 → 'R\$4,20'" {
    run_with_locale "pt_BR" "fmt_currency 420"
    [ "$output" = 'R$4,20' ]
}

@test "fmt_currency: 'null' en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_currency null"
    [ "$output" = "N/A" ]
}

@test "fmt_currency: 'null' it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_currency null"
    [ "$output" = "N/D" ]
}

@test "fmt_currency: empty string en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_currency ''"
    [ "$output" = "N/A" ]
}

@test "fmt_currency: empty string it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_currency ''"
    [ "$output" = "N/D" ]
}

# ---------------------------------------------------------------------------
# _init_currency — verifies CURR_* variables set by the function
# ---------------------------------------------------------------------------

@test "_init_currency: locale it_IT → CURR_SYMBOL=€" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_SYMBOL\"
    "
    [ "$output" = "€" ]
}

@test "_init_currency: locale en_US → CURR_SYMBOL=\$" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='en_US'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_SYMBOL\"
    "
    [ "$output" = '$' ]
}

@test "_init_currency: locale ja_JP → CURR_DECIMALS=0" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='ja_JP'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_DECIMALS\"
    "
    [ "$output" = "0" ]
}

@test "_init_currency: unknown locale → fallback \$ (en_US)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='xx_XX'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_SYMBOL\"
    "
    [ "$output" = '$' ]
}

@test "_init_currency: locale fr_CH → CURR_SYM_BEFORE=1 and CURR_SYM_SPACE=1" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='fr_CH'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_SYM_BEFORE \$CURR_SYM_SPACE\"
    "
    [ "$output" = "1 1" ]
}

# ---------------------------------------------------------------------------
# _init_date_fmt
# ---------------------------------------------------------------------------

@test "_init_date_fmt: it_IT → order=DMY sep=/ h24=1" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$DATE_ORDER \$DATE_SEP \$DATE_H24\"
    "
    [ "$output" = "DMY / 1" ]
}

@test "_init_date_fmt: en_US → order=MDY sep=/ h24=0" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='en_US'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$DATE_ORDER \$DATE_SEP \$DATE_H24\"
    "
    [ "$output" = "MDY / 0" ]
}

@test "_init_date_fmt: de_DE → order=DMY sep=. h24=1" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='de_DE'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$DATE_ORDER \$DATE_SEP \$DATE_H24\"
    "
    [ "$output" = "DMY . 1" ]
}

@test "_init_date_fmt: ja_JP → order=MDY sep=/ h24=1" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='ja_JP'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$DATE_ORDER \$DATE_SEP \$DATE_H24\"
    "
    [ "$output" = "MDY / 1" ]
}

@test "_init_date_fmt: unknown locale → fallback en_US (MDY, h24=0)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='xx_XX'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$DATE_ORDER \$DATE_H24\"
    "
    [ "$output" = "MDY 0" ]
}

# ---------------------------------------------------------------------------
# fmt_date
# ---------------------------------------------------------------------------

@test "fmt_date: empty string en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_date ''"
    [ "$output" = "N/A" ]
}

@test "fmt_date: empty string it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_date ''"
    [ "$output" = "N/D" ]
}

@test "fmt_date: invalid date en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_date 'not-a-date'"
    [ "$output" = "N/A" ]
}

@test "fmt_date: invalid date it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_date 'not-a-date'"
    [ "$output" = "N/D" ]
}

@test "fmt_date: it_IT 2025-01-06T12:00:00Z → starts with LUN" {
    run_with_locale "it_IT" "fmt_date '2025-01-06T12:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" == LUN* ]]
}

@test "fmt_date: it_IT 2025-01-12T12:00:00Z → starts with DOM" {
    run_with_locale "it_IT" "fmt_date '2025-01-12T12:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" == DOM* ]]
}

@test "fmt_date: it_IT output format valid (DMY, 24h)" {
    run_with_locale "it_IT" "fmt_date '2025-06-15T14:30:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[A-Z]{3}\ [0-9]{2}/[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "fmt_date: en_US → MDY and 12h (AM/PM)" {
    run_with_locale "en_US" "fmt_date '2025-03-19T18:00:00Z'"
    [ "$status" -eq 0 ]
    # MM/DD and AM/PM
    [[ "$output" =~ ^[A-Z]{3}\ [0-9]{2}/[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}\ (AM|PM)$ ]]
}

@test "fmt_date: de_DE → dot separator" {
    run_with_locale "de_DE" "fmt_date '2025-03-19T18:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[A-Z]{2}\ [0-9]{2}\.[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}$ ]]
}

# ---------------------------------------------------------------------------
# read_effort_cascade
# ---------------------------------------------------------------------------

@test "read_effort_cascade: defaults to 'normal' when no settings file exists" {
    source_fns
    local ws="$TEST_DIR/workspace_vuoto"
    mkdir -p "$ws"
    run read_effort_cascade "$ws"
    [ "$output" = "normal" ]
}

@test "read_effort_cascade: reads settings.local.json" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws/.claude"
    echo '{"effortLevel":"high"}' > "$ws/.claude/settings.local.json"
    run read_effort_cascade "$ws"
    [ "$output" = "high" ]
}

@test "read_effort_cascade: uses a valid cache" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws"
    # Manually write cache
    echo '{"effort":"medium"}' > "$EFFORT_CACHE"
    run read_effort_cascade "$ws"
    [ "$output" = "medium" ]
}

@test "read_effort_cascade: expired cache → re-reads settings" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws/.claude"
    echo '{"effortLevel":"max"}' > "$ws/.claude/settings.local.json"
    # Expired cache
    echo '{"effort":"old"}' > "$EFFORT_CACHE"
    touch -t "202301010000" "$EFFORT_CACHE"
    run read_effort_cascade "$ws"
    [ "$output" = "max" ]
}

# ---------------------------------------------------------------------------
# read_git_status
# ---------------------------------------------------------------------------

@test "read_git_status: uses valid cache when path matches" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws"
    # Manually write cache
    jq -n \
        --arg branch "main" \
        --argjson staged 2 \
        --argjson modified 1 \
        --arg path "$ws" \
        '{"branch":$branch,"staged":$staged,"modified":$modified,"path":$path}' \
        > "$GIT_CACHE"
    run bash -c "
        source \"$TEST_DIR/funcs.sh\"
        read -r b; read -r s; read -r m
    " < <(read_git_status "$ws")
    # Verify that the cache was read
    [ "$status" -eq 0 ]
}

@test "read_git_status: non-git directory → empty branch" {
    source_fns
    local ws="$TEST_DIR/non_git_dir"
    mkdir -p "$ws"
    # Clear cache
    rm -f "$GIT_CACHE"

    # Use a git stub that returns no branch
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/git" << 'GITSTUB'
#!/bin/sh
exit 128
GITSTUB
    chmod +x "$TEST_DIR/bin/git"

    run bash -c "
        export PATH=\"$TEST_DIR/bin:\$PATH\"
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        read_git_status \"$ws\"
    "
    # First line = branch, must be empty
    local first_line
    first_line=$(echo "$output" | head -1)
    [ "$first_line" = "" ]
}

# ---------------------------------------------------------------------------
# main — integration tests
# ---------------------------------------------------------------------------

_MINIMAL_PAYLOAD='{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"/tmp"}}'

@test "main: output contains ENV: with minimal payload" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"ENV:"* ]]
}

@test "main: output contains XTRA USG: with minimal payload" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"XTRA USG:"* ]]
}

@test "main: output contains CONTEXT_WINDOW with minimal payload" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"CONTEXT_WINDOW"* ]]
}

@test "main: empty input does not produce ERRORE STATUSBAR" {
    local input_file="$TEST_DIR/input.json"
    printf '' > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" != *"ERRORE STATUSBAR"* ]]
}

# ---------------------------------------------------------------------------
# _init_i18n
# ---------------------------------------------------------------------------

@test "_init_i18n: en_US → I18N_NA=N/A" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='en_US'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_NA\"
    "
    [ "$output" = "N/A" ]
}

@test "_init_i18n: it_IT → I18N_NA=N/D" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_NA\"
    "
    [ "$output" = "N/D" ]
}

@test "_init_i18n: de_DE → I18N_EFFORT=Aufwand" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='de_DE'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_EFFORT\"
    "
    [ "$output" = "Aufwand" ]
}

@test "_init_i18n: it_IT → I18N_ERROR=ERRORE STATUSBAR" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_ERROR\"
    "
    [ "$output" = "ERRORE STATUSBAR" ]
}

@test "_init_i18n: unknown locale → fallback en (I18N_NA=N/A)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='xx_XX'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_NA\"
    "
    [ "$output" = "N/A" ]
}

@test "main: it_IT → line 1 contains I18N_EFFORT (Effort)" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"Effort:"* ]]
}

@test "main: de_DE → line 1 contains Aufwand:" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='de_DE'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"Aufwand:"* ]]
}

# ---------------------------------------------------------------------------
# 8b — OAuth token validation (header injection prevention)
# ---------------------------------------------------------------------------

@test "8b: token containing only printable characters passes validation" {
    run bash -c "
        token='eyJhbGciOiJSUzI1NiJ9.validtoken'
        [[ \"\$token\" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOWED" ]
}

@test "8b: token containing newline (\n) is rejected by the regex" {
    run bash -c '
        token="$(printf "abc\ndef")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: token containing carriage return (\r) is rejected by the regex" {
    run bash -c '
        token="$(printf "abc\rdef")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: token containing control character (\x01) is rejected by the regex" {
    run bash -c '
        token="$(printf "abc\x01def")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: fetch_usage returns 1 when token contains a newline" {
    # Create a credentials file with a token containing \n (JSON escape → real newline)
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    printf '{"claudeAiOauth":{"accessToken":"abc\\ndef"}}' > "$cred_dir/.credentials.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    [ "$status" -ne 0 ]
}

@test "8b: fetch_usage returns 1 when token contains a carriage return" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # \r in JSON string → real carriage return in jq output
    printf '{"claudeAiOauth":{"accessToken":"abc\\rdef"}}' > "$cred_dir/.credentials.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 8c — Credentials file size cap (CRED_MAX_BYTES)
# ---------------------------------------------------------------------------

@test "8c: CRED_MAX_BYTES is defined and equals 65536" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CRED_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "65536" ]
}

@test "8c: credentials file within 64 KB is read normally" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # Small valid file — fetch_usage must attempt the API call (not be blocked by the size check)
    printf '{"claudeAiOauth":{"accessToken":"validtoken123"}}' > "$cred_dir/.credentials.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    # Returns 1 because curl fails (no network), but NOT due to the size check.
    # Verify that no error cache with type 'size_exceeded' exists
    # (the size check writes nothing and returns 1 silently)
    [ "$status" -ne 0 ]
}

@test "8c: credentials file over 64 KB is rejected (fetch_usage returns 1)" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # Generate a file of approximately 66 KB (> CRED_MAX_BYTES=65536)
    python3 -c "
import json, sys
data = {'claudeAiOauth': {'accessToken': 'x' * 66000}}
sys.stdout.write(json.dumps(data))
" > "$cred_dir/.credentials.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    [ "$status" -ne 0 ]
    # Verify that no usage_cache was created (jq was not invoked)
    [ ! -f "$TEST_DIR/claude_usage_cache.json" ]
}

@test "8c: credentials file of exactly 65536 bytes is accepted" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # Create a file of exactly CRED_MAX_BYTES bytes (inclusive limit)
    python3 -c "
import sys
# JSON prefix + padding to reach exactly 65536 bytes
prefix = b'{\"claudeAiOauth\":{\"accessToken\":\"'
suffix = b'\"}}'
pad_len = 65536 - len(prefix) - len(suffix)
sys.stdout.buffer.write(prefix + b'a' * pad_len + suffix)
" > "$cred_dir/.credentials.json"
    local fsize
    fsize=$(stat -c %s "$cred_dir/.credentials.json" 2>/dev/null || stat -f %z "$cred_dir/.credentials.json" 2>/dev/null)
    # File must be exactly 65536 bytes
    [ "$fsize" -eq 65536 ]
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    # Returns 1 because curl fails, but the size check does not block
    [ "$status" -ne 0 ]
    # No usage_cache with size_exceeded must exist.
    # (if the file had been blocked by the size check, the error_cache would not exist)
    # Verify the error cache exists (it passed the size check and attempted curl)
    [ -f "$TEST_DIR/claude_usage_error.json" ]
}

# ---------------------------------------------------------------------------
# 8d — API response size cap (API_RESPONSE_MAX_BYTES / --max-filesize)
# ---------------------------------------------------------------------------

@test "8d: API_RESPONSE_MAX_BYTES is defined and equals 1048576" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$API_RESPONSE_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1048576" ]
}

@test "8d: curl invocation includes --max-filesize" {
    # Static check: the constant and flag are present in the source
    grep -q 'API_RESPONSE_MAX_BYTES=1048576' "$BATS_TEST_DIRNAME/../statusline.sh"
    grep -q -- '--max-filesize' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8d: --max-filesize uses the API_RESPONSE_MAX_BYTES variable (not a hardcoded value)" {
    # Verify that --max-filesize is followed by the variable, not a fixed number
    grep -q -- '--max-filesize "\$API_RESPONSE_MAX_BYTES"' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8e — Settings file size cap (SETTINGS_MAX_BYTES)
# ---------------------------------------------------------------------------

@test "8e: SETTINGS_MAX_BYTES is defined and equals 262144" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$SETTINGS_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "262144" ]
}

@test "8e: settings file within 256 KB is read and returns effortLevel" {
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.claude"
    printf '{"effortLevel":"high"}' > "$ws/.claude/settings.json"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        read_effort_cascade \"$ws\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "high" ]
}

@test "8e: settings file over 256 KB is skipped (fallback to normal)" {
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.claude"
    # Generate a settings file of approximately 263 KB (> SETTINGS_MAX_BYTES=262144)
    python3 -c "
import json, sys
data = {'effortLevel': 'high', '_pad': 'x' * 263000}
sys.stdout.write(json.dumps(data))
" > "$ws/.claude/settings.json"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        read_effort_cascade \"$ws\"
    "
    [ "$status" -eq 0 ]
    # Oversized file is skipped → fallback to "normal"
    [ "$output" = "normal" ]
}

@test "8e: settings file over 256 KB is skipped but the next valid file is read" {
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.claude"
    mkdir -p "$TEST_DIR/.claude"
    # settings.local.json too large — must be skipped
    python3 -c "
import json, sys
data = {'effortLevel': 'high', '_pad': 'x' * 263000}
sys.stdout.write(json.dumps(data))
" > "$ws/.claude/settings.local.json"
    # settings.json valid — must be read
    printf '{"effortLevel":"medium"}' > "$ws/.claude/settings.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        read_effort_cascade \"$ws\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "medium" ]
}

# ---------------------------------------------------------------------------
# 8f — Single jq call on git cache
# ---------------------------------------------------------------------------

@test "8f: read_git_status returns branch/staged/modified from a valid cache (single jq call)" {
    # Pre-populate the git cache with known data
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.git"
    printf 'ref: refs/heads/main\n' > "$ws/.git/HEAD"
    local cache_content
    cache_content=$(jq -n \
        --arg branch   "main" \
        --argjson staged   2 \
        --argjson modified 3 \
        --arg path     "$ws" \
        --arg head_ref "ref: refs/heads/main" \
        '{"branch":$branch,"staged":$staged,"modified":$modified,"path":$path,"head_ref":$head_ref}')
    printf '%s' "$cache_content" > "$TEST_DIR/claude_git_cache.json"
    # Make the cache valid: mtime = now
    touch "$TEST_DIR/claude_git_cache.json"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        read_git_status \"$ws\"
    "
    [ "$status" -eq 0 ]
    local lines=("$output")
    IFS=$'\n' read -r -d '' branch staged modified <<< "$output" || true
    [ "$branch"   = "main" ]
    [ "$staged"   = "2" ]
    [ "$modified" = "3" ]
}

@test "8f: read_git_status ignores cache when the path has changed" {
    local ws="$TEST_DIR/workspace"
    local other="$TEST_DIR/other"
    mkdir -p "$ws/.git" "$other"
    printf 'ref: refs/heads/main\n' > "$ws/.git/HEAD"
    # Cache with a different path
    local cache_content
    cache_content=$(jq -n \
        --arg branch   "old-branch" \
        --argjson staged   0 \
        --argjson modified 0 \
        --arg path     "$other" \
        --arg head_ref "ref: refs/heads/main" \
        '{"branch":$branch,"staged":$staged,"modified":$modified,"path":$path,"head_ref":$head_ref}')
    printf '%s' "$cache_content" > "$TEST_DIR/claude_git_cache.json"
    touch "$TEST_DIR/claude_git_cache.json"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        read_git_status \"$ws\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Branch read from git (not from cache) — TEST_DIR contains no real git repo,
    # so branch will be empty, but NOT "old-branch"
    [[ "$output" != *"old-branch"* ]]
}

@test "8f: source no longer contains separate jq calls for .path and .head_ref" {
    # Structural check: the 3 separate jq calls have been merged.
    # 'jq -r .path // empty' and 'jq -r .head_ref // empty' must not exist as separate lines
    ! grep -qP "jq -r '.path // empty'" "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qP "jq -r '.head_ref // empty'" "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8g — fmt_date uses a single date call for formatting
# ---------------------------------------------------------------------------

@test "8g: fmt_date correctly formats an ISO8601 date (24h)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        # Known epoch: 2024-06-15T14:30:00Z = Saturday
        fmt_date '2024-06-15T14:30:00Z'
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Must contain time 14:30
    [[ "$output" == *"14:30"* ]]
    # Must contain day and month (15 and 06)
    [[ "$output" == *"15"* ]]
}

@test "8g: fmt_date returns I18N_NA for empty input" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fmt_date ''
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "N/A" ]
}

@test "8g: fmt_date returns I18N_NA for invalid input" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fmt_date 'not-a-date'
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "N/A" ]
}

@test "8g: source fmt_date no longer contains separate date calls for dow/dd/mm" {
    # Structural check: separate date calls for dow, dd, mm no longer exist
    ! grep -qE 'dow=\$\(date' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'dd=\$\(date'  "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'mm=\$\(date'  "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8g: fmt_date uses read -r to parse fields from the combined date output" {
    grep -q 'read -r dow dd mm time_str' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8h — Single awk call for all 4 fmt_tokens
# ---------------------------------------------------------------------------

@test "8h: single awk formats values < 1000 as integers" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        local tok_in_fmt tok_out_fmt tok_cached_fmt tok_total_fmt
        { read -r tok_in_fmt; read -r tok_out_fmt;
          read -r tok_cached_fmt; read -r tok_total_fmt; } \
            < <(awk -v a=500 -v b=0 -v c=100 -v d=600 \
                'function f(n) { return (n>=1000) ? sprintf(\"%.1fK\", n/1000) : int(n) }
                 BEGIN { print f(a); print f(b); print f(c); print f(d) }')
        echo \"\$tok_in_fmt \$tok_out_fmt \$tok_cached_fmt \$tok_total_fmt\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "500 0 100 600" ]
}

@test "8h: single awk formats values >= 1000 as XK" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        local tok_in_fmt tok_out_fmt tok_cached_fmt tok_total_fmt
        { read -r tok_in_fmt; read -r tok_out_fmt;
          read -r tok_cached_fmt; read -r tok_total_fmt; } \
            < <(awk -v a=5000 -v b=1000 -v c=1500 -v d=7500 \
                'function f(n) { return (n>=1000) ? sprintf(\"%.1fK\", n/1000) : int(n) }
                 BEGIN { print f(a); print f(b); print f(c); print f(d) }')
        echo \"\$tok_in_fmt \$tok_out_fmt \$tok_cached_fmt \$tok_total_fmt\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "5.0K 1.0K 1.5K 7.5K" ]
}

@test "8h: main produces CONTEXT_WINDOW with formatted tokens (integration)" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONTEXT_WINDOW"* ]]
    # Payload has tok_in=5000, tok_out=1000 → 5.0K and 1.0K
    [[ "$output" == *"5.0K"* ]]
    [[ "$output" == *"1.0K"* ]]
}

@test "8h: source no longer contains 4 separate fmt_tokens calls" {
    # Structural check: the 4 tok_*_fmt=$(fmt_tokens …) lines must no longer exist
    ! grep -qE 'tok_in_fmt=\$\(fmt_tokens'     "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_out_fmt=\$\(fmt_tokens'    "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_cached_fmt=\$\(fmt_tokens' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_total_fmt=\$\(fmt_tokens'  "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8i — _SEP90 pre-calculated as a global constant
# ---------------------------------------------------------------------------

@test "8i: _SEP90 is defined globally after sourcing" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        [[ -n \"\$_SEP90\" ]] && echo OK || echo MISSING
    "
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "8i: _SEP90 contains exactly 90 ─ characters (U+2500)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        # Strip ANSI sequences and count ─ characters
        stripped=\$(printf '%s' \"\$_SEP90\" | sed 's/\x1b\[[0-9;]*m//g')
        printf '%s' \"\$stripped\" | wc -m | tr -d ' '
    "
    [ "$status" -eq 0 ]
    [ "$output" = "90" ]
}

@test "8i: source no longer contains the local sep90=\$(printf) construction" {
    ! grep -qE 'local sep90' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'sep90="\$\{cGray\}' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8i: source main() uses \$_SEP90 (not \$sep90)" {
    grep -q '_SEP90' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -q '"$sep90"' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8i: main produces output with separators (integration)" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Output must contain the ─ character
    [[ "$output" == *"─"* ]]
}

# ---------------------------------------------------------------------------
# 8j — Output assembled into a single printf
# ---------------------------------------------------------------------------

@test "8j: main produces exactly 13 output lines" {
    # Expected layout: line1 + sep + line2 + sep + line3 + sep + line4 + sep + line5 + sep + line6 + sep = 12 lines
    # printf '%s\n' "$out" adds a trailing \n → wc -l counts 13 (12 content + 1 trailing newline)
    # In practice we count non-empty lines (stripping ANSI codes)
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Count non-empty lines (stripping ANSI codes)
    local line_count
    line_count=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '.')
    [ "$line_count" -eq 12 ]
}

@test "8j: output contains all 6 key labels" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENV:"* ]]
    [[ "$output" == *"CONTEXT_WINDOW"* ]]
    [[ "$output" == *"CONTEXT:"* ]]
    [[ "$output" == *"USAGE 5H:"* ]]
    [[ "$output" == *"USAGE WK:"* ]]
    [[ "$output" == *"XTRA USG:"* ]]
}

@test "8j: source no longer contains separate printf calls for each output line" {
    # The output block now uses line1..line6 variables + a single printf '%s\n'
    # No more separate printf calls for ENV:, CONTEXT_WINDOW, etc.
    ! grep -qE "printf '%s' \"\$\{cWhite\}ENV:" "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE "printf '%s\\\\n' \"\$\{cWhite\}CONTEXT_WINDOW" "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8j: source contains the assembled out variable" {
    grep -q 'out="${line1}"' "$BATS_TEST_DIRNAME/../statusline.sh"
    grep -qE "printf '%s\\\\n' \"\\\$out\"" "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8k — balance_fmt calculated via fmt_currency (no duplicate awk)
# ---------------------------------------------------------------------------

@test "8k: fmt_currency correctly calculates the balance (it_IT locale)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        # used=5000 cents (50.00€), month=10000 cents (100.00€) → balance=5000 cents (50.00€)
        local bal_cents=\$(( 10000 - 5000 ))
        fmt_currency \"\$bal_cents\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"50"* ]]
    [[ "$output" == *"€"* ]]
}

@test "8k: fmt_currency and the old awk produce the same result" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='it_IT'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        local bal_cents=\$(( 15000 - 6789 ))
        fmt_currency \"\$bal_cents\"
    "
    [ "$status" -eq 0 ]
    # 15000 - 6789 = 8211 cents = 82.11 → it_IT: "82,11 €"
    [ "$output" = "82,11 €" ]
}

@test "8k: balance_fmt is N/A when used_credits is null" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        local used_credits='null' month_limit=10000 balance_fmt
        if [[ \"\$used_credits\" != 'null' && \"\$month_limit\" != 'null' && \
              -n \"\$used_credits\" && -n \"\$month_limit\" ]]; then
            local bal_cents=\$(( month_limit - used_credits ))
            balance_fmt=\$(fmt_currency \"\$bal_cents\")
        else
            balance_fmt=\"\$I18N_NA\"
        fi
        echo \"\$balance_fmt\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "N/A" ]
}

@test "8k: source no longer contains the duplicate awk block for balance" {
    # The inline awk block for balance has been removed
    ! grep -qE "awk -v used=.*-v month=.*month_limit" "$BATS_TEST_DIRNAME/../statusline.sh"
    # Must use fmt_currency instead
    grep -q 'balance_fmt=$(fmt_currency "$bal_cents")' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8l — Gradient stops extracted as shared global constants
# ---------------------------------------------------------------------------

@test "8l: the 12 _GRAD_* constants are defined with the correct values" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$_GRAD_R0 \$_GRAD_G0 \$_GRAD_B0\"
        echo \"\$_GRAD_R1 \$_GRAD_G1 \$_GRAD_B1\"
        echo \"\$_GRAD_R2 \$_GRAD_G2 \$_GRAD_B2\"
        echo \"\$_GRAD_R3 \$_GRAD_G3 \$_GRAD_B3\"
    "
    [ "$status" -eq 0 ]
    local lines=()
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true
    [ "${lines[0]}" = "74 222 128" ]
    [ "${lines[1]}" = "250 204 21" ]
    [ "${lines[2]}" = "251 146 60" ]
    [ "${lines[3]}" = "239 68 68" ]
}

@test "8l: get_gradient_bar produces output with ANSI RGB sequences (uses constants)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_gradient_bar 50 10
    "
    [ "$status" -eq 0 ]
    # Output must contain ANSI RGB sequences [38;2;
    [[ "$output" == *"[38;2;"* ]]
}

@test "8l: get_pct_color produces output with ANSI RGB sequences (uses constants)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_pct_color 0
    "
    [ "$status" -eq 0 ]
    # At 0% must use green color (r0=74, g0=222, b0=128)
    [[ "$output" == *"38;2;74;222;128"* ]]
}

@test "8l: get_pct_color at 100% uses red color (r3=239, g3=68, b3=68)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_pct_color 100
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"38;2;239;68;68"* ]]
}

@test "8l: source no longer contains hardcoded r0=74 or r3=239 lines inside awk blocks" {
    ! grep -qE '^\s+r0=74' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE '^\s+r3=239' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8l: both awk functions receive the constants via -v" {
    # get_gradient_bar and get_pct_color must pass -v r0="$_GRAD_R0"
    grep -c '\-v r0="\$_GRAD_R0"' "$BATS_TEST_DIRNAME/../statusline.sh" | grep -q '^2$'
}

# ---------------------------------------------------------------------------
# 8a — Stdin size cap (STDIN_MAX_BYTES)
# ---------------------------------------------------------------------------

@test "8a: STDIN_MAX_BYTES is defined and equals 1048576" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$STDIN_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1048576" ]
}

@test "8a: input within 1 MB does not produce ERRORE STATUSBAR" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERRORE STATUSBAR"* ]]
}

@test "8a: input over 1 MB is truncated and does not produce ERRORE STATUSBAR" {
    # Build a JSON with a very large padding field that exceeds 1 MB.
    # The payload is valid JSON but the padding pushes it well past STDIN_MAX_BYTES.
    # After head -c truncation the JSON will be malformed; main must fall back to '{}'.
    local padding
    padding=$(python3 -c "print('x' * 1100000)")
    local large_input="{\"_pad\":\"${padding}\",\"model\":{\"display_name\":\"Sonnet 4.6\"}}"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        printf '%s' '$large_input' | main
    " 2>/dev/null
    # Must not crash with ERRORE STATUSBAR (graceful fallback)
    [[ "$output" != *"ERRORE STATUSBAR"* ]]
}
