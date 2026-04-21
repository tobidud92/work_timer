param(
    [string]$ExePath = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\dist\work_timer.exe",
    [string]$DesktopPath = [Environment]::GetFolderPath('Desktop')
)

if (-not (Test-Path $ExePath)) {
    Write-Host "Executable not found at $ExePath" -ForegroundColor Red
    exit 1
}

$WshShell = New-Object -ComObject WScript.Shell

# Kommen shortcut
$kommen = $WshShell.CreateShortcut("$DesktopPath\kommen.lnk")
$kommen.TargetPath = $ExePath
$kommen.Arguments = '--start-now'
$kommen.WorkingDirectory = Split-Path $ExePath
$kommen.IconLocation = $ExePath
$kommen.Save()
Write-Host "Shortcut 'kommen.lnk' created on Desktop." -ForegroundColor Green

# Gehen shortcut
$gehen = $WshShell.CreateShortcut("$DesktopPath\gehen.lnk")
$gehen.TargetPath = $ExePath
$gehen.Arguments = '--end-now'
$gehen.WorkingDirectory = Split-Path $ExePath
$gehen.IconLocation = $ExePath
$gehen.Save()
Write-Host "Shortcut 'gehen.lnk' created on Desktop." -ForegroundColor Green

Write-Host "Done." -ForegroundColor Cyan
