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

# --- Copy the entire onedir bundle ----------------------------------------
# /IS + /IT  : always overwrite existing files (same size, tweaked timestamps)
# /XF        : never touch the CSV database (preserve user data)
# Use robocopy for reliability; fall back to Copy-Item on unexpected failures.
$csvName = 'arbeitszeiten.csv'
$robocopyArgs = @($binDir, $Dest, '/E', '/IS', '/IT', '/XF', $csvName, '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP')
& robocopy @robocopyArgs | Out-Null
Write-DebugLog "robocopy exit code: $LASTEXITCODE"
if ($LASTEXITCODE -ge 8) {
    # robocopy exit codes 0-7 are success; 8+ are errors
    Write-Warning "robocopy reported errors (code $LASTEXITCODE). Falling back to Copy-Item."
    # Copy everything except the CSV database
    Get-ChildItem -Path $binDir -Recurse | Where-Object {
        -not $_.PSIsContainer -and $_.Name -ne $csvName
    } | ForEach-Object {
        $rel  = $_.FullName.Substring($binDir.Length).TrimStart('\','/')
        $dest = Join-Path $Dest $rel
        $dir  = Split-Path $dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -Path $_.FullName -Destination $dest -Force
    }
}

# --- Copy icons (stored next to install.ps1, not inside the bundle) -------
foreach ($ico in @('Kommen.ico', 'Gehen.ico', 'WorkTimer.ico')) {
    $found = Get-ChildItem -Path $Source -Filter $ico -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Copy-FileRetry -SrcPath $found.FullName -DestDir $Dest }
}

Write-DebugLog "Files copied to $Dest"

$exePath      = Join-Path $Dest 'work_timer.exe'
$quickExePath = Join-Path $Dest 'work_timer_quick.exe'
# Fall back to main exe if quick exe not present (e.g. older build)
if (-not (Test-Path $quickExePath)) { $quickExePath = $exePath }

# --- Create shortcuts ------------------------------------------------------
if (-not $SkipShortcuts) {
    try {
        $w = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')

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
    } catch {
        Write-DebugLog ("Shortcut creation failed: {0}" -f $_)
    }
}

Write-Host "Installation finished.`nFiles copied to: $Dest"
if ($SkipShortcuts) { Write-Host 'Desktop shortcuts creation: SKIPPED' } else { Write-Host 'Desktop shortcuts created: Kommen, Gehen, WorkTimer' }
