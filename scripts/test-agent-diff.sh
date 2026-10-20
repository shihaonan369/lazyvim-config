#!/bin/bash
# inline diff 回归门（headless --clean，秒级）。用法：bash scripts/test-agent-diff.sh
# 第一段：agent-diff-hook.sh 单测（真实 PostToolUse JSON 形状，2026-10-20 原型
# 捕获）——快照内容 = originalFile、已存在不覆盖（回合基线）、env 未注入 no-op。
# 第二段：agent_diff 模块判据见 scripts/test-agent-diff.lua。docs/adr/0007 层 2。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

HT="$(mktemp -d)"
export AGENT_DIFF_DIR="$HT/d" AGENT_SESSION_TAG="9.9"
JSON='{"tool_input":{"file_path":"/tmp/proto-z.txt","old_string":"aaa","new_string":"ccc"},"tool_response":{"originalFile":"aaa\nbbb\n"}}'
printf '%s' "$JSON" | "$ROOT/scripts/agent-diff-hook.sh"
grep -q '^aaa$' "$HT/d/9.9/tmp/proto-z.txt" && grep -q '^bbb$' "$HT/d/9.9/tmp/proto-z.txt" \
  || { echo "FAIL hook 快照内容 != originalFile"; rm -rf "$HT"; exit 1; }
printf 'x' > "$HT/d/9.9/tmp/proto-z.txt"
printf '%s' '{"tool_input":{"file_path":"/tmp/proto-z.txt"},"tool_response":{"originalFile":"CHANGED"}}' \
  | "$ROOT/scripts/agent-diff-hook.sh"
[ "$(cat "$HT/d/9.9/tmp/proto-z.txt")" = "x" ] \
  || { echo "FAIL 回合基线被覆盖"; rm -rf "$HT"; exit 1; }
rm -rf "$HT"
( unset AGENT_DIFF_DIR; printf '{}' | "$ROOT/scripts/agent-diff-hook.sh" ) \
  || { echo "FAIL env 未注入应 no-op"; exit 1; }
echo "hook OK"

exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-diff.lua]])"
