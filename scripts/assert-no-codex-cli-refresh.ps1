$ErrorActionPreference = 'Stop'

$pollerPath = Join-Path $PSScriptRoot '..\src\poller.rs'
$source = Get-Content -Raw -Path $pollerPath

foreach ($pattern in @(
    'cli_refresh_codex_token\s*\(',
    'resolve_windows_codex_path\s*\(',
    '"exec"\s*,\s*"\."',
    'Command::new\([^\r\n]*(codex|codex\.exe|codex\.cmd|codex\.ps1)',
    'where\.exe[^\r\n]*codex',
    'codex\s+app-server',
    'codex\s+--version'
)) {
    if ($source -match $pattern) {
        throw "Unsafe Codex CLI launch path detected: $pattern"
    }
}

$pollCodexMatch = [regex]::Match(
    $source,
    '(?s)fn\s+poll_codex\s*\(\s*\)\s*->\s*Result<UsageData,\s*PollError>\s*\{(?<body>.*?)\r?\n\}\r?\n\r?\nfn\s+build_agent'
)
if (-not $pollCodexMatch.Success) {
    throw 'Unable to locate the complete poll_codex() implementation in src/poller.rs'
}

$body = $pollCodexMatch.Groups['body'].Value
if ($body -notmatch 'Err\(PollError::AuthRequired\)\s*=>') {
    throw 'poll_codex() must explicitly handle AuthRequired.'
}
if ($body -notmatch 'Err\(PollError::TokenExpired\)') {
    throw 'Expected AuthRequired handling to return TokenExpired without CLI refresh.'
}
if ($body -match 'Command::new|std::process::Command|\.spawn\s*\(') {
    throw 'poll_codex() must not create any child process.'
}

Write-Host 'PASS: Codex usage polling cannot launch the Codex CLI.'
