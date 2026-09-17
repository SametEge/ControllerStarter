#Requires -Version 5.1
<#
.SYNOPSIS
    Command-line install: enables autostart and launches the tray app.

.DESCRIPTION
    The usual way to install is Setup.bat, which offers the same choices in a
    window. This script exists for unattended or scripted setups.

.PARAMETER NoAutoStart
    Start the tray app now, but do not register it to run at logon.

.PARAMETER NoStart
    Register autostart only; do not launch the app right away.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [switch]$NoAutoStart,
    [switch]$NoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Core.ps1')

Initialize-ControllerStarter -Root $PSScriptRoot

$AppScript  = Join-Path $PSScriptRoot 'ControllerStarterApp.ps1'
$PowerShell = Join-Path $PSHOME 'powershell.exe'
$Arguments  = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $AppScript

if (-not (Test-Path -LiteralPath $AppScript)) {
    throw "ControllerStarterApp.ps1 not found next to this installer: $AppScript"
}

Write-Host ''
Write-Host 'Controller Starter - installer' -ForegroundColor Cyan
Write-Host '------------------------------'
Write-Host "App    : $AppScript"
Write-Host "Steam  : $(if ($Global:CS.SteamExe) { $Global:CS.SteamExe } else { 'NOT FOUND' })"

if ($NoAutoStart) {
    Write-Host 'Autostart skipped (-NoAutoStart).' -ForegroundColor DarkGray
}
else {
    $method = Enable-AutoStart -TargetScript $AppScript
    if ($method -eq 'Task') {
        Write-Host "Autostart enabled via scheduled task 'ControllerStarter'." -ForegroundColor Green
    }
    else {
        Write-Host 'Autostart enabled via a Startup folder shortcut.' -ForegroundColor Green
    }
}

if (-not $NoStart) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -and $_.CommandLine -like '*ControllerStarter*' })

    if ($running.Count -gt 0) {
        Write-Host 'Controller Starter is already running.' -ForegroundColor Yellow
    }
    else {
        Start-Process -FilePath $PowerShell `
                      -ArgumentList $Arguments `
                      -WorkingDirectory $PSScriptRoot `
                      -WindowStyle Hidden | Out-Null
        Write-Host 'Controller Starter started (look for the tray icon).' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Done. Turn your controller on to test it.'
Write-Host "Logs : $($Global:CS.LogFile)"
Write-Host ''
