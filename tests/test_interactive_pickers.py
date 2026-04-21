import unittest
import src.work_timer as wt


class TestInteractivePickers(unittest.TestCase):
    def test_input_date_with_prompt_mock(self):
        orig, orig_i = wt._prompt, wt._prompt_toolkit_initialized
        try:
            wt._prompt_toolkit_initialized = True
            wt._prompt = lambda prompt, default=None: '16.04.2026'
            res = wt.input_date('Datum')
            self.assertEqual(res, '2026-04-16')
        finally:
            wt._prompt, wt._prompt_toolkit_initialized = orig, orig_i

    def test_input_time_with_prompt_mock(self):
        orig, orig_i = wt._prompt, wt._prompt_toolkit_initialized
        try:
            wt._prompt_toolkit_initialized = True
            wt._prompt = lambda prompt, default=None: '08:30'
            res = wt.input_time('Startzeit')
            self.assertEqual(res, '08:30')
        finally:
            wt._prompt, wt._prompt_toolkit_initialized = orig, orig_i


if __name__ == '__main__':
    unittest.main()
