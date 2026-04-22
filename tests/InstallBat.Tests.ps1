# Pester tests for install/install.bat + the install package as a whole.
#
# Design rationale
# ----------------
# Spawning cmd.exe -> bat -> powershell in tests pops console windows and makes
# tests needlessly slow. Instead we use two complementary strategies:
#
#   1. BAT CONTENT VALIDATION  – assert the bat file contains exactly the
#      arguments that matter (e.g. -Source '%~dp0').  This catches regressions
#      on the bug where -Source was missing, without spawning any process.
#
#   2. DIRECT PS1 INVOCATION   – call install.ps1 with the same arguments
#      the bat would supply.  Exercises every code path with full fidelity; no
#      window ever appears because install.ps1 already runs robocopy via
#      Start-Process -WindowStyle Hidden.
#
# Together these tests are MORE significant than a cmd.exe round-trip: they
# pin the exact bat content that caused the bug AND verify the full install
# behaviour end-to-end, silently.
#
# Run from repo root:  Invoke-Pester tests\InstallBat.Tests.ps1

$repoRoot = Split-Path -Parent $PSScriptRoot
$realBat  = Join-Path $repoRoot 'install\install.bat'
$realPs1  = Join-Path $repoRoot 'install\install.ps1'

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
# Helper: build a minimal install package (mirrors generate_install_folder.ps1).
# ---------------------------------------------------------------------------
function New-InstallPackage {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    Copy-Item -Path $realBat -Destination $Path -Force
    Copy-Item -Path $realPs1 -Destination $Path -Force

    $bundle = New-Item -ItemType Directory -Path (Join-Path $Path 'work_timer') -Force
    New-Item -Path (Join-Path $bundle.FullName 'work_timer.exe')       -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $bundle.FullName 'work_timer_quick.exe') -ItemType File -Force | Out-Null
    $int = New-Item -ItemType Directory -Path (Join-Path $bundle.FullName '_internal') -Force
    'dummy' | Out-File (Join-Path $int.FullName 'dummy.dll')

    New-Item -Path (Join-Path $Path 'Kommen.ico')    -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'Gehen.ico')     -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'WorkTimer.ico') -ItemType File -Force | Out-Null
}

# ---------------------------------------------------------------------------
Describe "install.bat – content validation (catches missing -Source regression)" {
    # These tests parse the bat file itself.  No process is spawned.

    It "calls install.ps1 with -Source '%~dp0' so CWD does not matter" {
        $content = Get-Content $realBat -Raw
        # Must pass -Source pointing to the bat's own directory
        $pattern = [regex]::Escape("-Source '%~dp0'")
        $content | Should Match $pattern
    }

    It "references install.ps1 via '%~dp0' (not a bare relative path)" {
        $content = Get-Content $realBat -Raw
        $pattern = [regex]::Escape("'%~dp0install.ps1'")
        $content | Should Match $pattern
    }

    It "uses -ExecutionPolicy Bypass so the script is not blocked" {
        $content = Get-Content $realBat -Raw
        $content | Should Match 'ExecutionPolicy\s+Bypass'
    }

    It "calls Unblock-File on the package dir before invoking install.ps1" {
        $content = Get-Content $realBat -Raw
        $content | Should Match 'Unblock-File'
    }

    It "sets console codepage to UTF-8 (chcp 65001) so umlauts display correctly" {
        $content = Get-Content $realBat -Raw
        $content | Should Match 'chcp\s+65001'
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – fresh install (ps1 invoked as bat would)' {

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:ps1  = Join-Path $script:pkg 'install.ps1'
        $script:dest = Join-Path $script:pkg 'dest'
    }

    AfterEach {
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates the destination directory' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path $script:dest | Should Be $true
    }

    It 'copies work_timer.exe' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies work_timer_quick.exe' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer_quick.exe') | Should Be $true
    }

    It 'copies all three icons' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    It 'copies _internal sub-directory' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – correct -Source resolution regardless of CWD' {
    # The critical regression: install.ps1 must resolve its binary dir from
    # $Source (the package dir), NOT from (Get-Location).  We verify by
    # calling install.ps1 with $Source = package dir while the current
    # PowerShell CWD is a completely different temp folder.

    BeforeEach {
        $script:pkg     = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        $script:altCwd  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_cwd_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        New-Item -ItemType Directory -Path $script:altCwd -Force | Out-Null
        $script:ps1     = Join-Path $script:pkg 'install.ps1'
        $script:dest    = Join-Path $script:pkg 'dest'
    }

    AfterEach {
        Remove-Item $script:pkg    -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:altCwd -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs successfully when PowerShell CWD is unrelated to the package' {
        Push-Location $script:altCwd
        try {
            Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        } finally {
            Pop-Location
        }
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'does NOT create files in the unrelated CWD' {
        Push-Location $script:altCwd
        try {
            Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        } finally {
            Pop-Location
        }
        # Nothing should be copied into the unrelated CWD
        (Get-ChildItem $script:altCwd -ErrorAction SilentlyContinue).Count | Should Be 0
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – protected user data survives reinstall' {

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:ps1  = Join-Path $script:pkg 'install.ps1'
        $script:dest = Join-Path $script:pkg 'dest'

        New-Item -ItemType Directory -Path $script:dest -Force | Out-Null
        'user data'         | Out-File (Join-Path $script:dest 'arbeitszeiten.csv')
        '{"soll":8}'        | Out-File (Join-Path $script:dest 'config.json')
        '{"start":"08:00"}' | Out-File (Join-Path $script:dest 'checkin_state.json')
        'holiday,date'      | Out-File (Join-Path $script:dest 'feiertage_2025.csv')
        'holiday,date'      | Out-File (Join-Path $script:dest 'holidays_custom.csv')
        New-Item -ItemType Directory -Path (Join-Path $script:dest 'reports') -Force | Out-Null
        'pdf stub'          | Out-File (Join-Path $script:dest 'reports\report.pdf')
    }

    AfterEach {
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves arbeitszeiten.csv' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'arbeitszeiten.csv') -Raw) | Should Match 'user data'
    }

    It 'preserves config.json' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'config.json') -Raw) | Should Match '"soll":8'
    }

    It 'preserves checkin_state.json' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'checkin_state.json') -Raw) | Should Match '"start":"08:00"'
    }

    It 'preserves feiertage*.csv' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'feiertage_2025.csv') -Raw) | Should Match 'holiday,date'
    }

    It 'preserves holidays*.csv' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'holidays_custom.csv') -Raw) | Should Match 'holiday,date'
    }

    It 'preserves the reports directory and contents' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'reports\report.pdf') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
# Scenario 1: package path contains spaces.
# Uses the real package layout (exe inside work_timer\ subdir, same as
# generate_install_folder.ps1 produces).  The spaces force robocopy to rely on
# the quoting in install.ps1; any regression here causes a "file not found" exit
# code >= 8 which trips the fallback path.
# ---------------------------------------------------------------------------
Describe 'install.bat – package path contains spaces (real layout)' {

    BeforeEach {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) "wt with spaces $([System.IO.Path]::GetRandomFileName())"
        $script:pkg  = $base
        New-InstallPackage -Path $script:pkg
        $script:ps1  = Join-Path $script:pkg 'install.ps1'
        $script:dest = Join-Path $script:pkg 'dest dir'   # spaces in dest too
    }

    AfterEach {
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'package path actually contains a space (test precondition)' {
        $script:pkg | Should Match ' '
    }

    It 'dest path actually contains a space (test precondition)' {
        $script:dest | Should Match ' '
    }

    It 'creates the destination directory' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path $script:dest | Should Be $true
    }

    It 'copies work_timer.exe when source path has spaces' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies work_timer_quick.exe when source path has spaces' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer_quick.exe') | Should Be $true
    }

    It 'copies _internal\dummy.dll when source path has spaces' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }

    It 'copies all three icons when source path has spaces' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    # --- Reinstall from a spaced path preserves user data -------------------
    It 'preserves arbeitszeiten.csv on reinstall (spaced paths)' {
        # First install
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        # Plant user data
        'user-rows' | Out-File (Join-Path $script:dest 'arbeitszeiten.csv')
        # Reinstall
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'arbeitszeiten.csv') -Raw) | Should Match 'user-rows'
    }

    It 'preserves config.json on reinstall (spaced paths)' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        '{"soll":7.5}' | Out-File (Join-Path $script:dest 'config.json')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'config.json') -Raw) | Should Match '"soll":7.5'
    }

    It 'preserves checkin_state.json on reinstall (spaced paths)' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        '{"start":"09:15"}' | Out-File (Join-Path $script:dest 'checkin_state.json')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'checkin_state.json') -Raw) | Should Match '"start":"09:15"'
    }

    It 'preserves feiertage*.csv on reinstall (spaced paths)' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        'feiertag-data' | Out-File (Join-Path $script:dest 'feiertage_2025.csv')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'feiertage_2025.csv') -Raw) | Should Match 'feiertag-data'
    }
}

# ---------------------------------------------------------------------------
# Scenario 2: reinstall replaces binaries with NEW CONTENT.
# Existing tests only check that user data is NOT touched.  This block checks
# the opposite side: that the exe IS overwritten when the source contains a
# newer/different version.  Both plain paths and paths with spaces are covered.
# ---------------------------------------------------------------------------
Describe 'install.bat – reinstall overwrites binaries with new content' {

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:ps1  = Join-Path $script:pkg 'install.ps1'
        $script:dest = Join-Path $script:pkg 'dest'
        $script:bundle = Join-Path $script:pkg 'work_timer'
    }

    AfterEach {
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'overwrites work_timer.exe with new content on reinstall' {
        # First install – exe starts as empty placeholder from New-InstallPackage
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        # Simulate an upgrade: put distinct content in the source exe
        'VERSION-2' | Out-File (Join-Path $script:bundle 'work_timer.exe')
        # Reinstall
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'work_timer.exe') -Raw) | Should Match 'VERSION-2'
    }

    It 'overwrites work_timer_quick.exe with new content on reinstall' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        'QUICK-V2' | Out-File (Join-Path $script:bundle 'work_timer_quick.exe')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'work_timer_quick.exe') -Raw) | Should Match 'QUICK-V2'
    }

    It 'overwrites _internal DLLs with new content on reinstall' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        'DLL-V2' | Out-File (Join-Path $script:bundle '_internal\dummy.dll')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest '_internal\dummy.dll') -Raw) | Should Match 'DLL-V2'
    }

    It 'does NOT overwrite arbeitszeiten.csv while overwriting exe (same reinstall)' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        'user-rows' | Out-File (Join-Path $script:dest 'arbeitszeiten.csv')
        'VERSION-2' | Out-File (Join-Path $script:bundle 'work_timer.exe')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        # Exe must be new
        (Get-Content (Join-Path $script:dest 'work_timer.exe') -Raw) | Should Match 'VERSION-2'
        # But user data must be old
        (Get-Content (Join-Path $script:dest 'arbeitszeiten.csv') -Raw) | Should Match 'user-rows'
    }

    It 'does NOT overwrite config.json while overwriting exe (same reinstall)' {
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        '{"soll":7.5}' | Out-File (Join-Path $script:dest 'config.json')
        'VERSION-2' | Out-File (Join-Path $script:bundle 'work_timer.exe')
        Invoke-InstallerWithTimeout $script:ps1 $script:pkg $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'config.json') -Raw) | Should Match '"soll":7.5'
    }

    # Same two checks but with spaces in every path
    It 'overwrites exe with new content when paths contain spaces' {
        $pkgS  = Join-Path ([System.IO.Path]::GetTempPath()) "wt space pkg $([System.IO.Path]::GetRandomFileName())"
        $destS = Join-Path ([System.IO.Path]::GetTempPath()) "wt space dest $([System.IO.Path]::GetRandomFileName())"
        try {
            New-InstallPackage -Path $pkgS
            $ps1S    = Join-Path $pkgS 'install.ps1'
            $bundleS = Join-Path $pkgS 'work_timer'
            Invoke-InstallerWithTimeout $ps1S $pkgS $destS -SkipShortcuts
            'V2-SPACED' | Out-File (Join-Path $bundleS 'work_timer.exe')
            Invoke-InstallerWithTimeout $ps1S $pkgS $destS -SkipShortcuts
            (Get-Content (Join-Path $destS 'work_timer.exe') -Raw) | Should Match 'V2-SPACED'
        } finally {
            Remove-Item $pkgS, $destS -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does NOT overwrite user data while overwriting exe when paths contain spaces' {
        $pkgS  = Join-Path ([System.IO.Path]::GetTempPath()) "wt space pkg $([System.IO.Path]::GetRandomFileName())"
        $destS = Join-Path ([System.IO.Path]::GetTempPath()) "wt space dest $([System.IO.Path]::GetRandomFileName())"
        try {
            New-InstallPackage -Path $pkgS
            $ps1S    = Join-Path $pkgS 'install.ps1'
            $bundleS = Join-Path $pkgS 'work_timer'
            Invoke-InstallerWithTimeout $ps1S $pkgS $destS -SkipShortcuts
            'user-rows-s' | Out-File (Join-Path $destS 'arbeitszeiten.csv')
            '{"soll":6}'  | Out-File (Join-Path $destS 'config.json')
            'V2-SPACED'   | Out-File (Join-Path $bundleS 'work_timer.exe')
            Invoke-InstallerWithTimeout $ps1S $pkgS $destS -SkipShortcuts
            (Get-Content (Join-Path $destS 'arbeitszeiten.csv') -Raw) | Should Match 'user-rows-s'
            (Get-Content (Join-Path $destS 'config.json') -Raw)       | Should Match '"soll":6'
        } finally {
            Remove-Item $pkgS, $destS -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
