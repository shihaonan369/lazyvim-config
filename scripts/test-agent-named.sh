#!/bin/bash
# 带名新建回归门（headless --clean，秒级）。用法：bash scripts/test-agent-named.sh
# 判据：❯ 渲染驱动就绪队列（buf_attach 事件）→ /rename 与括号粘贴注入原文
# 可捕获。冷启动链（:ClaudeCode）属 claudecode 插件域，不在此测（同 tab 测试
# 边界）。见 scripts/test-agent-named.lua、skills/agent-sessions/SKILL.md。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-named.lua]])"
