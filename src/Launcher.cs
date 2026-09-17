// Controller Starter - launcher stub.
//
// Compiled as a Windows (non-console) executable so that double-clicking it
// starts the tray application without flashing a console window. All it does
// is launch ControllerStarterApp.ps1 sitting next to it, forwarding any
// switches (for example -Setup).
//
// Build with Build-Exe.ps1.
//
// Author : Samet Ege
// License: MIT

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Controller Starter")]
[assembly: AssemblyProduct("Controller Starter")]
[assembly: AssemblyDescription("Launches Steam when an Xbox controller connects and closes the game plus Steam when it disconnects.")]
[assembly: AssemblyCompany("Samet Ege")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Samet Ege - MIT License")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Launcher
{
    private const string ScriptName = "ControllerStarterApp.ps1";
    private const string Caption = "Controller Starter";

    [STAThread]
    private static int Main(string[] args)
    {
        string directory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string script = Path.Combine(directory, ScriptName);

        if (!File.Exists(script))
        {
            MessageBox.Show(
                ScriptName + " was not found next to this executable." +
                Environment.NewLine + Environment.NewLine +
                "Expected at:" + Environment.NewLine + script,
                Caption,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        StringBuilder arguments = new StringBuilder();
        arguments.Append("-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"");
        arguments.Append(script);
        arguments.Append('"');

        // Forward switches such as -Setup or -NoHide straight through.
        foreach (string arg in args)
        {
            arguments.Append(' ');
            arguments.Append(arg);
        }

        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments.ToString(),
            WorkingDirectory = directory,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        try
        {
            Process.Start(startInfo);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Controller Starter could not be launched." +
                Environment.NewLine + Environment.NewLine + ex.Message,
                Caption,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
