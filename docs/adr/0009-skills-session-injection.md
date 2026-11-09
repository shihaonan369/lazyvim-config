# skills 投递改会话级注入：退出共享 agent 目录

日期：2026-11-09，状态：accepted

## 背景

0006 的自愈挂载把仓内 skills 链进 `~/.claude/skills` 与 `~/.agents/skills`
两个跨 agent 共享目录——离开 nvim 的会话（终端裸跑的 claude/codex/pi）也被
塞进 agent-sessions 这个依赖 `$NVIM` 的 skill，纯噪音。用户裁决（2026-11-08）：
改非侵入式——skill 只进 nvim agent pane 里 spawn 出来的会话，仓不写共享
agent 目录。

## 决定

- **投递随 spawn 走**（与 ADR 0007/0008 零安装房屋模式同构）：
  - **pi**：`pi_spawn_cmd` 追加 `--skill <config>/skills`（CLI 旗标，会话级）。
    实测门：RPC `get_commands`——全局链挪走后 40 个 skill 不含 agent-sessions，
    加 `--skill` 后 41 个含。
  - **claude**：`claude_spawn_cmd` 追加 `--plugin-dir <config>/scripts/
    agent-claude-plugin`（随仓插件壳：`.claude-plugin/plugin.json` + `skills/`
    相对链回仓内实体源；flag 自述 "for this session only"，2.1.312）。
  - **codex**：无 CLI 注入口（`-c` 只达 config.toml；`skills.config` 的 path
    条目实测**不能**注册未发现的 skill，只能启停已发现的）——唯一残留：自愈
    挂载到 codex 自家 `~/.codex/skills`（官方文档未列、`codex debug
    prompt-input` 实证的发现目录），不再进共享目录；裸跑 codex 仍可见，靠
    description「仅 env 有 NVIM」路由护栏。上游出注入口后撤此挂载收敛到全注入。
- **lazy.lua 挂载块改造**：旧两处共享目录挂载删除，改为**自愈卸载**（指回
  本仓 `skills/<name>` 的链启动即清，他人实体不碰）——旧机/克隆/devcontainer
  升级零手工；新挂载仅 `~/.codex/skills` 一处，沿用断链重建/占名保护规则。
- skill 实体源仍在仓 `skills/<name>/`（0006 的 source of truth 不变），本 ADR
  只改投递面。

## 弃选

- **pi 侧装全局扩展按 `$NVIM` 探测注入**：违 0008「机器侧 ~/.pi 零依赖」裁决。
- **codex config.toml 常禁 `[[skills.config]]` + spawn `-c` 启用**（实测可行）：
  为一条描述行引入 nvim 写 `~/.codex/config.toml`，不成比例。
- **CODEX_HOME 重定向**：auth/state 全随迁，重且脆。

## 已知边界

- 裸终端 codex 仍见 agent-sessions（`~/.codex/skills` 挂载），description
  自带路由护栏。
- 终端里手动跑的 claude/pi（含 nvim `:terminal` 里手敲的）不见 skill——本就
  依赖 `$NVIM` 且 pane 工作流走 spawn，可接受。
- resume：三家 resume 都经各自 `spawn_cmd` 包装，注入随行不丢。
