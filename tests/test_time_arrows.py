import unittest
from datetime import datetime
import src.work_timer as wt


class TestTimeArrows(unittest.TestCase):
    def test_adjust_time_display_empty_uses_now(self):
        res = wt.adjust_time_display('', 0)
        now_display = datetime.now().strftime(wt.TIME_FORMAT)
        self.assertEqual(res, now_display)

    def test_adjust_time_display_minus_one(self):
        sample = '08:30'
        res = wt.adjust_time_display(sample, -1)
        self.assertEqual(res, '08:29')

    def test_adjust_time_display_plus_one(self):
        sample = '08:30'
        res = wt.adjust_time_display(sample, 1)
        self.assertEqual(res, '08:31')


if __name__ == '__main__':
    unittest.main()
