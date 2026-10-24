-- :AI <自然语言> —— 自然语言直驱 nvim 操作：claude -p 单发把请求翻译成
-- cmd:<Ex 命令> / lua:<代码> 负载，**先审后执**（confirm 过目，用户裁决
-- 2026-10-21）。解析失败或拒审一律不执行（不假成功）。claude 固定跑在
-- stdpath("run")/ai-cmd 下——单发 transcript 不落当前项目，-r/aC picker
-- 不被翻译请求污染。提速实测（2026-10-21 探针）：--strict-mcp-config
-- 砍掉 MCP 装载 ~6s（8.9s→2.96s，翻译用不上 MCP）；本机 GLM 包装后端
-- 传任何 --model 都触发 unrecognized_model 回落——反而更慢且回答丢
-- cmd: 前缀，故**默认不传**；要走别的档设 vim.g.ai_cmd_model（值须后端认）。
-- 调查分档（用户裁决 2026-10-21）：纯操作类不查文件直接翻（保 ~3s 快
-- 路）；事实参数（如数据库连接）才查实不臆测——$() 现场取值优先、只读
-- 工具查证兜底。$() 有效域只在 :terminal/! shell 上下文（Ex 参数不做
-- 命令替换，探针实测模型会误塞进 :edit 参数——已写进提示词约束）。
-- :ai 小写入口见 setup 里的带守卫 cmdline 缩写。
local M = {}

local function bin()
  return vim.env.AGENT_CLAUDE_BIN or "claude"
end

-- 续链（用户裁决 2026-10-21「常驻后台 agent」的落地形态）：claude -p -r <sid>
-- 单发续链而非常驻进程——零新协议零看护（真常驻 stream-json 长管道是
-- ADR 0007 否决的 WS 桥同 genus）。上下文/调查结果留在链上，重复问题
-- 不重复调查；实测续链带缓存 2.3s（快于冷发）。链 sid 持久在
-- stdpath("cache")/ai-cmd/chain-sid——实测 stdpath("run") 是进程级临时
-- 目录（两实例路径随机不同），跨 nvim 重启续链必须用耐久位；claude 的
-- scratch cwd 仍走 run/ai-cmd（transcript 本体在 ~/.claude/projects，cwd
-- 目录短命无妨，隔离语义不变）；项目根另经 --add-dir 放行——-p 非交互
-- 下权限请求一律自动拒，无放行则事实参数类（查 .env/连接串等）的只读
-- 查证全被拒、烧满超时（2026-10-23 mysql 连接参数案实锤）。`:AI!` 重置
-- 链再问；链失效（transcript 被清等，claude 真报错）自动重开一次并明示
-- ——翻译超时另算：不动链不自动重试（2026-10-23 拆分：曾混进链失效分
-- 支，reset+重试撞同一堵墙再超时，用户见 WARN+ERROR 两跳），缺省 45s、
-- 可设 vim.g.ai_cmd_timeout（毫秒）。链会随条目增长变慢/变贵，bloat 咬
-- 手时 :AI! 即可——要不要自动按体积截链另议
local chain_file

local function chain_file_path()
  if not chain_file then
    chain_file = vim.fn.stdpath("cache") .. "/ai-cmd/chain-sid"
  end
  return chain_file
end

local function chain_load()
  local f = chain_file_path()
  if vim.uv.fs_stat(f) then -- readfile 对缺失文件抛 E484，先探在否
    local sid = vim.fn.readfile(f)
    if sid and sid[1] and sid[1] ~= "" then
      return sid[1]
    end
  end
  return nil
end

local function chain_save(sid)
  local f = chain_file_path()
  vim.fn.mkdir(vim.fn.fnamemodify(f, ":h"), "p")
  vim.fn.writefile({ sid or "" }, f)
end

function M.reset()
  chain_save(nil)
end

-- 输入框/图标内联形态均已弃（用户裁决 2026-10-21）：图标内联行因 cmdline
-- 的 <CR> 原生提交不可拦截（expr/回调映射双实证，E492 案）、setcmdprompt
-- 不存在、命令名必须 ASCII 大写而结构性不通；裸调则只提示缺内容，不弹
-- 任何输入框。唯一形态 = 带参 :AI 文本命令（五变体缩写归一）
-- 输入框复用（用户裁决 2026-10-23 二修：进度不为 popup 新框——notify 弹
-- 窗、底部过渡浮窗均已弃）：':' cmdline 一个面贯穿全程——等待期预填
-- ':"⠋ 翻译中… x.xs（ESC 取消）'（": 前缀=Ex 注释行，误回车=no-op——
-- cmdline CR 原生提交不可拦是既定结论，顺着原生语义设计而非对抗），tick
-- 定时 setcmdline 刷进度；完成原地变审查负载；超时/报错落注释行留框待
-- 收；等待期提前离开（Esc/C-c）=取消（SIGKILL）——离开即取消，拿到负载
-- 的唯一路径是守着输入框到它变身。播报走 M.report 缝；无 UI（headless）
-- UI 桩整体跳过。界面文案英文、进度行不回显原请求（用户裁决 2026-10-23
-- 三修）；等待期整框多色彩虹+颜色流动（2026-10-23 四修：多色非整框同
-- 色）；终态 8 段齐红

local function build_prompt(query)
  local bufname = vim.api.nvim_buf_get_name(0)
  local ver = vim.version()
  -- 配置词汇表（CONTEXT.md 唯一真相源）随问随读：模型对私有概念（agent
  -- tab/pane、session 状态等）零认知时只能瞎调研——「打开 agent tab 思
  -- 考半天还不对」案根因。词条覆盖不到的细节再给它配置目录只读兜底
  local ctx_path = vim.fn.stdpath("config") .. "/CONTEXT.md"
  local glossary = ""
  if vim.fn.filereadable(ctx_path) == 1 then
    glossary = table.concat(vim.fn.readfile(ctx_path), "\n"):sub(1, 12000)
  end
  local ret = { -- 先散表后拼：词汇表条件追加（concat 数组中间插 nil 会吞行）
    "你是 Neovim 操作翻译器：把用户请求转成 nvim 操作，只回负载本身，不要解释、不要 markdown 围栏。",
    "第一行起就是以下三种格式之一：",
    "cmd:<Ex 命令>（多命令用 | 或换行分隔，每行一条）",
    "lua:<lua 代码>（vim.cmd/vim.api/vim.fn 可用，可多行）",
    "say:<回复文本>（闲聊、问候、与 nvim 操作无关的纯对话用这个；say: 后面就是要给用户看的答案本身，不执行任何命令）",
    '翻译规则：优先 cmd:；用户请求本身就是一条命令时**原样直译**（如 :AI echo "你好" → cmd:echo "你好"），不包 terminal、不加 |；terminal 只用于打开外部交互程序（如新 tab: $tabnew | terminal mysql），且 terminal 之后禁止再用 | 拼接（其后全部文本都被当作 shell 命令，拼接不合法）；生成的操作只作用于当前 nvim 实例，不写文件系统。',
    "调查分档（用户裁决 2026-10-21）：纯操作类请求（开 tab、分屏、切换、关闭等，不依赖项目事实）**不查文件**，直接给负载；涉及本配置私有概念（agent tab、agent pane、session 状态等）**直接照下方词汇表给负载，一律禁用任何工具（Read/Grep/Glob 全不用）**——一轮工具调用用户就要多等 30 秒以上，词汇表没有的概念按最接近的常规 nvim 命令直译；仅当涉及项目事实参数（数据库连接、端口、账号、文件位置等）或词汇表没覆盖的配置细节才查实不臆测——优先让命令带 $(...) 现场取值（**$() 只在 :terminal/! 等 shell 上下文里展开**，纯 Ex 参数只认 $VAR 不做命令替换），$() 不可行时用只读工具（Read/Grep/Glob——项目根与配置目录已放行，Bash 仍会拒）查证。",
    "",
    string.format(
      "环境: nvim %d.%d | 项目根: %s（你的工作目录在别处，查项目文件用此绝对路径）| 配置目录: %s | buffer: %s (ft=%s) | tab数: %d",
      ver.major,
      ver.minor,
      vim.fn.getcwd(),
      vim.fn.stdpath("config"),
      bufname ~= "" and bufname or "[无名buffer]",
      vim.bo.filetype,
      #vim.api.nvim_list_tabpages()
    ),
  }
  -- 词汇表条件追加（concat 数组中间插 nil 会吞掉其后的行，故先散表后拼）
  if glossary ~= "" then
    ret[#ret + 1] = "——配置词汇表（本 nvim 私有概念的定义，涉及时照词条办事）：\n"
      .. glossary
  end
  ret[#ret + 1] = "用户请求: " .. query
  -- 提速关键行（2026-10-24 十二修实测）：GLM 输出 ~30 tok/s 计时计费，
  -- 模型会把 10KB 前导当设定而「等待请求」/长篇犹豫——明示单轮即时输出
  -- 后输出 token 1382→518，端到端 38.7s→18.5s（同 prompt 同 cwd 实测）
  ret[#ret + 1] =
    "不要再等待或确认，上面「用户请求」就是要翻译的那一条：第一行起直接输出负载，除负载外零输出。"
  return table.concat(ret, "\n")
end

-- 剥 markdown 围栏，取首个 cmd:/lua: 行起的整段（余行全收——提示词已锁
-- 「只回负载」，越界内容由先审后执兜住）
local function parse(out)
  local lines = {}
  for _, l in ipairs(vim.split(out, "\n", { trimempty = true })) do
    if not l:match("^%s*```") then
      lines[#lines + 1] = l
    end
  end
  for i, l in ipairs(lines) do
    local kind
    if l:sub(1, 4) == "cmd:" then
      kind = "cmd"
    elseif l:sub(1, 4) == "lua:" then
      kind = "lua"
    elseif l:sub(1, 4) == "say:" then
      kind = "say"
    end
    if kind then
      local rest = { vim.trim(l:sub(5)) }
      for j = i + 1, #lines do
        rest[#rest + 1] = lines[j]
      end
      return kind, vim.trim(table.concat(rest, "\n"))
    end
  end
end

local function execute(kind, body)
  local ok, err
  if kind == "cmd" then
    ok, err = pcall(function()
      vim.cmd(body)
    end)
  else
    local chunk = load(body)
    if chunk then
      ok, err = pcall(chunk)
    else
      ok, err = false, "lua 负载无法 load"
    end
  end
  if not ok then
    vim.api.nvim_echo({ { "AI ▸ Execute failed: " .. tostring(err), "ErrorMsg" } }, false, {})
  end
end

-- 输入框轮次（模块级单飞：nvim 单线程+离开即取消，天然无并发；gen 代
-- 计数防旧轮回调窜新轮）
local S = {
  gen = 0,
  phase = "idle",
  timer = nil,
  au = {},
  job = nil,
  left_at = nil,
  mode = false,
  mode_timer = nil,
  watching = false,
  t0 = nil, -- 本轮起点（绝对时间基准：色相流动/呼吸/冲击全部由它派生）
  fade_t0 = nil, -- 终态渐隐起点：tick 尾声 RB_FADE_MS 平滑回基线
  anim = nil, -- :AIAnim 预览轮标记
  anim_timer = nil, -- 预览 4s 定时器句柄（提前收场须停）
}

local function ui_present()
  return #vim.api.nvim_list_uis() > 0
end

-- 彩虹边框（2026-10-23 四修多色流动；五修终极形态：nui 的 border 本就是
-- 独立窗口，动窗体配置会双框、改 noice 配置被缓存击穿——最终直接在 nui
-- border 窗口的 buffer 上打自有命名空间的 extmark：边框字符是 nui 画的，
-- 我们只做原地染色，逐字符渐变、按 k 错位流动，窗体零手术=无双框。组
-- AiRainbow1..8 静态持调色板，收场清 extmark+清组；终态不染色（红圈
-- 试过 per-char/整块两条路都被 noice 异步重渲染清掉，弃——终态=边框回
-- 主题色、消息文本留框）
-- 彩虹色谱（2026-10-24 八修：Siri 色复刻，用户提供 GLSL）：cosine
-- palette（IQ 式 0.5+0.5*cos(2π(h+{0,.33,.67}))，相位三通道均分色轮）+
-- mix 白（珍珠高光）+ pow 0.7。48 采样 = 色轮离散化
--
-- 动效三段制（2026-10-24 九修，用户 spec）：唤起冲击（快攻慢衰+回弹涟漪）
-- → 持续呼吸（3.2s 正弦）→ 终态渐隐（RB_FADE_MS smoothstep 回基线）。强度 = 白混系
-- 数 w：w 越高越接近白热核心（峰值 ~0.9 近白闪，即 ANSI 侧的"白核"——像
-- 素级光晕交 ghostty bloom：亮度↑ 辉光自动扩张）。所有亮度均为绝对时间
-- 函数（不逐帧累加），色相流动与亮度呼吸独立参数
local RB_N = 48
local RB_2PI = 6.2831853
local RB_W_BASE = 0.38 -- 静息白混（八修定色，静态彩虹/呼吸基线）
local RB_W_MAX = 0.92 -- 峰值钳制（近白但留一丝色相）
local RB_WSTEP = 0.02 -- 亮度层距（2 RGB/层，呼吸扫层无可感台阶）
local RB_WLVL = 47 -- 亮度层数（0..0.92；层 21 = 基线 0.40，层 20 = 0.38）
local RB_FADE_MS = 300 -- 终态渐隐窗（tick 尾声当前强度→基线）
local LEFT_GRACE_MS = 300 -- waiting 期离框取消宽限（幽灵 Leave 裁决窗）

local function rb_mix_hex(i, w) -- i: 0..RB_N-1 色位，w: 白混系数 → "#rrggbb"
  local h = i / RB_N
  local r = 0.5 + 0.5 * math.cos(RB_2PI * (h + 0.0))
  local g = 0.5 + 0.5 * math.cos(RB_2PI * (h + 0.33))
  local b = 0.5 + 0.5 * math.cos(RB_2PI * (h + 0.67))
  -- 亮度硬约束：Rec.601 亮度须全采样 > 0.2（ghostty bloom.glsl 只给
  -- luma>0.2 的像素发光）。w ≥ 0.38 时最暗 0.659（3.3 倍余量）；渐隐段
  -- w→0 最暗 ~0.29 仍在线上——调 RB_W_BASE/RB_WSTEP 前先验算
  r = (r + (1 - r) * w) ^ 0.7
  g = (g + (1 - g) * w) ^ 0.7
  b = (b + (1 - b) * w) ^ 0.7
  return ("#%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local NS = vim.api.nvim_create_namespace("ai_cmd_rainbow")

-- 强度函数（绝对时间，秒）——spec §2：避免逐帧累加误差，全部 t 派生
local function rb_breath(t) -- 持续呼吸：3.2s 正弦（spec 周期 2.5-4s 取中）
  return 0.5 - 0.5 * math.cos(RB_2PI * t / 3.2)
end

local function rb_impact(t) -- 唤起冲击：快攻慢衰双指数（duang 主体）+ 7%
  -- 欠阻尼涟漪（回弹过冲 ~7%，阻尼感等价 spec 的 ζ≈0.65——不取真弹簧是
  -- 因欠阻尼脉冲会摆到负值=边框变暗闪烁，spec 明令禁止）
  if t <= 0 then
    return 0
  end
  local pulse = 1.777 * (math.exp(-t / 0.25) - math.exp(-t / 0.045)) -- 归一峰值 1.0 @~90ms
  local ripple = 0.07 * math.sin(RB_2PI * t / 0.28) * math.exp(-t / 0.30)
  return pulse * (1 + ripple)
end

local function rb_layer(w) -- 白混系数 → 亮度层号（钳制 1..RB_WLVL）
  return math.min(RB_WLVL, math.max(1, math.floor(w / RB_WSTEP) + 1))
end

local function rb_define() -- 组矩阵一次成型：亮度层×色相（47×48），流动/
  -- 呼吸/冲击只换层引用不重定义组（spec §4：不为动画重建窗口/重复建组）
  local lines = {}
  for li = 1, RB_WLVL do
    local w = (li - 1) * RB_WSTEP
    for i = 0, RB_N - 1 do
      lines[#lines + 1] = ("hi AiRainbow%d_%d guifg=%s"):format(li, i + 1, rb_mix_hex(i, w))
    end
  end
  vim.cmd(table.concat(lines, "\n"))
end

-- 提示词测试缝（同 report/default_review 惯例）：提速调参对照实验用
M._prompt = build_prompt
-- 动效数学测试缝（同 report/default_review 惯例）：headless 渲染不了动效，
-- 曲线形状/色值金值/选层落位/bloom 阈值在判据 13 断言
M._anim = {
  mix = rb_mix_hex,
  impact = rb_impact,
  breath = rb_breath,
  layer = rb_layer,
}

local function rb_text_win() -- noice cmdline 文字窗：zindex=200（views.lua 默认）
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg.relative ~= "" and cfg.zindex == 200 then
      local ok2, l1 = pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_win_get_buf(win), 0, 1, false)
      -- 字符级比较：Lua 的 [╭┌╔] 是字节类，⣿/⠋ 等 E2 系首字节全误命中
      local c1 = ok2 and vim.fn.strcharpart(l1[1] or "", 0, 1) or ""
      if ok2 and c1 ~= "╭" and c1 ~= "┌" and c1 ~= "╔" then
        return win
      end
    end
  end
end

local function rb_border_win(tw) -- nui border 窗：buffer 首行以左上角字符开头
  -- 的浮窗（几何判据试过：nui border 窗尺寸并非精确 +2，没命中）
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= tw then
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if ok and cfg.relative ~= "" then
        local ok2, l1 = pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_win_get_buf(win), 0, 1, false)
        local c1 = ok2 and vim.fn.strcharpart(l1[1] or "", 0, 1) or ""
        if ok2 and (c1 == "╭" or c1 == "┌" or c1 == "╔") then
          return win
        end
      end
    end
  end
end

local function rb_targets() -- 文字窗+border 窗 {buf,w,h}；缺一即 nil
  local tw = rb_text_win()
  if not tw then
    return nil
  end
  local bwin = rb_border_win(tw)
  if not bwin then
    return nil
  end
  return {
    buf = vim.api.nvim_win_get_buf(bwin),
    w = vim.api.nvim_win_get_width(bwin),
    h = vim.api.nvim_win_get_height(bwin),
  }
end

local function rb_paint(elapsed, fade) -- 沿周长逐字符渐变。elapsed=本轮秒
  -- （nil=静态基准层，输入期）；fade=0..1 渐隐进度（终态尾声）。颜色按
  -- buffer 实际内容染：非空格字符逐个上色（几何假设归零——行长短于窗宽
  -- 时几何周长会染空）。色相沿周长序分布（顺时针：上 L→R → 右 T→B →
  -- 下 R→L → 左 B→T）= fract(u + elapsed/6) 绕框循环流动（6s/圈，旧
  -- 16.7s 太缓配不上呼吸）；亮度按 elapsed 选层（冲击→呼吸）
  local t = rb_targets()
  if not t or t.w < 2 or t.h < 2 then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, t.buf, NS, 0, -1)
  local e = elapsed or 0
  local function intensity()
    return math.min(RB_W_MAX, RB_W_BASE + 0.5 * rb_impact(e) + 0.08 * rb_breath(e))
  end
  local w
  if fade then
    -- 渐隐=当前强度平滑回基线（spec §4「先平滑结束冲击状态，再转入空
    -- 闲」）。不落亚基线：w<0.38 是高饱和低亮度区（用户终态色病报告），
    -- 基线→主题色的收尾切变是八修既定行为
    local cur, s = intensity(), fade * fade * (3 - 2 * fade)
    w = cur + (RB_W_BASE - cur) * s
  elseif elapsed then
    w = intensity()
  else
    w = RB_W_BASE
  end
  local li = rb_layer(w)
  local P = 2 * t.w + 2 * t.h - 4 -- 周长字符数
  local function ring_group(r, c)
    local p
    if r == 0 then
      p = c
    elseif c == t.w - 1 then
      p = t.w - 1 + r
    elseif r == t.h - 1 then
      p = t.w + t.h - 2 + (t.w - 1 - c)
    else
      p = 2 * t.w + t.h - 3 + (t.h - 1 - r)
    end
    local h = (p / P + e / 6) % 1 -- fract(u + elapsed/6)
    return li .. "_" .. (math.floor(h * RB_N) + 1)
  end
  for r, line in ipairs(vim.api.nvim_buf_get_lines(t.buf, 0, -1, false)) do
    local n = vim.fn.strchars(line)
    for ci = 0, n - 1 do
      if vim.fn.strcharpart(line, ci, 1) ~= " " then
        pcall(vim.api.nvim_buf_set_extmark, t.buf, NS, r - 1, vim.fn.byteidx(line, ci), {
          end_line = r - 1,
          end_col = vim.fn.byteidx(line, ci) + 1,
          hl_group = "AiRainbow" .. ring_group(r - 1, ci),
          priority = 65534,
        })
      end
    end
  end
  vim.cmd("redraw") -- 观察者路径（输入期静态染色）同拍可见
end

local function rb_reset() -- 收场：只清自有 extmark。组不清——hi clear 会
  -- 在与 run()/观察者的时序竞争里把已定义的组清掉（extmark 无色，PTY 实
  -- 证），组常驻定义无害（仅被我们的 extmark 引用）
  local t = rb_targets()
  if t then
    pcall(vim.api.nvim_buf_clear_namespace, t.buf, NS, 0, -1)
  end
end

local function kill_job() -- 杀在跑的 claude（防御式：句柄可空/已死）
  if S.job then
    pcall(function()
      S.job:kill(9)
    end)
    S.job = nil
  end
end

local function ui_teardown() -- 停进度 tick（边框/事件桩留给收场或终态接管）
  if S.timer then
    vim.fn.timer_stop(S.timer)
    S.timer = nil
  end
end

local function ui_cleanup() -- 收场：停 tick、还原图谱、撤事件桩
  ui_teardown()
  if S.mode_timer then
    vim.fn.timer_stop(S.mode_timer)
    S.mode_timer = nil
  end
  if S.keyns then
    pcall(vim.on_key, nil, S.keyns)
    S.keyns = nil
  end
  rb_reset()
  for _, id in ipairs(S.au) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  S.au = {}
  S.fade_t0 = nil
  S.anim = nil
  if S.anim_timer then
    vim.fn.timer_stop(S.anim_timer)
    S.anim_timer = nil
  end
  S.phase = "idle"
end

-- 输入框开合不缓存事件标志（S.open 曾因 Enter/Leave 时序丢帧致播报误落
-- echo 分支，PTY 间歇复现）——一律现查真实状态
local function cmdline_open()
  return vim.fn.mode(1):sub(1, 1) == "c"
end

-- 等待期 cmdline 文本（英文文案、不回显原请求、无前缀——用户裁决
-- 2026-10-23 三修+七修：旧 `:"` Ex 注释前缀无视觉作用已删，误回车代价
-- =一次 E492+取消，可接受）
local function spin_text(s, el)
  return s .. string.format(" Translating… %4.1fs (ESC to cancel)", el)
end

-- 缺省审查形态（模块字段 = 测试缝，可整体替换）：**复用 ':' 本尊**（用户
-- 裁决 2026-10-21 三修）——2026-10-23 二修：进度本就在输入框里，完成不
-- 换面，setcmdline 原地变身负载单行（cmd 原样、lua 加前缀），原生编辑，
-- Enter 即原生执行，Esc 原生弃；on_ok 不回。输入框已离开（理论竞态兜
-- 底）退 feedkeys 预填
function M.default_review(kind, body, on_ok)
  local line = M.review_line(kind, body)
  if cmdline_open() then
    pcall(vim.fn.setcmdline, line)
  else
    vim.fn.feedkeys(":" .. line, "n")
  end
end

-- 负载 → 可单行预填的 cmdline 文本：cmd 行间并 " | "；lua 加 lua 前缀、
-- 行间并 "; "（分号是 lua 合法语句分隔）
function M.review_line(kind, body)
  local lines = vim.split(body, "\n", { trimempty = true })
  if kind == "lua" then
    return "lua " .. table.concat(lines, "; ")
  end
  return table.concat(lines, " | ")
end

-- 播报缝（模块字段 = 测试缝，同 default_review）：缺省落输入框，终态留
-- 框待 Esc 收（`:"` 注释前缀已随七修删除，回车=E492 一次，不再邀请）、
-- 瞬态由进度 tick 覆盖；输
-- 入框不在（无 UI/已离开/headless）退 cmdline echo。测试覆写收集文本，
-- 判据只断言文本本身
function M.report(text, terminal)
  local one = text:gsub("\n", " / "):gsub("|", "¦"):gsub("^AI ▸ ", "")
  local line = one .. (terminal and " (ESC to close)" or "")
  if not ui_present() then
    vim.api.nvim_echo({ { text, terminal and "ErrorMsg" or "WarningMsg" } }, false, {})
    return
  end
  if cmdline_open() then
    pcall(vim.fn.setcmdline, line) -- 异文驱动重绘（PTY 实证）
  elseif terminal and S.phase == "done" then
    -- 框被超时杀连坐关闭（nvim 级现象，PTY 实证：timeout 瞬间 mode 已翻
    -- n 且无 Leave/Cancel——最小探针洗清 vim.system，死因在全量配置联动
    -- 未究）：重开输入框落终态
    vim.fn.feedkeys(":" .. line, "n") -- 重开框必须带 ":" 打开命令行
  else
    vim.api.nvim_echo({ { text, terminal and "ErrorMsg" or "WarningMsg" } }, false, {})
  end
end

-- 输入框轮次起手（run 与 :AIAnim 共用）：静态彩虹 timer 交棒、组矩阵、
-- 吞 CR、tick 装配。tick 三分支：waiting=spinner+动效；done+渐隐中=白混
-- smoothstep 回基线后收场；waiting 期离框 LEFT_GRACE_MS=真取消
local function ui_enter()
  if S.phase ~= "idle" then -- 防御：上一轮未收场
    kill_job()
    ui_cleanup()
  end
  S.phase = "waiting"
  S.mode = false
  S.t0 = vim.uv.now()
  if S.mode_timer then -- 静态彩虹 timer 交棒给执行动效 tick
    vim.fn.timer_stop(S.mode_timer)
    S.mode_timer = nil
  end
  rb_define()
  -- 吞掉框内回车（纯展示无提交语义，误触零代价且不取消运行）；审查框在
  -- 拆 on_key / ui_cleanup 后 CR 原生提交不受影响
  S.keyns = vim.on_key(function(key)
    if key == "\r" and (S.phase == "waiting" or S.phase == "done") then
      return ""
    end
  end)
  vim.fn.feedkeys(":" .. spin_text("⠋", 0), "n") -- ":" 打开命令行
  S.au[#S.au + 1] = vim.api.nvim_create_autocmd("CmdlineLeave", {
    callback = function()
      if S.phase == "waiting" then
        -- Leave ≠ 一定是用户取消：框被超时杀连坐关闭时 nvim 同样发
        -- Leave（PTY 实证）。cancel-defer 与超时收尾回调是两条异步线，
        -- defer 先跑会误杀自愈 tick（三连败案）——改记时间戳，裁决挪进
        -- tick（LEFT_GRACE_MS 宽限），超时收尾一停 tick 即关闭取消窗口
        S.left_at = vim.uv.now()
      elseif S.phase == "done" then
        ui_cleanup() -- 终态框的正常收放（渐隐提前剪断，幂等）
      end
    end,
  })
  local spin = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local tick = 0
  S.timer = vim.fn.timer_start(80, function()
    tick = tick + 1
    -- 整体 pcall：timer 回调抛错会让 recurring timer 静默停摆，窗体死亡
    -- 竞态的 Invalid 一律吞掉
    pcall(function()
      if S.phase == "waiting" then
        if cmdline_open() then
          S.left_at = nil -- 重开/仍在框：取消窗口作废
          pcall(vim.fn.setcmdline, spin_text(spin[tick % #spin + 1], (vim.uv.now() - S.t0) / 1000))
          rb_paint((vim.uv.now() - S.t0) / 1000) -- setcmdline 后染色：noice 同拍重渲染先落，extmark 垫后
        elseif S.left_at and vim.uv.now() - S.left_at > LEFT_GRACE_MS then
          -- 真取消：框关了超过宽限还没回来，且收尾回调没来（phase 仍 waiting）
          S.left_at = nil
          kill_job()
          ui_cleanup()
          vim.api.nvim_echo({ { "AI ▸ Canceled", "Comment" } }, false, {})
        end
      elseif S.phase == "done" and S.fade_t0 then
        -- 终态渐隐（spec §4）：当前强度 smoothstep 回基线（不落亚基线——
        -- w<0.38 高饱和低亮度，终态色病根），落定 rb_reset 回主题色。框
        -- 已关（超时连坐/Esc）立收，不空转
        if cmdline_open() then
          local f = (vim.uv.now() - S.fade_t0) / RB_FADE_MS
          if f >= 1 then
            ui_cleanup()
          else
            rb_paint((vim.uv.now() - S.t0) / 1000, f)
          end
        else
          ui_cleanup()
        end
      end
    end)
  end, { ["repeat"] = -1 })
end

-- opts.review(kind, body, on_ok)：单次审查覆盖；opts.fresh=true 重置链
-- 再问（:AI!）；opts._retried 预置已重试标记（防循环）
function M.run(query, opts)
  opts = opts or {}
  local review = opts.review or M.default_review
  local timeout_ms = vim.g.ai_cmd_timeout or 45000 -- 测试缝+慢查调档（毫秒）
  local cwd = vim.fn.stdpath("run") .. "/ai-cmd"
  vim.fn.mkdir(cwd, "p")
  local sid = nil
  if not opts.fresh then
    sid = chain_load()
  end -- 勿写成 fresh and nil or …（and/or 旁路陷阱）
  local retried = opts._retried -- 链失效自愈上限一次

  -- 输入框接管（2026-10-23 二修）：无 UI（headless）整段跳过=纯逻辑路径
  if ui_present() then
    ui_enter()
  end
  S.gen = S.gen + 1 -- 换代：旧轮回调 gen 失配自灭
  local gen = S.gen

  -- stderr 提纯：头部是常驻噪音（[claude-code:unrecognized_model]=非官方
  -- 模型 ID 的登记警告，GLM 包装用户恒有、无害且曾经误导「耗时久=模型名
  -- 错」的诊断；no-stdin 提示随 stdin 关闭消失），真错误落尾部——从尾按
  -- 行收集到预算为止（noice cmdline 本就保尾截头）
  local function claude_err(res)
    local lines = {}
    for _, l in ipairs(vim.split(res.stderr or "", "\n")) do
      local noise = l:find("[claude-code:unrecognized_model]", 1, true) or l:find("^Warning: no stdin data")
      if not noise and l:match("%S") then
        lines[#lines + 1] = l
      end
    end
    local out, budget = {}, 180
    for i = #lines, 1, -1 do
      local w = #(out[1] or "") + #lines[i] + 3
      if out[1] and w > budget then
        break
      end
      table.insert(out, 1, lines[i])
    end
    return table.concat(out, " ⏎ ") ~= "" and table.concat(out, " ⏎ ") or "(stderr 仅噪音，无有效信息)"
  end

  local function attempt()
    -- --add-dir 必须等号连写：claude 2.x 它是变长参数，分写会吞掉后面的
    -- prompt 当目录（真机 2.1.281 + GLM 包装后端双实证「缺输入」报错）
    local argv = {
      bin(),
      "-p",
      "--strict-mcp-config",
      "--output-format",
      "json",
      "--add-dir=" .. vim.fn.getcwd(), -- 放行项目根只读查证（头注 2026-10-23 案）
    }
    if sid then
      argv[#argv + 1], argv[#argv + 2] = "-r", sid
    end
    if vim.g.ai_cmd_model then
      argv[#argv + 1], argv[#argv + 2] = "--model", vim.g.ai_cmd_model
    end
    argv[#argv + 1] = build_prompt(query)
    -- stdin 必须显式关闭：悬空时 CLI 干等 3s 才放弃读（十二修实测
    -- 5.1s→2.1s，快路径一半延迟；stderr 的 no-stdin 警告也同源）
    S.job = vim.system(argv, { text = true, cwd = cwd, timeout = timeout_ms, stdin = "" }, function(res)
      vim.schedule(function()
        if gen ~= S.gen or S.phase == "canceled" then
          return
        end
        -- vim.system 超时杀实测（0.12.6 探针）无 timeout 字段，呈
        -- code=124+SIGTERM(15)——判超时须认这个形状，res.timeout 留作前向兼容
        local function terminal_state(msg)
          -- 终态统一出口：消息留框，边框交 tick RB_FADE_MS 平滑回基线再落主题色
          -- （旧即时 rb_reset 是从亮彩虹硬切主题色；框已死者 tick 下一拍
          -- 立收不等）。红圈曾试过 per-char/整块两条路，extmark 都被 noice
          -- 的 schedule 异步行重写清掉——用户裁决简单实现，弃红圈只留文本
          S.phase = "done"
          S.fade_t0 = vim.uv.now()
          M.report(msg, true)
        end
        if res.timeout or (res.code == 124 and res.signal == 15) then
          -- 超时≠链失效：不动链不自动重试，报明可直接重试。文案须短——
          -- noice cmdline 保尾截头（光标在尾），头部超宽会被截掉
          terminal_state("AI ▸ Timeout (" .. timeout_ms .. "ms) — retry freely")
          return
        end
        if res.code ~= 0 then
          if sid and not retried then -- 链失效（transcript 被清等）：重开一次
            M.reset()
            sid = nil
            retried = true
            M.report("AI ▸ Chain broken — reopened a fresh chain", false) -- 瞬态：tick 随即覆盖
            attempt() -- phase 保持 waiting，进度接着走
            return
          end
          terminal_state("AI ▸ claude failed: " .. claude_err(res) .. " (code=" .. tostring(res.code) .. ")")
          return
        end
        local ok, obj = pcall(vim.json.decode, res.stdout or "")
        if not ok or type(obj) ~= "table" or not obj.session_id then
          terminal_state("AI ▸ Output is not JSON (not executed):\n" .. (res.stdout or ""):sub(1, 400))
          return
        end
        chain_save(obj.session_id)
        local kind, body = parse(obj.result or "")
        if not kind then
          terminal_state("AI ▸ Unparseable result (not executed):\n" .. (obj.result or ""):sub(1, 400))
          return
        end
        if kind == "say" then
          -- 闲聊直答（用户裁决 2026-10-24 十修）：不审不执——审查护的是执
          -- 行，say 无执行；文本落框即终态（回车由 on_key 吞，Esc 收框）。
          -- 空 say: 视同翻译失败
          if vim.trim(body) == "" then
            terminal_state("AI ▸ Empty reply")
          else
            S.phase = "done"
            S.fade_t0 = vim.uv.now()
            M.report(body, true)
          end
          return
        end
        S.phase = "done"
        S.fade_t0 = vim.uv.now() -- 渐隐 RB_FADE_MS：审查框短暂披余韵再落主题色
        -- 审查框 CR 必须原生提交：吞 CR 的 on_key 此刻先拆（feedkeys 排队
        -- 键在事件循环处理，迟拆会吞掉提交）；ui_cleanup 押给渐隐尾声，
        -- Esc 提前离开由 CmdlineLeave 兜底
        pcall(vim.on_key, nil, S.keyns)
        S.keyns = nil
        review(kind, body, function(edited)
          if edited and edited:find("%S") then
            execute(kind, vim.trim(edited))
          else
            vim.api.nvim_echo({ { "AI ▸ Canceled", "Comment" } }, false, {})
          end
        end)
      end)
    end)
  end
  attempt()
end

function M.setup()
  -- AI 模式边框隐喻观察者（用户裁决 2026-10-23 六修）：输入 `:AI…` 即静
  -- 态彩虹，回车执行转流动（run 的 tick），成功/离开回主题色。**注册必须
  -- 晚于 noice**：autocmd 按注册序执行，本观察者同步染色要落在 noice 渲
  -- 染之后才不被行重写清掉（PTY 实证：注册早于 noice 时输入期零染色）。
  -- noice 已载则现注册；未载（极早输入）则首个 CmdlineEnter（彼时 noice
  -- 必已载入渲染）时补注册。轮次进行中（phase≠idle）由 run 的 tick 全权
  -- 负责，本观察者让位
  local function mode_stop() -- 停静态彩虹 timer 并复位
    if S.mode_timer then
      vim.fn.timer_stop(S.mode_timer)
      S.mode_timer = nil
    end
    rb_reset()
  end

  local function rb_watchers()
    if S.watching then
      return
    end
    S.watching = true
    vim.api.nvim_create_autocmd("CmdlineChanged", {
      callback = function()
        if S.phase ~= "idle" then
          return
        end
        local ok, line = pcall(vim.fn.getcmdline)
        if ok and line:match("^AI") then
          if not S.mode then
            S.mode = true
            rb_define()
            -- 静态彩虹也走 timer：autocmd 上下文的染色必被 noice 随后的
            -- 渲染清掉（PTY 多轮实证），timer 上下文每拍必胜（与等待期
            -- 流动同构）
            S.mode_timer = vim.fn.timer_start(80, function()
              pcall(rb_paint) -- 静态基准层（无 elapsed=不流动不呼吸，八修定色）
            end, { ["repeat"] = -1 })
          end
        elseif S.mode then
          S.mode = false
          mode_stop()
        end
      end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
      callback = function()
        if S.phase == "idle" and S.mode then
          S.mode = false
          mode_stop()
        end
      end,
    })
  end
  local ok_noice = pcall(require, "noice.config")
  if ok_noice then
    rb_watchers()
  else
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      once = true,
      callback = function()
        vim.schedule(rb_watchers)
      end,
    })
  end
  vim.api.nvim_create_user_command("AI", function(o)
    local args = vim.trim(o.args or "")
    if args == "" then
      M.report("AI ▸ Missing query — usage: :AI <natural language> (e.g. :AI open mysql in a new tab)", true)
      return
    end
    M.run(args, { fresh = o.bang })
  end, {
    nargs = "*",
    bang = true,
    desc = "自然语言 → nvim 操作（claude -p 续链，可编辑审查；! 重置链）",
  })
  -- 动效预览（spec §4 手动测试缝）：跑完整 UI 轮次生命周期（spinner+冲
  -- 击→呼吸→渐隐收场）但不调 claude，4s 后假终态落框。Esc 中途取消走
  -- waiting 期原生取消路径
  vim.api.nvim_create_user_command("AIAnim", function()
    if not ui_present() or S.phase ~= "idle" then
      return
    end
    ui_enter()
    S.anim = true
    S.anim_timer = vim.fn.timer_start(4000, function()
      if S.anim and S.phase == "waiting" then
        S.anim = nil
        S.fade_t0 = vim.uv.now()
        S.phase = "done"
        M.report("AI ▸ Animation preview — impact, breath and fade all fired", true)
      end
    end)
  end, { desc = ":AI 动效预览（冲击/呼吸/渐隐，不调 claude）" }) -- 句柄入 S.anim_timer：ui_cleanup 统一停（spec §4 不遗留定时器）
  -- 入口五变体（用户裁决）：a/A/ai/Ai/aI 经带守卫缩写归一成 :AI 文本——
  -- :a query / :a! 即 :AI query / :AI!（词内续打如 :args 不触发，缩写只在
  -- 非词字符跟上时炸；裸 CR 也展开，PTY 实测，headless feedkeys 假阴勿信；
  -- :append 让位）
  for _, tok in ipairs({ "a", "A", "ai", "Ai", "aI" }) do
    vim.cmd(("cnoreabbrev <expr> %s getcmdtype() ==# ':' && getcmdline() ==# '%s' ? 'AI' : '%s'"):format(tok, tok, tok))
  end
end

return M
