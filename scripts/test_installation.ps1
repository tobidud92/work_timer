Param(
    [string]$OutDir = "WorkTimerInstall"
)

Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    Write-Host "Generating installer folder: $OutDir"
    .\scripts\generate_install_folder.ps1 -OutDir $OutDir -Force
    $out = Join-Path $root $OutDir
    $required = @("*.exe","install.bat","*.ico")
    $missing = @()
    foreach ($pat in $required) {
        $found = Get-ChildItem -Path $out -Filter $pat -File -ErrorAction SilentlyContinue
        if (-not $found) { $missing += $pat }
    }
    if ($missing.Count -eq 0) { Write-Host "TEST OK - all required artifacts present"; Exit 0 } else { Write-Error "MISSING: $($missing -join ', ')"; Exit 2 }
} finally { Pop-Location }
