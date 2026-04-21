Describe 'install.ps1 (real installer)' {
    BeforeEach {
        # Setup: create an isolated temp folder tree that mimics a downloaded/extracted ZIP
        # Layout:  <testRoot>\source\  <- contains dummy exe + icons
        #          <testRoot>\dest\    <- installer will copy files here
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'work_timer_pester_install'
        if (Test-Path $script:testRoot) { Remove-Item $script:testRoot -Recurse -Force }
        $script:source = Join-Path $script:testRoot 'source'
        $script:dest   = Join-Path $script:testRoot 'dest'
        New-Item -ItemType Directory -Path $script:source -Force | Out-Null

        # Dummy assets — real installer only needs the files to exist, not be valid binaries
        New-Item -Path (Join-Path $script:source 'work_timer.exe') -ItemType File | Out-Null
        New-Item -Path (Join-Path $script:source 'Kommen.ico')     -ItemType File | Out-Null
        New-Item -Path (Join-Path $script:source 'Gehen.ico')      -ItemType File | Out-Null
        New-Item -Path (Join-Path $script:source 'WorkTimer.ico')  -ItemType File | Out-Null
    }

    AfterEach {
        # Teardown: always remove the temp folder, even on failure
        if (Test-Path $script:testRoot) { Remove-Item $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'copies exe and icons to Dest when -Source and -Dest are provided' {
        $installer = Join-Path $script:repoRoot 'code\install.ps1'

        # Run the real installer synchronously; -SkipShortcuts avoids touching the desktop
        & $installer -Source $script:source -Dest $script:dest -SkipShortcuts

        Test-Path $script:dest                                           | Should Be $true
        Test-Path (Join-Path $script:dest 'work_timer.exe')             | Should Be $true
        Test-Path (Join-Path $script:dest 'Kommen.ico')                 | Should Be $true
        Test-Path (Join-Path $script:dest 'Gehen.ico')                  | Should Be $true
        Test-Path (Join-Path $script:dest 'WorkTimer.ico')              | Should Be $true
    }

    It 'creates kommen.bat and gehen.bat wrapper scripts in Dest' {
        $installer = Join-Path $script:repoRoot 'code\install.ps1'
        & $installer -Source $script:source -Dest $script:dest -SkipShortcuts

        Test-Path (Join-Path $script:dest 'kommen.bat') | Should Be $true
        Test-Path (Join-Path $script:dest 'gehen.bat')  | Should Be $true
    }

    It 'creates kommen.vbs and gehen.vbs wrapper scripts in Dest' {
        $installer = Join-Path $script:repoRoot 'code\install.ps1'
        & $installer -Source $script:source -Dest $script:dest -SkipShortcuts

        Test-Path (Join-Path $script:dest 'kommen.vbs') | Should Be $true
        Test-Path (Join-Path $script:dest 'gehen.vbs')  | Should Be $true
    }

    It 'bat wrappers reference the installed exe path' {
        $installer = Join-Path $script:repoRoot 'code\install.ps1'
        & $installer -Source $script:source -Dest $script:dest -SkipShortcuts

        $exeRef = Join-Path $script:dest 'work_timer.exe'
        (Get-Content (Join-Path $script:dest 'kommen.bat') -Raw) | Should Match ([regex]::Escape($exeRef))
        (Get-Content (Join-Path $script:dest 'gehen.bat')  -Raw) | Should Match ([regex]::Escape($exeRef))
    }
}
