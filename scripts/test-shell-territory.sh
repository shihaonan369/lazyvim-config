#!/bin/bash
# shell 领地标记回归门（headless --clean，秒级）。用法：bash scripts/test-shell-territory.sh
# 覆盖 2026-10-27 泄漏案：普通窗轮换到 terminal buffer 曾被标成领地，离开时
# relocate 把文件塞进 neo-tree 侧栏，触发其自卫造窗，轮换一次多一窗。
# 判据基于 winvar/窗口状态实测；见 docs/adr/0002（修订）、lua/agent_sessions.lua
# （mark_shell_territory / BufWinEnter 守卫 / main_target_win）。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-shell-territory.lua]])"
