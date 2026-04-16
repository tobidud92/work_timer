import unittest
from datetime import datetime, timedelta
import code.work_timer as wt


class TestDateArrows(unittest.TestCase):
    def test_adjust_date_display_empty_uses_today(self):
        res = wt.adjust_date_display('', 0)
        today = datetime.now().strftime(wt.DATE_FORMAT_DISPLAY)
        self.assertEqual(res, today)

    def test_adjust_date_display_minus_one(self):
        sample = '16.04.2026'
        res = wt.adjust_date_display(sample, -1)
        self.assertEqual(res, '15.04.2026')

    def test_adjust_date_display_plus_one(self):
        sample = '16.04.2026'
        res = wt.adjust_date_display(sample, 1)
        self.assertEqual(res, '17.04.2026')


if __name__ == '__main__':
    unittest.main()
