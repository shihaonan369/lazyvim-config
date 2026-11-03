-- pi 后端接线回归 payload（scripts/test-agent-pi.sh 驱动，headless --clean）。
-- 测接线层：dofile 真实 spec 并直调 config。fake pi：argv 落盘 + ─ 规则线
-- 渲染（就绪判据）+ OSC 7501 报文序列（idle→working(msg)→done(msg)→error）
-- + exec cat 存活。判据：
-- 0) pi 态键位在位（aC/aR/aM + inline diff 全家）、claude 专属命令不越界
-- 1) skill aspawn 带名：-n 落 argv（免 /rename 注入）、─ 就绪、7501 状态
--    error→attention 归一、7501 msg(base64) → 名字回流覆写
-- 2) aprompt_file 括号粘贴 + 延时 CR（后端中立通道）
-- 3) aC/aR spawn argv（--continue/--resume + --tui-mode fullscreen 恒附）
-- 4) aM 注入 "\21/model" + 300ms 延时独立 "\13"（分包铁律）
-- 5) M.rename：/name 注入 + 本地立即落名（7501 回流纠偏为后手）
-- 6) delete 优雅退出 = 单包 "\21\4"（Ctrl+D，无 CR 无斜杠命令）、不强杀
package.path = REPO .. "/lua/?.lua;" .. package.path
vim.g.ai_assistant = "pi" -- 对齐 pi 态（options.lua 的 AI_ASSISTANT 门）

-- fake pi：AGENT_PI_BIN 须先设再 require（模块加载时求值，AGENT_*_BIN 惯例）
local fake = "/tmp/fake-pi-" .. vim.fn.getpid()
local argsf = fake .. "-args"
local b64 = vim.base64.encode("renamed-by-7501")
vim.fn.writefile({
  "#!/bin/sh",
  -- stderr 必须隔离出 pty：stty 的报错若落回 pty，raw 模式可能没设成，
  -- \\3 会按规范模式变成 SIGINT 杀死 fake（2026-11-03 排障实证）
  "exec 2>/dev/null",
  "stty raw -echo",
  "trap '' INT",
  "printf '%s\\n' \"$@\" > " .. argsf,
  "sleep 0.4",
  "printf '\\033]7501;state=idle:app=pi\\033\\\\'",
  "sleep 0.15",
  "printf '\\033]7501;state=working:app=pi:msg=" .. b64 .. "\\033\\\\'",
  "sleep 0.15",
  "printf '\\033]7501;state=done:app=pi:msg=" .. b64 .. "\\033\\\\'",
  "sleep 0.15",
  "printf '\\033]7501;state=error:app=pi\\033\\\\'",
  "sleep 0.15",
  "printf 'Pi (fake) v1.5.0\\n\\n────────────────────\\n'",
  -- 退出判据要发 \\3/\\4 控制字节：真 TUI 都自设 raw 模式（pi 同款），fake
  -- 忠实模拟——否则 pty 规范模式把 \\3 解释成 SIGINT、\\4 是 VEOF，fake 必死
  "stty raw -echo",
  "trap '' INT",
  "exec sleep 300",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.AGENT_PI_BIN = fake

local lib = dofile(REPO .. "/scripts/testlib.lua")
local check = lib.check

local spec = dofile(REPO .. "/lua/plugins/agent.lua")
spec.config()
local A = require("agent_sessions")

-- 判据 0：pi 键位在位（diff 全家随 pi 接线）；claude 专属命令不越界
check("0 aC 在位", type(vim.fn.maparg("<leader>aC", "n", false, true).callback) == "function")
check("0 aR 在位", type(vim.fn.maparg("<leader>aR", "n", false, true).callback) == "function")
check("0 aM 在位", type(vim.fn.maparg("<leader>aM", "n", false, true).callback) == "function")
check("0 ad/ada/add 在位（inline diff 复用）", vim.fn.maparg("<leader>ad", "n") ~= ""
  and vim.fn.maparg("<leader>ada", "n") ~= "" and vim.fn.maparg("<leader>add", "n") ~= "")
check("0 :ClaudeCode 不越界", vim.fn.exists(":ClaudeCode") == 0)

-- 随仓桥接扩展路径（-e 注入，argv 判据共用）
local BRIDGE = REPO .. "/scripts/agent-pi-bridge.ts"

local function argv_wait(expect)
  return vim.wait(3000, function()
    local ok, lines = pcall(vim.fn.readfile, argsf)
    return ok and type(lines) == "table" and table.concat(lines, " ") == expect
  end)
end

-- 判据 1：skill aspawn 带名 → -n 落 argv（pi 本尊持久化，免 /rename 注入）
dofile(REPO .. "/skills/agent-sessions/scripts/asend.lua")
vim.cmd("wincmd h")
local before_win = vim.api.nvim_get_current_win()
local sid = _G.aspawn("skill-pi")
check("skill pi 建会话", A.count() == 1 and A.buf_of(sid) ~= nil)
check("skill 后台创建不抢焦点", vim.api.nvim_get_current_win() == before_win)
check("skill pi 带名走 -n（免注入）", argv_wait("-n skill-pi -e " .. BRIDGE .. " --tui-mode fullscreen"))
check("skill pi ─ 规则线就绪", vim.wait(3000, function() return _G.aready(sid) == "ready" end))
check("skill pi 7501 msg(base64) 名字回流覆写", vim.wait(3000, function()
  return A.list()[1].name == "renamed-by-7501"
end))
check("skill pi 7501 error→attention 归一", vim.wait(3000, function()
  return A.list()[1].state == "attention"
end))

-- 判据 1b：邮箱名字直报路由（agent-nvim-sync 扩展的 nvim 侧）——idle 态在
-- TUI 里 /name 不触发 7501 新报文（msg 只随 working/done 走），即时回流走
-- AGENT_STATUS_FILE 邮箱单行 {"tag","name"}
do
  local fh = io.open(A.event_file(), "a")
  if fh then
    fh:write(string.format('{"tag":"%s.%s","name":"%s"}\n', vim.fn.getpid(), sid, "mailed-name"))
    fh:close()
  end
  check("1b 邮箱名字直报回流", vim.wait(2000, function()
    return A.list()[1].name == "mailed-name"
  end))
end

-- 判据 2：首发 prompt 括号粘贴 + CR（后端中立）
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

-- 判据 3：aC/aR spawn argv（--tui-mode fullscreen 恒附其后）
vim.fn.delete(argsf)
check("3 aC 直调", lib.press("<leader>aC"))
check("3 aC 建 session", vim.wait(3000, function() return A.count() == 2 end))
check("3 aC argv=--continue -e bridge --tui-mode fullscreen", argv_wait("--continue -e " .. BRIDGE .. " --tui-mode fullscreen"))
vim.fn.delete(argsf)
check("3 aR 直调", lib.press("<leader>aR"))
check("3 aR 建 session", vim.wait(3000, function() return A.count() == 3 end))
check("3 aR argv=--resume -e bridge --tui-mode fullscreen", argv_wait("--resume -e " .. BRIDGE .. " --tui-mode fullscreen"))

-- 判据 4：aM 注入 /model（文字与 CR 分包，延时 CR 在后）
local sent = {}
local orig_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, s)
  sent[#sent + 1] = s
  return orig_send(ch, s)
end
check("4 aM 直调", lib.press("<leader>aM"))
local function idx(pat, from)
  for i = from or 1, #sent do
    if sent[i]:find(pat, 1, true) then return i end
  end
end
check("4 aM 注入 \\21/model", vim.wait(2000, function() return idx("/model") ~= nil end))
check("4 aM 文字无同包 CR", (function()
  local i = idx("/model")
  return i ~= nil and sent[i]:sub(-1) ~= "\r"
end)())

-- 判据 5：树内改名 = /name 注入 + 本地立即落名（7501 回流纠偏为后手）
A.rename(A.current_id(), "tree-rename")
check("5 rename 本地立即落名", vim.tbl_contains(
  vim.tbl_map(function(s) return s.name end, A.list()), "tree-rename"))
check("5 rename 注入 /name", (function()
  for _, s in ipairs(sent) do
    if s:find("/name tree-rename", 1, true) then return true end
  end
  return false
end)())

-- 判据 6：delete 优雅退出 = "\3" 清草稿 + 延时独立 "\4"（两段分包，同包
-- \21\4 实测吞掉退出），不强杀（fake 是 exec cat，收到 \4 不会退，count
-- 不降即证无 jobstop）
A.delete(A.current_id())
check("6 delete 注入 \\3 清草稿", vim.wait(2000, function()
  return vim.tbl_contains(sent, "\3")
end))
check("6 delete 延时独立 \\4", vim.wait(2000, function()
  local i3, i4
  for i, s in ipairs(sent) do
    if s == "\3" and not i3 then i3 = i end
    if s == "\4" then i4 = i end
  end
  return i3 ~= nil and i4 ~= nil and i4 > i3
end))
check("6 delete 不强杀", A.count() == 3)
vim.api.nvim_chan_send = orig_send

-- 收尾
local ids = {}
for _, sess in ipairs(A.list()) do ids[#ids + 1] = sess.id end
for _, s in ipairs(ids) do A.delete(s, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.fn.delete(fake)
vim.fn.delete(argsf)
lib.finish()
