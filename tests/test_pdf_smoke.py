"""
Smoke tests for PDF report generation.

Purpose: catch import/exclude errors (e.g. html, xml wrongly excluded from
PyInstaller bundle) and basic generation failures early.
"""

import os
import shutil
import pytest
import src.work_timer as wt


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_MINIMAL_CONFIG = """{
    "soll_stunden": 8.0,
    "pause_minuten": 30,
    "user_name": "Test User",
    "holidays_file": ""
}"""

_CSV_HEADER = "Datum,Start,Ende,Typ,Kommentar\n"


def _write_csv(path: str, rows: list[str]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(_CSV_HEADER)
        for r in rows:
            f.write(r + "\n")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_reportlab_importable():
    """reportlab and its sub-modules used by generate_pdf_report must import."""
    from reportlab.lib.pagesizes import A4  # noqa: F401
    from reportlab.platypus import SimpleDocTemplate  # noqa: F401
    from reportlab.lib.styles import getSampleStyleSheet  # noqa: F401
    from reportlab.lib.units import inch  # noqa: F401
    from reportlab.lib import colors  # noqa: F401


def test_pdf_generated_with_entries(tmp_path, monkeypatch):
    """generate_pdf_report() creates a non-empty PDF when data exists."""
    csv_file = str(tmp_path / "arbeitszeiten.csv")
    cfg_file = str(tmp_path / "config.json")
    pdf_dir  = str(tmp_path / "reports")

    _write_csv(csv_file, [
        "2025-01-06,08:00,16:30,Arbeit,",
        "2025-01-07,08:00,16:30,Arbeit,",
        "2025-01-08,08:00,16:30,Arbeit,",
    ])
    with open(cfg_file, "w", encoding="utf-8") as f:
        f.write(_MINIMAL_CONFIG)

    monkeypatch.setattr(wt, "CSV_FILE",       csv_file)
    monkeypatch.setattr(wt, "CONFIG_FILE",    cfg_file)
    monkeypatch.setattr(wt, "PDF_REPORT_DIR", pdf_dir)
    monkeypatch.setattr(wt, "_data_cache",     None)
    monkeypatch.setattr(wt, "_data_cache_mtime", 0.0)
    monkeypatch.setattr(wt, "_data_cache_path",  "")

    wt.generate_pdf_report()

    pdfs = [f for f in os.listdir(pdf_dir) if f.endswith(".pdf")]
    assert len(pdfs) == 1, f"Expected 1 PDF, got: {pdfs}"
    assert os.path.getsize(os.path.join(pdf_dir, pdfs[0])) > 0


def test_pdf_generated_with_various_types(tmp_path, monkeypatch):
    """generate_pdf_report() handles mixed Typ values without crashing."""
    csv_file = str(tmp_path / "arbeitszeiten.csv")
    cfg_file = str(tmp_path / "config.json")
    pdf_dir  = str(tmp_path / "reports")

    _write_csv(csv_file, [
        "2025-02-03,08:00,16:30,Arbeit,",
        "2025-02-04,08:00,12:00,Sonderarbeit,Samstagsdienst",
        "2025-02-05,,,Urlaub,",
        "2025-02-06,,,Feiertag,Rosenmontag",
        "2025-02-07,,,Zeitausgleich,",
    ])
    with open(cfg_file, "w", encoding="utf-8") as f:
        f.write(_MINIMAL_CONFIG)

    monkeypatch.setattr(wt, "CSV_FILE",       csv_file)
    monkeypatch.setattr(wt, "CONFIG_FILE",    cfg_file)
    monkeypatch.setattr(wt, "PDF_REPORT_DIR", pdf_dir)
    monkeypatch.setattr(wt, "_data_cache",     None)
    monkeypatch.setattr(wt, "_data_cache_mtime", 0.0)
    monkeypatch.setattr(wt, "_data_cache_path",  "")

    wt.generate_pdf_report()

    pdfs = [f for f in os.listdir(pdf_dir) if f.endswith(".pdf")]
    assert len(pdfs) == 1
    assert os.path.getsize(os.path.join(pdf_dir, pdfs[0])) > 0


def test_pdf_empty_data_no_crash(tmp_path, monkeypatch, capsys):
    """generate_pdf_report() exits gracefully when CSV is empty."""
    csv_file = str(tmp_path / "arbeitszeiten.csv")
    cfg_file = str(tmp_path / "config.json")
    pdf_dir  = str(tmp_path / "reports")

    _write_csv(csv_file, [])  # header only, no entries
    with open(cfg_file, "w", encoding="utf-8") as f:
        f.write(_MINIMAL_CONFIG)

    monkeypatch.setattr(wt, "CSV_FILE",       csv_file)
    monkeypatch.setattr(wt, "CONFIG_FILE",    cfg_file)
    monkeypatch.setattr(wt, "PDF_REPORT_DIR", pdf_dir)
    monkeypatch.setattr(wt, "_data_cache",     None)
    monkeypatch.setattr(wt, "_data_cache_mtime", 0.0)
    monkeypatch.setattr(wt, "_data_cache_path",  "")

    # Must not raise
    wt.generate_pdf_report()

    captured = capsys.readouterr()
    assert "Keine Daten" in captured.out
    # No PDF should have been created
    assert not os.path.isdir(pdf_dir) or not any(
        f.endswith(".pdf") for f in os.listdir(pdf_dir)
    )
