import csv
import json
from datetime import datetime, timedelta, date
import os
import shutil
import sys
from typing import Optional

# Optional interactive prompt support (prompt_toolkit)
_prompt = None
HAVE_PROMPT_TOOLKIT = False
try:
    from prompt_toolkit import shortcuts
    _prompt = shortcuts.prompt
    HAVE_PROMPT_TOOLKIT = True
except Exception:
    _prompt = None
    HAVE_PROMPT_TOOLKIT = False

# Allow forcing prompt_toolkit usage via environment variable (useful in packaged runs)
if os.environ.get('FORCE_PROMPT_TOOLKIT') == '1':
    if not HAVE_PROMPT_TOOLKIT:
        try:
            from prompt_toolkit import shortcuts as _shortcuts_force
            _prompt = _shortcuts_force.prompt
            HAVE_PROMPT_TOOLKIT = True
        except Exception:
            print('WARNING: FORCE_PROMPT_TOOLKIT set but prompt_toolkit is not importable.')
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.lib import colors

# --- Konfiguration ---
CSV_FILE             = 'arbeitszeiten.csv'
CONFIG_FILE          = 'config.json'
DATE_FORMAT_INTERNAL = '%Y-%m-%d'
DATE_FORMAT_DISPLAY  = '%d.%m.%Y'
TIME_FORMAT          = '%H:%M'
PDF_REPORT_DIR       = 'reports'
WEEKLY_HOURS         = 35.0
DAILY_HOURS          = WEEKLY_HOURS / 5   # 7.0 h
BREAK_THRESHOLD_HOURS = 6.0
BREAK_DURATION_HOURS  = 0.75             # 45 min
# --- Sicherheits-/Sanity-Settings ---
MAX_NAME_LEN         = 100
MAX_COMMENT_LEN      = 500
CSV_INJECTION_PREFIX_CHARS = ('=', '+', '-', '@')

# --- Konfigurationsverwaltung ---

def load_config():
    """Lädt die Konfiguration aus der config.json."""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, mode='r', encoding='utf-8') as f:
                cfg = json.load(f)
                # ensure expected keys exist
                if not isinstance(cfg, dict):
                    return {'name': '', 'holidays': {}}
                if 'holidays' not in cfg:
                    cfg['holidays'] = {}
                return cfg
        except (json.JSONDecodeError, IOError):
            # Backup corrupt config for inspection rather than silently ignore
            try:
                corrupt_name = CONFIG_FILE + f'.corrupt.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
                os.replace(CONFIG_FILE, corrupt_name)
            except Exception:
                pass
    return {'name': '', 'holidays': {}}

def save_config(config):
    """Speichert die Konfiguration in der config.json."""
    # Sanitize name and enforce max length
    if 'name' in config and config['name'] is not None:
        name = str(config['name']).strip()
        name = name.replace('\x00', '')[:MAX_NAME_LEN]
        config['name'] = name

    tmp = CONFIG_FILE + '.tmp'
    try:
        with open(tmp, mode='w', encoding='utf-8') as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
            f.flush()
            try:
                os.fsync(f.fileno())
            except Exception:
                pass
        os.replace(tmp, CONFIG_FILE)
    finally:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except Exception:
            pass


def backup_config():
    """Erstellt eine Zeitstempel-Backup-Kopie von `config.json`.

    Rückgabe: Pfad der Backup-Datei oder None.
    """
    if not os.path.exists(CONFIG_FILE):
        return None
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_name = CONFIG_FILE + f'.bak.{ts}'
    try:
        shutil.copy2(CONFIG_FILE, backup_name)
        # keep only the most recent backup (this one)
        dirpath = os.path.dirname(os.path.abspath(CONFIG_FILE)) or '.'
        base = os.path.basename(CONFIG_FILE)
        for f in os.listdir(dirpath):
            if f.startswith(base + '.bak'):
                full = os.path.join(dirpath, f)
                try:
                    if os.path.abspath(full) != os.path.abspath(backup_name):
                        os.remove(full)
                except Exception:
                    pass
        return backup_name
    except Exception:
        return None


def list_config_backups():
    """Gibt eine sortierte Liste vorhandener Config-Backups zurück."""
    dirpath = os.path.dirname(CONFIG_FILE) or '.'
    base = os.path.basename(CONFIG_FILE)
    items = []
    for f in os.listdir(dirpath):
        if f.startswith(base + '.bak'):
            items.append(os.path.join(dirpath, f))
    items.sort(reverse=True)
    return items


def restore_config_backup():
    """Interaktive Wiederherstellung eines Config-Backups.

    Listet vorhandene Backups auf, fragt den Benutzer und ersetzt `config.json`.
    """
    backups = list_config_backups()
    if not backups:
        print('Keine Config-Backups gefunden.')
        return
    print('\nGefundene Config-Backups:')
    for i, b in enumerate(backups, 1):
        print(f"{i}. {b}")
    sel = input('Wähle Backup-Nummer zum Wiederherstellen (leer = Abbrechen): ').strip()
    if not sel:
        print('Abgebrochen.')
        return
    try:
        idx = int(sel) - 1
        if idx < 0 or idx >= len(backups):
            print('Ungültige Auswahl.')
            return
        chosen = backups[idx]
        # backup current config before replacing
        backup_config()
        os.replace(chosen, CONFIG_FILE)
        print(f'Config aus {chosen} wiederhergestellt.')
    except ValueError:
        print('Ungültige Eingabe.')
        return

def get_user_name():
    """Gibt den gespeicherten Namen zurück."""
    return load_config().get('name', '')

def set_user_name():
    """Erlaubt das Setzen / Ändern des Benutzernamens."""
    config       = load_config()
    current_name = config.get('name', '')

    if current_name:
        print(f"Aktueller Name: {current_name}")
    else:
        print("Es ist noch kein Name hinterlegt.")

    new_name = input("Neuen Namen eingeben (leer lassen = keine Änderung): ").strip()

    if new_name:
        config['name'] = new_name
        save_config(config)
        print(f"Name erfolgreich auf '{new_name}' gesetzt.")
    else:
        print("Keine Änderung vorgenommen.")

def ensure_user_name():
    """Stellt sicher dass beim ersten Start ein Name hinterlegt wird."""
    config = load_config()
    if not config.get('name', '').strip():
        print("\n👋 Willkommen beim Arbeitszeittracker!")
        print("Bitte hinterlege zunächst deinen Namen für die Reports.")
        name = input("Dein Name: ").strip()
        if name:
            config['name'] = name
            save_config(config)
            print(f"Name '{name}' gespeichert. Los geht's!\n")
        else:
            print("Kein Name eingegeben. Du kannst ihn später über Option 12 setzen.\n")


# --- Datumskonvertierung ---

def to_display(date_str_internal):
    try:
        return datetime.strptime(date_str_internal, DATE_FORMAT_INTERNAL).strftime(DATE_FORMAT_DISPLAY)
    except ValueError:
        return date_str_internal

def to_internal(date_str_display):
    try:
        return datetime.strptime(date_str_display, DATE_FORMAT_DISPLAY).strftime(DATE_FORMAT_INTERNAL)
    except ValueError:
        return None

def input_date(prompt):
    today_display = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    full_prompt = prompt + f" (TT.MM.JJJJ, z.B. {today_display}): "
    while True:
        # use prompt_toolkit if available; tests can monkeypatch _prompt
        if _prompt:
            try:
                # try to provide arrow-key Up/Down to change the date if prompt_toolkit supports key bindings
                try:
                    from prompt_toolkit.key_binding import KeyBindings
                    from prompt_toolkit.document import Document
                except Exception:
                    KeyBindings = None

                if KeyBindings:
                    kb = KeyBindings()

                    def _adjust_buffer(buf, new_text):
                        try:
                            # set_document is available on buffers
                            buf.set_document(Document(new_text, cursor_position=len(new_text)), bypass_undo=True)
                        except Exception:
                            buf.text = new_text

                    @kb.add('up')
                    def _(_event):
                        buf = _event.current_buffer
                        cur = buf.text.strip() or today_display
                        new = adjust_date_display(cur, -1)
                        _adjust_buffer(buf, new)

                    @kb.add('down')
                    def _(_event):
                        buf = _event.current_buffer
                        cur = buf.text.strip() or today_display
                        new = adjust_date_display(cur, 1)
                        _adjust_buffer(buf, new)

                    # Some test mocks or older prompt implementations may not accept key_bindings kwarg.
                    try:
                        date_str = _prompt(full_prompt, default=today_display, key_bindings=kb)
                    except TypeError:
                        date_str = _prompt(full_prompt, default=today_display)
                else:
                    date_str = _prompt(full_prompt, default=today_display)
            except Exception:
                date_str = input(full_prompt)
        else:
            date_str = input(full_prompt)

        date_str = date_str.strip()
        if not date_str:
            date_str = today_display
        internal = to_internal(date_str)
        if internal:
            return internal
        print("Ungültiges Datumsformat. Bitte verwende TT.MM.JJJJ.")


def _show_messagebox(title: str, message: str):
    """Show a Windows message box (works in packaged exe too).

    Falls nicht unter Windows oder MessageBox nicht verfügbar, fällt es auf print zurück.
    """
    # Prefer native Windows API when available (works in packaged exe)
    try:
        import ctypes
        # show top-most information box so hidden/desktop-launched processes still surface
        MB_ICONINFORMATION = 0x40
        MB_SETFOREGROUND  = 0x10000
        MB_TOPMOST        = 0x40000
        flags = MB_ICONINFORMATION | MB_SETFOREGROUND | MB_TOPMOST
        ctypes.windll.user32.MessageBoxW(0, str(message), str(title), flags)
        return
    except Exception:
        pass

    # Fallback to tkinter.messagebox if available (works in many Python installs)
    try:
        import tkinter as _tk
        from tkinter import messagebox as _msg
        try:
            root = _tk.Tk()
            root.withdraw()
            _msg.showinfo(str(title), str(message))
        finally:
            try:
                root.destroy()
            except Exception:
                pass
        return
    except Exception:
        pass

    # Another robust non-blocking fallback using mshta popup (auto-closes after few seconds).
    # mshta is generally available on Windows and creates a visible window even for
    # processes started without a console. We spawn it asynchronously so the EXE can exit.
    try:
        import subprocess, shlex
        esc_msg = str(message).replace('"', '\\"').replace('\n', ' ')
        esc_title = str(title).replace('"', '\\"')
        # Popup(timeout_seconds) - using 4 seconds display and information icon (64)
        js = f"javascript:var sh=new ActiveXObject(\"WScript.Shell\"); sh.Popup(\"{esc_msg}\",4,\"{esc_title}\",64);close();"
        subprocess.Popen(['mshta', js], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    except Exception:
        pass

    # Final fallback: print to stdout/stderr
    try:
        print(f"{title}: {message}")
    except Exception:
        pass


def _get_last_checkout_time(data):
    """Return a tuple (date_display, time_str) of the most recent Endzeit found, or (None, None)."""
    for entry in reversed(data):
        et = entry.get('Endzeit')
        if et:
            return (to_display(entry.get('Datum', '')), et)
    return (None, None)


def quick_start_action():
    data = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str = datetime.now().strftime(TIME_FORMAT)
    today_entry = get_entry_by_date(data, today_internal)

    if today_entry:
        if today_entry.get('Typ') == 'Arbeit' and today_entry.get('Startzeit'):
            # already checked in
            _show_messagebox('Bereits eingecheckt', f"Sie sind bereits am {today_display} um {today_entry['Startzeit']} eingecheckt.")
            return
        if today_entry.get('Typ') != 'Arbeit':
            _show_messagebox('Eintrag-Konflikt', f"Für {today_display} existiert ein Eintrag vom Typ '{today_entry.get('Typ')}'. Bitte überprüfen.")
            return
        # entry exists but no starttime -> set it
        today_entry['Startzeit'] = now_str
        today_entry['Dauer'] = calculate_duration(today_entry.get('Startzeit', ''), today_entry.get('Endzeit', ''))
        save_data(data)
        _show_messagebox('Eingecheckt', f"Eingecheckt: {today_display} um {now_str}.")
        return

    # no entry -> create one
    data.append({'Datum': today_internal, 'Typ': 'Arbeit', 'Startzeit': now_str, 'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
    save_data(data)
    _show_messagebox('Eingecheckt', f"Eingecheckt: {today_display} um {now_str}.")


def quick_end_action():
    data = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str = datetime.now().strftime(TIME_FORMAT)
    today_entry = get_entry_by_date(data, today_internal)

    if not today_entry or today_entry.get('Typ') != 'Arbeit' or not today_entry.get('Startzeit'):
        # undefined state: no start recorded for today
        last_date, last_time = _get_last_checkout_time(data)
        if last_time:
            _show_messagebox('Kein Arbeitsbeginn gefunden', f"Kein Arbeitsbeginn für heute gefunden. Letzter Checkout: {last_date} um {last_time}. Aktion abgebrochen.")
        else:
            _show_messagebox('Kein Arbeitsbeginn gefunden', "Kein Arbeitsbeginn für heute gefunden. Aktion abgebrochen.")
        return

    if today_entry.get('Endzeit'):
        _show_messagebox('Bereits ausgecheckt', f"Sie haben bereits um {today_entry['Endzeit']} ausgecheckt.")
        return

    today_entry['Endzeit'] = now_str
    today_entry['Dauer'] = calculate_duration(today_entry.get('Startzeit', ''), today_entry.get('Endzeit', ''))
    save_data(data)
    _show_messagebox('Ausgecheckt', f"Ausgecheckt: {today_display} um {now_str}. Gearbeitet: {today_entry['Dauer']} Stunden.")


def input_time(prompt: str, default: Optional[str] = None) -> str:
    """Prompt for a time 'HH:MM'. Uses prompt_toolkit if available; returns validated time string."""
    if default is None:
        default = datetime.now().strftime(TIME_FORMAT)
    full_prompt = prompt + f" (HH:MM) [{default}]: "
    while True:
        if _prompt:
            try:
                # try to provide arrow-key Up/Down to change the time if prompt_toolkit supports key bindings
                try:
                    from prompt_toolkit.key_binding import KeyBindings
                    from prompt_toolkit.document import Document
                except Exception:
                    KeyBindings = None

                if KeyBindings:
                    kb = KeyBindings()

                    def _adjust_buffer(buf, new_text):
                        try:
                            buf.set_document(Document(new_text, cursor_position=len(new_text)), bypass_undo=True)
                        except Exception:
                            buf.text = new_text

                    @kb.add('up')
                    def _(_event):
                        buf = _event.current_buffer
                        cur = buf.text.strip() or default
                        new = adjust_time_display(cur, -1)
                        _adjust_buffer(buf, new)

                    @kb.add('down')
                    def _(_event):
                        buf = _event.current_buffer
                        cur = buf.text.strip() or default
                        new = adjust_time_display(cur, 1)
                        _adjust_buffer(buf, new)

                    # Some test mocks or older prompt implementations may not accept key_bindings kwarg.
                    try:
                        s = _prompt(full_prompt, default=default, key_bindings=kb)
                    except TypeError:
                        s = _prompt(full_prompt, default=default)
                else:
                    s = _prompt(full_prompt, default=default)
            except Exception:
                s = input(full_prompt)
        else:
            s = input(full_prompt)
        s = s.strip()
        if not s:
            s = default
        try:
            datetime.strptime(s, TIME_FORMAT)
            return s
        except ValueError:
            print("Ungültiges Zeitformat. Bitte HH:MM eingeben.")


def adjust_date_display(date_display: str, delta_days: int) -> str:
    """Return a display-format date string shifted by delta_days.

    If the input is empty or invalid, treat it as today.
    """
    if not date_display:
        d = date.today()
    else:
        try:
            d = datetime.strptime(date_display, DATE_FORMAT_DISPLAY).date()
        except Exception:
            # fallback to today
            d = date.today()
    d = d + timedelta(days=delta_days)
    return d.strftime(DATE_FORMAT_DISPLAY)


def adjust_time_display(time_display: str, delta_minutes: int) -> str:
    """Return a TIME_FORMAT string shifted by delta_minutes.

    If the input is empty or invalid, treat it as now (rounded to minute).
    """
    if not time_display:
        now = datetime.now().replace(second=0, microsecond=0)
    else:
        try:
            now = datetime.strptime(time_display, TIME_FORMAT)
        except Exception:
            now = datetime.now().replace(second=0, microsecond=0)
    new = now + timedelta(minutes=delta_minutes)
    return new.strftime(TIME_FORMAT)

# --- Feiertage Bayern / Erlangen 2026–2031 ---

def get_public_holidays(start_year=None, years=10):
    holidays = {}

    def add(d, name):
        holidays[d.strftime(DATE_FORMAT_INTERNAL)] = name

    if start_year is None:
        start_year = date.today().year

    for year in range(start_year, start_year + years):
        a = year % 19
        b = year // 100
        c = year % 100
        d = b // 4
        e = b % 4
        f = (b + 8) // 25
        g = (b - f + 1) // 3
        h = (19 * a + b - d - g + 15) % 30
        i = c // 4
        k = c % 4
        l = (32 + 2 * e + 2 * i - h - k) % 7
        m = (a + 11 * h + 22 * l) // 451
        month = (h + l - 7 * m + 114) // 31
        day   = ((h + l - 7 * m + 114) % 31) + 1
        easter_sunday = date(year, month, day)

        add(date(year, 1,  1),  "Neujahr")
        add(date(year, 1,  6),  "Heilige Drei Könige")
        add(date(year, 5,  1),  "Tag der Arbeit")
        add(date(year, 10, 3),  "Tag der Deutschen Einheit")
        add(date(year, 11, 1),  "Allerheiligen")
        add(date(year, 12, 25), "1. Weihnachtstag")
        add(date(year, 12, 26), "2. Weihnachtstag")

        add(easter_sunday - timedelta(days=2),  "Karfreitag")
        add(easter_sunday,                       "Ostersonntag")
        add(easter_sunday + timedelta(days=1),   "Ostermontag")
        add(easter_sunday + timedelta(days=39),  "Christi Himmelfahrt")
        add(easter_sunday + timedelta(days=49),  "Pfingstsonntag")
        add(easter_sunday + timedelta(days=50),  "Pfingstmontag")
        add(easter_sunday + timedelta(days=60),  "Fronleichnam")

    return holidays

PUBLIC_HOLIDAYS = get_public_holidays()

# --- Hilfsfunktionen ---

def load_data():
    data = []
    if os.path.exists(CSV_FILE):
        with open(CSV_FILE, mode='r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                for field in ['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar']:
                    if field not in row:
                        row[field] = ''
                data.append(row)
    return data


def sanitize_for_csv(value, max_len=None):
    """Sanitize a field before writing to CSV to mitigate CSV injection and control chars.

    - Remove null bytes
    - Trim to max_len if given
    - If starts with a CSV-injection prefix, prefix with a single quote
    """
    if value is None:
        return ''
    s = str(value)
    # remove null bytes
    s = s.replace('\x00', '')
    # normalize newlines to single space to avoid breaking CSV display
    s = s.replace('\r', ' ').replace('\n', ' ')
    s = s.strip()
    if max_len is not None and len(s) > max_len:
        s = s[:max_len]
    if s and s[0] in CSV_INJECTION_PREFIX_CHARS:
        s = "'" + s
    return s


def sanitize_for_pdf(value, max_len=None):
    """Sanitize text that will be placed into PDF Paragraphs/Tables.

    - Remove null bytes and control newlines
    - Collapse whitespace
    - Escape HTML special chars used by reportlab Paragraphs
    - Trim to max_len if provided
    """
    if value is None:
        return ''
    s = str(value)
    s = s.replace('\x00', '')
    # replace newlines/tabs with single spaces to avoid layout issues
    s = s.replace('\r', ' ').replace('\n', ' ').replace('\t', ' ')
    # collapse multiple spaces
    s = ' '.join(s.split())
    # escape HTML-like characters used by Paragraph
    s = s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    if max_len is not None and len(s) > max_len:
        s = s[:max_len]
    return s


def ask_yes(prompt, default=False):
    """Unified yes/no prompt.

    Accepts 'j'/'n' (German) or 'y'/'n' (English). Returns True for yes.
    """
    ans = input(prompt).strip().lower()
    if ans in ('j', 'y'):
        return True
    return False


def print_header():
    user_name = get_user_name()
    name_info = f" | Benutzer: {user_name}" if user_name else " | ⚠️ Kein Name hinterlegt"
    print(f"\n--- Arbeitszeittracker{name_info} ---")

def save_data(data):
    fieldnames = ['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar']
    tmp = CSV_FILE + '.tmp'
    try:
        with open(tmp, mode='w', newline='', encoding='utf-8') as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            for row in data:
                safe_row = {
                    'Datum': sanitize_for_csv(row.get('Datum', '')),
                    'Typ': sanitize_for_csv(row.get('Typ', '')),
                    'Startzeit': sanitize_for_csv(row.get('Startzeit', '')),
                    'Endzeit': sanitize_for_csv(row.get('Endzeit', '')),
                    'Dauer': sanitize_for_csv(row.get('Dauer', '')),
                    'Kommentar': sanitize_for_csv(row.get('Kommentar', ''), max_len=MAX_COMMENT_LEN),
                }
                writer.writerow(safe_row)
            file.flush()
            try:
                os.fsync(file.fileno())
            except Exception:
                pass
        os.replace(tmp, CSV_FILE)
    finally:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except Exception:
            pass

def get_entry_by_date(data, target_date_internal):
    for entry in data:
        if entry['Datum'] == target_date_internal:
            return entry
    return None

def calculate_duration(start_time_str, end_time_str):
    if not start_time_str or not end_time_str:
        return ""
    try:
        dummy    = datetime.now().strftime(DATE_FORMAT_INTERNAL)
        start_dt = datetime.strptime(f"{dummy} {start_time_str}", f"{DATE_FORMAT_INTERNAL} {TIME_FORMAT}")
        end_dt   = datetime.strptime(f"{dummy} {end_time_str}",   f"{DATE_FORMAT_INTERNAL} {TIME_FORMAT}")
        if end_dt < start_dt:
            end_dt += timedelta(days=1)
        return f"{(end_dt - start_dt).total_seconds() / 3600:.2f}"
    except ValueError:
        return ""

def is_public_holiday(date_internal, manually_entered_holidays=None):
    if date_internal in PUBLIC_HOLIDAYS:
        return True
    if manually_entered_holidays and date_internal in manually_entered_holidays:
        return True
    return False

def get_day_type_info(date_internal, manually_entered_holidays=None):
    try:
        d = datetime.strptime(date_internal, DATE_FORMAT_INTERNAL).date()
    except ValueError:
        return 'weekday'
    if is_public_holiday(date_internal, manually_entered_holidays):
        return 'holiday'
    if d.weekday() == 5:
        return 'saturday'
    if d.weekday() == 6:
        return 'sunday'
    return 'weekday'

def apply_surcharge(hours, day_type):
    if day_type == 'saturday':
        return hours * 1.5
    elif day_type in ('sunday', 'holiday'):
        return hours * 2.0
    return hours

def calculate_netto_hours(brutto_hours):
    if brutto_hours > BREAK_THRESHOLD_HOURS:
        return brutto_hours - BREAK_DURATION_HOURS
    return brutto_hours

def compute_day_delta(entry, manually_entered_holidays=None):
    date_internal = entry.get('Datum', '')
    typ           = entry.get('Typ', '')
    dauer_str     = entry.get('Dauer', '')

    try:
        d = datetime.strptime(date_internal, DATE_FORMAT_INTERNAL).date()
    except ValueError:
        return 0.0, '—', ''

    day_type      = get_day_type_info(date_internal, manually_entered_holidays)
    zuschlag_info = ''

    if typ in ('Arbeit', 'Sonderarbeit'):
        if dauer_str:
            try:
                brutto = float(dauer_str)
            except ValueError:
                return 0.0, '—', ''
            netto = calculate_netto_hours(brutto)
            if typ == 'Sonderarbeit' or day_type in ('saturday', 'sunday', 'holiday'):
                netto_mit_zuschlag = apply_surcharge(netto, day_type)
                if day_type == 'saturday':
                    zuschlag_info = '+50% Sa'
                elif day_type in ('sunday', 'holiday'):
                    zuschlag_info = '+100% So/Ft'
                delta = netto_mit_zuschlag
            else:
                delta = netto - DAILY_HOURS
            delta_str = f"+{delta:.2f} h" if delta >= 0 else f"{delta:.2f} h"
            return delta, delta_str, zuschlag_info
        else:
            return 0.0, '—', ''
    elif typ == 'Urlaub':
        return 0.0, '±0.00 h', ''
    elif typ == 'Zeitausgleich':
        delta = -DAILY_HOURS
        return delta, f"{delta:.2f} h", ''
    elif typ == 'Feiertag':
        return 0.0, '±0.00 h', ''

    return 0.0, '—', ''

# --- Zeitsaldo-Berechnung ---

def compute_saldo(data):
    """Zentrale Saldo-Berechnung, gibt alle Werte als Dict zurück."""
    today    = date.today()
    # holidays defined in config.json (mapping date->name) is the single source of truth
    cfg = load_config()
    config_holidays_map = cfg.get('holidays', {}) if isinstance(cfg, dict) else {}
    combined_holidays = set(config_holidays_map.keys()) if isinstance(config_holidays_map, dict) else set()

    all_dates = []
    for entry in data:
        try:
            all_dates.append(datetime.strptime(entry['Datum'], DATE_FORMAT_INTERNAL).date())
        except ValueError:
            pass

    if not all_dates:
        return None

    start_date   = min(all_dates)
    soll_stunden = 0.0
    current      = start_date

    while current <= today:
        di = current.strftime(DATE_FORMAT_INTERNAL)
        if current.weekday() < 5:
            if di not in PUBLIC_HOLIDAYS and di not in combined_holidays:
                soll_stunden += DAILY_HOURS
        current += timedelta(days=1)

    ist_brutto       = 0.0
    pausen_abzug     = 0.0
    zuschlag_stunden = 0.0

    for entry in data:
        try:
            ed = datetime.strptime(entry['Datum'], DATE_FORMAT_INTERNAL).date()
        except ValueError:
            continue
        if ed > today:
            continue
        typ       = entry.get('Typ', '')
        dauer_str = entry.get('Dauer', '')

        if typ in ('Arbeit', 'Sonderarbeit') and dauer_str:
            try:
                brutto = float(dauer_str)
                netto  = calculate_netto_hours(brutto)
                ist_brutto += brutto
                if brutto > BREAK_THRESHOLD_HOURS:
                    pausen_abzug += BREAK_DURATION_HOURS
                if typ == 'Sonderarbeit':
                    dt = get_day_type_info(entry['Datum'], combined_holidays)
                    zuschlag_stunden += apply_surcharge(netto, dt) - netto
            except ValueError:
                pass
        elif typ == 'Urlaub':
            ist_brutto += DAILY_HOURS

    ist_netto  = ist_brutto - pausen_abzug
    ist_gesamt = ist_netto + zuschlag_stunden
    saldo      = ist_gesamt - soll_stunden

    return {
        'start_date':       start_date,
        'today':            today,
        'soll':             soll_stunden,
        'ist_brutto':       ist_brutto,
        'pausen_abzug':     pausen_abzug,
        'ist_netto':        ist_netto,
        'zuschlag':         zuschlag_stunden,
        'ist_gesamt':       ist_gesamt,
        'saldo':            saldo,
        # expose both the combined set and the config mapping for report rendering
        'holidays': combined_holidays,
        'holidays_map': config_holidays_map,
    }


def ensure_holidays_in_config():
    """Wenn in `config.json` keine Feiertage existieren, fülle sie mit PUBLIC_HOLIDAYS (10 Jahre)."""
    cfg = load_config()
    if not isinstance(cfg, dict):
        cfg = {'name': '', 'holidays': {}}
    h = cfg.get('holidays') or {}
    if not h:
        cfg['holidays'] = PUBLIC_HOLIDAYS.copy()
        save_config(cfg)
        print(f"{CONFIG_FILE} mit Feiertagen vorbefüllt.")

def calculate_time_balance():
    data = load_data()
    if not data:
        print("Keine Daten vorhanden. Bitte erfasse zuerst Arbeitszeiten.")
        return

    current_year       = date.today().year
    holidays_this_year = [k for k in PUBLIC_HOLIDAYS if k.startswith(str(current_year))]
    if not holidays_this_year:
        print(f"\n⚠️  Keine Feiertagsdaten für {current_year} vorhanden!")
        print("Bitte trage die Feiertage manuell ein (Option 4 im Hauptmenü).")
        print("Die Saldo-Berechnung wird trotzdem durchgeführt, kann aber ungenau sein.\n")

    s = compute_saldo(data)
    if not s:
        print("Keine gültigen Datumseinträge gefunden.")
        return

    saldo_prefix = "+" if s['saldo'] >= 0 else ""
    saldo_label  = "Überstunden" if s['saldo'] >= 0 else "Minusstunden"

    print("\n" + "=" * 52)
    print("         ZEITSALDO-ÜBERSICHT")
    print("=" * 52)
    print(f"  Zeitraum:             {s['start_date'].strftime(DATE_FORMAT_DISPLAY)} – {s['today'].strftime(DATE_FORMAT_DISPLAY)}")
    print(f"  Wochenarbeitszeit:    {WEEKLY_HOURS:.1f} h  |  Tagessoll: {DAILY_HOURS:.1f} h")
    print(f"  Pausenregel:          -{int(BREAK_DURATION_HOURS * 60)} min ab {int(BREAK_THRESHOLD_HOURS)} h")
    print("-" * 52)
    print(f"  Soll-Stunden:         {s['soll']:.2f} h")
    print(f"  Ist-Stunden (brutto): {s['ist_brutto']:.2f} h")
    print(f"  Pausenabzug:         -{s['pausen_abzug']:.2f} h")
    print(f"  Ist-Stunden (netto):  {s['ist_netto']:.2f} h")
    if s['zuschlag'] > 0:
        print(f"  Zuschläge (Sa/So/Ft): +{s['zuschlag']:.2f} h")
    print("-" * 52)
    if s['saldo'] >= 0:
        print(f"  ✅ SALDO:             +{s['saldo']:.2f} h ({saldo_label})")
    else:
        print(f"  ❌ SALDO:             {s['saldo']:.2f} h ({saldo_label})")
    print("=" * 52 + "\n")

# --- Zeiterfassungsfunktionen ---

def start_work():
    data           = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display  = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str        = datetime.now().strftime(TIME_FORMAT)
    today_entry    = get_entry_by_date(data, today_internal)

    if today_entry:
        if today_entry['Typ'] == 'Arbeit' and today_entry['Startzeit']:
            print(f"Du hast heute bereits um {today_entry['Startzeit']} Uhr angefangen zu arbeiten.")
            if not ask_yes("Möchtest du den Arbeitsbeginn aktualisieren? (j/n): "):
                print("Vorgang abgebrochen.")
                return
            today_entry['Startzeit'] = now_str
            today_entry['Dauer']     = calculate_duration(today_entry['Startzeit'], today_entry['Endzeit'])
            print(f"Arbeitsbeginn für heute ({today_display}) auf {now_str} Uhr aktualisiert.")
        else:
            if not ask_yes(f"Für heute existiert bereits ein Eintrag vom Typ '{today_entry['Typ']}'. Überschreiben? (j/n): "):
                print("Vorgang abgebrochen.")
                return
            today_entry.update({'Typ': 'Arbeit', 'Startzeit': now_str, 'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
            print(f"Arbeitsbeginn für heute ({today_display}) um {now_str} Uhr erfasst.")
    else:
        data.append({'Datum': today_internal, 'Typ': 'Arbeit', 'Startzeit': now_str,
                     'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
        print(f"Arbeitsbeginn für heute ({today_display}) um {now_str} Uhr erfasst.")
    save_data(data)

def end_work():
    data           = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display  = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    now_str        = datetime.now().strftime(TIME_FORMAT)
    today_entry    = get_entry_by_date(data, today_internal)

    if not today_entry or today_entry['Typ'] != 'Arbeit':
        print("Kein Arbeitsbeginn für heute gefunden. Bitte zuerst Arbeitsbeginn erfassen.")
        return
    if not today_entry['Startzeit']:
        print("Kein Arbeitsbeginn erfasst. Bitte zuerst Arbeitsbeginn nachtragen (Option 6).")
        return
    if today_entry['Endzeit']:
        print(f"Arbeitsende heute bereits um {today_entry['Endzeit']} Uhr erfasst.")
        if not ask_yes("Möchtest du die Endzeit aktualisieren? (j/n): "):
            print("Vorgang abgebrochen.")
            return

    today_entry['Endzeit'] = now_str
    today_entry['Dauer']   = calculate_duration(today_entry['Startzeit'], today_entry['Endzeit'])
    print(f"Arbeitsende für heute ({today_display}) um {now_str} Uhr erfasst. Gearbeitet: {today_entry['Dauer']} Stunden.")
    save_data(data)

def add_special_day(day_type):
    data          = load_data()
    date_internal = input_date(f"Datum für {day_type} eingeben")
    date_display  = to_display(date_internal)
    comment       = input(f"Kommentar für {day_type} (optional): ")[:MAX_COMMENT_LEN]
    existing      = get_entry_by_date(data, date_internal)

    # For Feiertag: only update the config.json mapping (single source of truth)
    if day_type == 'Feiertag':
        cfg = load_config()
        if not isinstance(cfg, dict):
            cfg = {'name': '', 'holidays': {}}
        name_for_holiday = comment.strip() if comment.strip() else 'Manuell eingetragener Feiertag'
        cfg_map = cfg.get('holidays') or {}
        cfg_map[date_internal] = name_for_holiday
        cfg['holidays'] = cfg_map
        save_config(cfg)
        print(f"Feiertag {date_display} ('{name_for_holiday}') in {CONFIG_FILE} gespeichert (Config ist Single-Source-of-Truth).")
        return

    # Otherwise handle special day types that are stored in the CSV
    if day_type == 'Urlaub':
        # For vacation allow entering a range: start and end
        print('Urlaubszeitraum eingeben:')
        start_internal = input_date('Urlaubsbeginn')
        end_internal = input_date('Urlaubsende')
        try:
            start_dt = datetime.strptime(start_internal, DATE_FORMAT_INTERNAL).date()
            end_dt = datetime.strptime(end_internal, DATE_FORMAT_INTERNAL).date()
        except ValueError:
            print('Ungültiges Datum. Abgebrochen.')
            return

        if end_dt < start_dt:
            print('Das Enddatum liegt vor dem Beginn. Abgebrochen.')
            return

        cfg = load_config()
        cfg_holidays = set(cfg.get('holidays', {}).keys()) if isinstance(cfg, dict) else set()

        # classify days: collect candidates, hard conflicts and soft conflicts
        candidates = []
        hard_conflicts = []
        soft_conflicts = []
        current = start_dt
        while current <= end_dt:
            di = current.strftime(DATE_FORMAT_INTERNAL)
            dd = current.strftime(DATE_FORMAT_DISPLAY)

            # weekend = hard conflict
            if current.weekday() >= 5:
                hard_conflicts.append((dd, 'Wochenende'))
                current += timedelta(days=1)
                continue

            # holiday = hard conflict
            if is_public_holiday(di, cfg_holidays):
                name = PUBLIC_HOLIDAYS.get(di) or cfg.get('holidays', {}).get(di, 'Feiertag')
                hard_conflicts.append((dd, f'Feiertag ({name})'))
                current += timedelta(days=1)
                continue

            existing_entry = get_entry_by_date(data, di)
            if existing_entry and existing_entry.get('Typ') == 'Zeitausgleich':
                hard_conflicts.append((dd, 'Gleitzeittag (Zeitausgleich)'))
                current += timedelta(days=1)
                continue

            if existing_entry:
                soft_conflicts.append((dd, existing_entry.get('Typ')))
            else:
                candidates.append(di)

            current += timedelta(days=1)

        # report hard conflicts
        if hard_conflicts:
            print('\nNicht eintragbare Tage (Wochenende/Feiertag/Zeitausgleich):')
            for dstr, reason in hard_conflicts:
                print(f" - {dstr}: {reason}")

        # handle soft conflicts: either overwrite all, per-day, or skip
        to_add = list(candidates)
        to_overwrite = []
        if soft_conflicts:
            print('\nGefundene Konflikte mit bestehenden Einträgen:')
            for dstr, typ in soft_conflicts:
                print(f" - {dstr}: bestehender Eintrag '{typ}'")

            print('\nOptionen: (a) Alle überschreiben, (e) Einzeln pro Tag, (n) Nicht überschreiben')
            while True:
                ch = input('Wähle (a/e/n): ').strip().lower()
                if ch in ('a', 'e', 'n'):
                    break
            if ch == 'a':
                # overwrite all soft conflicts
                for dstr, _ in soft_conflicts:
                    di = to_internal(dstr)
                    if di:
                        to_overwrite.append(di)
            elif ch == 'e':
                # ask per date
                for dstr, typ in soft_conflicts:
                    if ask_yes(f"Für {dstr} existiert bereits ein Eintrag vom Typ '{typ}'. Überschreiben? (j/n): "):
                        di = to_internal(dstr)
                        if di:
                            to_overwrite.append(di)
                    else:
                        print(f"Überspringe {dstr}.")
            else:
                print('Keine bestehenden Einträge überschrieben.')

        # apply additions and overwrites
        added_count = 0
        for di in to_add:
            data.append({'Datum': di, 'Typ': 'Urlaub', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': comment})
            added_count += 1

        for di in to_overwrite:
            existing_entry = get_entry_by_date(data, di)
            if existing_entry:
                existing_entry.update({'Typ': 'Urlaub', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': comment})
                added_count += 1

        save_data(data)
        print(f"{added_count} Urlaubstag(er) hinzugefügt/überschrieben.")
        return

    # Zeitausgleich and other single-day types: existing behaviour
    if existing:
        if not ask_yes(f"Für {date_display} existiert bereits ein Eintrag vom Typ '{existing['Typ']}'. Überschreiben? (j/n): "):
            print("Vorgang abgebrochen.")
            return
        existing.update({'Typ': day_type, 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': comment})
        print(f"Eintrag für {date_display} als '{day_type}' aktualisiert.")
    else:
        data.append({'Datum': date_internal, 'Typ': day_type, 'Startzeit': '',
                     'Endzeit': '', 'Dauer': '', 'Kommentar': comment})
        print(f"Eintrag für {date_display} als '{day_type}' hinzugefügt.")
    save_data(data)

def add_special_work_day():
    data          = load_data()
    date_internal = input_date("Datum der Sonderarbeit (Samstag/Sonntag/Feiertag)")
    date_display  = to_display(date_internal)
    cfg = load_config()
    cfg_holidays = set(cfg.get('holidays', {}).keys()) if isinstance(cfg, dict) else set()
    day_type      = get_day_type_info(date_internal, cfg_holidays)

    if day_type == 'weekday':
        print(f"⚠️  {date_display} ist ein normaler Werktag.")
        print("Für normale Werktage bitte Option 1 oder Option 6/7 verwenden.")
        if not ask_yes("Trotzdem als Sonderarbeit erfassen? (j/n): "):
            print("Abgebrochen.")
            return

    if day_type == 'saturday':
        print(f"ℹ️  {date_display} ist ein Samstag → Zuschlag: +50%")
    elif day_type == 'sunday':
        print(f"ℹ️  {date_display} ist ein Sonntag → Zuschlag: +100%")
    elif day_type == 'holiday':
        holiday_name = PUBLIC_HOLIDAYS.get(date_internal, 'Manuell eingetragener Feiertag')
        print(f"ℹ️  {date_display} ist ein Feiertag ({holiday_name}) → Zuschlag: +100%")

    existing = get_entry_by_date(data, date_internal)
    if existing:
        if not ask_yes(f"Für {date_display} existiert bereits ein Eintrag vom Typ '{existing['Typ']}'. Überschreiben? (j/n): "):
            print("Abgebrochen.")
            return

    while True:
        start_str = input_time(f"Startzeit für {date_display}")
        try:
            datetime.strptime(start_str, TIME_FORMAT)
            break
        except ValueError:
            print("Ungültiges Zeitformat.")

    while True:
        end_str = input_time(f"Endzeit für {date_display}")
        try:
            datetime.strptime(end_str, TIME_FORMAT)
            break
        except ValueError:
            print("Ungültiges Zeitformat.")

    dauer   = calculate_duration(start_str, end_str)
    comment = input("Kommentar (optional): ")[:MAX_COMMENT_LEN]

    try:
        brutto = float(dauer)
        netto  = calculate_netto_hours(brutto)
        netto_mit_zuschlag = apply_surcharge(netto, day_type)
        pause_info = f", davon {BREAK_DURATION_HOURS:.2f} h Pause abgezogen" if brutto > BREAK_THRESHOLD_HOURS else ""
        print(f"\n  Bruttozeit:             {brutto:.2f} h{pause_info}")
        print(f"  Nettozeit:              {netto:.2f} h")
        print(f"  Nettozeit m. Zuschlag:  {netto_mit_zuschlag:.2f} h")
    except ValueError:
        pass

    entry_data = {'Datum': date_internal, 'Typ': 'Sonderarbeit',
                  'Startzeit': start_str, 'Endzeit': end_str,
                  'Dauer': dauer, 'Kommentar': comment}
    if existing:
        existing.update(entry_data)
    else:
        data.append(entry_data)

    save_data(data)
    print(f"Sonderarbeit für {date_display} erfasst.")

def edit_work_start():
    data = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    # Use the central input_date helper so prompt_toolkit (if available) is used
    date_internal = input_date("Datum des zu korrigierenden Arbeitsbeginns")
    date_display = to_display(date_internal)
    entry = get_entry_by_date(data, date_internal)

    if not entry:
        print(f"Kein Eintrag für {date_display} gefunden.")
        if ask_yes("Neuen Arbeits-Eintrag für dieses Datum erstellen? (j/n): "):
            new_start = input_time(f"Startzeit für {date_display}")
            try:
                datetime.strptime(new_start, TIME_FORMAT)
                data.append({'Datum': date_internal, 'Typ': 'Arbeit', 'Startzeit': new_start,
                             'Endzeit': '', 'Dauer': '', 'Kommentar': ''})
                save_data(data)
                print(f"Neuer Eintrag für {date_display} mit Startzeit {new_start} Uhr erstellt.")
            except ValueError:
                print("Ungültiges Zeitformat. Abgebrochen.")
        return

    if entry['Typ'] not in ('Arbeit', 'Sonderarbeit'):
        if not ask_yes(f"Eintrag für {date_display} ist vom Typ '{entry['Typ']}'. Auf 'Arbeit' ändern? (j/n): "):
            print("Abgebrochen.")
            return
        entry['Typ'] = 'Arbeit'
        entry['Kommentar'] = ''

    print(f"Aktueller Arbeitsbeginn für {date_display}: {entry.get('Startzeit', 'nicht gesetzt')} Uhr")
    new_start = input_time("Neue Startzeit (HH:MM, leer = keine Änderung)", default=entry.get('Startzeit') or None)
    if new_start:
        try:
            datetime.strptime(new_start, TIME_FORMAT)
            entry['Startzeit'] = new_start
            entry['Dauer']     = calculate_duration(entry['Startzeit'], entry['Endzeit'])
            save_data(data)
            print(f"Arbeitsbeginn für {date_display} auf {new_start} Uhr aktualisiert.")
        except ValueError:
            print("Ungültiges Zeitformat. Abgebrochen.")
    else:
        print("Keine Änderung vorgenommen.")

def edit_work_end():
    data = load_data()
    today_internal = datetime.now().strftime(DATE_FORMAT_INTERNAL)
    today_display = datetime.now().strftime(DATE_FORMAT_DISPLAY)
    # Use the central input_date helper so prompt_toolkit (if available) is used
    date_internal = input_date("Datum des zu korrigierenden Arbeitsendes")
    date_display = to_display(date_internal)
    entry = get_entry_by_date(data, date_internal)

    if not entry:
        print(f"Kein Eintrag für {date_display} gefunden. Bitte zuerst Arbeitsbeginn erfassen.")
        return
    if entry['Typ'] not in ('Arbeit', 'Sonderarbeit'):
        if not ask_yes(f"Eintrag für {date_display} ist vom Typ '{entry['Typ']}'. Auf 'Arbeit' ändern? (j/n): "):
            print("Abgebrochen.")
            return
        entry['Typ'] = 'Arbeit'
        entry['Kommentar'] = ''
    if not entry.get('Startzeit'):
        print(f"Kein Arbeitsbeginn für {date_display} erfasst. Bitte zuerst Arbeitsbeginn nachtragen (Option 6).")
        return

    print(f"Aktuelles Arbeitsende für {date_display}: {entry.get('Endzeit', 'nicht gesetzt')} Uhr")
    new_end = input_time("Neues Arbeitsende (HH:MM, leer = keine Änderung)", default=entry.get('Endzeit') or None)
    if new_end:
        try:
            datetime.strptime(new_end, TIME_FORMAT)
            entry['Endzeit'] = new_end
            entry['Dauer']   = calculate_duration(entry['Startzeit'], entry['Endzeit'])
            save_data(data)
            print(f"Arbeitsende für {date_display} auf {new_end} Uhr aktualisiert. Dauer: {entry['Dauer']} Stunden.")
        except ValueError:
            print("Ungültiges Zeitformat. Abgebrochen.")
    else:
        print("Keine Änderung vorgenommen.")

# --- PDF Report ---

def generate_pdf_report():
    data = load_data()
    if not data:
        print("Keine Daten vorhanden.")
        return

    user_name = sanitize_for_pdf(get_user_name() or "Unbekannt", max_len=MAX_NAME_LEN)
    s         = compute_saldo(data)
    if not s:
        print("Keine gültigen Datumseinträge gefunden.")
        return

    holidays = s['holidays']
    holidays_map = s.get('holidays_map', {})
    today     = s['today']
    sorted_data  = sorted(data, key=lambda x: x['Datum'])
    monthly_data = {}
    for entry in sorted_data:
        try:
            mo = datetime.strptime(entry['Datum'], DATE_FORMAT_INTERNAL).strftime('%Y-%m')
        except ValueError:
            mo = 'Unbekannt'
        monthly_data.setdefault(mo, []).append(entry)

    os.makedirs(PDF_REPORT_DIR, exist_ok=True)
    pdf_filename = os.path.join(PDF_REPORT_DIR,
                                f"arbeitszeitreport_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf")

    doc    = SimpleDocTemplate(pdf_filename, pagesize=A4,
                               topMargin=0.6*inch, bottomMargin=0.6*inch,
                               leftMargin=0.7*inch, rightMargin=0.7*inch)
    styles = getSampleStyleSheet()
    story  = []

    # --- Farben ---
    type_colors = {
        'Arbeit':        colors.HexColor('#E6FFE6'),
        'Sonderarbeit':  colors.HexColor('#FFE6FF'),
        'Urlaub':        colors.HexColor('#FFF2E6'),
        'Feiertag':      colors.HexColor('#E6F2FF'),
        'Zeitausgleich': colors.HexColor('#FFFFE6'),
        'Header':        colors.HexColor('#CCCCCC'),
    }
    delta_pos_color = colors.HexColor('#006600')
    delta_neg_color = colors.HexColor('#CC0000')

    table_style_base = [
        ('BACKGROUND',   (0, 0), (-1, 0), type_colors['Header']),
        ('TEXTCOLOR',    (0, 0), (-1, 0), colors.black),
        ('ALIGN',        (0, 0), (-1, -1), 'LEFT'),
        ('ALIGN',        (4, 1), (6, -1), 'RIGHT'),
        ('FONTNAME',     (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',     (0, 0), (-1, -1), 8),
        ('GRID',         (0, 0), (-1, -1), 0.5, colors.grey),
        ('LEFTPADDING',  (0, 0), (-1, -1), 4),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING',   (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING',(0, 0), (-1, -1), 4),
    ]

    saldo_prefix = "+" if s['saldo'] >= 0 else ""
    saldo_color  = colors.HexColor('#006600') if s['saldo'] >= 0 else colors.HexColor('#CC0000')

    # ── Deckblatt-Header ──────────────────────────────────────────
    # Name + Titel
    name_style = getSampleStyleSheet()['h1']
    story.append(Paragraph("Arbeitszeit Report", styles['h1']))
    story.append(Spacer(1, 0.05 * inch))

    # Mitarbeiter-Info-Tabelle
    info_data = [
        ['Mitarbeiter:',  user_name,
         'Erstellt am:',  datetime.now().strftime(DATE_FORMAT_DISPLAY + ' ' + TIME_FORMAT)],
        ['Zeitraum:',
         f"{s['start_date'].strftime(DATE_FORMAT_DISPLAY)} – {today.strftime(DATE_FORMAT_DISPLAY)}",
         'Wochenarbeitszeit:', f"{WEEKLY_HOURS:.1f} h  (Tagessoll: {DAILY_HOURS:.1f} h)"],
    ]
    info_style = [
        ('FONTNAME',     (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME',     (2, 0), (2, -1), 'Helvetica-Bold'),
        ('FONTSIZE',     (0, 0), (-1, -1), 9),
        ('LEFTPADDING',  (0, 0), (-1, -1), 4),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING',   (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING',(0, 0), (-1, -1), 3),
        ('BACKGROUND',   (0, 0), (-1, -1), colors.HexColor('#F5F5F5')),
        ('BOX',          (0, 0), (-1, -1), 0.5, colors.grey),
        ('INNERGRID',    (0, 0), (-1, -1), 0.3, colors.lightgrey),
    ]
    info_table = Table(info_data, colWidths=[1.2*inch, 2.2*inch, 1.4*inch, 2.0*inch])
    info_table.setStyle(TableStyle(info_style))
    story.append(info_table)
    story.append(Spacer(1, 0.12 * inch))

    # Gesamtsaldo-Box
    saldo_data = [
        ['Soll', 'Ist (brutto)', 'Pausenabzug', 'Ist (netto)', 'Zuschläge', 'GESAMTSALDO'],
        [
            f"{s['soll']:.2f} h",
            f"{s['ist_brutto']:.2f} h",
            f"-{s['pausen_abzug']:.2f} h",
            f"{s['ist_netto']:.2f} h",
            f"+{s['zuschlag']:.2f} h",
            f"{saldo_prefix}{s['saldo']:.2f} h"
        ]
    ]
    saldo_style = [
        ('BACKGROUND',   (0, 0), (-1, 0), colors.HexColor('#1a1a2e')),
        ('TEXTCOLOR',    (0, 0), (-1, 0), colors.white),
        ('BACKGROUND',   (5, 1), (5, 1), saldo_color),
        ('TEXTCOLOR',    (5, 1), (5, 1), colors.white),
        ('FONTNAME',     (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTNAME',     (5, 1), (5, 1), 'Helvetica-Bold'),
        ('FONTSIZE',     (0, 0), (-1, -1), 9),
        ('ALIGN',        (0, 0), (-1, -1), 'CENTER'),
        ('GRID',         (0, 0), (-1, -1), 0.5, colors.grey),
        ('LEFTPADDING',  (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING',   (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING',(0, 0), (-1, -1), 5),
    ]
    saldo_table = Table(saldo_data, colWidths=[1.1*inch]*6)
    saldo_table.setStyle(TableStyle(saldo_style))
    story.append(saldo_table)
    story.append(Spacer(1, 0.3 * inch))

    # ── Monatstabellen ────────────────────────────────────────────
    for month_year in sorted(monthly_data.keys()):
        try:
            month_name = datetime.strptime(month_year, '%Y-%m').strftime('%B %Y')
        except ValueError:
            month_name = month_year
        # start each month on a new page (except the first)
        if story:
            story.append(PageBreak())

        # Monatssaldo berechnen
        month_soll = month_ist = month_pause = month_zuschlag = 0.0
        for entry in monthly_data[month_year]:
            try:
                ed = datetime.strptime(entry['Datum'], DATE_FORMAT_INTERNAL).date()
            except ValueError:
                continue
            typ       = entry.get('Typ', '')
            dauer_str = entry.get('Dauer', '')
            di        = entry['Datum']

            if ed.weekday() < 5 and di not in PUBLIC_HOLIDAYS and di not in holidays:
                if typ != 'Sonderarbeit':
                    month_soll += DAILY_HOURS

            if typ in ('Arbeit', 'Sonderarbeit') and dauer_str:
                try:
                    brutto = float(dauer_str)
                    netto  = calculate_netto_hours(brutto)
                    month_ist += brutto
                    if brutto > BREAK_THRESHOLD_HOURS:
                        month_pause += BREAK_DURATION_HOURS
                    if typ == 'Sonderarbeit':
                        dt = get_day_type_info(di, holidays)
                        month_zuschlag += apply_surcharge(netto, dt) - netto
                except ValueError:
                    pass
            elif typ == 'Urlaub':
                month_ist += DAILY_HOURS

        month_netto  = month_ist - month_pause
        month_gesamt = month_netto + month_zuschlag
        month_saldo  = month_gesamt - month_soll
        ms_prefix    = "+" if month_saldo >= 0 else ""
        ms_color     = colors.HexColor('#006600') if month_saldo >= 0 else colors.HexColor('#CC0000')

        # Monats-Header mit Saldo-Zusammenfassung
        story.append(Paragraph(f"<b>{month_name}</b>", styles['h2']))
        story.append(Spacer(1, 0.05 * inch))

        ms_data = [
            ['Monat-Soll', 'Ist (brutto)', 'Pause', 'Ist (netto)', 'Zuschläge', 'Monat-Saldo'],
            [
                f"{month_soll:.2f} h",
                f"{month_ist:.2f} h",
                f"-{month_pause:.2f} h",
                f"{month_netto:.2f} h",
                f"+{month_zuschlag:.2f} h",
                f"{ms_prefix}{month_saldo:.2f} h"
            ]
        ]
        ms_style = [
            ('BACKGROUND',   (0, 0), (-1, 0), colors.HexColor('#444444')),
            ('TEXTCOLOR',    (0, 0), (-1, 0), colors.white),
            ('BACKGROUND',   (5, 1), (5, 1), ms_color),
            ('TEXTCOLOR',    (5, 1), (5, 1), colors.white),
            ('FONTNAME',     (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTNAME',     (5, 1), (5, 1), 'Helvetica-Bold'),
            ('FONTSIZE',     (0, 0), (-1, -1), 8),
            ('ALIGN',        (0, 0), (-1, -1), 'CENTER'),
            ('GRID',         (0, 0), (-1, -1), 0.5, colors.grey),
            ('LEFTPADDING',  (0, 0), (-1, -1), 4),
            ('RIGHTPADDING', (0, 0), (-1, -1), 4),
            ('TOPPADDING',   (0, 0), (-1, -1), 4),
            ('BOTTOMPADDING',(0, 0), (-1, -1), 4),
        ]
        ms_table = Table(ms_data, colWidths=[1.1*inch]*6)
        ms_table.setStyle(TableStyle(ms_style))
        story.append(ms_table)
        story.append(Spacer(1, 0.08 * inch))

        # Detailtabelle
        table_data          = [['Datum', 'Typ', 'Start', 'Ende', 'Dauer (h)', 'Zuschlag', 'Tages-Δ']]
        current_table_style = list(table_style_base)

        # Detect dates with multiple entries so we can render each interval as its own row
        date_counts = {}
        for e in monthly_data[month_year]:
            date_counts[e.get('Datum', '')] = date_counts.get(e.get('Datum', ''), 0) + 1

        # helper to lighten a HexColor by blending with white
        def _lighten_color(hexcol, amount):
            try:
                r, g, b = int(hexcol.hexval[1:3], 16), int(hexcol.hexval[3:5], 16), int(hexcol.hexval[5:7], 16)
            except Exception:
                return hexcol
            r = int(r + (255 - r) * amount)
            g = int(g + (255 - g) * amount)
            b = int(b + (255 - b) * amount)
            return colors.HexColor('#{:02X}{:02X}{:02X}'.format(r, g, b))

        # track per-date occurrence index so we can give the first interval a base color
        occ_index_for_date = {}
        for entry in monthly_data[month_year]:
            di = entry.get('Datum', '')
            occ_index = occ_index_for_date.get(di, 0)
            occ_index_for_date[di] = occ_index + 1

            multiple_intervals = date_counts.get(di, 0) > 1

            # For multiple intervals we show the interval duration in the Tages-Δ column
            if multiple_intervals:
                delta_val = 0.0
                delta_str = sanitize_for_pdf(entry.get('Dauer', ''), max_len=20)
                zuschlag_info = ''
            else:
                delta_val, delta_str, zuschlag_info = compute_day_delta(entry, holidays)

            table_data.append([
                sanitize_for_pdf(to_display(entry.get('Datum', '')), max_len=20),
                sanitize_for_pdf(entry.get('Typ', ''), max_len=20),
                sanitize_for_pdf(entry.get('Startzeit', ''), max_len=8),
                sanitize_for_pdf(entry.get('Endzeit', ''), max_len=8),
                sanitize_for_pdf(entry.get('Dauer', ''), max_len=10),
                sanitize_for_pdf(zuschlag_info, max_len=20),
                sanitize_for_pdf(delta_str, max_len=20)
            ])

            row_index    = len(table_data) - 1
            day_type_key = entry.get('Typ', 'Arbeit')

            # Determine background color. If the date has multiple intervals, derive
            # a family of shades: the first interval keeps the base type color, later
            # intervals get progressively lighter shades.
            if day_type_key in type_colors:
                base_col = type_colors[day_type_key]
                if multiple_intervals:
                    shade_amount = min(0.0 + 0.20 * (occ_index if occ_index > 0 else 0), 0.65)
                    bg_col = _lighten_color(base_col, shade_amount)
                else:
                    bg_col = base_col
                current_table_style.append(('BACKGROUND', (0, row_index), (-1, row_index), bg_col))

            # Color the Tages-Δ cell as before when it's an actual day delta
            if not multiple_intervals:
                if delta_val > 0:
                    current_table_style.append(('TEXTCOLOR', (6, row_index), (6, row_index), delta_pos_color))
                    current_table_style.append(('FONTNAME',  (6, row_index), (6, row_index), 'Helvetica-Bold'))
                elif delta_val < 0:
                    current_table_style.append(('TEXTCOLOR', (6, row_index), (6, row_index), delta_neg_color))
                    current_table_style.append(('FONTNAME',  (6, row_index), (6, row_index), 'Helvetica-Bold'))

        col_widths = [1.05*inch, 1.05*inch, 0.65*inch, 0.65*inch, 0.75*inch, 0.85*inch, 0.85*inch]
        table = Table(table_data, colWidths=col_widths)
        table.setStyle(TableStyle(current_table_style))
        story.append(table)
        story.append(Spacer(1, 0.35 * inch))

    doc.build(story)
    print(f"PDF-Report erfolgreich erstellt: {pdf_filename}")


def show_holidays_current_year():
    cfg = load_config()
    cfg_map = cfg.get('holidays') if isinstance(cfg, dict) else {}
    current_year = str(date.today().year)
    holidays = {d: n for d, n in (cfg_map or {}).items() if d.startswith(current_year)}
    if not holidays:
        print(f"Keine Feiertage für {current_year} in {CONFIG_FILE} gefunden.")
        return
    print(f"\nFeiertage aus {CONFIG_FILE} für {current_year}:")
    for d in sorted(holidays.keys()):
        print(f"  {to_display(d)}: {holidays[d]}")
    print()


def import_holidays_from_csv(path=None, merge_strategy='ask'):
    """Importiert Feiertage aus einer CSV-Datei in `config.json` (`holidays`).

    Erwartetes Format: zwei Spalten (Datum, Name). Datum kann intern (YYYY-MM-DD)
    oder Anzeigeformat (DD.MM.YYYY) sein. Trennzeichen werden mittels csv.Sniffer erkannt.
    Beim Import werden vorhandene Einträge für dieselben Daten überschrieben.
    """
    if not path:
        path = input('Pfad zur Feiertags-CSV (z.B. holidays.csv): ').strip()
    if not os.path.exists(path):
        print(f"Datei nicht gefunden: {path}")
        return

    with open(path, 'r', encoding='utf-8') as f:
        sample = f.read(2048)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample)
            reader = csv.reader(f, dialect)
        except Exception:
            # Fallback: default csv reader (comma)
            f.seek(0)
            reader = csv.reader(f)

        cfg = load_config()
        if not isinstance(cfg, dict):
            cfg = {'name': '', 'holidays': {}}
        mh = cfg.get('holidays') or {}

        rows = [r for r in reader if r]
        imported = 0
        skipped = 0
        parsed = []
        for row in rows:
            if not row:
                continue
            # tolerate header rows
            if len(row) >= 2 and row[0].lower().strip() in ('datum', 'date'):
                continue
            # take first two columns
            try:
                raw_date = row[0].strip()
                name = row[1].strip() if len(row) > 1 else 'Feiertag'
            except Exception:
                skipped += 1
                continue

            # try internal format first
            internal = None
            if len(raw_date) == 10 and raw_date[4] == '-':
                internal = raw_date
            else:
                # try display -> internal
                internal = to_internal(raw_date)

            if not internal:
                skipped += 1
                continue

            parsed.append((internal, name))

        if not parsed:
            print(f"Keine gültigen Feiertage in {path} gefunden.")
            return

        # detect conflicts: same date different name, or same name different date
        existing_dates = set(mh.keys())
        existing_names = {v: k for k, v in mh.items()}  # name->date
        imported_map = {d: n for d, n in parsed}

        date_conflicts = [(d, imported_map[d], mh.get(d)) for d in imported_map if d in existing_dates and mh.get(d) != imported_map[d]]
        name_conflicts = [(d, imported_map[d], existing_names.get(imported_map[d])) for d in imported_map if imported_map[d] in existing_names and existing_names.get(imported_map[d]) != d]

        if date_conflicts or name_conflicts:
            # conflicts exist
            # create a backup of current config before potentially destructive changes
            bkp = backup_config()
            if bkp:
                print(f'Config gesichert: {bkp}')
            if merge_strategy == 'overwrite_all':
                mh = imported_map.copy()
                imported = len(imported_map)
                skipped = 0
            elif merge_strategy == 'keep_existing':
                # only add non-conflicting entries
                for d, n in imported_map.items():
                    if d in existing_dates or n in existing_names:
                        skipped += 1
                        continue
                    mh[d] = n
                    imported += 1
            elif merge_strategy == 'ask_each':
                for d, n in imported_map.items():
                    d_conflict = d in existing_dates and mh.get(d) != n
                    n_conflict = n in existing_names and existing_names.get(n) != d
                    if d_conflict or n_conflict:
                        prompt = f"Konflikt für {to_display(d)}: importiert='{n}' vs vorhanden='{mh.get(d) or existing_names.get(n)}'. Überschreiben? (j/n): "
                        if ask_yes(prompt):
                            mh[d] = n
                            imported += 1
                        else:
                            skipped += 1
                    else:
                        if d not in mh:
                            mh[d] = n
                            imported += 1
            else:
                # interactive ask for global overwrite
                if ask_yes(f"Konflikte beim Import gefunden ({len(date_conflicts)+len(name_conflicts)}). Alle importierten Feiertage überschreiben? (j/n): "):
                    mh = imported_map.copy()
                    imported = len(imported_map)
                    skipped = 0
                else:
                    # ask per conflict
                    for d, n in parsed:
                        d_conflict = d in existing_dates and mh.get(d) != n
                        n_conflict = n in existing_names and existing_names.get(n) != d
                        if d_conflict or n_conflict:
                            prompt = f"Konflikt für {to_display(d)}: importiert='{n}' vs vorhanden='{mh.get(d) or existing_names.get(n)}'. Überschreiben? (j/n): "
                            if ask_yes(prompt):
                                mh[d] = n
                                imported += 1
                            else:
                                skipped += 1
                        else:
                            if d not in mh:
                                mh[d] = n
                                imported += 1
        else:
            # no conflicts, merge/overwrite by date
            for d, n in parsed:
                mh[d] = n
                imported += 1

        cfg['holidays'] = mh
        save_config(cfg)
        print(f"Import abgeschlossen: {imported} Feiertage importiert, {skipped} Zeilen übersprungen.")


def export_holidays_to_csv(path=None, date_style='display'):
    """Exportiert die aktuell in `config.json['holidays']` gespeicherten Feiertage als CSV.

    `date_style` kann 'display' (TT.MM.JJJJ) oder 'internal' (YYYY-MM-DD) sein.
    """
    cfg = load_config()
    mh = cfg.get('holidays') or {}
    if not mh:
        print(f"Keine Feiertage in {CONFIG_FILE} zum Export gefunden.")
        return

    if not path:
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        path = f"holidays_export_{ts}.csv"

    try:
        with open(path, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Datum', 'Name'])
            for d in sorted(mh.keys()):
                name = mh.get(d, '')
                if date_style == 'display':
                    out_date = to_display(d)
                else:
                    out_date = d
                writer.writerow([out_date, name])
        print(f"Feiertage exportiert: {path}")
    except Exception as e:
        print(f"Fehler beim Export: {e}")

# --- Hauptmenü ---

def main_menu():
    print_header()
    print("1. Arbeitsbeginn erfassen (jetzt)")
    print("2. Arbeitsende erfassen (jetzt)")
    print("3. Zeitsaldo anzeigen")
    print("4. Report als PDF erstellen")
    print("5. Arbeitsbeginn korrigieren")
    print("6. Arbeitsende korrigieren")
    print("7. Einstellungen / Optionen")
    print("8. Beenden")
    print("-" * 40)

    choice = input("Wähle eine Option (1-8): ")

    if choice == '1':
        start_work()
    elif choice == '2':
        end_work()
    elif choice == '3':
        calculate_time_balance()
    elif choice == '4':
        generate_pdf_report()
    elif choice == '5':
        edit_work_start()
    elif choice == '6':
        edit_work_end()
    elif choice == '7':
        settings_menu()
    elif choice == '8':
        print("Auf Wiedersehen!")
        return False
    else:
        print("Ungültige Eingabe. Bitte wähle eine Zahl aus dem Menü.")
    return True


def settings_menu():
    print("\n--- Einstellungen / Optionen ---")
    print("1. Urlaubstag eintragen")
    print("2. Feiertag eintragen (Config)")
    print("3. Zeitausgleichstag eintragen")
    print("4. Arbeitsbeginn/Ende korrigieren")
    print("5. Sonderarbeit erfassen (Sa/So/Feiertag)")
    print("6. Feiertage anzeigen (aktuelles Jahr)")
    print("7. Feiertage aus CSV importieren")
    print("8. Config-Backup wiederherstellen")
    print("9. Name ändern")
    print("0. Zurück")
    print("10. Feiertage exportieren (CSV)")

    choice = input('Wähle eine Option (0-10): ')
    if choice == '1':
        add_special_day('Urlaub')
    elif choice == '2':
        add_special_day('Feiertag')
    elif choice == '3':
        add_special_day('Zeitausgleich')
    elif choice == '4':
        # sub-menu to choose start or end
        print('1. Arbeitsbeginn korrigieren/nachtragen')
        print('2. Arbeitsende korrigieren/nachtragen')
        sub = input('Wähle (1-2): ')
        if sub == '1':
            edit_work_start()
        elif sub == '2':
            edit_work_end()
    elif choice == '5':
        add_special_work_day()
    elif choice == '6':
        show_holidays_current_year()
    elif choice == '7':
        import_holidays_from_csv()
    elif choice == '10':
        export_holidays_to_csv()
    elif choice == '8':
        restore_config_backup()
    elif choice == '9':
        set_user_name()
    elif choice == '0':
        return
    else:
        print('Ungültige Eingabe.')

if __name__ == "__main__":
    ensure_user_name()
    # ensure manual holidays are present in config.json (single source of truth)
    ensure_holidays_in_config()

    # Support quick desktop shortcuts that call the exe with --start-now / --end-now
    # These should perform the action immediately and exit without showing the menu.
    import argparse

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--start-now', action='store_true', help='Record start time now and exit')
    parser.add_argument('--end-now', action='store_true', help='Record end time now and exit')
    args, _ = parser.parse_known_args()

    if args.start_now:
        quick_start_action()
        sys.exit(0)
    if args.end_now:
        quick_end_action()
        sys.exit(0)

    running = True
    while running:
        running = main_menu()