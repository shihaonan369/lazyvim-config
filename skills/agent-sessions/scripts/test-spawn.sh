#!/usr/bin/env bash
# Isolated headless regression; requires nvim and python3, no real Claude/API use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
exec nvim --headless --clean \
  "+lua REPO=[[$ROOT]] dofile([[$ROOT/skills/agent-sessions/scripts/test-spawn.lua]])"
