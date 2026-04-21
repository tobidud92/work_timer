import unittest
from datetime import datetime
import src.work_timer as wt


class TestQuickActionsMessageBox(unittest.TestCase):
    def setUp(self):
        # in-memory data store to simulate CSV contents
        self.data_store = []
        def fake_load():
            return self.data_store
        def fake_save(d):
            # replace contents of the in-memory store to simulate write
            temp = list(d)
            self.data_store.clear()
            self.data_store.extend(temp)
        def fake_append(entry):
            # simulate _append_data_row: just add to the in-memory store
            self.data_store.append(entry)

        # patch load/save/append, state helpers, and messagebox
        wt.load_data_orig = wt.load_data
        wt.save_data_orig = wt.save_data
        wt._append_data_row_orig = wt._append_data_row
        wt._load_checkin_state_orig = wt._load_checkin_state
        wt._save_checkin_state_orig = wt._save_checkin_state
        wt._show_messagebox_orig = getattr(wt, '_show_messagebox', None)
        wt.load_data = fake_load
        wt.save_data = fake_save
        wt._append_data_row = fake_append
        # derive state dynamically from data_store so the fast-path reflects real data
        wt._load_checkin_state = lambda: wt._derive_checkin_state(self.data_store)
        wt._save_checkin_state = lambda s: None  # no-op

        self.msg_calls = []
        def fake_msg(title, message):
            self.msg_calls.append((title, message))
        wt._show_messagebox = fake_msg

    def tearDown(self):
        # restore
        wt.load_data = wt.load_data_orig
        wt.save_data = wt.save_data_orig
        wt._append_data_row = wt._append_data_row_orig
        wt._load_checkin_state = wt._load_checkin_state_orig
        wt._save_checkin_state = wt._save_checkin_state_orig
        if wt._show_messagebox_orig is None:
            try:
                delattr(wt, '_show_messagebox')
            except Exception:
                pass
        else:
            wt._show_messagebox = wt._show_messagebox_orig

    def test_quick_start_creates_entry_when_none(self):
        self.assertEqual(len(self.data_store), 0)
        wt.quick_start_action()
        self.assertEqual(len(self.data_store), 1)
        entry = self.data_store[0]
        self.assertEqual(entry['Typ'], 'Arbeit')
        self.assertIsNotNone(entry.get('Startzeit'))
        self.assertTrue(any('Eingecheckt' in t for t, m in self.msg_calls))

    def test_quick_start_when_already_started_shows_message(self):
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.append({'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
        wt.quick_start_action()
        # should not create another entry
        self.assertEqual(len(self.data_store), 1)
        self.assertTrue(any('Bereits eingecheckt' in t for t, m in self.msg_calls))

    def test_quick_end_without_start_shows_warning(self):
        # no entries
        wt.quick_end_action()
        self.assertTrue(any('Kein offenes Intervall' in t for t, m in self.msg_calls))

    def test_quick_end_success_sets_endtime(self):
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.append({'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
        wt.quick_end_action()
        entry = self.data_store[0]
        self.assertTrue(entry.get('Endzeit'))
        self.assertTrue(any('Ausgecheckt' in t for t, m in self.msg_calls))

    def test_quick_end_when_already_ended_shows_message(self):
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.append({'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00', 'Endzeit': '12:00', 'Dauer': '4.00', 'Kommentar': ''})
        wt.quick_end_action()
        # no open interval -> shows 'Kein offenes Intervall'
        self.assertTrue(any('Kein offenes Intervall' in t for t, m in self.msg_calls))

    def test_quick_start_blocked_when_shift_open(self):
        """Re-checkin must be blocked when a shift is still open (no Endzeit)."""
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.append({'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00',
                                'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
        wt.quick_start_action()
        # must NOT create a second entry
        self.assertEqual(len(self.data_store), 1)
        self.assertTrue(any('Bereits eingecheckt' in t for t, m in self.msg_calls))

    def test_quick_start_allowed_after_completed_shift(self):
        """Re-checkin should be allowed once previous shift is fully closed."""
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.append({'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00',
                                'Endzeit': '12:00', 'Dauer': '4.00', 'Kommentar': ''})
        wt.quick_start_action()
        # second Arbeit entry should now exist
        arbeit = [e for e in self.data_store if e.get('Typ') == 'Arbeit']
        self.assertEqual(len(arbeit), 2)
        self.assertTrue(any('Eingecheckt' in t for t, m in self.msg_calls))

    def test_quick_end_closes_second_shift(self):
        """quick_end should close the open (second) shift, not the first."""
        today = datetime.now().strftime(wt.DATE_FORMAT_INTERNAL)
        self.data_store.extend([
            {'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '08:00',
             'Endzeit': '12:00', 'Dauer': '4.00', 'Kommentar': ''},
            {'Datum': today, 'Typ': 'Arbeit', 'Startzeit': '13:00',
             'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
        ])
        wt.quick_end_action()
        # first entry unchanged, second entry now has Endzeit
        self.assertEqual(self.data_store[0]['Endzeit'], '12:00')
        self.assertTrue(bool(self.data_store[1].get('Endzeit')))
        self.assertTrue(any('Ausgecheckt' in t for t, m in self.msg_calls))


if __name__ == '__main__':
    unittest.main()
