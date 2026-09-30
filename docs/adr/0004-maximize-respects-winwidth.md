# 最大化存续期间对齐重算底线与挤压底线：临时 winwidth=winminwidth

日期：2026-09-30，状态：accepted（同日两次改向，见"弃选"——最终版为临时 winwidth 方案）

## 现象

`<C-S-Right>` 拉满 agent pane 后，第一次打开再关闭 snacks picker（`<leader><space>`）
pane 缩 ~10%，此后不再缩。排查实录（多轮实测）：裸 pty 真实 TUI 下 nvim 0.11 与
0.12 均复现（两版签名逐字一致，**非版本差异，升级消除不了**）；headless 不复现
（无 TUI 刷新循环）；tmux 无关（常被误判为元凶，裸 pty 照样缩）；与 agent pane
无关（普通文件窗口同样发生）。

## 机制

nvim 有两条互不通气的宽度规则：**挤压**看 `winminwidth`（默认 1，本配置 5——
别的窗口抢地盘时我最低可被挤到多窄），**重算/聚焦**看 `winwidth`（默认 20——
当前窗口最少该多宽，布局重算时强制加宽）。`vertical resize 9999` 只咨询前者，
把兄弟窗合法压到 winminwidth；picker 关浮窗触发一次布局重算，后者被咨询到，
兄弟窗被抬回 20、差额（20−5=15 列 ≈ 10%）恰好从 pane 偷走。"只缩第一次"：
此后兄弟窗已 ≥20。低于 winwidth 的窗口在 Vim 心智模型里是"收起态"——允许
存在、不允许"干活"；被最大化压扁的邻居本就该一直是收起态，重算却按"工作窗"
标准抬它，类目错用。

## 决定

`toggle_max_width`（keymaps.lua）保持 `resize 9999` 原语义不动（其余窗口挤到
winminwidth，1:1:x——用户实测后明确偏好：最大化主区窗时 pane 也照挤到 5，
对称且直觉）。唯一的动作：**最大化存续期间把重算底线对齐挤压底线**——临时
`vim.o.winwidth = vim.o.winminwidth`，重算再看 5 列的收起窗即"合法，不动"；
toggle 还原或最大化窗口未经 toggle 消亡（WinClosed）时扫描 `max_width`
winvar，无人最大化则恢复原值。`winheight` 默认即 1，无同类问题，高度 toggle
不动。

## 弃选（都有实测依据，记此防反复）

- **全局常置 `winwidth=1`**（一行根除）：用户不想动全局既有窗口逻辑。
- **让回（give-back）**：拉满后把兄弟窗托/压到 winwidth 底线、winfixwidth
  侧栏托回原宽。三连毙：① 几何怪异——实测最大化后呈 1:6:x（侧栏 1 格、主区
  ~6 格、pane 其余），用户判定不如原 1:1:x 直觉，否决；② nvim 放额/挤压的
  落点不可预言（frame 级再分配跨窗流动、`set_width` 只向相邻取放），只能
  测量收敛式重试兜底，复杂度暴涨且仍有窗口滞留底线之下；③ 写死 21/20 之类
  封顶公式只在两窗布局正确。
- **winwidth 临时写死 1**：nvim 强制 `winwidth ≥ winminwidth`（**E592**，
  实测踩过：--clean 下 winminwidth=1 掩盖了它，真实配置一按就断链）——必须
  动态取 `vim.o.winminwidth`。
- **winfixwidth 挡挤压**：不设防（实测 neo-tree 40→5）——主动 resize 不认
  fix 标记；侧栏被碾碎是 9999 的既有行为，用户知情接受（"原来就是"）。
- **WinResized 事后压回**：事件驱动不违轮询红线，但要启发式区分"规则抬的
  vs 用户自己加宽的"，误伤 + 闪变——改规则读的值（预防）优于跟规则打架
  （纠正）。

## 已知边界

- 让位路径（docs/adr/0002 修订：清 `max_width`）不即时恢复 winwidth——
  agent_sessions 不反向调用 keymaps；残留的 winwidth=winminwidth 在常态布局
  （无 <winminwidth 宽的窗口）无可观察差异，下次最大化→还原循环自愈。
- headless 回归判据（scripts/test-agent-pane-layout.lua 判据 5）显式设
  winminwidth=5 对齐真实配置，否则 --clean 默认 1 会掩盖 E592 类错误。

回归：scripts/test-agent-pane-layout.sh；TUI 端到端（真 toggle + picker 两轮
宽度恒定 + neo-tree 1:1:x 几何）已实测通过，无法 headless 固化，记录于此。
