-- :AI 自然语言→nvim 操作回归 payload（scripts/test-ai-cmd.sh 驱动，headless
-- --clean）。假 claude（AGENT_CLAUDE_BIN：dump argv+pwd；payload 文件吐
-- --output-format json 形状的 JSON；failflag 存在时对 -r 调用 exit 1 模拟
-- 链失效）驱动 vim.system 回调。判据 = 翻译/可编辑审查/执行/续链四段语义：
-- 1) cmd: 负载过审后执行；argv 装配（-p/--strict-mcp-config/--output-format
--    json，无 --model，首问无 -r）；cwd 走 stdpath("run")/ai-cmd
-- 1b) 续链：json.session_id 捕获，第二问 argv 带 -r <sid>
-- 2) lua: 负载过审后执行；3) markdown 围栏剥离
-- 4) 无 cmd:/lua: 前缀 → 不执行 + WARN（不假成功）
-- 5) 拒审 → 不执行、无 WARN
-- 6) setup 装配：:AI 命令 + :ai 带守卫缩写
-- 7) fresh（:AI!）→ 不带 -r
-- 8) 链失效自愈：-r 失败 → 重开新链（无 -r 重试）且执行、WARN 明示
package.path = REPO .. "/lua/?.lua;" .. package.path

local fake = "/tmp/fake-ai-claude-" .. vim.fn.getpid()
local payload = "/tmp/fake-ai-payload-" .. vim.fn.getpid()
local argvf = "/tmp/fake-ai-argv-" .. vim.fn.getpid()
local pwdf = "/tmp/fake-ai-pwd-" .. vim.fn.getpid()
local failflag = "/tmp/fake-ai-failflag-" .. vim.fn.getpid()
vim.fn.writefile({
  "#!/bin/sh",
  'printf "%s\\n" "$@" > "' .. argvf .. '"',
  'pwd > "' .. pwdf .. '"',
  'case " $* " in *" -r "*)',
  '  if [ -f "' .. failflag .. '" ]; then echo "resume failed" >&2; exit 1; fi;;',
  "esac",
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
local function set_result(text) -- payload = --output-format json 形状
  vim.fn.writefile({ string.format('{"session_id":"sid-fake-1","result":%s}',
    vim.json.encode(text)) }, payload)
end
local function yes(_, body, on_ok) on_ok(body) end -- 审查直通（原样采纳）
local function last_argv() return vim.fn.readfile(argvf) end

-- 清桩起跑（双向：既不受上轮残留影响，也不在本轮后污染用户真链）
A.reset()
vim.wait(300, function() return false end)

-- 判据 1：cmd: 负载 + argv/cwd 装配（--strict-mcp-config 实测砍 MCP 装载
-- ~6s；--model 默认不传——本机 GLM 包装后端传任何模型都走 unrecognized
-- 回落，更慢且丢 cmd: 前缀）
vim.g.ai_test_cmd = 0
set_result("cmd:let g:ai_test_cmd = 42")
A.run("做个测试", { review = yes })
check("1 cmd: 过审后执行", vim.wait(5000, function() return vim.g.ai_test_cmd == 42 end))
local args = last_argv()
check("1 argv 装配（-p/json/strict，无 --model/-r）", has_arg(args, "-p")
  and has_arg(args, "--strict-mcp-config") and has_arg(args, "--output-format")
  and not has_arg(args, "--model") and not has_arg(args, "-r")
  and (function()
    for _, a in ipairs(args) do
      if a:find("用户请求: 做个测试", 1, true) then return true end
    end
    return false
  end)())
local want_cwd = vim.fn.resolve(vim.fn.stdpath("run") .. "/ai-cmd") -- :edit/pwd 都解析符号链接
local got_cwd = vim.fn.resolve(table.concat(vim.fn.readfile(pwdf), ""))
check("1 cwd 隔离（run/ai-cmd，不落当前项目）", got_cwd == want_cwd)

-- 判据 1b：续链——session_id 捕获进第二问
vim.g.ai_test_chain = 0
set_result("cmd:let g:ai_test_chain = 1")
A.run("第二问", { review = yes })
check("1b 链上第二问执行", vim.wait(5000, function() return vim.g.ai_test_chain == 1 end))
check("1b 第二问 argv 带 -r <sid>", has_arg(last_argv(), "-r")
  and has_arg(last_argv(), "sid-fake-1"))

-- 判据 2：lua: 负载
vim.g.ai_test_lua = 0
set_result("lua:vim.g.ai_test_lua = 7")
A.run("lua 测试", { review = yes })
check("2 lua: 过审后执行", vim.wait(5000, function() return vim.g.ai_test_lua == 7 end))

-- 判据 3：markdown 围栏包裹
vim.g.ai_test_fence = 0
set_result("```lua\nlua:vim.g.ai_test_fence = 9\n```")
A.run("围栏测试", { review = yes })
check("3 围栏剥离后解析执行", vim.wait(5000, function() return vim.g.ai_test_fence == 9 end))

-- 判据 4：无前缀负载 → 不执行 + WARN（不假成功）
local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, _) notes[#notes + 1] = tostring(msg) end
vim.g.ai_bad = 0
set_result("let g:ai_bad = 1")
A.run("胡言乱语", { review = yes })
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
set_result("cmd:let g:ai_refuse = 5")
A.run("拒审测试", { review = function() end }) -- 不回 on_ok = 弃审
vim.wait(3000, function() return false end) -- 给足送达+执行窗口
check("5 拒审不执行", vim.g.ai_refuse == 0)
check("5 拒审无 WARN", #notes == 0)

-- 判据 6：setup 装配——:AI 命令注册 + 五变体文本缩写 + 无 CR 劫持残留
-- （图标内联行已弃：cmdline CR 原生提交不可拦截，expr/回调双实证 E492 案，
-- 回归守卫防复辟）
A.setup()
check("6 :AI 命令已注册", vim.api.nvim_get_commands({})["AI"] ~= nil)
-- maparg('c') 只查 cmdline 映射表不含缩写；:cabbrev 列表 + 每变体指纹
do
  local abbr = vim.fn.execute("cabbrev")
  local all = true
  for _, tok in ipairs({ "a", "A", "ai", "Ai", "aI" }) do
    if not abbr:find("==# '" .. tok .. "' ? 'AI'", 1, true) then all = false end
  end
  check("6 五变体缩写已注册（归一 :AI 文本）", all)
end
check("6 无 c-<CR> 劫持残留", vim.tbl_isempty(vim.fn.maparg("<CR>", "c", false, true)))

-- 判据 7：fresh（:AI!）→ 不带 -r
vim.g.ai_test_fresh = 0
set_result("cmd:let g:ai_test_fresh = 3")
A.run("重置问", { review = yes, fresh = true })
check("7 fresh 执行", vim.wait(5000, function() return vim.g.ai_test_fresh == 3 end))
check("7 fresh argv 无 -r", not has_arg(last_argv(), "-r"))

-- 判据 8：链失效自愈——failflag 使 -r 调用失败 → 重开（无 -r 重试）且执行
notes = {}
vim.fn.writefile({ "" }, failflag)
vim.g.ai_heal = 0
set_result("cmd:let g:ai_heal = 42")
A.run("自愈测试", { review = yes })
check("8 链失效自愈后执行", vim.wait(8000, function() return vim.g.ai_heal == 42 end))
check("8 重试 argv 无 -r", not has_arg(last_argv(), "-r"))
check("8 重开 WARN 明示", (function()
  for _, n in ipairs(notes) do
    if n:find("重开新链", 1, true) then return true end
  end
  return false
end)())
vim.notify = orig_notify
vim.fn.delete(failflag) -- 就地清，后续判据不带链失效噪音

-- 判据 9：裸调零参——只提示缺少内容，不弹输入框、不触发 claude（用户
-- 裁决 2026-10-21：图标输入框一并弃用）
local notes9 = {}
local orig_notify9 = vim.notify
vim.notify = function(msg, _) notes9[#notes9 + 1] = tostring(msg) end
local argv_before = table.concat(vim.fn.readfile(argvf), "\n")
vim.api.nvim_cmd({ cmd = "AI" }, {})
vim.wait(600, function() return false end)
check("9 裸调 → 提示缺少内容", (function()
  for _, n in ipairs(notes9) do
    if n:find("缺少内容", 1, true) then return true end
  end
  return false
end)())
check("9 裸调不触发 claude（argv 未变）", table.concat(vim.fn.readfile(argvf), "\n") == argv_before)
vim.notify = orig_notify9

-- 判据 10：可编辑审查（用户裁决 2026-10-21：要可编辑，不要确认弹窗）——
-- snacks 真形状桩（callable table）：负载预填 default、prompt 带 kind；
-- 回车执行**改后**内容
do
  local cap
  package.preload["snacks"] = function()
    return { input = setmetatable({}, { __call = function(_, opts, on_confirm)
      cap = opts
      -- 模拟用户改写后回车：交改后 body（kind 在 prompt，不在输入框内容里）
      if on_confirm then on_confirm("let g:ai_edit = 8") end
    end }) }
  end
  vim.g.ai_edit = 0
  set_result("cmd:let g:ai_edit = 0")
  A.run("改写测试", {}) -- 无 review 覆盖 → 走缺省可编辑审查进 snacks 桩
  check("10 预填负载（body）+ kind 提示", vim.wait(5000, function() return cap ~= nil end)
    and cap.default == "let g:ai_edit = 0"
    and cap.prompt:find("cmd", 1, true) ~= nil)
  check("10 回车执行改后内容", vim.wait(5000, function() return vim.g.ai_edit == 8 end))
  package.loaded["snacks"] = nil
  package.preload["snacks"] = nil
end

-- 收尾（链桩不留假 sid 在用户 run 目录）
vim.fn.delete(fake)
vim.fn.delete(payload)
vim.fn.delete(argvf)
vim.fn.delete(pwdf)
A.reset()
lib.finish()
