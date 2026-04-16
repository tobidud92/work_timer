import tempfile
import os
import shutil
import subprocess
from pathlib import Path


def write_dummy_files(src_dir: Path):
    # dummy exe file (content doesn't matter for shortcut creation)
    (src_dir / 'work_timer.exe').write_text('echo dummy exe')
    # create minimal valid ICO header bytes for icon files
    ico_header = bytes([0, 0, 1, 0]) + b'ICON'
    (src_dir / 'Kommen.ico').write_bytes(ico_header)
    (src_dir / 'Gehen.ico').write_bytes(ico_header)
    (src_dir / 'WorkTimer.ico').write_bytes(ico_header)


def simulate_install_and_create_shortcuts():
    tmp = Path(tempfile.mkdtemp(prefix='wt_inst_test_'))
    src = tmp / 'src'
    dest = tmp / 'dest'
    desktop = tmp / 'desktop'
    src.mkdir()
    dest.mkdir()
    desktop.mkdir()

    write_dummy_files(src)

    # copy files
    shutil.copy(src / 'work_timer.exe', dest / 'work_timer.exe')
    shutil.copy(src / 'Kommen.ico', dest / 'Kommen.ico')
    shutil.copy(src / 'Gehen.ico', dest / 'Gehen.ico')
    shutil.copy(src / 'WorkTimer.ico', dest / 'WorkTimer.ico')

    # create kommen.bat and gehen.bat like installer does
    kommen_bat = dest / 'kommen.bat'
    gehen_bat = dest / 'gehen.bat'
    kommen_bat.write_text(f'@echo off\n"{dest / "work_timer.exe"}" --start-now >> "{desktop / "work_timer_kommen_log.txt"}" 2>&1\n')
    gehen_bat.write_text(f'@echo off\n"{dest / "work_timer.exe"}" --end-now >> "{desktop / "work_timer_gehen_log.txt"}" 2>&1\n')

    # write temporary PowerShell script that creates shortcuts in our temp desktop
    ps = tmp / 'create_shortcuts_test.ps1'
    ps_lines = []
    ps_lines.append(f"$d = '{dest.as_posix()}'")
    ps_lines.append(f"$desktop = '{desktop.as_posix()}'")
    ps_lines.append("$w = New-Object -ComObject WScript.Shell")

    # Kommen.lnk
    ps_lines.append(f"$s = $w.CreateShortcut((Join-Path $desktop 'Kommen.lnk'))")
    ps_lines.append(f"$s.TargetPath = (Join-Path $d 'kommen.bat')")
    ps_lines.append(f"$s.Arguments = '--start-now'")
    ps_lines.append(f"$s.IconLocation = (Join-Path $d 'Kommen.ico') + ',0'")
    ps_lines.append(f"$s.WorkingDirectory = $d")
    ps_lines.append("$s.Save()")

    # Gehen.lnk
    ps_lines.append(f"$s = $w.CreateShortcut((Join-Path $desktop 'Gehen.lnk'))")
    ps_lines.append(f"$s.TargetPath = (Join-Path $d 'gehen.bat')")
    ps_lines.append(f"$s.Arguments = '--end-now'")
    ps_lines.append(f"$s.IconLocation = (Join-Path $d 'Gehen.ico') + ',0'")
    ps_lines.append(f"$s.WorkingDirectory = $d")
    ps_lines.append("$s.Save()")

    # WorkTimer.lnk
    ps_lines.append(f"$s = $w.CreateShortcut((Join-Path $desktop 'WorkTimer.lnk'))")
    ps_lines.append(f"$s.TargetPath = (Join-Path $d 'work_timer.exe')")
    ps_lines.append(f"$s.Arguments = ''")
    ps_lines.append(f"$s.IconLocation = (Join-Path $d 'WorkTimer.ico') + ',0'")
    ps_lines.append(f"$s.WorkingDirectory = $d")
    ps_lines.append("$s.Save()")

    ps.write_text('\n'.join(ps_lines), encoding='utf-8')

    # execute the PowerShell script
    cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ps)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print('PowerShell failed:', proc.stderr)
        raise SystemExit(1)

    # now query the created shortcuts for their properties using PowerShell
    check_cmd = ['powershell', '-NoProfile', '-Command',
                 f"$w = New-Object -ComObject WScript.Shell; $s = $w.CreateShortcut('{(desktop / 'Kommen.lnk').as_posix()}'); Write-Output ($s.TargetPath + '||' + $s.Arguments);"
                ]
    out = subprocess.run(check_cmd, capture_output=True, text=True)
    print('Kommen.lnk ->', out.stdout.strip())

    out2 = subprocess.run(['powershell', '-NoProfile', '-Command',
                           f"$w = New-Object -ComObject WScript.Shell; $s = $w.CreateShortcut('{(desktop / 'Gehen.lnk').as_posix()}'); Write-Output ($s.TargetPath + '||' + $s.Arguments);"],
                          capture_output=True, text=True)
    print('Gehen.lnk ->', out2.stdout.strip())

    out3 = subprocess.run(['powershell', '-NoProfile', '-Command',
                           f"$w = New-Object -ComObject WScript.Shell; $s = $w.CreateShortcut('{(desktop / 'WorkTimer.lnk').as_posix()}'); Write-Output ($s.TargetPath + '||' + $s.Arguments);"],
                          capture_output=True, text=True)
    print('WorkTimer.lnk ->', out3.stdout.strip())

    print('\nFiles in dest:', list(dest.iterdir()))
    print('Files in desktop:', list(desktop.iterdir()))

    # cleanup temp if desired
    return tmp


if __name__ == '__main__':
    tmp = simulate_install_and_create_shortcuts()
    print('Test install complete, temp dir:', tmp)
