# nvim-config

个人 Neovim 配置（LazyVim 基座）。本文件只做词汇表：统一配置中 AI agent 相关的叫法。

## Language

**Agent**:
当前配置的 AI 助手程序，三选一：claude / opencode / codex。由全局设置选择，同一时刻只有一种类型处于启用状态。
_Avoid_: AI、assistant、codex（用具体类型名指代时除外）

**Session**:
一个独立运行的 agent 进程，带各自的对话历史，各自执行一个任务。多个 session 可以同时存活，称呼用其在存活列表中的位置编号（如 claude #2），前面的 session 退出后编号顺延，不手动命名。
_Avoid_: terminal、buffer、instance、tab

**Agent pane**:
界面上唯一展示 session 的窗口槽位（右侧固定位置）。同一时刻只显示一个 session 的内容，切换 session 即换 pane 中的内容，隐藏 pane 不影响后台 session。
_Avoid_: agent window、sidebar（左侧文件栏才是 sidebar）

**Tab page**:
一个项目/任务的工作区：一套代码窗口布局。与 session 无关，不用于承载 session。
_Avoid_: 用 tab 指代 session 或文件
