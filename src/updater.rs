use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use sha2::{Digest, Sha256};
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{PostMessageW, WM_APP};

use crate::diagnose;

const LATEST_RELEASE_URL: &str =
    "https://api.github.com/repos/walle-2017/codex-usage-monitor/releases/latest";
const RELEASE_ASSET_PREFIX: &str =
    "https://github.com/walle-2017/codex-usage-monitor/releases/download/";
const EXE_ASSET_NAME: &str = "codex-usage.exe";
const CHECKSUM_ASSET_NAME: &str = "codex-usage.exe.sha256";
const UPDATE_TIMEOUT_SECS: u64 = 30;
const HELPER_WAIT_SECS: u64 = 60;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub(crate) const WM_APP_UPDATE_RESULT: u32 = WM_APP + 21;

static UPDATE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);
static UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateError {
    CheckFailed,
    InvalidRelease,
    MissingAsset,
    DownloadFailed,
    InvalidChecksum,
    ChecksumMismatch,
    TargetNotWritable,
    HelperLaunchFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateUiResult {
    Current { version: String },
    Failed(UpdateError),
    ReadyToRestart,
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

    fn parse_tag(value: &str) -> Option<Self> {
        Self::parse(value.strip_prefix('v').unwrap_or(value))
    }
}

#[derive(Clone, Debug, Deserialize)]
struct GithubRelease {
    tag_name: String,
    draft: bool,
    prerelease: bool,
    assets: Vec<GithubAsset>,
}

#[derive(Clone, Debug, Deserialize)]
struct GithubAsset {
    name: String,
    browser_download_url: String,
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

fn lock_result() -> MutexGuard<'static, Option<UpdateUiResult>> {
    UPDATE_RESULT.lock().unwrap_or_else(|error| error.into_inner())
}

pub(crate) fn start_update(hwnd: HWND) -> bool {
    if UPDATE_IN_PROGRESS
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return false;
    }

    let hwnd_raw = hwnd.0 as isize;
    std::thread::spawn(move || {
        let ui_result = match prepare_update() {
            Ok(UpdateOutcome::Current { version }) => UpdateUiResult::Current { version },
            Ok(UpdateOutcome::Ready(package)) => match launch_prepared_update(package) {
                Ok(()) => UpdateUiResult::ReadyToRestart,
                Err(error) => UpdateUiResult::Failed(error),
            },
            Err(error) => UpdateUiResult::Failed(error),
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

fn select_release_update(
    release: &GithubRelease,
    current: Version,
) -> Result<Option<ReleaseUpdate>, UpdateError> {
    if release.draft || release.prerelease {
        return Err(UpdateError::InvalidRelease);
    }

    let release_version =
        Version::parse_tag(&release.tag_name).ok_or(UpdateError::InvalidRelease)?;
    if release_version <= current {
        return Ok(None);
    }

    let executable = release
        .assets
        .iter()
        .find(|asset| asset.name == EXE_ASSET_NAME)
        .ok_or(UpdateError::MissingAsset)?;
    let checksum = release
        .assets
        .iter()
        .find(|asset| asset.name == CHECKSUM_ASSET_NAME)
        .ok_or(UpdateError::MissingAsset)?;

    for asset in [executable, checksum] {
        if !asset.browser_download_url.starts_with(RELEASE_ASSET_PREFIX) {
            return Err(UpdateError::InvalidRelease);
        }
    }

    Ok(Some(ReleaseUpdate {
        version: format!(
            "{}.{}.{}",
            release_version.major, release_version.minor, release_version.patch
        ),
        executable_url: executable.browser_download_url.clone(),
        checksum_url: checksum.browser_download_url.clone(),
    }))
}

fn build_agent() -> Result<ureq::Agent, UpdateError> {
    let tls = native_tls::TlsConnector::new().map_err(|error| {
        diagnose::log_error("updater: unable to create TLS connector", error);
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
        .set("Accept", "application/vnd.github+json")
}

fn prepare_update() -> Result<UpdateOutcome, UpdateError> {
    let current_text = env!("CARGO_PKG_VERSION");
    let current = Version::parse(current_text).ok_or(UpdateError::InvalidRelease)?;
    let agent = build_agent()?;

    let release_response = request_builder(&agent, LATEST_RELEASE_URL)
        .call()
        .map_err(|error| {
            diagnose::log_error("updater: latest release request failed", error);
            UpdateError::CheckFailed
        })?;
    let release: GithubRelease = release_response.into_json().map_err(|error| {
        diagnose::log_error("updater: unable to parse release metadata", error);
        UpdateError::InvalidRelease
    })?;

    let Some(update) = select_release_update(&release, current)? else {
        return Ok(UpdateOutcome::Current {
            version: current_text.to_string(),
        });
    };

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

    download_to(agent, &update.executable_url, &staged_exe)?;
    download_to(agent, &update.checksum_url, &checksum_path)?;

    let checksum_text = fs::read_to_string(&checksum_path).map_err(|error| {
        diagnose::log_error("updater: unable to read checksum asset", error);
        UpdateError::InvalidChecksum
    })?;
    let expected = parse_sha256(&checksum_text)?;
    verify_sha256(&staged_exe, &expected)?;

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
        diagnose::log_error("updater: release asset download failed", error);
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
        diagnose::log_error("updater: executable directory is not writable", error);
        UpdateError::TargetNotWritable
    })
}

fn sibling_path(target: &Path, suffix: &str) -> PathBuf {
    PathBuf::from(format!("{}.{}", target.to_string_lossy(), suffix))
}

fn ps_single_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

fn render_helper(package: &UpdatePackage, old_process_id: u32) -> String {
    let target = ps_single_quote(&package.target.to_string_lossy());
    let prepared_new = ps_single_quote(&package.prepared_new.to_string_lossy());
    let old = ps_single_quote(&sibling_path(&package.target, "old").to_string_lossy());
    let staging = ps_single_quote(&package.staging_dir.to_string_lossy());
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

    try {{
        if ($RelaunchArgs.Count -gt 0) {{
            Start-Process -FilePath $Target -ArgumentList $RelaunchArgs -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }} else {{
            Start-Process -FilePath $Target -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }}
    }} catch {{
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
        Ok(_) => Ok(()),
        Err(error) => {
            diagnose::log_error("updater: unable to launch replacement helper", error);
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

    fn release_json(tag: &str, draft: bool, prerelease: bool, assets: &str) -> GithubRelease {
        serde_json::from_str(&format!(
            r#"{{"tag_name":"{tag}","draft":{draft},"prerelease":{prerelease},"assets":[{assets}]}}"#
        ))
        .unwrap()
    }

    fn asset(name: &str, version: &str) -> String {
        format!(
            r#"{{"name":"{name}","browser_download_url":"https://github.com/walle-2017/codex-usage-monitor/releases/download/v{version}/{name}"}}"#
        )
    }

    fn complete_assets(version: &str) -> String {
        format!(
            "{},{}",
            asset(EXE_ASSET_NAME, version),
            asset(CHECKSUM_ASSET_NAME, version)
        )
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
    fn leading_v_is_accepted_for_release_tag() {
        assert_eq!(
            Version::parse_tag("v1.0.3"),
            Some(Version {
                major: 1,
                minor: 0,
                patch: 3
            })
        );
    }

    #[test]
    fn malformed_version_is_rejected() {
        assert!(Version::parse("1.0").is_none());
        assert!(Version::parse("1.0.2.1").is_none());
        assert!(Version::parse("1.0.x").is_none());
    }

    #[test]
    fn prerelease_and_draft_are_rejected() {
        let assets = complete_assets("1.0.3");
        let pre = release_json("v1.0.3", false, true, &assets);
        let draft = release_json("v1.0.3", true, false, &assets);
        let current = Version::parse("1.0.2").unwrap();
        assert_eq!(
            select_release_update(&pre, current).unwrap_err(),
            UpdateError::InvalidRelease
        );
        assert_eq!(
            select_release_update(&draft, current).unwrap_err(),
            UpdateError::InvalidRelease
        );
    }

    #[test]
    fn equal_or_lower_release_does_not_update() {
        let assets = complete_assets("1.0.2");
        let current = Version::parse("1.0.2").unwrap();
        assert!(select_release_update(&release_json("v1.0.2", false, false, &assets), current)
            .unwrap()
            .is_none());
        assert!(select_release_update(&release_json("v1.0.1", false, false, &assets), current)
            .unwrap()
            .is_none());
    }

    #[test]
    fn newer_release_requires_both_exact_assets() {
        let current = Version::parse("1.0.2").unwrap();
        let only_exe = release_json(
            "v1.0.3",
            false,
            false,
            &asset(EXE_ASSET_NAME, "1.0.3"),
        );
        assert_eq!(
            select_release_update(&only_exe, current).unwrap_err(),
            UpdateError::MissingAsset
        );

        let complete = release_json("v1.0.3", false, false, &complete_assets("1.0.3"));
        let selected = select_release_update(&complete, current).unwrap().unwrap();
        assert_eq!(selected.version, "1.0.3");
        assert!(selected.executable_url.ends_with("/codex-usage.exe"));
        assert!(selected.checksum_url.ends_with("/codex-usage.exe.sha256"));
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
