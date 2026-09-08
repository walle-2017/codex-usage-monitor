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

# Four-zone layout contract: Q1 label, Q2 progress, Q3 percentage, Q4 reset time.
foreach ($field in @('outer_padding', 'label_bar_gap', 'bar_percent_gap', 'percent_width', 'percent_reset_gap', 'reset_width')) {
    if ($appearanceProduction -notmatch ("pub\s+" + $field + ":\s*i32")) {
        throw "Appearance metrics must expose $field."
    }
}
if (($appearanceProduction | Select-String -Pattern 'outer_padding:\s*6' -AllMatches).Matches.Count -lt 2) {
    throw 'Compact and Minimal presets must use symmetric 6px horizontal outer padding.'
}
if (($appearanceProduction | Select-String -Pattern 'label_bar_gap:\s*6' -AllMatches).Matches.Count -lt 2) {
    throw 'Q1-to-Q2 gap must remain 6px in both presets.'
}
if (($appearanceProduction | Select-String -Pattern 'percent_reset_gap:\s*3' -AllMatches).Matches.Count -lt 2) {
    throw 'Q3-to-Q4 gap must be tightened to 3px.'
}
if (($appearanceProduction | Select-String -Pattern 'bar_percent_gap:\s*4' -AllMatches).Matches.Count -lt 2) {
    throw 'Q2-to-Q3 gap must remain 4px.'
}
if (($appearanceProduction | Select-String -Pattern 'percent_width:\s*36' -AllMatches).Matches.Count -lt 2) {
    throw 'Q3 percentage slot must remain a fixed 36px wide in both presets.'
}
if ($appearanceProduction -notmatch 'reset_width:\s*34') {
    throw 'Compact Q4 reset slot must be tightened to 34px.'
}
if ($appearanceProduction -notmatch 'secondary_font_height:\s*-11') {
    throw 'Compact reset time/date font must be increased to -11 for clarity.'
}
if ($windowProduction -notmatch 'DT_LEFT\s*\|\s*DT_VCENTER\s*\|\s*DT_SINGLELINE') {
    throw 'Percentage values must remain left aligned within their fixed slot.'
}

# Progress track/fill must be completely square-cornered.
if ($windowProduction -match 'corner_r\s*=') {
    throw 'Progress bar must not use a rounded-corner radius.'
}
if ($windowProduction -match 'CreateRoundRectRgn\([\s\S]{0,250}?bar_rect') {
    throw 'Progress fill must not use rounded clipping.'
}
if ($windowProduction -notmatch 'FillRect\(hdc,\s*&bar_rect') {
    throw 'Square progress track must be drawn with FillRect.'
}

# Semantic bar colors and stable percentage text color.
if ($windowProduction -notmatch 'fn\s+quota_bar_color\s*\(') {
    throw 'Quota bar color must be selected by a dedicated semantic color helper.'
}
foreach ($hex in @('#55A8F2', '#E6B84A', '#D95C5C')) {
    if ($windowProduction -notmatch [regex]::Escape($hex)) {
        throw "Quota bar palette must contain $hex."
    }
}
if ($windowProduction -notmatch 'remaining\s*>\s*50\.0' -or $windowProduction -notmatch 'remaining\s*>\s*20\.0') {
    throw 'Quota bar thresholds must be blue >50%, yellow 21-50%, red <=20% remaining.'
}
if ($windowProduction -notmatch 'percentage_text_color\s*=') {
    throw 'Percentage text must use a stable theme foreground independent of quota color.'
}

# Square GDI panel and dotted drag handle contract.
if ($appearanceProduction -notmatch 'panel_radius:\s*i32') {
    throw 'Appearance metrics must expose the panel corner metric.'
}
if (($appearanceProduction | Select-String -Pattern 'panel_radius:\s*0' -AllMatches).Matches.Count -lt 2) {
    throw 'Compact and Minimal panels must both use zero corner radius.'
}
if ($windowProduction -notmatch 'fn\s+draw_acrylic_panel\s*\(') {
    throw 'Widget must draw a unified GDI acrylic-style panel background.'
}
if ($windowProduction -notmatch 'draw_acrylic_panel\(hdc,\s*width,\s*height,\s*is_dark') {
    throw 'paint_content must draw the acrylic-style panel before content.'
}
if ($windowProduction -notmatch 'fn\s+draw_drag_handle\s*\(') {
    throw 'Widget must draw a dedicated dotted drag handle.'
}
if (($windowProduction | Select-String -Pattern 'for\s+row\s+in\s+0\.\.3' -AllMatches).Matches.Count -lt 1 -or
    ($windowProduction | Select-String -Pattern 'for\s+col\s+in\s+0\.\.2' -AllMatches).Matches.Count -lt 1) {
    throw 'Drag handle must use a 2x3 dot matrix.'
}
if ($windowProduction -notmatch 'DRAG_HANDLE_VISUAL_INSET_X:\s*i32\s*=\s*7') {
    throw 'Drag-handle dots must be inset to the visual midpoint between the panel edge and Q1 labels.'
}
if ($windowProduction -match 'Left divider') {
    throw 'Legacy vertical divider drawing must remain removed.'
}

Write-Host 'PASS: compact taskbar UI contract is satisfied.'
