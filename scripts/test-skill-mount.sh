#!/bin/bash
# skills 自愈挂载回归门（headless --clean，秒级）。用法：bash scripts/test-skill-mount.sh
# 判据：沙箱 HOME/XDG 下直接执行从 lua/config/lazy.lua 提取的 [skill-mount]
# 区间原文（测的就是 shipped 代码，不复制逻辑）。A=有 skills/（建/幂等/断链/
# 他人实体），B=无 skills/（整段不动作）。见 scripts/test-skill-mount.lua、
# docs/adr/0006。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/xdg/nvim/skills/agent-sessions" "$T/xdg/nvim/skills/demo-two" \
  "$T/empty/nvim" "$T/homeA" "$T/homeB"
echo x > "$T/xdg/nvim/skills/agent-sessions/SKILL.md"

run_case() { # $1=CASE $2=XDG_CONFIG_HOME $3=HOME
  env -i PATH="$PATH" TERM=dumb HOME="$3" XDG_CONFIG_HOME="$2" \
    XDG_DATA_HOME="$T/data" XDG_STATE_HOME="$T/state" XDG_CACHE_HOME="$T/cache" \
    nvim --headless --clean \
    "+lua REPO=[[$ROOT]] HOME_T=[[$3]] CASE=[[$1]] dofile([[$ROOT/scripts/test-skill-mount.lua]])"
}

rc=0
run_case A "$T/xdg" "$T/homeA" || rc=1
run_case B "$T/empty" "$T/homeB" || rc=1
exit $rc
