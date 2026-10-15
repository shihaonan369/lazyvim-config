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
  唯一豁免：欢迎 buffer（bufvar `agent_tab_welcome`）——空态时显示窗合法
  持有非 terminal buffer，是领地"只放 terminal"的唯一例外。
- `<C-a>`/pane toggle 在 agent tab 内 no-op（入口护栏）。pane 的几何/让位/
  隐藏路径一行不动；agent_sessions 的 display/spawn/BufWinEnter/TermClose 有
  为同步模型所必需的接缝改动——未注册 alt 视口时（--clean 测试态）行为与本
  决定之前逐字相同，真实环境 alt 恒注册但 `active()` 判据保证 tab 外等价旧
  路径。`ensure_visible`（provider 路径）在 tab 内改道为右窗就位。
  切入/新建时焦点落显示窗（terminal 才 startinsert），与 `<C-a>` toggle
  pane 的落点隐喻一致。
- `<leader>at` 幂等：tab 不存在则 `$tabnew` **建于末尾**（g1-g9 位置键零
  扰动）、存在则切入、已在其中 no-op；tab 内由 TabEnter 钩子撤映射
  （which-key 不列不可用键），离开恢复。tab 身份 = `vim.t` 标记。
- 最后一个 session 退出：tab 保留空壳（"(no agents)" + 欢迎页），幂等语义
  要求 tab 身份稳定——与 ADR 0002"session 生死不牵连 pane 几何"同构。
  TermClose 顺延在 tab 内不夺焦点：内容经事件同步，焦点留在用户所在处。
- agent tab 内新建 session：pane 不立，termopen 经 `nvim_buf_call` 直接在
  无宿主窗的 buffer 上执行（pane 路径仍走 win_call 旧语义，ADR 0002 修订
  的回归不扰动）。
- 左窗树被手动关掉：切入时（toggle 与 TabEnter）从显示窗左侧重开；右窗被
  关掉：同步路径尊重不重建，显式显示（`<CR>`/`a`）时重建。树窗身份 =
  winvar `agent_tree`（filetype 判定在 neo-tree 未加载的 headless 场景失真）。

## 弃选

- **agent tab 为过渡、未来废弃 pane**：用户明确否决——编辑为主的工作流里
  side pane 更顺手，双视口是终态分工。
- **各视口独立 current（per-tab current）**：`<`/`>` 锚点、statusline 实心、
  两窗显示会三处脱钩，特例丛生；同步模型反而最贴近旧 `display()` 语义。
- **`<C-S-a>` 快捷键**：Ghostty 直连可达但 tmux 内丢失，只绑 `<leader>at`。
- **自定义 tabline 标签**：需整体接管 `'tabline'`，代价大于收益；默认
  tabline 显示 tab 内 buffer 名已可辨认。

回归：scripts/test-agent-tab.sh（headless --clean，树以 winvar 骨架降级）。
