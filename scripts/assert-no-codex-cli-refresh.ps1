$ErrorActionPreference = 'Stop'

$pollerPath = Join-Path $PSScriptRoot '..\src\poller.rs'
$source = Get-Content -Raw -Path $pollerPath

$pollCodexMatch = [regex]::Match(
    $source,
    '(?s)fn poll_codex\(\).*?\n}\n\nfn poll_antigravity'
)
if (-not $pollCodexMatch.Success) {
    throw 'Unable to locate poll_codex() in src/poller.rs'
}

if ($pollCodexMatch.Value -match 'cli_refresh_codex_token\s*\(') {
    throw 'Unsafe Codex path detected: poll_codex() still invokes cli_refresh_codex_token()'
}

$refreshMatch = [regex]::Match(
    $source,
    '(?s)fn cli_refresh_codex_token\(\).*?\n}\n\n/// Spawn a command'
)
if ($refreshMatch.Success) {
    if ($refreshMatch.Value -match '\.spawn\s*\(' -or
        $refreshMatch.Value -match 'Command::new' -or
        $refreshMatch.Value -match '"exec"\s*,\s*"\."') {
        throw 'Unsafe Codex path detected: cli_refresh_codex_token() can still spawn Codex CLI'
    }
}

Write-Host 'PASS: Codex usage polling cannot launch the Codex CLI.'
