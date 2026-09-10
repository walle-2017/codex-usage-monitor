from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def remove_once(path: str, old: str) -> None:
    replace_once(path, old, "")


# Stop publishing legacy aliases. The current product/release identity is codex-usage-win.
remove_once(
    ".github/workflows/release.yml",
    "          Copy-Item target/release/codex-usage-win.exe dist/codex-usage.exe\n",
)
remove_once(
    ".github/workflows/release.yml",
    "          \"$hash  codex-usage.exe\" | Set-Content -Encoding ascii dist/codex-usage.exe.sha256\n",
)
remove_once(
    ".github/workflows/release.yml",
    "            dist/codex-usage.exe\n            dist/codex-usage.exe.sha256\n",
)

# Updater: distinguish a missing expected Release asset from an ordinary download failure.
replace_once(
    "src/updater.rs",
    "    DownloadFailed,\n    InvalidChecksum,",
    "    DownloadFailed,\n    AssetMissing,\n    InvalidChecksum,",
)
replace_once(
    "src/updater.rs",
    "pub(crate) enum UpdateUiResult {\n    Current { version: String },\n    Failed { error: UpdateError, detail: String },\n    ReadyToRestart,\n}",
    "pub(crate) enum UpdateUiResult {\n    Current { version: String },\n    ManualUpdateRequired { version: String },\n    Failed { error: UpdateError, detail: String },\n    ReadyToRestart,\n}",
)
replace_once(
    "src/updater.rs",
    "enum UpdateOutcome {\n    Current { version: String },\n    Ready(UpdatePackage),\n}",
    "enum UpdateOutcome {\n    Current { version: String },\n    ManualUpdateRequired { version: String },\n    Ready(UpdatePackage),\n}",
)
replace_once(
    "src/updater.rs",
    "        UpdateError::DownloadFailed => \"Release asset download failed\".to_string(),\n        UpdateError::InvalidChecksum => \"Checksum file is invalid\".to_string(),",
    "        UpdateError::DownloadFailed => \"Release asset download failed\".to_string(),\n        UpdateError::AssetMissing => \"Release asset name changed\".to_string(),\n        UpdateError::InvalidChecksum => \"Checksum file is invalid\".to_string(),",
)
replace_once(
    "src/updater.rs",
    "            Ok(UpdateOutcome::Current { version }) => UpdateUiResult::Current { version },\n            Ok(UpdateOutcome::Ready(package)) => match launch_prepared_update(package) {",
    "            Ok(UpdateOutcome::Current { version }) => UpdateUiResult::Current { version },\n            Ok(UpdateOutcome::ManualUpdateRequired { version }) => {\n                UpdateUiResult::ManualUpdateRequired { version }\n            }\n            Ok(UpdateOutcome::Ready(package)) => match launch_prepared_update(package) {",
)
replace_once(
    "src/updater.rs",
    "    match prepare_downloaded_package(&agent, update, staging_dir.clone()) {\n        Ok(package) => Ok(UpdateOutcome::Ready(package)),\n        Err(error) => {\n            let _ = fs::remove_dir_all(staging_dir);\n            Err(error)\n        }\n    }",
    "    let update_version = update.version.clone();\n    match prepare_downloaded_package(&agent, update, staging_dir.clone()) {\n        Ok(package) => Ok(UpdateOutcome::Ready(package)),\n        Err(UpdateError::AssetMissing) => {\n            let _ = fs::remove_dir_all(staging_dir);\n            diagnose::log(format!(\n                \"updater: expected Release asset missing for v{update_version}; manual update required\"\n            ));\n            Ok(UpdateOutcome::ManualUpdateRequired {\n                version: update_version,\n            })\n        }\n        Err(error) => {\n            let _ = fs::remove_dir_all(staging_dir);\n            Err(error)\n        }\n    }",
)
replace_once(
    "src/updater.rs",
    "    let response = request_builder(agent, url).call().map_err(|error| {\n        let detail = format!(\n            \"Release asset download failed: {}\",\n            ureq_error_detail(error)\n        );\n        set_error_detail(detail.clone());\n        diagnose::log(format!(\"updater: {detail}\"));\n        UpdateError::DownloadFailed\n    })?;",
    "    let response = request_builder(agent, url).call().map_err(|error| {\n        if matches!(&error, ureq::Error::Status(404, _)) {\n            diagnose::log(format!(\n                \"updater: expected Release asset returned HTTP 404 url={}\",\n                safe_detail(url)\n            ));\n            return UpdateError::AssetMissing;\n        }\n        let detail = format!(\n            \"Release asset download failed: {}\",\n            ureq_error_detail(error)\n        );\n        set_error_detail(detail.clone());\n        diagnose::log(format!(\"updater: {detail}\"));\n        UpdateError::DownloadFailed\n    })?;",
)

# Window/UI: Releases command, localized manual-update guidance, and explicit result handling.
replace_once(
    "src/window.rs",
    "use windows::Win32::UI::Shell::ExtractIconExW;",
    "use windows::Win32::UI::Shell::{ExtractIconExW, ShellExecuteW};",
)
replace_once(
    "src/window.rs",
    "const IDM_CHECK_UPDATE: u16 = 60;\nconst IDM_SHOW_SESSION_WINDOW: u16 = 71;",
    "const IDM_CHECK_UPDATE: u16 = 60;\nconst IDM_OPEN_RELEASES: u16 = 61;\nconst IDM_SHOW_SESSION_WINDOW: u16 = 71;",
)
replace_once(
    "src/window.rs",
    "const IDM_APPEARANCE_MINIMAL: u16 = 92;\n\nconst WM_DPICHANGED_MSG: u32 = 0x02E0;",
    "const IDM_APPEARANCE_MINIMAL: u16 = 92;\n\nconst GITHUB_RELEASES_URL: &str =\n    \"https://github.com/walle-2017/codex-usage-monitor/releases\";\nconst WM_DPICHANGED_MSG: u32 = 0x02E0;",
)
replace_once(
    "src/window.rs",
    "fn set_window_title(hwnd: HWND, strings: Strings) {",
    '''fn github_releases_menu_label(language: LanguageId) -> &'static str {
    match language {
        LanguageId::English => "Open GitHub Releases",
        LanguageId::Dutch => "GitHub Releases openen",
        LanguageId::Spanish => "Abrir GitHub Releases",
        LanguageId::French => "Ouvrir GitHub Releases",
        LanguageId::German => "GitHub Releases öffnen",
        LanguageId::Japanese => "GitHub Releases を開く",
        LanguageId::Korean => "GitHub Releases 열기",
        LanguageId::SimplifiedChinese => "前往 GitHub Releases",
        LanguageId::TraditionalChinese => "前往 GitHub Releases",
        LanguageId::Russian => "Открыть GitHub Releases",
        LanguageId::PortugueseBrazil => "Abrir GitHub Releases",
    }
}

fn manual_update_required_message(language: LanguageId, version: &str) -> String {
    match language {
        LanguageId::English => format!(
            "Version v{version} is available, but the program or release asset name has changed. Automatic update is unavailable. Open GitHub Releases and update manually."
        ),
        LanguageId::Dutch => format!(
            "Versie v{version} is beschikbaar, maar de programma- of releasebestandsnaam is gewijzigd. Automatisch bijwerken is niet mogelijk. Open GitHub Releases en werk handmatig bij."
        ),
        LanguageId::Spanish => format!(
            "La versión v{version} está disponible, pero el nombre del programa o de los archivos de la versión ha cambiado. La actualización automática no está disponible. Abre GitHub Releases y actualiza manualmente."
        ),
        LanguageId::French => format!(
            "La version v{version} est disponible, mais le nom du programme ou des fichiers de publication a changé. La mise à jour automatique est indisponible. Ouvrez GitHub Releases et mettez à jour manuellement."
        ),
        LanguageId::German => format!(
            "Version v{version} ist verfügbar, aber der Programmname oder der Name der Release-Datei hat sich geändert. Die automatische Aktualisierung ist nicht möglich. Öffnen Sie GitHub Releases und aktualisieren Sie manuell."
        ),
        LanguageId::Japanese => format!(
            "v{version} を利用できますが、プログラム名またはリリースファイル名が変更されています。自動更新できません。GitHub Releases を開き、手動で更新してください。"
        ),
        LanguageId::Korean => format!(
            "v{version} 버전을 사용할 수 있지만 프로그램 이름 또는 릴리스 파일 이름이 변경되었습니다. 자동 업데이트를 사용할 수 없습니다. GitHub Releases를 열어 수동으로 업데이트하세요."
        ),
        LanguageId::SimplifiedChinese => format!(
            "检测到 v{version}，但程序名称或发布文件名称已发生变化，无法自动升级。请前往 GitHub Releases 手动更新。"
        ),
        LanguageId::TraditionalChinese => format!(
            "偵測到 v{version}，但程式名稱或發佈檔案名稱已變更，無法自動升級。請前往 GitHub Releases 手動更新。"
        ),
        LanguageId::Russian => format!(
            "Доступна версия v{version}, но название программы или файла релиза изменилось. Автоматическое обновление недоступно. Откройте GitHub Releases и обновитесь вручную."
        ),
        LanguageId::PortugueseBrazil => format!(
            "A versão v{version} está disponível, mas o nome do programa ou do arquivo da versão mudou. A atualização automática não está disponível. Abra o GitHub Releases e atualize manualmente."
        ),
    }
}

fn open_github_releases(hwnd: HWND) {
    unsafe {
        let operation = native_interop::wide_str("open");
        let url = native_interop::wide_str(GITHUB_RELEASES_URL);
        let _ = ShellExecuteW(
            hwnd,
            PCWSTR::from_raw(operation.as_ptr()),
            PCWSTR::from_raw(url.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        );
    }
}

fn set_window_title(hwnd: HWND, strings: Strings) {''',
)
replace_once(
    "src/window.rs",
    "                    updater::UpdateUiResult::Failed { error, detail } => {",
    '''                    updater::UpdateUiResult::ManualUpdateRequired { version } => {
                        let (strings, language) = {
                            let state = lock_state();
                            state
                                .as_ref()
                                .map(|s| (s.language.strings(), s.language))
                                .unwrap_or_else(|| {
                                    (LanguageId::English.strings(), LanguageId::English)
                                })
                        };
                        tray_icon::clear_notification(hwnd);
                        let message = manual_update_required_message(language, &version);
                        tray_icon::notify_info(
                            hwnd,
                            tray_icon::TrayIconKind::Codex,
                            strings.update_title,
                            &message,
                        );
                    }
                    updater::UpdateUiResult::Failed { error, detail } => {''',
)
replace_once(
    "src/window.rs",
    "                IDM_CHECK_UPDATE => {\n                    diagnose::log(\"update command requested\");\n                    let _ = updater::start_update(hwnd);\n                }\n                IDM_RESET_POSITION => {",
    "                IDM_CHECK_UPDATE => {\n                    diagnose::log(\"update command requested\");\n                    let _ = updater::start_update(hwnd);\n                }\n                IDM_OPEN_RELEASES => {\n                    open_github_releases(hwnd);\n                }\n                IDM_RESET_POSITION => {",
)
replace_once(
    "src/window.rs",
    '''        let _ = AppendMenuW(
            settings_menu,
            MENU_ITEM_FLAGS(0),
            IDM_CHECK_UPDATE as usize,
            PCWSTR::from_raw(version_label.as_ptr()),
        );

        let settings_label = native_interop::wide_str(strings.settings);''',
    '''        let _ = AppendMenuW(
            settings_menu,
            MENU_ITEM_FLAGS(0),
            IDM_CHECK_UPDATE as usize,
            PCWSTR::from_raw(version_label.as_ptr()),
        );
        let releases_label = native_interop::wide_str(github_releases_menu_label(language));
        let _ = AppendMenuW(
            settings_menu,
            MENU_ITEM_FLAGS(0),
            IDM_OPEN_RELEASES as usize,
            PCWSTR::from_raw(releases_label.as_ptr()),
        );

        let settings_label = native_interop::wide_str(strings.settings);''',
)

# Keep README-FORK aligned with the maintained update behavior.
readme = Path("README-FORK.md")
readme_text = readme.read_text(encoding="utf-8")
needle = "- 发现更高版本时，版本菜单显示 `v当前版本 --> v最新版本`；只有用户点击后才进入下载、校验和替换流程。\n"
addition = (
    needle
    + "- 如果已经发现更高版本，但当前程序预期的 Release 资产名返回 HTTP 404，不展示原始 404 下载错误；改为提示程序名称或发布文件名称可能已变化，并引导用户前往 GitHub Releases 手动更新。\n"
    + "- 右键菜单的版本号选项下方提供 `前往 GitHub Releases`，可直接用默认浏览器打开项目 Releases 页面。\n"
)
if needle not in readme_text:
    raise RuntimeError("README-FORK.md: update behavior anchor not found")
readme.write_text(readme_text.replace(needle, addition, 1), encoding="utf-8")

# Remove the temporary mutation machinery before committing the real change.
Path("scripts/apply-manual-update-fix.py").unlink()
Path(".github/workflows/apply-manual-update-fix.yml").unlink()
