# Taskbar Layout and Small-Mode Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the taskbar widget into a four-zone fixed layout with square progress bars and semantic colors, vertically center the panel, and add an automatic one-row mode for small Windows taskbars with click-to-toggle 5H/7D.

**Architecture:** Keep the existing Win32/GDI rendering and taskbar embedding. Extend `StyleMetrics` with explicit outer padding and zone gaps, centralize color and small-taskbar decisions into pure helpers for unit testing, and make window height/row selection depend on taskbar height without changing provider/network/authentication behavior.

**Tech Stack:** Rust, Win32 GDI, serde, existing Windows taskbar integration.

**Spec:** User-approved requirements in the 2026-09-07 conversation.

## Global Constraints

- Only change taskbar presentation and mouse behavior.
- Preserve Codex CLI refresh hardening, Windows system proxy behavior, provider polling, authentication, and tray behavior.
- Progress tracks/fills must be completely square-cornered.
- Bar color is based on remaining quota: blue > 50%, yellow 21–50%, red <= 20%; percentage text is fixed white in dark mode and dark foreground in light mode.
- Q1/Q2/Q3/Q4 layout uses equal outer horizontal padding, Q1→Q2 gap equals Q3→Q4 gap, Q2→Q3 gap is smaller.
- Small-taskbar mode shows one row only, starts on 5H, and left-clicking the content area toggles 5H/7D; clicking the drag handle retains drag behavior.

---

### Task 1: Four-zone metrics and square semantic progress bars

**Files:**
- Modify: `src/appearance.rs`
- Modify: `src/window.rs`
- Modify: `scripts/assert-compact-ui.ps1`

**Interfaces:**
- Produces: fixed `outer_padding`, `label_bar_gap`, `bar_percent_gap`, `percent_reset_gap`, `percent_width`, `reset_width` metrics and semantic quota-bar color helpers.

- [ ] Add failing tests/assertions for the metric relationships, square bar drawing, fixed percent width/alignment, white percentage text, and blue/yellow/red thresholds.
- [ ] Run Windows CI and confirm RED only on the new UI contract/tests.
- [ ] Implement fixed Q1/Q2/Q3/Q4 layout and square `FillRect` track/fill rendering.
- [ ] Keep percentage text left-aligned inside a fixed slot large enough for `100%`.
- [ ] Run tests/CI and confirm GREEN.

### Task 2: Vertical centering and drag-handle spacing

**Files:**
- Modify: `src/window.rs`
- Modify: `scripts/assert-taskbar-drag.ps1`

**Interfaces:**
- Produces: `compute_anchor_y()` that vertically centers the widget and a dotted drag handle with explicit left inset while keeping the larger hit area.

- [ ] Add failing unit/assertion coverage for vertical center math and drag-handle inset.
- [ ] Run CI and confirm RED.
- [ ] Implement `anchor_top + (anchor_height - widget_height) / 2` clamped to taskbar bounds.
- [ ] Move the 2x3 visual dot matrix inward while preserving its hit target and drag safety.
- [ ] Run CI and confirm GREEN.

### Task 3: Small-taskbar one-row mode with click toggle

**Files:**
- Modify: `src/window.rs`
- Modify: `src/appearance.rs`
- Modify: `scripts/assert-compact-ui.ps1`

**Interfaces:**
- Produces: pure `is_small_taskbar_height(taskbar_height, dpi)` decision, `small_taskbar_mode` runtime state, and `small_window` selection between 5H and 7D.

- [ ] Add failing tests for normal/small taskbar thresholds and default 5H selection.
- [ ] Add failing UI contract assertion that a content-area left click toggles only in small-taskbar mode while drag-handle clicks still start drag.
- [ ] Run CI and confirm RED.
- [ ] Detect small-taskbar mode from taskbar height during positioning; switch widget height to a one-row height.
- [ ] Render only the selected 5H or 7D row in small mode; default to 5H whenever entering small mode.
- [ ] Handle content-area left click to toggle the selected row and re-render; do not persist this transient selection.
- [ ] Run full CI and release build.

### Task 4: Final cleanup and documentation

**Files:**
- Modify: `README-FORK.md`
- Delete before merge: `docs/superpowers/plans/2026-09-07-taskbar-layout-small-mode.md`

- [ ] Document the four-zone layout, semantic bar colors, vertical centering, and small-taskbar behavior.
- [ ] Remove temporary implementation-plan artifacts/workflows if any were used.
- [ ] Verify final PR diff contains only product code, long-lived regression checks, and fork documentation.
- [ ] Run final Windows CI, then merge only if all safety checks, tests, release build, and artifact upload pass.
