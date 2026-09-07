# Fork 说明

本文档记录 `walle-2017/codex-usage-monitor` 相对上游仓库 `upstream-ray/codex-usage-monitor` 的定制调整，方便后续快速判断本 Fork 与 upstream 的差异，并在同步上游代码时避免重新引入已移除的风险路径。

## 1. Fork 目的

本 Fork 的主要目的不是扩展 Provider 功能，而是针对 Windows 环境下的稳定性和网络适配问题进行收敛。

此前使用其他 Codex 额度监控工具时，监控程序频繁启动 `codex.exe` / `codex app-server`，曾与本机出现的 LSASS / RPCRT4 崩溃和系统强制重启高度相关。因此本 Fork 的核心原则是：

> **额度监控程序本身不得为了刷新 Token 主动启动 Codex CLI。**

本 Fork 仍然读取本地 Codex 登录凭证，并通过 HTTPS 请求 ChatGPT Codex usage 接口获取额度，但不会在认证失败时尝试拉起 `codex.exe`、`codex.cmd` 或 `codex.ps1`。

另外，为适配 FClash / Clash 等通过 Windows“系统代理”工作的网络环境，本 Fork 默认读取 Windows 当前用户的手动系统代理配置，使额度查询无需额外设置 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。

## 2. 当前相对 upstream 的核心差异

最终保留的主要差异有四类：

1. 修改 `src/poller.rs`，彻底移除 Codex CLI 自动刷新 Token 的实现和调用路径。
2. 新增 `scripts/assert-no-codex-cli-refresh.ps1`，作为安全回归检查，防止未来重新引入 Codex CLI 启动逻辑。
3. 新增 `.github/workflows/safe-build.yml`，在 Windows Runner 上执行安全检查、Rust 测试和 Release 构建，并生成 Windows x64 Artifact。
4. 新增 `src/system_proxy.rs`，在没有显式代理环境变量时自动读取 Windows 当前用户的手动系统代理并提供给现有 HTTP 客户端。

## 3. upstream 原始 Codex Token 刷新行为

上游逻辑在 Codex usage API 返回 `401` / `403` 时，会进入 `PollError::AuthRequired` 分支，然后：

```text
usage API 返回 401/403
        ↓
cli_refresh_codex_token()
        ↓
定位本机 Codex CLI
        ↓
执行 codex exec .
        ↓
重新读取 auth.json
        ↓
再次请求 usage API
```

其中还包含自动寻找以下命令的逻辑：

```text
codex.cmd
codex.ps1
codex.exe
codex
```

这意味着额度监控器自身可能创建 Codex CLI 子进程。

## 4. 本 Fork 修改后的行为

当前 `src/poller.rs` 已改为：

```rust
Err(PollError::AuthRequired) => {
    diagnose::log("Codex credentials rejected; automatic Codex CLI refresh is disabled");
    Err(PollError::TokenExpired)
}
```

因此现在的数据流为：

```text
%USERPROFILE%\.codex\auth.json
        ↓
读取 access_token / account_id
        ↓
HTTP 客户端（显式代理环境变量 / Windows 系统代理 / 直连）
        ↓
HTTPS
        ↓
https://chatgpt.com/backend-api/wham/usage
        ↓
任务栏显示额度
```

Token 正常时，额度查询与 upstream 保持一致。

Token 失效或接口返回 `401` / `403` 时：

```text
401 / 403
   ↓
PollError::TokenExpired
   ↓
停止本次 Codex 查询
   ↓
不会启动 Codex CLI
```

后续用户正常打开或使用官方 Codex，使官方客户端刷新本地登录凭证后，监控器下一次轮询会重新读取 `auth.json` 并恢复查询。

## 5. 已删除的 Codex CLI 相关实现

本 Fork 直接删除以下函数：

```rust
fn cli_refresh_codex_token()
fn resolve_windows_codex_path()
```

因此同时删除了以下行为：

- 自动执行 `codex exec .`
- 自动调用 `codex --version`
- 使用 `where.exe` 搜索 Codex CLI
- 根据 `.cmd` / `.ps1` / `.exe` 类型构造 Codex 启动命令
- 为 Token 刷新创建隐藏 Codex 子进程

需要特别注意：

> **这是源码级删除，不是通过配置项关闭。**

当前不存在类似以下配置：

```json
{
  "allow_codex_cli_token_refresh": false
}
```

如果以后要恢复该能力，应明确重新设计为可控配置，而不是直接从 upstream 无条件恢复原逻辑。

## 6. `auth.json` 与凭证使用方式

Codex 凭证默认读取位置：

```text
$CODEX_HOME/auth.json
```

或：

```text
%USERPROFILE%\.codex\auth.json
```

程序主要使用：

```text
tokens.access_token
tokens.account_id
```

`auth.json` 文件本身不会上传到本 Fork 作者服务器，也没有独立后端、Analytics 或 Telemetry。

但 `access_token` 会作为 Bearer Token 通过 HTTPS 发往 ChatGPT Codex usage 接口，这是实时查询额度所必需的认证行为。

主要请求目标：

```text
https://chatgpt.com/backend-api/wham/usage
```

典型请求头：

```text
Authorization: Bearer <access_token>
ChatGPT-Account-Id: <account_id>
User-Agent: codex-cli
```

因此代理环境需要可信。若使用具备 HTTPS MITM 解密能力的代理软件，理论上其可以看到 HTTPS 请求内部的 Bearer Token。

## 7. Provider 默认状态

当前项目支持：

| Provider | 默认状态 | 主要凭证来源 |
| --- | --- | --- |
| Codex / ChatGPT | 开启 | `~/.codex/auth.json` |
| Claude Code | 关闭 | `~/.claude/.credentials.json` 或 WSL |
| Google Antigravity | 关闭 | Windows Credential Manager |

默认配置对应：

```rust
show_claude_code: false,
show_codex: true,
show_antigravity: false,
```

因此首次运行默认只查询 Codex。其他 Provider 需要从托盘菜单 `Monitored services` 手动开启。

本 Fork 只修改了 **Codex** 自动 Token 刷新逻辑；Claude Code 和 Antigravity 的既有认证行为未因本次安全修改而改变。

## 8. Windows 系统代理支持

新增：

```text
src/system_proxy.rs
```

项目原本的 `ureq` 已启用 `proxy-from-env`，因此显式配置以下环境变量时仍按原方式工作：

```text
HTTPS_PROXY
HTTP_PROXY
ALL_PROXY
```

本 Fork 在程序启动时增加 Windows 当前用户手动代理读取，代理优先级为：

```text
1. HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
        ↓ 未配置
2. Windows 当前用户手动系统代理
        ↓ 未启用或不可读取
3. 直连
```

Windows 系统代理读取位置：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

使用：

```text
ProxyEnable
ProxyServer
```

支持常见的统一代理格式：

```text
127.0.0.1:7890
```

以及按协议拆分格式：

```text
http=127.0.0.1:7890;https=127.0.0.1:7891
```

对于 HTTPS Provider 请求，协议拆分配置优先选择 `https=`；没有 `https=` 时回退到 `http=`。没有显式 URL scheme 的本地代理地址按 HTTP CONNECT 代理处理，例如：

```text
127.0.0.1:7890
```

转换为：

```text
http://127.0.0.1:7890
```

当检测到 Windows 系统代理后，程序仅在自身进程环境中设置：

```text
HTTPS_PROXY
HTTP_PROXY
```

不会修改 Windows 系统配置，也不会写回注册表。

诊断模式下只记录：

```text
using Windows system proxy
```

不会输出完整代理 URL，避免极端情况下代理字符串中的认证信息进入日志。

如果用户已经显式设置代理环境变量，则 Windows 系统代理不会覆盖它们。

当前明确不支持自动解析：

```text
PAC
WPAD
Automatically detect settings
```

本功能主要针对 FClash / Clash 等开启 Windows 手动“系统代理”的场景。

## 9. 任务栏外观与拖动交互

本 Fork 的任务栏外观只保留两套预设，通过右键菜单 `外观 / Appearance` 即时切换：

| 预设 | 任务栏表现 | 适用场景 |
| --- | --- | --- |
| 紧凑 | `5H  [进度 + 百分比]  13:40` / `7D  [进度 + 百分比]  09/11` | **默认**，保留重置时间 |
| 极简 | `5H  [进度 + 百分比]` / `7D  [进度 + 百分比]` | 最小占用 |

设置保存在：

```text
%APPDATA%\CodexUsage\settings.json
```

字段示例：

```json
{
  "appearance_preset": "compact"
}
```

旧配置中没有 `appearance_preset` 时默认使用 `compact`。历史版本如果已经保存：

```json
{
  "appearance_preset": "default"
}
```

新版会自动迁移为 `compact`，无需删除原有配置文件。

任务栏标签统一使用大写 `5H` / `7D`。重置时间继续使用 `13:40` / `09/11` 这种短格式，不再添加 `↻` 等额外图标。

百分比与进度条现在作为同一个视觉组件绘制，但百分比拥有独立的固定宽度区域：进度填充不会进入百分比区域，因此不需要根据填充颜色动态反色或增加文字描边。紧凑模式的重置时间仍位于组合进度组件右侧；极简模式隐藏重置时间，但托盘 Tooltip 继续保留完整额度和重置说明。

进度条使用 **1 个逻辑像素**的小圆角，避免低高度 GDI 圆角产生明显的胶囊感或锯齿感。

单独显示 Codex 时，进度条和主百分比继续按**剩余额度**使用状态色：

```text
剩余 > 50%       正常
剩余 20% ~ 50%   提醒
剩余 < 20%       警示
```

多 Provider 同时显示时仍优先保留各 Provider 的识别色。

### 拖动稳定性修复

拖动左侧手柄时，`WM_MOUSEMOVE` 不再在持有全局 `STATE` Mutex 的情况下调用会再次获取同一锁的 `current_appearance_preset()`，避免 UI 线程发生不可重入锁死。

同时增加 `WM_CAPTURECHANGED` 和 `WM_CANCELMODE` 清理路径：Windows 取消拖动或鼠标捕获意外丢失时会立即清除 `dragging` 状态，防止光标长期停留在左右调整状态以及任务栏输入被持续捕获。

CI 额外执行：

```text
scripts/assert-drag-handler-safe.ps1
scripts/assert-compact-ui.ps1
```

分别防止重新引入拖动期间的重复加锁路径，以及 Default 预设、重置图标、大圆角等已移除 UI 行为。

主任务栏显示不使用 Emoji。原因是当前 Win32 GDI / Segoe UI 绘制链路下彩色 Emoji 的字体回退、基线和尺寸一致性不可控；状态信息继续使用文字、几何进度条和颜色表达。

两套预设继续跟随 Windows 明/暗主题，不改变 Provider、Token、代理和轮询逻辑，也不会恢复 Codex CLI 自动刷新路径。
## 10. 安全回归检查

新增：

```text
scripts/assert-no-codex-cli-refresh.ps1
```

该脚本用于检查 `src/poller.rs`，确保没有重新出现以下关键路径：

```text
cli_refresh_codex_token(
resolve_windows_codex_path(
"exec", "."
```

同时要求 `poll_codex()` 的认证失败路径直接返回：

```rust
Err(PollError::TokenExpired)
```

若以后同步 upstream 时重新引入上述 Codex CLI 启动逻辑，安全检查会失败。

## 11. Windows CI / Build

新增：

```text
.github/workflows/safe-build.yml
```

主要执行流程：

```text
checkout
   ↓
Codex CLI 安全检查
   ↓
cargo test
   ↓
cargo build --release
   ↓
生成 codex-usage.exe
   ↓
生成 SHA256
   ↓
上传 Windows x64 Artifact
```

当前 Workflow 使用：

```yaml
permissions:
  contents: read
```

因此 CI 是只读的，不会自动修改、提交或 Push 源码。

构建产物包含：

```text
codex-usage.exe
codex-usage.exe.sha256
```

## 12. 后续同步 upstream 时的重点检查

以后从 `upstream-ray/codex-usage-monitor` 合并新版本时，重点检查 `src/poller.rs` 以及网络客户端初始化方式。

不要直接恢复以下模式：

```rust
Err(PollError::AuthRequired) => {
    cli_refresh_codex_token();
    // ...重新读取凭证并重试
}
```

也要检查 upstream 是否以新的函数名或新的 Provider 抽象重新加入类似行为，例如：

```text
Command::new("codex...")
cmd.exe /c codex...
powershell.exe ... codex.ps1
codex exec
codex app-server
codex --version
```

如果 upstream 调整 HTTP 客户端或移除 `ureq` 的 `proxy-from-env` 支持，需要同步确认 `src/system_proxy.rs` 注入的 `HTTPS_PROXY` / `HTTP_PROXY` 仍然能够被实际请求路径使用。

同步完成后至少确认：

```text
scripts/assert-no-codex-cli-refresh.ps1
cargo test
cargo build --release
```

全部通过。

如果 upstream 大幅重构 `poller.rs`，现有 PowerShell 静态检查可能因为函数结构变化而需要同步调整，但安全目标保持不变：

> **Codex 额度轮询不得主动创建 Codex CLI 子进程。**

## 13. 手工快速验证

源码级搜索建议：

```powershell
rg -n "cli_refresh_codex_token|resolve_windows_codex_path|codex.*exec|codex.*app-server|codex.*--version" src scripts
```

运行安全检查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\assert-no-codex-cli-refresh.ps1
```

执行测试和 Release 构建：

```powershell
cargo test
cargo build --release
```

检查 Windows 当前用户代理配置：

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' `
  -Name ProxyEnable,ProxyServer
```

运行诊断模式：

```powershell
.\codex-usage.exe --diagnose
```

日志位置：

```text
%TEMP%\codex-usage.log
```

启用 Windows 手动系统代理时，应能看到：

```text
using Windows system proxy
```

运行时若要进一步确认 Codex CLI 安全隔离，可以使用 Process Monitor、Sysmon 或 WMI 进程启动跟踪观察 `codex.exe` 的 Parent Process，确认 `codex-usage.exe` 没有创建 Codex CLI 子进程。

## 14. 关键 Git 记录

### Codex CLI 安全修改

工作分支：

```text
safe-no-codex-cli
```

核心生产代码提交：

```text
e9169f22aff2bedcb8790835b8c56f7acfa88571
fix: disable automatic Codex CLI token refresh
```

最终合并 PR：

```text
PR #1 - Disable Codex CLI token refresh in usage monitor
```

合并到 `main` 的提交：

```text
847a34ecd268560a0775caf25202274933ddfd44
Disable automatic Codex CLI token refresh
```

### Windows 系统代理修改

工作分支：

```text
windows-system-proxy
```

PR：

```text
PR #2 - Use Windows system proxy by default
```

主要新增文件：

```text
src/system_proxy.rs
```

---

后续维护本 Fork 时，应优先阅读本文档，再查看 `src/poller.rs`、`src/system_proxy.rs`、安全检查脚本和 `safe-build.yml`，即可快速了解本 Fork 与 upstream 最关键的行为差异。

