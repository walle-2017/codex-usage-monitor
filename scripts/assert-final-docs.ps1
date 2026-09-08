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
    'self-update',
    '自更新',
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
if (-not $ForkReadme.Contains('1.0.0')) {
    throw 'README-FORK.md must document the final 1.0.0 baseline.'
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

Write-Output 'PASS: user-facing documentation matches the final Codex-only v1.0.0 product state.'
exit 0
