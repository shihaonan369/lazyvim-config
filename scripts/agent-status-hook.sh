#!/bin/sh
# agent 状态事件钩子（claude / codex 共用，docs/adr/0003）。
# 用法（状态词由各家 hook 配置的 argv 写死，脚本不做任何 JSON 解析）：
#   agent-status-hook.sh working | idle | attention
# env 未注入（agent 不在 nvim agent pane 里跑）时静默 no-op；永远 exit 0
# （claude hook 退出码 2 有阻塞语义，不可误触）。
[ -n "$AGENT_STATUS_FILE" ] && [ -n "$AGENT_SESSION_TAG" ] || exit 0
printf '{"tag":"%s","state":"%s"}\n' "$AGENT_SESSION_TAG" "$1" >> "$AGENT_STATUS_FILE"
