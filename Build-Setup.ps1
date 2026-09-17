#Requires -Version 5.1
<#
.SYNOPSIS
    Builds ControllerStarterSetup.exe, the single-file installer.

.DESCRIPTION
    Compiles the launcher, stages the application files, packs them into a ZIP,
    and embeds that ZIP as a managed resource inside the installer executable.
    The result needs no external files: running it extracts the application,
    creates shortcuts and registers an entry under Programs and Features.

    Uses the C# compiler bundled with the .NET Framework, so nothing has to be
    installed.

.PARAMETER SkipLauncher
    Reuse the existing ControllerStarter.exe instead of rebuilding it.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [switch]$SkipLauncher
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src\Core.ps1')

$Source   = Join-Path $PSScriptRoot 'installer\Setup.cs'
$IconFile = Join-Path $PSScriptRoot 'build\app.ico'
$Output   = Join-Path $PSScriptRoot 'ControllerStarterSetup.exe'
$Payload  = Join-Path $env:TEMP ('cs-payload-' + [Guid]::NewGuid().ToString('N') + '.zip')

# Files that make up an installed copy of the application.
$PayloadItems = @(
    'ControllerStarterApp.ps1',
    'ControllerStarter.ps1',
    'ControllerStarter.exe',
    'Install.ps1',
    'Uninstall.ps1',
    'config.json',
    'LICENSE',
    'README.md',
    'README.tr.md',
    'src\Core.ps1'
)

if (-not (Test-Path -LiteralPath $Source)) { throw "Installer source not found: $Source" }

$csc = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) { throw 'csc.exe (.NET Framework 4.x compiler) not found.' }

Write-Host ''
Write-Host 'Controller Starter - installer build' -ForegroundColor Cyan
Write-Host '-----------------------------------'

# --- 1. Launcher --------------------------------------------------------
if (-not $SkipLauncher) {
    Write-Host 'Building the launcher...'
    & (Join-Path $PSScriptRoot 'Build-Exe.ps1') | Out-Null
}
if (-not (Test-Path -LiteralPath $IconFile)) {
    [void](Save-GamepadIcoFile -Path $IconFile)
}

# --- 2. Pack the payload -----------------------------------------------
# Built with ZipArchive rather than Compress-Archive: the latter writes entry
# names with backslashes, which the ZIP specification does not allow.
Write-Host 'Packing payload...'
Add-Type -AssemblyName System.IO.Compression.FileSystem

try {
    if (Test-Path -LiteralPath $Payload) { Remove-Item -LiteralPath $Payload -Force }

    $archive = [System.IO.Compression.ZipFile]::Open($Payload, 'Create')
    try {
        foreach ($item in $PayloadItems) {
            $sourcePath = Join-Path $PSScriptRoot $item
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                throw "Payload file missing: $item"
            }

            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $sourcePath, ($item -replace '\\', '/'), 'Optimal')
        }
    }
    finally {
        $archive.Dispose()
    }

    $payloadKb = [Math]::Round((Get-Item -LiteralPath $Payload).Length / 1KB, 1)
    Write-Host "Payload           : $($PayloadItems.Count) files, $payloadKb KB"

    # --- 3. Compile -----------------------------------------------------
    Write-Host 'Compiling installer...'
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu `
           /reference:System.dll `
           /reference:System.Drawing.dll `
           /reference:System.Windows.Forms.dll `
           /reference:System.IO.Compression.dll `
           /reference:System.IO.Compression.FileSystem.dll `
           "/resource:$Payload,payload.zip" `
           "/win32icon:$IconFile" `
           "/out:$Output" $Source

    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $Payload) { Remove-Item -LiteralPath $Payload -Force }
}

$size = [Math]::Round((Get-Item -LiteralPath $Output).Length / 1KB, 1)
Write-Host ''
Write-Host "Built ControllerStarterSetup.exe ($size KB)." -ForegroundColor Green
Write-Host ''
