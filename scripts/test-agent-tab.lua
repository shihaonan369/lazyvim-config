-- agent tab 视口回归 payload（scripts/test-agent-tab.sh 驱动，headless --clean）。
-- 判据 = tab/窗口/模块状态实测，不依赖 UI redraw；neo-tree 缺席时树降级为
-- winvar 骨架（agent_tree winvar 判据与真实环境同构）。覆盖（docs/adr/0005）：
-- 1) <leader>at 幂等：末尾建 tab、存在即切、tab 内 no-op 且撤映射
-- 2) tab 内 spawn：pane 不立、右窗即显、termopen 走 buf_call
-- 3) 单一 current 全视口同步：agent tab 选中，主 tab pane 跨 tab 换 buffer
-- 4) <C-a> 护栏：tab 内 toggle 不另立 pane 窗
-- 5) TermClose 顺延/清空：右窗跟 current，全灭转欢迎页、tab 壳保留
package.path = REPO .. "/lua/?.lua;" .. package.path
dofile(REPO .. "/lua/config/keymaps.lua") -- 真键位路径：<leader>at 映射 + agent_tab.setup()

local A = require("agent_sessions")
local T = require("agent_tab")
A.setup()

local fails = {}
local function check(name, cond)
  if cond then
    print("ok   " .. name)
  else
    print("FAIL " .. name)
    fails[#fails + 1] = name
  end
end
local function quiesce(ms)
  vim.wait(ms or 400, function()
    return false
  end)
end
local function press_at() -- 直接调真键位回调（headless 修饰键编码不可靠，判据同 pane 测试惯例）
  local m = vim.fn.maparg("<leader>at", "n", false, true)
  assert(type(m.callback) == "function", "<leader>at 映射缺失")
  m.callback()
end
local function tab_wins()
  return vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
end
local function dw() -- agent tab 右窗
  local tab = T.tab()
  local win = tab and vim.t[tab].agent_display
  if win and vim.api.nvim_win_is_valid(win) then return win end
end

vim.o.columns = 200
vim.o.lines = 50
vim.o.winminwidth = 5

-- 判据 1：末尾建 tab、身份标记、左树右显示窗、欢迎页 -------------------
check("<leader>at 已映射", type((vim.fn.maparg("<leader>at", "n", false, true)).callback) == "function")
press_at()
quiesce()
local tab = T.tab()
check("tab 已建于末尾", tab ~= nil and vim.api.nvim_get_current_tabpage() == tab
  and tab == vim.api.nvim_list_tabpages()[#vim.api.nvim_list_tabpages()])
check("布局两窗", #tab_wins() == 2)
local dwin = dw()
check("右窗领地身份", dwin ~= nil and vim.w[dwin].agent_pane == true)
check("右窗空态显示欢迎页", vim.b[vim.api.nvim_win_get_buf(dwin)].agent_tab_welcome == true)
local tree_marked = false
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_tree == true then tree_marked = true end
end
check("左窗树身份（winvar 骨架）", tree_marked)
check("tab 内 <leader>at 已撤（which-key 不列）", vim.fn.maparg("<leader>at", "n") == "")

-- 判据 2：tab 内 spawn——pane 不立、右窗即显、无多余窗 -------------------
A.claude_open("/bin/sleep 600", {}, false) -- session #1
A.claude_open("/bin/sleep 601", {}, false) -- session #2（当前）
quiesce()
check("两个 session 存活", A.count() == 2)
check("tab 内未另立窗", #tab_wins() == 2)
check("pane 未在 tab 内创建", not A.pane_visible())
check("右窗显示当前 session", vim.api.nvim_win_get_buf(dwin) == A.current_buf())

-- 判据 3：单一 current 全视口同步 --------------------------------------
A.select(1, false) -- tab 内切回 #1
quiesce()
check("tab 内切换右窗跟随", vim.api.nvim_win_get_buf(dwin) == A.buf_of(1))
vim.cmd("tabnext 1") -- 主 tab：开 pane（旧路径不受扰）
A.toggle()
quiesce()
local pane_w
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_pane == true and w ~= dwin then pane_w = w end
end
check("主 tab pane 已开", pane_w ~= nil and A.pane_visible())
check("pane 显示同一 current", vim.api.nvim_win_get_buf(pane_w) == A.buf_of(1))
vim.cmd("tabnext 2") -- 回 agent tab 选中 #2：主 pane 跨 tab 同步
A.select(2, false)
quiesce()
check("agent tab 选中后 pane 跨 tab 换 buffer", vim.api.nvim_win_get_buf(pane_w) == A.buf_of(2))
check("右窗显示新 current", vim.api.nvim_win_get_buf(dwin) == A.buf_of(2))

-- 判据 4：<C-a> 护栏 ----------------------------------------------------
local wins_before = #tab_wins()
A.toggle() -- agent tab 内应 no-op
quiesce()
check("tab 内 toggle pane 为 no-op", #tab_wins() == wins_before and not A.pane_visible())

-- 判据 5：TermClose 顺延/清空、空壳保留、离开恢复映射 -------------------
A.delete(2) -- 当前，顺延 #1
check("删当前后顺延", vim.wait(2000, function()
  return A.count() == 1
end))
quiesce()
check("右窗顺延显示 #1", dw() ~= nil and vim.api.nvim_win_get_buf(dw()) == A.buf_of(1))
A.delete(1) -- 最后一个：转欢迎页
check("全灭后 session 清零", vim.wait(2000, function()
  return A.count() == 0
end))
quiesce()
check("右窗转欢迎页", dw() ~= nil and vim.b[vim.api.nvim_win_get_buf(dw())].agent_tab_welcome == true)
check("tab 空壳保留", T.tab() == tab)
vim.cmd("tabnext 1")
quiesce()
check("离开后 <leader>at 恢复", type((vim.fn.maparg("<leader>at", "n", false, true)).callback) == "function")
press_at() -- 幂等：存在即切（末尾那个）
quiesce()
check("再次 <leader>at 存在即切", vim.api.nvim_get_current_tabpage() == T.tab())

print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
