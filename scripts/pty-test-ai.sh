#!/bin/bash
# :AI PTY 全链验（script -q 真配置真 TUI，秒级）。判据 = 翻译/取消/超时/
# 执行四段语义 + 动效三段（冲击峰值层/呼吸带/extmark 清零）+ 单帧多色。
# 用法：TERMINAL_THEME=retro bash scripts/pty-test-ai.sh（默认 tokyonight）
set -u
FAKE=/tmp/pty-fake-claude.sh
PAYLOAD=/tmp/pty-payload.json
LOG=/tmp/pty-ai.log
cat > "$FAKE" <<EOF
#!/bin/sh
sleep 3
cat "$PAYLOAD"
EOF
printf '%s' '{"session_id":"sid-pty-1","result":"cmd:tabnew | let g:ai_pty_ok = 7"}' > "$PAYLOAD"
chmod +x "$FAKE"
CHAIN="$HOME/.cache/nvim/ai-cmd/chain-sid"
[ -f "$CHAIN" ] && cp "$CHAIN" "$CHAIN.bak-pty"
{ sleep 14
  printf ':let g:ai_cmd_timeout=500\r'; sleep 2
  printf ':AI 开新tab\r'          # 超时段：终态注释行 + 渐隐落主题色
  sleep 2; printf '\x1b'          # Esc 收注释行
  sleep 1; printf ':let g:ai_cmd_timeout=60000\r'; sleep 2
  printf ':AI 开新tab\r'          # 取消段：等待期 Esc
  sleep 1; printf '\x1b'; sleep 1.5
  printf ':AI 开新tab\r'          # 成功段：冲击→呼吸流动 + 原地变身
  sleep 4.5; printf '\r'
  sleep 1; printf ':lua print("PTYTABS="..vim.fn.tabpagenr("$").." OK="..tostring(vim.g.ai_pty_ok))\r'
  sleep 1; printf ':lua local ns=vim.api.nvim_get_namespaces()["ai_cmd_rainbow"] local n=0 for _,b in ipairs(vim.api.nvim_list_bufs()) do pcall(function() n=n+#vim.api.nvim_buf_get_extmarks(b,ns,0,-1,{}) end) end vim.fn.writefile({tostring(n)},"/tmp/pty-ext.txt")\r'
  sleep 1; printf ':qa!\r'; sleep 2
} | script -q "$LOG" env AGENT_CLAUDE_BIN="$FAKE" nvim >/dev/null 2>&1
echo "=== PTY 判据 ==="
for pat in "retry freely" "Canceled" "Translating" "PTYTABS=2 OK=7"; do
  if grep -aq "$pat" "$LOG"; then echo "ok   $pat"; else echo "FAIL $pat"; fi
done
python3 - "$LOG" <<'EOF'
import math, sys
data = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
def sgr(i, w):  # 色位 i、白混 w → SGR 真彩色串（与 rb_mix_hex 同式）
    h = i / 48.0
    two_pi = 6.2831853
    r = 0.5 + 0.5 * math.cos(two_pi * (h + 0.00))
    g = 0.5 + 0.5 * math.cos(two_pi * (h + 0.33))
    b = 0.5 + 0.5 * math.cos(two_pi * (h + 0.67))
    f = lambda v_: int((v_ + (1 - v_) * w) ** 0.7 * 255 + 0.5)
    return "38;2;%d;%d;%d" % (f(r), f(g), f(b))

band = [sgr(i, w) for w in (0.38, 0.40, 0.42, 0.44, 0.46) for i in range(48)]  # 静息+呼吸带
peak = [sgr(i, 0.90) for i in range(48)]   # 冲击近白层
pb = sum(1 for sg in band if sg in data)
pp = sum(1 for sg in peak if sg in data)
print(f"ok   静息/呼吸带命中 {pb}/240" if pb >= 40 else f"FAIL 呼吸带仅 {pb}")
print(f"ok   冲击峰值层命中 {pp}/48（动效触发）" if pp >= 8 else f"FAIL 冲击层仅 {pp}")
try:
    left = open("/tmp/pty-ext.txt").read().strip()
except OSError:
    left = "missing"
print(f"ok   终态清理 extmark=0（收场触发）" if left == "0" else f"FAIL 终态残留 extmark={left}")
family = band + peak
best = 0
for i in range(0, len(data) - 2000, 500):
    w = data[i : i + 2000]
    n = sum(1 for sg in family if sg in w)
    best = max(best, n)
print(f"ok   单帧多色同框: {best} 色" if best >= 8 else f"FAIL 单帧仅 {best} 色")
EOF
if [ -f "$CHAIN.bak-pty" ]; then mv "$CHAIN.bak-pty" "$CHAIN"; else rm -f "$CHAIN"; fi
rm -f "$FAKE" "$PAYLOAD"
