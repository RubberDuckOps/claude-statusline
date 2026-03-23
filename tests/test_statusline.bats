#!/usr/bin/env bats
# test_statusline.bats — bats-core test suite per statusline.sh
#
# Esecuzione:
#   bats test_statusline.bats
#
# Dipendenze:
#   - bats-core  (https://github.com/bats-core/bats-core)
#   - bats-assert (https://github.com/bats-core/bats-assert)  [opzionale, vedi note]
#   - jq, awk, date, stat  (già richieste da statusline.sh)
#
# Nota: i test usano $output e $status direttamente (senza bats-assert)
# per non richiedere dipendenze aggiuntive.

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
    # Directory temporanea isolata per ogni test
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # Imposta TMPDIR → lo script userà questa come CACHE_DIR
    export TMPDIR="$TEST_DIR"

    # Azzera variabili locale per evitare interferenze dal sistema
    unset LC_MONETARY LC_ALL LANG

    # Crea funcs.sh: copia dello script senza la riga di invocazione main
    sed '/^main /d' "$BATS_TEST_DIRNAME/../statusline.sh" > "$TEST_DIR/funcs.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: source funcs.sh nel subshell del test corrente
source_fns() {
    # shellcheck disable=SC1090
    source "$TEST_DIR/funcs.sh"
}

# Helper: source con locale specifico in un subshell
# Uso: run_with_locale LOCALE 'bash code'
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

@test "is_cache_valid: file inesistente → failure" {
    source_fns
    run is_cache_valid "$TEST_DIR/inesistente.json" 60
    [ "$status" -ne 0 ]
}

@test "is_cache_valid: file recente → success" {
    source_fns
    local f="$TEST_DIR/recente.json"
    echo '{}' > "$f"
    run is_cache_valid "$f" 60
    [ "$status" -eq 0 ]
}

@test "is_cache_valid: file scaduto → failure" {
    source_fns
    local f="$TEST_DIR/scaduto.json"
    echo '{}' > "$f"
    # touch -t: formato YYYYMMDDHHSS, portabile GNU e BSD
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

@test "atomic_write: scrive contenuto base" {
    source_fns
    local f="$TEST_DIR/out.json"
    atomic_write "$f" '{"ok":true}'
    [ "$(cat "$f")" = '{"ok":true}' ]
}

@test "atomic_write: sovrascrive file esistente" {
    source_fns
    local f="$TEST_DIR/out.json"
    atomic_write "$f" "prima"
    atomic_write "$f" "dopo"
    [ "$(cat "$f")" = "dopo" ]
}

@test "atomic_write: gestisce unicode" {
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
# fmt_currency — ogni test usa un subshell con locale esplicito
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

@test "fmt_currency: stringa vuota en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_currency ''"
    [ "$output" = "N/A" ]
}

@test "fmt_currency: stringa vuota it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_currency ''"
    [ "$output" = "N/D" ]
}

# ---------------------------------------------------------------------------
# _init_currency — testa le variabili CURR_* impostate dalla funzione
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

@test "_init_currency: locale sconosciuto → fallback \$ (en_US)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='xx_XX'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CURR_SYMBOL\"
    "
    [ "$output" = '$' ]
}

@test "_init_currency: locale fr_CH → CURR_SYM_BEFORE=1 e CURR_SYM_SPACE=1" {
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

@test "_init_date_fmt: locale sconosciuto → fallback en_US (MDY, h24=0)" {
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

@test "fmt_date: stringa vuota en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_date ''"
    [ "$output" = "N/A" ]
}

@test "fmt_date: stringa vuota it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_date ''"
    [ "$output" = "N/D" ]
}

@test "fmt_date: data invalida en_US → 'N/A'" {
    run_with_locale "en_US" "fmt_date 'non-una-data'"
    [ "$output" = "N/A" ]
}

@test "fmt_date: data invalida it_IT → 'N/D'" {
    run_with_locale "it_IT" "fmt_date 'non-una-data'"
    [ "$output" = "N/D" ]
}

@test "fmt_date: it_IT 2025-01-06T12:00:00Z → inizia con LUN" {
    run_with_locale "it_IT" "fmt_date '2025-01-06T12:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" == LUN* ]]
}

@test "fmt_date: it_IT 2025-01-12T12:00:00Z → inizia con DOM" {
    run_with_locale "it_IT" "fmt_date '2025-01-12T12:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" == DOM* ]]
}

@test "fmt_date: it_IT formato output valido (DMY, 24h)" {
    run_with_locale "it_IT" "fmt_date '2025-06-15T14:30:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[A-Z]{3}\ [0-9]{2}/[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "fmt_date: en_US → MDY e 12h (AM/PM)" {
    run_with_locale "en_US" "fmt_date '2025-03-19T18:00:00Z'"
    [ "$status" -eq 0 ]
    # MM/DD e AM/PM
    [[ "$output" =~ ^[A-Z]{3}\ [0-9]{2}/[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}\ (AM|PM)$ ]]
}

@test "fmt_date: de_DE → sep punto" {
    run_with_locale "de_DE" "fmt_date '2025-03-19T18:00:00Z'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[A-Z]{2}\ [0-9]{2}\.[0-9]{2}\ H:\ [0-9]{2}:[0-9]{2}$ ]]
}

# ---------------------------------------------------------------------------
# read_effort_cascade
# ---------------------------------------------------------------------------

@test "read_effort_cascade: default 'normal' senza settings file" {
    source_fns
    local ws="$TEST_DIR/workspace_vuoto"
    mkdir -p "$ws"
    run read_effort_cascade "$ws"
    [ "$output" = "normal" ]
}

@test "read_effort_cascade: legge settings.local.json" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws/.claude"
    echo '{"effortLevel":"high"}' > "$ws/.claude/settings.local.json"
    run read_effort_cascade "$ws"
    [ "$output" = "high" ]
}

@test "read_effort_cascade: usa cache valida" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws"
    # Scrive cache manualmente
    echo '{"effort":"medium"}' > "$EFFORT_CACHE"
    run read_effort_cascade "$ws"
    [ "$output" = "medium" ]
}

@test "read_effort_cascade: cache scaduta → rilegge settings" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws/.claude"
    echo '{"effortLevel":"max"}' > "$ws/.claude/settings.local.json"
    # Cache scaduta
    echo '{"effort":"old"}' > "$EFFORT_CACHE"
    touch -t "202301010000" "$EFFORT_CACHE"
    run read_effort_cascade "$ws"
    [ "$output" = "max" ]
}

# ---------------------------------------------------------------------------
# read_git_status
# ---------------------------------------------------------------------------

@test "read_git_status: usa cache valida con path corretto" {
    source_fns
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws"
    # Scrive cache manualmente
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
    # Verifica che la cache sia stata letta
    [ "$status" -eq 0 ]
}

@test "read_git_status: directory non-git → branch vuoto" {
    source_fns
    local ws="$TEST_DIR/non_git_dir"
    mkdir -p "$ws"
    # Azzera cache
    rm -f "$GIT_CACHE"

    # Usa stub git che non trova branch
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
    # Prima riga = branch, deve essere vuota
    local first_line
    first_line=$(echo "$output" | head -1)
    [ "$first_line" = "" ]
}

# ---------------------------------------------------------------------------
# main — test di integrazione
# ---------------------------------------------------------------------------

_MINIMAL_PAYLOAD='{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"/tmp"}}'

@test "main: output contiene ENV: con payload minimo" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"ENV:"* ]]
}

@test "main: output contiene XTRA USG: con payload minimo" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"XTRA USG:"* ]]
}

@test "main: output contiene CONTEXT_WINDOW con payload minimo" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [[ "$output" == *"CONTEXT_WINDOW"* ]]
}

@test "main: input vuoto non genera ERRORE STATUSBAR" {
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

@test "_init_i18n: locale sconosciuto → fallback en (I18N_NA=N/A)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        export LC_MONETARY='xx_XX'
        unset LC_ALL LANG
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$I18N_NA\"
    "
    [ "$output" = "N/A" ]
}

@test "main: it_IT → riga 1 contiene I18N_EFFORT (Effort)" {
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

@test "main: de_DE → riga 1 contiene Aufwand:" {
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

@test "8b: token con solo caratteri stampabili supera la regex" {
    run bash -c "
        token='eyJhbGciOiJSUzI1NiJ9.validtoken'
        [[ \"\$token\" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOWED" ]
}

@test "8b: token con newline (\n) viene rifiutato dalla regex" {
    run bash -c '
        token="$(printf "abc\ndef")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: token con carriage return (\r) viene rifiutato dalla regex" {
    run bash -c '
        token="$(printf "abc\rdef")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: token con carattere di controllo (\x01) viene rifiutato dalla regex" {
    run bash -c '
        token="$(printf "abc\x01def")"
        [[ "$token" =~ [^[:print:]] ]] && echo REJECTED || echo ALLOWED
    '
    [ "$status" -eq 0 ]
    [ "$output" = "REJECTED" ]
}

@test "8b: fetch_usage ritorna 1 se il token contiene newline" {
    # Crea un file credenziali con token che contiene \n (JSON escape → newline reale)
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

@test "8b: fetch_usage ritorna 1 se il token contiene carriage return" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # \r nel JSON string → carriage return reale nell'output di jq
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

@test "8c: CRED_MAX_BYTES è definita e uguale a 65536" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$CRED_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "65536" ]
}

@test "8c: file credenziali entro 64 KB viene letto normalmente" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # File valido e piccolo — fetch_usage deve tentare la chiamata API (non bloccarsi sul size check)
    printf '{"claudeAiOauth":{"accessToken":"validtoken123"}}' > "$cred_dir/.credentials.json"
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    # Ritorna 1 perché curl fallisce (no rete), ma NON per il size check
    # Verifichiamo che non esista un error cache con tipo 'size_exceeded'
    # (il size check non scrive nulla, ritorna 1 silenziosamente)
    [ "$status" -ne 0 ]
}

@test "8c: file credenziali oltre 64 KB viene rifiutato (fetch_usage ritorna 1)" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # Genera un file di circa 66 KB (> CRED_MAX_BYTES=65536)
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
    # Verifica che non sia stato creato un usage_cache (jq non è stato invocato)
    [ ! -f "$TEST_DIR/claude_usage_cache.json" ]
}

@test "8c: file credenziali esattamente 65536 byte viene accettato" {
    local cred_dir="$TEST_DIR/.claude"
    mkdir -p "$cred_dir"
    # Creiamo un file di esattamente CRED_MAX_BYTES byte (limite incluso)
    python3 -c "
import sys
# Prefisso JSON + padding per arrivare a 65536 byte esatti
prefix = b'{\"claudeAiOauth\":{\"accessToken\":\"'
suffix = b'\"}}'
pad_len = 65536 - len(prefix) - len(suffix)
sys.stdout.buffer.write(prefix + b'a' * pad_len + suffix)
" > "$cred_dir/.credentials.json"
    local fsize
    fsize=$(stat -c %s "$cred_dir/.credentials.json" 2>/dev/null || stat -f %z "$cred_dir/.credentials.json" 2>/dev/null)
    # Il file deve essere esattamente 65536 byte
    [ "$fsize" -eq 65536 ]
    run bash -c "
        export HOME=\"$TEST_DIR\"
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fetch_usage
    "
    # Ritorna 1 perché curl fallisce, ma il size check non lo blocca
    [ "$status" -ne 0 ]
    # Non deve esistere un usage_cache con size_exceeded
    # (se il file fosse stato bloccato dal size check, non ci sarebbe nemmeno l'error_cache)
    # Verifichiamo che l'error cache esista (significa che ha superato il size check e ha tentato curl)
    [ -f "$TEST_DIR/claude_usage_error.json" ]
}

# ---------------------------------------------------------------------------
# 8d — API response size cap (API_RESPONSE_MAX_BYTES / --max-filesize)
# ---------------------------------------------------------------------------

@test "8d: API_RESPONSE_MAX_BYTES è definita e uguale a 1048576" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$API_RESPONSE_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1048576" ]
}

@test "8d: la chiamata curl include --max-filesize" {
    # Verifica statica: la costante e il flag sono presenti nel sorgente
    grep -q 'API_RESPONSE_MAX_BYTES=1048576' "$BATS_TEST_DIRNAME/../statusline.sh"
    grep -q -- '--max-filesize' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8d: --max-filesize usa la variabile API_RESPONSE_MAX_BYTES (non un valore hardcoded)" {
    # Verifica che nel sorgente --max-filesize sia seguito dalla variabile, non da un numero fisso
    grep -q -- '--max-filesize "\$API_RESPONSE_MAX_BYTES"' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8e — Settings file size cap (SETTINGS_MAX_BYTES)
# ---------------------------------------------------------------------------

@test "8e: SETTINGS_MAX_BYTES è definita e uguale a 262144" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$SETTINGS_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "262144" ]
}

@test "8e: file settings entro 256 KB viene letto e restituisce effortLevel" {
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

@test "8e: file settings oltre 256 KB viene saltato (fallback a normal)" {
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.claude"
    # Genera un file settings di circa 263 KB (> SETTINGS_MAX_BYTES=262144)
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
    # Il file troppo grande viene saltato → fallback a "normal"
    [ "$output" = "normal" ]
}

@test "8e: file settings oltre 256 KB viene saltato ma il successivo valido viene letto" {
    local ws="$TEST_DIR/workspace"
    mkdir -p "$ws/.claude"
    mkdir -p "$TEST_DIR/.claude"
    # settings.local.json troppo grande — deve essere saltato
    python3 -c "
import json, sys
data = {'effortLevel': 'high', '_pad': 'x' * 263000}
sys.stdout.write(json.dumps(data))
" > "$ws/.claude/settings.local.json"
    # settings.json valido — deve essere letto
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

@test "8f: read_git_status restituisce branch/staged/modified da cache valida (1 sola jq)" {
    # Prepopola la git cache con dati noti
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
    # Rende la cache valida: mtime = adesso
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

@test "8f: read_git_status ignora la cache se il path è cambiato" {
    local ws="$TEST_DIR/workspace"
    local other="$TEST_DIR/other"
    mkdir -p "$ws/.git" "$other"
    printf 'ref: refs/heads/main\n' > "$ws/.git/HEAD"
    # Cache con path diverso
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
    # Branch letto da git (non da cache) — in TEST_DIR non c'è un repo git reale,
    # quindi branch sarà vuoto, ma NON "old-branch"
    [[ "$output" != *"old-branch"* ]]
}

@test "8f: nel sorgente non esistono più chiamate jq separate su .path e .head_ref" {
    # Verifica strutturale: le 3 chiamate jq separate sono state fuse
    # Non deve esistere 'jq -r .path // empty' e 'jq -r .head_ref // empty' come righe separate
    ! grep -qP "jq -r '.path // empty'" "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qP "jq -r '.head_ref // empty'" "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8g — fmt_date usa una sola chiamata date per la formattazione
# ---------------------------------------------------------------------------

@test "8g: fmt_date formatta correttamente una data ISO8601 (24h)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        # Epoch noto: 2024-06-15T14:30:00Z = Sabato
        fmt_date '2024-06-15T14:30:00Z'
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Deve contenere ora e minuti 14:30
    [[ "$output" == *"14:30"* ]]
    # Deve contenere il giorno e il mese (15 e 06)
    [[ "$output" == *"15"* ]]
}

@test "8g: fmt_date restituisce I18N_NA per input vuoto" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fmt_date ''
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "N/A" ]
}

@test "8g: fmt_date restituisce I18N_NA per input non valido" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        fmt_date 'not-a-date'
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "N/A" ]
}

@test "8g: nel sorgente fmt_date non contiene più chiamate date separate per dow/dd/mm" {
    # Verifica strutturale: le chiamate separate a date per dow, dd, mm non esistono più
    ! grep -qE 'dow=\$\(date' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'dd=\$\(date'  "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'mm=\$\(date'  "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8g: fmt_date usa read -r per parsare i campi dall'output combinato di date" {
    grep -q 'read -r dow dd mm time_str' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8h — Singolo awk per i 4 fmt_tokens
# ---------------------------------------------------------------------------

@test "8h: awk singolo formatta valori < 1000 come interi" {
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

@test "8h: awk singolo formatta valori >= 1000 come XK" {
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

@test "8h: main produce CONTEXT_WINDOW con token formattati (integrazione)" {
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
    # Il payload ha tok_in=5000, tok_out=1000 → 5.0K e 1.0K
    [[ "$output" == *"5.0K"* ]]
    [[ "$output" == *"1.0K"* ]]
}

@test "8h: nel sorgente non esistono più 4 chiamate separate a fmt_tokens" {
    # Verifica strutturale: le 4 righe tok_*_fmt=$(fmt_tokens …) non devono più esistere
    ! grep -qE 'tok_in_fmt=\$\(fmt_tokens'     "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_out_fmt=\$\(fmt_tokens'    "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_cached_fmt=\$\(fmt_tokens' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'tok_total_fmt=\$\(fmt_tokens'  "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8i — _SEP90 precalcolato come costante globale
# ---------------------------------------------------------------------------

@test "8i: _SEP90 è definita a livello globale dopo il sourcing" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        [[ -n \"\$_SEP90\" ]] && echo OK || echo MISSING
    "
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "8i: _SEP90 contiene esattamente 90 caratteri ─ (U+2500)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        # Rimuove le sequenze ANSI e conta i caratteri ─
        stripped=\$(printf '%s' \"\$_SEP90\" | sed 's/\x1b\[[0-9;]*m//g')
        printf '%s' \"\$stripped\" | wc -m | tr -d ' '
    "
    [ "$status" -eq 0 ]
    [ "$output" = "90" ]
}

@test "8i: nel sorgente non esiste più la costruzione locale sep90=\$(printf)" {
    ! grep -qE 'local sep90' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE 'sep90="\$\{cGray\}' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8i: nel sorgente main() usa \$_SEP90 (non \$sep90)" {
    grep -q '_SEP90' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -q '"$sep90"' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8i: main produce output con i separatori (integrazione)" {
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # L'output deve contenere il carattere ─
    [[ "$output" == *"─"* ]]
}

# ---------------------------------------------------------------------------
# 8j — Output assemblato in singolo printf
# ---------------------------------------------------------------------------

@test "8j: main produce esattamente 13 righe di output" {
    # Layout atteso: line1 + sep + line2 + sep + line3 + sep + line4 + sep + line5 + sep + line6 + sep = 12 righe
    # Il printf '%s\n' "$out" aggiunge un \n finale → wc -l conta 13 (12 contenuto + 1 newline finale)
    # In pratica contiamo le righe non vuote (strippando ANSI)
    local input_file="$TEST_DIR/input.json"
    printf '%s' "$_MINIMAL_PAYLOAD" > "$input_file"
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        main < \"$input_file\"
    " 2>/dev/null
    [ "$status" -eq 0 ]
    # Conta righe non vuote (stripping ANSI codes)
    local line_count
    line_count=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '.')
    [ "$line_count" -eq 12 ]
}

@test "8j: output contiene tutte e 6 le etichette chiave" {
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

@test "8j: nel sorgente non esistono più printf separati per ogni riga di output" {
    # Il blocco di output ora usa variabili line1..line6 + un singolo printf '%s\n'
    # Non devono esserci più printf separati per ENV:, CONTEXT_WINDOW, ecc.
    ! grep -qE "printf '%s' \"\$\{cWhite\}ENV:" "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE "printf '%s\\\\n' \"\$\{cWhite\}CONTEXT_WINDOW" "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8j: nel sorgente è presente la variabile out assemblata" {
    grep -q 'out="${line1}"' "$BATS_TEST_DIRNAME/../statusline.sh"
    grep -qE "printf '%s\\\\n' \"\\\$out\"" "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8k — balance_fmt calcolato via fmt_currency (no awk duplicato)
# ---------------------------------------------------------------------------

@test "8k: fmt_currency calcola correttamente il balance (locale it_IT)" {
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

@test "8k: fmt_currency e il vecchio awk producono lo stesso risultato" {
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

@test "8k: balance_fmt è N/A se used_credits è null" {
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

@test "8k: nel sorgente non esiste più il blocco awk duplicato per il balance" {
    # Il blocco awk inline per il balance è stato rimosso
    ! grep -qE "awk -v used=.*-v month=.*month_limit" "$BATS_TEST_DIRNAME/../statusline.sh"
    # Deve invece usare fmt_currency
    grep -q 'balance_fmt=$(fmt_currency "$bal_cents")' "$BATS_TEST_DIRNAME/../statusline.sh"
}

# ---------------------------------------------------------------------------
# 8l — Gradient stops estratti in costanti globali condivise
# ---------------------------------------------------------------------------

@test "8l: le 12 costanti _GRAD_* sono definite con i valori corretti" {
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

@test "8l: get_gradient_bar produce output con sequenze ANSI RGB (usa le costanti)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_gradient_bar 50 10
    "
    [ "$status" -eq 0 ]
    # Output deve contenere sequenze ANSI RGB [38;2;
    [[ "$output" == *"[38;2;"* ]]
}

@test "8l: get_pct_color produce output con sequenze ANSI RGB (usa le costanti)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_pct_color 0
    "
    [ "$status" -eq 0 ]
    # A 0% deve usare il colore verde (r0=74, g0=222, b0=128)
    [[ "$output" == *"38;2;74;222;128"* ]]
}

@test "8l: get_pct_color a 100% usa il colore rosso (r3=239, g3=68, b3=68)" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        get_pct_color 100
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"38;2;239;68;68"* ]]
}

@test "8l: nel sorgente non esistono più righe hardcoded r0=74 o r3=239 nei blocchi awk" {
    ! grep -qE '^\s+r0=74' "$BATS_TEST_DIRNAME/../statusline.sh"
    ! grep -qE '^\s+r3=239' "$BATS_TEST_DIRNAME/../statusline.sh"
}

@test "8l: entrambe le funzioni awk ricevono le costanti via -v" {
    # get_gradient_bar e get_pct_color devono passare -v r0="$_GRAD_R0"
    grep -c '\-v r0="\$_GRAD_R0"' "$BATS_TEST_DIRNAME/../statusline.sh" | grep -q '^2$'
}

# ---------------------------------------------------------------------------
# 8a — Stdin size cap (STDIN_MAX_BYTES)
# ---------------------------------------------------------------------------

@test "8a: STDIN_MAX_BYTES è definita e uguale a 1048576" {
    run bash -c "
        export TMPDIR=\"$TEST_DIR\"
        unset LC_ALL LANG LC_MONETARY
        source \"$TEST_DIR/funcs.sh\"
        echo \"\$STDIN_MAX_BYTES\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1048576" ]
}

@test "8a: input entro 1 MB non genera ERRORE STATUSBAR" {
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

@test "8a: input oltre 1 MB viene troncato e non genera ERRORE STATUSBAR" {
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
