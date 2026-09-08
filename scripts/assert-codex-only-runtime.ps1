$ErrorActionPreference = 'Stop'

$srcRoot = Join-Path $PSScriptRoot '..\src'
$window = Get-Content -Raw (Join-Path $srcRoot 'window.rs')
$poller = Get-Content -Raw (Join-Path $srcRoot 'poller.rs')
$main = Get-Content -Raw (Join-Path $srcRoot 'main.rs')
$tray = Get-Content -Raw (Join-Path $srcRoot 'tray_icon.rs')

# Runtime provider implementations must be Codex-only. Compatibility fields and
# localization strings are removed in the following dead-code-cleanup stage.
foreach ($forbidden in @(
    'poll_claude_code',
    'poll_antigravity',
    'USAGE_URL',
    'MESSAGES_URL',
    'ANTIGRAVITY_ENDPOINTS',
    'ANTIGRAVITY_CREDENTIAL_TARGET',
    'cli_refresh_windows_token',
    'cli_refresh_wsl_token'
)) {
    if ($poller -match [regex]::Escape($forbidden)) {
        throw "Codex-only poller must not contain provider runtime path: $forbidden"
    }
}

foreach ($forbidden in @('IDM_MODEL_CLAUDE_CODE', 'IDM_MODEL_CODEX', 'IDM_MODEL_ANTIGRAVITY')) {
    if ($window -match [regex]::Escape($forbidden)) {
        throw "Provider-selection menu/action must be removed: $forbidden"
    }
}

# Stage 1 removes all reachable update entry points. The orphaned updater module
# and helper implementations are deleted in the dedicated dead-code stage.
if ($main -match 'updater::handle_cli_mode' -or
    $window -match 'IDM_VERSION_ACTION' -or
    $window -match 'TIMER_UPDATE_CHECK\s*=>' -or
    $window -match 'begin_update_check\(hwnd,\s*(true|false)\)') {
    throw 'In-app update entry points must be unreachable.'
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

Write-Host 'PASS: runtime is Codex-only, has no reachable in-app updater, and taskbar widget is always visible.'
