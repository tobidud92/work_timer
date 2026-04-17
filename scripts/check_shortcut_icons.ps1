$desktop = [Environment]::GetFolderPath('Desktop')
$w = New-Object -ComObject WScript.Shell
$names = @('Kommen.lnk','Gehen.lnk','WorkTimer.lnk')
foreach ($n in $names) {
    $p = Join-Path $desktop $n
    if (Test-Path $p) {
        $s = $w.CreateShortcut($p)
        Write-Output "$n -> $($s.IconLocation)"
    } else {
        Write-Output "$n -> MISSING"
    }
}
