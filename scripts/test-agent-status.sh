#!/bin/bash
# agent 状态事件管线回归门（headless --clean，秒级）。用法：bash scripts/test-agent-status.sh
# 判据全部基于模块状态与 status() 字符串，不依赖 UI redraw。见 docs/adr/0003。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean -i NONE \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-status.lua]])"
