Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$UpdaterPath = Join-Path $PSScriptRoot '..\src\updater.rs'
$WindowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$MainPath = Join-Path $PSScriptRoot '..\src\main.rs'
$updater = Get-Content -Raw -LiteralPath $UpdaterPath
$window = Get-Content -Raw -LiteralPath $WindowPath
$main = Get-Content -Raw -LiteralPath $MainPath

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $updater 'WM_APP_STARTUP_UPDATE_RESULT' 'Startup update check needs a dedicated UI result message.'
Assert-Match $updater 'start_startup_update_check' 'Updater must expose a startup check-only path.'
Assert-Match $updater 'StartupUpdateCheckResult' 'Startup update checks need a check-only result type.'
Assert-Match $window 'available_update_version\s*:\s*Option<String>' 'AppState must remember a discovered newer version for the menu.'
Assert-Match $window 'v\{\} --> v\{\}' 'Version menu must show current --> available version when a newer Release is known.'
Assert-Match $window 'successful_update_version_from_args[\s\S]*start_startup_update_check' 'Startup update check must be started after update-success notification handling.'
Assert-Match $main '"--diagnose"' 'Runtime logging must be gated by the --diagnose command-line flag.'
Assert-Match $main 'diagnose_enabled' 'main.rs must explicitly gate diagnose::init().'
Assert-Match $main 'if\s+diagnose_enabled\s*\{[\s\S]*diagnose::init\(\)' 'diagnose::init() must run inside the --diagnose gate.'

Write-Host 'PASS: startup update discovery, menu hint, ordering, and --diagnose logging contract are present.'
