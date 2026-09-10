Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DiagnosePath = Join-Path $PSScriptRoot '..\src\diagnose.rs'
$MainPath = Join-Path $PSScriptRoot '..\src\main.rs'
$UpdaterPath = Join-Path $PSScriptRoot '..\src\updater.rs'
$WindowPath = Join-Path $PSScriptRoot '..\src\window.rs'

$diagnose = Get-Content -Raw -LiteralPath $DiagnosePath
$main = Get-Content -Raw -LiteralPath $MainPath
$updater = Get-Content -Raw -LiteralPath $UpdaterPath
$window = Get-Content -Raw -LiteralPath $WindowPath

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $diagnose 'const\s+LOG_FILE_NAME\s*:\s*&str\s*=\s*"codex-usage\.log"' 'Runtime log must use codex-usage.log.'
Assert-Match $diagnose 'const\s+MAX_LOG_BYTES\s*:\s*u64\s*=\s*5\s*\*\s*1024\s*\*\s*1024' 'Runtime log rotation threshold must be 5 MB.'
Assert-Match $diagnose 'current_exe\(\)' 'Runtime log path must derive from the current executable.'
Assert-Match $diagnose '\.parent\(\)' 'Runtime log must be created beside the executable.'
Assert-Match $diagnose '\.append\(true\)' 'Runtime log must append across restarts.'
Assert-Match $diagnose 'codex-usage\.log\.1|with_file_name\(' 'Runtime log must rotate to a single .1 backup.'
Assert-Match $diagnose 'metadata\(' 'Runtime log rotation must inspect file size.'
Assert-Match $main 'diagnose::init\(\)' 'Logging must initialize during normal startup.'
if ($main -match 'if\s+diagnose_enabled\s*\{\s*match\s+diagnose::init') {
    throw 'Runtime logging must not require --diagnose.'
}
Assert-Match $main 'version=.*executable=' 'Startup log must include version and executable path.'
Assert-Match $updater 'diagnose::log\("updater: check started"\)' 'Updater must log check start.'
Assert-Match $updater 'diagnose::log\(format!\(\s*"updater: latest release' 'Updater must log resolved latest release state.'
Assert-Match $window 'diagnose::log\("update command requested"\)' 'Version menu action must log update requests.'

$combined = $diagnose + "`n" + $main + "`n" + $updater + "`n" + $window
foreach ($forbidden in @(
    'diagnose::log\([^\r\n]*access_token',
    'diagnose::log\([^\r\n]*refresh_token',
    'diagnose::log\([^\r\n]*Authorization',
    'diagnose::log\([^\r\n]*auth\.json.*content'
)) {
    if ($combined -match $forbidden) {
        throw "Runtime logging may expose credential material: $forbidden"
    }
}

Write-Host 'PASS: persistent runtime logging contract is present and avoids credential material.'
