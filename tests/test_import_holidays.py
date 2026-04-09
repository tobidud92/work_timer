import os
import tempfile
import unittest
import csv

import code.work_timer as work_timer


class TestImportHolidays(unittest.TestCase):
    def test_import_csv_with_display_and_internal_dates(self):
        with tempfile.TemporaryDirectory() as td:
            cfg_file = os.path.join(td, 'config.json')
            work_timer.CONFIG_FILE = cfg_file
            # prepare CSV with two lines: one display format, one internal
            csv_path = os.path.join(td, 'holidays.csv')
            rows = [
                ['08.04.2026', 'TestFeiertagDisplay'],
                ['2027-12-25', 'Weihnachten2027']
            ]
            with open(csv_path, 'w', encoding='utf-8', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['Datum', 'Name'])
                writer.writerows(rows)

            # run import (non-interactive: overwrite_all)
            work_timer.import_holidays_from_csv(csv_path, merge_strategy='overwrite_all')

            cfg = work_timer.load_config()
            mh = cfg.get('holidays') or {}
            self.assertIn('2026-04-08', mh)
            self.assertEqual(mh.get('2026-04-08'), 'TestFeiertagDisplay')
            self.assertIn('2027-12-25', mh)
            self.assertEqual(mh.get('2027-12-25'), 'Weihnachten2027')


if __name__ == '__main__':
    unittest.main()
