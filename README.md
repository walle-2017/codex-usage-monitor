![Windows](https://img.shields.io/badge/platform-Windows-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**English** | [简体中文](README.zh-CN.md)

# Codex Usage

<img src=".github/codex-usage-icon.png" alt="Codex Usage icon" width="96" height="96">

![Screenshot](.github/animation.gif)

A lightweight native Windows taskbar widget for monitoring **Codex usage**. The current v1.0.2 fork is intentionally Codex-only: it reads the credentials already maintained by Codex and shows the remaining 5-hour and weekly quota directly in the taskbar.

## Features

- Codex **5h** and **7d** remaining-quota bars
- Reset time/date display and live countdown data
- Compact and minimal taskbar appearances
- Independent visibility controls for the 5h and 7d rows, with at least one row always visible
- Optional low-quota alerts at 10%, 20%, or 30% remaining, deduplicated per reset window
- Configurable refresh interval: 1 minute, 5 minutes, 15 minutes, or 1 hour
- Windows light/dark theme support
- Simplified Chinese and multiple other UI languages
- Multi-monitor taskbar placement with live cross-taskbar dragging, DPI-aware pointer anchoring, and continuous A → B → A movement while the mouse button remains held
- Explorer restart watchdog and single-instance protection
- Windows manual system-proxy support when explicit proxy environment variables are absent
- One tray icon for refresh/settings/exit while the taskbar widget remains visible

## Safety behavior

This fork deliberately removes automatic Codex CLI token refresh from the monitor.

The app reads Codex credentials from `$CODEX_HOME/auth.json` or `~/.codex/auth.json` and calls the Codex usage endpoint over HTTPS. If the endpoint returns `401` or `403`, the monitor reports an authentication error and pauses polling until the credential source changes. It **does not launch `codex.exe`, `codex.cmd`, `codex.ps1`, or `codex exec`** to refresh credentials.

To recover from an expired login, sign in through the official Codex CLI/app yourself, then refresh or restart Codex Usage.

## Requirements

- Windows 10 or Windows 11
- Codex CLI or the Codex app installed and authenticated

## Install

For a per-user installation, download `install.ps1` from the [latest fork release](https://github.com/walle-2017/codex-usage-monitor/releases/latest), then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer verifies the release SHA256, installs without administrator access to `%LOCALAPPDATA%\Programs\CodexUsage`, creates Start-menu and desktop shortcuts, and registers an uninstall entry in Windows Installed Apps.

For portable use, download `codex-usage.exe` from the same release and run it from a user-writable directory. To build locally:

```powershell
cargo build --release
```

The executable is created at `target\release\codex-usage.exe`.

## Uninstall

Uninstall **Codex Usage** from Windows Settings > Apps > Installed apps, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\CodexUsage\uninstall.ps1"
```

Normal uninstall preserves `%APPDATA%\CodexUsage\settings.json`. Add `-RemoveSettings` for a full settings reset. See [Installation model](docs/installation.md).

## Use

Run `codex-usage.exe` or the installed shortcut. The widget embeds into the selected Windows taskbar and the notification area keeps one tray icon available for commands.

- Drag the left handle to reposition the widget.
- On multi-monitor systems, keep holding the mouse button and drag onto another taskbar; the widget reattaches immediately, keeps the pointer aligned to the same logical point on the drag handle, and continues following the cursor across different DPI settings.
- Right-click the widget or tray icon for Refresh, Update Frequency, usage-row controls, quota alerts, Appearance, Start with Windows, Reset Position, Language, the read-only version entry, and Exit.
- The taskbar widget is intentionally always visible while the process is running; there is no hide/show toggle.

### Usage display and alerts

The widget shows remaining quota consistently in every language. Progress length, percentage text, and semantic status color all use the same remaining-quota value.

Use the settings menu to show both quota windows or only one. Low-quota alerts can be set to 10%, 20%, or 30% remaining and are emitted once per quota-reset window.

### Appearance

Two taskbar presets are retained:

- **Compact**: quota bar + percentage + reset time/date
- **Minimal**: quota bar + percentage only

Both follow the Windows light/dark theme. Small-taskbar layouts are handled separately to preserve readability.

## Network and proxy behavior

If `HTTPS_PROXY`, `HTTP_PROXY`, or `ALL_PROXY` is explicitly set, the HTTP client uses the normal proxy environment behavior. Otherwise, on Windows the app can read the current user's manual proxy configuration from:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

It reads `ProxyEnable` / `ProxyServer` and applies the result only to the current process. It does not modify Windows proxy settings. PAC/WPAD automatic proxy discovery is not implemented.

Because the Codex request includes an OAuth Bearer token inside TLS, only use proxies you trust.

## Diagnostics

Run:

```powershell
codex-usage.exe --diagnose
```

The log is written to `%TEMP%\codex-usage.log`. It records application/version information, executable path, polling failure category, retry timing, and taskbar recovery events. It does not record access tokens or credential-file contents. See [Troubleshooting](docs/troubleshooting.md).

Settings are stored at:

```text
%APPDATA%\CodexUsage\settings.json
```

Current settings cover taskbar position/screen, polling frequency, language, appearance, visible quota rows, alert threshold, and alert de-duplication state.

## Privacy

The application reads the local Codex access token/account identifier and sends them only as required to the ChatGPT Codex usage endpoint. It has no project backend, analytics, or telemetry and does not upload project files.

The monitor does not directly edit `auth.json` and does not start Codex CLI processes for authentication recovery.

## Version and releases

The current release is **1.0.2**. The in-app menu displays `v1.0.2` from the package version, and Windows executable metadata is generated from the same source. The initial cleaned Codex-only safety baseline was `v1.0.0`.

The application itself contains no update checker or in-app updater. Upgrades are explicit: install a newer fork release or replace the portable executable yourself.

## Open source

This project is licensed under the MIT License. The original [LICENSE](LICENSE) and copyright notice are preserved.

Codex Usage is derived from [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) and later upstream work. The current fork is maintained independently and is not affiliated with or endorsed by upstream maintainers or OpenAI.

See [README-FORK.md](README-FORK.md) for the fork-specific safety and maintenance baseline.

### In-app update check

The version row in **Settings** is clickable. Clicking it checks only the latest stable Release of `walle-2017/codex-usage-monitor`. If a newer version exists, Codex Usage downloads `codex-usage.exe` and `codex-usage.exe.sha256`, verifies SHA256, safely replaces the currently running installed or portable executable, and restarts automatically. There is no startup or periodic background update check.

