import os
import tempfile
import unittest
from datetime import datetime, timedelta

import code.work_timer as work_timer


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


if __name__ == '__main__':
    unittest.main()
