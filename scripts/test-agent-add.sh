#!/bin/bash
# Smart Add 草稿注入回归门（headless --clean，秒级）。用法：bash scripts/test-agent-add.sh
# 判据：M.draft 序列 = Ctrl-U → 括号粘贴（多行安全）→ **无 CR**（不提交，
# 过目语义；与 skill 的 aprompt 提交语义相对）。见 scripts/test-agent-add.lua、
# docs/adr/0007。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-add.lua]])"
