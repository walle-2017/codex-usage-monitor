# Taskbar Appearance Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Default, Compact, and Minimal taskbar appearance presets with Compact as the default, improved quota text hierarchy, semantic quota colors, and immediate menu-based switching.

**Architecture:** Keep the existing Win32/GDI rendering path. Add a focused `appearance.rs` module for preset serialization, layout metrics, taskbar display text and quota tone decisions; integrate that module into `window.rs` for settings persistence, sizing, drawing, and the context menu.

**Tech Stack:** Rust, serde, Win32 GDI, Windows taskbar embedding, existing `windows` crate.

**Spec:** `docs/superpowers/specs/2026-09-07-taskbar-appearance-presets.md`

## Global Constraints

- Preserve the existing Win32/GDI architecture; do not add WinUI/WPF or a heavyweight UI dependency.
- Existing settings without `appearance_preset` must deserialize as `compact`.
- Do not alter Codex authentication, Windows system proxy support, or Codex CLI safety hardening.
- Preserve existing Windows light/dark theme auto-detection.

---

### Task 1: Appearance model and formatting

**Files:**
- Create: `src/appearance.rs`
- Modify: `src/main.rs`

**Interfaces:**
- Produces: `AppearancePreset`, `StyleMetrics`, `QuotaTone`, `taskbar_value_text`, `quota_tone`, and preset menu labels.
- Consumes: `models::UsageSection`, `poller::UsageWindowKind`, `localization::LanguageId`.

- [ ] **Step 1: Write failing tests**

Add tests proving:

```rust
assert_eq!(AppearancePreset::default(), AppearancePreset::Compact);
assert_eq!(taskbar_value_text(AppearancePreset::Compact, LanguageId::SimplifiedChinese, &section, UsageWindowKind::Session).primary, "19%");
assert_eq!(taskbar_value_text(AppearancePreset::Compact, LanguageId::SimplifiedChinese, &section, UsageWindowKind::Session).secondary.as_deref(), Some("13:40"));
assert_eq!(taskbar_value_text(AppearancePreset::Minimal, LanguageId::SimplifiedChinese, &section, UsageWindowKind::Session).secondary, None);
assert_eq!(quota_tone(81.0), QuotaTone::Critical);
assert_eq!(quota_tone(70.0), QuotaTone::Warning);
assert_eq!(quota_tone(10.0), QuotaTone::Normal);
```

- [ ] **Step 2: Run tests and confirm RED**

Run `cargo test` on Windows CI. Expected: compilation/test failure because appearance production types/functions do not yet exist.

- [ ] **Step 3: Implement minimal appearance module**

Implement serializable presets (`default`, `compact`, `minimal`), style metrics, percent/reset formatting and quota tone thresholds.

- [ ] **Step 4: Run tests and confirm GREEN**

Run `cargo test`; all existing and new tests must pass.

- [ ] **Step 5: Commit**

Commit with `feat: add taskbar appearance model`.

### Task 2: Persist and switch appearance presets

**Files:**
- Modify: `src/window.rs`

**Interfaces:**
- Consumes: `appearance::AppearancePreset`.
- Produces: `appearance_preset` persisted in `SettingsFile` and stored in `AppState`; context-menu commands update it.

- [ ] **Step 1: Write failing settings tests**

Add tests that deserialize legacy settings without `appearance_preset` as Compact and round-trip an explicitly selected Minimal preset.

- [ ] **Step 2: Run tests and confirm RED**

Run `cargo test`; expected failure because `SettingsFile` has no appearance field.

- [ ] **Step 3: Implement persistence and menu switching**

Add the setting/state field, three menu IDs, an Appearance / 外观 submenu, and command handling. Changing presets must call `save_state_settings`, `position_at_taskbar`, and `render_layered`.

- [ ] **Step 4: Run tests and confirm GREEN**

Run `cargo test`; all tests pass.

- [ ] **Step 5: Commit**

Commit with `feat: add appearance preset settings`.

### Task 3: Apply compact layout and semantic rendering

**Files:**
- Modify: `src/window.rs`
- Modify: `src/appearance.rs`

**Interfaces:**
- Consumes: `StyleMetrics`, `TaskbarValueText`, `QuotaTone`.
- Produces: preset-aware width/height/bar/font rendering.

- [ ] **Step 1: Write failing layout tests**

Test that Compact is narrower than Default and Minimal is narrower than Compact, while all computed widths remain positive for one-, two-, and three-provider layouts.

- [ ] **Step 2: Run tests and confirm RED**

Run `cargo test`; expected failure until widget sizing consumes preset metrics.

- [ ] **Step 3: Implement preset-aware drawing**

Use preset metrics for bar height/width, text width, row gaps, font sizes, and drag-handle dimensions. Draw percentage as the primary value and reset time as secondary text. For the single-provider Codex view, choose normal/warning/critical fill from remaining percentage.

- [ ] **Step 4: Preserve full tooltip detail**

Generate tray tooltip rows from raw `UsageSection` data using the existing full formatter rather than the shortened taskbar text.

- [ ] **Step 5: Run tests and Windows release build**

Run `scripts/assert-no-codex-cli-refresh.ps1`, `cargo test`, and `cargo build --release`.

- [ ] **Step 6: Commit**

Commit with `feat: refine taskbar quota visuals`.

### Task 4: Documentation and final verification

**Files:**
- Modify: `README-FORK.md`

**Interfaces:**
- Documents the new appearance presets, Compact default behavior, settings key, and unchanged Codex CLI safety guarantees.

- [ ] **Step 1: Update fork documentation**

Document the presets and configuration location without adding historical debugging noise.

- [ ] **Step 2: Run final verification**

Run the Codex CLI safety assertion, full tests, and Windows release build on the final branch HEAD.

- [ ] **Step 3: Open PR and merge only after CI is green**

Create a PR from `appearance-presets` to `main`, verify all CI steps, then merge.
