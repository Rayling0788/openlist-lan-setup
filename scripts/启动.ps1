$ErrorActionPreference = 'Stop'
# 按实际安装目录、监听 IP 与网络适配器名称修改
$root = 'D:\openlist'
$lanIp = '192.168.1.100'
$interfaceAlias = '以太网'

$lock = $null
$job = [IntPtr]::Zero
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class OpenListJob {
 [StructLayout(LayoutKind.Sequential)] public struct Basic { public long UserTime,JobTime; public uint Flags; public UIntPtr MinWorking,MaxWorking; public uint ActiveLimit; public UIntPtr Affinity; public uint Priority,Schedule; }
 [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong A,B,C,D,E,F; }
 [StructLayout(LayoutKind.Sequential)] public struct Extended { public Basic Basic; public Io Io; public UIntPtr ProcessMemory,JobMemory,PeakProcessMemory,PeakJobMemory; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateJobObject(IntPtr attrs,string name);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job,int cls,ref Extended info,int size);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
 public static IntPtr Create() { var j=CreateJobObject(IntPtr.Zero,null); var info=new Extended(); info.Basic.Flags=0x2000; if(j==IntPtr.Zero || !SetInformationJobObject(j,9,ref info,Marshal.SizeOf(info))) throw new System.ComponentModel.Win32Exception(); return j; }
}
'@
try {
    $lock = [IO.File]::Open((Join-Path $root 'data\launcher.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $listenerIds = @(Get-NetTCPConnection -LocalPort 5244 -State Listen -ErrorAction SilentlyContinue | Where-Object LocalAddress -eq $lanIp | Select-Object -ExpandProperty OwningProcess)
    $existing = Get-CimInstance Win32_Process -Filter "Name='openlist.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $root 'openlist.exe') -or ((-not $_.ExecutablePath) -and $listenerIds -contains $_.ProcessId) }
    if ($existing) { exit 0 }
    # Wait only for the approved address. A changed DHCP address fails closed.
    for ($i = 0; $i -lt 60; $i++) {
        if (Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -eq $lanIp) { break }
        Start-Sleep -Seconds 5
    }
    if (-not (Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -eq $lanIp)) { throw 'Approved Ethernet address unavailable. Configure DHCP reservation.' }
    # Rotate console logs only at launch, keeping disk activity low.
    foreach ($file in @('console.out.log', 'console.err.log')) {
        $path = Join-Path $root ('data\log\' + $file)
        if (Test-Path -LiteralPath $path) { Move-Item -LiteralPath $path -Destination ($path + '.previous') -Force }
    }
    $job = [OpenListJob]::Create()
    $p = Start-Process -FilePath (Join-Path $root 'openlist.exe') -ArgumentList @('server', '--data', (Join-Path $root 'data')) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'data\log\console.out.log') -RedirectStandardError (Join-Path $root 'data\log\console.err.log')
    if (-not [OpenListJob]::AssignProcessToJobObject($job, $p.Handle)) { $p.Kill(); throw 'Cannot attach OpenList to lifetime job.' }
    $p.WaitForExit(); exit $p.ExitCode
} catch [IO.IOException] {
    exit 0
} finally {
    if ($job -ne [IntPtr]::Zero) { [void][OpenListJob]::CloseHandle($job) }
    if ($lock) { $lock.Dispose() }
}
