$ErrorActionPreference = 'Stop'
# 按实际安装目录和监听 IP 修改
$root = 'D:\openlist'
$lanIp = '192.168.1.100'

Add-Type -AssemblyName System.Windows.Forms
$protected = Import-Clixml -LiteralPath (Join-Path $root 'maintenance\accounts.dpapi.xml')
$form = New-Object Windows.Forms.Form
$form.Text = 'OpenList 本机账号（请保存在密码管理器中）'
$form.Size = New-Object Drawing.Size(660, 260)
$form.StartPosition = 'CenterScreen'
$text = New-Object Windows.Forms.TextBox
$text.Multiline = $true
$text.ReadOnly = $true
$text.Dock = 'Fill'
$text.Font = New-Object Drawing.Font('Microsoft YaHei', 11)
$lines = @("访问：http://${lanIp}:5244", "WebDAV：http://${lanIp}:5244/dav/", '')
foreach ($name in @('admin', 'reader')) {
    $plain = ([System.Net.NetworkCredential]::new('', $protected[$name])).Password
    $lines += "$name ：$plain"
}
$lines += ''; $lines += 'admin 仅用于配置；手机和平板请使用 reader（只读）。'
$text.Lines = $lines
$form.Controls.Add($text)
[void]$form.ShowDialog()
$text.Clear(); $lines = $null; $plain = $null
