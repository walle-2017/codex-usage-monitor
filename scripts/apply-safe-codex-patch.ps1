$ErrorActionPreference = 'Stop'

$pollerPath = Join-Path $PSScriptRoot '..\src\poller.rs'
$source = Get-Content -Raw -Path $pollerPath
$original = $source

$authRefreshPattern = '(?s)        Err\(PollError::AuthRequired\) => \{\r?\n            cli_refresh_codex_token\(\);\r?\n            let refreshed = read_codex_credentials\(\)\.ok_or\(PollError::TokenExpired\)\?;\r?\n            fetch_codex_usage\(&refreshed\.access_token, refreshed\.account_id\.as_deref\(\)\)\r?\n        \}'
$authRefreshReplacement = @'
        Err(PollError::AuthRequired) => {
            diagnose::log("Codex credentials rejected; automatic Codex CLI refresh is disabled");
            Err(PollError::TokenExpired)
        }
'@
$source = [regex]::Replace($source, $authRefreshPattern, $authRefreshReplacement, 1)

$cliRefreshPattern = '(?s)\r?\nfn cli_refresh_codex_token\(\) \{.*?\r?\n\}\r?\n\r?\n/// Spawn a command'
$source = [regex]::Replace($source, $cliRefreshPattern, "`r`n/// Spawn a command", 1)

$resolvePattern = '(?s)\r?\nfn resolve_windows_codex_path\(\) -> String \{.*?\r?\n\}\r?\n\r?\nfn build_agent\(\)'
$source = [regex]::Replace($source, $resolvePattern, "`r`nfn build_agent()", 1)

if ($source -eq $original) {
    Write-Host 'No source changes required; safe Codex patch is already applied.'
    exit 0
}

if ($source -match 'cli_refresh_codex_token\s*\(') {
    throw 'Patch incomplete: cli_refresh_codex_token reference remains'
}
if ($source -match 'resolve_windows_codex_path\s*\(') {
    throw 'Patch incomplete: resolve_windows_codex_path reference remains'
}

Set-Content -Path $pollerPath -Value $source -Encoding utf8NoBOM
Write-Host 'Applied safe Codex patch: automatic Codex CLI token refresh removed.'
