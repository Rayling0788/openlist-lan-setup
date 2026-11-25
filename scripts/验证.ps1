$ErrorActionPreference = 'Stop'
# 按实际安装目录修改；确保 python 在 PATH 中，或改为本机 python.exe 路径
$root = 'D:\openlist'
$pythonExe = 'python'

$items = Import-Clixml (Join-Path $root 'maintenance\accounts.dpapi.xml')
$payload = @{}
foreach ($name in @('admin', 'reader')) {
    $payload[$name] = ([Net.NetworkCredential]::new('', $items[$name])).Password
}
$payload | ConvertTo-Json -Compress | & $pythonExe (Join-Path $root 'maintenance\validate.py') @args
if ($LASTEXITCODE -ne 0) { throw 'Validation failed; see validation.json.' }
$payload.Clear()
