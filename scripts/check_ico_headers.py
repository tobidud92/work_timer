import os
files = [r"C:\Users\z003xbha\Documents\Arbeitszeit\Kommen.ico",
         r"C:\Users\z003xbha\Documents\Arbeitszeit\Gehen.ico",
         r"C:\Users\z003xbha\Documents\Arbeitszeit\WorkTimer.ico"]
for p in files:
    if not os.path.exists(p):
        print(f"{os.path.basename(p)} MISSING")
        continue
    with open(p, 'rb') as f:
        data = f.read(16)
    hexs = ' '.join(f"{b:02X}" for b in data)
    print(f"{os.path.basename(p)} {os.path.getsize(p)} bytes -> {hexs}")
