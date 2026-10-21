#!/bin/bash
# :AI 自然语言直驱回归门（headless --clean，秒级）。用法：bash scripts/test-ai-cmd.sh
# 判据：假 claude 驱动翻译/审查/执行三段——cmd:/lua: 负载、围栏剥离、
# 无前缀不假成功、拒审不执行、argv/cwd 装配。见 scripts/test-ai-cmd.lua、
# lua/ai_cmd.lua 头注。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-ai-cmd.lua]])"
