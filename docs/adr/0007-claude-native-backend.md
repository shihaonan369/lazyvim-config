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

- **native 后端为默认**：`lua/plugins/agent.lua`（**唯一**的本地 dir spec，
  吞并原 codex.lua 与 claude.lua）持有全部键位，config 内按 ai_assistant/
  claude_backend 分流；`adapters.claude.new` 自构 `{claude}` 直 spawn（cmd/env
  经既有 `claude_spawn_cmd`/`claude_spawn_env` 收口，`--settings`/NO_FLICKER/
  沙箱 bypassPermissions 语义不变）。另注册 `:ClaudeCode` 兼容命令（无参=新建、
  带参透传，ADR 0001 的命令面契约）。
  **为什么必须唯一 dir spec（2026-10-21 案）**：lazy.nvim 把同 dir 的多个
  spec 合并成一个裁决者——claude-config 与 codex-config 同指
  stdpath("config") 时，claude 态两者双双从 plugins 表消失（症状：「只有
  agent tab 没有 pane」——pane 键位全 housed 在 spec 里，而 `<leader>at`
  在全局 keymaps.lua 幸存）。codex 态恰好幸存是因裁决落在 codex 侧。
- **磨合期双后端并存，一键回退**：`vim.g.claude_backend`（options.lua 默认
  `"native"`，`CLAUDE_BACKEND` env 覆盖，仿 `ai_assistant` 同款隐喻）。plugin
  态下 provider 桥、`:ClaudeCode` 冷启动链、宽度守卫原样保留——就是今天。
  切换 = env/默认值 + 重启（session 进程随 nvim 亡，transcript 常驻，
  `--continue`/`-r` 即回，应急语义可接受）。
- **上下文投递走 PTY 注入，不走协议桥**：`<leader>as` 构造 `@path` 草稿注入
  TUI 输入框不提交（复用就绪队列/括号粘贴），`<leader>aM` 走 `M.command`
  （rename 同款 Ctrl-U + 文字 + 延时 CR 序列的通用化）。
- **inline diff 走 PostToolUse 快照**（层 2 已落地，2026-10-20 原型修订）：
  单钩 `scripts/agent-diff-hook.sh`（matcher `Edit|Write|MultiEdit|NotebookEdit`）
  落 `tool_response.originalFile`（本回合该文件首次编辑前的完整原文，hook
  JSON 实证携带）为回合基线，路径 = `$AGENT_DIFF_DIR/$AGENT_SESSION_TAG
  <绝对路径镜像>`。nvim 侧 `lua/agent_diff.lua` 只在按键时扫描（零轮询），
  `<leader>ad` 审查视图开**专属 tab**（建于末尾，equalalways 只在 tabpage 内
  重排——主区开窗会把 pane 一并重排，违反 ADR 0002「几何只属于用户」）；
  accept=删快照（改动留盘），deny=基线字节级写回（fs_copyfile）+checktime；
  ExitPre 清本实例 tag 目录。邮箱事件取消：originalFile 使 PreToolUse 与
  推送事件都成冗余。
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

- **本仓 dir spec 只允许一个**（agent.lua）——再添 `dir = stdpath("config")`
  的 spec 会触发 lazy 同 dir 合并互吞（见决定节的 2026-10-21 案）。
- **headless 全配置 ≠ 真实会话**：`nvim --headless`（真配置）下 lazy 的
  启动加载不完整（keymaps.lua 不被 source、start 插件 config 不跑）——spec
  层验证必须走 PTY 真 TUI（`script -q <log> nvim --listen <sock>` +
  `--remote-expr` 驱动，本仓 asend 同款通道）。
- native 态 `S.claude_cache` 只作「上次可执行」记忆沿用（skill aspawn 后同
  二进制），env 不沿用（那是插件 IDE 三件套）。
- `AGENT_CLAUDE_BIN` 在模块加载时求值——headless 门须先设 env 再
  require（test-agent-named 判据 0）。
- `--bare` 会跳过全部 hooks（CLI help 明示）——native 态的 spawn 链路禁用
  `--bare`（当前不经此旗标）。
- buffer 名经 `:edit` 的符号链接解析（macOS `/var`→`/private/var`），与
  hook 上报路径（claude 侧已解析）比较时须 `resolve()` 对齐（deny 的
  checktime 匹配、回归门判据同）。
- 快照 `readfile/writefile` 为文本语义（deny 走 `fs_copyfile` 字节级写回，
  审查窗的 scratch 显示不保二进制保真）。
- 插件路径的宽度守卫（`nvim_win_set_width` 包装、`guard_display_width`）在
  并存期保留（plugin 态仍需），0b 一并摘除。
