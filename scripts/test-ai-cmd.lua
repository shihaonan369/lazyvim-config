-- :AI 自然语言→nvim 操作回归 payload（scripts/test-ai-cmd.sh 驱动，headless
-- --clean）。假 claude（AGENT_CLAUDE_BIN：dump argv+pwd、cat 负载文件）驱动
-- vim.system 回调，判据 = 翻译/审查/执行三段语义（先审后执，用户裁决
-- 2026-10-21；docs 见 lua/ai_cmd.lua 头注）：
-- 1) cmd: 负载过审后执行；argv 装配含 -p/--model/用户请求；cwd 走
--    stdpath("run")/ai-cmd（transcript 不进当前项目）
-- 2) lua: 负载过审后执行
-- 3) markdown 围栏包裹仍可解析（剥 ``` 行）
-- 4) 无 cmd:/lua: 前缀 → 不执行 + WARN notify（不假成功）
-- 5) 拒审 → 不执行、无 WARN
package.path = REPO .. "/lua/?.lua;" .. package.path

local fake = "/tmp/fake-ai-claude-" .. vim.fn.getpid()
local payload = "/tmp/fake-ai-payload-" .. vim.fn.getpid()
local argvf = "/tmp/fake-ai-argv-" .. vim.fn.getpid()
local pwdf = "/tmp/fake-ai-pwd-" .. vim.fn.getpid()
vim.fn.writefile({
  "#!/bin/sh",
  'printf "%s\\n" "$@" > "' .. argvf .. '"',
  'pwd > "' .. pwdf .. '"',
  'cat "' .. payload .. '"',
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.AGENT_CLAUDE_BIN = fake

local A = require("ai_cmd")
local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

local function has_arg(list, want) -- vim.indexof 在本机 nvim 缺席，纯循环
  for _, v in ipairs(list) do
    if v == want then return true end
  end
  return false
end

local function set_payload(text)
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), payload)
end
local function yes() return true end

-- 判据 1：cmd: 负载 + argv/cwd 装配（--strict-mcp-config 必在——实测砍
-- MCP 装载 ~6s；--model 默认**不传**——本机 GLM 包装后端传任何模型都走
-- unrecognized 回落，更慢且丢 cmd: 前缀；设 vim.g.ai_cmd_model 才追加）
vim.g.ai_test_cmd = 0
set_payload("cmd:let g:ai_test_cmd = 42")
A.run("做个测试", { confirm = yes })
check("1 cmd: 过审后执行", vim.wait(5000, function() return vim.g.ai_test_cmd == 42 end))
local args = vim.fn.readfile(argvf)
check("1 argv 装配（-p/--strict-mcp-config/请求，无 --model）", has_arg(args, "-p")
  and has_arg(args, "--strict-mcp-config")
  and not has_arg(args, "--model")
  and (function()
    for _, a in ipairs(args) do
      if a:find("用户请求: 做个测试", 1, true) then return true end
    end
    return false
  end)())
local want_cwd = vim.fn.resolve(vim.fn.stdpath("run") .. "/ai-cmd") -- :edit/pwd 都解析符号链接
local got_cwd = vim.fn.resolve(table.concat(vim.fn.readfile(pwdf), ""))
check("1 cwd 隔离（run/ai-cmd，不落当前项目）", got_cwd == want_cwd)

-- 判据 2：lua: 负载
vim.g.ai_test_lua = 0
set_payload("lua:vim.g.ai_test_lua = 7")
A.run("lua 测试", { confirm = yes })
check("2 lua: 过审后执行", vim.wait(5000, function() return vim.g.ai_test_lua == 7 end))

-- 判据 3：markdown 围栏包裹
vim.g.ai_test_fence = 0
set_payload("```lua\nlua:vim.g.ai_test_fence = 9\n```")
A.run("围栏测试", { confirm = yes })
check("3 围栏剥离后解析执行", vim.wait(5000, function() return vim.g.ai_test_fence == 9 end))

-- 判据 4：无前缀负载 → 不执行 + WARN（不假成功）
local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, _) notes[#notes + 1] = tostring(msg) end
vim.g.ai_bad = 0
set_payload("let g:ai_bad = 1")
A.run("胡言乱语", { confirm = yes })
check("4 无前缀 → WARN 恰一条", vim.wait(5000, function()
  local c = 0
  for _, n in ipairs(notes) do
    if n:find("无法解析", 1, true) then c = c + 1 end
  end
  return c == 1
end))
check("4 无前缀负载不执行", vim.g.ai_bad == 0)

-- 判据 5：拒审 → 不执行、无 WARN（清账：判据 4 的合法 WARN 不算新债）
notes = {}
vim.g.ai_refuse = 0
set_payload("cmd:let g:ai_refuse = 5")
A.run("拒审测试", { confirm = function() return false end })
vim.wait(3000, function() return false end) -- 给足送达+执行窗口
check("5 拒审不执行", vim.g.ai_refuse == 0)
check("5 拒审无 WARN", (function()
  for _, n in ipairs(notes) do
    if n:find("无法解析", 1, true) then return false end
  end
  return true
end)())
vim.notify = orig_notify

-- 判据 6：setup 装配——:AI 命令注册 + :ai 带守卫缩写在位
A.setup()
check("6 :AI 命令已注册", vim.api.nvim_get_commands({})["AI"] ~= nil)
-- maparg('c') 只查 cmdline 映射表不含缩写；:cabbrev 列表 + 守卫指纹为准
check("6 :ai 缩写已注册", vim.fn.execute("cabbrev"):find("? 'AI' : 'ai'", 1, true) ~= nil)

-- 收尾
vim.fn.delete(fake)
vim.fn.delete(payload)
vim.fn.delete(argvf)
vim.fn.delete(pwdf)
lib.finish()
