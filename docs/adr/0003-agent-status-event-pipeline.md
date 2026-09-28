# Agent 状态事件管线：边缘归一 + env 归因 + 文件邮箱 + fs_event

日期：2026-09-27，状态：accepted

需求：statusline 里逐 session 显示 agent 状态（working / idle / attention），pane 收起时全体闭眼、颜色仍实时更新。约束是硬的：拒绝 timer 轮询、拒绝终端输出/文案抓取；没有干净机制就宁可不做（用户既有裁决）。三路核实（claude/codex 官方文档、opencode 源码与文档、nvim 0.12.5 本机实测）后确认三家都有官方事件出口，本管线成立。

## 决定

```
spawn 注入 env ──> agent 进程 ──> 边缘归一化 ──> 文件邮箱 ──> nvim fs_event ──> S.sessions[i].state ──> statusline
AGENT_SESSION_TAG      claude/codex hooks      每 nvim 实例     按新行读+tag 归因    随 TermClose 自灭      emit() 刷新
AGENT_STATUS_FILE      （共用 scripts/agent-status-hook.sh）    一个文件
                       opencode ts 插件镜像
```

- **状态词表**：`working`（回合进行）/ `idle`（一轮完成、等待输入）/ `attention`（待确认）。**"completed"=idle，不是进程退出态**——session 退出即完全移除、不留显示不留色（与 ADR 0001 无墓碑一致）。
- **归因**：`spawn()` 一处给三家注入 `AGENT_SESSION_TAG=<nvim getpid()>.<sess.id>` 与 `AGENT_STATUS_FILE`。文件路径走 env 而非写死进 hook 配置，于是每 nvim 实例一个邮箱（`stdpath("run")`，本实例私有临时目录），零跨实例过滤；agent 在 nvim 外裸跑时 env 未设，脚本静默 no-op，互不干扰。
- **边缘归一**：claude/codex 的 hooks 配置按事件分条目，状态词直接写死在各条目 argv 里，`scripts/agent-status-hook.sh` 零 JSON 解析（5 行）；opencode 插件把事件总线映射成同一状态词。邮箱里只有 `{"tag":…,"state":…}` 单行 JSON，append < PIPE_BUF 原子。
- **事件订阅**（claude / codex 同构）：`UserPromptSubmit`/`PostToolUse`→working、`Stop`→idle、`PermissionRequest`→attention；codex 另有 `Interrupt`→idle。`PostToolUse` 的作用是 attention 态的恢复信号（批准后 agent 继续干活）。
- **nvim 侧**：`luv fs_event`（macOS FSEvents，实测即时回调；`vim.fs.watch` 不存在）监听追加，seek 到已读 offset 只消费新完整行（残行留待续读，截断兜底归零）；状态挂在 `S.sessions[i].state`，TermClose 移除 session 时状态随之消失，**零垃圾回收**；变化后 `emit()`（既有 `redrawstatus` + `User AgentSessionsChanged`）驱动 statusline，闭眼颜色实时性由此保证。
- **渲染**：`M.status()` 每 session 一个 `<leader>a` 同款图标（U+EE0D），当前 session 加方括号；pane 收起时全体换闭眼（nf-md-eye_off，U+F0209）。颜色用内嵌 `%#Group#`（lualine 对组件串内嵌 `%#` 是一等支持，`component.lua` 显式处理）。`#N/M` 前缀弃用——图标个数即 session 数，顺序=编号顺延。（曾评估"同字形大小两档"标记当前：需借 Ghostty 字体槽（Mono 压缩/非 Mono 自然宽）+ bold 属性路由，机制复杂且有 ModeMsg 本身带 bold 的连带坑，弃。）
- **降级**：claude 侧 hooks 由 spawn 自动注入（见下）恒生效；codex/opencode 的机器侧配置未装时状态恒为 nil，图标呈中性色（`ModeMsg`），不报错。

## 弃用的通道（都有核实依据，记此防止反复）

- **codex 终端标题**（盲文 spinner @100ms / "[ ! ] Action Required" 闪烁 @1s）：真实可用且零配置，nvim 侧 `b:term_title` + `status_redraw_buf` 自动刷新，但解析的是**展示层文案**，属用户判定的准抓取，弃。日后若接受可作零配置 fallback。
- **claude statusline JSON tee**：数据最富（context% / cost），但把"给 claude 自己渲染 statusline 的通道"劫持作外部消费是未批准用法，弃。
- **`--output-format stream-json`**：仅 `-p` 模式，不适用交互 TUI，弃。
- **opencode SSE**（`--port` + `/event` + `/session/status`）：协议干净，但当前适配器裸 `--port`=临时端口无法发现；改固定端口又引入多 session 端口分配问题。插件在 server 进程内直接拿总线，更简，弃 SSE。

## 状态配色（浅色/深色双主题对比度实测）

statusline 透明，图标配色实际落在终端背景上，故按两套生效主题的 base bg 核验（tokyonight `#1a1b26`、catppuccin-latte(paper) `#eff1f5`），标准 WCAG ≥3:1（图形对象）。语义首选反而全部落选：`DiagnosticWarn` 橙 latte 2.31、`Special` 粉 latte 2.34、`DiagnosticInfo` latte 2.47、`Constant` 橙 latte 2.64、`DiagnosticOk` 绿 latte 2.96、`Comment` 灰 tokyo 2.76。

| 状态 | 组 | tokyo(暗) | latte(亮) | 色相 |
|---|---|---|---|---|
| working | `Function` | 6.79 | 4.34 | 蓝（进行中） |
| idle | `Character` | 9.35 | 3.31 | 绿→青（完成） |
| attention | `DiagnosticError` | 4.17 | 4.80 | 红（待裁决） |
| 无事件 | `ModeMsg` | 8.10 | 7.06 | 灰（中性） |

配色集中在 `agent_sessions.lua` 的 `STATE_HL` / `HL_NEUTRAL`，勿按语义直觉改回 DiagnosticWarn 一类（见上表落选数据）。

## 机器侧配置

**claude：零安装**。`claude_spawn_cmd`（agent_sessions.lua）在 spawn 时自动追加 `--settings <config>/scripts/agent-status-settings.json`——hooks 配置随本仓库走版本控制，只作用于 agent pane 里 spawn 的 claude，**不触碰全局 `~/.claude/settings.json`**。终端里裸跑的 claude 双重免疫：不加载该文件、也没有 `AGENT_*` env（脚本静默 no-op）。（也曾考虑 Claude Code 插件级 hooks/hooks.json——需要 marketplace/插件目录机器配置，注入面反而更宽；`--settings` 按 spawn 精确注入，更贴身。）

**~/.codex/hooks.json**（同构 + `Interrupt`→idle；装后 codex 内 `/hooks` 信任一次）：

```json
{
  "hooks": {
    "UserPromptSubmit":  [ { "hooks": [ { "type": "command", "command": "$HOME/.config/nvim/scripts/agent-status-hook.sh working" } ] } ],
    "PostToolUse":       [ { "hooks": [ { "type": "command", "command": "$HOME/.config/nvim/scripts/agent-status-hook.sh working" } ] } ],
    "Stop":              [ { "hooks": [ { "type": "command", "command": "$HOME/.config/nvim/scripts/agent-status-hook.sh idle" } ] } ],
    "Interrupt":         [ { "hooks": [ { "type": "command", "command": "$HOME/.config/nvim/scripts/agent-status-hook.sh idle" } ] } ],
    "PermissionRequest": [ { "hooks": [ { "type": "command", "command": "$HOME/.config/nvim/scripts/agent-status-hook.sh attention" } ] } ]
  }
}
```

**~/.config/opencode/plugins/agent-status.ts**（插件跑在 server 进程内，无需端口；payload 结构以 opencode 当前文档为准，装时校签名）：

```ts
// 把 opencode 事件总线的 session 状态镜像进 nvim agent 状态邮箱（docs/adr/0003）
import { appendFileSync } from "node:fs"

const STATE: Record<string, string> = { busy: "working", idle: "idle", retry: "working" }

export const AgentStatusMirror = async () => ({
  event: async ({ event }: { event: { type: string; properties: Record<string, any> } }) => {
    const file = process.env.AGENT_STATUS_FILE
    const tag = process.env.AGENT_SESSION_TAG
    if (!file || !tag) return // 不在 nvim agent pane 里跑：静默跳过
    let state: string | undefined
    if (event.type === "session.status") state = STATE[event.properties?.status?.type]
    else if (event.type === "permission.asked") state = "attention"
    if (state) appendFileSync(file, JSON.stringify({ tag, state }) + "\n")
  },
})
```

## 刻意不为

- 不做动画/spinner 帧：动画需要 timer，机制红线。
- 不改 `<leader>a` picker 的呈现（状态图标可作后续增量）。
- 进程退出态不留显示（ADR 0001 无墓碑；用户重申）。
- 不监听 `PreToolUse`/`MessageDisplay` 等高频事件：三态不需要每工具粒度，省 per-event 进程 spawn。

## 已知边界

- **图标渲染依赖终端主字体为 Nerd Font**（2026-09-28 实证）：Ghostty 未配 `font-family` 时，PUA 图标走 CoreText 回退级联，且回退选择是 shaping 上下文相关的——tmux 抓包证实"正常图标"与"变大图标"的 cell 字节逐位一致（同 fg/bg、无属性差），但 run 中段与行尾孤字两条路径选中了不同字体（小尺寸 symbols 回退 vs 已安装 HackNerdFont 本尊），表现为"状态栏最后一个 PUA 图标突然变大"。修复：ghostty 配置 `font-family = Hack Nerd Font Mono`——主字体自含 PUA 字形，回退级联不再参与，大小恒定。本质是 Ghostty 渲染 quirk（相同输入不同输出），可报上游；"终端主字体用 Nerd Font"即正解。

- **FSEvents 启动竞态**：`uv_fs_event_start` 后 macOS 的流要等事件循环跑一次才真正激活，此前写入的**通知**会丢——但 drain 按 offset 补读，后续任一事件会把漏掉的状态行全部补上；真实场景 spawn 到首个 hook 事件隔着用户交互，无实际影响（回归测试里先泵一次循环再发首个事件即为此）。
- **claude 无 Interrupt hook**：用户 Esc 打断回合后状态可能滞留 working，直到下一个 Stop/UserPromptSubmit 修正；接受。
- 沙箱（IS_SANDBOX=1）claude 走 bypassPermissions，attention 态基本只在非沙箱出现。

回归门：`scripts/test-agent-status.sh`（headless --clean，判据=模块状态与 `status()` 字符串，不依赖 UI redraw）。
