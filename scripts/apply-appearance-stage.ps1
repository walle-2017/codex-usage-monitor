# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'
$path = 'src/window.rs'
$text = Get-Content -Raw -Path $path

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:text.Contains($old)) { throw "Required source fragment not found:`n$old" }
    $script:text = $script:text.Replace($old, $new)
}

if ($text.Contains('fn draw_usage_value_text(')) {
    Write-Host 'Final appearance hierarchy already present.'
    exit 0
}

# Preset-specific widget heights.
$text = $text.Replace('sc(WIDGET_HEIGHT),', 'sc(AppearancePreset::Compact.metrics().widget_height),')
$text = $text.Replace('let height = sc(WIDGET_HEIGHT);', 'let height = sc(current_appearance_preset().metrics().widget_height);')
$text = $text.Replace('let widget_height = sc(WIDGET_HEIGHT);', 'let widget_height = sc(current_appearance_preset().metrics().widget_height);')
$text = $text.Replace(
    'let divider_top = (sc(WIDGET_HEIGHT) - divider_h) / 2;',
    'let divider_top = (sc(current_appearance_preset().metrics().widget_height) - divider_h) / 2;'
)

# Preset-specific row spacing.
Replace-Required @'
        let row2_y = height - sc(5) - sc(SEGMENT_H);
        let row1_y = row2_y - sc(10) - sc(SEGMENT_H);
'@ @'
        let row2_y = height - sc(4) - sc(SEGMENT_H);
        let row1_y = row2_y - sc(preset.metrics().row_gap) - sc(SEGMENT_H);
'@

# Replace the single-font value draw with primary/secondary visual hierarchy.
Replace-Required @'
        let text_x = bar_x + bar_width + sc(current_appearance_preset().metrics().bar_right_margin);
        let mut text_wide: Vec<u16> = text.encode_utf16().collect();
        let mut text_rect = RECT {
            left: text_x,
            top: y,
            right: text_x + sc(text_width),
            bottom: y + seg_h,
        };
        let _ = SetTextColor(hdc, COLORREF(text_color.to_colorref()));
        let _ = DrawTextW(
            hdc,
            &mut text_wide,
            &mut text_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE,
        );
'@ @'
        let text_x = bar_x + bar_width + sc(current_appearance_preset().metrics().bar_right_margin);
        draw_usage_value_text(hdc, text_x, y, seg_h, text, text_color, text_width);
'@

Replace-Required @'
fn draw_rounded_rect(hdc: HDC, rect: &RECT, color: &Color, radius: i32) {
'@ @'
fn draw_usage_value_text(
    hdc: HDC,
    text_x: i32,
    y: i32,
    row_height: i32,
    text: &str,
    primary_color: &Color,
    total_text_width: i32,
) {
    let preset = current_appearance_preset();
    let metrics = preset.metrics();
    let (primary, secondary) = text
        .split_once("  ")
        .map(|(primary, secondary)| (primary, Some(secondary)))
        .unwrap_or((text, None));

    unsafe {
        let font_name = native_interop::wide_str("Segoe UI");
        let primary_font = CreateFontW(
            sc(metrics.value_font_height),
            0, 0, 0,
            FW_SEMIBOLD.0 as i32,
            0, 0, 0,
            DEFAULT_CHARSET.0 as u32,
            OUT_TT_PRECIS.0 as u32,
            CLIP_DEFAULT_PRECIS.0 as u32,
            CLEARTYPE_QUALITY.0 as u32,
            (DEFAULT_PITCH.0 | FF_DONTCARE.0) as u32,
            PCWSTR::from_raw(font_name.as_ptr()),
        );
        let old_font = SelectObject(hdc, primary_font);
        let _ = SetTextColor(hdc, COLORREF(primary_color.to_colorref()));
        let mut primary_wide: Vec<u16> = primary.encode_utf16().collect();
        let mut primary_rect = RECT {
            left: text_x,
            top: y,
            right: text_x + sc(metrics.text_width),
            bottom: y + row_height,
        };
        let _ = DrawTextW(
            hdc,
            &mut primary_wide,
            &mut primary_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE,
        );

        if let Some(secondary) = secondary {
            let secondary_font = CreateFontW(
                sc(metrics.secondary_font_height),
                0, 0, 0,
                FW_NORMAL.0 as i32,
                0, 0, 0,
                DEFAULT_CHARSET.0 as u32,
                OUT_TT_PRECIS.0 as u32,
                CLIP_DEFAULT_PRECIS.0 as u32,
                CLEARTYPE_QUALITY.0 as u32,
                (DEFAULT_PITCH.0 | FF_DONTCARE.0) as u32,
                PCWSTR::from_raw(font_name.as_ptr()),
            );
            SelectObject(hdc, secondary_font);
            let secondary_color = if theme::is_dark_mode() {
                Color::from_hex("#92979D")
            } else {
                Color::from_hex("#666666")
            };
            let _ = SetTextColor(hdc, COLORREF(secondary_color.to_colorref()));
            let mut secondary_wide: Vec<u16> = secondary.encode_utf16().collect();
            let secondary_x = text_x + sc(metrics.text_width);
            let mut secondary_rect = RECT {
                left: secondary_x,
                top: y,
                right: text_x + sc(total_text_width),
                bottom: y + row_height,
            };
            let _ = DrawTextW(
                hdc,
                &mut secondary_wide,
                &mut secondary_rect,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE,
            );
            SelectObject(hdc, primary_font);
            let _ = DeleteObject(secondary_font);
        }

        SelectObject(hdc, old_font);
        let _ = DeleteObject(primary_font);
    }
}

fn draw_rounded_rect(hdc: HDC, rect: &RECT, color: &Color, radius: i32) {
'@

Set-Content -Path $path -Value $text -Encoding utf8NoBOM
Write-Host 'Applied preset height, row spacing, and primary/secondary value hierarchy.'
