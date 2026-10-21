-- Statusline: lualine. Replaces vim-airline.
return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = {
    options = {
      theme = "catppuccin",
      icons_enabled = true,
      globalstatus = true,
      section_separators = "",
      component_separators = "",
    },
  },
}
