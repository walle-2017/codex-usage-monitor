# Codex-only v1 Cleanup Design

## Goal

将 Fork 收敛为仅监控 Codex 的 Windows 任务栏工具，并按明确阶段完成：功能收敛 → 死代码/分支清理 → 版本统一为 1.0.0 → 重写 README-FORK.md → main 上打 v1.0.0 Tag → 创建 v1.0.0 GitHub Release。

## Functional scope

运行时只保留 Codex：从 `$CODEX_HOME/auth.json` 或 `%USERPROFILE%\.codex\auth.json` 读取 `access_token/account_id`，通过现有 HTTPS usage API 获取 5H / 7D 配额，并在任务栏显示剩余额度。

彻底移除 Claude Code 和 Google Antigravity 的轮询、凭证、CLI/WSL 刷新、Credential Manager、状态字段、Tooltip、通知分支和右键菜单入口。

## No in-app update

删除程序内 GitHub Release 检查、自动更新 Timer、自更新 helper、WinGet 更新与安装渠道判断。右键菜单不再出现检查更新或更新动作。程序只显示只读版本号，不联网检查更新；后续 Fork 版本通过 GitHub Release 手动下载更新。

## Always-visible widget

删除 `widget_visible` 状态、设置字段、托盘左键隐藏/显示行为以及右键菜单中的“显示任务栏组件”入口。进程运行时任务栏组件始终显示；唯一隐藏方式是退出程序。

## Repository cleanup

功能收敛完成并验证后，再删除因此变成无用的 imports、constants、types、functions、localization fields、Cargo dependencies、历史 `iterations/` 过程目录和不再需要的 WinGet packaging。清理无用 Git 分支时只删除已经合并、明确属于历史实现或临时补丁的分支，不删除 `main`、当前清理分支或无法确认用途的分支。

## Version policy

Fork 版本从 `1.0.0` 重新开始，以下位置统一：Cargo package `1.0.0`、UI `v1.0.0`、Git Tag `v1.0.0`、GitHub Release `v1.0.0`。

## README-FORK.md

最终重写为“当前最终状态”文档，不按 PR/提交追加历史。对同一功能的多轮调整合并成最终规则，删除已被后续改动覆盖的中间状态。

## Release

只有在清理 PR 合并到 main 且 main CI 完整通过后，才在该 main commit 上创建 `v1.0.0` Tag 和 Fork 的 `v1.0.0` Release。Release 使用最终 main 构建产物及 SHA256。

## Safety constraints

- 绝不恢复 Codex CLI 自动 Token 刷新。
- 保留 Windows 系统代理支持。
- 保留 Explorer 重启 watchdog、单实例 mutex、拖动安全修复和现有任务栏布局行为。
- 程序内更新不是改成 Fork 更新源，而是彻底删除。
