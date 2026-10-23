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
-- UI 桩整体跳过

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
    vim.api.nvim_echo({ { "AI ▸ 执行失败: " .. tostring(err), "ErrorMsg" } }, false, {})
  end
end

-- 输入框会话（模块级单飞：nvim 单线程+离开即取消，天然无并发；gen 代
-- 计数防旧会话回调窜新会话）
local S = { gen = 0, phase = "idle", open = false, timer = nil, au = {}, job = nil }

local function ui_present()
  return #vim.api.nvim_list_uis() > 0
end

local function ui_teardown() -- 停 tick、撤事件桩（cmdline 内容留给用户收）
  if S.timer then
    vim.fn.timer_stop(S.timer)
    S.timer = nil
  end
  for _, id in ipairs(S.au) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  S.au = {}
end

-- 等待期 cmdline 文本：":" 打头=Ex 注释行，误回车=no-op；"|" 换 ¦ 防
-- 误回车吃到注释后的追加命令
local function spin_text(s, el, query)
  return ':"' .. s .. string.format(" AI ▸ 翻译中… %4.1fs（ESC 取消） ", el) .. query:gsub("|", "¦")
end

-- 缺省审查形态（模块字段 = 测试缝，可整体替换）：**复用 ':' 本尊**（用户
-- 裁决 2026-10-21 三修）——2026-10-23 二修：进度本就在输入框里，完成不
-- 换面，setcmdline 原地变身负载单行（cmd 原样、lua 加前缀），原生编辑，
-- Enter 即原生执行，Esc 原生弃；on_ok 不回。输入框已离开（理论竞态兜
-- 底）退 feedkeys 预填
function M.default_review(kind, body, on_ok)
  local line = M.review_line(kind, body)
  if S.open then
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
  if ui_present() and S.open then
    local one = text:gsub("\n", " / "):gsub("|", "¦")
    pcall(vim.fn.setcmdline, ':"' .. one .. (terminal and "（回车/Esc 关闭）" or ""))
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
    ui_teardown() -- 防御：清上一会话残留桩
    if S.job then
      pcall(function()
        S.job:kill(9)
      end)
    end
    S.phase = "waiting"
    S.open = false
    vim.fn.feedkeys(spin_text("⠋", 0, query), "n")
    S.au[#S.au + 1] = vim.api.nvim_create_autocmd("CmdlineEnter", {
      callback = function()
        S.open = true
      end,
    })
    S.au[#S.au + 1] = vim.api.nvim_create_autocmd("CmdlineLeave", {
      callback = function()
        S.open = false
        if S.phase == "waiting" then -- 提前离开=取消
          S.phase = "canceled"
          ui_teardown()
          if S.job then
            pcall(function()
              S.job:kill(9)
            end)
          end
          vim.api.nvim_echo({ { "AI ▸ 已取消", "Comment" } }, false, {})
        end
      end,
    })
    local spin = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    local start, tick = vim.uv.now(), 0
    S.timer = vim.fn.timer_start(80, function()
      if S.phase == "waiting" and S.open then
        tick = tick + 1
        pcall(vim.fn.setcmdline, spin_text(spin[tick % #spin + 1], (vim.uv.now() - start) / 1000, query))
      end
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
        if res.timeout or (res.code == 124 and res.signal == 15) then
          -- 超时≠链失效：不动链不自动重试，报明可直接重试
          S.phase = "done"
          ui_teardown()
          M.report(
            "AI ▸ 翻译超时（"
              .. timeout_ms
              .. "ms）——链未动可直接重试；偏慢可设 vim.g.ai_cmd_timeout",
            true
          )
          return
        end
        if res.code ~= 0 then
          if sid and not retried then -- 链失效（transcript 被清等）：重开一次
            M.reset()
            sid = nil
            retried = true
            M.report("AI ▸ 续链失效，已重开新链", false) -- 瞬态：tick 随即覆盖
            attempt() -- phase 保持 waiting，进度接着走
            return
          end
          S.phase = "done"
          ui_teardown()
          M.report(
            "AI ▸ claude 调用失败 (code=" .. tostring(res.code) .. "): " .. (res.stderr or ""):sub(1, 200),
            true
          )
          return
        end
        S.phase = "done"
        ui_teardown() -- 停 tick：输入框内容交给审查接管
        local ok, obj = pcall(vim.json.decode, res.stdout or "")
        if not ok or type(obj) ~= "table" or not obj.session_id then
          M.report("AI ▸ 输出非 JSON（不执行）:\n" .. (res.stdout or ""):sub(1, 400), true)
          return
        end
        chain_save(obj.session_id)
        local kind, body = parse(obj.result or "")
        if not kind then
          M.report("AI ▸ 无法解析（不执行）:\n" .. (obj.result or ""):sub(1, 400), true)
          return
        end
        review(kind, body, function(edited)
          if edited and edited:find("%S") then
            execute(kind, vim.trim(edited))
          else
            vim.api.nvim_echo({ { "AI ▸ 已取消", "Comment" } }, false, {})
          end
        end)
      end)
    end)
  end
  attempt()
end

function M.setup()
  vim.api.nvim_create_user_command("AI", function(o)
    local args = vim.trim(o.args or "")
    if args == "" then
      M.report("AI: 缺少内容——用法 :AI <自然语言>（如 :AI 在新tab中打开mysql）", true)
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
