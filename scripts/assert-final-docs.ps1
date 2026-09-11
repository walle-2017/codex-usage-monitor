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
    '可能会在后台调用本地 Codex CLI 进行刷新',
    'The application itself contains no update checker or in-app updater',
    '程序内部不包含更新检查或程序内升级器',
    'The application has no built-in update checker or updater',
    '程序内更新已删除',
    '%TEMP%\\codex-usage.log'
)

foreach ($Text in $Forbidden) {
    if ($Joined.Contains($Text)) {
        throw "Stale documentation text remains: $Text"
    }
}

$Readme = Get-Content -Raw -LiteralPath 'README.md'
$ReadmeZh = Get-Content -Raw -LiteralPath 'README.zh-CN.md'
$ForkReadme = Get-Content -Raw -LiteralPath 'README-FORK.md'
$Install = Get-Content -Raw -LiteralPath 'docs/installation.md'
$Troubleshooting = Get-Content -Raw -LiteralPath 'docs/troubleshooting.md'

if (-not $Readme.Contains('https://github.com/walle-2017/codex-usage-win/releases/latest')) {
    throw 'README.md must point installation downloads at the fork release page.'
}
if (-not $ReadmeZh.Contains('https://github.com/walle-2017/codex-usage-win/releases/latest')) {
    throw 'README.zh-CN.md must point installation downloads at the fork release page.'
}
if (-not $ForkReadme.Contains('1.0.3')) {
    throw 'README-FORK.md must document the current 1.0.3 release.'
}
if (-not $ForkReadme.Contains('drag_anchor_logical_x') -or -not $ForkReadme.Contains('DPI')) {
    throw 'README-FORK.md must retain the v1.0.2 DPI-aware drag-anchor baseline.'
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

if (-not $Joined.Contains('walle-2017/codex-usage-win') -or -not $Joined.Contains('codex-usage.exe.sha256')) {
    throw 'User-facing docs must describe the pinned fork Release updater and checksum asset.'
}
if (-not $Readme.Contains('vCURRENT --> vLATEST') -or -not $ReadmeZh.Contains('v当前版本 --> v最新版本')) {
    throw 'Primary READMEs must document the startup-discovered version menu hint.'
}
if (-not $Joined.Contains('--diagnose')) {
    throw 'User-facing docs must document opt-in diagnostic logging.'
}
if (-not $ForkReadme.Contains('--codex-usage-updated-to=') -or -not $Install.Contains('one-shot internal success argument')) {
    throw 'Fork and installation docs must document process-local update success handoff.'
}
if (-not $Readme.Contains('codex-usage.log') -or -not $ReadmeZh.Contains('codex-usage.log') -or -not $Troubleshooting.Contains('codex-usage.log.1')) {
    throw 'User-facing docs must describe persistent executable-directory logging and rotation.'
}
if (-not $ForkReadme.Contains('普通更新状态和额度提醒') -or -not $ReadmeZh.Contains('合并为一条')) {
    throw 'v1.0.3 docs must describe concise update/quota notifications.'
}

Write-Output 'PASS: user-facing documentation matches the Codex-only v1.0.3 product state with startup discovery and manual in-app updates.'
exit 0
