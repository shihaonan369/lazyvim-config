-- agent_tree 渲染跟随回归 payload（scripts/test-agent-tree.sh 驱动，headless
-- --clean + 真 neo-tree——lazy 路径注入 package.path，树本体渲染在此固化，
-- 补 test-agent-tab.lua 的 winvar 骨架降级盲区）。判据（2026-10-17 实测 bug：
-- 显示窗 </> 切换后树"高亮行"不跟随）：
-- 1) 首开/切换后 current 标记挪窝（树节点 extra.current 在正确行）
-- 2) 树光标行 = current 节点行（CursorLine 跟随——树里最醒目的行）
-- 3) 主 tab pane 侧切换后回 agent tab：TabEnter 补刷，标记与光标对齐当下
local LAZY = vim.fn.stdpath("data") .. "/lazy"
package.path =
  REPO .. "/lua/?.lua;"
  .. LAZY .. "/neo-tree.nvim/lua/?.lua;" .. LAZY .. "/neo-tree.nvim/lua/?/init.lua;"
  .. LAZY .. "/nui.nvim/lua/?.lua;" .. LAZY .. "/nui.nvim/lua/?/init.lua;"
  .. LAZY .. "/plenary.nvim/lua/?.lua;" .. LAZY .. "/plenary.nvim/lua/?/init.lua;"
  .. package.path

require("neo-tree").setup({
  sources = { "agent_tree" },
  default_source = "agent_tree",
})

vim.g.ai_assistant = "claude" -- 对齐真实配置默认（--clean 下未设会让 adapters 空转）
dofile(REPO .. "/lua/config/keymaps.lua") -- 真键位路径：<leader>at 映射 + agent_tab.setup()

local A = require("agent_sessions")
local T = require("agent_tab")
local manager = require("neo-tree.sources.manager")

local fails = {}
local function check(name, cond)
  print((cond and "ok   " or "FAIL ") .. name)
  if not cond then fails[#fails + 1] = name end
end
local function quiesce(ms)
  vim.wait(ms or 500, function() return false end)
end

local function tree_state()
  local tab = T.tab()
  if not tab then return end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.w[w].agent_tree then
      return manager.get_state("agent_tree", tab, w), w
    end
  end
end

-- 返回 current 节点所在行、树光标行
local function current_node_line()
  local state, tw = tree_state()
  if not state then return end
  local cur = A.current_id()
  if not cur then return end
  local _, linenr = state.tree:get_node("session:" .. cur)
  return linenr, vim.api.nvim_win_get_cursor(tw)[1]
end

-- 直接调 term buffer 上的 < / > 真键位回调（headless 惯例；maparg 必须在
-- term buffer 语境取——树 buffer 上这两个键是 "none"）
local function press_cycle(buf, lhs)
  local m
  vim.api.nvim_buf_call(buf, function() m = vim.fn.maparg(lhs, "n", false, true) end)
  assert(m and m.callback ~= nil, lhs .. " 映射缺失")
  m.callback()
end

vim.o.columns = 200
vim.o.lines = 50

A.claude_open("/bin/sleep 700", {}, false) -- #1
A.claude_open("/bin/sleep 701", {}, false) -- #2（当前）
check("两 session 就位", vim.wait(2000, function() return A.count() == 2 end))

T.toggle()
quiesce()
local before_node, before_cursor = current_node_line()
check("首开光标即 current 行", before_node ~= nil and before_node == before_cursor)

local dwin = vim.t[T.tab()].agent_display
local tbuf = vim.api.nvim_win_get_buf(dwin)
vim.api.nvim_set_current_win(dwin) -- 真实姿势：焦点在显示窗按 < / >

press_cycle(tbuf, "<")
quiesce()
local id1 = A.list()[1].id
check("显示窗 < 切到 #1", A.current_id() == id1)
local node1, cursor1 = current_node_line()
check("树 current 标记在 #1 行", node1 ~= nil and node1 == 1)
check("树光标行跟随 current（CursorLine 同步）", cursor1 == node1)

-- 判据 3：主 tab pane 上切换，回 agent tab 树补齐。pane 在 spawn 时已开
-- （claude_open → show_pane，tab 1 布局里），不能再 toggle——那会把开着的
-- pane 收起
vim.cmd("tabnext 1")
quiesce()
local pane_win
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
  if vim.w[w].agent_pane then pane_win = w end
end
local id2 = A.list()[2].id
A.select(id2, false) -- 主 tab 侧切 current
quiesce()
check("主 tab pane 显示新 current", pane_win ~= nil
  and vim.api.nvim_win_get_buf(pane_win) == A.buf_of(id2))

vim.api.nvim_set_current_tabpage(T.tab()) -- 回 agent tab：TabEnter 补刷
quiesce()
local node2, cursor2 = current_node_line()
check("回 agent tab 后树标记对齐 #2", node2 ~= nil and node2 == 2)
check("回 agent tab 后光标行对齐 #2", cursor2 == node2)

A.delete(id1, true)
A.delete(id2, true)
vim.wait(2000, function() return A.count() == 0 end)
print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
