$ErrorActionPreference = 'Stop'

$appearance = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\appearance.rs')
$window = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\window.rs')

if ($appearance -match '(?m)^\s*Default,\s*$') {
    throw 'Legacy Default appearance variant must be removed from the active preset enum.'
}
if ($window -match 'IDM_APPEARANCE_DEFAULT') {
    throw 'Appearance menu must only expose Compact and Minimal.'
}
if (($appearance + $window) -match '↻') {
    throw 'Reset-time icon must not appear in the taskbar UI.'
}
if ($window -notmatch 'format!\("5H ') {
    throw '5-hour labels must use uppercase 5H.'
}
if ($window -notmatch 'format!\("7D ') {
    throw '7-day labels must use uppercase 7D.'
}
if ($window -notmatch 'corner_r\s*=\s*sc\(1\)') {
    throw 'Progress-bar corner radius must be reduced to one logical pixel.'
}
if ($window -notmatch 'bar_value_width') {
    throw 'Percentage must be integrated into the progress component through a dedicated value area.'
}

Write-Host 'PASS: compact taskbar UI contract is satisfied.'
