$ErrorActionPreference = 'Stop'
# 按实际安装目录修改
$root = 'D:\openlist'

try {
    Stop-ScheduledTask -TaskName 'OpenList-LAN'
    Get-CimInstance Win32_Process -Filter "Name='openlist.exe'" | Where-Object ExecutablePath -eq (Join-Path $root 'openlist.exe') | ForEach-Object { Stop-Process -Id $_.ProcessId }
    Start-ScheduledTask -TaskName 'OpenList-LAN'
    @{ ok = $true } | ConvertTo-Json | Set-Content (Join-Path $root 'maintenance\launcher-repair-result.json')
} catch {
    @{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json | Set-Content (Join-Path $root 'maintenance\launcher-repair-result.json')
    exit 1
}
