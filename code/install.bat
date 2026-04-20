@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Installer for work_timer (assumes this script and files are in the same folder)
rem Copies work_timer.exe and .ico files to %%USERPROFILE%%\Documents\Arbeitszeit
rem Creates three desktop shortcuts: Kommen (--start-now), Gehen (--end-now), WorkTimer (no args)

rem Change working directory to the script folder so paths with spaces/() are handled safely
pushd "%~dp0" >nul
set "SRC=%CD%\"

rem Determine the user's Documents folder in a language-neutral way
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')"`) do set "DOCS=%%D"
set "DEST=%DOCS%\Arbeitszeit"

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
    if not exist "%SRC%dist\work_timer.exe" (
        echo ERROR: work_timer.exe not found in %SRC% or %SRC%dist\
        pause
        exit /b 1
    )
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
rem Prefer built exe in a 'dist' subfolder if present (PyInstaller output)
if exist "%SRC%dist\work_timer.exe" (
    copy /Y "%SRC%dist\work_timer.exe" "%DEST%\" >nul
) else (
    copy /Y "%SRC%work_timer.exe" "%DEST%\" >nul
)
copy /Y "%SRC%Kommen.ico" "%DEST%\" >nul
copy /Y "%SRC%Gehen.ico" "%DEST%\" >nul
copy /Y "%SRC%WorkTimer.ico" "%DEST%\" >nul
rem Prefer canonical .ico files from repo data folder if present (when installer run from code/)
if exist "%SRC%..\data\Kommen.ico" (
    copy /Y "%SRC%..\data\Kommen.ico" "%DEST%" >nul
)
if exist "%SRC%..\data\Gehen.ico" (
    copy /Y "%SRC%..\data\Gehen.ico" "%DEST%" >nul
)
if exist "%SRC%..\data\WorkTimer.ico" (
    copy /Y "%SRC%..\data\WorkTimer.ico" "%DEST%" >nul
)

rem Create small wrapper batch files that call the EXE and log stdout/stderr to Desktop
(echo @echo off) > "%DEST%\kommen.bat"
(echo "%DEST%\work_timer.exe" --start-now ^>^> "%USERPROFILE%\Desktop\work_timer_kommen_log.txt" 2^>^&1) >> "%DEST%\kommen.bat"
(echo exit /b) >> "%DEST%\kommen.bat"

(echo @echo off) > "%DEST%\gehen.bat"
(echo "%DEST%\work_timer.exe" --end-now ^>^> "%USERPROFILE%\Desktop\work_timer_gehen_log.txt" 2^>^&1) >> "%DEST%\gehen.bat"
(echo exit /b) >> "%DEST%\gehen.bat"

rem Create VBS wrappers to run the exe without showing a console window
echo Set WshShell = CreateObject("WScript.Shell") > "%DEST%\kommen.vbs"
echo WshShell.Run Chr(34) ^& "%DEST%\work_timer.exe" ^& Chr(34) ^& " --start-now", 0, False >> "%DEST%\kommen.vbs"

echo Set WshShell = CreateObject("WScript.Shell") > "%DEST%\gehen.vbs"
echo WshShell.Run Chr(34) ^& "%DEST%\work_timer.exe" ^& Chr(34) ^& " --end-now", 0, False >> "%DEST%\gehen.vbs"

echo Creating desktop shortcuts...

rem Create a temporary PowerShell script to reliably create shortcuts with icon paths
set "PSFILE=%TEMP%\work_timer_create_shortcuts.ps1"
echo $d = '%DEST%' > "%PSFILE%"
echo $desktop = [Environment]::GetFolderPath('Desktop') >> "%PSFILE%"
echo $w = New-Object -ComObject WScript.Shell >> "%PSFILE%"

echo $icon = Join-Path $d 'Kommen.ico' >> "%PSFILE%"
echo $s = $w.CreateShortcut((Join-Path $desktop 'Kommen.lnk')) >> "%PSFILE%"
echo $s.TargetPath = Join-Path $d 'kommen.vbs' >> "%PSFILE%"
echo $s.Arguments = '' >> "%PSFILE%"
echo $s.IconLocation = $icon + ',0' >> "%PSFILE%"
echo $s.WorkingDirectory = $d >> "%PSFILE%"
echo $s.Save() >> "%PSFILE%"

echo $icon = Join-Path $d 'Gehen.ico' >> "%PSFILE%"
echo $s = $w.CreateShortcut((Join-Path $desktop 'Gehen.lnk')) >> "%PSFILE%"
echo $s.TargetPath = Join-Path $d 'gehen.vbs' >> "%PSFILE%"
echo $s.Arguments = '' >> "%PSFILE%"
echo $s.IconLocation = $icon + ',0' >> "%PSFILE%"
echo $s.WorkingDirectory = $d >> "%PSFILE%"
echo $s.Save() >> "%PSFILE%"

echo $icon = Join-Path $d 'WorkTimer.ico' >> "%PSFILE%"
echo $s = $w.CreateShortcut((Join-Path $desktop 'WorkTimer.lnk')) >> "%PSFILE%"
echo $s.TargetPath = Join-Path $d 'work_timer.exe' >> "%PSFILE%"
echo $s.Arguments = '' >> "%PSFILE%"
echo $s.IconLocation = $icon + ',0' >> "%PSFILE%"
echo $s.WorkingDirectory = $d >> "%PSFILE%"
echo $s.Save() >> "%PSFILE%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
if exist "%PSFILE%" del "%PSFILE%"

rem Try to refresh Windows icon cache so the new .ico files are shown on the Desktop
echo Refreshing Windows icon cache (may restart Explorer)...
timeout /t 1 /nobreak >nul
tasklist /FI "IMAGENAME eq explorer.exe" | findstr /I "explorer.exe" >nul
if %ERRORLEVEL%==0 (
    taskkill /IM explorer.exe /F >nul 2>&1
    rem remove Explorer icon cache files (no admin required for local AppData)
    del /F /Q "%localappdata%\Microsoft\Windows\Explorer\iconcache*" >nul 2>&1
    del /F /Q "%localappdata%\IconCache.db" >nul 2>&1
    start explorer.exe
    rem try IE icon refresh helper if available
    if exist "%windir%\system32\ie4uinit.exe" (
        "%windir%\system32\ie4uinit.exe" -show >nul 2>&1
    )
) else (
    rem Explorer not running? try ie4uinit anyway
    if exist "%windir%\system32\ie4uinit.exe" (
        "%windir%\system32\ie4uinit.exe" -show >nul 2>&1
    )
)

if errorlevel 1 (
    echo WARNING: Shortcut creation may have failed. Ensure PowerShell is available and ExecutionPolicy allows running commands.
    echo You can create shortcuts manually if needed.
)

echo Installation finished.
echo Files copied to: %DEST%
echo Desktop shortcuts created: Kommen, Gehen, WorkTimer
pause

endlocal
popd >nul
