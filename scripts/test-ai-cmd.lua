-- :AI 自然语言→nvim 操作回归 payload（scripts/test-ai-cmd.sh 驱动，headless
-- --clean）。假 claude（AGENT_CLAUDE_BIN：dump argv+pwd；payload 文件吐
-- --output-format json 形状的 JSON；failflag 存在时对 -r 调用 exit 1 模拟
-- 链失效）驱动 vim.system 回调。判据 = 翻译/可编辑审查/执行/续链四段语义：
-- 1) cmd: 负载过审后执行；argv 装配（-p/--strict-mcp-config/--output-format
--    json/--add-dir 项目根，无 --model，首问无 -r）；cwd 走 stdpath("run")/ai-cmd
-- 1b) 续链：json.session_id 捕获，第二问 argv 带 -r <sid>
-- 2) lua: 负载过审后执行；3) markdown 围栏剥离
-- 4) 无 cmd:/lua: 前缀 → 不执行 + 终态播报（不假成功；播报缝 = A.report）
-- 5) 拒审 → 不执行、无播报
-- 6) setup 装配：:AI 命令 + :ai 带守卫缩写
-- 7) fresh（:AI!）→ 不带 -r
-- 8) 链失效自愈：-r 失败 → 重开新链（无 -r 重试）且执行、重开播报明示
-- 11) 翻译超时≠链失效：终态播报、链 sid 原样、不自动重试（2026-10-23 拆）
-- 12) 输入框复用守卫：零 vim.notify/零浮窗，成功路径零播报（2026-10-23）
package.path = REPO .. "/lua/?.lua;" .. package.path

local fake = "/tmp/fake-ai-claude-" .. vim.fn.getpid()
local payload = "/tmp/fake-ai-payload-" .. vim.fn.getpid()
local argvf = "/tmp/fake-ai-argv-" .. vim.fn.getpid()
local pwdf = "/tmp/fake-ai-pwd-" .. vim.fn.getpid()
local failflag = "/tmp/fake-ai-failflag-" .. vim.fn.getpid()
local slowflag = "/tmp/fake-ai-slowflag-" .. vim.fn.getpid()
vim.fn.writefile({
  "#!/bin/sh",
  'printf "%s\\n" "$@" > "' .. argvf .. '"',
  'pwd > "' .. pwdf .. '"',
  'if [ -f "' .. slowflag .. '" ]; then sleep 2; fi', -- 挂住过 timeout 触发超时分支
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
    if v == want then
      return true
    end
  end
  return false
end
local function set_result(text) -- payload = --output-format json 形状
  vim.fn.writefile({ string.format('{"session_id":"sid-fake-1","result":%s}', vim.json.encode(text)) }, payload)
end
local function yes(_, body, on_ok)
  on_ok(body)
end -- 审查直通（原样采纳）
local function last_argv()
  return vim.fn.readfile(argvf)
end

-- 护真链（2026-10-24 事故：本套件起跑/收尾的 A.reset 曾把用户真链 sid
-- 抹掉——新链=冷启动变慢+翻译风格漂移 terminal-|-echo 案。备份/恢复，
-- 同 scripts/pty-test-ai.sh 惯例）
local CHAIN = vim.fn.stdpath("cache") .. "/ai-cmd/chain-sid"
local chain_bak = vim.fn.filereadable(CHAIN) == 1 and vim.fn.readfile(CHAIN)[1] or nil

-- 清桩起跑（双向：既不受上轮残留影响，也不在本轮后污染用户真链）
A.reset()
vim.wait(300, function()
  return false
end)

-- 判据 1：cmd: 负载 + argv/cwd 装配（--strict-mcp-config 实测砍 MCP 装载
-- ~6s；--model 默认不传——本机 GLM 包装后端传任何模型都走 unrecognized
-- 回落，更慢且丢 cmd: 前缀）
vim.g.ai_test_cmd = 0
set_result("cmd:let g:ai_test_cmd = 42")
A.run("做个测试", { review = yes })
check(
  "1 cmd: 过审后执行",
  vim.wait(5000, function()
    return vim.g.ai_test_cmd == 42
  end)
)
local args = last_argv()
check(
  "1 argv 装配（-p/json/strict/add-dir=，无 --model/-r）",
  has_arg(args, "-p")
    and has_arg(args, "--strict-mcp-config")
    and has_arg(args, "--output-format")
    and has_arg(args, "--add-dir=" .. vim.fn.getcwd()) -- 等号连写：分写会被变长参数吞 prompt（真机实证）
    and not has_arg(args, "--model")
    and not has_arg(args, "-r")
    and (function()
      for _, a in ipairs(args) do
        if a:find("用户请求: 做个测试", 1, true) then
          return true
        end
      end
      return false
    end)()
)
local want_cwd = vim.fn.resolve(vim.fn.stdpath("run") .. "/ai-cmd") -- :edit/pwd 都解析符号链接
local got_cwd = vim.fn.resolve(table.concat(vim.fn.readfile(pwdf), ""))
check("1 cwd 隔离（run/ai-cmd，不落当前项目）", got_cwd == want_cwd)

-- 判据 1b：续链——session_id 捕获进第二问
vim.g.ai_test_chain = 0
set_result("cmd:let g:ai_test_chain = 1")
A.run("第二问", { review = yes })
check(
  "1b 链上第二问执行",
  vim.wait(5000, function()
    return vim.g.ai_test_chain == 1
  end)
)
check("1b 第二问 argv 带 -r <sid>", has_arg(last_argv(), "-r") and has_arg(last_argv(), "sid-fake-1"))

-- 判据 2：lua: 负载
vim.g.ai_test_lua = 0
set_result("lua:vim.g.ai_test_lua = 7")
A.run("lua 测试", { review = yes })
check(
  "2 lua: 过审后执行",
  vim.wait(5000, function()
    return vim.g.ai_test_lua == 7
  end)
)

-- 判据 3：markdown 围栏包裹
vim.g.ai_test_fence = 0
set_result("```lua\nlua:vim.g.ai_test_fence = 9\n```")
A.run("围栏测试", { review = yes })
check(
  "3 围栏剥离后解析执行",
  vim.wait(5000, function()
    return vim.g.ai_test_fence == 9
  end)
)

-- 判据 4：无前缀负载 → 不执行 + 终态播报（不假成功）；播报缝 = A.report
-- （notify 弹窗已弃，用户裁决 2026-10-23；异步收尾须轮询等）
local notes = {}
local orig_report = A.report
A.report = function(text, _)
  notes[#notes + 1] = tostring(text)
end
vim.g.ai_bad = 0
set_result("let g:ai_bad = 1")
A.run("胡言乱语", { review = yes })
check(
  "4 无前缀 → 终态播报恰一条",
  vim.wait(5000, function()
    local c = 0
    for _, n in ipairs(notes) do
      if n:find("Unparseable", 1, true) then
        c = c + 1
      end
    end
    return c == 1
  end)
)
check("4 无前缀负载不执行", vim.g.ai_bad == 0)

-- 判据 5：拒审 → 不执行、无播报（清账：判据 4 的合法终态播报不算新债）
notes = {}
vim.g.ai_refuse = 0
set_result("cmd:let g:ai_refuse = 5")
A.run("拒审测试", { review = function() end }) -- 不回 on_ok = 弃审
vim.wait(2000, function()
  return false
end) -- 给足送达窗口
check("5 拒审不执行", vim.g.ai_refuse == 0)
check("5 拒审无播报", #notes == 0)

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
    if not abbr:find("==# '" .. tok .. "' ? 'AI'", 1, true) then
      all = false
    end
  end
  check("6 五变体缩写已注册（归一 :AI 文本）", all)
end
check("6 无 c-<CR> 劫持残留", vim.tbl_isempty(vim.fn.maparg("<CR>", "c", false, true)))

-- 判据 7：fresh（:AI!）→ 不带 -r
vim.g.ai_test_fresh = 0
set_result("cmd:let g:ai_test_fresh = 3")
A.run("重置问", { review = yes, fresh = true })
check(
  "7 fresh 执行",
  vim.wait(5000, function()
    return vim.g.ai_test_fresh == 3
  end)
)
check("7 fresh argv 无 -r", not has_arg(last_argv(), "-r"))

-- 判据 8：链失效自愈——failflag 使 -r 调用失败 → 重开（无 -r 重试）且执行
notes = {}
vim.fn.writefile({ "" }, failflag)
vim.g.ai_heal = 0
set_result("cmd:let g:ai_heal = 42")
A.run("自愈测试", { review = yes })
check(
  "8 链失效自愈后执行",
  vim.wait(8000, function()
    return vim.g.ai_heal == 42
  end)
)
check("8 重试 argv 无 -r", not has_arg(last_argv(), "-r"))
check(
  "8 重开播报明示",
  (function()
    for _, n in ipairs(notes) do
      if n:find("reopened a fresh chain", 1, true) then
        return true
      end
    end
    return false
  end)()
)
A.report = orig_report
vim.fn.delete(failflag) -- 就地清，后续判据不带链失效噪音

-- 判据 9：裸调零参——提示缺少内容（走 report 缝）、不触发 claude（用户
-- 裁决 2026-10-21：图标输入框一并弃用；2026-10-23 提示并入 report 缝）
local notes9 = {}
local orig_report9 = A.report
A.report = function(text, _)
  notes9[#notes9 + 1] = tostring(text)
end
local argv_before = table.concat(vim.fn.readfile(argvf), "\n")
vim.api.nvim_cmd({ cmd = "AI" }, {})
check(
  "9 裸调 → 提示缺少内容",
  (function()
    for _, n in ipairs(notes9) do
      if n:find("Missing query", 1, true) then
        return true
      end
    end
    return false
  end)()
)
check("9 裸调不触发 claude（argv 未变）", table.concat(vim.fn.readfile(argvf), "\n") == argv_before)
A.report = orig_report9

-- 判据 10：缺省审查 = 复用 ':' 本尊（用户裁决 2026-10-21 三修）——负载
-- 规整成单行 cmdline 文本：cmd 原样/行间并 " | "；lua 加前缀、行间并
-- "; "。feedkeys 预填属交互层，PTY 全链验（headless feedkeys 假阴）
check("10 cmd 单行原样", A.review_line("cmd", "tabnew | terminal mysql") == "tabnew | terminal mysql")
check("10 cmd 多行并 | ", A.review_line("cmd", "tabnew\nterminal mysql") == "tabnew | terminal mysql")
check(
  "10 lua 加前缀并 ; ",
  A.review_line("lua", "vim.cmd('tabnew')\nvim.cmd('terminal mysql')")
    == "lua vim.cmd('tabnew'); vim.cmd('terminal mysql')"
)

-- 判据 11：翻译超时≠链失效（2026-10-23 拆分——曾混进链失效分支：reset+
-- 自动重试撞同一堵墙再超时，用户见 WARN+ERROR 两跳）。slowflag 挂住假
-- claude、vim.g.ai_cmd_timeout 压到 300ms 秒级触发；判据 = 终态播报恰一
-- 条（沉降窗后仍恰一条；旧代码无「翻译超时」报文即挂）、无重开播报、
-- 链 sid 原样（不被 reset）
notes = {}
A.report = function(text, _)
  notes[#notes + 1] = tostring(text)
end
vim.fn.writefile({ "" }, slowflag)
vim.g.ai_cmd_timeout = 300
A.run("慢翻译", { review = yes })
check(
  "11 超时 → 终态播报恰一条",
  vim.wait(3000, function()
    local c = 0
    for _, n in ipairs(notes) do
      if n:find("Timeout", 1, true) then
        c = c + 1
      end
    end
    return c == 1
  end)
)
vim.wait(500, function()
  return false
end) -- 沉降窗：若有自动重试，第二报文必落此窗
local healed11, c11 = false, 0
for _, n in ipairs(notes) do
  if n:find("reopened a fresh chain", 1, true) then
    healed11 = true
  end
  if n:find("Timeout", 1, true) then
    c11 = c11 + 1
  end
end
check("11 超时不误诊重开（无重开播报、仍恰一条）", not healed11 and c11 == 1)
check(
  "11 超时不动链（sid 原样）",
  (function()
    local f = vim.fn.stdpath("cache") .. "/ai-cmd/chain-sid"
    return vim.fn.filereadable(f) == 1 and vim.fn.readfile(f)[1] == "sid-fake-1"
  end)()
)
vim.g.ai_cmd_timeout = nil
vim.fn.delete(slowflag)
A.report = orig_report

-- 判据 12：输入框复用改版守卫（用户裁决 2026-10-23：notify 弹窗、进度浮
-- 窗均已弃）——全程零 vim.notify、播报只走 M.report 缝；成功路径零播报
-- （输入框原地变身即审查）
local notes12n = {}
local orig_notify12 = vim.notify
vim.notify = function(msg, _)
  notes12n[#notes12n + 1] = tostring(msg)
end
local notes12r = {}
A.report = function(text, _)
  notes12r[#notes12r + 1] = tostring(text)
end
vim.g.ai_test_silent = 0
set_result("cmd:let g:ai_test_silent = 1")
A.run("静默守卫", { review = yes })
check(
  "12 异步全流程执行",
  vim.wait(5000, function()
    return vim.g.ai_test_silent == 1
  end)
)
check("12 全程零 notify（弹窗已弃）", #notes12n == 0)
check("12 成功路径零播报", #notes12r == 0)
vim.notify = orig_notify12

-- 判据 14：say: 闲聊直答（2026-10-24 十修）——不执行、不走审查、文本经
-- report 落框为终态；空 say: 落 Empty reply（视同翻译失败）
do
  local notes14, reviewed14 = {}, false
  local orig14 = A.report
  A.report = function(text, _)
    notes14[#notes14 + 1] = tostring(text)
  end
  set_result("say:你好呀，今天状态不错")
  A.run("你今天怎么样", {
    review = function()
      reviewed14 = true
    end,
  })
  check(
    "14 say 文本落框恰一次",
    vim.wait(5000, function()
      local c = 0
      for _, n in ipairs(notes14) do
        if n == "你好呀，今天状态不错" then
          c = c + 1
        end
      end
      return c == 1
    end)
  )
  check("14 say 不走审查", reviewed14 == false)
  notes14 = {}
  set_result("say:")
  A.run("空直答", { review = function() end })
  check(
    "14 空 say → Empty reply（视同失败）",
    vim.wait(5000, function()
      for _, n in ipairs(notes14) do
        if n:find("Empty reply", 1, true) then
          return true
        end
      end
      return false
    end)
  )
  A.report = orig14
end

A.report = orig_report

-- 判据 13：动效三段制（2026-10-24 九修）——冲击快攻慢衰+回弹、呼吸正弦、
-- 白混选层、bloom 阈值铁律。headless 无 UI 渲染，全部走 M._anim 数学缝
do
  local an = A._anim
  check("13 冲击 t0 从零起跳", an.impact(0) == 0 and an.impact(-1) == 0)
  local pk, pt = 0, 0
  for i = 0, 400 do
    local t, v = i / 1000, an.impact(i / 1000)
    if v > pk then
      pk, pt = v, t
    end
  end
  check("13 冲击峰值 1.0-1.1 @≤150ms（duang 且不过曝）", pk > 1.0 and pk < 1.1 and pt <= 0.15)
  check("13 冲击 500ms 回落 <0.3、1s 熄 <0.05", an.impact(0.5) < 0.3 and an.impact(1.0) < 0.05)
  check(
    "13 冲击全程为正（欠阻尼不取真弹簧：负摆=变暗闪烁，禁）",
    an.impact(0.07) > 0 and an.impact(0.21) > 0 and an.impact(0.36) > 0
  )
  check(
    "13 呼吸正弦 0→1→0（3.2s 周期）",
    an.breath(0) == 0 and math.abs(an.breath(1.6) - 1) < 1e-6 and an.breath(3.2) < 1e-6
  )
  check("13 基线选层=20（w=0.38 与八修定色连续，浮点 0.38/0.02 恰=19 实证）", an.layer(0.38) == 20)
  check(
    "13 渐隐落 0 → 层1、峰值 → 近顶层",
    an.layer(0) == 1 and an.layer(0.905) == 46 and an.layer(1) == 47
  )
  check(
    "13 基线色金值（八修连续性：色相 0/对角 @w0.38）",
    an.mix(0, 0.38) == "#ffa6a6" and an.mix(24, 0.38) == "#82e2e2"
  )
  check("13 白热峰值色（w0.9 近白留丝色相）", an.mix(0, 0.9) == "#fff2f2")
  -- bloom 阈值铁律：全网格（47 层×48 色位）Rec.601 亮度 > 0.2——ghostty
  -- bloom.glsl 只给 luma>0.2 的像素发光，任一层跌破即动画中段无辉光
  local minl = 1
  for li = 0, 46 do
    for i = 0, 47 do
      local hex = an.mix(i, li * 0.02)
      local l = 0.299 * tonumber(hex:sub(2, 3), 16) / 255
        + 0.587 * tonumber(hex:sub(4, 5), 16) / 255
        + 0.114 * tonumber(hex:sub(6, 7), 16) / 255
      if l < minl then
        minl = l
      end
    end
  end
  check("13 全网格 luma>0.2（bloom 铁律，实测最暗 " .. string.format("%.3f", minl) .. "）", minl > 0.2)
  check("13 AIAnim 预览命令已注册", vim.api.nvim_get_commands({})["AIAnim"] ~= nil)
end

-- 收尾（链桩不留假 sid 在用户 run 目录；真链 sid 归位）
vim.fn.delete(fake)
vim.fn.delete(payload)
vim.fn.delete(argvf)
vim.fn.delete(pwdf)
A.reset()
if chain_bak then
  vim.fn.mkdir(vim.fn.fnamemodify(CHAIN, ":h"), "p")
  vim.fn.writefile({ chain_bak }, CHAIN)
end
lib.finish()
