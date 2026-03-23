# Test Suite

Three parallel test suites — one per runtime variant — verify that `statusline.ps1`, `statusline.sh`, and `statusline.py` produce identical output and enforce the same security, stability, and performance guarantees.

| File | Framework | Test definitions | Approx. expanded cases |
|------|-----------|-----------------|------------------------|
| `test_statusline.bats` | bats-core | 113 | 113 |
| `test_statusline.py` | pytest | 101 | ~155+ (parametrize) |
| `test_statusline.ps1` | Pester v5 | 98 | 98 |
| **Total** | | **312** | **~366+** |

All three suites share the same functional coverage areas, the same minimal JSON test payload, and the same set of locale/security/I18N scenarios, ensuring consistent behaviour across runtimes.

---

## Table of Contents

- [Bash — `test_statusline.bats`](#bash--test_statuslinebats)
- [Python — `test_statusline.py`](#python--test_statuslinepy)
- [PowerShell — `test_statusline.ps1`](#powershell--test_statuslineps1)
- [Shared Patterns](#shared-patterns)

---

## Bash — `test_statusline.bats`

**Framework:** [bats-core](https://github.com/bats-core/bats-core) — no external assertion libraries; assertions use direct `$status` / `$output` checks.

### Requirements

| Dependency | Notes |
|------------|-------|
| bats-core | `sudo apt install bats` (Debian/Ubuntu/WSL) · `brew install bats-core` (macOS) |
| jq | Required by `statusline.sh` |
| awk, date, stat | POSIX tools (pre-installed on all supported platforms) |
| python3 | Used by a small number of tests to generate oversized fixture files |

### Run

```bash
# Run the full suite
bats tests/test_statusline.bats

# Run with TAP output
bats --formatter tap tests/test_statusline.bats

# Run a single test by name
bats --filter "atomic_write" tests/test_statusline.bats
```

### Setup / Teardown

Each test gets an isolated temp directory via `setup()` / `teardown()`:

- `setup()` — creates `$BATS_TEST_TMPDIR`, sets `TMPDIR`, strips the `main` call from `statusline.sh` into a sourceable `funcs.sh`.
- `teardown()` — removes the temp directory unconditionally.

Helper: `run_with_locale LOCALE 'bash code'` — executes code in a subshell with a specific `LC_MONETARY`.

### Coverage (113 tests)

| Area | Tests | Description |
|------|-------|-------------|
| `is_cache_valid` | 4 | Missing file, fresh file, expired file, TTL=0 |
| `atomic_write` | 3 | Basic write, overwrite, unicode content |
| `fmt_tokens` | 5 | 0, 999, 1 000, 1 500, 10 000 (K threshold) |
| `fmt_currency` | 14 | `it_IT`, `en_US`, `en_GB`, `ja_JP`, `fr_CH`, `pt_BR`; `null`/empty → N/A / N/D |
| `_init_currency` | 5 | Symbol, decimals, space/position per locale |
| `_init_date_fmt` | 5 | Order, separator, 12h/24h per locale |
| `fmt_date` | 10 | Empty/invalid input; Italian weekdays (`LUN`–`DOM`); format regex for `it`, `en_US`, `de_DE` |
| `read_effort_cascade` | 4 | Default, reads `settings.local.json`, valid cache, expired cache |
| `read_git_status` | 2 | Cache hit, non-git directory |
| `_init_i18n` | 5 | N/A strings, effort labels, error labels, unknown locale fallback |
| Integration (`main`) | 6 | `ENV:`, `XTRA USG:`, `CONTEXT_WINDOW` in output; empty input; `it_IT`/`de_DE` labels |
| Security — stdin cap | 3 | `STDIN_MAX_BYTES=1048576`, within/over limit |
| Security — credentials cap | 4 | `CRED_MAX_BYTES=65536`, within/over/exact limit |
| Security — API response cap | 3 | `API_RESPONSE_MAX_BYTES=1048576`, `curl --max-filesize` |
| Security — settings cap | 4 | `SETTINGS_MAX_BYTES=262144`, within/over limit, fallback to next file |
| Security — token validation | 6 | Printable token accepted; `\n`, `\r`, control chars rejected |
| Performance — single `jq` git | 3 | Cache read, path-change invalidation, no redundant `jq` calls |
| Performance — single `date` call | 5 | ISO format, empty/invalid → N/A, uses `read -r` |
| Performance — single `awk` tokens | 4 | Values <1 000 and ≥1 000, integration, no redundant calls |
| Performance — `$_SEP90` pre-calc | 5 | Defined globally, exactly 90 chars, used in `main` |
| Performance — single output block | 4 | 13 output lines, all 6 labels, assembled into `$out` |
| Performance — balance dedup | 4 | Via `fmt_currency`, matches expected value, N/A on null, no duplicate awk |
| Performance — gradient constants | 6 | 12 `_GRAD_*` constants, ANSI usage, 0%/100% colors, no hardcoded values |

---

## Python — `test_statusline.py`

**Framework:** [pytest](https://docs.pytest.org/) ≥ 7. Uses standard `pytest` fixtures and `@pytest.mark.parametrize`.

### Requirements

| Dependency | Version | Notes |
|------------|---------|-------|
| Python | 3.8+ | No external packages; `statusline.py` uses stdlib only |
| pytest | ≥ 7 | `pip install pytest` |

### Run

```bash
# Run the full suite (verbose)
pytest tests/test_statusline.py -v

# Compact output on failure
pytest tests/test_statusline.py -v --tb=short

# Run a single class
pytest tests/test_statusline.py::TestFmtCurrency -v

# Run a single test
pytest tests/test_statusline.py::TestAtomicWrite::test_scrittura_base -v
```

### Fixtures

| Fixture | Scope | Description |
|---------|-------|-------------|
| `tmp_cache` | function | Redirects `USAGE_CACHE`, `GIT_CACHE`, `EFFORT_CACHE` to `tmp_path`; monkeypatches module globals |
| `isolate_home` | function (autouse in `TestReadEffortCascade`) | Redirects `Path.home()` to a temp directory for settings cascade tests |

Shared constant `_MINIMAL_PAYLOAD` provides the canonical JSON test payload used by all integration tests.

### Coverage (101 functions, ~155+ expanded cases)

| Class | Functions | Description |
|-------|-----------|-------------|
| `TestIsCacheValid` | 5 | Missing, fresh, expired, TTL=0, TTL negative |
| `TestAtomicWrite` | 4 | Basic write, overwrite, unicode, empty content |
| `TestLoadJson` | 4 | Valid JSON, missing file, corrupt JSON, empty file |
| `TestDetectLocaleTag` | 6 | `locale.getlocale()`, hyphen normalisation, `LANG`/`LC_ALL` env fallback, exception handling |
| `TestGetCurrencyFmt` | 3 + 16 params | Full locale table (16 locales), unknown/empty fallback |
| `TestLocaleTag` | 5 | Module-level locale consistency; `detect_locale_tag()` called once |
| `TestFmtCurrency` | 10 + params | 6 locales (€ / $ / £ / ¥ / CHF / R$); `None` → N/A / N/D; non-numeric input |
| `TestGetDateFmt` | 3 + 16 params | Full date format table (16 locales), unknown fallback |
| `TestFmtDate` | 8 + 7 params | Empty/invalid input; 7 Italian weekdays; format regex for `it`, `en_US`, `de_DE`, `ja_JP` |
| `TestFmtTokens` | 1 + 6 params | 0, 999, 1 000, 1 500, 10 000, 1 000 000 |
| `TestInterpColor` | 4 + 8 params | Gradient start/end, negative/upper clamping, 8 positions in range `[0, 255]` |
| `TestGradientBar` | 8 | Default/custom width, 0%/100%, width 0/1, dim bucket used/absent |
| `TestDimBucket` | 5 | Type, content (`DIM_GRAY`, `BKT`, `RST`), equality to f-string |
| `TestReadEffortCascade` | 4 | Default, reads `settings.local.json`, cache hit, cache expired |
| `TestReadGitStatus` | 5 | Cache hit, path-change invalidation, mocked subprocess output, non-git repo, `timeout=` passed |
| `TestGitSubprocessTimeout` | 2 | Is positive integer, default value is 5 |
| `TestValidazioneCache` | 4 | `fetch_usage` skips write on missing fields / writes on valid fields; effort/git write guards |
| `TestFetchUsageTokenValidation` | 2 + 4 params | 4 invalid tokens rejected, valid token calls `urlopen` |
| `TestCredMaxBytes` | 4 | Is positive integer, equals 64 KB, oversized file rejected, within-limit file accepted |
| `TestApiResponseMaxBytes` | 3 | Is positive integer, equals 1 MB, `resp.read()` called with limit |
| `TestSettingsMaxBytes` | 4 | Is positive integer, equals 256 KB, oversized file skipped, within-limit file read |
| `TestStdinMaxBytes` | 4 | Is positive integer, equals 1 MB, `main` reads with limit, truncated payload no error |
| `TestMain` | 10 | All 6 output sections present; empty/invalid JSON input; separators; locale-specific labels; balance calculation; N/A on null values |
| `TestI18N` | 7 | All languages present, all keys present, N/A/N/D values, effort/error labels, `lang2` fallback |

---

## PowerShell — `test_statusline.ps1`

**Framework:** [Pester v5](https://pester.dev/).

### Requirements

| Dependency | Version | Notes |
|------------|---------|-------|
| PowerShell | 5.1+ | PS 7+ (pwsh) recommended |
| Pester | v5 | `Install-Module -Name Pester -Force -SkipPublisherCheck` |

### Run

```powershell
# Run with Pester (detailed output)
Invoke-Pester -Path tests/test_statusline.ps1 -Output Detailed

# Run via pwsh (used in CI)
pwsh -NoProfile tests/test_statusline.ps1

# Run a single Describe block
Invoke-Pester -Path tests/test_statusline.ps1 -Output Detailed -FullNameFilter "Format-Currency*"
```

### Setup / Teardown

- `BeforeAll` — dot-sources `statusline.ps1` with an empty `$Input` pipeline to load all functions and script-scope variables without running `main`.
- Per-`Describe` `BeforeEach` blocks set `$script:CurrFmt`, `$script:DateFmt`, and `$script:I18nFmt` to the locale required by that block.

### Coverage (98 tests)

| Describe block | Tests | Description |
|----------------|-------|-------------|
| `Format-Currency` | 16 | `it_IT` (6 values), `en_US` (3), `en_GB` (1), `ja_JP` (3), `fr_CH` (2), `pt_BR` (1); `null` handling |
| `CurrencyTable` | 7 | 16 locales present; `it_IT`/`en_US`/`ja_JP` properties; unknown fallback to `en_US` |
| `DateTable` | 5 | 16 locales present; `it_IT` DMY/24h; `en_US` MDY/12h; `de_DE` dot separator; unknown fallback |
| `Get-FmtDate` | 10 | Empty/null/invalid input; `it_IT` — `LUN`, `DOM`, `MAR`, format regex; `en_US` MDY 12h + `MON`; `de_DE` dot |
| `Format-Tokens` | 5 | 0, 999, 1 000, 1 500, 10 000 |
| `Get-GradientBar` | 6 | Width=10 bucket count, 0%/100%, width=0 empty, width=1, width=48 default |
| `Get-PctColor` | 4 | 0% → green, 100% → red, ANSI format, RGB values in `[0, 255]` |
| Integration | 4 | `ENV:`, `XTRA USG:`, `CONTEXT_WINDOW` in output; empty input no error |
| I18N | 11 | 8 languages present; `it` N/D, `en` N/A; `de` Aufwand; error strings; unknown fallback; `Format-Currency null` + `Get-FmtDate` empty/invalid per locale |
| `ConvertTo-Json -Depth 10` | 3 | Round-trip with depth 3, default depth truncates nested objects, API response survives round-trip |
| Git path validation | 4 | Non-existent path: no error, `ENV:` still rendered; empty path fallback; valid path renders |
| Gradient stops dedup | 11 | `$GradientStops` defined, 4 stops, RGB values for green/yellow/orange/red, 0%/100% colors via stops, modifying stops changes output |
| Pre-calculated constants | 11 | `$cDimGray` ANSI format; `$Sep90` defined/90 chars/ANSI start/reset end; `Get-GradientBar`/`Get-PctColor` use constants |
| Atomic cache write | 4 | `WriteAllText` produces valid JSON, compact single line, round-trip preserves values, no `Out-File` |
| Single `[Console]::Write` | 4 | Uses `[Console]::Write`, no `Write-Host` in try body, exactly 12 output lines, contains `ENV:` |

---

## Shared Patterns

All three suites follow the same conventions to ensure cross-variant consistency.

**Same test payload** — every integration test pipes this exact JSON:
```json
{"model":{"display_name":"Sonnet 4.6"},"context_window":{"context_window_size":200000,"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1000,"current_usage":{"cache_read_input_tokens":0}},"workspace":{"current_dir":"/home/user/my-project"}}
```

**Same functional areas** — all three suites cover the same core functions: `is_cache_valid`, `atomic_write`, `fmt_tokens`, `fmt_currency`, `fmt_date`, `read_effort_cascade`, `read_git_status`, gradient bar rendering, and end-to-end integration.

**Same locale set** — currency and date formatting is verified for `it_IT`, `en_US`, `en_GB`, `de_DE`, `ja_JP`, `fr_CH`, `pt_BR` with identical expected values.

**Same security scenarios** — OAuth token control-character rejection, credential file 64 KB cap, API response 1 MB cap, and settings file 256 KB cap are tested in all three suites.

**Temp directory isolation** — each test gets its own isolated cache directory:
- bash: `mktemp -d` in `setup()`, removed in `teardown()`
- Python: `pytest` built-in `tmp_path` fixture + `monkeypatch`
- PowerShell: `BeforeAll` / `BeforeEach` with `$script:` scoped variables pointing to `$TestDrive`

**Structural source assertions** (bash and PowerShell) — a subset of tests grep the source code to verify performance patterns (e.g. single `[Console]::Write`, no `Out-File`, no duplicate `fmt_tokens` calls). The Python suite covers the same patterns via mock-based assertions.
