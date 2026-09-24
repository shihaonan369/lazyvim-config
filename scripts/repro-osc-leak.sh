#!/bin/bash
# nvim terminal 的 DCS 泄漏复现 + agent_sessions 剥 tmux env 的机制回归门。
# 根因（2026-09-24 headless 实测闭环，nvim 0.12.5）：
#   nvimdc 的 nvim 跑在 tmux 内 → claude 继承 TMUX → 把终端查询写成 tmux
#   passthrough DCS（ESC P tmux ; …）→ nvim terminal 解不了 DCS，内层载荷
#   （OSC11 背景色查询）泄漏成字面 "11;?" 渲染进 buffer。
# 判据（headless --clean，秒级，判据 = terminal buffer 行文本）：
#   1) DCS 包装版查询 → 泄漏 "11;?"（信息性：哪天 nvim 修了 DCS 处理本条会翻转）
#   2) 裸 OSC11 查询（关回显）→ buffer 无 "11;?"，nvim 自行应答
#   3) termopen env 空串覆盖 → 子进程 TMUX 为空（scrub_tmux_env 的机制）
# 用法：bash scripts/repro-osc-leak.sh

set -u

# 在 headless nvim 的 :terminal 里跑 $1（sh -c 命令串），$2 为 termopen opts，
# 打印 terminal buffer 全部行文本。父进程注入假 TMUX 模拟 nvimdc 环境。
run_term() {
  local extra="${2:+, $2}"
  TMUX=/tmp/fake,1234,0 TMUX_PANE=%5 nvim --headless --clean -i NONE \
    -c "lua vim.fn.termopen({'sh','-c',[[$1]]}${extra})" \
    -c 'sleep 1' \
    -c 'lua io.write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))' \
    -c 'qa!' 2>&1
}

fail=0

out=$(run_term 'stty -echo; printf "\ePtmux;\e\e]11;?\e\e\\"')
if grep -qF '11;?' <<<"$out"; then
  echo "1. DCS 包装查询泄漏字面 11;?   ：是（nvim terminal quirk，见头部注释）"
else
  echo "1. DCS 包装查询泄漏字面 11;?   ：否（nvim 可能已修复 DCS 解析；剥 TMUX 仍建议保留）"
fi

out=$(run_term 'stty -echo; printf "\e]11;?\e\\"')
if grep -qF '11;?' <<<"$out"; then
  echo "2. 裸 OSC11 查询泄漏           ：是 —— 回归！" >&2
  fail=1
else
  echo "2. 裸 OSC11 查询泄漏           ：否（nvim 消费并应答，符合预期）"
fi

out=$(run_term 'echo "child TMUX=[$TMUX] TMUX_PANE=[$TMUX_PANE]"' '{env={TMUX="",TMUX_PANE=""}}')
if grep -qF 'TMUX=[] TMUX_PANE=[]' <<<"$out"; then
  echo "3. env 空串覆盖后子进程 TMUX 空 ：是（scrub 机制有效）"
else
  echo "3. env 空串覆盖后子进程 TMUX 空 ：否 —— 回归！" >&2
  fail=1
fi

exit $fail
