# Code signing policy

This document describes who is responsible for the binaries published by this
project, how those binaries are produced, and what they do on a user's machine.
It exists because signed software should come with a statement of who stands
behind it.

## Project

| | |
|---|---|
| Project | Controller Starter |
| Repository | <https://github.com/SametEge/ControllerStarter> |
| License | [MIT](../LICENSE) — OSI-approved, no dual licensing |
| Downloads | <https://github.com/SametEge/ControllerStarter/releases> |

## Team and roles

Controller Starter is maintained by one person.

| Name | GitHub | Role |
|---|---|---|
| Samet Ege | [@SametEge](https://github.com/SametEge) | Author, reviewer and approver |

The same person owns the source repository, develops the software and approves
every signing request. Two-factor authentication is enabled on the GitHub
account that owns the repository.

If the project gains additional maintainers, this table is updated before they
are given any role in the signing process.

## How binaries are produced

Every published binary is built by
[the Build workflow](../.github/workflows/build.yml) on a clean GitHub-hosted
Windows runner, from the commit the release tag points at. Nothing is built or
uploaded from a developer machine.

The build has no third-party dependencies. It uses the C# compiler that ships
with the .NET Framework and PowerShell 5.1, both present on the runner:

1. `build/Build-Exe.ps1` generates the application icon from the drawing code in
   `app/Core.ps1`, then compiles `src/Launcher.cs` into `app/ControllerStarter.exe`.
2. `build/Build-Setup.ps1` packs everything in `app/` plus `LICENSE` into a ZIP
   and embeds it as a managed resource inside `ControllerStarterSetup.exe`,
   compiled from `src/Setup.cs`.

The workflow then verifies that the installer carries the expected product
metadata and that its embedded payload contains every expected file, before the
artifact is published.

Two executables are produced, and both are self-developed:

| Binary | Source | Purpose |
|---|---|---|
| `ControllerStarterSetup.exe` | `src/Setup.cs` | Installer; contains the application as an embedded ZIP |
| `ControllerStarter.exe` | `src/Launcher.cs` | Launcher; starts the tray application without a console window |

No upstream or third-party binaries are signed by this project.

## What the software does

Controller Starter watches for an XInput gamepad. When one connects it launches
Steam; when one disconnects it closes the running Steam game and then Steam.

Because it closes programs, its scope is deliberately narrow:

- Only processes whose executable path is inside a Steam library's
  `steamapps\common\` folder are closed. Library paths are read from Steam's own
  `libraryfolders.vdf`.
- The only exception is `extraGameProcessNames`, a list that is empty by default
  and populated by the user in `config.json`.
- Closing is always attempted with `CloseMainWindow()` first, so a game can save.
  A process is force-terminated only after a configurable timeout.
- Steam is closed with `steam.exe -shutdown`, Valve's own clean-exit path.

The application requests no administrator rights, changes no system settings,
and installs no drivers or services.

## Privacy

Controller Starter collects nothing and sends nothing.

- **No network access.** The application makes no outbound connections of any
  kind. There is no telemetry, no update check, and no analytics.
- **No personal data.** Nothing about the user, their machine or their games is
  collected, stored off-machine or transmitted.
- **Local log only.** A plain-text log is written to `logs\controller-starter.log`
  inside the installation folder, recording controller connects and disconnects
  and which processes were closed. It never leaves the machine, is rotated at a
  configurable size, and can be switched off with `logEnabled` in `config.json`.
- **Settings stay local.** `config.json` sits next to the application and is
  read and written only by it.

## Uninstallation

The installer registers a standard entry under **Settings → Apps → Installed
apps**, so the application is removed the same way as any other program.
Uninstalling stops the running instance, removes the autostart entry, deletes
the Start Menu and desktop shortcuts, and deletes the installation folder.

## Code signing

Free code signing is provided by the [SignPath Foundation](https://signpath.org/),
with a certificate and signing infrastructure from [SignPath.io](https://signpath.io/).

Signing happens inside the build workflow, between building the installer and
publishing it. SignPath verifies that the submitted artifact was produced by
this repository's own workflow from its public source before signing it, and
each release is approved manually by the maintainer listed above.
