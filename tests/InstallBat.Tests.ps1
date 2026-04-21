# Pester tests for install/install.bat
# Exercises the bat file itself — not just install.ps1 — including the scenario
# where the bat is run from a working directory DIFFERENT from its own folder.
#
# Run from repo root:  Invoke-Pester tests\InstallBat.Tests.ps1
#
# How tests avoid writing to the real install destination (Documents\Arbeitszeit):
#   The installer checks  $env:SKIP_COPY -eq '1'  and when set, uses
#   $Source\test_installed as the destination instead.  Every test sets this
#   env var before invoking the bat and restores it in AfterEach.
#
# Package layout produced by generate_install_folder.ps1 (what the end user gets):
#   <pkg>\
#     install.bat          <- the script under test
#     install.ps1          <- real installer (copied from repo)
#     work_timer\          <- onedir bundle (contains the exe)
#       work_timer.exe
#       work_timer_quick.exe
#       _internal\
#         dummy.dll
#     Kommen.ico
#     Gehen.ico
#     WorkTimer.ico

$repoRoot  = Split-Path -Parent $PSScriptRoot
$realBat   = Join-Path $repoRoot 'install\install.bat'
$realPs1   = Join-Path $repoRoot 'install\install.ps1'

# ---------------------------------------------------------------------------
# Helper: build a minimal install package (mirrors generate_install_folder.ps1 output).
# ---------------------------------------------------------------------------
function New-InstallPackage {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    # Real installer scripts (the bat is what we're testing; ps1 must be the real one)
    Copy-Item -Path $realBat -Destination $Path -Force
    Copy-Item -Path $realPs1 -Destination $Path -Force

    # Onedir bundle subfolder
    $bundle = New-Item -ItemType Directory -Path (Join-Path $Path 'work_timer') -Force
    New-Item -Path (Join-Path $bundle.FullName 'work_timer.exe')       -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $bundle.FullName 'work_timer_quick.exe') -ItemType File -Force | Out-Null
    $int = New-Item -ItemType Directory -Path (Join-Path $bundle.FullName '_internal') -Force
    'dummy' | Out-File (Join-Path $int.FullName 'dummy.dll')

    # Icons (in package root, not inside the bundle)
    New-Item -Path (Join-Path $Path 'Kommen.ico')    -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'Gehen.ico')     -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $Path 'WorkTimer.ico') -ItemType File -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Helper: invoke install.bat via cmd.exe and wait for completion.
#   $BatPath  – full path to install.bat inside the package
#   $FromDir  – working directory for the cmd.exe process (may differ from package dir)
#   Returns the process exit code.
# ---------------------------------------------------------------------------
function Invoke-InstallBat {
    param([string]$BatPath, [string]$FromDir)

    # Redirect stdin from an empty temp file so that cmd's "pause" returns
    # immediately on EOF without blocking the test run.
    $stdinFile  = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList "/c `"$BatPath`"" `
            -WorkingDirectory $FromDir `
            -RedirectStandardInput  $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError  $stderrFile `
            -Wait -PassThru
        return $proc.ExitCode
    } finally {
        Remove-Item $stdinFile,$stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – invoked from its own directory (normal double-click)' {

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:batPath = Join-Path $script:pkg 'install.bat'
        $script:dest    = Join-Path $script:pkg 'test_installed'
        $env:SKIP_COPY  = '1'
    }

    AfterEach {
        $env:SKIP_COPY = $null
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits without error' {
        $code = Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        $code | Should Be 0
    }

    It 'creates the test_installed destination directory' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        Test-Path $script:dest | Should Be $true
    }

    It 'copies work_timer.exe to test_installed' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies work_timer_quick.exe to test_installed' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        Test-Path (Join-Path $script:dest 'work_timer_quick.exe') | Should Be $true
    }

    It 'copies all three icons to test_installed' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    It 'copies _internal sub-directory to test_installed' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – invoked from a DIFFERENT working directory (terminal use)' {
    # Before the fix, install.bat did NOT pass -Source to install.ps1.
    # The installer then used the CWD ($Source = Get-Location) instead of the
    # package directory, so it could not find work_timer.exe and aborted with
    # exit code 1. After the fix, -Source '%~dp0' is passed, so the installer
    # always uses the bat file's own directory regardless of CWD.

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:batPath = Join-Path $script:pkg 'install.bat'
        $script:dest    = Join-Path $script:pkg 'test_installed'
        $env:SKIP_COPY  = '1'

        # A deliberately different CWD — somewhere completely unrelated to the package
        $script:diffCwd = $env:TEMP
    }

    AfterEach {
        $env:SKIP_COPY = $null
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits without error even when CWD differs from package dir' {
        $code = Invoke-InstallBat -BatPath $script:batPath -FromDir $script:diffCwd
        $code | Should Be 0
    }

    It 'creates test_installed in the package directory (not in CWD)' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:diffCwd

        # Destination must be in the PACKAGE dir, not the different CWD
        Test-Path $script:dest | Should Be $true

        # Must NOT have spilled into the unrelated CWD
        Test-Path (Join-Path $script:diffCwd 'test_installed') | Should Be $false
    }

    It 'copies work_timer.exe when run from a different CWD' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:diffCwd
        Test-Path (Join-Path $script:dest 'work_timer.exe') | Should Be $true
    }

    It 'copies all icons when run from a different CWD' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:diffCwd
        foreach ($ico in @('Kommen.ico','Gehen.ico','WorkTimer.ico')) {
            Test-Path (Join-Path $script:dest $ico) | Should Be $true
        }
    }

    It 'copies _internal dir when run from a different CWD' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:diffCwd
        Test-Path (Join-Path $script:dest '_internal\dummy.dll') | Should Be $true
    }
}

# ---------------------------------------------------------------------------
Describe 'install.bat – protected user data survives reinstall' {

    BeforeEach {
        $script:pkg  = Join-Path ([System.IO.Path]::GetTempPath()) "wt_bat_$([System.IO.Path]::GetRandomFileName())"
        New-InstallPackage -Path $script:pkg
        $script:batPath = Join-Path $script:pkg 'install.bat'
        $script:dest    = Join-Path $script:pkg 'test_installed'
        $env:SKIP_COPY  = '1'

        # Simulate a previous install: create protected user files in the destination
        New-Item -ItemType Directory -Path $script:dest -Force | Out-Null
        'user data' | Out-File (Join-Path $script:dest 'arbeitszeiten.csv')
        '{"soll":8}' | Out-File (Join-Path $script:dest 'config.json')
        '{"start":"08:00"}' | Out-File (Join-Path $script:dest 'checkin_state.json')
        'holiday,date' | Out-File (Join-Path $script:dest 'feiertage_2025.csv')
        New-Item -ItemType Directory -Path (Join-Path $script:dest 'reports') -Force | Out-Null
        'pdf stub' | Out-File (Join-Path $script:dest 'reports\report.pdf')
    }

    AfterEach {
        $env:SKIP_COPY = $null
        Remove-Item $script:pkg -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves arbeitszeiten.csv' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        (Get-Content (Join-Path $script:dest 'arbeitszeiten.csv') -Raw) | Should Match 'user data'
    }

    It 'preserves config.json' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        (Get-Content (Join-Path $script:dest 'config.json') -Raw) | Should Match '"soll":8'
    }

    It 'preserves checkin_state.json' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        (Get-Content (Join-Path $script:dest 'checkin_state.json') -Raw) | Should Match '"start":"08:00"'
    }

    It 'preserves feiertage*.csv' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        (Get-Content (Join-Path $script:dest 'feiertage_2025.csv') -Raw) | Should Match 'holiday,date'
    }

    It 'preserves the reports directory' {
        Invoke-InstallBat -BatPath $script:batPath -FromDir $script:pkg
        Test-Path (Join-Path $script:dest 'reports\report.pdf') | Should Be $true
    }
}
