# Maintenance Baseline

This document records the maintained product constraints for **Codex Usage Win**.

## Current baseline

- Current release: `v1.0.4`
- Repository: `walle-2017/codex-usage-win`
- Product name: `Codex Usage Win`
- Standalone executable: `codex-usage-win.exe`
- Runtime scope: Codex-only
- Settings compatibility directory: `%APPDATA%\CodexUsage`

## Security constraints

- Never restore automatic Codex CLI token refresh.
- Codex credentials are read from the existing Codex credential file only.
- 401/403 pauses normal polling until credentials change.
- Update discovery is pinned to this repository's stable GitHub Releases.
- Standalone update assets require SHA256 verification before replacement.
- Diagnostic logging is opt-in via `--diagnose`.

## Update channels

### GitHub standalone

The default Cargo feature is `github-update`. It supports startup Release discovery and manual executable replacement.

A renamed/missing Release asset after a newer version has been discovered must fall back to a manual-update notice and the GitHub Releases menu instead of surfacing raw HTTP 404.

### Microsoft Store

Store packages are built with:

```text
--no-default-features --features store
```

Store builds must not initiate GitHub executable self-updates. Package updates are managed by Microsoft Store.

## Compatibility

v1.0.3 intentionally keeps the legacy product name, icon, and `codex-usage.exe` filename, while its rewritten release uses the current repository URL and supports the manual-update migration notice.

v1.0.4 is the renamed Codex Usage Win baseline with the new icon and complete current functionality.

## UI invariants

The DPI-aware multi-monitor drag implementation must preserve the logical pointer anchor across taskbars. Mouse capture must be released before reparenting, restored after the switch, and released unconditionally on button-up.
