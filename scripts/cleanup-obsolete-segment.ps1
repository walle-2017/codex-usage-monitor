$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\src\window.rs'
$source = Get-Content -Raw $path
$line = 'const SEGMENT_COUNT: i32 = 10;'
if (-not $source.Contains($line)) {
    throw 'Expected obsolete SEGMENT_COUNT constant was not found.'
}
$source = $source.Replace("$line`r`n", '').Replace("$line`n", '')
if ($source.Contains($line)) {
    throw 'SEGMENT_COUNT constant still remains after cleanup.'
}
Set-Content -Path $path -Value $source -Encoding utf8NoBOM -NoNewline
& (Join-Path $PSScriptRoot 'assert-compact-ui.ps1')
git diff --check
