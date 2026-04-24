param(
    [string]$Source = (Get-Location).Path,
    [string]$Dest = $null,
    [switch]$SkipShortcuts,
    [switch]$Debug,
    # Override the Desktop folder used for shortcut creation/removal.
    # Intended for tests only; leave empty to use the real Desktop.
    [string]$DesktopOverride = ''
)

# Ensure UTF-8 output regardless of the console codepage that was active when
# this process started.  cmd.exe defaults to CP850 on German Windows; chcp 65001
# in install.bat switches the *terminal* to UTF-8, but PowerShell's
# [Console]::OutputEncoding is captured at process start before chcp runs.
# Setting it here guarantees Write-Host emits UTF-8 bytes for every umlaut.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-DebugLog {
    param($msg)
    if ($Debug) {
        $dbg = Join-Path $env:TEMP 'work_timer_install_debug.txt'
        "$((Get-Date).ToString('o'))\t$msg" | Out-File -FilePath $dbg -Append -Encoding utf8
    }
}

Write-DebugLog "Installer started. Source=$Source"

# Run an external process with a hard timeout.  If the process does not finish
# within $TimeoutMs milliseconds it is killed and the function returns -1.
# This prevents any subprocess from hanging the installer indefinitely.
# (robocopy default /R:1000000 /W:30 would block for ~347 days without this.)
function Start-ProcessWithTimeout {
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$StdOut,
        [string]$StdErr,
        [int]$TimeoutMs = 120000   # 2 minutes default
    )
    $proc = Start-Process -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -NoNewWindow `
        -RedirectStandardOutput $StdOut `
        -RedirectStandardError  $StdErr `
        -PassThru
    $finished = $proc.WaitForExit($TimeoutMs)
    if (-not $finished) {
        Write-DebugLog ("Process '{0}' timed out after {1} ms — killing." -f $FilePath, $TimeoutMs)
        try { $proc.Kill() } catch { }
        $proc.WaitForExit(5000) | Out-Null   # brief grace period after kill
        return -1
    }
    return $proc.ExitCode
}

# Copy a file to a destination folder, retrying on transient locks (e.g. Explorer holding .ico).
# Uses [IO.File]::Copy instead of Copy-Item.
# IMPORTANT: In PowerShell 5.1 calls to .NET methods throw MethodInvocationException
# (not the inner IOException directly), so we use a bare catch and unwrap the inner
# exception chain to detect IOException.  A typed 'catch [IOException]' would never
# fire and every lock condition would propagate immediately without retrying.
function Copy-FileRetry {
    param(
        [string]$SrcPath,
        [string]$DestDir,
        [int]$Retries = $(if ($env:WT_TEST_ICO_RETRIES) { [int]$env:WT_TEST_ICO_RETRIES } else { 20 }),
        [int]$DelayMs = $(if ($env:WT_TEST_ICO_DELAY_MS) { [int]$env:WT_TEST_ICO_DELAY_MS } else { 1000 })
    )
    $destPath = Join-Path $DestDir (Split-Path $SrcPath -Leaf)
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            [System.IO.File]::Copy($SrcPath, $destPath, $true)   # $true = overwrite
            return
        } catch {
            # Unwrap: PS 5.1 wraps .NET method exceptions in MethodInvocationException.
            # Walk the InnerException chain to find the real exception type.
            $ex = $_.Exception
            while ($ex.InnerException -and $ex -isnot [System.IO.IOException]) {
                $ex = $ex.InnerException
            }
            if ($ex -is [System.IO.IOException]) {
                if ($i -lt ($Retries - 1)) {
                    Write-DebugLog ("Copy locked, retry {0}/{1}: {2}" -f ($i+1), $Retries, $SrcPath)
                    Start-Sleep -Milliseconds $DelayMs
                } else {
                    Write-Warning ("Kopieren fehlgeschlagen nach $Retries Versuchen (Datei gesperrt): $SrcPath")
                    Write-DebugLog ("Copy failed after $Retries retries: $SrcPath")
                    return
                }
            } else {
                # Not a locking error – re-throw immediately.
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
# Check the canonical package layout first ($Source\work_timer\work_timer.exe).
# Falling back to a recursive search is necessary for dev/build layouts, but we
# MUST NOT recurse into $Dest: after a reinstall $Dest (which may live inside
# $Source) also contains work_timer.exe, and picking that path would make
# robocopy copy a directory onto itself, causing it to hang indefinitely.
$canonicalExe = Join-Path $Source 'work_timer\work_timer.exe'
if (Test-Path $canonicalExe) {
    $mainExe = Get-Item $canonicalExe
} else {
    # Exclude $Dest from the recursive search so a previously-installed copy
    # inside $Source does not shadow the real bundle.
    $mainExe = Get-ChildItem -Path $Source -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $Dest -or -not $_.FullName.StartsWith($Dest, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if (-not $mainExe) {
        $parent = Split-Path -Path $Source -Parent
        if ($parent) {
            $mainExe = Get-ChildItem -Path $parent -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { -not $Dest -or -not $_.FullName.StartsWith($Dest, [System.StringComparison]::OrdinalIgnoreCase) } |
                Select-Object -First 1
        }
    }
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
    # Use cmd to handle MAX_PATH paths that PowerShell can't remove directly.
    # Redirect output to temp files: no pipe buffer, no PTY inheritance, no deadlock.
    # Timeout: 30 s — rmdir should never take longer; kill it if it does.
    $rmOut = [System.IO.Path]::GetTempFileName()
    $rmErr = [System.IO.Path]::GetTempFileName()
    $rmExit = Start-ProcessWithTimeout -FilePath 'cmd.exe' `
        -ArgumentList "/c rmdir /s /q `"$($_.FullName)`"" `
        -StdOut $rmOut -StdErr $rmErr -TimeoutMs 30000
    if ($rmExit -eq -1) { Write-Warning "rmdir timed out for: $($_.FullName)" }
    Remove-Item $rmOut, $rmErr -Force -ErrorAction SilentlyContinue
}

# --- Remove existing shortcuts BEFORE any file copy ----------------------
# Explorer holds .ico files open as long as a shortcut that references them
# exists on the Desktop. We must delete shortcuts HERE — before robocopy —
# so Explorer releases its .ico handles before we touch those files.
# If we delete shortcuts only after robocopy, Explorer immediately re-opens
# the freshly-written .ico files and the subsequent Copy-FileRetry hits a lock.
$desktop = if ($DesktopOverride) { $DesktopOverride } else { [Environment]::GetFolderPath('Desktop') }
if ($DesktopOverride -and -not (Test-Path $DesktopOverride)) {
    New-Item -ItemType Directory -Path $DesktopOverride -Force | Out-Null
}
$removedShortcut = $false
foreach ($lnk in @('Kommen.lnk', 'Gehen.lnk', 'WorkTimer.lnk')) {
    $lnkPath = Join-Path $desktop $lnk
    if (Test-Path $lnkPath) {
        Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue
        Write-DebugLog "Removed existing shortcut: $lnkPath"
        $removedShortcut = $true
    }
}
# Give Explorer time to release the .ico file handles after shortcut removal.
if ($removedShortcut) { Start-Sleep -Milliseconds 1500 }

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
# Paths must be quoted in case they contain spaces.
# Flags and wildcard exclusions do not need quoting.
$robocopyArgs = @("`"$binDir`"", "`"$Dest`"", '/E') +
                @('/XF') + $protectedFiles +
                @('/XD') + $protectedDirs +
                @('/MT:8', '/R:10', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP')
# /R:10 /W:1 : retry each file up to 10 times with 1-second wait (total max 10s).
#              robocopy default is R:1000000 W:30 which would hang for ~347 days.
# Redirect robocopy output to temp files: no pipe buffer, no PTY inheritance,
# no deadlock possible regardless of output volume. -NoNewWindow prevents a
# new console window opening.
Write-Host 'Kopiere Programmdateien...' -NoNewline
$robocopyOut = [System.IO.Path]::GetTempFileName()
$robocopyErr = [System.IO.Path]::GetTempFileName()
# Timeout: 5 minutes.  With /R:10 /W:1 each locked file costs at most 10 s;
# a 5-minute ceiling ensures the installer always terminates, even if hundreds
# of files are locked simultaneously (which would never happen in practice).
$robocopyExit = Start-ProcessWithTimeout -FilePath 'robocopy' `
    -ArgumentList ($robocopyArgs -join ' ') `
    -StdOut $robocopyOut -StdErr $robocopyErr -TimeoutMs 300000
Remove-Item $robocopyOut, $robocopyErr -Force -ErrorAction SilentlyContinue
Write-DebugLog "robocopy exit code: $robocopyExit"
if ($robocopyExit -eq -1 -or $robocopyExit -ge 8) {
    # robocopy exit codes 0-7 are success; 8+ are errors; -1 means timed out (killed)
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
        if (-not $_.PSIsContainer) {
                try {
                    Copy-Item -Path $_.FullName -Destination $destFile -Force -ErrorAction Stop
                } catch {
                    $copyErr = $_
                    Write-Warning "Konnte Datei nicht kopieren (gesperrt?): $destFile"
                    Write-DebugLog "Fallback Copy-Item failed for ${destFile}: $copyErr"
                }
            }
    }
    Write-Host ' fertig.'
} else {
    Write-Host ' fertig.'
}

# Give Explorer time to finish re-caching icon thumbnails that robocopy just
# wrote. Without this pause, Explorer re-acquires the .ico lock immediately
# after robocopy and Copy-FileRetry hits a lock on the very first attempt.
Start-Sleep -Milliseconds 2000
Write-Host 'Kopiere Icons...' -NoNewline

# --- Copy icons not already handled by robocopy ---------------------------
# robocopy already copied icons that live inside the onedir bundle ($binDir).
# This loop handles the rare case where icons are stored OUTSIDE the bundle
# (i.e. directly next to install.ps1 but not under $binDir). Icons already
# present in $Dest from robocopy are skipped to avoid a redundant overwrite
# that could race with Explorer re-opening freshly-written .ico files.
foreach ($ico in @('Kommen.ico', 'Gehen.ico', 'WorkTimer.ico')) {
    $destIco   = Join-Path $Dest   $ico
    $bundleIco = Join-Path $binDir $ico
    # If robocopy already delivered this icon (it lives inside $binDir), skip.
    # If the icon is outside the bundle (only at $Source root), copy it now.
    if (Test-Path $bundleIco) {
        Write-DebugLog "Icon already in bundle, skipping extra copy: $ico"
        continue
    }
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
