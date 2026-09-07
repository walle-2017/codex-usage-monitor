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

if ($source -notmatch 'WM_CAPTURECHANGED') {
    throw 'Drag handling must clear dragging state when mouse capture is lost (WM_CAPTURECHANGED).'
}

if ($source -notmatch 'WM_CANCELMODE') {
    throw 'Drag handling must clear dragging state when Windows cancels the interaction (WM_CANCELMODE).'
}

Write-Host 'PASS: taskbar drag handler avoids re-entrant STATE locking and releases cancelled capture state.'
