---
name: agent-sessions
description: 在 nvim agent pane 里批量创建/投喂/命名/删除 Claude 或 Codex 或 Pi session。当用户要按 Gitee issue 建会话、多开并行 agent、「建几个 session」时使用。仅适用于经 nvim agent_sessions 插件 spawn 的 Claude/Codex/Pi（env 有 NVIM）。
---

# agent-sessions 远程驱动

从 Claude/Codex/Pi session 内控制宿主 nvim 的 `agent_sessions` 模块（lua/agent_sessions.lua），
批量建 agent 会话。所有控制经 `nvim --server "$NVIM" --remote-expr` →
`luaeval` → 本 skill 的 `scripts/asend.lua`（挂 `_G.*` API）。

## 前提

- `echo $NVIM` 非空（在 nvim agent pane 里跑的 Claude/Codex/Pi 才有）。没有则本 skill
  不适用，先进入 nvim 的 agent pane。
- nvim cwd = 项目根；新 session 使用宿主配置的 Agent 类型。Claude 按原有路径加载 CLAUDE.md；Codex/Pi 加载 AGENTS.md 和自身配置。
- Claude 须支持 `--name`（已验证 2.1.317；`claude --help` 可查）；新建带名走启动参数，不走 TUI 自动改名。
- Neovim 启动时把本 skill 挂到 `~/.claude/skills` 与 `~/.agents/skills`；Codex 中通过 `/skills` 或 `$agent-sessions` 选择。

## 快速路径（一条命令一个会话）

```bash
~/.config/nvim/skills/agent-sessions/scripts/spawn_one.sh <会话名> [prompt文件]
```

建会话＋带名，命令即回 id。Claude 名字随 `--name` 在启动时设置，Pi 随 `-n`；
均不依赖自动改名注入。Codex 名称仅存于 Neovim，不写入 Codex 历史。
prompt 文件由就绪队列等待输入框后投递（60s 未就绪作废）：Claude 额外 settle
1.2s，再括号粘贴＋400ms 延时 CR 提交。Claude 树名以 transcript 回流为准，返回 id 不等于名字已回流。
会话名惯例＝issue 号（如 IKMGVU）。批量＝for 循环，**同 worktree 并发 ≤4**
（撞文件风险，用户并行习惯上限）。

## 手动 API（call 模式）

```bash
call() { nvim --server "$NVIM" --remote-expr "luaeval(\"(function() dofile('$HOME/.config/nvim/skills/agent-sessions/scripts/asend.lua') return $1 end)()\")"; }
call '_G.aspawn([[IKMGVU]])'  # 建会话（可选启动带名）→ 返回 id
call '_G.aready(7)'         # 'ready'/'wait'（Claude ❯ / Codex › / Pi ─ 规则线就绪）
call '_G.arename(7, [[IKMGVU]])'  # 事后改名（aspawn 已带名则不必）
call '_G.aprompt_file(7, [[/tmp/p.md]])'   # 就绪后投喂，prompt 从文件读，多行安全
call '_G.alist()'           # 会话清单（id/state/name/current）
call '_G.abuf(7, 10)'       # buffer 尾部非空行（排障）
call '_G.adelete(7)'        # 优雅退出（Claude /exit，Codex /quit，Pi Ctrl+C→Ctrl+D）
```

## 铁律与坑（2026-10-17 全链路实证）

- **转义**：`\r`(CR)/`\21`(Ctrl-U)/`\27[200~`(括号粘贴) 只允许写在 asend.lua
  里。调用侧内联这些序列会被 bash→vim 双层转义半路展开（`\r` 炸 E5107、
  `\21` 被吞变字面量）。传内容一律 `[[...]]` 或文件路径。
- **文字与 CR 必须分开发**（注入已统一分包：M.rename/arename 300ms、
  aprompt 400ms 延时 CR；队列按占用时长串行）——同包紧跟的 CR 会被 TUI
  吞掉，命令躺输入框不提交。
- **禁用 `agent_sessions.M.send()`**：它附带 M.focus() 抢用户焦点；本 skill 的
  API 全部 chansend 直注，不碰焦点。
- **spawn 期吞字 ≠ 回流滞后**：Claude 的 ❯ 首帧可能早于输入循环启动；
  此时 channel 发送成功也可能丢掉整条 `/rename`。skill 新建用 `claude_spawn.sh`
  把名字还原成一个 `--name` 参数，绕开该窗口；首发 prompt 另加 settle。
- Claude 分支的 `M.claude_open` 带 `--session-id <uuid>` 保证新建；focus=false
  防抢焦点；第 4 参留空（传名字会重新启用有竞态的自动 `/rename` 队列）。
  helper 的名字 token 是 base64，因为宿主按空白拆命令，不解析 shell 引号。
- **事后 `arename` 会清草稿**：仅在会话空闲、没有用户未提交文字时补发；
  已工作的会话先与用户确认，避免毁掉输入或把命令混进任务。
- prompt 走括号粘贴，含 `[[`/`]]` 的内容改用文件路径传入更稳。

## 排障

- 就绪超时（nvim 队列 60s 作废）：`_G.abuf(id)` 看 buffer——有 banner 无对应输入框
  是启动慢；空 buffer 是 termopen 没起来（alist 看 state）。
- 新建后无名：先用 `_G.alist()` / `_G.abuf(id)` 确认会话仍活着，再查该会话
  transcript 的 `custom-title` / `customTitle`。已有目标名＝回流显示问题；没有＝
  尚未落盘或命名未生效。Claude 2.1.317 的 `--name` 可先在 TUI 标题生效，
  transcript 却直到首条输入提交才创建；**无 prompt 的新会话，树名可能暂缺，
  首条输入后再核验**。不要用 transcript born 作为首发 prompt 的硬闸（会死等）。
  `custom-title.json` 的存在与否不足以判定失败。
  旧版 skill 的 trace 若有 `command … /rename … ok=true` 却始终无 `apply id=`
  且 transcript 无目标名，符合启动吞字；更新 skill 后用一次性新会话验证。
  旧会话需要补名时，确认空闲且无草稿，再 `_G.arename(id, [[名字]])`，以 transcript
  的目标名或 `_G.alist()` 名字回流为完成判据；不自动重试去碰用户输入。
- 提交无效：确认文字与 CR 分包；输入框残留草稿可能是 CR 被吞，整段消失可能是
  TUI 尚未消费输入。先确认用户草稿归属，再通过 skill 的分包入口重发。

## 维护验证

`bash skills/agent-sessions/scripts/test-spawn.sh`：真实 skill → 插件 spawn → 假 Claude
PTY，模拟 ❯ 先出现、早期输入被丢；断言 transcript 名字回流、名字参数完整、无自动
`/rename`、首发 prompt＋CR 幸存、后台创建不抢焦点，以及后续普通新建不继承旧名字。
不使用用户的 live 会话。
