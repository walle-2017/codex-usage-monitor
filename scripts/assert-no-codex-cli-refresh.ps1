$ErrorActionPreference = 'Stop'

$pollerPath = Join-Path $PSScriptRoot '..\src\poller.rs'
$source = Get-Content -Raw -Path $pollerPath

if ($source -match 'cli_refresh_codex_token\s*\(') {
    throw 'Unsafe Codex path detected: cli_refresh_codex_token() still exists or is referenced'
}

if ($source -match 'resolve_windows_codex_path\s*\(') {
    throw 'Unsafe Codex path detected: resolve_windows_codex_path() still exists or is referenced'
}

if ($source -match '"exec"\s*,\s*"\."') {
    throw 'Unsafe Codex path detected: codex exec . command remains in src/poller.rs'
}

$pollCodexMatch = [regex]::Match(
    $source,
    '(?s)fn poll_codex\(\).*?\r?\n\}\r?\n\r?\nfn poll_antigravity'
)
if (-not $pollCodexMatch.Success) {
    throw 'Unable to locate poll_codex() in src/poller.rs'
}

if ($pollCodexMatch.Value -notmatch 'Err\(PollError::TokenExpired\)') {
    throw 'Expected AuthRequired handling to return TokenExpired without CLI refresh'
}

Write-Host 'PASS: Codex usage polling cannot launch the Codex CLI.'
