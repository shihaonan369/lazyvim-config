# agent tab 视口：双视口并存与单一 current 同步

日期：2026-10-15，状态：accepted

## 决定

session 的第四种视口：专属 agent tab（左 = neo-tree `agent_tree` 外部源做
列表——`<CR>` 切换、`a` 新建、`d` 删除带确认；右 = 显示窗），与 Agent pane
**长期并存、各有分工**（编辑为主 → pane；agent 为主 → tab）。不是过渡形态，
不废弃 pane——用户明确推翻过"未来全面转 tab"的想法。

这是对 ADR 0001「tab page 不承载 session」域约定的开口子：当年否决的是
"一个 agent 一个 tab"（tab 是项目工作区）；本决定是"所有 session 共用
一个专属 tab"，tab 语义仍是工作区——agent 专属工作区。

架构不变量：**单一全局 current，所有 agent 显示窗同步**。任一视口选中即更新
`S.current`，主 tab 的 pane 与 tab 右窗一并换 buffer（同一 terminal buffer
多窗显示，输入进同一个 job——两个取景，一个 agent），`<`/`>` 循环锚点、
statusline 实心、两窗内容永远一致，零特例。实现：agent_sessions 增设
`alt_viewport` 注册口（agent_tab 注册 `active`/`show`，未注册时行为与本决定
之前逐字相同），`display()` 按当前 tab 路由 + `pane_open()` 跨 tab 同步
pane；后台联动（spawn 即显、TermClose 顺延/清空、状态变化刷新树）全部走
既有 User `AgentSessionsChanged` 事件（emit 管线，零轮询，与 ADR 0003 同源）。

## 边界与豁免（未来读者会问的）

- tab 右窗复用 winvar `agent_pane`：ADR 0002 领地守卫自动覆盖，不写新守卫。
  唯一豁免：空态占位 buffer（bufvar `agent_tab_welcome`，无文案纯空白——
  欢迎页被用户否决，2026-10-15）——空态时显示窗合法持有非 terminal
  buffer，是领地"只放 terminal"的唯一例外。
- `<C-a>` 在 agent tab 内 no-op：护栏只设在 `M.toggle`（`<C-a>` 的真实映射
  处）。`claude_toggle`（`:ClaudeCode` 的 provider 入口）**不设**护栏——树内
  `a` 的冷启动（无 claude_cache）经 `:ClaudeCode` → provider 必须放行，
  曾因护栏掐断致 tab 内首次新建无声失败（2026-10-15 修）；tab 场景由收尾
  `display()` 路由到右窗，pane_valid 跨 tab 判假不会另立 pane。pane 的
  几何/让位/隐藏路径一行不动；agent_sessions 的 display/spawn/BufWinEnter/
  TermClose 有为同步模型所必需的接缝改动——未注册 alt 视口时（--clean 测试
  态）行为与本决定之前逐字相同。`ensure_visible`（provider 路径）在 tab 内
  改道为右窗就位。切入/新建时焦点落显示窗（terminal 才 startinsert），与
  `<C-a>` toggle pane 的落点隐喻一致。
- `<leader>at` 幂等：tab 不存在则 `$tabnew` **建于末尾**（g1-g9 位置键零
  扰动）、存在则切入、已在其中 no-op；tab 内由 TabEnter 钩子撤映射
  （which-key 不列不可用键），离开恢复。tab 身份 = `vim.t` 标记。
- 最后一个 session 退出：tab 保留空壳（树空 + 右窗空白占位），幂等语义
  要求 tab 身份稳定——与 ADR 0002"session 生死不牵连 pane 几何"同构。
  **首开**（创建 tab 时）无 session 则直接新建一个、树不设 "+ new agent"
  行（新建走 `a` 键）、不做欢迎页文案——均为用户实用裁决（2026-10-15）。
  TermClose 顺延在 tab 内不夺焦点：内容经事件同步，焦点留在用户所在处。
- agent tab 内新建 session：pane 不立，termopen 经 `nvim_buf_call` 直接在
  无宿主窗的 buffer 上执行（pane 路径仍走 win_call 旧语义，ADR 0002 修订
  的回归不扰动）。
- 左窗树被手动关掉：`q` 与 `<leader>aa` 都是树 toggle 的把手——**aa 的隐喻
  是"给我看 agent 列表"，形态随视口**（主 tab = 浮窗 picker，agent tab =
  左侧树 toggle，经 `M.picker` 的 alt_viewport 分派，三个插件 spec 零改动；
  用户裁决 2026-10-15）；切入 tab（TabEnter）也会兜底重开。**q 必须由本源
  接管真关窗**：neo-tree 自带 close_window 在 position=current 窗口里只清
  buffer 不关窗，留下空 editor 窗且 agent_tree winvar 还挂着——ensure_tree
  误判树在、永远不重建（实测踩过）。右窗被关掉：同步路径尊重不重建，显式
  显示（`<CR>`/`a`）时重建。树窗身份 = winvar `agent_tree`（filetype 判定
  在 neo-tree 未加载的 headless 场景失真）。

## 弃选

- **agent tab 为过渡、未来废弃 pane**：用户明确否决——编辑为主的工作流里
  side pane 更顺手，双视口是终态分工。
- **各视口独立 current（per-tab current）**：`<`/`>` 锚点、statusline 实心、
  两窗显示会三处脱钩，特例丛生；同步模型反而最贴近旧 `display()` 语义。
- **`<C-S-a>` 快捷键**：Ghostty 直连可达但 tmux 内丢失，只绑 `<leader>at`。
- **自定义 tabline 标签**：需整体接管 `'tabline'`，代价大于收益；默认
  tabline 显示 tab 内 buffer 名已可辨认。

回归：scripts/test-agent-tab.sh（headless --clean，树以 winvar 骨架降级）。

## 修订（2026-10-15）：agent tab 只收 agent 域

用户裁决：agent window（pane/tab）不出现其他 buffer，agent buffer 不出现在
其他 window（与 ADR 0002 修订的双向守卫同一句誓言的两半）。file buffer 落
树窗/显示窗（bufferline 点击等入口）→ 挪回来源 tab 主区（return_tab 由
toggle/TabEnter 记录来路）、视角跟随、污染窗复原（树窗关闭重建，显示窗
sync）。两个防乒乓细节，缺一即死循环：redirect 可重入——set_buf 落地会再
触发一轮域守卫（污染窗此刻仍显示该 buffer），前一轮已清退则 win 失效跳过；
树窗重建须立即换占位 buffer——vsplit 从显示窗继承 agent terminal（BWE 不响、
sweep 清退成 blank），blank 落进树窗又触发域守卫，无限乒乓。
回归：scripts/test-agent-tab.lua 判据 4b。

## 修订（2026-10-19）：显示窗宽度守卫（30% 泄漏案终结）

三天偶发"显示窗变 ~30%"由全网记录仪定罪：claudecode.nvim 的 diff 清理
（diff.lua `_cleanup_diff_state`）在 diff 关闭后把"claudecode 终端窗"强写回
`split_width_percentage`（默认 0.30）——插件假设天下只有一个 30% pane，多视口
下它找到的当前 claude 窗是 agent tab 显示窗（239 列时写 71，实测树随之
40→167）。修复：`nvim_win_set_width` 表级包装常驻守卫——显示窗宽度是
"列宽−树 40"的涌现值，任何 Lua 侧直写一律吞掉（用户手动 resize 走 Ex
命令不经此表，不受影响，宽度稳定法不破）。主 pane 的 30% 恢复是插件
自家设计且与 pane 几何一致，不拦。回归：test-agent-tab.lua 判据 1e。

## 修订（2026-10-20）：视口恒满屏自愈（frame 预算冻结案）

容器实机 agent tab 视窗全缩成 6 行、下方 40+ 行空白；同刻主 tab h=50 正常。
定性：该 tab 的 frame 预算被钉死在 ~7 行——布局引擎按冻结预算等比缩放
（&lines 52→53 窗口 6→7），`:resize`/`nvim_win_set_height`/`&lines` 抖动/
tab 重入/`wincmd =`/新挂 UI 全部无效，孤窗独占也只有 6 行。真凶无目击：
隐藏 tab 强写、非当前 tab 改 lines、winfixheight、隐藏 tab win_call resize
（终端 buffer + winfixwidth）四组 headless 对照实验均免疫，属 nvim 内部
状态损坏。唯一有效解：结构性重建壳（摘牌→tabclose→toggle 重建），终端
buffer 随窗隐藏不卸载、job 不死——生命周期解耦设计的事实验证。
决定：满屏成为 decree（同"树恒在左、宽度稳定 40"一族）——底缘空隙 ≥3 行
（阈值免疫 chrome 记账与 1-2 行手滑）即病，`<leader>at` 进门与 TabEnter
重入两个入口自愈重建。副作用（用户知情）：主动把显示窗缩矮留大片空隙
同样进门即愈——agent tab 内缩高无受益者。只剩本 tab 时跳过（tabclose 即
退出，且无再进来入口）。return_tab 接力，让位身份不因换壳丢失。
回归：test-agent-tab.lua 判据 7（真冻结无法 headless 复现，以 resize 缩窗
造同款不满屏态固化用户契约；健康态重入不重建防误伤）。
