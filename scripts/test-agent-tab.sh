#!/bin/bash
# agent tab 视口回归门（headless --clean，秒级）。用法：bash scripts/test-agent-tab.sh
# 判据基于 tab/窗口/模块状态实测；neo-tree 缺席时树以 winvar 骨架降级，
# 树本体（渲染/键位）属 TUI 端到端，不在此固化。见 scripts/test-agent-tab.lua、
# docs/adr/0005。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-tab.lua]])"
