import os
import tempfile
import unittest
from datetime import datetime, timedelta, date
from unittest.mock import patch

import src.work_timer as work_timer


class TestEdgeCases(unittest.TestCase):
    def test_long_comment_is_truncated(self):
        long_comment = 'A' * (work_timer.MAX_COMMENT_LEN + 200)
        with tempfile.TemporaryDirectory() as td:
            work_timer.CSV_FILE = os.path.join(td, 'arbeitszeiten.csv')
            row = {'Datum': '2026-04-01', 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '16:00', 'Dauer': '8.00', 'Kommentar': long_comment}
            work_timer.save_data([row])
            # read raw file and check truncated length present
            with open(work_timer.CSV_FILE, 'r', encoding='utf-8') as f:
                content = f.read()
            # ensure we don't have the full long comment
            self.assertTrue(len(long_comment) > work_timer.MAX_COMMENT_LEN)
            self.assertFalse(long_comment in content)

    def test_overnight_shift_duration(self):
        dur = work_timer.calculate_duration('23:00', '02:00')
        # expect ~3.00 hours
        self.assertTrue(dur)
        self.assertAlmostEqual(float(dur), 3.0, places=2)

    def test_zero_length_shift(self):
        dur = work_timer.calculate_duration('08:00', '08:00')
        self.assertTrue(dur is not None)
        self.assertAlmostEqual(float(dur), 0.0, places=2)

    def test_many_rows_compute_saldo(self):
        # create many days of data to ensure compute_saldo scales and returns values
        with tempfile.TemporaryDirectory() as td:
            work_timer.CSV_FILE = os.path.join(td, 'arbeitszeiten.csv')
            start = datetime.today().date() - timedelta(days=500)
            data = []
            for i in range(500):
                d = (start + timedelta(days=i)).strftime(work_timer.DATE_FORMAT_INTERNAL)
                data.append({'Datum': d, 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '16:00', 'Dauer': '8.00', 'Kommentar': ''})
            work_timer.save_data(data)
            loaded = work_timer.load_data()
            self.assertEqual(len(loaded), 500)
            s = work_timer.compute_saldo(loaded)
            self.assertIsInstance(s, dict)
            self.assertIn('saldo', s)


class TestFillMissingWeekdays(unittest.TestCase):
    """Tests for _fill_missing_weekdays (synthetic Fehltag gap-filling logic)."""

    # Use a fixed week: 2026-03-16 (Mon) ... 2026-03-20 (Fri), no public holidays
    MON = date(2026, 3, 16)
    TUE = date(2026, 3, 17)
    WED = date(2026, 3, 18)
    THU = date(2026, 3, 19)
    FRI = date(2026, 3, 20)
    SAT = date(2026, 3, 21)
    SUN = date(2026, 3, 22)

    def _d(self, d):
        return d.strftime(work_timer.DATE_FORMAT_INTERNAL)

    def _entry(self, d, typ='Arbeit'):
        return {'Datum': self._d(d), 'Typ': typ, 'Startzeit': '08:00',
                'Endzeit': '16:00', 'Dauer': '8.00', 'Kommentar': ''}

    def _expand(self, entries, start, end, holidays=None):
        month_year = start.strftime('%Y-%m')
        return work_timer._fill_missing_weekdays(
            entries, month_year,
            holidays or set(),
            start,
            end,
        )

    def test_gap_between_monday_and_wednesday_fills_tuesday(self):
        """Mon and Wed have entries → Tue must be inserted as Fehltag."""
        entries = [self._entry(self.MON), self._entry(self.WED)]
        result  = self._expand(entries, self.MON, self.WED)
        datums  = [e['Datum'] for e in result]
        self.assertIn(self._d(self.TUE), datums)
        syn = [e for e in result if e.get('_synthetic') and e['Datum'] == self._d(self.TUE)]
        self.assertEqual(len(syn), 1)
        self.assertEqual(syn[0]['Typ'], 'Fehltag')

    def test_no_weekend_rows_inserted(self):
        """Weekend days must never appear as synthetic entries."""
        entries = [self._entry(self.FRI)]
        # range covers Sat and Sun as well
        result  = self._expand(entries, self.FRI, self.SUN)
        synth_dates = {e['Datum'] for e in result if e.get('_synthetic')}
        self.assertNotIn(self._d(self.SAT), synth_dates)
        self.assertNotIn(self._d(self.SUN), synth_dates)

    def test_holiday_day_not_inserted(self):
        """A day marked as holiday must not become a Fehltag."""
        holiday_date = self._d(self.TUE)
        entries = [self._entry(self.MON), self._entry(self.WED)]
        result  = self._expand(entries, self.MON, self.WED, holidays={holiday_date})
        synth_dates = {e['Datum'] for e in result if e.get('_synthetic')}
        self.assertNotIn(holiday_date, synth_dates)

    def test_existing_entry_not_duplicated(self):
        """A day that already has an entry must not also get a synthetic row."""
        entries = [self._entry(self.MON), self._entry(self.TUE), self._entry(self.WED)]
        result  = self._expand(entries, self.MON, self.WED)
        tue_rows = [e for e in result if e['Datum'] == self._d(self.TUE)]
        self.assertEqual(len(tue_rows), 1)
        self.assertFalse(tue_rows[0].get('_synthetic'))

    def test_result_is_sorted_by_date(self):
        """Returned list must be sorted chronologically."""
        # only Mon and Fri → Tue/Wed/Thu should be inserted and sorted in between
        entries = [self._entry(self.FRI), self._entry(self.MON)]
        result  = self._expand(entries, self.MON, self.FRI)
        datums  = [e['Datum'] for e in result]
        self.assertEqual(datums, sorted(datums))

    def test_full_week_no_entries_all_weekdays_filled(self):
        """With no entries, all 5 weekdays of a week should be inserted as Fehltag."""
        result     = self._expand([], self.MON, self.FRI)
        synth      = [e for e in result if e.get('_synthetic')]
        synth_days = {e['Datum'] for e in synth}
        for d in (self.MON, self.TUE, self.WED, self.THU, self.FRI):
            self.assertIn(self._d(d), synth_days)
        self.assertEqual(len(synth), 5)

    def test_fehltag_delta_equals_minus_daily_hours(self):
        """The Fehltag row delta value in the helper is _synthetic=True; caller sets -DAILY_HOURS."""
        entries = [self._entry(self.MON), self._entry(self.WED)]
        result  = self._expand(entries, self.MON, self.WED)
        syn = next(e for e in result if e.get('_synthetic'))
        # The helper itself doesn't set delta — it's set by the PDF caller.
        # What we verify here: _synthetic flag is True and Typ is 'Fehltag'.
        self.assertTrue(syn['_synthetic'])
        self.assertEqual(syn['Typ'], 'Fehltag')
        self.assertEqual(syn['Dauer'], '')


class TestInteractiveMenu(unittest.TestCase):
    """Tests for _interactive_menu() plain-text fallback."""

    def _call(self, user_input, items=None):
        if items is None:
            items = [('1', 'Option A'), ('2', 'Option B'), ('0', 'Zurück')]
        orig = work_timer.HAVE_PROMPT_TOOLKIT
        work_timer.HAVE_PROMPT_TOOLKIT = False
        try:
            with patch('builtins.input', return_value=user_input):
                return work_timer._interactive_menu('Test', items)
        finally:
            work_timer.HAVE_PROMPT_TOOLKIT = orig

    def test_returns_selected_key(self):
        self.assertEqual(self._call('2'), '2')

    def test_returns_zero_for_back(self):
        self.assertEqual(self._call('0'), '0')

    def test_unknown_input_returned_as_is(self):
        """Unknown input is returned as-is so callers can show error messages."""
        self.assertEqual(self._call('x'), 'x')

    def test_empty_input_returned_as_empty_string(self):
        self.assertEqual(self._call(''), '')


class TestBrowseMonths(unittest.TestCase):
    """Tests for browse_months() data preparation and fallback rendering."""

    def _make_entries(self, td):
        """Create a small dataset spanning two months."""
        work_timer.CSV_FILE    = os.path.join(td, 'arbeitszeiten.csv')
        work_timer.CONFIG_FILE = os.path.join(td, 'config.json')
        data = [
            {'Datum': '2026-03-09', 'Typ': 'Arbeit', 'Startzeit': '08:00',
             'Endzeit': '16:00', 'Dauer': '8.00', 'Kommentar': ''},
            {'Datum': '2026-03-11', 'Typ': 'Arbeit', 'Startzeit': '08:00',
             'Endzeit': '16:00', 'Dauer': '8.00', 'Kommentar': ''},
            {'Datum': '2026-04-01', 'Typ': 'Arbeit', 'Startzeit': '09:00',
             'Endzeit': '17:00', 'Dauer': '8.00', 'Kommentar': ''},
        ]
        work_timer.save_data(data)
        import json
        with open(work_timer.CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump({'name': 'Test', 'holidays': {}}, f)
        return data

    def test_no_data_returns_early(self):
        """browse_months prints a message and returns when no data is available."""
        with tempfile.TemporaryDirectory() as td:
            work_timer.CSV_FILE    = os.path.join(td, 'arbeitszeiten.csv')
            work_timer.CONFIG_FILE = os.path.join(td, 'config.json')
            import json
            with open(work_timer.CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump({'name': 'Test', 'holidays': {}}, f)
            # Empty CSV → load_data returns []
            with open(work_timer.CSV_FILE, 'w', encoding='utf-8') as f:
                f.write('')
            # Should not raise; just print a message and return
            work_timer.browse_months()

    def test_fallback_plain_text_quit_immediately(self):
        """Plain-text fallback: entering 'q' exits after showing first month."""
        with tempfile.TemporaryDirectory() as td:
            self._make_entries(td)
            # Disable prompt_toolkit to force fallback
            orig = work_timer.HAVE_PROMPT_TOOLKIT
            work_timer.HAVE_PROMPT_TOOLKIT = False
            try:
                with patch('builtins.input', return_value='q'):
                    work_timer.browse_months()
            finally:
                work_timer.HAVE_PROMPT_TOOLKIT = orig

    def test_fallback_navigate_next_then_quit(self):
        """Plain-text fallback: navigate next month then quit."""
        with tempfile.TemporaryDirectory() as td:
            self._make_entries(td)
            orig = work_timer.HAVE_PROMPT_TOOLKIT
            work_timer.HAVE_PROMPT_TOOLKIT = False
            try:
                inputs = iter(['n', 'q'])
                with patch('builtins.input', side_effect=inputs):
                    work_timer.browse_months()
            finally:
                work_timer.HAVE_PROMPT_TOOLKIT = orig

    def test_fallback_navigate_prev_at_start_stays(self):
        """Plain-text fallback: navigating prev at first month doesn't crash."""
        with tempfile.TemporaryDirectory() as td:
            self._make_entries(td)
            orig = work_timer.HAVE_PROMPT_TOOLKIT
            work_timer.HAVE_PROMPT_TOOLKIT = False
            try:
                # Start at last month, go to prev, prev again (stays at first), quit
                inputs = iter(['p', 'p', 'q'])
                with patch('builtins.input', side_effect=inputs):
                    work_timer.browse_months()
            finally:
                work_timer.HAVE_PROMPT_TOOLKIT = orig


if __name__ == '__main__':
    unittest.main()
