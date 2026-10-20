-- testlib: 回归 payload 共享脚手架（scripts/test-*.lua 经 dofile 引入；REPO
-- 全局由驱动 .sh 注入）。dofile 每 payload 独立实例，fails 互不共享。
-- 失败一律记 FAIL 干净退出——assert 抛错会让 headless nvim 挂住不退，红相也
-- 要能出非零退出码（收尾见 finish：全过 qa!、有败 cq）
local M = { fails = {}, quiesce_ms = 400 }

function M.check(name, cond)
  print((cond and "ok   " or "FAIL ") .. name)
  if not cond then M.fails[#M.fails + 1] = name end
end

-- 静置：谓词恒假，等 schedule 链走完。默认毫秒数按 payload 各自节奏设
-- lib.quiesce_ms（status 200 / pane、tab 400 / tree、goto 500）
function M.quiesce(ms)
  vim.wait(ms or M.quiesce_ms, function() return false end)
end

-- 直调真键位回调（headless 惯例：修饰键/nvim_input 编码不可靠，回调等价且
-- 确定）。buf 给定时在 buffer 语境取 maparg（buffer 局部键，如显示窗 </>）。
-- 映射缺失记 FAIL 返回 false——判据连锁失败但干净退出
function M.press(lhs, buf)
  local m
  if buf then
    vim.api.nvim_buf_call(buf, function() m = vim.fn.maparg(lhs, "n", false, true) end)
  else
    m = vim.fn.maparg(lhs, "n", false, true)
  end
  if not (type(m) == "table" and m.callback) then
    M.check(lhs .. " 映射在位", false)
    return false
  end
  m.callback()
  return true
end

-- 收尾：汇总判据，全过 qa!、有败 cq（非零退出码）
function M.finish()
  print(#M.fails == 0 and "ALL PASS" or ("FAILED: " .. table.concat(M.fails, ", ")))
  vim.cmd(#M.fails == 0 and "qa!" or "cq")
end

return M
