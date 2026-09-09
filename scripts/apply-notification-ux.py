from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, got {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str, flags=0) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected one regex match, got {count}")
    return updated


cargo_path = Path("Cargo.toml")
cargo = cargo_path.read_text(encoding="utf-8")
cargo = replace_once(cargo, 'FileDescription = "Lightweight Codex usage monitor for Windows"', 'FileDescription = "Codex Usage"', "Cargo FileDescription")
cargo_path.write_text(cargo, encoding="utf-8")

tray_path = Path("src/tray_icon.rs")
tray = tray_path.read_text(encoding="utf-8")
tray = replace_once(
    tray,
    "ExtractIconExW, Shell_NotifyIconW, NIF_ICON, NIF_INFO, NIF_MESSAGE, NIF_TIP, NIIF_WARNING,\n",
    "ExtractIconExW, Shell_NotifyIconW, NIF_ICON, NIF_INFO, NIF_MESSAGE, NIF_TIP, NIIF_NONE,\n    NIIF_WARNING,\n",
    "tray imports",
)
tray = replace_once(
    tray,
    '''pub fn notify_balloon(hwnd: HWND, _kind: TrayIconKind, title: &str, message: &str) {
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
''',
    '''pub fn notify_info(hwnd: HWND, kind: TrayIconKind, title: &str, message: &str) {
    notify_balloon(hwnd, kind, title, message, false);
}

pub fn notify_warning(hwnd: HWND, kind: TrayIconKind, title: &str, message: &str) {
    notify_balloon(hwnd, kind, title, message, true);
}

fn notify_balloon(hwnd: HWND, _kind: TrayIconKind, title: &str, message: &str, warning: bool) {
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = APP_TRAY_ICON_ID;
        nid.uFlags = NIF_INFO;
        nid.dwInfoFlags = if warning { NIIF_WARNING } else { NIIF_NONE };
        copy_wide(title, &mut nid.szInfoTitle);
        copy_wide(message, &mut nid.szInfo);
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}

pub fn clear_notification(hwnd: HWND) {
    unsafe {
        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = APP_TRAY_ICON_ID;
        nid.uFlags = NIF_INFO;
        nid.dwInfoFlags = NIIF_NONE;
        copy_wide("", &mut nid.szInfoTitle);
        copy_wide("", &mut nid.szInfo);
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}
''',
    "tray notification API",
)
tray_path.write_text(tray, encoding="utf-8")

updater_path = Path("src/updater.rs")
u = updater_path.read_text(encoding="utf-8")
u = replace_once(u, "use std::sync::atomic::{AtomicBool, Ordering};", "use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};", "AtomicU8 import")
u = replace_once(
    u,
    'const CREATE_NO_WINDOW: u32 = 0x0800_0000;\nconst UPDATE_SUCCESS_MARKER_SUFFIX: &str = "update-success";',
    'const CREATE_NO_WINDOW: u32 = 0x0800_0000;\nconst UPDATE_CHECK_NOTIFY_DELAY_MS: u64 = 800;\nconst UPDATE_SUCCESS_ARG_PREFIX: &str = "--codex-usage-updated-to=";\nconst UPDATE_STAGE_IDLE: u8 = 0;\nconst UPDATE_STAGE_CHECKING: u8 = 1;\nconst UPDATE_STAGE_UPDATING: u8 = 2;',
    "updater constants",
)
u = replace_once(
    u,
    "static UPDATE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);\nstatic UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);",
    "static UPDATE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);\nstatic UPDATE_STAGE: AtomicU8 = AtomicU8::new(UPDATE_STAGE_IDLE);\nstatic UPDATE_SUCCESS_ARG_CONSUMED: AtomicBool = AtomicBool::new(false);\nstatic UPDATE_RESULT: Mutex<Option<UpdateUiResult>> = Mutex::new(None);",
    "updater statics",
)
u = replace_once(
    u,
    '''pub(crate) enum UpdateProgress {
    Checking,
    Downloading { version: String },
    Restarting { version: String },
}
''',
    '''pub(crate) enum UpdateProgress {
    Checking,
    Updating { version: String },
}
''',
    "UpdateProgress enum",
)
u = replace_once(
    u,
    '''    let hwnd_raw = hwnd.0 as isize;
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
''',
    '''    let hwnd_raw = hwnd.0 as isize;
    lock_progress().clear();
    UPDATE_STAGE.store(UPDATE_STAGE_CHECKING, Ordering::Release);
    let delayed_hwnd_raw = hwnd_raw;
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(UPDATE_CHECK_NOTIFY_DELAY_MS));
        if UPDATE_IN_PROGRESS.load(Ordering::Acquire)
            && UPDATE_STAGE.load(Ordering::Acquire) == UPDATE_STAGE_CHECKING
        {
            post_progress(delayed_hwnd_raw, UpdateProgress::Checking);
        }
    });

    std::thread::spawn(move || {
        let ui_result = match prepare_update(hwnd_raw) {
            Ok(UpdateOutcome::Current { version }) => UpdateUiResult::Current { version },
            Ok(UpdateOutcome::Ready(package)) => match launch_prepared_update(package) {
                Ok(()) => UpdateUiResult::ReadyToRestart,
                Err(error) => {
                    let detail = visible_error_detail(&error);
                    diagnose::log(format!("updater: helper failed error={error:?} detail={detail}"));
                    UpdateUiResult::Failed { error, detail }
                },
            },
            Err(error) => {
                let detail = visible_error_detail(&error);
                diagnose::log(format!("updater: failed error={error:?} detail={detail}"));
                UpdateUiResult::Failed { error, detail }
            },
        };

        UPDATE_STAGE.store(UPDATE_STAGE_IDLE, Ordering::Release);
        *lock_result() = Some(ui_result);
        let target_hwnd = HWND(hwnd_raw as *mut _);
        unsafe {
            let _ = PostMessageW(target_hwnd, WM_APP_UPDATE_RESULT, WPARAM(0), LPARAM(0));
        }
    });
''',
    "start_update progress flow",
)
u = replace_once(
    u,
    '''    post_progress(
        hwnd_raw,
        UpdateProgress::Downloading {
            version: latest_text.clone(),
        },
    );
''',
    '''    UPDATE_STAGE.store(UPDATE_STAGE_UPDATING, Ordering::Release);
    post_progress(
        hwnd_raw,
        UpdateProgress::Updating {
            version: latest_text.clone(),
        },
    );
''',
    "updating progress",
)
u = replace_once(
    u,
    "    let relaunch_args = std::env::args().skip(1).collect();",
    "    let relaunch_args = std::env::args()\n        .skip(1)\n        .filter(|arg| !is_internal_update_arg(arg))\n        .collect();",
    "filter relaunch args",
)
u = sub_once(
    u,
    r'''fn success_marker_path\(target: &Path\) -> PathBuf \{.*?\n\}\n\npub\(crate\) fn take_successful_update_version\(\) -> Option<String> \{.*?\n\}\n''',
    '''pub(crate) fn is_internal_update_arg(arg: &str) -> bool {
    arg.starts_with(UPDATE_SUCCESS_ARG_PREFIX)
}

fn successful_update_version_from_iter<I>(args: I, current_version: &str) -> Option<String>
where
    I: IntoIterator<Item = String>,
{
    args.into_iter().find_map(|arg| {
        let version = arg.strip_prefix(UPDATE_SUCCESS_ARG_PREFIX)?;
        if Version::parse(version).is_some() && version == current_version {
            Some(version.to_string())
        } else {
            None
        }
    })
}

pub(crate) fn successful_update_version_from_args() -> Option<String> {
    if UPDATE_SUCCESS_ARG_CONSUMED.swap(true, Ordering::AcqRel) {
        return None;
    }
    let version = successful_update_version_from_iter(std::env::args().skip(1), env!("CARGO_PKG_VERSION"));
    if let Some(version) = version.as_ref() {
        diagnose::log(format!("updater: successful update argument consumed version={version}"));
    }
    version
}
''',
    "replace success marker functions",
    flags=re.S,
)
u = replace_once(
    u,
    '''    let staging = ps_single_quote(&package.staging_dir.to_string_lossy());
    let success_marker = ps_single_quote(&success_marker_path(&package.target).to_string_lossy());
    let version = ps_single_quote(&package.version);
''',
    '''    let staging = ps_single_quote(&package.staging_dir.to_string_lossy());
    let success_arg = ps_single_quote(&format!("{UPDATE_SUCCESS_ARG_PREFIX}{}", package.version));
    let version = ps_single_quote(&package.version);
''',
    "helper success arg variable",
)
u = replace_once(
    u,
    '''$Staging = {staging}
$SuccessMarker = {success_marker}
$Version = {version}
$WorkingDirectory = {working_dir}
$RelaunchArgs = {args}
''',
    '''$Staging = {staging}
$SuccessArg = {success_arg}
$Version = {version}
$WorkingDirectory = {working_dir}
$RelaunchArgs = {args}
$LaunchArgs = @($RelaunchArgs) + @($SuccessArg)
''',
    "PowerShell success arg",
)
u = u.replace("    Remove-Item -LiteralPath $SuccessMarker -Force -ErrorAction SilentlyContinue\n", "")
u = u.replace("    Set-Content -LiteralPath $SuccessMarker -Value $Version -Encoding ascii\n\n", "")
u = replace_once(
    u,
    '''        if ($RelaunchArgs.Count -gt 0) {{
            Start-Process -FilePath $Target -ArgumentList $RelaunchArgs -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }} else {{
            Start-Process -FilePath $Target -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
        }}
''',
    '''        Start-Process -FilePath $Target -ArgumentList $LaunchArgs -WorkingDirectory $WorkingDirectory -WindowStyle Hidden
''',
    "PowerShell relaunch args",
)
u = sub_once(
    u,
    r'''    #\[test\]\n    fn success_marker_is_consumed_only_for_current_version\(\) \{.*?    #\[test\]\n    fn numeric_version_order_handles_two_digit_patch''',
    '''    #[test]
    fn success_argument_is_accepted_only_for_current_version() {
        assert_eq!(
            successful_update_version_from_iter(vec!["--codex-usage-updated-to=1.2.3".to_string()], "1.2.3"),
            Some("1.2.3".to_string())
        );
        assert_eq!(
            successful_update_version_from_iter(vec!["--codex-usage-updated-to=9.9.9".to_string()], "1.2.3"),
            None
        );
    }

    #[test]
    fn internal_success_argument_is_identified_for_filtering() {
        assert!(is_internal_update_arg("--codex-usage-updated-to=1.2.3"));
        assert!(!is_internal_update_arg("--diagnose"));
    }

    #[test]
    fn numeric_version_order_handles_two_digit_patch''',
    "replace marker tests",
    flags=re.S,
)
updater_path.write_text(u, encoding="utf-8")

window_path = Path("src/window.rs")
w = window_path.read_text(encoding="utf-8")
w = replace_once(
    w,
    "    let args: Vec<String> = std::env::args().skip(1).collect();",
    "    let args: Vec<String> = std::env::args()\n        .skip(1)\n        .filter(|arg| !updater::is_internal_update_arg(arg))\n        .collect();",
    "watchdog arg filter",
)
w = w.replace("tray_icon::notify_balloon", "tray_icon::notify_info")
w = replace_once(w, "if let Some(version) = updater::take_successful_update_version() {", "if let Some(version) = updater::successful_update_version_from_args() {", "startup success arg")
auth_info = '''                    tray_icon::notify_info(
                        hwnd,
                        tray_icon::TrayIconKind::Codex,
                        s.language.strings().codex_token_expired_title,
                        s.language.strings().codex_token_expired_body,
                    );'''
w = replace_once(w, auth_info, auth_info.replace("notify_info", "notify_warning"), "auth warning")
w = replace_once(
    w,
    '''            for alert in &quota_alerts {
                tray_icon::notify_info(hwnd, alert.kind, &alert.title, &alert.message);
            }
''',
    '''            notify_quota_alerts(hwnd, &quota_alerts);
''',
    "poll quota aggregation",
)
w = replace_once(
    w,
    '''                    for alert in &alerts {
                        tray_icon::notify_info(hwnd, alert.kind, &alert.title, &alert.message);
                    }
''',
    '''                    notify_quota_alerts(hwnd, &alerts);
''',
    "settings quota aggregation",
)
w = replace_once(
    w,
    "#[allow(clippy::too_many_arguments)]\nfn append_provider_alerts(",
    '''fn notify_quota_alerts(hwnd: HWND, alerts: &[QuotaAlert]) {
    let Some(first) = alerts.first() else {
        return;
    };
    let message = alerts
        .iter()
        .map(|alert| alert.message.as_str())
        .collect::<Vec<_>>()
        .join("\\n");
    tray_icon::notify_info(hwnd, first.kind, &first.title, &message);
}

#[allow(clippy::too_many_arguments)]
fn append_provider_alerts(''',
    "quota notify helper",
)
w = replace_once(w, 'format!("{provider_label} 额度提醒")', 'format!("{provider_label} 额度")', "Chinese quota title")
w = replace_once(w, '"{window_label}额度仅剩 {remaining}%，重置时间：{}",', '"{window_label} 剩余 {remaining}% · {} 重置",', "Chinese quota message")
w = replace_once(w, 'format!("{provider_label} quota alert")', 'format!("{provider_label} quota")', "English quota title")
w = replace_once(w, '"{window_label} quota has {remaining}% remaining. Reset: {}",', '"{window_label} {remaining}% remaining · reset {}",', "English quota message")
w = replace_once(
    w,
    '''                let message = match progress {
                    updater::UpdateProgress::Checking => strings.update_checking.to_string(),
                    updater::UpdateProgress::Downloading { version } => {
                        format!("{} v{}", strings.update_downloading, version)
                    }
                    updater::UpdateProgress::Restarting { version } => {
                        format!("{} v{}…", strings.update_restarting, version)
                    }
                };
                tray_icon::notify_info(
                    hwnd,
                    tray_icon::TrayIconKind::Codex,
                    strings.update_title,
                    &message,
                );
''',
    '''                let message = match progress {
                    updater::UpdateProgress::Checking => strings.update_checking.to_string(),
                    updater::UpdateProgress::Updating { version } => {
                        tray_icon::clear_notification(hwnd);
                        format!("{} v{}…", strings.update_downloading, version)
                    }
                };
                tray_icon::notify_info(
                    hwnd,
                    tray_icon::TrayIconKind::Codex,
                    strings.update_title,
                    &message,
                );
''',
    "update progress UI",
)
w = replace_once(
    w,
    '''                        let message = format!("{} v{}", strings.update_current, version);
                        tray_icon::notify_info(
''',
    '''                        tray_icon::clear_notification(hwnd);
                        let message = format!("{} v{}", strings.update_current, version);
                        tray_icon::notify_info(
''',
    "current result clears progress",
)
w = replace_once(
    w,
    '''                        let message = if detail.is_empty() {
                            message.to_string()
                        } else {
                            format!("{message}: {detail}")
                        };
                        tray_icon::notify_info(
                            hwnd,
                            tray_icon::TrayIconKind::Codex,
                            strings.update_title,
                            &message,
                        );''',
    '''                        let message = if detail.is_empty() {
                            message.to_string()
                        } else {
                            format!("{message}: {detail}")
                        };
                        tray_icon::clear_notification(hwnd);
                        tray_icon::notify_warning(
                            hwnd,
                            tray_icon::TrayIconKind::Codex,
                            strings.update_title,
                            &message,
                        );''',
    "failure warning",
)
w = sub_once(
    w,
    r'''                    updater::UpdateUiResult::ReadyToRestart => \{.*?                    \}\n                \}\n''',
    '''                    updater::UpdateUiResult::ReadyToRestart => {
                        tray_icon::clear_notification(hwnd);
                        let _ = PostMessageW(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0));
                    }
                }
''',
    "ready-to-restart UI",
    flags=re.S,
)
window_path.write_text(w, encoding="utf-8")

translations = {
    "english.rs": "Updating to",
    "dutch.rs": "Bijwerken naar",
    "spanish.rs": "Actualizando a",
    "french.rs": "Mise à jour vers",
    "german.rs": "Aktualisierung auf",
    "japanese.rs": "更新中",
    "korean.rs": "업데이트 중",
    "simplified_chinese.rs": "正在更新到",
    "traditional_chinese.rs": "正在更新至",
    "russian.rs": "Обновление до",
    "portuguese_brazil.rs": "Atualizando para",
}
for filename, text in translations.items():
    path = Path("src/localization") / filename
    content = path.read_text(encoding="utf-8")
    content = sub_once(content, r'    update_downloading: ".*?",', f'    update_downloading: "{text}",', f"{filename} update copy")
    content, count = re.subn(r'^    update_restarting: .*\n', '', content, count=1, flags=re.M)
    if count != 1:
        raise SystemExit(f"{filename}: expected one update_restarting field, got {count}")
    path.write_text(content, encoding="utf-8")

loc_mod_path = Path("src/localization/mod.rs")
loc_mod = loc_mod_path.read_text(encoding="utf-8")
loc_mod, count = re.subn(r'^    pub update_restarting: .*\n', '', loc_mod, count=1, flags=re.M)
if count != 1:
    raise SystemExit(f"localization/mod.rs: expected one update_restarting field, got {count}")
loc_mod_path.write_text(loc_mod, encoding="utf-8")

print("notification UX patch applied")
