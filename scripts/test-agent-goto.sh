#!/bin/bash
# <leader>a1..9 直达位置编号回归门（headless --clean，秒级）。
# 用法：bash scripts/test-agent-goto.sh
# 判据见 scripts/test-agent-goto.lua（切换不夺焦、右窗路由、越界反馈）。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean -u NONE \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-goto.lua]])"
