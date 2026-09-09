Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Match $window 'const\s+IDM_CHECK_UPDATE\s*:' 'window.rs must define IDM_CHECK_UPDATE.'
Assert-Match $window 'IDM_CHECK_UPDATE\s+as\s+usize' 'The version menu item must use IDM_CHECK_UPDATE as its command ID.'

$versionBlock = [regex]::Match(
    $window,
    'let\s+version_label\s*=.*?AppendMenuW\((?<body>.*?)\);',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $versionBlock.Success) {
    throw 'Unable to find version menu AppendMenuW block.'
}
if ($versionBlock.Groups['body'].Value -match 'MF_GRAYED') {
    throw 'The version menu item must not be MF_GRAYED.'
}
if ($versionBlock.Groups['body'].Value -notmatch 'IDM_CHECK_UPDATE') {
    throw 'The version menu item must dispatch IDM_CHECK_UPDATE.'
}

Assert-Match $window 'IDM_CHECK_UPDATE\s*=>' 'WM_COMMAND must handle IDM_CHECK_UPDATE.'
Assert-Match $window 'updater::start_update' 'The version command must start updater asynchronously.'
Assert-Match $main '(?m)^mod\s+updater;' 'main.rs must register the updater module.'

Assert-Match $updater 'https://api\.github\.com/repos/walle-2017/codex-usage-monitor/releases/latest' 'Updater source must be pinned to this fork latest Release API.'
Assert-Match $updater 'codex-usage\.exe' 'Updater must require codex-usage.exe.'
Assert-Match $updater 'codex-usage\.exe\.sha256' 'Updater must require codex-usage.exe.sha256.'
Assert-Match $updater '(?i)sha256' 'Updater must verify SHA256.'
Assert-Match $updater '\.old' 'Updater helper must contain rollback backup behavior.'
Assert-Match $updater '(?i)Wait-Process|Get-Process' 'Updater helper must wait for the old process.'
Assert-Match $updater '(?i)prerelease' 'Updater must reject prerelease Releases.'
Assert-Match $updater '(?i)draft' 'Updater must reject draft Releases.'

$forbidden = @(
    'codex login',
    'codex auth',
    'refresh_token',
    'auth\.json.*write',
    'Command::new\("codex"\)',
    'Command::new\("codex\.exe"\)'
)
foreach ($pattern in $forbidden) {
    if ($updater -match $pattern) {
        throw "Updater contains forbidden Codex credential/CLI behavior: $pattern"
    }
}

Write-Host 'PASS: auto-update source, menu wiring, checksum and rollback contracts are present.'
