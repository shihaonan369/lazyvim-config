-- Smart Add 草稿注入回归 payload（scripts/test-agent-add.sh 驱动，headless --clean）。
-- 假 TUI（fake-claude：延迟渲染 banner+❯ 后 exec cat 存活）驱动就绪队列，
-- 判据 = M.draft 的注入序列与「不提交」语义（ADR 0007 层 1；行范围语法
-- @path:l1-l2 / @path:l 是 claude 原生格式，2026-10-21 -p 实证，选区原文
-- 不随发——claude 按范围自己读盘）：
-- 1) 空池冷建：draft 无会话时自动 M.new（AGENT_CLAUDE_BIN 冒充，native 态）
-- 2) 序列：Ctrl-U(\21) 先于括号粘贴包 [200~...[201~（全文同包）
-- 3) 草稿内容精确：范围引用原文（无选区文本、无 CR）
-- 4) 草稿无 CR：draft 之后不产生新的 \13
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

-- chan_send 间谍：捕获注入原文（列表次序即发送次序）
local sent = {}
local orig_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, s)
  sent[#sent + 1] = s
  return orig_send(ch, s)
end
local function idx_of(pat, from)
  for i = from or 1, #sent do
    if sent[i]:find(pat, 1, true) then return i end
  end
end
local function idx_exact(txt, from)
  for i = from or 1, #sent do
    if sent[i] == txt then return i end
  end
end
local function count_exact(txt)
  local n = 0
  for i = 1, #sent do
    if sent[i] == txt then n = n + 1 end
  end
  return n
end

local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

-- 判据 1/2/3：空池范围引用草稿（<leader>as 选区形态：仅 @path:l1-l2，无原文）
A.draft("@/repo/lua/x.lua:3-5 ")
check("1 空池冷建", A.count() == 1)
check("1 草稿已送达", vim.wait(5000, function()
  return idx_of("[200~@/repo/lua/x.lua:3-5") ~= nil
end))
check("2 Ctrl-U 先于粘贴包", (function()
  local i_u, i_p = idx_exact("\21"), idx_of("[200~@/repo/lua/x.lua:3-5")
  return i_u ~= nil and i_p ~= nil and i_u < i_p
end)())
check("3 范围引用原文精确（无选区文本）", (function()
  local i_p = idx_of("[200~@/repo/lua/x.lua:3-5")
  if not i_p then return false end
  return sent[i_p] == "\27[200~@/repo/lua/x.lua:3-5 \27[201~"
end)())

-- 判据 4：二次草稿（就绪态同步投递）不产生新 CR
local cr_before = count_exact("\13")
A.draft("@/another.txt ")
check("4 二次草稿送达", vim.wait(5000, function()
  return idx_of("[200~@/another.txt") ~= nil
end))
check("4 草稿无 CR", count_exact("\13") == cr_before)

-- 收尾
local ids = {}
for _, sess in ipairs(A.list()) do ids[#ids + 1] = sess.id end
for _, sid in ipairs(ids) do A.delete(sid, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.api.nvim_chan_send = orig_send
vim.fn.delete(fake)
lib.finish()
