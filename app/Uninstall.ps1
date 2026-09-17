#Requires -Version 5.1
<#
.SYNOPSIS
    Removes Controller Starter's autostart entries and stops the running app.

.PARAMETER KeepRunning
    Remove the autostart entries but leave the current instance running.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [switch]$KeepRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Core.ps1')

Initialize-ControllerStarter -Root $PSScriptRoot

Write-Host ''
Write-Host 'Controller Starter - uninstaller' -ForegroundColor Cyan
Write-Host '--------------------------------'

if (Test-AutoStartEnabled) {
    Disable-AutoStart
    Write-Host 'Autostart removed.' -ForegroundColor Green
}
else {
    Write-Host 'Autostart was not enabled.' -ForegroundColor DarkGray
}

if (-not $KeepRunning) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -and $_.CommandLine -like '*ControllerStarter*' })

    if ($running.Count -eq 0) {
        Write-Host 'Controller Starter is not running.' -ForegroundColor DarkGray
    }
    else {
        foreach ($proc in $running) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                Write-Host "Stopped running instance (PID $($proc.ProcessId))." -ForegroundColor Green
            }
            catch {
                Write-Host "Could not stop PID $($proc.ProcessId): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ''
Write-Host 'Done. The project folder itself was left untouched.'
Write-Host ''
