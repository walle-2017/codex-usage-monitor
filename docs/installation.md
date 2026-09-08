# Codex Usage installation model

Codex Usage is a single native Windows executable. Installation places the executable and uninstall helper in a stable per-user directory; it does not add a runtime, service, driver, telemetry component, or machine-wide dependency.

## Direct installation

- Install directory: `%LOCALAPPDATA%\Programs\CodexUsage`
- Executable: `%LOCALAPPDATA%\Programs\CodexUsage\codex-usage.exe`
- Uninstall helper: `%LOCALAPPDATA%\Programs\CodexUsage\uninstall.ps1`
- Start menu shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Codex Usage.lnk`
- Desktop shortcut: `Codex Usage.lnk`
- Add/Remove Programs key: `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexUsage`

The installer is per-user and does not request elevation. It verifies the release SHA256 before replacing an existing executable. Replacement uses a staged `.new` file and preserves the previous executable as `.old` until the new installation has completed successfully.

Online installation downloads release assets only from the fork repository:

```text
walle-2017/codex-usage-monitor
```

The installer expects `codex-usage.exe`, `codex-usage.exe.sha256`, and `uninstall.ps1` from the same Release.

## Portable mode

`codex-usage.exe` can be run directly from any user-writable directory. Portable and installed copies use the same settings file:

```text
%APPDATA%\CodexUsage\settings.json
```

The application has no built-in update checker or updater. To upgrade, explicitly install a newer fork Release or replace the portable executable yourself.

## Settings and startup behavior

- Upgrades preserve `%APPDATA%\CodexUsage\settings.json`.
- Normal uninstall preserves settings so a later reinstall restores preferences.
- `uninstall.ps1 -RemoveSettings` explicitly deletes the settings directory.
- The installer does not enable startup automatically.
- If Start with Windows was already enabled, reinstall/upgrade preserves that choice and updates the registry entry to the stable installed executable.
- Users can enable or disable Start with Windows from the application's settings menu.
- Uninstall removes the `CodexUsage` startup entry because the executable no longer exists.

Current settings include taskbar position/screen, polling frequency, language, appearance, visible 5h/7d rows, quota-alert threshold, and alert de-duplication state.

## Release integrity

The release executable is accompanied by `codex-usage.exe.sha256`. The PowerShell installer computes SHA256 for the staged executable and aborts installation if it does not match the expected release checksum.

For the v1.0.0 baseline, the executable's Windows FileVersion/ProductVersion and the application's read-only version menu are both derived from the Cargo package version.
