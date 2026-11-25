$ErrorActionPreference = 'Stop'
# 按实际安装目录、本机局域网 IP、子网与网络适配器名称修改
$root = 'D:\openlist'
$lanIp = '192.168.1.100'
$lanSubnet = '192.168.1.0/24'
$interfaceAlias = '以太网'
$userId = "$env:USERDOMAIN\$env:USERNAME"

$result = Join-Path $root 'maintenance\system-setup-result.json'
try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Windows administrator rights required.' }
    $ip = Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 | Where-Object IPAddress -eq $lanIp
    if (-not $ip -or $ip.PrefixLength -ne 24) { throw 'Approved network does not match.' }
    $old = Get-NetFirewallRule | Where-Object { $_.DisplayName -eq 'openlist' }
    if (-not (Test-Path (Join-Path $root 'backups\original-firewall.xml'))) { $old | Export-Clixml (Join-Path $root 'backups\original-firewall.xml') }
    $old | Disable-NetFirewallRule
    Get-NetFirewallRule -Name 'OpenList-LAN-ReadOnly', 'OpenList-Block-Outside-LAN' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name 'OpenList-LAN-ReadOnly' -DisplayName "OpenList LAN TCP 5244 (Ethernet $lanSubnet)" -Direction Inbound -Action Allow -Enabled True -Profile Any -Program (Join-Path $root 'openlist.exe') -Protocol TCP -LocalPort 5244 -LocalAddress $lanIp -RemoteAddress $lanSubnet -InterfaceAlias $interfaceAlias -EdgeTraversalPolicy Block | Out-Null
    # 以下 CIDR 列表为 192.168.1.0/24 的 IPv4 补集；若你的局域网网段不是 192.168.1.0/24，请重新计算外网阻断网段。
    $outside = @('0.0.0.0/1','128.0.0.0/2','224.0.0.0/3','208.0.0.0/4','200.0.0.0/5','196.0.0.0/6','194.0.0.0/7','193.0.0.0/8','192.0.0.0/9','192.192.0.0/10','192.128.0.0/11','192.176.0.0/12','192.160.0.0/13','192.172.0.0/14','192.170.0.0/15','192.169.0.0/16','192.168.128.0/17','192.168.64.0/18','192.168.32.0/19','192.168.16.0/20','192.168.8.0/21','192.168.4.0/22','192.168.2.0/23','192.168.0.0/24')
    New-NetFirewallRule -Name 'OpenList-Block-Outside-LAN' -DisplayName 'OpenList block sources outside approved LAN' -Direction Inbound -Action Block -Enabled True -Profile Any -Program (Join-Path $root 'openlist.exe') -Protocol TCP -LocalPort 5244 -RemoteAddress $outside -EdgeTraversalPolicy Block | Out-Null
    $startScript = Join-Path $root 'maintenance\启动.ps1'
    $action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`"" -WorkingDirectory $root
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $userId -LogonType S4U -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'OpenList-LAN' -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\start_alist_v3 - 快捷方式.lnk'
    if (Test-Path -LiteralPath $startup) { Move-Item -LiteralPath $startup -Destination (Join-Path $root 'backups\original-startup.lnk') -Force }
    @{ ok = $true; firewall = "$lanSubnet TCP 5244 Ethernet only"; startup = 'OpenList-LAN startup S4U limited' } | ConvertTo-Json | Set-Content $result -Encoding UTF8
} catch {
    @{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json | Set-Content $result -Encoding UTF8
    exit 1
}
