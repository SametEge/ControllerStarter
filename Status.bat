@echo off
title Controller Starter - Status
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ControllerStarter.ps1" -Once
echo.
pause
