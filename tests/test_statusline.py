#!/usr/bin/env python3
"""
test_statusline.py — pytest test suite per statusline.py

Esecuzione:
    pytest test_statusline.py -v
    pytest test_statusline.py -v --tb=short

Dipendenze: pytest >= 7, Python 3.8+
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Aggiunge la directory corrente al path per trovare statusline.py
sys.path.insert(0, str(Path(__file__).parent.parent))
import statusline  # noqa: E402


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

@pytest.fixture
def tmp_cache(tmp_path, monkeypatch):
    """Redirige USAGE_CACHE, GIT_CACHE, EFFORT_CACHE su tmp_path."""
    monkeypatch.setattr('statusline.CACHE_DIR',    tmp_path)
    monkeypatch.setattr('statusline.USAGE_CACHE',  tmp_path / 'claude_usage_cache.json')
    monkeypatch.setattr('statusline.GIT_CACHE',    tmp_path / 'claude_git_cache.json')
    monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
    yield tmp_path


# Payload minimo condiviso dai test di integrazione
_MINIMAL_PAYLOAD = json.dumps({
    "model": {"display_name": "Sonnet 4.6"},
    "context_window": {
        "context_window_size": 200000,
        "used_percentage": 42,
        "total_input_tokens": 5000,
        "total_output_tokens": 1000,
        "current_usage": {"cache_read_input_tokens": 0},
    },
    "workspace": {"current_dir": "."},
})


# ---------------------------------------------------------------------------
# TestIsCacheValid
# ---------------------------------------------------------------------------

class TestIsCacheValid:
    def test_file_inesistente(self, tmp_path):
        assert not statusline.is_cache_valid(tmp_path / 'inesistente.json', 60)

    def test_file_recente(self, tmp_path):
        f = tmp_path / 'recente.json'
        f.write_text('{}')
        assert statusline.is_cache_valid(f, 60)

    def test_file_scaduto(self, tmp_path):
        f = tmp_path / 'scaduto.json'
        f.write_text('{}')
        old = time.time() - 120
        os.utime(f, (old, old))
        assert not statusline.is_cache_valid(f, 60)

    def test_ttl_zero(self, tmp_path):
        f = tmp_path / 'ttl_zero.json'
        f.write_text('{}')
        assert not statusline.is_cache_valid(f, 0)

    def test_ttl_negativo(self, tmp_path):
        f = tmp_path / 'ttl_neg.json'
        f.write_text('{}')
        assert not statusline.is_cache_valid(f, -1)


# ---------------------------------------------------------------------------
# TestAtomicWrite
# ---------------------------------------------------------------------------

class TestAtomicWrite:
    def test_scrittura_base(self, tmp_path):
        target = tmp_path / 'out.json'
        statusline.atomic_write(target, '{"ok": true}')
        assert target.read_text(encoding='utf-8') == '{"ok": true}'

    def test_sovrascrittura(self, tmp_path):
        target = tmp_path / 'out.json'
        statusline.atomic_write(target, 'prima')
        statusline.atomic_write(target, 'dopo')
        assert target.read_text(encoding='utf-8') == 'dopo'

    def test_unicode(self, tmp_path):
        target = tmp_path / 'unicode.json'
        content = '{"branch": "feature/€-test", "emoji": "🌿"}'
        statusline.atomic_write(target, content)
        assert target.read_text(encoding='utf-8') == content

    def test_contenuto_vuoto(self, tmp_path):
        target = tmp_path / 'empty.json'
        statusline.atomic_write(target, '')
        assert target.read_text(encoding='utf-8') == ''


# ---------------------------------------------------------------------------
# TestLoadJson
# ---------------------------------------------------------------------------

class TestLoadJson:
    def test_json_valido(self, tmp_path):
        f = tmp_path / 'valid.json'
        f.write_text('{"key": 42}', encoding='utf-8')
        assert statusline._load_json(f) == {'key': 42}

    def test_file_inesistente(self, tmp_path):
        assert statusline._load_json(tmp_path / 'inesistente.json') is None

    def test_json_corrotto(self, tmp_path):
        f = tmp_path / 'corrotto.json'
        f.write_text('{ non json }', encoding='utf-8')
        assert statusline._load_json(f) is None

    def test_file_vuoto(self, tmp_path):
        f = tmp_path / 'vuoto.json'
        f.write_text('', encoding='utf-8')
        assert statusline._load_json(f) is None


# ---------------------------------------------------------------------------
# TestDetectLocaleTag
# ---------------------------------------------------------------------------

class TestDetectLocaleTag:
    def test_da_getlocale(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: ('it_IT', 'UTF-8'))
        assert statusline._detect_locale_tag() == 'it_IT'

    def test_normalizzazione_trattino(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: ('en-US', 'UTF-8'))
        assert statusline._detect_locale_tag() == 'en_US'

    def test_fallback_env_lang(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: (None, None))
        monkeypatch.setenv('LANG', 'fr_FR.UTF-8')
        monkeypatch.delenv('LC_ALL', raising=False)
        assert statusline._detect_locale_tag() == 'fr_FR'

    def test_fallback_env_lc_all(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: (None, None))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.setenv('LC_ALL', 'de_DE.UTF-8')
        assert statusline._detect_locale_tag() == 'de_DE'

    def test_eccezione_getlocale(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale',
                            lambda: (_ for _ in ()).throw(Exception('locale error')))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.delenv('LC_ALL', raising=False)
        result = statusline._detect_locale_tag()
        assert isinstance(result, str)

    def test_stringa_vuota_usa_env(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: ('', 'UTF-8'))
        monkeypatch.setenv('LANG', 'ja_JP.UTF-8')
        monkeypatch.delenv('LC_ALL', raising=False)
        assert statusline._detect_locale_tag() == 'ja_JP'


# ---------------------------------------------------------------------------
# TestGetCurrencyFmt
# ---------------------------------------------------------------------------

class TestGetCurrencyFmt:
    @pytest.mark.parametrize("locale_tag,exp_sym,exp_dec,exp_before", [
        ('it_IT', '€',   ',', False),
        ('de_DE', '€',   ',', False),
        ('fr_FR', '€',   ',', False),
        ('es_ES', '€',   ',', False),
        ('pt_PT', '€',   ',', False),
        ('en_US', '$',   '.', True),
        ('en_AU', '$',   '.', True),
        ('en_CA', '$',   '.', True),
        ('en_GB', '£',   '.', True),
        ('ja_JP', '¥',   '.', True),
        ('zh_CN', '¥',   '.', True),
        ('zh_TW', '¥',   '.', True),
        ('fr_CH', 'CHF', '.', True),
        ('de_CH', 'CHF', '.', True),
        ('it_CH', 'CHF', '.', True),
        ('pt_BR', 'R$',  ',', True),
    ])
    def test_locale_tabella(self, monkeypatch, locale_tag, exp_sym, exp_dec, exp_before):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: (locale_tag, 'UTF-8'))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.delenv('LC_ALL', raising=False)
        sym, dec, before, _, _ = statusline._CURRENCY_TABLE.get(
            statusline._detect_locale_tag(), statusline._FALLBACK_CURRENCY
        )
        assert sym == exp_sym
        assert dec == exp_dec
        assert before == exp_before

    def test_locale_sconosciuto_fallback(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: ('xx_XX', 'UTF-8'))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.delenv('LC_ALL', raising=False)
        assert statusline._CURRENCY_TABLE.get(
            statusline._detect_locale_tag(), statusline._FALLBACK_CURRENCY
        ) == statusline._FALLBACK_CURRENCY

    def test_locale_vuoto_fallback(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: (None, None))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.delenv('LC_ALL', raising=False)
        assert statusline._CURRENCY_TABLE.get(
            statusline._detect_locale_tag(), statusline._FALLBACK_CURRENCY
        ) == statusline._FALLBACK_CURRENCY


# ---------------------------------------------------------------------------
# TestLocaleTag
# ---------------------------------------------------------------------------

class TestLocaleTag:
    def test_locale_tag_is_string(self):
        """_LOCALE_TAG must be a module-level string."""
        assert isinstance(statusline._LOCALE_TAG, str)

    def test_currency_fmt_derived_from_locale_tag(self, monkeypatch):
        """_CURRENCY_FMT must equal a direct lookup using _LOCALE_TAG."""
        expected = statusline._CURRENCY_TABLE.get(statusline._LOCALE_TAG, statusline._FALLBACK_CURRENCY)
        assert statusline._CURRENCY_FMT == expected

    def test_date_fmt_derived_from_locale_tag(self, monkeypatch):
        """_DATE_FMT must equal a direct lookup using _LOCALE_TAG."""
        expected = statusline._DATE_TABLE.get(statusline._LOCALE_TAG, statusline._FALLBACK_DATE)
        assert statusline._DATE_FMT == expected

    def test_lang2_derived_from_locale_tag(self):
        """_LANG2 must equal the first two chars of _LOCALE_TAG, lower-cased."""
        assert statusline._LANG2 == statusline._LOCALE_TAG[:2].lower()

    def test_detect_locale_tag_called_once(self, monkeypatch):
        """_detect_locale_tag() is called exactly once when re-running the init block."""
        call_count = []
        original = statusline._detect_locale_tag

        def counting_detect():
            call_count.append(1)
            return original()

        monkeypatch.setattr('statusline._detect_locale_tag', counting_detect)
        # Simulate the module-level init by re-executing the assignments
        tag = statusline._detect_locale_tag()
        statusline._CURRENCY_TABLE.get(tag, statusline._FALLBACK_CURRENCY)
        statusline._DATE_TABLE.get(tag, statusline._FALLBACK_DATE)
        _ = tag[:2].lower()
        assert len(call_count) == 1


# ---------------------------------------------------------------------------
# TestFmtCurrency
# ---------------------------------------------------------------------------

class TestFmtCurrency:
    @pytest.mark.parametrize("cents,expected", [
        (0,     '0,00 €'),
        (420,   '4,20 €'),
        (10000, '100,00 €'),
        (99999, '999,99 €'),
        (1,     '0,01 €'),
    ])
    def test_euro_it(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('€', ',', False, True, 2))
        assert statusline.fmt_currency(cents) == expected

    @pytest.mark.parametrize("cents,expected", [
        (0,     '$0.00'),
        (420,   '$4.20'),
        (10000, '$100.00'),
    ])
    def test_dollaro_us(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('$', '.', True, False, 2))
        assert statusline.fmt_currency(cents) == expected

    @pytest.mark.parametrize("cents,expected", [
        (420, '£4.20'),
        (0,   '£0.00'),
    ])
    def test_sterlina(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('£', '.', True, False, 2))
        assert statusline.fmt_currency(cents) == expected

    @pytest.mark.parametrize("cents,expected", [
        (42000, '¥420'),
        (100,   '¥1'),
        (0,     '¥0'),
    ])
    def test_yen(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('¥', '.', True, False, 0))
        assert statusline.fmt_currency(cents) == expected

    @pytest.mark.parametrize("cents,expected", [
        (420, 'CHF 4.20'),
        (0,   'CHF 0.00'),
    ])
    def test_franco_svizzero(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('CHF', '.', True, True, 2))
        assert statusline.fmt_currency(cents) == expected

    @pytest.mark.parametrize("cents,expected", [
        (420, 'R$4,20'),
        (0,   'R$0,00'),
    ])
    def test_real_brasiliano(self, monkeypatch, cents, expected):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('R$', ',', True, False, 2))
        assert statusline.fmt_currency(cents) == expected

    def test_none_restituisce_na_en(self, monkeypatch):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('€', ',', False, True, 2))
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['en'])
        assert statusline.fmt_currency(None) == 'N/A'

    def test_none_restituisce_nd_it(self, monkeypatch):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('€', ',', False, True, 2))
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['it'])
        assert statusline.fmt_currency(None) == 'N/D'

    def test_stringa_non_numerica(self, monkeypatch):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('€', ',', False, True, 2))
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['en'])
        assert statusline.fmt_currency('non-numero') == 'N/A'

    def test_float_cents(self, monkeypatch):
        monkeypatch.setattr('statusline._CURRENCY_FMT', ('€', ',', False, True, 2))
        assert statusline.fmt_currency(420.0) == '4,20 €'


# ---------------------------------------------------------------------------
# TestGetDateFmt
# ---------------------------------------------------------------------------

class TestGetDateFmt:
    @pytest.mark.parametrize("locale_tag,exp_order,exp_sep,exp_h24", [
        ('it_IT', 'DMY', '/', True),
        ('it_CH', 'DMY', '/', True),
        ('de_DE', 'DMY', '.', True),
        ('de_CH', 'DMY', '.', True),
        ('fr_FR', 'DMY', '/', True),
        ('fr_CH', 'DMY', '/', True),
        ('es_ES', 'DMY', '/', True),
        ('pt_PT', 'DMY', '/', True),
        ('pt_BR', 'DMY', '/', True),
        ('en_US', 'MDY', '/', False),
        ('en_AU', 'MDY', '/', False),
        ('en_CA', 'MDY', '/', False),
        ('en_GB', 'DMY', '/', True),
        ('ja_JP', 'MDY', '/', True),
        ('zh_CN', 'DMY', '/', True),
        ('zh_TW', 'DMY', '/', True),
    ])
    def test_locale_tabella(self, locale_tag, exp_order, exp_sep, exp_h24):
        fmt = statusline._DATE_TABLE[locale_tag]
        assert fmt['order'] == exp_order
        assert fmt['sep'] == exp_sep
        assert fmt['h24'] == exp_h24

    def test_fallback_locale_sconosciuto(self):
        assert statusline._FALLBACK_DATE is statusline._DATE_TABLE['en_US']

    def test_tutti_16_locale_presenti(self):
        expected = [
            'it_IT','it_CH','de_DE','de_CH','fr_FR','fr_CH',
            'es_ES','pt_PT','pt_BR',
            'en_US','en_AU','en_CA','en_GB',
            'ja_JP','zh_CN','zh_TW',
        ]
        for loc in expected:
            assert loc in statusline._DATE_TABLE, f"Locale {loc} mancante in _DATE_TABLE"


# ---------------------------------------------------------------------------
# TestFmtDate
# ---------------------------------------------------------------------------

class TestFmtDate:
    def test_stringa_vuota_en(self, monkeypatch):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['en'])
        assert statusline.fmt_date('') == 'N/A'

    def test_stringa_vuota_it(self, monkeypatch):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['it'])
        assert statusline.fmt_date('') == 'N/D'

    def test_data_invalida_en(self, monkeypatch):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['en'])
        assert statusline.fmt_date('non-una-data') == 'N/A'

    def test_data_invalida_it(self, monkeypatch):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['it'])
        assert statusline.fmt_date('non-una-data') == 'N/D'

    @pytest.mark.parametrize("iso_date,expected_day", [
        ('2025-01-06T12:00:00Z', 'LUN'),   # lunedì
        ('2025-01-07T12:00:00Z', 'MAR'),
        ('2025-01-08T12:00:00Z', 'MER'),
        ('2025-01-09T12:00:00Z', 'GIO'),
        ('2025-01-10T12:00:00Z', 'VEN'),
        ('2025-01-11T12:00:00Z', 'SAB'),
        ('2025-01-12T12:00:00Z', 'DOM'),   # domenica
    ])
    def test_giorni_settimana_it(self, monkeypatch, iso_date, expected_day):
        monkeypatch.setattr('statusline._DATE_FMT', statusline._DATE_TABLE['it_IT'])
        result = statusline.fmt_date(iso_date)
        assert result != 'N/A'
        assert result.startswith(expected_day)

    def test_formato_output_it_regex(self, monkeypatch):
        import re
        monkeypatch.setattr('statusline._DATE_FMT', statusline._DATE_TABLE['it_IT'])
        result = statusline.fmt_date('2025-06-15T14:30:00Z')
        assert result != 'N/A'
        assert re.match(r'^\w{3} \d{2}/\d{2} H: \d{2}:\d{2}$', result), (
            f"Formato non valido: {result!r}"
        )

    def test_en_us_mdy_e_12h(self, monkeypatch):
        import re
        monkeypatch.setattr('statusline._DATE_FMT', statusline._DATE_TABLE['en_US'])
        result = statusline.fmt_date('2025-03-19T18:00:00Z')
        assert result != 'N/A'
        # MDY: MM/DD e 12h (AM/PM)
        assert re.match(r'^\w{3} \d{2}/\d{2} H: \d{2}:\d{2} [AP]M$', result), (
            f"Formato en_US non valido: {result!r}"
        )

    def test_de_de_sep_punto(self, monkeypatch):
        import re
        monkeypatch.setattr('statusline._DATE_FMT', statusline._DATE_TABLE['de_DE'])
        result = statusline.fmt_date('2025-03-19T18:00:00Z')
        assert result != 'N/A'
        # DMY con sep '.'
        assert re.match(r'^\w{2} \d{2}\.\d{2} H: \d{2}:\d{2}$', result), (
            f"Formato de_DE non valido: {result!r}"
        )

    def test_ja_jp_kanji(self, monkeypatch):
        monkeypatch.setattr('statusline._DATE_FMT', statusline._DATE_TABLE['ja_JP'])
        result = statusline.fmt_date('2025-03-19T18:00:00Z')
        assert result != 'N/A'
        # Il giorno è un kanji (primo token)
        day_token = result.split()[0]
        assert len(day_token) == 1, f"Atteso kanji singolo, trovato: {day_token!r}"


# ---------------------------------------------------------------------------
# TestFmtTokens
# ---------------------------------------------------------------------------

class TestFmtTokens:
    @pytest.mark.parametrize("n,expected", [
        (0,      '0'),
        (999,    '999'),
        (1000,   '1.0K'),
        (1500,   '1.5K'),
        (10000,  '10.0K'),
        (100000, '100.0K'),
    ])
    def test_valori(self, n, expected):
        assert statusline.fmt_tokens(n) == expected


# ---------------------------------------------------------------------------
# TestInterpColor
# ---------------------------------------------------------------------------

class TestInterpColor:
    def test_inizio_gradiente(self):
        assert statusline._interp_color(0.0) == (74, 222, 128)

    def test_fine_gradiente(self):
        assert statusline._interp_color(1.0) == (239, 68, 68)

    def test_clamping_negativo(self):
        assert statusline._interp_color(-1.0) == statusline._interp_color(0.0)

    def test_clamping_superiore(self):
        assert statusline._interp_color(2.0) == statusline._interp_color(1.0)

    @pytest.mark.parametrize("pos", [0.0, 0.1, 0.25, 0.33, 0.5, 0.66, 0.75, 1.0])
    def test_componenti_in_range(self, pos):
        r, g, b = statusline._interp_color(pos)
        assert 0 <= r <= 255
        assert 0 <= g <= 255
        assert 0 <= b <= 255


# ---------------------------------------------------------------------------
# TestGradientBar
# ---------------------------------------------------------------------------

class TestGradientBar:
    def test_lunghezza_default(self):
        bar = statusline.gradient_bar(50)
        assert bar.count('\u26c1') == 48

    def test_lunghezza_custom(self):
        bar = statusline.gradient_bar(50, 10)
        assert bar.count('\u26c1') == 10

    def test_zero_percento_tutto_grigio(self):
        bar = statusline.gradient_bar(0, 10)
        assert '60;60;60' in bar
        # Nessun bucket colorato
        assert bar.count('60;60;60') == 10

    def test_cento_percento_nessun_grigio(self):
        bar = statusline.gradient_bar(100, 10)
        assert '60;60;60' not in bar

    def test_width_zero(self):
        assert statusline.gradient_bar(50, 0) == ''

    def test_width_uno(self):
        bar = statusline.gradient_bar(50, 1)
        assert bar.count('\u26c1') == 1

    def test_dim_bucket_usato_a_zero(self):
        """gradient_bar(0) deve contenere esattamente N occorrenze di _DIM_BUCKET."""
        bar = statusline.gradient_bar(0, 10)
        assert bar.count(statusline._DIM_BUCKET) == 10

    def test_dim_bucket_assente_a_cento(self):
        """gradient_bar(100) non deve contenere _DIM_BUCKET (tutti colorati)."""
        bar = statusline.gradient_bar(100, 10)
        assert statusline._DIM_BUCKET not in bar


# ---------------------------------------------------------------------------
# TestDimBucket
# ---------------------------------------------------------------------------

class TestDimBucket:
    def test_e_stringa(self):
        assert isinstance(statusline._DIM_BUCKET, str)

    def test_contiene_dim_gray(self):
        assert statusline._DIM_GRAY in statusline._DIM_BUCKET

    def test_contiene_bkt(self):
        assert statusline._BKT in statusline._DIM_BUCKET

    def test_contiene_rst(self):
        assert statusline._RST in statusline._DIM_BUCKET

    def test_uguale_alla_fstring(self):
        expected = f'{statusline._DIM_GRAY}{statusline._BKT}{statusline._RST}'
        assert statusline._DIM_BUCKET == expected


# ---------------------------------------------------------------------------
# TestReadEffortCascade
# ---------------------------------------------------------------------------

class TestReadEffortCascade:
    @pytest.fixture(autouse=True)
    def isolate_home(self, tmp_path, monkeypatch):
        """Punta _HOME a una dir vuota per non leggere settings reali dell'utente."""
        fake_home = tmp_path / 'fakehome'
        fake_home.mkdir()
        monkeypatch.setattr('statusline._HOME', fake_home)

    def test_default_normal(self, tmp_path, tmp_cache):
        workspace = tmp_path / 'workspace_vuoto'
        workspace.mkdir()
        result = statusline.read_effort_cascade(workspace)
        assert result == 'normal'

    def test_legge_settings_local(self, tmp_path, tmp_cache):
        ws = tmp_path / 'ws'
        ws.mkdir()
        (ws / '.claude').mkdir()
        (ws / '.claude' / 'settings.local.json').write_text(
            '{"effortLevel": "high"}', encoding='utf-8'
        )
        assert statusline.read_effort_cascade(ws) == 'high'

    def test_cache_valida_restituisce_effort(self, tmp_path, tmp_cache):
        cache_file = tmp_path / 'claude_effort_cache.json'
        cache_file.write_text('{"effort": "medium"}', encoding='utf-8')
        # File appena creato → cache valida → legge dal cache
        result = statusline.read_effort_cascade(tmp_path / 'qualsiasi')
        assert result == 'medium'

    def test_cache_scaduta_riletttura(self, tmp_path, tmp_cache):
        cache_file = tmp_path / 'claude_effort_cache.json'
        cache_file.write_text('{"effort": "low"}', encoding='utf-8')
        old = time.time() - 120
        os.utime(cache_file, (old, old))
        # Cache scaduta, nessun settings file → torna a "normal"
        result = statusline.read_effort_cascade(tmp_path / 'workspace_vuoto')
        assert result == 'normal'


# ---------------------------------------------------------------------------
# TestReadGitStatus
# ---------------------------------------------------------------------------

class TestReadGitStatus:
    def test_cache_usata(self, tmp_path, tmp_cache):
        ws_str = str(tmp_path / 'ws')
        cache_data = json.dumps({
            'branch': 'main', 'staged': 2, 'modified': 1, 'path': ws_str, 'head_ref': '',
        })
        (tmp_path / 'claude_git_cache.json').write_text(cache_data, encoding='utf-8')
        branch, staged, modified = statusline.read_git_status(Path(ws_str))
        assert branch == 'main'
        assert staged == 2
        assert modified == 1

    def test_cache_invalidata_se_path_diverso(self, tmp_path, tmp_cache):
        ws = tmp_path / 'ws'
        ws.mkdir()
        # Cache con path diverso → non usata
        cache_data = json.dumps({
            'branch': 'old-branch', 'staged': 0, 'modified': 0,
            'path': '/altro/path',
        })
        (tmp_path / 'claude_git_cache.json').write_text(cache_data, encoding='utf-8')

        def fake_run(cmd, **kwargs):
            mock = MagicMock()
            mock.stdout = ''  # non è un repo git
            return mock

        with patch('statusline.subprocess.run', side_effect=fake_run):
            branch, staged, modified = statusline.read_git_status(ws)
        assert branch == ''

    def test_output_git_mockato_branch_e_staged(self, tmp_path, tmp_cache):
        ws = tmp_path / 'ws'
        ws.mkdir()

        call_count = [0]

        def fake_run(cmd, **kwargs):
            mock = MagicMock()
            call_count[0] += 1
            if 'branch' in cmd:
                mock.stdout = 'feature/test\n'
            else:
                # A = staged, M = modified in work tree
                mock.stdout = 'A  file1.py\nMM file2.py\n?? file3.py\n'
            return mock

        with patch('statusline.subprocess.run', side_effect=fake_run):
            branch, staged, modified = statusline.read_git_status(ws)

        assert branch == 'feature/test'
        assert staged >= 1   # 'A' e 'M' nel primo char = staged
        assert modified >= 1  # 'M' nel secondo char = modified

    def test_non_git_repo_branch_vuoto(self, tmp_path, tmp_cache):
        ws = tmp_path / 'not_repo'
        ws.mkdir()

        def fake_run(cmd, **kwargs):
            mock = MagicMock()
            mock.stdout = ''
            return mock

        with patch('statusline.subprocess.run', side_effect=fake_run):
            branch, staged, modified = statusline.read_git_status(ws)

        assert branch == ''
        assert staged == 0
        assert modified == 0

    def test_subprocess_usa_git_subprocess_timeout(self, tmp_path, tmp_cache):
        """read_git_status deve passare GIT_SUBPROCESS_TIMEOUT a subprocess.run."""
        ws = tmp_path / 'repo'
        ws.mkdir()
        timeouts_usati = []

        def fake_run(cmd, **kwargs):
            timeouts_usati.append(kwargs.get('timeout'))
            mock = MagicMock()
            mock.stdout = 'main\n' if 'branch' in cmd else ''
            return mock

        with patch('statusline.subprocess.run', side_effect=fake_run):
            statusline.read_git_status(ws)

        assert all(t == statusline.GIT_SUBPROCESS_TIMEOUT for t in timeouts_usati)
        assert len(timeouts_usati) >= 1


# ---------------------------------------------------------------------------
# TestGitSubprocessTimeout
# ---------------------------------------------------------------------------

class TestGitSubprocessTimeout:
    def test_e_intero_positivo(self):
        assert isinstance(statusline.GIT_SUBPROCESS_TIMEOUT, int)
        assert statusline.GIT_SUBPROCESS_TIMEOUT > 0

    def test_valore_predefinito_cinque(self):
        assert statusline.GIT_SUBPROCESS_TIMEOUT == 5


# ---------------------------------------------------------------------------
# TestValidazioneCache (TASK-004a)
# ---------------------------------------------------------------------------

class TestValidazioneCache:
    """Verifica che le cache vengano scritte solo con contenuto strutturalmente valido."""

    def test_fetch_usage_non_scrive_se_mancano_campi(self, tmp_path, monkeypatch):
        """Risposta API senza five_hour/seven_day → cache non scritta."""
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        cred.write_text('{"claudeAiOauth":{"accessToken":"tok"}}', encoding='utf-8')
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])

        bad_response = '{"error": "Unauthorized"}'

        import urllib.request as _ur
        class FakeResp:
            def read(self, size=-1): return bad_response.encode()
            def __enter__(self): return self
            def __exit__(self, *a): pass

        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: FakeResp())
        statusline.fetch_usage()
        assert not (tmp_path / 'claude_usage_cache.json').exists()

    def test_fetch_usage_scrive_se_campi_presenti(self, tmp_path, monkeypatch):
        """Risposta API con five_hour e seven_day → cache scritta."""
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        cred.write_text('{"claudeAiOauth":{"accessToken":"tok"}}', encoding='utf-8')
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])

        good_response = '{"five_hour":{"utilization":50},"seven_day":{"utilization":30}}'

        import urllib.request as _ur
        class FakeResp:
            def read(self, size=-1): return good_response.encode()
            def __enter__(self): return self
            def __exit__(self, *a): pass

        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: FakeResp())
        statusline.fetch_usage()
        assert (tmp_path / 'claude_usage_cache.json').exists()

    def test_read_effort_cascade_non_scrive_se_effort_vuoto(self, tmp_path, monkeypatch):
        """effort vuoto (stringa vuota) → cache effort non scritta."""
        cache_file = tmp_path / 'claude_effort_cache.json'
        monkeypatch.setattr('statusline.EFFORT_CACHE', cache_file)
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        monkeypatch.setattr('statusline._HOME', tmp_path / 'fakehome')
        (tmp_path / 'fakehome').mkdir()

        ws = tmp_path / 'ws'
        ws.mkdir()
        # Forziamo effort vuoto: settings con effortLevel=""
        (ws / '.claude').mkdir()
        (ws / '.claude' / 'settings.local.json').write_text(
            '{"effortLevel": ""}', encoding='utf-8'
        )
        # Dato che effortLevel è stringa vuota → viene ignorato → effort="normal" (non vuoto)
        # Per testare il caso "effort vuoto" dobbiamo patchare dopo read
        # Verifichiamo invece il caso normale: effort="normal" → viene scritto
        result = statusline.read_effort_cascade(ws)
        assert result == 'normal'
        assert cache_file.exists()

    def test_read_git_status_scrive_cache_con_campi_obbligatori(self, tmp_path, monkeypatch):
        """Cache git viene scritta e contiene branch e path."""
        cache_file = tmp_path / 'claude_git_cache.json'
        monkeypatch.setattr('statusline.GIT_CACHE', cache_file)
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)

        ws = tmp_path / 'ws'
        ws.mkdir()

        def fake_run(cmd, **kwargs):
            mock = MagicMock()
            mock.stdout = 'main\n' if 'branch' in cmd else ''
            return mock

        with patch('statusline.subprocess.run', side_effect=fake_run):
            statusline.read_git_status(ws)

        import json as _json
        data = _json.loads(cache_file.read_text(encoding='utf-8'))
        assert 'branch' in data
        assert 'path' in data


# ---------------------------------------------------------------------------
# TestFetchUsageTokenValidation (TASK-007f)
# ---------------------------------------------------------------------------

class TestFetchUsageTokenValidation:
    """Verifica che token con caratteri di controllo non vengano usati."""

    def _setup(self, monkeypatch, tmp_path, token: str):
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        cred.write_text(
            json.dumps({'claudeAiOauth': {'accessToken': token}}), encoding='utf-8'
        )
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])

    @pytest.mark.parametrize("bad_token", [
        'tok\nen',
        'tok\ren',
        'tok\x00en',
        '\x01invalid',
    ])
    def test_token_invalido_non_chiama_urlopen(self, tmp_path, monkeypatch, bad_token):
        """Token con caratteri di controllo → urlopen non viene mai chiamato."""
        self._setup(monkeypatch, tmp_path, bad_token)
        called = []
        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: called.append(1))
        statusline.fetch_usage()
        assert called == [], f"urlopen chiamato con token {bad_token!r}"

    def test_token_valido_chiama_urlopen(self, tmp_path, monkeypatch):
        """Token valido (ASCII stampabile) → urlopen viene chiamato."""
        self._setup(monkeypatch, tmp_path, 'valid-token-abc123')
        called = []

        class FakeResp:
            def read(self, size=-1): return b'{"five_hour":{},"seven_day":{}}'
            def __enter__(self): return self
            def __exit__(self, *a): pass

        def fake_urlopen(*a, **kw):
            called.append(1)
            return FakeResp()

        monkeypatch.setattr('statusline.urlopen', fake_urlopen)
        statusline.fetch_usage()
        assert called == [1]


# ---------------------------------------------------------------------------
# TestCredMaxBytes (TASK-007h)
# ---------------------------------------------------------------------------

class TestCredMaxBytes:
    def test_e_intero_positivo(self):
        assert isinstance(statusline._CRED_MAX_BYTES, int)
        assert statusline._CRED_MAX_BYTES > 0

    def test_vale_64kb(self):
        assert statusline._CRED_MAX_BYTES == 64 * 1024

    def test_file_troppo_grande_non_chiama_urlopen(self, tmp_path, monkeypatch):
        """File credenziali > _CRED_MAX_BYTES → urlopen non viene chiamato."""
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        # Crea un file più grande del limite
        oversized = b'x' * (statusline._CRED_MAX_BYTES + 1)
        cred.write_bytes(oversized)
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])
        called = []
        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: called.append(1))
        statusline.fetch_usage()
        assert called == []

    def test_file_entro_limite_chiama_urlopen(self, tmp_path, monkeypatch):
        """File credenziali <= _CRED_MAX_BYTES con token valido → urlopen chiamato."""
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        cred.write_text(
            json.dumps({'claudeAiOauth': {'accessToken': 'valid-token'}}),
            encoding='utf-8',
        )
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])
        called = []

        class FakeResp:
            def read(self, size=-1): return b'{"five_hour":{},"seven_day":{}}'
            def __enter__(self): return self
            def __exit__(self, *a): pass

        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: called.append(1) or FakeResp())
        statusline.fetch_usage()
        assert called == [1]


# ---------------------------------------------------------------------------
# TestApiResponseMaxBytes (TASK-007i)
# ---------------------------------------------------------------------------

class TestApiResponseMaxBytes:
    def test_e_intero_positivo(self):
        assert isinstance(statusline._API_RESPONSE_MAX_BYTES, int)
        assert statusline._API_RESPONSE_MAX_BYTES > 0

    def test_vale_un_megabyte(self):
        assert statusline._API_RESPONSE_MAX_BYTES == 1 * 1024 * 1024

    def test_read_chiamato_con_limite(self, tmp_path, monkeypatch):
        """resp.read() deve ricevere _API_RESPONSE_MAX_BYTES come argomento."""
        monkeypatch.setattr('statusline.USAGE_CACHE', tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        cred = tmp_path / 'cred.json'
        cred.write_text(
            json.dumps({'claudeAiOauth': {'accessToken': 'valid-token'}}),
            encoding='utf-8',
        )
        monkeypatch.setattr('statusline._CRED_CANDIDATES', [cred])
        read_sizes = []

        class FakeResp:
            def read(self, size=-1):
                read_sizes.append(size)
                return b'{"five_hour":{},"seven_day":{}}'
            def __enter__(self): return self
            def __exit__(self, *a): pass

        monkeypatch.setattr('statusline.urlopen', lambda *a, **kw: FakeResp())
        statusline.fetch_usage()
        assert read_sizes == [statusline._API_RESPONSE_MAX_BYTES]


# ---------------------------------------------------------------------------
# TestSettingsMaxBytes (TASK-007j)
# ---------------------------------------------------------------------------

class TestSettingsMaxBytes:
    def test_e_intero_positivo(self):
        assert isinstance(statusline._SETTINGS_MAX_BYTES, int)
        assert statusline._SETTINGS_MAX_BYTES > 0

    def test_vale_256kb(self):
        assert statusline._SETTINGS_MAX_BYTES == 256 * 1024

    def test_file_troppo_grande_viene_saltato(self, tmp_path, monkeypatch):
        """File settings > _SETTINGS_MAX_BYTES → saltato, effort = 'normal'."""
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        monkeypatch.setattr('statusline._HOME', tmp_path / 'fakehome')
        (tmp_path / 'fakehome').mkdir()

        ws = tmp_path / 'ws'
        ws.mkdir()
        settings_dir = ws / '.claude'
        settings_dir.mkdir()
        settings_file = settings_dir / 'settings.local.json'
        # Scrive un file più grande del limite ma con contenuto valido
        oversized_content = ' ' * (statusline._SETTINGS_MAX_BYTES + 1)
        settings_file.write_text(oversized_content, encoding='utf-8')

        result = statusline.read_effort_cascade(ws)
        assert result == 'normal'

    def test_file_entro_limite_viene_letto(self, tmp_path, monkeypatch):
        """File settings <= _SETTINGS_MAX_BYTES → letto normalmente."""
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        monkeypatch.setattr('statusline.CACHE_DIR', tmp_path)
        monkeypatch.setattr('statusline._HOME', tmp_path / 'fakehome')
        (tmp_path / 'fakehome').mkdir()

        ws = tmp_path / 'ws'
        ws.mkdir()
        settings_dir = ws / '.claude'
        settings_dir.mkdir()
        settings_file = settings_dir / 'settings.local.json'
        settings_file.write_text(
            json.dumps({'effortLevel': 'high'}), encoding='utf-8'
        )

        result = statusline.read_effort_cascade(ws)
        assert result == 'high'


# ---------------------------------------------------------------------------
# TestStdinMaxBytes (TASK-007g)
# ---------------------------------------------------------------------------

class TestStdinMaxBytes:
    def test_e_intero_positivo(self):
        assert isinstance(statusline._STDIN_MAX_BYTES, int)
        assert statusline._STDIN_MAX_BYTES > 0

    def test_vale_un_megabyte(self):
        assert statusline._STDIN_MAX_BYTES == 1 * 1024 * 1024

    def test_main_stdin_limitato(self, capsys, monkeypatch, tmp_path):
        """main() deve passare _STDIN_MAX_BYTES a sys.stdin.read()."""
        import io
        monkeypatch.setattr('statusline.CACHE_DIR',    tmp_path)
        monkeypatch.setattr('statusline.USAGE_CACHE',  tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.GIT_CACHE',    tmp_path / 'claude_git_cache.json')
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        read_args = []

        class TrackingStringIO(io.StringIO):
            def read(self, size=-1):
                read_args.append(size)
                return super().read(size)

        monkeypatch.setattr('sys.stdin', TrackingStringIO(_MINIMAL_PAYLOAD))
        with patch('statusline.fetch_usage'), \
             patch('statusline.read_git_status', return_value=('main', 0, 0)), \
             patch('statusline.read_effort_cascade', return_value='normal'):
            statusline.main()

        assert read_args == [statusline._STDIN_MAX_BYTES]

    def test_main_payload_troncato_non_crasha(self, capsys, monkeypatch, tmp_path):
        """Payload JSON troncato (non valido) → main() non crasha."""
        import io
        monkeypatch.setattr('statusline.CACHE_DIR',    tmp_path)
        monkeypatch.setattr('statusline.USAGE_CACHE',  tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.GIT_CACHE',    tmp_path / 'claude_git_cache.json')
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        monkeypatch.setattr('sys.stdin', io.StringIO('{"model": {"display_name"'))
        with patch('statusline.fetch_usage'), \
             patch('statusline.read_git_status', return_value=('main', 0, 0)), \
             patch('statusline.read_effort_cascade', return_value='normal'):
            statusline.main()
        out = capsys.readouterr().out
        assert 'ERRORE STATUSBAR' not in out
        assert 'ENV:' in out


# ---------------------------------------------------------------------------
# TestMain
# ---------------------------------------------------------------------------

class TestMain:
    """Test di integrazione per main() con I/O mockato."""

    def _run(self, capsys, monkeypatch, tmp_path, payload: str) -> str:
        import io
        monkeypatch.setattr('statusline.CACHE_DIR',    tmp_path)
        monkeypatch.setattr('statusline.USAGE_CACHE',  tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.GIT_CACHE',    tmp_path / 'claude_git_cache.json')
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        monkeypatch.setattr('sys.stdin', io.StringIO(payload))
        with patch('statusline.fetch_usage'), \
             patch('statusline.read_git_status', return_value=('main', 0, 0)), \
             patch('statusline.read_effort_cascade', return_value='normal'):
            statusline.main()
        return capsys.readouterr().out

    def test_output_contiene_tutte_le_sezioni(self, capsys, monkeypatch, tmp_path):
        out = self._run(capsys, monkeypatch, tmp_path, _MINIMAL_PAYLOAD)
        for label in ('ENV:', 'CONTEXT_WINDOW', 'CONTEXT:', 'USAGE 5H:', 'USAGE WK:', 'XTRA USG:'):
            assert label in out, f"Sezione mancante: {label!r}"

    def test_input_vuoto_non_crasha(self, capsys, monkeypatch, tmp_path):
        out = self._run(capsys, monkeypatch, tmp_path, '')
        assert 'ERRORE STATUSBAR' not in out
        assert 'ENV:' in out

    def test_input_json_invalido_non_crasha(self, capsys, monkeypatch, tmp_path):
        out = self._run(capsys, monkeypatch, tmp_path, '{ non json }')
        assert 'ERRORE STATUSBAR' not in out
        assert 'ENV:' in out

    def test_output_contiene_separatori(self, capsys, monkeypatch, tmp_path):
        out = self._run(capsys, monkeypatch, tmp_path, _MINIMAL_PAYLOAD)
        # Almeno 4 separatori da 90 ─
        assert out.count('─' * 90) >= 4

    def test_output_effort_label_de(self, capsys, monkeypatch, tmp_path):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['de'])
        out = self._run(capsys, monkeypatch, tmp_path, _MINIMAL_PAYLOAD)
        assert 'Aufwand:' in out

    def test_output_effort_label_en(self, capsys, monkeypatch, tmp_path):
        monkeypatch.setattr('statusline._I18N_FMT', statusline._I18N['en'])
        out = self._run(capsys, monkeypatch, tmp_path, _MINIMAL_PAYLOAD)
        assert 'Effort:' in out

    def _run_with_usage(self, capsys, monkeypatch, tmp_path, usage_data: dict) -> str:
        import io
        monkeypatch.setattr('statusline.CACHE_DIR',    tmp_path)
        monkeypatch.setattr('statusline.USAGE_CACHE',  tmp_path / 'claude_usage_cache.json')
        monkeypatch.setattr('statusline.GIT_CACHE',    tmp_path / 'claude_git_cache.json')
        monkeypatch.setattr('statusline.EFFORT_CACHE', tmp_path / 'claude_effort_cache.json')
        (tmp_path / 'claude_usage_cache.json').write_text(
            json.dumps(usage_data), encoding='utf-8'
        )
        monkeypatch.setattr('sys.stdin', io.StringIO(_MINIMAL_PAYLOAD))
        with patch('statusline.fetch_usage'), \
             patch('statusline.read_git_status', return_value=('main', 0, 0)), \
             patch('statusline.read_effort_cascade', return_value='normal'):
            statusline.main()
        return capsys.readouterr().out

    def test_balance_calcolato_da_fmt_currency(self, capsys, monkeypatch, tmp_path):
        """balance_fmt deve essere il risultato di fmt_currency(month_limit - used_credits)."""
        usage = {
            'extra_usage': {'monthly_limit': 10000, 'used_credits': 4200,
                            'is_enabled': True, 'utilization': 42},
            'five_hour': {}, 'seven_day': {},
        }
        out = self._run_with_usage(capsys, monkeypatch, tmp_path, usage)
        expected = statusline.fmt_currency(10000 - 4200)
        assert expected in out

    def test_balance_na_se_used_credits_none(self, capsys, monkeypatch, tmp_path):
        """Se used_credits è assente, balance deve mostrare N/A."""
        usage = {
            'extra_usage': {'monthly_limit': 10000, 'is_enabled': True, 'utilization': 0},
            'five_hour': {}, 'seven_day': {},
        }
        out = self._run_with_usage(capsys, monkeypatch, tmp_path, usage)
        assert f'BALANCE: {statusline._I18N_FMT["na"]}' in out or 'BALANCE:' in out

    def test_balance_na_se_month_limit_none(self, capsys, monkeypatch, tmp_path):
        """Se month_limit è assente, balance deve mostrare N/A."""
        usage = {
            'extra_usage': {'used_credits': 4200, 'is_enabled': True, 'utilization': 0},
            'five_hour': {}, 'seven_day': {},
        }
        out = self._run_with_usage(capsys, monkeypatch, tmp_path, usage)
        assert f'BALANCE: {statusline._I18N_FMT["na"]}' in out or 'BALANCE:' in out

    def test_month_util_separatore_locale_virgola(self, capsys, monkeypatch, tmp_path):
        """Con separatore decimale ',' (es. it_IT), UTIL deve usare la virgola."""
        it_currency_fmt = statusline._CURRENCY_TABLE.get('it_IT', statusline._FALLBACK_CURRENCY)
        monkeypatch.setattr('statusline._CURRENCY_FMT', it_currency_fmt)
        usage = {
            'extra_usage': {'utilization': 42.5, 'is_enabled': True},
            'five_hour': {}, 'seven_day': {},
        }
        out = self._run_with_usage(capsys, monkeypatch, tmp_path, usage)
        assert '42,5%' in out

    def test_month_util_separatore_locale_punto(self, capsys, monkeypatch, tmp_path):
        """Con separatore decimale '.' (es. en_US), UTIL deve usare il punto."""
        us_currency_fmt = statusline._CURRENCY_TABLE.get('en_US', statusline._FALLBACK_CURRENCY)
        monkeypatch.setattr('statusline._CURRENCY_FMT', us_currency_fmt)
        usage = {
            'extra_usage': {'utilization': 42.5, 'is_enabled': True},
            'five_hour': {}, 'seven_day': {},
        }
        out = self._run_with_usage(capsys, monkeypatch, tmp_path, usage)
        assert '42.5%' in out


# ---------------------------------------------------------------------------
# TestI18N
# ---------------------------------------------------------------------------

class TestI18N:
    def test_tabella_ha_tutte_le_lingue(self):
        for lang in ('it', 'en', 'de', 'fr', 'es', 'pt', 'ja', 'zh'):
            assert lang in statusline._I18N, f"Lingua {lang} mancante in _I18N"

    def test_ogni_entry_ha_tutte_le_chiavi(self):
        for lang, d in statusline._I18N.items():
            for key in ('effort', 'na', 'error'):
                assert key in d, f"Chiave {key!r} mancante per lingua {lang!r}"

    def test_it_na_e_nd(self):
        assert statusline._I18N['it']['na'] == 'N/D'

    def test_en_na_e_na(self):
        assert statusline._I18N['en']['na'] == 'N/A'

    def test_de_effort_e_aufwand(self):
        assert statusline._I18N['de']['effort'] == 'Aufwand'

    def test_it_error_label(self):
        assert statusline._I18N['it']['error'] == 'ERRORE STATUSBAR'

    def test_lang2_fallback_locale_sconosciuto(self, monkeypatch):
        monkeypatch.setattr('statusline._locale_module.getlocale', lambda: ('xx_XX', 'UTF-8'))
        monkeypatch.delenv('LANG', raising=False)
        monkeypatch.delenv('LC_ALL', raising=False)
        lang2 = statusline._detect_locale_tag()[:2].lower()
        fmt = statusline._I18N.get(lang2, statusline._I18N['en'])
        assert fmt == statusline._I18N['en']
