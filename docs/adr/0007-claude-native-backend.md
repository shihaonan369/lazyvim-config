# claude 原生后端：弃用 claudecode.nvim，自持 spawn + 原生 CLI 通道

日期：2026-10-20，状态：accepted（磨合期，双后端并存）

## 背景

claude 集成自始用 `coder/claudecode.nvim`（11,045 LOC）。盘点证实本仓的
session 池/pane/领地/tab 视口/树/状态管线/名字续流/skill/回归门早已全部自持，
对插件的真实依赖只有三处：provider 桥（`lua/plugins/claudecode.lua`）、冷启动
`vim.cmd("ClaudeCode")`（agent_sessions）、spawn env 的 IDE 三件套
（`ENABLE_IDE_INTEGRATION`/`FORCE_CODE_TERMINAL`/`CLAUDE_CODE_SSE_PORT`）。
插件的真身是跑在 nvim 里的 WebSocket MCP 服务端（`~/.claude/ide/<port>.lock`
+ claude 反连），@引用/选中广播/OpenDiff/10 个 IDE 工具全走这条**无文档内部
协议**通道。

动因（用户裁决 2026-10-20）：太重、只用一小块；收回控制权。

## 决定

- **native 后端为默认**：`lua/plugins/claude.lua`（本地 dir spec，与 codex.lua
  同构）持有全部键位；`adapters.claude.new` 自构 `{claude}` 直 spawn（cmd/env
  经既有 `claude_spawn_cmd`/`claude_spawn_env` 收口，`--settings`/NO_FLICKER/
  沙箱 bypassPermissions 语义不变）。
- **磨合期双后端并存，一键回退**：`vim.g.claude_backend`（options.lua 默认
  `"native"`，`CLAUDE_BACKEND` env 覆盖，仿 `ai_assistant` 同款隐喻）。plugin
  态下 provider 桥、`:ClaudeCode` 冷启动链、宽度守卫原样保留——就是今天。
  切换 = env/默认值 + 重启（session 进程随 nvim 亡，transcript 常驻，
  `--continue`/`-r` 即回，应急语义可接受）。
- **上下文投递走 PTY 注入，不走协议桥**：`<leader>as` 构造 `@path` 草稿注入
  TUI 输入框不提交（复用就绪队列/括号粘贴），`<leader>aM` 走 `M.command`
  （rename 同款 Ctrl-U + 文字 + 延时 CR 序列的通用化）。
- **inline diff 走 hooks 快照 + 状态邮箱**（后续层落地）：PreToolUse 快照、
  PostToolUse 推既有邮箱、nvim 侧开 diff；accept=删快照、deny=快照写回。
- **收官摘除（0b）推迟到磨合期后用户拍板**：删 claudecode.lua、provider 桥
  （`M.claude_toggle`/`M.show_only`/`S.intent`/`S.claude_cache`）、宽度守卫，
  ADR 0001/0005 的插件引用历史化。

## 弃选

- **对等移植 WS 桥**（vendor server/+lockfile+at-mention ≈2k 行，diff 重写）：
  6-9 session + 永久协议跟进税——WS 上的 MCP 握手/payload 是 claude 无文档
  内部契约，失效即层 1+2 整体消失、无降级路径。与 ADR 0003 已接受的
  custom-title 依赖不是一个量级（那个是单点、可静默降级）。PTY 注入的失败
  模式是降级不是失效（`@path` 作纯文本模型也能读）。
- **git revert 作应急回退**：慢且重；运行中被打断时要求秒级切换。
- **运行时热切后端**：两套键位/命令面互斥语义复杂化，重启+resume 已够。

## 已接受的语义取舍（native 态）

- IDE 三件套不注入：mention chip 富展示、claude 主动拉 selection/diagnostics
  的 10 个 MCP 工具面消失（"claude 反驱 nvim"由 skill 侧 `$NVIM
  --remote-expr` 部分覆盖）。
- `<leader>aC/aR/aM/as` 语义：cwd 界"最近"、TUI 原生 picker、注入式 /model、
  草稿式 @引用（过目后自己 CR）。
- inline diff（后续层）：**先落后审 + 一键回滚**，非插件的"先审后落"。
  原生"先审后落" = 非沙箱 permission mode + TUI 自带审批（attention 状态
  已接管线）。

## 已知边界

- native 态 `S.claude_cache` 只作「上次可执行」记忆沿用（skill aspawn 后同
  二进制），env 不沿用（那是插件 IDE 三件套）。
- `AGENT_CLAUDE_BIN` 在模块加载时求值——headless 门须先设 env 再
  require（test-agent-named 判据 0）。
- 插件路径的宽度守卫（`nvim_win_set_width` 包装、`guard_display_width`）在
  并存期保留（plugin 态仍需），0b 一并摘除。
