-- shell 领地标记回归 payload（scripts/test-shell-territory.sh 驱动，headless --clean）。
-- 判据 = winvar/窗口状态实测。领地语义（2026-10-27 修订，ADR 0002）：
-- shell 领地只认 snacks 管理的终端窗（w:snacks_win），普通窗承载的 terminal
-- buffer（:terminal mysql、H/L 轮换）不入领地。覆盖：
-- 1) 轮换进 manual terminal：不标记、不 relocate、窗口数不增（泄漏案本体）
-- 2) snacks 底部 shell 首开：TermOpen 兜底照常标记
-- 3) 文件入侵真领地：relocate 照常（terminal 恢复、文件落真编辑窗）
-- 4) 候选仅剩侧栏（nofile）时：不塞侧栏，新开 split（main_target_win 过滤）
-- 5) hide/show 换窗：schedule 复查自愈重标
-- 6) 领地窗内切 terminal：territory_buf 记账不回归
package.path = REPO .. "/lua/?.lua;" .. package.path
local A = require("agent_sessions")
A.setup()

local lib = dofile(REPO .. "/scripts/testlib.lua")
local check, quiesce = lib.check, lib.quiesce
local function wins() return vim.api.nvim_list_wins() end
local function buf_of(w) return vim.api.nvim_win_get_buf(w) end
local function buftype(w) return vim.bo[buf_of(w)].buftype end

-- 布局：tab1 = [侧栏(nofile) | a.txt]（结构等价 neo-tree 布局，无需真插件）
vim.cmd("edit " .. REPO .. "/README.md")
local main = vim.api.nvim_get_current_win()
local filebuf = buf_of(main)
vim.cmd("vsplit")
local side = vim.api.nvim_get_current_win()
local sidebuf = vim.api.nvim_create_buf(false, true)
vim.bo[sidebuf].buftype = "nofile"
vim.api.nvim_win_set_buf(side, sidebuf)
vim.wo[side].winfixwidth = true
vim.api.nvim_set_current_win(main)

-- manual terminal（mysql 替身）：新 tab 新窗承载（:tabnew | terminal 时序）
vim.cmd("tabnew | terminal sh")
local termbuf = vim.api.nvim_get_current_buf()
local birthwin = vim.api.nvim_get_current_win()
quiesce(200)
check("manual terminal 出生窗不入领地", vim.w[birthwin].shell_term == nil)

-- 场景 1：轮换 H/L 等价（:buffer / 回文件）×3 —— 泄漏案本体
local base_wins = #wins()
for i = 1, 3 do
  vim.api.nvim_set_current_win(main)
  vim.cmd("buffer " .. termbuf)
  quiesce(150)
  check("轮换进 terminal 不标记领地（第" .. i .. "次）", vim.w[main].shell_term == nil)
  check("侧栏未被标记领地（第" .. i .. "次）", vim.w[side].shell_term == nil)
  vim.cmd("buffer " .. filebuf)
  quiesce(150)
  check("窗口数不增（第" .. i .. "次）", #wins() == base_wins)
  check("侧栏 buffer 未被收留（第" .. i .. "次）", buf_of(side) == sidebuf)
end

-- 场景 2+3：snacks 底部 shell 首开标记 + 文件入侵 relocate
-- 按 snacks open_win 真实时序模拟：split 载入 termbuf（BWE，buftype 尚 ""）
-- → 写 w:snacks_win → termopen（TermOpen 兜底标记）
vim.cmd("tabnew")
local scratch = buf_of(vim.api.nvim_get_current_win())
vim.cmd("botright 10split")
local shellwin = vim.api.nvim_get_current_win()
local shellbuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(shellwin, shellbuf)
vim.w[shellwin].snacks_win = { id = 1, position = "bottom" }
vim.api.nvim_buf_call(shellbuf, function() vim.fn.termopen("sleep 600") end)
quiesce(300)
check("snacks 底部 shell 首开标记领地", vim.w[shellwin].shell_term == true)
check("territory_buf 记账 shellbuf", vim.w[shellwin].territory_buf == shellbuf)
check("邻窗（scratch）不受波及", vim.w[main].shell_term == nil)

local wins_before_intrude = #wins()
vim.api.nvim_set_current_win(shellwin)
vim.cmd("edit " .. REPO .. "/CONTEXT.md")
local intruder = buf_of(shellwin)
quiesce(400)
check("入侵后领地恢复 terminal", buf_of(shellwin) == shellbuf)
local iwin = vim.fn.bufwinid(intruder)
check("入侵文件落在真编辑窗", iwin ~= -1 and buftype(iwin) == "")
check("入侵不增窗", #wins() == wins_before_intrude)

-- 场景 4：候选仅剩侧栏（nofile）——不塞侧栏，新开 split
vim.cmd("tabnew")
local sbwin = vim.api.nvim_get_current_win()
local sbbuf = vim.api.nvim_create_buf(false, true)
vim.bo[sbbuf].buftype = "nofile"
vim.api.nvim_win_set_buf(sbwin, sbbuf)
vim.cmd("botright 10split")
local sw2 = vim.api.nvim_get_current_win()
local shellbuf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(sw2, shellbuf2)
vim.w[sw2].snacks_win = { id = 2, position = "bottom" }
vim.api.nvim_buf_call(shellbuf2, function() vim.fn.termopen("sleep 600") end)
quiesce(300)
check("场景 4 领地就位", vim.w[sw2].shell_term == true)
vim.api.nvim_set_current_win(sw2)
vim.cmd("edit " .. REPO .. "/lua/agent_sessions.lua")
local intruder2 = buf_of(sw2)
quiesce(400)
check("侧栏未收留入侵文件", buf_of(sbwin) == sbbuf)
check("侧栏未被误标记领地", vim.w[sbwin].shell_term == nil)
check("领地窗恢复 terminal", buf_of(sw2) == shellbuf2)
local dwin = vim.fn.bufwinid(intruder2)
check("文件落在新开编辑窗", dwin ~= -1 and dwin ~= sbwin and dwin ~= sw2)

-- 场景 5：hide/show 换窗自愈（BWE 时 buftype 已 terminal → schedule 复查重标）
vim.api.nvim_win_close(shellwin, true)
quiesce(100)
vim.cmd("botright 10split")
local shellwin2 = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(shellwin2, shellbuf)
vim.w[shellwin2].snacks_win = { id = 1, position = "bottom" }
quiesce(300)
check("hide/show 换窗后自愈重标", vim.w[shellwin2].shell_term == true)
check("自愈后 territory_buf 正确", vim.w[shellwin2].territory_buf == shellbuf)

-- 场景 6：领地窗内切 terminal，territory_buf 记账（shell_term 分支，未改）
local shellbuf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_call(shellbuf3, function() vim.fn.termopen("sleep 600") end)
vim.api.nvim_set_current_win(shellwin2)
vim.cmd("buffer " .. shellbuf3)
quiesce(150)
check("领地窗切换 terminal 记账", vim.w[shellwin2].territory_buf == shellbuf3)
check("记账不额外标记他窗", vim.w[birthwin].shell_term == nil and vim.w[main].shell_term == nil)

lib.finish()
