# Auto Update Design

## Goal

Add an in-app update flow to Codex Usage so the version item in the tray settings menu is clickable. Clicking the current version checks the latest non-draft, non-prerelease GitHub Release from this fork (`walle-2017/codex-usage-win`), and when a newer version exists, downloads, verifies, installs, and restarts automatically without an additional confirmation dialog.

The update flow must support both the normal installed layout and a portable executable launched from an arbitrary writable directory.

## Scope

In scope:

- Make the currently disabled version menu item clickable.
- Check `https://api.github.com/repos/walle-2017/codex-usage-win/releases/latest` only when the user clicks the version item.
- Compare the latest Release version against `env!("CARGO_PKG_VERSION")` using numeric semantic-version ordering rather than string comparison.
- Ignore draft and prerelease releases.
- Require both `codex-usage.exe` and `codex-usage.exe.sha256` Release assets.
- Download update assets in the background without blocking the Windows UI thread.
- Verify the downloaded executable's SHA256 before the running process exits.
- Replace the executable in its current location, regardless of whether that location is the installed directory or a portable directory.
- Use a temporary updater process/script to wait for the current process to terminate, perform a rollback-safe replacement, and relaunch the updated executable.
- Preserve the current command-line arguments when relaunching, except updater-internal arguments or environment markers if introduced.
- Update the Windows uninstall `DisplayVersion` value when the existing installation registry entry belongs to this application; skip registry changes for portable usage.
- Report a clear user-visible result when the application is already current or when update preparation fails.
- Keep the existing proxy behavior and Codex credential/security behavior unchanged.
- Update user-facing documentation and CI assertions that currently state that in-app updating is unavailable.

Out of scope for the first version:

- Automatic periodic/background update checks.
- Silent update checks on startup.
- User-selectable update channels.
- Prerelease/beta channels.
- UAC elevation or updating from a directory that the current user cannot write.
- Delta/binary-patch updates.
- A separate permanent updater executable distributed in Release assets.
- Updating from the upstream/original repository or any repository other than this fork.

## Existing Context

The settings submenu currently renders the version using `MF_GRAYED` and menu command ID `0`, so it cannot generate a command event. The application already obtains its compile-time version through `env!("CARGO_PKG_VERSION")`.

The app applies its existing proxy environment before entering `window::run()`. Update HTTP requests must use the same process environment and must not introduce a second, conflicting proxy-discovery implementation.

The current Release workflow publishes these relevant assets for every release:

- `codex-usage.exe`
- `codex-usage.exe.sha256`
- `install.ps1`
- `uninstall.ps1`

The existing installer already demonstrates the desired replacement safety pattern: stage the new executable, validate its SHA256, move the existing executable to `.old`, move the new executable into place, restore `.old` if replacement fails, then relaunch.

## Architecture

### 1. UI integration remains in `window.rs`

`window.rs` owns native menu creation and `WM_COMMAND` dispatch, so it will receive a new menu command ID, for example `IDM_CHECK_UPDATE`.

The version entry changes from a disabled informational row to a normal menu item:

- Label remains `v{CARGO_PKG_VERSION}`.
- The menu item is enabled.
- Clicking it starts the updater workflow asynchronously.
- Repeated clicks while one check/update operation is already running are ignored or result in a single in-flight operation; concurrent updater runs are not allowed.

`window.rs` must not perform HTTP parsing, version parsing, checksum validation, or replacement logic itself.

### 2. New focused `src/updater.rs` module

A new `updater.rs` module owns update-domain behavior. It is intentionally separate because `window.rs` is already large and update logic is independently testable.

The module responsibilities are:

- Define the fixed fork repository and latest-release API endpoint.
- Fetch and parse GitHub Release metadata.
- Reject draft or prerelease releases.
- Parse current and release versions.
- Determine whether the release is strictly newer.
- Locate required Release assets by exact file name.
- Download the executable and checksum to a unique temporary staging directory.
- Parse the expected SHA256 and compute/compare the actual SHA256.
- Verify that the target executable directory can be updated before asking the main process to exit.
- Generate and launch the one-time replacement helper.
- Return structured status/error results to the UI layer.

Network/checksum/update errors must be represented by a small explicit error type rather than user-facing English strings spread throughout the implementation.

### 3. Release source and trust boundary

The only update metadata source is:

`https://api.github.com/repos/walle-2017/codex-usage-win/releases/latest`

The updater does not follow repository data supplied by local configuration and does not accept another owner/repository at runtime.

A release is eligible only if all of the following hold:

1. `draft == false`.
2. `prerelease == false`.
3. `tag_name` parses as a supported version after removing one leading `v`.
4. Parsed release version is strictly greater than the running `CARGO_PKG_VERSION`.
5. An asset named exactly `codex-usage.exe` exists.
6. An asset named exactly `codex-usage.exe.sha256` exists.
7. The checksum file contains one valid 64-hex-character SHA256 value.
8. The downloaded executable's SHA256 exactly matches that value.

No update occurs when the latest version is equal to or lower than the running version.

## Version Comparison

Version ordering must not be implemented by lexicographic string comparison. In particular, `1.0.10` must compare newer than `1.0.9`.

Use a small semantic-version representation capable of parsing the repository's release format (`major.minor.patch`). A leading `v` is accepted only for GitHub tag input; `CARGO_PKG_VERSION` is parsed without requiring `v`.

The first implementation does not need general SemVer prerelease/build-metadata ordering because prerelease GitHub Releases are rejected. If the parser accepts metadata, it must still never select a GitHub Release marked prerelease.

## Asynchronous Flow

Clicking the version item follows this sequence:

1. UI thread records that an update operation is in progress.
2. A worker thread checks the latest Release.
3. If no newer version exists, the worker posts a message back to the app window and the UI displays `当前已是最新版本 vX.Y.Z` (localized equivalents are preferred when practical within the existing localization model).
4. If a newer version exists, the worker downloads and verifies the required assets in a unique temporary directory.
5. The worker verifies that the target executable path can participate in the replacement flow.
6. Only after download, checksum verification, and target preflight all succeed does the app launch the replacement helper.
7. The main process then exits normally so the helper can replace the executable.
8. The helper restarts the new executable using the original working context/arguments needed by the application.

No GitHub request or file download may run synchronously inside the Win32 menu/command handler.

## Replacement Helper

Windows cannot reliably overwrite the currently running executable. The application therefore creates a one-time PowerShell helper under the update staging directory and launches it as a detached/hidden process.

Inputs to the helper must include at least:

- PID of the current Codex Usage process.
- Absolute path of the current executable.
- Absolute path of the staged new executable.
- Staging directory.
- Relaunch arguments or an equivalent safe representation.
- New version for optional installed-registry metadata update.

The helper performs this sequence:

1. Wait for the old process PID to exit, with a bounded timeout and failure path.
2. Define sibling paths for `codex-usage.exe.old` and `codex-usage.exe.new` (or equivalent names based on the current executable name).
3. Copy/move the staged executable to the target filesystem in preparation for an atomic same-volume rename where possible.
4. Remove any stale `.old` file from a previous completed update if safe.
5. Rename the existing target to `.old`.
6. Rename the staged/new target into the original executable path.
7. If step 6 fails, restore `.old` to the original path and report failure without launching a missing/corrupt target.
8. If an existing per-user uninstall registry entry for Codex Usage points to this installed executable, update `DisplayVersion`; otherwise do not create installation metadata for a portable executable.
9. Start the new executable.
10. Remove `.old` only after successful replacement/relaunch initiation.
11. Remove the temporary updater/staging files when safe.

The helper is temporary and is not added to Release assets.

## Installed vs Portable Behavior

The target path is always derived from `std::env::current_exe()`.

Examples:

- Installed: `%LOCALAPPDATA%\Programs\CodexUsage\codex-usage.exe`
- Portable: `D:\Tools\CodexUsage\codex-usage.exe`

Both use the same replacement flow.

For installed use, existing uninstall metadata may be updated only when it is already present and corresponds to the running installation. The updater must not turn a portable executable into an installed application and must not create shortcuts or startup entries that did not already exist.

If the target directory is not writable, update preparation fails before the application exits. The current executable remains untouched and keeps running.

## Failure Handling

Failures before helper launch are non-destructive. The app remains running and displays an error. This includes:

- GitHub API/network failure.
- Invalid release JSON.
- Invalid release version.
- Missing release asset.
- Checksum download/parse failure.
- SHA256 mismatch.
- Temporary staging failure.
- Current executable path resolution failure.
- Target directory not writable/preflight failure.
- Failure to launch the replacement helper.

Failures after the old process exits are handled by the helper. The helper must preserve or restore the old executable whenever replacement cannot complete.

The user-facing error should identify the category at a useful level (for example, `检查更新失败`, `下载更新失败`, `更新文件校验失败`, `当前目录无法写入`) without exposing secrets or large raw HTTP responses.

## Proxy and Network Behavior

Update networking must respect the process proxy environment already prepared by `system_proxy::apply_windows_system_proxy_env()` before `window::run()`.

The updater may construct its own `ureq::Agent`/TLS connector for GitHub requests, but it must not modify Codex authentication state and must not invoke the Codex CLI.

GitHub requests should set a product-specific User-Agent such as `CodexUsage-Updater/{version}` and use bounded timeouts.

## Security Requirements

- Never invoke Codex CLI token refresh.
- Never modify `auth.json` or other Codex credentials.
- Never update from upstream or a configurable arbitrary repository.
- Never execute a downloaded script from the Release as the update mechanism.
- The replacement helper is generated locally by the running application; only the EXE payload is accepted after SHA256 verification against the Release checksum asset.
- Do not exit the old application before the new executable has been fully downloaded and its SHA256 has been verified.
- Do not disable existing CI security assertions.

## UI and Localization

The existing version text remains visually simple and located where it is today. The only menu-layout change is that it is enabled/clickable.

The expected user-visible states are:

- Already current: `当前已是最新版本 vX.Y.Z`.
- Update available: no confirmation prompt; download and update start automatically.
- Pre-update failure: show a concise error and keep the current application running.
- Successful update: the old process exits and the updated process restarts; no separate success prompt is required before restart.

Where the project already centralizes user-facing tray/menu strings, new strings should be added to that localization structure rather than hard-coded only in Simplified Chinese.

## Files Expected to Change

- `src/main.rs` — register the updater module.
- `src/updater.rs` — new update-domain implementation and unit tests.
- `src/window.rs` — enabled version menu item, command handling, in-flight state, worker result dispatch, user messages.
- `src/localization/*` — update status/error strings if required by the current localization structure.
- `Cargo.toml` / `Cargo.lock` — only if a narrowly justified dependency is needed for SHA256 or version handling. Prefer existing dependencies or a minimal addition.
- `README.md`
- `README.zh-CN.md`
- `README-FORK.md` and/or relevant docs that currently state there is no updater.
- `.github/workflows/safe-build.yml` and/or assertion scripts — add permanent regression checks for updater safety and clickable-version behavior.
- New test/assertion scripts under `scripts/` if they fit the existing CI pattern.

`main` is not modified during development. All implementation and test work remains on `feature/auto-update` until the user tests and explicitly approves merging.

## Testing Strategy

Development follows TDD. At minimum, automated coverage must prove:

1. `1.0.3` is newer than `1.0.2`.
2. `1.0.2` is not newer than `1.0.2`.
3. `1.0.10` is newer than `1.0.9`.
4. Lower versions do not trigger update.
5. Draft/prerelease release metadata is rejected.
6. Missing `codex-usage.exe` is rejected.
7. Missing `codex-usage.exe.sha256` is rejected.
8. Invalid checksum text is rejected.
9. SHA256 mismatch is rejected.
10. Version menu item is not `MF_GRAYED` and has a real command ID.
11. Version command dispatch starts the updater path rather than blocking the UI thread.
12. Replacement helper contains rollback behavior and waits for the old PID.
13. Update source is pinned to `walle-2017/codex-usage-win`.
14. Existing no-Codex-CLI-refresh assertion still passes.
15. Existing Codex-only runtime assertions still pass.
16. `cargo test` passes.
17. `cargo clippy -- -D warnings` passes.
18. Windows release build passes.

A feature-branch Windows artifact is produced for real-machine testing. The branch is not merged and no new Release is published until the user explicitly confirms testing passed.

## Acceptance Criteria

The feature is accepted when, on a Windows machine:

- The version row in the settings menu is enabled and clickable.
- Clicking it while running the latest version reports that the application is current.
- When a newer valid Release exists in `walle-2017/codex-usage-win`, clicking it requires no confirmation, downloads the two required assets, verifies SHA256, replaces the executable, and restarts into the newer version.
- The same flow works when the executable is installed under the normal local-app-data path and when it is launched from an arbitrary writable portable directory.
- A checksum mismatch or unwritable directory leaves the old application running and unchanged.
- A replacement failure after process exit restores the previous executable.
- No updater operation modifies Codex credentials or invokes Codex CLI refresh.
- All existing and new CI checks pass.
