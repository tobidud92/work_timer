import unittest
import src.work_timer as wt


class TestDateTimeParsing(unittest.TestCase):
    def test_to_internal_and_display(self):
        self.assertEqual(wt.to_internal('16.04.2026'), '2026-04-16')
        self.assertEqual(wt.to_internal('01.01.2020'), '2020-01-01')
        self.assertEqual(wt.to_display('2026-04-16'), '16.04.2026')

    def test_calculate_duration_simple(self):
        d = wt.calculate_duration('08:00', '16:30')
        self.assertEqual(d, '8.50')

    def test_calculate_duration_overnight(self):
        d = wt.calculate_duration('22:30', '01:15')
        # 2h45m => 2.75
        self.assertEqual(d, '2.75')


if __name__ == '__main__':
    unittest.main()
