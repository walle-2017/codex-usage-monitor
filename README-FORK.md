# Fork 说明

本文档定义 `walle-2017/codex-usage-monitor` 相对上游仓库的当前维护基线。当前开发版本为 `v1.0.4`，在用户测试通过后再创建 Tag 和正式 Release。运行时继续以 Codex-only、最小权限、稳定任务栏显示和可审计网络行为为核心目标。

本文档只描述当前仍然有效的差异和约束，不记录中间重构过程。

## 1. v1.0.4 更新内容

候选版本：

```text
版本：1.0.4
Tag：待测试通过后创建
产品名称：Codex Usage Win
程序文件：codex-usage-win.exe
运行时范围：Codex-only
平台：Windows 10 / Windows 11
```

`v1.0.4` 在 `v1.0.3` 基线上完成产品身份和图标统一：

- 产品显示名称统一为 `Codex Usage Win`，Windows ProductName、FileDescription、窗口标题、托盘相关显示和更新通知均使用该名称。
- 程序文件名统一为 `codex-usage-win.exe`，Release 校验文件名统一为 `codex-usage-win.exe.sha256`。
- Windows 安装目录调整为 `%LOCALAPPDATA%\Programs\CodexUsageWin`，快捷方式名称统一为 `Codex Usage Win`。
- 用户设置目录继续保留 `%APPDATA%\CodexUsage`，避免升级或重新安装后丢失已有设置。
- EXE 内嵌图标、任务栏托盘图标和快捷方式图标统一使用新的应用图标资源。
- 更新成功使用一次性内部参数 `--codex-usage-win-updated-to=X.Y.Z` 交给新进程显示通知；迁移阶段仍兼容旧参数 `--codex-usage-updated-to=`。
- 软件每次启动后仍只执行一次只读稳定 Release 检查；仅发现更高版本时通知用户，不自动下载或安装。
- 设置中的版本号保持可点击；发现更高版本后显示 `v当前版本 --> v最新版本`，点击后进入手动更新流程。
- 普通更新状态和额度提醒继续使用简洁 Windows 通知；真正的更新失败保留警告样式和具体错误信息。
- 同一轮轮询触发多个额度窗口提醒时继续合并为一条通知。
- 仅使用 `--diagnose` 启动时才在 EXE 同目录创建或追加 `codex-usage-win.log`；达到 5 MB 后轮转为 `codex-usage-win.log.1`。普通启动不写诊断日志。

`Cargo.toml` 是产品版本的权威来源；`Cargo.lock` 根包版本、程序右键菜单版本号，以及 Windows EXE 的 FileVersion/ProductVersion 均与 `1.0.4` 保持一致。

## 2. v1.0.3 更新基线

`v1.0.3` 完成应用内安全更新、启动更新发现、诊断日志和通知精简：

- 每次启动只执行一次只读稳定 Release 检查，仅发现更高版本时通知。
- 最新版本只从当前 Fork `walle-2017/codex-usage-monitor` 的稳定 Release 获取。
- 最新版本发现通过 `https://github.com/walle-2017/codex-usage-monitor/releases/latest` 重定向解析稳定 `vX.Y.Z`，不依赖 GitHub 未认证 REST `releases/latest` API。
- 更新只下载当前 Fork Release 中的程序文件及 SHA256 校验文件，通过校验后才进入替换流程。
- 更新目标固定为 `std::env::current_exe()`，支持安装版和位于可写目录中的便携版。
- 使用本地一次性 PowerShell helper 等待旧进程退出，执行 `.new` / `.old` 替换和失败回滚，然后重启新版本；不会下载或执行 Release 中的 `install.ps1`。
- 普通启动不写诊断日志，`--diagnose` 才启用持久日志。

## 3. v1.0.2 多显示器拖动基线

`v1.0.2` 修正多显示器与不同缩放比例下的拖动锚点：

- 拖动开始时保存 DPI 无关的逻辑抓取点 `drag_anchor_logical_x`；
- 跨入目标任务栏时读取目标任务栏 DPI，并按目标 DPI 换算鼠标锚点；
- 拖动期间以当前鼠标屏幕坐标直接计算组件左边界；
- 支持不同 DPI / 缩放比例显示器之间 A → B、A → B → A 连续拖动；
- 保留 Mouse Capture 安全修复：重新挂载前释放 Capture、区分内部 `WM_CAPTURECHANGED`、挂载后恢复 Capture，并在按钮释放时无条件 `ReleaseCapture()`。

## 4. v1.0.1 与 v1.0.0 安全基线

`v1.0.1` 增加实时跨任务栏拖动；`v1.0.0` 建立 Codex-only 与安全运行时基线。后续版本不得破坏这些约束。

## 5. Codex-only 运行时

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

任务栏百分比、进度长度和状态色统一使用剩余额度语义，不因界面语言改变含义。

## 6. Codex CLI 自动刷新必须保持禁用

当 usage API 返回 `401` / `403` 时，固定行为为：

```text
usage API 返回 401 / 403
        ↓
判定 Codex 凭据失效
        ↓
暂停认证轮询并等待凭据来源变化
        ↓
不会启动 Codex CLI
```

监控器不得为了额度查询主动执行或寻找 `codex.exe`、`codex.cmd`、`codex.ps1` 或 `codex exec`。登录失效时，由用户自行通过官方 Codex CLI / Codex 应用完成登录，监控器不直接修改 `auth.json`。

CI 中的 `scripts/assert-no-codex-cli-refresh.ps1` 持续锁定这一安全边界。

## 7. 凭据、隐私与 system proxy

本 Fork 不把 Codex 凭据上传到项目作者自己的服务器，不使用独立后端，不收集 Analytics / Telemetry，也不上传项目文件。

若用户显式设置 `HTTPS_PROXY`、`HTTP_PROXY` 或 `ALL_PROXY`，则沿用环境变量代理。否则程序可读取 Windows 当前用户的手动 system proxy：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

读取 `ProxyEnable` / `ProxyServer` 并只作用于当前进程，不修改注册表或系统代理设置。当前不实现 PAC/WPAD。

## 8. 任务栏 UI 最终状态

任务栏保留 Compact / 紧凑与 Minimal / 极简两套外观，并继续满足：

- Windows 明/暗主题和小任务栏布局；
- 多显示器任务栏和 DPI-aware 实时跨任务栏拖动；
- Explorer restart watchdog 与 single-instance mutex；
- 任务栏组件在进程运行期间始终显示；
- 托盘图标提供刷新、设置和退出。

设置文件继续位于：

```text
%APPDATA%\CodexUsage\settings.json
```

## 9. 应用内更新安全边界

更新流程必须满足：

```text
用户点击版本号
        ↓
当前 Fork latest Release 重定向
        ↓
解析稳定 vX.Y.Z
        ↓
固定 Fork Release 下载地址
        ↓
codex-usage-win.exe + codex-usage-win.exe.sha256
        ↓
SHA256 校验
        ↓
本地 helper 替换 / 失败回滚
        ↓
携带一次性成功参数重启
```

不得把更新源重新指向 upstream Release，不得为更新要求 GitHub PAT，不得自动下载并信任 Release `install.ps1`。允许且只允许每次软件启动后执行一次只读更新检查；不得扩展为周期性后台检查。

在线安装源同样固定为：

```text
walle-2017/codex-usage-monitor
```

## 10. 安装模型

`v1.0.4` Release 目标资产：

```text
codex-usage-win.exe
codex-usage-win.exe.sha256
install.ps1
uninstall.ps1
```

PowerShell 安装程序按用户安装到 `%LOCALAPPDATA%\Programs\CodexUsageWin`，安装前校验 SHA256，不要求管理员权限。普通卸载保留 `%APPDATA%\CodexUsage\settings.json`，显式使用 `-RemoveSettings` 才删除设置。

## 11. CI 安全回归

`.github/workflows/safe-build.yml` 使用只读仓库权限，并执行产品命名、版本、安全、任务栏交互、更新、日志以及 Rust 测试/Clippy/Release Build 回归。成功后生成 Windows x64 Artifact，并附带 EXE SHA256。

## 12. 同步 upstream 时必须保护的边界

以后同步上游代码时，至少确认：

1. 不得恢复任何自动启动 Codex CLI 的 Token 刷新路径。
2. 运行时必须保持 Codex-only。
3. 应用内更新源必须固定到 `walle-2017/codex-usage-monitor` 的稳定 Release，并保留一次启动时只读检查。
4. 不得恢复任务栏组件隐藏/显示状态机。
5. 不得覆盖 Windows system proxy 支持。
6. 不得破坏 Explorer watchdog、single-instance mutex、实时跨任务栏拖动、DPI-aware 拖动锚点和小任务栏适配。
7. 安装脚本不得重新指向 upstream Release。
8. 所有语言必须保持相同的剩余额度语义。
9. 版本号必须继续由单一包版本源派生。
10. 合并前必须通过 Safe Windows Build 全部检查。

## 13. 上游与许可证

本项目继续遵守 MIT License，并保留原始 [LICENSE](LICENSE) 与版权信息。

Codex Usage Win 源自 [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) 及其后续衍生工作。当前 Fork 的改动由本仓库独立维护，与原作者、上游维护者或 OpenAI 不存在隶属或背书关系。
