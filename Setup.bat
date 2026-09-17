@echo off
rem Opens the setup window: pick your options, choose whether Controller
rem Starter should run at Windows startup, then it installs and starts.
cd /d "%~dp0"
start "" powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0ControllerStarterApp.ps1" -Setup
