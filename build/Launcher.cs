// Controller Starter - launcher stub.
//
// Compiled as a Windows (non-console) executable so that double-clicking it
// starts the watcher without flashing a console window. Everything it does is
// start ControllerStarter.ps1 sitting next to it, forwarding any switches.
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

internal static class Launcher
{
    private const string ScriptName = "ControllerStarter.ps1";
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

        // Forward switches such as -NoHide or -Once straight through.
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
