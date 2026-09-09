# Fork 说明

本文档定义 `walle-2017/codex-usage-monitor` 相对上游仓库的**最终维护基线**。当前正式版本为 `v1.0.2`，继续以 Codex-only、最小运行时权限、稳定任务栏显示和可审计网络行为为核心目标。

本文档只描述当前仍然有效的差异和约束，不记录中间重构过程。

## 1. v1.0.2 更新内容

正式版本：

```text
版本：1.0.2
Tag：v1.0.2
运行时范围：Codex-only
平台：Windows 10 / Windows 11
```

`v1.0.2` 在 `v1.0.1` 实时跨任务栏拖动基础上进一步修正鼠标锚点与 DPI 变化时的交互：

- 拖动开始时保存 DPI 无关的逻辑抓取点 `drag_anchor_logical_x`；
- 组件跨入目标任务栏时，优先读取目标任务栏 DPI，并按目标 DPI 换算鼠标锚点；
- 拖动期间以当前鼠标屏幕坐标直接计算组件左边界，不再依赖旧的增量 `drag_start_mouse_x + delta` 模型；
- 跨任务栏时鼠标继续保持在左侧拖动手柄的同一逻辑抓取位置，避免组件与鼠标发生横向错位；
- 拖动期间允许组件在任务栏边缘临时被父窗口裁剪，以鼠标锚点连续性为优先，不在切换瞬间强制停靠 clamp；
- 鼠标松开后才将当前位置换算为合法 `tray_offset` 并执行最终 clamp，再统一持久化 `taskbar_index` 与 `tray_offset`；
- 保留 `v1.0.1` 的 Mouse Capture 安全修复：跨任务栏重新挂载前释放 Capture、区分内部 `WM_CAPTURECHANGED`、重新挂载后恢复 Capture，并在按钮释放时无条件 `ReleaseCapture()`；
- 支持 A → B、A → B → A 的连续拖动，也适配不同 DPI / 缩放比例的多显示器组合。

`Cargo.toml` 是产品版本的权威来源；`Cargo.lock` 根包版本、程序右键菜单中的只读版本号，以及 Windows EXE 的 FileVersion/ProductVersion 均与该版本保持一致。

## 2. v1.0.0 安全基线

`v1.0.0` 建立了当前 Fork 的 Codex-only 与安全运行时基线。后续 `v1.0.1` / `v1.0.2` 不改变这些安全约束，只增加任务栏交互与稳定性改进。

## 3. Codex-only 运行时

程序运行时只查询 Codex 用量，不再提供多 Provider 选择、轮询、绘制或托盘切换逻辑。

当前主要数据流：

```text
$CODEX_HOME/auth.json 或 ~/.codex/auth.json
        ↓
读取 access_token / account_id
        ↓
显式代理环境变量 / Windows 手动系统代理 / 直连
        ↓
HTTPS
        ↓
ChatGPT Codex usage endpoint
        ↓
任务栏显示 5h / 7d 剩余额度
```

任务栏百分比、进度长度和状态色统一使用**剩余额度**语义，不因界面语言改变含义。

## 4. Codex CLI 自动刷新必须保持禁用

这是本 Fork 最重要的安全约束。

上游历史实现曾在 Codex usage API 返回 `401` / `403` 时尝试启动本地 Codex CLI，通过 CLI 更新登录凭据后再重新读取 `auth.json`。

本 Fork 已从源码中删除这条自动刷新路径。当前行为固定为：

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

登录失效时，由用户自行通过官方 Codex CLI / Codex 应用完成登录。官方客户端更新本地凭据后，监控器再恢复查询。

该限制是**源码级删除**，不是运行时配置开关。后续同步 upstream 时不得无条件恢复自动 Token 刷新逻辑。

CI 中的：

```text
scripts/assert-no-codex-cli-refresh.ps1
```

用于持续锁定这一安全边界。

## 5. auth.json 与网络请求

默认凭据位置：

```text
$CODEX_HOME/auth.json
```

或：

```text
%USERPROFILE%\.codex\auth.json
```

程序使用其中的 Codex access token 和 account id 请求 ChatGPT Codex 用量接口。

本 Fork：

- 不直接修改 `auth.json`；
- 不把凭据上传到项目作者自己的服务器；
- 不使用独立后端；
- 不收集 Analytics / Telemetry；
- 不上传项目文件。

Bearer Token 会作为 HTTPS 认证信息发送到 Codex 用量接口，这是实时查询额度所必需的行为。使用代理时应确保代理可信。

## 6. Windows system proxy 支持

若用户已经显式设置：

```text
HTTPS_PROXY
HTTP_PROXY
ALL_PROXY
```

则沿用环境变量代理行为。

如果没有显式代理变量，程序会读取 Windows 当前用户的手动 system proxy：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

读取：

```text
ProxyEnable
ProxyServer
```

支持常见统一地址和按协议拆分的代理配置。解析结果只作用于当前 Codex Usage 进程，不会修改注册表或 Windows 系统代理设置。

当前不实现 PAC、WPAD 或“自动检测设置”。

## 7. 任务栏 UI 最终状态

任务栏只保留两套外观：

| 外观 | 内容 |
| --- | --- |
| Compact / 紧凑 | 进度条 + 剩余百分比 + 重置时间/日期 |
| Minimal / 极简 | 进度条 + 剩余百分比 |

其它稳定性约束：

- 支持 Windows 明/暗主题；
- 支持 Windows 小任务栏布局；
- 支持多显示器任务栏；
- 左侧拖动手柄支持安全捕获、取消、实时跨任务栏拖动和 DPI-aware 鼠标锚点；
- 保留 Explorer 重启 watchdog；
- 保留 single-instance mutex；
- 任务栏组件在进程运行期间始终显示，不存在隐藏/显示开关；
- 托盘图标只作为后台入口，提供刷新、设置和退出。

设置文件：

```text
%APPDATA%\CodexUsage\settings.json
```

当前持久化内容包括任务栏位置/屏幕、刷新频率、语言、外观、5h/7d 行显示、额度提醒阈值及提醒去重状态。

## 8. 程序内更新已删除

当前 Fork 不执行后台版本检查，也没有程序内 updater。

程序不会为了检查版本主动请求 GitHub。升级方式是用户显式安装新的 Fork Release，或手动替换便携版 `codex-usage.exe`。

`scripts/install.ps1` 的在线下载源固定指向：

```text
walle-2017/codex-usage-monitor
```

不得重新指向 upstream Release。

## 9. 安装模型

正式 Release 包至少应提供：

```text
codex-usage.exe
codex-usage.exe.sha256
install.ps1
uninstall.ps1
```

PowerShell 安装程序按用户安装到：

```text
%LOCALAPPDATA%\Programs\CodexUsage
```

安装前校验 SHA256，不要求管理员权限。普通卸载保留 `%APPDATA%\CodexUsage\settings.json`，显式使用 `-RemoveSettings` 才删除设置。

## 10. CI 安全回归

`.github/workflows/safe-build.yml` 使用：

```yaml
permissions:
  contents: read
```

正式 CI 不提交或修改仓库源码。

当前关键检查包括：

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
cargo test
cargo clippy -- -D warnings
cargo build --release
```

成功后生成 Windows x64 Artifact，并附带 EXE SHA256。

## 11. 同步 upstream 时必须保护的边界

以后同步上游代码时，至少逐项确认：

1. 不得恢复任何自动启动 Codex CLI 的 Token 刷新路径。
2. 运行时必须保持 Codex-only。
3. 不得恢复程序内更新器。
4. 不得恢复任务栏组件隐藏/显示状态机。
5. 不得覆盖 Windows system proxy 支持。
6. 不得破坏 Explorer watchdog、single-instance mutex、实时跨任务栏拖动、DPI-aware 拖动锚点、拖动安全和小任务栏适配。
7. 安装脚本不得重新指向 upstream Release。
8. 所有语言必须保持相同的剩余额度语义。
9. 版本号必须继续由单一包版本源派生。
10. 合并前必须通过 Safe Windows Build 全部检查。

## 12. 上游与许可证

本项目继续遵守 MIT License，并保留原始 [LICENSE](LICENSE) 与版权信息。

Codex Usage 源自 [CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor) 及其后续衍生工作。当前 Fork 的改动由本仓库独立维护，与原作者、上游维护者或 OpenAI 不存在隶属或背书关系。
