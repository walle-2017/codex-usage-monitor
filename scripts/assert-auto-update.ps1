Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Permanent regression contract for the in-app updater.
$WindowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$MainPath = Join-Path $PSScriptRoot '..\src\main.rs'
$UpdaterPath = Join-Path $PSScriptRoot '..\src\updater.rs'
$LocalizationPath = Join-Path $PSScriptRoot '..\src\localization\mod.rs'

$window = Get-Content -Raw -LiteralPath $WindowPath
$main = Get-Content -Raw -LiteralPath $MainPath
$localization = Get-Content -Raw -LiteralPath $LocalizationPath

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

# Normal successful updates must expose progress through Win32 UI notifications.
Assert-Match $updater 'WM_APP_UPDATE_PROGRESS' 'Updater must define a progress message distinct from final result.'
Assert-Match $updater 'enum\s+UpdateProgress' 'Updater must model update progress states.'
Assert-Match $updater 'Checking' 'Updater must report the checking stage.'
Assert-Match $updater 'Downloading\s*\{\s*version:\s*String\s*\}' 'Updater must report discovered version while downloading.'
Assert-Match $updater 'Restarting\s*\{\s*version:\s*String\s*\}' 'Updater must report verified update before restart.'
Assert-Match $updater 'fn\s+post_progress\s*\(' 'Updater worker must post progress to the UI thread.'
Assert-Match $window 'updater::WM_APP_UPDATE_PROGRESS\s*=>' 'Window procedure must handle update progress.'
Assert-Match $window 'UpdateProgress::Checking' 'Window must notify while checking.'
Assert-Match $window 'UpdateProgress::Downloading' 'Window must notify while downloading.'
Assert-Match $window 'UpdateProgress::Restarting' 'Window must notify immediately before restart.'
Assert-Match $window 'Duration::from_millis\(1200\)' 'Restart must be delayed briefly so the final Windows notification can become visible.'

# Successful replacement must leave a one-shot marker so the new process can announce success.
Assert-Match $updater 'UPDATE_SUCCESS_MARKER_SUFFIX' 'Updater must define a one-shot success marker.'
Assert-Match $updater 'fn\s+success_marker_path\s*\(' 'Updater must derive marker path beside the executable.'
Assert-Match $updater 'fn\s+take_successful_update_version\s*\(' 'New process must consume the success marker once.'
Assert-Match $updater 'Remove-Item -LiteralPath \$SuccessMarker' 'Replacement helper must remove stale success markers before replacement.'
Assert-Match $updater 'Set-Content -LiteralPath \$SuccessMarker' 'Replacement helper must write the marker only after successful replacement.'
Assert-Match $window 'take_successful_update_version' 'Window startup must consume update success state.'
Assert-Match $window 'update_success' 'Window must show a localized successful-update notification.'

foreach ($field in @('update_checking','update_downloading','update_restarting','update_success')) {
    Assert-Match $localization ("pub " + $field + ":") "Localization Strings must define $field."
}

if ($updater -match 'upstream-ray/codex-usage-monitor|ShumTin/CodexTray') {
    throw 'Updater must never use upstream/original repositories.'
}
foreach ($pattern in @('codex login','codex auth','refresh_token','auth\.json.*write','Command::new\("codex"\)','Command::new\("codex\.exe"\)')) {
    if ($updater -match $pattern) { throw "Forbidden credential/CLI behavior: $pattern" }
}

Write-Host 'PASS: rate-limit-free Release discovery, visible update progress, secure downloads, diagnostics, checksum and rollback contracts are present.'
