import os
import tempfile
import unittest
import json

import code.work_timer as work_timer


class TestSanitizeAtomic(unittest.TestCase):
    def test_sanitize_for_csv_prefix_and_control_chars(self):
        s = "=SUM(1,2)\x00\nNext"
        res = work_timer.sanitize_for_csv(s, max_len=50)
        self.assertTrue(res.startswith("'"))
        self.assertNotIn('\x00', res)
        self.assertNotIn('\n', res)

    def test_save_data_atomic_and_sanitization(self):
        with tempfile.TemporaryDirectory() as td:
            work_timer.CSV_FILE = os.path.join(td, 'arbeitszeiten.csv')
            data = [{'Datum':'2026-04-09','Typ':'Arbeit','Startzeit':'08:00','Endzeit':'16:00','Dauer':'8.00','Kommentar':'=cmd'}]
            work_timer.save_data(data)
            # file exists and contains sanitized comment
            with open(work_timer.CSV_FILE, 'r', encoding='utf-8') as f:
                content = f.read()
            self.assertIn("'=cmd", content)
            # tmp file should not remain
            self.assertFalse(os.path.exists(work_timer.CSV_FILE + '.tmp'))

    def test_save_and_load_config_backup_corrupt(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = os.path.join(td, 'config.json')
            work_timer.CONFIG_FILE = cfg
            # write corrupt JSON
            with open(cfg, 'w', encoding='utf-8') as f:
                f.write('{"name": "Test",}')
            loaded = work_timer.load_config()
            # After loading, the corrupt file should have been moved/renamed
            files = os.listdir(td)
            corrupts = [p for p in files if p.startswith('config.json.corrupt')]
            self.assertTrue(corrupts, 'Corrupt config backup not created')
            # Now saving a new valid config must create a proper config.json
            work_timer.save_config({'name': 'NewName'})
            with open(cfg, 'r', encoding='utf-8') as f:
                d = json.load(f)
            self.assertEqual(d.get('name'), 'NewName')


if __name__ == '__main__':
    unittest.main()
