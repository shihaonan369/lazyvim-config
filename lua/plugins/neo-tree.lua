return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    -- agent_tree 是外部源（lua/agent_tree.lua，agent tab 左侧列表，ADR 0005）。
    -- sources 必须追加而非赋值：lazy 合并 opts 时数组是整体替换，
    -- 直接写 sources={"agent_tree"} 会替掉 LazyVim 默认三源（filesystem/
    -- buffers/git_status），<leader>e 即失效
    opts.sources = opts.sources or {}
    table.insert(opts.sources, "agent_tree")
    -- neo-tree 默认 + LazyVim 全局 window.mappings 会并入每个源；文件类命令
    -- （open/preview/split/close_node…）在 agent_tree 无实现，按一次报一次。
    -- per-source 的 user 层优先级最高，逐个 "none" 禁用
    opts.agent_tree = {
      window = {
        mappings = {
          -- l 与 <CR> 同义（neo-tree 惯例 l=open）。必须放这层：LazyVim 全局
          -- window.mappings 的 l="open" 在 user 层，会压过源模块 default_config，
          -- 而本源无 open 命令、映射会被整体跳过
          ["l"] = "agent_open",
          ["h"] = "none",
          ["P"] = "none",
          ["z"] = "none",
          ["Z"] = "none",
          ["o"] = "none",
          ["O"] = "none",
          ["s"] = "none",
          ["S"] = "none",
          ["Y"] = "none",
          ["gy"] = "none",
          ["c"] = "none",
          ["m"] = "none",
          ["A"] = "none",
          ["w"] = "none",
          ["<C-s>"] = "none",
          ["<"] = "none",
          [">"] = "none",
          ["<C-;>"] = "none",
          ["<C-b>"] = "none",
          ["<C-f>"] = "none",
          ["<C-r>"] = "none",
          ["<Tab>"] = "none",
          ["C"] = "none",
          ["e"] = "none",
          ["p"] = "none",
          ["t"] = "none",
          ["T"] = "none",
          ["u"] = "none",
          ["U"] = "none",
          ["x"] = "none",
          ["y"] = "none",
        },
      },
    }
    opts.filesystem = vim.tbl_deep_extend("force", opts.filesystem or {}, {
      filtered_items = {
        visible = true,
      },
    })
  end,
}
