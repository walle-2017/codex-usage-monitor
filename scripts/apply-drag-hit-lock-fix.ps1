$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '..\src\window.rs'
$source = Get-Content -Raw $path

$old = @'
    let widget_height = {
        let state = lock_state();
        state
            .as_ref()
            .map(widget_height_for_state)
            .unwrap_or(sc(current_appearance_preset().metrics().widget_height))
    };
'@
$new = @'
    let widget_height = {
        let state = lock_state();
        state
            .as_ref()
            .map(widget_height_for_state)
            .unwrap_or(sc(AppearancePreset::Compact.metrics().widget_height))
    };
'@

if (-not $source.Contains($old)) {
    throw 'Expected re-entrant drag hit-test fallback not found.'
}
$source = $source.Replace($old, $new)
Set-Content -Path $path -Value $source -Encoding utf8NoBOM -NoNewline
git diff --check
