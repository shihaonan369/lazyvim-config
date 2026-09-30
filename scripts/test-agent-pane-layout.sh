#!/bin/bash
# agent pane 布局回归门（headless --clean，秒级）。用法：bash scripts/test-agent-pane-layout.sh
# 判据基于窗口/模块状态实测，不依赖 UI redraw；picker 关浮窗的重算偷宽无法
# headless 复现（需 TUI 刷新循环），判据 5 以"兄弟窗 ≥ winwidth"结构性保证覆盖。
# 见 scripts/test-agent-pane-layout.lua、docs/adr/0002（修订）、0004。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean -i NONE \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-pane-layout.lua]])"
