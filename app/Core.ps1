# Controller Starter - shared engine.
#
# Dot-sourced by both ControllerStarter.ps1 (headless) and
# ControllerStarterApp.ps1 (system tray UI). Defines functions only; the
# caller owns the loop.
#
# Author : Samet Ege
# License: MIT

# Shared state container, initialised by Initialize-ControllerStarter.
$Global:CS = @{
    Root       = $null
    LogDir     = $null
    LogFile    = $null
    ConfigPath = $null
    Config     = $null
    SteamExe   = $null
    SteamRoot  = $null
}

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

    if ($Global:CS.Config -and -not $Global:CS.Config.logEnabled) { return }
    if (-not $Global:CS.LogFile) { return }

    try {
        if (-not (Test-Path -LiteralPath $Global:CS.LogDir)) {
            New-Item -ItemType Directory -Path $Global:CS.LogDir -Force | Out-Null
        }

        $maxKB = if ($Global:CS.Config) { [int]$Global:CS.Config.logMaxSizeKB } else { 1024 }
        if ((Test-Path -LiteralPath $Global:CS.LogFile) -and
            ((Get-Item -LiteralPath $Global:CS.LogFile).Length -gt ($maxKB * 1KB))) {
            Move-Item -LiteralPath $Global:CS.LogFile -Destination "$($Global:CS.LogFile).1" -Force
        }

        Add-Content -LiteralPath $Global:CS.LogFile -Value $line -Encoding UTF8
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
        language                                    = 'auto'
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
        showNotifications                           = $true
        extraGameProcessNames                       = @()
        ignoreProcessNames                          = @('steam', 'steamwebhelper', 'steamerrorreporter', 'gameoverlayui')
        logEnabled                                  = $true
        logMaxSizeKB                                = 1024
    }
}

function Import-Config {
    param([string]$Path)

    $config = Get-DefaultConfig
    if (-not $Path) { $Path = $Global:CS.ConfigPath }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $config }

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

function Export-Config {
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Path
    )

    if (-not $Path) { $Path = $Global:CS.ConfigPath }
    $ordered = [ordered]@{}
    foreach ($key in (Get-DefaultConfig).Keys) { $ordered[$key] = $Config[$key] }
    ($ordered | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Log "Settings saved to $Path"
}

# ---------------------------------------------------------------------------
# Native interop: XInput + console window
# ---------------------------------------------------------------------------

if (-not ('ControllerStarterNative' -as [type])) {
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

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    // Without this the process is just powershell.exe as far as the shell is
    // concerned, so anything it shows is filed under PowerShell. Giving it an
    // explicit identity makes Windows treat it as its own application.
    public static void SetAppId(string appId)
    {
        try { SetCurrentProcessExplicitAppUserModelID(appId); }
        catch { }
    }

    public static void HideConsole()
    {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); } // SW_HIDE
    }

    // When a process is started with a hidden window style, Windows applies
    // that STARTUPINFO show command to the first top-level window it creates —
    // which can leave a dialog present but invisible. Forcing SW_SHOW after the
    // form is shown makes it appear regardless of how the process was launched.
    public static void ForceShow(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero) { return; }
        ShowWindow(hWnd, 5); // SW_SHOW
        SetForegroundWindow(hWnd);
    }
}
'@ -ErrorAction Stop
}

function Hide-ConsoleWindow {
    try { [ControllerStarterNative]::HideConsole() } catch { }
}

# ---------------------------------------------------------------------------
# Artwork
#
# The gamepad mark is drawn in code rather than shipped as a binary asset, so
# the tray icon and the launcher's .ico come from one definition.
#
# Loaded here rather than inside the functions: typed parameters and default
# values are bound before a function body runs.
# ---------------------------------------------------------------------------

Add-Type -AssemblyName System.Drawing

function New-GamepadBitmap {
    param(
        [int]$Size = 32,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Everything below is authored on a 32x32 grid and scaled to $Size.
    $g.ScaleTransform($Size / 32, $Size / 32)

    # A flat, wide silhouette with downward grips reads as a gamepad even when
    # Windows scales the icon down to 16 px in the notification area.
    $body = New-Object System.Drawing.SolidBrush($Color)
    $g.FillEllipse($body, 0, 7, 15, 15)    # left grip
    $g.FillEllipse($body, 17, 7, 15, 15)   # right grip
    $g.FillEllipse($body, 1, 14, 11, 13)   # left handle
    $g.FillEllipse($body, 20, 14, 11, 13)  # right handle
    $g.FillRectangle($body, 7, 8, 18, 12)  # centre bridge

    $hole = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 24, 24, 27))
    $g.FillRectangle($hole, 4, 12, 9, 3)   # d-pad, horizontal
    $g.FillRectangle($hole, 7, 9, 3, 9)    # d-pad, vertical
    $g.FillEllipse($hole, 19, 9, 5, 5)     # button
    $g.FillEllipse($hole, 23, 13, 5, 5)    # button

    $body.Dispose()
    $hole.Dispose()
    $g.Dispose()

    return $bitmap
}

function New-GamepadIcon {
    param([Parameter(Mandatory)][System.Drawing.Color]$Color)

    $bitmap = New-GamepadBitmap -Size 32 -Color $Color
    $handle = $bitmap.GetHicon()
    $icon   = [System.Drawing.Icon]::FromHandle($handle)
    $clone  = [System.Drawing.Icon]$icon.Clone()

    [void][ControllerStarterNative]::DestroyIcon($handle)
    $bitmap.Dispose()

    return $clone
}

function ConvertTo-IconDib {
    <#
        Encodes a bitmap as an ICO directory entry in classic DIB form: a
        BITMAPINFOHEADER whose height covers both the colour and mask planes,
        32bpp BGRA rows stored bottom-up, then an all-zero AND mask (the alpha
        channel already carries transparency).
    #>
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $width  = $Bitmap.Width
    $height = $Bitmap.Height

    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $data = $Bitmap.LockBits($rect,
                [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $pixels = New-Object byte[] ($stride * $height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    $Bitmap.UnlockBits($data)

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)

    $writer.Write([uint32]40)                   # biSize
    $writer.Write([int32]$width)                # biWidth
    $writer.Write([int32]($height * 2))         # biHeight: colour plane + mask
    $writer.Write([uint16]1)                    # biPlanes
    $writer.Write([uint16]32)                   # biBitCount
    $writer.Write([uint32]0)                    # biCompression: BI_RGB
    $writer.Write([uint32]($width * $height * 4))
    $writer.Write([int32]0)                     # biXPelsPerMeter
    $writer.Write([int32]0)                     # biYPelsPerMeter
    $writer.Write([uint32]0)                    # biClrUsed
    $writer.Write([uint32]0)                    # biClrImportant

    for ($y = $height - 1; $y -ge 0; $y--) {
        $writer.Write($pixels, $y * $stride, $width * 4)
    }

    $maskStride = [Math]::Floor(($width + 31) / 32) * 4
    $writer.Write((New-Object byte[] ($maskStride * $height)))

    $writer.Flush()
    $bytes = $stream.ToArray()
    $writer.Dispose()
    $stream.Dispose()

    return , $bytes
}

function Save-GamepadIcoFile {
    <#
        Writes a multi-resolution .ico. Sizes up to 128 px are stored as DIBs,
        which every Windows surface can read; only the 256 px entry is PNG
        compressed, which is the convention Vista and later expect.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(255, 76, 175, 80)
    )

    $sizes   = @(16, 24, 32, 48, 64, 128, 256)
    $payload = @()

    foreach ($size in $sizes) {
        $bitmap = New-GamepadBitmap -Size $size -Color $Color

        if ($size -ge 256) {
            $stream = New-Object System.IO.MemoryStream
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            $payload += , $stream.ToArray()
            $stream.Dispose()
        }
        else {
            $payload += , (ConvertTo-IconDib -Bitmap $bitmap)
        }

        $bitmap.Dispose()
    }

    $file   = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter($file)

    $writer.Write([uint16]0)              # reserved
    $writer.Write([uint16]1)              # type: icon
    $writer.Write([uint16]$sizes.Count)

    $offset = 6 + (16 * $sizes.Count)
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension)   # width
        $writer.Write([byte]$dimension)   # height
        $writer.Write([byte]0)            # palette entries
        $writer.Write([byte]0)            # reserved
        $writer.Write([uint16]1)          # colour planes
        $writer.Write([uint16]32)         # bits per pixel
        $writer.Write([uint32]$payload[$i].Length)
        $writer.Write([uint32]$offset)
        $offset += $payload[$i].Length
    }

    foreach ($png in $payload) { $writer.Write($png) }

    $writer.Flush()
    $writer.Dispose()
    $file.Dispose()

    return $Path
}

function Get-ConnectedPadCount {
    try { return [ControllerStarterNative]::ConnectedCount() }
    catch {
        Write-Log "XInput query failed: $($_.Exception.Message)" 'WARN'
        return 0
    }
}

function Test-ControllerConnected {
    return ((Get-ConnectedPadCount) -gt 0)
}

function Get-XInputBackend {
    try { return [ControllerStarterNative]::Backend } catch { return 'unavailable' }
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
    if (-not $Global:CS.SteamRoot) { return $dirs }

    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($Global:CS.SteamRoot)

    $vdf = Join-Path $Global:CS.SteamRoot 'steamapps\libraryfolders.vdf'
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

    $ignore = @(@($Global:CS.Config.ignoreProcessNames) |
                    Where-Object { $_ } |
                    ForEach-Object { ($_ -replace '\.exe$', '').ToLowerInvariant() })
    $extra  = @(@($Global:CS.Config.extraGameProcessNames) |
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

function Wait-WithPump {
    # Sleeps while keeping a WinForms message loop responsive, so the tray icon
    # does not freeze during the long close/shutdown waits.
    param([int]$Milliseconds = 500)

    if ('System.Windows.Forms.Application' -as [type]) {
        [System.Windows.Forms.Application]::DoEvents()
    }
    Start-Sleep -Milliseconds $Milliseconds
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

    $deadline = (Get-Date).AddSeconds([int]$Global:CS.Config.gracefulCloseTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $alive = @($games | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) {
            Write-Log 'All games closed gracefully.'
            return
        }
        Wait-WithPump
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
    if (-not $Global:CS.SteamExe) {
        Write-Log 'Steam executable not found, cannot launch.' 'ERROR'
        return $false
    }

    $steamArgs = @(@($Global:CS.Config.steamLaunchArgs) | Where-Object { $_ })

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
            Write-Log "Launching Steam: $($Global:CS.SteamExe) $($steamArgs -join ' ')"
            Start-Process -FilePath $Global:CS.SteamExe -ArgumentList $steamArgs | Out-Null
        }
        else {
            Write-Log "Launching Steam: $($Global:CS.SteamExe)"
            Start-Process -FilePath $Global:CS.SteamExe | Out-Null
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

    if (-not $Global:CS.SteamExe) {
        Write-Log 'Steam executable unknown, cannot request a clean shutdown.' 'WARN'
    }
    else {
        Write-Log 'Requesting Steam shutdown (steam.exe -shutdown).'
        try { Start-Process -FilePath $Global:CS.SteamExe -ArgumentList '-shutdown' | Out-Null }
        catch { Write-Log "Shutdown request failed: $($_.Exception.Message)" 'WARN' }
    }

    $deadline = (Get-Date).AddSeconds([int]$Global:CS.Config.steamShutdownTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-SteamRunning)) {
            Write-Log 'Steam closed cleanly.'
            return
        }
        Wait-WithPump
    }

    Write-Log 'Steam did not exit in time, terminating.' 'WARN'
    foreach ($name in @('steam', 'steamwebhelper')) {
        try { Stop-Process -Name $name -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

function New-WatcherState {
    [pscustomobject]@{
        Phase             = 'Waiting'
        ConnectedSince    = $null
        DisconnectedSince = $null
        SteamMissingSince = $null
        SessionStartedAt  = $null
        SteamLaunchedByUs = $false
        Paused            = $false
        Connected         = $false
        PadCount          = 0
    }
}

function Initialize-WatcherState {
    param([Parameter(Mandatory)]$State)

    if (Test-ControllerConnected) {
        if ($Global:CS.Config.launchIfControllerAlreadyConnectedAtStartup) {
            Write-Log 'Controller already connected at startup; Steam will be launched.'
        }
        else {
            Write-Log 'Controller already connected at startup; waiting for a reconnect before launching Steam.'
            $State.Phase = 'Suspended'
        }
    }
}

function Invoke-WatcherTick {
    <#
        Advances the state machine by one step. Returns the name of the event
        that occurred this tick, or $null: 'Connected', 'Lost', 'Started',
        'Closed', 'LaunchFailed', 'SteamQuit'.
    #>
    param([Parameter(Mandatory)]$State)

    $padCount  = Get-ConnectedPadCount
    $connected = $padCount -gt 0
    $now       = Get-Date
    $event     = $null

    $wasConnected    = $State.Connected
    $State.Connected = $connected
    $State.PadCount  = $padCount

    if ($connected) {
        $State.DisconnectedSince = $null
        if (-not $State.ConnectedSince) { $State.ConnectedSince = $now }
        if (-not $wasConnected) { $event = 'Connected' }
    }
    else {
        $State.ConnectedSince = $null
        if (-not $State.DisconnectedSince) {
            $State.DisconnectedSince = $now
            if ($State.Phase -eq 'Active') {
                Write-Log ('Controller lost; closing in {0}s unless it comes back.' -f `
                    $Global:CS.Config.disconnectGraceSeconds)
                $event = 'Lost'
            }
        }
    }

    if ($State.Paused) { return $event }

    switch ($State.Phase) {

        'Waiting' {
            if ($connected -and
                ($now - $State.ConnectedSince).TotalSeconds -ge [int]$Global:CS.Config.connectDebounceSeconds) {
                Write-Log '--- Controller connected ---'
                if (Start-Steam) {
                    $State.SteamLaunchedByUs = $true
                    $State.Phase             = 'Active'
                    $State.SessionStartedAt  = $now
                    $State.SteamMissingSince = $null
                    $event                   = 'Started'
                }
                else {
                    # Launch failed: park until the controller cycles, so we do
                    # not retry in a tight loop.
                    $State.Phase = 'Suspended'
                    $event       = 'LaunchFailed'
                }
            }
        }

        'Active' {
            if (-not $connected -and
                ($now - $State.DisconnectedSince).TotalSeconds -ge [int]$Global:CS.Config.disconnectGraceSeconds) {
                Write-Log '--- Controller disconnected ---'

                if ($Global:CS.Config.closeGamesOnDisconnect) { Stop-GameProcess }
                else { Write-Log 'closeGamesOnDisconnect is false, leaving games running.' }

                if (-not $Global:CS.Config.closeSteamOnDisconnect) {
                    Write-Log 'closeSteamOnDisconnect is false, leaving Steam running.'
                }
                elseif ($Global:CS.Config.closeSteamOnlyIfLaunchedByThisTool -and -not $State.SteamLaunchedByUs) {
                    Write-Log 'Steam was not launched by this tool, leaving it running.'
                }
                else {
                    Stop-Steam
                }

                $State.Phase             = 'Waiting'
                $State.SteamLaunchedByUs = $false
                $State.SteamMissingSince = $null
                $event                   = 'Closed'
            }
            elseif ($connected -and ($now - $State.SessionStartedAt).TotalSeconds -ge 45) {
                # Steam closed by the user while the controller stayed on.
                if (Test-SteamRunning) {
                    $State.SteamMissingSince = $null
                }
                elseif (-not $State.SteamMissingSince) {
                    $State.SteamMissingSince = $now
                }
                elseif (($now - $State.SteamMissingSince).TotalSeconds -ge 10) {
                    Write-Log 'Steam was closed manually; suspending until the controller reconnects.'
                    $State.Phase             = 'Suspended'
                    $State.SteamLaunchedByUs = $false
                    $State.SteamMissingSince = $null
                    $event                   = 'SteamQuit'
                }
            }
        }

        'Suspended' {
            if (-not $connected -and
                ($now - $State.DisconnectedSince).TotalSeconds -ge [int]$Global:CS.Config.disconnectGraceSeconds) {
                Write-Log 'Controller is off; armed again.'
                $State.Phase = 'Waiting'
            }
        }
    }

    return $event
}

# ---------------------------------------------------------------------------
# Autostart registration
# ---------------------------------------------------------------------------

$Global:CSTaskName = 'ControllerStarter'

function Get-StartupShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'Controller Starter.lnk'
}

function Test-AutoStartEnabled {
    try {
        if (Get-ScheduledTask -TaskName $Global:CSTaskName -ErrorAction SilentlyContinue) { return $true }
    }
    catch { }
    return (Test-Path -LiteralPath (Get-StartupShortcutPath))
}

function Enable-AutoStart {
    <#
        Registers a logon task pointing at the tray app, falling back to a
        Startup-folder shortcut when the task cannot be created.
    #>
    param([string]$TargetScript)

    if (-not $TargetScript) { $TargetScript = Join-Path $Global:CS.Root 'ControllerStarterApp.ps1' }

    $powershell = Join-Path $PSHOME 'powershell.exe'
    $arguments  = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $TargetScript

    try {
        $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $Global:CS.Root

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

        Register-ScheduledTask -TaskName $Global:CSTaskName `
                               -Action $action `
                               -Trigger $trigger `
                               -Principal $principal `
                               -Settings $settings `
                               -Description 'Launches Steam when an Xbox controller connects and closes the game plus Steam when it disconnects.' `
                               -Force | Out-Null

        Write-Log "Autostart enabled (scheduled task '$Global:CSTaskName')."
        return 'Task'
    }
    catch {
        Write-Log "Scheduled task could not be created, using Startup folder: $($_.Exception.Message)" 'WARN'
    }

    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Get-StartupShortcutPath))
    $shortcut.TargetPath       = $powershell
    $shortcut.Arguments        = $arguments
    $shortcut.WorkingDirectory = $Global:CS.Root
    $shortcut.WindowStyle      = 7
    $shortcut.Description      = 'Controller Starter'
    $shortcut.Save()

    Write-Log 'Autostart enabled (Startup folder shortcut).'
    return 'Startup'
}

function Disable-AutoStart {
    try {
        if (Get-ScheduledTask -TaskName $Global:CSTaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $Global:CSTaskName -Confirm:$false
            Write-Log "Autostart disabled (scheduled task '$Global:CSTaskName' removed)."
        }
    }
    catch {
        Write-Log "Scheduled task could not be removed: $($_.Exception.Message)" 'WARN'
    }

    $shortcut = Get-StartupShortcutPath
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
        Write-Log 'Autostart disabled (Startup shortcut removed).'
    }
}

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

function Initialize-ControllerStarter {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ConfigPath
    )

    $Global:CS.Root       = $Root
    $Global:CS.LogDir     = Join-Path $Root 'logs'
    $Global:CS.LogFile    = Join-Path $Global:CS.LogDir 'controller-starter.log'
    $Global:CS.ConfigPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $Root 'config.json' }
    $Global:CS.Config     = Import-Config -Path $Global:CS.ConfigPath
    $Global:CS.SteamExe   = Resolve-SteamExe -Configured $Global:CS.Config.steamExePath
    $Global:CS.SteamRoot  = if ($Global:CS.SteamExe) { Split-Path -Parent $Global:CS.SteamExe } else { $null }
}

function Update-SteamPaths {
    # Called after settings change, so a new steamExePath takes effect at once.
    $Global:CS.SteamExe  = Resolve-SteamExe -Configured $Global:CS.Config.steamExePath
    $Global:CS.SteamRoot = if ($Global:CS.SteamExe) { Split-Path -Parent $Global:CS.SteamExe } else { $null }
}
