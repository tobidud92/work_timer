import unittest
from datetime import datetime
import src.work_timer as wt


class TestInputDateDefaults(unittest.TestCase):
    def _patch_prompt(self, fn):
        """Set a mock _prompt and disable lazy-init so the mock is not overwritten."""
        orig_prompt = wt._prompt
        orig_init   = wt._prompt_toolkit_initialized
        wt._prompt_toolkit_initialized = True  # suppress _ensure_prompt_toolkit
        wt._prompt = fn
        return orig_prompt, orig_init

    def _restore_prompt(self, orig_prompt, orig_init):
        wt._prompt = orig_prompt
        wt._prompt_toolkit_initialized = orig_init

    def test_input_date_prompt_toolkit_enter_uses_today(self):
        orig_p, orig_i = self._patch_prompt(lambda prompt, default=None: '')
        try:
            res = wt.input_date('Datum')
            today_display = datetime.now().strftime(wt.DATE_FORMAT_DISPLAY)
            self.assertEqual(res, datetime.strptime(today_display, wt.DATE_FORMAT_DISPLAY).strftime(wt.DATE_FORMAT_INTERNAL))
        finally:
            self._restore_prompt(orig_p, orig_i)

    def test_input_date_with_value(self):
        orig_p, orig_i = self._patch_prompt(lambda prompt, default=None: '16.04.2026')
        try:
            res = wt.input_date('Datum')
            self.assertEqual(res, '2026-04-16')
        finally:
            self._restore_prompt(orig_p, orig_i)


if __name__ == '__main__':
    unittest.main()
