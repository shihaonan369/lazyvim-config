-- codex 续接/模型键回归 payload（scripts/test-agent-codex.sh 驱动，headless
-- --clean）。测接线层：dofile 真实 spec 并直调 config（--clean 不走 lazy，
-- spec 只是 setup+keymap 载体无 lazy 依赖）。判据：
-- 0) codex 态三键在位、claude 专属面不越界（ad/aC-of-claude/:ClaudeCode）
-- 1) <leader>aC 直调 → spawn argv = resume --last（fake bin 落盘 $@ 佐证）
-- 2) <leader>aR 直调 → argv = resume（无 --last）
-- 3) <leader>aM 直调 → 活会话注入 "\21/model" + 300ms 延时独立 "\13"
--    （M.command 同款分包，与 claude aM 同一通道）
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "codex" -- 对齐 codex 态（options.lua 的 AI_ASSISTANT 门）

-- fake codex：argv 落盘佐证 + › 渲染（就绪判据）+ cat 存活。AGENT_CODEX_BIN
-- 须先设再 require（模块加载时求值，同 AGENT_CLAUDE_BIN 惯例）
local fake = "/tmp/fake-codex-" .. vim.fn.getpid()
local argsf = fake .. "-args"
vim.fn.writefile({
  "#!/bin/sh",
  "printf '%s\\n' \"$@\" > " .. argsf,
  "sleep 0.4",
  "printf 'Codex (fake)\\n\\n› \\n'",
  "exec cat",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.AGENT_CODEX_BIN = fake

local lib = dofile(REPO .. "/scripts/testlib.lua")
local check = lib.check

local spec = dofile(REPO .. "/lua/plugins/agent.lua")
spec.config()
local A = require("agent_sessions")

-- 判据 0：codex 三键在位；claude 专属键/命令不越界注册
check("0 aC 在位", type(vim.fn.maparg("<leader>aC", "n", false, true).callback) == "function")
check("0 aR 在位", type(vim.fn.maparg("<leader>aR", "n", false, true).callback) == "function")
check("0 aM 在位", type(vim.fn.maparg("<leader>aM", "n", false, true).callback) == "function")
check("0 claude diff 键不越界", vim.fn.maparg("<leader>ad", "n") == "")
check("0 :ClaudeCode 不越界", vim.fn.exists(":ClaudeCode") == 0)

-- argv 佐证：count 判据在 spawn 注册即真，fake 进程异步起跑——须等到 argv
-- 落盘且与期望一致（readfile 一律 pcall，缺文件不是错误是未到时）
local function argv_wait(expect)
  return vim.wait(3000, function()
    local ok, lines = pcall(vim.fn.readfile, argsf)
    return ok and type(lines) == "table" and table.concat(lines, " ") == expect
  end)
end

-- Skill 从 Codex session 创建同类型 session，并保持编辑焦点。
dofile(REPO .. "/skills/agent-sessions/scripts/asend.lua")
vim.cmd("wincmd h")
local before_win = vim.api.nvim_get_current_win()
local sid = _G.aspawn("skill-codex")
check("skill Codex 建会话", A.count() == 1 and A.buf_of(sid) ~= nil)
check("skill 后台创建不抢焦点", vim.api.nvim_get_current_win() == before_win)
check("skill Codex 本地名", A.list()[1].name == "skill-codex")
check("skill Codex › 就绪", vim.wait(3000, function() return _G.aready(sid) == "ready" end))
local pf = vim.fn.tempname()
vim.fn.writefile({ "skill first prompt", "second line" }, pf)
local skill_sent = {}
local original_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, value)
  skill_sent[#skill_sent + 1] = value
  return original_send(ch, value)
end
_G.aprompt_file(sid, pf)
check("skill 首发 prompt 与 CR", vim.wait(2000, function()
  return vim.tbl_contains(skill_sent, "\27[200~skill first prompt\nsecond line\27[201~")
    and vim.tbl_contains(skill_sent, "\13")
end))
vim.api.nvim_chan_send = original_send
vim.fn.delete(pf)
A.delete(sid, true)
check("skill 样本退出", vim.wait(2000, function() return A.count() == 0 end))

-- 判据 1：aC = resume --last（空池冷启动直调真键位）
vim.fn.delete(argsf)
check("1 aC 直调", lib.press("<leader>aC"))
check("1 aC 建 session", vim.wait(3000, function() return A.count() == 1 end))
check("1 aC argv=resume --last", argv_wait("resume --last"))

-- 判据 2：aR = resume（无 --last）
vim.fn.delete(argsf)
check("2 aR 直调", lib.press("<leader>aR"))
check("2 aR 建 session", vim.wait(3000, function() return A.count() == 2 end))
check("2 aR argv=resume（无 --last）", argv_wait("resume"))

-- 判据 3：aM 注入 /model（文字与 CR 分包，延时 CR 在后）
local sent = {}
local orig_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, s)
  sent[#sent + 1] = s
  return orig_send(ch, s)
end
check("3 aM 直调", lib.press("<leader>aM"))
local function idx(pat, from)
  for i = from or 1, #sent do
    if sent[i]:find(pat, 1, true) then return i end
  end
end
check("3 aM 注入 \\21/model", vim.wait(2000, function() return idx("/model") ~= nil end))
check("3 aM 文字无同包 CR", (function()
  local i = idx("/model")
  return i ~= nil and sent[i]:sub(-1) ~= "\r"
end)())
check("3 aM CR 独立分包在后", vim.wait(2000, function()
  local i_txt, i_cr = idx("/model")
  for j = (i_txt or -1) + 1, #sent do
    if sent[j] == "\13" then i_cr = j break end
  end
  return i_txt ~= nil and i_cr ~= nil
end))

-- 判据 4：M.delete 优雅退出 = 单包 "\21/quit\r"（claude /exit 同款形状），
-- 不强杀——fake 是 exec cat 收到文字不会退，count 不降即证无 jobstop
A.delete(A.current_id())
check("4 delete 注入 \\21/quit\\r", vim.wait(2000, function()
  for i = 1, #sent do
    if sent[i] == "\21/quit\r" then return true end
  end
end))
check("4 delete 不强杀", A.count() == 2)
vim.api.nvim_chan_send = orig_send

-- 收尾
local ids = {}
for _, sess in ipairs(A.list()) do ids[#ids + 1] = sess.id end
for _, sid in ipairs(ids) do A.delete(sid, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.fn.delete(fake)
vim.fn.delete(argsf)
lib.finish()
