$ErrorActionPreference = 'Stop'
# 按实际安装目录修改；确保 python 在 PATH 中，或改为本机 python.exe 路径
$root = 'D:\openlist'
$pythonExe = 'python'
$userId = "$env:USERDOMAIN\$env:USERNAME"

$credentialFile = Join-Path $root 'maintenance\accounts.dpapi.xml'
if (Test-Path -LiteralPath $credentialFile) { throw 'Credential file already exists; refusing to reset passwords twice.' }
function New-Password {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes)
}
$accounts = @{ admin = (New-Password); reader = (New-Password) }
$protected = @{}
foreach ($name in $accounts.Keys) { $protected[$name] = ConvertTo-SecureString $accounts[$name] -AsPlainText -Force }
$protected | Export-Clixml -LiteralPath $credentialFile
& icacls $credentialFile /inheritance:r /grant:r "${userId}:F" 'SYSTEM:F' 'BUILTIN\Administrators:F' | Out-Null
# Build offline database changes without passwords in arguments, console output or logs.
$payload = $accounts | ConvertTo-Json -Compress
$payload | & $pythonExe (Join-Path $root 'maintenance\accounts.py')
if ($LASTEXITCODE -ne 0) { throw 'Account configuration failed.' }
$accounts.Clear()
Write-Output 'Administrator and read-only reader configured; credentials protected with Windows DPAPI.'
