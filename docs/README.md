# Work Timer — Bedienungsanleitung

Kurze Anleitung zur Nutzung des kleinen Arbeitszeit-Trackers.

Installation

- Lege ein virtuelles Environment an und installiere Abhängigkeiten (ReportLab):

```powershell
python -m venv .venv
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Hinweis zur interaktiven Datumsauswahl

- Für die interaktive Datumsauswahl (Up/Down zum Wechseln des Datums) wird
	`prompt_toolkit` benötigt. `requirements.txt` enthält `prompt_toolkit>=3.0`.
- Wenn du eine Windows-Exe mit PyInstaller baust, installiere vorher die
	Anforderungen in der Build-Umgebung, damit PyInstaller `prompt_toolkit`
	analysieren und in die Executable einbinden kann.

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

Hinweis zu Korrekturen

 - Wenn `prompt_toolkit` installiert ist, zeigt die Datumseingabe eine interaktive
	 Maske an, in der `Up`/`Down` das Datum ändert und `Left`/`Right` den Cursor
	 bewegt. Ohne `prompt_toolkit` wird ein einfaches Eingabefeld mit einem
	 vorausgefüllten Datum in eckigen Klammern angezeigt.
 - Lässt du die Datumseingabe leer, wird automatisch das aktuelle Datum vorausgefüllt.

Interaktive Zeit­eingabe

- Bei Zeit-Eingaben (Format `HH:MM`) wird standardmäßig die aktuelle Zeit
	vorausgefüllt. Wenn `prompt_toolkit` verfügbar ist, kannst du dort mit
	`Up`/`Down` die Minuten erhöhen bzw. verringern und mit `Left`/`Right` den
	Cursor bewegen. In der Standardeinstellung erhöhen/vermindern `Up`/`Down`
	die Zeit um 1 Minute. Ohne `prompt_toolkit` zeigt das Programm einen
	einfachen Eingabeprompt mit dem Default in eckigen Klammern.

Quick‑Shortcuts (Desktop)

- Im Ordner `code/` liegt `create_shortcuts.ps1`, das zwei Shortcuts anlegt:
	- `kommen.lnk` — ruft die EXE mit `--start-now` auf und erfasst sofort einen Arbeitsbeginn
	- `gehen.lnk`  — ruft die EXE mit `--end-now` auf und schließt die zuletzt offene Schicht
- Verhalten beim Klicken:
	- `kommen`: Legt einen neuen Start an. Falls bereits ein offener Start existiert,
		fragt die App (Überschreiben / Neuer Eintrag / Abbrechen).
	- `gehen`: Schließt die zuletzt offene Schicht. Falls keine offene Schicht existiert,
		warnt die App und legt keinen neuen Eintrag an.

Automatisierte / stille Ausführung

- Zur Unterdrückung von MessageBoxen (z. B. in Tests oder Scripted Runs) setze
	`SUPPRESS_CONFIRMATION=1` oder benutze das CLI‑Flag `--no-confirm`.
- Um `prompt_toolkit` in einer gebauten EXE zu erzwingen (falls nötig), setze
	`FORCE_PROMPT_TOOLKIT=1` vor dem Start der EXE.

Fehlerbehebung beim Erstellen der Exe

- Baue die Exe aus derselben virtuellen Umgebung, in der `prompt_toolkit`
	installiert ist. Beispiel:

```powershell
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
pyinstaller --onefile --console --additional-hooks-dir=code\pyinstaller-hooks code\work_timer.py
```

- Falls die Exe die interaktive Maske nicht zeigt, kannst du beim Start die
	Umgebung variablen setzen, um Verhalten und Debug-Ausgabe zu erzwingen:

```powershell
$env:FORCE_PROMPT_TOOLKIT = '1'      # erzwingt Verwendung von prompt_toolkit
$env:DEBUG_DATEPICKER = '1'         # zeigt Runtime-Debug-Infos
.\dist\work_timer.exe
```

Shortcuts auf dem Desktop anlegen

Im Ordner `code/` liegt ein kleines PowerShell-Skript `create_shortcuts.ps1`, das zwei
Shortcuts auf dem aktuellen Benutzer-Desktop anlegt:

- `kommen.lnk` — startet die exe mit `--start-now` und erfasst sofort Arbeitsbeginn.
- `gehen.lnk` — startet die exe mit `--end-now` und erfasst sofort Arbeitsende.

Beispiel (aus `code`):

```powershell
& .\create_shortcuts.ps1 -ExePath "C:\Path\To\dist\work_timer.exe"
```

Das Skript versucht standardmäßig `dist\work_timer.exe` relativ zum Skriptverzeichnis.

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