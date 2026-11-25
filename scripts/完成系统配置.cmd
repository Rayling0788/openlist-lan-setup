@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0配置防火墙与开机启动.ps1"
if errorlevel 1 (echo Configuration failed. Check system-setup-result.json.) else (echo Firewall and startup configuration completed.)
pause
