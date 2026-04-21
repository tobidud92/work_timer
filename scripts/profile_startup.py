"""Profile startup and quick action timing."""
import time
import subprocess
import sys
import os

os.chdir(os.path.join(os.path.dirname(__file__), '..'))
PY = sys.executable

def timeit(label, cmd, runs=3):
    times = []
    for _ in range(runs):
        t0 = time.perf_counter()
        subprocess.run(cmd, capture_output=True)
        times.append(round((time.perf_counter() - t0) * 1000))
    avg = round(sum(times) / len(times))
    print(f"  {label:<35} {times}  avg={avg}ms")

print("=== Baseline ===")
timeit("bare python -c pass",         [PY, "-c", "pass"])
timeit("bare python -c (import csv)", [PY, "-c", "import csv,json,os,sys,shutil"])

print("\n=== Module import ===")
timeit("import src.work_timer",       [PY, "-c", "import src.work_timer"])

print("\n=== Quick actions (full run) ===")
# warm run first
subprocess.run([PY, "src/work_timer.py", "--end-now"], capture_output=True)
timeit("--start-now",                 [PY, "src/work_timer.py", "--start-now"])
timeit("--end-now",                   [PY, "src/work_timer.py", "--end-now"])

print("\n=== _show_messagebox overhead ===")
with open("_tmp_msgtest.py", "w") as f:
    f.write("""
import time
import src.work_timer as wt
t = time.perf_counter()
wt._show_messagebox('Test', 'Profiling messagebox')
print(f"messagebox: {round((time.perf_counter()-t)*1000)}ms")
""")
try:
    r = subprocess.run([PY, "_tmp_msgtest.py"], capture_output=True, timeout=15)
    print("  messagebox time:", r.stdout.decode().strip() or r.stderr.decode().strip())
finally:
    try:
        os.remove("_tmp_msgtest.py")
    except Exception:
        pass
