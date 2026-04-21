# PyInstaller hook to ensure prompt_toolkit submodules are collected
# Place this in a hooks directory and pass --additional-hooks-dir to pyinstaller
hiddenimports = [
    'prompt_toolkit.shortcuts',
    'prompt_toolkit.key_binding',
    'prompt_toolkit.application',
    'prompt_toolkit.buffer',
    'prompt_toolkit.filters',
    'prompt_toolkit.formatted_text',
    'prompt_toolkit.document',
    'prompt_toolkit.styles',
    'prompt_toolkit.widgets',
    'prompt_toolkit.layout',
]
