-- agent pane 布局回归 payload（scripts/test-agent-pane-layout.sh 驱动，headless --clean）。
-- 判据 = 窗口/模块状态实测，不依赖 UI redraw。覆盖（docs/adr/0002 修订、0004）：
-- 1) 最大化 pane 上关当前 session：原窗原宽（bd! 删正显示 buffer 连带关窗的回归）
-- 2) 关后台 session：布局不动
-- 3) 独占布局删最后一个 session：指针清空、领地交还（E444 崩溃回归）
-- 4) 领地独占时文件进入 pane：让位回 30% 且清除 max_width（陈旧 toggle 还原值）
-- 5) <C-S-Right> 拉满：9999 原语义挤到 winminwidth，最大化期间重算底线对齐
--    挤压底线 winwidth=winminwidth（否则重算把兄弟窗抬回 20、从 pane 偷宽）
package.path = REPO .. "/lua/?.lua;" .. package.path
local A = require("agent_sessions") -- require 而非 dofile：keymaps 顶层会拉起
-- agent_tab → agent_sessions，两份实例会让空实例的领地守卫拆掉真实例的标记
dofile(REPO .. "/lua/config/keymaps.lua") -- 真键位路径：toggle_max_width 让回逻辑
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
local function quiesce(ms) -- 静置：谓词恒假，等 schedule 链走完
  vim.wait(ms or 400, function()
    return false
  end)
end
local function pane_win()
  local buf = A.current_buf()
  if not buf then
    return
  end
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      return w
    end
  end
end
local function wins()
  return vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
end
-- 直接调真键位的回调：nvim_input 注入的 <C-S-Right> 修饰键编码在 headless
-- 下不落到该映射上（迟到执行反而污染后续断言），回调等价且确定
local function press_max_width()
  local m = vim.fn.maparg("<C-S-Right>", "n", false, true) -- dict=true 才带 callback
  assert(type(m.callback) == "function", "toggle_max_width 映射缺失")
  m.callback()
end

vim.o.columns = 200
vim.o.lines = 50
vim.o.winminwidth = 5 -- 对齐真实配置（--clean 默认 1 会掩盖 E592：winwidth 不得小于 winminwidth）

-- 场景 A：两窗布局，最大化后删 session ------------------------------
A.claude_open("/bin/sleep 600", {}, false) -- session #1（后台）
A.claude_open("/bin/sleep 600", {}, false) -- session #2（当前显示）
local pw = pane_win()
vim.api.nvim_set_current_win(pw)
vim.cmd("stopinsert")

-- 判据 5：真 <C-S-Right>——9999 原语义（兄弟压到 winminwidth）+ 最大化期间
-- 重算底线对齐挤压底线（winwidth=winminwidth，重算无从抬宽偷宽，ADR 0004）
press_max_width()
check("最大化已执行（winvar 落地）", vim.w[pw] and vim.w[pw].max_width ~= nil)
check("最大化期间 winwidth 对齐 winminwidth", vim.o.winwidth == vim.o.winminwidth)
local maxed = vim.api.nvim_win_get_width(pw)
check("拉满保持 9999 语义（兄弟窗压到 winminwidth）", maxed == 200 - 1 - vim.o.winminwidth)
press_max_width() -- 还原
check("还原后宽度回原值", vim.api.nvim_win_get_width(pw) == 60)
check("还原后 winwidth 恢复默认", vim.o.winwidth == 20)
press_max_width() -- 为后续判据重新拉满
maxed = vim.api.nvim_win_get_width(pw)
quiesce()

-- 判据 1：关当前 session，pane 原窗原宽
A.delete(2, true)
check(
  "关当前后 session 数减一",
  vim.wait(2000, function()
    return A.count() == 1
  end)
)
quiesce()
check("关当前后 pane 窗口未重建", pane_win() == pw)
check("关当前后 pane 宽度不变", vim.api.nvim_win_get_width(pw) == maxed)
check("关当前后无多余窗口", #wins() == 2)

-- 判据 2：关后台 session，布局不动（新 spawn 的 #3 为当前，#1 转后台）
A.claude_open("/bin/sleep 600", {}, false) -- session #3（当前显示）
quiesce()
local pw3 = pane_win()
A.delete(1, true)
check(
  "关后台后 session 数减一",
  vim.wait(2000, function()
    return A.count() == 2
  end)
)
quiesce()
check("关后台后 pane 窗口宽度不变", pane_win() == pw3 and vim.api.nvim_win_get_width(pw3) == maxed)

-- 判据 3：独占布局删最后一个 session，无 E444、状态收干净
for _, w in ipairs(wins()) do
  if w ~= pw3 then
    pcall(vim.api.nvim_win_close, w, true)
  end
end
A.delete(3, true) -- 当前
check(
  "删当前至剩一个",
  vim.wait(2000, function()
    return A.count() == 1
  end)
)
A.delete(4, true) -- 最后一个
check(
  "删最后一个后 session 清零",
  vim.wait(2000, function()
    return A.count() == 0
  end)
)
quiesce()
check("删最后一个后 pane 指针清空", not A.pane_visible())
local survivor = wins()[1]
check(
  "幸存窗口已非领地且非 terminal",
  vim.w[survivor].agent_pane == nil and vim.bo[vim.api.nvim_win_get_buf(survivor)].buftype ~= "terminal"
)

-- 场景 B：领地独占时文件进入 pane（让位 + 清 max_width）------------
A.claude_open("/bin/sleep 600", {}, false) -- 新 session，pane 另立（初始 30%）
quiesce()
local pb = pane_win()
for _, w in ipairs(wins()) do
  if w ~= pb then
    pcall(vim.api.nvim_win_close, w, true)
  end
end
vim.api.nvim_set_current_win(pb)
vim.cmd("stopinsert")
press_max_width()
check("场景 B 最大化已执行", vim.w[pb] and vim.w[pb].max_width ~= nil)
quiesce()

local fbuf = vim.api.nvim_create_buf(false, true) -- 非 terminal、非 agent：对领地是入侵
vim.api.nvim_buf_set_name(fbuf, "fake_file.txt")
vim.api.nvim_win_set_buf(pb, fbuf) -- 触发 ADR 0002 守卫：让位
quiesce(600)
check("让位后 pane 回初始宽度", vim.api.nvim_win_get_width(pb) == math.floor(200 * 0.30))
check("让位后 max_width 已清除", vim.w[pb].max_width == nil)
local fbuf_relocated = false
for _, w in ipairs(vim.fn.win_findbuf(fbuf)) do
  if w ~= pb then
    fbuf_relocated = true
  end
end
check("入侵文件已被搬到主区", fbuf_relocated)

A.delete(5, true)
vim.wait(2000, function()
  return A.count() == 0
end)

-- 判据 6（ADR 0002 修订）：反向入侵——agent buffer 不出领地窗。
-- split 克隆 pane（w: 变量不继承、buffer 已在别窗显示不触发 BWE——实测），
-- 泄漏窗靠 WinNew/WinEnter/BufEnter 清查兜底回收
A.claude_open("/bin/sleep 600", {}, false)
vim.wait(800, function()
  return false
end)
local pb6 = pane_win()
local wins_before6 = #wins()
local clone_buf = A.current_buf()
vim.api.nvim_win_call(pb6, function() vim.cmd("split") end)
vim.wait(800, function()
  return false
end)
local stray = 0
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == clone_buf
    and not vim.w[w].agent_pane and not vim.w[w].shell_term and not vim.w[w].agent_tree
  then
    stray = stray + 1
  end
end
check("split 克隆的 agent buffer 已被清退", stray == 0)
check("清退即关窗、无残留空窗", #wins() == wins_before6)
check("pane 自身不受清退影响", vim.api.nvim_win_get_buf(pb6) == clone_buf)
A.delete(A.current_id(), true)
vim.wait(2000, function()
  return A.count() == 0
end)

print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
