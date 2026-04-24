# -*- mode: python ; coding: utf-8 -*-
#
# onedir build: two EXEs in one dist/work_timer/ folder
#   work_timer.exe       – full interactive tool
#   work_timer_quick.exe – minimal Kommen/Gehen handler (fast startup)

# Modules that are never needed by either entry point.
_EXCLUDES = [
    'tkinter', '_tkinter',
    'unittest', 'doctest', 'pdb', 'profile', 'cProfile', 'timeit',
    'difflib', 'pydoc',
    'lib2to3', 'distutils', 'ensurepip', 'venv', 'pip',
    'multiprocessing',
    'sqlite3', '_sqlite3',
    'ftplib', 'imaplib', 'smtplib', 'poplib', 'telnetlib',
    'turtle', 'curses', 'readline',
    'idlelib', 'antigravity',
]

# ── Full interactive app ────────────────────────────────────────────────────
a_main = Analysis(
    ['../src/work_timer.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=['../install/pyinstaller-hooks'],
    hooksconfig={},
    runtime_hooks=[],
    excludes=_EXCLUDES,
    noarchive=False,
    optimize=2,
)
pyz_main = PYZ(a_main.pure)

exe_main = EXE(
    pyz_main,
    a_main.scripts,
    [],
    name='work_timer',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

# ── Minimal quick-action exe (Kommen / Gehen shortcuts) ────────────────────
a_quick = Analysis(
    ['../src/work_timer_quick.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=_EXCLUDES,
    noarchive=False,
    optimize=2,
)
pyz_quick = PYZ(a_quick.pure)

exe_quick = EXE(
    pyz_quick,
    a_quick.scripts,
    [],
    name='work_timer_quick',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    console=False,      # no console window for quick popups
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

# ── Single onedir output (both EXEs share one dist/work_timer/ folder) ─────
coll = COLLECT(
    exe_main,  a_main.binaries,  a_main.zipfiles,  a_main.datas,
    exe_quick, a_quick.binaries, a_quick.zipfiles, a_quick.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='work_timer',
)
