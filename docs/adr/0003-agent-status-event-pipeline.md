# Agent 状态事件管线：边缘归一 + env 归因 + 文件邮箱 + fs_event

日期：2026-09-27（2026-09-29 修订：状态表情图标），状态：accepted

需求：statusline 里逐 session 显示 agent 状态（working / idle / attention），pane 收起时全体换睡觉图标、颜色仍实时更新。约束是硬的：拒绝 timer 轮询、拒绝终端输出/文案抓取；没有干净机制就宁可不做（用户既有裁决）。三路核实（claude/codex 官方文档、opencode 源码与文档、nvim 0.12.5 本机实测）后确认三家都有官方事件出口，本管线成立。

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
- **nvim 侧**：`luv fs_event`（macOS FSEvents，实测即时回调；`vim.fs.watch` 不存在）监听追加，seek 到已读 offset 只消费新完整行（残行留待续读，截断兜底归零）；状态挂在 `S.sessions[i].state`，TermClose 移除 session 时状态随之消失，**零垃圾回收**；变化后 `emit()`（既有 `redrawstatus` + `User AgentSessionsChanged`）驱动 statusline，睡觉图标的颜色实时性由此保证。
- **渲染（2026-09-29 修订：表情机器人）**：每 session 一个「图标 + 随行空格」等距单元，图标 = 状态表情 × 当前(实心)/后台(空心)孪生，与颜色**双编码**状态（色盲可辨）：**working = robot_excited（U+F16A3 / outline U+F16A4）、idle = robot_happy（U+F1719 / outline U+F171A）、attention = robot_confused（U+F169F / outline U+F16A0）**——每对实心=当前、空心=后台（字形通道标记"当前"，对称是构造性的）；无事件（机器侧 hook 未配置）无表情，落回 **robot（U+F06A9）/ robot_outline（U+F167A）**（`<leader>a` 分组同款）——"未知"≠"睡觉"，两个概念两个图标；pane 收起时全体换 **robot_off（U+F16A7）**，状态色保留（替原 eye_off U+F0209）。隐喻闭环：醒着的机器人有情绪，收起的统一睡觉。angry/dead/love 有字形无状态可挂，刻意不用（图标与状态 1:1，不为图标开新状态；退出即抹除与 ADR 0001 无墓碑一致）。颜色内嵌 `%#Group#`（lualine 一等支持）。`#N/M` 前缀弃用。**随行空格是机制的一部分**：PUA 大字形墨迹向右溢出（Ghostty kitty 式"PUA+尾随空白"渲染），随行空格承接溢出，并让所有图标走同一渲染路径（用户实测成立）——也因此格子对齐的属性标记（方括号/下划线/反色）必然与溢出墨迹错位、无法对称，被逐一证伪；bold 会切字体槽改变字形，同样禁用。
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

- **图标渲染绕开 Ghostty 字体回退（2026-09-28 终版）**：Ghostty 1.3.1 对"主字体缺失码点"的回退渲染是**位置相关**的——tmux 抓包证实"正常"与"变大"的图标 cell 字节逐位一致（同码点/前景/背景、无属性差），但 run 中段与行尾（右侧是空格/结尾）走不同解析路径，同一 PUA 图标两种尺寸。上游 2023 年即有同类记录（#1071 "PUA characters rendered bigger when there is a space to the right"，已关闭；1.3.1 上症状仍可复现，疑回归，有一手字节证据可新开 issue）。**被证伪的修法**：`font-codepoint-map` 钉不住（两次实测）、重复 `font-family` 不是字体栈（单值覆盖）、仅留单一回退候选（内嵌 Symbols Nerd Font）仍漂、只在行尾补一个空格无效（中间图标仍走小字形路径）；**每图标随行空格**成立并成为终版机制（见渲染段）。**两条稳定机制（均实测）**：① 主字体自带 PUA 字形（本地构建 JetBrainsMono Nerd Font 验证过，构建法存档 `scripts/build-jetbrains-nerd-font.md`，用户弃用——不想改 ghostty 默认配置，字体文件暂存 `~/fonts-disabled/`）；② **终版：默认字体 + 每图标随行空格**——所有 PUA 图标统一走"PUA+尾随空白"放大路径，尺寸恒定且无需任何非默认配置（2026-09-28 用户实测通过）。

- **FSEvents 启动竞态**：`uv_fs_event_start` 后 macOS 的流要等事件循环跑一次才真正激活，此前写入的**通知**会丢——但 drain 按 offset 补读，后续任一事件会把漏掉的状态行全部补上；真实场景 spawn 到首个 hook 事件隔着用户交互，无实际影响（回归测试里先泵一次循环再发首个事件即为此）。
- **claude 无 Interrupt hook**：用户 Esc 打断回合后状态可能滞留 working，直到下一个 Stop/UserPromptSubmit 修正；接受。
- 沙箱（IS_SANDBOX=1）claude 走 bypassPermissions，attention 态基本只在非沙箱出现。

回归门：`scripts/test-agent-status.sh`（headless --clean，判据=模块状态与 `status()` 字符串，不依赖 UI redraw）。

## 修订（2026-10-15）：睡觉隐喻 = "当前视角看不到但仍存在"；agent tab 内段隐藏

睡觉判定回归最简（`not pane_valid()`，本就是同 tab 判定——人在哪个 tab 就看
哪个 tab 的 pane）：可见性以**当前视角**为准，agent tab 存在 ≠ 此刻看得到，
人不在 agent tab 时那边再热闹也是"看不到"= 睡。曾短暂引入"任一视口在展示
即醒"的 showing() 判据，被用户纠正后拆除（记此防反复）。agent tab 内
statusline 的 agent 段整体隐藏——树已承载全部信息，statusline 只服务此刻
看不到的人。

## 修订（2026-10-15，同日第三条）：session 名字与双向同步

名字通道（claude 先行，codex/opencode 暂本地名 TODO）：
- **claude → nvim（事件驱动零轮询）**：SessionStart hook（scripts/agent-rename-hook.sh，
  jq 一行，缺依赖/缺字段静默降级）把 session_id+transcript_path 报进既有邮箱；
  nvim 侧 luv 盯 transcript 增量，扫 {"type":"custom-title"} 行取名——登记时
  先读 <sid>/custom-title.json 兜住 resume 已命名。custom-title 是 claude 内部
  格式（文档明言随版本变），失效即名字同步静默降级，状态管线不受牵连。
- **nvim → claude**：运行中 session 无文档化外部改名通道（inbox socket 只投
  文本不执行命令、agents 只读、云回路不适用），PTY 注入 `/rename <name>`
  是唯一路径——与 M.send（Smart Add）同通道同语义（回合中排队、与手输竞争），
  有先例故可接受；claude 侧改名回流的 custom-title 行与本地同值，幂等不回环。
- spawn 时定名有干净通道 `claude -n <name>`（未接，YAGNI）。
标签呈现：名字优先，无名回退位置编号 #n（picker 同步修复了 PTYPE_ICON
未定义全局的旧瑕疵）。

修订补记（同日）：注入序列定为 `\21(Ctrl-U) + "/rename <name>" + \r`——CR
是 pty 裸模式的回车（\n 不提交）；Ctrl-U 先清 input 草稿，盲通道下无法感知
或保存用户未提交文字，不清则命令与草稿拼接（改名失败且草稿被毁，两头
不一致）。取舍：罕见窗口的草稿被牺牲，换 rename 恒定干净执行。名字为
**单写者**：claude transcript 是唯一权威，nvim 只发命令永不落名（失败 =
树保持旧名，不假成功）。

修订补记（2026-10-21，resume 改名失配案）：PTY 全周期探针实测 claude
2.1.274——resume 后的 `/rename` **只改进程内存**：custom-title.json 与
transcript 均无写入（改名 TUI 生效、干净退出、盘上零痕迹；fresh 会话
08:27 案例则 json 当刻落盘——不对称待上游澄清）。树名回流通道本身无罪
（SessionStart resume 报文实测字段齐全、json 兜底与 fsevent 增量均有
回归门）。处置：`M.rename` 发送后 1.5s/6s 双点读 custom-title.json，
失配 notify 一条明示不同步——**不本地落名假装成功**（单写者裁决不动），
tw_path 未登记（fresh 早期）静默跳过。test-agent-status 增三判据。
