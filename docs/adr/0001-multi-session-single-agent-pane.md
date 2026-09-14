# 多 agent session：后台 terminal buffer + 单一 agent pane

日期：2026-09-14，状态：accepted

需要并行跑多个 agent 任务（每个 session 是独立进程、独立对话历史）。决定：session 在后台以 terminal buffer 存活，界面上只有一个 agent pane（右侧固定槽位），切换 session 即换 pane 中的 buffer，隐藏 pane 不影响后台进程。tab page 不承载 session。

## Considered Options

- **一个 agent 一个 tab page**：否决。本配置中 tab page 是项目/任务工作区（`g1-`​`g9`），塞进 agent 会打乱这个心智模型。
- **多个 split 同屏并排**：否决。动机是"同时活着、轮换关注"，不是同时读两边的输出；且多个 split 抢位置正是历史布局 bug（commit 1f3e14d 所修）的来源。单 pane 使布局恒定。

## 刻意为之的细节（不要"修"它们）

- `<` / `>` 循环键是 **buffer-local**（terminal buffer 内、normal 模式），与左侧栏循环切换的体验统一。不能改成全局映射：那会覆盖代码 buffer 的缩进操作符（`>j`、`<ap`）。terminal 模式下这两个字符照常进入 agent 输入框，属预期行为。
- 不混用 agent 类型：N 个 session 都是 `ai_assistant` 当前选中的类型。
- session 按创建顺序自动编号（`claude #2`），不手动命名；进程退出即从列表消失，不留记录；所有 session 统一从 nvim cwd 启动。
- 三个集成接入点不同：codex.lua 完全自控；claudecode.nvim 走其自定义 terminal provider 接口（`provider` 函数表，`ClaudeCodeSend` 经 `provider.send` 照常工作）；opencode.nvim 绕开其单例 toggle，用其导出的 `terminal.setup(win)` 给自建终端挂 session 导航键位。
