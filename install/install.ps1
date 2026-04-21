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
    $destFile = Join-Path $DestDir (Split-Path $SrcPath -Leaf)
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

# Find exe: search Source, then Source\dist, then parent
$exe = Get-ChildItem -Path $Source -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { $exe = Get-ChildItem -Path (Join-Path $Source 'dist') -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $exe) { $parent = Split-Path -Path $Source -Parent; if ($parent) { $exe = Get-ChildItem -Path $parent -Filter 'work_timer.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 } }
if (-not $exe) { Write-Error 'work_timer.exe not found'; exit 1 }
Write-DebugLog "Found exe: $($exe.FullName)"

# Find icons
$kommen = Get-ChildItem -Path $Source -Filter 'Kommen.ico' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$gehen = Get-ChildItem -Path $Source -Filter 'Gehen.ico' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$workico = Get-ChildItem -Path $Source -Filter 'WorkTimer.ico' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

# Copy files
Copy-FileRetry -SrcPath $exe.FullName -DestDir $Dest
if ($kommen)  { Copy-FileRetry -SrcPath $kommen.FullName  -DestDir $Dest }
if ($gehen)   { Copy-FileRetry -SrcPath $gehen.FullName   -DestDir $Dest }
if ($workico) { Copy-FileRetry -SrcPath $workico.FullName -DestDir $Dest }

Write-DebugLog "Files copied to $Dest"

$exePath = Join-Path $Dest 'work_timer.exe'

# Create shortcuts unless skipped
if (-not $SkipShortcuts) {
    try {
        $w = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')

        $s = $w.CreateShortcut((Join-Path $desktop 'Kommen.lnk'))
        $s.TargetPath = $exePath
        $s.Arguments = '--start-now'
        $s.IconLocation = (Join-Path $Dest 'Kommen.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.WindowStyle = 7  # SW_SHOWMINNOACTIVE: starts minimized, no console flash in foreground
        $s.Save()

        $s = $w.CreateShortcut((Join-Path $desktop 'Gehen.lnk'))
        $s.TargetPath = $exePath
        $s.Arguments = '--end-now'
        $s.IconLocation = (Join-Path $Dest 'Gehen.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.WindowStyle = 7
        $s.Save()

        $s = $w.CreateShortcut((Join-Path $desktop 'WorkTimer.lnk'))
        $s.TargetPath = $exePath
        $s.IconLocation = (Join-Path $Dest 'WorkTimer.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.Save()
    } catch {
        Write-DebugLog ("Shortcut creation failed: {0}" -f $_)
    }
}

Write-Host "Installation finished.`nFiles copied to: $Dest"
if ($SkipShortcuts) { Write-Host 'Desktop shortcuts creation: SKIPPED' } else { Write-Host 'Desktop shortcuts created: Kommen, Gehen, WorkTimer' }
