@echo off
rem Starts Controller Starter in the notification area (system tray).
cd /d "%~dp0"
start "" powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0ControllerStarterApp.ps1"
