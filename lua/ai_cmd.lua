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

local function bin() return vim.env.AGENT_CLAUDE_BIN or "claude" end

-- 续链（用户裁决 2026-10-21「常驻后台 agent」的落地形态）：claude -p -r <sid>
-- 单发续链而非常驻进程——零新协议零看护（真常驻 stream-json 长管道是
-- ADR 0007 否决的 WS 桥同 genus）。上下文/调查结果留在链上，重复问题
-- 不重复调查；实测续链带缓存 2.3s（快于冷发）。链 sid 持久在
-- stdpath("cache")/ai-cmd/chain-sid——实测 stdpath("run") 是进程级临时
-- 目录（两实例路径随机不同），跨 nvim 重启续链必须用耐久位；claude 的
-- scratch cwd 仍走 run/ai-cmd（transcript 本体在 ~/.claude/projects，cwd
-- 目录短命无妨，隔离语义不变）。`:AI!` 重置链再问；链失效（transcript
-- 被清等）自动重开一次并明示。链会随条目增长变慢/变贵，bloat 咬手时
-- :AI! 即可——要不要自动按体积截链另议
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
    if sid and sid[1] and sid[1] ~= "" then return sid[1] end
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

-- 内联形态（用户裁决 2026-10-21 二次修正）：`:a<空格>` 起手变形——词形
-- 被图标替换，整行内联成 `: robot 纯查询`，CR 提交。行文同 `:!cmd`：'!'
-- 本来就是冒号后的内容首字符（提示符 ':' 不归内容管——setcmdprompt 在
-- 0.12.6 根本不存在，vimfn 只有只读 getcmdprompt；vim.fn 惰性代理让
-- type() 假报 function、调用才 E117，pcall 吞错即假装成功，勿再踩）。
-- 图标 = agent 本体脸（agent_sessions NEUTRAL_ICON 实心 0xF06A9）。
local INLINE_ICON = vim.fn.nr2char(0xF06A9)
local inline_active = false

-- 缩写命中（五大小写变体，空格/CR 触发都进）：守卫通过则换成图标+空格
-- （触发空格自然成为图标后的分隔）；已在 AI 态（查询恰为 "a"/"ai" 词）
-- 原样返回不重复变形。:a! 的 bang 走不进内联态（! 也触发缩写）——用 :AI!
function M._abbrev(tok)
  local line = vim.fn.getcmdline()
  if inline_active or vim.fn.getcmdtype() ~= ":" or line ~= tok then return tok end
  inline_active = true
  return INLINE_ICON .. " "
end

-- 输入框回落形态（裸 :AI / :a<CR> 空查询）：同一 agent 图标做 prompt。
-- 须声明在 M._cr 之前（局部前向引用落 nil 全局）
local function ask_box(fresh)
  vim.ui.input({ prompt = INLINE_ICON .. " " }, function(q)
    if q and q:find("%S") then M.run(vim.trim(q), { fresh = fresh }) end
  end)
end

-- CR 截获：AI 态下整行即查询（吞掉提交——查询不进命令历史），空查询回落
-- 输入框；非 AI 态透传。返回 Esc 键序终结本次 cmdline
function M._cr()
  if not inline_active then return "\r" end
  inline_active = false
  local q = vim.fn.getcmdline()
  if q:sub(1, #INLINE_ICON) == INLINE_ICON then q = q:sub(#INLINE_ICON + 1) end -- 图标是装饰，不进查询
  q = vim.trim(q)
  vim.schedule(function()
    if q == "" then
      ask_box(false)
    else
      M.run(q)
    end
  end)
  return "\27"
end

local function build_prompt(query)
  local bufname = vim.api.nvim_buf_get_name(0)
  local ver = vim.version()
  return table.concat({
    "你是 Neovim 操作翻译器：把用户请求转成 nvim 操作，只回负载本身，不要解释、不要 markdown 围栏。",
    "第一行起就是以下两种格式之一：",
    "cmd:<Ex 命令>（多命令用 | 或换行分隔，每行一条）",
    "lua:<lua 代码>（vim.cmd/vim.api/vim.fn 可用，可多行）",
    "翻译规则：优先 cmd:；打开外部程序 = 终端（如新 tab: $tabnew | terminal mysql）；生成的操作只作用于当前 nvim 实例，不写文件系统。",
    "调查分档（用户裁决 2026-10-21）：纯操作类请求（开 tab、分屏、切换、关闭等，不依赖项目事实）**不查文件**，直接给负载；仅当涉及事实参数（数据库连接、端口、账号、文件位置等）才查实不臆测——优先让命令带 $(...) 现场取值（**$() 只在 :terminal/! 等 shell 上下文里展开**，纯 Ex 参数只认 $VAR 不做命令替换），$() 不可行时用只读工具查项目文件确认。",
    "",
    string.format("环境: nvim %d.%d | 项目根: %s（你的工作目录在别处，查项目文件用此绝对路径）| buffer: %s (ft=%s) | tab数: %d",
      ver.major, ver.minor, vim.fn.getcwd(),
      bufname ~= "" and bufname or "[无名buffer]",
      vim.bo.filetype, #vim.api.nvim_list_tabpages()),
    "用户请求: " .. query,
  }, "\n")
end

-- 剥 markdown 围栏，取首个 cmd:/lua: 行起的整段（余行全收——提示词已锁
-- 「只回负载」，越界内容由先审后执兜住）
local function parse(out)
  local lines = {}
  for _, l in ipairs(vim.split(out, "\n", { trimempty = true })) do
    if not l:match("^%s*```") then lines[#lines + 1] = l end
  end
  for i, l in ipairs(lines) do
    local kind
    if l:sub(1, 4) == "cmd:" then kind = "cmd"
    elseif l:sub(1, 4) == "lua:" then kind = "lua" end
    if kind then
      local rest = { vim.trim(l:sub(5)) }
      for j = i + 1, #lines do rest[#rest + 1] = lines[j] end
      return kind, vim.trim(table.concat(rest, "\n"))
    end
  end
end

local function execute(kind, body)
  local ok, err
  if kind == "cmd" then
    ok, err = pcall(function() vim.cmd(body) end)
  else
    local chunk = load(body)
    if chunk then
      ok, err = pcall(chunk)
    else
      ok, err = false, "lua 负载无法 load"
    end
  end
  if not ok then
    vim.notify("AI ▸ 执行失败: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- 缺省审查对话框（模块字段 = 测试缝，可整体替换）：confirm 数字选择，
-- Enter/1=执行，Esc/2=取消
function M.default_confirm(kind, body)
  return vim.fn.confirm(("AI 生成 (%s):\n%s\n\n执行？"):format(kind, body), "执行\n取消") == 1
end

-- opts.confirm(kind, body) -> boolean：单次审查覆盖；opts.fresh=true
-- 重置链再问（:AI!）；opts._retried 内部自愈标记防循环
function M.run(query, opts)
  opts = opts or {}
  local confirm = opts.confirm or M.default_confirm
  vim.api.nvim_echo({ { "AI ▸ 生成中…", "Comment" } }, false, {})
  local cwd = vim.fn.stdpath("run") .. "/ai-cmd"
  vim.fn.mkdir(cwd, "p")
  local sid = nil
  if not opts.fresh then sid = chain_load() end -- 勿写成 fresh and nil or …（and/or 旁路陷阱）
  local argv = { bin(), "-p", "--strict-mcp-config", "--output-format", "json" }
  if sid then argv[#argv + 1], argv[#argv + 2] = "-r", sid end
  if vim.g.ai_cmd_model then argv[#argv + 1], argv[#argv + 2] = "--model", vim.g.ai_cmd_model end
  argv[#argv + 1] = build_prompt(query)
  vim.system(argv, { text = true, cwd = cwd, timeout = 45000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or res.timeout then
        if sid and not opts._retried then -- 链失效（transcript 被清等）：重开一次
          M.reset()
          vim.notify("AI ▸ 续链失效，已重开新链", vim.log.levels.WARN)
          M.run(query, { confirm = confirm, _retried = true })
          return
        end
        vim.notify("AI ▸ claude 调用失败 (code=" .. tostring(res.code) .. "): "
          .. (res.stderr or ""):sub(1, 200), vim.log.levels.ERROR)
        return
      end
      local ok, obj = pcall(vim.json.decode, res.stdout or "")
      if not ok or type(obj) ~= "table" or not obj.session_id then
        vim.notify("AI ▸ 输出非 JSON（不执行）:\n" .. (res.stdout or ""):sub(1, 400),
          vim.log.levels.ERROR)
        return
      end
      chain_save(obj.session_id)
      local kind, body = parse(obj.result or "")
      if not kind then
        vim.notify("AI ▸ 无法解析（不执行）:\n" .. (obj.result or ""):sub(1, 400),
          vim.log.levels.WARN)
        return
      end
      if confirm(kind, body) then
        execute(kind, body)
      else
        vim.api.nvim_echo({ { "AI ▸ 已取消", "Comment" } }, false, {})
      end
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("AI", function(o)
    local args = vim.trim(o.args or "")
    if args == "" then
      ask_box(o.bang)
    else
      M.run(args, { fresh = o.bang })
    end
  end, { nargs = "*", bang = true, desc = "自然语言 → nvim 操作（:a<空格> 内联图标行，claude -p 续链，先审后执；! 重置链）" })
  -- 入口五变体（用户裁决）：a/A/ai/Ai/aI 经缩写变形进 AI 态（:AI 本体
  -- 无需缩写）。守卫在 _abbrev 内（cmdtype : 且整行恰为词形）；缩写在
  -- 空格与裸 CR 下都展开（PTY 实测，headless feedkeys 假阴勿信）；
  -- :args 等词内续打不触发（缩写只在非词字符跟上时炸），:append 让位
  for _, tok in ipairs({ "a", "A", "ai", "Ai", "aI" }) do
    vim.cmd(("cnoreabbrev <expr> %s v:lua.require'ai_cmd'._abbrev('%s')"):format(tok, tok))
  end
  -- CR 截获：AI 态吞提交取整行为查询；非 AI 态原样透传（expr 结果不再
  -- 被 remap，无递归）
  vim.cmd([[cnoremap <expr> <CR> v:lua.require'ai_cmd'._cr()]])
  -- AI 态随 cmdline 生灭：Esc 弃/异常退出不残留标志（残留会劫持下一次
  -- 普通命令的 CR）
  vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineLeave" }, {
    callback = function() inline_active = false end,
    desc = "ai_cmd 内联态随 cmdline 生灭",
  })
end

return M
