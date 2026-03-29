#!/usr/bin/env python3
"""
statusline.py — HUD for Claude Code (Windows / Linux / macOS / WSL)
Python port of statusline.ps1
Dependencies: Python 3.8+ stdlib only
"""

from __future__ import annotations

import json
import locale as _locale_module
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------
# Constants — identical to statusline.ps1
# ---------------------------------------------------------------------------
USAGE_TTL   = 120  # seconds — Anthropic API call
GIT_TTL     = 8    # seconds — git branch + status
EFFORT_TTL  = 30   # seconds — settings file read
ERROR_TTL   = 30   # seconds — API error backoff (4d)
API_TIMEOUT = 3    # seconds — HTTP API call timeout
GIT_SUBPROCESS_TIMEOUT = 5  # seconds — git subprocess hard deadline
_STDIN_MAX_BYTES = 1 * 1024 * 1024  # 1 MB — sanity cap on stdin payload
_CRED_MAX_BYTES          = 64 * 1024        # 64 KB — credentials file is never legitimately large
_API_RESPONSE_MAX_BYTES  = 1 * 1024 * 1024  # 1 MB — sanity cap on API response
_SETTINGS_MAX_BYTES      = 256 * 1024       # 256 KB — settings files are never legitimately large

CACHE_DIR         = Path(tempfile.gettempdir())
USAGE_CACHE       = CACHE_DIR / 'claude_usage_cache.json'
USAGE_ERROR_CACHE = CACHE_DIR / 'claude_usage_error.json'
GIT_CACHE         = CACHE_DIR / 'claude_git_cache.json'
EFFORT_CACHE      = CACHE_DIR / 'claude_effort_cache.json'

_HOME = Path.home()
_CRED_CANDIDATES: List[Path] = [
    _HOME / '.claude' / '.credentials.json',
    _HOME / '.config' / 'claude' / '.credentials.json',
]

# ---------------------------------------------------------------------------
# RGB gradient — stops identical to statusline.ps1
# ---------------------------------------------------------------------------
_GRADIENT_STOPS: List[Tuple[float, Tuple[int, int, int]]] = [
    (0.00, (74,  222, 128)),   # green
    (0.33, (250, 204, 21)),    # yellow
    (0.66, (251, 146, 60)),    # orange
    (1.00, (239, 68,  68)),    # red
]

# ---------------------------------------------------------------------------
# Currency localisation — locale → (symbol, dec_sep, sym_before, space, decimals)
# ---------------------------------------------------------------------------
_CURRENCY_TABLE: Dict[str, Tuple[str, str, bool, bool, int]] = {
    'it_IT': ('\u20ac', ',', False, True,  2),
    'de_DE': ('\u20ac', ',', False, True,  2),
    'fr_FR': ('\u20ac', ',', False, True,  2),
    'es_ES': ('\u20ac', ',', False, True,  2),
    'pt_PT': ('\u20ac', ',', False, True,  2),
    'en_US': ('$',      '.', True,  False, 2),
    'en_AU': ('$',      '.', True,  False, 2),
    'en_CA': ('$',      '.', True,  False, 2),
    'en_GB': ('\u00a3', '.', True,  False, 2),
    'ja_JP': ('\u00a5', '.', True,  False, 0),
    'zh_CN': ('\u00a5', '.', True,  False, 2),
    'zh_TW': ('\u00a5', '.', True,  False, 2),
    'fr_CH': ('CHF', '.', True,  True,  2),
    'de_CH': ('CHF', '.', True,  True,  2),
    'it_CH': ('CHF', '.', True,  True,  2),
    'pt_BR': ('R$',  ',', True,  False, 2),
}
_FALLBACK_CURRENCY: Tuple[str, str, bool, bool, int] = ('$', '.', True, False, 2)

_DATE_TABLE: Dict[str, Dict] = {
    'it_IT': {'days': ['','LUN','MAR','MER','GIO','VEN','SAB','DOM'], 'order':'DMY','sep':'/','h24':True},
    'it_CH': {'days': ['','LUN','MAR','MER','GIO','VEN','SAB','DOM'], 'order':'DMY','sep':'/','h24':True},
    'de_DE': {'days': ['','MO','DI','MI','DO','FR','SA','SO'],        'order':'DMY','sep':'.','h24':True},
    'de_CH': {'days': ['','MO','DI','MI','DO','FR','SA','SO'],        'order':'DMY','sep':'.','h24':True},
    'fr_FR': {'days': ['','LUN','MAR','MER','JEU','VEN','SAM','DIM'], 'order':'DMY','sep':'/','h24':True},
    'fr_CH': {'days': ['','LUN','MAR','MER','JEU','VEN','SAM','DIM'], 'order':'DMY','sep':'/','h24':True},
    'es_ES': {'days': ['','LUN','MAR','MIE','JUE','VIE','SAB','DOM'],'order':'DMY','sep':'/','h24':True},
    'pt_PT': {'days': ['','SEG','TER','QUA','QUI','SEX','SAB','DOM'], 'order':'DMY','sep':'/','h24':True},
    'pt_BR': {'days': ['','SEG','TER','QUA','QUI','SEX','SAB','DOM'], 'order':'DMY','sep':'/','h24':True},
    'en_US': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'MDY','sep':'/','h24':False},
    'en_AU': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'MDY','sep':'/','h24':False},
    'en_CA': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'MDY','sep':'/','h24':False},
    'en_GB': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'DMY','sep':'/','h24':True},
    'ja_JP': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'MDY','sep':'/','h24':True},
    'zh_CN': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'DMY','sep':'/','h24':True},
    'zh_TW': {'days': ['','MON','TUE','WED','THU','FRI','SAT','SUN'], 'order':'DMY','sep':'/','h24':True},
}
_FALLBACK_DATE: Dict = _DATE_TABLE['en_US']

_I18N: Dict[str, Dict[str, str]] = {
    'it': {'effort': 'Effort',   'na': 'N/D', 'error': 'ERRORE STATUSBAR'},
    'en': {'effort': 'Effort',   'na': 'N/A', 'error': 'STATUS ERROR'},
    'de': {'effort': 'Aufwand',  'na': 'N/A', 'error': 'STATUSLEISTE FEHLER'},
    'fr': {'effort': 'Effort',   'na': 'N/V', 'error': 'ERREUR STATUSBAR'},
    'es': {'effort': 'Esfuerzo', 'na': 'N/V', 'error': 'ERROR STATUSBAR'},
    'pt': {'effort': 'Esforco',  'na': 'N/D', 'error': 'ERRO STATUSBAR'},
    'ja': {'effort': 'Effort',   'na': 'N/A', 'error': 'STATUS ERROR'},
    'zh': {'effort': 'Effort',   'na': 'N/A', 'error': 'STATUS ERROR'},
}


def _detect_locale_tag() -> str:
    """Returns the normalised locale tag (e.g. 'it_IT', 'en_US')."""
    try:
        loc = _locale_module.getlocale()[0] or ''
    except Exception:
        loc = ''
    if not loc:
        loc = os.environ.get('LANG', os.environ.get('LC_ALL', ''))
        loc = loc.split('.')[0]
    return loc.replace('-', '_')


_LOCALE_TAG   = _detect_locale_tag()
_CURRENCY_FMT = _CURRENCY_TABLE.get(_LOCALE_TAG, _FALLBACK_CURRENCY)
_DATE_FMT: Dict = _DATE_TABLE.get(_LOCALE_TAG, _FALLBACK_DATE)
_LANG2        = _LOCALE_TAG[:2].lower()
_I18N_FMT: Dict[str, str] = _I18N.get(_LANG2, _I18N['en'])

_EFFORT_MAP = {'low': 'Low', 'medium': 'Medium', 'high': 'High', 'max': 'Max'}

# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------

def is_cache_valid(path: Path, ttl: int) -> bool:
    """True if the file exists and was written less than ttl seconds ago."""
    try:
        return time.time() - path.stat().st_mtime < ttl
    except OSError:
        return False


def atomic_write(target: Path, content: str) -> None:
    """Atomic write: mkstemp in the same directory → os.replace().
    os.replace() is atomic on POSIX and best-effort on Windows.
    mkstemp sets permissions to 0600 — no explicit chmod needed."""
    fd, tmp_path = tempfile.mkstemp(dir=target.parent, prefix='claude_tmp_')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            fh.write(content)
        os.replace(tmp_path, target)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _load_json(path: Path) -> Optional[Dict]:
    """Reads and parses a JSON file; returns None on any error."""
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return None

# ---------------------------------------------------------------------------
# Formattazione
# ---------------------------------------------------------------------------

def fmt_date(raw: str) -> str:
    """ISO 8601 → localised date format 'DDD dd/MM H: HH:mm' (or locale variant)."""
    if not raw:
        return _I18N_FMT['na']
    try:
        dt = datetime.fromisoformat(raw.replace('Z', '+00:00')).astimezone()
        days = _DATE_FMT['days']
        sep  = _DATE_FMT['sep']
        day  = days[dt.isoweekday()]
        if _DATE_FMT['order'] == 'MDY':
            date_str = dt.strftime(f'%m{sep}%d')
        else:
            date_str = dt.strftime(f'%d{sep}%m')
        time_str = dt.strftime('%H:%M') if _DATE_FMT['h24'] else dt.strftime('%I:%M %p')
        return f'{day} {date_str} H: {time_str}'
    except (ValueError, OverflowError, OSError):
        return _I18N_FMT['na']


def fmt_tokens(n: int) -> str:
    """Formats token count: ≥1000 → 'X.XK', otherwise integer."""
    return f'{n / 1000:.1f}K' if n >= 1000 else str(n)


def fmt_currency(cents) -> str:
    """Cents → locale currency string. None/non-numeric → localised N/A."""
    if cents is None:
        return _I18N_FMT['na']
    try:
        sym, dec_sep, sym_before, sym_space, decimals = _CURRENCY_FMT
        value = float(cents) / 100
        if decimals == 0:
            num_str = str(int(round(value)))
        else:
            num_str = f'{value:.{decimals}f}'.replace('.', dec_sep)
        sp = ' ' if sym_space else ''
        if sym_before:
            return f'{sym}{sp}{num_str}'
        else:
            return f'{num_str}{sp}{sym}'
    except (TypeError, ValueError):
        return _I18N_FMT['na']

# ---------------------------------------------------------------------------
# Gradiente RGB — O(n) con list + join, nessuna concatenazione in loop
# ---------------------------------------------------------------------------

def _interp_color(pos: float) -> Tuple[int, int, int]:
    """Interpolates the RGB color at position [0,1] along the gradient."""
    pos = max(0.0, min(1.0, pos))
    for i in range(len(_GRADIENT_STOPS) - 1):
        p0, c0 = _GRADIENT_STOPS[i]
        p1, c1 = _GRADIENT_STOPS[i + 1]
        if pos <= p1:
            t = (pos - p0) / (p1 - p0) if p1 > p0 else 0.0
            return (
                int(c0[0] + t * (c1[0] - c0[0])),
                int(c0[1] + t * (c1[1] - c0[1])),
                int(c0[2] + t * (c1[2] - c0[2])),
            )
    return _GRADIENT_STOPS[-1][1]


_ESC      = '\033'
_DIM_GRAY = f'{_ESC}[38;2;60;60;60m'
_RST      = f'{_ESC}[0m'
_BKT        = '\u26c1'   # ⛁
_DIM_BUCKET = f'{_DIM_GRAY}{_BKT}{_RST}'   # pre-built empty bucket string


def gradient_bar(percent: float, total_width: int = 48) -> str:
    """RGB gradient bar of total_width ⛁ characters.
    Uses list + join → O(n), avoids O(n²) allocations from string concatenation."""
    filled = min(total_width, max(0, round(percent / 100 * total_width)))
    parts: List[str] = []
    for i in range(1, total_width + 1):
        pos = (i - 1) / (total_width - 1) if total_width > 1 else 0.0
        if i <= filled:
            r, g, b = _interp_color(pos)
            parts.append(f'{_ESC}[38;2;{r};{g};{b}m{_BKT}{_RST}')
        else:
            parts.append(_DIM_BUCKET)
    return ''.join(parts)


def pct_color(percent: float) -> str:
    """ANSI RGB color code for the given percentage (same gradient as the bar)."""
    r, g, b = _interp_color(percent / 100)
    return f'{_ESC}[38;2;{r};{g};{b}m'

# ---------------------------------------------------------------------------
# API Anthropic — Usage (cache 120s)
# ---------------------------------------------------------------------------

def _find_cred_file() -> Optional[Path]:
    """Returns the first existing credentials file from _CRED_CANDIDATES, or None."""
    for p in _CRED_CANDIDATES:
        if p.exists():
            return p
    return None


def fetch_usage() -> None:
    """Updates USAGE_CACHE if expired.
    The OAuth token is passed only in the HTTP header, never logged or interpolated
    into strings that land on disk."""
    if is_cache_valid(USAGE_CACHE, USAGE_TTL):
        return
    # 4d: skip API if a fresh error is cached (prevents hammering with expired token)
    if is_cache_valid(USAGE_ERROR_CACHE, ERROR_TTL):
        return
    cred_path = _find_cred_file()
    if cred_path is None:
        return
    try:
        if cred_path.stat().st_size > _CRED_MAX_BYTES:
            return
        creds = json.loads(cred_path.read_text(encoding='utf-8'))
        token: str = creds.get('claudeAiOauth', {}).get('accessToken', '')
        if not token:
            return
        if not token.isprintable() or any(c in token for c in ('\r', '\n', '\x00')):
            return
        req = Request(
            'https://api.anthropic.com/api/oauth/usage',
            headers={
                'Authorization': f'Bearer {token}',
                'anthropic-beta': 'oauth-2025-04-20',
            },
        )
        with urlopen(req, timeout=API_TIMEOUT) as resp:
            data = resp.read(_API_RESPONSE_MAX_BYTES).decode('utf-8')
        # Validate structure before writing: must be valid JSON with expected fields
        parsed = json.loads(data)
        if 'five_hour' in parsed and 'seven_day' in parsed:
            atomic_write(USAGE_CACHE, data)
            USAGE_ERROR_CACHE.unlink(missing_ok=True)
    except Exception as exc:
        err_payload = json.dumps({'error': type(exc).__name__, 'timestamp': int(time.time())})
        atomic_write(USAGE_ERROR_CACHE, err_payload)

# ---------------------------------------------------------------------------
# Effort Level (cache 30s)
# ---------------------------------------------------------------------------

def read_effort_cascade(workspace: Path) -> str:
    """Reads effortLevel from settings files with cascade and caching."""
    if is_cache_valid(EFFORT_CACHE, EFFORT_TTL):
        cached = _load_json(EFFORT_CACHE)
        if cached is not None:
            return str(cached.get('effort', 'normal'))

    effort = 'normal'
    settings_paths = [
        workspace / '.claude' / 'settings.local.json',
        workspace / '.claude' / 'settings.json',
        _HOME / '.claude' / 'settings.local.json',
        _HOME / '.claude' / 'settings.json',
    ]
    for sp in settings_paths:
        if sp.exists():
            try:
                if sp.stat().st_size > _SETTINGS_MAX_BYTES:
                    continue
                data = json.loads(sp.read_text(encoding='utf-8'))
                val = data.get('effortLevel', '')
                if val:
                    effort = str(val)
                    break
            except Exception:
                continue

    try:
        effort_data = {'effort': effort}
        if effort_data.get('effort'):
            atomic_write(EFFORT_CACHE, json.dumps(effort_data))
    except Exception:
        pass
    return effort

# ---------------------------------------------------------------------------
# Git Status (8s cache, invalidated on path change)
# ---------------------------------------------------------------------------

def _read_head_ref(workspace: Path) -> str:
    """Reads .git/HEAD without git subprocesses (4e)."""
    try:
        return (workspace / '.git' / 'HEAD').read_text(encoding='utf-8').strip()
    except OSError:
        return ''


def read_git_status(workspace: Path) -> Tuple[str, int, int]:
    """(branch, staged, modified) with GIT_CACHE caching.
    Cache invalidated by TTL, path change, or HEAD change (4e)."""
    head_ref = _read_head_ref(workspace)
    if is_cache_valid(GIT_CACHE, GIT_TTL):
        cached = _load_json(GIT_CACHE)
        if (cached is not None
                and cached.get('path') == str(workspace)
                and cached.get('head_ref') == head_ref):
            return (
                str(cached.get('branch', '')),
                int(cached.get('staged', 0)),
                int(cached.get('modified', 0)),
            )

    branch, staged, modified = '', 0, 0
    if workspace.is_dir():
        try:
            res = subprocess.run(
                ['git', '-C', str(workspace), 'branch', '--show-current'],
                capture_output=True, text=True, timeout=GIT_SUBPROCESS_TIMEOUT,
            )
            branch = res.stdout.strip()
            if branch:
                res = subprocess.run(
                    ['git', '-C', str(workspace), 'status', '--porcelain'],
                    capture_output=True, text=True, timeout=GIT_SUBPROCESS_TIMEOUT,
                )
                for line in res.stdout.splitlines():
                    if len(line) >= 2:
                        x, y = line[0], line[1]
                        if x not in (' ', '?'):
                            staged += 1
                        if y not in (' ', '?'):
                            modified += 1
        except Exception:
            pass

    try:
        # json.dumps ensures branch cannot contain escape injection
        git_data = {
            'branch': branch, 'staged': staged,
            'modified': modified, 'path': str(workspace),
            'head_ref': head_ref,
        }
        if 'branch' in git_data and 'path' in git_data:
            atomic_write(GIT_CACHE, json.dumps(git_data))
    except Exception:
        pass
    return branch, staged, modified

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    """Entry point: reads Claude Code telemetry JSON from stdin and writes the
    6-line ANSI RGB HUD to stdout.

    Reads up to _STDIN_MAX_BYTES from stdin, parses the JSON payload, enriches
    it with git status, effort level from the settings cascade, and Anthropic
    OAuth API usage metrics, then writes the formatted output in a single
    sys.stdout.write call to minimise system-call overhead.
    """
    # Force UTF-8 output (needed on Windows where the default may be cp1252)
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')

    # 1. Read JSON from stdin
    raw = sys.stdin.read(_STDIN_MAX_BYTES).strip() or '{}'
    try:
        j: Dict = json.loads(raw)
    except json.JSONDecodeError:
        j = {}

    # 2. Claude Code fields — safe access with .get() + defaults
    model         = j.get('model', {}).get('display_name', 'Claude') or 'Claude'
    workspace_str = j.get('workspace', {}).get('current_dir', '.') or '.'
    workspace     = Path(workspace_str)
    dir_name      = workspace.name or workspace_str

    ctx_win    = j.get('context_window') or {}
    pct        = int(float(ctx_win.get('used_percentage') or 0))
    ctx_max    = int(float(ctx_win.get('context_window_size') or 200_000))
    tok_in     = int(float(ctx_win.get('total_input_tokens') or 0))
    tok_out    = int(float(ctx_win.get('total_output_tokens') or 0))
    cur_usage  = ctx_win.get('current_usage') or {}
    tok_cached = int(float(cur_usage.get('cache_read_input_tokens') or 0))
    tok_total  = tok_in + tok_out + tok_cached

    if ctx_max >= 1_000_000:
        ctx_max_fmt = f'{ctx_max // 1_000_000}M'
    elif ctx_max >= 1_000:
        ctx_max_fmt = f'{ctx_max // 1_000}K'
    else:
        ctx_max_fmt = str(ctx_max)

    # 3. Effort
    effort_raw = read_effort_cascade(workspace)
    effort     = _EFFORT_MAP.get(effort_raw, 'Not Set')

    # 4. Usage API (cache 120s)
    fetch_usage()

    # Stato cache dopo il fetch: 'fresh' | 'stale' | 'missing'
    try:
        _cache_age = time.time() - USAGE_CACHE.stat().st_mtime
        _usage_state = 'fresh' if _cache_age < USAGE_TTL else 'stale'
    except OSError:
        _cache_age = float('inf')
        _usage_state = 'missing'

    u5h = uwk = 0
    r5h = rwk = _I18N_FMT['na']
    extra_usage: Optional[bool] = None
    month_limit = used_credits = None
    month_util  = _I18N_FMT['na']

    usage = _load_json(USAGE_CACHE)
    if usage:
        fh = usage.get('five_hour') or {}
        sd = usage.get('seven_day') or {}
        ex = usage.get('extra_usage') or {}

        u5h = int(float(fh.get('utilization') or 0))
        uwk = int(float(sd.get('utilization') or 0))
        r5h = fmt_date(fh.get('resets_at', ''))
        rwk = fmt_date(sd.get('resets_at', ''))

        extra_usage  = ex.get('is_enabled')
        month_limit  = ex.get('monthly_limit')
        used_credits = ex.get('used_credits')
        util_raw     = ex.get('utilization')
        if util_raw is not None:
            month_util = f'{float(util_raw):.1f}%'.replace('.', _CURRENCY_FMT[1])

    # 5. Git
    branch, staged, modified = read_git_status(workspace)

    # 6. ANSI Colors
    E   = '\033'
    cR  = f'{E}[0m'    # reset
    cC  = f'{E}[36m'   # cyan
    cG  = f'{E}[32m'   # green
    cY  = f'{E}[33m'   # yellow
    cGr = f'{E}[90m'   # gray
    cW  = f'{E}[37m'   # white
    cBr = f'{E}[38;2;186;230;253m'   # branch (light blue)
    cOr = f'{E}[38;2;255;165;0m'     # orange

    ico_folder = '\U0001f4c1'   # 📁
    ico_leaf   = '\U0001f33f'   # 🌿

    # 7. Git branch string
    branch_str = ''
    if branch:
        suffix = ''
        if staged:
            suffix += f' {cG}+{staged}{cR}'
        if modified:
            suffix += f' {cY}~{modified}{cR}'
        branch_str = f' {ico_leaf} {cBr}Branch{cR}: {branch}{suffix}'

    # 8. Separator 90× ─
    sep = f'{cGr}{"─" * 90}{cR}'

    # 9. Gradient bars and percentage colors
    bar_ctx = gradient_bar(pct, 76)
    bar_5h  = gradient_bar(u5h, 49)
    bar_wk  = gradient_bar(uwk, 49)
    pc_ctx  = pct_color(pct)
    pc_5h   = pct_color(u5h)
    pc_wk   = pct_color(uwk)

    # Indicatori visivi stale-while-revalidate (TASK-4b)
    stale_flag  = '\u26a0 ' if (_usage_state == 'stale' and _cache_age > USAGE_TTL * 2) else ''
    uvc         = cGr if _usage_state == 'missing' else ''   # color for N/A values
    ucr         = cR  if _usage_state == 'missing' else ''   # reset after N/A values
    pc_5h_disp  = cGr if _usage_state == 'missing' else pc_5h
    pc_wk_disp  = cGr if _usage_state == 'missing' else pc_wk

    # 10. Currency values
    used_fmt    = fmt_currency(used_credits)
    month_fmt   = fmt_currency(month_limit)
    balance_fmt = _I18N_FMT['na']
    if used_credits is not None and month_limit is not None:
        try:
            balance_fmt = fmt_currency(float(month_limit) - float(used_credits))
        except (TypeError, ValueError):
            pass

    extra_color = cG if extra_usage is True else cOr
    extra_label = 'True' if extra_usage is True else 'False'

    # 11. Output — 6 lines + separators
    # Collect everything into a list and do a single write to minimise
    # system calls (one flush at the end)
    lines: List[str] = [
        f'{cW}ENV:{cR}{cC} {model}{cR} {cGr}({ctx_max_fmt} token){cR}'
        f' | {cW}{_I18N_FMT["effort"]}:{cR} {effort}'
        f' | {ico_folder} {cW}{dir_name}{cR}'
        f' |{branch_str}\n',

        f'{sep}\n',

        f'{cW}CONTEXT_WINDOW{cR}'
        f' | {cW}IN:{cR} {fmt_tokens(tok_in)}'
        f' | {cW}OUT:{cR} {fmt_tokens(tok_out)}'
        f' | {cW}Cached:{cR} {fmt_tokens(tok_cached)}'
        f' | {cW}Total:{cR} {fmt_tokens(tok_total)}\n',

        f'{sep}\n',

        f'{cW}CONTEXT:{cR} {bar_ctx} {pc_ctx}{pct:3d}%{cR}\n',

        f'{sep}\n',

        f'{cW}USAGE 5H:{cR} {bar_5h} {pc_5h_disp}{stale_flag}{u5h:3d}%{cR} | {cY}RST:{cR} {uvc}{r5h}{ucr}\n',

        f'{sep}\n',

        f'{cW}USAGE WK:{cR} {bar_wk} {pc_wk_disp}{stale_flag}{uwk:3d}%{cR} | {cY}RST:{cR} {uvc}{rwk}{ucr}\n',

        f'{sep}\n',

        f'{cW}XTRA USG:{cR} {extra_color}{extra_label}{cR}'
        f' | {cW}USED:{cR} {uvc}{used_fmt}{ucr}'
        f' | {cW}MONTH:{cR} {uvc}{month_fmt}{ucr}'
        f' | {cW}UTIL:{cR} {uvc}{month_util}{ucr}'
        f' | {cW}BALANCE:{cR} {uvc}{balance_fmt}{ucr}\n',

        f'{sep}\n',
    ]
    sys.stdout.write(''.join(lines))
    sys.stdout.flush()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        sys.stdout.write(f"{_I18N_FMT['error']}: execution failed\n")
        sys.stdout.flush()
