use serde::{Deserialize, Serialize};

use crate::localization::LanguageId;
use crate::models::UsageSection;
use crate::native_interop;
use crate::poller::{self, UsageWindowKind};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AppearancePreset {
    Default,
    #[default]
    Compact,
    Minimal,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StyleMetrics {
    pub widget_height: i32,
    pub bar_width: i32,
    pub bar_height: i32,
    pub label_width: i32,
    pub label_right_margin: i32,
    pub bar_right_margin: i32,
    pub text_width: i32,
    pub secondary_width: i32,
    pub row_gap: i32,
    pub font_height: i32,
    pub value_font_height: i32,
    pub secondary_font_height: i32,
    pub divider_right_margin: i32,
    pub model_right_margin: i32,
    pub hide_reset_time: bool,
}

impl AppearancePreset {

    pub fn metrics(self) -> StyleMetrics {
        match self {
            Self::Default => StyleMetrics {
                widget_height: 46,
                bar_width: 108,
                bar_height: 10,
                label_width: 20,
                label_right_margin: 8,
                bar_right_margin: 7,
                text_width: 34,
                secondary_width: 52,
                row_gap: 9,
                font_height: -12,
                value_font_height: -13,
                secondary_font_height: -11,
                divider_right_margin: 9,
                model_right_margin: 5,
                hide_reset_time: false,
            },
            Self::Compact => StyleMetrics {
                widget_height: 42,
                bar_width: 82,
                bar_height: 8,
                label_width: 18,
                label_right_margin: 6,
                bar_right_margin: 6,
                text_width: 31,
                secondary_width: 43,
                row_gap: 7,
                font_height: -11,
                value_font_height: -12,
                secondary_font_height: -10,
                divider_right_margin: 7,
                model_right_margin: 4,
                hide_reset_time: false,
            },
            Self::Minimal => StyleMetrics {
                widget_height: 40,
                bar_width: 62,
                bar_height: 7,
                label_width: 18,
                label_right_margin: 5,
                bar_right_margin: 5,
                text_width: 31,
                secondary_width: 0,
                row_gap: 7,
                font_height: -11,
                value_font_height: -12,
                secondary_font_height: -10,
                divider_right_margin: 6,
                model_right_margin: 3,
                hide_reset_time: true,
            },
        }
    }

    pub fn menu_label(self, language: LanguageId) -> &'static str {
        match (self, language == LanguageId::SimplifiedChinese) {
            (Self::Default, true) => "默认",
            (Self::Compact, true) => "紧凑",
            (Self::Minimal, true) => "极简",
            (Self::Default, false) => "Default",
            (Self::Compact, false) => "Compact",
            (Self::Minimal, false) => "Minimal",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskbarValueText {
    pub primary: String,
    pub secondary: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum QuotaTone {
    Normal,
    Warning,
    Critical,
}

/// Determine the visual tone from *used* percentage. Thresholds are based on
/// remaining quota: >50% normal, 20..=50% warning, <20% critical.
pub fn quota_tone(used_percentage: f64) -> QuotaTone {
    let remaining = poller::remaining_percentage(used_percentage);
    if remaining < 20.0 {
        QuotaTone::Critical
    } else if remaining <= 50.0 {
        QuotaTone::Warning
    } else {
        QuotaTone::Normal
    }
}

pub fn taskbar_value_text(
    preset: AppearancePreset,
    language: LanguageId,
    section: &UsageSection,
    window: UsageWindowKind,
) -> TaskbarValueText {
    let percentage = if language == LanguageId::SimplifiedChinese {
        poller::remaining_percentage(section.percentage)
    } else {
        section.percentage.clamp(0.0, 100.0)
    };

    let primary = format!("{percentage:.0}%");
    let secondary = if preset.metrics().hide_reset_time {
        None
    } else {
        section
            .resets_at
            .and_then(native_interop::system_time_to_local)
            .map(|reset| match window {
                UsageWindowKind::Session => format!("{:02}:{:02}", reset.wHour, reset.wMinute),
                UsageWindowKind::Weekly => format!("{:02}/{:02}", reset.wMonth, reset.wDay),
            })
    };

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
mod tests {
    use super::*;
    use std::time::{Duration, UNIX_EPOCH};

    fn section_with_local_reset(used: f64, unix_seconds: u64) -> UsageSection {
        UsageSection {
            percentage: used,
            resets_at: Some(UNIX_EPOCH + Duration::from_secs(unix_seconds)),
        }
    }

    #[test]
    fn compact_is_the_default_preset() {
        assert_eq!(AppearancePreset::default(), AppearancePreset::Compact);
    }

    #[test]
    fn minimal_has_the_smallest_layout() {
        let default = AppearancePreset::Default.metrics();
        let compact = AppearancePreset::Compact.metrics();
        let minimal = AppearancePreset::Minimal.metrics();

        assert!(compact.bar_width < default.bar_width);
        assert!(minimal.bar_width < compact.bar_width);
        assert!(compact.text_width < default.text_width);
        assert!(minimal.text_width <= compact.text_width);
        assert!(minimal.hide_reset_time);
        assert!(!compact.hide_reset_time);
    }

    #[test]
    fn taskbar_text_separates_percentage_from_reset_hint() {
        let section = section_with_local_reset(81.0, 1_789_000_000);
        let compact = taskbar_value_text(
            AppearancePreset::Compact,
            LanguageId::SimplifiedChinese,
            &section,
            UsageWindowKind::Session,
        );
        assert_eq!(compact.primary, "19%");
        assert!(compact.secondary.is_some());

        let minimal = taskbar_value_text(
            AppearancePreset::Minimal,
            LanguageId::SimplifiedChinese,
            &section,
            UsageWindowKind::Session,
        );
        assert_eq!(minimal.primary, "19%");
        assert_eq!(minimal.secondary, None);
    }

    #[test]
    fn taskbar_line_matches_each_preset_density() {
        let section = section_with_local_reset(81.0, 1_789_000_000);
        let default = taskbar_line(
            AppearancePreset::Default,
            LanguageId::SimplifiedChinese,
            &section,
            UsageWindowKind::Session,
        );
        let compact = taskbar_line(
            AppearancePreset::Compact,
            LanguageId::SimplifiedChinese,
            &section,
            UsageWindowKind::Session,
        );
        let minimal = taskbar_line(
            AppearancePreset::Minimal,
            LanguageId::SimplifiedChinese,
            &section,
            UsageWindowKind::Session,
        );

        assert!(default.starts_with("19%  ↻"));
        assert!(compact.starts_with("19%  "));
        assert!(!compact.contains('↻'));
        assert_eq!(minimal, "19%");
        assert!(minimal.len() < compact.len());
        assert!(compact.len() < default.len());
    }

    #[test]
    fn quota_tone_tracks_remaining_quota() {
        assert_eq!(quota_tone(81.0), QuotaTone::Critical);
        assert_eq!(quota_tone(80.0), QuotaTone::Warning);
        assert_eq!(quota_tone(50.0), QuotaTone::Warning);
        assert_eq!(quota_tone(49.0), QuotaTone::Normal);
    }
}


