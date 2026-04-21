Describe 'run_install.ps1' {
    It 'calls install.bat in nested folder and passes env vars' {
        $repoRoot = Split-Path -Parent $PSScriptRoot

        # create an isolated test folder for this run
        $testRoot = Join-Path $repoRoot 'pester_runinstall_test'
        if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
        $inner = Join-Path $testRoot 'WorkTimerInstall (1)\WorkTimerInstall'
        New-Item -ItemType Directory -Path $inner -Force | Out-Null

        $bat = Join-Path $inner 'install.bat'
        $marker = Join-Path $inner 'marker.txt'
        $batContent = @'
@echo off
echo CALLED > "%CD%\marker.txt"
echo SKIP_COPY=%SKIP_COPY% >> "%CD%\marker.txt"
echo SKIP_DESKTOP_SHORTCUTS=%SKIP_DESKTOP_SHORTCUTS% >> "%CD%\marker.txt"
'@
        Set-Content -LiteralPath $bat -Value $batContent -Encoding ASCII

        $script = Join-Path $repoRoot 'run_install.ps1'
        # Execute the launcher script pointing it to our isolated inner folder
        & $script -InstallRoot $inner

        try {
            (Test-Path $marker) | Should Be $true
            (Get-Content $marker -Raw) | Should Match 'SKIP_COPY=1'
            (Get-Content $marker -Raw) | Should Match 'SKIP_DESKTOP_SHORTCUTS=1'
        } finally {
            # cleanup test folder
            if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
