-- :AI <自然语言> —— 自然语言直驱 nvim 操作：claude -p 单发把请求翻译成
-- cmd:<Ex 命令> / lua:<代码> 负载，**先审后执**（confirm 过目，用户裁决
-- 2026-10-21）。解析失败或拒审一律不执行（不假成功）。claude 固定跑在
-- stdpath("run")/ai-cmd 下——单发 transcript 不落当前项目，-r/aC picker
-- 不被翻译请求污染。提速实测（2026-10-21 探针）：--strict-mcp-config
-- 砍掉 MCP 装载 ~6s（8.9s→2.96s，翻译用不上 MCP）；本机 GLM 包装后端
-- 传任何 --model 都触发 unrecognized_model 回落——反而更慢且回答丢
-- cmd: 前缀，故**默认不传**；要走别的档设 vim.g.ai_cmd_model（值须后端认）。
-- :ai 小写入口见 setup 里的带守卫 cmdline 缩写。
local M = {}

local function bin() return vim.env.AGENT_CLAUDE_BIN or "claude" end

local function build_prompt(query)
  local bufname = vim.api.nvim_buf_get_name(0)
  local ver = vim.version()
  return table.concat({
    "你是 Neovim 操作翻译器：把用户请求转成 nvim 操作，只回负载本身，不要解释、不要 markdown 围栏。",
    "第一行起就是以下两种格式之一：",
    "cmd:<Ex 命令>（多命令用 | 或换行分隔，每行一条）",
    "lua:<lua 代码>（vim.cmd/vim.api/vim.fn 可用，可多行）",
    "翻译规则：优先 cmd:；打开外部程序 = 终端（如新 tab: $tabnew | terminal mysql）；只操作当前 nvim 实例，不读写文件系统。",
    "需要运行时信息（端口/账号/文件位置等）时，生成带 $(...) 现场取值的命令（如 terminal mysql -h$(grep ... )——审查时会展示），不要调用工具调查项目。",
    "",
    string.format("环境: nvim %d.%d | cwd: %s | buffer: %s (ft=%s) | tab数: %d",
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

-- opts.confirm(kind, body) -> boolean：审查钩子（测试注入点；缺省走
-- vim.fn.confirm 数字选择：Enter/1=执行，Esc/2=取消）
function M.run(query, opts)
  opts = opts or {}
  local confirm = opts.confirm
    or function(kind, body)
      return vim.fn.confirm(("AI 生成 (%s):\n%s\n\n执行？"):format(kind, body), "执行\n取消") == 1
    end
  vim.api.nvim_echo({ { "AI ▸ 生成中…", "Comment" } }, false, {})
  local cwd = vim.fn.stdpath("run") .. "/ai-cmd"
  vim.fn.mkdir(cwd, "p")
  local argv = { bin(), "-p", "--strict-mcp-config", build_prompt(query) }
  if vim.g.ai_cmd_model then argv[#argv + 1], argv[#argv + 2] = "--model", vim.g.ai_cmd_model end
  vim.system(argv, { text = true, cwd = cwd, timeout = 45000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or res.timeout then
        vim.notify("AI ▸ claude 调用失败 (code=" .. tostring(res.code) .. "): "
          .. (res.stderr or ""):sub(1, 200), vim.log.levels.ERROR)
        return
      end
      local kind, body = parse(res.stdout or "")
      if not kind then
        vim.notify("AI ▸ 无法解析（不执行）:\n" .. (res.stdout or ""):sub(1, 400),
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
    local q = vim.trim(o.args or "")
    if q ~= "" then M.run(q) end
  end, { nargs = "+", desc = "自然语言 → nvim 操作（claude -p，先审后执）" })
  -- nvim 用户命令强制大写开头，:ai 小写用带守卫的 cmdline 缩写补形：
  -- 仅命令行类型为 : 且当前整行恰为 "ai" 时展开（参数位置/搜索串不误伤）
  vim.cmd([[cnoreabbrev <expr> ai getcmdtype() ==# ':' && getcmdline() ==# 'ai' ? 'AI' : 'ai']])
end

return M
