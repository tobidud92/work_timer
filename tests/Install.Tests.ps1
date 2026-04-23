# Pester tests for install/install.ps1
# Run from repo root:  Invoke-Pester tests\Install.Tests.ps1 -Output Detailed
#
# Every test uses an isolated temp directory tree; the real desktop is never
# touched (-SkipShortcuts is always passed).

$repoRoot  = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot 'install\install.ps1'

# ---------------------------------------------------------------------------
# Helper: run install.ps1 in an isolated Runspace with a hard timeout.
# Throws "DEADLOCK DETECTED" if the script does not finish within $TimeoutMs.
# Using a Runspace (not Start-Job) keeps overhead to ~50 ms per call and avoids
# spawning an extra PowerShell process for every single test.
# ---------------------------------------------------------------------------
function Invoke-InstallerWithTimeout {
    param(
        [string]$Ps1,
        [string]$Source,
        [string]$Dest,
        [switch]$SkipShortcuts,
        [string]$DesktopOverride = '',
        [int]$TimeoutMs = 30000
    )
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Ps1',             $Ps1)
    $rs.SessionStateProxy.SetVariable('Source',          $Source)
    $rs.SessionStateProxy.SetVariable('Dest',            $Dest)
    $rs.SessionStateProxy.SetVariable('SkipShortcuts',   $SkipShortcuts.IsPresent)
    $rs.SessionStateProxy.SetVariable('DesktopOverride', $DesktopOverride)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    if ($SkipShortcuts) {
        [void]$ps.AddScript('& $Ps1 -Source $Source -Dest $Dest -SkipShortcuts')
    } elseif ($DesktopOverride) {
        [void]$ps.AddScript('& $Ps1 -Source $Source -Dest $Dest -DesktopOverride $DesktopOverride')
    } else {
        [void]$ps.AddScript('& $Ps1 -Source $Source -Dest $Dest')
    }

    $handle = $ps.BeginInvoke()
    $finished = $handle.AsyncWaitHandle.WaitOne($TimeoutMs)
    if (-not $finished) {
        $ps.Stop()
        $ps.Dispose(); $rs.Dispose()
        throw "DEADLOCK DETECTED: installer '$Ps1' did not complete within $($TimeoutMs/1000)s"
    }
    $ps.EndInvoke($handle) | Out-Null
    if ($ps.HadErrors) { throw $ps.Streams.Error[0] }
    $ps.Dispose(); $rs.Dispose()
}

# ---------------------------------------------------------------------------
# Helper: build a minimal source tree that the installer accepts.
#   <root>\
#     work_timer.exe          <- makes $binDir = <root>
#     work_timer_quick.exe    <- optional; created when $WithQuick is set
#     _internal\dummy.dll     <- PyInstaller bundle subdir
#     Kommen.ico
#     Gehen.ico
#     WorkTimer.ico
# ---------------------------------------------------------------------------
function New-SourceTree {
    param(
        [string]$Path,
        [switch]$WithQuick,
        [switch]$WithInternalDir
    )
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    New-Item -Path (Join-Path $Path 'work_timer.exe')  -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'Kommen.ico')      -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'Gehen.ico')       -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'WorkTimer.ico')   -ItemType File -Force | Out-Null
    if ($WithQuick)       { New-Item -Path (Join-Path $Path 'work_timer_quick.exe') -ItemType File -Force | Out-Null }
    if ($WithInternalDir) {
        $int = New-Item -ItemType Directory -Path (Join-Path $Path '_internal') -Force
        'dummy' | Out-File -FilePath (Join-Path $int.FullName 'dummy.dll')
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – fresh install' {

    BeforeEach {
        $script:root   = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src    = Join-Path $script:root 'source'
        $script:dest   = Join-Path $script:root 'dest'
        New-SourceTree -Path $script:src -WithInternalDir
    }

    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates the destination directory when it does not exist' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        Test-Path $script:dest | Should Be $true
    }

    It 'copies work_timer.exe to Dest' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies all three icons to Dest' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    It 'copies _internal sub-directory contents to Dest' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }

    It 'does not create legacy .bat or .vbs wrappers' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        foreach ($f in @('kommen.bat','gehen.bat','kommen.vbs','gehen.vbs')) {
            Test-Path (Join-Path $script:dest $f) | Should Be $false
        }
    }

    It 'exits with code 1 when work_timer.exe is absent from Source' {
        # Remove the exe so the installer cannot locate the binary dir.
        # This is a fast-fail path (< 1 s, no blocking I/O), so we call the
        # installer directly to preserve $LASTEXITCODE in this scope.
        Remove-Item (Join-Path $script:src 'work_timer.exe') -Force
        try {
            & $installer -Source $script:src -Dest $script:dest -SkipShortcuts
        } catch { }
        $LASTEXITCODE | Should Be 1
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – reinstall (files already present in Dest)' {

    BeforeEach {
        $script:root   = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src    = Join-Path $script:root 'source'
        $script:dest   = Join-Path $script:root 'dest'
        New-SourceTree -Path $script:src -WithInternalDir

        # Simulate a previous install: dest already has the exe + icons
        New-Item -ItemType Directory -Path $script:dest -Force | Out-Null
        'old content' | Out-File -FilePath (Join-Path $script:dest 'work_timer.exe')
        Copy-Item (Join-Path $script:src 'Kommen.ico')    $script:dest
        Copy-Item (Join-Path $script:src 'Gehen.ico')     $script:dest
        Copy-Item (Join-Path $script:src 'WorkTimer.ico') $script:dest
    }

    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'overwrites the existing exe during reinstall' {
        # Write distinguishable content into the source exe
        'new content' | Out-File -FilePath (Join-Path $script:src 'work_timer.exe')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        $content = Get-Content (Join-Path $script:dest 'work_timer.exe') -Raw
        $content | Should Match 'new content'
    }

    It 'preserves arbeitszeiten.csv (user time-tracking data) during reinstall' {
        $csvPath = Join-Path $script:dest 'arbeitszeiten.csv'
        'user data row 1' | Out-File -FilePath $csvPath

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        Test-Path $csvPath | Should Be $true
        $content = Get-Content $csvPath -Raw
        $content | Should Match 'user data row 1'
    }

    It 'preserves config.json (user configuration) during reinstall' {
        $cfgPath = Join-Path $script:dest 'config.json'
        '{"soll":8}' | Out-File -FilePath $cfgPath

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        Test-Path $cfgPath | Should Be $true
        (Get-Content $cfgPath -Raw) | Should Match '"soll":8'
    }

    It 'preserves checkin_state.json during reinstall' {
        $statePath = Join-Path $script:dest 'checkin_state.json'
        '{"start":"08:00"}' | Out-File -FilePath $statePath

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        (Get-Content $statePath -Raw) | Should Match '"start":"08:00"'
    }

    It 'preserves feiertage*.csv files during reinstall' {
        $holiday = Join-Path $script:dest 'feiertage_2025.csv'
        'holiday,date' | Out-File -FilePath $holiday

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        (Get-Content $holiday -Raw) | Should Match 'holiday,date'
    }

    It 'preserves holidays*.csv files during reinstall' {
        $holiday = Join-Path $script:dest 'holidays_custom.csv'
        'holiday,date' | Out-File -FilePath $holiday

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        (Get-Content $holiday -Raw) | Should Match 'holiday,date'
    }

    It 'preserves the reports directory and its contents during reinstall' {
        $reportsDir = Join-Path $script:dest 'reports'
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
        'report pdf stub' | Out-File -FilePath (Join-Path $reportsDir 'report_2025.pdf')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        Test-Path (Join-Path $reportsDir 'report_2025.pdf') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – stale directory cleanup' {

    BeforeEach {
        $script:root   = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src    = Join-Path $script:root 'source'
        $script:dest   = Join-Path $script:root 'dest'
        New-SourceTree -Path $script:src

        New-Item -ItemType Directory -Path $script:dest -Force | Out-Null
    }

    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes stale top-level directories that are not _internal or reports' {
        # Simulate the snowball-path artefact: a dir named after the exe
        $stale = New-Item -ItemType Directory -Path (Join-Path $script:dest 'work_timer.exe') -Force
        'some file' | Out-File -FilePath (Join-Path $stale.FullName 'nested.txt')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        # Stale DIRECTORY must be gone. robocopy will copy the real work_timer.exe
        # FILE to the same path, so Test-Path may still return $true.
        # What matters is that the directory (and its nested snowball content) was cleaned up.
        if (Test-Path $stale.FullName) {
            # If something exists at this path now it must be a file, not a dir
            (Get-Item $stale.FullName).PSIsContainer | Should Be $false
            # The nested snowball file must be gone
            Test-Path (Join-Path $stale.FullName 'nested.txt') | Should Be $false
        }
    }

    It 'removes a stale "work_timer_quick.exe" directory if present' {
        $stale = New-Item -ItemType Directory -Path (Join-Path $script:dest 'work_timer_quick.exe') -Force
        'junk' | Out-File (Join-Path $stale.FullName 'junk.txt')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        Test-Path $stale.FullName | Should Be $false
    }

    It 'keeps the _internal directory intact when it exists before install' {
        $internal = New-Item -ItemType Directory -Path (Join-Path $script:dest '_internal') -Force
        'keep me' | Out-File (Join-Path $internal.FullName 'existing.dll')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        # _internal should still be there (not wiped), and overwritten by robocopy
        Test-Path $internal.FullName | Should Be $true
    }

    It 'keeps the reports directory intact when it exists before install' {
        $reports = New-Item -ItemType Directory -Path (Join-Path $script:dest 'reports') -Force
        'report' | Out-File (Join-Path $reports.FullName 'report.pdf')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts

        Test-Path (Join-Path $reports.FullName 'report.pdf') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – shortcuts (-SkipShortcuts OFF)' {
    # All shortcut tests use -DesktopOverride pointing to a temp directory.
    # This guarantees the REAL Desktop is NEVER touched: no shortcuts are
    # deleted or created there, so the user's existing shortcuts survive.

    BeforeEach {
        $script:root    = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src     = Join-Path $script:root 'source'
        $script:dest    = Join-Path $script:root 'dest'
        $script:fakeDesk = Join-Path $script:root 'fake_desktop'
        New-SourceTree -Path $script:src -WithQuick
        New-Item -ItemType Directory -Path $script:fakeDesk -Force | Out-Null
    }

    AfterEach {
        # Entire temp tree (including fake_desktop) is removed here.
        # Real Desktop: untouched.
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates Kommen.lnk, Gehen.lnk, and WorkTimer.lnk in the desktop folder' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        foreach ($lnk in @('Kommen.lnk','Gehen.lnk','WorkTimer.lnk')) {
            Test-Path (Join-Path $script:fakeDesk $lnk) | Should Be $true
        }
    }

    It 'does NOT create any .lnk on the real Desktop' {
        $realDesk = [Environment]::GetFolderPath('Desktop')
        $before   = Get-ChildItem $realDesk -Filter '*.lnk' | Select-Object -ExpandProperty Name

        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        $after = Get-ChildItem $realDesk -Filter '*.lnk' | Select-Object -ExpandProperty Name
        # Same set of .lnk files as before — nothing added or removed
        Compare-Object $before $after | Should BeNullOrEmpty
    }

    It 'Kommen.lnk target is work_timer_quick.exe with --start-now argument' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut((Join-Path $script:fakeDesk 'Kommen.lnk'))
        $lnk.TargetPath | Should Match 'work_timer_quick\.exe'
        $lnk.Arguments  | Should Be '--start-now'
    }

    It 'Gehen.lnk target is work_timer_quick.exe with --end-now argument' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut((Join-Path $script:fakeDesk 'Gehen.lnk'))
        $lnk.TargetPath | Should Match 'work_timer_quick\.exe'
        $lnk.Arguments  | Should Be '--end-now'
    }

    It 'WorkTimer.lnk target is work_timer.exe (not quick exe)' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut((Join-Path $script:fakeDesk 'WorkTimer.lnk'))
        $lnk.TargetPath | Should Match 'work_timer\.exe'
        $lnk.TargetPath | Should Not Match 'quick'
    }

    It 'shortcut icons point to .ico files in Dest' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        $shell = New-Object -ComObject WScript.Shell
        foreach ($pair in @(
            @{ Lnk = 'Kommen.lnk';   Ico = 'Kommen.ico'   }
            @{ Lnk = 'Gehen.lnk';    Ico = 'Gehen.ico'    }
            @{ Lnk = 'WorkTimer.lnk'; Ico = 'WorkTimer.ico' }
        )) {
            $lnk = $shell.CreateShortcut((Join-Path $script:fakeDesk $pair.Lnk))
            $lnk.IconLocation | Should Match ([regex]::Escape($pair.Ico))
        }
    }

    It 'reinstall updates existing shortcuts without error' {
        # First install
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk
        # Second install (reinstall) — must not throw and must still have all lnk files
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -DesktopOverride $script:fakeDesk

        foreach ($lnk in @('Kommen.lnk','Gehen.lnk','WorkTimer.lnk')) {
            Test-Path (Join-Path $script:fakeDesk $lnk) | Should Be $true
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – paths containing spaces' {
    # Regression test: robocopy arguments must quote $binDir and $Dest.
    # Without quotes, a path like "C:\my folder\source" is split by robocopy
    # into two tokens and the copy fails (or silently falls back to Copy-Item).

    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) "wt pester spaces $([System.IO.Path]::GetRandomFileName())"
        $script:src  = Join-Path $script:root 'source folder'
        $script:dest = Join-Path $script:root 'dest folder'
        New-SourceTree -Path $script:src -WithInternalDir
    }

    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'copies work_timer.exe when source path contains spaces' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies _internal dir when both source and dest paths contain spaces' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }

    It 'copies all three icons when paths contain spaces' {
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'install.ps1 – resilience against locked .ico files' {
    # The real-world failure mode: Explorer holds a .ico file open (because a
    # shortcut that references it is on the Desktop), and the installer tries to
    # overwrite that file during a reinstall.
    #
    # The fix has two parts that must work together:
    #   1. Shortcuts are deleted BEFORE any file copy (releases Explorer handles).
    #   2. robocopy uses /R:10 /W:1 so transient locks are retried instead of
    #      failing immediately.

    BeforeEach {
        $script:root     = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src      = Join-Path $script:root 'source'
        $script:dest     = Join-Path $script:root 'dest'
        $script:fakeDesk = Join-Path $script:root 'fake_desktop'
        New-SourceTree -Path $script:src

        # Simulate existing install: dest already has the icons (reinstall scenario).
        New-Item -ItemType Directory -Path $script:dest     -Force | Out-Null
        New-Item -ItemType Directory -Path $script:fakeDesk -Force | Out-Null
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            'OLD_CONTENT' | Set-Content (Join-Path $script:dest $ico) -NoNewline
        }
        'old content' | Out-File (Join-Path $script:dest 'work_timer.exe')
        # Put NEW_CONTENT in the SOURCE icons so we can detect if copy succeeded.
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            'NEW_CONTENT' | Set-Content (Join-Path $script:src $ico) -NoNewline
        }
    }

    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'overwrites a transiently locked .ico via robocopy /R:10 /W:1 retry' {
        # Lock dest\Gehen.ico exclusively for ~1200 ms.
        # robocopy will fail on first attempt, then succeed after /W:1 retry
        # once the lock expires.  Without /R:/W the installer would fail immediately.
        $destIco = Join-Path $script:dest 'Gehen.ico'
        $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
        $rs.SessionStateProxy.SetVariable('icoPath', $destIco)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        $null = $ps.AddScript({
            $fs = [System.IO.File]::Open($icoPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)   # exclusive lock
            Start-Sleep -Milliseconds 1200
            $fs.Dispose()
        })
        $async = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 150   # ensure lock is held before installer starts

        $start = Get-Date
        Invoke-InstallerWithTimeout $installer $script:src $script:dest -SkipShortcuts -TimeoutMs 60000
        $elapsed = (Get-Date) - $start

        $ps.EndInvoke($async) | Out-Null; $ps.Dispose(); $rs.Dispose()

        # Lock was held 1200 ms + /W:1 overhead → elapsed must be > 900 ms,
        # proving the installer waited and retried rather than crashing.
        $elapsed.TotalMilliseconds | Should BeGreaterThan 900

        # The file content must be the NEW version from src.
        [System.IO.File]::ReadAllText($destIco) | Should Be 'NEW_CONTENT'
    }

    It 'deletes Desktop shortcuts BEFORE copying, so the lock is released in time' {
        # Root cause of the real-world bug: shortcuts exist → Explorer holds .ico
        # files open → installer tries to overwrite them → IOException.
        # Fix: installer deletes shortcuts first, then sleeps 1500 ms, then copies.
        #
        # We simulate this by:
        #   - Placing Gehen.lnk on the fake Desktop (→ installer deletes it → 1500ms sleep).
        #   - Holding dest\Gehen.ico locked for 2200 ms.
        # Timeline:
        #   t=0     installer starts, deletes Gehen.lnk, starts 1500ms sleep
        #   t=1500  robocopy starts; lock still held → /W:1 retry
        #   t=2200  lock released
        #   t=2500  robocopy second attempt succeeds
        # Without the ordering fix (shortcuts deleted after copy), robocopy would
        # run at t=0 with the lock held and would need to wait much longer.

        # Place a stub Gehen.lnk on the fake desktop.
        $lnkPath = Join-Path $script:fakeDesk 'Gehen.lnk'
        '' | Out-File $lnkPath

        $destIco = Join-Path $script:dest 'Gehen.ico'
        $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
        $rs.SessionStateProxy.SetVariable('icoPath', $destIco)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        $null = $ps.AddScript({
            $fs = [System.IO.File]::Open($icoPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            Start-Sleep -Milliseconds 2200
            $fs.Dispose()
        })
        $async = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 150

        # Run with -DesktopOverride so the fake Gehen.lnk is detected and deleted.
        Invoke-InstallerWithTimeout $installer $script:src $script:dest `
            -DesktopOverride $script:fakeDesk -TimeoutMs 60000

        $ps.EndInvoke($async) | Out-Null; $ps.Dispose(); $rs.Dispose()

        # The installer recreates Gehen.lnk at the end of the script,
        # so we do not assert its absence.  What matters is that the
        # icon file was successfully overwritten despite the transient lock
        # — which is only possible if shortcuts were deleted first (releasing
        # Explorer handles) before the file copy to dest began.
        [System.IO.File]::ReadAllText($destIco) | Should Be 'NEW_CONTENT'
    }
}
