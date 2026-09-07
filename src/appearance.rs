#[cfg(test)]
mod tests {
    use super::*;
    use crate::localization::LanguageId;
    use crate::models::UsageSection;
    use crate::poller::UsageWindowKind;
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
        assert!(minimal.text_width < compact.text_width);
        assert!(minimal.hide_reset_time);
        assert!(!compact.hide_reset_time);
    }

    #[test]
    fn taskbar_text_separates_percentage_from_reset_hint() {
        // 2026-09-07 13:40 local conversion is platform/timezone dependent, so
        // validate the stable primary/visibility contract here; exact local
        // formatting is already covered by existing poller tests.
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
    fn quota_tone_tracks_remaining_quota() {
        assert_eq!(quota_tone(81.0), QuotaTone::Critical);
        assert_eq!(quota_tone(80.0), QuotaTone::Warning);
        assert_eq!(quota_tone(50.0), QuotaTone::Warning);
        assert_eq!(quota_tone(49.0), QuotaTone::Normal);
    }
}
