# Work Timer — Bedienungsanleitung

Kurze Anleitung zur Nutzung des kleinen Arbeitszeit-Trackers.

Installation

- Lege ein virtuelles Environment an und installiere Abhängigkeiten (ReportLab):

```powershell
python -m venv .venv
& .venv\Scripts\Activate.ps1
pip install reportlab
```

Start

- Starte das Script:

```powershell
python work_timer.py
```

Hauptmenü (Kurzüberblick)

- `1` Arbeitsbeginn erfassen (jetzt)
- `2` Arbeitsende erfassen (jetzt)
- `3` Zeitsaldo anzeigen
- `4` Report als PDF erstellen
- `5` Einstellungen / Optionen (Urlaub, Feiertag, Korrekturen, Import, Backup)
- `6` Beenden

Einstellungen / Optionen (im Untermenü)

- `1` Urlaubstag eintragen
- `2` Feiertag eintragen (speichert in `config.json`)
- `3` Zeitausgleichstag eintragen
- `4` Arbeitsbeginn/Ende korrigieren
- `5` Sonderarbeit erfassen (Sa/So/Feiertag)
- `6` Feiertage anzeigen (aktuelles Jahr)
- `7` Feiertage aus CSV importieren (two-column CSV: `Datum,Name`)
- `8` Config-Backup wiederherstellen
- `9` Name ändern
- `0` Zurück

Wichtige Hinweise

- `config.json` ist die Single-Source-of-Truth für manuell eingetragene Feiertage (`holidays` mapping).
- Interaktive Ja/Nein-Abfragen akzeptieren `j` (Deutsch) oder `y` (Englisch).
- Beim CSV-Schreiben werden führende Zeichen (`=`, `+`, `-`, `@`) mit einem führenden `'` escaped, damit Tabellenprogramme keine Formeln ausführen.
- Schreiboperationen für Daten und Config sind atomar implementiert (Zwischendatei + `os.replace`).

Tests

- Unit-Tests liegen im Ordner `tests/`. Führe sie mit:

```powershell
python -m unittest discover tests
```

Support

- Bei Bedarf kann das Tool zu SQLite migriert werden oder weitere Regionen/Feiertage ergänzt werden.