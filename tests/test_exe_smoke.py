"""Smoke test: run the built exe with --check-imports.

This test only runs when dist/work_timer/work_timer.exe exists (i.e. after
a local PyInstaller build). It is skipped on a clean checkout where no
build has been produced yet.

Catches PyInstaller _EXCLUDES bugs that silently break lazy imports
(prompt_toolkit, reportlab, etc.) at runtime.
"""
import os
import subprocess
import pytest

_EXE = os.path.join(os.path.dirname(__file__), '..', 'dist', 'work_timer', 'work_timer.exe')
_EXE = os.path.normpath(_EXE)


@pytest.mark.skipif(not os.path.exists(_EXE), reason="dist/work_timer/work_timer.exe not built yet")
def test_lazy_imports_in_built_exe():
    """All lazy imports (prompt_toolkit, reportlab) must load in the built exe.

    Runs: work_timer.exe --check-imports
    Expects: exit code 0, stdout contains 'OK' for each import.

    Failure means a PyInstaller exclusion or missing hidden import is
    breaking an interactive feature.
    """
    result = subprocess.run(
        [_EXE, '--check-imports'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Lazy imports failed in built exe.\n"
        f"stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    assert 'prompt_toolkit: OK' in result.stdout
    assert 'reportlab: OK' in result.stdout
