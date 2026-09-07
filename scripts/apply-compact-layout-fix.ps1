$ErrorActionPreference = 'Stop'

$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$zhPath = Join-Path $PSScriptRoot '..\src\localization\simplified_chinese.rs'

$window = Get-Content -Raw $windowPath
$oldWidth = @'
    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)
        + sc(metrics.bar_right_margin)
        + sc(text_width);
'@
$newWidth = @'
    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)
        + sc(metrics.bar_value_width)
        + sc(metrics.bar_right_margin)
        + sc(text_width);
'@
if (-not $window.Contains($oldWidth)) { throw 'Expected total-widget width block was not found.' }
$window = $window.Replace($oldWidth, $newWidth)

$oldBar = @'
    let progress_width = segment_count * (seg_w + seg_gap) - seg_gap;
    let bar_value_width = sc(metrics.bar_value_width);
    let bar_width = progress_width + bar_value_width;
    let bar_h = sc(metrics.bar_height).min(seg_h);
'@
$newBar = @'
    let progress_width = segment_count * (seg_w + seg_gap) - seg_gap;
    let bar_h = sc(metrics.bar_height).min(seg_h);
'@
if (-not $window.Contains($oldBar)) { throw 'Expected progress/value width block was not found.' }
$window = $window.Replace($oldBar, $newBar)

$oldRight = '            right: bar_x + bar_width,'
$newRight = '            right: bar_x + progress_width,'
if (-not $window.Contains($oldRight)) { throw 'Expected progress track right edge was not found.' }
$window = $window.Replace($oldRight, $newRight)
Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline

$zh = Get-Content -Raw $zhPath
if (-not $zh.Contains('    session_window: "5h",')) { throw 'Expected lowercase 5h localization was not found.' }
if (-not $zh.Contains('    weekly_window: "7d",')) { throw 'Expected lowercase 7d localization was not found.' }
$zh = $zh.Replace('    session_window: "5h",', '    session_window: "5H",')
$zh = $zh.Replace('    weekly_window: "7d",', '    weekly_window: "7D",')
Set-Content -Path $zhPath -Value $zh -Encoding utf8NoBOM -NoNewline

& (Join-Path $PSScriptRoot 'assert-compact-ui.ps1')
git diff --check
