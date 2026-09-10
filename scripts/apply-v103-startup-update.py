from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8", newline="\n")


def replace_exact(text, old, new, label):
    if old not in text:
        raise SystemExit(f"missing expected text for {label}")
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one match for {label}, found {text.count(old)}")
    return text.replace(old, new, 1)


def replace_regex(text, pattern, replacement, label, flags=re.S):
    text2, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"expected exactly one regex match for {label}, found {count}")
    return text2


# --- src/main.rs: diagnostics are opt-in via --diagnose ---
main = read("src/main.rs")
old_main = '''fn main() {
    let executable = std::env::current_exe()
        .map(|value| value.display().to_string())
        .unwrap_or_else(|error| format!("unavailable:{error}"));
    if let Ok(path) = diagnose::init() {
        diagnose::log(format!(
            "version={} executable={} log_path={}",
            env!("CARGO_PKG_VERSION"),
            executable,
            path.display()
        ));
    }
    system_proxy::apply_windows_system_proxy_env();
    diagnose::log("entering window::run");
    window::run();
}
'''
new_main = '''fn main() {
    let diagnose_enabled = std::env::args().skip(1).any(|arg| arg == "--diagnose");
    if diagnose_enabled {
        let executable = std::env::current_exe()
            .map(|value| value.display().to_string())
            .unwrap_or_else(|error| format!("unavailable:{error}"));
        if let Ok(path) = diagnose::init() {
            diagnose::log(format!(
                "version={} executable={} log_path={}",
                env!("CARGO_PKG_VERSION"),
                executable,
                path.display()
            ));
        }
    }
    system_proxy::apply_windows_system_proxy_env();
    diagnose::log("entering window::run");
    window::run();
}
'''
main = replace_exact(main, old_main, new_main, "main diagnose gate")
write("src/main.rs", main)


# --- src/updater.rs: shared release discovery + startup check-only result ---
updater = read("src/updater.rs")
updater = replace_exact(
    updater,
    "pub(crate) const WM_APP_UPDATE_RESULT: u32 = WM_APP + 21;\npub(crate) const WM_APP_UPDATE_PROGRESS: u32 = WM_APP + 22;",
    "pub(crate) const WM_APP_UPDATE_RESULT: u32 = WM_APP + 21;\npub(crate) const WM_APP_UPDATE_PROGRESS: u32 = WM_APP + 22;\npub(crate) const WM_APP_STARTUP_UPDATE_RESULT: u32 = WM_APP + 23;",
    "startup update window message",
)
updater = replace_exact(
    updater,
    "static UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);\nstatic UPDATE_PROGRESS: Mutex<VecDeque<UpdateProgress>> = Mutex::new(VecDeque::new());",
    "static UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);\nstatic UPDATE_PROGRESS: Mutex<VecDeque<UpdateProgress>> = Mutex::new(VecDeque::new());\nstatic STARTUP_UPDATE_RESULT: Mutex<Option<StartupUpdateCheckResult>> = Mutex::new(None);\nstatic STARTUP_CHECK_STARTED: AtomicBool = AtomicBool::new(false);",
    "startup result storage",
)
updater = replace_exact(
    updater,
    '''#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateProgress {
    Checking,
    Updating { version: String },
}
''',
    '''#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum UpdateProgress {
    Checking,
    Updating { version: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum StartupUpdateCheckResult {
    Current,
    Available { version: String },
    Failed,
}
''',
    "startup result enum",
)
updater = replace_exact(
    updater,
    '''fn lock_progress() -> MutexGuard<'static, VecDeque<UpdateProgress>> {
    UPDATE_PROGRESS
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}
''',
    '''fn lock_progress() -> MutexGuard<'static, VecDeque<UpdateProgress>> {
    UPDATE_PROGRESS
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}

fn lock_startup_result() -> MutexGuard<'static, Option<StartupUpdateCheckResult>> {
    STARTUP_UPDATE_RESULT
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}
''',
    "startup result lock",
)
updater = replace_exact(
    updater,
    '''pub(crate) fn take_progress() -> Option<UpdateProgress> {
    lock_progress().pop_front()
}

pub(crate) fn start_update(hwnd: HWND) -> bool {
''',
    '''pub(crate) fn take_progress() -> Option<UpdateProgress> {
    lock_progress().pop_front()
}

pub(crate) fn start_startup_update_check(hwnd: HWND, after_update_success: bool) {
    if STARTUP_CHECK_STARTED.swap(true, Ordering::AcqRel) {
        return;
    }

    let hwnd_raw = hwnd.0 as isize;
    std::thread::spawn(move || {
        if after_update_success {
            std::thread::sleep(Duration::from_millis(1_500));
        }
        diagnose::log("updater: startup release check started");
        let result = match discover_release_update() {
            Ok((_current, Some(update))) => StartupUpdateCheckResult::Available {
                version: update.version,
            },
            Ok((_current, None)) => StartupUpdateCheckResult::Current,
            Err(error) => {
                diagnose::log(format!("updater: startup release check failed error={error:?}"));
                StartupUpdateCheckResult::Failed
            }
        };
        *lock_startup_result() = Some(result);
        let target_hwnd = HWND(hwnd_raw as *mut _);
        unsafe {
            let _ = PostMessageW(
                target_hwnd,
                WM_APP_STARTUP_UPDATE_RESULT,
                WPARAM(0),
                LPARAM(0),
            );
        }
    });
}

pub(crate) fn take_startup_update_result() -> Option<StartupUpdateCheckResult> {
    lock_startup_result().take()
}

pub(crate) fn start_update(hwnd: HWND) -> bool {
''',
    "startup check API",
)

new_discovery_and_prepare = r'''fn discover_release_update() -> Result<(String, Option<ReleaseUpdate>), UpdateError> {
    let current_text = env!("CARGO_PKG_VERSION");
    diagnose::log(format!(
        "updater: checking latest Release current={current_text}"
    ));
    let current = Version::parse(current_text).ok_or(UpdateError::InvalidRelease)?;

    let discovery_agent = build_discovery_agent()?;
    let release_response = request_builder(&discovery_agent, LATEST_RELEASE_URL)
        .call()
        .map_err(|error| {
            let detail = format!(
                "GitHub latest Release redirect request failed: {}",
                ureq_error_detail(error)
            );
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
        return Ok((current_text.to_string(), None));
    }

    Ok((
        current_text.to_string(),
        Some(release_update_for_version(&latest_text)),
    ))
}

fn prepare_update(hwnd_raw: isize) -> Result<UpdateOutcome, UpdateError> {
    let (current_version, update) = discover_release_update()?;
    let Some(update) = update else {
        return Ok(UpdateOutcome::Current {
            version: current_version,
        });
    };

    UPDATE_STAGE.store(UPDATE_STAGE_UPDATING, Ordering::Release);
    post_progress(
        hwnd_raw,
        UpdateProgress::Updating {
            version: update.version.clone(),
        },
    );
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

fn prepare_downloaded_package'''
updater = replace_regex(
    updater,
    r'fn prepare_update\(hwnd_raw: isize\) -> Result<UpdateOutcome, UpdateError> \{.*?\n\}\n\nfn prepare_downloaded_package',
    new_discovery_and_prepare,
    "shared release discovery",
)
write("src/updater.rs", updater)


# --- src/window.rs: order, startup result handling, and menu version hint ---
window = read("src/window.rs")
window = replace_exact(
    window,
    "    last_poll_ok: bool,\n\n    taskbar_index: usize,",
    "    last_poll_ok: bool,\n    available_update_version: Option<String>,\n\n    taskbar_index: usize,",
    "AppState available version",
)
window = replace_exact(
    window,
    "                last_poll_ok: false,\n                taskbar_index: settings.taskbar_index,",
    "                last_poll_ok: false,\n                available_update_version: None,\n                taskbar_index: settings.taskbar_index,",
    "AppState available version init",
)
old_success = '''        if let Some(version) = updater::successful_update_version_from_args() {
            let strings = language.strings();
            let message = format!("{} v{}", strings.update_success, version);
            tray_icon::notify_info(
                hwnd,
                tray_icon::TrayIconKind::Codex,
                strings.update_title,
                &message,
            );
        }
'''
new_success = '''        let update_success_notified = if let Some(version) = updater::successful_update_version_from_args() {
            let strings = language.strings();
            let message = format!("{} v{}", strings.update_success, version);
            tray_icon::notify_info(
                hwnd,
                tray_icon::TrayIconKind::Codex,
                strings.update_title,
                &message,
            );
            true
        } else {
            false
        };
        updater::start_startup_update_check(hwnd, update_success_notified);
'''
window = replace_exact(window, old_success, new_success, "startup check ordering")
startup_handler = '''        updater::WM_APP_STARTUP_UPDATE_RESULT => {
            if let Some(result) = updater::take_startup_update_result() {
                match result {
                    updater::StartupUpdateCheckResult::Available { version } => {
                        let strings = {
                            let mut state = lock_state();
                            match state.as_mut() {
                                Some(s) => {
                                    s.available_update_version = Some(version.clone());
                                    s.language.strings()
                                }
                                None => LanguageId::English.strings(),
                            }
                        };
                        tray_icon::clear_notification(hwnd);
                        let message = format!("{} v{}", strings.update_available, version);
                        tray_icon::notify_info(
                            hwnd,
                            tray_icon::TrayIconKind::Codex,
                            strings.update_title,
                            &message,
                        );
                    }
                    updater::StartupUpdateCheckResult::Current => {
                        let mut state = lock_state();
                        if let Some(s) = state.as_mut() {
                            s.available_update_version = None;
                        }
                    }
                    updater::StartupUpdateCheckResult::Failed => {
                        diagnose::log("startup update check ended without a user notification");
                    }
                }
            }
            LRESULT(0)
        }
'''
window = replace_exact(
    window,
    "        updater::WM_APP_UPDATE_PROGRESS => {\n",
    startup_handler + "        updater::WM_APP_UPDATE_PROGRESS => {\n",
    "startup update result handler",
)
window = replace_exact(
    window,
    "            alert_threshold_percent,\n            appearance_preset,\n        ) = {",
    "            alert_threshold_percent,\n            appearance_preset,\n            available_update_version,\n        ) = {",
    "menu tuple declaration",
)
window = replace_exact(
    window,
    "                    s.alert_threshold_percent,\n                    s.appearance_preset,\n                ),",
    "                    s.alert_threshold_percent,\n                    s.appearance_preset,\n                    s.available_update_version.clone(),\n                ),",
    "menu tuple state value",
)
window = replace_exact(
    window,
    "                    0,\n                    AppearancePreset::Compact,\n                ),",
    "                    0,\n                    AppearancePreset::Compact,\n                    None,\n                ),",
    "menu tuple fallback value",
)
window = replace_exact(
    window,
    '''        let version_label = native_interop::wide_str(&format!("v{}", env!("CARGO_PKG_VERSION")));
''',
    '''        let version_label_text = match available_update_version.as_deref() {
            Some(latest) => format!("v{} --> v{}", env!("CARGO_PKG_VERSION"), latest),
            None => format!("v{}", env!("CARGO_PKG_VERSION")),
        };
        let version_label = native_interop::wide_str(&version_label_text);
''',
    "version menu upgrade hint",
)
write("src/window.rs", window)


# --- localization: new startup-availability message ---
loc_mod = read("src/localization/mod.rs")
loc_mod = replace_exact(
    loc_mod,
    "    pub update_current: &'static str,\n    pub update_check_failed: &'static str,",
    "    pub update_current: &'static str,\n    pub update_available: &'static str,\n    pub update_check_failed: &'static str,",
    "localization update_available field",
)
write("src/localization/mod.rs", loc_mod)

translations = {
    "english.rs": "New version available",
    "dutch.rs": "Nieuwe versie beschikbaar",
    "spanish.rs": "Nueva versión disponible",
    "french.rs": "Nouvelle version disponible",
    "german.rs": "Neue Version verfügbar",
    "japanese.rs": "新しいバージョンがあります",
    "korean.rs": "새 버전 사용 가능",
    "simplified_chinese.rs": "发现新版本",
    "traditional_chinese.rs": "發現新版本",
    "russian.rs": "Доступна новая версия",
    "portuguese_brazil.rs": "Nova versão disponível",
}
for filename, value in translations.items():
    path = f"src/localization/{filename}"
    text = read(path)
    marker = re.search(r'(?m)^(\s*update_current:\s*".*",\n)', text)
    if not marker:
        raise SystemExit(f"missing update_current in {path}")
    insert_at = marker.end()
    text = text[:insert_at] + f'    update_available: "{value}",\n' + text[insert_at:]
    write(path, text)


# --- regression scripts ---
runtime = read("scripts/assert-runtime-log.ps1")
runtime = replace_exact(
    runtime,
    "Assert-Match $main 'diagnose::init\\(\\)' 'Logging must initialize during normal startup.'\nif ($main -match 'if\\s+diagnose_enabled\\s*\\{\\s*match\\s+diagnose::init') {\n    throw 'Runtime logging must not require --diagnose.'\n}\n",
    "Assert-Match $main '\"--diagnose\"' 'Runtime logging must require the --diagnose flag.'\nAssert-Match $main 'diagnose_enabled' 'main.rs must explicitly gate runtime logging.'\nAssert-Match $main 'if\\s+diagnose_enabled\\s*\\{[\\s\\S]*diagnose::init\\(\\)' 'diagnose::init() must run only inside the --diagnose gate.'\nif ($main -match '(?m)^\\s*if\\s+let\\s+Ok\\(path\\)\\s*=\\s*diagnose::init\\(\\)') {\n    throw 'diagnose::init() must not run unconditionally during normal startup.'\n}\n",
    "runtime log assertion",
)
runtime = runtime.replace(
    "PASS: persistent runtime logging contract is present and avoids credential material.",
    "PASS: --diagnose-gated runtime logging contract is present and avoids credential material.",
)
write("scripts/assert-runtime-log.ps1", runtime)

auto_assert = read("scripts/assert-auto-update.ps1")
auto_assert = replace_exact(
    auto_assert,
    "foreach ($field in @('update_checking','update_downloading','update_success')) {",
    "foreach ($field in @('update_checking','update_downloading','update_success','update_available')) {",
    "auto-update localization assertion",
)
write("scripts/assert-auto-update.ps1", auto_assert)


# --- user-facing docs ---
readme = read("README.md")
readme = replace_exact(
    readme,
    "- Manual in-app update from this fork's latest stable Release, with SHA256 verification, rollback, restart, and concise Windows notifications",
    "- One startup Release check that only notifies about a newer stable version, plus manual in-app update with SHA256 verification, rollback, restart, and concise Windows notifications",
    "README feature startup update",
)
readme = replace_exact(
    readme,
    "Runtime logging is enabled automatically. `codex-usage.log` is written beside the running executable and is retained across restarts. At 5 MB it rotates to `codex-usage.log.1`, keeping only the current and previous log.",
    "Runtime logging is opt-in. Start Codex Usage with `--diagnose` to create `codex-usage.log` beside the running executable. The log is retained across diagnostic restarts and rotates at 5 MB to `codex-usage.log.1`, keeping only the current and previous log. Normal startup does not create or append the diagnostic log.",
    "README diagnostics",
)
readme = replace_exact(
    readme,
    "The version row in **Settings** is clickable. Clicking it checks only the latest stable Release of `walle-2017/codex-usage-monitor`. Latest-version discovery uses the fork's GitHub Release redirect rather than the unauthenticated GitHub REST API, avoiding the shared-IP REST rate limit encountered with public proxy exits.",
    "Codex Usage performs one check-only Release lookup after startup. If a higher stable version exists, it shows a concise notification and the **Settings** version row becomes `vCURRENT --> vLATEST`. The startup check never downloads or installs an update. Clicking the version row performs the existing manual update flow. All discovery is limited to the latest stable Release of `walle-2017/codex-usage-monitor` and uses the fork's GitHub Release redirect rather than the unauthenticated GitHub REST API.",
    "README version behavior",
)
readme = replace_exact(
    readme,
    "If a newer version exists, Codex Usage downloads `codex-usage.exe` and `codex-usage.exe.sha256`, verifies SHA256, safely replaces the currently running installed or portable executable, and restarts automatically. The updater keeps a rollback copy until replacement succeeds and never downloads or executes a Release `install.ps1`. There is no startup or periodic background update check.",
    "When the user clicks the version row and a newer version exists, Codex Usage downloads `codex-usage.exe` and `codex-usage.exe.sha256`, verifies SHA256, safely replaces the currently running installed or portable executable, and restarts automatically. The updater keeps a rollback copy until replacement succeeds and never downloads or executes a Release `install.ps1`. There is no periodic background update check; the automatic check runs once per application startup and is notification-only.",
    "README no periodic update",
)
write("README.md", readme)

readme_zh = read("README.zh-CN.md")
readme_zh = replace_exact(
    readme_zh,
    "- 支持从当前 Fork 最新稳定 Release 手动触发应用内更新，包含 SHA256 校验、回滚、自动重启和精简 Windows 通知",
    "- 软件启动后执行一次仅检查的稳定 Release 更新检测；发现更高版本时通知用户，并支持手动触发 SHA256 校验、回滚和自动重启更新",
    "README.zh feature startup update",
)
readme_zh = replace_exact(
    readme_zh,
    "运行日志默认启用，无需 `--diagnose`。`codex-usage.log` 写在当前 `codex-usage.exe` 同目录，并跨正常重启追加保留；达到 5 MB 时轮转为 `codex-usage.log.1`，只保留当前和上一份日志。",
    "运行日志改为按需启用。只有使用 `--diagnose` 启动 Codex Usage 时，才会在当前 `codex-usage.exe` 同目录创建或追加 `codex-usage.log`；达到 5 MB 时轮转为 `codex-usage.log.1`，只保留当前和上一份日志。普通启动不会创建或写入诊断日志。",
    "README.zh diagnostics",
)
readme_zh = replace_exact(
    readme_zh,
    "**设置**中的版本号可点击。点击后只检查 `walle-2017/codex-usage-monitor` 当前 Fork 的最新稳定 Release。最新版本发现通过 Fork 的 GitHub Release 重定向完成，不依赖 GitHub 未认证 REST API，因此不会受到共享代理出口常见的 REST API 60 次/小时/IP 配额影响。",
    "软件每次启动后会自动执行一次只读的 Release 更新检查。若发现更高的稳定版本，会先显示一条精简通知，并把**设置**中的版本号显示为 `v当前版本 --> v最新版本`；启动检查本身不会下载或安装更新。点击该版本号后才进入现有手动更新流程。版本发现仍只访问 `walle-2017/codex-usage-monitor` 当前 Fork 的最新稳定 Release，并通过 GitHub Release 重定向完成，不依赖 GitHub 未认证 REST API。",
    "README.zh version behavior",
)
readme_zh = replace_exact(
    readme_zh,
    "发现新版本时，程序会下载 `codex-usage.exe` 与 `codex-usage.exe.sha256`，完成 SHA256 校验后安全替换当前安装版或便携版程序并自动重启。更新器在替换成功前保留回滚副本，也不会下载或执行 Release 中的 `install.ps1`。当前版本不会在启动时或后台定时检查更新。",
    "用户点击版本号并确认存在更高版本后，程序会下载 `codex-usage.exe` 与 `codex-usage.exe.sha256`，完成 SHA256 校验后安全替换当前安装版或便携版程序并自动重启。更新器在替换成功前保留回滚副本，也不会下载或执行 Release 中的 `install.ps1`。不会执行周期性后台更新检查；自动检查仅在每次软件启动后执行一次，并且只通知、不自动下载安装。",
    "README.zh no periodic update",
)
write("README.zh-CN.md", readme_zh)

installation = read("docs/installation.md")
installation = replace_exact(
    installation,
    "Both installed and portable writable copies support the manually initiated in-app updater. Open **Settings** and click the displayed version. Codex Usage checks only the latest stable Release from `walle-2017/codex-usage-monitor`, downloads `codex-usage.exe` plus `codex-usage.exe.sha256`, verifies SHA256, stages the replacement beside the running executable, and restarts automatically.",
    "Both installed and portable copies perform one check-only lookup of the latest stable Release from `walle-2017/codex-usage-monitor` after startup. If a higher version exists, Codex Usage notifies the user and the **Settings** version row displays `vCURRENT --> vLATEST`. No file is downloaded by the startup check. Clicking the version row starts the manual updater, which downloads `codex-usage.exe` plus `codex-usage.exe.sha256`, verifies SHA256, stages the replacement beside the running executable, and restarts automatically.",
    "installation startup update",
)
installation = replace_exact(
    installation,
    "The version item is user-triggered only; there is no startup or periodic background update check. Latest-version discovery uses the fork's GitHub `releases/latest` redirect and strictly accepts only this repository's stable numeric `vX.Y.Z` tag path.",
    "Latest-version discovery runs once after application startup and again when the user clicks the version row. The startup pass is check-only and silent when current or failed; it only notifies when a higher stable version is found. There is no periodic background update check. Discovery uses the fork's GitHub `releases/latest` redirect and strictly accepts only this repository's stable numeric `vX.Y.Z` tag path.",
    "installation update behavior",
)
write("docs/installation.md", installation)

trouble = read("docs/troubleshooting.md")
trouble = replace_exact(
    trouble,
    "Runtime logging is enabled automatically. `codex-usage.log` is created in the same directory as the running `codex-usage.exe`; no `--diagnose` argument is required.",
    "Runtime logging is disabled during normal startup. Start the executable with `--diagnose` to create or append `codex-usage.log` in the same directory as the running `codex-usage.exe`.",
    "troubleshooting diagnostics",
)
trouble = replace_exact(
    trouble,
    "There is no startup or periodic background update check.",
    "A check-only update lookup runs once after startup. It is silent when the current version is latest or the lookup fails, and only notifies when a higher stable version is found. There is no periodic background update check.",
    "troubleshooting startup update",
)
trouble = replace_exact(
    trouble,
    "The running version is left unchanged when the Release check, download, SHA256 verification, target-directory write preflight, or updater launch fails. The notification includes a concise technical reason; the full diagnostic sequence is written to `codex-usage.log` beside the executable.",
    "The running version is left unchanged when the Release check, download, SHA256 verification, target-directory write preflight, or updater launch fails. Manual update failures include a concise technical reason. For the full diagnostic sequence, restart Codex Usage with `--diagnose`; normal startup does not write `codex-usage.log`.",
    "troubleshooting update failure log",
)
write("docs/troubleshooting.md", trouble)

fork = read("README-FORK.md")
fork = replace_exact(
    fork,
    "- **设置**中的版本号改为可点击，用户点击后手动检查更新；不会在启动时或后台定时检查。",
    "- 软件每次启动后自动执行一次只读的稳定 Release 检查；仅在发现更高版本时通知用户，不自动下载或安装。\n- **设置**中的版本号保持可点击；发现更高版本后显示 `v当前版本 --> v最新版本`，点击后进入现有手动更新流程。不会执行周期性后台更新检查。",
    "README-FORK startup update",
)
fork = replace_exact(
    fork,
    "- 正常运行始终在 EXE 同目录追加写入 `codex-usage.log`；达到 5 MB 后轮转为 `codex-usage.log.1`，只保留一份历史日志。",
    "- 仅使用 `--diagnose` 启动时才在 EXE 同目录创建或追加 `codex-usage.log`；达到 5 MB 后轮转为 `codex-usage.log.1`，只保留一份历史日志。普通启动不写诊断日志。",
    "README-FORK diagnose log",
)
fork = replace_exact(
    fork,
    "不得把更新源重新指向 upstream Release，不得为更新要求 GitHub PAT，不得自动下载并信任 Release `install.ps1`，不得在启动时或定时后台检查更新。",
    "不得把更新源重新指向 upstream Release，不得为更新要求 GitHub PAT，不得自动下载并信任 Release `install.ps1`。允许且只允许每次软件启动后执行一次只读更新检查；该检查不得自动下载或安装，也不得扩展为周期性后台检查。",
    "README-FORK update boundary",
)
fork = replace_exact(
    fork,
    "3. 应用内更新源必须继续固定到 `walle-2017/codex-usage-monitor` 的稳定 Release，不得改为 upstream，也不得恢复后台自动检查。",
    "3. 应用内更新源必须继续固定到 `walle-2017/codex-usage-monitor` 的稳定 Release；保留一次启动时只读检查，不得改为 upstream，也不得增加周期性后台检查。",
    "README-FORK sync boundary",
)
write("README-FORK.md", fork)

final_docs = read("scripts/assert-final-docs.ps1")
final_docs = replace_exact(
    final_docs,
    "if (-not $Readme.Contains('Version and in-app updates') -or -not $ReadmeZh.Contains('版本与应用内更新')) {\n    throw 'Primary READMEs must document the clickable in-app update flow.'\n}\n",
    "if (-not $Readme.Contains('vCURRENT --> vLATEST') -or -not $ReadmeZh.Contains('v当前版本 --> v最新版本')) {\n    throw 'Primary READMEs must document the startup-discovered version menu hint.'\n}\nif (-not $Joined.Contains('--diagnose')) {\n    throw 'User-facing docs must document opt-in diagnostic logging.'\n}\n",
    "final docs startup update assertion",
)
final_docs = final_docs.replace(
    "PASS: user-facing documentation matches the Codex-only v1.0.3 product state with secure manual in-app updates.",
    "PASS: user-facing documentation matches the Codex-only v1.0.3 product state with startup discovery and manual in-app updates.",
)
write("scripts/assert-final-docs.ps1", final_docs)

print("Applied v1.0.3 startup update discovery and --diagnose logging changes.")
