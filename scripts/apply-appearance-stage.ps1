# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'
$windowPath = 'src/window.rs'
$appearancePath = 'src/appearance.rs'
$window = Get-Content -Raw -Path $windowPath
$appearance = Get-Content -Raw -Path $appearancePath

function Replace-Window([string]$old, [string]$new) {
    if (-not $script:window.Contains($old)) { throw "Window fragment not found:`n$old" }
    $script:window = $script:window.Replace($old, $new)
}
function Replace-Appearance([string]$old, [string]$new) {
    if (-not $script:appearance.Contains($old)) { throw "Appearance fragment not found:`n$old" }
    $script:appearance = $script:appearance.Replace($old, $new)
}

if ($window.Contains('fn codex_quota_status_color(') -and $appearance.Contains('pub fn taskbar_line(')) {
    Write-Host 'Taskbar visual implementation already present.'
    exit 0
}

# Taskbar text hierarchy: percentage first, reset time secondary, Minimal hides reset.
Replace-Appearance @'
    TaskbarValueText { primary, secondary }
}

#[cfg(test)]
'@ @'
    TaskbarValueText { primary, secondary }
}

pub fn taskbar_line(
    preset: AppearancePreset,
    language: LanguageId,
    section: &UsageSection,
    window: UsageWindowKind,
) -> String {
    let value = taskbar_value_text(preset, language, section, window);
    match (preset, value.secondary) {
        (AppearancePreset::Default, Some(reset)) => format!("{}  ↻{}", value.primary, reset),
        (AppearancePreset::Compact, Some(reset)) => format!("{}  {}", value.primary, reset),
        _ => value.primary,
    }
}

#[cfg(test)]
'@

# Cached taskbar strings are now presentation-specific instead of verbose tooltip strings.
Replace-Window @'
fn refresh_usage_texts(state: &mut AppState) {
    if !state.last_poll_ok {
        return;
    }

    let strings = state.language.strings();
    let show_remaining = state.language == LanguageId::SimplifiedChinese;
    let Some(data) = state.data.as_ref() else {
        return;
    };

    if let Some(claude_code) = data.claude_code.as_ref() {
        state.session_text = poller::format_line(
            &claude_code.session,
            strings,
            show_remaining,
            poller::UsageWindowKind::Session,
        );
        state.weekly_text = poller::format_line(
            &claude_code.weekly,
            strings,
            show_remaining,
            poller::UsageWindowKind::Weekly,
        );
    } else if state.show_claude_code {
        state.session_text = "!".to_string();
        state.weekly_text = "!".to_string();
    }

    if let Some(codex) = data.codex.as_ref() {
        state.codex_session_text = poller::format_line(
            &codex.session,
            strings,
            show_remaining,
            poller::UsageWindowKind::Session,
        );
        state.codex_weekly_text = poller::format_line(
            &codex.weekly,
            strings,
            show_remaining,
            poller::UsageWindowKind::Weekly,
        );
    } else if state.show_codex {
        state.codex_session_text = "!".to_string();
        state.codex_weekly_text = "!".to_string();
    }

    if let Some(antigravity) = data.antigravity.as_ref() {
        state.antigravity_session_text = poller::format_line(
            &antigravity.session,
            strings,
            show_remaining,
            poller::UsageWindowKind::Session,
        );
        state.antigravity_weekly_text =
            if antigravity.weekly.resets_at.is_none() && antigravity.weekly.percentage == 0.0 {
                "--".to_string()
            } else {
                poller::format_line(
                    &antigravity.weekly,
                    strings,
                    show_remaining,
                    poller::UsageWindowKind::Weekly,
                )
            };
    } else if state.show_antigravity {
        state.antigravity_session_text = "!".to_string();
        state.antigravity_weekly_text = "!".to_string();
    }
}
'@ @'
fn refresh_usage_texts(state: &mut AppState) {
    if !state.last_poll_ok {
        return;
    }

    let preset = state.appearance_preset;
    let language = state.language;
    let Some(data) = state.data.as_ref() else {
        return;
    };

    if let Some(claude_code) = data.claude_code.as_ref() {
        state.session_text = appearance::taskbar_line(
            preset, language, &claude_code.session, poller::UsageWindowKind::Session,
        );
        state.weekly_text = appearance::taskbar_line(
            preset, language, &claude_code.weekly, poller::UsageWindowKind::Weekly,
        );
    } else if state.show_claude_code {
        state.session_text = "!".to_string();
        state.weekly_text = "!".to_string();
    }

    if let Some(codex) = data.codex.as_ref() {
        state.codex_session_text = appearance::taskbar_line(
            preset, language, &codex.session, poller::UsageWindowKind::Session,
        );
        state.codex_weekly_text = appearance::taskbar_line(
            preset, language, &codex.weekly, poller::UsageWindowKind::Weekly,
        );
    } else if state.show_codex {
        state.codex_session_text = "!".to_string();
        state.codex_weekly_text = "!".to_string();
    }

    if let Some(antigravity) = data.antigravity.as_ref() {
        state.antigravity_session_text = appearance::taskbar_line(
            preset, language, &antigravity.session, poller::UsageWindowKind::Session,
        );
        state.antigravity_weekly_text =
            if antigravity.weekly.resets_at.is_none() && antigravity.weekly.percentage == 0.0 {
                "--".to_string()
            } else {
                appearance::taskbar_line(
                    preset, language, &antigravity.weekly, poller::UsageWindowKind::Weekly,
                )
            };
    } else if state.show_antigravity {
        state.antigravity_session_text = "!".to_string();
        state.antigravity_weekly_text = "!".to_string();
    }
}
'@

# Switching appearance must recompute shortened taskbar text immediately.
Replace-Window @'
                        if let Some(s) = state.as_mut() {
                            s.appearance_preset = preset;
                        }
'@ @'
                        if let Some(s) = state.as_mut() {
                            s.appearance_preset = preset;
                            refresh_usage_texts(s);
                        }
'@

# Keep tray tooltip verbose even when Compact/Minimal shorten the taskbar row.
Replace-Window @'
fn tray_icon_data_from_state() -> Option<tray_icon::TrayIconData> {
    let state = lock_state();
    match state.as_ref() {
        Some(s) if s.last_poll_ok => {
            let mut services = Vec::new();
            let strings = s.language.strings();
            if s.show_claude_code {
                services.push(service_tooltip(
                    strings.claude_code_model,
                    &s.session_text,
                    &s.weekly_text,
                    s.show_session_window,
                    s.show_weekly_window,
                ));
            }
            if s.show_codex {
                services.push(service_tooltip(
                    strings.codex_model,
                    &s.codex_session_text,
                    &s.codex_weekly_text,
                    s.show_session_window,
                    s.show_weekly_window,
                ));
            }
            if s.show_antigravity {
                services.push(service_tooltip(
                    strings.antigravity_model,
                    &s.antigravity_session_text,
                    &s.antigravity_weekly_text,
                    s.show_session_window,
                    s.show_weekly_window,
                ));
            }
            Some(tray_icon::TrayIconData {
                tooltip: if services.is_empty() {
                    strings.window_title.to_string()
                } else {
                    services.join("\n")
                },
            })
        }
        Some(s) => {
            let strings = s.language.strings();
            let tooltip = match (s.show_claude_code, s.show_codex, s.show_antigravity) {
                (false, true, false) => strings.codex_window_title,
                (false, false, true) => strings.antigravity_window_title,
                _ => strings.window_title,
            };
            Some(tray_icon::TrayIconData {
                tooltip: tooltip.to_string(),
            })
        }
        None => None,
    }
}
'@ @'
fn full_usage_line(
    section: &crate::models::UsageSection,
    language: LanguageId,
    strings: Strings,
    window: poller::UsageWindowKind,
) -> String {
    poller::format_line(
        section,
        strings,
        language == LanguageId::SimplifiedChinese,
        window,
    )
}

fn tray_icon_data_from_state() -> Option<tray_icon::TrayIconData> {
    let state = lock_state();
    match state.as_ref() {
        Some(s) if s.last_poll_ok => {
            let mut services = Vec::new();
            let strings = s.language.strings();
            let data = s.data.as_ref()?;
            if s.show_claude_code {
                if let Some(usage) = data.claude_code.as_ref() {
                    let session = full_usage_line(&usage.session, s.language, strings, poller::UsageWindowKind::Session);
                    let weekly = full_usage_line(&usage.weekly, s.language, strings, poller::UsageWindowKind::Weekly);
                    services.push(service_tooltip(strings.claude_code_model, &session, &weekly, s.show_session_window, s.show_weekly_window));
                }
            }
            if s.show_codex {
                if let Some(usage) = data.codex.as_ref() {
                    let session = full_usage_line(&usage.session, s.language, strings, poller::UsageWindowKind::Session);
                    let weekly = full_usage_line(&usage.weekly, s.language, strings, poller::UsageWindowKind::Weekly);
                    services.push(service_tooltip(strings.codex_model, &session, &weekly, s.show_session_window, s.show_weekly_window));
                }
            }
            if s.show_antigravity {
                if let Some(usage) = data.antigravity.as_ref() {
                    let session = full_usage_line(&usage.session, s.language, strings, poller::UsageWindowKind::Session);
                    let weekly = if usage.weekly.resets_at.is_none() && usage.weekly.percentage == 0.0 {
                        "--".to_string()
                    } else {
                        full_usage_line(&usage.weekly, s.language, strings, poller::UsageWindowKind::Weekly)
                    };
                    services.push(service_tooltip(strings.antigravity_model, &session, &weekly, s.show_session_window, s.show_weekly_window));
                }
            }
            Some(tray_icon::TrayIconData {
                tooltip: if services.is_empty() { strings.window_title.to_string() } else { services.join("\n") },
            })
        }
        Some(s) => {
            let strings = s.language.strings();
            let tooltip = match (s.show_claude_code, s.show_codex, s.show_antigravity) {
                (false, true, false) => strings.codex_window_title,
                (false, false, true) => strings.antigravity_window_title,
                _ => strings.window_title,
            };
            Some(tray_icon::TrayIconData { tooltip: tooltip.to_string() })
        }
        None => None,
    }
}
'@

# Preset-aware width calculation. CreateWindow starts compact, then normal positioning
# applies a saved preset after AppState is initialized.
Replace-Window @'
fn row_bar_segment_count(active_models: i32) -> i32 {
    match active_models {
        1 => SEGMENT_COUNT,
        2 => 5,
        _ => 4,
    }
}

fn usage_layout_widths(language: LanguageId) -> (i32, i32) {
    if language == LanguageId::SimplifiedChinese {
        (
            SIMPLIFIED_CHINESE_LABEL_WIDTH,
            SIMPLIFIED_CHINESE_TEXT_WIDTH,
        )
    } else {
        (LABEL_WIDTH, TEXT_WIDTH)
    }
}
'@ @'
fn current_appearance_preset() -> AppearancePreset {
    let state = lock_state();
    state.as_ref().map(|s| s.appearance_preset).unwrap_or_default()
}

fn row_bar_segment_count(active_models: i32, preset: AppearancePreset) -> i32 {
    match active_models {
        1 => match preset {
            AppearancePreset::Default => SEGMENT_COUNT,
            AppearancePreset::Compact => 8,
            AppearancePreset::Minimal => 6,
        },
        2 => match preset {
            AppearancePreset::Default => 5,
            AppearancePreset::Compact => 4,
            AppearancePreset::Minimal => 3,
        },
        _ => 3,
    }
}

fn usage_layout_widths(_language: LanguageId, preset: AppearancePreset) -> (i32, i32) {
    let metrics = preset.metrics();
    (metrics.label_width, metrics.text_width + metrics.secondary_width)
}
'@

Replace-Window @'
fn total_widget_width_for(active_models: i32, language: LanguageId) -> i32 {
    let bar_segments = row_bar_segment_count(active_models);
    let (label_width, text_width) = usage_layout_widths(language);
    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)
        + sc(BAR_RIGHT_MARGIN)
        + sc(text_width);

    sc(LEFT_DIVIDER_W)
        + sc(DIVIDER_RIGHT_MARGIN)
        + sc(label_width)
        + sc(LABEL_RIGHT_MARGIN)
        + model_width * active_models
        + sc(MODEL_RIGHT_MARGIN) * (active_models - 1)
        + sc(RIGHT_MARGIN)
}

fn total_widget_width_for_state(state: &AppState) -> i32 {
    total_widget_width_for(
        active_model_count(
            state.show_claude_code,
            state.show_codex,
            state.show_antigravity,
        ),
        state.language,
    )
}

fn total_widget_width() -> i32 {
    let (active_models, language) = {
        let state = lock_state();
        state
            .as_ref()
            .map(|s| {
                (
                    active_model_count(s.show_claude_code, s.show_codex, s.show_antigravity),
                    s.language,
                )
            })
            .unwrap_or((1, LanguageId::English))
    };
    total_widget_width_for(active_models, language)
}
'@ @'
fn total_widget_width_for_preset(
    active_models: i32,
    language: LanguageId,
    preset: AppearancePreset,
) -> i32 {
    let bar_segments = row_bar_segment_count(active_models, preset);
    let (label_width, text_width) = usage_layout_widths(language, preset);
    let metrics = preset.metrics();
    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)
        + sc(metrics.bar_right_margin)
        + sc(text_width);

    sc(LEFT_DIVIDER_W)
        + sc(metrics.divider_right_margin)
        + sc(label_width)
        + sc(metrics.label_right_margin)
        + model_width * active_models
        + sc(metrics.model_right_margin) * (active_models - 1)
        + sc(RIGHT_MARGIN)
}

fn total_widget_width_for(active_models: i32, language: LanguageId) -> i32 {
    total_widget_width_for_preset(active_models, language, AppearancePreset::Compact)
}

fn total_widget_width_for_state(state: &AppState) -> i32 {
    total_widget_width_for_preset(
        active_model_count(state.show_claude_code, state.show_codex, state.show_antigravity),
        state.language,
        state.appearance_preset,
    )
}

fn total_widget_width() -> i32 {
    let (active_models, language, preset) = {
        let state = lock_state();
        state
            .as_ref()
            .map(|s| (
                active_model_count(s.show_claude_code, s.show_codex, s.show_antigravity),
                s.language,
                s.appearance_preset,
            ))
            .unwrap_or((1, LanguageId::English, AppearancePreset::Compact))
    };
    total_widget_width_for_preset(active_models, language, preset)
}
'@

# Both render paths call paint_content without holding the AppState lock, so it
# can resolve the preset locally without widening the already-large parameter list.
Replace-Window 'let (label_width, text_width) = usage_layout_widths(language);' 'let preset = current_appearance_preset();`n        let (label_width, text_width) = usage_layout_widths(language, preset);'
Replace-Window 'let segment_count = row_bar_segment_count(active_models);' 'let preset = current_appearance_preset();`n    let segment_count = row_bar_segment_count(active_models, preset);'
Replace-Window 'let mut model_x = x + sc(label_width) + sc(LABEL_RIGHT_MARGIN);' 'let mut model_x = x + sc(label_width) + sc(preset.metrics().label_right_margin);'
Replace-Window 'model_x += model_usage_width(segment_count, text_width) + sc(MODEL_RIGHT_MARGIN);' 'model_x += model_usage_width(segment_count, text_width, preset) + sc(preset.metrics().model_right_margin);'
Replace-Window @'
fn model_usage_width(segment_count: i32, text_width: i32) -> i32 {
    (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * segment_count - sc(SEGMENT_GAP)
        + sc(BAR_RIGHT_MARGIN)
        + sc(text_width)
}
'@ @'
fn model_usage_width(segment_count: i32, text_width: i32, preset: AppearancePreset) -> i32 {
    (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * segment_count - sc(SEGMENT_GAP)
        + sc(preset.metrics().bar_right_margin)
        + sc(text_width)
}
'@

# Use a slimmer centered progress track while keeping the row height large enough for ClearType text.
Replace-Window @'
    let seg_w = sc(SEGMENT_W);
    let seg_h = sc(SEGMENT_H);
    let seg_gap = sc(SEGMENT_GAP);
    let bar_width = segment_count * (seg_w + seg_gap) - seg_gap;
    let corner_r = seg_h / 2;
'@ @'
    let seg_w = sc(SEGMENT_W);
    let seg_h = sc(SEGMENT_H);
    let seg_gap = sc(SEGMENT_GAP);
    let bar_width = segment_count * (seg_w + seg_gap) - seg_gap;
    let bar_h = sc(current_appearance_preset().metrics().bar_height).min(seg_h);
    let bar_y = y + (seg_h - bar_h) / 2;
    let corner_r = bar_h / 2;
'@
Replace-Window @'
            top: y,
            right: bar_x + bar_width,
            bottom: y + seg_h,
'@ @'
            top: bar_y,
            right: bar_x + bar_width,
            bottom: bar_y + bar_h,
'@
Replace-Window @'
                top: y,
                right: bar_x + fill_width,
                bottom: y + seg_h,
'@ @'
                top: bar_y,
                right: bar_x + fill_width,
                bottom: bar_y + bar_h,
'@
Replace-Window 'let text_x = bar_x + bar_width + sc(BAR_RIGHT_MARGIN);' 'let text_x = bar_x + bar_width + sc(current_appearance_preset().metrics().bar_right_margin);'

# Semantic single-Codex colors based on remaining quota.
Replace-Window @'
fn antigravity_usage_text_color(is_dark: bool) -> Color {
    if is_dark {
        Color::from_hex("#8AB4F8")
    } else {
        Color::from_hex("#1967D2")
    }
}
'@ @'
fn antigravity_usage_text_color(is_dark: bool) -> Color {
    if is_dark {
        Color::from_hex("#8AB4F8")
    } else {
        Color::from_hex("#1967D2")
    }
}

fn codex_quota_status_color(is_dark: bool, displayed_percent: f64) -> Color {
    let language = {
        let state = lock_state();
        state.as_ref().map(|s| s.language).unwrap_or(LanguageId::English)
    };
    let used = if language == LanguageId::SimplifiedChinese {
        100.0 - displayed_percent
    } else {
        displayed_percent
    };
    match appearance::quota_tone(used) {
        appearance::QuotaTone::Normal => {
            if is_dark { Color::from_hex("#5AA9E6") } else { Color::from_hex("#2563EB") }
        }
        appearance::QuotaTone::Warning => {
            if is_dark { Color::from_hex("#F4C95D") } else { Color::from_hex("#A16207") }
        }
        appearance::QuotaTone::Critical => {
            if is_dark { Color::from_hex("#FF6B6B") } else { Color::from_hex("#C62828") }
        }
    }
}
'@

Replace-Window @'
    let codex_value_color = if use_model_text_colors {
        codex_usage_text_color(is_dark)
    } else {
        *text_color
    };
'@ @'
    let codex_bar_color = if active_models == 1 && show_codex {
        codex_quota_status_color(is_dark, codex_percent)
    } else {
        *codex_accent
    };
    let codex_value_color = if active_models == 1 && show_codex {
        codex_bar_color
    } else if use_model_text_colors {
        codex_usage_text_color(is_dark)
    } else {
        *text_color
    };
'@
Replace-Window @'
                codex_accent,
                track,
                &codex_value_color,
'@ @'
                &codex_bar_color,
                track,
                &codex_value_color,
'@

# Softer track, stronger secondary text, less prominent drag handle.
$window = $window.Replace('Color::from_hex("#444444")', 'Color::from_hex("#363A3F")')
$window = $window.Replace('Color::from_hex("#888888")', 'Color::from_hex("#A0A0A0")')
$window = $window.Replace('let divider_h = sc(25);', 'let divider_h = sc(18);')

Set-Content -Path $appearancePath -Value $appearance -Encoding utf8NoBOM
Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM
Write-Host 'Applied compact taskbar visual implementation.'
