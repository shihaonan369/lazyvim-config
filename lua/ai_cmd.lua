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
  return table.concat({
    "你是 Neovim 操作翻译器：把用户请求转成 nvim 操作，只回负载本身，不要解释、不要 markdown 围栏。",
    "第一行起就是以下两种格式之一：",
    "cmd:<Ex 命令>（多命令用 | 或换行分隔，每行一条）",
    "lua:<lua 代码>（vim.cmd/vim.api/vim.fn 可用，可多行）",
    "翻译规则：优先 cmd:；打开外部程序 = 终端（如新 tab: $tabnew | terminal mysql）；生成的操作只作用于当前 nvim 实例，不写文件系统。",
    "调查分档（用户裁决 2026-10-21）：纯操作类请求（开 tab、分屏、切换、关闭等，不依赖项目事实）**不查文件**，直接给负载；仅当涉及事实参数（数据库连接、端口、账号、文件位置等）才查实不臆测——优先让命令带 $(...) 现场取值（**$() 只在 :terminal/! 等 shell 上下文里展开**，纯 Ex 参数只认 $VAR 不做命令替换），$() 不可行时用只读工具（Read/Grep/Glob——项目根已放行，Bash 仍会拒）查项目文件确认。",
    "",
    string.format(
      "环境: nvim %d.%d | 项目根: %s（你的工作目录在别处，查项目文件用此绝对路径）| buffer: %s (ft=%s) | tab数: %d",
      ver.major,
      ver.minor,
      vim.fn.getcwd(),
      bufname ~= "" and bufname or "[无名buffer]",
      vim.bo.filetype,
      #vim.api.nvim_list_tabpages()
    ),
    "用户请求: " .. query,
  }, "\n")
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

-- 输入框会话（模块级单飞：nvim 单线程+离开即取消，天然无并发；gen 代
-- 计数防旧会话回调窜新会话）
local S = { gen = 0, phase = "idle", timer = nil, au = {}, job = nil, left_at = nil }

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
local RAINBOW = {
  "#ff5f6d",
  "#ffa751",
  "#ffd56b",
  "#38ef7d",
  "#18dcff",
  "#7d5fff",
  "#c56cf0",
  "#ff6b81",
}
local NS = vim.api.nvim_create_namespace("ai_cmd_rainbow")

local function rb_define() -- 组静态持色（流动靠 extmark 错位，不靠改组）
  for i, c in ipairs(RAINBOW) do
    pcall(vim.cmd, ("hi AiRainbow%d guifg=%s"):format(i, c))
  end
end

local function rb_text_win() -- noice cmdline 文字窗：zindex=200（views.lua 默认）
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg.relative ~= "" and cfg.zindex == 200 then
      local ok2, l1 = pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_win_get_buf(win), 0, 1, false)
      if ok2 and not (l1[1] or ""):match("^[╭┌╔]") then
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
        if ok2 and (l1[1] or ""):match("^[╭┌╔]") then
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

local function rb_paint(k) -- 沿周长逐字符渐变：pos 偏移 k 取组 → 颜色流动
  local t = rb_targets()
  if not t or t.w < 2 or t.h < 2 then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, t.buf, NS, 0, -1)
  local function mark(line, col, g)
    pcall(vim.api.nvim_buf_set_extmark, t.buf, NS, line, col, {
      end_line = line,
      end_col = col + 1,
      hl_group = "AiRainbow" .. g,
      priority = 65534,
    })
  end
  for col = 0, t.w - 1 do -- 上 L→R
    mark(0, col, (k + col) % 8 + 1)
  end
  for row = 1, t.h - 2 do -- 右 T→B
    mark(row, t.w - 1, (k + t.w - 1 + row) % 8 + 1)
  end
  for col = 0, t.w - 1 do -- 下 L→R（续 pos）
    mark(t.h - 1, col, (k + t.w + t.h - 1 + col) % 8 + 1)
  end
  for row = 1, t.h - 2 do -- 左 T→B（续 pos）
    mark(row, 0, (k + 2 * t.w + t.h - 2 + row) % 8 + 1)
  end
end

local function rb_reset() -- 收场：只清自有 extmark。组不清——hi clear 会
  -- 在与 run()/观察者的时序竞争里把已定义的组清掉（extmark 无色，PTY 实
  -- 证），组常驻定义无害（仅被我们的 extmark 引用）
  local t = rb_targets()
  if t then
    pcall(vim.api.nvim_buf_clear_namespace, t.buf, NS, 0, -1)
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
  rb_reset()
  for _, id in ipairs(S.au) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  S.au = {}
  S.phase = "idle"
end

-- 输入框开合不缓存事件标志（S.open 曾因 Enter/Leave 时序丢帧致播报误落
-- echo 分支，PTY 间歇复现）——一律现查真实状态
local function cmdline_open()
  return vim.fn.mode(1):sub(1, 1) == "c"
end

-- 等待期 cmdline 文本：":" 打头=Ex 注释行，误回车=no-op（英文文案、不
-- 回显原请求——用户裁决 2026-10-23 三修）
local function spin_text(s, el)
  return ':"' .. s .. string.format(" AI ▸ Translating… %4.1fs (ESC to cancel)", el)
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

-- 播报缝（模块字段 = 测试缝，同 default_review）：缺省落输入框——':' 注
-- 释行（误回车=no-op），终态留框待回车/Esc 收、瞬态由进度 tick 覆盖；输
-- 入框不在（无 UI/已离开/headless）退 cmdline echo。测试覆写收集文本，
-- 判据只断言文本本身
function M.report(text, terminal)
  local one = text:gsub("\n", " / "):gsub("|", "¦")
  local line = ':"' .. one .. (terminal and " (ENTER/ESC to close)" or "")
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
    vim.fn.feedkeys(":" .. line, "n")
  else
    vim.api.nvim_echo({ { text, terminal and "ErrorMsg" or "WarningMsg" } }, false, {})
  end
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
    if S.phase ~= "idle" then -- 防御：上一会话未收场
      if S.job then
        pcall(function()
          S.job:kill(9)
        end)
      end
      ui_cleanup()
    end
    S.phase = "waiting"
    rb_define()
    vim.fn.feedkeys(spin_text("⠋", 0), "n")
    S.au[#S.au + 1] = vim.api.nvim_create_autocmd("CmdlineLeave", {
      callback = function()
        if S.phase == "waiting" then
          -- Leave ≠ 一定是用户取消：框被超时杀连坐关闭时 nvim 同样发
          -- Leave（PTY 实证）。cancel-defer 与超时收尾回调是两条异步线，
          -- defer 先跑会误杀自愈 tick（三连败案）——改记时间戳，裁决挪进
          -- tick（300ms 宽限），超时收尾一停 tick 即关闭取消窗口
          S.left_at = vim.uv.now()
        elseif S.phase == "done" then
          ui_cleanup() -- 终态框的正常收放
        end
      end,
    })
    local spin = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    local start, tick = vim.uv.now(), 0
    S.timer = vim.fn.timer_start(80, function()
      tick = tick + 1
      -- 整体 pcall：timer 回调抛错会让 recurring timer 静默停摆，窗体死亡
      -- 竞态的 Invalid 一律吞掉
      pcall(function()
        if S.phase == "waiting" then
          if cmdline_open() then
            S.left_at = nil -- 重开/仍在框：取消窗口作废
            pcall(vim.fn.setcmdline, spin_text(spin[tick % #spin + 1], (vim.uv.now() - start) / 1000))
            rb_paint(tick) -- setcmdline 后染色：noice 同拍重渲染先落，extmark 垫后
          elseif S.left_at and vim.uv.now() - S.left_at > 300 then
            -- 真取消：框关了 300ms 还没回来，且收尾回调没来（phase 仍 waiting）
            S.left_at = nil
            if S.job then
              pcall(function()
                S.job:kill(9)
              end)
            end
            ui_cleanup()
            vim.api.nvim_echo({ { "AI ▸ Canceled", "Comment" } }, false, {})
          end
        end
      end)
    end, { ["repeat"] = -1 })
  end
  S.gen = S.gen + 1 -- 换代：旧会话回调 gen 失配自灭
  local gen = S.gen

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
    S.job = vim.system(argv, { text = true, cwd = cwd, timeout = timeout_ms }, function(res)
      vim.schedule(function()
        if gen ~= S.gen or S.phase == "canceled" then
          return
        end
        -- vim.system 超时杀实测（0.12.6 探针）无 timeout 字段，呈
        -- code=124+SIGTERM(15)——判超时须认这个形状，res.timeout 留作前向兼容
        local function terminal_state(msg)
          -- 终态统一出口：停 tick、边框回主题色、消息留框（红圈试过
          -- per-char/整块两条路，extmark 都被 noice 的 schedule 异步行重写
          -- 清掉——用户裁决简单实现，弃红圈只留文本）
          S.phase = "done"
          ui_teardown()
          rb_reset()
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
          terminal_state(
            "AI ▸ claude failed: " .. (res.stderr or ""):sub(1, 150) .. " (code=" .. tostring(res.code) .. ")"
          )
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
        S.phase = "done"
        ui_teardown() -- 停 tick；cleanup 押后——审查要现查 cmdline 开合判定 setcmdline/feedkeys
        rb_reset() -- 组色先归默认：审查负载框不披彩虹
        review(kind, body, function(edited)
          if edited and edited:find("%S") then
            execute(kind, vim.trim(edited))
          else
            vim.api.nvim_echo({ { "AI ▸ Canceled", "Comment" } }, false, {})
          end
        end)
        ui_cleanup() -- 收在审查落定之后：图谱还原、撤桩
      end)
    end)
  end
  attempt()
end

function M.setup()
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
        end
        -- schedule 落染：本观察者注册早于 noice，同步染色会被 noice 随后
        -- 的行重写清掉；排到其渲染之后即胜
        vim.schedule(function()
          rb_paint(0)
        end)
      elseif S.mode then
        S.mode = false
        vim.schedule(rb_reset)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    callback = function()
      if S.phase == "idle" and S.mode then
        S.mode = false
        rb_reset()
      end
    end,
  })
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
  -- 入口五变体（用户裁决）：a/A/ai/Ai/aI 经带守卫缩写归一成 :AI 文本——
  -- :a query / :a! 即 :AI query / :AI!（词内续打如 :args 不触发，缩写只在
  -- 非词字符跟上时炸；裸 CR 也展开，PTY 实测，headless feedkeys 假阴勿信；
  -- :append 让位）
  for _, tok in ipairs({ "a", "A", "ai", "Ai", "aI" }) do
    vim.cmd(("cnoreabbrev <expr> %s getcmdtype() ==# ':' && getcmdline() ==# '%s' ? 'AI' : '%s'"):format(tok, tok, tok))
  end
end

return M
