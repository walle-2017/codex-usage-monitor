# Troubleshooting Codex Usage

## Taskbar error labels

Codex Usage separates authentication failures from transient service failures:

| Simplified Chinese | Other languages | Meaning | Recommended action |
|---|---|---|---|
| `!` | `!` | Codex credentials are missing or expired | Sign in with the official Codex CLI/app, then refresh or restart Codex Usage |
| `网络` | `NET` | Network or TLS connection failed | Check connectivity, VPN, proxy, and firewall settings |
| `限流` | `429` | Codex usage endpoint rate limit | Wait for the retry window; Codex Usage retries with backoff |
| `服务` | `5XX` | Service failure | Wait and retry; check service status if the problem persists |
| `错误` | `ERR` | Invalid or unsupported response | Enable diagnostics and inspect the log |

When the usage endpoint returns `401` or `403`, authentication polling is paused until the local Codex credential source changes. The monitor does not launch Codex CLI processes to refresh credentials.

Transient failures use backoff up to the configured refresh interval.

## Authentication recovery

If the taskbar shows `!`:

1. Open the official Codex CLI or Codex app yourself.
2. Complete sign-in if required.
3. Confirm that the local Codex credentials have been refreshed.
4. Refresh or restart Codex Usage.

The monitor reads `$CODEX_HOME/auth.json` or `~/.codex/auth.json` but does not directly edit it.

## Diagnostic log

Run:

```powershell
codex-usage.exe --diagnose
```

The log is written to `%TEMP%\codex-usage.log`. It can include:

- application version and executable path
- polling failure category and retry delay
- taskbar placement and Explorer-recovery events
- whether Windows manual system proxy support was selected

The log does not include access tokens, refresh tokens, credential-file contents, or API response bodies.

## Network and proxy failures

First check whether explicit proxy variables are set:

```powershell
Get-ChildItem Env:HTTPS_PROXY,Env:HTTP_PROXY,Env:ALL_PROXY -ErrorAction SilentlyContinue
```

If none are set, Codex Usage can use the current user's Windows manual proxy from:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

The application reads `ProxyEnable` and `ProxyServer` without changing the registry. PAC/WPAD automatic discovery is not supported.

If a proxy is used, it must be trusted because the Codex usage request carries an OAuth Bearer token inside the TLS connection.

## Reset local position without deleting settings

Right-click the taskbar component or tray icon and choose **Settings > Reset Position**. Settings are stored at:

```text
%APPDATA%\CodexUsage\settings.json
```

## Reinstall while preserving settings

Normal uninstall keeps the settings file. Reinstalling restores saved taskbar position, refresh interval, language, appearance, visible 5h/7d rows, and quota-alert preferences.

Use:

```powershell
uninstall.ps1 -RemoveSettings
```

only when a full settings reset is intended.

## Explorer/taskbar restart recovery

The application keeps a watchdog for Explorer/taskbar replacement. If Explorer restarts and destroys the embedded taskbar window, Codex Usage relaunches a fresh instance and uses a single-instance mutex to hand over cleanly.

If the widget does not return after Explorer has stabilized, exit any remaining `codex-usage.exe` process and start the application again.

## Upgrade problems

Codex Usage has no background update checker or in-app updater. Upgrades are explicit.

For an installed copy, download/run `install.ps1` from the fork Release you intend to install. The installer verifies the executable SHA256 before replacement and restores the previous executable if replacement fails.

For a portable copy, verify the published SHA256 and replace `codex-usage.exe` manually while the old process is not running.

## In-app update fails

The running version is left unchanged when the Release check, download, SHA256 verification, target-directory write preflight, or updater launch fails. Ensure GitHub is reachable through the same proxy environment used by Codex Usage and that the directory containing the running executable is writable. The updater does not request UAC elevation.

