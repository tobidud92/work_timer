import csv
import json
import builtins


def test_vacation_range_overwrite_all(tmp_path, monkeypatch):
    import src.work_timer as wt

    # isolate data and config in tmp_path
    wt.CSV_FILE = str(tmp_path / 'arbeitszeiten.csv')
    wt.CONFIG_FILE = str(tmp_path / 'config.json')

    # write empty config (no manual holidays)
    with open(wt.CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump({'name': '', 'holidays': {}}, f)

    # create initial CSV with a Zeitausgleich (blocking) and an Arbeit (soft conflict)
    rows = [
        {'Datum': '2026-04-20', 'Typ': 'Zeitausgleich', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
        {'Datum': '2026-04-21', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '17:00', 'Dauer': '8.00', 'Kommentar': ''},
    ]
    with open(wt.CSV_FILE, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar'])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    # ensure interactive input uses builtins.input
    monkeypatch.setattr(wt, '_prompt', None)

    # sequence of inputs:
    # 1) Datum für Urlaub (ignored for range but required by function)
    # 2) Kommentar
    # 3) Urlaubsbeginn
    # 4) Urlaubsende
    # 5) Wahl: 'a' = Alle überschreiben (soft conflicts)
    inputs = iter(['20.04.2026', 'Test Urlaub', '20.04.2026', '22.04.2026', 'a'])
    monkeypatch.setattr(builtins, 'input', lambda prompt='': next(inputs))

    # run the interactive function
    wt.add_special_day('Urlaub')

    # load resulting data
    data = wt.load_data()
    mapping = {e['Datum']: e for e in data}

    # 20 should remain Zeitausgleich (hard conflict not overwritten)
    assert mapping['2026-04-20']['Typ'] == 'Zeitausgleich'

    # 21 should have been overwritten to Urlaub
    assert mapping['2026-04-21']['Typ'] == 'Urlaub'

    # 22 should have been added as Urlaub
    assert mapping['2026-04-22']['Typ'] == 'Urlaub'


def test_vacation_range_per_day_choice(tmp_path, monkeypatch):
    import src.work_timer as wt

    wt.CSV_FILE = str(tmp_path / 'arbeitszeiten.csv')
    wt.CONFIG_FILE = str(tmp_path / 'config.json')

    with open(wt.CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump({'name': '', 'holidays': {}}, f)

    rows = [
        {'Datum': '2026-04-20', 'Typ': 'Zeitausgleich', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
        {'Datum': '2026-04-21', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '17:00', 'Dauer': '8.00', 'Kommentar': ''},
    ]
    with open(wt.CSV_FILE, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar'])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    monkeypatch.setattr(wt, '_prompt', None)

    # choose per-day prompt ('e') and answer 'y' to overwrite the soft conflict on 2026-04-21
    inputs = iter(['20.04.2026', 'Test Urlaub', '20.04.2026', '22.04.2026', 'e', 'y'])
    import builtins
    monkeypatch.setattr(builtins, 'input', lambda prompt='': next(inputs))

    wt.add_special_day('Urlaub')

    data = wt.load_data()
    mapping = {e['Datum']: e for e in data}

    assert mapping['2026-04-20']['Typ'] == 'Zeitausgleich'
    assert mapping['2026-04-21']['Typ'] == 'Urlaub'
    assert mapping['2026-04-22']['Typ'] == 'Urlaub'


def test_vacation_range_skip_soft_conflicts(tmp_path, monkeypatch):
    import src.work_timer as wt

    wt.CSV_FILE = str(tmp_path / 'arbeitszeiten.csv')
    wt.CONFIG_FILE = str(tmp_path / 'config.json')

    with open(wt.CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump({'name': '', 'holidays': {}}, f)

    rows = [
        {'Datum': '2026-04-20', 'Typ': 'Zeitausgleich', 'Startzeit': '', 'Endzeit': '', 'Dauer': '', 'Kommentar': ''},
        {'Datum': '2026-04-21', 'Typ': 'Arbeit', 'Startzeit': '09:00', 'Endzeit': '17:00', 'Dauer': '8.00', 'Kommentar': ''},
    ]
    with open(wt.CSV_FILE, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['Datum', 'Typ', 'Startzeit', 'Endzeit', 'Dauer', 'Kommentar'])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    monkeypatch.setattr(wt, '_prompt', None)

    # choose 'n' to not overwrite soft conflicts
    inputs = iter(['20.04.2026', 'Test Urlaub', '20.04.2026', '22.04.2026', 'n'])
    import builtins
    monkeypatch.setattr(builtins, 'input', lambda prompt='': next(inputs))

    wt.add_special_day('Urlaub')

    data = wt.load_data()
    mapping = {e['Datum']: e for e in data}

    assert mapping['2026-04-20']['Typ'] == 'Zeitausgleich'
    # soft conflict should remain
    assert mapping['2026-04-21']['Typ'] == 'Arbeit'
    # free day should be added
    assert mapping['2026-04-22']['Typ'] == 'Urlaub'
