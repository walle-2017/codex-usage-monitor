# Codex-only v1 Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Fork 收敛为 Codex-only 工具，并按功能收敛、死代码/分支清理、版本 1.0.0、README-FORK 重写、v1.0.0 Tag/Release 的顺序完成。

**Architecture:** 先删除运行时多 Provider、自更新与 widget visibility 行为，并用静态回归约束锁定最终边界；之后再清理由此产生的死代码和仓库历史内容。版本和发布动作最后执行，确保 Tag 指向已验证的最终 main。

**Tech Stack:** Rust 2021, Win32 API, PowerShell regression scripts, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-codex-only-v1-cleanup-design.md`

## Global Constraints

- Codex CLI 自动 Token 刷新必须继续保持源码级禁用。
- 保留 Windows 系统代理、Explorer watchdog、单实例 mutex、拖动安全和现有任务栏 UI 行为。
- 程序内更新必须彻底移除，不改成 Fork 自动更新。
- Fork 最终版本统一为 `1.0.0` / `v1.0.0`。

---

### Task 1: 收敛运行时功能

**Files:** `src/poller.rs`, `src/window.rs`, `src/tray_icon.rs`, `src/main.rs`, `src/models.rs`, `src/localization/*`, `.github/workflows/safe-build.yml`, `scripts/assert-codex-only-runtime.ps1`

- [ ] 先新增失败的 Codex-only/no-updater/always-visible 静态检查。
- [ ] 验证 RED：现有 main 必须因 Claude/Antigravity、updater、widget toggle 仍存在而失败。
- [ ] 删除 Claude Code/Antigravity 轮询和运行时状态，`poll()` 变成 Codex-only。
- [ ] 删除程序内更新入口、Timer、状态和菜单动作，删除 `src/updater.rs`。
- [ ] 删除 widget visibility 状态、设置和托盘/菜单切换。
- [ ] 保留只读版本号菜单项，但此阶段仍沿用当前包版本。
- [ ] 更新受影响测试并运行 Safe Windows Build，要求全部通过。

### Task 2: 死代码、依赖和仓库分支清理

**Files:** `Cargo.toml`, `Cargo.lock`, `src/*`, `src/localization/*`, `docs/*`, `iterations/*`, `packaging/winget/*`, `scripts/*`

- [ ] 删除 Task 1 后未使用的 import/type/function/localization 字段和依赖。
- [ ] 删除 WinGet packaging 与历史 `iterations/`。
- [ ] 更新 installer，任何在线仓库引用不得指向 upstream。
- [ ] 运行 `cargo test`、`cargo clippy -- -D warnings`、release build 和静态检查。
- [ ] 列出远程分支，仅删除已合并且明确属于历史 PR/临时补丁的分支；保留 main 和当前分支。

### Task 3: 统一版本为 1.0.0

**Files:** `Cargo.toml`, `Cargo.lock`, UI/version display, installer/docs metadata as applicable.

- [ ] 将包版本统一为 `1.0.0`。
- [ ] 只读版本菜单显示 `v1.0.0`。
- [ ] 全仓搜索旧版本字符串并清理不应保留的产品版本引用。
- [ ] 运行完整 CI。

### Task 4: 重写 README-FORK.md

**Files:** `README-FORK.md`, 必要时 `README.md`, `README.zh-CN.md`, `docs/installation.md`, `docs/troubleshooting.md`。

- [ ] 将 README-FORK 改成最终状态文档，整合同一处的多轮变更。
- [ ] 删除 Claude/Antigravity、WinGet、自更新、widget visibility 和过时 UI 中间状态描述。
- [ ] 与当前源码、CI 和 settings 字段逐项核对。

### Task 5: 合并、Tag 和 Release

- [ ] PR 最终 CI 通过后合并到 main。
- [ ] main post-merge CI 再次全部通过并取得最终 Windows artifact + SHA256。
- [ ] 在该 main commit 创建 `v1.0.0` Tag。
- [ ] 由 Fork release workflow 或 GitHub Release API 创建 `v1.0.0` Release，确保产物来自同一 Tag/commit。
- [ ] 验证 Release 页面、Tag commit 和 artifact checksum 一致。
