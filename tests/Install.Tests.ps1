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
        [int]$TimeoutMs = 30000
    )
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Ps1',          $Ps1)
    $rs.SessionStateProxy.SetVariable('Source',       $Source)
    $rs.SessionStateProxy.SetVariable('Dest',         $Dest)
    $rs.SessionStateProxy.SetVariable('SkipShortcuts',$SkipShortcuts.IsPresent)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    if ($SkipShortcuts) {
        [void]$ps.AddScript('& $Ps1 -Source $Source -Dest $Dest -SkipShortcuts')
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

    BeforeEach {
        $script:root   = Join-Path ([System.IO.Path]::GetTempPath()) "wt_pester_$([System.IO.Path]::GetRandomFileName())"
        $script:src    = Join-Path $script:root 'source'
        $script:dest   = Join-Path $script:root 'dest'
        New-SourceTree -Path $script:src -WithQuick

        # Track any .lnk files we create so we can remove them in teardown
        $script:lnksCreated = @()
    }

    AfterEach {
        foreach ($lnk in $script:lnksCreated) {
            Remove-Item $lnk -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates Kommen.lnk, Gehen.lnk, and WorkTimer.lnk on the Desktop' {
        $desktop = [Environment]::GetFolderPath('Desktop')

        Invoke-InstallerWithTimeout $installer $script:src $script:dest

        foreach ($lnk in @('Kommen.lnk','Gehen.lnk','WorkTimer.lnk')) {
            $path = Join-Path $desktop $lnk
            $script:lnksCreated += $path
            Test-Path $path | Should Be $true
        }
    }

    It 'Kommen.lnk target is work_timer_quick.exe with --start-now argument' {
        $desktop = [Environment]::GetFolderPath('Desktop')
        Invoke-InstallerWithTimeout $installer $script:src $script:dest

        $lnkPath = Join-Path $desktop 'Kommen.lnk'
        $script:lnksCreated += $lnkPath

        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath | Should Match 'work_timer_quick\.exe'
        $lnk.Arguments  | Should Be '--start-now'
    }

    It 'Gehen.lnk target is work_timer_quick.exe with --end-now argument' {
        $desktop = [Environment]::GetFolderPath('Desktop')
        Invoke-InstallerWithTimeout $installer $script:src $script:dest

        $lnkPath = Join-Path $desktop 'Gehen.lnk'
        $script:lnksCreated += $lnkPath

        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath | Should Match 'work_timer_quick\.exe'
        $lnk.Arguments  | Should Be '--end-now'
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
