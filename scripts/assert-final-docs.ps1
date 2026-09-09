$ErrorActionPreference = 'Stop'

$Files = @(
    'README.md',
    'README.zh-CN.md',
    'README-FORK.md',
    'docs/installation.md',
    'docs/troubleshooting.md'
)

foreach ($File in $Files) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Required user-facing document is missing: $File"
    }
}

$Joined = ($Files | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"

$Forbidden = @(
    'upstream-ray/codex-usage-monitor/releases/latest',
    'Monitored Services',
    '监控服务',
    'Google Antigravity',
    'gemini:antigravity',
    'WinGet',
    'winget upgrade',
    'widget visibility',
    '组件显示状态',
    'Left-click the tray icon to toggle',
    '左键单击托盘图标可显示或隐藏',
    'may ask the local Codex CLI to refresh',
    '可能会在后台调用本地 Codex CLI进行刷新',
    '可能会在后台调用本地 Codex CLI 进行刷新'
)

foreach ($Text in $Forbidden) {
    if ($Joined.Contains($Text)) {
        throw "Stale documentation text remains: $Text"
    }
}

$Readme = Get-Content -Raw -LiteralPath 'README.md'
$ReadmeZh = Get-Content -Raw -LiteralPath 'README.zh-CN.md'
$ForkReadme = Get-Content -Raw -LiteralPath 'README-FORK.md'

if (-not $Readme.Contains('https://github.com/walle-2017/codex-usage-monitor/releases/latest')) {
    throw 'README.md must point installation downloads at the fork release page.'
}
if (-not $ReadmeZh.Contains('https://github.com/walle-2017/codex-usage-monitor/releases/latest')) {
    throw 'README.zh-CN.md must point installation downloads at the fork release page.'
}
if (-not $ForkReadme.Contains('1.0.2')) {
    throw 'README-FORK.md must document the current 1.0.2 release.'
}
if (-not $ForkReadme.Contains('drag_anchor_logical_x') -or -not $ForkReadme.Contains('DPI')) {
    throw 'README-FORK.md must document the v1.0.2 DPI-aware drag-anchor behavior.'
}
if (-not $ForkReadme.Contains('Codex-only')) {
    throw 'README-FORK.md must describe the final Codex-only scope.'
}
if (-not $ForkReadme.Contains('Codex CLI') -or -not $ForkReadme.Contains('401') -or -not $ForkReadme.Contains('403')) {
    throw 'README-FORK.md must retain the Codex CLI refresh safety contract.'
}
if (-not $ForkReadme.Contains('system proxy') -and -not $ForkReadme.Contains('系统代理')) {
    throw 'README-FORK.md must retain the Windows system proxy behavior.'
}

if (-not $Joined.Contains('walle-2017/codex-usage-monitor') -or -not $Joined.Contains('codex-usage.exe.sha256')) {
    throw 'User-facing docs must describe the pinned fork Release updater and checksum asset.'
}
if (-not $Readme.Contains('In-app update check') -or -not $ReadmeZh.Contains('应用内更新')) {
    throw 'Primary READMEs must document the clickable in-app update flow.'
}

Write-Output 'PASS: user-facing documentation matches the Codex-only v1.0.2 product state with manual in-app updates.'
exit 0
