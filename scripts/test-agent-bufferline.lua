-- 真 bufferline + 假 agent 常驻进程：域隔离、标签导航/点击/关闭、pane 同步。
package.path = REPO .. "/lua/?.lua;" .. package.path
local plugin = vim.env.BUFFERLINE_DIR or (vim.fn.stdpath("data") .. "/lazy/bufferline.nvim")
assert(vim.uv.fs_stat(plugin .. "/lua/bufferline.lua"), "set BUFFERLINE_DIR to a bufferline.nvim checkout")
vim.opt.rtp:prepend(plugin)
vim.g.ai_assistant = "claude"
vim.o.columns, vim.o.lines = 200, 50
local lib = dofile(REPO .. "/scripts/testlib.lua")
local check, quiesce, press = lib.check, lib.quiesce, lib.press

-- 在真实 keymaps/setup 路径上安装 spec 的键位与 opts，不启动 LazyVim。
dofile(REPO .. "/lua/config/keymaps.lua")
dofile(REPO .. "/lua/config/autocmds.lua")
local A, T = require("agent_sessions"), require("agent_tab")
local spec = dofile(REPO .. "/lua/plugins/bufferline.lua")
local delegated = {}
local opts = {
  options = {
    show_buffer_icons = false,
    diagnostics = false,
    close_command = function(buf)
      delegated.close = buf
    end,
    right_mouse_command = function(buf)
      delegated.right = buf
    end,
  },
}
spec.opts(nil, opts)
require("bufferline").setup(opts)
for _, key in ipairs(spec.keys) do
  vim.keymap.set("n", key[1], key[2], { desc = key.desc })
end
local options = opts.options
local function elements()
  nvim_bufferline() -- headless 没有 TUI redraw，显式走真渲染更新组件快照
  return require("bufferline").get_elements().elements
end
local function contains(items, buf)
  for _, item in ipairs(items) do
    if item.id == buf then
      return true
    end
  end
  return false
end
local function display_buf()
  return vim.api.nvim_win_get_buf(vim.t[T.tab()].agent_display)
end

local editor = vim.api.nvim_get_current_tabpage()
local main = vim.api.nvim_get_current_win()
local file1 = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(file1, "bufferline-one.txt")
local file2 = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(file2, "bufferline-two.txt")
A.claude_open("/bin/cat", {}, false)
local first = A.current_id()
local pane
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(editor)) do
  if vim.w[win].agent_pane then
    pane = win
  end
end
A.claude_open("/bin/cat -u", {}, false)
local second = A.current_id()
A.claude_open("/bin/cat -u", {}, false)
local third = A.current_id()
quiesce()
local listed = elements()
check(
  "editor 只列文件，pane 可见也不泄漏 agent 标签",
  #listed == 2 and contains(listed, file1) and contains(listed, file2) and A.pane_visible()
)
check(
  "所有 agent buffer 都是 listed（bufferline 真实候选）",
  vim.bo[A.buf_of(first)].buflisted and vim.bo[A.buf_of(second)].buflisted and vim.bo[A.buf_of(third)].buflisted
)
vim.api.nvim_set_current_win(main)
vim.api.nvim_set_current_buf(file1)
elements()
press("<S-l>")
check("editor L 仍用 bufferline 切文件", vim.api.nvim_get_current_buf() == file2 and A.current_id() == third)
elements()
press("<S-h>")
check("editor H 仍用 bufferline 切文件", vim.api.nvim_get_current_buf() == file1 and A.current_id() == third)
options.close_command(file1)
options.right_mouse_command(file2)
check("文件关闭操作仍委托原实现", delegated.close == file1 and delegated.right == file2)

T.toggle()
quiesce()
local tab = T.tab()
listed = elements()
check(
  "agent tab 只列三个 agent，无文件/树/空白占位",
  #listed == 3
    and contains(listed, A.buf_of(first))
    and contains(listed, A.buf_of(second))
    and contains(listed, A.buf_of(third))
    and not contains(listed, file1)
)
check("无名标签使用类型 + 位置编号", options.name_formatter({ bufnr = A.buf_of(first) }) == "claude #1")
-- 改名走真实事件邮箱（claude 权威回流），不伪造本地名字。
local tag = vim.fn.getpid() .. "." .. second
local line = vim.json.encode({ tag = tag, name = "标签里的名字" })
vim.fn.writefile({ line }, A.event_file(), "a")
check(
  "名字事件已回流",
  vim.wait(2000, function()
    return options.name_formatter({ bufnr = A.buf_of(second) }) == "标签里的名字"
  end)
)

-- 手动打乱顺序，H/L 必须仍和眼前的标签一致。
require("bufferline").move(-1)
listed = elements()
local current
for i, item in ipairs(listed) do
  if item.id == A.current_buf() then
    current = i
  end
end
local previous = listed[((current - 2) % #listed) + 1].id
press("<S-h>")
quiesce()
check(
  "agent H 按标签顺序切换，右窗与跨 tab pane 同步",
  A.current_buf() == previous and display_buf() == previous and vim.api.nvim_win_get_buf(pane) == previous
)
elements()
press("<S-l>")
quiesce()
check("agent L 按标签顺序返回", A.current_id() == third and display_buf() == A.buf_of(third))
listed = elements()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  if vim.w[win].agent_tree then
    vim.api.nvim_set_current_win(win)
  end
end
press("<S-l>")
quiesce()
check(
  "树内 L 也切换右窗，不污染树窗",
  A.current_id() ~= third and vim.w.agent_tree == true and not vim.b.agent_session and display_buf() == A.current_buf()
)

-- 点击标签不可直接 :buffer，必须走 select 并把焦点送显示窗。
options.left_mouse_command(A.buf_of(first))
quiesce()
check(
  "点击标签更新 current、双视口并聚焦右窗",
  A.current_id() == first
    and display_buf() == A.buf_of(first)
    and vim.api.nvim_win_get_buf(pane) == A.buf_of(first)
    and vim.api.nvim_get_current_win() == vim.t[tab].agent_display
)
press("<", A.current_buf())
press(">", A.current_buf())
quiesce()
check("agent tab 内 </> 不再切换", A.current_id() == first)
options.close_command(A.buf_of(second))
options.right_mouse_command(A.buf_of(third))
quiesce()
check(
  "agent 标签关闭走优雅退出，不委托文件强删",
  A.count() == 3 and delegated.close == file1 and delegated.right == file2
)

vim.api.nvim_set_current_tabpage(editor)
vim.api.nvim_set_current_win(pane)
quiesce()
elements()
press(">", A.current_buf())
quiesce()
check("回 editor 后 pane 的 > 仍循环 session", A.current_id() == second)
press("<", A.current_buf())
quiesce()
check("回 editor 后 pane 的 < 仍循环 session", A.current_id() == first)
listed = elements()
check("返回 editor 后仍无 agent 标签", #listed == 2 and not contains(listed, A.current_buf()))

-- session 生死即时反映到标签，空壳只留 tab 页标签；空列表 H/L 安全。
vim.api.nvim_set_current_tabpage(tab)
A.delete(third, true)
quiesce()
listed = elements()
check("退出的 agent 标签立即消失", #listed == 2 and not contains(listed, A.buf_of(third)))
A.delete(second, true)
A.delete(first, true)
quiesce()
check("全灭后标签为空且 tab 壳保留", #elements() == 0 and T.tab() == tab)
press("<S-h>")
press("<S-l>")
check("空态 H/L 为 no-op", A.count() == 0 and T.tab() == tab)
A.claude_open("/bin/cat -u", {}, false)
quiesce()
check("tab 内新建 agent 立即加入标签", #elements() == 1 and contains(elements(), A.current_buf()))
vim.api.nvim_set_current_tabpage(editor)
quiesce()

-- agent 列表不得把 editor 的单文件 tabline 撑出来。
vim.api.nvim_buf_delete(file2, { force = true })
vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tab))
quiesce()
check("单 editor tab + 单文件：后台 agent 不影响显隐", vim.o.showtabline == 0)
for _, item in ipairs(A.list()) do
  A.delete(item.id, true)
end
quiesce()
lib.finish()
