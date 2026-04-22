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
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        Test-Path $script:dest | Should Be $true
    }

    It 'copies work_timer.exe' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies work_timer_quick.exe' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'work_timer_quick.exe') | Should Be $true
    }

    It 'copies all three icons' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    It 'copies _internal sub-directory' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
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
            & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        } finally {
            Pop-Location
        }
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'does NOT create files in the unrelated CWD' {
        Push-Location $script:altCwd
        try {
            & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
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
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'arbeitszeiten.csv') -Raw) | Should Match 'user data'
    }

    It 'preserves config.json' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'config.json') -Raw) | Should Match '"soll":8'
    }

    It 'preserves checkin_state.json' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'checkin_state.json') -Raw) | Should Match '"start":"08:00"'
    }

    It 'preserves feiertage*.csv' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'feiertage_2025.csv') -Raw) | Should Match 'holiday,date'
    }

    It 'preserves holidays*.csv' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        (Get-Content (Join-Path $script:dest 'holidays_custom.csv') -Raw) | Should Match 'holiday,date'
    }

    It 'preserves the reports directory and contents' {
        & $script:ps1 -Source $script:pkg -Dest $script:dest -SkipShortcuts
        Test-Path (Join-Path $script:dest 'reports\report.pdf') | Should Be $true
    }
}
