#!/bin/bash
# pi 后端接线回归门（headless --clean，秒级）。用法：bash scripts/test-agent-pi.sh
# 判据：AGENT_PI_BIN 冒充（argv 落盘 + ─ 规则线渲染 + 7501 报文）→ -n 带名、
# aC/aR 的 spawn argv、7501 状态/名字回流、aM 分包注入、/name 改名、
# Ctrl+D 优雅退出。见 scripts/test-agent-pi.lua。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-pi.lua]])"
