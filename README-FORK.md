# Fork 说明

本文档定义 `walle-2017/codex-usage-monitor` 相对上游仓库的**最终维护基线**。当前正式版本为 `v1.0.3`，继续以 Codex-only、最小运行时权限、稳定任务栏显示和可审计网络行为为核心目标。

本文档只描述当前仍然有效的差异和约束，不记录中间重构过程。

## 1. v1.0.3 更新内容

正式版本：

```text
版本：1.0.3
Tag：v1.0.3
运行时范围：Codex-only
平台：Windows 10 / Windows 11
```

`v1.0.3` 在 `v1.0.2` 多显示器拖动基线上增加并完成应用内自动更新，同时补充持久运行日志和精简 Windows 通知：

- **设置**中的版本号改为可点击，用户点击后手动检查更新；不会在启动时或后台定时检查。
- 最新版本只从当前 Fork `walle-2017/codex-usage-monitor` 的稳定 Release 获取。
- 最新版本发现通过 `https://github.com/walle-2017/codex-usage-monitor/releases/latest` 重定向解析稳定 `vX.Y.Z`，不依赖 GitHub 未认证 REST `releases/latest` API。
- 只下载当前 Fork Release 中的 `codex-usage.exe` 与 `codex-usage.exe.sha256`，SHA256 一致后才进入替换流程。
- 更新目标固定为 `std::env::current_exe()`，同时支持安装版和位于可写目录中的便携版。
- 使用本地生成的一次性 PowerShell helper 等待旧进程退出，执行 `.new` / `.old` 替换和失败回滚，然后重启新版本；不会下载或执行 Release 中的 `install.ps1`。
- 更新成功通过一次性内部参数 `--codex-usage-updated-to=X.Y.Z` 交给新进程显示成功通知，不在程序目录创建持久 success marker 文件。
- 普通更新状态和额度提醒使用简洁无警告大图标的 Windows 通知；真正的更新失败仍保留警告样式和具体错误信息。
- 同一轮轮询触发多个额度窗口提醒时合并为一条通知，并继续按额度重置窗口去重。
- 正常运行始终在 EXE 同目录追加写入 `codex-usage.log`；达到 5 MB 后轮转为 `codex-usage.log.1`，只保留一份历史日志。
- 日志保留更新、网络、轮询和任务栏恢复关键事件，但不记录 access token、refresh token、`auth.json` 内容或代理密码。

`Cargo.toml` 是产品版本的权威来源；`Cargo.lock` 根包版本、程序右键菜单中的版本号，以及 Windows EXE 的 FileVersion/ProductVersion 均与该版本保持一致。

## 2. v1.0.2 多显示器拖动基线

`v1.0.2` 在 `v1.0.1` 实时跨任务栏拖动基础上修正鼠标锚点与 DPI 变化时的交互：

- 拖动开始时保存 DPI 无关的逻辑抓取点 `drag_anchor_logical_x`；
- 组件跨入目标任务栏时，优先读取目标任务栏 DPI，并按目标 DPI 换算鼠标锚点；
- 拖动期间以当前鼠标屏幕坐标直接计算组件左边界；
- 跨任务栏时鼠标保持在左侧拖动手柄的同一逻辑抓取位置；
- 拖动期间允许任务栏边缘临时裁剪，松开鼠标后再执行最终 clamp 并持久化位置；
- 保留 Mouse Capture 安全修复：重新挂载前释放 Capture、区分内部 `WM_CAPTURECHANGED`、挂载后恢复 Capture，并在按钮释放时无条件 `ReleaseCapture()`；
- 支持 A → B、A → B → A 连续拖动，以及不同 DPI / 缩放比例的多显示器组合。

## 3. v1.0.0 安全基线

`v1.0.0` 建立了当前 Fork 的 Codex-only 与安全运行时基线。后续版本不得破坏这些安全约束。

## 4. Codex-only 运行时

程序运行时只查询 Codex 用量，不提供多 Provider 选择、轮询、绘制或托盘切换逻辑。

主要数据流：

```text
$CODEX_HOME/auth.json 或 ~/.codex/auth.json
        ↓
读取 access_token / account_id
        ↓
显式代理环境变量 / Windows 手动 system proxy / 直连
        ↓
HTTPS
        ↓
ChatGPT Codex usage endpoint
        ↓
任务栏显示 5h / 7d 剩余额度
```

任务栏百分比、进度长度和状态色统一使用**剩余额度**语义，不因界面语言改变含义。

## 5. Codex CLI 自动刷新必须保持禁用

这是本 Fork 最重要的安全约束。

当 usage API 返回 `401` / `403` 时，当前行为固定为：

```text
usage API 返回 401 / 403
        ↓
判定 Codex 凭据失效
        ↓
本次查询失败并暂停认证轮询
        ↓
等待 auth.json 凭据来源发生变化
        ↓
不会启动 Codex CLI
```

监控器不得为了额度查询主动执行或寻找：

```text
codex.exe
codex.cmd
codex.ps1
codex exec
```

登录失效时，由用户自行通过官方 Codex CLI / Codex 应用完成登录。监控器不直接修改 `auth.json`。

CI 中的 `scripts/assert-no-codex-cli-refresh.ps1` 持续锁定这一安全边界。

## 6. 凭据、隐私与 system proxy

本 Fork：

- 不把 Codex 凭据上传到项目作者自己的服务器；
- 不使用独立后端；
- 不收集 Analytics / Telemetry；
- 不上传项目文件。

若用户显式设置 `HTTPS_PROXY`、`HTTP_PROXY` 或 `ALL_PROXY`，则沿用环境变量代理行为。否则程序可读取 Windows 当前用户的手动 system proxy：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

读取 `ProxyEnable` / `ProxyServer` 并只作用于当前进程，不修改注册表或系统代理设置。当前不实现 PAC/WPAD。

## 7. 任务栏 UI 最终状态

任务栏只保留两套外观：

| 外观 | 内容 |
| --- | --- |
| Compact / 紧凑 | 进度条 + 剩余百分比 + 重置时间/日期 |
| Minimal / 极简 | 进度条 + 剩余百分比 |

稳定性约束：

- 支持 Windows 明/暗主题和小任务栏布局；
- 支持多显示器任务栏和 DPI-aware 实时跨任务栏拖动；
- 保留 Explorer restart watchdog 与 single-instance mutex；
- 任务栏组件在进程运行期间始终显示；
- 托盘图标提供刷新、设置和退出；
- 普通状态/额度通知不使用警告大图标，错误通知才使用警告样式。

设置文件：

```text
%APPDATA%\CodexUsage\settings.json
```

## 8. 应用内更新安全边界

更新检查必须满足：

```text
用户点击版本号
        ↓
当前 Fork latest Release 重定向
        ↓
解析稳定 vX.Y.Z
        ↓
固定 Fork Release 下载地址
        ↓
codex-usage.exe + codex-usage.exe.sha256
        ↓
SHA256 校验
        ↓
本地 helper 替换 / 失败回滚
        ↓
携带一次性成功参数重启
```

不得把更新源重新指向 upstream Release，不得为更新要求 GitHub PAT，不得自动下载并信任 Release `install.ps1`，不得在启动时或定时后台检查更新。

`scripts/install.ps1` 的在线下载源也固定指向：

```text
walle-2017/codex-usage-monitor
```

## 9. 安装模型

正式 Release 至少提供：

```text
codex-usage.exe
codex-usage.exe.sha256
install.ps1
uninstall.ps1
```

PowerShell 安装程序按用户安装到 `%LOCALAPPDATA%\Programs\CodexUsage`，安装前校验 SHA256，不要求管理员权限。普通卸载保留 `%APPDATA%\CodexUsage\settings.json`，显式使用 `-RemoveSettings` 才删除设置。

## 10. CI 安全回归

`.github/workflows/safe-build.yml` 使用只读仓库权限：

```yaml
permissions:
  contents: read
```

关键检查包括：

```text
assert-no-codex-cli-refresh.ps1
assert-codex-only-runtime.ps1
assert-clean-codex-only-source.ps1
assert-v1-version.ps1
assert-final-docs.ps1
assert-drag-handler-safe.ps1
assert-live-drag-anchor.ps1
assert-compact-ui.ps1
assert-small-taskbar-ui.ps1
assert-language-independent-quota.ps1
assert-auto-update.ps1
assert-runtime-log.ps1
cargo test
cargo clippy -- -D warnings
cargo build --release
```

成功后生成 Windows x64 Artifact，并附带 EXE SHA256。

## 11. 同步 upstream 时必须保护的边界

以后同步上游代码时，至少逐项确认：

1. 不得恢复任何自动启动 Codex CLI 的 Token 刷新路径。
2. 运行时必须保持 Codex-only。
3. 应用内更新源必须继续固定到 `walle-2017/codex-usage-monitor` 的稳定 Release，不得改为 upstream，也不得恢复后台自动检查。
4. 不得恢复任务栏组件隐藏/显示状态机。
5. 不得覆盖 Windows system proxy 支持。
6. 不得破坏 Explorer watchdog、single-instance mutex、实时跨任务栏拖动、DPI-aware 拖动锚点和小任务栏适配。
7. 安装脚本不得重新指向 upstream Release。
8. 所有语言必须保持相同的剩余额度语义。
9. 版本号必须继续由单一包版本源派生。
10. 合并前必须通过 Safe Windows Build 全部检查。

## 12. 上游与许可证

本项目继续遵守 MIT License，并保留原始 [LICENSE](LICENSE) 与版权信息。

Codex Usage 源自 [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) 及其后续衍生工作。当前 Fork 的改动由本仓库独立维护，与原作者、上游维护者或 OpenAI 不存在隶属或背书关系。
