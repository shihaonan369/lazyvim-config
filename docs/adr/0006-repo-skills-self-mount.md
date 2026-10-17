# 仓带 skills 自愈挂载：~/.claude/skills 的 source of truth 在本仓

日期：2026-10-17，状态：accepted

## 背景

agent-sessions skill（在 claude 会话内远程驱动宿主 nvim 的 agent_sessions 模块）
实体在本仓 `skills/agent-sessions/`，消费侧挂载点是 `~/.claude/skills/agent-sessions`
（claude CLI 的 skill 发现目录）。此前挂载靠手工 `ln -sfn`：devcontainer 重建
（/root 清空 → 重新克隆本仓）后挂载即丢，每次环境重建都要重来一遍——这正是
要消灭的「每次建立环境还得重新来一遍」。

## 决定

- **本仓 `skills/<name>/` 目录 = skill 实体源**，随 git 分发；`~/.claude/skills`
  里同名条目只是挂载点，不是副本。
- `lua/config/lazy.lua` 引导段（与 lazy.nvim bootstrap 同层：那里已是
  fs_stat+补建范式）每次启动自愈挂载：
  - 名下无物 → 建 symlink（绝对路径，目标 = `stdpath("config")/skills/<name>`，
    运行时求值——HOME 迁移后的断链下次启动自动重建）；
  - 断链（目标已消失）→ 删链重建；
  - 名字被他人实体占用——真实目录（如 skillhub 的 `@tencent-adm`）或外指
    有效链（如 `~/.agents` 的既有接线）——**不碰**，WARN 提醒一次；
  - 全程 pcall/返回值判定，失败静默不炸启动；发生修复 notify 一行。
- 只接管 `skills/` 子目录名单内的名字：不扫描、不清理 `~/.claude/skills`
  其他条目，与 skillhub 的 store 零交集。

## 弃选

- **仓库 bootstrap 脚本**（README 安装段 / stow / chezmoi）：本仓无安装脚本
  体系，为一个 symlink 引入一套分发机制不成比例；nvim 启动自愈已覆盖
  「克隆＋起 nvim」全流程，不多一步手工。
- **写时拷贝**（copy 而非 symlink）：仓内文件更新后 `~/.claude` 侧陈旧分化，
  需再加同步机制——轮询/抓取类方案，明确不做。
- **agent_sessions.setup() 内做**：setup 只在 provider 插件 config 时执行，
  且把环境装配混进 session 运行域，层次不符（用户裁决 2026-10-17）。

## 已知边界

- asend.lua 的 uuid 读 `/proc/sys/kernel/random/uuid`，Linux 容器成立；macOS
  上 `_G.aspawn` 不可用（其余 API 不依赖 /proc）。挂载本身跨平台无副作用。
- Windows 宿主直接跑本配置时 `fs_symlink` 需开发者模式/权限，失败走静默
  分支（当前无此场景，不为其加复杂度）。
- 判据落在 `lua/config/lazy.lua` 的 `[skill-mount-begin/end]` 标记区间，
  `scripts/test-skill-mount.sh/.lua` 提取该区间原文在沙箱 HOME/XDG 下实测。
