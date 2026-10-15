# nvim-config

个人 Neovim 配置（LazyVim 基座）。本文件只做词汇表：统一配置中 AI agent 相关的叫法。

## Language

**Agent**:
当前配置的 AI 助手程序，三选一：claude / opencode / codex。由全局设置选择，同一时刻只有一种类型处于启用状态。
_Avoid_: AI、assistant、codex（用具体类型名指代时除外）

**Session**:
一个独立运行的 agent 进程，带各自的对话历史，各自执行一个任务。多个 session 可以同时存活，称呼用其在存活列表中的位置编号（如 claude #2），前面的 session 退出后编号顺延，不手动命名。
_Avoid_: terminal、buffer、instance、tab

**Session 状态（working / idle / attention）**:
session 的回合级状态，由各家官方事件出口经统一事件管线驱动（docs/adr/0003）：working=回合进行中；idle=一轮完成、等待输入（即"completed"）；attention=等待用户确认（权限等）。进程退出不是状态——session 退出即移除，不留显示不留色。statusline 里每 session 一个等距表情机器人图标：working=excited、idle=happy、attention=confused，实心=当前、空心孪生=后台；无事件（未知）无表情（robot 对）——"未知"≠"睡觉"；pane 收起时全体换睡觉机器人（robot_off），颜色照旧=状态。
_Avoid_: running/completed/failed（用统一状态词）、把退出当状态

**Agent pane**:
主工作区右侧固定槽位的 session 显示窗（多视口之一，见"视口"）。同一时刻只显示一个 session 的内容，切换 session 即换 pane 中的内容，隐藏 pane 不影响后台 session。pane 几何（宽度/最大化）只属于用户：session 生死、pane 隐藏复显一律不碰既有几何；唯一例外见"Pane 让位"，以及窗口重建（全灭后复现）回初始宽度。
_Avoid_: agent window、sidebar（左侧文件栏才是 sidebar）

**Agent tab**:
session 池的专属工作区 tab（左 agent list + 右显示窗，docs/adr/0005），与 Agent pane 并列的视口，各有分工：编辑为主用 pane，agent 为主用 tab。`<leader>at` 幂等切换（不存在则建于末尾、存在则切入，已在其中 no-op 且该键不显示）；空态保留 tab 壳（欢迎页）。
_Avoid_: 把 Agent tab 当 session 容器或过渡形态（tab 仍是工作区；双视口是终态分工）

**视口（viewport）**:
同一 session 池的一种呈现。现有四：Agent pane、picker、statusline 图标串、Agent tab。单一全局 current：任一视口选中即更新，所有"显示窗"同步显示 current（terminal buffer 多窗显示，输入进同一个 job）。
_Avoid_: 视口=副本/分身（不是两个 agent，是两个取景）

**Pane 让位**:
主区没有文件窗口而有文件需要落位时，pane 缩回初始宽度（右侧槽位 30%）、文件开进主区，同一动作取消 pane 的最大化（若有）。这是唯一允许系统改写 pane 几何的路径（docs/adr/0002）。
_Avoid_: 把 session 退出、picker 开关当作让位（它们不得改 pane 几何）

**Tab page**:
一个项目/任务的工作区：一套代码窗口布局。不按 session 分 tab（如一个 agent 一个 tab，docs/adr/0001）；唯一例外是专属 Agent tab——所有 session 共用的一个工作区 tab（docs/adr/0005）。
_Avoid_: 用 tab 指代 session 或文件
