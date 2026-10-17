-- 带名新建回归 payload（scripts/test-agent-named.sh 驱动，headless --clean）。
-- 假 TUI（fake-claude：延迟渲染 banner+❯ 后 exec cat 存活）以 buf_attach 事件
-- 触发就绪队列，判据 = nvim_chan_send 注入原文（agent_sessions 的
-- when_ready/name_named；skills/agent-sessions/SKILL.md）：
-- 1) claude_open 第 4 参带名 → 就绪后自动 "/rename <name>"
-- 2) when_ready 就绪态同步执行
-- 3) 真实 asend.lua 的 aprompt_file → 就绪后括号粘贴投喂（多行安全）
-- 4) M.new(name) 暖路径带名（<leader>aN 同源；冷启动链属插件域不测）
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）
local A = require("agent_sessions")
A.setup()

-- chan_send 间谍：捕获注入原文（顺序即队列序）
local sent = {}
local orig_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, s)
  sent[#sent + 1] = s
  return orig_send(ch, s)
end
local function sent_has(pat)
  for _, s in ipairs(sent) do
    if s:find(pat, 1, true) then return true end
  end
  return false
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

local fails = {}
local function check(name, cond)
  if cond then print("ok   " .. name) else print("FAIL " .. name) end
  if not cond then fails[#fails + 1] = name end
end

-- 判据 1：claude_open 第 4 参带名（skill 的 aspawn 同路）
A.claude_open(fake .. " --fresh", {}, false, "IKMGVU-7")
check("1 会话已建", A.count() == 1)
local id1 = A.current_id()
check("1 就绪后自动 /rename", vim.wait(5000, function()
  return sent_has("/rename IKMGVU-7")
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
  return sent_has("hello\nworld")
end))

-- 判据 4：M.new(name) 暖路径（<leader>aN 同源）
A.new("NIAME-9")
check("4 暖路径新建", A.count() == 2 and A.current_id() ~= id1)
check("4 暖路径带名", vim.wait(5000, function()
  return sent_has("/rename NIAME-9")
end))

-- 收尾
for _, sid in ipairs({ A.current_id(), id1 }) do
  A.delete(sid, true)
end
vim.wait(2000, function() return A.count() == 0 end)
vim.api.nvim_chan_send = orig_send
vim.fn.delete(fake)
vim.fn.delete(pf)
print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
