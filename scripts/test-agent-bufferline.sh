#!/bin/bash
# 真 bufferline 集成回归；默认使用本机 lazy 安装，也可传 BUFFERLINE_DIR。
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-bufferline.lua]])"
