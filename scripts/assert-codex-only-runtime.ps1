$ErrorActionPreference = 'Stop'

$srcRoot = Join-Path $PSScriptRoot '..\src'
$window = Get-Content -Raw (Join-Path $srcRoot 'window.rs')
$poller = Get-Content -Raw (Join-Path $srcRoot 'poller.rs')
$main = Get-Content -Raw (Join-Path $srcRoot 'main.rs')
$tray = Get-Content -Raw (Join-Path $srcRoot 'tray_icon.rs')

# Runtime provider implementations must be Codex-only. Compatibility fields and
# localization strings are removed in the following dead-code-cleanup stage.
foreach ($pattern in @(
    '\bpoll_claude_code\b',
    '\bpoll_antigravity\b',
    '(?m)^\s*const\s+USAGE_URL\s*:',
    '(?m)^\s*const\s+MESSAGES_URL\s*:',
    '(?m)^\s*const\s+ANTIGRAVITY_ENDPOINTS\s*:',
    '(?m)^\s*const\s+ANTIGRAVITY_CREDENTIAL_TARGET\s*:',
    '\bcli_refresh_windows_token\b',
    '\bcli_refresh_wsl_token\b'
)) {
    if ($poller -match $pattern) {
        throw "Codex-only poller must not contain provider runtime path: $pattern"
    }
}

foreach ($forbidden in @('IDM_MODEL_CLAUDE_CODE', 'IDM_MODEL_CODEX', 'IDM_MODEL_ANTIGRAVITY')) {
    if ($window -match [regex]::Escape($forbidden)) {
        throw "Provider-selection menu/action must be removed: $forbidden"
    }
}

# Keep the removed pre-v1 updater framework unreachable. The supported updater
# uses IDM_CHECK_UPDATE + src/updater.rs and must not revive these old paths.
if ($main -match 'updater::handle_cli_mode' -or
    $window -match 'IDM_VERSION_ACTION' -or
    $window -match 'TIMER_UPDATE_CHECK\s*=>' -or
    $window -match 'begin_update_check\(hwnd,\s*(true|false)\)') {
    throw 'Legacy updater entry points must remain removed.'
}

foreach ($forbidden in @('IDM_TOGGLE_WIDGET', 'ToggleWidget', 'toggle_widget_visibility')) {
    if (($window + $tray) -match [regex]::Escape($forbidden)) {
        throw "Taskbar widget visibility toggle behavior must be removed: $forbidden"
    }
}

if ($poller -notmatch 'pub\s+fn\s+poll\s*\(\s*\)\s*->\s*Result<AppUsageData,\s*PollError>') {
    throw 'poll() must be a zero-argument Codex-only entry point.'
}

if ($window -notmatch 'ShowWindow\(hwnd,\s*SW_SHOWNOACTIVATE\)') {
    throw 'Taskbar widget must be shown unconditionally while the process is running.'
}

Write-Host 'PASS: runtime is Codex-only, legacy updater paths stay removed, secure manual updates are allowed, and taskbar widget is always visible.'
