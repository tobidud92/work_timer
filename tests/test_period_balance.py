import builtins
import json
import unittest
from datetime import date
from tempfile import TemporaryDirectory
from unittest.mock import patch

import src.work_timer as work_timer


class TestPeriodBalance(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.original_csv = work_timer.CSV_FILE
        self.original_config = work_timer.CONFIG_FILE
        self.addCleanup(self._restore_paths)
        work_timer.CSV_FILE = f'{self.temp_dir.name}/arbeitszeiten.csv'
        work_timer.CONFIG_FILE = f'{self.temp_dir.name}/config.json'
        work_timer._data_cache = None
        work_timer._data_cache_mtime = None
        work_timer._data_cache_path = None
        work_timer._data_index = {}
        with open(work_timer.CONFIG_FILE, 'w', encoding='utf-8') as config_file:
            json.dump({'name': '', 'holidays': {}}, config_file)

    def _restore_paths(self):
        work_timer.CSV_FILE = self.original_csv
        work_timer.CONFIG_FILE = self.original_config
        work_timer._data_cache = None
        work_timer._data_cache_mtime = None
        work_timer._data_cache_path = None
        work_timer._data_index = {}

    def test_calculates_soll_and_ist_for_the_requested_period(self):
        entries = [
            {'Datum': '2026-04-20', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '15:00', 'Dauer': '6.00', 'Kommentar': ''},
            {'Datum': '2026-04-21', 'Typ': 'Urlaub', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
            {'Datum': '2026-04-22', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '15:00', 'Dauer': '6.00', 'Kommentar': ''},
            {'Datum': '2026-04-23', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
        ]

        result = work_timer.compute_time_balance_for_period(
            entries, date(2026, 4, 20), date(2026, 4, 24)
        )

        self.assertEqual(result['soll'], 4 * work_timer.DAILY_HOURS)
        self.assertEqual(result['ist_brutto'], 19.0)
        self.assertEqual(result['ist_netto'], 19.0)
        self.assertEqual(result['saldo'], 19.0 - 4 * work_timer.DAILY_HOURS)

    def test_absence_range_asks_only_context_specific_dates(self):
        prompts = []
        answers = iter(['2026-04-20', '2026-04-20', 'Arzttermin'])

        def fake_input_date(prompt):
            prompts.append(prompt)
            return next(answers)

        with (patch.object(work_timer, 'input_date', fake_input_date),
              patch.object(builtins, 'input', lambda prompt='': next(answers))):
            work_timer.add_special_day('Krankheit')

        self.assertTrue(any('Krankheitbeginn' in prompt for prompt in prompts))
        self.assertTrue(any('Krankheitende' in prompt for prompt in prompts))
        self.assertFalse(any('Datum für Krankheit' in prompt for prompt in prompts))
        data = work_timer.load_data()
        self.assertEqual(data[0]['Typ'], 'Krankheit')

    def test_main_menu_omits_immediate_start_and_end_actions(self):
        captured_items = []

        def fake_menu(_, items):
            captured_items.extend(items)
            return ''

        with patch.object(work_timer, '_interactive_menu', fake_menu):
            self.assertFalse(work_timer.main_menu())

        labels = [label for _, label in captured_items]
        self.assertNotIn('Arbeitsbeginn erfassen (jetzt)', labels)
        self.assertNotIn('Arbeitsende erfassen (jetzt)', labels)
        self.assertEqual(captured_items[0], ('1', 'Zeitsaldo anzeigen'))
        self.assertEqual(captured_items[1], ('2', 'Zeitraum auswerten (Soll / Ist)'))


if __name__ == '__main__':
    unittest.main()
