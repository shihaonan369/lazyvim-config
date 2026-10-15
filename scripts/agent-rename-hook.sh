#!/bin/sh
# SessionStart 钩子（docs/adr/0003 修订）：把 claude session 的身份报给 nvim
# 事件邮箱——nvim 侧 luv 盯 transcript 增量捕捉 {"type":"custom-title"} 行，
# 实现 claude /rename → agent 名字同步。env 未注入（agent 不在 nvim 里跑）、
# jq 缺失、字段缺失时静默降级；永远 exit 0（退出码 2 有阻塞语义，不可误触）。
[ -n "$AGENT_STATUS_FILE" ] && [ -n "$AGENT_SESSION_TAG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
jq -c --arg t "$AGENT_SESSION_TAG" \
  'select(.session_id and .transcript_path) | {tag:$t,sid:.session_id,transcript:.transcript_path}' \
  >> "$AGENT_STATUS_FILE" 2>/dev/null
exit 0
