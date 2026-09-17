#Requires -Version 5.1
<#
.SYNOPSIS
    Controller Starter - system tray application.

.DESCRIPTION
    Runs in the background with an icon in the notification area. The icon
    colour reflects what the watcher is doing, the context menu exposes
    settings, pausing and the log, and a setup window offers the
    "start with Windows" choice.

.PARAMETER Setup
    Show the setup window before starting (used by Setup.bat and on first run).

.PARAMETER NoHide
    Keep the console window visible, for debugging.

.NOTES
    Author : Samet Ege
    License: MIT
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$NoHide
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Core.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Claim an identity before any window exists, so the shell files this as
# Controller Starter rather than as PowerShell.
try { [ControllerStarterNative]::SetAppId('SametEge.ControllerStarter') } catch { }

Initialize-ControllerStarter -Root $PSScriptRoot

# ---------------------------------------------------------------------------
# Localisation
# ---------------------------------------------------------------------------

$Texts = @{
    tr = @{
        AppName        = 'Controller Starter'
        Tagline        = "Xbox kontrolcünü açtığında Steam otomatik açılır.`r`nKapattığında açık oyun ve Steam kapanır."
        SetupTitle     = 'Controller Starter - Kurulum'
        SettingsTitle  = 'Controller Starter - Ayarlar'
        StatusHeader   = 'Durum'
        Controller     = 'Kontrolcü'
        Steam          = 'Steam'
        Connected      = 'Bağlı ({0} adet)'
        NotConnected   = 'Bağlı değil'
        NotFound       = 'Bulunamadı'
        OptionsHeader  = 'Seçenekler'
        LanguageLabel  = 'Arayüz dili'
        LangAuto       = 'Otomatik (Windows dili)'
        LangTr         = 'Türkçe'
        LangEn         = 'English'
        AutoStart      = 'Windows başlangıcında çalıştır'
        BigPicture     = "Steam'i Big Picture modunda aç"
        CloseGames     = 'Bağlantı kesilince oyunu kapat'
        CloseSteam     = "Bağlantı kesilince Steam'i kapat"
        Notifications  = 'Bildirim balonları göster'
        GraceLabel     = 'Bağlantı koptuktan sonra bekleme süresi'
        Seconds        = 'saniye'
        GraceHint      = 'Xbox kontrolcüsü 15 dakika hareketsizlikte kendini kapatır.'
        SteamPath      = 'Steam yolu (boş bırakırsan otomatik bulunur)'
        Browse         = 'Gözat...'
        InstallRun     = 'Kur ve Başlat'
        Save           = 'Kaydet'
        Cancel         = 'İptal'
        MenuSettings   = 'Ayarlar...'
        MenuLog        = 'Log dosyasını aç'
        MenuPause      = 'Duraklat'
        MenuResume     = 'Devam et'
        MenuExit       = 'Çıkış'
        TipWaiting     = 'Hazır - kontrolcü bekleniyor'
        TipActive      = 'Oyun oturumu açık'
        TipSuspended   = 'Beklemede - kontrolcüyü kapatıp aç'
        TipPaused      = 'Duraklatıldı'
        BalloonStarted = 'Kontrolcü bağlandı, Steam açılıyor.'
        BalloonClosed  = 'Kontrolcü kapandı, oyun ve Steam kapatıldı.'
        BalloonLost    = 'Kontrolcü bağlantısı koptu. {0} saniye içinde geri gelmezse kapatılacak.'
        BalloonFailed  = 'Steam başlatılamadı. Ayarlardan Steam yolunu kontrol et.'
        AlreadyRunning = 'Controller Starter zaten çalışıyor. Simgesini saat yanındaki bildirim alanında bulabilirsin.'
        SetupDone      = "Kurulum tamamlandı.`r`n`r`nController Starter artık bildirim alanında çalışıyor. Simgeyi görmüyorsan saatin yanındaki oka tıkla ve simgeyi sürükleyerek sabitle."
        NoSteam        = "Steam bulunamadı.`r`n`r`nAyarlar penceresinden steam.exe yolunu elle seçebilirsin."
    }
    en = @{
        AppName        = 'Controller Starter'
        Tagline        = "Steam launches when your Xbox controller connects.`r`nThe running game and Steam close when it disconnects."
        SetupTitle     = 'Controller Starter - Setup'
        SettingsTitle  = 'Controller Starter - Settings'
        StatusHeader   = 'Status'
        Controller     = 'Controller'
        Steam          = 'Steam'
        Connected      = 'Connected ({0})'
        NotConnected   = 'Not connected'
        NotFound       = 'Not found'
        OptionsHeader  = 'Options'
        LanguageLabel  = 'Interface language'
        LangAuto       = 'Automatic (Windows language)'
        LangTr         = 'Türkçe'
        LangEn         = 'English'
        AutoStart      = 'Start with Windows'
        BigPicture     = 'Open Steam in Big Picture mode'
        CloseGames     = 'Close the game on disconnect'
        CloseSteam     = 'Close Steam on disconnect'
        Notifications  = 'Show notification balloons'
        GraceLabel     = 'Wait after the controller drops out'
        Seconds        = 'seconds'
        GraceHint      = 'An Xbox controller powers itself off after 15 minutes idle.'
        SteamPath      = 'Steam path (leave empty to auto-detect)'
        Browse         = 'Browse...'
        InstallRun     = 'Install and Start'
        Save           = 'Save'
        Cancel         = 'Cancel'
        MenuSettings   = 'Settings...'
        MenuLog        = 'Open log file'
        MenuPause      = 'Pause'
        MenuResume     = 'Resume'
        MenuExit       = 'Exit'
        TipWaiting     = 'Ready - waiting for a controller'
        TipActive      = 'Game session active'
        TipSuspended   = 'On hold - cycle the controller'
        TipPaused      = 'Paused'
        BalloonStarted = 'Controller connected, launching Steam.'
        BalloonClosed  = 'Controller off, game and Steam closed.'
        BalloonLost    = 'Controller lost. Closing in {0} seconds unless it comes back.'
        BalloonFailed  = 'Steam could not be launched. Check the Steam path in Settings.'
        AlreadyRunning = 'Controller Starter is already running. Look for its icon in the notification area.'
        SetupDone      = "Setup complete.`r`n`r`nController Starter now runs in the notification area. If you cannot see the icon, click the arrow next to the clock and drag the icon out to pin it."
        NoSteam        = "Steam was not found.`r`n`r`nYou can pick steam.exe manually from the Settings window."
    }
}

$LanguageCodes = @('auto', 'tr', 'en')

function Resolve-Language {
    # 'auto' follows Windows; anything unknown falls back to English.
    $lang = [string]$Global:CS.Config.language
    if (-not $lang -or $lang -eq 'auto') {
        $lang = if ((Get-Culture).TwoLetterISOLanguageName -eq 'tr') { 'tr' } else { 'en' }
    }
    if (-not $Texts.ContainsKey($lang)) { $lang = 'en' }
    return $lang
}

$script:T = $Texts[(Resolve-Language)]

# ---------------------------------------------------------------------------
# Icons (drawn by New-GamepadIcon in Core.ps1)
# ---------------------------------------------------------------------------

$IconActive    = New-GamepadIcon -Color ([System.Drawing.Color]::FromArgb(255, 76, 175, 80))
$IconWaiting   = New-GamepadIcon -Color ([System.Drawing.Color]::FromArgb(255, 158, 158, 158))
$IconSuspended = New-GamepadIcon -Color ([System.Drawing.Color]::FromArgb(255, 255, 167, 38))

# ---------------------------------------------------------------------------
# Settings / setup window
# ---------------------------------------------------------------------------

function Show-SettingsDialog {
    param([switch]$IsSetup)

    $font      = New-Object System.Drawing.Font('Segoe UI', 9)
    $fontBold  = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $fontHint  = New-Object System.Drawing.Font('Segoe UI', 8)
    $muted     = [System.Drawing.Color]::FromArgb(255, 110, 110, 115)

    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = if ($IsSetup) { $T.SetupTitle } else { $T.SettingsTitle }
    $form.Size            = New-Object System.Drawing.Size(470, 600)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.StartPosition   = 'CenterScreen'
    $form.BackColor       = [System.Drawing.Color]::White
    $form.Font            = $font
    $form.Icon            = $IconActive
    # This is a tray application; its settings window does not belong in the
    # taskbar, where it would otherwise sit under a PowerShell button.
    $form.ShowInTaskbar   = $false
    $form.TopMost         = $true

    $y = 18

    # --- Header --------------------------------------------------------
    $picture          = New-Object System.Windows.Forms.PictureBox
    $picture.Image    = $IconActive.ToBitmap()
    $picture.SizeMode = 'Zoom'
    $picture.Location = New-Object System.Drawing.Point(22, $y)
    $picture.Size     = New-Object System.Drawing.Size(38, 38)
    $form.Controls.Add($picture)

    $title          = New-Object System.Windows.Forms.Label
    $title.Text     = $T.AppName
    $title.Font     = $fontTitle
    $title.Location = New-Object System.Drawing.Point(70, ($y + 4))
    $title.Size     = New-Object System.Drawing.Size(350, 28)
    $form.Controls.Add($title)

    $y += 46

    $tagline          = New-Object System.Windows.Forms.Label
    $tagline.Text     = $T.Tagline
    $tagline.ForeColor = $muted
    $tagline.Location = New-Object System.Drawing.Point(22, $y)
    $tagline.Size     = New-Object System.Drawing.Size(410, 36)
    $form.Controls.Add($tagline)

    $y += 46

    # --- Status --------------------------------------------------------
    $statusHeader          = New-Object System.Windows.Forms.Label
    $statusHeader.Text     = $T.StatusHeader
    $statusHeader.Font     = $fontBold
    $statusHeader.Location = New-Object System.Drawing.Point(22, $y)
    $statusHeader.Size     = New-Object System.Drawing.Size(200, 18)
    $form.Controls.Add($statusHeader)

    $y += 22

    $padCount   = Get-ConnectedPadCount
    $statusText = '{0,-12}: {1}' -f $T.Controller, $(
        if ($padCount -gt 0) { $T.Connected -f $padCount } else { $T.NotConnected })
    $statusText += "`r`n" + ('{0,-12}: {1}' -f $T.Steam, $(
        if ($Global:CS.SteamExe) { $Global:CS.SteamExe } else { $T.NotFound }))

    $statusBox           = New-Object System.Windows.Forms.Label
    $statusBox.Text      = $statusText
    $statusBox.Font      = New-Object System.Drawing.Font('Consolas', 8.5)
    $statusBox.ForeColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 65)
    $statusBox.BackColor = [System.Drawing.Color]::FromArgb(255, 246, 246, 248)
    $statusBox.Location  = New-Object System.Drawing.Point(22, $y)
    $statusBox.Size      = New-Object System.Drawing.Size(410, 42)
    $statusBox.Padding   = New-Object System.Windows.Forms.Padding(8, 6, 6, 6)
    $form.Controls.Add($statusBox)

    $y += 56

    # --- Options -------------------------------------------------------
    $optionsHeader          = New-Object System.Windows.Forms.Label
    $optionsHeader.Text     = $T.OptionsHeader
    $optionsHeader.Font     = $fontBold
    $optionsHeader.Location = New-Object System.Drawing.Point(22, $y)
    $optionsHeader.Size     = New-Object System.Drawing.Size(200, 18)
    $form.Controls.Add($optionsHeader)

    $y += 24

    $langLabel          = New-Object System.Windows.Forms.Label
    $langLabel.Text     = $T.LanguageLabel
    $langLabel.Location = New-Object System.Drawing.Point(26, ($y + 4))
    $langLabel.Size     = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($langLabel)

    $langBox               = New-Object System.Windows.Forms.ComboBox
    $langBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $langBox.Location      = New-Object System.Drawing.Point(150, $y)
    $langBox.Size          = New-Object System.Drawing.Size(220, 24)
    [void]$langBox.Items.Add($T.LangAuto)
    [void]$langBox.Items.Add($T.LangTr)
    [void]$langBox.Items.Add($T.LangEn)
    $langBox.SelectedIndex = [Math]::Max(0, $LanguageCodes.IndexOf([string]$Global:CS.Config.language))
    $form.Controls.Add($langBox)

    $y += 36

    function New-Check {
        param([string]$Text, [bool]$Checked, [int]$Top)
        $box          = New-Object System.Windows.Forms.CheckBox
        $box.Text     = $Text
        $box.Checked  = $Checked
        $box.Location = New-Object System.Drawing.Point(24, $Top)
        $box.Size     = New-Object System.Drawing.Size(400, 24)
        return $box
    }

    $chkAutoStart = New-Check $T.AutoStart (Test-AutoStartEnabled) $y
    $form.Controls.Add($chkAutoStart); $y += 26

    $chkBigPicture = New-Check $T.BigPicture (@($Global:CS.Config.steamLaunchArgs) -contains '-bigpicture') $y
    $form.Controls.Add($chkBigPicture); $y += 26

    $chkCloseGames = New-Check $T.CloseGames ([bool]$Global:CS.Config.closeGamesOnDisconnect) $y
    $form.Controls.Add($chkCloseGames); $y += 26

    $chkCloseSteam = New-Check $T.CloseSteam ([bool]$Global:CS.Config.closeSteamOnDisconnect) $y
    $form.Controls.Add($chkCloseSteam); $y += 26

    $chkNotify = New-Check $T.Notifications ([bool]$Global:CS.Config.showNotifications) $y
    $form.Controls.Add($chkNotify); $y += 34

    # --- Grace period --------------------------------------------------
    $graceLabel          = New-Object System.Windows.Forms.Label
    $graceLabel.Text     = $T.GraceLabel
    $graceLabel.Location = New-Object System.Drawing.Point(22, ($y + 4))
    $graceLabel.Size     = New-Object System.Drawing.Size(280, 20)
    $form.Controls.Add($graceLabel)

    $graceInput          = New-Object System.Windows.Forms.NumericUpDown
    $graceInput.Minimum  = 0
    $graceInput.Maximum  = 600
    $graceInput.Value    = [int]$Global:CS.Config.disconnectGraceSeconds
    $graceInput.Location = New-Object System.Drawing.Point(310, $y)
    $graceInput.Size     = New-Object System.Drawing.Size(62, 24)
    $form.Controls.Add($graceInput)

    $secondsLabel          = New-Object System.Windows.Forms.Label
    $secondsLabel.Text     = $T.Seconds
    $secondsLabel.Location = New-Object System.Drawing.Point(378, ($y + 4))
    $secondsLabel.Size     = New-Object System.Drawing.Size(60, 20)
    $form.Controls.Add($secondsLabel)

    $y += 26

    $graceHint           = New-Object System.Windows.Forms.Label
    $graceHint.Text      = $T.GraceHint
    $graceHint.Font      = $fontHint
    $graceHint.ForeColor = $muted
    $graceHint.Location  = New-Object System.Drawing.Point(24, $y)
    $graceHint.Size      = New-Object System.Drawing.Size(410, 18)
    $form.Controls.Add($graceHint)

    $y += 30

    # --- Steam path ----------------------------------------------------
    $pathLabel          = New-Object System.Windows.Forms.Label
    $pathLabel.Text     = $T.SteamPath
    $pathLabel.Location = New-Object System.Drawing.Point(22, $y)
    $pathLabel.Size     = New-Object System.Drawing.Size(410, 18)
    $form.Controls.Add($pathLabel)

    $y += 22

    $pathInput          = New-Object System.Windows.Forms.TextBox
    $pathInput.Text     = [string]$Global:CS.Config.steamExePath
    $pathInput.Location = New-Object System.Drawing.Point(24, $y)
    $pathInput.Size     = New-Object System.Drawing.Size(310, 24)
    $form.Controls.Add($pathInput)

    $browse          = New-Object System.Windows.Forms.Button
    $browse.Text     = $T.Browse
    $browse.Location = New-Object System.Drawing.Point(342, ($y - 1))
    $browse.Size     = New-Object System.Drawing.Size(90, 26)
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'steam.exe|steam.exe|*.exe|*.exe'
        if ($dialog.ShowDialog() -eq 'OK') { $pathInput.Text = $dialog.FileName }
    }.GetNewClosure())
    $form.Controls.Add($browse)

    # --- Buttons -------------------------------------------------------
    $ok          = New-Object System.Windows.Forms.Button
    $ok.Text     = if ($IsSetup) { $T.InstallRun } else { $T.Save }
    $ok.Location = New-Object System.Drawing.Point(232, 513)
    $ok.Size     = New-Object System.Drawing.Size(120, 32)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancel          = New-Object System.Windows.Forms.Button
    $cancel.Text     = $T.Cancel
    $cancel.Location = New-Object System.Drawing.Point(360, 513)
    $cancel.Size     = New-Object System.Drawing.Size(74, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $form.Add_Shown({
        $this.Activate()
        try { [ControllerStarterNative]::ForceShow($this.Handle) } catch { }
    })

    $result = $form.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $false
    }

    # --- Apply ---------------------------------------------------------
    $Global:CS.Config.language               = $LanguageCodes[$langBox.SelectedIndex]
    $Global:CS.Config.steamLaunchArgs        = if ($chkBigPicture.Checked) { @('-bigpicture') } else { @() }
    $Global:CS.Config.closeGamesOnDisconnect = $chkCloseGames.Checked
    $Global:CS.Config.closeSteamOnDisconnect = $chkCloseSteam.Checked
    $Global:CS.Config.showNotifications      = $chkNotify.Checked
    $Global:CS.Config.disconnectGraceSeconds = [int]$graceInput.Value
    $Global:CS.Config.steamExePath           = $pathInput.Text.Trim()

    Export-Config -Config $Global:CS.Config
    Update-SteamPaths

    # Re-resolve the string table so a language change takes effect at once.
    $script:T = $Texts[(Resolve-Language)]

    if ($chkAutoStart.Checked) {
        # Always re-register rather than skipping when an entry exists: an older
        # install may point at a different script, and registration is idempotent.
        Enable-AutoStart | Out-Null
    }
    elseif (Test-AutoStartEnabled) {
        Disable-AutoStart
    }

    $form.Dispose()
    return $true
}

# ---------------------------------------------------------------------------
# Single instance
# ---------------------------------------------------------------------------

$mutex = New-Object System.Threading.Mutex($false, 'Global\ControllerStarter_SametEge')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show($T.AlreadyRunning, $T.AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not $NoHide) { Hide-ConsoleWindow }

# ---------------------------------------------------------------------------
# Setup pass
# ---------------------------------------------------------------------------

if ($Setup) {
    if (-not (Show-SettingsDialog -IsSetup)) {
        $mutex.ReleaseMutex(); $mutex.Dispose()
        return
    }

    if (-not $Global:CS.SteamExe) {
        [System.Windows.Forms.MessageBox]::Show($T.NoSteam, $T.AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }

    [System.Windows.Forms.MessageBox]::Show($T.SetupDone, $T.AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

# ---------------------------------------------------------------------------
# Tray icon
# ---------------------------------------------------------------------------

Write-Log '==========================================='
Write-Log 'Controller Starter (tray app) started.'
Write-Log "Steam executable: $(if ($Global:CS.SteamExe) { $Global:CS.SteamExe } else { 'NOT FOUND' })"

$script:State = New-WatcherState
Initialize-WatcherState -State $script:State

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$menuHeader           = $menu.Items.Add($T.AppName)
$menuHeader.Enabled   = $false
$menuHeader.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$menuStatus           = $menu.Items.Add($T.TipWaiting)
$menuStatus.Enabled   = $false

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuSettings = $menu.Items.Add($T.MenuSettings)
$menuLog      = $menu.Items.Add($T.MenuLog)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuPause = $menu.Items.Add($T.MenuPause)
$menuExit  = $menu.Items.Add($T.MenuExit)

$tray             = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon        = $IconWaiting
$tray.Text        = "$($T.AppName) - $($T.TipWaiting)"
$tray.Visible     = $true
$tray.ContextMenuStrip = $menu

function Show-Balloon {
    param([string]$Message, [string]$Icon = 'Info')

    if (-not $Global:CS.Config.showNotifications) { return }
    $tray.BalloonTipTitle = $T.AppName
    $tray.BalloonTipText  = $Message
    $tray.BalloonTipIcon  = $Icon
    $tray.ShowBalloonTip(4000)
}

function Update-TrayVisual {
    $phase = $script:State.Phase

    if ($script:State.Paused) {
        $tray.Icon = $IconSuspended
        $label     = $T.TipPaused
    }
    else {
        switch ($phase) {
            'Active'    { $tray.Icon = $IconActive;    $label = $T.TipActive }
            'Suspended' { $tray.Icon = $IconSuspended; $label = $T.TipSuspended }
            default     { $tray.Icon = $IconWaiting;   $label = $T.TipWaiting }
        }
    }

    $detail = if ($script:State.Connected) { $T.Connected -f $script:State.PadCount } else { $T.NotConnected }
    $menuStatus.Text = "$label  -  $detail"

    $tip = "$($T.AppName) - $label"
    if ($tip.Length -gt 62) { $tip = $tip.Substring(0, 62) }
    $tray.Text = $tip
}

function Update-MenuTexts {
    # Called after the settings dialog, so a language change reaches the menu
    # without restarting the application.
    $menuHeader.Text   = $T.AppName
    $menuSettings.Text = $T.MenuSettings
    $menuLog.Text      = $T.MenuLog
    $menuPause.Text    = if ($script:State.Paused) { $T.MenuResume } else { $T.MenuPause }
    $menuExit.Text     = $T.MenuExit
}

# ---------------------------------------------------------------------------
# Watcher loop, driven by the UI timer
# ---------------------------------------------------------------------------

# Created before the menu handlers, which reference it when settings change.
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(1, [int]$Global:CS.Config.pollIntervalSeconds) * 1000

$timer.Add_Tick({
    try {
        $tickEvent = Invoke-WatcherTick -State $script:State

        switch ($tickEvent) {
            'Started'      { Show-Balloon $T.BalloonStarted }
            'Closed'       { Show-Balloon $T.BalloonClosed }
            'Lost'         { Show-Balloon ($T.BalloonLost -f $Global:CS.Config.disconnectGraceSeconds) 'Warning' }
            'LaunchFailed' { Show-Balloon $T.BalloonFailed 'Error' }
        }

        Update-TrayVisual
    }
    catch {
        Write-Log "Tick failed: $($_.Exception.Message)" 'ERROR'
    }
})

# ---------------------------------------------------------------------------
# Menu behaviour
# ---------------------------------------------------------------------------

$menuSettings.Add_Click({
    if (Show-SettingsDialog) {
        $timer.Interval = [Math]::Max(1, [int]$Global:CS.Config.pollIntervalSeconds) * 1000
        Update-MenuTexts
        Update-TrayVisual
    }
})

$menuLog.Add_Click({
    if (Test-Path -LiteralPath $Global:CS.LogFile) {
        Start-Process notepad.exe $Global:CS.LogFile
    }
})

$menuPause.Add_Click({
    $script:State.Paused = -not $script:State.Paused
    $menuPause.Text = if ($script:State.Paused) { $T.MenuResume } else { $T.MenuPause }
    Write-Log $(if ($script:State.Paused) { 'Paused by user.' } else { 'Resumed by user.' })
    Update-TrayVisual
})

$menuExit.Add_Click({
    Write-Log 'Exit requested from the tray menu.'
    $timer.Stop()
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$tray.Add_DoubleClick({
    if (Show-SettingsDialog) {
        $timer.Interval = [Math]::Max(1, [int]$Global:CS.Config.pollIntervalSeconds) * 1000
        Update-MenuTexts
        Update-TrayVisual
    }
})

Update-TrayVisual
$timer.Start()

try {
    $context = New-Object System.Windows.Forms.ApplicationContext
    [System.Windows.Forms.Application]::Run($context)
}
finally {
    Write-Log 'Controller Starter (tray app) stopped.'
    $timer.Dispose()
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
