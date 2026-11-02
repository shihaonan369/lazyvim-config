#!/bin/bash
# Codex OSC 标题 → session 名字 → 真 agent tree 渲染回归。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/scripts/test-agent-codex-rename.lua]])"
