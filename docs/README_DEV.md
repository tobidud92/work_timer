# work_timer — Developer Documentation

This document explains the internals of `work_timer.py`, the project layout, CI/CD setup, and where to extend functionality.

---

## Repository layout

```
src/              # Application source (work_timer.py, __init__.py)
data/             # Static data: holiday CSVs, .ico icons
install/          # Installer & build artefacts
  install.ps1     # Windows installer (copies files, creates shortcuts)
  install.bat     # Double-click launcher for install.ps1 (handles Unblock-File)
  work_timer.spec # PyInstaller spec
  pyinstaller-hooks/
tests/            # pytest test suite
docs/             # README.md (user) + README_DEV.md (this file)
requirements.txt  # Runtime deps (reportlab, prompt_toolkit)
.github/workflows/
  ci.yml          # Runs on every push to main: tests + installer ZIP artifact
  release.yml     # Runs on v* tags: builds exe, packages ZIP, creates GitHub Release
```

---

## Data storage

- **Timesheet:** `arbeitszeiten.csv` — columns `Datum,Typ,Startzeit,Endzeit,Dauer,Kommentar`
- **Config:** `config.json` — keys `name` (string) and `holidays` (object `YYYY-MM-DD → Name`)

---

## Key functions

### Config & data I/O

- `load_config()` / `save_config()` — atomic JSON read/write (`.tmp` + `os.replace`).
- `load_data()` / `save_data()` — CSV read/write. `save_data()` sanitizes fields to prevent CSV injection and writes atomically.

### Business logic

- `compute_saldo(data)` — computes working-time balance (Soll/Ist).
  Uses `PUBLIC_HOLIDAYS` (computed for next 10 years via Easter algorithm) merged with `config.json → holidays`.
- `generate_pdf_report()` — multi-page PDF, one month per page. Text is sanitized via `sanitize_for_pdf()`.
- `quick_start_action()` / `quick_end_action()` — called by `--start-now` / `--end-now` CLI args.
  Both call `_show_messagebox()` to surface immediate feedback to the user.

### UI helpers

- `ask_yes()` — centralized yes/no prompt; accepts `j` (German) or `y` (English).
- `print_header()` — renders the main menu header with the configured user name.
- `_show_messagebox(title, message)` — shows a Windows `MessageBoxW` (topmost, MB_ICONINFORMATION).
  Falls back to `tkinter.messagebox`, then `print`.

---

## Interactive date & time picker

- `date_input_with_arrows(default)` — uses `prompt_toolkit` when available.
  - `Up` → previous day, `Down` → next day, `Left`/`Right` → cursor movement.
  - Falls back to a plain `input()` prompt showing the default in brackets.
  - Empty input → current date used as default.
- `time_input_with_arrows(default)` — same pattern for `HH:MM` input.
  - `Up`/`Down` → ±1 minute, `Left`/`Right` → cursor.

### Environment flags

| Variable | Effect |
|----------|--------|
| `FORCE_PROMPT_TOOLKIT=1` | Force use of `prompt_toolkit` even if `sys.stdin.isatty()` is False |
| `DEBUG_DATEPICKER=1` | Print runtime debug info about picker detection |

---

## CLI arguments

| Argument | Description |
|----------|-------------|
| `--start-now` | Record start time now and exit (used by Kommen shortcut) |
| `--end-now` | Record end time now and exit (used by Gehen shortcut) |
| `--log-file <path>` | Append quick-action events to a log file |
| `--mshta-timeout <seconds>` | Timeout for mshta popups (legacy, rarely needed) |

---

## Desktop shortcuts & installer

`install/install.ps1` parameters: `-Source`, `-Dest`, `-SkipShortcuts`, `-Debug`.

The installer creates three `.lnk` shortcuts that point **directly** to `work_timer.exe`:

| Shortcut | Target arguments | WindowStyle |
|----------|-----------------|-------------|
| `Kommen.lnk` | `--start-now` | 7 (minimized) |
| `Gehen.lnk` | `--end-now` | 7 (minimized) |
| `WorkTimer.lnk` | *(none)* | 1 (normal) |

Using `WindowStyle=7` (SW_SHOWMINNOACTIVE) instead of a hidden VBS wrapper ensures the process runs on the **interactive desktop**, so `MessageBoxW` is displayed immediately after the quick action.

`install/install.bat` calls `Unblock-File` on all files in the folder before invoking `install.ps1`, removing the Zone.Identifier that Windows attaches to downloaded files.

---

## Holiday handling

- `get_public_holidays(start_year, years)` — computes Bavarian public holidays using an Easter algorithm + fixed-date holidays.
- User-defined holidays live in `config.json['holidays']` and are the single source of truth.
- `import_holidays_from_csv()` — interactive import with conflict resolution.

---

## CI / CD

### ci.yml (push to `main`)

1. Set up Python 3.11
2. Install dependencies (`requirements.txt` + `pytest`)
3. Run `pytest`
4. Build exe with `pyinstaller install/work_timer.spec`
5. Run `install/generate_install_folder.ps1` to package exe + icons + installer scripts
6. Upload `WorkTimerInstall/` as a GitHub Actions artifact (downloads as a ZIP)

### release.yml (push of `v*` tag)

Same steps as CI, plus:
- Optional code signing step (set `PFX_BASE64` and `PFX_PASSWORD` secrets)
- Creates a GitHub Release with `WorkTimerInstall_release.zip` attached

To trigger a release:

```powershell
git tag v1.2.3
git push --tags
```

---

## Tests

```powershell
& .venv\Scripts\Activate.ps1
python -m pytest          # all Python unit tests
```

Pester integration tests for the installer (requires Pester ≥ 5):

```powershell
Invoke-Pester tests\InstallBat.Tests.ps1 -Output Detailed
```

The Pester tests use `BeforeEach`/`AfterEach` with an isolated temp folder in `$env:TEMP` and call the real `install/install.ps1` with `-SkipShortcuts`.

---

## Build (exe)

```powershell
& .venv\Scripts\Activate.ps1
pip install -r requirements.txt
pyinstaller install\work_timer.spec --distpath dist --workpath build
```

Custom PyInstaller hooks for `prompt_toolkit` are in `install/pyinstaller-hooks/`.

---

## Extending

- **Different holiday regions:** extract `get_public_holidays()` to a separate module and provide switchable generators.
- **Database backend:** replace `load_data()`/`save_data()` with `sqlite3`-based functions — keep CSV import/export for portability.
- **Additional CLI flags:** extend the `argparse` block in `if __name__ == '__main__'` at the bottom of `work_timer.py`.

---

## Style & conventions

- Functions are small and single-purpose; I/O is performed close to top-level actions.
- Config and data writes are atomic (`.tmp` + `os.replace`) to avoid corruption on interrupted writes.
- CSV injection prevention: leading `=`, `+`, `-`, `@` characters are prefixed with `'` on write.
