import os
candidates = [
    r"c:\Users\z003xbha\Documents\Code\work_timer\code\WorkTimer.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\code\Kommen.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\code\Gehen.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\code\WorkTimerInstall\WorkTimer.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\data\WorkTimer.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\data\Kommen.ico",
    r"c:\Users\z003xbha\Documents\Code\work_timer\data\Gehen.ico",
]
for p in candidates:
    if os.path.exists(p):
        with open(p,'rb') as f:
            b = f.read(12)
        print(f"{p} -> {os.path.getsize(p)} bytes -> {' '.join(f'{x:02X}' for x in b)}")
    else:
        print(f"{p} -> MISSING")
