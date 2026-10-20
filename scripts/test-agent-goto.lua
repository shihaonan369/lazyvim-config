-- <leader>a1..9 直达位置编号判据（scripts/test-agent-goto.sh 驱动，headless
-- --clean；树降级为 winvar 骨架，同 test-agent-tab）。设计共识（2026-10-20）：
-- #n = 存活序位置编号（CONTEXT.md 词汇，切换不重排）；display 全语义不夺焦
-- （pane 开着换 buffer、收着弹出；agent tab 内右窗换 buffer）；树上不加编号
-- 前缀（图标串/树行位即编号）。判据：
-- 1) a1..9 映射在位，desc = "Agent #n"
-- 2) 主 tab pane 开着：a2 → current=#2、pane 换 buffer、焦点原地
-- 3) agent tab 内：焦点在树窗按 a1 → 右窗换 buffer、焦点不动
-- 4) 越界 a9（2 live）：notify 恰一条含 "#9"、current 不变（不假成功）
-- 5) pane 收着时 a2：弹出 pane 显 #2 且焦点回原窗——show_pane 的 botright
--    vsplit 会把当前窗留给新 pane 窗，键位层必须把焦点弹回去（弹出不夺焦）
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）；--clean 下未设会让 adapters 空转
dofile(REPO .. "/lua/config/keymaps.lua") -- 真键位路径

local A = require("agent_sessions")
local T = require("agent_tab")
A.setup()

local fails = {}
local function check(name, cond)
  print((cond and "ok   " or "FAIL ") .. name)
  if not cond then fails[#fails + 1] = name end
end
local function quiesce(ms)
  vim.wait(ms or 500, function() return false end)
end

-- 直调全局 n 模式键位回调（headless 惯例；<leader>a* 是全局映射，任意正常
-- buffer 语境取 maparg 均可）。映射缺失记 FAIL 返回 false——红相也走 qa!
-- 干净退出，assert 抛错会让 headless nvim 挂住不退
local function press(lhs)
  local m = vim.fn.maparg(lhs, "n", false, true)
  if not (type(m) == "table" and m.callback) then
    check(lhs .. " 映射在位", false)
    return false
  end
  m.callback()
  return true
end

local function win_with(mark, tab)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab or vim.api.nvim_get_current_tabpage())) do
    if vim.w[w][mark] then return w end
  end
end

vim.o.columns = 200
vim.o.lines = 50

A.claude_open("/bin/sleep 700", {}, false) -- #1
A.claude_open("/bin/sleep 701", {}, false) -- #2（当前）
check("两 session 就位", vim.wait(2000, function() return A.count() == 2 end))
local id1, id2 = A.list()[1].id, A.list()[2].id

-- 判据 1：映射在位（首/中/尾抽查 + desc）
for _, n in ipairs({ 1, 5, 9 }) do
  local m = vim.fn.maparg("<leader>a" .. n, "n", false, true)
  check("a" .. n .. " 映射在位", type(m) == "table" and m.callback ~= nil)
end
check("a3 desc = Agent #3", vim.fn.maparg("<leader>a3", "n", false, true).desc == "Agent #3")

-- 判据 2：主 tab（spawn 已开 pane）切换不夺焦。current 现为 #2，按 a1 切离
-- 才有状态变化可观察（按 a2 是同义反复，红相曾假绿）
local main_win = vim.api.nvim_get_current_win()
local p1 = press("<leader>a1")
quiesce()
check("a1 切 current 到 #1", p1 and A.current_id() == id1)
local pane_win = win_with("agent_pane")
check("pane buf 跟随 #1", p1 and pane_win ~= nil and vim.api.nvim_win_get_buf(pane_win) == A.buf_of(id1))
check("焦点原地", p1 and vim.api.nvim_get_current_win() == main_win)

-- 判据 3：agent tab 内右窗路由、焦点不动
T.toggle()
quiesce()
local tab = T.tab()
local dwin = vim.t[tab].agent_display
local twin = win_with("agent_tree", tab)
check("agent tab 骨架在位", dwin ~= nil and twin ~= nil)
vim.api.nvim_set_current_win(twin) -- 焦点放树窗再切：右窗换 buffer、人不动（此刻 current=#1，a2 切回才有变化）
local p2 = press("<leader>a2")
quiesce()
check("右窗 buf 跟随 #2", p2 and vim.api.nvim_win_get_buf(dwin) == A.buf_of(id2))
check("焦点仍在树窗", p2 and vim.api.nvim_get_current_win() == twin)

-- 判据 4：越界反馈。2 live 按 a9：静默 no-op 会让用户分不清键没生效还是
-- 没这个 agent——notify 一行（同 rename 处「不假成功」原则）
local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, _) notes[#notes + 1] = tostring(msg) end
local cur_before = A.current_id()
local p9 = press("<leader>a9")
quiesce()
vim.notify = orig_notify
check("越界 current 不变", p9 and A.current_id() == cur_before)
check("越界 notify 恰一条含 #9", #notes == 1 and notes[1]:find("#9", 1, true) ~= nil)

-- 判据 5：弹出分支不夺焦。pane 收着（hide）后按 a2，show_pane 于 botright
-- 重开 pane——键位语义是"弹出不夺焦"（状态切换键，不打断编辑）
vim.cmd("tabnext 1")
quiesce()
A.hide()
quiesce()
vim.api.nvim_set_current_win(main_win)
local p5 = press("<leader>a2")
quiesce()
local pane5 = win_with("agent_pane")
check("收着时 a2 弹出 pane 显 #2", p5 and pane5 ~= nil and vim.api.nvim_win_get_buf(pane5) == A.buf_of(id2))
check("弹出后焦点回原窗", p5 and vim.api.nvim_get_current_win() == main_win)

A.delete(id1, true)
A.delete(id2, true)
vim.wait(2000, function() return A.count() == 0 end)
print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
