param(
    [string]$Source = (Get-Location).Path,
    [string]$Dest = $null,
    [switch]$SkipShortcuts,
    [switch]$Debug
)

function Write-DebugLog {
    param($msg)
    if ($Debug) {
        $dbg = Join-Path $env:TEMP 'work_timer_install_debug.txt'
        "$((Get-Date).ToString('o'))\t$msg" | Out-File -FilePath $dbg -Append -Encoding utf8
    }
}

Write-DebugLog "Installer started. Source=$Source"

# Copy a file to a destination folder, retrying on transient locks (e.g. Explorer holding .ico).
function Copy-FileRetry {
    param(
        [string]$SrcPath,
        [string]$DestDir,
        [int]$Retries = 6,
        [int]$DelayMs = 300
    )
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            Copy-Item -Path $SrcPath -Destination $DestDir -Force -ErrorAction Stop
            return
        } catch [System.IO.IOException] {
            if ($i -lt ($Retries - 1)) {
                Write-DebugLog ("Copy locked, retry {0}/{1}: {2}" -f ($i+1), $Retries, $SrcPath)
                Start-Sleep -Milliseconds $DelayMs
            } else {
                Write-DebugLog ("Copy failed after $Retries retries: $SrcPath")
                throw
            }
        }
    }
}

# Normalize Source
$Source = (Resolve-Path -Path $Source).ProviderPath

if ($env:SKIP_COPY -eq '1' -or $Dest) {
    if ($env:SKIP_COPY -eq '1' -and -not $Dest) {
        $Dest = Join-Path $Source 'test_installed'
    }
} else {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $Dest = Join-Path $docs 'Arbeitszeit'
}

Write-DebugLog "Resolved Dest=$Dest"

if (-not (Test-Path $Dest)) {
    try { New-Item -ItemType Directory -Path $Dest -Force | Out-Null } catch { Write-DebugLog ("Failed to create {0}: {1}" -f $Dest, $_); throw }
}

# --- Find the onedir bundle (directory containing work_timer.exe) ---------
# Build output is dist/work_timer/ - search Source and common parent locations.
$mainExe = Get-ChildItem -Path $Source -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mainExe) {
    $parent = Split-Path -Path $Source -Parent
    if ($parent) { $mainExe = Get-ChildItem -Path $parent -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
}
if (-not $mainExe) { Write-Error 'work_timer.exe not found'; exit 1 }

$binDir = Split-Path -Parent $mainExe.FullName
Write-DebugLog "Binary directory: $binDir"
Write-Host "WorkTimer Installer"
Write-Host "Quelle : $binDir"
Write-Host "Ziel   : $Dest"
Write-Host ''

# --- Clean up stale/corrupt directories left by previous installs --------
# The previous buggy installer created snowball paths in $Dest (e.g.
# work_timer.exe\work_timer_quick.exe\...). These cause robocopy code 16
# (MAX_PATH exceeded). Remove any top-level directory in $Dest that is not
# a known good subdir (_internal = PyInstaller bundle, reports = user data).
$knownDirs = @('_internal', 'reports')
Get-ChildItem -Path $Dest -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notin $knownDirs
} | ForEach-Object {
    Write-Host "Bereinige veraltetes Verzeichnis: $($_.Name)"
    Write-DebugLog "Removing stale dir: $($_.FullName)"
    # Use cmd to handle MAX_PATH paths that PowerShell can't remove directly
    & cmd /c "rmdir /s /q `"$($_.FullName)`"" 2>$null
}

# --- Copy the entire onedir bundle ----------------------------------------
# /IS + /IT  : always overwrite existing files (same size, tweaked timestamps)
# /XF        : never overwrite user data files
# /XD        : never overwrite user data directories
# Protected files/dirs (user data that must survive a reinstall):
#   arbeitszeiten.csv   - time-tracking database
#   config.json         - user configuration (Soll-Stunden, holidays file, name, ...)
#   checkin_state.json  - open-shift sidecar used by quick actions
#   feiertage*.csv      - public-holiday tables imported by the user
#   reports/            - generated PDF reports
$protectedFiles = @('arbeitszeiten.csv', 'config.json', 'checkin_state.json', 'feiertage*.csv', 'holidays*.csv')
$protectedDirs  = @('reports')
$robocopyArgs = @($binDir, $Dest, '/E', '/IS', '/IT') +
                @('/XF') + $protectedFiles +
                @('/XD') + $protectedDirs +
                @('/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP')
# Use Start-Process with file redirects to avoid the PowerShell pipeline deadlock.
# Both "| Out-Null" and "*> $null" still route through the PS pipeline buffer,
# which deadlocks when robocopy emits large output on reinstall.
Write-Host 'Kopiere Programmdateien...' -NoNewline
$tmpOut = [System.IO.Path]::GetTempFileName()
$tmpErr = [System.IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath 'robocopy' -ArgumentList $robocopyArgs `
    -Wait -NoNewWindow -PassThru `
    -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
$robocopyExit = $proc.ExitCode
Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
Write-DebugLog "robocopy exit code: $robocopyExit"
if ($robocopyExit -ge 8) {
    # robocopy exit codes 0-7 are success; 8+ are errors
    Write-Host ' (Fallback)'
    Write-Warning "robocopy reported errors (code $robocopyExit). Falling back to Copy-Item."
    # Copy everything except protected user-data files/dirs
    $protectedExact = @('arbeitszeiten.csv', 'config.json', 'checkin_state.json')
    $allItems = Get-ChildItem -Path $binDir -Recurse
    $total = $allItems.Count
    $i = 0
    $allItems | Where-Object {
        if ($_.PSIsContainer) { return $_.Name -notin $protectedDirs }
        if ($_.Name -in $protectedExact) { return $false }
        if ($_.Name -like 'feiertage*.csv') { return $false }
        if ($_.Name -like 'holidays*.csv') { return $false }
        return $true
    } | ForEach-Object {
        $i++
        if ($i % 50 -eq 0) { Write-Host "." -NoNewline }
        $rel      = $_.FullName.Substring($binDir.Length).TrimStart('\','/')
        $destFile = Join-Path $Dest $rel
        $dir      = Split-Path $destFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (-not $_.PSIsContainer) { Copy-Item -Path $_.FullName -Destination $destFile -Force }
    }
    Write-Host ' fertig.'
} else {
    Write-Host ' fertig.'
}

# --- Remove existing shortcuts before copying icons -----------------------
# Explorer holds .ico files open as long as a shortcut that references them
# exists. Removing the shortcuts first releases the lock so Copy-Item succeeds.
$desktop = [Environment]::GetFolderPath('Desktop')
$removedShortcut = $false
foreach ($lnk in @('Kommen.lnk', 'Gehen.lnk', 'WorkTimer.lnk')) {
    $lnkPath = Join-Path $desktop $lnk
    if (Test-Path $lnkPath) {
        Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue
        Write-DebugLog "Removed existing shortcut: $lnkPath"
        $removedShortcut = $true
    }
}
# Give Explorer time to release the .ico file handles after shortcut removal
if ($removedShortcut) { Start-Sleep -Milliseconds 1500 }

Write-Host 'Kopiere Icons...' -NoNewline

# --- Copy icons (stored next to install.ps1, not inside the bundle) -------
foreach ($ico in @('Kommen.ico', 'Gehen.ico', 'WorkTimer.ico')) {
    $found = Get-ChildItem -Path $Source -Filter $ico -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Copy-FileRetry -SrcPath $found.FullName -DestDir $Dest }
}
Write-Host ' fertig.'

Write-DebugLog "Files copied to $Dest"

$exePath      = Join-Path $Dest 'work_timer.exe'
$quickExePath = Join-Path $Dest 'work_timer_quick.exe'
# Fall back to main exe if quick exe not present (e.g. older build)
if (-not (Test-Path $quickExePath)) { $quickExePath = $exePath }

# --- Create shortcuts -----------------------------------------------------------
Write-Host 'Erstelle Verknüpfungen...' -NoNewline
if (-not $SkipShortcuts) {
    try {
        $w = New-Object -ComObject WScript.Shell

        # Kommen: use quick exe (no console window, fast startup)
        $s = $w.CreateShortcut((Join-Path $desktop 'Kommen.lnk'))
        $s.TargetPath      = $quickExePath
        $s.Arguments       = '--start-now'
        $s.IconLocation    = (Join-Path $Dest 'Kommen.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.Save()

        # Gehen: use quick exe
        $s = $w.CreateShortcut((Join-Path $desktop 'Gehen.lnk'))
        $s.TargetPath      = $quickExePath
        $s.Arguments       = '--end-now'
        $s.IconLocation    = (Join-Path $Dest 'Gehen.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.Save()

        # WorkTimer: full interactive app
        $s = $w.CreateShortcut((Join-Path $desktop 'WorkTimer.lnk'))
        $s.TargetPath      = $exePath
        $s.IconLocation    = (Join-Path $Dest 'WorkTimer.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.Save()
        Write-Host ' fertig.'
    } catch {
        Write-DebugLog ("Shortcut creation failed: {0}" -f $_)
        Write-Host ' (Fehler)'
    }
}
Write-Host ''
Write-Host 'Installation abgeschlossen.'
