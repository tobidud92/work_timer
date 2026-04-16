@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Installer for work_timer (assumes this script and files are in the same folder)
rem Copies work_timer.exe and .ico files to %%USERPROFILE%%\Documents\Arbeitszeit
rem Creates three desktop shortcuts: Kommen (--start-now), Gehen (--end-now), WorkTimer (no args)

set "DEST=%USERPROFILE%\Documents\Arbeitszeit"
set "SRC=%~dp0"

echo Installing Work Timer to %DEST%
if not exist "%DEST%" (
    mkdir "%DEST%"
    if errorlevel 1 (
        echo ERROR: Could not create destination folder %DEST%
        pause
        exit /b 1
    )
)

echo Checking required files in the installer folder...
if not exist "%SRC%work_timer.exe" (
    echo ERROR: work_timer.exe not found in %SRC%
    pause
    exit /b 1
)
if not exist "%SRC%Kommen.ico" (
    echo ERROR: Kommen.ico not found in %SRC%
    pause
    exit /b 1
)
if not exist "%SRC%Gehen.ico" (
    echo ERROR: Gehen.ico not found in %SRC%
    pause
    exit /b 1
)
if not exist "%SRC%WorkTimer.ico" (
    echo ERROR: WorkTimer.ico not found in %SRC%
    pause
    exit /b 1
)

echo Copying files...
copy /Y "%SRC%work_timer.exe" "%DEST%\" >nul
copy /Y "%SRC%Kommen.ico" "%DEST%\" >nul
copy /Y "%SRC%Gehen.ico" "%DEST%\" >nul
copy /Y "%SRC%WorkTimer.ico" "%DEST%\" >nul

echo Creating desktop shortcuts...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%DEST%';$desktop=[Environment]::GetFolderPath('Desktop');$w=New-Object -ComObject WScript.Shell;$s=$w.CreateShortcut((Join-Path $desktop 'Kommen.lnk'));$s.TargetPath=Join-Path $d 'work_timer.exe';$s.Arguments='--start-now';$s.IconLocation=(Join-Path $d 'Kommen.ico') + ',0';$s.WorkingDirectory=$d;$s.Save();$s=$w.CreateShortcut((Join-Path $desktop 'Gehen.lnk'));$s.TargetPath=Join-Path $d 'work_timer.exe';$s.Arguments='--end-now';$s.IconLocation=(Join-Path $d 'Gehen.ico') + ',0';$s.WorkingDirectory=$d;$s.Save();$s=$w.CreateShortcut((Join-Path $desktop 'WorkTimer.lnk'));$s.TargetPath=Join-Path $d 'work_timer.exe';$s.Arguments='';$s.IconLocation=(Join-Path $d 'WorkTimer.ico') + ',0';$s.WorkingDirectory=$d;$s.Save();"

if errorlevel 1 (
    echo WARNING: Shortcut creation may have failed. Ensure PowerShell is available and ExecutionPolicy allows running commands.
    echo You can create shortcuts manually if needed.
)

echo Installation finished.
echo Files copied to: %DEST%
echo Desktop shortcuts created: Kommen, Gehen, WorkTimer
pause

endlocal
