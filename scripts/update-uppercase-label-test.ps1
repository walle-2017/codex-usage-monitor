$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\src\poller.rs'
$source = Get-Content -Raw $path
$old5 = '        assert_eq!(strings.session_window, "5h");'
$new5 = '        assert_eq!(strings.session_window, "5H");'
$old7 = '        assert_eq!(strings.weekly_window, "7d");'
$new7 = '        assert_eq!(strings.weekly_window, "7D");'
if (-not $source.Contains($old5) -or -not $source.Contains($old7)) {
    throw 'Expected lowercase localization assertions were not found.'
}
$source = $source.Replace($old5, $new5).Replace($old7, $new7)
Set-Content -Path $path -Value $source -Encoding utf8NoBOM -NoNewline
git diff --check
