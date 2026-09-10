<p align="center">
  <img src=".github/codex-usage-icon.png" alt="Codex Usage Win" width="144" height="144">
</p>

<h1 align="center">Codex Usage Win — Fork 维护说明</h1>

<p align="center">
  <strong>Windows 原生 Codex 用量监控 · Codex-only · 无后台服务 · 安全手动更新</strong>
</p>

本文档定义 `walle-2017/codex-usage-monitor` 相对上游仓库的当前维护基线。当前维护版本为 **v1.0.4**，产品名称统一为 **Codex Usage Win**，程序文件统一为 `codex-usage-win.exe`。

> 本文只记录当前仍然有效的 Fork 差异、安全边界和发布约束，不保留中间重构过程。

## 1. 当前版本

| 项目 | 当前值 |
| --- | --- |
| 版本 | `v1.0.4` |
| 产品名称 | `Codex Usage Win` |
| 程序文件 | `codex-usage-win.exe` |
| SHA256 文件 | `codex-usage-win.exe.sha256` |
| 平台 | Windows 10 / Windows 11 |
| 运行时范围 | Codex-only |
| Release | [v1.0.4](https://github.com/walle-2017/codex-usage-monitor/releases/tag/v1.0.4) |

### v1.0.4 主要变化

- Windows `ProductName`、`FileDescription`、窗口标题、托盘相关显示和消息通知统一为 `Codex Usage Win`。
- 可执行文件和 Release 资产统一使用 `codex-usage-win.exe` / `codex-usage-win.exe.sha256`。
- 安装目录调整为 `%LOCALAPPDATA%\Programs\CodexUsageWin`，快捷方式和卸载项统一为 `Codex Usage Win`。
- 用户设置继续保存在 `%APPDATA%\CodexUsage`，避免品牌改名导致已有设置丢失。
- EXE 内嵌图标、任务栏托盘图标和快捷方式图标统一使用新的应用图标。
- 更新成功通过一次性内部参数 `--codex-usage-win-updated-to=X.Y.Z` 交给新进程显示通知；迁移阶段仍兼容旧的 `--codex-usage-updated-to=` 参数。
- 每次启动只进行一次稳定 Release 只读检查；没有新版本或检查失败时不打扰用户。
- 发现更高版本时，版本菜单显示 `v当前版本 --> v最新版本`；只有用户点击后才进入下载、校验和替换流程。
- 如果已经发现更高版本，但当前程序预期的 Release 资产名返回 HTTP 404，不展示原始 404 下载错误；改为提示程序名称或发布文件名称可能已变化，并引导用户前往 GitHub Releases 手动更新。
- 右键菜单的版本号选项下方提供 `前往 GitHub Releases`，可直接用默认浏览器打开项目 Releases 页面。
- 普通更新状态和额度提醒继续使用简洁 Windows 通知；真正的更新失败保留警告样式和具体错误信息。
- 同一轮轮询触发多个额度窗口提醒时合并为一条通知。
- 仅使用 `--diagnose` 启动时才在 EXE 同目录写入 `codex-usage-win.log`，超过 5 MB 后轮转为 `codex-usage-win.log.1`；普通启动不写诊断日志。

`Cargo.toml` 是版本号的权威来源；`Cargo.lock` 根包版本、程序菜单版本以及 Windows `FileVersion` / `ProductVersion` 均由同一版本基线保持一致。

## 2. 功能与 UI 基线

程序在任务栏中直接显示 Codex 5 小时和 7 天剩余额度，保留 Compact / 紧凑与 Minimal / 极简两套外观，并支持：

- Windows 明/暗主题与小任务栏布局；
- 多显示器任务栏；
- DPI-aware 实时跨任务栏拖动；
- Explorer restart watchdog；
- single-instance mutex；
- 托盘刷新、设置和退出；
- 低额度提醒与合并通知；
- 启动一次只读更新发现 + 手动应用内更新。

### v1.0.2 拖动基线不得回退

多显示器与不同缩放比例下的拖动依赖逻辑抓取点 `drag_anchor_logical_x`。拖动跨入目标任务栏时必须重新读取目标任务栏 DPI，并按目标 DPI 换算抓取锚点；需要继续支持 A → B、A → B → A 的连续跨屏拖动。

Mouse Capture 安全约束同样保留：重新挂载前释放 Capture、区分内部 `WM_CAPTURECHANGED`、挂载后恢复 Capture，并在按钮释放时无条件 `ReleaseCapture()`。

## 3. Codex-only 运行时

程序运行时只查询 Codex 用量，不恢复多 Provider 选择、轮询、绘制或托盘切换逻辑。

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

任务栏百分比、进度长度和状态色统一使用“剩余额度”语义，不因界面语言变化而改变含义。

## 4. Codex CLI 自动刷新必须保持禁用

当 usage API 返回 `401` / `403` 时，固定行为是：

```text
usage API 返回 401 / 403
        ↓
判定 Codex 凭据失效
        ↓
暂停认证轮询并等待凭据来源变化
        ↓
不会启动 Codex CLI
```

监控器不得为了额度查询主动执行或寻找 `codex.exe`、`codex.cmd`、`codex.ps1` 或 `codex exec`。登录失效后由用户通过官方 Codex CLI / Codex 应用重新登录，监控器不直接修改 `auth.json`。

CI 中的 `scripts/assert-no-codex-cli-refresh.ps1` 持续锁定这一安全边界。

## 5. 凭据、隐私与代理

本 Fork：

- 不把 Codex 凭据上传到项目作者自己的服务器；
- 不使用独立后端；
- 不收集 Analytics / Telemetry；
- 不上传用户项目文件。

代理优先级为：

```text
HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
        ↓
Windows 当前用户手动 system proxy
        ↓
直连
```

Windows 手动代理读取位置：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

仅读取 `ProxyEnable` / `ProxyServer` 并作用于当前进程，不修改注册表和系统代理设置；当前不实现 PAC/WPAD。

## 6. 应用内更新安全边界

更新源固定为当前 Fork：

```text
walle-2017/codex-usage-monitor
```

完整流程：

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

必须继续满足：

- 不把更新源重新指向 upstream Release；
- 不要求 GitHub PAT；
- 不自动下载或执行 Release 中的 `install.ps1`；
- 每次启动最多执行一次只读稳定 Release 检查；
- 启动检查不得扩展为周期性后台更新检查；
- 真正安装更新必须由用户主动点击触发；
- 更新目标仍以当前运行程序为安全替换对象，并保留 SHA256 校验、`.new` / `.old` 回滚和重启流程。

## 7. 安装与卸载模型

v1.0.4 正式 Release 资产：

```text
codex-usage-win.exe
codex-usage-win.exe.sha256
install.ps1
uninstall.ps1
```

PowerShell 安装程序按当前用户安装到：

```text
%LOCALAPPDATA%\Programs\CodexUsageWin
```

不要求管理员权限。普通卸载保留：

```text
%APPDATA%\CodexUsage\settings.json
```

只有显式使用 `-RemoveSettings` 才删除设置。

## 8. CI 与发布约束

`.github/workflows/safe-build.yml` 使用只读仓库权限，并验证：

- Codex CLI 自动刷新保持禁用；
- Codex-only 运行时；
- `Codex Usage Win` / `codex-usage-win` 品牌一致性；
- v1.0.4 版本一致性；
- 任务栏拖动和小任务栏 UI；
- 应用内更新安全边界；
- 启动更新发现；
- `--diagnose` 日志行为；
- `cargo test`；
- Clippy；
- Release Build。

正式发布由 `.github/workflows/release.yml` 在 `v*` Tag 推送后构建 Windows x64 程序并上传四个 Release 资产。

## 9. 同步 upstream 时必须保护的边界

以后同步上游代码时至少确认：

1. 不恢复任何自动启动 Codex CLI 的 Token 刷新路径。
2. 运行时保持 Codex-only。
3. 应用内更新源固定到 `walle-2017/codex-usage-monitor` 的稳定 Release。
4. 启动时只允许一次只读更新检查。
5. 不恢复任务栏组件隐藏/显示状态机。
6. 不覆盖 Windows system proxy 支持。
7. 不破坏 Explorer watchdog、single-instance mutex、实时跨任务栏拖动、DPI-aware 拖动锚点和小任务栏适配。
8. 安装脚本不得重新指向 upstream Release。
9. 所有语言保持一致的剩余额度语义。
10. 版本号继续由单一包版本源派生。
11. 合并和正式发布前必须通过 Safe Windows Build 全部检查。

## 10. 上游与许可证

本项目继续遵守 MIT License，并保留原始 [LICENSE](LICENSE) 与版权信息。

Codex Usage Win 源自 [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) 及其后续衍生工作。当前 Fork 的改动由本仓库独立维护，与原作者、上游维护者或 OpenAI 不存在隶属或背书关系。
