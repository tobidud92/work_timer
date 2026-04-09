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
