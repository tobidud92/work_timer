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
Copy-Item -Path $exe.FullName -Destination $Dest -Force
if ($kommen) { Copy-Item -Path $kommen.FullName -Destination $Dest -Force }
if ($gehen)  { Copy-Item -Path $gehen.FullName -Destination $Dest -Force }
if ($workico) { Copy-Item -Path $workico.FullName -Destination $Dest -Force }

Write-DebugLog "Files copied to $Dest"

# Create wrappers
$kommenBat = Join-Path $Dest 'kommen.bat'
$gehenBat = Join-Path $Dest 'gehen.bat'
$kommenVbs = Join-Path $Dest 'kommen.vbs'
$gehenVbs = Join-Path $Dest 'gehen.vbs'
$exePath = Join-Path $Dest 'work_timer.exe'

"@echo off" | Out-File -FilePath $kommenBat -Encoding ASCII
('"{0}" --start-now --log-file "{1}\Desktop\work_timer_quick.log"' -f $exePath, $env:USERPROFILE) | Out-File -FilePath $kommenBat -Encoding ASCII -Append
"exit /b" | Out-File -FilePath $kommenBat -Encoding ASCII -Append

"@echo off" | Out-File -FilePath $gehenBat -Encoding ASCII
('"{0}" --end-now --log-file "{1}\Desktop\work_timer_quick.log"' -f $exePath, $env:USERPROFILE) | Out-File -FilePath $gehenBat -Encoding ASCII -Append
"exit /b" | Out-File -FilePath $gehenBat -Encoding ASCII -Append

# VBS wrappers (Chr(34) produces a double-quote in VBScript)
$vb1 = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run Chr(34) & "$exePath" & Chr(34) & " --start-now --log-file Chr(34) & ""$env:USERPROFILE\Desktop\work_timer_quick.log"" & Chr(34)", 0, False
"@
$vb1 | Out-File -FilePath $kommenVbs -Encoding ASCII

$vb2 = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run Chr(34) & "$exePath" & Chr(34) & " --end-now --log-file Chr(34) & ""$env:USERPROFILE\Desktop\work_timer_quick.log"" & Chr(34)", 0, False
"@
$vb2 | Out-File -FilePath $gehenVbs -Encoding ASCII

# Create shortcuts unless skipped
if (-not $SkipShortcuts) {
    try {
        $w = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        $s = $w.CreateShortcut((Join-Path $desktop 'Kommen.lnk'))
        $s.TargetPath = $kommenVbs
        $s.IconLocation = (Join-Path $Dest 'Kommen.ico') + ',0'
        $s.WorkingDirectory = $Dest
        $s.Save()

        $s = $w.CreateShortcut((Join-Path $desktop 'Gehen.lnk'))
        $s.TargetPath = $gehenVbs
        $s.IconLocation = (Join-Path $Dest 'Gehen.ico') + ',0'
        $s.WorkingDirectory = $Dest
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
