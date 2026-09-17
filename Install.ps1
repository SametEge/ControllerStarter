#Requires -Version 5.1
<#
.SYNOPSIS
    Registers Controller Starter so it runs automatically at logon.

.DESCRIPTION
    Two installation methods are supported:

      Task    - a Scheduled Task triggered at logon (preferred: survives
                restarts cleanly, runs hidden, no console flash).
      Startup - a shortcut in the user's Startup folder (no special rights
                required; used automatically when the task cannot be created).

.PARAMETER Method
    Auto (default), Task or Startup.

.PARAMETER NoStart
    Register only; do not start the watcher right away.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Task', 'Startup')]
    [string]$Method = 'Auto',
    [switch]$NoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName   = 'ControllerStarter'
$Root       = $PSScriptRoot
$ScriptPath = Join-Path $Root 'ControllerStarter.ps1'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Controller Starter.lnk'
$PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "ControllerStarter.ps1 not found next to this installer: $ScriptPath"
}

function Install-AsScheduledTask {
    $action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $Arguments -WorkingDirectory $Root

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $trigger.Delay = 'PT15S'   # let the desktop settle before polling

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                            -LogonType Interactive `
                                            -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -StartWhenAvailable `
                                             -DontStopOnIdleEnd `
                                             -MultipleInstances IgnoreNew `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $TaskName `
                           -Action $action `
                           -Trigger $trigger `
                           -Principal $principal `
                           -Settings $settings `
                           -Description 'Launches Steam when an Xbox controller connects and closes the game plus Steam when it disconnects. (github.com/sametege)' `
                           -Force | Out-Null
}

function Install-AsStartupShortcut {
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath       = $PowerShellExe
    $shortcut.Arguments        = $Arguments
    $shortcut.WorkingDirectory = $Root
    $shortcut.WindowStyle      = 7          # minimized; the script hides itself right after
    $shortcut.Description      = 'Controller Starter'
    $shortcut.Save()
}

Write-Host ''
Write-Host 'Controller Starter - installer' -ForegroundColor Cyan
Write-Host '------------------------------'
Write-Host "Script : $ScriptPath"

$installed = $null

if ($Method -in @('Auto', 'Task')) {
    try {
        Install-AsScheduledTask
        $installed = 'Task'
        Write-Host "Installed as scheduled task '$TaskName' (runs at logon)." -ForegroundColor Green
    }
    catch {
        if ($Method -eq 'Task') { throw }
        Write-Host "Scheduled task could not be created ($($_.Exception.Message))." -ForegroundColor Yellow
        Write-Host 'Falling back to the Startup folder.' -ForegroundColor Yellow
    }
}

if (-not $installed) {
    Install-AsStartupShortcut
    $installed = 'Startup'
    Write-Host "Installed as a Startup shortcut: $ShortcutPath" -ForegroundColor Green
}

if (-not $NoStart) {
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -and $_.CommandLine -like '*ControllerStarter.ps1*' }

    if ($running) {
        Write-Host 'Controller Starter is already running.' -ForegroundColor Yellow
    }
    else {
        Start-Process -FilePath $PowerShellExe `
                      -ArgumentList $Arguments `
                      -WorkingDirectory $Root `
                      -WindowStyle Hidden | Out-Null
        Write-Host 'Controller Starter started.' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Done. Turn your controller on to test it.'
Write-Host "Logs : $(Join-Path $Root 'logs\controller-starter.log')"
Write-Host 'Uninstall with: .\Uninstall.ps1'
Write-Host ''
