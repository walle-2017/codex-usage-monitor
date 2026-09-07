# Taskbar Appearance Presets Design

## Goal

Improve the taskbar widget's visual hierarchy without changing its Win32/GDI architecture or adding a heavyweight UI framework.

## Presets

- **Default**: balanced spacing and full reset-time hint.
- **Compact**: reduced bar/text widths and tighter spacing. This is the default for settings that do not yet contain an appearance value.
- **Minimal**: shortest bar, percentage-focused value text, reset time hidden from the taskbar row.

## Display hierarchy

Each quota row is rendered as:

```text
5h  [progress]  19%  ↻13:40
7d  [progress]  80%  ↻09/11
```

Compact mode omits the reset glyph separator and uses tighter spacing; Minimal mode shows only the percentage beside a shorter bar. Full quota/reset wording remains available in the tray tooltip.

## Semantic quota color

Progress fill uses remaining quota rather than a fixed Codex white fill:

- remaining > 50%: normal
- remaining 20%..50%: warning
- remaining < 20%: critical

Provider-specific colors remain available for multi-provider identification where appropriate, but the single-provider Codex view prioritizes quota state.

## Settings and menu

Persist `appearance_preset` in `%APPDATA%\CodexUsage\settings.json` with values:

```text
default
compact
minimal
```

The context menu gains an Appearance / 外观 submenu with the three presets. Changing the preset immediately resizes and redraws the widget.

## Compatibility

- Existing settings without `appearance_preset` deserialize as `compact`.
- Existing provider, quota-window, update-frequency and alert settings are unchanged.
- No change to Codex authentication, proxy handling or the Codex CLI safety hardening.
- Windows light/dark theme auto-detection remains intact.
