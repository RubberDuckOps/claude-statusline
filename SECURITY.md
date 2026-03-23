# Security, Stability & Performance

This document describes the security controls, stability mechanisms, and performance optimisations implemented across all three variants of Claude Code Statusline: `statusline.ps1` (PowerShell), `statusline.sh` (bash), and `statusline.py` (Python). All three variants implement the same design principles; implementation details differ per runtime.

---

## Table of Contents

- [Shared Design Principles](#shared-design-principles)
- [PowerShell — `statusline.ps1`](#powershell--statuslineps1)
- [Bash — `statusline.sh`](#bash--statuslinesh)
- [Python — `statusline.py`](#python--statuslinepy)
- [Cross-Variant Comparison](#cross-variant-comparison)

---

## Shared Design Principles

These properties hold across all three variants.

### Input Size Caps

Every external data source is capped before being read into memory to prevent resource exhaustion.

| Source | Cap | Rationale |
|--------|-----|-----------|
| stdin (Claude Code JSON) | 1 MB | Telemetry payload is always tiny; cap prevents flooding |
| OAuth credentials file | 64 KB | A well-formed JSON credentials file is < 1 KB |
| Anthropic API response | 1 MB | Usage API response is a small JSON object |
| Settings files (cascade) | 256 KB | Settings files are typically < 10 KB |

### OAuth Token Security

The OAuth token is treated as a secret throughout its lifecycle:

- **Source**: read from `~/.claude/.credentials.json` (or `~/.config/claude/.credentials.json` on Linux).
- **Validation**: validated for control characters (`\r`, `\n`, `\x00`, and non-printable characters) before use. A token that fails validation is discarded silently; no API call is made.
- **Use**: passed only as the value of the `Authorization: Bearer` HTTP header. Never logged, never written to disk, never interpolated into any string.
- **Scope**: the token value is not stored in any cache file. Only usage data returned by the API is cached.

### JSON Serialisation Safety

All data written to cache files passes through the runtime's native JSON serialiser:

- PowerShell: `ConvertTo-Json`
- bash: `jq -n --arg` (variables passed as `--arg` arguments, never interpolated into the JSON string)
- Python: `json.dumps()`

This prevents injection attacks where a crafted Git branch name or workspace path containing quote characters could corrupt a cache file.

### Workspace Path Validation

Before any `git` subprocess is launched, the workspace path from stdin is validated as an existing directory on the local filesystem. This prevents git from operating on unexpected or attacker-controlled paths.

### Atomic Cache Writes

Cache files are written via a write-to-temp-then-rename pattern so that a concurrent reader can never observe a partial write:

- bash / Python: `mktemp` / `tempfile.mkstemp()` → write → `mv -f` / `os.replace()`
- PowerShell: `[System.IO.File]::WriteAllText()` (single BCL call, no observable partial state on NTFS)

`mktemp` and `mkstemp` create files with `0600` permissions by default; no explicit `chmod` is needed.

### Error Backoff (API Error Cache)

When an API call fails (expired token, network error, non-2xx response), an error cache file is written with a 30-second TTL. Subsequent script invocations within that window skip the API call entirely, preventing repeated hammering of the Anthropic API on auth failures.

### Caching Strategy

Four cache files are stored in the system temp directory (`%TEMP%` on Windows, `$TMPDIR` / `/tmp` on Unix):

| Cache file | TTL | Content |
|------------|-----|---------|
| `claude_usage_cache.json` | 120 s | Full Anthropic OAuth API response |
| `claude_usage_error_cache.json` | 30 s | Error type — error backoff |
| `claude_git_cache.json` | 8 s | Branch, staged count, modified count, workspace path, HEAD ref |
| `claude_effort_cache.json` | 30 s | `effortLevel` string from settings cascade |

TTL is checked via filesystem mtime (`stat().st_mtime`), not a timestamp embedded in the JSON. The git cache is also invalidated when either the `workspace.current_dir` field or the `.git/HEAD` content changes between invocations.

### Graceful Degradation

No variant crashes on missing external data:

- **No credentials file**: usage section shows `N/A`, no API call is made.
- **API failure**: falls back to the stale cache file if present; shows a stale indicator (`⚠`) if the cache is older than 2× TTL.
- **Git unavailable**: branch and file counts are omitted from line 1.
- **Settings unavailable**: effort defaults to `Not Set`.
- **Missing data fields**: displayed as `N/A` using the locale-appropriate string.

---

## PowerShell — `statusline.ps1`

### Security

**Input size caps**
- Credentials file: size checked before `Get-Content` — `(Get-Item $CRED_FILE).Length -le 65536` (64 KB, line 149).
- Settings files: `(Get-Item $sp).Length -le 262144` (256 KB, line 258) inside the cascade loop.
- Stdin and API response: implicitly bounded by the PowerShell pipeline and `Invoke-RestMethod`'s default behaviour; the JSON payload from Claude Code is small by design.

**OAuth token validation**
```powershell
if ($token -match '[\r\n\x00]') { $token = $null }   # line 152
```
Tokens containing carriage return, line feed, or null bytes are discarded before the `Authorization` header is constructed. This prevents HTTP header injection.

**JSON serialisation safety**
All cache writes use `ConvertTo-Json` piped to `[System.IO.File]::WriteAllText()`:
- Usage cache: lines 157–159
- Error cache: line 167
- Effort cache: lines 269–271
- Git cache: lines 413–415

No string interpolation is used for any value written to disk.

**Workspace path validation**
```powershell
Test-Path $path -PathType Container   # line 378
```

### Stability

**Top-level error handler**
The entire script body is wrapped in a `try/catch` block (lines 124–475). On any unhandled exception, a localised error message is printed without exposing internal details or stack traces.

**Nested error handlers**
- API call: inner `try/catch` (lines 148–169). On failure: error cache is written, stale usage cache is loaded as fallback (line 168).
- Git operations: `try/catch` (line 402) — silently catches all exceptions.
- Effort cache parse: `-ErrorAction SilentlyContinue` (line 248).

**Cache TTL constants**
```powershell
$USAGE_TTL  = 120   # line 29
$GIT_TTL    = 8     # line 30
$EFFORT_TTL = 30    # line 31
$ERROR_TTL  = 30    # line 32
```
TTL checked via `LastWriteTime.AddSeconds()` compared against `$now` (lines 136, 143, 249, 384).

**Git cache dual-key invalidation**
The git cache is valid only when both `$gc.path -eq $path` (workspace) and `$gc.head_ref -eq $headRef` (HEAD file content) match the current invocation (line 384). HEAD is read via file I/O (`Get-Content .git/HEAD`, line 380) to avoid an extra subprocess.

**API timeout**
```powershell
Invoke-RestMethod ... -TimeoutSec $API_TIMEOUT   # line 155, $API_TIMEOUT = 3
```

**Stale-while-revalidate indicators**
Lines 428–433: if a cache is present but older than 2× its TTL, a `⚠` stale flag is appended and the value is coloured gray.

### Performance

**O(n) gradient bar construction**
`Get-GradientBar` function (lines 319–345) uses a pre-allocated `[System.Text.StringBuilder]::new($totalWidth * 26)` (line 325). Each bucket appends a fixed-size ANSI sequence. No string concatenation inside the loop.

**Single output write**
All 6 output lines are appended to a second pre-allocated `StringBuilder` (4 KB, line 452). A single `[Console]::Write($sb.ToString())` call (line 471) writes the entire HUD to stdout.

**JSON parsed once per source**
`ConvertFrom-Json` is called exactly once per data source: stdin (line 130), usage cache (line 137), git cache (line 383), effort cache (line 248), credentials file (line 150), each settings file (line 259).

**Subprocess minimisation**
At most 2 git subprocesses per cache miss: `git branch --show-current` (line 393) and `git status --porcelain` (line 396). HEAD ref is read from `.git/HEAD` via file I/O (line 380) without spawning a process.

---

## Bash — `statusline.sh`

### Security

**Input size caps (named constants)**
```bash
readonly STDIN_MAX_BYTES=1048576    # line 15 — enforced via head -c (line 521)
readonly CRED_MAX_BYTES=65536       # line 16 — stat-checked before read (lines 373-374)
readonly API_RESPONSE_MAX_BYTES=1048576  # line 17 — curl --max-filesize (line 383)
readonly SETTINGS_MAX_BYTES=262144  # line 18 — stat-checked before read (lines 425-426)
```

**OAuth token validation**
```bash
[[ "$token" =~ [^[:print:]] ]] && return 1   # line 379
```
Rejects any non-printable character (broader than the `\r\n\x00` check in PS1/Python), then passes the token only to `curl -H "Authorization: Bearer $token"` (line 384).

**JSON serialisation safety**
All cache writes use `jq -n --arg` to construct JSON with variables as typed arguments:
```bash
jq -n --arg e "$effort" '{"effort": $e}'   # line 439
```
Variables are never interpolated into raw JSON strings.

**Workspace path validation**
```bash
[[ -d "$workspace_path" ]]   # line 475
```

**Temp file permissions**
`atomic_write()` uses `mktemp` (line 205), which creates files with `0600` permissions by default. No explicit `chmod` is required.

**Strict mode**
```bash
set -uo pipefail   # line 5
```
Undefined variable references cause immediate failure; pipeline errors are not silently swallowed.

### Stability

**Top-level error handler**
```bash
main "$@" 2>/dev/null || printf '%s: execution failed\n' "$I18N_ERROR"   # line 725
```
All stderr from `main` is suppressed; any failure prints a localised error message.

**Atomic cache writes — `atomic_write()` function**
```bash
# lines 203-208
local tmp
tmp=$(mktemp "${CACHE_DIR}/claude_tmp_XXXXXX")
printf '%s' "$1" > "$tmp"
mv -f "$tmp" "$2"
```
The rename (`mv -f`) is atomic on POSIX filesystems.

**EXIT trap for temp file cleanup**
```bash
trap '_cleanup' EXIT   # line 180
```
`_cleanup` (lines 177–180) removes the in-flight temp file (`$_TMP_FILE`) on any exit, including signals, preventing orphaned temp files.

**Cache TTL constants**
```bash
readonly USAGE_TTL=120   # line 10
readonly GIT_TTL=8       # line 11
readonly EFFORT_TTL=30   # line 12
readonly ERROR_TTL=30    # line 13
```

**`is_cache_valid()` function**
Lines 186–197: computes `now - mtime` using the pre-detected GNU/BSD `stat` variant; returns 0 (true) if the cache is within its TTL.

**Git cache dual-key invalidation**
Line 467: `cached_path == workspace_path && cached_head_ref == head_ref`. HEAD is read via `read -r head_ref < .git/HEAD` (lines 457–458).

**API timeout and curl error handling**
```bash
curl --max-time "$API_TIMEOUT" --max-filesize "$API_RESPONSE_MAX_BYTES" ...   # lines 382-386
```
Non-zero curl exit or invalid JSON response both trigger error cache write (lines 387–399).

**ANSI constants pre-declared**
Lines 146–163: all colour codes, icons, the 90-character separator, and gradient RGB stops are declared `readonly` at load time, evaluated once.

### Performance

**O(n) gradient bar — single `awk` program**
`get_gradient_bar()` (lines 279–323) delegates the entire computation to a single `awk` invocation. No bash subshells exist inside the gradient loop; all per-bucket arithmetic and `printf` calls happen inside awk.

**Batched `jq` extractions**
- Stdin: single `jq` call extracts 7 fields via multi-output (lines 534–542), captured with `read -r` loop.
- Usage cache: single `jq` call extracts 8 fields (lines 613–622).
- Git cache: single `jq` call extracts 5 fields (lines 464–466).
- Token values: batched into a single `awk` call for 4 conversions (lines 557–559).

**GNU/BSD detection at startup**
```bash
readonly DATE_IS_GNU STAT_IS_GNU   # lines 34-44
```
`date --version` and `stat --version` are called once at script load. All subsequent `stat`/`date` calls use the pre-detected variant, avoiding repeated detection overhead.

**Single output write**
Lines 713–722: all 6 output lines are concatenated into a single `$out` variable; the terminal receives one `printf '%s\n' "$out"` call.

**Subprocess minimisation**
At most 2 git subprocesses per cache miss. HEAD is read via shell file I/O (`read -r < .git/HEAD`), not a subprocess.

---

## Python — `statusline.py`

### Security

**Input size caps (named constants)**
```python
_STDIN_MAX_BYTES        = 1 * 1024 * 1024   # line 31 — sys.stdin.read(limit) at line 434
_CRED_MAX_BYTES         = 64 * 1024          # line 32 — stat check at line 288
_API_RESPONSE_MAX_BYTES = 1 * 1024 * 1024   # line 33 — resp.read(limit) at line 304
_SETTINGS_MAX_BYTES     = 256 * 1024         # line 34 — stat check at line 335
```

**OAuth token validation**
```python
# line 294
if not token.isprintable() or any(c in token for c in ('\r', '\n', '\x00')):
    return None
```
Two independent checks: `str.isprintable()` catches all non-printable Unicode code points; the explicit membership test is defence-in-depth for the three most dangerous header injection characters.

**JSON serialisation safety**
All cache writes use `json.dumps()`:
- Usage cache: line 308
- Error cache: line 311
- Effort cache: line 348
- Git cache: lines 404–411 (with inline comment: *"json.dumps ensures branch cannot contain escape injection"*)

**Workspace path validation**
```python
workspace.is_dir()   # line 381
```

**Atomic cache writes — `atomic_write()` function**
```python
# lines 145-159
fd, tmp_path = tempfile.mkstemp(dir=target.parent, prefix='claude_tmp_')
# ...
os.replace(tmp_path, target)   # atomic on POSIX, best-effort on Windows
```
On any exception, the temp file is removed in the `except` block (lines 155–158).

**Multiple credential file candidates**
```python
# lines 43-46
Path.home() / '.claude' / '.credentials.json'
Path.home() / '.config' / 'claude' / '.credentials.json'
```
Both standard locations are probed; neither path is hard-coded as the sole location.

**Safe field access throughout**
All JSON field access uses `.get()` with explicit defaults (lines 441–453, 485–499). `KeyError` is never raised on missing fields.

### Stability

**Top-level error handler**
```python
# lines 602-607
try:
    main()
except Exception:
    print(f'{_I18N_FMT["error"]}: execution failed')
```

**Per-function error handlers**
- `fetch_usage()` (lines 275–312): entire function in `try/except`; on any exception, writes error cache with the exception type name (line 311).
- `read_effort_cascade()` (line 342): per-file `try/except`; continues to the next candidate on any read or parse failure.
- `read_git_status()` (line 400): `try/except` around both subprocesses; returns `('', 0, 0)` on any failure.
- `_load_json()` (lines 162–167): returns `None` on any error.

**Cache TTL constants**
```python
USAGE_TTL  = 120   # line 25
GIT_TTL    = 8     # line 26
EFFORT_TTL = 30    # line 27
ERROR_TTL  = 30    # line 28
```

**`is_cache_valid()` function**
```python
# lines 137-142
time.time() - path.stat().st_mtime < ttl
```

**Git subprocess timeout (only variant with explicit limit)**
```python
GIT_SUBPROCESS_TIMEOUT = 5   # line 30
subprocess.run(..., timeout=GIT_SUBPROCESS_TIMEOUT)   # lines 385, 389
```
A `subprocess.TimeoutExpired` exception is caught by the surrounding `try/except`, returning empty git data rather than blocking the UI.

**API timeout**
```python
urlopen(req, timeout=API_TIMEOUT)   # line 303, API_TIMEOUT = 3
```

**UTF-8 output reconfiguration**
```python
sys.stdout.reconfigure(encoding='utf-8')   # lines 430-431 (Windows only)
```
Prevents `UnicodeEncodeError` on Windows terminals that default to `cp1252`.

### Performance

**O(n) gradient bar construction**
`gradient_bar()` function (lines 243–255) builds a `list[str]`, then calls `''.join()` once at the end. No string concatenation inside the loop.

**Pre-built empty bucket constant**
```python
_DIM_BUCKET = f'{_DIM_GRAY}{_BKT}{_RST}'   # line 240
```
The dim gray bucket string is constructed once at module load and reused for every unfilled position in every bar.

**Single `json.loads()` per source**
`_load_json()` (lines 162–167) is the sole JSON parsing entry point. It is called exactly once per cache file; all field access uses `.get()` on the already-parsed dict.

**Subprocess minimisation**
At most 2 git subprocesses per cache miss. HEAD is read via `Path.read_text()` (line 360), not a subprocess.

**Single output write**
```python
# lines 562-599
lines: List[str] = []
# ... append all content ...
sys.stdout.write(''.join(lines))
sys.stdout.flush()
```
One `write()` + one `flush()` call for the entire 6-line HUD.

---

## Cross-Variant Comparison

| Feature | `statusline.ps1` | `statusline.sh` | `statusline.py` |
|---------|-----------------|-----------------|-----------------|
| **Stdin cap** | Implicit (pipeline) | 1 MB — `head -c` | 1 MB — `sys.stdin.read()` |
| **Credentials cap** | 64 KB — `Get-Item.Length` | 64 KB — `stat` | 64 KB — `Path.stat().st_size` |
| **API response cap** | Implicit (`Invoke-RestMethod`) | 1 MB — `curl --max-filesize` | 1 MB — `resp.read()` |
| **Settings cap** | 256 KB — `Get-Item.Length` | 256 KB — `stat` | 256 KB — `Path.stat().st_size` |
| **Token validation** | `[\r\n\x00]` regex | `[^[:print:]]` regex | `isprintable()` + `\r\n\x00` |
| **Atomic writes** | `WriteAllText` (BCL) | `mktemp` + `mv -f` | `mkstemp` + `os.replace()` |
| **EXIT cleanup** | None | `trap '_cleanup' EXIT` | `except` in `atomic_write()` |
| **Git subprocess timeout** | None | None | 5 s — `subprocess timeout=` |
| **API timeout** | 3 s — `-TimeoutSec` | 3 s — `--max-time` | 3 s — `urlopen timeout=` |
| **Top-level error handler** | `try/catch` | `main \|\| printf error` | `try/except Exception` |
| **Gradient bar strategy** | `StringBuilder` pre-alloc | Single `awk` program | `list` + `''.join()` |
| **JSON parse calls** | 1 per source (`ConvertFrom-Json`) | 1 per source (`jq`) | 1 per source (`json.loads`) |
| **Single output write** | `[Console]::Write(sb)` | `printf '%s\n' "$out"` | `sys.stdout.write(join)` |
| **GNU/BSD detection** | N/A (Windows only) | Once at startup (`readonly`) | N/A (Python abstracts OS) |
| **Strict mode** | Default PS behaviour | `set -uo pipefail` | N/A |
| **UTF-8 reconfiguration** | `[Console]::OutputEncoding` | Locale from `$LANG`/`$LC_ALL` | `sys.stdout.reconfigure()` |
