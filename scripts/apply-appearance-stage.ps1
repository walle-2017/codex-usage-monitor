# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'
$path = 'README-FORK.md'
$text = Get-Content -Raw -Path $path
$marker = '## 9. 任务栏外观预设'
if ($text.Contains($marker)) {
    Write-Host 'Fork appearance notes already present.'
    exit 0
}

$needle = '## 9. 安全回归检查'
$section = @'
## 9. 任务栏外观预设

本 Fork 新增 `src/appearance.rs`，提供三套内置任务栏外观，通过右键菜单 `外观 / Appearance` 即时切换：

| 预设 | 任务栏表现 | 适用场景 |
| --- | --- | --- |
| 默认 | `19%  ↻13:40`，空间更宽松 | 信息完整 |
| 紧凑 | `19%  13:40`，更细的进度条和更短宽度 | **默认推荐** |
| 极简 | `19%`，隐藏任务栏重置时间 | 最小占用 |

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

旧配置中没有该字段时默认使用 `compact`，因此无需删除原有 `settings.json`。

任务栏数值采用分层显示：百分比使用更醒目的字重和字号，重置时间使用更小、更弱的次级文字；极简模式虽然不在任务栏显示重置时间，但托盘 Tooltip 仍保留完整额度和重置说明。

单独显示 Codex 时，进度条和主百分比会按**剩余额度**使用状态色：

```text
剩余 > 50%       正常
剩余 20% ~ 50%   提醒
剩余 < 20%       警示
```

多 Provider 同时显示时仍优先保留各 Provider 的识别色，避免不同服务难以区分。

三套预设继续跟随 Windows 明/暗主题，不改变 Provider、Token、代理和轮询逻辑，也不会恢复 Codex CLI 自动刷新路径。

'@

if (-not $text.Contains($needle)) {
    throw 'Unable to locate README insertion point.'
}
$text = $text.Replace($needle, $section + $needle)
# Renumber following headings to keep the fork document sequential.
$text = $text.Replace('## 10. Windows CI / Build', '## 11. Windows CI / Build')
$text = $text.Replace('## 11. 后续同步 upstream 时的重点检查', '## 12. 后续同步 upstream 时的重点检查')
$text = $text.Replace('## 12. 手工快速验证', '## 13. 手工快速验证')
$text = $text.Replace('## 13. 关键 Git 记录', '## 14. 关键 Git 记录')
$text = $text.Replace('## 9. 安全回归检查', '## 10. 安全回归检查')
Set-Content -Path $path -Value $text -Encoding utf8NoBOM
Write-Host 'Inserted fork appearance notes.'
