#Requires -Version 5.1
<#
.SYNOPSIS
    Compiles ControllerStarter.exe from build\Launcher.cs.

.DESCRIPTION
    Uses the C# compiler that ships with the .NET Framework, so nothing has to
    be installed. The result is a small Windows-subsystem executable that
    starts ControllerStarter.ps1 without showing a console window.

    The repository already contains a prebuilt ControllerStarter.exe; run this
    only if you changed Launcher.cs or want to build it yourself.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Source = Join-Path $PSScriptRoot 'build\Launcher.cs'
$Output = Join-Path $PSScriptRoot 'ControllerStarter.exe'

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source file not found: $Source"
}

$csc = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) {
    throw 'csc.exe (.NET Framework 4.x compiler) not found. Install the .NET Framework 4 developer tools, or just use the prebuilt ControllerStarter.exe.'
}

Write-Host "Compiler : $csc"
Write-Host "Source   : $Source"
Write-Host "Output   : $Output"
Write-Host ''

& $csc /nologo /target:winexe /optimize+ /platform:anycpu `
       /reference:System.dll /reference:System.Windows.Forms.dll `
       "/out:$Output" $Source

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

$size = [Math]::Round((Get-Item -LiteralPath $Output).Length / 1KB, 1)
Write-Host "Built ControllerStarter.exe ($size KB)." -ForegroundColor Green
