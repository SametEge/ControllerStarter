#Requires -Version 5.1
<#
.SYNOPSIS
    Controller Starter - headless watcher (no tray icon).

.DESCRIPTION
    Same engine as the tray application, without a user interface. Useful for
    diagnostics, for running under a service-style host, or on machines where
    a tray icon is not wanted. Most people should use ControllerStarterApp.ps1
    (Setup.bat / ControllerStarter.bat) instead.

.PARAMETER ConfigPath
    Path to config.json. Defaults to config.json next to this script.

.PARAMETER NoHide
    Keep the console window visible.

.PARAMETER Once
    Print a one-shot status report and exit.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$NoHide,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Core.ps1')

Initialize-ControllerStarter -Root $PSScriptRoot -ConfigPath $ConfigPath

if ($Once) {
    $games = @(Get-GameProcess)
    Write-Host ''
    Write-Host 'Controller Starter - status'
    Write-Host '---------------------------'
    Write-Host ('Controller connected : {0}' -f (Test-ControllerConnected))
    Write-Host ('Pads detected        : {0}' -f (Get-ConnectedPadCount))
    Write-Host ('XInput backend       : {0}' -f (Get-XInputBackend))
    Write-Host ('Steam executable     : {0}' -f $(if ($Global:CS.SteamExe) { $Global:CS.SteamExe } else { 'NOT FOUND' }))
    Write-Host ('Steam running        : {0}' -f (Test-SteamRunning))
    Write-Host ('Autostart enabled    : {0}' -f (Test-AutoStartEnabled))
    Write-Host ('Game folders         : {0}' -f ((Get-SteamLibraryGameDir) -join ' | '))
    Write-Host ('Detected games       : {0}' -f $(if ($games.Count) { ($games | ForEach-Object { $_.Name }) -join ', ' } else { '(none)' }))
    Write-Host ''
    return
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\ControllerStarter_SametEge')
if (-not $mutex.WaitOne(0)) {
    Write-Log 'Another Controller Starter instance is already running, exiting.' 'WARN'
    return
}

if (-not $NoHide) { Hide-ConsoleWindow }

try {
    Write-Log '==========================================='
    Write-Log 'Controller Starter (headless) started.'
    Write-Log "Steam executable: $(if ($Global:CS.SteamExe) { $Global:CS.SteamExe } else { 'NOT FOUND' })"
    Write-Log ('Grace period: {0}s, poll interval: {1}s' -f `
        $Global:CS.Config.disconnectGraceSeconds, $Global:CS.Config.pollIntervalSeconds)

    $state = New-WatcherState
    Initialize-WatcherState -State $state

    while ($true) {
        [void](Invoke-WatcherTick -State $state)
        Start-Sleep -Seconds ([Math]::Max(1, [int]$Global:CS.Config.pollIntervalSeconds))
    }
}
finally {
    Write-Log 'Controller Starter (headless) stopped.'
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
