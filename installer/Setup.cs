// Controller Starter - installer.
//
// A single self-contained setup executable. The application payload is a ZIP
// embedded as a managed resource; installing extracts it to the chosen folder,
// creates shortcuts, registers an entry under Programs and Features, and
// optionally enables autostart by delegating to the application's own
// Install.ps1 so there is exactly one autostart mechanism.
//
// Running it with /uninstall performs the reverse.
//
// Targets C# 5 / .NET Framework 4.x, which is what the in-box compiler
// supports. Build with Build-Setup.ps1.
//
// Author : Samet Ege
// License: MIT

using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Controller Starter Setup")]
[assembly: AssemblyProduct("Controller Starter")]
[assembly: AssemblyDescription("Installer for Controller Starter.")]
[assembly: AssemblyCompany("Samet Ege")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Samet Ege - MIT License")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Strings
{
    private static readonly bool Tr =
        CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr";

    public static string Pick(string turkish, string english) { return Tr ? turkish : english; }

    public static string Title { get { return Pick("Controller Starter Kurulumu", "Controller Starter Setup"); } }
    public static string AppName { get { return "Controller Starter"; } }
    public static string Tagline
    {
        get
        {
            return Pick(
                "Xbox kontrolcünü açtığında Steam otomatik açılır.\r\nKapattığında açık oyun ve Steam kapanır.",
                "Steam launches when your Xbox controller connects.\r\nThe running game and Steam close when it disconnects.");
        }
    }
    public static string LocationHeader { get { return Pick("Kurulum konumu", "Install location"); } }
    public static string Browse { get { return Pick("Gözat...", "Browse..."); } }
    public static string OptionsHeader { get { return Pick("Seçenekler", "Options"); } }
    public static string OptAutoStart { get { return Pick("Windows başlangıcında çalıştır", "Start with Windows"); } }
    public static string OptDesktop { get { return Pick("Masaüstü kısayolu oluştur", "Create a desktop shortcut"); } }
    public static string OptLaunch { get { return Pick("Kurulumdan sonra başlat", "Launch after installing"); } }
    public static string Install { get { return Pick("Kur", "Install"); } }
    public static string Cancel { get { return Pick("İptal", "Cancel"); } }
    public static string Close { get { return Pick("Kapat", "Close"); } }
    public static string License { get { return Pick("MIT Lisansı · Samet Ege", "MIT License · Samet Ege"); } }

    public static string StepExtract { get { return Pick("Dosyalar kopyalanıyor...", "Copying files..."); } }
    public static string StepShortcuts { get { return Pick("Kısayollar oluşturuluyor...", "Creating shortcuts..."); } }
    public static string StepRegister { get { return Pick("Kayıt yapılıyor...", "Registering..."); } }
    public static string StepAutoStart { get { return Pick("Otomatik başlatma ayarlanıyor...", "Configuring autostart..."); } }
    public static string StepDone { get { return Pick("Kurulum tamamlandı.", "Installation complete."); } }

    public static string DoneMessage
    {
        get
        {
            return Pick(
                "Controller Starter kuruldu ve bildirim alanında çalışıyor.\r\n\r\nSimgeyi göremiyorsan saatin yanındaki oka tıkla, sonra gamepad simgesini görev çubuğuna sürükleyerek sabitle.",
                "Controller Starter is installed and running in the notification area.\r\n\r\nIf you cannot see the icon, click the arrow next to the clock, then drag the gamepad icon onto the taskbar to pin it.");
        }
    }

    public static string UninstallConfirm
    {
        get
        {
            return Pick(
                "Controller Starter kaldırılsın mı?",
                "Remove Controller Starter?");
        }
    }
    public static string UninstallDone { get { return Pick("Controller Starter kaldırıldı.", "Controller Starter has been removed."); } }
    public static string FailedTitle { get { return Pick("Kurulum başarısız", "Setup failed"); } }
    public static string NeedPowerShell
    {
        get
        {
            return Pick(
                "Windows PowerShell bulunamadı. Controller Starter çalışmak için ona ihtiyaç duyar.",
                "Windows PowerShell was not found. Controller Starter needs it to run.");
        }
    }
}

internal static class Shortcuts
{
    public static void Create(string shortcutPath, string target, string arguments,
                              string workingDirectory, string iconLocation, string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) { return; }

        object shell = Activator.CreateInstance(shellType);
        object link = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                             null, shell, new object[] { shortcutPath });
        Type linkType = link.GetType();

        Set(linkType, link, "TargetPath", target);
        Set(linkType, link, "Arguments", arguments);
        Set(linkType, link, "WorkingDirectory", workingDirectory);
        Set(linkType, link, "Description", description);
        if (!string.IsNullOrEmpty(iconLocation))
        {
            Set(linkType, link, "IconLocation", iconLocation);
        }

        linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
    }

    private static void Set(Type type, object instance, string property, string value)
    {
        type.InvokeMember(property, BindingFlags.SetProperty, null, instance, new object[] { value });
    }
}

internal static class Installer
{
    public const string ProductName = "Controller Starter";
    public const string RegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ControllerStarter";
    public const string PayloadResource = "payload.zip";
    public const string LauncherName = "ControllerStarter.exe";
    public const string UninstallerName = "Uninstall.exe";
    public const string ShortcutName = "Controller Starter.lnk";

    public static string DefaultInstallPath
    {
        get
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                Path.Combine("Programs", ProductName));
        }
    }

    public static string PowerShellPath
    {
        get
        {
            string path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            return File.Exists(path) ? path : null;
        }
    }

    public static void ExtractPayload(string destination)
    {
        Directory.CreateDirectory(destination);

        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream stream = assembly.GetManifestResourceStream(PayloadResource))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("Embedded payload is missing from this installer.");
            }

            using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string target = Path.Combine(destination, entry.FullName);

                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }

                    string parent = Path.GetDirectoryName(target);
                    if (!string.IsNullOrEmpty(parent)) { Directory.CreateDirectory(parent); }

                    entry.ExtractToFile(target, true);
                }
            }
        }
    }

    public static void RegisterUninstallEntry(string installPath)
    {
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RegistryKey))
        {
            if (key == null) { return; }

            string launcher = Path.Combine(installPath, LauncherName);
            string uninstaller = Path.Combine(installPath, UninstallerName);

            key.SetValue("DisplayName", ProductName);
            key.SetValue("DisplayVersion", "1.0.0");
            key.SetValue("Publisher", "Samet Ege");
            key.SetValue("DisplayIcon", launcher);
            key.SetValue("InstallLocation", installPath);
            key.SetValue("UninstallString", "\"" + uninstaller + "\" /uninstall");
            key.SetValue("QuietUninstallString", "\"" + uninstaller + "\" /uninstall /quiet");
            key.SetValue("URLInfoAbout", "https://github.com/SametEge/ControllerStarter");
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            key.SetValue("EstimatedSize", DirectorySizeKb(installPath), RegistryValueKind.DWord);
        }
    }

    private static int DirectorySizeKb(string path)
    {
        try
        {
            long total = 0;
            foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
            {
                total += new FileInfo(file).Length;
            }
            return (int)(total / 1024);
        }
        catch
        {
            return 0;
        }
    }

    public static int RunPowerShell(string scriptPath, string extraArguments, bool wait)
    {
        string powershell = PowerShellPath;
        if (powershell == null) { return -1; }

        string arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \""
                           + scriptPath + "\"";
        if (!string.IsNullOrEmpty(extraArguments)) { arguments += " " + extraArguments; }

        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = powershell,
            Arguments = arguments,
            WorkingDirectory = Path.GetDirectoryName(scriptPath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        Process process = Process.Start(startInfo);
        if (process == null) { return -1; }
        if (!wait) { return 0; }

        process.WaitForExit(60000);
        return process.HasExited ? process.ExitCode : 0;
    }

    public static string StartMenuShortcutPath
    {
        get
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                ShortcutName);
        }
    }

    public static string DesktopShortcutPath
    {
        get
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                ShortcutName);
        }
    }
}

internal sealed class SetupForm : Form
{
    private readonly TextBox _pathBox;
    private readonly CheckBox _autoStart;
    private readonly CheckBox _desktopShortcut;
    private readonly CheckBox _launchAfter;
    private readonly Button _installButton;
    private readonly Button _cancelButton;
    private readonly ProgressBar _progress;
    private readonly Label _statusLabel;
    private readonly Icon _appIcon;

    private bool _installed;

    public SetupForm(Icon appIcon)
    {
        _appIcon = appIcon;

        Text = Strings.Title;
        ClientSize = new Size(460, 396);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9F);
        Icon = appIcon;

        Color muted = Color.FromArgb(110, 110, 115);

        PictureBox picture = new PictureBox
        {
            Image = appIcon.ToBitmap(),
            SizeMode = PictureBoxSizeMode.Zoom,
            Location = new Point(22, 20),
            Size = new Size(42, 42)
        };
        Controls.Add(picture);

        Controls.Add(new Label
        {
            Text = Strings.AppName,
            Font = new Font("Segoe UI", 14F, FontStyle.Bold),
            Location = new Point(76, 24),
            Size = new Size(340, 28)
        });

        Controls.Add(new Label
        {
            Text = Strings.Tagline,
            ForeColor = muted,
            Location = new Point(24, 72),
            Size = new Size(412, 36)
        });

        Controls.Add(new Label
        {
            Text = Strings.LocationHeader,
            Font = new Font("Segoe UI", 9F, FontStyle.Bold),
            Location = new Point(24, 122),
            Size = new Size(240, 18)
        });

        _pathBox = new TextBox
        {
            Text = Installer.DefaultInstallPath,
            Location = new Point(26, 144),
            Size = new Size(310, 24)
        };
        Controls.Add(_pathBox);

        Button browse = new Button
        {
            Text = Strings.Browse,
            Location = new Point(344, 143),
            Size = new Size(92, 26)
        };
        browse.Click += OnBrowse;
        Controls.Add(browse);

        Controls.Add(new Label
        {
            Text = Strings.OptionsHeader,
            Font = new Font("Segoe UI", 9F, FontStyle.Bold),
            Location = new Point(24, 186),
            Size = new Size(240, 18)
        });

        _autoStart = NewCheck(Strings.OptAutoStart, 210);
        _desktopShortcut = NewCheck(Strings.OptDesktop, 238);
        _launchAfter = NewCheck(Strings.OptLaunch, 266);

        _progress = new ProgressBar
        {
            Location = new Point(26, 306),
            Size = new Size(410, 8),
            Style = ProgressBarStyle.Continuous,
            Maximum = 100,
            Visible = false
        };
        Controls.Add(_progress);

        _statusLabel = new Label
        {
            Text = string.Empty,
            ForeColor = muted,
            Location = new Point(24, 320),
            Size = new Size(412, 18)
        };
        Controls.Add(_statusLabel);

        Controls.Add(new Label
        {
            Text = Strings.License,
            ForeColor = muted,
            Font = new Font("Segoe UI", 8F),
            Location = new Point(24, 358),
            Size = new Size(220, 18)
        });

        _installButton = new Button
        {
            Text = Strings.Install,
            Location = new Point(258, 350),
            Size = new Size(96, 32)
        };
        _installButton.Click += OnInstall;
        Controls.Add(_installButton);
        AcceptButton = _installButton;

        _cancelButton = new Button
        {
            Text = Strings.Cancel,
            Location = new Point(362, 350),
            Size = new Size(74, 32)
        };
        _cancelButton.Click += delegate { Close(); };
        Controls.Add(_cancelButton);
        CancelButton = _cancelButton;
    }

    private CheckBox NewCheck(string text, int top)
    {
        CheckBox box = new CheckBox
        {
            Text = text,
            Checked = true,
            Location = new Point(26, top),
            Size = new Size(410, 24)
        };
        Controls.Add(box);
        return box;
    }

    private void OnBrowse(object sender, EventArgs e)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            dialog.Description = Strings.LocationHeader;
            dialog.SelectedPath = _pathBox.Text;
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                _pathBox.Text = Path.Combine(dialog.SelectedPath, Installer.ProductName);
            }
        }
    }

    private void Report(string message, int percent)
    {
        _statusLabel.Text = message;
        _progress.Value = Math.Min(100, Math.Max(0, percent));
        Application.DoEvents();
    }

    private void OnInstall(object sender, EventArgs e)
    {
        if (_installed) { Close(); return; }

        if (Installer.PowerShellPath == null)
        {
            MessageBox.Show(this, Strings.NeedPowerShell, Strings.FailedTitle,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string installPath = _pathBox.Text.Trim();
        if (installPath.Length == 0) { return; }

        _installButton.Enabled = false;
        _cancelButton.Enabled = false;
        _pathBox.Enabled = false;
        _progress.Visible = true;

        try
        {
            Report(Strings.StepExtract, 15);
            Installer.ExtractPayload(installPath);

            Report(Strings.StepShortcuts, 45);
            string launcher = Path.Combine(installPath, Installer.LauncherName);
            string target = File.Exists(launcher) ? launcher : Installer.PowerShellPath;
            string arguments = File.Exists(launcher)
                ? string.Empty
                : "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""
                  + Path.Combine(installPath, "ControllerStarterApp.ps1") + "\"";

            Shortcuts.Create(Installer.StartMenuShortcutPath, target, arguments,
                             installPath, launcher, Installer.ProductName);

            if (_desktopShortcut.Checked)
            {
                Shortcuts.Create(Installer.DesktopShortcutPath, target, arguments,
                                 installPath, launcher, Installer.ProductName);
            }

            Report(Strings.StepRegister, 65);
            File.Copy(Assembly.GetExecutingAssembly().Location,
                      Path.Combine(installPath, Installer.UninstallerName), true);
            Installer.RegisterUninstallEntry(installPath);

            if (_autoStart.Checked)
            {
                Report(Strings.StepAutoStart, 85);
                Installer.RunPowerShell(Path.Combine(installPath, "Install.ps1"), "-NoStart", true);
            }

            Report(Strings.StepDone, 100);

            if (_launchAfter.Checked)
            {
                Installer.RunPowerShell(Path.Combine(installPath, "ControllerStarterApp.ps1"), null, false);
            }

            _installed = true;
            _installButton.Text = Strings.Close;
            _installButton.Enabled = true;
            _cancelButton.Visible = false;

            MessageBox.Show(this, Strings.DoneMessage, Strings.AppName,
                            MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, Strings.FailedTitle,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            _installButton.Enabled = true;
            _cancelButton.Enabled = true;
            _pathBox.Enabled = true;
            _progress.Visible = false;
            _statusLabel.Text = string.Empty;
        }
    }
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        bool uninstall = false;
        bool quiet = false;
        foreach (string arg in args)
        {
            string value = arg.TrimStart('/', '-').ToLowerInvariant();
            if (value == "uninstall" || value == "u") { uninstall = true; }
            if (value == "quiet" || value == "silent" || value == "s") { quiet = true; }
        }

        if (uninstall) { return Uninstall(quiet); }

        Icon icon = LoadIcon();
        Application.Run(new SetupForm(icon));
        return 0;
    }

    private static Icon LoadIcon()
    {
        try
        {
            return Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
        }
        catch
        {
            return SystemIcons.Application;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) { File.Delete(path); }
        }
        catch
        {
            // A shortcut we cannot remove is not worth failing the uninstall over.
        }
    }

    private static int Uninstall(bool quiet)
    {
        if (!quiet)
        {
            DialogResult answer = MessageBox.Show(Strings.UninstallConfirm, Installer.ProductName,
                                                  MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) { return 1; }
        }

        string installPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

        // Let the application tear down its own autostart entry and stop itself.
        string uninstallScript = Path.Combine(installPath, "Uninstall.ps1");
        if (File.Exists(uninstallScript))
        {
            Installer.RunPowerShell(uninstallScript, null, true);
        }

        TryDelete(Installer.StartMenuShortcutPath);
        TryDelete(Installer.DesktopShortcutPath);

        try { Registry.CurrentUser.DeleteSubKeyTree(Installer.RegistryKey, false); }
        catch { }

        // The uninstaller cannot remove the folder it is running from, so hand
        // that last step to a detached shell.
        try
        {
            ProcessStartInfo cleanup = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c timeout /t 3 /nobreak >nul & rmdir /s /q \"" + installPath + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            Process.Start(cleanup);
        }
        catch { }

        if (!quiet)
        {
            MessageBox.Show(Strings.UninstallDone, Installer.ProductName,
                            MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        return 0;
    }
}
