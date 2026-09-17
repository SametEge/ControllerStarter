# Controller Starter

**Turn your Xbox controller on — Steam opens. Turn it off — the game and Steam close.**

A console-like experience on Windows: pick up the controller, play, put it down. No keyboard, no mouse. Lives quietly in the notification area.

🇬🇧 English · [🇹🇷 Türkçe](README.tr.md)

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

<p align="center">
  <img src="docs/setup.png" alt="Controller Starter setup window" width="440">
</p>

---

## Contents

- [What it does](#what-it-does)
- [Quick start](#quick-start)
- [The tray icon](#the-tray-icon)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Files](#files)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Safety](#safety)
- [About the .exe](#about-the-exe)
- [Uninstalling](#uninstalling)
- [License](#license)

---

## What it does

| Event | Result |
|---|---|
| Controller connects (Bluetooth, USB or Xbox Wireless Adapter) | Steam launches — in **Big Picture** mode by default |
| Controller turns off or drops out | The running Steam game is closed gracefully, then Steam shuts down |
| Controller blips out for a moment | Nothing happens — if it comes back within the grace period, your game keeps running |
| You quit Steam yourself while the controller is still on | Steam is not relaunched; the tool waits for you to cycle the controller |

## Quick start

1. Download **`ControllerStarterSetup.exe`** from the [latest release](https://github.com/SametEge/ControllerStarter/releases/latest).
2. Run it, pick your options, press **Install**.
3. Turn your controller on.

The installer is a single self-contained file — the application is embedded inside it. It installs per-user (no administrator rights), adds a Start Menu shortcut and registers an entry under *Apps & features* so it uninstalls like any other program.

> **Windows 11 with Smart App Control:** the installer is unsigned and Windows will refuse to run it. There is no way around that short of turning the feature off — see [About the .exe](#about-the-exe). If you would rather not, clone the repository and double-click `app\Setup.bat` instead; it gives you exactly the same application.

### Running from source instead

```bash
git clone https://github.com/SametEge/ControllerStarter.git
```

Then double-click **`app\Setup.bat`**. It opens the same setup window the installer shows. Nothing to build, nothing to install, and Smart App Control does not block it.

For a text-only diagnostic report:

```powershell
powershell -ExecutionPolicy Bypass -File .\app\ControllerStarter.ps1 -Once
```

## The tray icon

Controller Starter sits in the notification area next to the clock. The icon colour tells you what it is doing:

| Icon | Meaning |
|---|---|
| 🟢 Green | A game session is active — Steam was launched for your controller |
| ⚪ Grey | Armed and waiting for a controller |
| 🟠 Amber | On hold (you quit Steam yourself, or the app is paused) — cycle the controller to re-arm |

**Right-click** for settings, the log file, pause/resume and exit. **Double-click** to open settings directly.

> Windows hides new tray icons by default. Click the **˄** arrow next to the clock, then drag the gamepad icon down onto the taskbar to pin it permanently.

## How it works

Controller detection goes through **XInput** (`XInputGetState`) rather than scanning device lists. Windows is asked directly "is a gamepad connected right now?", so a controller going to sleep or running out of battery registers immediately.

The watcher is a small state machine:

```
Waiting   ── controller present 2s ───────────►  launch Steam  ──►  Active
Active    ── controller absent 20s ───────────►  close game + Steam  ──►  Waiting
Active    ── user quit Steam ─────────────────►  Suspended
Suspended ── controller off ──────────────────►  Waiting  (armed again)
```

The `Suspended` state exists so that quitting Steam by hand — while the controller is still on — does not immediately relaunch it in a loop.

**Game detection.** A process is treated as a game only when its executable lives under a Steam library's `steamapps\common\` folder. Library paths are read from `libraryfolders.vdf`, so games on a second or third drive are found too.

**Shutdown order.** Games first get a `CloseMainWindow()` request so they can save, then 15 seconds to comply, then a forced terminate. Steam is closed with `steam.exe -shutdown`, which is Valve's own clean-exit path.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 — ships with Windows, nothing to install
- Steam
- An XInput-compatible controller: Xbox One, Xbox Series, Xbox 360, and most third-party pads that present themselves as XInput devices

> DualShock and DualSense controllers are not XInput devices and will not be seen directly. They work if you run them through a translation layer such as DS4Windows or Steam Input.

## Files

```
ControllerStarter/
├── app/                       # the application — this is what gets installed
│   ├── ControllerStarterApp.ps1   # tray app, setup and settings window
│   ├── ControllerStarter.ps1      # headless watcher, and -Once diagnostics
│   ├── Core.ps1                   # engine: XInput, Steam, state machine
│   ├── Install.ps1                # autostart on
│   ├── Uninstall.ps1              # autostart off
│   ├── Setup.bat                  # run it without the installer
│   └── config.json                # all settings
├── src/                       # C# sources
│   ├── Launcher.cs                # the small launcher executable
│   └── Setup.cs                   # the installer
├── build/                     # build scripts
│   ├── Build-Exe.ps1
│   └── Build-Setup.ps1
├── docs/setup.png
├── README.md                  # this file
├── README.tr.md               # Turkish version
└── LICENSE
```

## Configuration

Most settings are in the setup/settings window. `config.json` holds the full set, including a few that have no checkbox:

| Key | Default | Meaning |
|---|---|---|
| `language` | `"auto"` | UI language: `auto`, `tr` or `en`. `auto` follows your Windows language. |
| `steamExePath` | `""` | Empty means auto-detect from the registry. |
| `steamLaunchArgs` | `["-bigpicture"]` | Arguments passed to Steam. `[]` gives a normal Steam window. |
| `pollIntervalSeconds` | `2` | How often controller state is checked. |
| `connectDebounceSeconds` | `2` | How long the controller must stay connected before Steam launches. |
| `disconnectGraceSeconds` | `20` | **Important.** How long to wait after a dropout before closing anything. |
| `launchIfControllerAlreadyConnectedAtStartup` | `false` | Launch Steam if the controller is already on when Windows starts? |
| `closeGamesOnDisconnect` | `true` | Close the running game on disconnect? |
| `closeSteamOnDisconnect` | `true` | Close Steam on disconnect? |
| `closeSteamOnlyIfLaunchedByThisTool` | `false` | When `true`, a Steam you started yourself is left alone. |
| `gracefulCloseTimeoutSeconds` | `15` | Grace given to a game before it is force-terminated. |
| `steamShutdownTimeoutSeconds` | `30` | Grace given to Steam before it is force-terminated. |
| `showNotifications` | `true` | Show balloon notifications. |
| `extraGameProcessNames` | `[]` | Extra executables to close, e.g. `["RiotClientServices.exe"]`. |
| `ignoreProcessNames` | Steam helpers | Processes that must never be touched. |
| `logEnabled` | `true` | Write a log file? |
| `logMaxSizeKB` | `1024` | Rotate the log once it grows past this. |

### Settings worth changing

**An Xbox controller powers itself off after 15 minutes of inactivity.** If you do not want a long break to close your game, raise the wait time in the settings window, or:

```json
"disconnectGraceSeconds": 90
```

## Troubleshooting

**Steam opens when I plug the controller in just to charge it.**
A cabled controller reports itself as connected through XInput and there is no way to tell charging apart from playing. `launchIfControllerAlreadyConnectedAtStartup` is `false` by default so this never happens at boot; raising `connectDebounceSeconds` filters out short plug-ins while running.

**My controller slept mid-game and the game closed.**
Raise the wait time — see above.

**Steam does not launch.**
Open the settings window and check the `Steam` line under *Status*. If it says *Not found*, pick `steam.exe` with the Browse button.

**The controller is not detected.**
If the status line says *Not connected* with the pad switched on, XInput cannot see it. Check whether Windows lists it in `joy.cpl`.

**I cannot find the tray icon.**
Click the **˄** arrow next to the clock. Drag the gamepad icon onto the taskbar to pin it.

**Steam hangs on "Steam is shutting down".**
Expected; it is force-closed once `steamShutdownTimeoutSeconds` (default 30) elapses. Raise it if you often have downloads in flight.

## Safety

This tool terminates processes, so here is exactly what it will and will not touch:

- Only processes whose executable path sits under a Steam library's `steamapps\common\` folder are closed.
- The single exception is `extraGameProcessNames`, which **you** populate in `config.json`.
- Closing is always attempted politely first; forced termination only happens after a timeout.
- No administrator rights are requested, no system settings are changed, no network connections are made.

Unsaved progress can still be lost, especially in games without autosave. Tune the wait time to match how you actually play.

## About the .exe

`ControllerStarter.exe` is a 16 KB launcher: it starts the tray app with no console window at all. It is not a repackaged interpreter — the engine is still the PowerShell alongside it, which you can read.

### The Smart App Control catch

The executable is **unsigned**. Windows 11 with **Smart App Control** enabled refuses to run unsigned binaries — double-clicking does nothing visible, and from a console you get *"Application Control policy blocked this file"*. Signing requires a code-signing certificate from a trusted CA, which is a paid, identity-verified product.

Check your machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\build\Build-Exe.ps1 -CheckPolicy
```

If it reports **On (enforcing)**, you have two options:

- **Use `app\Setup.bat`.** Batch launchers are not affected and give you the same tray app. Nothing to disable.
- **Turn Smart App Control off** under Windows Security → App & browser control → Smart App Control. ⚠️ **This cannot be undone without reinstalling Windows**, and it removes the protection for every application, not just this one. Weigh that against the convenience of one icon.

### Building it yourself

```powershell
powershell -ExecutionPolicy Bypass -File .\build\Build-Setup.ps1
```

This generates the multi-resolution icon from the same drawing code the tray icon uses, compiles `src/Launcher.cs` into `app/ControllerStarter.exe`, packs everything in `app/` into a ZIP and embeds it inside `ControllerStarterSetup.exe`. It uses the C# compiler bundled in the .NET Framework, so nothing has to be installed — and you never have to trust a binary you did not build.

`build\Build-Exe.ps1` builds just the launcher, without the installer around it.

## Uninstalling

Double-click `Uninstall.bat`, or untick *Start with Windows* in the settings window and choose **Exit** from the tray menu. The project folder is left untouched.

## License

[MIT](LICENSE) — Samet Ege
