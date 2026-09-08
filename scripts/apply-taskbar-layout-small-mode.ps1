$ErrorActionPreference = 'Stop'

$appearancePath = Join-Path $PSScriptRoot '..\src\appearance.rs'
$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$appearance = Get-Content -Raw $appearancePath
$window = Get-Content -Raw $windowPath

function Replace-Once([string]$text, [string]$pattern, [string]$replacement, [string]$name) {
    $updated = [regex]::Replace($text, $pattern, $replacement, 1)
    if ($updated -eq $text) { throw "Patch target not found: $name" }
    return $updated
}

# ---- appearance metrics ----------------------------------------------------
if ($appearance -notmatch 'pub outer_padding: i32') {
    $appearance = Replace-Once $appearance '(?m)^(\s*)pub panel_radius: i32,\r?$' ('$1pub panel_radius: i32,' + "`r`n" + '$1pub outer_padding: i32,' + "`r`n" + '$1pub label_bar_gap: i32,' + "`r`n" + '$1pub bar_percent_gap: i32,' + "`r`n" + '$1pub percent_width: i32,' + "`r`n" + '$1pub percent_reset_gap: i32,' + "`r`n" + '$1pub reset_width: i32,') 'StyleMetrics zone fields'
    $appearance = Replace-Once $appearance '(?m)^(\s*)panel_radius: 5,\r?\n(\s*)bar_width: 82,' ('$1panel_radius: 5,' + "`r`n" + '$1outer_padding: 6,' + "`r`n" + '$1label_bar_gap: 6,' + "`r`n" + '$1bar_percent_gap: 4,' + "`r`n" + '$1percent_width: 36,' + "`r`n" + '$1percent_reset_gap: 6,' + "`r`n" + '$1reset_width: 43,' + "`r`n" + '$2bar_width: 82,') 'Compact zone metrics'
    $appearance = Replace-Once $appearance '(?m)^(\s*)panel_radius: 5,\r?\n(\s*)bar_width: 62,' ('$1panel_radius: 5,' + "`r`n" + '$1outer_padding: 6,' + "`r`n" + '$1label_bar_gap: 6,' + "`r`n" + '$1bar_percent_gap: 4,' + "`r`n" + '$1percent_width: 36,' + "`r`n" + '$1percent_reset_gap: 6,' + "`r`n" + '$1reset_width: 0,' + "`r`n" + '$2bar_width: 62,') 'Minimal zone metrics'
}

# ---- app state and constants ----------------------------------------------
if ($window -notmatch 'small_taskbar_mode: bool') {
    $window = Replace-Once $window '(?m)^(\s*)appearance_preset: AppearancePreset,\r?$' ('$1appearance_preset: AppearancePreset,' + "`r`n" + '$1small_taskbar_mode: bool,' + "`r`n" + '$1small_show_weekly: bool,') 'AppState small mode fields'
    $window = Replace-Once $window '(?m)^(\s*)appearance_preset: settings\.appearance_preset,\r?$' ('$1appearance_preset: settings.appearance_preset,' + "`r`n" + '$1small_taskbar_mode: false,' + "`r`n" + '$1small_show_weekly: false,') 'AppState small mode initialization'
}

$window = $window.Replace('const DRAG_HANDLE_HIT_W: i32 = 8;', "const DRAG_HANDLE_HIT_W: i32 = 12;`r`nconst DRAG_HANDLE_VISUAL_INSET_X: i32 = 4;`r`nconst SMALL_TASKBAR_THRESHOLD: i32 = 34;`r`nconst SMALL_WIDGET_HEIGHT: i32 = 28;")
$window = [regex]::Replace($window, '(?m)^const RIGHT_MARGIN: i32 = 1;\r?\n', '')

# ---- layout helpers --------------------------------------------------------
$usageLayoutPattern = '(?s)fn usage_layout_widths\(_language: LanguageId, preset: AppearancePreset\) -> \(i32, i32\) \{.*?\r?\n\}\r?\n\r?\nfn usage_percent_for_display'
$usageLayoutReplacement = @'
fn usage_layout_widths(_language: LanguageId, preset: AppearancePreset) -> (i32, i32) {
    let metrics = preset.metrics();
    (metrics.label_width, metrics.reset_width)
}

fn usage_percent_for_display
'@
$window = Replace-Once $window $usageLayoutPattern $usageLayoutReplacement 'usage_layout_widths'

$totalWidthPattern = '(?s)fn total_widget_width_for_preset\(.*?\r?\n\}\r?\n\r?\nfn total_widget_width_for\('
$totalWidthReplacement = @'
fn total_widget_width_for_preset(
    active_models: i32,
    language: LanguageId,
    preset: AppearancePreset,
) -> i32 {
    let bar_segments = row_bar_segment_count(active_models, preset);
    let (label_width, reset_width) = usage_layout_widths(language, preset);
    let metrics = preset.metrics();
    let progress_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP);
    let model_width = progress_width
        + sc(metrics.bar_percent_gap)
        + sc(metrics.percent_width)
        + if reset_width > 0 {
            sc(metrics.percent_reset_gap) + sc(reset_width)
        } else {
            0
        };

    sc(DRAG_HANDLE_HIT_W)
        + sc(metrics.outer_padding)
        + sc(label_width)
        + sc(metrics.label_bar_gap)
        + model_width * active_models
        + sc(metrics.model_right_margin) * (active_models - 1)
        + sc(metrics.outer_padding)
}

fn total_widget_width_for(
'@
$window = Replace-Once $window $totalWidthPattern $totalWidthReplacement 'total_widget_width_for_preset'

# Replace old usage/text/status color helpers with the new semantic palette.
$colorPattern = '(?s)fn claude_usage_text_color\(.*?\r?\n\}\r?\n\r?\nfn codex_quota_status_color\(.*?\r?\n\}\r?\n'
$colorReplacement = @'
fn quota_bar_color(_is_dark: bool, displayed_percent: f64, language: LanguageId) -> Color {
    let remaining = if language == LanguageId::SimplifiedChinese {
        displayed_percent.clamp(0.0, 100.0)
    } else {
        100.0 - displayed_percent.clamp(0.0, 100.0)
    };
    if remaining > 50.0 {
        Color::from_hex("#55A8F2")
    } else if remaining > 20.0 {
        Color::from_hex("#E6B84A")
    } else {
        Color::from_hex("#D95C5C")
    }
}

fn stable_percentage_text_color(is_dark: bool) -> Color {
    if is_dark {
        Color::from_hex("#FFFFFF")
    } else {
        Color::from_hex("#202020")
    }
}
'@
$window = Replace-Once $window $colorPattern $colorReplacement 'semantic quota colors'

# Helpers for taskbar sizing/small mode.
if ($window -notmatch 'fn is_small_taskbar_height\(') {
    $marker = 'fn current_appearance_preset() -> AppearancePreset {'
    $helpers = @'
fn is_small_taskbar_height(taskbar_height: i32) -> bool {
    taskbar_height <= sc(SMALL_TASKBAR_THRESHOLD)
}

fn widget_height_for_state(state: &AppState) -> i32 {
    if state.small_taskbar_mode {
        sc(SMALL_WIDGET_HEIGHT)
    } else {
        sc(state.appearance_preset.metrics().widget_height)
    }
}

'@
    if (-not $window.Contains($marker)) { throw 'current_appearance_preset marker missing' }
    $window = $window.Replace($marker, $helpers + $marker)
}

# ---- draw row / bar --------------------------------------------------------
$drawRowPattern = '(?s)fn draw_row\(.*?\r?\n\}\r?\n\r?\nfn model_usage_width'
$drawRowReplacement = @'
fn draw_row(
    hdc: HDC,
    x: i32,
    y: i32,
    is_dark: bool,
    language: LanguageId,
    text_color: &Color,
    label: &str,
    claude_percent: f64,
    claude_text: &str,
    codex_percent: f64,
    codex_text: &str,
    antigravity_percent: f64,
    antigravity_text: &str,
    show_claude_code: bool,
    show_codex: bool,
    show_antigravity: bool,
    _claude_accent: &Color,
    _codex_accent: &Color,
    _antigravity_accent: &Color,
    track: &Color,
    label_width: i32,
    text_width: i32,
) {
    let seg_h = sc(SEGMENT_H);
    let active_models = active_model_count(show_claude_code, show_codex, show_antigravity);
    let preset = current_appearance_preset();
    let segment_count = row_bar_segment_count(active_models, preset);
    let metrics = preset.metrics();
    let percentage_text_color = stable_percentage_text_color(is_dark);

    unsafe {
        let _ = SetTextColor(hdc, COLORREF(text_color.to_colorref()));
        let mut label_wide: Vec<u16> = label.encode_utf16().collect();
        let mut label_rect = RECT {
            left: x,
            top: y,
            right: x + sc(label_width),
            bottom: y + seg_h,
        };
        let _ = DrawTextW(hdc, &mut label_wide, &mut label_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE);

        let mut model_x = x + sc(label_width) + sc(metrics.label_bar_gap);
        if show_claude_code {
            let bar_color = quota_bar_color(is_dark, claude_percent, language);
            draw_usage_bar(hdc, model_x, y, segment_count, claude_percent, claude_text, &bar_color, track, &percentage_text_color, text_width);
            model_x += model_usage_width(segment_count, text_width, preset) + sc(metrics.model_right_margin);
        }
        if show_codex {
            let bar_color = quota_bar_color(is_dark, codex_percent, language);
            draw_usage_bar(hdc, model_x, y, segment_count, codex_percent, codex_text, &bar_color, track, &percentage_text_color, text_width);
            model_x += model_usage_width(segment_count, text_width, preset) + sc(metrics.model_right_margin);
        }
        if show_antigravity {
            let bar_color = quota_bar_color(is_dark, antigravity_percent, language);
            draw_usage_bar(hdc, model_x, y, segment_count, antigravity_percent, antigravity_text, &bar_color, track, &percentage_text_color, text_width);
        }
    }
}

fn model_usage_width
'@
$window = Replace-Once $window $drawRowPattern $drawRowReplacement 'draw_row'

$modelAndBarPattern = '(?s)fn model_usage_width\(.*?\r?\n\}\r?\n\r?\nfn draw_usage_value_text'
$modelAndBarReplacement = @'
fn model_usage_width(segment_count: i32, text_width: i32, preset: AppearancePreset) -> i32 {
    let metrics = preset.metrics();
    let progress_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * segment_count - sc(SEGMENT_GAP);
    progress_width
        + sc(metrics.bar_percent_gap)
        + sc(metrics.percent_width)
        + if text_width > 0 {
            sc(metrics.percent_reset_gap) + sc(text_width)
        } else {
            0
        }
}

fn draw_usage_bar(
    hdc: HDC,
    bar_x: i32,
    y: i32,
    segment_count: i32,
    percent: f64,
    text: &str,
    accent: &Color,
    track: &Color,
    text_color: &Color,
    text_width: i32,
) {
    let seg_w = sc(SEGMENT_W);
    let seg_h = sc(SEGMENT_H);
    let seg_gap = sc(SEGMENT_GAP);
    let metrics = current_appearance_preset().metrics();
    let progress_width = segment_count * (seg_w + seg_gap) - seg_gap;
    let bar_h = sc(metrics.bar_height).min(seg_h);
    let bar_y = y + (seg_h - bar_h) / 2;

    unsafe {
        let percent_clamped = percent.clamp(0.0, 100.0);
        let bar_rect = RECT { left: bar_x, top: bar_y, right: bar_x + progress_width, bottom: bar_y + bar_h };
        let track_brush = CreateSolidBrush(COLORREF(track.to_colorref()));
        FillRect(hdc, &bar_rect, track_brush);
        let _ = DeleteObject(track_brush);

        let fill_width = (progress_width as f64 * percent_clamped / 100.0).round() as i32;
        if fill_width > 0 {
            let fill_rect = RECT { left: bar_x, top: bar_y, right: bar_x + fill_width, bottom: bar_y + bar_h };
            let fill_brush = CreateSolidBrush(COLORREF(accent.to_colorref()));
            FillRect(hdc, &fill_rect, fill_brush);
            let _ = DeleteObject(fill_brush);
        }

        let text_x = bar_x + progress_width + sc(metrics.bar_percent_gap);
        draw_usage_value_text(hdc, text_x, y, seg_h, text, text_color, text_width);
    }
}

fn draw_usage_value_text
'@
$window = Replace-Once $window $modelAndBarPattern $modelAndBarReplacement 'model_usage_width/draw_usage_bar'

# Fixed Q3 and Q4 slots inside draw_usage_value_text.
$window = $window.Replace('right: text_x + sc(metrics.bar_value_width),', 'right: text_x + sc(metrics.percent_width),')
$window = $window.Replace('let secondary_x = text_x + sc(metrics.bar_value_width) + sc(metrics.bar_right_margin);', 'let secondary_x = text_x + sc(metrics.percent_width) + sc(metrics.percent_reset_gap);')

# ---- paint content ---------------------------------------------------------
$paintPattern = '(?s)fn paint_content\(.*?\r?\n\}\r?\n\r?\nfn poll_error_display_label'
$paintReplacement = @'
fn paint_content(
    hdc: HDC,
    width: i32,
    height: i32,
    is_dark: bool,
    bg: &Color,
    text_color: &Color,
    accent: &Color,
    track: &Color,
    language: LanguageId,
    strings: Strings,
    session_pct: f64,
    session_text: &str,
    weekly_pct: f64,
    weekly_text: &str,
    codex_session_pct: f64,
    codex_session_text: &str,
    codex_weekly_pct: f64,
    codex_weekly_text: &str,
    antigravity_session_pct: f64,
    antigravity_session_text: &str,
    antigravity_weekly_pct: f64,
    antigravity_weekly_text: &str,
    show_claude_code: bool,
    show_codex: bool,
    show_antigravity: bool,
    show_session_window: bool,
    show_weekly_window: bool,
    codex_accent: &Color,
    antigravity_accent: &Color,
) {
    unsafe {
        let session_pct = usage_percent_for_display(language, session_pct);
        let weekly_pct = usage_percent_for_display(language, weekly_pct);
        let codex_session_pct = usage_percent_for_display(language, codex_session_pct);
        let codex_weekly_pct = usage_percent_for_display(language, codex_weekly_pct);
        let antigravity_session_pct = usage_percent_for_display(language, antigravity_session_pct);
        let antigravity_weekly_pct = usage_percent_for_display(language, antigravity_weekly_pct);
        let preset = current_appearance_preset();
        let metrics = preset.metrics();
        let (label_width, text_width) = usage_layout_widths(language, preset);
        let (small_taskbar_mode, small_show_weekly) = {
            let state = lock_state();
            state.as_ref().map(|s| (s.small_taskbar_mode, s.small_show_weekly)).unwrap_or((false, false))
        };
        let effective_show_session = if small_taskbar_mode { !small_show_weekly } else { show_session_window };
        let effective_show_weekly = if small_taskbar_mode { small_show_weekly } else { show_weekly_window };

        let client_rect = RECT { left: 0, top: 0, right: width, bottom: height };
        let bg_brush = CreateSolidBrush(COLORREF(bg.to_colorref()));
        FillRect(hdc, &client_rect, bg_brush);
        let _ = DeleteObject(bg_brush);

        draw_acrylic_panel(hdc, width, height, is_dark, metrics.panel_radius);
        draw_drag_handle(hdc, height, is_dark);

        let content_x = sc(DRAG_HANDLE_HIT_W) + sc(metrics.outer_padding);
        let row2_y = height - sc(4) - sc(SEGMENT_H);
        let row1_y = row2_y - sc(metrics.row_gap) - sc(SEGMENT_H);
        let single_row_y = (height - sc(SEGMENT_H)) / 2;

        let _ = SetBkMode(hdc, TRANSPARENT);
        let _ = SetTextColor(hdc, COLORREF(text_color.to_colorref()));
        let font_name = native_interop::wide_str("Segoe UI");
        let font = CreateFontW(sc(metrics.font_height), 0, 0, 0, FW_MEDIUM.0 as i32, 0, 0, 0, DEFAULT_CHARSET.0 as u32, OUT_TT_PRECIS.0 as u32, CLIP_DEFAULT_PRECIS.0 as u32, CLEARTYPE_QUALITY.0 as u32, (DEFAULT_PITCH.0 | FF_DONTCARE.0) as u32, PCWSTR::from_raw(font_name.as_ptr()));
        let old_font = SelectObject(hdc, font);

        if effective_show_session {
            draw_row(hdc, content_x, if effective_show_weekly { row1_y } else { single_row_y }, is_dark, language, text_color, strings.session_window, session_pct, session_text, codex_session_pct, codex_session_text, antigravity_session_pct, antigravity_session_text, show_claude_code, show_codex, show_antigravity, accent, codex_accent, antigravity_accent, track, label_width, text_width);
        }
        if effective_show_weekly {
            draw_row(hdc, content_x, if effective_show_session { row2_y } else { single_row_y }, is_dark, language, text_color, strings.weekly_window, weekly_pct, weekly_text, codex_weekly_pct, codex_weekly_text, antigravity_weekly_pct, antigravity_weekly_text, show_claude_code, show_codex, show_antigravity, accent, codex_accent, antigravity_accent, track, label_width, text_width);
        }

        SelectObject(hdc, old_font);
        let _ = DeleteObject(font);
    }
}

fn poll_error_display_label
'@
$window = Replace-Once $window $paintPattern $paintReplacement 'paint_content'

# ---- drag handle visual inset ---------------------------------------------
$window = $window.Replace('let origin_x = (sc(DRAG_HANDLE_HIT_W) - matrix_w) / 2;', 'let origin_x = sc(DRAG_HANDLE_VISUAL_INSET_X);')

# ---- positioning and small-taskbar mode -----------------------------------
$positionPattern = '(?s)fn position_at_taskbar\(\) \{.*?\r?\n\}\r?\n\r?\nfn compute_anchor_y'
$positionReplacement = @'
fn position_at_taskbar() {
    refresh_dpi();
    let (hwnd, embedded, tray_offset, taskbar_hwnd) = {
        let state = lock_state();
        let s = match state.as_ref() { Some(s) => s, None => return };
        if s.dragging { return; }
        let taskbar_hwnd = match s.taskbar_hwnd {
            Some(h) => h,
            None => { diagnose::log("position_at_taskbar skipped: no taskbar handle"); return; }
        };
        (s.hwnd.to_hwnd(), s.embedded, s.tray_offset, taskbar_hwnd)
    };

    let taskbar_rect = match native_interop::get_taskbar_rect(taskbar_hwnd) {
        Some(r) => r,
        None => { diagnose::log("position_at_taskbar skipped: unable to query taskbar rect"); return; }
    };
    let taskbar_height = taskbar_rect.bottom - taskbar_rect.top;
    let small_mode = is_small_taskbar_height(taskbar_height);
    {
        let mut state = lock_state();
        if let Some(s) = state.as_mut() {
            if s.small_taskbar_mode != small_mode {
                s.small_taskbar_mode = small_mode;
                if small_mode { s.small_show_weekly = false; }
            }
        }
    }

    let mut tray_left = taskbar_rect.right;
    let anchor_top = taskbar_rect.top;
    let anchor_height = taskbar_height;
    if let Some(tray_hwnd) = native_interop::find_child_window(taskbar_hwnd, "TrayNotifyWnd") {
        if let Some(tray_rect) = native_interop::get_window_rect_safe(tray_hwnd) { tray_left = tray_rect.left; }
    }

    let widget_width = total_widget_width();
    let max_offset = (tray_left - taskbar_rect.left - widget_width).max(0);
    let tray_offset = tray_offset.clamp(0, max_offset);
    let offset_changed = {
        let mut state = lock_state();
        if let Some(s) = state.as_mut() {
            if s.tray_offset != tray_offset { s.tray_offset = tray_offset; true } else { false }
        } else { false }
    };
    if offset_changed { save_state_settings(); }

    let widget_height = {
        let state = lock_state();
        state.as_ref().map(widget_height_for_state).unwrap_or(sc(AppearancePreset::Compact.metrics().widget_height))
    };
    let y = compute_anchor_y(anchor_top, anchor_height, widget_height);
    if embedded {
        let x = tray_left - taskbar_rect.left - widget_width - tray_offset;
        native_interop::move_window(hwnd, x, y - taskbar_rect.top, widget_width, widget_height);
        diagnose::log(format!("positioned embedded widget at x={x} y={} w={widget_width} h={widget_height}", y - taskbar_rect.top));
    } else {
        let x = tray_left - widget_width - tray_offset;
        native_interop::move_window(hwnd, x, y, widget_width, widget_height);
        diagnose::log(format!("positioned fallback widget at x={x} y={y} w={widget_width} h={widget_height}"));
    }
}

fn compute_anchor_y
'@
$window = Replace-Once $window $positionPattern $positionReplacement 'position_at_taskbar'

$window = Replace-Once $window '(?s)fn compute_anchor_y\(anchor_top: i32, anchor_height: i32, widget_height: i32\) -> i32 \{.*?\r?\n\}' @'
fn compute_anchor_y(anchor_top: i32, anchor_height: i32, widget_height: i32) -> i32 {
    anchor_top + (anchor_height - widget_height).max(0) / 2
}
'@ 'compute_anchor_y'

# Render-layered height and drag height must honor small mode.
$window = $window.Replace('let height = sc(current_appearance_preset().metrics().widget_height);', @'
let height = {
        let state = lock_state();
        state.as_ref().map(widget_height_for_state).unwrap_or(sc(current_appearance_preset().metrics().widget_height))
    };
'@)
$window = $window.Replace('let widget_height = sc(s.appearance_preset.metrics().widget_height);', 'let widget_height = widget_height_for_state(s);')

# Content left-click toggles 5H/7D only in small-taskbar mode; drag path remains unchanged.
$toggleNeedle = @'
            if let Some((current_taskbar_index, drag_start_client_x)) = drag_result {
'@
$toggleReplacement = @'
            if drag_result.is_none() {
                let client_x = (lparam.0 & 0xFFFF) as i16 as i32;
                let client_y = ((lparam.0 >> 16) & 0xFFFF) as i16 as i32;
                if !is_drag_handle_point(client_x, client_y) {
                    let toggled = {
                        let mut state = lock_state();
                        if let Some(s) = state.as_mut() {
                            if s.small_taskbar_mode {
                                s.small_show_weekly = !s.small_show_weekly;
                                true
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    };
                    if toggled { render_layered(); }
                }
            }
            if let Some((current_taskbar_index, drag_start_client_x)) = drag_result {
'@
if (-not $window.Contains($toggleNeedle)) { throw 'WM_LBUTTONUP insertion point missing' }
$window = $window.Replace($toggleNeedle, $toggleReplacement)

# ---- regression tests ------------------------------------------------------
$testMarker = '    #[test]`r`n    fn service_tooltip_combines_visible_quota_rows() {'
if ($window -notmatch 'fn centers_widget_vertically\(') {
    $tests = @'
    #[test]
    fn centers_widget_vertically() {
        assert_eq!(compute_anchor_y(100, 48, 42), 103);
        assert_eq!(compute_anchor_y(100, 32, 28), 102);
        assert_eq!(compute_anchor_y(100, 24, 28), 100);
    }

    #[test]
    fn small_taskbar_threshold_is_dpi_aware_at_96_dpi() {
        CURRENT_DPI.store(96, Ordering::Relaxed);
        assert!(is_small_taskbar_height(32));
        assert!(is_small_taskbar_height(34));
        assert!(!is_small_taskbar_height(35));
    }

'@
    $marker = "    #[test]`r`n    fn service_tooltip_combines_visible_quota_rows() {"
    if (-not $window.Contains($marker)) { $marker = "    #[test]`n    fn service_tooltip_combines_visible_quota_rows() {" }
    if (-not $window.Contains($marker)) { throw 'test insertion marker missing' }
    $window = $window.Replace($marker, $tests + $marker)
}

Set-Content -Path $appearancePath -Value $appearance -Encoding utf8NoBOM -NoNewline
Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline

git diff --check
