#!/usr/bin/env bash
# 经 nvim agent_sessions 建 1 个 claude 会话，可选命名＋首发 prompt。
# 用法: spawn_one.sh <会话名> [prompt文件]
#   prompt 文件建议单条完整指令；多行安全（括号粘贴）。不带 prompt 则建好即闲置。
# 语义: 命令即回 id；改名与投喂在 TUI 就绪后由 nvim 侧就绪队列自动送达
#   （FIFO 先改名后投喂，60s 超时作废）——bash 侧不再等待循环，批量更快。
# 依赖: env NVIM（在 nvim agent pane 里跑的 claude 才有）；agent_sessions 模块。
set -euo pipefail

NAME=${1:?用法: spawn_one.sh <会话名> [prompt文件]}
PROMPT_FILE=${2:-}
SKILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ASLUA="$SKILL_DIR/scripts/asend.lua"
: "${NVIM:?不在 nvim agent pane 内（\$NVIM 未设）——本 skill 只适用于 nvim 内 spawn 的 claude}"

# dofile ＋ 表达式合并进一次 remote-expr；调用侧只出现裸标识符/数字/[[...]]
call() { nvim --server "$NVIM" --remote-expr "luaeval(\"(function() dofile('$ASLUA') return $1 end)()\")"; }

ID=$(call "_G.aspawn([[$NAME]])")
[[ "$ID" =~ ^[0-9]+$ ]] || { echo "spawn 失败: $ID" >&2; exit 1; }

if [ -n "$PROMPT_FILE" ]; then
  call "_G.aprompt_file($ID, [[$PROMPT_FILE]])" >/dev/null
fi
echo "id=$ID name=$NAME（就绪后自动送达）prompt=$([ -n "$PROMPT_FILE" ] && echo 已排队 || echo 无)"
