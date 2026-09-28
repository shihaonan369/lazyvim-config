-- agent 状态事件管线回归测试 payload（由 scripts/test-agent-status.sh 驱动，
-- headless --clean，判据 = 模块状态与 status() 字符串，不依赖 UI redraw）。
-- 覆盖：邮箱落地、tag 归因着色、外来 tag 忽略、半行续读、非法状态词忽略、
-- pane 收起全体闭眼且颜色保留、session 删除后状态随之消失。docs/adr/0003。
local A = dofile(REPO .. "/lua/agent_sessions.lua")
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

local icon = vim.fn.nr2char(0xF06A9) -- PTYPE_ICON(nf-md-robot)，同模块定义
local eye = vim.fn.nr2char(0xF0209) -- 闭眼，同模块定义
local outline = vim.fn.nr2char(0xF167A) -- 后台空心图标，同模块定义

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

-- session2 是当前显示（后 spawn），带空格方括号；初始无事件全体中性色（ModeMsg）
check("初始中性色 + 当前实心/后台空心",
  A.status():find("%#ModeMsg#" .. outline, 1, true) ~= nil
  and A.status():find("%#ModeMsg#" .. icon, 1, true) ~= nil)

-- 先泵一次事件循环：macOS FSEvents 流要等 loop 运行才真正激活，
-- 此前写入的通知会丢（真实场景 spawn 到首个 hook 事件隔着用户交互，无此竞态）
quiesce(300)

emit(tag1, "working")
check("tag1(后台空心) working → Function", settle("%#Function#" .. outline))

emit(tag2, "idle")
check("tag2(当前实心) idle → Character", settle("%#Character#" .. icon))

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
check("补全后 attention → DiagnosticError", settle("%#DiagnosticError#" .. outline))

-- 非法状态词：不得清掉既有状态
emit(tag1, "bogus")
quiesce()
check("非法状态词被忽略", A.status():find("%#DiagnosticError#" .. outline, 1, true) ~= nil)

-- pane 收起：全体闭眼，颜色仍按状态
A.hide()
quiesce()
check("收起后全体闭眼且色保留",
  A.status():find("%#DiagnosticError#" .. eye, 1, true) ~= nil
  and A.status():find("%#Character#" .. eye, 1, true) ~= nil)

-- 删除当前 session：TermClose 移除、编号顺延、状态随之消失。
-- pane 仍处于收起状态，先 show 回来再断言睁眼图标与状态保留
A.delete(2)
A.show_only()
check("删除后 session1 转正(空心→实心)且状态保留", settle("%#DiagnosticError#" .. icon))
check("删除后无闭眼/空心残留",
  not A.status():find(eye, 1, true) and not A.status():find(outline, 1, true))

print(#fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(fails, ", ")))
vim.cmd(#fails == 0 and "qa!" or "cq")
