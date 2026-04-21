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

# Choose installer script from several possible locations
$installCandidates = @("code/install.ps1", "code/WorkTimerInstall/install.ps1", "code/install.bat")
$install = $null
foreach ($c in $installCandidates) {
    $p = Join-Path $root $c
    if (Test-Path $p) { $install = $p; break }
}
if ($install) { Copy-Item -Path $install -Destination $out -Force }

# Copy any .exe artifacts from common locations
$exePatterns = @("code/WorkTimerInstall/*.exe","dist/*.exe","build/*.exe")
foreach ($pattern in $exePatterns) {
    $fullPattern = Join-Path $root $pattern
    $matches = Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue
    if ($matches) { foreach ($m in $matches) { Copy-Item $m.FullName $out -Force } ; break }
}

# Copy .ico files — canonical source is data/
$icoPatterns = @("code/WorkTimerInstall/*.ico", "data/*.ico")
foreach ($pattern in $icoPatterns) {
    $fullPattern = Join-Path $root $pattern
    $matches = Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue
    if ($matches) { foreach ($m in $matches) { Copy-Item $m.FullName $out -Force } }
}

# Copy optional extras (README/license)
$extras = @("README.md","docs/README.md")
foreach ($f in $extras) { if (Test-Path (Join-Path $root $f)) { Copy-Item -Path (Join-Path $root $f) -Destination $out -Force } }

Write-Host "Packaged files into $out"
Get-ChildItem $out

Exit 0
