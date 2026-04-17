import os
import tempfile
import unittest

import src.work_timer as work_timer


class TestMultipleCheckins(unittest.TestCase):
    def test_compute_saldo_with_multiple_checkins(self):
        with tempfile.TemporaryDirectory() as td:
            work_timer.CSV_FILE = os.path.join(td, 'arbeitszeiten.csv')
            # create two work entries on same date totaling 8h
            d = '2026-04-01'
            e1 = {'Datum': d, 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '12:00', 'Dauer': '4.00', 'Kommentar': ''}
            e2 = {'Datum': d, 'Typ': 'Arbeit', 'Startzeit': '13:00', 'Endzeit': '17:00', 'Dauer': '4.00', 'Kommentar': ''}
            work_timer.save_data([e1, e2])
            loaded = work_timer.load_data()
            self.assertEqual(len(loaded), 2)
            s = work_timer.compute_saldo(loaded)
            self.assertIsInstance(s, dict)
            # ist_brutto should include both entries (8h)
            self.assertAlmostEqual(s['ist_brutto'], 8.0, places=2)


if __name__ == '__main__':
    unittest.main()
