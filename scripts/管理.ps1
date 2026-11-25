param([ValidateSet('start','stop','status','backup','disable')][string]$Action = 'status')
$ErrorActionPreference = 'Stop'
# 按实际安装目录和监听 IP 修改
$root = 'D:\openlist'
$lanIp = '192.168.1.100'

function Get-OpenListProcess {
    $listenerIds = @(Get-NetTCPConnection -LocalPort 5244 -State Listen -ErrorAction SilentlyContinue | Where-Object LocalAddress -eq $lanIp | Select-Object -ExpandProperty OwningProcess)
    # S4U processes may hide ExecutablePath from the interactive user's token.
    Get-CimInstance Win32_Process -Filter "Name='openlist.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $root 'openlist.exe') -or ((-not $_.ExecutablePath) -and $listenerIds -contains $_.ProcessId) }
}
function Start-OpenList {
    $task = Get-ScheduledTask -TaskName 'OpenList-LAN' -ErrorAction SilentlyContinue
    if ($task) { if ($task.State.ToString() -ne 'Running') { Start-ScheduledTask -TaskName 'OpenList-LAN' } }
    else { Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $root 'maintenance\启动.ps1')`"" }
}
function Stop-OpenList {
    if (Get-ScheduledTask -TaskName 'OpenList-LAN' -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName 'OpenList-LAN' }
    for ($attempt = 0; $attempt -lt 20; $attempt++) { if (-not (Get-OpenListProcess)) { return }; Start-Sleep -Milliseconds 200 }
    Get-OpenListProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction Stop }
}
switch ($Action) {
    'start' { Start-OpenList; Write-Output '启动请求已提交。稍后查看状态。' }
    'stop' { Stop-OpenList; Write-Output '服务已停止；下次开机仍会启动。' }
    'disable' { Disable-ScheduledTask -TaskName 'OpenList-LAN' | Out-Null; Stop-OpenList; Write-Output '自启动已取消，服务已停止。' }
    'backup' {
        $wasRunning = @(Get-OpenListProcess).Count -gt 0
        Stop-OpenList
        try {
            $target = Join-Path $root ('backups\manual-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -ItemType Directory -Path $target | Out-Null
            Copy-Item -LiteralPath (Join-Path $root 'data') -Destination $target -Recurse
            Copy-Item -LiteralPath (Join-Path $root 'maintenance\accounts.dpapi.xml') -Destination $target
            Copy-Item -LiteralPath (Join-Path $root 'maintenance\启动.ps1') -Destination $target
            Write-Output ('备份已保存：' + $target)
        } finally { if ($wasRunning) { Start-OpenList } }
    }
    'status' {
        $p = Get-OpenListProcess
        Write-Output ('运行实例数：' + @($p).Count)
        Get-NetTCPConnection -LocalPort 5244 -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table
        Get-ScheduledTask -TaskName 'OpenList-LAN' -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table
        Get-ScheduledTaskInfo -TaskName 'OpenList-LAN' -ErrorAction SilentlyContinue | Select-Object LastRunTime, LastTaskResult | Format-List
        Write-Output "浏览器：http://${lanIp}:5244"
        Write-Output "WebDAV：http://${lanIp}:5244/dav/"
    }
}
