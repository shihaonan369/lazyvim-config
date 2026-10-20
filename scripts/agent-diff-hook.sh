#!/bin/sh
# claude 改动快照钩子（先落后审，docs/adr/0007 层 2）。
# PostToolUse stdin JSON 的 tool_response.originalFile = 本次编辑前的完整
# 原文（2026-10-20 实证）；同一文件只写一次 = 本回合基线，accept 删快照、
# deny 快照写回。快照路径 = $AGENT_DIFF_DIR/$AGENT_SESSION_TAG<绝对路径镜像>
# （tag 前缀隔离 nvim 实例与 session，目录镜像免去编码歧义）。
# AGENT_DIFF_DIR 未注入（plugin 态/裸跑）时静默 no-op；永远 exit 0
# （claude hook 退出码 2 有阻塞语义，不可误触）。
# 注意：--bare 会跳过全部 hooks——native 态的 spawn 不用 --bare。
[ -n "$AGENT_DIFF_DIR" ] && [ -n "$AGENT_SESSION_TAG" ] || exit 0
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
snap="$AGENT_DIFF_DIR/$AGENT_SESSION_TAG$file"
mkdir -p "$(dirname "$snap")"
[ -e "$snap" ] || printf '%s' "$input" | jq -r '.tool_response.originalFile // empty' > "$snap"
