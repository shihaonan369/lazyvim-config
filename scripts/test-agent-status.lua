-- agent 状态事件管线回归测试 payload（由 scripts/test-agent-status.sh 驱动，
-- headless --clean，判据 = 模块状态与 status() 字符串，不依赖 UI redraw）。
-- 覆盖：邮箱落地、tag 归因着色（含状态表情图标）、外来 tag 忽略、半行续读、
-- 非法状态词忽略、pane 收起全体睡觉且颜色保留、session 删除后状态随之消失。
-- docs/adr/0003。
local A = dofile(REPO .. "/lua/agent_sessions.lua")
vim.g.ai_assistant = "claude" -- 对齐真实配置默认（options.lua）；rename 分派依赖 ptype
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
local function settle(pat) -- 等状态收敛到含 pat（plain find）
  return vim.wait(2000, function() return A.status():find(pat, 1, true) ~= nil end)
end
local function quiesce(ms) -- 静置等待：谓词恒假，用于断言"无变化"
  vim.wait(ms or 200, function() return false end)
end

local icon = vim.fn.nr2char(0xF06A9) -- robot 实心（无事件/当前），同模块定义
local outline = vim.fn.nr2char(0xF167A) -- robot 空心（无事件/后台），同模块定义
local asleep = vim.fn.nr2char(0xF16A7) -- robot_off 收起睡觉，同模块定义
-- 状态表情（实心=当前/空心=后台），同模块定义
local excited_o = vim.fn.nr2char(0xF16A4) -- working 空心
local happy = vim.fn.nr2char(0xF1719) -- idle 实心
local confused = vim.fn.nr2char(0xF169F) -- attention 实心
local confused_o = vim.fn.nr2char(0xF16A0) -- attention 空心

-- 两个假 agent（绝对路径：termopen env 会替换继承环境，相对路径秒死）
A.claude_open("/bin/sleep 600", {}, false)
A.claude_open("/bin/sleep 600", {}, false)

local file = A.event_file()
check("事件邮箱已落地", file ~= nil and vim.uv.fs_stat(file) ~= nil)

local pid = vim.fn.getpid()
local tag1, tag2 = pid .. ".1", pid .. ".2"
local function emit(tag, state)
  local fh = assert(io.open(file, "a"))
  fh:write(string.format('{"tag":"%s","state":"%s"}\n', tag, state))
  fh:close()
end

-- session2 是当前显示（后 spawn）；初始无事件全体中性色（ModeMsg）+ 无表情
check("初始中性色 + 当前实心/后台空心",
  A.status():find("%#ModeMsg#" .. outline, 1, true) ~= nil
  and A.status():find("%#ModeMsg#" .. icon, 1, true) ~= nil)

-- 先泵一次事件循环：macOS FSEvents 流要等 loop 运行才真正激活，
-- 此前写入的通知会丢（真实场景 spawn 到首个 hook 事件隔着用户交互，无此竞态）
quiesce(300)

emit(tag1, "working")
check("tag1(后台) working → Function + excited 空心", settle("%#Function#" .. excited_o))

emit(tag2, "idle")
check("tag2(当前) idle → Character + happy 实心", settle("%#Character#" .. happy))

-- 外来 tag：别的 nvim 实例的事件不得影响本实例
local before = A.status()
emit("999999.9", "attention")
quiesce()
check("外来 tag 被忽略", A.status() == before and not A.status():find("DiagnosticError", 1, true))

-- 半行写入：残行不消费，补全换行后生效
do
  local fh = assert(io.open(file, "a"))
  fh:write(string.format('{"tag":"%s","state":"attention"', tag1))
  fh:close()
end
quiesce()
check("半行暂不生效", not A.status():find("DiagnosticError", 1, true))
do
  local fh = assert(io.open(file, "a"))
  fh:write("}\n")
  fh:close()
end
check("补全后 attention → DiagnosticError", settle("%#DiagnosticError#" .. confused_o))

-- 非法状态词：不得清掉既有状态
emit(tag1, "bogus")
quiesce()
check("非法状态词被忽略", A.status():find("%#DiagnosticError#" .. confused_o, 1, true) ~= nil)

-- pane 收起：全体睡觉，颜色仍按状态
A.hide()
quiesce()
check("收起后全体睡觉且色保留",
  A.status():find("%#DiagnosticError#" .. asleep, 1, true) ~= nil
  and A.status():find("%#Character#" .. asleep, 1, true) ~= nil)

-- 删除当前 session：TermClose 移除、编号顺延、状态随之消失。
-- pane 仍处于收起状态，先 show 回来再断言表情图标与状态保留
A.delete(2)
A.show_only()
check("删除后 session1 转正(空心→实心)且状态保留", settle("%#DiagnosticError#" .. confused))
check("删除后无睡觉/空心残留",
  not A.status():find(asleep, 1, true) and not A.status():find(confused_o, 1, true)
  and not A.status():find(outline, 1, true))

-- 名字同步（docs/adr/0003 修订）：SessionStart 上报 → 登记时读 custom-title.json
-- 兜住 resume 已命名；运行中 /rename 追加 custom-title 行 → luv 增量捕捉。
-- 剩下的唯一 session（删除后 session1 转正）用 tag1 归因
local tdir = vim.fn.stdpath("run") .. "/agent-rename-test"
vim.fn.mkdir(tdir, "p")
local tpath = tdir .. "/sid42.jsonl"
do
  local fh = assert(io.open(tpath, "w"))
  fh:write('{"type":"user","message":"hi"}\n')
  fh:close()
end
vim.fn.mkdir(tdir .. "/sid42", "p")
vim.fn.writefile({ '{"customTitle":"旧名字"}' }, tdir .. "/sid42/custom-title.json")
do
  local fh = assert(io.open(file, "a"))
  fh:write(string.format('{"tag":"%s","sid":"sid42","transcript":"%s"}\n', tag1, tpath))
  fh:close()
end
check("登记时读 custom-title.json（resume 命名）", vim.wait(2000, function()
  return A.list()[1] and A.list()[1].name == "旧名字"
end))
do
  local fh = assert(io.open(tpath, "a"))
  fh:write('{"type":"custom-title","customTitle":"新名字","sessionId":"sid42"}\n')
  fh:close()
end
check("/rename → transcript 增量同步", vim.wait(2000, function()
  return A.list()[1] and A.list()[1].name == "新名字"
end))

-- nvim 侧改名（claude）：只发命令不落名——名字单点在回流，假成功不科学
A.rename(A.list()[1].id, "本地改名")
check("r 只发命令不本地落名（claude 回流单点）", A.list()[1].name == "新名字")

print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
