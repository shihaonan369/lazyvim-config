/**
 * agent-pi-bridge —— nvim agent_sessions 的 pi 侧通道扩展（**随 nvim 仓走**，
 * spawn 时经 `pi -e <本文件>` 注入——与 claude 的 `--settings
 * scripts/agent-status-settings.json` 同款零安装模式，ADR 0008；新装 pi 即用，
 * 机器侧 ~/.pi 无任何依赖）。env 未注入（终端里裸跑的 pi）时整体 no-op。
 *
 * 职责两件：
 * 1. inline diff 快照：tool_call 在工具执行**前**触发，edit/write 命中时同步
 *    读盘快照落 `$AGENT_DIFF_DIR/$AGENT_SESSION_TAG<绝对路径镜像>`（同
 *    scripts/agent-diff-hook.sh 布局，nvim 侧 agent_diff.lua 后端中立复用）；
 *    同文件只写一次 = 回合基线；失败不阻塞工具。
 * 2. 名字即时回流：idle 态 TUI 内 /name 不触发 OSC 7501 新报文（msg 只随
 *    working/done 走）——session_info_changed 时向 $AGENT_STATUS_FILE 单行
 *    追加 `{"tag","name"}`（ADR 0003 邮箱通道，nvim 侧 status_apply name
 *    路由）；session_start 亦上报既有名（resume 即上树，不必等首回合）。
 */
import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

export default function (pi: ExtensionAPI) {
  const diffDir = process.env.AGENT_DIFF_DIR;
  const statusFile = process.env.AGENT_STATUS_FILE;
  const tag = process.env.AGENT_SESSION_TAG;
  if (!tag || (!diffDir && !statusFile)) return;

  if (diffDir) {
    pi.on("tool_call", (event) => {
      const p =
        (isToolCallEventType("edit", event) && event.input.path) ||
        (isToolCallEventType("write", event) && event.input.path);
      if (typeof p !== "string" || p === "") return;
      try {
        const abs = path.resolve(p);
        if (!fs.existsSync(abs)) return; // 新建文件无基线可快
        const snap = path.join(diffDir, tag + abs);
        if (fs.existsSync(snap)) return; // 同文件只写一次 = 回合基线
        fs.mkdirSync(path.dirname(snap), { recursive: true });
        fs.copyFileSync(abs, snap);
      } catch {
        /* 快照失败不阻塞工具 */
      }
    });
  }

  if (statusFile) {
    const report = (name: string | undefined) => {
      if (!name) return;
      try {
        fs.appendFileSync(statusFile, JSON.stringify({ tag, name }) + "\n");
      } catch {
        /* 邮箱不可写不阻塞会话 */
      }
    };
    pi.on("session_info_changed", (event) => report(event.name));
    pi.on("session_start", () => report(pi.getSessionName()));
  }
}
