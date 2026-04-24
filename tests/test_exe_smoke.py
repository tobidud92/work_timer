"""Smoke test: run the built exe with --check-prompt-toolkit.

This test only runs when dist/work_timer/work_timer.exe exists (i.e. after
a local PyInstaller build). It is skipped on a clean checkout where no
build has been produced yet.

The test would have caught the '_EXCLUDES = [..., "email", ...]' bug
immediately: the exe would exit 1 and print the traceback instead of
silently falling back to bare input().
"""
import os
import subprocess
import pytest

_EXE = os.path.join(os.path.dirname(__file__), '..', 'dist', 'work_timer', 'work_timer.exe')
_EXE = os.path.normpath(_EXE)


@pytest.mark.skipif(not os.path.exists(_EXE), reason="dist/work_timer/work_timer.exe not built yet")
def test_prompt_toolkit_loads_in_built_exe():
    """The built exe must load prompt_toolkit successfully.

    Runs: work_timer.exe --check-prompt-toolkit
    Expects: exit code 0 and stdout contains 'prompt_toolkit: OK'

    Failure here means a PyInstaller exclusion (or missing hidden import)
    is breaking the interactive date/time picker.
    """
    result = subprocess.run(
        [_EXE, '--check-prompt-toolkit'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"prompt_toolkit failed to load in built exe.\n"
        f"stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    assert 'prompt_toolkit: OK' in result.stdout
