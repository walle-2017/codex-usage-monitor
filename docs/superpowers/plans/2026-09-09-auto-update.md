# Auto Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tray-menu version item clickable and let Codex Usage securely update itself from the latest stable Release of `walle-2017/codex-usage-win`, supporting both installed and portable executions.

**Architecture:** Keep Win32 menu/message concerns in `window.rs` and add a focused `updater.rs` domain module for GitHub Release discovery, version selection, download/checksum verification, staging, and launching a generated one-time PowerShell replacement helper. The helper waits for the old PID to exit, performs `.old` rollback-safe replacement at `current_exe()`, updates uninstall metadata only when it already refers to this executable, and relaunches the new binary.

**Tech Stack:** Rust 2021, `ureq` + `native-tls`, `serde`/`serde_json`, Win32 APIs via `windows`, PowerShell replacement helper, GitHub Actions Windows CI.

**Spec:** `docs/superpowers/specs/2026-09-09-auto-update-design.md`

## Global Constraints

- Development stays on `feature/auto-update`; do not modify `main` until explicit user approval after real-machine testing.
- Update metadata and assets come only from `walle-2017/codex-usage-win` Releases.
- Only stable, non-draft, non-prerelease Releases are eligible.
- Require exact assets `codex-usage.exe` and `codex-usage.exe.sha256`.
- Do not exit the running app until the new EXE is completely downloaded and its SHA256 is verified.
- Support both installed and portable executable locations derived from `std::env::current_exe()`.
- No UAC/elevation, no startup update checks, no periodic checks, no alternate update channels.
- Never invoke Codex CLI refresh and never modify Codex credentials.
- Preserve existing proxy behavior.

---

### Task 1: Establish RED update contracts in CI

**Files:**
- Create: `src/updater.rs` (test-only scaffold initially)
- Modify: `src/main.rs`
- Create: `scripts/assert-auto-update.ps1`
- Modify: `.github/workflows/safe-build.yml`

**Interfaces:**
- Consumes: existing Rust test harness and PowerShell assertion style.
- Produces: failing Rust tests for `Version`, release selection, checksum parsing, and a failing source-level CI contract for menu/update wiring.

- [ ] **Step 1: Add test-only updater module wiring**

Add `#[cfg(test)] mod updater;` to `src/main.rs` so unit tests in the new module compile only under `cargo test` before production wiring exists.

- [ ] **Step 2: Add failing unit tests in `src/updater.rs`**

Define tests that require these future interfaces:

```rust
Version::parse("1.0.10") -> Some(Version { major: 1, minor: 0, patch: 10 })
Version::parse_tag("v1.0.3")
Version::parse_tag("1.0.3")
select_release_update(&ReleaseMetadata, &Version) -> Result<Option<ReleaseUpdate>, UpdateError>
parse_sha256(&str) -> Result<String, UpdateError>
```

Cover numeric ordering (`1.0.10 > 1.0.9`), equal/lower versions, draft/prerelease rejection, exact required assets, invalid checksum text, and repository-pinned asset URLs from parsed metadata fixtures.

- [ ] **Step 3: Add source-level update safety assertion**

Create `scripts/assert-auto-update.ps1` that fails until all of these are true:

```text
src/window.rs defines IDM_CHECK_UPDATE
version menu item uses IDM_CHECK_UPDATE and is not MF_GRAYED
WM_COMMAND dispatches IDM_CHECK_UPDATE
src/main.rs contains mod updater;
src/updater.rs contains the fixed latest-release URL for walle-2017/codex-usage-win
updater requires codex-usage.exe and codex-usage.exe.sha256
updater contains SHA256 verification and rollback helper behavior
updater does not contain codex login/auth token mutation or codex CLI execution
```

- [ ] **Step 4: Enable Safe Windows Build for the feature branch and new assertion**

Add `feature/auto-update` to the workflow push branches and add a `Verify auto-update safety contract` PowerShell step before Rust setup.

- [ ] **Step 5: Push and verify RED**

Expected: `Safe Windows Build` fails because updater production interfaces and menu wiring do not yet exist. Inspect the run/logs and confirm the failure is caused by the missing feature rather than malformed test/configuration.

---

### Task 2: Implement release/version/checksum core

**Files:**
- Modify: `src/updater.rs`
- Modify: `src/main.rs`
- Modify: `Cargo.toml`
- Modify: `Cargo.lock`

**Interfaces:**
- Produces:
  - `pub(crate) fn start_update(hwnd: HWND)` later consumed by `window.rs`.
  - Internal `Version { major: u64, minor: u64, patch: u64 }` with numeric ordering.
  - `ReleaseMetadata` serde model and `select_release_update`.
  - `parse_sha256` and SHA256 file verification.

- [ ] **Step 1: Implement minimal version parser and Release metadata models**

Support only `major.minor.patch`, accept one leading `v` for tags, and reject malformed input. Model `tag_name`, `draft`, `prerelease`, and Release assets `{ name, browser_download_url }`.

- [ ] **Step 2: Implement deterministic release selection**

Reject draft/prerelease metadata; parse tag; compare numerically; return `Ok(None)` for equal/lower version; require exact executable/checksum assets only for a newer eligible version.

- [ ] **Step 3: Add a minimal SHA256 dependency and verification helpers**

Add `sha2 = "0.10"` and implement `parse_sha256` plus streaming/file hashing. Accept exactly one 64-hex token from the checksum file and compare case-insensitively.

- [ ] **Step 4: Run CI and verify core tests turn GREEN while the source-level menu assertion remains RED**

Expected: Rust updater unit tests pass; workflow still fails at the not-yet-wired menu/update contract.

---

### Task 3: Implement asynchronous download, staging, rollback helper, and Win32 integration

**Files:**
- Modify: `src/updater.rs`
- Modify: `src/window.rs`
- Modify: `src/main.rs`

**Interfaces:**
- `updater::start_update(hwnd: HWND) -> bool` returns false when an update operation is already in flight and otherwise starts one worker thread.
- `updater::take_ui_result() -> Option<UpdateUiResult>` lets the window consume worker completion after a posted app message.
- Add `WM_APP_UPDATE_RESULT` in the window/native message range.
- `UpdateUiResult`: `Current { version }`, `Failed { category }`, or `ReadyToRestart` only if needed before process exit.

- [ ] **Step 1: Add worker-state/result tests before production async code**

Test the pure transition helpers used by the worker: target preflight path decisions, helper-script quoting/rendering, and generated helper content containing bounded PID wait, `.old` rollback, original-path replacement, relaunch, portable registry skip, and installed-registry conditional update.

- [ ] **Step 2: Implement GitHub fetch and asset download**

Use a bounded-timeout `ureq::Agent` and product User-Agent. Fetch only the fixed `/releases/latest` endpoint. Download assets to a unique `%TEMP%` staging directory and verify checksum before any exit/restart action.

- [ ] **Step 3: Implement target preflight**

Resolve `current_exe()`, verify the parent directory exists and is writable using a unique probe file, stage a `.new` copy on the target filesystem before exit when possible, and leave the running executable untouched on failure.

- [ ] **Step 4: Implement generated PowerShell helper**

Render a local script that waits for the current PID with timeout, removes stale `.old`, renames original to `.old`, renames staged `.new` into place, restores `.old` on replacement failure, conditionally updates HKCU uninstall `DisplayVersion` only when `InstallLocation`/`DisplayIcon` corresponds to the target, launches the target with safely encoded original arguments, then cleans backup/staging when safe.

- [ ] **Step 5: Wire clickable version menu**

Add `IDM_CHECK_UPDATE`, replace the `MF_GRAYED`/ID `0` menu entry with a normal command item, and dispatch it to the updater without performing network work on the UI thread.

- [ ] **Step 6: Post result messages to the Win32 window**

On already-current or pre-update failure, post a custom app message, clear in-flight state, and show a localized `MessageBoxW`. On verified update readiness, launch the helper and exit only after helper launch succeeds.

- [ ] **Step 7: Run CI and verify the auto-update assertion and Rust tests are GREEN**

Expected: updater-specific checks pass; existing security/UI tests remain green.

---

### Task 4: Localization and documentation contract

**Files:**
- Modify: `src/localization/mod.rs`
- Modify: every existing `src/localization/*.rs` language table
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `README-FORK.md`
- Modify: `docs/installation.md` and/or `docs/troubleshooting.md` where updater behavior belongs
- Modify: `scripts/assert-final-docs.ps1`

**Interfaces:**
- Add centralized strings for already-current and update-failure categories; `window.rs` consumes these through `LanguageId::strings()`.

- [ ] **Step 1: Add localization fields and values**

Provide concise messages for already-current, check failure, download failure, verification failure, unwritable target, and helper-launch failure in all existing languages. English fallback is not introduced because every `Strings` const must remain structurally complete.

- [ ] **Step 2: Update docs**

Remove statements that the app has no in-app updater. Document that update checking is manual-on-click via the version item, source is this Fork's latest stable Release, update is automatic after a newer version is found, checksum validation is mandatory, and installed/portable locations are both supported.

- [ ] **Step 3: Update documentation assertion**

Require the new update behavior/source while retaining Codex-only/security wording.

- [ ] **Step 4: Run full Safe Windows Build**

Expected: all PowerShell contracts, `cargo test`, Clippy with warnings denied, and Windows release build pass.

---

### Task 5: Produce and verify the user test artifact

**Files:**
- No product source changes unless verification exposes a defect.

**Interfaces:**
- Consumes: successful feature-branch Safe Windows Build.
- Produces: Windows x64 artifact ZIP and verified EXE SHA256 for user real-machine testing.

- [ ] **Step 1: Inspect final branch diff against `main`**

Verify only intended updater/tests/docs/CI/dependency changes exist and no upstream/original repository is touched.

- [ ] **Step 2: Verify final workflow run step-by-step**

Require success for existing Codex CLI refresh prohibition, Codex-only runtime, docs, drag/capture/UI/language checks, new updater assertion, Rust tests, Clippy, release build, and artifact upload.

- [ ] **Step 3: Download the workflow artifact and independently verify the EXE checksum**

Compare the actual SHA256 of `codex-usage.exe` with `codex-usage.exe.sha256` from the same artifact.

- [ ] **Step 4: Hand off the feature-branch artifact for real Windows testing**

Do not merge to `main`, tag, or publish a Release. Wait for explicit user confirmation after testing.
