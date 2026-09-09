Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Permanent regression contract for the in-app updater.
$WindowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$MainPath = Join-Path $PSScriptRoot '..\src\main.rs'
$UpdaterPath = Join-Path $PSScriptRoot '..\src\updater.rs'

$window = Get-Content -Raw -LiteralPath $WindowPath
$main = Get-Content -Raw -LiteralPath $MainPath

if (-not (Test-Path -LiteralPath $UpdaterPath -PathType Leaf)) {
    throw 'src/updater.rs is missing.'
}
$updater = Get-Content -Raw -LiteralPath $UpdaterPath

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $window 'const\s+IDM_CHECK_UPDATE\s*:' 'window.rs must define IDM_CHECK_UPDATE.'
Assert-Match $window 'IDM_CHECK_UPDATE\s+as\s+usize' 'The version menu item must use IDM_CHECK_UPDATE as its command ID.'
Assert-Match $window 'IDM_CHECK_UPDATE\s*=>' 'WM_COMMAND must handle IDM_CHECK_UPDATE.'
Assert-Match $window 'updater::start_update' 'The version command must start updater asynchronously.'
Assert-Match $window 'updater::WM_APP_UPDATE_RESULT\s*=>' 'Update worker results must return to the UI thread.'
Assert-Match $main '(?m)^mod\s+updater;' 'main.rs must register updater.'

# Latest-version discovery must use github.com Release redirect rather than unauthenticated REST API.
Assert-Match $updater 'https://github\.com/walle-2017/codex-usage-monitor/releases/latest' 'Latest Release discovery must use the fork github.com redirect endpoint.'
if ($updater -match 'https://api\.github\.com/repos/walle-2017/codex-usage-monitor/releases/latest') {
    throw 'Normal update discovery must not depend on the rate-limited GitHub REST latest-release API.'
}
Assert-Match $updater '\.redirects\(0\)' 'Latest Release discovery must inspect the redirect instead of following it blindly.'
Assert-Match $updater 'header\("Location"\)' 'Latest Release discovery must inspect the Location header.'
Assert-Match $updater 'fn\s+parse_release_redirect\s*\(' 'Latest Release redirect must be parsed by a strict helper.'
Assert-Match $updater 'releases/tag/v' 'Latest Release redirect must be restricted to this fork release tag path.'
Assert-Match $updater 'discovery=github-redirect' 'Runtime log must identify redirect-based Release discovery.'
Assert-Match $updater 'https://github\.com/walle-2017/codex-usage-monitor/releases/download/' 'Release assets must stay pinned to this fork.'

Assert-Match $updater 'std::env::current_exe\(\)' 'Updater must target the running installed or portable executable.'
Assert-Match $updater 'AtomicBool' 'Updater must guard concurrent operations.'
Assert-Match $updater 'compare_exchange' 'Updater must atomically reject duplicate starts.'
Assert-Match $updater 'std::thread::spawn' 'Network/disk work must stay off UI thread.'
Assert-Match $updater 'PostMessageW' 'Completion must return to UI thread.'
Assert-Match $updater 'codex-usage\.exe\.sha256' 'Updater must require checksum asset.'
Assert-Match $updater '(?i)sha256' 'Updater must verify SHA256.'
Assert-Match $updater '\.old' 'Updater helper must retain rollback backup.'
Assert-Match $updater '(?i)Wait-Process|Get-Process' 'Updater helper must wait for old process.'

Assert-Match $updater 'Failed\s*\{\s*error:\s*UpdateError,\s*detail:\s*String\s*\}' 'Failures must retain visible technical detail.'
Assert-Match $updater 'fn\s+github_status_detail\s*\(' 'HTTP failures must retain bounded diagnostics.'
Assert-Match $updater 'body_message' 'JSON HTTP failures must expose safe message details.'
Assert-Match $updater 'body_preview' 'Non-JSON HTTP failures must expose a bounded safe preview.'
Assert-Match $updater 'redact_url_userinfo' 'HTTP diagnostics must redact URL credentials.'

if ($updater -match 'upstream-ray/codex-usage-monitor|ShumTin/CodexTray') {
    throw 'Updater must never use upstream/original repositories.'
}
foreach ($pattern in @('codex login','codex auth','refresh_token','auth\.json.*write','Command::new\("codex"\)','Command::new\("codex\.exe"\)')) {
    if ($updater -match $pattern) { throw "Forbidden credential/CLI behavior: $pattern" }
}

Write-Host 'PASS: rate-limit-free Release discovery, secure downloads, diagnostics, checksum and rollback contracts are present.'
