from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 replacement, got {count}")
    return updated


def remove_fn_until(text: str, name: str, next_marker: str) -> str:
    pattern = rf"(?ms)^fn\s+{re.escape(name)}\s*\(.*?(?=^{re.escape(next_marker)})"
    updated, count = re.subn(pattern, "", text, count=1)
    if count != 1:
        raise RuntimeError(f"remove {name}: expected 1 replacement, got {count}")
    return updated

# --- Small source files -----------------------------------------------------
main_path = ROOT / "src" / "main.rs"
main = main_path.read_text(encoding="utf-8").replace("mod updater;\n", "")
main_path.write_text(main, encoding="utf-8")

models_path = ROOT / "src" / "models.rs"
models_path.write_text('''use std::time::SystemTime;\n\n#[derive(Clone, Debug, Default)]\npub struct UsageSection {\n    pub percentage: f64,\n    pub resets_at: Option<SystemTime>,\n}\n\n#[derive(Clone, Debug, Default)]\npub struct UsageData {\n    pub session: UsageSection,\n    pub weekly: UsageSection,\n}\n\n#[derive(Clone, Debug, Default)]\npub struct AppUsageData {\n    pub codex: Option<UsageData>,\n}\n''', encoding="utf-8")

poller_path = ROOT / "src" / "poller.rs"
poller = poller_path.read_text(encoding="utf-8")
poller = poller.replace('''    Ok(AppUsageData {\n        codex: Some(codex),\n        ..Default::default()\n    })''', '''    Ok(AppUsageData { codex: Some(codex) })''')
poller_path.write_text(poller, encoding="utf-8")

native_path = ROOT / "src" / "native_interop.rs"
native = native_path.read_text(encoding="utf-8")
native = native.replace("pub const TIMER_UPDATE_CHECK: usize = 4;\n", "")
native_path.write_text(native, encoding="utf-8")

tray_path = ROOT / "src" / "tray_icon.rs"
tray_path.write_text(r'''use windows::core::PCWSTR;
use windows::Win32::Foundation::*;
use windows::Win32::System::LibraryLoader::GetModuleFileNameW;
use windows::Win32::UI::Shell::{
    ExtractIconExW, Shell_NotifyIconW, NIF_ICON, NIF_INFO, NIF_MESSAGE, NIF_TIP, NIIF_WARNING,
    NIM_ADD, NIM_DELETE, NIM_MODIFY, NOTIFYICONDATAW,
};
use windows::Win32::UI::WindowsAndMessaging::*;

use crate::native_interop::WM_APP_TRAY;

const APP_TRAY_ICON_ID: u32 = 1;
const LEGACY_PROVIDER_TRAY_ICON_IDS: [u32; 2] = [2, 3];

pub enum TrayAction {
    None,
    ShowContextMenu,
}

#[derive(Clone, Copy)]
pub enum TrayIconKind {
    Codex,
}

pub struct TrayIconData {
    pub tooltip: String,
}

pub fn create_icon() -> HICON {
    load_embedded_app_icon()
}

fn load_embedded_app_icon() -> HICON {
    unsafe {
        let mut exe_buf = [0u16; 260];
        let len = GetModuleFileNameW(None, &mut exe_buf) as usize;
        if len == 0 {
            return HICON::default();
        }

        let mut small_icon = HICON::default();
        let mut large_icon = HICON::default();
        let extracted = ExtractIconExW(
            PCWSTR::from_raw(exe_buf.as_ptr()),
            0,
            Some(&mut large_icon),
            Some(&mut small_icon),
            1,
        );

        if extracted == 0 {
            return HICON::default();
        }

        if !small_icon.is_invalid() {
            if !large_icon.is_invalid() {
                let _ = DestroyIcon(large_icon);
            }
            small_icon
        } else {
            large_icon
        }
    }
}

pub fn notify_balloon(hwnd: HWND, _kind: TrayIconKind, title: &str, message: &str) {
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = APP_TRAY_ICON_ID;
        nid.uFlags = NIF_INFO;
        nid.dwInfoFlags = NIIF_WARNING;
        copy_wide(title, &mut nid.szInfoTitle);
        copy_wide(message, &mut nid.szInfo);
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}

fn copy_wide<const N: usize>(s: &str, buf: &mut [u16; N]) {
    let wide: Vec<u16> = s.encode_utf16().collect();
    let mut len = wide.len().min(N - 1);
    if len > 0 && (0xD800..=0xDBFF).contains(&wide[len - 1]) {
        len -= 1;
    }
    buf[..len].copy_from_slice(&wide[..len]);
    buf[len] = 0;
}

fn add(hwnd: HWND, tooltip: &str) {
    let hicon = create_icon();
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = APP_TRAY_ICON_ID;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_APP_TRAY;
        nid.hIcon = hicon;
        copy_wide(tooltip, &mut nid.szTip);
        let _ = Shell_NotifyIconW(NIM_ADD, &nid);
        if !hicon.is_invalid() {
            let _ = DestroyIcon(hicon);
        }
    }
}

fn update(hwnd: HWND, tooltip: &str) {
    let hicon = create_icon();
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = APP_TRAY_ICON_ID;
        nid.uFlags = NIF_ICON | NIF_TIP;
        nid.hIcon = hicon;
        copy_wide(tooltip, &mut nid.szTip);
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
        if !hicon.is_invalid() {
            let _ = DestroyIcon(hicon);
        }
    }
}

fn remove_id(hwnd: HWND, id: u32) {
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = id;
        let _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}

pub fn sync(hwnd: HWND, icon: Option<&TrayIconData>) {
    for id in LEGACY_PROVIDER_TRAY_ICON_IDS {
        remove_id(hwnd, id);
    }
    if let Some(icon) = icon {
        add(hwnd, &icon.tooltip);
        update(hwnd, &icon.tooltip);
    } else {
        remove_id(hwnd, APP_TRAY_ICON_ID);
    }
}

pub fn remove_all(hwnd: HWND) {
    remove_id(hwnd, APP_TRAY_ICON_ID);
    for id in LEGACY_PROVIDER_TRAY_ICON_IDS {
        remove_id(hwnd, id);
    }
}

pub fn handle_message(lparam: LPARAM) -> TrayAction {
    match lparam.0 as u32 {
        WM_RBUTTONUP => TrayAction::ShowContextMenu,
        _ => TrayAction::None,
    }
}
''', encoding="utf-8")

# --- Localization: retain only fields used by the Codex-only UI ------------
allowed_fields = [
    "window_title", "refresh", "update_frequency", "one_minute", "five_minutes",
    "fifteen_minutes", "one_hour", "codex_model", "settings", "start_with_windows",
    "reset_position", "language", "system_default", "exit", "session_window",
    "weekly_window", "now", "day_suffix", "hour_suffix", "minute_suffix",
    "second_suffix", "codex_token_expired_title", "codex_token_expired_body",
]
allowed_set = set(allowed_fields)
loc_dir = ROOT / "src" / "localization"
for path in loc_dir.glob("*.rs"):
    if path.name == "mod.rs":
        continue
    text = path.read_text(encoding="utf-8")
    match = re.search(r"pub\(super\) const STRINGS: Strings = Strings \{(?P<body>.*?)\n\};", text, re.S)
    if not match:
        raise RuntimeError(f"unable to find STRINGS in {path}")
    values = {}
    for line in match.group("body").splitlines():
        field = re.match(r"\s*([A-Za-z0-9_]+):\s*(.*),\s*$", line)
        if field:
            values[field.group(1)] = field.group(2)
    missing = [field for field in allowed_fields if field not in values]
    if missing:
        raise RuntimeError(f"{path}: missing fields {missing}")
    body = "\n".join(f"    {field}: {values[field]}," for field in allowed_fields)
    text = re.sub(r"\npub\(super\) const UPDATE_VIA_WINGET_LABEL:.*?\n", "\n", text, count=1)
    text = re.sub(r"pub\(super\) const STRINGS: Strings = Strings \{.*?\n\};", f"pub(super) const STRINGS: Strings = Strings {{\n{body}\n}};", text, count=1, flags=re.S)
    path.write_text(text, encoding="utf-8")

loc_mod_path = loc_dir / "mod.rs"
loc_mod = loc_mod_path.read_text(encoding="utf-8")
loc_mod = replace_once(
    loc_mod,
    r"\n\s*pub fn update_via_winget_label\(self\).*?\n\s*}\n(?=\n\s*pub fn from_code)",
    "\n",
    "remove LanguageId::update_via_winget_label",
)
loc_mod = replace_once(
    loc_mod,
    r"#\[derive\(Clone, Copy, Debug\)\]\npub struct Strings \{.*?\n}\n",
    "#[derive(Clone, Copy, Debug)]\npub struct Strings {\n" + "".join(f"    pub {field}: &'static str,\n" for field in allowed_fields) + "}\n",
    "rewrite Strings",
)
loc_mod = re.sub(r"\npub fn update_via_winget\(language: LanguageId\).*?\n}\n", "\n", loc_mod, count=1, flags=re.S)
loc_mod_path.write_text(loc_mod, encoding="utf-8")

# --- Cargo / installer ------------------------------------------------------
cargo_path = ROOT / "Cargo.toml"
cargo = cargo_path.read_text(encoding="utf-8")
cargo = cargo.replace("https://github.com/upstream-ray/codex-usage-monitor", "https://github.com/walle-2017/codex-usage-monitor")
cargo = re.sub(r"(?m)^sha2\s*=.*\n", "", cargo)
cargo = cargo.replace('    "Win32_Security",\n', '')
cargo_path.write_text(cargo, encoding="utf-8")

installer_path = ROOT / "scripts" / "install.ps1"
installer = installer_path.read_text(encoding="utf-8").replace("$Repository = 'upstream-ray/codex-usage-monitor'", "$Repository = 'walle-2017/codex-usage-monitor'")
installer_path.write_text(installer, encoding="utf-8")

# --- window.rs --------------------------------------------------------------
window_path = ROOT / "src" / "window.rs"
w = window_path.read_text(encoding="utf-8")
w = w.replace("self, Color, TIMER_COUNTDOWN, TIMER_POLL, TIMER_RESET_POLL, TIMER_UPDATE_CHECK, WM_APP_TRAY,\n    WM_APP_USAGE_UPDATED,", "self, Color, TIMER_COUNTDOWN, TIMER_POLL, TIMER_RESET_POLL, WM_APP_TRAY, WM_APP_USAGE_UPDATED,")
w = re.sub(r"(?m)^use crate::updater::.*\n", "", w)
w = w.replace("const WM_APP_UPDATE_CHECK_COMPLETE: u32 = WM_APP + 2;\n", "")

app_state = '''struct AppState {
    hwnd: SendHwnd,
    taskbar_hwnd: Option<HWND>,
    tray_notify_hwnd: Option<HWND>,
    win_event_hook: Option<HWINEVENTHOOK>,
    is_dark: bool,
    embedded: bool,
    language_override: Option<LanguageId>,
    language: LanguageId,
    appearance_preset: AppearancePreset,
    small_taskbar_mode: bool,
    small_show_weekly: bool,

    codex_session_percent: f64,
    codex_session_text: String,
    codex_weekly_percent: f64,
    codex_weekly_text: String,
    show_session_window: bool,
    show_weekly_window: bool,
    alert_threshold_percent: u8,
    notified_quota_windows: BTreeSet<String>,
    data: Option<AppUsageData>,

    poll_interval_ms: u32,
    retry_count: u32,
    force_notify_auth_error: bool,
    auth_error_paused_polling: bool,
    auth_watch_mode: poller::CredentialWatchMode,
    auth_watch_snapshot: poller::CredentialWatchSnapshot,
    last_poll_ok: bool,

    taskbar_index: usize,
    tray_offset: i32,
    dragging: bool,
    drag_start_mouse_x: i32,
    drag_start_client_x: i32,
    drag_start_offset: i32,
}'''
w = replace_once(w, r"struct AppState \{.*?\n}\n\n#\[derive\(Clone, Debug\)\]\nenum UpdateStatus \{.*?\n}\n", app_state + "\n", "AppState/update state")

settings_block = '''#[derive(Debug, Serialize, Deserialize)]
struct SettingsFile {
    #[serde(default)]
    tray_offset: i32,
    #[serde(default)]
    taskbar_index: usize,
    #[serde(default = "default_poll_interval")]
    poll_interval_ms: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    language: Option<String>,
    #[serde(default)]
    appearance_preset: AppearancePreset,
    #[serde(default = "default_show_usage_window")]
    show_session_window: bool,
    #[serde(default = "default_show_usage_window")]
    show_weekly_window: bool,
    #[serde(default)]
    alert_threshold_percent: u8,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    notified_quota_windows: Vec<String>,
}

impl Default for SettingsFile {
    fn default() -> Self {
        Self {
            tray_offset: 0,
            taskbar_index: 0,
            poll_interval_ms: default_poll_interval(),
            language: None,
            appearance_preset: AppearancePreset::Compact,
            show_session_window: true,
            show_weekly_window: true,
            alert_threshold_percent: 0,
            notified_quota_windows: Vec::new(),
        }
    }
}

fn default_poll_interval() -> u32 {
    POLL_15_MIN
}

fn default_show_usage_window() -> bool {
    true
}

fn load_settings() -> SettingsFile {
    let current_path = settings_path();
    let legacy_path = legacy_settings_path();
    let (settings, migrated) = load_settings_from_paths(&current_path, &legacy_path)
        .unwrap_or_else(|| (SettingsFile::default(), false));
    let settings = normalize_settings(settings);
    if migrated {
        save_settings(&settings);
        diagnose::log(format!(
            "migrated settings from {} to {}",
            legacy_path.display(),
            current_path.display()
        ));
    }
    settings
}

fn load_settings_from_paths(
    current_path: &std::path::Path,
    legacy_path: &std::path::Path,
) -> Option<(SettingsFile, bool)> {
    if let Ok(content) = std::fs::read_to_string(current_path) {
        return serde_json::from_str(&content)
            .ok()
            .map(|settings| (settings, false));
    }

    let content = std::fs::read_to_string(legacy_path).ok()?;
    serde_json::from_str(&content)
        .ok()
        .map(|settings| (settings, true))
}

fn normalize_settings(mut settings: SettingsFile) -> SettingsFile {
    if !settings.show_session_window && !settings.show_weekly_window {
        settings.show_session_window = true;
    }
    if !matches!(settings.alert_threshold_percent, 0 | 10 | 20 | 30) {
        settings.alert_threshold_percent = 0;
    }
    settings.notified_quota_windows.sort();
    settings.notified_quota_windows.dedup();
    settings
}

fn save_settings(settings: &SettingsFile) {
    let path = settings_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_string_pretty(settings) {
        let _ = std::fs::write(path, json);
    }
}

fn save_state_settings() {
    let state = lock_state();
    if let Some(s) = state.as_ref() {
        save_settings(&SettingsFile {
            tray_offset: s.tray_offset,
            taskbar_index: s.taskbar_index,
            poll_interval_ms: s.poll_interval_ms,
            language: s.language_override.map(|language| language.code().to_string()),
            appearance_preset: s.appearance_preset,
            show_session_window: s.show_session_window,
            show_weekly_window: s.show_weekly_window,
            alert_threshold_percent: s.alert_threshold_percent,
            notified_quota_windows: s.notified_quota_windows.iter().cloned().collect(),
        });
    }
}

'''
w = replace_once(w, r"#\[derive\(Debug, Serialize, Deserialize\)\]\nstruct SettingsFile \{.*?(?=fn format_precise_reset_time)", settings_block, "settings block")

collect_alerts = '''fn collect_low_quota_alerts(state: &mut AppState, data: &AppUsageData) -> Vec<QuotaAlert> {
    let threshold = state.alert_threshold_percent;
    if threshold == 0 {
        return Vec::new();
    }

    let mut alerts = Vec::new();
    if let Some(usage) = data.codex.as_ref() {
        let strings = state.language.strings();
        append_provider_alerts(
            &mut alerts,
            &mut state.notified_quota_windows,
            threshold,
            state.language,
            tray_icon::TrayIconKind::Codex,
            "codex",
            strings.codex_model,
            usage,
            strings,
        );
    }
    alerts
}

'''
w = replace_once(w, r"fn collect_low_quota_alerts\(.*?(?=#\[allow\(clippy::too_many_arguments\)\]\nfn append_provider_alerts)", collect_alerts, "collect alerts")
w = replace_once(w, r"fn claude_code_menu_label\(.*?(?=struct QuotaAlert)", "", "remove legacy menu label")

tray_data = '''fn tray_icon_data_from_state() -> Option<tray_icon::TrayIconData> {
    let state = lock_state();
    let s = state.as_ref()?;
    if !s.last_poll_ok {
        return Some(tray_icon::TrayIconData {
            tooltip: s.language.strings().window_title.to_string(),
        });
    }

    let strings = s.language.strings();
    let usage = s.data.as_ref()?.codex.as_ref()?;
    let session = full_usage_line(
        &usage.session,
        s.language,
        strings,
        poller::UsageWindowKind::Session,
    );
    let weekly = full_usage_line(
        &usage.weekly,
        s.language,
        strings,
        poller::UsageWindowKind::Weekly,
    );
    Some(tray_icon::TrayIconData {
        tooltip: service_tooltip(
            strings.codex_model,
            &session,
            &weekly,
            s.show_session_window,
            s.show_weekly_window,
        ),
    })
}

'''
w = replace_once(w, r"fn tray_icon_data_from_state\(\).*?(?=fn sync_tray_icons)", tray_data, "tray data")

w = remove_fn_until(w, "update_check_interval", "fn auto_update_check_due")
w = remove_fn_until(w, "auto_update_check_due", "fn schedule_auto_update_check")
w = remove_fn_until(w, "schedule_auto_update_check", "fn refresh_usage_texts")
refresh_usage = '''fn refresh_usage_texts(state: &mut AppState) {
    if !state.last_poll_ok {
        return;
    }
    let Some(codex) = state.data.as_ref().and_then(|data| data.codex.as_ref()) else {
        return;
    };
    state.codex_session_text = appearance::taskbar_line(
        state.appearance_preset,
        state.language,
        &codex.session,
        poller::UsageWindowKind::Session,
    );
    state.codex_weekly_text = appearance::taskbar_line(
        state.appearance_preset,
        state.language,
        &codex.weekly,
        poller::UsageWindowKind::Weekly,
    );
}

'''
w = replace_once(w, r"fn refresh_usage_texts\(.*?(?=fn set_window_title)", refresh_usage, "refresh usage")
w = remove_fn_until(w, "show_info_message", "fn show_error_message")
w = remove_fn_until(w, "show_error_message", "fn show_update_prompt")
w = remove_fn_until(w, "show_update_prompt", "fn apply_language_to_state")
w = remove_fn_until(w, "version_action_label", "fn begin_update_check")
w = remove_fn_until(w, "begin_update_check", "fn begin_update_apply")
w = remove_fn_until(w, "begin_update_apply", "fn begin_winget_update")
w = replace_once(w, r"fn begin_winget_update\(.*?(?=const STARTUP_REGISTRY_PATH)", "", "remove winget update")

w = replace_once(w, r"fn active_model_count\(.*?(?=fn is_small_taskbar_height_at_dpi)", "", "remove active model count")
w = replace_once(w, r"fn row_bar_segment_count\(.*?(?=fn usage_layout_widths)", '''fn row_bar_segment_count(preset: AppearancePreset) -> i32 {
    match preset {
        AppearancePreset::Compact => 8,
        AppearancePreset::Minimal => 6,
    }
}

''', "segment count")
w = replace_once(w, r"fn total_widget_width_for_preset\(.*?(?=fn quota_bar_color)", '''fn total_widget_width_for_preset(language: LanguageId, preset: AppearancePreset) -> i32 {
    let bar_segments = row_bar_segment_count(preset);
    let (label_width, reset_width) = usage_layout_widths(language, preset);
    let metrics = preset.metrics();
    let progress_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP);
    let usage_width = progress_width
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
        + usage_width
        + sc(metrics.outer_padding)
}

fn total_widget_width_for(language: LanguageId) -> i32 {
    total_widget_width_for_preset(language, AppearancePreset::Compact)
}

fn total_widget_width_for_state(state: &AppState) -> i32 {
    total_widget_width_for_preset(state.language, state.appearance_preset)
}

fn total_widget_width() -> i32 {
    let (language, preset) = {
        let state = lock_state();
        state
            .as_ref()
            .map(|s| (s.language, s.appearance_preset))
            .unwrap_or((LanguageId::English, AppearancePreset::Compact))
    };
    total_widget_width_for_preset(language, preset)
}

''', "single-provider layout")

# Run initialization: keep runtime behavior, only remove dead provider/updater state.
w = w.replace('''        let claude_code_available = false;
        let settings = load_settings(claude_code_available);
        let language_override = settings.language.as_deref().and_then(LanguageId::from_code);
        let language = localization::resolve_language(language_override);
        let install_channel = updater::current_install_channel();

        // Create as layered popup (will be reparented into taskbar)
        let title = native_interop::wide_str(language.strings().window_title);
        let initial_model_count = active_model_count(
            settings.show_claude_code,
            settings.show_codex,
            settings.show_antigravity,
        );''', '''        let settings = load_settings();
        let language_override = settings.language.as_deref().and_then(LanguageId::from_code);
        let language = localization::resolve_language(language_override);

        // Create as layered popup (will be reparented into taskbar)
        let title = native_interop::wide_str(language.strings().window_title);''')
w = w.replace("total_widget_width_for(initial_model_count, language)", "total_widget_width_for(language)")
w = replace_once(w, r"\*state = Some\(AppState \{.*?\n            \}\);", '''*state = Some(AppState {
                hwnd: SendHwnd::from_hwnd(hwnd),
                taskbar_hwnd: None,
                tray_notify_hwnd: None,
                win_event_hook: None,
                is_dark,
                embedded: false,
                language_override,
                language,
                appearance_preset: settings.appearance_preset,
                small_taskbar_mode: false,
                small_show_weekly: false,
                codex_session_percent: 0.0,
                codex_session_text: "--".to_string(),
                codex_weekly_percent: 0.0,
                codex_weekly_text: "--".to_string(),
                show_session_window: settings.show_session_window,
                show_weekly_window: settings.show_weekly_window,
                alert_threshold_percent: settings.alert_threshold_percent,
                notified_quota_windows: settings.notified_quota_windows.into_iter().collect(),
                data: None,
                poll_interval_ms: settings.poll_interval_ms,
                retry_count: 0,
                force_notify_auth_error: false,
                auth_error_paused_polling: false,
                auth_watch_mode: poller::CredentialWatchMode::ActiveSource,
                auth_watch_snapshot: Vec::new(),
                last_poll_ok: false,
                taskbar_index: settings.taskbar_index,
                tray_offset: settings.tray_offset,
                dragging: false,
                drag_start_mouse_x: 0,
                drag_start_client_x: 0,
                drag_start_offset: 0,
            });''', "AppState init")

render_layered = r'''fn render_layered() {
    refresh_dpi();
    let (
        hwnd_val,
        is_dark,
        embedded,
        language,
        strings,
        codex_session_pct,
        codex_session_text,
        codex_weekly_pct,
        codex_weekly_text,
        show_session_window,
        show_weekly_window,
    ) = {
        let state = lock_state();
        match state.as_ref() {
            Some(s) => (
                s.hwnd,
                s.is_dark,
                s.embedded,
                s.language,
                s.language.strings(),
                s.codex_session_percent,
                s.codex_session_text.clone(),
                s.codex_weekly_percent,
                s.codex_weekly_text.clone(),
                s.show_session_window,
                s.show_weekly_window,
            ),
            None => return,
        }
    };

    let hwnd = hwnd_val.to_hwnd();
    if !embedded {
        unsafe {
            let _ = InvalidateRect(hwnd, None, false);
        }
        return;
    }

    let width = total_widget_width();
    let height = {
        let state = lock_state();
        state
            .as_ref()
            .map(widget_height_for_state)
            .unwrap_or(sc(AppearancePreset::Compact.metrics().widget_height))
    };
    let track = if is_dark {
        Color::from_hex("#363A3F")
    } else {
        Color::from_hex("#AAAAAA")
    };
    let text_color = if is_dark {
        Color::from_hex("#A0A0A0")
    } else {
        Color::from_hex("#404040")
    };
    let bg_color = if is_dark {
        Color::from_hex("#1C1C1C")
    } else {
        Color::from_hex("#F3F3F3")
    };

    unsafe {
        let screen_dc = GetDC(hwnd);
        let bmi = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: width,
                biHeight: -height,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: 0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut bits: *mut std::ffi::c_void = std::ptr::null_mut();
        let mem_dc = CreateCompatibleDC(screen_dc);
        let dib = CreateDIBSection(mem_dc, &bmi, DIB_RGB_COLORS, &mut bits, None, 0)
            .unwrap_or_default();
        if dib.is_invalid() || bits.is_null() {
            let _ = DeleteDC(mem_dc);
            ReleaseDC(hwnd, screen_dc);
            return;
        }

        let old_bmp = SelectObject(mem_dc, dib);
        let pixel_count = (width * height) as usize;
        paint_content(
            mem_dc,
            width,
            height,
            is_dark,
            &bg_color,
            &text_color,
            &track,
            language,
            strings,
            codex_session_pct,
            &codex_session_text,
            codex_weekly_pct,
            &codex_weekly_text,
            show_session_window,
            show_weekly_window,
        );

        let bg_bgr = bg_color.to_colorref();
        let pixel_data = std::slice::from_raw_parts_mut(bits as *mut u32, pixel_count);
        for px in pixel_data.iter_mut() {
            let rgb = *px & 0x00FFFFFF;
            if rgb == bg_bgr {
                *px = 0x01000000;
            } else {
                *px = rgb | 0xFF000000;
            }
        }

        let pt_src = POINT { x: 0, y: 0 };
        let sz = SIZE { cx: width, cy: height };
        let blend = BLENDFUNCTION {
            BlendOp: 0,
            BlendFlags: 0,
            SourceConstantAlpha: 255,
            AlphaFormat: 1,
        };
        let _ = UpdateLayeredWindow(
            hwnd,
            screen_dc,
            None,
            Some(&sz),
            mem_dc,
            Some(&pt_src),
            COLORREF(0),
            Some(&blend),
            ULW_ALPHA,
        );
        SelectObject(mem_dc, old_bmp);
        let _ = DeleteObject(dib);
        let _ = DeleteDC(mem_dc);
        ReleaseDC(hwnd, screen_dc);
    }
}
'''
w = replace_once(w, r"fn render_layered\(\) \{.*?(?=/// Paint all widget content)", render_layered + "\n", "render layered")

paint_content = r'''fn paint_content(
    hdc: HDC,
    width: i32,
    height: i32,
    is_dark: bool,
    bg: &Color,
    text_color: &Color,
    track: &Color,
    language: LanguageId,
    strings: Strings,
    codex_session_pct: f64,
    codex_session_text: &str,
    codex_weekly_pct: f64,
    codex_weekly_text: &str,
    show_session_window: bool,
    show_weekly_window: bool,
) {
    unsafe {
        let codex_session_pct = usage_percent_for_display(language, codex_session_pct);
        let codex_weekly_pct = usage_percent_for_display(language, codex_weekly_pct);
        let preset = current_appearance_preset();
        let metrics = preset.metrics();
        let (label_width, text_width) = usage_layout_widths(language, preset);
        let (small_taskbar_mode, small_show_weekly) = {
            let state = lock_state();
            state
                .as_ref()
                .map(|s| (s.small_taskbar_mode, s.small_show_weekly))
                .unwrap_or((false, false))
        };
        let effective_show_session = if small_taskbar_mode {
            !small_show_weekly
        } else {
            show_session_window
        };
        let effective_show_weekly = if small_taskbar_mode {
            small_show_weekly
        } else {
            show_weekly_window
        };

        let client_rect = RECT {
            left: 0,
            top: 0,
            right: width,
            bottom: height,
        };
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
        let font = CreateFontW(
            sc(metrics.font_height),
            0,
            0,
            0,
            FW_MEDIUM.0 as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET.0 as u32,
            OUT_TT_PRECIS.0 as u32,
            CLIP_DEFAULT_PRECIS.0 as u32,
            CLEARTYPE_QUALITY.0 as u32,
            (DEFAULT_PITCH.0 | FF_DONTCARE.0) as u32,
            PCWSTR::from_raw(font_name.as_ptr()),
        );
        let old_font = SelectObject(hdc, font);

        if effective_show_session {
            draw_row(
                hdc,
                content_x,
                if effective_show_weekly { row1_y } else { single_row_y },
                is_dark,
                language,
                text_color,
                strings.session_window,
                codex_session_pct,
                codex_session_text,
                track,
                label_width,
                text_width,
            );
        }
        if effective_show_weekly {
            draw_row(
                hdc,
                content_x,
                if effective_show_session { row2_y } else { single_row_y },
                is_dark,
                language,
                text_color,
                strings.weekly_window,
                codex_weekly_pct,
                codex_weekly_text,
                track,
                label_width,
                text_width,
            );
        }

        SelectObject(hdc, old_font);
        let _ = DeleteObject(font);
    }
}
'''
w = replace_once(w, r"fn paint_content\(.*?(?=fn poll_error_display_label)", paint_content + "\n", "paint content")

# Refresh command no longer touches removed service text.
w = w.replace('''                            s.session_text = "...".to_string();
                            s.weekly_text = "...".to_string();
                            s.codex_session_text = "...".to_string();''', '''                            s.codex_session_text = "...".to_string();''')

# Context menu state contains only values still used below.
w = replace_once(w, r"        let \(\n            current_interval,.*?\n        };\n\n        let menu", '''        let (
            current_interval,
            strings,
            language,
            language_override,
            show_session_window,
            show_weekly_window,
            alert_threshold_percent,
            appearance_preset,
        ) = {
            let state = lock_state();
            match state.as_ref() {
                Some(s) => (
                    s.poll_interval_ms,
                    s.language.strings(),
                    s.language,
                    s.language_override,
                    s.show_session_window,
                    s.show_weekly_window,
                    s.alert_threshold_percent,
                    s.appearance_preset,
                ),
                None => (
                    POLL_15_MIN,
                    LanguageId::English.strings(),
                    LanguageId::English,
                    None,
                    true,
                    true,
                    0,
                    AppearancePreset::Compact,
                ),
            }
        };

        let menu''', "context menu state")

paint = r'''fn paint(hdc: HDC, hwnd: HWND) {
    let (
        is_dark,
        language,
        strings,
        codex_session_pct,
        codex_session_text,
        codex_weekly_pct,
        codex_weekly_text,
        show_session_window,
        show_weekly_window,
    ) = {
        let state = lock_state();
        match state.as_ref() {
            Some(s) => (
                s.is_dark,
                s.language,
                s.language.strings(),
                s.codex_session_percent,
                s.codex_session_text.clone(),
                s.codex_weekly_percent,
                s.codex_weekly_text.clone(),
                s.show_session_window,
                s.show_weekly_window,
            ),
            None => return,
        }
    };

    let track = if is_dark {
        Color::from_hex("#363A3F")
    } else {
        Color::from_hex("#AAAAAA")
    };
    let text_color = if is_dark {
        Color::from_hex("#A0A0A0")
    } else {
        Color::from_hex("#404040")
    };
    let bg_color = if is_dark {
        Color::from_hex("#1C1C1C")
    } else {
        Color::from_hex("#F3F3F3")
    };

    unsafe {
        let mut client_rect = RECT::default();
        let _ = GetClientRect(hwnd, &mut client_rect);
        let width = client_rect.right - client_rect.left;
        let height = client_rect.bottom - client_rect.top;
        if width <= 0 || height <= 0 {
            return;
        }

        let mem_dc = CreateCompatibleDC(hdc);
        let mem_bmp = CreateCompatibleBitmap(hdc, width, height);
        let old_bmp = SelectObject(mem_dc, mem_bmp);
        paint_content(
            mem_dc,
            width,
            height,
            is_dark,
            &bg_color,
            &text_color,
            &track,
            language,
            strings,
            codex_session_pct,
            &codex_session_text,
            codex_weekly_pct,
            &codex_weekly_text,
            show_session_window,
            show_weekly_window,
        );
        let _ = BitBlt(hdc, 0, 0, width, height, mem_dc, 0, 0, SRCCOPY);
        SelectObject(mem_dc, old_bmp);
        let _ = DeleteObject(mem_bmp);
        let _ = DeleteDC(mem_dc);
    }
}
'''
w = replace_once(w, r"fn paint\(hdc: HDC, hwnd: HWND\) \{.*?(?=fn draw_row)", paint + "\n", "fallback paint")

draw_row = r'''fn draw_row(
    hdc: HDC,
    x: i32,
    y: i32,
    is_dark: bool,
    language: LanguageId,
    text_color: &Color,
    label: &str,
    percent: f64,
    value_text: &str,
    track: &Color,
    label_width: i32,
    text_width: i32,
) {
    let seg_h = sc(SEGMENT_H);
    let preset = current_appearance_preset();
    let segment_count = row_bar_segment_count(preset);
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
        let _ = DrawTextW(
            hdc,
            &mut label_wide,
            &mut label_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE,
        );

        let bar_x = x + sc(label_width) + sc(metrics.label_bar_gap);
        let bar_color = quota_bar_color(is_dark, percent, language);
        draw_usage_bar(
            hdc,
            bar_x,
            y,
            segment_count,
            percent,
            value_text,
            &bar_color,
            track,
            &percentage_text_color,
            text_width,
        );
    }
}
'''
w = replace_once(w, r"fn draw_row\(.*?(?=fn model_usage_width)", draw_row + "\n", "draw row")

# Replace tests with Codex-only regression coverage; legacy path migration remains supported.
tests = r'''#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn centers_widget_vertically() {
        assert_eq!(compute_anchor_y(100, 48, 42), 103);
        assert_eq!(compute_anchor_y(100, 32, 28), 102);
        assert_eq!(compute_anchor_y(100, 24, 28), 100);
    }

    #[test]
    fn small_taskbar_threshold_is_dpi_aware() {
        assert!(is_small_taskbar_height_at_dpi(32, 96));
        assert!(is_small_taskbar_height_at_dpi(34, 96));
        assert!(!is_small_taskbar_height_at_dpi(35, 96));
        assert!(is_small_taskbar_height_at_dpi(51, 144));
        assert!(!is_small_taskbar_height_at_dpi(52, 144));
    }

    #[test]
    fn service_tooltip_combines_visible_quota_rows() {
        assert_eq!(
            service_tooltip(
                "Codex",
                "剩余13% 19:04重置",
                "剩余86% 07/18重置",
                true,
                true,
            ),
            "Codex: 5H 剩余13% 19:04重置 | 7D 剩余86% 07/18重置"
        );
    }

    fn test_settings_json(language: &str) -> String {
        format!(
            r#"{{
  "tray_offset": 321,
  "taskbar_index": 1,
  "poll_interval_ms": 60000,
  "language": "{language}"
}}"#
        )
    }

    #[test]
    fn legacy_settings_default_to_compact_appearance() {
        let settings: SettingsFile = serde_json::from_str("{}").unwrap();
        assert_eq!(settings.appearance_preset, AppearancePreset::Compact);
    }

    #[test]
    fn explicit_minimal_appearance_round_trips() {
        let mut settings = SettingsFile::default();
        settings.appearance_preset = AppearancePreset::Minimal;
        let json = serde_json::to_string(&settings).unwrap();
        let parsed: SettingsFile = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.appearance_preset, AppearancePreset::Minimal);
    }

    #[test]
    fn loads_legacy_settings_when_new_path_is_missing() {
        let base = std::env::temp_dir().join(format!(
            "codex-usage-settings-test-{}-{}",
            std::process::id(),
            now_unix_secs()
        ));
        let current = base.join("CodexUsage").join("settings.json");
        let legacy = base.join("ClaudeCodeUsageMonitor").join("settings.json");
        std::fs::create_dir_all(legacy.parent().unwrap()).unwrap();
        std::fs::write(&legacy, test_settings_json("zh-CN")).unwrap();
        let (settings, migrated) = load_settings_from_paths(&current, &legacy).unwrap();
        assert!(migrated);
        assert_eq!(settings.tray_offset, 321);
        assert_eq!(settings.poll_interval_ms, 60_000);
        assert_eq!(settings.language.as_deref(), Some("zh-CN"));
        assert!(settings.show_session_window);
        assert!(settings.show_weekly_window);
        let _ = std::fs::remove_dir_all(base);
    }

    #[test]
    fn new_settings_take_precedence_over_legacy_settings() {
        let base = std::env::temp_dir().join(format!(
            "codex-usage-settings-precedence-test-{}-{}",
            std::process::id(),
            now_unix_secs()
        ));
        let current = base.join("CodexUsage").join("settings.json");
        let legacy = base.join("ClaudeCodeUsageMonitor").join("settings.json");
        std::fs::create_dir_all(current.parent().unwrap()).unwrap();
        std::fs::create_dir_all(legacy.parent().unwrap()).unwrap();
        std::fs::write(&current, test_settings_json("en")).unwrap();
        std::fs::write(&legacy, test_settings_json("zh-CN")).unwrap();
        let (settings, migrated) = load_settings_from_paths(&current, &legacy).unwrap();
        assert!(!migrated);
        assert_eq!(settings.language.as_deref(), Some("en"));
        let _ = std::fs::remove_dir_all(base);
    }

    #[test]
    fn startup_migration_only_writes_when_legacy_exists_without_current_entry() {
        assert!(should_write_migrated_startup(true, false));
        assert!(!should_write_migrated_startup(false, false));
        assert!(!should_write_migrated_startup(true, true));
        assert!(!should_write_migrated_startup(false, true));
    }

    #[test]
    fn displays_distinct_transient_error_categories() {
        assert_eq!(
            poll_error_display_label(poller::PollError::NetworkUnavailable, LanguageId::SimplifiedChinese),
            "网络"
        );
        assert_eq!(
            poll_error_display_label(poller::PollError::RateLimited, LanguageId::SimplifiedChinese),
            "限流"
        );
        assert_eq!(poll_error_display_label(poller::PollError::ServerError, LanguageId::English), "5XX");
        assert_eq!(poll_error_display_label(poller::PollError::RequestFailed, LanguageId::English), "ERR");
    }

    #[test]
    fn normalizes_usage_display_and_alert_settings() {
        let settings = normalize_settings(SettingsFile {
            show_session_window: false,
            show_weekly_window: false,
            alert_threshold_percent: 17,
            notified_quota_windows: vec!["codex:weekly:1".into(), "codex:weekly:1".into()],
            ..SettingsFile::default()
        });
        assert!(settings.show_session_window);
        assert!(!settings.show_weekly_window);
        assert_eq!(settings.alert_threshold_percent, 0);
        assert_eq!(settings.notified_quota_windows.len(), 1);
    }

    #[test]
    fn formats_precise_local_reset_time() {
        let local = SYSTEMTIME {
            wYear: 2026,
            wMonth: 7,
            wDay: 17,
            wHour: 18,
            wMinute: 30,
            ..Default::default()
        };
        assert_eq!(format_local_system_time(local), "2026-07-17 18:30");
        assert_eq!(format_precise_reset_time(None), None);
    }

    #[test]
    fn low_quota_alert_is_deduplicated_until_reset_window_changes() {
        let mut alerts = Vec::new();
        let mut notified = BTreeSet::new();
        let first_reset = UNIX_EPOCH + Duration::from_secs(2_000_000_000);
        let first = crate::models::UsageSection {
            percentage: 85.0,
            resets_at: Some(first_reset),
        };
        append_quota_alert(
            &mut alerts,
            &mut notified,
            20,
            LanguageId::SimplifiedChinese,
            tray_icon::TrayIconKind::Codex,
            "codex",
            "Codex",
            "session",
            "5小时",
            &first,
        );
        append_quota_alert(
            &mut alerts,
            &mut notified,
            20,
            LanguageId::SimplifiedChinese,
            tray_icon::TrayIconKind::Codex,
            "codex",
            "Codex",
            "session",
            "5小时",
            &first,
        );
        assert_eq!(alerts.len(), 1);
        assert!(alerts[0].message.contains("仅剩 15%"));

        let next = crate::models::UsageSection {
            percentage: 90.0,
            resets_at: Some(first_reset + Duration::from_secs(18_000)),
        };
        append_quota_alert(
            &mut alerts,
            &mut notified,
            20,
            LanguageId::SimplifiedChinese,
            tray_icon::TrayIconKind::Codex,
            "codex",
            "Codex",
            "session",
            "5小时",
            &next,
        );
        assert_eq!(alerts.len(), 2);
        assert_eq!(notified.len(), 1);
    }
}
'''
w = replace_once(w, r"#\[cfg\(test\)\]\nmod tests \{.*\Z", tests, "tests")
window_path.write_text(w, encoding="utf-8")

print("stage2 source cleanup patch applied")
