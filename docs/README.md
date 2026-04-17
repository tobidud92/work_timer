# Work Timer — Bedienungsanleitung

Kurze Anleitung zur Nutzung des kleinen Arbeitszeit-Trackers.

Installation

- Lege ein virtuelles Environment an und installiere Abhängigkeiten (ReportLab und optional `prompt_toolkit`):

CI: [![CI](https://github.com/tobidud92/work_timer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tobidud92/work_timer/actions/workflows/ci.yml)

# Work Timer — Bedienungsanleitung

Kurze Anleitung zur Nutzung des kleinen Arbeitszeit-Trackers.

Installation

- Lege ein virtuelles Environment an und installiere Abhängigkeiten (ReportLab und optional `prompt_toolkit`):

```powershell
python -m venv .venv
& .venv\Scripts\Activate.ps1
pip install -r code\requirements.txt
```

Hinweis zur interaktiven Datumsauswahl

- Für die interaktive Datumsauswahl (Up/Down zum Wechseln des Datums) wird `prompt_toolkit` benötigt. `code\requirements.txt` listet `prompt_toolkit>=3.0`.
- Wenn du eine Windows-Exe mit PyInstaller baust, installiere vorher die Anforderungen in der Build-Umgebung, damit PyInstaller `prompt_toolkit` analysieren und in die Executable einbinden kann.

Start

- Starte das Script (aus dem Projekt-Root):

```powershell
& .venv\Scripts\Activate.ps1
python code\work_timer.py
```

Hauptmenü (Kurzüberblick)

- `1` Arbeitsbeginn erfassen (jetzt)
- `2` Arbeitsende erfassen (jetzt)
- `3` Zeitsaldo anzeigen
- `4` Report als PDF erstellen
- `5` Arbeitsbeginn korrigieren (korrigieren / nachtragen)
- `6` Arbeitsende korrigieren (korrigieren / nachtragen)
- `7` Einstellungen / Optionen (Urlaub, Feiertag, Korrekturen, Import, Backup)
- `8` Beenden

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

Interaktive Datums- und Zeiteingabe

- Wenn `prompt_toolkit` installiert ist, zeigt die Datumseingabe eine interaktive Maske an, in der `Up`/`Down` das Datum ändert und `Left`/`Right` den Cursor bewegt. Ohne `prompt_toolkit` wird ein einfacher Eingabeprompt mit einem vorausgefüllten Datum angezeigt.
- Zeit-Eingaben (Format `HH:MM`) werden standardmäßig mit der aktuellen Zeit vorausgefüllt. Bei installiertem `prompt_toolkit` lassen sich Minuten per `Up`/`Down` anpassen.
 - Lässt du die Datumseingabe leer, wird standardmäßig das aktuelle Datum verwendet.

Quick‑Shortcuts (Desktop)

- `code\install.bat` ist der einfache Installer: es kopiert die benötigten Dateien nach `%USERPROFILE%\Documents\Arbeitszeit`, legt kleine wrapper-`.bat`-Dateien an (`kommen.bat` / `gehen.bat`) die die exe mit `--start-now` bzw. `--end-now` aufrufen, und erstellt Desktop-Shortcuts (`Kommen.lnk`, `Gehen.lnk`, `WorkTimer.lnk`) die auf diese Wrapper verweisen. Die Wrapper leiten stdout/stderr in Logdateien auf dem Desktop um (`work_timer_kommen_log.txt`, `work_timer_gehen_log.txt`).

- Alternativ gibt es `code\create_shortcuts.ps1` zum gezielten Anlegen von Shortcuts (z.B. wenn du die Exe bereits an einem bestimmten Ort hast):

```powershell
& .\create_shortcuts.ps1 -ExePath "C:\Path\To\dist\work_timer.exe"
```

Build / Exe erstellen

- Empfohlener Ablauf (aus Projekt-Root):

```powershell
& .venv\Scripts\Activate.ps1
pip install -r code\requirements.txt
cd code
..\.venv\Scripts\python.exe -m PyInstaller -F work_timer.py
```

- Wenn du eigene Hooks einbinden musst, kannst du PyInstaller mit `--additional-hooks-dir` aufrufen. Achte darauf, die Build-Umgebung so einzurichten, dass `prompt_toolkit` installiert ist, wenn du die interaktive Eingabe in der EXE erwartest.

- Wenn die EXE die interaktive Maske nicht zeigt, setzte beim Start in der Umgebung `FORCE_PROMPT_TOOLKIT=1` (Hilfreich beim Debuggen in gebauten Umgebungen).

Tests

- Unit-Tests liegen im Ordner `tests/`. Führe sie mit:

```powershell
& .venv\Scripts\Activate.ps1
python -m unittest discover -v tests
```

Wichtige Hinweise

- `config.json` ist die Single-Source-of-Truth für manuell eingetragene Feiertage (`holidays` mapping).
- Interaktive Ja/Nein-Abfragen akzeptieren `j` (Deutsch) oder `y` (Englisch).
- Beim CSV-Schreiben werden führende Zeichen (`=`, `+`, `-`, `@`) mit einem führenden `'` escaped, damit Tabellenprogramme keine Formeln ausführen.
- Schreiboperationen für Daten und Config sind atomar implementiert (Zwischendatei + `os.replace`).

Support

- Bei Bedarf kann das Tool zu SQLite migriert werden oder weitere Regionen/Feiertage ergänzt werden.
