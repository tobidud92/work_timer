"""Minimal quick-action entry point for Kommen / Gehen desktop shortcuts.

Intentionally tiny: only uses stdlib (csv, json, os, sys, ctypes, datetime).
No prompt_toolkit, no reportlab, no shutil — keeps PyInstaller bundle small
and startup fast (<300 ms target in onedir mode).

Invoked via:
    work_timer_quick.exe --start-now
    work_timer_quick.exe --end-now
"""

import csv
import ctypes
import json
import os
import sys
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration (must mirror work_timer.py)
# ---------------------------------------------------------------------------
DATE_FORMAT_INTERNAL = '%Y-%m-%d'
DATE_FORMAT_DISPLAY  = '%d.%m.%Y'
TIME_FORMAT          = '%H:%M'
CSV_FILE             = 'arbeitszeiten.csv'
CHECKIN_STATE_FILE   = 'checkin_state.json'

# ---------------------------------------------------------------------------
# Tiny helpers
# ---------------------------------------------------------------------------

def _show_messagebox(title: str, message: str) -> None:
    """Native Win32 MessageBox — synchronous, topmost, always visible."""
    try:
        MB_ICONINFORMATION = 0x40
        MB_SETFOREGROUND   = 0x10000
        MB_TOPMOST         = 0x40000
        ctypes.windll.user32.MessageBoxW(
            0, str(message), str(title),
            MB_ICONINFORMATION | MB_SETFOREGROUND | MB_TOPMOST
        )
    except Exception:
        print(f"{title}: {message}")


def _load_checkin_state() -> dict:
    try:
        with open(CHECKIN_STATE_FILE, 'r', encoding='utf-8') as f:
            s = json.load(f)
        return s if isinstance(s, dict) else {}
    except Exception:
        return {}


def _save_checkin_state(state: dict) -> None:
    try:
        tmp = CHECKIN_STATE_FILE + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(state, f)
            f.flush()
            try:
                os.fsync(f.fileno())
            except Exception:
                pass
        os.replace(tmp, CHECKIN_STATE_FILE)
    except Exception:
        pass


def _load_today_arbeit(today_internal: str) -> list:
    """Read only the Arbeit rows for today from the CSV."""
    rows = []
    if not os.path.exists(CSV_FILE):
        return rows
    try:
        with open(CSV_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('Datum') == today_internal and row.get('Typ') == 'Arbeit':
                    rows.append(dict(row))
    except Exception:
        pass
    return rows


def _append_csv_row(entry: dict) -> None:
    """Append a single row to the CSV without rewriting the whole file."""
    fieldnames = ['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar']
    file_exists = os.path.exists(CSV_FILE)
    try:
        with open(CSV_FILE, 'a', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if not file_exists or os.path.getsize(CSV_FILE) == 0:
                writer.writeheader()
            writer.writerow({k: entry.get(k, '') for k in fieldnames})
            f.flush()
            try:
                os.fsync(f.fileno())
            except Exception:
                pass
    except Exception as e:
        print(f"CSV append error: {e}")


def _rewrite_csv_update_row(target_datum: str, target_start: str,
                            new_endzeit: str, new_dauer: str) -> None:
    """Rewrite the CSV updating the one row that matches datum+startzeit."""
    if not os.path.exists(CSV_FILE):
        return
    fieldnames = ['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar']
    rows = []
    try:
        with open(CSV_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                r = dict(row)
                if (r.get('Datum') == target_datum
                        and r.get('Startzeit') == target_start
                        and not r.get('Endzeit')):
                    r['Endzeit'] = new_endzeit
                    r['Dauer']   = new_dauer
                rows.append(r)
    except Exception as e:
        print(f"CSV read error: {e}")
        return
    tmp = CSV_FILE + '.tmp'
    try:
        with open(tmp, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for row in rows:
                writer.writerow({k: row.get(k, '') for k in fieldnames})
            f.flush()
            try:
                os.fsync(f.fileno())
            except Exception:
                pass
        os.replace(tmp, CSV_FILE)
    except Exception as e:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except Exception:
                pass
        print(f"CSV write error: {e}")


def _calc_duration(start_str: str, end_str: str) -> str:
    """Return duration as '7.50' (hours, two decimal places)."""
    try:
        fmt = TIME_FORMAT
        s = datetime.strptime(start_str, fmt)
        e = datetime.strptime(end_str, fmt)
        delta = e - s
        if delta.total_seconds() < 0:
            delta_sec = delta.total_seconds() + 86400  # overnight
        else:
            delta_sec = delta.total_seconds()
        return f"{delta_sec / 3600:.2f}"
    except Exception:
        return ''


# ---------------------------------------------------------------------------
# Quick action handlers
# ---------------------------------------------------------------------------

def quick_start():
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display  = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str        = datetime.now().strftime(TIME_FORMAT)

    # Fast path: no CSV I/O
    state = _load_checkin_state()
    open_shift = state.get('open_shift')
    if open_shift and open_shift.get('date') == today_internal:
        _show_messagebox(
            'Bereits eingecheckt',
            f"Intervall seit {open_shift['start']} ist noch offen.\n"
            f"Bitte zuerst 'Gehen' buchen."
        )
        return

    # Slow path: verify via CSV
    today_arbeit = _load_today_arbeit(today_internal)
    open_entry = next(
        (e for e in reversed(today_arbeit) if e.get('Startzeit') and not e.get('Endzeit')),
        None
    )
    if open_entry:
        _save_checkin_state(_derive_state_from_today(today_internal, today_arbeit))
        _show_messagebox(
            'Bereits eingecheckt',
            f"Intervall seit {open_entry['Startzeit']} ist noch offen.\n"
            f"Bitte zuerst 'Gehen' buchen."
        )
        return

    # Act: append new interval
    new_entry = {
        'Datum': today_internal, 'Typ': 'Arbeit',
        'Startzeit': now_str, 'Endzeit': '', 'Dauer': '', 'Kommentar': ''
    }
    _append_csv_row(new_entry)
    shift_num = len(today_arbeit) + 1
    _save_checkin_state({
        'version': 1,
        'open_shift': {'date': today_internal, 'start': now_str, 'shift_num': shift_num}
    })
    if shift_num > 1:
        _show_messagebox('Eingecheckt',
                         f"Eingecheckt (Schicht {shift_num}): {today_display} um {now_str}.")
    else:
        _show_messagebox('Eingecheckt', f"Eingecheckt: {today_display} um {now_str}.")


def quick_end():
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display  = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str        = datetime.now().strftime(TIME_FORMAT)

    # Fast path
    state = _load_checkin_state()
    open_shift = state.get('open_shift')
    if not open_shift or open_shift.get('date') != today_internal:
        _show_messagebox(
            'Kein offenes Intervall',
            "Kein offenes Intervall für heute gefunden.\n"
            "Bitte zuerst 'Kommen' buchen."
        )
        return

    # Slow path: find open entry in CSV
    today_arbeit = _load_today_arbeit(today_internal)
    open_entry = next(
        (e for e in reversed(today_arbeit) if e.get('Startzeit') and not e.get('Endzeit')),
        None
    )
    if not open_entry:
        _save_checkin_state(_derive_state_from_today(today_internal, today_arbeit))
        _show_messagebox(
            'Kein offenes Intervall',
            "Kein offenes Intervall für heute gefunden.\n"
            "Bitte zuerst 'Kommen' buchen."
        )
        return

    start_str = open_entry['Startzeit']
    dauer     = _calc_duration(start_str, now_str)
    _rewrite_csv_update_row(today_internal, start_str, now_str, dauer)

    # Update sidecar: clear open_shift, set last_checkout
    _save_checkin_state({
        'version': 1,
        'last_checkout': {'date': today_internal, 'start': start_str, 'time': now_str}
    })

    shift_num = today_arbeit.index(open_entry) + 1
    if len(today_arbeit) > 1:
        _show_messagebox('Ausgecheckt',
                         f"Ausgecheckt (Schicht {shift_num}): {today_display} um {now_str}. "
                         f"Gearbeitet: {dauer} Stunden.")
    else:
        _show_messagebox('Ausgecheckt',
                         f"Ausgecheckt: {today_display} um {now_str}. "
                         f"Gearbeitet: {dauer} Stunden.")


def _derive_state_from_today(today_internal: str, today_arbeit: list) -> dict:
    """Rebuild the sidecar state from the today Arbeit rows."""
    for entry in reversed(today_arbeit):
        if entry.get('Startzeit') and not entry.get('Endzeit'):
            return {
                'version': 1,
                'open_shift': {
                    'date': today_internal,
                    'start': entry['Startzeit'],
                    'shift_num': today_arbeit.index(entry) + 1,
                }
            }
    # All closed
    for entry in reversed(today_arbeit):
        if entry.get('Endzeit'):
            return {
                'version': 1,
                'last_checkout': {
                    'date': today_internal,
                    'start': entry.get('Startzeit', ''),
                    'time': entry['Endzeit'],
                }
            }
    return {'version': 1}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    import argparse

    # Change working directory to exe location so relative paths (CSV, sidecar) resolve correctly
    if getattr(sys, 'frozen', False):
        os.chdir(os.path.dirname(sys.executable))

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--start-now', action='store_true')
    parser.add_argument('--end-now',   action='store_true')
    args, _ = parser.parse_known_args()

    if args.start_now:
        quick_start()
    elif args.end_now:
        quick_end()
    else:
        _show_messagebox(
            'WorkTimer Quick',
            'Kein Argument angegeben.\nNutze --start-now oder --end-now.'
        )
