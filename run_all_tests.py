import os
import subprocess
import sys

tests_dir = os.path.join(os.path.dirname(__file__), 'tests')
failed = False
for fn in sorted(os.listdir(tests_dir)):
    if fn.startswith('test_') and fn.endswith('.py'):
        mod = fn[:-3]
        print('\nRunning', mod)
        r = subprocess.run([sys.executable, '-m', 'unittest', f'tests.{mod}', '-v'], cwd=os.path.dirname(__file__))
        if r.returncode != 0:
            failed = True

if failed:
    sys.exit(1)
