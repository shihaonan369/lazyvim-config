-- 带名新建回归 payload（scripts/test-agent-named.sh 驱动，headless --clean）。
-- 假 TUI（fake-claude：延迟渲染 banner+❯ 后 exec cat 存活）以 buf_attach 事件
-- 触发就绪队列，判据 = nvim_chan_send 注入原文与次序（agent_sessions 的
-- when_ready/ready_drain/name_named；skills/agent-sessions/SKILL.md）：
-- 1) claude_open 第 4 参带名 → 就绪后自动 "/rename <name>"
-- 1b) 文字与 CR 分包：rename 文字之后是独立的 "\13"，不是同包 "\r"
-- 2) when_ready 就绪态同步执行
-- 3) 真实 asend.lua 的 aprompt_file → 就绪后括号粘贴投喂（多行安全）
-- 4) M.new(name) 暖路径带名（<leader>aN 同源；冷启动链属插件域不测）
-- 5) 队列串行：rename 的 CR 落地（占用 450ms）之后，投喂的括号粘贴才进场
--    ——否则投喂的 Ctrl-U 会清掉 rename 未提交的文字
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）
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

-- 假 TUI：sleep 模拟 3-10s 启动的微缩版；❯ 渲染即就绪判据命中
local fake = "/tmp/fake-claude-" .. vim.fn.getpid()
vim.fn.writefile({
  "#!/bin/sh",
  "sleep 0.4",
  "printf 'Claude Code (fake) v1\\n\\n❯ \\n'",
  "exec cat",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")

local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

-- 判据 1/1b：claude_open 第 4 参带名（skill 的 aspawn 同路）
A.claude_open(fake .. " --fresh", {}, false, "IKMGVU-7")
check("1 会话已建", A.count() == 1)
local id1 = A.current_id()
check("1 就绪后自动 /rename", vim.wait(5000, function()
  return idx_of("/rename IKMGVU-7") ~= nil
end))
check("1b rename 文字无同包 CR", (function()
  local i = idx_of("/rename IKMGVU-7")
  return i ~= nil and sent[i]:sub(-1) ~= "\r"
end)())
check("1b CR 独立分包在后", vim.wait(2000, function()
  local i_txt, i_cr = idx_of("/rename IKMGVU-7"), idx_exact("\13")
  return i_txt ~= nil and i_cr ~= nil and i_cr > i_txt
end))

-- 判据 2：就绪态 when_ready 同步执行（无排队）
local hit_now = false
A.when_ready(id1, function() hit_now = true end)
check("2 就绪态同步执行", hit_now)

-- 判据 3：真实 skill 文件的 aprompt_file 就绪后投喂
dofile(REPO .. "/skills/agent-sessions/scripts/asend.lua")
local pf = vim.fn.tempname()
vim.fn.writefile({ "hello", "world" }, pf)
check("3 aprompt 返回 ok", _G.aprompt_file(id1, pf) == "ok")
check("3 括号粘贴投喂", vim.wait(5000, function()
  return idx_of("hello\nworld") ~= nil
end))

-- 判据 4：M.new(name) 暖路径（<leader>aN 同源）
A.new("NIAME-9")
check("4 暖路径新建", A.count() == 2 and A.current_id() ~= id1)
check("4 暖路径带名", vim.wait(5000, function()
  return idx_of("/rename NIAME-9") ~= nil
end))

-- 判据 5：同队串行——rename CR 先落地，投喂的粘贴后进场
local pf2 = vim.fn.tempname()
vim.fn.writefile({ "order-prompt" }, pf2)
A.claude_open(fake .. " --fresh3", {}, false, "ORD-5") -- 未就绪即排队
local id3 = A.current_id()
check("5 aprompt 返回 ok", _G.aprompt_file(id3, pf2) == "ok")
check("5 投喂与改名均已送达", vim.wait(8000, function()
  return idx_of("[200~order-prompt") ~= nil and idx_of("/rename ORD-5") ~= nil
end))
check("5 串行次序 rename→CR→粘贴", (function()
  local i_txt = idx_of("/rename ORD-5")
  if not i_txt then return false end
  local i_cr = idx_exact("\13", i_txt + 1)
  local i_paste = idx_of("[200~order-prompt", i_txt + 1)
  return i_cr ~= nil and i_paste ~= nil and i_txt < i_cr and i_cr < i_paste
end)())

-- 收尾
local ids = {}
for _, sess in ipairs(A.list()) do ids[#ids + 1] = sess.id end
for _, sid in ipairs(ids) do A.delete(sid, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.api.nvim_chan_send = orig_send
vim.fn.delete(fake)
vim.fn.delete(pf)
vim.fn.delete(pf2)
lib.finish()
