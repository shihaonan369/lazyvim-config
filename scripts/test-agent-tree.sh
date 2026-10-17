#!/bin/bash
# agent_tree 渲染跟随回归门（headless --clean + 真 neo-tree，秒级）。
# 用法：bash scripts/test-agent-tree.sh
# 与 test-agent-tab.sh 的分工：那边树降级为 winvar 骨架，这边固化树本体
# （current 标记、光标跟随、跨 tab 补刷）。见 scripts/test-agent-tree.lua。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean -u NONE \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-tree.lua]])"
