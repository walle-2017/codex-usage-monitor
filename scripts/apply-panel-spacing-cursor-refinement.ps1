$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '..\src\window.rs'
$source = Get-Content -Raw $path

$source = $source.Replace(
    'const DRAG_HANDLE_VISUAL_INSET_X: i32 = 4;',
    'const DRAG_HANDLE_VISUAL_INSET_X: i32 = 7;'
)

$sizeWeCount = ([regex]::Matches($source, 'IDC_SIZEWE')).Count
if ($sizeWeCount -ne 2) {
    throw "Expected exactly 2 IDC_SIZEWE occurrences, found $sizeWeCount."
}
$source = $source.Replace('IDC_SIZEWE', 'IDC_SIZEALL')

$oldPanel = @'
    let radius = sc(panel_radius).max(sc(1));
    draw_rounded_rect(hdc, &outer, &border, radius);

    let inner_inset = outer_inset + sc(1);
    let inner = RECT {
        left: inner_inset,
        top: inner_inset,
        right: width - inner_inset,
        bottom: height - inner_inset,
    };
    draw_rounded_rect(hdc, &inner, &fill, (radius - sc(1)).max(sc(1)));
'@

$newPanel = @'
    let inner_inset = outer_inset + sc(1);
    let inner = RECT {
        left: inner_inset,
        top: inner_inset,
        right: width - inner_inset,
        bottom: height - inner_inset,
    };

    if panel_radius <= 0 {
        unsafe {
            let border_brush = CreateSolidBrush(COLORREF(border.to_colorref()));
            FillRect(hdc, &outer, border_brush);
            let _ = DeleteObject(border_brush);

            let fill_brush = CreateSolidBrush(COLORREF(fill.to_colorref()));
            FillRect(hdc, &inner, fill_brush);
            let _ = DeleteObject(fill_brush);
        }
        return;
    }

    let radius = sc(panel_radius).max(sc(1));
    draw_rounded_rect(hdc, &outer, &border, radius);
    draw_rounded_rect(hdc, &inner, &fill, (radius - sc(1)).max(sc(1)));
'@

if (-not $source.Contains($oldPanel)) {
    throw 'Expected acrylic-panel rounded block not found.'
}
$source = $source.Replace($oldPanel, $newPanel)

Set-Content -Path $path -Value $source -Encoding utf8NoBOM -NoNewline
git diff --check
