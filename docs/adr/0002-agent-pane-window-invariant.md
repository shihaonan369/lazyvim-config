# 终端领地窗口不变量：agent pane 与底部 shell 只放 terminal buffer

日期：2026-09-24，状态：accepted（同日修订：范围从"仅 agent pane"扩大到底部 shell）

一切"打开 buffer"的 nvim 语义（`:e`、gf、quickfix、`:buffer`、API `nvim_win_set_buf`）都指向当前窗口；焦点在终端窗口时文件会开进去，顶掉 terminal。snacks picker 的主窗口选择（`main.lua`）本会排除 terminal 窗口，但其兜底分支 `wins[1] or non_float` 在布局中没有合法文件窗口时仍会把 terminal 窗口当目标——agent pane 与底部 shell 都实测复现（后者即"<leader><leader> 后光标没跳过去"的报告），也解释了现象"时好时坏"：主区有文件窗口傍身时 picker 干净，主区空了必中。

决定：在窗口层强制不变量，对一切入口（含 snacks 内部行为）免疫——

- 领地标记两种：agent pane（winvar `agent_pane`，合法集 = agent session buffer，session buffer 在 spawn 时打 bufvar `agent_session`）；底部 shell 等（winvar `shell_term`，由 TermOpen/BufWinEnter 按 `buftype==terminal && 非agent && 非浮窗` 自动标记宿主窗口，hide/show 换窗口后自愈，合法集 = 任意 terminal buffer）。
- `BufWinEnter` 守卫发现非 terminal buffer 进入领地即重定向：搬到当前 tabpage 最左/最上的普通窗口（按窗口坐标取，不信任 winnr 编号）；领地独占时按几何形态新开主区窗口（全宽 shell 上方 split，右侧 pane 左侧 vsplit、pane 回 30%）。领地恢复 terminal，焦点跟随文件。重定向在 `vim.schedule` 里执行——`:e`/`:buffer` 的收尾会改写原窗口，同步搬会被覆盖。静默。
- 焦点跟随是**事件驱动**的：snacks 会同步把误入自家窗口的文件挪走并恢复 terminal（多步异步），我们的重定回调发现"已被接管"时不重搬 buffer，只挂待兑现标记（`S.follow_buf`），同一 buffer 落定非领地窗口的那个 BWE 把焦点送达。
- 单一机制：`BufWinEnter` 对 `:buffer` / `nvim_win_set_buf` / `:edit` 均触发（含 buffer 已在他窗显示的情况，已实测），无需覆盖各插件入口。

## 例外：显式选择优先

pick_win（`<S-CR>`）显式选中 pane 时放行一次：snacks 的包装 action（`agent_pick`，见 `lua/plugins/snacks.lua`）在 pick_win 选中 `agent_pane` 窗口后调用 `agent_sessions.arm_override()`，下一个进入 pane 的 buffer 免于重定向。显式意图压过不变量；标志一次性消费，无持久状态。

## 刻意不为（修订后仍成立）

- ~~不推广到底部 shell 终端~~ 已修订：底部 shell 同样被 snacks 兜底分支命中（实测复现），且其自动挪移不带走焦点，纳入领地。
- 不追踪"最近聚焦的主窗口"：目标恒为当前 tabpage 空间左上角的普通窗口，零额外状态。
