-- Colorscheme: catppuccin (mocha). Integrates with treesitter, lsp,
-- telescope, gitsigns and lualine out of the box.
return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000, -- load before other plugins so highlights apply
  opts = {
    flavour = "mocha", -- latte / frappe / macchiato / mocha
    integrations = {
      treesitter = true,
      telescope = true,
      gitsigns = true,
      native_lsp = { enabled = true },
      blink_cmp = true,
    },
  },
  config = function(_, opts)
    require("catppuccin").setup(opts)
    vim.cmd.colorscheme("catppuccin")
  end,
}
