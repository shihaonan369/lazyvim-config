# 终端领地窗口不变量：agent pane 与底部 shell 只放 terminal buffer

日期：2026-09-24，状态：accepted（同日修订：范围从"仅 agent pane"扩大到底部 shell；2026-09-30 修订：session 生命周期与 pane 几何解耦，见文末）

一切"打开 buffer"的 nvim 语义（`:e`、gf、quickfix、`:buffer`、API `nvim_win_set_buf`）都指向当前窗口；焦点在终端窗口时文件会开进去，顶掉 terminal。snacks picker 的主窗口选择（`main.lua`）本会排除 terminal 窗口，但其兜底分支 `wins[1] or non_float` 在布局中没有合法文件窗口时仍会把 terminal 窗口当目标——agent pane 与底部 shell 都实测复现（后者即"<leader><leader> 后光标没跳过去"的报告），也解释了现象"时好时坏"：主区有文件窗口傍身时 picker 干净，主区空了必中。

决定：在窗口层强制不变量，对一切入口（含 snacks 内部行为）免疫——

- 领地标记两种：agent pane（winvar `agent_pane`，合法集 = agent session buffer，session buffer 在 spawn 时打 bufvar `agent_session`）；底部 shell（winvar `shell_term`，仅标记 **snacks 管理的终端窗** `w:snacks_win` 非空的宿主窗口：TermOpen 兜底 + BWE schedule 复查双路（snacks open_win 先 sbuffer 后写 winvar，同步判必漏），hide/show 换窗口后自愈，合法集 = 任意 terminal buffer；普通窗承载的 `:terminal mysql`、H/L 轮换进的 terminal buffer **不入领地**）。
- `BufWinEnter` 守卫发现非 terminal buffer 进入领地即重定向：搬到当前 tabpage 最左/最上的普通窗口（按窗口坐标取，不信任 winnr 编号）；领地独占时按几何形态新开主区窗口（全宽 shell 上方 split，右侧 pane 左侧 vsplit、pane 回 30%）。领地恢复 terminal，焦点跟随文件。重定向在 `vim.schedule` 里执行——`:e`/`:buffer` 的收尾会改写原窗口，同步搬会被覆盖。静默。
- 焦点跟随是**事件驱动**的：snacks 会同步把误入自家窗口的文件挪走并恢复 terminal（多步异步），我们的重定回调发现"已被接管"时不重搬 buffer，只挂待兑现标记（`S.follow_buf`），同一 buffer 落定非领地窗口的那个 BWE 把焦点送达。
- 单一机制：`BufWinEnter` 对 `:buffer` / `nvim_win_set_buf` / `:edit` 均触发（含 buffer 已在他窗显示的情况，已实测），无需覆盖各插件入口。

## 例外：显式选择优先

pick_win（`<S-CR>`）显式选中 pane 时放行一次：snacks 的包装 action（`agent_pick`，见 `lua/plugins/snacks.lua`）在 pick_win 选中 `agent_pane` 窗口后调用 `agent_sessions.arm_override()`，下一个进入 pane 的 buffer 免于重定向。显式意图压过不变量；标志一次性消费，无持久状态。

## 刻意不为（修订后仍成立）

- ~~不推广到底部 shell 终端~~ 已修订：底部 shell 同样被 snacks 兜底分支命中（实测复现），且其自动挪移不带走焦点，纳入领地。
- 不追踪"最近聚焦的主窗口"：目标恒为当前 tabpage 空间左上角的普通窗口，零额外状态。

## 修订 2026-09-30：session 生命周期不得牵动 pane 几何

三个实测缺陷同出"pane 窗口存续期间被隐式路径改写几何"（回归门
`scripts/test-agent-pane-layout.sh`，headless --clean，假 agent 手法同
`test-agent-status.sh`）：

- **TermClose 顺序**（"最大化后关 session 回初始宽度"的根因）：原实现先
  `nvim_buf_delete(force)` 再安顿 pane。bd! 删**正显示中**的 buffer 会连带
  关窗（Vim 语义，非最后窗口时 pane 失窗），`show_pane` 随即按初始 30% 重建，
  最大化布局被砸回初始宽度。nvim 0.11/0.12 同现（headless 逐事件复现：
  WinClosed(pane) → WinNew → 新 pane w60）。修：**先安顿（display 下一个 /
  hide），最后删死 buffer**——此刻它已不在任何窗口显示，删除不可能再牵动布局。
- **hide_pane 唯一窗口守卫**：领地独占时删最后一个 session，hide_pane 对唯一
  窗口 `nvim_win_close` 抛 E444，schedule 回调中断——`S.pane_win` 悬挂、窗口
  留成被降级的僵尸领地。修：唯一窗口时领地交还（摘 `agent_pane` + `enew` 换出
  buffer，否则窗口继续渲染后台 session、复活时两窗同显一个 terminal）、指针
  清空，下次 show_pane 另立新窗（初始宽度，与"pane 重建即回初始宽度"语义一致）。
- **让位分支按领地身份，不按宽度**：原"宽度 ≥ columns-2 走上方 split"是给
  全宽底部 shell 设计的宽度代理，最大化 pane 同样命中；而 `set_width(pane, 30%)`
  在纯水平 frame 里是几何空转（无竖直邻居接盘）——让位发生了、pane 却仍占
  全宽。修：agent pane 让位恒走 `leftabove vsplit` 回右侧正统槽位（宽度随后
  让回 30%）；shell 侧维持宽度判分支（全宽上方 split / 侧竖 vsplit）不变。
- **让位即取消最大化**：让位点顺手清 `vim.w[pane].max_width`（winvar 归
  keymaps.lua 的 `toggle_max_width` 所有）。否则让位回 30% 后该 winvar 仍存
  旧值，下次 `<C-S-Right>` 走"还原"分支把 pane resize 回陈旧宽度，而非重新
  拉满。pane 全灭后隐藏/重建则无此虑：winvar 随窗口存亡自然消失。


## 修订（2026-10-15）：不变量双向化

领地守卫原本只守一个方向（非 agent buffer 不进 agent pane）。实测暴露反例：
agent buffer 出现在 editor 窗口——split 克隆 pane（w: 变量不继承，buffer 已在
别窗显示不触发 BufWinEnter），正向守卫与 BWE 都无从得知。修：反向清查
sweep_strays 挂 WinNew/WinEnter/BufEnter 全窗扫描，agent session buffer 落进
非领地窗即清退（enew），入口无关。领地同时扩为三种：agent pane（合法集 =
session buffer）、底部 shell（任意 terminal）、agent tab 树窗（树 buffer，
winvar agent_tree）——树窗不算领地时，file buffer 进显示窗会被
main_target_win"救"进树窗（ADR 0005 的实测反例）。agent tab 显示窗的入侵
由 tab 视口接管（alt_viewport.claims，file buffer 挪回来源 tab，ADR 0005）。
回归：scripts/test-agent-pane-layout.lua 判据 6。

## 修订（2026-10-15，同日第三条）：显示窗 terminal 选项不赌 TermOpen 时机

行号回归（pane 后建时出现 number/relativenumber）：nvim 内建 defaults
（runtime/lua/vim/_core/defaults.lua 的 TermOpen autocmd）把 nonumber 打在
`vim.wo[0][0]`——**termopen 时刻的当前窗**上。旧世界 termopen 恒在 pane 窗
发生；agent tab 落地后 pane 可为已存 session 后建，该窗从未 termopen，无人
关行号，又从开着 number 的主窗 vsplit 继承。修：show_pane / build_display
对显示窗显式 apply（number/relativenumber=false），与任何时机无关。

## 修订（2026-10-27）：shell 领地收窄为 snacks 终端窗——轮换造窗泄漏案

普通编辑窗 H/L 轮换到 manual terminal buffer（`:terminal mysql` 等）曾被
TermOpen/BufWinEnter 无差别标记为 `shell_term` 领地（任何普通窗见 terminal
即标）。连锁：H 离开时文件被判入侵 → `relocate()` 经 `main_target_win` 把
文件塞进 neo-tree 侧栏（候选未排除 nofile 侧栏）→ neo-tree 自卫
（`buffer_enter_event` → `force_new_split2`）新开窗口 → 下一轮 L 该窗又承载
terminal 被标 → 循环造窗，无上限（headless 复现 + `WinNew` 栈证实）。

修（断循环于根源 + 纵深防御，回归 scripts/test-shell-territory.lua 红绿
28 判据）：

- **标记加 `w:snacks_win` 门**：shell 领地只认 snacks 管理的终端窗（底部
  shell 家族 `<C-/>`/`<leader>zz`）。TermOpen 兜标同步判（winvar 在
  open_win 同步流程末尾落位，必先于 job/termopen）；BWE 路因 snacks 先
  sbuffer 后写 winvar，推迟 `vim.schedule` 复查（彼时 open_win 已收尾），
  hide/show 换窗自愈经此路保住。语义变化：`:tabnew|terminal`、
  `:vsplit|terminal` 等手动终端不再成领地——文件可正常落窗，无守卫亦无
  relocate，泄漏族根除。
- **`main_target_win`/`follow_buf` 只认 `buftype==""` 真编辑窗**：侧栏
  （neo-tree 等 nofile）与特殊窗不再是 relocate 去处/焦点落点；候选全无时
  走原有几何兜底开新 split（确定性单窗，无级联）。
