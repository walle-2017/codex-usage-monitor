from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

poller = r'''use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::Deserialize;

use crate::diagnose;
use crate::localization::Strings;
use crate::models::{AppUsageData, UsageData, UsageSection};
use crate::native_interop;

const CODEX_USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_SESSION_WINDOW_MAX_SECONDS: u64 = 24 * 60 * 60;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PollError {
    AuthRequired,
    NoCredentials,
    TokenExpired,
    NetworkUnavailable,
    RateLimited,
    ServerError,
    RequestFailed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UsageWindowKind {
    Session,
    Weekly,
}

impl PollError {
    pub fn category(self) -> &'static str {
        match self {
            Self::AuthRequired => "auth_required",
            Self::NoCredentials => "no_credentials",
            Self::TokenExpired => "token_expired",
            Self::NetworkUnavailable => "network_unavailable",
            Self::RateLimited => "rate_limited",
            Self::ServerError => "server_error",
            Self::RequestFailed => "invalid_response",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CredentialWatchMode {
    ActiveSource,
    AllSources,
}

pub type CredentialWatchSnapshot = Vec<String>;

#[derive(Deserialize)]
struct CodexAuthFile {
    tokens: Option<CodexTokenData>,
}

#[derive(Clone, Deserialize)]
struct CodexTokenData {
    access_token: String,
    account_id: Option<String>,
}

#[derive(Deserialize)]
struct CodexUsageResponse {
    rate_limit: Option<Option<Box<CodexRateLimitDetails>>>,
}

#[derive(Deserialize)]
struct CodexRateLimitDetails {
    primary_window: Option<Option<Box<CodexRateLimitWindow>>>,
    secondary_window: Option<Option<Box<CodexRateLimitWindow>>>,
}

#[derive(Deserialize)]
struct CodexRateLimitWindow {
    used_percent: f64,
    reset_at: i64,
    limit_window_seconds: Option<u64>,
}

pub fn poll() -> Result<AppUsageData, PollError> {
    let codex = poll_codex()?;
    Ok(AppUsageData {
        codex: Some(codex),
        ..Default::default()
    })
}

fn poll_codex() -> Result<UsageData, PollError> {
    let creds = read_codex_credentials().ok_or_else(|| {
        diagnose::log("Codex usage poll failed: no Codex credentials found");
        PollError::NoCredentials
    })?;

    match fetch_codex_usage(&creds.access_token, creds.account_id.as_deref()) {
        Ok(data) => Ok(data),
        Err(PollError::AuthRequired) => {
            diagnose::log("Codex credentials rejected; automatic Codex CLI refresh is disabled");
            Err(PollError::TokenExpired)
        }
        Err(error) => Err(error),
    }
}

fn build_agent() -> Result<ureq::Agent, PollError> {
    let tls = native_tls::TlsConnector::new().map_err(|_| PollError::RequestFailed)?;
    Ok(ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(30))
        .tls_connector(std::sync::Arc::new(tls))
        .build())
}

fn classify_http_status(status: u16) -> PollError {
    match status {
        401 | 403 => PollError::AuthRequired,
        429 => PollError::RateLimited,
        500..=599 => PollError::ServerError,
        _ => PollError::RequestFailed,
    }
}

fn classify_ureq_error(error: &ureq::Error) -> PollError {
    match error {
        ureq::Error::Status(status, _) => classify_http_status(*status),
        ureq::Error::Transport(_) => PollError::NetworkUnavailable,
    }
}

fn codex_auth_path() -> Option<PathBuf> {
    if let Some(codex_home) = std::env::var_os("CODEX_HOME").map(PathBuf::from) {
        return Some(codex_home.join("auth.json"));
    }
    Some(dirs::home_dir()?.join(".codex").join("auth.json"))
}

fn read_codex_credentials() -> Option<CodexTokenData> {
    let auth_path = codex_auth_path()?;
    let content = match std::fs::read_to_string(&auth_path) {
        Ok(content) => content,
        Err(error) => {
            if diagnose::is_enabled() {
                diagnose::log_error(
                    &format!("unable to read Codex credentials at {}", auth_path.display()),
                    error,
                );
            }
            return None;
        }
    };
    let auth: CodexAuthFile = serde_json::from_str(&content).ok()?;
    auth.tokens.filter(|tokens| !tokens.access_token.is_empty())
}

pub fn credential_watch_snapshot(_mode: CredentialWatchMode) -> CredentialWatchSnapshot {
    vec![codex_credential_watch_signature()]
}

fn codex_credential_watch_signature() -> String {
    let Some(path) = codex_auth_path() else {
        return "codex:auth|unresolved".to_string();
    };
    let key = format!("codex:{}", path.display());
    match std::fs::metadata(path) {
        Ok(metadata) => {
            let modified = metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_secs())
                .unwrap_or(0);
            format!("{key}|present|{}|{modified}", metadata.len())
        }
        Err(_) => format!("{key}|missing"),
    }
}

fn fetch_codex_usage(token: &str, account_id: Option<&str>) -> Result<UsageData, PollError> {
    let agent = build_agent()?;
    let mut request = agent
        .get(CODEX_USAGE_URL)
        .set("Authorization", &format!("Bearer {token}"))
        .set("User-Agent", "codex-cli");

    if let Some(account_id) = account_id.filter(|value| !value.is_empty()) {
        request = request.set("ChatGPT-Account-Id", account_id);
    }

    let resp = match request.call() {
        Ok(resp) => resp,
        Err(error) => {
            let classified = classify_ureq_error(&error);
            diagnose::log_error("Codex usage endpoint request failed", error);
            return Err(classified);
        }
    };

    let response: CodexUsageResponse = resp.into_json().map_err(|error| {
        diagnose::log_error("unable to parse Codex usage response", error);
        PollError::RequestFailed
    })?;

    codex_usage_from_response(response).ok_or(PollError::RequestFailed)
}

fn codex_usage_from_response(response: CodexUsageResponse) -> Option<UsageData> {
    let details = *response.rate_limit.flatten()?;
    let mut data = UsageData::default();
    let mut has_session = false;
    let mut has_weekly = false;

    let primary = details.primary_window.flatten();
    let secondary = details.secondary_window.flatten();

    for window in [primary.as_deref(), secondary.as_deref()]
        .into_iter()
        .flatten()
    {
        match codex_window_kind(window) {
            Some(UsageWindowKind::Session) if !has_session => {
                data.session = codex_section_from_window(window);
                has_session = true;
            }
            Some(UsageWindowKind::Weekly) if !has_weekly => {
                data.weekly = codex_section_from_window(window);
                has_weekly = true;
            }
            _ => {}
        }
    }

    if let Some(window) = primary
        .as_deref()
        .filter(|window| window.limit_window_seconds.is_none() && !has_session)
    {
        data.session = codex_section_from_window(window);
    }
    if let Some(window) = secondary
        .as_deref()
        .filter(|window| window.limit_window_seconds.is_none() && !has_weekly)
    {
        data.weekly = codex_section_from_window(window);
    }

    Some(data)
}

fn codex_window_kind(window: &CodexRateLimitWindow) -> Option<UsageWindowKind> {
    window.limit_window_seconds.map(|seconds| {
        if seconds <= CODEX_SESSION_WINDOW_MAX_SECONDS {
            UsageWindowKind::Session
        } else {
            UsageWindowKind::Weekly
        }
    })
}

fn codex_section_from_window(window: &CodexRateLimitWindow) -> UsageSection {
    UsageSection {
        percentage: window.used_percent,
        resets_at: unix_to_system_time(Some(window.reset_at)),
    }
}

fn unix_to_system_time(unix_secs: Option<i64>) -> Option<SystemTime> {
    let secs = unix_secs?;
    if secs < 0 {
        return None;
    }
    Some(UNIX_EPOCH + Duration::from_secs(secs as u64))
}

pub fn remaining_percentage(used_percentage: f64) -> f64 {
    (100.0 - used_percentage).clamp(0.0, 100.0)
}

pub fn format_line(
    section: &UsageSection,
    strings: Strings,
    simplified_chinese: bool,
    window: UsageWindowKind,
) -> String {
    let remaining = remaining_percentage(section.percentage);
    if simplified_chinese {
        let reset = section
            .resets_at
            .and_then(native_interop::system_time_to_local);
        return match reset {
            None => format!("剩余{remaining:.0}%"),
            Some(reset) => match window {
                UsageWindowKind::Session => format!(
                    "剩余{remaining:.0}%  {:02}:{:02}重置",
                    reset.wHour, reset.wMinute
                ),
                UsageWindowKind::Weekly => format!(
                    "剩余{remaining:.0}%  {:02}/{:02}重置",
                    reset.wMonth, reset.wDay
                ),
            },
        };
    }

    let pct = format!("{remaining:.0}% remaining");
    let cd = format_countdown(section.resets_at, strings);
    if cd.is_empty() {
        pct
    } else {
        format!("{pct} \u{00b7} {cd}")
    }
}

fn format_countdown(resets_at: Option<SystemTime>, strings: Strings) -> String {
    let reset = match resets_at {
        Some(t) => t,
        None => return String::new(),
    };
    let remaining = match reset.duration_since(SystemTime::now()) {
        Ok(d) => d,
        Err(_) => return strings.now.to_string(),
    };
    format_countdown_from_secs(remaining.as_secs(), strings)
}

fn format_countdown_from_secs(total_secs: u64, strings: Strings) -> String {
    let total_mins = total_secs / 60;
    let total_hours = total_secs / 3600;
    let total_days = total_secs / 86400;
    if total_days >= 1 {
        format!("{total_days}{}", strings.day_suffix)
    } else if total_hours >= 1 {
        format!("{total_hours}{}", strings.hour_suffix)
    } else if total_mins >= 1 {
        format!("{total_mins}{}", strings.minute_suffix)
    } else {
        format!("{total_secs}{}", strings.second_suffix)
    }
}

pub fn time_until_display_change(resets_at: Option<SystemTime>) -> Option<Duration> {
    let reset = resets_at?;
    let remaining = reset.duration_since(SystemTime::now()).ok()?;
    Some(time_until_display_change_from_secs(remaining.as_secs()))
}

fn time_until_display_change_from_secs(total_secs: u64) -> Duration {
    let total_mins = total_secs / 60;
    let total_hours = total_secs / 3600;
    let total_days = total_secs / 86400;
    let current_bucket_start = if total_days >= 1 {
        total_days * 86400
    } else if total_hours >= 1 {
        total_hours * 3600
    } else if total_mins >= 1 {
        total_mins * 60
    } else {
        total_secs
    };
    Duration::from_secs(total_secs.saturating_sub(current_bucket_start) + 1)
}

pub fn is_past_reset(data: &UsageData) -> bool {
    let now = SystemTime::now();
    let past = |s: &UsageSection| matches!(s.resets_at, Some(t) if now.duration_since(t).is_ok());
    past(&data.session) || past(&data.weekly)
}

pub fn app_is_past_reset(data: &AppUsageData) -> bool {
    data.codex.as_ref().is_some_and(is_past_reset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remaining_percentage_is_clamped() {
        assert_eq!(remaining_percentage(30.0), 70.0);
        assert_eq!(remaining_percentage(-5.0), 100.0);
        assert_eq!(remaining_percentage(120.0), 0.0);
    }

    #[test]
    fn codex_weekly_only_window_is_not_misreported_as_session_usage() {
        let response: CodexUsageResponse = serde_json::from_str(r#"{
            "rate_limit": {
                "primary_window": {
                    "used_percent": 21,
                    "limit_window_seconds": 604800,
                    "reset_at": 1784500338
                },
                "secondary_window": null
            }
        }"#).unwrap();
        let usage = codex_usage_from_response(response).unwrap();
        assert_eq!(usage.session.percentage, 0.0);
        assert_eq!(usage.weekly.percentage, 21.0);
    }

    #[test]
    fn codex_legacy_windows_keep_positional_mapping_without_durations() {
        let response: CodexUsageResponse = serde_json::from_str(r#"{
            "rate_limit": {
                "primary_window": {"used_percent": 18, "reset_at": 1784500338},
                "secondary_window": {"used_percent": 33, "reset_at": 1785000000}
            }
        }"#).unwrap();
        let usage = codex_usage_from_response(response).unwrap();
        assert_eq!(usage.session.percentage, 18.0);
        assert_eq!(usage.weekly.percentage, 33.0);
    }

    #[test]
    fn classifies_http_failures() {
        assert_eq!(classify_http_status(401), PollError::AuthRequired);
        assert_eq!(classify_http_status(429), PollError::RateLimited);
        assert_eq!(classify_http_status(503), PollError::ServerError);
        assert_eq!(classify_http_status(404), PollError::RequestFailed);
    }
}
'''
(ROOT / 'src' / 'poller.rs').write_text(poller, encoding='utf-8')

# Main: stop exposing the in-app updater CLI path. The module itself is removed
# in stage 2 after all dead references are cleaned.
main_path = ROOT / 'src' / 'main.rs'
main = main_path.read_text(encoding='utf-8')
main = re.sub(r'\n\s*if let Some\(exit_code\) = updater::handle_cli_mode\(&args\) \{.*?\n\s*\}\n', '\n', main, flags=re.S)
main_path.write_text(main, encoding='utf-8')

# Tray: left-click no longer hides/shows the taskbar widget.
tray_path = ROOT / 'src' / 'tray_icon.rs'
tray = tray_path.read_text(encoding='utf-8')
tray = tray.replace('    ToggleWidget,\n', '')
tray = tray.replace('        WM_LBUTTONUP => TrayAction::ToggleWidget,\n', '        WM_LBUTTONUP => TrayAction::None,\n')
tray_path.write_text(tray, encoding='utf-8')

window_path = ROOT / 'src' / 'window.rs'
window = window_path.read_text(encoding='utf-8')

# Force legacy settings to a single active Codex provider and an always-visible widget.
needle = 'fn normalize_settings(mut settings: SettingsFile) -> SettingsFile {\n'
assert needle in window
window = window.replace(needle, needle + '    settings.show_claude_code = false;\n    settings.show_codex = true;\n    settings.show_antigravity = false;\n    settings.widget_visible = true;\n', 1)

# No provider-selection menu IDs or command handling.
window = re.sub(r'const IDM_MODEL_CLAUDE_CODE: u16 = 60;\nconst IDM_MODEL_CODEX: u16 = 61;\nconst IDM_MODEL_ANTIGRAVITY: u16 = 62;\n', '', window)
window, n = re.subn(r'\n\s*// Models submenu\n.*?\n\s*// Usage window visibility submenu\.', '\n\n        // Usage window visibility submenu.', window, count=1, flags=re.S)
assert n == 1, 'models submenu block not found'
window, n = re.subn(r'\n\s*IDM_MODEL_CLAUDE_CODE \| IDM_MODEL_CODEX \| IDM_MODEL_ANTIGRAVITY => \{.*?\n\s*\}\n\s*IDM_APPEARANCE_COMPACT', '\n                IDM_APPEARANCE_COMPACT', window, count=1, flags=re.S)
assert n == 1, 'provider command block not found'

# Use the zero-argument Codex-only poller and only update Codex values.
window, n = re.subn(
    r'fn do_poll\(send_hwnd: SendHwnd\) \{.*?\n\}\n\nfn schedule_countdown_timer\(\)',
    r'''fn do_poll(send_hwnd: SendHwnd) {
    let hwnd = send_hwnd.to_hwnd();
    match poller::poll() {
        Ok(data) => {
            let mut state = lock_state();
            let mut quota_alerts = Vec::new();
            if let Some(s) = state.as_mut() {
                if let Some(codex) = data.codex.as_ref() {
                    s.codex_session_percent = codex.session.percentage;
                    s.codex_weekly_percent = codex.weekly.percentage;
                }
                if !poller::app_is_past_reset(&data) {
                    unsafe { let _ = KillTimer(hwnd, TIMER_RESET_POLL); }
                }
                quota_alerts = collect_low_quota_alerts(s, &data);
                s.data = Some(data);
                s.last_poll_ok = true;
                refresh_usage_texts(s);
                if s.retry_count > 0 {
                    s.retry_count = 0;
                    unsafe { SetTimer(hwnd, TIMER_POLL, s.poll_interval_ms, None); }
                }
                s.force_notify_auth_error = false;
                s.auth_error_paused_polling = false;
                s.auth_watch_mode = poller::CredentialWatchMode::ActiveSource;
                s.auth_watch_snapshot.clear();
            }
            drop(state);
            for alert in &quota_alerts {
                tray_icon::notify_balloon(hwnd, alert.kind, &alert.title, &alert.message);
            }
            if !quota_alerts.is_empty() { save_state_settings(); }
            unsafe { let _ = PostMessageW(hwnd, WM_APP_USAGE_UPDATED, WPARAM(0), LPARAM(0)); }
        }
        Err(e) => {
            let auth_watch = match e {
                poller::PollError::AuthRequired | poller::PollError::TokenExpired => Some((
                    poller::CredentialWatchMode::ActiveSource,
                    poller::credential_watch_snapshot(poller::CredentialWatchMode::ActiveSource),
                )),
                poller::PollError::NoCredentials => Some((
                    poller::CredentialWatchMode::AllSources,
                    poller::credential_watch_snapshot(poller::CredentialWatchMode::AllSources),
                )),
                _ => None,
            };
            let notify_auth_error = {
                let mut state = lock_state();
                let mut notify = false;
                if let Some(s) = state.as_mut() {
                    s.last_poll_ok = false;
                    if let Some((mode, snapshot)) = auth_watch {
                        notify = s.retry_count == 0 || s.force_notify_auth_error;
                        s.force_notify_auth_error = false;
                        s.auth_error_paused_polling = true;
                        s.auth_watch_mode = mode;
                        s.auth_watch_snapshot = snapshot;
                        s.codex_session_text = "!".to_string();
                        s.codex_weekly_text = "!".to_string();
                        s.retry_count = s.retry_count.saturating_add(1);
                        unsafe {
                            let _ = KillTimer(hwnd, TIMER_POLL);
                            let _ = KillTimer(hwnd, TIMER_RESET_POLL);
                            let _ = KillTimer(hwnd, TIMER_COUNTDOWN);
                            SetTimer(hwnd, TIMER_POLL, s.poll_interval_ms, None);
                        }
                    } else {
                        s.force_notify_auth_error = false;
                        s.auth_error_paused_polling = false;
                        s.auth_watch_mode = poller::CredentialWatchMode::ActiveSource;
                        s.auth_watch_snapshot.clear();
                        let label = poll_error_display_label(e, s.language).to_string();
                        s.codex_session_text = label.clone();
                        s.codex_weekly_text = label;
                        s.retry_count = s.retry_count.saturating_add(1);
                        let backoff = RETRY_BASE_MS.saturating_mul(
                            1u32.checked_shl(s.retry_count - 1).unwrap_or(u32::MAX),
                        );
                        unsafe {
                            let _ = KillTimer(hwnd, TIMER_RESET_POLL);
                            SetTimer(hwnd, TIMER_POLL, backoff.min(s.poll_interval_ms), None);
                        }
                    }
                }
                notify
            };
            if notify_auth_error {
                let state = lock_state();
                if let Some(s) = state.as_ref() {
                    tray_icon::notify_balloon(
                        hwnd,
                        tray_icon::TrayIconKind::Codex,
                        s.language.strings().codex_token_expired_title,
                        s.language.strings().codex_token_expired_body,
                    );
                }
            }
            unsafe { let _ = PostMessageW(hwnd, WM_APP_USAGE_UPDATED, WPARAM(0), LPARAM(0)); }
        }
    }
}

fn schedule_countdown_timer()''',
    window,
    count=1,
    flags=re.S,
)
assert n == 1, 'do_poll block not found'

# Countdown only watches Codex reset windows.
window, n = re.subn(
    r'let delays = \[.*?\];\n\s*let min_delay',
    '''let delays = [
        data.codex.as_ref().and_then(|usage| poller::time_until_display_change(usage.session.resets_at)),
        data.codex.as_ref().and_then(|usage| poller::time_until_display_change(usage.weekly.resets_at)),
    ];
    let min_delay''',
    window,
    count=1,
    flags=re.S,
)
assert n == 1, 'countdown delays block not found'

# Disable the in-app update entry points without deleting their dead implementations yet.
window = window.replace('                TIMER_UPDATE_CHECK => {\n                    begin_update_check(hwnd, false);\n                }\n', '')
window = re.sub(r'\n\s*WM_APP_UPDATE_CHECK_COMPLETE => \{.*?\n\s*\}\n', '\n', window, count=1, flags=re.S)
window = re.sub(r'\n\s*IDM_VERSION_ACTION => \{.*?\n\s*\}\n\s*2 =>', '\n                2 =>', window, count=1, flags=re.S)
window = re.sub(r'\n\s*schedule_auto_update_check\(hwnd\);\n\s*let should_check_updates = \{.*?\n\s*if should_check_updates \{\n\s*begin_update_check\(hwnd, false\);\n\s*\}\n', '\n', window, count=1, flags=re.S)

# Replace interactive update menu item with a disabled, read-only version label.
window, n = re.subn(
    r'\n\s*let _ = AppendMenuW\(settings_menu, MF_SEPARATOR, 0, PCWSTR::null\(\)\);\n\n\s*let version_label =.*?\n\s*\);\n\n\s*let settings_label',
    '''
        let _ = AppendMenuW(settings_menu, MF_SEPARATOR, 0, PCWSTR::null());
        let version_label = native_interop::wide_str(&format!("v{}", env!("CARGO_PKG_VERSION")));
        let _ = AppendMenuW(
            settings_menu,
            MF_GRAYED,
            0,
            PCWSTR::from_raw(version_label.as_ptr()),
        );

        let settings_label''',
    window,
    count=1,
    flags=re.S,
)
assert n == 1, 'version menu block not found'
window = window.replace('const IDM_VERSION_ACTION: u16 = 31;\n', '')

# Remove widget visibility menu/action and make process-running widget always visible.
window, n = re.subn(r'\n\s*let widget_label = native_interop::wide_str\(strings.show_widget\);.*?PCWSTR::from_raw\(widget_label.as_ptr\(\)\),\n\s*\);\n', '\n', window, count=1, flags=re.S)
assert n == 1, 'widget menu block not found'
window = re.sub(r'\n\s*id if id == tray_icon::IDM_TOGGLE_WIDGET => \{\n\s*toggle_widget_visibility\(hwnd\);\n\s*\}\n', '\n', window, count=1)
window = re.sub(r'\nfn toggle_widget_visibility\(hwnd: HWND\) \{.*?\n\}\n\nfn attach_to_taskbar', '\nfn attach_to_taskbar', window, count=1, flags=re.S)
window = window.replace('                tray_icon::TrayAction::ToggleWidget => {\n                    toggle_widget_visibility(hwnd);\n                }\n', '')
window, n = re.subn(r'// Position and show \(only if widget_visible preference is true\)\n\s*position_at_taskbar\(\);\n\s*if settings.widget_visible \{\n\s*let _ = ShowWindow\(hwnd, SW_SHOWNOACTIVATE\);\n\s*\}', '// Position and show. While the process runs, the taskbar widget is always visible.\n        position_at_taskbar();\n        let _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);', window, count=1)
assert n == 1, 'initial visibility block not found'

# The old provider availability probe no longer exists; settings normalization forces Codex only.
window = window.replace('let claude_code_available = poller::claude_code_credentials_available();', 'let claude_code_available = false;')

window_path.write_text(window, encoding='utf-8')

print('stage1 patch applied')
