# PyInstaller hook to ensure ALL prompt_toolkit submodules are collected.
# prompt_toolkit dynamically imports platform-specific I/O modules at runtime
# (e.g. prompt_toolkit.input.win32, prompt_toolkit.output.windows10).
# A hand-curated hiddenimports list misses these; collect_submodules is the
# only reliable way to capture every module PyInstaller cannot auto-detect.
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

hiddenimports = collect_submodules('prompt_toolkit')
datas = collect_data_files('prompt_toolkit')
