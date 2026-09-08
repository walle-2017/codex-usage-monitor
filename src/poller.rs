use std::path::PathBuf;
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
                    &format!(
                        "unable to read Codex credentials at {}",
                        auth_path.display()
                    ),
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
        let response: CodexUsageResponse = serde_json::from_str(
            r#"{
            "rate_limit": {
                "primary_window": {
                    "used_percent": 21,
                    "limit_window_seconds": 604800,
                    "reset_at": 1784500338
                },
                "secondary_window": null
            }
        }"#,
        )
        .unwrap();
        let usage = codex_usage_from_response(response).unwrap();
        assert_eq!(usage.session.percentage, 0.0);
        assert_eq!(usage.weekly.percentage, 21.0);
    }

    #[test]
    fn codex_legacy_windows_keep_positional_mapping_without_durations() {
        let response: CodexUsageResponse = serde_json::from_str(
            r#"{
            "rate_limit": {
                "primary_window": {"used_percent": 18, "reset_at": 1784500338},
                "secondary_window": {"used_percent": 33, "reset_at": 1785000000}
            }
        }"#,
        )
        .unwrap();
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
