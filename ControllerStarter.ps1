#Requires -Version 5.1
<#
.SYNOPSIS
    Controller Starter - launches Steam when an Xbox controller connects and
    closes the running game plus Steam when it disconnects.

.DESCRIPTION
    Polls XInput for a connected gamepad and drives a small state machine:

        Waiting   -> controller present for connectDebounceSeconds -> launch Steam -> Active
        Active    -> controller absent  for disconnectGraceSeconds -> close game(s) + Steam -> Waiting
        Active    -> Steam exited on its own                       -> Suspended
        Suspended -> controller absent  for disconnectGraceSeconds -> Waiting

    The Suspended state exists so that quitting Steam by hand while the
    controller is still on does not immediately relaunch it in a loop.

.PARAMETER ConfigPath
    Path to config.json. Defaults to config.json next to this script.

.PARAMETER NoHide
    Keep the console window visible (useful for debugging).

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

$script:Root      = $PSScriptRoot
$script:LogDir    = Join-Path $script:Root 'logs'
$script:LogFile   = Join-Path $script:LogDir 'controller-starter.log'
$script:Config    = $null
$script:SteamExe  = $null
$script:SteamRoot = $null

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    if ($script:Config -and -not $script:Config.logEnabled) { return }

    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) {
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
        }

        $maxKB = if ($script:Config) { [int]$script:Config.logMaxSizeKB } else { 1024 }
        if ((Test-Path -LiteralPath $script:LogFile) -and
            ((Get-Item -LiteralPath $script:LogFile).Length -gt ($maxKB * 1KB))) {
            Move-Item -LiteralPath $script:LogFile -Destination "$script:LogFile.1" -Force
        }

        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never take the watcher down.
    }
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

function Get-DefaultConfig {
    [ordered]@{
        steamExePath                                = ''
        steamLaunchArgs                             = @('-bigpicture')
        pollIntervalSeconds                         = 2
        connectDebounceSeconds                      = 2
        disconnectGraceSeconds                      = 20
        launchIfControllerAlreadyConnectedAtStartup = $false
        closeGamesOnDisconnect                      = $true
        closeSteamOnDisconnect                      = $true
        closeSteamOnlyIfLaunchedByThisTool          = $false
        gracefulCloseTimeoutSeconds                 = 15
        steamShutdownTimeoutSeconds                 = 30
        extraGameProcessNames                       = @()
        ignoreProcessNames                          = @('steam', 'steamwebhelper', 'steamerrorreporter', 'gameoverlayui')
        logEnabled                                  = $true
        logMaxSizeKB                                = 1024
    }
}

function Import-Config {
    param([string]$Path)

    $config = Get-DefaultConfig
    if (-not $Path) { $Path = Join-Path $script:Root 'config.json' }
    if (-not (Test-Path -LiteralPath $Path)) { return $config }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Log "config.json could not be parsed, using defaults: $($_.Exception.Message)" 'WARN'
        return $config
    }

    foreach ($key in @($config.Keys)) {
        if ($raw.PSObject.Properties.Name -contains $key) {
            $value = $raw.$key
            if ($null -ne $value) { $config[$key] = $value }
        }
    }
    return $config
}

# ---------------------------------------------------------------------------
# Native interop: XInput + console window
# ---------------------------------------------------------------------------

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ControllerStarterNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct XInputGamepad
    {
        public ushort wButtons;
        public byte bLeftTrigger;
        public byte bRightTrigger;
        public short sThumbLX;
        public short sThumbLY;
        public short sThumbRX;
        public short sThumbRY;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct XInputState
    {
        public uint dwPacketNumber;
        public XInputGamepad Gamepad;
    }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    private static extern int XInputGetState14(int dwUserIndex, out XInputState pState);

    [DllImport("xinput1_3.dll", EntryPoint = "XInputGetState")]
    private static extern int XInputGetState13(int dwUserIndex, out XInputState pState);

    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
    private static extern int XInputGetState910(int dwUserIndex, out XInputState pState);

    // 0 = undecided, 1 = xinput1_4, 2 = xinput1_3, 3 = xinput9_1_0, -1 = none available
    private static int _backend = 0;

    private const int ERROR_DEVICE_NOT_CONNECTED = 1167;

    private static int Query(int index, out XInputState state)
    {
        state = new XInputState();

        if (_backend == 0)
        {
            try { int r = XInputGetState14(index, out state); _backend = 1; return r; }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }

            try { int r = XInputGetState13(index, out state); _backend = 2; return r; }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }

            try { int r = XInputGetState910(index, out state); _backend = 3; return r; }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }

            _backend = -1;
            return ERROR_DEVICE_NOT_CONNECTED;
        }

        switch (_backend)
        {
            case 1: return XInputGetState14(index, out state);
            case 2: return XInputGetState13(index, out state);
            case 3: return XInputGetState910(index, out state);
            default: return ERROR_DEVICE_NOT_CONNECTED;
        }
    }

    public static string Backend
    {
        get
        {
            switch (_backend)
            {
                case 1:  return "xinput1_4.dll";
                case 2:  return "xinput1_3.dll";
                case 3:  return "xinput9_1_0.dll";
                case -1: return "none";
                default: return "undetermined";
            }
        }
    }

    public static int ConnectedCount()
    {
        int count = 0;
        for (int i = 0; i < 4; i++)
        {
            XInputState state;
            if (Query(i, out state) == 0) { count++; }
        }
        return count;
    }

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void HideConsole()
    {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); } // SW_HIDE
    }
}
'@ -ErrorAction Stop

function Test-ControllerConnected {
    try { return ([ControllerStarterNative]::ConnectedCount() -gt 0) }
    catch {
        Write-Log "XInput query failed: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

# ---------------------------------------------------------------------------
# Steam discovery
# ---------------------------------------------------------------------------

function Resolve-SteamExe {
    param([string]$Configured)

    if ($Configured) {
        $candidate = $Configured -replace '/', '\'
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        Write-Log "steamExePath in config does not exist: $Configured" 'WARN'
    }

    $probes = @(
        { (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe },
        { $p = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
          if ($p) { Join-Path $p 'steam.exe' } },
        { $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
          if ($p) { Join-Path $p 'steam.exe' } },
        { 'C:\Program Files (x86)\Steam\steam.exe' },
        { 'C:\Program Files\Steam\steam.exe' }
    )

    foreach ($probe in $probes) {
        $path = & $probe
        if ($path) {
            $path = $path -replace '/', '\'
            if (Test-Path -LiteralPath $path) { return (Resolve-Path -LiteralPath $path).Path }
        }
    }
    return $null
}

function Get-SteamLibraryGameDir {
    # Returns every "<library>\steamapps\common\" folder, so that any running
    # process located underneath one of them can be treated as a Steam game.
    $dirs = New-Object System.Collections.Generic.List[string]
    if (-not $script:SteamRoot) { return $dirs }

    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($script:SteamRoot)

    $vdf = Join-Path $script:SteamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        try {
            $content = Get-Content -LiteralPath $vdf -Raw
            foreach ($match in [regex]::Matches($content, '"path"\s*"([^"]+)"')) {
                $libPath = $match.Groups[1].Value -replace '\\\\', '\'
                if ($libPath -and -not $roots.Contains($libPath)) { $roots.Add($libPath) }
            }
        }
        catch {
            Write-Log "libraryfolders.vdf could not be read: $($_.Exception.Message)" 'WARN'
        }
    }

    foreach ($root in $roots) {
        $common = Join-Path $root 'steamapps\common'
        if (Test-Path -LiteralPath $common) {
            # Normalise before de-duplicating: the registry and libraryfolders.vdf
            # spell the same library with different casing.
            $normalised = ((Resolve-Path -LiteralPath $common).Path.TrimEnd('\') + '\').ToLowerInvariant()
            if (-not $dirs.Contains($normalised)) { $dirs.Add($normalised) }
        }
    }
    return $dirs
}

# ---------------------------------------------------------------------------
# Process handling
# ---------------------------------------------------------------------------

function Get-GameProcess {
    # A process counts as a game only when its executable lives inside a Steam
    # library's common folder, or when its name is listed in
    # extraGameProcessNames. Nothing else is ever touched.
    $result = New-Object System.Collections.Generic.List[object]

    $ignore = @(@($script:Config.ignoreProcessNames) |
                    Where-Object { $_ } |
                    ForEach-Object { ($_ -replace '\.exe$', '').ToLowerInvariant() })
    $extra  = @(@($script:Config.extraGameProcessNames) |
                    Where-Object { $_ } |
                    ForEach-Object { ($_ -replace '\.exe$', '').ToLowerInvariant() })

    $gameDirs = Get-SteamLibraryGameDir

    try {
        $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
    }
    catch {
        Write-Log "Process list could not be read: $($_.Exception.Message)" 'WARN'
        return $result
    }

    foreach ($proc in $processes) {
        if ($proc.ProcessId -le 4) { continue }

        $name = ($proc.Name -replace '\.exe$', '').ToLowerInvariant()
        if ($ignore -contains $name) { continue }

        $isGame = ($extra -contains $name)

        if (-not $isGame -and $proc.ExecutablePath) {
            $exe = $proc.ExecutablePath.ToLowerInvariant()
            foreach ($dir in $gameDirs) {
                if ($exe.StartsWith($dir)) { $isGame = $true; break }
            }
        }

        if ($isGame) {
            $result.Add([pscustomobject]@{
                ProcessId = [int]$proc.ProcessId
                Name      = $proc.Name
                Path      = $proc.ExecutablePath
            })
        }
    }
    return $result
}

function Stop-GameProcess {
    $games = @(Get-GameProcess)
    if ($games.Count -eq 0) {
        Write-Log 'No running Steam game found.'
        return
    }

    foreach ($game in $games) {
        Write-Log "Closing game: $($game.Name) (PID $($game.ProcessId))"
        try {
            $proc = Get-Process -Id $game.ProcessId -ErrorAction Stop
            $null = $proc.CloseMainWindow()
        }
        catch {
            # Already gone, or no message pump; the force pass below handles it.
        }
    }

    $deadline = (Get-Date).AddSeconds([int]$script:Config.gracefulCloseTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $alive = @($games | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) {
            Write-Log 'All games closed gracefully.'
            return
        }
        Start-Sleep -Milliseconds 500
    }

    foreach ($game in $games) {
        if (Get-Process -Id $game.ProcessId -ErrorAction SilentlyContinue) {
            Write-Log "Game did not exit in time, terminating: $($game.Name) (PID $($game.ProcessId))" 'WARN'
            try { Stop-Process -Id $game.ProcessId -Force -ErrorAction Stop }
            catch { Write-Log "Could not terminate PID $($game.ProcessId): $($_.Exception.Message)" 'ERROR' }
        }
    }
}

function Test-SteamRunning {
    return [bool](Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
}

function Start-Steam {
    if (-not $script:SteamExe) {
        Write-Log 'Steam executable not found, cannot launch.' 'ERROR'
        return $false
    }

    $steamArgs = @(@($script:Config.steamLaunchArgs) | Where-Object { $_ })

    if (Test-SteamRunning) {
        Write-Log 'Steam is already running.'
        if ($steamArgs -contains '-bigpicture') {
            try {
                Start-Process 'steam://open/bigpicture' | Out-Null
                Write-Log 'Big Picture requested.'
            }
            catch { Write-Log "Big Picture could not be opened: $($_.Exception.Message)" 'WARN' }
        }
        return $true
    }

    try {
        if ($steamArgs.Count -gt 0) {
            Write-Log "Launching Steam: $script:SteamExe $($steamArgs -join ' ')"
            Start-Process -FilePath $script:SteamExe -ArgumentList $steamArgs | Out-Null
        }
        else {
            Write-Log "Launching Steam: $script:SteamExe"
            Start-Process -FilePath $script:SteamExe | Out-Null
        }
        return $true
    }
    catch {
        Write-Log "Steam could not be launched: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Stop-Steam {
    if (-not (Test-SteamRunning)) {
        Write-Log 'Steam is not running.'
        return
    }

    if (-not $script:SteamExe) {
        Write-Log 'Steam executable unknown, cannot request a clean shutdown.' 'WARN'
    }
    else {
        Write-Log 'Requesting Steam shutdown (steam.exe -shutdown).'
        try { Start-Process -FilePath $script:SteamExe -ArgumentList '-shutdown' | Out-Null }
        catch { Write-Log "Shutdown request failed: $($_.Exception.Message)" 'WARN' }
    }

    $deadline = (Get-Date).AddSeconds([int]$script:Config.steamShutdownTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-SteamRunning)) {
            Write-Log 'Steam closed cleanly.'
            return
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Log 'Steam did not exit in time, terminating.' 'WARN'
    foreach ($name in @('steam', 'steamwebhelper')) {
        try { Stop-Process -Name $name -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# ---------------------------------------------------------------------------
# Session actions
# ---------------------------------------------------------------------------

function Start-Session {
    Write-Log '--- Controller connected ---'
    $launched = Start-Steam
    $script:SteamLaunchedByUs = $launched
    return $launched
}

function Stop-Session {
    Write-Log '--- Controller disconnected ---'

    if ($script:Config.closeGamesOnDisconnect) { Stop-GameProcess }
    else { Write-Log 'closeGamesOnDisconnect is false, leaving games running.' }

    if (-not $script:Config.closeSteamOnDisconnect) {
        Write-Log 'closeSteamOnDisconnect is false, leaving Steam running.'
        return
    }
    if ($script:Config.closeSteamOnlyIfLaunchedByThisTool -and -not $script:SteamLaunchedByUs) {
        Write-Log 'Steam was not launched by this tool, leaving it running.'
        return
    }
    Stop-Steam
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

$script:Config            = Import-Config -Path $ConfigPath
$script:SteamExe          = Resolve-SteamExe -Configured $script:Config.steamExePath
$script:SteamLaunchedByUs = $false
if ($script:SteamExe) { $script:SteamRoot = Split-Path -Parent $script:SteamExe }

if ($Once) {
    $games = @(Get-GameProcess)
    Write-Host ''
    Write-Host 'Controller Starter - status'
    Write-Host '---------------------------'
    Write-Host ('Controller connected : {0}' -f (Test-ControllerConnected))
    Write-Host ('Pads detected        : {0}' -f [ControllerStarterNative]::ConnectedCount())
    Write-Host ('XInput backend       : {0}' -f [ControllerStarterNative]::Backend)
    Write-Host ('Steam executable     : {0}' -f $(if ($script:SteamExe) { $script:SteamExe } else { 'NOT FOUND' }))
    Write-Host ('Steam running        : {0}' -f (Test-SteamRunning))
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

if (-not $NoHide) {
    try { [ControllerStarterNative]::HideConsole() } catch { }
}

try {
    Write-Log '==========================================='
    Write-Log 'Controller Starter started.'
    Write-Log "Steam executable: $(if ($script:SteamExe) { $script:SteamExe } else { 'NOT FOUND' })"
    Write-Log ('Grace period: {0}s, poll interval: {1}s' -f `
        $script:Config.disconnectGraceSeconds, $script:Config.pollIntervalSeconds)

    $state             = 'Waiting'
    $connectedSince    = $null
    $disconnectedSince = $null
    $steamMissingSince = $null
    $sessionStartedAt  = $null

    if (Test-ControllerConnected) {
        if ($script:Config.launchIfControllerAlreadyConnectedAtStartup) {
            Write-Log 'Controller already connected at startup; Steam will be launched.'
        }
        else {
            Write-Log 'Controller already connected at startup; waiting for a reconnect before launching Steam.'
            $state = 'Suspended'
        }
    }

    while ($true) {
        $connected = Test-ControllerConnected
        $now       = Get-Date

        if ($connected) {
            $disconnectedSince = $null
            if (-not $connectedSince) { $connectedSince = $now }
        }
        else {
            $connectedSince = $null
            if (-not $disconnectedSince) {
                $disconnectedSince = $now
                if ($state -eq 'Active') {
                    Write-Log ('Controller lost; closing in {0}s unless it comes back.' -f `
                        $script:Config.disconnectGraceSeconds)
                }
            }
        }

        switch ($state) {

            'Waiting' {
                if ($connected -and
                    ($now - $connectedSince).TotalSeconds -ge [int]$script:Config.connectDebounceSeconds) {
                    if (Start-Session) {
                        $state             = 'Active'
                        $sessionStartedAt  = $now
                        $steamMissingSince = $null
                    }
                    else {
                        # Launch failed: park until the controller cycles, so we
                        # do not retry in a tight loop.
                        $state = 'Suspended'
                    }
                }
            }

            'Active' {
                if (-not $connected -and
                    ($now - $disconnectedSince).TotalSeconds -ge [int]$script:Config.disconnectGraceSeconds) {
                    Stop-Session
                    $state                    = 'Waiting'
                    $script:SteamLaunchedByUs = $false
                    $steamMissingSince        = $null
                }
                elseif ($connected -and ($now - $sessionStartedAt).TotalSeconds -ge 45) {
                    # Steam closed by the user while the controller stayed on.
                    if (Test-SteamRunning) {
                        $steamMissingSince = $null
                    }
                    elseif (-not $steamMissingSince) {
                        $steamMissingSince = $now
                    }
                    elseif (($now - $steamMissingSince).TotalSeconds -ge 10) {
                        Write-Log 'Steam was closed manually; suspending until the controller reconnects.'
                        $state                    = 'Suspended'
                        $script:SteamLaunchedByUs = $false
                        $steamMissingSince        = $null
                    }
                }
            }

            'Suspended' {
                if (-not $connected -and
                    ($now - $disconnectedSince).TotalSeconds -ge [int]$script:Config.disconnectGraceSeconds) {
                    Write-Log 'Controller is off; armed again.'
                    $state = 'Waiting'
                }
            }
        }

        Start-Sleep -Seconds ([Math]::Max(1, [int]$script:Config.pollIntervalSeconds))
    }
}
finally {
    Write-Log 'Controller Starter stopped.'
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
