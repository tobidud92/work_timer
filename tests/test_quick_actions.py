import os
import csv
import json
import tempfile
import importlib

import unittest

import src.work_timer as wt


class TestQuickActions(unittest.TestCase):
    def setUp(self):
        # create isolated temp directory for CSV and config
        self.tmpdir = tempfile.TemporaryDirectory()
        self.csv_path = os.path.join(self.tmpdir.name, 'arbeitszeiten.csv')
        self.cfg_path = os.path.join(self.tmpdir.name, 'config.json')

        # ensure module uses these paths
        wt.CSV_FILE = self.csv_path
        wt.CONFIG_FILE = self.cfg_path

        # minimal config
        with open(self.cfg_path, 'w', encoding='utf-8') as f:
            json.dump({'name': 'Test', 'holidays': {}}, f)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_start_and_end_work_create_entry(self):
        # ensure no CSV exists
        if os.path.exists(self.csv_path):
            os.remove(self.csv_path)

        # call start_work and then end_work
        wt.start_work()

        # CSV should exist and contain one entry with Typ 'Arbeit'
        self.assertTrue(os.path.exists(self.csv_path))
        with open(self.csv_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        self.assertGreaterEqual(len(rows), 1)
        row = rows[-1]
        self.assertEqual(row.get('Typ'), 'Arbeit')
        self.assertTrue(row.get('Startzeit'))

        # now call end_work
        wt.end_work()

        # reload CSV and check Endzeit and Dauer
        with open(self.csv_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        row = rows[-1]
        self.assertTrue(row.get('Endzeit'))
        self.assertTrue(row.get('Dauer'))


if __name__ == '__main__':
    unittest.main()
