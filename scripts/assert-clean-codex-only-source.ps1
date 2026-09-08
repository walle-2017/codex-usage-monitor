$ErrorActionPreference = 'Stop'

$repoRoot = Join-Path $PSScriptRoot '..'
$srcRoot = Join-Path $repoRoot 'src'
$sourceFiles = Get-ChildItem -Path $srcRoot -Recurse -File -Filter '*.rs'
$source = ($sourceFiles | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$cargo = Get-Content -Raw (Join-Path $repoRoot 'Cargo.toml')
$installer = Get-Content -Raw (Join-Path $PSScriptRoot 'install.ps1')

$forbidden = @(
    '\bmod\s+updater\s*;',
    '\bupdater::',
    '\bUpdateStatus\b',
    '\bInstallChannel\b',
    '\bReleaseDescriptor\b',
    '\bUpdateCheckResult\b',
    '\blast_update_check_unix\b',
    '\bTIMER_UPDATE_CHECK\b',
    '\bshow_claude_code\b',
    '\bclaude_code_available\b',
    '\bclaude_code_model\b',
    '\bshow_antigravity\b',
    '\bantigravity_[A-Za-z0-9_]*\b',
    '\bantigravity_model\b',
    '\bwidget_visible\b',
    '\bshow_widget\b',
    '\bupdate_via_winget\b',
    '\bWINGET_[A-Z0-9_]*\b'
)

foreach ($pattern in $forbidden) {
    if ($source -match $pattern) {
        throw "Dead or removed feature code remains in src/: $pattern"
    }
}

if (Test-Path (Join-Path $srcRoot 'updater.rs')) {
    throw 'src/updater.rs must be deleted.'
}
if (Test-Path (Join-Path $repoRoot 'iterations')) {
    throw 'Historical iterations/ directory must be removed.'
}
if (Test-Path (Join-Path $repoRoot 'packaging\winget')) {
    throw 'Obsolete WinGet packaging must be removed.'
}
if ($cargo -match '(?m)^sha2\s*=') {
    throw 'sha2 dependency is updater-only and must be removed.'
}
if ($cargo -match 'upstream-ray/codex-usage-monitor') {
    throw 'Cargo package metadata must point at this fork, not upstream-ray.'
}
if ($installer -notmatch '\$Repository\s*=\s*''walle-2017/codex-usage-monitor''') {
    throw 'Installer must download releases from this fork.'
}

Write-Host 'PASS: source and repository contain no removed providers, updater, WinGet packaging, widget visibility toggle, or historical iteration artifacts.'
