$ErrorActionPreference = 'Stop'

$srcRoot = Join-Path $PSScriptRoot '..\src'
$window = Get-Content -Raw (Join-Path $srcRoot 'window.rs')
$poller = Get-Content -Raw (Join-Path $srcRoot 'poller.rs')
$main = Get-Content -Raw (Join-Path $srcRoot 'main.rs')
$tray = Get-Content -Raw (Join-Path $srcRoot 'tray_icon.rs')

foreach ($forbidden in @(
    'show_claude_code',
    'show_antigravity',
    'IDM_MODEL_CLAUDE_CODE',
    'IDM_MODEL_ANTIGRAVITY',
    'poll_claude_code',
    'poll_antigravity',
    'ANTIGRAVITY_',
    'Claude Code',
    'claude_code_available'
)) {
    if (($window + $poller) -match [regex]::Escape($forbidden)) {
        throw "Codex-only runtime must not contain provider path: $forbidden"
    }
}

if ($main -match 'mod\s+updater\s*;' -or $window -match 'UpdateStatus|begin_update_check|TIMER_UPDATE_CHECK|IDM_VERSION_ACTION') {
    throw 'In-app updater runtime must be removed.'
}

foreach ($forbidden in @('widget_visible', 'IDM_TOGGLE_WIDGET', 'ToggleWidget', 'toggle_widget_visibility')) {
    if (($window + $tray) -match [regex]::Escape($forbidden)) {
        throw "Taskbar widget visibility toggle must be removed: $forbidden"
    }
}

if ($poller -notmatch 'pub\s+fn\s+poll\s*\(\s*\)\s*->\s*Result<AppUsageData,\s*PollError>') {
    throw 'poll() must be a zero-argument Codex-only entry point.'
}

Write-Host 'PASS: runtime is Codex-only, has no in-app updater, and taskbar widget is always visible.'
