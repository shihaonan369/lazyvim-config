-- skills 自愈挂载回归 payload（scripts/test-skill-mount.sh 驱动，headless --clean）。
-- 直接执行从 lua/config/lazy.lua 提取的 [skill-mount-begin/end] 区间原文——
-- 测的就是 shipped 代码。沙箱 HOME/XDG 下断言挂载语义（docs/adr/0006）：
-- A1 缺则建（绝对 symlink）A2 幂等 A3 断链重建
-- A4 他人真实目录不碰      A5 外指有效链不碰   B1 无源目录整段不动作
local src = vim.fn.readfile(REPO .. "/lua/config/lazy.lua")
local block, on = {}, false
for _, l in ipairs(src) do
  if l:find("skill-mount-begin", 1, true) then on = true end
  if on then block[#block + 1] = l end
  if l:find("skill-mount-end", 1, true) then on = false end
end
assert(#block > 1, "lazy.lua 里找不到 [skill-mount] 区间")
local run_block = assert(load(table.concat(block, "\n")))
local notify_n = 0
vim.notify = function() notify_n = notify_n + 1 end -- 静默化＋可断言

local dst = HOME_T .. "/.claude/skills"
local cfg = vim.fn.stdpath("config")
local function rl(p) return vim.uv.fs_readlink(p) end
local function has(p) return vim.uv.fs_stat(p) ~= nil end
local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

if CASE == "A" then
  -- A4/A5 先行：两类他人实体占名 → 不碰
  vim.fn.mkdir(dst .. "/demo-two", "p")
  vim.fn.writefile({ "occupied" }, dst .. "/demo-two/keep")
  vim.fn.mkdir(HOME_T .. "/elsewhere", "p")
  vim.uv.fs_symlink(HOME_T .. "/elsewhere", dst .. "/agent-sessions")
  run_block()
  check("A4 他人真实目录保留", has(dst .. "/demo-two/keep") and rl(dst .. "/demo-two") == nil)
  check("A5 外指有效链原样", rl(dst .. "/agent-sessions") == HOME_T .. "/elsewhere")

  vim.uv.fs_unlink(dst .. "/agent-sessions")
  vim.fn.delete(dst .. "/demo-two", "rf")
  run_block() -- 名下无物 → 建
  check("A1 agent-sessions 挂载", rl(dst .. "/agent-sessions") == cfg .. "/skills/agent-sessions")
  check("A1 demo-two 挂载", rl(dst .. "/demo-two") == cfg .. "/skills/demo-two")
  check("A1 修复有提示", notify_n >= 2)

  local n0 = notify_n
  run_block() -- 全部已就位 → 无事发生
  check("A2 幂等不重建", notify_n == n0 and rl(dst .. "/agent-sessions") == cfg .. "/skills/agent-sessions")

  vim.uv.fs_unlink(dst .. "/agent-sessions")
  vim.uv.fs_symlink(HOME_T .. "/gone-away", dst .. "/agent-sessions")
  check("A3 前置确是断链", not has(dst .. "/agent-sessions"))
  run_block()
  check("A3 断链重建", rl(dst .. "/agent-sessions") == cfg .. "/skills/agent-sessions")
else -- CASE B：源 skills/ 不存在
  run_block()
  check("B1 无源整段不动作", vim.uv.fs_stat(HOME_T .. "/.claude") == nil)
end

lib.finish()
