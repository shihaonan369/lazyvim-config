#!/bin/bash
# codex 续接/模型键回归门（headless --clean，秒级）。用法：bash scripts/test-agent-codex.sh
# 判据：AGENT_CODEX_BIN 冒充（argv 落盘 + ❯ 渲染）→ aC/aR 的 spawn argv、
# aM 的 /model 注入分包、claude 专属面不越界。见 scripts/test-agent-codex.lua。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-codex.lua]])"
