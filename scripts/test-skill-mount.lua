-- skills 投递回归 payload（scripts/test-skill-mount.sh 驱动，headless --clean）。
-- 直接执行从 lua/config/lazy.lua 提取的 [skill-mount-begin/end] 区间原文——
-- 测的就是 shipped 代码。沙箱 HOME/XDG 下断言（docs/adr/0009）：
-- U1 旧全局链(指回本仓)卸载  U2 他人外指链不碰  U3 缺失旧目录不建
-- C1 codex 挂载缺则建        C2 幂等           C3 断链重建  C4 他人实体不碰
-- B1 无源目录整段不动作
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

local cfg = vim.fn.stdpath("config")
local function rl(p) return vim.uv.fs_readlink(p) end
local function has(p) return vim.uv.fs_stat(p) ~= nil end
local function lstat(p)
  local _, st = pcall(vim.uv.fs_lstat, p)
  return st
end
local lib = dofile(REPO .. "/scripts/testlib.lua") -- 共享脚手架：check/finish
local check = lib.check

if CASE == "A" then
  -- 场景布置：两个旧共享目录各有「本仓旧链 + 他人外指链」，codex 目录空缺
  vim.fn.mkdir(HOME_T .. "/elsewhere", "p")
  local legacy = { HOME_T .. "/.claude/skills", HOME_T .. "/.agents/skills" }
  for _, d in ipairs(legacy) do
    vim.fn.mkdir(d, "p")
    vim.uv.fs_symlink(cfg .. "/skills/agent-sessions", d .. "/agent-sessions")
    vim.uv.fs_symlink(HOME_T .. "/elsewhere", d .. "/demo-two")
  end
  run_block()
  for _, d in ipairs(legacy) do
    check("U1 旧链卸载 " .. d, lstat(d .. "/agent-sessions") == nil)
    check("U2 外指链不碰 " .. d, rl(d .. "/demo-two") == HOME_T .. "/elsewhere")
  end
  check(
    "C1 codex 挂载 agent-sessions",
    rl(HOME_T .. "/.codex/skills/agent-sessions") == cfg .. "/skills/agent-sessions"
  )
  check("C1 codex 挂载 demo-two", rl(HOME_T .. "/.codex/skills/demo-two") == cfg .. "/skills/demo-two")
  check("C1 修复有提示", notify_n >= 3)

  local n0 = notify_n
  run_block()
  check(
    "C2 幂等不重建",
    notify_n == n0 and rl(HOME_T .. "/.codex/skills/agent-sessions") == cfg .. "/skills/agent-sessions"
  )

  vim.uv.fs_unlink(HOME_T .. "/.codex/skills/agent-sessions")
  vim.uv.fs_symlink(HOME_T .. "/gone-away", HOME_T .. "/.codex/skills/agent-sessions")
  check("C3 前置确是断链", not has(HOME_T .. "/.codex/skills/agent-sessions"))
  run_block()
  check(
    "C3 断链重建",
    rl(HOME_T .. "/.codex/skills/agent-sessions") == cfg .. "/skills/agent-sessions"
  )

  vim.uv.fs_unlink(HOME_T .. "/.codex/skills/demo-two")
  vim.fn.mkdir(HOME_T .. "/.codex/skills/demo-two", "p")
  vim.fn.writefile({ "occupied" }, HOME_T .. "/.codex/skills/demo-two/keep")
  run_block()
  check(
    "C4 他人真实目录保留",
    has(HOME_T .. "/.codex/skills/demo-two/keep") and rl(HOME_T .. "/.codex/skills/demo-two") == nil
  )

  vim.fn.delete(HOME_T .. "/.agents/skills", "rf")
  run_block()
  check("U3 缺失旧目录不重建", lstat(HOME_T .. "/.agents/skills") == nil)
else -- CASE B：源 skills/ 不存在
  run_block()
  check(
    "B1 无源整段不动作",
    vim.uv.fs_stat(HOME_T .. "/.codex/skills") == nil
      and vim.uv.fs_stat(HOME_T .. "/.claude/skills") == nil
      and vim.uv.fs_stat(HOME_T .. "/.agents/skills") == nil
  )
end

lib.finish()
