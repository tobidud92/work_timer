param(
	[Parameter(Mandatory=$false)]
	[string]$InstallRoot = (Join-Path $PSScriptRoot 'WorkTimerInstall (1)\WorkTimerInstall')
)

if (-not (Test-Path $InstallRoot)) {
	New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}
Set-Location -LiteralPath $InstallRoot
$env:SKIP_COPY='1'
$env:SKIP_DESKTOP_SHORTCUTS='1'
& '.\install.bat'
