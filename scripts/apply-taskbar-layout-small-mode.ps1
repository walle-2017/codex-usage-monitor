$ErrorActionPreference = 'Stop'

$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$window = Get-Content -Raw $windowPath

# small-taskbar selection is transient runtime state; it must not be persisted in SettingsFile.
$settingsPattern = '(?s)(struct SettingsFile \{.*?appearance_preset: AppearancePreset,\r?\n)\s*small_taskbar_mode: bool,\r?\n\s*small_show_weekly: bool,\r?\n'
$updated = [regex]::Replace($window, $settingsPattern, '$1', 1)
if ($updated -eq $window -and $window -match '(?s)struct SettingsFile \{.*?small_taskbar_mode: bool') {
    throw 'Could not remove transient small-taskbar fields from SettingsFile.'
}
$window = $updated

# Moving the dotted handle to an explicit x inset no longer needs its old computed matrix width.
$window = [regex]::Replace($window, '(?m)^\s*let matrix_w = dot \* 2 \+ gap_x;\r?\n', '', 1)

Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline
git diff --check
