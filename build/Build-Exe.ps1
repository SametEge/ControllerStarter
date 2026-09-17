#Requires -Version 5.1
<#
.SYNOPSIS
    Compiles app\ControllerStarter.exe from src\Launcher.cs.

.DESCRIPTION
    Generates the gamepad .ico from the same drawing code the tray icon uses,
    then compiles the launcher with the C# compiler that ships with the .NET
    Framework, so nothing has to be installed. The result is a small
    Windows-subsystem executable that starts the tray app with no console
    window at all.

    IMPORTANT: the output is unsigned. Windows 11 with Smart App Control
    enabled refuses to run unsigned executables ("Application Control policy
    blocked this file"). Compiling still works; only launching is blocked.
    Run this script with -CheckPolicy to see the current setting.

.PARAMETER CheckPolicy
    Report the Smart App Control state and exit without building.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [switch]$CheckPolicy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot

. (Join-Path $Repo 'app\Core.ps1')

function Get-SmartAppControlState {
    try {
        $value = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
                    -Name VerifiedAndReputablePolicyState -ErrorAction Stop).VerifiedAndReputablePolicyState
        switch ($value) {
            0 { return 'Off' }
            1 { return 'On (enforcing)' }
            2 { return 'Evaluation mode' }
            default { return "Unknown ($value)" }
        }
    }
    catch {
        return 'Not present (older Windows build)'
    }
}

$policy = Get-SmartAppControlState

if ($CheckPolicy) {
    Write-Host ''
    Write-Host "Smart App Control : $policy"
    if ($policy -like 'On*') {
        Write-Host ''
        Write-Host 'Unsigned executables are blocked on this machine.' -ForegroundColor Yellow
        Write-Host 'Windows Security -> App & browser control -> Smart App Control.' -ForegroundColor Yellow
        Write-Host 'Turning it off cannot be undone without reinstalling Windows.' -ForegroundColor Yellow
    }
    Write-Host ''
    return
}

$Source   = Join-Path $Repo 'src\Launcher.cs'
$IconFile = Join-Path $PSScriptRoot 'app.ico'
$Output   = Join-Path $Repo 'app\ControllerStarter.exe'

if (-not (Test-Path -LiteralPath $Source)) { throw "Source file not found: $Source" }

$csc = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) { throw 'csc.exe (.NET Framework 4.x compiler) not found.' }

Write-Host ''
Write-Host 'Controller Starter - launcher build' -ForegroundColor Cyan
Write-Host '-----------------------------------'
Write-Host "Compiler          : $csc"
Write-Host "Source            : $Source"
Write-Host "Output            : $Output"
Write-Host "Smart App Control : $policy"
Write-Host ''

Write-Host 'Generating icon...'
[void](Save-GamepadIcoFile -Path $IconFile)
Write-Host "Icon              : $IconFile ($([Math]::Round((Get-Item -LiteralPath $IconFile).Length / 1KB, 1)) KB)"

Write-Host 'Compiling...'
& $csc /nologo /target:winexe /optimize+ /platform:anycpu `
       /reference:System.dll /reference:System.Windows.Forms.dll `
       "/win32icon:$IconFile" "/out:$Output" $Source

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

$size = [Math]::Round((Get-Item -LiteralPath $Output).Length / 1KB, 1)
Write-Host ''
Write-Host "Built app\ControllerStarter.exe ($size KB)." -ForegroundColor Green

if ($policy -like 'On*') {
    Write-Host ''
    Write-Host 'Heads up: Smart App Control is enabled, so Windows will refuse to' -ForegroundColor Yellow
    Write-Host 'run this unsigned executable. app\Setup.bat works regardless.' -ForegroundColor Yellow
}

Write-Host ''
