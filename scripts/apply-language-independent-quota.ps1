$ErrorActionPreference = 'Stop'

$appearancePath = Join-Path $PSScriptRoot '..\src\appearance.rs'
$appearance = Get-Content -Raw $appearancePath
$oldAppearance = @'
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
'@
$newAppearance = @'
pub fn taskbar_value_text(
    preset: AppearancePreset,
    _language: LanguageId,
    section: &UsageSection,
    window: UsageWindowKind,
) -> TaskbarValueText {
    let percentage = poller::remaining_percentage(section.percentage);
'@
if (-not $appearance.Contains($oldAppearance)) { throw 'Expected taskbar_value_text language-dependent block not found.' }
$appearance = $appearance.Replace($oldAppearance, $newAppearance)

$testAnchor = @'
    #[test]
    fn taskbar_line_never_uses_reset_icon() {
'@
$newTest = @'
    #[test]
    fn remaining_quota_is_language_independent() {
        let section = section_with_local_reset(8.0, 1_789_000_000);
        for language in [
            LanguageId::SimplifiedChinese,
            LanguageId::English,
            LanguageId::Japanese,
        ] {
            let value = taskbar_value_text(
                AppearancePreset::Compact,
                language,
                &section,
                UsageWindowKind::Session,
            );
            assert_eq!(value.primary, "92%");
        }
    }

    #[test]
    fn taskbar_line_never_uses_reset_icon() {
'@
if (-not $appearance.Contains($testAnchor)) { throw 'Expected appearance test anchor not found.' }
$appearance = $appearance.Replace($testAnchor, $newTest)
Set-Content -Path $appearancePath -Value $appearance -Encoding utf8NoBOM -NoNewline

$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$window = Get-Content -Raw $windowPath
$oldDisplay = @'
fn usage_percent_for_display(language: LanguageId, used_percentage: f64) -> f64 {
    if language == LanguageId::SimplifiedChinese {
        poller::remaining_percentage(used_percentage)
    } else {
        used_percentage.clamp(0.0, 100.0)
    }
}
'@
$newDisplay = @'
fn usage_percent_for_display(_language: LanguageId, used_percentage: f64) -> f64 {
    poller::remaining_percentage(used_percentage)
}
'@
if (-not $window.Contains($oldDisplay)) { throw 'Expected language-dependent display percentage block not found.' }
$window = $window.Replace($oldDisplay, $newDisplay)

$oldColor = @'
fn quota_bar_color(_is_dark: bool, displayed_percent: f64, language: LanguageId) -> Color {
    let remaining = if language == LanguageId::SimplifiedChinese {
        displayed_percent.clamp(0.0, 100.0)
    } else {
        100.0 - displayed_percent.clamp(0.0, 100.0)
    };
'@
$newColor = @'
fn quota_bar_color(_is_dark: bool, displayed_percent: f64, _language: LanguageId) -> Color {
    let remaining = displayed_percent.clamp(0.0, 100.0);
'@
if (-not $window.Contains($oldColor)) { throw 'Expected language-dependent quota color block not found.' }
$window = $window.Replace($oldColor, $newColor)
Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline

git diff --check
