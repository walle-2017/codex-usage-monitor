use std::collections::VecDeque;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{PostMessageW, WM_APP};

use crate::diagnose;

const LATEST_RELEASE_URL: &str =
    "https://github.com/walle-2017/codex-usage-monitor/releases/latest";
const RELEASE_TAG_PREFIX: &str =
    "https://github.com/walle-2017/codex-usage-monitor/releases/tag/v";
const RELEASE_TAG_RELATIVE_PREFIX: &str =
    "/walle-2017/codex-usage-monitor/releases/tag/v";
const RELEASE_ASSET_PREFIX: &str =
    "https://github.com/walle-2017/codex-usage-monitor/releases/download/";
const EXE_ASSET_NAME: &str = "codex-usage.exe";
const CHECKSUM_ASSET_NAME: &str = "codex-usage.exe.sha256";
const UPDATE_TIMEOUT_SECS: u64 = 30;
const HELPER_WAIT_SECS: u64 = 60;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const UPDATE_SUCCESS_MARKER_SUFFIX: &str = "update-success";

pub(crate) const WM_APP_UPDATE_RESULT: u32 = WM_APP + 21;
pub(crate) const WM_APP_UPDATE_PROGRESS: u32 = WM_APP + 22;

static UPDATE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);
static UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);
static UPDATE_PROGRESS: Mutex<VecDeque<UpdateProgress>> = Mutex::new(VecDeque::new());
static LAST_ERROR_DETAIL: Mutex<String> = Mutex::new(String::new());

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateError {
    CheckFailed,
    InvalidRelease,
    DownloadFailed,
    InvalidChecksum,
    ChecksumMismatch,
    TargetNotWritable,
    HelperLaunchFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateUiResult {
    Current { version: String },
    Failed { error: UpdateError, detail: String },
    ReadyToRestart,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateProgress {
    Checking,
    Downloading { version: String },
    Restarting { version: String },
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
struct Version {
    major: u64,
    minor: u64,
    patch: u64,
}

impl Version {
    fn parse(value: &str) -> Option<Self> {
        let mut parts = value.split('.');
        let major = parts.next()?.parse().ok()?;
        let minor = parts.next()?.parse().ok()?;
        let patch = parts.next()?.parse().ok()?;
        if parts.next().is_some() {
            return None;
        }
        Some(Self {
            major,
            minor,
            patch,
        })
    }

}


#[derive(Clone, Debug)]
struct ReleaseUpdate {
    version: String,
    executable_url: String,
    checksum_url: String,
}

#[derive(Debug)]
struct UpdatePackage {
    version: String,
    staging_dir: PathBuf,
    target: PathBuf,
    prepared_new: PathBuf,
    working_dir: PathBuf,
    relaunch_args: Vec<String>,
}

enum UpdateOutcome {
    Current { version: String },
    Ready(UpdatePackage),
}

fn safe_detail(value: impl std::fmt::Display) -> String {
    let raw = value.to_string().replace(['\r', '\n'], " ");
    redact_url_userinfo(&raw).chars().take(240).collect()
}

fn redact_url_userinfo(value: &str) -> String {
    let mut output = value.to_string();
    for scheme in ["https://", "http://"] {
        let mut search_from = 0;
        while let Some(relative) = output[search_from..].find(scheme) {
            let start = search_from + relative + scheme.len();
            let tail = &output[start..];
            let Some(at_relative) = tail.find('@') else { break };
            let slash_relative = tail.find('/').unwrap_or(usize::MAX);
            if at_relative > slash_relative { break; }
            let userinfo = &tail[..at_relative];
            if userinfo.contains(':') {
                output.replace_range(start..start + at_relative, "<redacted>");
                search_from = start + "<redacted>@".len();
            } else {
                search_from = start + at_relative + 1;
            }
        }
    }
    output
}

fn set_error_detail(detail: impl Into<String>) {
    let mut stored = LAST_ERROR_DETAIL.lock().unwrap_or_else(|error| error.into_inner());
    *stored = detail.into();
}

fn clear_error_detail() {
    set_error_detail(String::new());
}

fn visible_error_detail(error: &UpdateError) -> String {
    let stored = LAST_ERROR_DETAIL
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    if !stored.is_empty() {
        return stored;
    }
    match error {
        UpdateError::CheckFailed => "GitHub Release request failed".to_string(),
        UpdateError::InvalidRelease => "Release metadata is invalid".to_string(),
        UpdateError::DownloadFailed => "Release asset download failed".to_string(),
        UpdateError::InvalidChecksum => "Checksum file is invalid".to_string(),
        UpdateError::ChecksumMismatch => "SHA256 mismatch".to_string(),
        UpdateError::TargetNotWritable => "Executable directory is not writable".to_string(),
        UpdateError::HelperLaunchFailed => "Unable to start update helper".to_string(),
    }
}

fn diagnostic_body_summary(content_type: Option<&str>, body: &str) -> (Option<String>, Option<String>) {
    let sanitized = safe_detail(body);
    let is_json = content_type
        .map(|value| value.to_ascii_lowercase().contains("json"))
        .unwrap_or(false);
    let body_message = if is_json {
        serde_json::from_str::<serde_json::Value>(body)
            .ok()
            .and_then(|value| value.get("message").and_then(|message| message.as_str()).map(safe_detail))
    } else {
        None
    };
    let body_preview = if body_message.is_none() && !sanitized.is_empty() {
        Some(sanitized)
    } else {
        None
    };
    (body_message, body_preview)
}

fn github_status_detail(status: u16, response: ureq::Response) -> String {
    let header_names = [
        "X-RateLimit-Limit",
        "X-RateLimit-Remaining",
        "X-RateLimit-Reset",
        "X-RateLimit-Resource",
        "Retry-After",
        "Server",
        "Content-Type",
    ];
    let content_type = response.header("Content-Type").map(str::to_string);
    let mut parts = vec![format!("HTTP {status}")];
    for name in header_names {
        if let Some(value) = response.header(name) {
            parts.push(format!("{}={}", name.to_ascii_lowercase(), safe_detail(value)));
        }
    }

    let mut body = String::new();
    let mut reader = response.into_reader().take(4096);
    let _ = reader.read_to_string(&mut body);
    let (body_message, body_preview) = diagnostic_body_summary(content_type.as_deref(), &body);
    if let Some(message) = body_message {
        parts.push(format!("body_message={message}"));
    } else if let Some(preview) = body_preview {
        parts.push(format!("body_preview={preview}"));
    }
    parts.join(" ")
}

fn ureq_error_detail(error: ureq::Error) -> String {
    match error {
        ureq::Error::Status(status, response) => github_status_detail(status, response),
        ureq::Error::Transport(transport) => format!("network/TLS: {}", safe_detail(transport)),
    }
}

fn lock_result() -> MutexGuard<'static, Option<UpdateUiResult>> {
    UPDATE_RESULT.lock().unwrap_or_else(|error| error.into_inner())
}

fn lock_progress() -> MutexGuard<'static, VecDeque<UpdateProgress>> {
    UPDATE_PROGRESS
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}

fn post_progress(hwnd_raw: isize, progress: UpdateProgress) {
    diagnose::log(format!("updater: progress={progress:?}"));
    lock_progress().push_back(progress);
    let target_hwnd = HWND(hwnd_raw as *mut _);
    unsafe {
        let _ = PostMessageW(target_hwnd, WM_APP_UPDATE_PROGRESS, WPARAM(0), LPARAM(0));
    }
}

pub(crate) fn take_progress() -> Option<UpdateProgress> {
    lock_progress().pop_front()
}

pub(crate) fn start_update(hwnd: HWND) -> bool {
    diagnose::log("updater: check started");
    clear_error_detail();
    if UPDATE_IN_PROGRESS
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return false;
    }

    let hwnd_raw = hwnd.0 as isize;
    post_progress(hwnd_raw, UpdateProgress::Checking);
    std::thread::spawn(move || {
        let ui_result = match prepare_update(hwnd_raw) {
            Ok(UpdateOutcome::Current { version }) => UpdateUiResult::Current { version },
            Ok(UpdateOutcome::Ready(package)) => {
                let version = package.version.clone();
                match launch_prepared_update(package) {
                    Ok(()) => {
                        post_progress(hwnd_raw, UpdateProgress::Restarting { version });
                        UpdateUiResult::ReadyToRestart
                    },
                    Err(error) => {
                        let detail = visible_error_detail(&error);
                        diagnose::log(format!("updater: helper failed error={error:?} detail={detail}"));
                        UpdateUiResult::Failed { error, detail }
                    },
                }
            },
            Err(error) => {
                let detail = visible_error_detail(&error);
                diagnose::log(format!("updater: failed error={error:?} detail={detail}"));
                UpdateUiResult::Failed { error, detail }
            },
        };

        *lock_result() = Some(ui_result);
        let target_hwnd = HWND(hwnd_raw as *mut _);
        unsafe {
            let _ = PostMessageW(target_hwnd, WM_APP_UPDATE_RESULT, WPARAM(0), LPARAM(0));
        }
    });

    true
}

pub(crate) fn take_ui_result() -> Option<UpdateUiResult> {
    let result = lock_result().take();
    if result.is_some() {
        UPDATE_IN_PROGRESS.store(false, Ordering::Release);
    }
    result
}

fn parse_release_redirect(location: &str) -> Result<(Version, String), UpdateError> {
    let tag = location
        .strip_prefix(RELEASE_TAG_PREFIX)
        .or_else(|| location.strip_prefix(RELEASE_TAG_RELATIVE_PREFIX))
        .ok_or_else(|| {
            set_error_detail(format!("unexpected latest Release redirect: {}", safe_detail(location)));
            UpdateError::InvalidRelease
        })?;

    if tag.is_empty()
        || tag.contains('/')
        || tag.contains('?')
        || tag.contains('#')
        || tag.contains('-')
        || tag.contains('+')
    {
        set_error_detail(format!("invalid latest Release tag redirect: {}", safe_detail(location)));
        return Err(UpdateError::InvalidRelease);
    }

    let version = Version::parse(tag).ok_or_else(|| {
        set_error_detail(format!("invalid latest Release version: {}", safe_detail(tag)));
        UpdateError::InvalidRelease
    })?;
    let version_text = format!("{}.{}.{}", version.major, version.minor, version.patch);
    Ok((version, version_text))
}

fn release_update_for_version(version: &str) -> ReleaseUpdate {
    ReleaseUpdate {
        version: version.to_string(),
        executable_url: format!("{RELEASE_ASSET_PREFIX}v{version}/{EXE_ASSET_NAME}"),
        checksum_url: format!("{RELEASE_ASSET_PREFIX}v{version}/{CHECKSUM_ASSET_NAME}"),
    }
}

fn build_discovery_agent() -> Result<ureq::Agent, UpdateError> {
    let tls = native_tls::TlsConnector::new().map_err(|error| {
        let detail = format!("TLS initialization failed: {}", safe_detail(&error));
        set_error_detail(detail.clone());
        diagnose::log(format!("updater: {detail}"));
        UpdateError::CheckFailed
    })?;
    Ok(ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(UPDATE_TIMEOUT_SECS))
        .redirects(0)
        .tls_connector(Arc::new(tls))
        .build())
}

fn build_agent() -> Result<ureq::Agent, UpdateError> {
    let tls = native_tls::TlsConnector::new().map_err(|error| {
        let detail = format!("TLS initialization failed: {}", safe_detail(&error));
        set_error_detail(detail.clone());
        diagnose::log(format!("updater: {detail}"));
        UpdateError::CheckFailed
    })?;
    Ok(ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(UPDATE_TIMEOUT_SECS))
        .tls_connector(Arc::new(tls))
        .build())
}

fn request_builder<'a>(agent: &'a ureq::Agent, url: &'a str) -> ureq::Request {
    agent
        .get(url)
        .set(
            "User-Agent",
            &format!("CodexUsage-Updater/{}", env!("CARGO_PKG_VERSION")),
        )
        .set("Accept", "*/*")
}

fn prepare_update(hwnd_raw: isize) -> Result<UpdateOutcome, UpdateError> {
    let current_text = env!("CARGO_PKG_VERSION");
    diagnose::log(format!("updater: checking latest Release current={current_text}"));
    let current = Version::parse(current_text).ok_or(UpdateError::InvalidRelease)?;

    let discovery_agent = build_discovery_agent()?;
    let release_response = request_builder(&discovery_agent, LATEST_RELEASE_URL)
        .call()
        .map_err(|error| {
            let detail = format!("GitHub latest Release redirect request failed: {}", ureq_error_detail(error));
            set_error_detail(detail.clone());
            diagnose::log(format!("updater: {detail}"));
            UpdateError::CheckFailed
        })?;

    let status = release_response.status();
    if !matches!(status, 301 | 302 | 303 | 307 | 308) {
        let detail = format!("GitHub latest Release endpoint returned unexpected HTTP {status}");
        set_error_detail(detail.clone());
        diagnose::log(format!("updater: {detail}"));
        return Err(UpdateError::InvalidRelease);
    }
    let location = release_response.header("Location").ok_or_else(|| {
        set_error_detail("GitHub latest Release redirect is missing Location header");
        UpdateError::InvalidRelease
    })?;
    let (latest, latest_text) = parse_release_redirect(location)?;
    diagnose::log(format!(
        "updater: latest release tag=v{latest_text} current={current_text} discovery=github-redirect"
    ));

    if latest <= current {
        diagnose::log("updater: current version is already latest");
        return Ok(UpdateOutcome::Current {
            version: current_text.to_string(),
        });
    }

    post_progress(
        hwnd_raw,
        UpdateProgress::Downloading {
            version: latest_text.clone(),
        },
    );
    let update = release_update_for_version(&latest_text);
    let agent = build_agent()?;
    let staging_dir = unique_staging_dir();
    fs::create_dir_all(&staging_dir).map_err(|error| {
        diagnose::log_error("updater: unable to create staging directory", error);
        UpdateError::DownloadFailed
    })?;

    match prepare_downloaded_package(&agent, update, staging_dir.clone()) {
        Ok(package) => Ok(UpdateOutcome::Ready(package)),
        Err(error) => {
            let _ = fs::remove_dir_all(staging_dir);
            Err(error)
        }
    }
}

fn prepare_downloaded_package(
    agent: &ureq::Agent,
    update: ReleaseUpdate,
    staging_dir: PathBuf,
) -> Result<UpdatePackage, UpdateError> {
    let staged_exe = staging_dir.join(EXE_ASSET_NAME);
    let checksum_path = staging_dir.join(CHECKSUM_ASSET_NAME);

    diagnose::log(format!("updater: update available version={}", update.version));
    download_to(agent, &update.executable_url, &staged_exe)?;
    download_to(agent, &update.checksum_url, &checksum_path)?;

    let checksum_text = fs::read_to_string(&checksum_path).map_err(|error| {
        diagnose::log_error("updater: unable to read checksum asset", error);
        UpdateError::InvalidChecksum
    })?;
    let expected = parse_sha256(&checksum_text)?;
    verify_sha256(&staged_exe, &expected)?;
    diagnose::log("updater: downloaded executable SHA256 verified");

    let target = std::env::current_exe().map_err(|error| {
        diagnose::log_error("updater: unable to resolve current executable", error);
        UpdateError::TargetNotWritable
    })?;
    let target_parent = target.parent().ok_or(UpdateError::TargetNotWritable)?;
    preflight_writable(target_parent)?;

    let prepared_new = sibling_path(&target, "new");
    let _ = fs::remove_file(&prepared_new);
    fs::copy(&staged_exe, &prepared_new).map_err(|error| {
        diagnose::log_error("updater: unable to stage replacement beside executable", error);
        UpdateError::TargetNotWritable
    })?;
    if let Err(error) = verify_sha256(&prepared_new, &expected) {
        let _ = fs::remove_file(&prepared_new);
        return Err(error);
    }

    let working_dir = std::env::current_dir().unwrap_or_else(|_| target_parent.to_path_buf());
    let relaunch_args = std::env::args().skip(1).collect();

    Ok(UpdatePackage {
        version: update.version,
        staging_dir,
        target,
        prepared_new,
        working_dir,
        relaunch_args,
    })
}

fn download_to(agent: &ureq::Agent, url: &str, destination: &Path) -> Result<(), UpdateError> {
    if !url.starts_with(RELEASE_ASSET_PREFIX) {
        return Err(UpdateError::InvalidRelease);
    }
    let response = request_builder(agent, url).call().map_err(|error| {
        let detail = format!("Release asset download failed: {}", ureq_error_detail(error));
        set_error_detail(detail.clone());
        diagnose::log(format!("updater: {detail}"));
        UpdateError::DownloadFailed
    })?;
    let mut reader = response.into_reader();
    let mut file = File::create(destination).map_err(|error| {
        diagnose::log_error("updater: unable to create staged asset", error);
        UpdateError::DownloadFailed
    })?;
    io::copy(&mut reader, &mut file).map_err(|error| {
        diagnose::log_error("updater: unable to write staged asset", error);
        UpdateError::DownloadFailed
    })?;
    file.flush().map_err(|error| {
        diagnose::log_error("updater: unable to flush staged asset", error);
        UpdateError::DownloadFailed
    })?;
    Ok(())
}

fn parse_sha256(value: &str) -> Result<String, UpdateError> {
    let matches: Vec<&str> = value
        .split_whitespace()
        .filter(|token| token.len() == 64 && token.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .collect();
    if matches.len() != 1 {
        set_error_detail("checksum asset does not contain exactly one SHA256 value");
        return Err(UpdateError::InvalidChecksum);
    }
    Ok(matches[0].to_ascii_lowercase())
}

fn sha256_file(path: &Path) -> Result<String, UpdateError> {
    let mut file = File::open(path).map_err(|_| UpdateError::InvalidChecksum)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|_| UpdateError::InvalidChecksum)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn verify_sha256(path: &Path, expected: &str) -> Result<(), UpdateError> {
    let actual = sha256_file(path)?;
    if actual.eq_ignore_ascii_case(expected) {
        Ok(())
    } else {
        set_error_detail(format!("SHA256 mismatch: expected {expected}, actual {actual}"));
        Err(UpdateError::ChecksumMismatch)
    }
}

fn unique_staging_dir() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "codex-usage-update-{}-{nonce}",
        std::process::id()
    ))
}

fn preflight_writable(directory: &Path) -> Result<(), UpdateError> {
    if !directory.is_dir() {
        return Err(UpdateError::TargetNotWritable);
    }
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let probe = directory.join(format!(
        ".codex-usage-update-probe-{}-{nonce}",
        std::process::id()
    ));
    let result = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
        .and_then(|mut file| file.write_all(b"probe"));
    let _ = fs::remove_file(&probe);
    result.map_err(|error| {
        let detail = format!("executable directory is not writable: {}", safe_detail(&error));
        set_error_detail(detail.clone());
        diagnose::log(format!("updater: {detail}"));
        UpdateError::TargetNotWritable
    })
}

fn sibling_path(target: &Path, suffix: &str) -> PathBuf {
    PathBuf::from(format!("{}.{}", target.to_string_lossy(), suffix))
}

fn success_marker_path(target: &Path) -> PathBuf {
    sibling_path(target, UPDATE_SUCCESS_MARKER_SUFFIX)
}

fn consume_success_marker(marker: &Path, current_version: &str) -> Option<String> {
    let value = fs::read_to_string(marker).ok()?;
    let _ = fs::remove_file(marker);
    let version = value.trim();
    if Version::parse(version).is_none() || version != current_version {
        diagnose::log(format!(
            "updater: ignored stale or invalid success marker version={}",
            safe_detail(version)
        ));
        return None;
    }
    Some(version.to_string())
}

pub(crate) fn take_successful_update_version() -> Option<String> {
    let target = std::env::current_exe().ok()?;
    let marker = success_marker_path(&target);
    let version = consume_success_marker(&marker, env!("CARGO_PKG_VERSION"));
    if let Some(version) = version.as_ref() {
        diagnose::log(format!("updater: successful update marker consumed version={version}"));
    }
    version
}

fn ps_single_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

fn render_helper(package: &UpdatePackage, old_process_id: u32) -> String {
    let target = ps_single_quote(&package.target.to_string_lossy());
    let prepared_new = ps_single_quote(&package.prepared_new.to_string_lossy());
    let old = ps_single_quote(&sibling_path(&package.target, "old").to_string_lossy());
    let staging = ps_single_quote(&package.staging_dir.to_string_lossy());
    let success_marker = ps_single_quote(&success_marker_path(&package.target).to_string_lossy());
    let version = ps_single_quote(&package.version);
    let working_dir = ps_single_quote(&package.working_dir.to_string_lossy());
    let args = if package.relaunch_args.is_empty() {
        "@()".to_string()
    } else {
        format!(
            "@({})",
            package
                .relaunch_args
                .iter()
                .map(|arg| ps_single_quote(arg))
                .collect::<Vec<_>>()
                .join(", ")
        )
    };

    format!(
        r#"Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OldProcessId = {old_process_id}
$Target = {target}
$New = {prepared_new}
$Old = {old}
$Staging = {staging}
$SuccessMarker = {success_marker}
$Version = {version}
$WorkingDirectory = {working_dir}
$RelaunchArgs = {args}
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexUsage'
$Deadline = (Get-Date).AddSeconds({helper_wait})

while (Get-Process -Id $OldProcessId -ErrorAction SilentlyContinue) {{
    if ((Get-Date) -ge $Deadline) {{ exit 10 }}
    Start-Sleep -Milliseconds 200
}}

$MovedOld = $false
$InstalledNew = $false
try {{
    Remove-Item -LiteralPath $SuccessMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Old -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {{
        throw 'Current executable disappeared before replacement.'
    }}
    if (-not (Test-Path -LiteralPath $New -PathType Leaf)) {{
        throw 'Prepared update executable is missing.'
    }}

    Move-Item -LiteralPath $Target -Destination $Old -Force
    $MovedOld = $true
    Move-Item -LiteralPath $New -Destination $Target -Force
    $InstalledNew = $true

    try {{
        if (Test-Path -LiteralPath $UninstallKey) {{
            $Meta = Get-ItemProperty -LiteralPath $UninstallKey -ErrorAction Stop
            $TargetFull = [IO.Path]::GetFullPath($Target)
            $MatchesTarget = $false
            if ($Meta.DisplayIcon) {{
                $IconPath = ([string]$Meta.DisplayIcon).Split(',')[0].Trim().Trim('"')
                if ($IconPath) {{
                    $MatchesTarget = ([IO.Path]::GetFullPath($IconPath) -eq $TargetFull)
                }}
            }}
            if (-not $MatchesTarget -and $Meta.InstallLocation) {{
                $InstalledPath = Join-Path ([string]$Meta.InstallLocation) 'codex-usage.exe'
                $MatchesTarget = ([IO.Path]::GetFullPath($InstalledPath) -eq $TargetFull)
            }}
            if ($MatchesTarget) {{
                Set-ItemProperty -LiteralPath $UninstallKey -Name DisplayVersion -Value $Version
            }}
        }}
    }} catch {{
        # Registry metadata is best-effort and must not block a valid portable update.
    }}

    Set-Content -LiteralPath $SuccessMarker -Value $Version -Encoding ascii

    try {{
        if ($RelaunchArgs.Count -gt 0) {{
            Start-Process -FilePath $Target -ArgumentList $RelaunchArgs -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }} else {{
            Start-Process -FilePath $Target -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }}
    }} catch {{
        Remove-Item -LiteralPath $SuccessMarker -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Old -PathType Leaf) {{
            Move-Item -LiteralPath $Old -Destination $Target -Force
            $MovedOld = $false
        }}
        throw
    }}

    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $Old -Force -ErrorAction SilentlyContinue
    $MovedOld = $false
}} catch {{
    Remove-Item -LiteralPath $SuccessMarker -Force -ErrorAction SilentlyContinue
    if ($InstalledNew -and (Test-Path -LiteralPath $Target -PathType Leaf)) {{
        Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    }}
    if ($MovedOld -and (Test-Path -LiteralPath $Old -PathType Leaf)) {{
        Move-Item -LiteralPath $Old -Destination $Target -Force -ErrorAction SilentlyContinue
    }}
    exit 11
}} finally {{
    Remove-Item -LiteralPath $New -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
}}
"#,
        helper_wait = HELPER_WAIT_SECS
    )
}

fn launch_prepared_update(package: UpdatePackage) -> Result<(), UpdateError> {
    let helper_path = package.staging_dir.join("updater.ps1");
    let helper = render_helper(&package, std::process::id());
    fs::write(&helper_path, helper).map_err(|error| {
        diagnose::log_error("updater: unable to write replacement helper", error);
        cleanup_failed_package(&package);
        UpdateError::HelperLaunchFailed
    })?;

    match spawn_hidden_powershell(&helper_path) {
        Ok(_) => {
            diagnose::log("updater: replacement helper launched; application will restart");
            Ok(())
        },
        Err(error) => {
            let detail = format!("unable to launch replacement helper: {}", safe_detail(&error));
            set_error_detail(detail.clone());
            diagnose::log(format!("updater: {detail}"));
            cleanup_failed_package(&package);
            Err(UpdateError::HelperLaunchFailed)
        }
    }
}

fn spawn_hidden_powershell(script_path: &Path) -> io::Result<Child> {
    let mut command = Command::new("powershell.exe");
    command.args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    ]);
    command.arg(script_path);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    command.spawn()
}

fn cleanup_failed_package(package: &UpdatePackage) {
    let _ = fs::remove_file(&package.prepared_new);
    let _ = fs::remove_dir_all(&package.staging_dir);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn success_marker_is_consumed_only_for_current_version() {
        let root = unique_staging_dir();
        fs::create_dir_all(&root).unwrap();
        let target = root.join("codex-usage.exe");
        let marker = success_marker_path(&target);
        fs::write(&marker, "1.2.3\n").unwrap();
        assert_eq!(
            consume_success_marker(&marker, "1.2.3"),
            Some("1.2.3".to_string())
        );
        assert!(!marker.exists());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn stale_success_marker_is_removed_without_notification() {
        let root = unique_staging_dir();
        fs::create_dir_all(&root).unwrap();
        let target = root.join("codex-usage.exe");
        let marker = success_marker_path(&target);
        fs::write(&marker, "9.9.9").unwrap();
        assert_eq!(consume_success_marker(&marker, "1.2.3"), None);
        assert!(!marker.exists());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn numeric_version_order_handles_two_digit_patch() {
        assert!(Version::parse("1.0.10").unwrap() > Version::parse("1.0.9").unwrap());
    }

    #[test]
    fn equal_version_is_not_newer() {
        assert_eq!(Version::parse("1.0.2"), Version::parse("1.0.2"));
    }


    #[test]
    fn release_redirect_accepts_absolute_and_relative_fork_tags() {
        let (absolute, text) = parse_release_redirect(
            "https://github.com/walle-2017/codex-usage-monitor/releases/tag/v1.0.10",
        )
        .unwrap();
        assert_eq!(absolute, Version::parse("1.0.10").unwrap());
        assert_eq!(text, "1.0.10");

        let (relative, text) = parse_release_redirect(
            "/walle-2017/codex-usage-monitor/releases/tag/v1.0.3",
        )
        .unwrap();
        assert_eq!(relative, Version::parse("1.0.3").unwrap());
        assert_eq!(text, "1.0.3");
    }

    #[test]
    fn release_redirect_rejects_other_repo_and_prerelease_tags() {
        assert_eq!(
            parse_release_redirect(
                "https://github.com/other-owner/codex-usage-monitor/releases/tag/v9.9.9"
            )
            .unwrap_err(),
            UpdateError::InvalidRelease
        );
        assert_eq!(
            parse_release_redirect(
                "https://github.com/walle-2017/codex-usage-monitor/releases/tag/v1.0.3-beta.1"
            )
            .unwrap_err(),
            UpdateError::InvalidRelease
        );
    }

    #[test]
    fn release_update_builds_exact_fork_asset_urls() {
        let update = release_update_for_version("1.0.3");
        assert_eq!(update.version, "1.0.3");
        assert_eq!(
            update.executable_url,
            "https://github.com/walle-2017/codex-usage-monitor/releases/download/v1.0.3/codex-usage.exe"
        );
        assert_eq!(
            update.checksum_url,
            "https://github.com/walle-2017/codex-usage-monitor/releases/download/v1.0.3/codex-usage.exe.sha256"
        );
    }

    #[test]
    fn json_http_error_extracts_message_without_preview() {
        let (message, preview) = diagnostic_body_summary(
            Some("application/json; charset=utf-8"),
            r#"{"message":"API rate limit exceeded"}"#,
        );
        assert_eq!(message.as_deref(), Some("API rate limit exceeded"));
        assert!(preview.is_none());
    }

    #[test]
    fn non_json_http_error_keeps_bounded_sanitized_preview() {
        let (message, preview) = diagnostic_body_summary(
            Some("text/html"),
            "proxy denied https://user:secret@example.com/request",
        );
        assert!(message.is_none());
        let preview = preview.expect("preview");
        assert!(preview.contains("<redacted>@example.com"));
        assert!(!preview.contains("secret"));
    }

    #[test]
    fn malformed_version_is_rejected() {
        assert!(Version::parse("1.0").is_none());
        assert!(Version::parse("1.0.2.1").is_none());
        assert!(Version::parse("1.0.x").is_none());
    }

    #[test]
    fn checksum_parser_accepts_standard_release_line() {
        let hash = parse_sha256(
            "33a2e08a6d7bc3f42bdf1de2a9a1c6cd82ff6d891a80e274e6951335d5eda428  codex-usage.exe",
        )
        .unwrap();
        assert_eq!(
            hash,
            "33a2e08a6d7bc3f42bdf1de2a9a1c6cd82ff6d891a80e274e6951335d5eda428"
        );
    }

    #[test]
    fn checksum_parser_rejects_invalid_or_ambiguous_text() {
        assert_eq!(parse_sha256("abc").unwrap_err(), UpdateError::InvalidChecksum);
        let two = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        assert_eq!(parse_sha256(two).unwrap_err(), UpdateError::InvalidChecksum);
    }

    #[test]
    fn sha256_verification_detects_mismatch() {
        let path = unique_staging_dir().with_extension("hash-test");
        fs::write(&path, b"codex-usage").unwrap();
        let actual = sha256_file(&path).unwrap();
        assert!(verify_sha256(&path, &actual).is_ok());
        assert_eq!(
            verify_sha256(
                &path,
                "0000000000000000000000000000000000000000000000000000000000000000"
            )
            .unwrap_err(),
            UpdateError::ChecksumMismatch
        );
        let _ = fs::remove_file(path);
    }

    #[test]
    fn powershell_quote_doubles_single_quotes() {
        assert_eq!(ps_single_quote("C:\\it's\\app.exe"), "'C:\\it''s\\app.exe'");
    }

    #[test]
    fn helper_contains_wait_rollback_registry_and_relaunch_steps() {
        let package = UpdatePackage {
            version: "1.0.3".to_string(),
            staging_dir: PathBuf::from(r"C:\Temp\codex-update"),
            target: PathBuf::from(r"C:\Tools\codex-usage.exe"),
            prepared_new: PathBuf::from(r"C:\Tools\codex-usage.exe.new"),
            working_dir: PathBuf::from(r"C:\Tools"),
            relaunch_args: vec!["--diagnose".to_string()],
        };
        let script = render_helper(&package, 1234);
        assert!(script.contains("Get-Process -Id $OldProcessId"));
        assert!(script.contains(".old"));
        assert!(script.contains("Move-Item"));
        assert!(script.contains("DisplayVersion"));
        assert!(script.contains("Start-Process"));
        assert!(script.contains("1234"));
        assert!(script.contains("--diagnose"));
    }
}
