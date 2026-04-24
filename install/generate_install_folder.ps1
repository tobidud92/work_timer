Param(
    [string]$OutDir = "WorkTimerInstall",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root $OutDir

if (Test-Path $out) {
    if ($Force) { Remove-Item $out -Recurse -Force } else { Remove-Item $out -Recurse -Force }
}
New-Item -Path $out -ItemType Directory | Out-Null

# Copy the installer script and bat launcher from the install/ folder
$instScript = Join-Path $PSScriptRoot 'install.ps1'
if (Test-Path $instScript) { Copy-Item -Path $instScript -Destination $out -Force }
$instBat = Join-Path $PSScriptRoot 'install.bat'
if (Test-Path $instBat) { Copy-Item -Path $instBat -Destination $out -Force }

# --- Copy the onedir bundle (dist/work_timer/) ----------------------------
# The build produces dist/work_timer/ containing work_timer.exe,
# work_timer_quick.exe and all required DLLs / .pyd / _internal/.
$bundleDir = Join-Path $root 'dist\work_timer'
if (Test-Path $bundleDir) {
    $bundleDest = Join-Path $out 'work_timer'
    Copy-Item -Path $bundleDir -Destination $bundleDest -Recurse -Force
    Write-Host "Copied onedir bundle: $bundleDir -> $bundleDest"
} else {
    # Fallback: look for any .exe in dist/ or build/ (legacy onefile builds)
    $exePatterns = @("dist/*.exe", "build/*.exe")
    foreach ($pattern in $exePatterns) {
        $fullPattern = Join-Path $root $pattern
        $found = Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue
        if ($found) { foreach ($f in $found) { Copy-Item $f.FullName $out -Force } ; break }
    }
    Write-Warning "Onedir bundle not found at $bundleDir - copied loose EXE files as fallback."
}

# Copy .ico files from data/ into the onedir bundle directory so robocopy
# handles them during install and the extra ico-copy loop is never triggered.
# Placing them at $out root would cause the extra loop to fire (bundleIco
# check fails), making Copy-FileRetry read from an Explorer-locked source.
$icoPattern = Join-Path $root 'data/*.ico'
$icoDest = if (Test-Path $bundleDest) { $bundleDest } else { $out }
Get-ChildItem -Path $icoPattern -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $icoDest -Force }

# Copy optional extras (README/license)
$extras = @("README.md","docs/README.md")
foreach ($f in $extras) { if (Test-Path (Join-Path $root $f)) { Copy-Item -Path (Join-Path $root $f) -Destination $out -Force } }

Write-Host "Packaged files into $out"
Get-ChildItem $out -Recurse | Select-Object FullName

Exit 0

