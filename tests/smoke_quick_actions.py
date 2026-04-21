import tempfile
import os
import json
import importlib.util
import pathlib

# Import work_timer.py by path to avoid package/import layout issues
repo_root = pathlib.Path(__file__).resolve().parents[1]
wt_path = repo_root / 'work_timer.py'
spec = importlib.util.spec_from_file_location('work_timer', str(wt_path))
wt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wt)

print('Running quick-action smoke in temp dir...')

tmp = tempfile.mkdtemp(prefix='wt_smoke_')
wt.CSV_FILE = os.path.join(tmp, 'arbeitszeiten.csv')
wt.CONFIG_FILE = os.path.join(tmp, 'config.json')

with open(wt.CONFIG_FILE, 'w', encoding='utf-8') as f:
    json.dump({'name': 'Smoke', 'holidays': {}}, f)

print('Config and CSV paths:', wt.CONFIG_FILE, wt.CSV_FILE)

wt.start_work()
wt.end_work()

print('\n--- CSV CONTENT ---')
with open(wt.CSV_FILE, 'r', encoding='utf-8') as f:
    print(f.read())

print('Smoke run complete.')
