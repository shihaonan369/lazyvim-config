local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- 本仓自带 skills（skills/<name>/ 即 skill 实体源）的投递（docs/adr/0009）：
-- claude/pi 走 spawn 时会话级注入（--plugin-dir / --skill，见 agent_sessions.lua），
-- 仓不写共享 agent 目录；codex 无 CLI 注入口，自愈挂载到其自家 ~/.codex/skills
-- （缺则建、断链重建、他人实体不碰只提醒）。旧版曾挂 ~/.claude/skills 与
-- ~/.agents/skills（docs/adr/0006）——自愈卸载：指回本仓源的旧链启动即清。
-- [skill-mount-begin/end] 区间供 scripts/test-skill-mount.lua 提取实测
do -- [skill-mount-begin]
  local skill_src = vim.fn.stdpath("config") .. "/skills"
  if vim.uv.fs_stat(skill_src) then
    local names = {}
    for name in vim.fs.dir(skill_src) do
      local _, st = pcall(vim.uv.fs_stat, skill_src .. "/" .. name)
      if st and st.type == "directory" then names[#names + 1] = name end
    end
    -- 自愈卸载：旧共享目录里指回本仓 skills/<name> 的链清掉；他人实体不碰
    for _, dir in ipairs({ "~/.claude/skills", "~/.agents/skills" }) do
      local old_root = vim.fn.expand(dir)
      for _, name in ipairs(names) do
        local link = old_root .. "/" .. name
        local _, lst = pcall(vim.uv.fs_lstat, link)
        if lst and lst.type == "link" then
          local _, target = pcall(vim.uv.fs_readlink, link)
          if target == skill_src .. "/" .. name and pcall(vim.uv.fs_unlink, link) then
            vim.notify("skills 旧全局挂载已卸载: " .. dir .. "/" .. name)
          end
        end
      end
    end
    -- codex 专属挂载（无注入口的如实残留，上游出注入口后撤，见 ADR 0009）
    local dst_root = vim.fn.expand("~/.codex/skills")
    pcall(vim.fn.mkdir, dst_root, "p")
    for _, name in ipairs(names) do
      local src = skill_src .. "/" .. name
      local link = dst_root .. "/" .. name
      local _, lst = pcall(vim.uv.fs_lstat, link)
      if not lst then -- 名下无物：直接建
        if vim.uv.fs_symlink(src, link) then
          vim.notify("skills 自愈挂载(codex): " .. name)
        end
      elseif lst.type == "link" then
        -- 断链（目标已消失）重建；外指有效链是有意接线，不动
        local _, target = pcall(vim.uv.fs_readlink, link)
        if target ~= src and not vim.uv.fs_stat(link) then
          pcall(vim.uv.fs_unlink, link)
          if vim.uv.fs_symlink(src, link) then
            vim.notify("skills 自愈重建断链(codex): " .. name)
          end
        end
      else -- 真实文件/目录等他人实体：不碰，提醒一次
        vim.notify(dst_root .. "/" .. name .. " 已有非本仓实体，跳过", vim.log.levels.WARN)
      end
    end
  end
end -- [skill-mount-end]

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
