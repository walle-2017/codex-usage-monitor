# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'

$path = 'src/window.rs'
$text = Get-Content -Raw -Path $path
$marker = 'fn legacy_settings_default_to_compact_appearance()'
if ($text.Contains($marker)) {
    Write-Host 'Appearance settings tests already present.'
    exit 0
}

$needle = @'
    #[test]
    fn loads_legacy_settings_when_new_path_is_missing() {
'@

$insert = @'
    #[test]
    fn legacy_settings_default_to_compact_appearance() {
        let settings: SettingsFile = serde_json::from_str(r#"{"show_codex":true}"#).unwrap();
        assert_eq!(
            settings.appearance_preset,
            crate::appearance::AppearancePreset::Compact
        );
    }

    #[test]
    fn explicit_minimal_appearance_round_trips() {
        let mut settings = SettingsFile::default();
        settings.appearance_preset = crate::appearance::AppearancePreset::Minimal;
        let json = serde_json::to_string(&settings).unwrap();
        let parsed: SettingsFile = serde_json::from_str(&json).unwrap();
        assert_eq!(
            parsed.appearance_preset,
            crate::appearance::AppearancePreset::Minimal
        );
    }

    #[test]
    fn loads_legacy_settings_when_new_path_is_missing() {
'@

if (-not $text.Contains($needle)) {
    throw 'Unable to locate settings test insertion point.'
}
$text = $text.Replace($needle, $insert)
Set-Content -Path $path -Value $text -Encoding utf8NoBOM
Write-Host 'Inserted appearance settings tests.'
