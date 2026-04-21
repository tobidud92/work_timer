# Work Timer — Bedienungsanleitung

[![CI](https://github.com/tobidud92/work_timer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tobidud92/work_timer/actions/workflows/ci.yml)

Kurze Anleitung zur Nutzung des kleinen Arbeitszeit-Trackers.

---

## Installation

### Option A — Fertige Windows-Exe (empfohlen)

1. Lade das neueste Artefakt `WorkTimerInstall.zip` von der [CI-Seite](https://github.com/tobidud92/work_timer/actions/workflows/ci.yml) herunter (letzter grüner Lauf → Artefakte) oder das offizielle Release-ZIP von der [Releases-Seite](https://github.com/tobidud92/work_timer/releases).
2. Entpacke das ZIP an einen beliebigen Ort.
3. Doppelklicke auf `install.bat`. Das Skript:
   - Entsperrt alle Dateien (hebt den Windows-Download-Block auf)
   - Kopiert `work_timer.exe` und Icons nach `%USERPROFILE%\Documents\Arbeitszeit`
   - Erstellt Desktop-Shortcuts `Kommen.lnk`, `Gehen.lnk`, `WorkTimer.lnk`

### Option B — Aus dem Quellcode (Entwickler)

```powershell
python -m venv .venv
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python src\work_timer.py
```

---

## Start

```powershell
& .venv\Scripts\Activate.ps1
python src\work_timer.py
```

Oder direkt die installierte Exe über den Desktop-Shortcut `WorkTimer` starten.

---

## Hauptmenü

| Taste | Funktion |
|-------|----------|
| `1` | Arbeitsbeginn erfassen (jetzt) |
| `2` | Arbeitsende erfassen (jetzt) |
| `3` | Zeitsaldo anzeigen |
| `4` | Report als PDF erstellen |
| `5` | Arbeitsbeginn korrigieren (korrigieren / nachtragen) |
| `6` | Arbeitsende korrigieren (korrigieren / nachtragen) |
| `7` | Einstellungen / Optionen |
| `8` | Beenden |

---

## Einstellungen / Optionen (Untermenü 7)

| Taste | Funktion |
|-------|----------|
| `1` | Urlaubstag eintragen |
| `2` | Feiertag eintragen (speichert in `config.json`) |
| `3` | Zeitausgleichstag eintragen |
| `4` | Arbeitsbeginn/Ende korrigieren |
| `5` | Sonderarbeit erfassen (Sa/So/Feiertag) |
| `6` | Feiertage anzeigen (aktuelles Jahr) |
| `7` | Feiertage aus CSV importieren (`Datum,Name`) |
| `8` | Config-Backup wiederherstellen |
| `9` | Name ändern |
| `0` | Zurück |

---

## Quick-Shortcuts (Desktop)

Nach der Installation gibt es drei Desktop-Verknüpfungen:

| Shortcut | Aktion |
|----------|--------|
| `Kommen.lnk` | Startet `work_timer.exe --start-now` und zeigt eine Bestätigungsmeldung |
| `Gehen.lnk` | Startet `work_timer.exe --end-now` und zeigt eine Bestätigungsmeldung |
| `WorkTimer.lnk` | Öffnet das interaktive Hauptmenü |

Die Quick-Action-Shortcuts öffnen ein minimiertes Konsolenfenster, führen die Aktion durch, zeigen eine **MessageBox** mit Feedback (z. B. „Eingecheckt: 21.04.2026 um 08:00") und beenden sich dann automatisch.

---

## Interaktive Datums- und Zeiteingabe

- Mit installiertem `prompt_toolkit` zeigt die Datumseingabe eine interaktive Maske:
  - `Up` / `Down` wechselt den Tag
  - `Left` / `Right` bewegt den Cursor für manuelle Eingabe
- Zeiteingaben (Format `HH:MM`) werden mit der aktuellen Zeit vorausgefüllt; `Up`/`Down` ändert die Minuten.
- Lässt du die Datumseingabe leer, wird automatisch das heutige Datum verwendet.

---

## Build (Exe selbst erstellen)

```powershell
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
pyinstaller install\work_timer.spec
```

Die Exe landet unter `dist\work_timer.exe`.

---

## Tests

```powershell
& .venv\Scripts\Activate.ps1
python -m pytest
```

---

## Wichtige Hinweise

- `config.json` ist die einzige Quelle für manuell eingetragene Feiertage (`holidays`-Mapping).
- Interaktive Ja/Nein-Abfragen akzeptieren `j` (Deutsch) oder `y` (Englisch).
- Schreiboperationen für Daten und Config sind atomar (`os.replace`), sodass keine korrupten Dateien entstehen.
- Beim CSV-Schreiben werden Zeichen wie `=`, `+`, `-`, `@` am Zeilenanfang escaped, um CSV-Injection in Tabellenkalkulationen zu verhindern.
