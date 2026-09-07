$ErrorActionPreference = 'Stop'
$readmePath = Join-Path $PSScriptRoot '..\README-FORK.md'
$readme = Get-Content -Raw $readmePath

$section = @'
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

'@

$pattern = '(?s)## 9\. 任务栏外观预设.*?(?=## 10\. 安全回归检查)'
$updated = [regex]::Replace($readme, $pattern, $section, 1)
if ($updated -eq $readme) {
    throw 'README-FORK appearance section was not replaced.'
}
Set-Content -Path $readmePath -Value $updated -Encoding utf8NoBOM -NoNewline

& (Join-Path $PSScriptRoot 'assert-drag-handler-safe.ps1')
& (Join-Path $PSScriptRoot 'assert-compact-ui.ps1')
git diff --check
