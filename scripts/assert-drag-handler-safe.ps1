$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\window.rs')

$moveMatch = [regex]::Match(
    $source,
    '(?s)WM_MOUSEMOVE\s*=>\s*\{(?<body>.*?)\n\s*WM_LBUTTONUP\s*=>'
)
if (-not $moveMatch.Success) {
    throw 'Unable to locate WM_MOUSEMOVE handler.'
}

$moveBody = $moveMatch.Groups['body'].Value
if ($moveBody -match 'current_appearance_preset\s*\(') {
    throw 'WM_MOUSEMOVE must not re-lock STATE through current_appearance_preset() while dragging.'
}

$hitTestMatch = [regex]::Match(
    $source,
    '(?s)fn\s+is_drag_handle_point\s*\([^)]*\)\s*->\s*bool\s*\{(?<body>.*?)\n\}'
)
if (-not $hitTestMatch.Success) {
    throw 'Unable to locate is_drag_handle_point().'
}
if ($hitTestMatch.Groups['body'].Value -match 'current_appearance_preset\s*\(') {
    throw 'is_drag_handle_point() must not re-lock STATE through current_appearance_preset().'
}

if ($source -match 'map\(widget_height_for_state\)\s*\.unwrap_or\(sc\(current_appearance_preset\(\)\.metrics\(\)\.widget_height\)\)') {
    throw 'Widget-height fallback must not eagerly re-lock STATE through current_appearance_preset().'
}

$setCursorMatch = [regex]::Match(
    $source,
    '(?s)WM_SETCURSOR\s*=>\s*\{(?<body>.*?)\n\s*WM_LBUTTONDOWN\s*=>'
)
if (-not $setCursorMatch.Success) {
    throw 'Unable to locate WM_SETCURSOR handler.'
}
$setCursorBody = $setCursorMatch.Groups['body'].Value
if ($setCursorBody -notmatch 'IDC_SIZEALL') {
    throw 'Drag handle hover/drag cursor must use the four-way move cursor IDC_SIZEALL.'
}
if ($setCursorBody -match 'IDC_SIZEWE') {
    throw 'Drag handle must not use the horizontal resize cursor IDC_SIZEWE.'
}

if ($source -notmatch 'WM_CAPTURECHANGED') {
    throw 'Drag handling must clear dragging state when mouse capture is lost (WM_CAPTURECHANGED).'
}

if ($source -notmatch 'WM_CANCELMODE') {
    throw 'Drag handling must clear dragging state when Windows cancels the interaction (WM_CANCELMODE).'
}

Write-Host 'PASS: taskbar state-lock paths avoid re-entrant locking, use a move cursor, and release cancelled drag capture.'
