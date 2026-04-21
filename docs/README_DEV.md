# work_timer — Developer Documentation

This document explains the internals of `work_timer.py`, configuration layout and where to extend functionality.

## Overview

- `work_timer.py` is a small CLI application to track work start/end, special days and generate monthly PDF reports.
- Data storage:
  - Timesheet data: `arbeitszeiten.csv` (CSV with header columns `Datum,Typ,Startzeit,Endzeit,Dauer,Kommentar`).
  - Configuration: `config.json` (JSON object with keys `name` and `holidays`).

## Key concepts and modules

- `load_config()` / `save_config()` — atomic JSON read/write. Config contains:
  - `name` (string)
  - `holidays` (object mapping `YYYY-MM-DD` → `Name des Feiertags`)

- `load_data()` / `save_data()` — CSV read/write. `save_data()` sanitizes fields to avoid CSV injection and writes atomically.

- `compute_saldo(data)` — computes working-time balance (Soll/Ist) using:
  - `PUBLIC_HOLIDAYS` (computed for next 10 years)
  - `config.json` → `holidays` as single source of truth for manually defined holidays.

- `generate_pdf_report()` — creates a multi-page PDF (one month per page). Text passed to ReportLab is sanitized via `sanitize_for_pdf()`.

## UI / Usability notes

- The CLI uses a centralized `ask_yes()` helper for yes/no prompts. It accepts `j` (Deutsch) or `y` (English).
- The main menu header is rendered via `print_header()` which shows the configured user name if present.

Interactive date & time picker

- The project provides an interactive date picker (`date_input_with_arrows`) and
  a time picker (`time_input_with_arrows`) that use `prompt_toolkit` when
  available. Behaviour:
  - Date picker: `Up` → previous day, `Down` → next day. `Left`/`Right` move the cursor for manual edits.
  - Time picker: `Up`/`Down` change the minutes (step = 1 minute by default). `Left`/`Right` move the cursor.
  - Both have a text-mode fallback that shows the default value in brackets.

Packaging notes regarding prompt_toolkit

- Build the exe from a virtualenv where `prompt_toolkit` is installed so PyInstaller
  can detect and include its submodules. We also include a PyInstaller hook in
  `install/pyinstaller-hooks/hook-prompt_toolkit.py` to help collect required submodules.
- Example build command:

```powershell
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
pyinstaller install\work_timer.spec
```

Runtime feature flags

- `FORCE_PROMPT_TOOLKIT=1` forces the code path that uses `prompt_toolkit` even
  if `sys.stdin.isatty()` is False (useful in some packaged scenarios).
- `DEBUG_DATEPICKER=1` prints debug information about prompt_toolkit detection.
- `SUPPRESS_CONFIRMATION=1` or `--no-confirm` disables messagebox confirmations for automation.

Corrections (Korrekturen)

- The main menu now exposes direct options to correct start and end times (`Arbeitsbeginn korrigieren`, `Arbeitsende korrigieren`).
- Correction prompts accept dates in `TT.MM.JJJJ`. If the user leaves the date input empty, the application will use the current date as default.
 - In the interactive date prompt Up/Down arrow keys navigate the date:
   - `Up` → previous day (scroll backwards)
   - `Down` → next day (scroll forwards)
 - Left/Right arrows behave normally and move the text cursor so you can edit the date manually.

Packaging and interactive prompt notes

- The interactive date picker uses `prompt_toolkit`. To include it in a
  PyInstaller-built exe, build from a Python environment that has
  `prompt_toolkit` installed (e.g. via `pip install -r requirements.txt`).
- Example build command that includes the repository hooks directory we
  provided to help PyInstaller collect prompt_toolkit submodules:

```powershell
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
pyinstaller install\work_timer.spec
```

- Debugging: set environment variables before running the exe to force
  or inspect the date picker behavior:

```powershell
$env:FORCE_PROMPT_TOOLKIT = '1'   # force use of prompt_toolkit
$env:DEBUG_DATEPICKER = '1'      # print runtime debug info about picker
.\dist\work_timer.exe
```

## Holiday handling

- `PUBLIC_HOLIDAYS` is computed by `get_public_holidays(start_year, years)` using an Easter algorithm and a set of fixed-date holidays.
- User-defined holidays are stored in `config.json['holidays']` and are the single source of truth.
- Holidays can be imported from CSV via `import_holidays_from_csv()` (interactive conflict resolution supported).

## Tests

- Unit tests are located in `tests/`.
- Run tests using the project Python interpreter:

```bash
python -m unittest discover tests
```

## Extending

- To support regions with different holidays, extract `get_public_holidays()` to a separate module and provide switchable generators.
- To switch to a small DB backend, replace `load_data()`/`save_data()` with `sqlite3` based functions — keep the CSV format import/export for portability.

## Style and conventions

- Functions are small and single-purpose. I/O operations are performed near the top-level actions.
- Config and data file writes are atomic (`.tmp` + `os.replace`) to avoid corruption.

If you need more details about a specific function, open `work_timer.py` and search for the function name.
