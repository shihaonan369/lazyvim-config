#!/bin/sh
# agent 状态事件钩子（claude / codex 共用，docs/adr/0003）。
# 用法（状态词由各家 hook 配置的 argv 写死，脚本不做任何 JSON 解析）：
#   agent-status-hook.sh working | idle | attention
# env 未注入（agent 不在 nvim agent pane 里跑）时静默 no-op；永远 exit 0
# （claude hook 退出码 2 有阻塞语义，不可误触）。
# Codex 通过管道写入事件 JSON；即便 no-op 也须读完，否则大负载会使
# 调用方写 stdin 遇到 EPIPE，把退出码 0 的 hook 仍判为失败。
cat >/dev/null
[ -n "$AGENT_STATUS_FILE" ] && [ -n "$AGENT_SESSION_TAG" ] || exit 0
# nvim 退出后临时邮箱可能已消失；状态上报失败不能影响 agent。
{ printf '{"tag":"%s","state":"%s"}\n' "$AGENT_SESSION_TAG" "$1" >> "$AGENT_STATUS_FILE"; } 2>/dev/null
exit 0
