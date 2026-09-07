$ErrorActionPreference = 'Stop'

$appearancePath = Join-Path $PSScriptRoot '..\src\appearance.rs'
$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'

$appearance = Get-Content -Raw $appearancePath
$window = Get-Content -Raw $windowPath

# Appearance metrics: add a shared panel radius without changing any existing quota/layout values.
if ($appearance -notmatch 'pub panel_radius: i32') {
    $appearance = $appearance.Replace(
        "    pub widget_height: i32,`r`n",
        "    pub widget_height: i32,`r`n    pub panel_radius: i32,`r`n"
    )
    $appearance = $appearance.Replace(
        "                widget_height: 42,`r`n",
        "                widget_height: 42,`r`n                panel_radius: 5,`r`n"
    )
    $appearance = $appearance.Replace(
        "                widget_height: 40,`r`n",
        "                widget_height: 40,`r`n                panel_radius: 5,`r`n"
    )
}

# Replace the narrow legacy divider hit area with a wider dedicated drag-handle hit area.
$window = $window.Replace(
    'const LEFT_DIVIDER_W: i32 = 3;',
    "const DRAG_HANDLE_HIT_W: i32 = 8;`r`nconst DRAG_HANDLE_HIT_H: i32 = 24;"
)

$oldHitTest = @'
fn is_drag_handle_point(client_x: i32, client_y: i32) -> bool {
    let divider_h = sc(18);
    let divider_top = (sc(current_appearance_preset().metrics().widget_height) - divider_h) / 2;
    client_x >= 0
        && client_x < sc(LEFT_DIVIDER_W)
        && client_y >= divider_top
        && client_y < divider_top + divider_h
}
'@
$newHitTest = @'
fn is_drag_handle_point(client_x: i32, client_y: i32) -> bool {
    let hit_h = sc(DRAG_HANDLE_HIT_H);
    let hit_top = (sc(current_appearance_preset().metrics().widget_height) - hit_h) / 2;
    client_x >= 0
        && client_x < sc(DRAG_HANDLE_HIT_W)
        && client_y >= hit_top
        && client_y < hit_top + hit_h
}
'@
if ($window.Contains($oldHitTest)) {
    $window = $window.Replace($oldHitTest, $newHitTest)
} elseif ($window -notmatch 'DRAG_HANDLE_HIT_H') {
    throw 'Could not replace drag-handle hit test.'
}

# Width accounting must reserve the new 8px drag hit area.
$window = $window.Replace('    sc(LEFT_DIVIDER_W)', '    sc(DRAG_HANDLE_HIT_W)')

$oldDivider = @'
        // Left divider
        let divider_h = sc(18);
        let divider_top = (height - divider_h) / 2;
        let divider_bottom = divider_top + divider_h;

        let (div_left, div_right) = if is_dark {
            ((80, 80, 80), (40, 40, 40))
        } else {
            ((160, 160, 160), (230, 230, 230))
        };
        let left_brush = CreateSolidBrush(COLORREF(native_interop::colorref(
            div_left.0, div_left.1, div_left.2,
        )));
        let left_rect = RECT {
            left: 0,
            top: divider_top,
            right: sc(2),
            bottom: divider_bottom,
        };
        FillRect(hdc, &left_rect, left_brush);
        let _ = DeleteObject(left_brush);

        let right_brush = CreateSolidBrush(COLORREF(native_interop::colorref(
            div_right.0,
            div_right.1,
            div_right.2,
        )));
        let right_rect = RECT {
            left: sc(2),
            top: divider_top,
            right: sc(3),
            bottom: divider_bottom,
        };
        FillRect(hdc, &right_rect, right_brush);
        let _ = DeleteObject(right_brush);

        let content_x = sc(LEFT_DIVIDER_W) + sc(preset.metrics().divider_right_margin);
'@
$newDivider = @'
        draw_acrylic_panel(hdc, width, height, is_dark, preset.metrics().panel_radius);
        draw_drag_handle(hdc, height, is_dark);

        let content_x = sc(DRAG_HANDLE_HIT_W) + sc(preset.metrics().divider_right_margin);
'@
if ($window.Contains($oldDivider)) {
    $window = $window.Replace($oldDivider, $newDivider)
} elseif ($window -notmatch 'draw_acrylic_panel\(hdc, width, height, is_dark') {
    throw 'Could not replace legacy divider drawing.'
}

# Add reusable GDI helpers just before the existing rounded-rectangle helper.
if ($window -notmatch 'fn draw_acrylic_panel\(') {
    $helpers = @'
fn draw_acrylic_panel(hdc: HDC, width: i32, height: i32, is_dark: bool, panel_radius: i32) {
    let (border, fill) = if is_dark {
        (Color::from_hex("#343B43"), Color::from_hex("#242A31"))
    } else {
        (Color::from_hex("#D4D9DF"), Color::from_hex("#EEF1F4"))
    };

    let outer_inset = sc(1);
    let outer = RECT {
        left: outer_inset,
        top: outer_inset,
        right: width - outer_inset,
        bottom: height - outer_inset,
    };
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
}

fn draw_drag_handle(hdc: HDC, height: i32, is_dark: bool) {
    let dot = sc(2).max(1);
    let gap_x = sc(1).max(1);
    let gap_y = sc(2).max(1);
    let matrix_w = dot * 2 + gap_x;
    let matrix_h = dot * 3 + gap_y * 2;
    let origin_x = (sc(DRAG_HANDLE_HIT_W) - matrix_w) / 2;
    let origin_y = (height - matrix_h) / 2;
    let color = if is_dark {
        Color::from_hex("#69727C")
    } else {
        Color::from_hex("#8A929A")
    };

    for row in 0..3 {
        for col in 0..2 {
            let left = origin_x + col * (dot + gap_x);
            let top = origin_y + row * (dot + gap_y);
            let rect = RECT {
                left,
                top,
                right: left + dot,
                bottom: top + dot,
            };
            draw_rounded_rect(hdc, &rect, &color, sc(1).max(1));
        }
    }
}

'@
    $marker = 'fn draw_rounded_rect(hdc: HDC, rect: &RECT, color: &Color, radius: i32) {'
    if (-not $window.Contains($marker)) {
        throw 'Could not locate draw_rounded_rect insertion point.'
    }
    $window = $window.Replace($marker, $helpers + $marker)
}

Set-Content -Path $appearancePath -Value $appearance -Encoding utf8NoBOM -NoNewline
Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline

git diff --check
