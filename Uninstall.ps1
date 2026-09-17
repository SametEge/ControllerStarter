#Requires -Version 5.1
<#
.SYNOPSIS
    Removes Controller Starter's autostart entries and stops the watcher.

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

$TaskName     = 'ControllerStarter'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Controller Starter.lnk'

Write-Host ''
Write-Host 'Controller Starter - uninstaller' -ForegroundColor Cyan
Write-Host '--------------------------------'

# Scheduled task
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' removed." -ForegroundColor Green
    }
    else {
        Write-Host "No scheduled task named '$TaskName'." -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "Scheduled task could not be removed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Startup shortcut
if (Test-Path -LiteralPath $ShortcutPath) {
    Remove-Item -LiteralPath $ShortcutPath -Force
    Write-Host 'Startup shortcut removed.' -ForegroundColor Green
}
else {
    Write-Host 'No Startup shortcut.' -ForegroundColor DarkGray
}

# Running instance
if (-not $KeepRunning) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -and $_.CommandLine -like '*ControllerStarter.ps1*' })

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
