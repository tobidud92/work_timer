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

# Copy the installer script from the install/ folder
$instScript = Join-Path $PSScriptRoot 'install.ps1'
if (Test-Path $instScript) { Copy-Item -Path $instScript -Destination $out -Force }

# Copy any .exe artifacts from common build output locations
$exePatterns = @("dist/*.exe", "build/*.exe")
foreach ($pattern in $exePatterns) {
    $fullPattern = Join-Path $root $pattern
    $found = Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue
    if ($found) { foreach ($f in $found) { Copy-Item $f.FullName $out -Force } ; break }
}

# Copy .ico files from data/ (canonical location)
$icoPattern = Join-Path $root 'data/*.ico'
Get-ChildItem -Path $icoPattern -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $out -Force }

# Copy optional extras (README/license)
$extras = @("README.md","docs/README.md")
foreach ($f in $extras) { if (Test-Path (Join-Path $root $f)) { Copy-Item -Path (Join-Path $root $f) -Destination $out -Force } }

Write-Host "Packaged files into $out"
Get-ChildItem $out

Exit 0
