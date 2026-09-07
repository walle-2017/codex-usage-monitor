# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'
$path = 'src/window.rs'
$text = Get-Content -Raw -Path $path

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:text.Contains($old)) {
        throw "Required source fragment not found:`n$old"
    }
    $script:text = $script:text.Replace($old, $new)
}

if ($text.Contains('appearance_preset: AppearancePreset,')) {
    Write-Host 'Appearance settings implementation already present.'
    exit 0
}

Replace-Required 'use crate::diagnose;' "use crate::appearance::{self, AppearancePreset};`nuse crate::diagnose;"

Replace-Required @'
    install_channel: InstallChannel,

    session_percent: f64,
'@ @'
    install_channel: InstallChannel,
    appearance_preset: AppearancePreset,

    session_percent: f64,
'@

Replace-Required @'
const IDM_ALERT_30: u16 = 83;
'@ @'
const IDM_ALERT_30: u16 = 83;
const IDM_APPEARANCE_DEFAULT: u16 = 90;
const IDM_APPEARANCE_COMPACT: u16 = 91;
const IDM_APPEARANCE_MINIMAL: u16 = 92;
'@

Replace-Required @'
    #[serde(default = "default_widget_visible")]
    widget_visible: bool,
'@ @'
    #[serde(default = "default_widget_visible")]
    widget_visible: bool,
    #[serde(default)]
    appearance_preset: AppearancePreset,
'@

Replace-Required @'
            widget_visible: true,
            show_claude_code: false,
'@ @'
            widget_visible: true,
            appearance_preset: AppearancePreset::Compact,
            show_claude_code: false,
'@

Replace-Required @'
            widget_visible: s.widget_visible,
            show_claude_code: s.show_claude_code,
'@ @'
            widget_visible: s.widget_visible,
            appearance_preset: s.appearance_preset,
            show_claude_code: s.show_claude_code,
'@

Replace-Required @'
                install_channel,
                session_percent: 0.0,
'@ @'
                install_channel,
                appearance_preset: settings.appearance_preset,
                session_percent: 0.0,
'@

# Add appearance command handling before language commands.
Replace-Required @'
                IDM_LANG_SYSTEM
                | IDM_LANG_ENGLISH
'@ @'
                IDM_APPEARANCE_DEFAULT | IDM_APPEARANCE_COMPACT | IDM_APPEARANCE_MINIMAL => {
                    let preset = match id {
                        IDM_APPEARANCE_DEFAULT => AppearancePreset::Default,
                        IDM_APPEARANCE_MINIMAL => AppearancePreset::Minimal,
                        _ => AppearancePreset::Compact,
                    };
                    {
                        let mut state = lock_state();
                        if let Some(s) = state.as_mut() {
                            s.appearance_preset = preset;
                        }
                    }
                    save_state_settings();
                    position_at_taskbar();
                    render_layered();
                    sync_tray_icons(hwnd);
                }
                IDM_LANG_SYSTEM
                | IDM_LANG_ENGLISH
'@

# Extend context-menu state tuple.
Replace-Required @'
            show_weekly_window,
            alert_threshold_percent,
        ) = {
'@ @'
            show_weekly_window,
            alert_threshold_percent,
            appearance_preset,
        ) = {
'@

Replace-Required @'
                    s.show_weekly_window,
                    s.alert_threshold_percent,
                ),
'@ @'
                    s.show_weekly_window,
                    s.alert_threshold_percent,
                    s.appearance_preset,
                ),
'@

Replace-Required @'
                    true,
                    true,
                    0,
                ),
'@ @'
                    true,
                    true,
                    0,
                    AppearancePreset::Compact,
                ),
'@

# Insert Appearance submenu immediately before Settings submenu.
Replace-Required @'
        // Settings submenu
        let settings_menu = CreatePopupMenu().unwrap();
'@ @'
        // Appearance submenu
        let appearance_menu = CreatePopupMenu().unwrap();
        let appearance_items = [
            (IDM_APPEARANCE_DEFAULT, AppearancePreset::Default),
            (IDM_APPEARANCE_COMPACT, AppearancePreset::Compact),
            (IDM_APPEARANCE_MINIMAL, AppearancePreset::Minimal),
        ];
        for (id, preset) in appearance_items {
            let label = native_interop::wide_str(preset.menu_label(language));
            let flags = if preset == appearance_preset {
                MF_CHECKED
            } else {
                MENU_ITEM_FLAGS(0)
            };
            let _ = AppendMenuW(
                appearance_menu,
                flags,
                id as usize,
                PCWSTR::from_raw(label.as_ptr()),
            );
        }
        let appearance_label = native_interop::wide_str(
            if language == LanguageId::SimplifiedChinese { "外观" } else { "Appearance" }
        );
        let _ = AppendMenuW(
            menu,
            MF_POPUP,
            appearance_menu.0 as usize,
            PCWSTR::from_raw(appearance_label.as_ptr()),
        );

        // Settings submenu
        let settings_menu = CreatePopupMenu().unwrap();
'@

Set-Content -Path $path -Value $text -Encoding utf8NoBOM
Write-Host 'Applied appearance settings implementation.'
