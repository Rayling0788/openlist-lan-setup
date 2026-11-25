' 按实际安装目录修改路径
Set ws = CreateObject("Wscript.Shell")
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""D:\openlist\maintenance\管理.ps1"" -Action start", 0, False
