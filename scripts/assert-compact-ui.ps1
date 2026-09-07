$ErrorActionPreference = 'Stop'

$appearance = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\appearance.rs')
$window = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\window.rs')
$simplifiedChinese = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\localization\simplified_chinese.rs')
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
    throw 'Tooltip 5-hour labels must use uppercase 5H.'
}
if ($windowProduction -notmatch 'format!\("7D ') {
    throw 'Tooltip 7-day labels must use uppercase 7D.'
}
if ($simplifiedChinese -notmatch 'session_window:\s*"5H"') {
    throw 'Simplified-Chinese taskbar session label must use uppercase 5H.'
}
if ($simplifiedChinese -notmatch 'weekly_window:\s*"7D"') {
    throw 'Simplified-Chinese taskbar weekly label must use uppercase 7D.'
}
if ($windowProduction -notmatch 'corner_r\s*=\s*sc\(1\)') {
    throw 'Progress-bar corner radius must be reduced to one logical pixel.'
}
if ($windowProduction -notmatch 'bar_value_width') {
    throw 'Percentage must use a dedicated fixed-width value area.'
}
if ($appearanceProduction -notmatch 'bar_value_gap:\s*i32') {
    throw 'Appearance metrics must expose a dedicated progress-to-percentage gap.'
}
if (($appearanceProduction | Select-String -Pattern 'bar_value_gap:\s*2' -AllMatches).Matches.Count -lt 2) {
    throw 'Compact and Minimal presets must both use a 2px progress-to-percentage gap.'
}
if ($windowProduction -match 'let\s+bar_width\s*=\s*progress_width\s*\+\s*bar_value_width') {
    throw 'Progress track must not extend underneath the percentage value area.'
}
if ($windowProduction -notmatch 'text_x\s*=\s*bar_x\s*\+\s*progress_width\s*\+\s*sc\(metrics\.bar_value_gap\)') {
    throw 'Percentage text must start after the configured progress-to-percentage gap.'
}
if ($windowProduction -notmatch 'model_width\s*=.*?[\r\n]+(?:.*[\r\n]+){0,8}?\s*\+\s*sc\(metrics\.bar_value_gap\)') {
    throw 'Total widget width must reserve the progress-to-percentage gap.'
}
if ($windowProduction -notmatch 'model_usage_width[\s\S]*?sc\(preset\.metrics\(\)\.bar_value_gap\)') {
    throw 'Per-provider width calculations must reserve the progress-to-percentage gap.'
}
if ($windowProduction -notmatch 'model_width\s*=.*?[\r\n]+(?:.*[\r\n]+){0,10}?\s*\+\s*sc\(metrics\.bar_value_width\)') {
    throw 'Total widget width must reserve the percentage value area so reset time is not clipped.'
}

# GDI acrylic-style panel and dotted drag handle contract.
if ($appearanceProduction -notmatch 'panel_radius:\s*i32') {
    throw 'Appearance metrics must expose an acrylic-style panel radius.'
}
if (($appearanceProduction | Select-String -Pattern 'panel_radius:\s*5' -AllMatches).Matches.Count -lt 2) {
    throw 'Compact and Minimal presets must both use a 5px panel radius.'
}
if ($windowProduction -notmatch 'fn\s+draw_acrylic_panel\s*\(') {
    throw 'Widget must draw a unified GDI acrylic-style panel background.'
}
if ($windowProduction -notmatch 'draw_acrylic_panel\(hdc,\s*width,\s*height,\s*is_dark') {
    throw 'paint_content must draw the acrylic-style panel before content.'
}
if ($windowProduction -notmatch 'const\s+DRAG_HANDLE_HIT_W:\s*i32\s*=\s*8') {
    throw 'Drag handle hit area must be 8 logical pixels wide.'
}
if ($windowProduction -notmatch 'fn\s+draw_drag_handle\s*\(') {
    throw 'Widget must draw a dedicated dotted drag handle.'
}
if (($windowProduction | Select-String -Pattern 'for\s+row\s+in\s+0\.\.3' -AllMatches).Matches.Count -lt 1 -or
    ($windowProduction | Select-String -Pattern 'for\s+col\s+in\s+0\.\.2' -AllMatches).Matches.Count -lt 1) {
    throw 'Drag handle must use a 2x3 dot matrix.'
}
if ($windowProduction -match 'Left divider') {
    throw 'Legacy vertical divider drawing must be removed.'
}

Write-Host 'PASS: compact taskbar UI contract is satisfied.'
