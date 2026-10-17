---
name: agent-sessions
description: 在 nvim agent pane 里批量创建/投喂/命名/删除 claude 会话。当用户要按 Gitee issue 建会话、多开并行 agent、「建几个 session」时使用。仅适用于经 nvim agent_sessions 插件 spawn 的 claude（env 有 NVIM）。
---

# agent-sessions 远程驱动

从 claude 会话内控制宿主 nvim 的 `agent_sessions` 模块（lua/agent_sessions.lua），
批量建 agent 会话。所有控制经 `nvim --server "$NVIM" --remote-expr` →
`luaeval` → 本 skill 的 `scripts/asend.lua`（挂 `_G.*` API）。

## 前提

- `echo $NVIM` 非空（在 nvim agent pane 里跑的 claude 才有）。没有则本 skill
  不适用，退化方案：tmux 起新终端跑 claude（不进 pane 注册表）。
- nvim cwd = 项目根；新会话继承 CLAUDE.md/memory/bypassPermissions（IS_SANDBOX=1）。

## 快速路径（一条命令一个会话）

```bash
~/.config/nvim/skills/agent-sessions/scripts/spawn_one.sh <会话名> [prompt文件]
```

建会话＋带名，prompt 文件则括号粘贴＋延时 CR 提交——命令即回 id，改名/投喂
在 TUI 就绪后由 nvim 侧就绪队列自动送达（先改名后投喂，60s 超时作废）。
会话名惯例＝issue 号（如 IKMGVU）。批量＝for 循环，**同 worktree 并发 ≤4**
（撞文件风险，用户并行习惯上限）。

## 手动 API（call 模式）

```bash
call() { nvim --server "$NVIM" --remote-expr "luaeval(\"(function() dofile('$HOME/.config/nvim/skills/agent-sessions/scripts/asend.lua') return $1 end)()\")"; }
call '_G.aspawn([[IKMGVU]])'  # 建会话（可选带名，就绪后自动命名）→ 返回 id
call '_G.aready(7)'         # 'ready'/'wait'（输入框 ❯ 渲染即就绪，启动约 3-10s）
call '_G.arename(7, [[IKMGVU]])'  # 事后改名（aspawn 已带名则不必）
call '_G.aprompt_file(7, [[/tmp/p.md]])'   # 就绪后投喂，prompt 从文件读，多行安全
call '_G.alist()'           # 会话清单（id/state/name/current）
call '_G.abuf(7, 10)'       # buffer 尾部非空行（排障）
call '_G.adelete(7)'        # 优雅退出（/exit 注入）
```

## 铁律与坑（2026-10-17 全链路实证）

- **转义**：`\r`(CR)/`\21`(Ctrl-U)/`\27[200~`(括号粘贴) 只允许写在 asend.lua
  里。调用侧内联这些序列会被 bash→vim 双层转义半路展开（`\r` 炸 E5107、
  `\21` 被吞变字面量）。传内容一律 `[[...]]` 或文件路径。
- **文字与 CR 必须分开发**（asend.lua 内已用 defer_fn 隔开）——同包紧跟的 CR
  会被 TUI 吞掉，prompt 躺输入框不提交。
- **禁用 `agent_sessions.M.send()`**：它附带 M.focus() 抢用户焦点；本 skill 的
  API 全部 chansend 直注，不碰焦点。
- 命名回流滞后：claude 侧 `custom-title.json` 即时落名，nvim 树/pane 的名字靠
  transcript 事件搭车刷新，闲置会话可能一直不显示——不是失败。
- `M.claude_open` 带额外参数（`--session-id <uuid>`）才走 spawn 新会话分支，
  单 `claude` 两参只聚焦现有会话；focus=false 防抢焦点；第 4 参 = 会话名
  （就绪队列注入，与 nvim 侧 <leader>aN 同一条链）。
- prompt 走括号粘贴，含 `[[`/`]]` 的内容改用文件路径传入更稳。

## 排障

- 就绪超时（nvim 队列 60s 作废）：`_G.abuf(id)` 看 buffer——有 banner 无 ❯
  是启动慢；空 buffer 是 termopen 没起来（alist 看 state）。
- 提交无效：确认 CR 是延时分发的；看 abuf 输入框是否残留草稿（残留＝CR 被吞，
  补 `_G.asend` 系列手动 `\13`——只在 asend.lua 里维护，不要内联）。
