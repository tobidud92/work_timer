@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem '%~dp0' | Unblock-File; & '%~dp0install.ps1' -Source '%~dp0'"
pause
