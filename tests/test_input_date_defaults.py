import unittest
from datetime import datetime
import code.work_timer as wt


class TestInputDateDefaults(unittest.TestCase):
    def test_input_date_prompt_toolkit_enter_uses_today(self):
        orig = wt._prompt
        try:
            # simulate prompt_toolkit returning an empty string (user pressed Enter)
            wt._prompt = lambda prompt, default=None: ''
            res = wt.input_date('Datum')
            today_display = datetime.now().strftime(wt.DATE_FORMAT_DISPLAY)
            self.assertEqual(res, datetime.strptime(today_display, wt.DATE_FORMAT_DISPLAY).strftime(wt.DATE_FORMAT_INTERNAL))
        finally:
            wt._prompt = orig

    def test_input_date_with_value(self):
        orig = wt._prompt
        try:
            wt._prompt = lambda prompt, default=None: '16.04.2026'
            res = wt.input_date('Datum')
            self.assertEqual(res, '2026-04-16')
        finally:
            wt._prompt = orig


if __name__ == '__main__':
    unittest.main()
