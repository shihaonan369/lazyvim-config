# pi 后端：第四家 Agent 接入（OSC 7501 直收 + 全家桶复用）

日期：2026-11-03，状态：accepted

## 背景

pi（`@earendil-works/pi-coding-agent`，原 badlogic/pi-mono 公司化迁移，本机
1.5.0 = 当日 latest，main 分支文档与实装逐字节一致）接入前的全量差距调查：
双路一手调查（官方文档/随包源码/CHANGELOG vs 本仓支持面盘点）+ 四个实测门
（headless nvim + 真 pi），结论 **完美 14 / 退避 5 / 无法实现 0**——多条
pi 机制比 claude/codex 更干净（`-n` 落名免注入、`--session-id` 链缺则建、
状态通道零装机）。用户裁决（2026-11-03）：与 nexus/hermes 完全正交（pi pane
= 裸 pi，全局扩展自然生效）；`:AI` 默认后端全局切 pi；pane 用
`--tui-mode fullscreen`（同日终裁：初选 regular 后改 fullscreen，与 claude
的 CLAUDE_CODE_NO_FLICKER=1 全屏 alternate screen 对齐）；`ai_assistant` 默认
仍 claude（pi 为第四值）。

## 决定

- **adapters.pi**（agent_sessions.lua）：新建 spawn
  `{PI_BIN, [-n name], -e scripts/agent-pi-bridge.ts, --tui-mode fullscreen}`
  ——名字随 `-n` 落进 pi 本尊（session_info entry 持久化），**免 /rename
  注入队列**；resume 同 codex 键位面（`--continue`=cwd 最近 / `--resume`=TUI
  原生选择器）。`--tui-mode fullscreen`（alternate screen 整窗渲染，与 claude
  CLAUDE_CODE_NO_FLICKER 同款）恒附钉住，防用户 /settings 改动漂移；env 注
  `PI_PROGRAM_STATUS=1` + `AGENT_DIFF_DIR`。
- **状态+名字 = OSC 7501 Program Status 直收**（ADR 0003 管线的 pi 出口）：
  pi 原生发 `\27]7501;state=…:app=…:msg=<base64 会话名>ST`，nvim 既有
  TermRequest autocmd 按 buffer 归因（G1 实测：nvim 原样收到、terminator
  已剥——与 codex OSC 0 同一接缝）。五态收敛进闭词表：working→working、
  idle/done→idle、blocked/error→attention；msg 兼作改名回流（仅
  working/done 携带）。`PI_PROGRAM_STATUS=1` 绕过终端应答握手（nvim
  :terminal 无人应答协议查询）。**零机器侧安装件**——优于 claude
  `--settings` 与 codex `~/.codex/hooks.json`。
- **优雅退出 = Ctrl+C 清草稿 → 延时 Ctrl+D**：pi 无退出斜杠命令
  （keybindings `app.clear`/`app.exit`）。**必须分包**：`\21\4` 同包实测
  吞掉退出、单发 `\4` 有效（2026-11-03 E2E 探针）；\3 先清草稿保 Ctrl+D
  的空编辑器前提——分包同 M.command 文字/CR 铁律。
- **树内 r = /name 注入 + 本地落名**（codex 同款形状）：pi 侧 session_info
  持久化，随仓桥接扩展邮箱回流纠偏为后手（见下）。
- **idle 态改名即时回流 = 随仓桥接扩展走状态邮箱**（2026-11-03 修订）：7501
  的 msg 只随 working/done 报文携带——idle 态（新会话未跑 prompt / Esc 中止
  后）TUI 内 `/name` 不触发新 7501 报文，树要等下一回合才见名。
  `scripts/agent-pi-bridge.ts` 在 `session_info_changed` 时向
  `AGENT_STATUS_FILE` 单行追加 `{"tag","name"}`（ADR 0003 既有邮箱通道，
  nvim 侧 fs_event 消费，`status_apply` 增设 name 路由）；`session_start`
  亦上报既有名——resume 的会话名立即可见，不必等首回合。零轮询、env 未注入
  时整体 no-op。
- **Smart Add = 纯文本草稿**：`path:行范围` 不带 `@`、不提交（pi 的 `@`
  是交互式整文件附件搜索、无行区间语法；G2 实证括号粘贴 `@…` 落纯文本不
  触发弹窗）。pi 用 read 工具按行取——语义从结构化引用退为文本提示（已
  接受的取舍）。
- **:AI 默认 pi**（ai_cmd.lua 后端缝）：`resolve_backend()`——手动
  `vim.g.ai_cmd_backend="claude"` 优先；pi 不可执行（容器装机过渡期）回退
  claude + 一次性 notify，装好自动切回。pi 路径：cwd=项目根（相对路径可
  用）、transcript 经 `--session-dir` 落 scratch（不进 ~/.pi/agent/sessions
  的项目会话树，隔离语义同 claude 的 scratch cwd）；链 sid 我方生成经
  `--session-id` 传入（**缺则建**——会话目录被清也自动重建，无 claude 的
  「链失效」形态，出错直报不重开）；`--no-mcp/--no-extensions/--no-skills/
  --no-prompt-templates` 纯提速（翻译轮用不上）。链文件带后端前缀
  `pi:`/`claude:`（旧无前缀 = claude，回读兼容）。
- **随仓桥接扩展 `scripts/agent-pi-bridge.ts`，spawn 经 `pi -e <path>` 注入**
  （2026-11-03 二修，用户裁决：**nvim 插件的功能件必须随仓走**——新装后端
  即用，机器侧 ~/.pi 零依赖；与 claude `--settings scripts/
  agent-status-settings.json` 同款零安装房屋模式）。职责两件：
  ① inline diff：`tool_call` 在工具执行**前**触发，edit/write 命中即同步
  读盘快照落同一 `$AGENT_DIFF_DIR/$AGENT_SESSION_TAG<路径镜像>` 布局
  （`agent_diff.lua` 后端中立零改动，`<leader>ad/ada/add` 随 pi 接线）；
  ② idle 态改名即时回流（见上条）。对照：**codex/opencode 无等价注入口**
  （codex `-c` 只达 config.toml、hooks 在独立 hooks.json；opencode 插件
  只认其 config 目录）——那是机制缺失的如实记录（ADR 0003 维持），不是
  本仓可仿的形状。
- **沙箱：无 flag 可注**：pi 无内建权限系统（官方 security.md，天生
  full-auto），IS_SANDBOX 注入面为空——沙箱内外行为一致。

## 弃选

- **状态走扩展写邮箱**（调查期备胎）：7501 直收实测可行后不用于状态；扩展
  API 是文档化后备（若未来 nvim TermRequest 行为变化可切换）——名字通道
  已由随仓桥接经同一 API 承担。
- **`--mode rpc` 驱动受控会话**：pane 是 TUI-first 领地隐喻；RPC 属未来
  另一种集成形态（官方 RpcClient 在包内 examples/rpc-client.ts）。
- **keybindings.json 重绑 followUp**（alt+enter→ctrl+q）：G3 静态证据
  （pi-tui keys.js）`\x1b\r` 在 legacy 键盘模式即 alt+enter，nvim :terminal
  不应答 kitty 握手、pi 自动落 legacy——无需重绑。

## 已接受的语义取舍

- Smart Add 行区间引用降级为纯文本（见决定）。
- error→attention（信息量高于 claude 惯例的 error 后归 idle——亮图标提醒）。
- 改名回流只在 working/done 报文携带 msg；idle 态改名由随仓桥接邮箱直报
  补齐（机制干净，非降级）。
- 容器过渡期 :AI 回退 claude（装好 pi 零配置自动切回）。

## 已知边界

- 7501 msg 为 base64（编码上限 2KB）；名字回流仅在 working/done——idle 态
  改名经随仓桥接邮箱直报补齐（见决定节）。
- Ctrl+D 仅编辑器空时生效；\21(Ctrl-U) 在 pi 编辑器非清草稿键且同包会吞
  掉后续 \4——退出序列是 \3 → 延时 \4 两段分包（见决定）。
- alt+enter 排队键依赖 legacy 键盘模式（nvim :terminal 不应答 kitty 协议
  握手自动落 legacy；若 nvim 未来实现 kitty passthrough 需复测）。
- 就绪探测 = `─` 规则线（banner 分隔线亦命中——TUI 渲染即就绪，语义成立）。
- **pi 后端机器侧装机需求为零**（桥接扩展随仓经 `-e` 注入）——容器装 pi
  只需二进制 + key。nvim 功能件随仓注入是本仓不变量：后端无注入口时（codex
  hooks.json / opencode 插件）如实记缺口，不以装机件或降级凑数。
- `AGENT_PI_BIN` 模块加载时求值（`AGENT_*_BIN` 冒充惯例，headless 门先设
  env 再 require）。
- pi 1.x 迭代快（月 6 minor）、会话格式有版本化迁移但无冻结承诺——本仓
  **不解析 pi 会话文件**（树枚举走 nvim registry，盘上格式无耦合），对接
  按 ≥1.5.0 钉。
- pi 会话文件按 cwd 分目录（`~/.pi/agent/sessions/--<path>--/`）：:AI 已用
  `--session-dir` 隔离，pane 会话正常落项目目录（resume 的 cwd 界语义依赖
  它，与 codex 同构）。

## 回归门

`scripts/test-agent-pi.{sh,lua}`（fake pi：argv 落盘 + ─ 规则线 + 7501 报文
序列）：键位面、-n 带名、7501 状态归一/名字回流、aC/aR argv、aM 分包、
/name 改名、`\3`→延时`\4` 两段优雅退出、邮箱名字直报路由（判据 1b）；
`test-ai-cmd.lua` 判据 15（pi argv/cwd/链 sid/文本 stdout 直解/缺位回退/
失败直报）。
