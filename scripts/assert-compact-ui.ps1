$ErrorActionPreference = 'Stop'

$appearance = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\appearance.rs')
$window = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\window.rs')
$appearanceProduction = ($appearance -split '#\[cfg\(test\)\]', 2)[0]
$windowProduction = ($window -split '#\[cfg\(test\)\]', 2)[0]

if ($appearanceProduction -match '(?m)^\s*Default,\s*$') {
    throw 'Legacy Default appearance variant must be removed from the active preset enum.'
}
if ($windowProduction -match 'IDM_APPEARANCE_DEFAULT') {
    throw 'Appearance menu must only expose Compact and Minimal.'
}
if ($windowProduction -match '(?m)^const SEGMENT_COUNT:') {
    throw 'Obsolete Default-preset SEGMENT_COUNT constant must be removed.'
}
if (($appearanceProduction + $windowProduction) -match '↻') {
    throw 'Reset-time icon must not appear in the taskbar UI.'
}
if ($windowProduction -notmatch 'format!\("5H ') {
    throw '5-hour labels must use uppercase 5H.'
}
if ($windowProduction -notmatch 'format!\("7D ') {
    throw '7-day labels must use uppercase 7D.'
}
if ($windowProduction -notmatch 'corner_r\s*=\s*sc\(1\)') {
    throw 'Progress-bar corner radius must be reduced to one logical pixel.'
}
if ($windowProduction -notmatch 'bar_value_width') {
    throw 'Percentage must be integrated into the progress component through a dedicated value area.'
}

Write-Host 'PASS: compact taskbar UI contract is satisfied.'
