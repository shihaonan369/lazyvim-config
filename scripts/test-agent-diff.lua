-- inline diff 回归 payload（scripts/test-agent-diff.sh 驱动，headless --clean）。
-- 假 TUI 冒充 claude 建 session（tag = getpid().1），手工落快照模拟
-- agent-diff-hook.sh 的产物，判据（ADR 0007 层 2，先落后审）：
-- 1) changed() 列出存活 session 的快照
-- 2) review：开一对新窗（快照/现况）且双双 diffthis；pane 宽度未动（领地：
--    几何只属于用户，ADR 0002）
-- 3) deny：文件字节回基线、快照删、审查窗撤
-- 4) accept：改动留盘、快照删、审查窗撤
-- 5) ExitPre：本实例 tag 目录清空（孤儿不留）
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）
vim.g.claude_backend = "native" -- 同上（ADR 0007）

-- 假 TUI 先落盘、先设 AGENT_CLAUDE_BIN 再 require——CLAUDE_BIN 加载时求值
local fake = "/tmp/fake-claude-" .. vim.fn.getpid()
vim.fn.writefile({
  "#!/bin/sh",
  "sleep 0.4",
  "printf 'Claude Code (fake) v1\\n\\n❯ \\n'",
  "exec cat",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.AGENT_CLAUDE_BIN = fake

local A = require("agent_sessions")
A.setup()
local D = require("agent_diff")
D.setup()

local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

local ROOT = vim.fn.stdpath("run") .. "/agent-diff"
local tag = vim.fn.getpid() .. ".1" -- A.new 首个 session 的 tag

-- 场景：file 盘上是 agent 改后的内容，快照是回合基线
local file = vim.fn.tempname()
vim.fn.writefile({ "new-1", "old-2" }, file)
local snap = ROOT .. "/" .. tag .. file
vim.fn.mkdir(vim.fn.fnamemodify(snap, ":h"), "p")
vim.fn.writefile({ "old-1", "old-2" }, snap)

A.new() -- 建存活 session（tag 对齐快照目录）
check("1 changed 列出快照", (function()
  local items = D.changed()
  return #items == 1 and items[1].file == file
end)())

-- pane 宽度基线（领地几何只属于用户）
local function pane_width()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.b[b].agent_session then return vim.api.nvim_win_get_width(w) end
  end
end
local wins_before = #vim.api.nvim_list_wins()
local orig_tab = vim.api.nvim_get_current_tabpage()
local pane_w = pane_width()

D.review(file)
local rtab = vim.api.nvim_get_current_tabpage()
check("2a 审查开专属 tab 两窗", vim.api.nvim_get_current_tabpage() ~= orig_tab
  and #vim.api.nvim_tabpage_list_wins(rtab) == 2)
check("2b 快照窗在显且 diffthis", (function()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(rtab)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_buf_get_name(b) == "agent-diff://" .. file then
      return vim.wo[w].diff == true
    end
  end
  return false
end)())
check("2c 现况窗 diffthis", (function()
  -- buffer 名经 :edit 的符号链接解析（macOS /var→/private/var），比较须 resolve
  local want = vim.fn.resolve(file)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(rtab)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.fn.resolve(vim.api.nvim_buf_get_name(b)) == want then
      return vim.wo[w].diff == true
    end
  end
  return false
end)())
check("2d pane 宽度未动", pane_width() == pane_w)

D.deny()
check("3 deny 回基线+删快照+撤审查", vim.wait(3000, function()
  return vim.fn.filereadable(snap) ~= 1
    and table.concat(vim.fn.readfile(file), "\n") == "old-1\nold-2"
    and not vim.api.nvim_tabpage_is_valid(rtab)
    and vim.api.nvim_get_current_tabpage() == orig_tab
end))

-- 判据 4：accept = 改动留盘（盘上保持 agent 改后内容）、快照删、审查撤
vim.fn.writefile({ "new-1", "old-2" }, file)
vim.fn.writefile({ "old-1", "old-2" }, snap)
D.review(file)
D.accept()
check("4 accept 改动留盘+删快照+撤审查", vim.fn.filereadable(snap) ~= 1
  and vim.fn.readfile(file)[1] == "new-1"
  and vim.api.nvim_get_current_tabpage() == orig_tab)

vim.cmd("doautocmd ExitPre")
check("5 ExitPre 清实例目录", vim.wait(2000, function()
  if vim.fn.isdirectory(ROOT) ~= 1 then return true end
  local prefix = tostring(vim.fn.getpid()) .. "."
  for name, _ in vim.fs.dir(ROOT) do
    if name:sub(1, #prefix) == prefix then return false end
  end
  return true
end))

-- 收尾
local ids = {}
for _, sess in ipairs(A.list()) do ids[#ids + 1] = sess.id end
for _, sid in ipairs(ids) do A.delete(sid, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.fn.delete(fake)
vim.fn.delete(file)
lib.finish()
