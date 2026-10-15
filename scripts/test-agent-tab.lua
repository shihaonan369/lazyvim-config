-- agent tab 视口回归 payload（scripts/test-agent-tab.sh 驱动，headless --clean）。
-- 判据 = tab/窗口/模块状态实测，不依赖 UI redraw；neo-tree 缺席时树降级为
-- winvar 骨架（agent_tree winvar 判据与真实环境同构）。覆盖（docs/adr/0005）：
-- 1) <leader>at 幂等：末尾建 tab、首开自动新建、存在即切、tab 内 no-op 且撤映射
-- 1b) <leader>aa 视口分派：agent tab 内 = 树 toggle（主 tab 仍浮窗 picker，不在
--     --clean 测——Snacks 缺席，分派判据已保证不落到那段）
-- 2) tab 内再建：pane 不立、右窗即显、termopen 走 buf_call
-- 3) 单一 current 全视口同步：agent tab 选中，主 tab pane 跨 tab 换 buffer
-- 4) <C-a> 护栏：tab 内 toggle 不另立 pane 窗
-- 5) TermClose 顺延/清空：右窗跟 current，全灭转空白占位、tab 壳保留
-- 注：adapters 的 :ClaudeCode 冷启动链属 claudecode 插件域（--clean 无此命令），
-- 这里以预置 claude_cache（建后删）覆盖 agent.new() 的缓存路径
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）；--clean 下未设会让 adapters 空转
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

-- 预置 claude_cache：建一个 session 再删掉——缓存留下、session 清零、pane 收起。
-- 命令必须是单 token 常驻进程（adapters.claude.new 只取 cmd_list[1]，
-- 裸 /bin/sleep 缺参数会秒退）
A.claude_open("/bin/cat", {}, false)
check("缓存预置 session 建好", vim.wait(2000, function()
  return A.count() == 1
end))
A.delete(1)
check("预置 session 已清", vim.wait(2000, function()
  return A.count() == 0
end))
quiesce()

-- 判据 1：末尾建 tab、首开自动新建、左树右显示窗 ------------------------
check("<leader>at 已映射", type((vim.fn.maparg("<leader>at", "n", false, true)).callback) == "function")
press_at()
quiesce()
local tab = T.tab()
check("tab 已建于末尾", tab ~= nil and vim.api.nvim_get_current_tabpage() == tab
  and tab == vim.api.nvim_list_tabpages()[#vim.api.nvim_list_tabpages()])
check("布局两窗", #tab_wins() == 2)
local dwin = dw()
check("右窗领地身份", dwin ~= nil and vim.w[dwin].agent_pane == true)
check("首开自动新建 session（无欢迎页）", A.count() == 1
  and vim.bo[vim.api.nvim_win_get_buf(dwin)].buftype == "terminal")
local auto_id = A.current_id()
local tree_marked = false
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_tree == true then tree_marked = true end
end
check("左窗树身份（winvar 骨架）", tree_marked)
check("tab 内 <leader>at 已撤（which-key 不列）", vim.fn.maparg("<leader>at", "n") == "")

-- 判据 1b：<leader>aa 在 tab 内 = 树 toggle --------------------------------
A.picker() -- agent tab 内改道：关树
quiesce()
check("tab 内 <leader>aa 关树", #tab_wins() == 1)
check("关树后显示窗仍在", dw() ~= nil and vim.w[dw()].agent_pane == true)
A.picker() -- 再按：重开
quiesce()
check("tab 内 <leader>aa 重开树", #tab_wins() == 2)
local tree_again = false
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_tree == true then tree_again = true end
end
check("重开树窗身份就位", tree_again)

-- 判据 2：tab 内再建——pane 不立、右窗即显、无多余窗 ---------------------
A.claude_open("/bin/sleep 601", {}, false) -- 新 session（当前）
quiesce()
local opened_id = A.current_id()
check("两个 session 存活", A.count() == 2)
check("tab 内未另立窗", #tab_wins() == 2)
check("pane 未在 tab 内创建", not A.pane_visible())
check("右窗显示当前 session", vim.api.nvim_win_get_buf(dwin) == A.current_buf())

-- 判据 2b（ADR 0003 修订）：agent tab 内 statusline 段隐藏；可见性以当前视角
-- 为准——人在主 tab、pane 收着，agent tab 再在场也是"看不到"= 睡
check("agent tab 内 statusline 段隐藏", A.status() == "")
vim.cmd("tabnext 1")
quiesce()
local st = A.status()
local off = vim.fn.nr2char(0xF16A7)
check("主 tab pane 收起：睡觉（agent tab 在场也算看不到）", st ~= "" and st:find(off, 1, true) ~= nil)
vim.cmd("tabnext 2")
quiesce()

-- 判据 3：单一 current 全视口同步 --------------------------------------
A.select(auto_id, false) -- tab 内切回首开 session
quiesce()
check("tab 内切换右窗跟随", vim.api.nvim_win_get_buf(dwin) == A.buf_of(auto_id))
vim.cmd("tabnext 1") -- 主 tab：开 pane（旧路径不受扰）
A.toggle()
quiesce()
local pane_w
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_pane == true and w ~= dwin then pane_w = w end
end
check("主 tab pane 已开", pane_w ~= nil and A.pane_visible())
check("pane 显示同一 current", vim.api.nvim_win_get_buf(pane_w) == A.buf_of(auto_id))
-- rename（ADR 0003 修订）：claude 只发命令不落名（回流单点），树不假成功
A.rename(auto_id, "树外的名字")
check("r 只发命令不本地落名（claude 回流单点）", (function()
  for _, it in ipairs(A.list()) do
    if it.id == auto_id then return it.name == nil end
  end
end)())
vim.cmd("tabnext 2") -- 回 agent tab 选中另一个：主 pane 跨 tab 同步
A.select(opened_id, false)
quiesce()
check("agent tab 选中后 pane 跨 tab 换 buffer", vim.api.nvim_win_get_buf(pane_w) == A.buf_of(opened_id))
check("右窗显示新 current", vim.api.nvim_win_get_buf(dwin) == A.buf_of(opened_id))

-- 判据 4：<C-a> 护栏 ----------------------------------------------------
local wins_before = #tab_wins()
A.toggle() -- agent tab 内应 no-op
quiesce()
check("tab 内 toggle pane 为 no-op", #tab_wins() == wins_before and not A.pane_visible())

-- 判据 4b（ADR 0005）：域守卫——file buffer 落树窗，挪回来源 tab、树复原、
-- 视角跟随（agent tab 只收 agent 域）
local fbuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(fbuf, "agent-tab-stray.txt")
local tw0
for _, w in ipairs(tab_wins()) do
  if vim.w[w].agent_tree == true then tw0 = w end
end
vim.api.nvim_win_set_buf(tw0, fbuf)
quiesce(800)
local stray_tab
for _, t in ipairs(vim.api.nvim_list_tabpages()) do
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
    if vim.api.nvim_win_get_buf(w) == fbuf then stray_tab = t end
  end
end
check("file buffer 已挪出 agent tab", stray_tab ~= nil and stray_tab ~= tab)
local tree_kept = false
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  if vim.w[w].agent_tree == true then tree_kept = true end
end
check("树窗已复原", tree_kept and #vim.api.nvim_tabpage_list_wins(tab) == 2)
check("视角已跟到来源 tab", vim.api.nvim_get_current_tabpage() == 1)
vim.api.nvim_set_current_tabpage(tab) -- 回 tab 继续后续判据
quiesce()

-- 判据 5：TermClose 顺延/清空、空壳保留、离开恢复映射 -------------------
A.delete(opened_id) -- 当前，顺延首开 session
check("删当前后顺延", vim.wait(2000, function()
  return A.count() == 1
end))
quiesce()
check("右窗顺延显示存活 session", dw() ~= nil and vim.api.nvim_win_get_buf(dw()) == A.buf_of(auto_id))
A.delete(auto_id) -- 最后一个：转空白占位
check("全灭后 session 清零", vim.wait(2000, function()
  return A.count() == 0
end))
quiesce()
check("右窗转空白占位", dw() ~= nil and vim.b[vim.api.nvim_win_get_buf(dw())].agent_tab_welcome == true)
check("tab 空壳保留", T.tab() == tab)
vim.cmd("tabnext 1")
quiesce()
check("离开后 <leader>at 恢复", type((vim.fn.maparg("<leader>at", "n", false, true)).callback) == "function")
press_at() -- 幂等：存在即切（末尾那个）
quiesce()
check("再次 <leader>at 存在即切", vim.api.nvim_get_current_tabpage() == T.tab())

print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
