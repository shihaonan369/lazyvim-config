#!/bin/bash
# 带名新建回归门（headless --clean，秒级）。用法：bash scripts/test-agent-named.sh
# 判据：❯ 渲染驱动就绪队列（buf_attach 事件）→ /rename 与括号粘贴注入原文
# 可捕获。native 冷启动（自构命令）由判据 0 覆盖；plugin 态冷启动链
# （:ClaudeCode）属 claudecode 插件域，不在此测。见 scripts/test-agent-named.lua。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-named.lua]])"
